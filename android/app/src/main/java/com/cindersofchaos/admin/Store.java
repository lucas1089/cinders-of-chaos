package com.cindersofchaos.admin;

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
 * Settings and the ssh private key. The key never leaves the phone and is stored encrypted with an AES key that lives
 * in the Android Keystore (hardware backed where the phone has it), so a copy of the app's files is useless.
 */
final class Store {
    private static final String ALIAS = "cc_admin_key";
    private static final String PREFS = "cc_admin";
    private final SharedPreferences p;

    Store(Context c) {
        p = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    String get(String k, String def) {
        return p.getString(k, def);
    }

    void put(String k, String v) {
        p.edit().putString(k, v).apply();
    }

    String host() {
        return get("host", "");
    }

    int port() {
        try {
            return Integer.parseInt(get("port", "22"));
        } catch (NumberFormatException e) {
            return 22;
        }
    }

    String user() {
        return get("user", "chaosadmin");
    }

    String ctl() {
        return get("ctl", "/opt/chaos/repo/server/deploy/chaos-ctl.sh");
    }

    String hostFingerprint() {
        return get("hostfp", "");
    }

    String publicKey() {
        return get("pub", "");
    }

    boolean configured() {
        return !host().isEmpty() && !get("keyenc", "").isEmpty();
    }

    private static SecretKey aesKey() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (ks.containsAlias(ALIAS)) {
            return (SecretKey) ks.getKey(ALIAS, null);
        }
        KeyGenerator g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        g.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build());
        return g.generateKey();
    }

    void saveKey(byte[] privatePem, String publicLine) throws Exception {
        Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
        c.init(Cipher.ENCRYPT_MODE, aesKey());
        byte[] iv = c.getIV();
        byte[] ct = c.doFinal(privatePem);
        byte[] all = new byte[iv.length + ct.length];
        System.arraycopy(iv, 0, all, 0, iv.length);
        System.arraycopy(ct, 0, all, iv.length, ct.length);
        p.edit().putString("keyenc", Base64.encodeToString(all, Base64.NO_WRAP)).putString("pub", publicLine)
                .remove("hostfp").apply();
    }

    byte[] loadKey() throws Exception {
        String enc = get("keyenc", "");
        if (enc.isEmpty()) {
            throw new IllegalStateException("Sem chave: gere uma na aba Config.");
        }
        byte[] all = Base64.decode(enc, Base64.NO_WRAP);
        Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
        c.init(Cipher.DECRYPT_MODE, aesKey(), new GCMParameterSpec(128, all, 0, 12));
        return c.doFinal(all, 12, all.length - 12);
    }
}
