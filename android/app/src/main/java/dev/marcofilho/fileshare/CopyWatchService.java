package dev.marcofilho.fileshare;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;

import java.util.List;
import java.util.Locale;

/**
 * Cópia automática: percebe o toque em "Copiar" (ou o aviso de "copiado" do sistema) e abre por
 * um instante a ReadClipActivity, que lê a área de transferência e envia ao Mac.
 */
public class CopyWatchService extends AccessibilityService {
    private static final long READ_DELAY_MS = 150;
    private static final long DEBOUNCE_MS = 800;
    private static final long FROM_MAC_GRACE_MS = 2000;

    private final Handler main = new Handler(Looper.getMainLooper());
    private long lastTrigger;

    /**
     * O sistema liga a acessibilidade logo no desbloqueio, mas o One UI chega a atrasar o
     * BOOT_COMPLETED em minutos: aproveita para subir o serviço de conexão mais cedo.
     */
    @Override
    protected void onServiceConnected() {
        if (PairingStore.load(this) == null) return;
        try {
            startForegroundService(new Intent(this, BridgeService.class));
            Log.i(BridgeService.TAG, "service started by accessibility binding");
        } catch (Exception e) {
            Log.w(BridgeService.TAG, "could not start service from accessibility: " + e);
        }
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent e) {
        String reason = triggerReason(e);
        if (reason == null) return;
        long now = SystemClock.elapsedRealtime();
        if (now - lastTrigger < DEBOUNCE_MS) return;
        if (now - BridgeService.lastSetFromMacAt < FROM_MAC_GRACE_MS) return; // fomos nós, com o que veio do Mac
        lastTrigger = now;
        Log.i(BridgeService.TAG, "copy detected (" + reason + ") in " + e.getPackageName());
        main.postDelayed(() -> startActivity(new Intent(this, ReadClipActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION)
                .putExtra(ReadClipActivity.EXTRA_AUTO, true)), READ_DELAY_MS);
    }

    static String triggerReason(AccessibilityEvent e) {
        switch (e.getEventType()) {
            case AccessibilityEvent.TYPE_VIEW_CLICKED: {
                String label = label(e).toLowerCase(Locale.ROOT);
                return label.equals("copiar") || label.equals("copy") || label.startsWith("copiar ") ? "botão" : null;
            }
            case AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED: {
                String text = joined(e.getText()).toLowerCase(Locale.ROOT);
                return text.contains("copiad") || text.contains("copied") ? "aviso" : null;
            }
            case AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED:
                return "com.android.systemui".contentEquals(String.valueOf(e.getPackageName()))
                        && String.valueOf(e.getClassName()).toLowerCase(Locale.ROOT).contains("clipboard") ? "overlay" : null;
            default:
                return null;
        }
    }

    private static String label(AccessibilityEvent e) {
        CharSequence desc = e.getContentDescription();
        return (desc != null ? desc.toString() : joined(e.getText())).trim();
    }

    private static String joined(List<CharSequence> parts) {
        StringBuilder sb = new StringBuilder();
        for (CharSequence p : parts) if (p != null) sb.append(p).append(' ');
        return sb.toString().trim();
    }

    @Override
    public void onInterrupt() {
    }
}
