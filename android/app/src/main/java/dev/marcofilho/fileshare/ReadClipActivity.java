package dev.marcofilho.fileshare;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.os.Bundle;
import android.util.Log;

import java.security.MessageDigest;
import java.util.Arrays;

/**
 * Tela invisível: o Android só deixa ler a área de transferência com o app em primeiro plano,
 * então ela abre, lê quando ganha o foco, entrega ao MacSender e fecha. Aberta pelo botão das
 * Configurações rápidas ou, na cópia automática, pelo CopyWatchService.
 */
public class ReadClipActivity extends Activity {
    static final String EXTRA_AUTO = "auto";
    private static byte[] lastAutoHash;

    private boolean done;
    private boolean auto;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        auto = getIntent().getBooleanExtra(EXTRA_AUTO, false);
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (!hasFocus || done) return;
        done = true;
        try {
            ClipData clip = getSystemService(ClipboardManager.class).getPrimaryClip();
            ClipReader.Payload p = ClipReader.read(this, clip);
            if (p == null) {
                if (!auto) MacSender.toast(this, "Nada para enviar");
            } else if (auto && isRepeat(p)) {
                Log.i(ReceiverService.TAG, "skip: same content already sent");
            } else {
                MacSender.send(this, p);
            }
        } catch (Exception e) {
            Log.e(ReceiverService.TAG, "read clipboard failed", e);
            MacSender.toast(this, "Não consegui ler a área de transferência");
        }
        finish();
    }

    /** A cópia automática pode disparar duas vezes para a mesma cópia (botão + aviso). */
    private static boolean isRepeat(ClipReader.Payload p) throws Exception {
        byte[] hash = MessageDigest.getInstance("SHA-256").digest(p.data());
        boolean repeat = Arrays.equals(hash, lastAutoHash);
        lastAutoHash = hash;
        return repeat;
    }

    @Override
    public void finish() {
        super.finish();
        overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0);
    }
}
