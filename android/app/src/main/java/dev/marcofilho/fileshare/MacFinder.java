package dev.marcofilho.fileshare;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.util.Log;

import java.net.InetAddress;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Procura o Mac na rede local pelo serviço Bonjour/NSD "_fileshare._tcp". */
final class MacFinder {
    static final String SERVICE_TYPE = "_fileshare._tcp.";

    record Found(String name, InetAddress host, int port) {
    }

    private MacFinder() {
    }

    /** Bloqueia até achar um Mac ou estourar o tempo; retorna null se não achou. */
    @SuppressWarnings("deprecation") // resolveService: a alternativa só existe a partir do Android 14
    static Found find(Context ctx, long timeoutMs) throws InterruptedException {
        NsdManager nsd = ctx.getSystemService(NsdManager.class);
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<Found> result = new AtomicReference<>();

        NsdManager.DiscoveryListener discovery = new NsdManager.DiscoveryListener() {
            private boolean resolving;

            @Override
            public void onServiceFound(NsdServiceInfo info) {
                synchronized (this) {
                    if (resolving) return;
                    resolving = true;
                }
                nsd.resolveService(info, new NsdManager.ResolveListener() {
                    @Override
                    public void onServiceResolved(NsdServiceInfo r) {
                        result.set(new Found(r.getServiceName(), r.getHost(), r.getPort()));
                        done.countDown();
                    }

                    @Override
                    public void onResolveFailed(NsdServiceInfo r, int error) {
                        Log.w(BridgeService.TAG, "resolve failed: " + error);
                        synchronized (this) {
                            resolving = false;
                        }
                    }
                });
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
            done.await(timeoutMs, TimeUnit.MILLISECONDS);
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
