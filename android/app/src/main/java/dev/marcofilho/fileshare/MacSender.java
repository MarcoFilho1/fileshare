package dev.marcofilho.fileshare;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.Toast;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

/**
 * Envia conteúdo ao Mac. Protocolo provisório: "mime\ntamanho\n<bytes>" para 127.0.0.1:47801,
 * levado ao Mac por `adb reverse`; o Mac responde "k" quando gravou na área de transferência.
 */
final class MacSender {
    static final int MAC_PORT = 47801;
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private MacSender() {
    }

    static void send(Context ctx, ClipReader.Payload p) {
        Context app = ctx.getApplicationContext();
        new Thread(() -> {
            try (Socket s = new Socket()) {
                s.connect(new InetSocketAddress("127.0.0.1", MAC_PORT), 2000);
                s.setSoTimeout(5000);
                OutputStream out = s.getOutputStream();
                out.write((p.mime() + "\n" + p.data().length + "\n").getBytes(StandardCharsets.UTF_8));
                out.write(p.data());
                out.flush();
                if (s.getInputStream().read() != 'k') throw new IOException("no ack from Mac");
                Log.i(ReceiverService.TAG, "sent to Mac: " + p.mime() + " " + p.data().length + " B");
                toast(app, "Enviado ao Mac: " + p.description() + " (" + kb(p.data().length) + ")");
            } catch (Exception e) {
                Log.e(ReceiverService.TAG, "send to Mac failed", e);
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
