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
import android.os.BatteryManager;
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
    private static final String LINKS_CHANNEL = "links";
    private static final String RECEIVING_CHANNEL = "receiving";
    private static final int RECEIVING_NOTIFICATION_ID = 5;
    private static final int LINK_NOTIFICATION_ID = 4;
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
    /** Texto atual da notificação fixa ("Conectado ao…", "Procurando…"). */
    private volatile String lastState = "Procurando o Mac no Wi-Fi…";
    private ConnectivityManager.NetworkCallback networkCallback;
    /** Último nível de bateria mandado ao Mac (-1: nenhum nesta conexão); só a thread principal mexe. */
    private int sentBatteryLevel = -1;
    private boolean sentCharging;
    private final BroadcastReceiver battery = new BroadcastReceiver() {
        @Override
        public void onReceive(Context ctx, Intent intent) {
            sendBattery(intent, false);
        }
    };
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
        // o serviço é chamado de novo (acessibilidade, botão…) com a conexão já de pé: mantém o estado atual
        startForeground(NOTIFICATION_ID, notification(lastState),
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
                    lastState = state;
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
                public void onFolder(String folder, int files, String macName) {
                    notifyFolder(folder, files, macName);
                }

                @Override
                public void onReceiving(String name, long received, long size) {
                    int percent = (int) (received * 100 / Math.max(size, 1));
                    nm.createNotificationChannel(new NotificationChannel(RECEIVING_CHANNEL, "Recebendo do Mac", NotificationManager.IMPORTANCE_LOW));
                    nm.notify(RECEIVING_NOTIFICATION_ID, new Notification.Builder(BridgeService.this, RECEIVING_CHANNEL)
                            .setContentTitle("Recebendo do Mac")
                            .setContentText(name + " — " + FileSender.readable(received) + " de " + FileSender.readable(size))
                            .setSmallIcon(android.R.drawable.stat_sys_download)
                            .setProgress(100, percent, false)
                            .addAction(new Notification.Action.Builder(null, "Cancelar",
                                    TransferCancelReceiver.intent(BridgeService.this, TransferCancelReceiver.RECEIVE)).build())
                            .setOngoing(true)
                            .setOnlyAlertOnce(true)
                            .build());
                }

                @Override
                public void onReceivingEnded() {
                    nm.cancel(RECEIVING_NOTIFICATION_ID);
                }

                @Override
                public void onConnected() {
                    // Em outra thread: a entrega espera a confirmação, que chega pela thread da conexão.
                    MacLink current = link;
                    // bateria logo ao conectar, mesmo sem mudança desde a última conexão
                    main.post(() -> sendBattery(registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED)), true));
                    new Thread(() -> {
                        MacSender.deliverHeld(BridgeService.this, current);
                        FileSender.drainOutbox(BridgeService.this);
                    }, "fileshare-outbox").start();
                }
            });
            Outbox.updateNotification(this); // fila que sobrou de antes de reiniciar
            link.start();
            networkCallback = new ConnectivityManager.NetworkCallback() {
                private Network current;

                @Override
                public void onAvailable(Network network) {
                    // Trocou de rede (ex.: 2,4 GHz → 5 GHz): a conexão antiga morreu, mas só daria
                    // erro depois do tempo de leitura. Larga já e reencontra o Mac em segundos.
                    if (current != null && !current.equals(network)) {
                        Log.i(TAG, "network changed; reconnecting");
                        link.repair();
                    } else {
                        link.wake();
                    }
                    current = network;
                }
            };
            getSystemService(ConnectivityManager.class).registerDefaultNetworkCallback(networkCallback);
            IntentFilter f = new IntentFilter(Intent.ACTION_SCREEN_ON);
            f.addAction(Intent.ACTION_USER_PRESENT);
            registerReceiver(screenOn, f, RECEIVER_NOT_EXPORTED);
            registerReceiver(battery, new IntentFilter(Intent.ACTION_BATTERY_CHANGED), RECEIVER_NOT_EXPORTED);
        }
        ShareTargets.update(this);
        return START_STICKY;
    }

    /**
     * Manda o nível ao Mac quando a porcentagem ou o carregamento muda (o sistema avisa também por
     * temperatura e tensão, que não interessam). Na thread principal; a rede vai em outra thread.
     */
    private void sendBattery(Intent intent, boolean force) {
        MacLink current = link;
        if (intent == null || current == null || !current.isConnected()) return;
        int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
        if (level < 0 || scale <= 0) return;
        int percent = Math.round(level * 100f / scale);
        int status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
        boolean charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL;
        if (!force && percent == sentBatteryLevel && charging == sentCharging) return;
        sentBatteryLevel = percent;
        sentCharging = charging;
        new Thread(() -> current.sendBattery(percent, charging), "fileshare-battery").start();
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
            String link = singleLink(text);
            if (link != null) notifyLink(link);
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

    /** Pasta recebida; tocar abre o app Arquivos em Downloads. */
    private void notifyFolder(String folder, int files, String macName) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(FILES_CHANNEL, "Arquivos recebidos do Mac", NotificationManager.IMPORTANCE_DEFAULT));
        Intent open = new Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent tap = PendingIntent.getActivity(this, folder.hashCode(), open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        nm.notify(("folder" + folder).hashCode(), new Notification.Builder(this, FILES_CHANNEL)
                .setContentTitle("Pasta recebida do " + macName)
                .setContentText(folder + " — " + files + (files == 1 ? " arquivo" : " arquivos") + " (Downloads › FileShare)")
                .setSmallIcon(R.drawable.ic_stat_fileshare)
                .setContentIntent(tap)
                .setAutoCancel(true)
                .build());
    }

    /** O texto é só um link da web (o que se copia na barra de endereço)? Devolve o link, ou null. */
    static String singleLink(String text) {
        String t = text.trim();
        if (t.length() > 8192 || t.isEmpty() || t.chars().anyMatch(Character::isWhitespace)) return null;
        try {
            java.net.URI uri = new java.net.URI(t);
            String scheme = uri.getScheme();
            if (scheme == null || !(scheme.equalsIgnoreCase("http") || scheme.equalsIgnoreCase("https"))) return null;
            return uri.getHost() == null || uri.getHost().isEmpty() ? null : t;
        } catch (java.net.URISyntaxException e) {
            return null;
        }
    }

    /**
     * Link copiado no Mac: além de colar, dá para abrir aqui com um toque. Notificação silenciosa,
     * uma só (o link novo substitui o anterior), que some sozinha depois de 10 minutos.
     */
    private void notifyLink(String link) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(LINKS_CHANNEL, "Links copiados no Mac", NotificationManager.IMPORTANCE_LOW));
        Intent view = new Intent(Intent.ACTION_VIEW, Uri.parse(link)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent open = PendingIntent.getActivity(this, LINK_NOTIFICATION_ID, view,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Uri uri = Uri.parse(link);
        nm.notify(LINK_NOTIFICATION_ID, new Notification.Builder(this, LINKS_CHANNEL)
                .setContentTitle("Link do Mac")
                .setContentText(uri.getHost() + uri.getPath())
                .setSmallIcon(R.drawable.ic_stat_fileshare)
                .setContentIntent(open)
                .addAction(new Notification.Action.Builder(null, "Abrir", open).build())
                .setAutoCancel(true)
                .setTimeoutAfter(10 * 60_000)
                .build());
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
            unregisterReceiver(battery);
        }
        if (link != null) link.stop();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
