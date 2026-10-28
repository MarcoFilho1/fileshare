package dev.marcofilho.fileshare;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Compartilhar → Abrir no Mac: abre no navegador do Mac o link compartilhado (de um navegador,
 * do YouTube…). Não tem tela; acha o primeiro endereço http(s) no texto, que muitas vezes vem
 * junto do título da página.
 */
public class OpenOnMacActivity extends Activity {
    private static final Pattern URL = Pattern.compile("https?://\\S+", Pattern.CASE_INSENSITIVE);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        CharSequence text = getIntent().getCharSequenceExtra(Intent.EXTRA_TEXT);
        String url = text == null ? null : firstLink(text.toString());
        if (url == null) {
            MacSender.toast(this, "Não achei um link para abrir no Mac");
        } else {
            if (MacLink.current == null) startForegroundService(new Intent(this, BridgeService.class));
            MacSender.openOnMac(this, url);
        }
        finish();
    }

    /** Primeiro link http(s) do texto, sem a pontuação que costuma grudar no fim. */
    static String firstLink(String text) {
        Matcher m = URL.matcher(text);
        if (!m.find()) return null;
        return m.group().replaceAll("[)\\].,;:!?'\"»>]+$", "");
    }
}
