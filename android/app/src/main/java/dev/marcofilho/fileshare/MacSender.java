package dev.marcofilho.fileshare;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.Toast;

/** Envia ao Mac pela conexão Wi-Fi do BridgeService e avisa o resultado com um toast. */
final class MacSender {
    private static final long ACK_TIMEOUT_MS = 10_000;
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private MacSender() {
    }

    static void send(Context ctx, ClipReader.Payload p) {
        Context app = ctx.getApplicationContext();
        MacLink link = MacLink.current;
        if (link == null || !link.isConnected()) {
            toast(app, "Mac não conectado");
            return;
        }
        new Thread(() -> {
            try {
                link.send(p.mime(), p.data(), ACK_TIMEOUT_MS);
                Log.i(BridgeService.TAG, "sent to Mac: " + p.mime() + " " + p.data().length + " B");
                toast(app, "Enviado ao Mac: " + p.description() + " (" + kb(p.data().length) + ")");
            } catch (Exception e) {
                Log.e(BridgeService.TAG, "send to Mac failed", e);
                toast(app, "Mac não respondeu");
            }
        }, "fileshare-send").start();
    }

    static void toast(Context ctx, String msg) {
        Context app = ctx.getApplicationContext();
        MAIN.post(() -> Toast.makeText(app, msg, Toast.LENGTH_SHORT).show());
    }

    private static String kb(int bytes) {
        return bytes < 1024 ? bytes + " B" : (bytes / 1024) + " KB";
    }
}
