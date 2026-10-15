package dev.marcofilho.fileshare;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;

/**
 * Destino do menu Compartilhar (e do atalho direto com o nome do Mac). Não tem tela: repassa os
 * arquivos ao BridgeService, que já mantém a conexão, e fecha na hora para o usuário voltar ao app
 * de onde compartilhou. Texto compartilhado (um link, por exemplo) vai para a área de transferência do Mac.
 */
public class ShareActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            handle(getIntent());
        } catch (Exception e) {
            Log.e(BridgeService.TAG, "share failed", e);
            MacSender.toast(this, "Não consegui enviar ao Mac");
        }
        finish();
    }

    private void handle(Intent intent) {
        ArrayList<Uri> uris = new ArrayList<>();
        if (Intent.ACTION_SEND_MULTIPLE.equals(intent.getAction())) {
            ArrayList<Uri> list = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri.class);
            if (list != null) uris.addAll(list);
        } else {
            Uri uri = intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri.class);
            if (uri != null) uris.add(uri);
        }

        if (uris.isEmpty()) {
            CharSequence text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT);
            if (text == null) {
                MacSender.toast(this, "Nada para enviar ao Mac");
                return;
            }
            byte[] data = text.toString().getBytes(StandardCharsets.UTF_8);
            MacSender.send(this, new ClipReader.Payload("text/plain", data, "texto"));
            return;
        }

        // A permissão de leitura veio para esta tela; o ClipData com a flag a estende ao serviço.
        ClipData clip = ClipData.newRawUri("FileShare", uris.get(0));
        for (int i = 1; i < uris.size(); i++) clip.addItem(new ClipData.Item(uris.get(i)));
        Intent forward = new Intent(this, BridgeService.class)
                .setAction(BridgeService.ACTION_SEND_FILES)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        forward.setClipData(clip);
        startForegroundService(forward);
    }
}
