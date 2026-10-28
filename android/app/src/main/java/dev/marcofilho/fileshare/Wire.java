package dev.marcofilho.fileshare;

import java.io.DataInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Base64;
import java.util.Collections;
import java.util.Set;
import java.util.TreeSet;

/**
 * Protocolo v2 (igual ao Wire.swift do Mac): [tamanho: int32 big-endian][quadro]. O quadro é a
 * mensagem "TIPO args\n" + corpo; depois do AUTH, cada quadro vai cifrado pelo SecureChannel.
 * Mensagens: AUTH nonce (única em claro), HELLO nome, CLIP id mime + bytes,
 * HELD id copiadoEm(ms) mime + bytes (cópia que o Mac guardou com o tablet fora), ACK id, PING, PONG,
 * e para o menu Compartilhar: FILE id tamanho mime nome, PART id + pedaço, FAIL id motivo (Mac recusou).
 * Desde a 2.4, o HELLO leva no corpo a versão e os recursos de cada lado (Peer), e um tipo
 * desconhecido vira UNKNOWN, que é ignorado em vez de derrubar a conexão.
 */
final class Wire {
    static final int MAX_PAYLOAD = 25 * 1024 * 1024;
    static final int MAX_FRAME = MAX_PAYLOAD + 1024;
    /** Arquivos vão em pedaços, então podem passar do limite de um quadro. */
    static final long MAX_FILE_SIZE = 100L * 1024 * 1024;
    static final int PART_SIZE = 512 * 1024;

    enum Type { AUTH, HELLO, CLIP, HELD, FILE, PART, ACK, FAIL, PING, PONG, BATT, OPEN, UNKNOWN }

    /**
     * O que cada lado anuncia no HELLO: a versão do app e os recursos que ele entende. Vai no corpo
     * do HELLO, que as versões até a 2.3 ignoram; para elas, isto chega vazio. Só envie uma mensagem
     * nova se o outro lado anunciou o recurso: um app antigo derruba a conexão ao receber um tipo
     * que não conhece.
     */
    static final class Peer {
        static final Peer NONE = new Peer("", Collections.emptySet());

        final String version;
        final Set<String> capabilities;

        Peer(String version, Set<String> capabilities) {
            this.version = version;
            this.capabilities = Collections.unmodifiableSet(new TreeSet<>(capabilities));
        }

        boolean supports(String capability) {
            return capabilities.contains(capability);
        }

        byte[] body() {
            if (version.isEmpty() && capabilities.isEmpty()) return null;
            return ("v=" + version + "\ncaps=" + String.join(",", capabilities) + "\n").getBytes(StandardCharsets.UTF_8);
        }

        /** Linhas "chave=valor"; chaves desconhecidas são ignoradas, para poder crescer depois. */
        static Peer parse(byte[] body) {
            String version = "";
            Set<String> caps = new TreeSet<>();
            for (String line : new String(body, StandardCharsets.UTF_8).split("\n")) {
                int eq = line.indexOf('=');
                if (eq <= 0) continue;
                String key = line.substring(0, eq), value = line.substring(eq + 1);
                if (key.equals("v")) version = value;
                else if (key.equals("caps")) {
                    caps.clear();
                    for (String c : value.split(",")) if (!c.isEmpty()) caps.add(c);
                }
            }
            return new Peer(version, caps);
        }
    }

    static final class Message {
        final Type type;
        final int id;
        final String text; // nome no HELLO, mime no CLIP/HELD/FILE, motivo no FAIL
        final byte[] data;
        final long copiedAt; // só no HELD
        final long size; // só no FILE
        final String name; // só no FILE
        final Peer peer; // só no HELLO

        private Message(Type type, int id, String text, byte[] data) {
            this(type, id, text, data, 0, 0, null);
        }

        private Message(Type type, int id, String text, byte[] data, long copiedAt, long size, String name) {
            this(type, id, text, data, copiedAt, size, name, Peer.NONE);
        }

        private Message(Type type, int id, String text, byte[] data, long copiedAt, long size, String name, Peer peer) {
            this.peer = peer;
            this.type = type;
            this.id = id;
            this.text = text;
            this.data = data;
            this.copiedAt = copiedAt;
            this.size = size;
            this.name = name;
        }

        static Message auth(byte[] nonce) { return new Message(Type.AUTH, 0, null, nonce); }
        static Message hello(String name) { return hello(name, Peer.NONE); }
        static Message hello(String name, Peer peer) { return new Message(Type.HELLO, 0, name, peer.body(), 0, 0, null, peer); }
        static Message clip(int id, String mime, byte[] data) { return new Message(Type.CLIP, id, mime, data); }
        static Message held(int id, long copiedAt, String mime, byte[] data) { return new Message(Type.HELD, id, mime, data, copiedAt, 0, null); }
        static Message file(int id, long size, String mime, String name) { return new Message(Type.FILE, id, mime, null, 0, size, name); }
        static Message part(int id, byte[] data) { return new Message(Type.PART, id, null, data); }
        static Message ack(int id) { return new Message(Type.ACK, id, null, null); }
        static Message fail(int id, String reason) { return new Message(Type.FAIL, id, reason, null); }
        static Message ping() { return new Message(Type.PING, 0, null, null); }
        static Message pong() { return new Message(Type.PONG, 0, null, null); }
        /** Bateria do tablet: id é o nível (0–100), copiedAt 1 se está carregando. Só para Mac com "batt". */
        static Message battery(int level, boolean charging) { return new Message(Type.BATT, level, null, null, charging ? 1 : 0, 0, null); }
        /** Link para abrir no navegador do Mac (text); só para Mac com "open". Ele responde ACK ou FAIL. */
        static Message open(int id, String url) { return new Message(Type.OPEN, id, url, null); }
        /** Tipo de uma versão mais nova do Mac; text é o nome do tipo. */
        static Message unknown(String type) { return new Message(Type.UNKNOWN, 0, type, null); }
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
            case PONG: header = "PONG\n"; break;
            case OPEN: header = "OPEN " + m.id + " " + m.text + "\n"; break;
            case BATT: header = "BATT " + m.id + " " + m.copiedAt + "\n"; break;
            default: header = m.text + "\n"; break; // UNKNOWN: só nos testes
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
                case "HELLO": return Message.hello(header.length() > 6 ? header.substring(6) : "", Peer.parse(body));
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
                case "OPEN":
                    if (parts.length != 3 || parts[2].isEmpty()) break;
                    return Message.open(Integer.parseInt(parts[1]), parts[2]);
                case "BATT": {
                    if (parts.length != 3 || !parts[2].matches("[01]")) break;
                    int level = Integer.parseInt(parts[1]);
                    if (level < 0 || level > 100) break;
                    return Message.battery(level, parts[2].equals("1"));
                }
                default:
                    // Um tipo novo é uma palavra curta em maiúsculas; qualquer outra coisa é lixo.
                    if (parts[0].matches("[A-Z]{1,16}")) return Message.unknown(parts[0]);
                    break;
            }
        } catch (IllegalArgumentException ignored) { // número ou base64 inválido
        }
        throw new IOException("bad message: " + header);
    }
}
