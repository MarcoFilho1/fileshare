package dev.marcofilho.fileshare;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.assertThrows;

import java.io.ByteArrayInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

import org.junit.Test;

public class WireTest {
    /** Mesmo vetor do WireTests.swift: os dois lados precisam gerar os mesmos bytes. */
    @Test
    public void matchesSharedVector() {
        byte[] wire = Wire.encode(Wire.Message.clip(7, "text/plain", "oi".getBytes(StandardCharsets.UTF_8)));
        byte[] body = "CLIP 7 text/plain\noi".getBytes(StandardCharsets.UTF_8);
        byte[] expected = new byte[4 + body.length];
        expected[3] = 0x14;
        System.arraycopy(body, 0, expected, 4, body.length);
        assertArrayEquals(expected, wire);
    }

    @Test
    public void readsMessagesBackToBack() throws IOException {
        byte[] img = {(byte) 0x89, 'P', '\n', 0};
        byte[] a = Wire.encode(Wire.Message.hello("Galaxy Tab S9 FE"));
        byte[] b = Wire.encode(Wire.Message.clip(3, "image/png", img));
        byte[] c = Wire.encode(Wire.Message.ack(3));
        byte[] all = new byte[a.length + b.length + c.length];
        System.arraycopy(a, 0, all, 0, a.length);
        System.arraycopy(b, 0, all, a.length, b.length);
        System.arraycopy(c, 0, all, a.length + b.length, c.length);
        DataInputStream in = new DataInputStream(new ByteArrayInputStream(all));

        Wire.Message hello = Wire.read(in);
        assertEquals(Wire.Type.HELLO, hello.type);
        assertEquals("Galaxy Tab S9 FE", hello.text);
        Wire.Message clip = Wire.read(in);
        assertEquals(Wire.Type.CLIP, clip.type);
        assertEquals(3, clip.id);
        assertEquals("image/png", clip.text);
        assertArrayEquals(img, clip.data);
        Wire.Message ack = Wire.read(in);
        assertEquals(Wire.Type.ACK, ack.type);
        assertEquals(3, ack.id);
    }

    @Test
    public void authCarriesSixteenByteNonce() throws IOException {
        byte[] nonce = new byte[16];
        nonce[0] = (byte) 0xA0;
        Wire.Message m = Wire.decode(Wire.messageBytes(Wire.Message.auth(nonce)));
        assertEquals(Wire.Type.AUTH, m.type);
        assertArrayEquals(nonce, m.data);
        assertThrows(IOException.class, () -> Wire.decode("AUTH AAAA\n".getBytes(StandardCharsets.UTF_8)));
    }

    @Test
    public void heldCarriesCopyTime() throws IOException {
        Wire.Message m = Wire.decode(Wire.messageBytes(
                Wire.Message.held(2, 1_792_000_000_123L, "text/plain", "guardado".getBytes(StandardCharsets.UTF_8))));
        assertEquals(Wire.Type.HELD, m.type);
        assertEquals(2, m.id);
        assertEquals(1_792_000_000_123L, m.copiedAt);
        assertEquals("text/plain", m.text);
        assertEquals("guardado", new String(m.data, StandardCharsets.UTF_8));
    }

    /** Mesmo cabeçalho que o Wire.swift gera para .held. */
    @Test
    public void heldMatchesMacFormat() {
        byte[] bytes = Wire.messageBytes(Wire.Message.held(2, 1_792_000_000_123L, "text/plain", "x".getBytes(StandardCharsets.UTF_8)));
        assertEquals("HELD 2 1792000000123 text/plain\nx", new String(bytes, StandardCharsets.UTF_8));
    }

    /** Mesmo cabeçalho do WireTests.swift: o nome do arquivo vai por último e pode ter espaços. */
    @Test
    public void fileHeaderMatchesMacFormat() throws IOException {
        byte[] bytes = Wire.messageBytes(Wire.Message.file(4, 2048, "application/pdf", "Nota de aula.pdf"));
        assertEquals("FILE 4 2048 application/pdf Nota de aula.pdf\n", new String(bytes, StandardCharsets.UTF_8));
        Wire.Message m = Wire.decode(bytes);
        assertEquals(Wire.Type.FILE, m.type);
        assertEquals(4, m.id);
        assertEquals(2048, m.size);
        assertEquals("application/pdf", m.text);
        assertEquals("Nota de aula.pdf", m.name);
    }

    @Test
    public void partAndFailRoundTrip() throws IOException {
        byte[] chunk = {'%', 'P', 'D', 'F', '\n'};
        Wire.Message part = Wire.decode(Wire.messageBytes(Wire.Message.part(4, chunk)));
        assertEquals(Wire.Type.PART, part.type);
        assertEquals(4, part.id);
        assertArrayEquals(chunk, part.data);

        Wire.Message fail = Wire.decode("FAIL 4 arquivo maior que 100 MB\n".getBytes(StandardCharsets.UTF_8));
        assertEquals(Wire.Type.FAIL, fail.type);
        assertEquals(4, fail.id);
        assertEquals("arquivo maior que 100 MB", fail.text);
    }

    @Test
    public void downloadNamesFromMacAreSafe() {
        assertEquals("-..-.ssh-authorized_keys", IncomingDownload.safeName("../../.ssh/authorized_keys"));
        assertEquals("zshrc", IncomingDownload.safeName(".zshrc"));
        assertEquals("Aula3.pdf", IncomingDownload.safeName("Aula\n3.pdf"));
        assertEquals("arquivo", IncomingDownload.safeName("  "));
    }

    @Test
    public void rejectsOversizedFrame() {
        DataInputStream in = new DataInputStream(new ByteArrayInputStream(new byte[]{0x7f, (byte) 0xff, (byte) 0xff, (byte) 0xff}));
        assertThrows(IOException.class, () -> Wire.read(in));
    }

    /** Um tipo de uma versão mais nova não derruba a conexão: vira UNKNOWN e é ignorado. */
    @Test
    public void toleratesMessageFromNewerVersion() throws IOException {
        Wire.Message m = Wire.decode("HIST 3 texto\n".getBytes(StandardCharsets.UTF_8));
        assertEquals(Wire.Type.UNKNOWN, m.type);
        assertEquals("HIST", m.text);
        assertEquals("NOTIF", Wire.decode("NOTIF\ncorpo qualquer".getBytes(StandardCharsets.UTF_8)).text);
    }

    /** Mesmo texto do WireTests.swift. */
    @Test
    public void batteryMatchesMacFormat() throws IOException {
        assertEquals("BATT 7 1\n", new String(Wire.messageBytes(Wire.Message.battery(7, true)), StandardCharsets.UTF_8));
        Wire.Message m = Wire.decode("BATT 72 0\n".getBytes(StandardCharsets.UTF_8));
        assertEquals(Wire.Type.BATT, m.type);
        assertEquals(72, m.id);
        assertEquals(0, m.copiedAt);
        assertThrows(IOException.class, () -> Wire.decode("BATT 101 0\n".getBytes(StandardCharsets.UTF_8)));
        assertThrows(IOException.class, () -> Wire.decode("BATT 50 sim\n".getBytes(StandardCharsets.UTF_8)));
    }

    /** Mesmo texto do WireTests.swift. */
    @Test
    public void openMatchesMacFormat() throws IOException {
        byte[] bytes = Wire.messageBytes(Wire.Message.open(3, "https://exemplo.com/a"));
        assertEquals("OPEN 3 https://exemplo.com/a\n", new String(bytes, StandardCharsets.UTF_8));
        Wire.Message m = Wire.decode(bytes);
        assertEquals(Wire.Type.OPEN, m.type);
        assertEquals("https://exemplo.com/a", m.text);
    }

    /** O link vem muitas vezes junto do título da página, às vezes entre parênteses. */
    @Test
    public void findsFirstLinkInSharedText() {
        assertEquals("https://youtu.be/abc123", OpenOnMacActivity.firstLink("Vídeo legal https://youtu.be/abc123"));
        assertEquals("https://ex.com/a?b=1", OpenOnMacActivity.firstLink("Título (https://ex.com/a?b=1)."));
        assertEquals("http://ex.com", OpenOnMacActivity.firstLink("http://ex.com\noutra https://y.com"));
        assertEquals(null, OpenOnMacActivity.firstLink("sem link aqui, só ex.com"));
        assertEquals(null, OpenOnMacActivity.firstLink("file:///sdcard/a.pdf"));
    }

    /** Só um link sozinho vira a notificação "Link do Mac"; texto com link no meio é só texto. */
    @Test
    public void detectsLinkCopiedOnMac() {
        assertEquals("https://ex.com/a?b=1", BridgeService.singleLink("  https://ex.com/a?b=1\n"));
        assertEquals(null, BridgeService.singleLink("veja https://ex.com"));
        assertEquals(null, BridgeService.singleLink("file:///etc/hosts"));
        assertEquals(null, BridgeService.singleLink("ex.com"));
    }

    /** Lixo continua sendo erro: só uma palavra curta em maiúsculas conta como tipo novo. */
    @Test
    public void rejectsGarbage() {
        for (String text : new String[]{"hack 1\n", "\n", "HIST1 2\n", "ÇÃO\n", "UMTIPOMUITOCOMPRIDO\n"}) {
            assertThrows(text, IOException.class, () -> Wire.decode(text.getBytes(StandardCharsets.UTF_8)));
        }
    }

    /** Mesmo texto do WireTests.swift: versão e recursos vão no corpo do HELLO. */
    @Test
    public void helloInfoMatchesMacFormat() throws IOException {
        Wire.Peer peer = new Wire.Peer("2.4.0", new java.util.HashSet<>(java.util.Arrays.asList("held", "batt")));
        byte[] bytes = Wire.messageBytes(Wire.Message.hello("Marco MacBook Air", peer));
        assertEquals("HELLO Marco MacBook Air\nv=2.4.0\ncaps=batt,held\n", new String(bytes, StandardCharsets.UTF_8));
        Wire.Message m = Wire.decode(bytes);
        assertEquals("Marco MacBook Air", m.text);
        assertEquals("2.4.0", m.peer.version);
        assertTrue(m.peer.supports("batt"));
        assertTrue(m.peer.supports("held"));
    }

    /** Até a 2.3 o HELLO não tem corpo: o outro lado fica sem versão e sem recursos. */
    @Test
    public void helloFromOldVersionHasNoInfo() throws IOException {
        Wire.Message m = Wire.decode("HELLO Marco MacBook Air\n".getBytes(StandardCharsets.UTF_8));
        assertEquals("Marco MacBook Air", m.text);
        assertEquals("", m.peer.version);
        assertFalse(m.peer.supports("batt"));
        // e o tablet novo sem recursos também manda um HELLO que a 2.3 entende
        assertEquals("HELLO Tab\n", new String(Wire.messageBytes(Wire.Message.hello("Tab")), StandardCharsets.UTF_8));
    }

    /** Chaves desconhecidas no corpo do HELLO são ignoradas, para o formato poder crescer. */
    @Test
    public void helloIgnoresUnknownKeys() throws IOException {
        Wire.Message m = Wire.decode("HELLO Tab\nv=2.6.0\ntema=escuro\ncaps=batt,,hist\nlixo\n".getBytes(StandardCharsets.UTF_8));
        assertEquals("2.6.0", m.peer.version);
        assertEquals(new java.util.TreeSet<>(java.util.Arrays.asList("batt", "hist")), m.peer.capabilities);
    }
}
