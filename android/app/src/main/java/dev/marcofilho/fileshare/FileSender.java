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

    /** Arquivo já aberto pela ShareActivity; size é -1 quando o app de origem não informa. */
    record Item(String name, String mime, long size, InputStream in) {
    }

    /** Lê nome, tipo e tamanho e abre o arquivo; precisa rodar enquanto a permissão de leitura vale. */
    static Item open(Context ctx, Uri uri) throws IOException {
        ContentResolver resolver = ctx.getContentResolver();
        String mime = resolver.getType(uri);
        if (mime == null || mime.contains(" ")) mime = "application/octet-stream";
        String name = "arquivo";
        long size = -1;
        try (Cursor c = resolver.query(uri, new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                if (!c.isNull(0)) name = c.getString(0);
                if (!c.isNull(1)) size = c.getLong(1);
            }
        }
        InputStream in = resolver.openInputStream(uri);
        if (in == null) throw new IOException("não consegui abrir " + uri);
        return new Item(name.replaceAll("[\\r\\n]", " ").trim(), mime, size, in);
    }

    static void send(Context ctx, List<Item> items) {
        Context app = ctx.getApplicationContext();
        for (Item item : items) QUEUE.execute(() -> sendOne(app, item));
    }

    private static void sendOne(Context ctx, Item item) {
        String name = item.name();
        File copy = null;
        InputStream in = item.in();
        try {
            long size = item.size();
            if (size < 0) { // o app não informou o tamanho: copia antes para saber
                copy = File.createTempFile("share", null, ctx.getCacheDir());
                try (OutputStream out = new FileOutputStream(copy)) {
                    in.transferTo(out);
                }
                in.close();
                in = new FileInputStream(copy);
                size = copy.length();
            }
            if (size > Wire.MAX_FILE_SIZE) {
                MacSender.toast(ctx, name + " tem mais de 100 MB: não enviei");
                return;
            }
            MacLink link = waitForConnection();
            if (link == null) {
                // Mac longe: guarda na fila, que vai quando ele reconectar
                try {
                    Outbox.enqueue(ctx, name, item.mime(), size, in, copy);
                    copy = null; // agora é da fila
                    Outbox.updateNotification(ctx);
                    Log.i(BridgeService.TAG, "outbox: queued " + item.mime() + " " + size + " B");
                    MacSender.toast(ctx, "Mac longe: " + name + " vai quando ele voltar");
                } catch (IOException e) {
                    Log.w(BridgeService.TAG, "outbox: not queued: " + e.getMessage());
                    MacSender.toast(ctx, "Mac não conectado e " + e.getMessage() + ": " + name + " não foi enviado");
                }
                return;
            }
            if (transfer(ctx, link, name, item.mime(), size, in) == Result.SENT) {
                MacSender.toast(ctx, "Enviado ao Mac: " + name + " (" + readable(size) + ")");
            }
        } catch (Exception e) {
            Log.e(BridgeService.TAG, "file send failed", e);
            MacSender.toast(ctx, "Falha ao enviar " + name + " ao Mac");
        } finally {
            try {
                in.close();
            } catch (IOException ignored) {
            }
            if (copy != null) copy.delete();
        }
    }

    private enum Result { SENT, REFUSED, FAILED }

    /** Manda um arquivo com o progresso na notificação; avisa recusa e falha com um toast. */
    private static Result transfer(Context ctx, MacLink link, String name, String mime, long size, InputStream in) {
        NotificationManager nm = ctx.getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL, "Arquivos enviados ao Mac", NotificationManager.IMPORTANCE_LOW));
        try {
            long[] lastUpdate = {0};
            nm.notify(NOTIFICATION_ID, progress(ctx, name, 0, size));
            link.sendFile(name, mime, size, in, sent -> {
                long now = SystemClock.elapsedRealtime();
                if (now - lastUpdate[0] > 300) {
                    lastUpdate[0] = now;
                    nm.notify(NOTIFICATION_ID, progress(ctx, name, sent, size));
                }
            }, ACK_TIMEOUT_MS);
            Log.i(BridgeService.TAG, "file sent to Mac: " + mime + " " + size + " B");
            return Result.SENT;
        } catch (MacLink.RefusedException e) {
            Log.w(BridgeService.TAG, "Mac refused file: " + e.getMessage());
            MacSender.toast(ctx, "O Mac recusou " + name + ": " + e.getMessage());
            return Result.REFUSED;
        } catch (TimeoutException e) {
            MacSender.toast(ctx, "O Mac não confirmou " + name);
            return Result.FAILED;
        } catch (Exception e) {
            Log.e(BridgeService.TAG, "file send failed", e);
            MacSender.toast(ctx, "Falha ao enviar " + name + " ao Mac");
            return Result.FAILED;
        } finally {
            nm.cancel(NOTIFICATION_ID);
        }
    }

    /**
     * Conexão pronta: manda, na mesma fila dos envios, os arquivos que esperavam o Mac. Para no
     * primeiro que falhar (a conexão caiu de novo); um arquivo recusado sai da fila.
     */
    static void drainOutbox(Context ctx) {
        Context app = ctx.getApplicationContext();
        QUEUE.execute(() -> {
            int sent = 0;
            for (Outbox.QueuedFile f : Outbox.list(app)) {
                MacLink link = MacLink.current;
                if (link == null || !link.isConnected()) break;
                Result r;
                try (InputStream in = new FileInputStream(f.data())) {
                    r = transfer(app, link, f.name(), f.mime(), f.size(), in);
                } catch (IOException e) {
                    r = Result.REFUSED; // arquivo da fila ilegível: não adianta tentar de novo
                }
                if (r == Result.FAILED) break;
                Outbox.remove(f);
                if (r == Result.SENT) sent++;
            }
            Outbox.updateNotification(app);
            if (sent > 0) MacSender.toast(app, sent == 1 ? "Arquivo guardado enviado ao Mac" : sent + " arquivos guardados enviados ao Mac");
        });
    }

    /**
     * Logo depois de acordar o tablet (ou de o serviço subir) a conexão pode estar se refazendo:
     * espera um pouco. Devolve a conexão pronta, ou null.
     */
    private static MacLink waitForConnection() throws InterruptedException {
        long until = SystemClock.elapsedRealtime() + CONNECT_WAIT_MS;
        boolean woke = false;
        while (SystemClock.elapsedRealtime() < until) {
            MacLink link = MacLink.current;
            if (link != null && link.isConnected()) return link;
            if (link != null && !woke) {
                link.wake();
                woke = true;
            }
            Thread.sleep(200);
        }
        return null;
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
