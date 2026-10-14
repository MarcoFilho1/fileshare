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
        tv.setText("FileShare\n\nServiço iniciado. Pode sair deste app.");
        setContentView(tv);
        requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        startForegroundService(new Intent(this, ReceiverService.class));
    }
}
