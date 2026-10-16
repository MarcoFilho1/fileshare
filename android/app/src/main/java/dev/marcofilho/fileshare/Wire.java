package dev.marcofilho.fileshare;

import java.io.DataInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Base64;

/**
 * Protocolo v2 (igual ao Wire.swift do Mac): [tamanho: int32 big-endian][quadro]. O quadro é a
 * mensagem "TIPO args\n" + corpo; depois do AUTH, cada quadro vai cifrado pelo SecureChannel.
 * Mensagens: AUTH nonce (única em claro), HELLO nome, CLIP id mime + bytes,
 * HELD id copiadoEm(ms) mime + bytes (cópia que o Mac guardou com o tablet fora), ACK id, PING, PONG,
 * e para o menu Compartilhar: FILE id tamanho mime nome, PART id + pedaço, FAIL id motivo (Mac recusou).
 */
final class Wire {
    static final int MAX_PAYLOAD = 25 * 1024 * 1024;
    static final int MAX_FRAME = MAX_PAYLOAD + 1024;
    /** Arquivos vão em pedaços, então podem passar do limite de um quadro. */
    static final long MAX_FILE_SIZE = 100L * 1024 * 1024;
    static final int PART_SIZE = 512 * 1024;

    enum Type { AUTH, HELLO, CLIP, HELD, FILE, PART, ACK, FAIL, PING, PONG }

    static final class Message {
        final Type type;
        final int id;
        final String text; // nome no HELLO, mime no CLIP/HELD/FILE, motivo no FAIL
        final byte[] data;
        final long copiedAt; // só no HELD
        final long size; // só no FILE
        final String name; // só no FILE

        private Message(Type type, int id, String text, byte[] data) {
            this(type, id, text, data, 0, 0, null);
        }

        private Message(Type type, int id, String text, byte[] data, long copiedAt, long size, String name) {
            this.type = type;
            this.id = id;
            this.text = text;
            this.data = data;
            this.copiedAt = copiedAt;
            this.size = size;
            this.name = name;
        }

        static Message auth(byte[] nonce) { return new Message(Type.AUTH, 0, null, nonce); }
        static Message hello(String name) { return new Message(Type.HELLO, 0, name, null); }
        static Message clip(int id, String mime, byte[] data) { return new Message(Type.CLIP, id, mime, data); }
        static Message held(int id, long copiedAt, String mime, byte[] data) { return new Message(Type.HELD, id, mime, data, copiedAt, 0, null); }
        static Message file(int id, long size, String mime, String name) { return new Message(Type.FILE, id, mime, null, 0, size, name); }
        static Message part(int id, byte[] data) { return new Message(Type.PART, id, null, data); }
        static Message ack(int id) { return new Message(Type.ACK, id, null, null); }
        static Message fail(int id, String reason) { return new Message(Type.FAIL, id, reason, null); }
        static Message ping() { return new Message(Type.PING, 0, null, null); }
        static Message pong() { return new Message(Type.PONG, 0, null, null); }
    }

    private Wire() {
    }

    /** Mensagem já com o tamanho na frente (quadro em claro). */
    static byte[] encode(Message m) {
        return frame(messageBytes(m));
    }

    static byte[] frame(byte[] body) {
        return ByteBuffer.allocate(4 + body.length).putInt(body.length).put(body).array();
    }

    static byte[] messageBytes(Message m) {
        String header;
        byte[] body = m.data;
        switch (m.type) {
            case AUTH:
                header = "AUTH " + Base64.getEncoder().encodeToString(m.data) + "\n";
                body = null;
                break;
            case HELLO: header = "HELLO " + m.text + "\n"; break;
            case CLIP: header = "CLIP " + m.id + " " + m.text + "\n"; break;
            case HELD: header = "HELD " + m.id + " " + m.copiedAt + " " + m.text + "\n"; break;
            case FILE: header = "FILE " + m.id + " " + m.size + " " + m.text + " " + m.name + "\n"; break;
            case PART: header = "PART " + m.id + "\n"; break;
            case ACK: header = "ACK " + m.id + "\n"; break;
            case FAIL: header = "FAIL " + m.id + " " + m.text + "\n"; break;
            case PING: header = "PING\n"; break;
            default: header = "PONG\n"; break;
        }
        byte[] h = header.getBytes(StandardCharsets.UTF_8);
        if (body == null) return h;
        return ByteBuffer.allocate(h.length + body.length).put(h).put(body).array();
    }

    static void writeFrame(OutputStream out, byte[] body) throws IOException {
        out.write(frame(body));
        out.flush();
    }

    static byte[] readFrame(DataInputStream in) throws IOException {
        int size = in.readInt();
        if (size <= 0 || size > MAX_FRAME) throw new IOException("frame too large: " + size);
        byte[] frame = new byte[size];
        in.readFully(frame);
        return frame;
    }

    static Message read(DataInputStream in) throws IOException {
        return decode(readFrame(in));
    }

    static Message decode(byte[] frame) throws IOException {
        int nl = 0;
        while (nl < frame.length && frame[nl] != '\n') nl++;
        if (nl == frame.length) throw new IOException("no header");
        String header = new String(frame, 0, nl, StandardCharsets.UTF_8);
        byte[] body = Arrays.copyOfRange(frame, nl + 1, frame.length);
        // o último argumento (nome, mime, motivo) pode ter espaços
        String[] parts = header.split(" ", header.startsWith("FILE ") ? 5 : header.startsWith("HELD ") ? 4 : 3);
        try {
            switch (parts[0]) {
                case "AUTH":
                    if (parts.length != 2) break;
                    byte[] nonce = Base64.getDecoder().decode(parts[1]);
                    if (nonce.length != 16) break;
                    return Message.auth(nonce);
                case "HELLO": return Message.hello(header.length() > 6 ? header.substring(6) : "");
                case "CLIP":
                    if (parts.length != 3 || body.length == 0) break;
                    return Message.clip(Integer.parseInt(parts[1]), parts[2], body);
                case "HELD":
                    if (parts.length != 4 || body.length == 0) break;
                    return Message.held(Integer.parseInt(parts[1]), Long.parseLong(parts[2]), parts[3], body);
                case "FILE": {
                    if (parts.length != 5 || body.length != 0) break;
                    long size = Long.parseLong(parts[2]);
                    if (size < 0) break;
                    return Message.file(Integer.parseInt(parts[1]), size, parts[3], parts[4]);
                }
                case "PART":
                    if (parts.length != 2 || body.length == 0) break;
                    return Message.part(Integer.parseInt(parts[1]), body);
                case "ACK":
                    if (parts.length != 2) break;
                    return Message.ack(Integer.parseInt(parts[1]));
                case "FAIL":
                    if (parts.length != 3) break;
                    return Message.fail(Integer.parseInt(parts[1]), parts[2]);
                case "PING": return Message.ping();
                case "PONG": return Message.pong();
                default: break;
            }
        } catch (IllegalArgumentException ignored) { // número ou base64 inválido
        }
        throw new IOException("bad message: " + header);
    }
}
