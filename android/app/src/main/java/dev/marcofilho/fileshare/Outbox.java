package dev.marcofilho.fileshare;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.SystemClock;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * O que o tablet tentou mandar com o Mac longe: a última cópia (vale 10 min, só na memória) e uma
 * fila de arquivos em files/outbox (vale 24 h, até 500 MB). Tudo vai ao Mac quando ele reconectar.
 */
final class Outbox {
    static final long CLIP_TTL_MS = 10 * 60_000;
    static final long FILE_TTL_MS = 24 * 60 * 60_000L;
    /** Cabe um arquivo do tamanho máximo; o espaço livre do tablet também é conferido. */
    static final long MAX_BYTES = Wire.MAX_FILE_SIZE;
    private static final String CHANNEL = "outbox";
    private static final int NOTIFICATION_ID = 3;

    /** Cópia guardada; copiedAt é o relógio de parede (para o Mac comparar), heldAt o relógio do aparelho. */
    record Clip(String mime, byte[] data, long copiedAt, long heldAt) {
        boolean expired() {
            return SystemClock.elapsedRealtime() - heldAt > CLIP_TTL_MS;
        }
    }

    /** Arquivo na fila: uma pasta com "data" e "meta" (nome e tipo, uma linha cada). */
    record QueuedFile(File dir, String name, String mime, long createdAt) {
        File data() {
            return new File(dir, "data");
        }

        long size() {
            return data().length();
        }
    }

    private static Clip clip;

    private Outbox() {
    }

    // ---------- cópia ----------

    static synchronized void holdClip(String mime, byte[] data) {
        clip = new Clip(mime, data, System.currentTimeMillis(), SystemClock.elapsedRealtime());
    }

    /** Tira a cópia guardada para enviar; null se não há ou se passou de 10 min. */
    static synchronized Clip takeClip() {
        Clip c = clip;
        clip = null;
        return c == null || c.expired() ? null : c;
    }

    /** O envio falhou: devolve a cópia, a menos que o usuário já tenha copiado outra coisa. */
    static synchronized void restoreClip(Clip c) {
        if (clip == null) clip = c;
    }

    // ---------- arquivos ----------

    private static File root(Context ctx) {
        return new File(ctx.getFilesDir(), "outbox");
    }

    /**
     * Guarda o arquivo na fila. Se `existing` não for null (cópia temporária já feita), ela é movida
     * em vez de lida de novo. Recusa com IOException se a fila passaria de 500 MB.
     */
    static synchronized QueuedFile enqueue(Context ctx, String name, String mime, long size, InputStream in, File existing) throws IOException {
        long used = 0;
        for (QueuedFile f : list(ctx)) used += f.size();
        if (used + size > MAX_BYTES) throw new IOException("a fila para o Mac já tem " + FileSender.readable(used));
        if (!Wire.hasRoom(size, ctx.getFilesDir().getUsableSpace())) throw new IOException("falta espaço no tablet");
        long now = System.currentTimeMillis();
        File dir = new File(root(ctx), now + "-" + Integer.toHexString((int) (Math.random() * 0xffff)));
        if (!dir.mkdirs()) throw new IOException("não consegui criar " + dir);
        try {
            File data = new File(dir, "data");
            if (existing == null || !existing.renameTo(data)) {
                try (OutputStream out = new FileOutputStream(data)) {
                    if (existing != null) Files.copy(existing.toPath(), out);
                    else in.transferTo(out);
                }
            }
            Files.write(new File(dir, "meta").toPath(), (name + "\n" + mime + "\n").getBytes(StandardCharsets.UTF_8));
        } catch (IOException e) {
            deleteDir(dir);
            throw e;
        }
        return new QueuedFile(dir, name, mime, now);
    }

    /** Arquivos na fila, do mais antigo ao mais novo; apaga os que passaram de 24 h ou ficaram incompletos. */
    static synchronized List<QueuedFile> list(Context ctx) {
        List<QueuedFile> out = new ArrayList<>();
        File[] dirs = root(ctx).listFiles(File::isDirectory);
        if (dirs == null) return out;
        Arrays.sort(dirs, (a, b) -> a.getName().compareTo(b.getName()));
        long now = System.currentTimeMillis();
        for (File dir : dirs) {
            try {
                long createdAt = Long.parseLong(dir.getName().split("-")[0]);
                String[] meta = new String(Files.readAllBytes(new File(dir, "meta").toPath()), StandardCharsets.UTF_8).split("\n");
                if (meta.length < 2 || !new File(dir, "data").isFile()) throw new IOException("incompleto");
                if (now - createdAt > FILE_TTL_MS) {
                    Log.i(BridgeService.TAG, "outbox: " + meta[0] + " waited more than 24 h; discarded");
                    deleteDir(dir);
                    continue;
                }
                out.add(new QueuedFile(dir, meta[0], meta[1], createdAt));
            } catch (IOException | RuntimeException e) {
                deleteDir(dir);
            }
        }
        return out;
    }

    static synchronized void remove(QueuedFile f) {
        deleteDir(f.dir());
    }

    static synchronized void clear(Context ctx) {
        File[] dirs = root(ctx).listFiles();
        if (dirs != null) for (File d : dirs) deleteDir(d);
    }

    private static void deleteDir(File dir) {
        File[] files = dir.listFiles();
        if (files != null) for (File f : files) f.delete();
        dir.delete();
    }

    // ---------- aviso ----------

    /** Notificação fixa "Esperando o Mac" enquanto há arquivos na fila, com o botão Cancelar. */
    static void updateNotification(Context ctx) {
        NotificationManager nm = ctx.getSystemService(NotificationManager.class);
        List<QueuedFile> files = list(ctx);
        if (files.isEmpty()) {
            nm.cancel(NOTIFICATION_ID);
            return;
        }
        nm.createNotificationChannel(new NotificationChannel(CHANNEL, "Esperando o Mac", NotificationManager.IMPORTANCE_LOW));
        long bytes = 0;
        for (QueuedFile f : files) bytes += f.size();
        String what = files.size() == 1 ? files.get(0).name() : files.size() + " arquivos";
        PendingIntent cancel = PendingIntent.getBroadcast(ctx, 0, new Intent(ctx, CancelReceiver.class),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        nm.notify(NOTIFICATION_ID, new Notification.Builder(ctx, CHANNEL)
                .setContentTitle("Esperando o Mac")
                .setContentText(what + " (" + FileSender.readable(bytes) + ") vai quando o Mac estiver por perto")
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .addAction(new Notification.Action.Builder(null, "Cancelar", cancel).build())
                .build());
    }

    /** Botão Cancelar da notificação: esvazia a fila. */
    public static final class CancelReceiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context ctx, Intent intent) {
            clear(ctx);
            updateNotification(ctx);
            MacSender.toast(ctx, "Fila para o Mac cancelada");
        }
    }
}
