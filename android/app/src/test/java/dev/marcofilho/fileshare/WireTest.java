package dev.marcofilho.fileshare;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
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

    @Test
    public void rejectsOversizedFrame() {
        DataInputStream in = new DataInputStream(new ByteArrayInputStream(new byte[]{0x7f, (byte) 0xff, (byte) 0xff, (byte) 0xff}));
        assertThrows(IOException.class, () -> Wire.read(in));
    }

    @Test
    public void rejectsUnknownMessage() {
        assertThrows(IOException.class, () -> Wire.decode("HACK\n".getBytes(StandardCharsets.UTF_8)));
    }
}
