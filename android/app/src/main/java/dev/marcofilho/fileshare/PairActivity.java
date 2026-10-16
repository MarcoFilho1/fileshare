package dev.marcofilho.fileshare;

import android.app.Activity;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.net.Uri;
import android.os.Bundle;
import android.util.Base64;
import android.util.Log;
import android.view.View;
import android.view.animation.OvershootInterpolator;
import android.widget.ImageView;
import android.widget.TextView;

/** Abre pelo link do QR (fileshare://pair?...) mostrado no Mac e guarda o pareamento. */
public class PairActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_pair);
        TextView title = findViewById(R.id.title);
        TextView text = findViewById(R.id.text);
        View badge = findViewById(R.id.badge);
        ImageView icon = findViewById(R.id.badge_icon);
        findViewById(R.id.next).setOnClickListener(v -> {
            startActivity(new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP));
            finish();
        });

        Uri link = getIntent().getData();
        try {
            if (link == null || !"1".equals(link.getQueryParameter("v"))) throw new IllegalArgumentException("link inválido");
            String macId = link.getQueryParameter("id");
            String name = link.getQueryParameter("name");
            byte[] key = Base64.decode(link.getQueryParameter("k"), Base64.URL_SAFE | Base64.NO_PADDING | Base64.NO_WRAP);
            if (macId == null || macId.isEmpty() || key.length != 32) throw new IllegalArgumentException("link inválido");
            PairingStore.save(this, macId, name != null ? name : "Mac", key);
            title.setText(getString(R.string.pair_ok_title, name != null ? name : "Mac"));
            text.setText(R.string.pair_ok_text);
            badge.setBackgroundTintList(ColorStateList.valueOf(getColor(R.color.ok)));
            icon.setImageResource(R.drawable.ic_check);
            startForegroundService(new Intent(this, BridgeService.class));
            MacLink current = MacLink.current;
            if (current != null) current.repair();
        } catch (Exception e) {
            Log.e(BridgeService.TAG, "pairing failed", e);
            title.setText(R.string.pair_fail_title);
            text.setText(R.string.pair_fail_text);
            badge.setBackgroundTintList(ColorStateList.valueOf(getColor(R.color.warn)));
            icon.setImageResource(R.drawable.ic_stat_fileshare);
        }

        // o selo entra com um pulinho
        badge.setScaleX(0.4f);
        badge.setScaleY(0.4f);
        badge.setAlpha(0f);
        badge.animate().scaleX(1).scaleY(1).alpha(1).setStartDelay(120).setDuration(420)
                .setInterpolator(new OvershootInterpolator(2.2f)).start();
        findViewById(R.id.root).setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets bars = insets.getInsets(android.view.WindowInsets.Type.systemBars());
            v.setPadding(bars.left + 32, bars.top + 32, bars.right + 32, bars.bottom + 32);
            return insets;
        });
    }
}
