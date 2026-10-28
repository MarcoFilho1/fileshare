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
    /** Cancelar da notificação "Enviando ao Mac": vale para o arquivo que está indo agora. */
    private static volatile boolean cancelRequested;
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
                MacSender.toast(ctx, name + " é grande demais: não enviei");
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

    private enum Result { SENT, REFUSED, FAILED, CANCELLED }

    /** Botão Cancelar da notificação de envio. */
    static void cancelCurrent() {
        cancelRequested = true;
    }

    /** Manda um arquivo com o progresso na notificação; avisa recusa e falha com um toast. */
    private static final int MAX_ATTEMPTS = 6;
    /** Quanto esperar o Mac voltar para continuar um arquivo que caiu no meio. */
    private static final long RESUME_WAIT_MS = 2 * 60_000;

    private static Result transfer(Context ctx, MacLink link, String name, String mime, long size, InputStream in) {
        NotificationManager nm = ctx.getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL, "Arquivos enviados ao Mac", NotificationManager.IMPORTANCE_LOW));
        long limit = Wire.maxFileSize(link.macSupports(MacLink.Capability.BIG_FILES));
        if (size > limit) {
            MacSender.toast(ctx, name + " passa de " + readable(limit) + ": atualize o FileShare no Mac");
            return Result.REFUSED;
        }
        cancelRequested = false;
        long startedAt = SystemClock.elapsedRealtime();
        // Mesmo transferId em todas as tentativas: se a conexão cair, o Mac 2.6+ continua de onde parou.
        String transferId = Wire.newTransferId();
        boolean resumable = in instanceof FileInputStream;
        long[] lastUpdate = {0};
        java.util.function.LongConsumer onProgress = sent -> {
            long now = SystemClock.elapsedRealtime();
            if (now - lastUpdate[0] > 300) {
                lastUpdate[0] = now;
                nm.notify(NOTIFICATION_ID, progress(ctx, name, sent, size));
            }
        };
        try {
            nm.notify(NOTIFICATION_ID, progress(ctx, name, 0, size));
            for (int attempt = 1; ; attempt++) {
                try {
                    link.sendFile(name, mime, size, in, transferId, onProgress, () -> cancelRequested, ACK_TIMEOUT_MS);
                    Log.i(BridgeService.TAG, "file sent to Mac: " + mime + " " + Wire.speed(size, startedAt, SystemClock.elapsedRealtime()));
                    return Result.SENT;
                } catch (MacLink.CancelledException | MacLink.RefusedException e) {
                    throw e;
                } catch (Exception e) {
                    boolean dropped = !link.isConnected();
                    if (!resumable || !dropped || cancelRequested || attempt >= MAX_ATTEMPTS || !link.macSupports(MacLink.Capability.RESUME)) throw e;
                    Log.i(BridgeService.TAG, "connection dropped while sending; waiting to continue (" + e + ")");
                    nm.notify(NOTIFICATION_ID, waiting(ctx, name));
                    MacLink next = waitForConnection(RESUME_WAIT_MS);
                    if (next == null) throw e;
                    link = next;
                }
            }
        } catch (MacLink.CancelledException e) {
            Log.i(BridgeService.TAG, "file send cancelled");
            MacSender.toast(ctx, "Envio cancelado: " + name);
            return Result.CANCELLED;
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

    /** Conexão caiu no meio de um arquivo: espera o Mac voltar para continuar de onde parou. */
    private static Notification waiting(Context ctx, String name) {
        return new Notification.Builder(ctx, CHANNEL)
                .setContentTitle("Esperando o Mac para continuar")
                .setContentText(name + " — continua de onde parou quando ele voltar")
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setProgress(0, 0, true)
                .addAction(new Notification.Action.Builder(null, "Cancelar", TransferCancelReceiver.intent(ctx, TransferCancelReceiver.SEND)).build())
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build();
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
        return waitForConnection(CONNECT_WAIT_MS);
    }

    private static MacLink waitForConnection(long waitMs) throws InterruptedException {
        long until = SystemClock.elapsedRealtime() + waitMs;
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
                .addAction(new Notification.Action.Builder(null, "Cancelar", TransferCancelReceiver.intent(ctx, TransferCancelReceiver.SEND)).build())
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build();
    }

    static String readable(long bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024) + " KB";
        if (bytes < 1024L * 1024 * 1024) return String.format(Locale.forLanguageTag("pt-BR"), "%.1f MB", bytes / (1024.0 * 1024.0));
        return String.format(Locale.forLanguageTag("pt-BR"), "%.1f GB", bytes / (1024.0 * 1024.0 * 1024.0));
    }
}
