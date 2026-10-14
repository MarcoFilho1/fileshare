package dev.marcofilho.fileshare;

import android.content.ClipData;
import android.content.Context;
import android.net.Uri;
import android.text.Html;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/** Extrai texto ou imagem de um ClipData, incluindo o formato HTML que o Samsung Notes usa. */
final class ClipReader {
    record Payload(String mime, byte[] data, String description) {
    }

    private ClipReader() {
    }

    /** Retorna null se não houver nada a enviar (vazio ou conteúdo que veio do próprio Mac). */
    static Payload read(Context ctx, ClipData clip) throws Exception {
        if (clip == null || clip.getItemCount() == 0) return null;
        if (ReceiverService.CLIP_LABEL.contentEquals(String.valueOf(clip.getDescription().getLabel()))) return null;

        ClipData.Item item = clip.getItemAt(0);
        Uri uri = item.getUri();
        if (uri != null) {
            String type = ctx.getContentResolver().getType(uri);
            return new Payload(type != null ? type : "image/*", readAll(ctx, uri), "imagem");
        }
        String html = item.getHtmlText();
        CharSequence text = item.getText();
        if (html != null) {
            Uri img = HtmlImage.firstImage(html);
            if (img != null) return new Payload("image/*", readImage(ctx, img), "imagem");
            if (text == null || text.length() == 0) text = Html.fromHtml(html, Html.FROM_HTML_MODE_COMPACT).toString().trim();
        }
        if (text == null) text = item.coerceToText(ctx);
        if (text == null || text.length() == 0) return null;
        return new Payload("text/plain", text.toString().getBytes(StandardCharsets.UTF_8), "texto");
    }

    private static byte[] readImage(Context ctx, Uri img) throws Exception {
        if ("data".equals(img.getScheme())) return HtmlImage.decodeDataUri(img.toString());
        try {
            return readAll(ctx, img);
        } catch (Exception e) {
            // Samsung Notes usa "userId@autoridade"; tenta de novo sem o prefixo.
            String auth = img.getEncodedAuthority();
            if (auth == null || !auth.contains("@")) throw e;
            Log.w(ReceiverService.TAG, "retry without user prefix: " + e);
            return readAll(ctx, img.buildUpon().encodedAuthority(auth.substring(auth.indexOf('@') + 1)).build());
        }
    }

    private static byte[] readAll(Context ctx, Uri uri) throws Exception {
        try (InputStream in = ctx.getContentResolver().openInputStream(uri)) {
            if (in == null) throw new java.io.FileNotFoundException(String.valueOf(uri));
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            byte[] b = new byte[65536];
            int r;
            while ((r = in.read(b)) != -1) buf.write(b, 0, r);
            return buf.toByteArray();
        }
    }
}
