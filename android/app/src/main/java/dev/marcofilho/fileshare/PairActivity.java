package dev.marcofilho.fileshare;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Base64;
import android.util.Log;
import android.widget.TextView;

/** Abre pelo link do QR (fileshare://pair?...) mostrado no Mac e guarda o pareamento. */
public class PairActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        TextView tv = new TextView(this);
        tv.setPadding(48, 48, 48, 48);
        tv.setTextSize(18);
        setContentView(tv);

        Uri link = getIntent().getData();
        try {
            if (link == null || !"1".equals(link.getQueryParameter("v"))) throw new IllegalArgumentException("link inválido");
            String macId = link.getQueryParameter("id");
            String name = link.getQueryParameter("name");
            byte[] key = Base64.decode(link.getQueryParameter("k"), Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
            if (macId == null || macId.isEmpty() || key.length != 32) throw new IllegalArgumentException("link inválido");
            PairingStore.save(this, macId, name != null ? name : "Mac", key);
            tv.setText("Pareado com " + (name != null ? name : "o Mac") + ".\n\nPode fechar esta tela: a conexão é feita sozinha pelo Wi-Fi.");
            startForegroundService(new Intent(this, BridgeService.class));
            MacLink link2 = MacLink.current;
            if (link2 != null) link2.repair();
        } catch (Exception e) {
            Log.e(BridgeService.TAG, "pairing failed", e);
            tv.setText("Não consegui parear: " + e.getMessage() + "\n\nNo Mac, use \"Parear tablet…\" de novo.");
        }
    }
}
