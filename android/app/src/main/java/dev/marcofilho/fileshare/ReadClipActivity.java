package dev.marcofilho.fileshare;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.util.Log;

/**
 * Tela invisível: o Android só deixa ler a área de transferência com o app em primeiro plano,
 * então ela abre, lê quando ganha o foco, entrega ao MacSender e fecha.
 */
public class ReadClipActivity extends Activity {
    private boolean done;

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (!hasFocus || done) return;
        done = true;
        try {
            ClipData clip = getSystemService(ClipboardManager.class).getPrimaryClip();
            ClipReader.Payload p = ClipReader.read(this, clip);
            if (p == null) MacSender.toast(this, "Nada para enviar");
            else MacSender.send(this, p);
        } catch (Exception e) {
            Log.e(ReceiverService.TAG, "read clipboard failed", e);
            MacSender.toast(this, "Não consegui ler a área de transferência");
        }
        finish();
    }
}
