package dev.marcofilho.fileshare;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Pareamento no tablet: id e nome do Mac em SharedPreferences; a chave do pareamento cifrada com
 * uma chave AES do Android Keystore, que nunca sai do hardware.
 */
final class PairingStore {
    record Pairing(String macId, String macName, byte[] key) {
    }

    private static final String PREFS = "pairing";
    private static final String KEYSTORE_ALIAS = "fileshare-pairing";

    private PairingStore() {
    }

    static void save(Context ctx, String macId, String macName, byte[] key) throws Exception {
        Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
        c.init(Cipher.ENCRYPT_MODE, wrappingKey());
        byte[] wrapped = c.doFinal(key);
        prefs(ctx).edit()
                .putString("macId", macId)
                .putString("macName", macName)
                .putString("iv", Base64.encodeToString(c.getIV(), Base64.NO_WRAP))
                .putString("key", Base64.encodeToString(wrapped, Base64.NO_WRAP))
                .apply();
    }

    /** null se não houver pareamento (ou se a chave do Keystore sumiu). */
    static Pairing load(Context ctx) {
        SharedPreferences p = prefs(ctx);
        String macId = p.getString("macId", null);
        String iv = p.getString("iv", null);
        String wrapped = p.getString("key", null);
        if (macId == null || iv == null || wrapped == null) return null;
        try {
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.DECRYPT_MODE, wrappingKey(), new GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)));
            byte[] key = c.doFinal(Base64.decode(wrapped, Base64.NO_WRAP));
            return new Pairing(macId, p.getString("macName", "Mac"), key);
        } catch (Exception e) {
            return null;
        }
    }

    private static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static SecretKey wrappingKey() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (ks.containsAlias(KEYSTORE_ALIAS)) return (SecretKey) ks.getKey(KEYSTORE_ALIAS, null);
        KeyGenerator gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        gen.init(new KeyGenParameterSpec.Builder(KEYSTORE_ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build());
        return gen.generateKey();
    }
}
