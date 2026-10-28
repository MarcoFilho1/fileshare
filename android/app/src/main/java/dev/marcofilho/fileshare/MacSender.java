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
            hold(app, p, "Mac longe: " + p.description() + " vai quando ele voltar (até 10 min)");
            if (link != null) link.wake();
            return;
        }
        new Thread(() -> {
            try {
                link.send(p.mime(), p.data(), ACK_TIMEOUT_MS);
                Log.i(BridgeService.TAG, "sent to Mac: " + p.mime() + " " + p.data().length + " B");
                toast(app, "Enviado ao Mac: " + p.description() + " (" + kb(p.data().length) + ")");
            } catch (Exception e) {
                Log.e(BridgeService.TAG, "send to Mac failed", e);
                hold(app, p, "Mac não respondeu: tento de novo quando ele voltar");
            }
        }, "fileshare-send").start();
    }

    /** Guarda a cópia para o Mac (só a última vale) e avisa. */
    private static void hold(Context app, ClipReader.Payload p, String message) {
        Outbox.holdClip(p.mime(), p.data());
        Log.i(BridgeService.TAG, "held for the Mac: " + p.mime() + " " + p.data().length + " B");
        toast(app, message);
    }

    /** Compartilhar → Abrir no Mac. Com o Mac longe só avisa: abrir uma página sozinha horas depois seria estranho. */
    static void openOnMac(Context ctx, String url) {
        Context app = ctx.getApplicationContext();
        MacLink link = MacLink.current;
        if (link == null || !link.isConnected()) {
            toast(app, "Mac não conectado: não abri o link");
            if (link != null) link.wake();
            return;
        }
        if (!link.macSupports(MacLink.Capability.OPEN)) {
            toast(app, "Atualize o FileShare no Mac para abrir links nele");
            return;
        }
        new Thread(() -> {
            try {
                link.sendOpen(url, ACK_TIMEOUT_MS);
                Log.i(BridgeService.TAG, "link opened on Mac");
                toast(app, "Aberto no Mac");
            } catch (MacLink.RefusedException e) {
                toast(app, "O Mac não abriu: " + e.getMessage());
            } catch (Exception e) {
                Log.e(BridgeService.TAG, "open on Mac failed", e);
                toast(app, "Mac não respondeu");
            }
        }, "fileshare-open").start();
    }

    /** Conexão pronta: entrega a cópia guardada, se o Mac sabe recebê-la. Roda fora da thread principal. */
    static void deliverHeld(Context ctx, MacLink link) {
        Outbox.Clip c = Outbox.takeClip();
        if (c == null) return;
        if (!link.macSupports(MacLink.Capability.HELD)) {
            Log.i(BridgeService.TAG, "Mac is older than 2.4 and can't take the held copy; dropped");
            toast(ctx, "Atualize o FileShare no Mac para receber cópias guardadas");
            return;
        }
        try {
            link.sendHeld(c.mime(), c.data(), c.copiedAt(), ACK_TIMEOUT_MS);
            Log.i(BridgeService.TAG, "held copy delivered to Mac: " + c.mime() + " " + c.data().length + " B");
            toast(ctx, "Cópia guardada entregue ao Mac");
        } catch (Exception e) {
            Log.e(BridgeService.TAG, "held copy not delivered", e);
            Outbox.restoreClip(c);
        }
    }

    static void toast(Context ctx, String msg) {
        Context app = ctx.getApplicationContext();
        MAIN.post(() -> Toast.makeText(app, msg, Toast.LENGTH_SHORT).show());
    }

    private static String kb(int bytes) {
        return bytes < 1024 ? bytes + " B" : (bytes / 1024) + " KB";
    }
}
