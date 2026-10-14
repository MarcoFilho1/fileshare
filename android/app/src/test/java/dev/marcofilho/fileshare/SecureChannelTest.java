package dev.marcofilho.fileshare;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HexFormat;

import org.junit.Test;

public class SecureChannelTest {
    private static final HexFormat HEX = HexFormat.of();

    static byte[] pairingKey() {
        byte[] k = new byte[32];
        for (int i = 0; i < 32; i++) k[i] = (byte) i;
        return k;
    }

    static byte[] filled(int value) {
        byte[] b = new byte[16];
        Arrays.fill(b, (byte) value);
        return b;
    }

    /** RFC 5869, apêndice A.1. */
    @Test
    public void hkdfMatchesRfc5869() throws Exception {
        byte[] okm = SecureChannel.hkdf(
                HEX.parseHex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"),
                HEX.parseHex("000102030405060708090a0b0c"),
                HEX.parseHex("f0f1f2f3f4f5f6f7f8f9"), 42);
        assertEquals("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
                HEX.formatHex(okm));
    }

    /** Mesmos valores do SecureChannelTests.swift: o Mac (CryptoKit) e o Android precisam bater. */
    @Test
    public void matchesSharedVector() throws Exception {
        byte[] salt = new byte[32];
        System.arraycopy(filled(0xA0), 0, salt, 0, 16);
        System.arraycopy(filled(0xB0), 0, salt, 16, 16);
        assertEquals("97302912c35b777570dcbbe3251b944ea0544065536749f049dc77891a65477c",
                HEX.formatHex(SecureChannel.hkdf(pairingKey(), salt, "fileshare v1 tablet->mac".getBytes(StandardCharsets.UTF_8), 32)));
        assertEquals("1c6b6886b71d45a6c1bb4d71e25af976a686c10ab058b6904382ad10cea7fa05",
                HEX.formatHex(SecureChannel.hkdf(pairingKey(), salt, "fileshare v1 mac->tablet".getBytes(StandardCharsets.UTF_8), 32)));

        SecureChannel tablet = new SecureChannel(pairingKey(), filled(0xA0), filled(0xB0));
        assertEquals("536459b3e09ced1d5857f801afa1c0aee3e373f8bcf2e7ef6b07",
                HEX.formatHex(tablet.seal("HELLO Tab\n".getBytes(StandardCharsets.UTF_8))));
        assertEquals("f4afcab4d342284ca3f3263857c2236e8552d97308",
                HEX.formatHex(tablet.seal("PING\n".getBytes(StandardCharsets.UTF_8))));
    }

    @Test
    public void rejectsFrameSealedWithAnotherKey() throws Exception {
        SecureChannel tablet = new SecureChannel(pairingKey(), filled(0xA0), filled(0xB0));
        // um quadro "do Mac" cifrado com outra chave
        SecureChannel other = new SecureChannel(new byte[32], filled(0xA0), filled(0xB0));
        byte[] fake = other.seal("HELLO Mac\n".getBytes(StandardCharsets.UTF_8));
        assertThrows(SecureChannel.DecryptException.class, () -> tablet.open(fake));
    }

    @Test
    public void nonceIsCounterBigEndian() {
        assertArrayEquals(HEX.parseHex("000000000000000000000001"), SecureChannel.nonce(1));
    }
}
