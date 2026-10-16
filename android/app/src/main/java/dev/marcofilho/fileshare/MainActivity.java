package dev.marcofilho.fileshare;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.StatusBarManager;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.drawable.Icon;
import android.net.Uri;
import android.os.Bundle;
import android.os.PowerManager;
import android.provider.DocumentsContract;
import android.provider.Settings;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Tela inicial: o Mac pareado com o estado da conexão ao vivo, o que falta configurar (cada item
 * com um botão que leva direto ao lugar certo) e como usar.
 */
public class MainActivity extends Activity {
    private static final String PREFS = "ui";
    /** Largura máxima do conteúdo no tablet deitado, para as linhas não ficarem compridas demais. */
    private static final int MAX_WIDTH_DP = 640;

    private TextView macName;
    private TextView status;
    private View statusDot;
    private View macIconBg;
    private View pairSteps;
    private View forget;
    private Row notifRow, batteryRow, tileRow;
    private TextView a11yState;
    private TextView a11yButton;
    private View a11yCheck;
    private View a11yIconBg;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_main);
        macName = findViewById(R.id.mac_name);
        status = findViewById(R.id.status);
        statusDot = findViewById(R.id.status_dot);
        macIconBg = findViewById(R.id.mac_icon_bg);
        pairSteps = findViewById(R.id.pair_steps);
        forget = findViewById(R.id.forget);
        forget.setOnClickListener(v -> confirmForget());
        ((TextView) findViewById(R.id.footer)).setText(getString(R.string.footer, versionName()));
        fitContent();

        ViewGroup setup = findViewById(R.id.setup);
        notifRow = new Row(setup, R.drawable.ic_bell, R.color.icon_bell, R.string.notif_title);
        batteryRow = new Row(setup, R.drawable.ic_battery, R.color.icon_battery, R.string.battery_title);
        tileRow = new Row(setup, R.drawable.ic_toggle, R.color.icon_tile, R.string.tile_title);
        a11yState = findViewById(R.id.a11y_state);
        a11yButton = findViewById(R.id.a11y_button);
        a11yCheck = findViewById(R.id.a11y_check);
        a11yIconBg = findViewById(R.id.a11y_icon_bg);
        notifRow.action(R.string.action_allow, v -> askNotifications());
        batteryRow.action(R.string.action_allow, v -> askBattery());
        tileRow.action(R.string.action_add, v -> addTile());

        ViewGroup howto = findViewById(R.id.howto);
        new Row(howto, R.drawable.ic_copy, R.color.icon_copy, R.string.howto_paste_title).subtitle(R.string.howto_paste_text);
        new Row(howto, R.drawable.ic_share, R.color.icon_share, R.string.howto_share_title).subtitle(R.string.howto_share_text);
        new Row(howto, R.drawable.ic_folder, R.color.icon_folder, R.string.howto_folder_title).subtitle(R.string.howto_folder_text)
                .softAction(R.string.action_open, v -> openReceivedFolder());

        startForegroundService(new Intent(this, BridgeService.class));
    }

    @Override
    protected void onResume() {
        super.onResume();
        // volta dos Ajustes: confere de novo o que foi ativado
        refresh();
        BridgeService.statusListener = this::refreshStatus;
    }

    @Override
    protected void onPause() {
        BridgeService.statusListener = null;
        super.onPause();
    }

    private void refresh() {
        refreshStatus();
        refreshAccessibility();
        notifRow.state(checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED,
                R.string.notif_on, R.string.notif_off);
        batteryRow.state(getSystemService(PowerManager.class).isIgnoringBatteryOptimizations(getPackageName()),
                R.string.battery_on, R.string.battery_off);
        tileRow.state(getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(SendTileService.PREF_ADDED, false),
                R.string.tile_on, R.string.tile_off);
    }

    private void refreshStatus() {
        PairingStore.Pairing pairing = PairingStore.load(this);
        MacLink link = MacLink.current;
        boolean connected = pairing != null && link != null && link.isConnected();
        int color = getColor(connected ? R.color.ok : pairing == null ? R.color.off : R.color.warn);
        macName.setText(pairing != null ? pairing.macName() : getString(R.string.unpaired_title));
        status.setText(pairing == null ? getString(R.string.unpaired_subtitle)
                : connected ? getString(R.string.status_connected) : getString(R.string.status_searching));
        statusDot.setBackgroundTintList(ColorStateList.valueOf(color));
        macIconBg.setBackgroundTintList(ColorStateList.valueOf(getColor(pairing != null ? R.color.brand : R.color.off)));
        pairSteps.setVisibility(pairing == null ? View.VISIBLE : View.GONE);
        forget.setVisibility(pairing != null ? View.VISIBLE : View.GONE);
    }

    /** Cartão da acessibilidade: permitida (✓ e Revogar) ou não (Ativar em destaque). */
    private void refreshAccessibility() {
        boolean on = isAccessibilityOn();
        a11yState.setText(on ? R.string.a11y_on : R.string.a11y_off);
        a11yState.setTextColor(getColor(on ? R.color.ok : R.color.warn));
        a11yCheck.setVisibility(on ? View.VISIBLE : View.GONE);
        a11yIconBg.setBackgroundTintList(ColorStateList.valueOf(getColor(on ? R.color.icon_copy : R.color.off)));
        a11yButton.setText(on ? R.string.action_revoke : R.string.action_turn_on);
        a11yButton.setBackgroundResource(on ? R.drawable.bg_pill_soft : R.drawable.bg_pill);
        a11yButton.setTextColor(on ? getColor(R.color.brand) : 0xFFFFFFFF);
        a11yButton.setOnClickListener(v -> {
            if (on) confirmRevoke();
            else guideAccessibility();
        });
    }

    /**
     * O One UI ignora o atalho direto para a tela do serviço e abre a lista geral: antes de ir para
     * os Ajustes, mostra o caminho.
     */
    private void guideAccessibility() {
        new AlertDialog.Builder(this)
                .setTitle(R.string.enable_title)
                .setMessage(R.string.enable_steps)
                .setNegativeButton(R.string.cancel, null)
                .setPositiveButton(R.string.open_settings, (d, w) -> openAccessibility())
                .show();
    }

    private void confirmRevoke() {
        new AlertDialog.Builder(this)
                .setTitle(R.string.revoke_title)
                .setMessage(R.string.revoke_text)
                .setNegativeButton(R.string.cancel, null)
                .setPositiveButton(R.string.action_revoke, (d, w) -> {
                    CopyWatchService service = CopyWatchService.running;
                    if (service != null) {
                        service.disableSelf(); // o próprio serviço se desliga: nada a fazer nos Ajustes
                        CopyWatchService.running = null;
                        // o sistema grava a mudança um instante depois
                        a11yButton.postDelayed(this::refreshAccessibility, 400);
                    } else {
                        openAccessibility();
                    }
                })
                .show();
    }

    // MARK: ações

    private boolean isAccessibilityOn() {
        String enabled = Settings.Secure.getString(getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        ComponentName me = new ComponentName(this, CopyWatchService.class);
        return enabled != null && (enabled.contains(me.flattenToString()) || enabled.contains(me.flattenToShortString()));
    }

    private void openAccessibility() {
        // direto na tela do FileShare quando o sistema permite (ação não pública, mas existente desde o
        // Android 11); senão, a lista de Acessibilidade
        Intent details = new Intent("android.settings.ACCESSIBILITY_DETAILS_SETTINGS")
                .putExtra(Intent.EXTRA_COMPONENT_NAME, new ComponentName(this, CopyWatchService.class).flattenToString());
        try {
            startActivity(details);
        } catch (Exception e) {
            startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));
        }
    }

    private void askNotifications() {
        if (shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
                || !getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean("askedNotifications", false)) {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean("askedNotifications", true).apply();
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        } else {
            // o Android não pergunta de novo depois de duas recusas: abre os ajustes do app
            startActivity(new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName()));
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        refresh();
    }

    private void askBattery() {
        try {
            startActivity(new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + getPackageName())));
        } catch (Exception e) {
            startActivity(new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
        }
    }

    private void addTile() {
        getSystemService(StatusBarManager.class).requestAddTileService(
                new ComponentName(this, SendTileService.class), getString(R.string.send_to_mac),
                Icon.createWithResource(this, R.drawable.ic_stat_fileshare), getMainExecutor(), result -> {
                    if (result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED
                            || result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED) {
                        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(SendTileService.PREF_ADDED, true).apply();
                    }
                    refresh();
                });
    }

    private void openReceivedFolder() {
        Uri folder = DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:" + IncomingDownload.FOLDER);
        Intent open = new Intent(Intent.ACTION_VIEW).setDataAndType(folder, DocumentsContract.Document.MIME_TYPE_DIR)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            startActivity(open);
        } catch (Exception e) {
            try {
                startActivity(new Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS));
            } catch (Exception e2) {
                Toast.makeText(this, R.string.no_file_manager, Toast.LENGTH_SHORT).show();
            }
        }
    }

    private void confirmForget() {
        PairingStore.Pairing pairing = PairingStore.load(this);
        if (pairing == null) return;
        new AlertDialog.Builder(this)
                .setTitle(getString(R.string.forget_title, pairing.macName()))
                .setMessage(R.string.forget_text)
                .setNegativeButton(R.string.cancel, null)
                .setPositiveButton(R.string.forget_confirm, (d, w) -> {
                    PairingStore.clear(this);
                    ShareTargets.update(this);
                    MacLink link = MacLink.current;
                    if (link != null) link.repair();
                    refresh();
                })
                .show();
    }

    // MARK: layout

    /** Respeita as barras do sistema (a tela vai de ponta a ponta) e limita a largura no tablet. */
    private void fitContent() {
        View scroll = findViewById(R.id.scroll);
        View content = findViewById(R.id.content);
        scroll.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return WindowInsets.CONSUMED;
        });
        scroll.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
            int max = Math.round(MAX_WIDTH_DP * getResources().getDisplayMetrics().density) + content.getPaddingStart() + content.getPaddingEnd();
            int width = Math.min(r - l - v.getPaddingLeft() - v.getPaddingRight(), max);
            FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) content.getLayoutParams();
            if (lp.width != width) {
                lp.width = width;
                content.post(() -> content.setLayoutParams(lp));
            }
        });
    }

    private String versionName() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (PackageManager.NameNotFoundException e) {
            return "";
        }
    }

    /** Uma linha de cartão (row_item.xml), com divisória fina entre linhas. */
    private final class Row {
        final TextView subtitle;
        final TextView action;
        final ImageView done;

        Row(ViewGroup card, int icon, int color, int title) {
            if (card.getChildCount() > 0) {
                View divider = new View(MainActivity.this);
                divider.setBackgroundColor(getColor(R.color.divider));
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1);
                lp.setMarginStart(Math.round(78 * getResources().getDisplayMetrics().density));
                card.addView(divider, lp);
            }
            View row = LayoutInflater.from(MainActivity.this).inflate(R.layout.row_item, card, false);
            card.addView(row);
            row.findViewById(R.id.icon_bg).setBackgroundTintList(ColorStateList.valueOf(getColor(color)));
            ((ImageView) row.findViewById(R.id.icon)).setImageResource(icon);
            ((TextView) row.findViewById(R.id.title)).setText(title);
            subtitle = row.findViewById(R.id.subtitle);
            action = row.findViewById(R.id.action);
            done = row.findViewById(R.id.done);
        }

        Row subtitle(int text) {
            subtitle.setText(text);
            return this;
        }

        void action(int label, View.OnClickListener click) {
            action.setText(label);
            action.setOnClickListener(click);
        }

        void softAction(int label, View.OnClickListener click) {
            action(label, click);
            action.setBackgroundResource(R.drawable.bg_pill_soft);
            action.setTextColor(getColor(R.color.brand));
            action.setVisibility(View.VISIBLE);
        }

        void state(boolean on, int onText, int offText) {
            subtitle.setText(on ? onText : offText);
            action.setVisibility(on ? View.GONE : View.VISIBLE);
            done.setVisibility(on ? View.VISIBLE : View.GONE);
        }
    }
}
