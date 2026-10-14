package dev.marcofilho.fileshare;

import android.content.Context;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Conexão permanente com o Mac pelo Wi-Fi: acha o Mac por NSD, conecta, manda PING a cada 20 s
 * e reconecta sozinha (espera crescente até 30 s) quando a conexão cai.
 */
final class MacLink {
    interface Listener {
        void onClip(String mime, byte[] data);

        void onState(String state);
    }

    private static final int PING_MS = 20_000;
    private static final int READ_TIMEOUT_MS = 60_000;
    private static final long MAX_BACKOFF_MS = 30_000;

    static volatile MacLink current;

    private final Context ctx;
    private final Listener listener;
    private final AtomicInteger nextId = new AtomicInteger(1);
    private final Map<Integer, CompletableFuture<Void>> pending = new ConcurrentHashMap<>();
    private final Object sleepLock = new Object();
    private volatile boolean running;
    private volatile Socket socket;
    private volatile OutputStream out;
    private Thread loop;

    MacLink(Context ctx, Listener listener) {
        this.ctx = ctx.getApplicationContext();
        this.listener = listener;
    }

    void start() {
        if (running) return;
        running = true;
        current = this;
        loop = new Thread(this::run, "fileshare-link");
        loop.start();
    }

    void stop() {
        running = false;
        if (current == this) current = null;
        closeSocket();
        wake();
    }

    /** Rede mudou: tenta de novo agora em vez de esperar o fim da espera. */
    void wake() {
        synchronized (sleepLock) {
            sleepLock.notifyAll();
        }
    }

    boolean isConnected() {
        return out != null;
    }

    /** Envia ao Mac e espera a confirmação. */
    void send(String mime, byte[] data, long timeoutMs) throws Exception {
        if (out == null) throw new IOException("Mac não conectado");
        int id = nextId.getAndIncrement();
        CompletableFuture<Void> ack = new CompletableFuture<>();
        pending.put(id, ack);
        try {
            write(Wire.Message.clip(id, mime, data));
            ack.get(timeoutMs, TimeUnit.MILLISECONDS);
        } finally {
            pending.remove(id);
        }
    }

    private void run() {
        long backoff = 1000;
        while (running) {
            try {
                listener.onState("Procurando o Mac no Wi-Fi…");
                MacFinder.Found mac = MacFinder.find(ctx, 15_000);
                if (mac != null) {
                    session(mac);
                    backoff = 1000; // conectou: a próxima tentativa começa rápida
                }
            } catch (InterruptedException e) {
                return;
            } catch (Exception e) {
                Log.w(BridgeService.TAG, "link error: " + e);
            }
            if (!running) return;
            listener.onState("Mac não encontrado; tentando de novo");
            synchronized (sleepLock) {
                try {
                    sleepLock.wait(backoff);
                } catch (InterruptedException e) {
                    return;
                }
            }
            backoff = Math.min(backoff * 2, MAX_BACKOFF_MS);
        }
    }

    private void session(MacFinder.Found mac) throws IOException {
        Socket s = new Socket();
        try {
            s.connect(new InetSocketAddress(mac.host(), mac.port()), 5000);
            s.setSoTimeout(READ_TIMEOUT_MS);
            s.setKeepAlive(true);
            s.setTcpNoDelay(true);
            socket = s;
            out = new BufferedOutputStream(s.getOutputStream(), 1 << 16);
            write(Wire.Message.hello(deviceName()));
            Log.i(BridgeService.TAG, "connected to " + mac.name() + " at " + mac.host() + ":" + mac.port());
            listener.onState("Conectado ao " + mac.name());

            Thread pinger = new Thread(() -> {
                try {
                    while (socket == s) {
                        Thread.sleep(PING_MS);
                        write(Wire.Message.ping());
                    }
                } catch (Exception ignored) {
                    // a sessão acabou
                }
            }, "fileshare-ping");
            pinger.start();

            DataInputStream in = new DataInputStream(new BufferedInputStream(s.getInputStream(), 1 << 16));
            while (running) {
                Wire.Message m = Wire.read(in);
                switch (m.type) {
                    case CLIP:
                        listener.onClip(m.text, m.data);
                        write(Wire.Message.ack(m.id));
                        break;
                    case ACK: {
                        CompletableFuture<Void> f = pending.remove(m.id);
                        if (f != null) f.complete(null);
                        break;
                    }
                    case PING:
                        write(Wire.Message.pong());
                        break;
                    default:
                        break;
                }
            }
        } finally {
            closeSocket();
            for (CompletableFuture<Void> f : pending.values()) f.completeExceptionally(new IOException("conexão caiu"));
            pending.clear();
            Log.i(BridgeService.TAG, "disconnected from " + mac.name());
        }
    }

    private synchronized void write(Wire.Message m) throws IOException {
        OutputStream o = out;
        if (o == null) throw new IOException("Mac não conectado");
        Wire.write(o, m);
    }

    private void closeSocket() {
        out = null;
        Socket s = socket;
        socket = null;
        if (s != null) {
            try {
                s.close();
            } catch (IOException ignored) {
            }
        }
    }

    private String deviceName() {
        String name = Settings.Global.getString(ctx.getContentResolver(), "device_name");
        return name != null && !name.isEmpty() ? name : Build.MODEL;
    }
}
