package dev.marcofilho.fileshare;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/** Liga o serviço sozinho depois de reiniciar o tablet ou atualizar o app (se já estiver pareado). */
public class StartReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context ctx, Intent intent) {
        String action = intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action) && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) return;
        if (PairingStore.load(ctx) == null) return; // sem pareamento não há com quem conectar
        try {
            ctx.startForegroundService(new Intent(ctx, BridgeService.class));
            Log.i(BridgeService.TAG, "service started after " + action);
        } catch (Exception e) {
            Log.e(BridgeService.TAG, "could not start service after " + action, e);
        }
    }
}
