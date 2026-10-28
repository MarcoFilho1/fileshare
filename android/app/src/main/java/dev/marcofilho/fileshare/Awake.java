package dev.marcofilho.fileshare;

import android.content.Context;
import android.net.wifi.WifiManager;
import android.os.PowerManager;

/**
 * Mantém o processador e o Wi-Fi acordados enquanto um arquivo vai ou vem, para o tablet não
 * dormir no meio de um envio grande. Conta quem pediu: solta quando o último termina.
 */
final class Awake {
    private static PowerManager.WakeLock cpu;
    private static WifiManager.WifiLock wifi;
    private static int holders;

    private Awake() {
    }

    @SuppressWarnings("deprecation") // WIFI_MODE_FULL_HIGH_PERF: o modo novo só vale com a tela ligada
    static synchronized void acquire(Context ctx) {
        if (holders++ > 0) return;
        Context app = ctx.getApplicationContext();
        if (cpu == null) {
            cpu = app.getSystemService(PowerManager.class).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "FileShare:transfer");
            cpu.setReferenceCounted(false);
            wifi = app.getSystemService(WifiManager.class).createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "FileShare:transfer");
            wifi.setReferenceCounted(false);
        }
        cpu.acquire(60 * 60_000L); // nunca mais que 1 h, mesmo se algo esquecer de soltar
        wifi.acquire();
    }

    static synchronized void release() {
        if (holders == 0 || --holders > 0) return;
        if (cpu != null && cpu.isHeld()) cpu.release();
        if (wifi != null && wifi.isHeld()) wifi.release();
    }
}
