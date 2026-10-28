package dev.marcofilho.fileshare;

import java.io.IOException;
import java.util.Arrays;
import java.util.Locale;
import java.util.Set;
import java.util.zip.DataFormatException;
import java.util.zip.Deflater;
import java.util.zip.Inflater;

/**
 * Compressão dos pedaços de arquivo durante a viagem (PARZ, 2.6+), igual ao PartCompression.swift:
 * invisível para o usuário — quem recebe descomprime antes de gravar e o arquivo chega idêntico.
 * DEFLATE cru (RFC 1951), o mesmo do zip.
 */
final class PartCompression {
    /** Só vale mandar comprimido se encolher pelo menos 10%. */
    static final double MINIMUM_GAIN = 0.10;
    /** Depois de tantos pedaços seguidos sem ganho, o resto do arquivo vai direto. */
    static final int GIVE_UP_AFTER = 4;

    private static final Set<String> ALREADY_COMPRESSED = Set.of(
            "mp4", "mov", "m4v", "mkv", "avi", "webm", "3gp",
            "jpg", "jpeg", "heic", "heif", "png", "gif", "webp", "avif",
            "mp3", "m4a", "aac", "ogg", "opus", "flac",
            "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst",
            "apk", "dmg", "ipa", "pkg", "jar", "docx", "xlsx", "pptx", "epub");

    private PartCompression() {
    }

    /** Vale tentar comprimir este arquivo? Tipos que já vêm comprimidos nem tentam. */
    static boolean worthTrying(String name, String mime) {
        if (Wire.FOLDER_MIME.equals(mime) || mime.startsWith("video/") || mime.startsWith("audio/")) return false;
        if (mime.startsWith("image/") && !Set.of("image/bmp", "image/tiff", "image/x-ms-bmp", "image/svg+xml").contains(mime)) return false;
        int dot = name.lastIndexOf('.');
        String ext = dot < 0 ? "" : name.substring(dot + 1).toLowerCase(Locale.ROOT);
        return !ALREADY_COMPRESSED.contains(ext);
    }

    /** Os primeiros `length` bytes de `data` comprimidos, ou null se não encolheram pelo menos 10%. */
    static byte[] compress(byte[] data, int length) {
        if (length <= 0) return null;
        int limit = (int) (length * (1 - MINIMUM_GAIN));
        Deflater deflater = new Deflater(Deflater.BEST_SPEED, true);
        try {
            deflater.setInput(data, 0, length);
            deflater.finish();
            byte[] out = new byte[limit];
            int n = 0;
            while (!deflater.finished()) {
                if (n == limit) return null; // não coube: não encolheu o bastante
                n += deflater.deflate(out, n, limit - n);
            }
            return Arrays.copyOf(out, n);
        } finally {
            deflater.end();
        }
    }

    /** Descomprime um pedaço, recusando o que passar de maxSize (proteção contra "bombas"). */
    static byte[] decompress(byte[] data, int maxSize) throws IOException {
        if (data.length == 0) throw new IOException("pedaço comprimido vazio");
        Inflater inflater = new Inflater(true);
        try {
            inflater.setInput(data);
            byte[] out = new byte[maxSize + 1];
            int n = 0;
            while (!inflater.finished()) {
                if (n > maxSize) throw new IOException("pedaço comprimido grande demais");
                int got = inflater.inflate(out, n, out.length - n);
                if (got == 0 && (inflater.needsInput() || inflater.needsDictionary())) throw new IOException("pedaço comprimido inválido");
                n += got;
            }
            if (n > maxSize) throw new IOException("pedaço comprimido grande demais");
            return Arrays.copyOf(out, n);
        } catch (DataFormatException e) {
            throw new IOException("pedaço comprimido inválido", e);
        } finally {
            inflater.end();
        }
    }
}
