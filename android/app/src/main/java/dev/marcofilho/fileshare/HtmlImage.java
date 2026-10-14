package dev.marcofilho.fileshare;

import android.net.Uri;
import android.util.Base64;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Acha a primeira imagem (<img src>) num trecho HTML copiado. */
final class HtmlImage {
    private static final Pattern IMG_SRC =
            Pattern.compile("<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']", Pattern.CASE_INSENSITIVE);

    private HtmlImage() {
    }

    static Uri firstImage(String html) {
        Matcher m = IMG_SRC.matcher(html);
        return m.find() ? Uri.parse(m.group(1)) : null;
    }

    static byte[] decodeDataUri(String src) {
        return Base64.decode(src.substring(src.indexOf(',') + 1), Base64.DEFAULT);
    }
}
