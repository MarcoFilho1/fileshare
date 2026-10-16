package dev.marcofilho.fileshare;

import android.app.PendingIntent;
import android.content.Intent;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/** Botão "Enviar ao Mac" nas Configurações rápidas. */
public class SendTileService extends TileService {
    /** Guardado nas preferências "ui": a tela inicial mostra se o botão já está nas Configurações rápidas. */
    static final String PREF_ADDED = "tileAdded";

    @Override
    public void onTileAdded() {
        getSharedPreferences("ui", MODE_PRIVATE).edit().putBoolean(PREF_ADDED, true).apply();
    }

    @Override
    public void onTileRemoved() {
        getSharedPreferences("ui", MODE_PRIVATE).edit().putBoolean(PREF_ADDED, false).apply();
    }

    @Override
    public void onStartListening() {
        Tile t = getQsTile();
        if (t == null) return;
        t.setState(Tile.STATE_INACTIVE);
        t.setLabel(getString(R.string.send_to_mac));
        t.updateTile();
    }

    @Override
    public void onClick() {
        Intent i = new Intent(this, ReadClipActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent pi = PendingIntent.getActivity(this, 0, i,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        startActivityAndCollapse(pi);
    }
}
