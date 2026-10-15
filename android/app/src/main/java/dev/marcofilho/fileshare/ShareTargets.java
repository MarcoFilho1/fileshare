package dev.marcofilho.fileshare;

import android.content.Context;
import android.content.Intent;
import android.content.pm.ShortcutInfo;
import android.content.pm.ShortcutManager;
import android.graphics.drawable.Icon;
import android.util.Log;

import java.util.Set;

/**
 * Atalho de compartilhamento direto: o Mac pareado aparece pelo nome, com ícone de notebook, na
 * fileira de cima do menu Compartilhar (casa com o share-target de res/xml/shortcuts.xml).
 */
final class ShareTargets {
    static final String CATEGORY = "dev.marcofilho.fileshare.category.MAC";
    private static final String ID = "mac";

    private ShareTargets() {
    }

    static void update(Context ctx) {
        ShortcutManager sm = ctx.getSystemService(ShortcutManager.class);
        PairingStore.Pairing pairing = PairingStore.load(ctx);
        try {
            if (pairing == null) {
                sm.removeLongLivedShortcuts(java.util.List.of(ID));
                sm.removeDynamicShortcuts(java.util.List.of(ID));
                return;
            }
            ShortcutInfo shortcut = new ShortcutInfo.Builder(ctx, ID)
                    .setShortLabel(pairing.macName())
                    .setLongLabel("Enviar ao " + pairing.macName())
                    .setIcon(Icon.createWithResource(ctx, R.drawable.ic_mac))
                    .setIntent(new Intent(Intent.ACTION_DEFAULT, null, ctx, MainActivity.class))
                    .setCategories(Set.of(CATEGORY))
                    .setLongLived(true)
                    .build();
            sm.pushDynamicShortcut(shortcut);
        } catch (Exception e) {
            Log.w(BridgeService.TAG, "could not publish share shortcut: " + e);
        }
    }
}
