package dev.marcofilho.fileshare;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.util.Log;

import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.Queue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Procura na rede local o serviço "_fileshare._tcp" do Mac pareado (id no registro TXT);
 * outros Macs com FileShare na mesma rede são ignorados.
 */
final class MacFinder {
    static final String SERVICE_TYPE = "_fileshare._tcp.";

    record Found(InetAddress host, int port) {
    }

    private MacFinder() {
    }

    /**
     * Bloqueia até achar o Mac, estourar o tempo ou `stop` pedir (rede mudou, tela ligou: vale
     * recomeçar a busca); retorna null se não achou.
     */
    @SuppressWarnings("deprecation") // resolveService: a alternativa só existe a partir do Android 14
    static Found find(Context ctx, String macId, long timeoutMs, java.util.function.BooleanSupplier stop) throws InterruptedException {
        NsdManager nsd = ctx.getSystemService(NsdManager.class);
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Found> result = new AtomicReference<>();
        Queue<NsdServiceInfo> toResolve = new ArrayDeque<>();
        boolean[] resolving = {false};

        // O NSD resolve um serviço por vez: vai tirando da fila até achar o id certo.
        Runnable[] resolveNext = new Runnable[1];
        resolveNext[0] = () -> {
            NsdServiceInfo next;
            synchronized (toResolve) {
                if (resolving[0] || (next = toResolve.poll()) == null) return;
                resolving[0] = true;
            }
            nsd.resolveService(next, new NsdManager.ResolveListener() {
                @Override
                public void onServiceResolved(NsdServiceInfo r) {
                    byte[] id = r.getAttributes().get("id");
                    if (id != null && macId.equals(new String(id, StandardCharsets.UTF_8))) {
                        result.set(new Found(r.getHost(), r.getPort()));
                        done.countDown();
                    }
                    finished();
                }

                @Override
                public void onResolveFailed(NsdServiceInfo r, int error) {
                    Log.w(BridgeService.TAG, "resolve failed: " + error);
                    finished();
                }

                private void finished() {
                    synchronized (toResolve) {
                        resolving[0] = false;
                    }
                    resolveNext[0].run();
                }
            });
        };

        NsdManager.DiscoveryListener discovery = new NsdManager.DiscoveryListener() {
            @Override
            public void onServiceFound(NsdServiceInfo info) {
                synchronized (toResolve) {
                    toResolve.add(info);
                }
                resolveNext[0].run();
            }

            @Override
            public void onStartDiscoveryFailed(String type, int error) {
                Log.w(BridgeService.TAG, "discovery failed: " + error);
                done.countDown();
            }

            @Override public void onDiscoveryStarted(String type) { }
            @Override public void onDiscoveryStopped(String type) { }
            @Override public void onServiceLost(NsdServiceInfo info) { }
            @Override public void onStopDiscoveryFailed(String type, int error) { }
        };

        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discovery);
        try {
            long until = android.os.SystemClock.elapsedRealtime() + timeoutMs;
            long left;
            while ((left = until - android.os.SystemClock.elapsedRealtime()) > 0 && !stop.getAsBoolean()) {
                if (done.await(Math.min(left, 500), TimeUnit.MILLISECONDS)) break;
            }
        } finally {
            try {
                nsd.stopServiceDiscovery(discovery);
            } catch (IllegalArgumentException ignored) {
                // a descoberta não chegou a começar
            }
        }
        return result.get();
    }
}
