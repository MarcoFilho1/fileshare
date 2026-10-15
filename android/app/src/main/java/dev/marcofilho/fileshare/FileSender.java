package dev.marcofilho.fileshare;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.SystemClock;
import android.provider.OpenableColumns;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeoutException;

/** Envia ao Mac, um de cada vez, os arquivos do menu Compartilhar, com o progresso numa notificação. */
final class FileSender {
    private static final int NOTIFICATION_ID = 2;
    private static final String CHANNEL = "files";
    private static final long CONNECT_WAIT_MS = 15_000;
    private static final long ACK_TIMEOUT_MS = 30_000;
    private static final ExecutorService QUEUE = Executors.newSingleThreadExecutor(r -> new Thread(r, "fileshare-files"));

    private FileSender() {
    }

    static void send(Context ctx, MacLink link, List<Uri> uris) {
        Context app = ctx.getApplicationContext();
        for (Uri uri : uris) QUEUE.execute(() -> sendOne(app, link, uri));
    }

    private static void sendOne(Context ctx, MacLink link, Uri uri) {
        NotificationManager nm = ctx.getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL, "Arquivos enviados ao Mac", NotificationManager.IMPORTANCE_LOW));
        ContentResolver resolver = ctx.getContentResolver();
        String name = "arquivo";
        File copy = null;
        try {
            String mime = resolver.getType(uri);
            if (mime == null || mime.contains(" ")) mime = "application/octet-stream";
            long size = -1;
            try (Cursor c = resolver.query(uri, new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE}, null, null, null)) {
                if (c != null && c.moveToFirst()) {
                    if (!c.isNull(0)) name = c.getString(0);
                    if (!c.isNull(1)) size = c.getLong(1);
                }
            }
            name = name.replaceAll("[\\r\\n]", " ").trim();
            if (size < 0) { // o app não informou o tamanho: copia antes para saber
                copy = File.createTempFile("share", null, ctx.getCacheDir());
                try (InputStream in = resolver.openInputStream(uri); OutputStream out = new FileOutputStream(copy)) {
                    if (in == null) throw new IOException("não consegui abrir o arquivo");
                    in.transferTo(out);
                }
                size = copy.length();
            }
            if (size > Wire.MAX_FILE_SIZE) {
                MacSender.toast(ctx, name + " tem mais de 100 MB: não enviei");
                return;
            }
            if (!waitForConnection(link)) {
                MacSender.toast(ctx, "Mac não conectado: " + name + " não foi enviado");
                return;
            }

            String label = name;
            long total = size;
            long[] lastUpdate = {0};
            nm.notify(NOTIFICATION_ID, progress(ctx, label, 0, total));
            try (InputStream in = copy != null ? new FileInputStream(copy) : resolver.openInputStream(uri)) {
                if (in == null) throw new IOException("não consegui abrir o arquivo");
                link.sendFile(name, mime, size, in, sent -> {
                    long now = SystemClock.elapsedRealtime();
                    if (now - lastUpdate[0] > 300) {
                        lastUpdate[0] = now;
                        nm.notify(NOTIFICATION_ID, progress(ctx, label, sent, total));
                    }
                }, ACK_TIMEOUT_MS);
            }
            Log.i(BridgeService.TAG, "file sent to Mac: " + mime + " " + size + " B");
            MacSender.toast(ctx, "Enviado ao Mac: " + name + " (" + readable(size) + ")");
        } catch (MacLink.RefusedException e) {
            Log.w(BridgeService.TAG, "Mac refused file: " + e.getMessage());
            MacSender.toast(ctx, "O Mac recusou " + name + ": " + e.getMessage());
        } catch (TimeoutException e) {
            MacSender.toast(ctx, "O Mac não confirmou " + name);
        } catch (Exception e) {
            Log.e(BridgeService.TAG, "file send failed", e);
            MacSender.toast(ctx, "Falha ao enviar " + name + " ao Mac");
        } finally {
            nm.cancel(NOTIFICATION_ID);
            if (copy != null) copy.delete();
        }
    }

    /** Logo depois de acordar o tablet a conexão pode estar se refazendo: espera um pouco. */
    private static boolean waitForConnection(MacLink link) throws InterruptedException {
        if (link.isConnected()) return true;
        link.wake();
        long until = SystemClock.elapsedRealtime() + CONNECT_WAIT_MS;
        while (!link.isConnected() && SystemClock.elapsedRealtime() < until) Thread.sleep(200);
        return link.isConnected();
    }

    private static Notification progress(Context ctx, String name, long sent, long total) {
        int percent = total == 0 ? 100 : (int) (sent * 100 / total);
        return new Notification.Builder(ctx, CHANNEL)
                .setContentTitle("Enviando ao Mac")
                .setContentText(name + " — " + readable(sent) + " de " + readable(total))
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setProgress(100, percent, false)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build();
    }

    static String readable(long bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024) + " KB";
        return String.format(Locale.forLanguageTag("pt-BR"), "%.1f MB", bytes / (1024.0 * 1024.0));
    }
}
