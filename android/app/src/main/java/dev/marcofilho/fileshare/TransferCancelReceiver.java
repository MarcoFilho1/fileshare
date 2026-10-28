package dev.marcofilho.fileshare;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Botões Cancelar das notificações "Enviando ao Mac" e "Recebendo do Mac". */
public final class TransferCancelReceiver extends BroadcastReceiver {
    static final String SEND = "send";
    static final String RECEIVE = "receive";
    private static final String EXTRA = "what";

    static PendingIntent intent(Context ctx, String what) {
        Intent i = new Intent(ctx, TransferCancelReceiver.class).putExtra(EXTRA, what);
        return PendingIntent.getBroadcast(ctx, what.hashCode(), i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    @Override
    public void onReceive(Context ctx, Intent intent) {
        if (SEND.equals(intent.getStringExtra(EXTRA))) {
            FileSender.cancelCurrent();
        } else {
            MacLink link = MacLink.current;
            if (link != null) link.cancelReceiving();
        }
    }
}
