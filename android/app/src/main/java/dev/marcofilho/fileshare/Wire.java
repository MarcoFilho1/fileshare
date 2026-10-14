package dev.marcofilho.fileshare;

import java.io.DataInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/**
 * Protocolo v2 (igual ao Wire.swift do Mac): [tamanho: int32 big-endian][cabeçalho "TIPO args\n"][corpo].
 * Mensagens: HELLO nome, CLIP id mime + bytes, ACK id, PING, PONG.
 */
final class Wire {
    static final int MAX_PAYLOAD = 25 * 1024 * 1024;
    static final int MAX_FRAME = MAX_PAYLOAD + 1024;

    enum Type { HELLO, CLIP, ACK, PING, PONG }

    static final class Message {
        final Type type;
        final int id;
        final String text; // nome no HELLO, mime no CLIP
        final byte[] data;

        private Message(Type type, int id, String text, byte[] data) {
            this.type = type;
            this.id = id;
            this.text = text;
            this.data = data;
        }

        static Message hello(String name) { return new Message(Type.HELLO, 0, name, null); }
        static Message clip(int id, String mime, byte[] data) { return new Message(Type.CLIP, id, mime, data); }
        static Message ack(int id) { return new Message(Type.ACK, id, null, null); }
        static Message ping() { return new Message(Type.PING, 0, null, null); }
        static Message pong() { return new Message(Type.PONG, 0, null, null); }
    }

    private Wire() {
    }

    static byte[] encode(Message m) {
        String header;
        switch (m.type) {
            case HELLO: header = "HELLO " + m.text + "\n"; break;
            case CLIP: header = "CLIP " + m.id + " " + m.text + "\n"; break;
            case ACK: header = "ACK " + m.id + "\n"; break;
            case PING: header = "PING\n"; break;
            default: header = "PONG\n"; break;
        }
        byte[] h = header.getBytes(StandardCharsets.UTF_8);
        int bodyLen = m.data != null ? m.data.length : 0;
        ByteBuffer buf = ByteBuffer.allocate(4 + h.length + bodyLen);
        buf.putInt(h.length + bodyLen).put(h);
        if (m.data != null) buf.put(m.data);
        return buf.array();
    }

    static void write(OutputStream out, Message m) throws IOException {
        out.write(encode(m));
        out.flush();
    }

    static Message read(DataInputStream in) throws IOException {
        int size = in.readInt();
        if (size <= 0 || size > MAX_FRAME) throw new IOException("frame too large: " + size);
        byte[] frame = new byte[size];
        in.readFully(frame);
        return decode(frame);
    }

    static Message decode(byte[] frame) throws IOException {
        int nl = 0;
        while (nl < frame.length && frame[nl] != '\n') nl++;
        if (nl == frame.length) throw new IOException("no header");
        String header = new String(frame, 0, nl, StandardCharsets.UTF_8);
        byte[] body = Arrays.copyOfRange(frame, nl + 1, frame.length);
        String[] parts = header.split(" ", 3);
        try {
            switch (parts[0]) {
                case "HELLO": return Message.hello(header.length() > 6 ? header.substring(6) : "");
                case "CLIP":
                    if (parts.length != 3 || body.length == 0) break;
                    return Message.clip(Integer.parseInt(parts[1]), parts[2], body);
                case "ACK":
                    if (parts.length != 2) break;
                    return Message.ack(Integer.parseInt(parts[1]));
                case "PING": return Message.ping();
                case "PONG": return Message.pong();
                default: break;
            }
        } catch (NumberFormatException ignored) {
        }
        throw new IOException("bad message: " + header);
    }
}
