package dev.marcofilho.fileshare;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        TextView tv = new TextView(this);
        tv.setPadding(48, 48, 48, 48);
        tv.setTextSize(18);
        PairingStore.Pairing pairing = PairingStore.load(this);
        tv.setText(pairing != null
                ? "FileShare\n\nPareado com " + pairing.macName() + ". Serviço iniciado: pode sair deste app."
                : "FileShare\n\nAinda não pareado.\n\nNo Mac, clique no ícone ⇄ da barra de menu → \"Parear tablet…\" "
                        + "e aponte a câmera do tablet para o QR code.");
        setContentView(tv);
        requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        startForegroundService(new Intent(this, BridgeService.class));
    }
}
