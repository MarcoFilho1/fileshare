package dev.marcofilho.fileshare;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;

import javax.crypto.AEADBadTagException;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Criptografia da sessão (igual ao SecureChannel.swift): HKDF-SHA256 da chave do pareamento com os
 * nonces dos dois lados gera uma chave por sentido; cada quadro vai com ChaCha20-Poly1305 e um
 * contador como nonce, o que barra quadros repetidos ou adulterados.
 */
final class SecureChannel {
    static final class DecryptException extends java.io.IOException {
        DecryptException() {
            super("decrypt failed (wrong pairing key?)");
        }
    }

    private static final SecureRandom RANDOM = new SecureRandom();

    private final byte[] sendKey;
    private final byte[] receiveKey;
    private long sendCounter;
    private long receiveCounter;

    /** Lado do tablet. */
    SecureChannel(byte[] pairingKey, byte[] tabletNonce, byte[] macNonce) throws GeneralSecurityException {
        byte[] salt = ByteBuffer.allocate(tabletNonce.length + macNonce.length).put(tabletNonce).put(macNonce).array();
        sendKey = hkdf(pairingKey, salt, "fileshare v1 tablet->mac".getBytes(StandardCharsets.UTF_8), 32);
        receiveKey = hkdf(pairingKey, salt, "fileshare v1 mac->tablet".getBytes(StandardCharsets.UTF_8), 32);
    }

    synchronized byte[] seal(byte[] plaintext) throws GeneralSecurityException {
        Cipher c = Cipher.getInstance("ChaCha20-Poly1305");
        c.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(sendKey, "ChaCha20"), new IvParameterSpec(nonce(sendCounter++)));
        return c.doFinal(plaintext); // texto cifrado + tag de 16 bytes, como no CryptoKit
    }

    synchronized byte[] open(byte[] frame) throws java.io.IOException {
        try {
            Cipher c = Cipher.getInstance("ChaCha20-Poly1305");
            c.init(Cipher.DECRYPT_MODE, new SecretKeySpec(receiveKey, "ChaCha20"), new IvParameterSpec(nonce(receiveCounter)));
            byte[] plaintext = c.doFinal(frame);
            receiveCounter++;
            return plaintext;
        } catch (AEADBadTagException e) {
            throw new DecryptException();
        } catch (GeneralSecurityException e) {
            throw new java.io.IOException(e);
        }
    }

    static byte[] nonce(long counter) {
        return ByteBuffer.allocate(12).putInt(0).putLong(counter).array();
    }

    static byte[] randomBytes(int n) {
        byte[] b = new byte[n];
        RANDOM.nextBytes(b);
        return b;
    }

    /** HKDF-SHA256 (RFC 5869). */
    static byte[] hkdf(byte[] ikm, byte[] salt, byte[] info, int length) throws GeneralSecurityException {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(salt, "HmacSHA256"));
        byte[] prk = mac.doFinal(ikm);
        mac.init(new SecretKeySpec(prk, "HmacSHA256"));
        byte[] out = new byte[length];
        byte[] t = new byte[0];
        for (int i = 1, pos = 0; pos < length; i++) {
            mac.update(t);
            mac.update(info);
            mac.update((byte) i);
            t = mac.doFinal();
            int n = Math.min(t.length, length - pos);
            System.arraycopy(t, 0, out, pos, n);
            pos += n;
        }
        return out;
    }
}
