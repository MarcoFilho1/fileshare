package dev.marcofilho.fileshare;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.net.Uri;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

/**
 * Recebe conteúdo do Mac e grava na área de transferência do tablet.
 * Protocolo provisório: "mime\ntamanho\n<bytes>" em 127.0.0.1:47800, exposto ao Mac por `adb forward`;
 * responde "k" depois de gravar. O tamanho vem no cabeçalho porque o túnel do adb não repassa
 * o fechamento só da escrita (half-close).
 */
public class ReceiverService extends Service {
    static final String TAG = "FileShare";
    static final String CLIP_LABEL = "FileShare";
    static final int PORT = 47800;
    private static final int MAX_CACHED_IMAGES = 10;
    private static final int MAX_PAYLOAD = 25 * 1024 * 1024;

    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile boolean running;
    private ServerSocket server;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel("bridge", "Conexão com o Mac", NotificationManager.IMPORTANCE_LOW));
        Notification n = new Notification.Builder(this, "bridge")
                .setContentTitle("FileShare")
                .setContentText("Aguardando conteúdo do Mac")
                .setSmallIcon(android.R.drawable.stat_sys_upload_done)
                .setOngoing(true)
                .build();
        startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
        if (!running) {
            running = true;
            new Thread(this::serve, "fileshare-server").start();
        }
        return START_STICKY;
    }

    private void serve() {
        try {
            server = new ServerSocket(PORT, 1, InetAddress.getByName("127.0.0.1"));
            Log.i(TAG, "listening on " + PORT);
            while (running) {
                try (Socket s = server.accept()) {
                    handle(s);
                    s.getOutputStream().write('k');
                } catch (Exception e) {
                    Log.e(TAG, "connection error", e);
                }
            }
        } catch (IOException e) {
            Log.e(TAG, "server error", e);
        }
    }

    private void handle(Socket s) throws IOException {
        InputStream in = new BufferedInputStream(s.getInputStream());
        String mime = readLine(in);
        int size = Integer.parseInt(readLine(in));
        if (size <= 0 || size > MAX_PAYLOAD) throw new IOException("invalid size " + size);
        byte[] data = new byte[size];
        new DataInputStream(in).readFully(data);

        if (mime.startsWith("text/")) {
            String text = new String(data, StandardCharsets.UTF_8);
            main.post(() -> setClip(ClipData.newPlainText(CLIP_LABEL, text), "text " + text.length() + " chars"));
            return;
        }
        File dir = ClipProvider.dir(this);
        dir.mkdirs();
        File f = new File(dir, "clip-" + System.currentTimeMillis() + ".png");
        try (FileOutputStream out = new FileOutputStream(f)) {
            out.write(data);
        }
        pruneOldImages(dir);
        Uri uri = ClipProvider.uriFor(f);
        main.post(() -> setClip(ClipData.newUri(getContentResolver(), CLIP_LABEL, uri),
                "image " + data.length + " B"));
    }

    private void setClip(ClipData clip, String what) {
        try {
            getSystemService(ClipboardManager.class).setPrimaryClip(clip);
            Log.i(TAG, "clipboard set from Mac: " + what);
        } catch (Exception e) {
            Log.e(TAG, "setPrimaryClip failed: " + what, e);
        }
    }

    private static void pruneOldImages(File dir) {
        File[] files = dir.listFiles();
        if (files == null || files.length <= MAX_CACHED_IMAGES) return;
        java.util.Arrays.sort(files, (a, c) -> Long.compare(a.lastModified(), c.lastModified()));
        for (int i = 0; i < files.length - MAX_CACHED_IMAGES; i++) files[i].delete();
    }

    private static String readLine(InputStream in) throws IOException {
        StringBuilder sb = new StringBuilder();
        int c;
        while ((c = in.read()) != -1 && c != '\n') sb.append((char) c);
        return sb.toString().trim();
    }

    @Override
    public void onDestroy() {
        running = false;
        try {
            if (server != null) server.close();
        } catch (IOException ignored) {
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
