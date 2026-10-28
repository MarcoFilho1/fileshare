package dev.marcofilho.fileshare;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.Uri;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/**
 * Serviço em primeiro plano que mantém a conexão com o Mac (MacLink) e grava na área de
 * transferência do tablet o que chega de lá.
 */
public class BridgeService extends Service {
    static final String TAG = "FileShare";
    static final String CLIP_LABEL = "FileShare";
    private static final String FILES_CHANNEL = "received-files";
    private static final int NOTIFICATION_ID = 1;
    private static final int MAX_CACHED_IMAGES = 10;

    /** Quando gravamos algo vindo do Mac; o aviso de "copiado" que o sistema mostra em seguida não é do usuário. */
    static volatile long lastSetFromMacAt;

    /** Quando o usuário copiou algo no tablet (relógio de parede, ms), para comparar com o HELD do Mac. */
    static volatile long lastUserCopyAt;

    /** Tela inicial aberta: é avisada (na thread principal) quando o estado da conexão muda. */
    static volatile Runnable statusListener;

    private final Handler main = new Handler(Looper.getMainLooper());
    private MacLink link;
    private ConnectivityManager.NetworkCallback networkCallback;
    private final BroadcastReceiver screenOn = new BroadcastReceiver() {
        @Override
        public void onReceive(Context ctx, Intent intent) {
            if (link != null) link.onScreenOn();
        }
    };

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel("bridge", "Conexão com o Mac", NotificationManager.IMPORTANCE_LOW));
        startForeground(NOTIFICATION_ID, notification("Procurando o Mac no Wi-Fi…"),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
        if (link == null) {
            link = new MacLink(this, new MacLink.Listener() {
                @Override
                public void onClip(String mime, byte[] data) {
                    received(mime, data);
                }

                @Override
                public void onHeld(String mime, byte[] data, long copiedAt) {
                    if (copiedAt < lastUserCopyAt) {
                        Log.i(TAG, "held copy from Mac is older than the last copy on the tablet; ignored");
                        return;
                    }
                    received(mime, data);
                }

                @Override
                public void onState(String state) {
                    nm.notify(NOTIFICATION_ID, notification(state));
                    main.post(() -> {
                        Runnable listener = statusListener;
                        if (listener != null) listener.run();
                    });
                }

                @Override
                public void onFile(Uri uri, String name, String mime, String macName) {
                    notifyFile(uri, name, mime, macName);
                }

                @Override
                public void onConnected() {
                    // Em outra thread: a entrega espera a confirmação, que chega pela thread da conexão.
                    MacLink current = link;
                    new Thread(() -> {
                        MacSender.deliverHeld(BridgeService.this, current);
                        FileSender.drainOutbox(BridgeService.this);
                    }, "fileshare-outbox").start();
                }
            });
            Outbox.updateNotification(this); // fila que sobrou de antes de reiniciar
            link.start();
            networkCallback = new ConnectivityManager.NetworkCallback() {
                @Override
                public void onAvailable(Network network) {
                    link.wake();
                }
            };
            getSystemService(ConnectivityManager.class).registerDefaultNetworkCallback(networkCallback);
            IntentFilter f = new IntentFilter(Intent.ACTION_SCREEN_ON);
            f.addAction(Intent.ACTION_USER_PRESENT);
            registerReceiver(screenOn, f, RECEIVER_NOT_EXPORTED);
        }
        ShareTargets.update(this);
        return START_STICKY;
    }

    private Notification notification(String text) {
        return new Notification.Builder(this, "bridge")
                .setContentTitle("FileShare")
                .setContentText(text)
                .setSmallIcon(R.drawable.ic_stat_fileshare)
                .setOngoing(true)
                .build();
    }

    /** Aviso de arquivo recebido; tocar abre o arquivo no app escolhido (Samsung Notes para PDF, por exemplo). */
    private void notifyFile(Uri uri, String name, String mime, String macName) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(FILES_CHANNEL, "Arquivos recebidos do Mac", NotificationManager.IMPORTANCE_DEFAULT));
        Intent open = new Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mime)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent tap = PendingIntent.getActivity(this, uri.hashCode(), Intent.createChooser(open, "Abrir " + name),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        String kind = mime.equals("application/pdf") ? "PDF" : mime.startsWith("image/") ? "Imagem" : mime.startsWith("video/") ? "Vídeo" : "Arquivo";
        nm.notify(uri.hashCode(), new Notification.Builder(this, FILES_CHANNEL)
                .setContentTitle(kind + " recebido do " + macName)
                .setContentText(name + " — toque para abrir (Downloads › FileShare)")
                .setSmallIcon(R.drawable.ic_stat_fileshare)
                .setContentIntent(tap)
                .setAutoCancel(true)
                .build());
    }

    private void received(String mime, byte[] data) {
        if (mime.startsWith("text/")) {
            String text = new String(data, StandardCharsets.UTF_8);
            main.post(() -> setClip(ClipData.newPlainText(CLIP_LABEL, text), "text " + text.length() + " chars"));
            return;
        }
        try {
            File dir = ClipProvider.dir(this);
            dir.mkdirs();
            File f = new File(dir, "clip-" + System.currentTimeMillis() + ".png");
            try (FileOutputStream out = new FileOutputStream(f)) {
                out.write(data);
            }
            pruneOldImages(dir);
            Uri uri = ClipProvider.uriFor(f);
            main.post(() -> setClip(ClipData.newUri(getContentResolver(), CLIP_LABEL, uri), "image " + data.length + " B"));
        } catch (IOException e) {
            Log.e(TAG, "could not store image from Mac", e);
        }
    }

    private void setClip(ClipData clip, String what) {
        try {
            lastSetFromMacAt = SystemClock.elapsedRealtime();
            getSystemService(ClipboardManager.class).setPrimaryClip(clip);
            Log.i(TAG, "clipboard set from Mac: " + what);
        } catch (Exception e) {
            Log.e(TAG, "setPrimaryClip failed: " + what, e);
        }
    }

    private static void pruneOldImages(File dir) {
        File[] files = dir.listFiles();
        if (files == null || files.length <= MAX_CACHED_IMAGES) return;
        Arrays.sort(files, (a, b) -> Long.compare(a.lastModified(), b.lastModified()));
        for (int i = 0; i < files.length - MAX_CACHED_IMAGES; i++) files[i].delete();
    }

    @Override
    public void onDestroy() {
        if (networkCallback != null) {
            getSystemService(ConnectivityManager.class).unregisterNetworkCallback(networkCallback);
            unregisterReceiver(screenOn);
        }
        if (link != null) link.stop();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
