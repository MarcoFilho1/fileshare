package dev.marcofilho.fileshare;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.net.Uri;
import android.provider.MediaStore;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * Pasta vinda do Mac (compactada em zip): os pedaços vão para um arquivo no cache do app e, no
 * fim, ela é desfeita em Download/FileShare/<nome>/, com as subpastas.
 */
final class IncomingFolder implements Incoming {
    /** Contra zips maliciosos que se expandem demais. */
    static final long MIN_EXPANSION_ALLOWED = 1024L * 1024 * 1024;
    static final int MAX_ENTRIES = 10_000;

    private final Context ctx;
    private final String name;
    private final long size;
    private final File zip;
    private OutputStream out;
    private long received;

    IncomingFolder(Context ctx, String rawName, long size, String transferId) throws IOException {
        this.transferId = transferId;
        if (size > Wire.MAX_FILE_SIZE) throw new IOException("pasta grande demais");
        // o zip e os arquivos desfeitos ficam ao mesmo tempo no tablet
        if (!Wire.hasRoom(2 * size, IncomingDownload.freeSpace())) throw new IOException("não há espaço no tablet para " + FileSender.readable(size));
        this.ctx = ctx.getApplicationContext();
        this.name = IncomingDownload.safeName(rawName);
        this.size = size;
        zip = File.createTempFile("folder", ".zip", ctx.getCacheDir());
        out = new FileOutputStream(zip);
    }

    @Override
    public String name() {
        return name;
    }

    @Override
    public long size() {
        return size;
    }

    private final long startedAt = android.os.SystemClock.elapsedRealtime();
    private final String transferId;

    @Override
    public String transferId() {
        return transferId;
    }

    @Override
    public long startedAt() {
        return startedAt;
    }

    @Override
    public long received() {
        return received;
    }

    @Override
    public void append(byte[] data) throws IOException {
        if (received + data.length > size) {
            discard();
            throw new IOException("chegou mais do que o anunciado");
        }
        out.write(data);
        received += data.length;
    }

    /** Pasta desfeita: onde ficou (nome livre em Download/FileShare) e quantos arquivos. */
    record Result(String folder, int files) {
    }

    Result finish() throws IOException {
        out.close();
        out = null;
        String folder = freeName(name);
        int count = 0;
        long expanded = 0;
        // contra zips maliciosos: no máximo 20× o zip (pelo menos 1 GB), e nunca além do espaço livre
        long maxExpanded = Math.min(Math.max(20 * size, MIN_EXPANSION_ALLOWED), IncomingDownload.freeSpace() - Wire.SPARE_SPACE);
        ContentResolver resolver = ctx.getContentResolver();
        try (ZipInputStream in = new ZipInputStream(new FileInputStream(zip), StandardCharsets.UTF_8)) {
            ZipEntry entry;
            byte[] buf = new byte[1 << 16];
            while ((entry = in.getNextEntry()) != null) {
                if (entry.isDirectory()) continue;
                List<String> path = safePath(entry.getName());
                if (path == null) continue; // oculto (.DS_Store) ou tentando sair da pasta
                if (++count > MAX_ENTRIES) throw new IOException("arquivos demais na pasta");
                String fileName = path.remove(path.size() - 1);
                StringBuilder dir = new StringBuilder(IncomingDownload.FOLDER).append('/').append(folder);
                for (String p : path) dir.append('/').append(p);
                ContentValues values = new ContentValues();
                values.put(MediaStore.Downloads.DISPLAY_NAME, fileName);
                values.put(MediaStore.Downloads.MIME_TYPE, mimeOf(fileName));
                values.put(MediaStore.Downloads.RELATIVE_PATH, dir.toString());
                values.put(MediaStore.Downloads.IS_PENDING, 1);
                Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
                if (uri == null) throw new IOException("não consegui criar " + fileName);
                try (OutputStream o = resolver.openOutputStream(uri)) {
                    if (o == null) throw new IOException("não consegui abrir " + fileName);
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        expanded += n;
                        if (expanded > maxExpanded) throw new IOException("a pasta descompactada não cabe no tablet");
                        o.write(buf, 0, n);
                    }
                } catch (IOException e) {
                    resolver.delete(uri, null, null);
                    throw e;
                }
                ContentValues done = new ContentValues();
                done.put(MediaStore.Downloads.IS_PENDING, 0);
                resolver.update(uri, done, null, null);
            }
        } finally {
            zip.delete();
        }
        return new Result(folder, count);
    }

    @Override
    public void discard() {
        try {
            if (out != null) out.close();
        } catch (IOException ignored) {
        }
        out = null;
        zip.delete();
    }

    /**
     * Caminho de uma entrada do zip, já em pedaços e com os acentos normalizados (o macOS guarda o
     * acento separado da letra). null para entradas ocultas ou que tentem sair da pasta (../, /etc…).
     */
    static List<String> safePath(String raw) {
        String nfc = Normalizer.normalize(raw.replace('\\', '/'), Normalizer.Form.NFC);
        if (nfc.startsWith("/")) return null;
        List<String> parts = new ArrayList<>();
        for (String p : nfc.split("/")) {
            if (p.isEmpty()) continue;
            if (p.equals("..") || p.equals(".") || p.startsWith(".") || p.equals("__MACOSX")) return null;
            String clean = p.replaceAll("[\\p{Cntrl}:]", "").trim();
            if (clean.isEmpty()) return null;
            parts.add(clean);
        }
        return parts.isEmpty() ? null : parts;
    }

    /** "Aulas", ou "Aulas (2)" se já existe uma pasta Aulas deste app em Download/FileShare. */
    private String freeName(String base) {
        for (int i = 1; i < 1000; i++) {
            String candidate = i == 1 ? base : base + " (" + i + ")";
            String like = IncomingDownload.FOLDER + "/" + candidate + "/%";
            try (android.database.Cursor c = ctx.getContentResolver().query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    new String[]{MediaStore.Downloads._ID}, MediaStore.Downloads.RELATIVE_PATH + " LIKE ?", new String[]{like}, null)) {
                if (c == null || !c.moveToFirst()) return candidate;
            }
        }
        return base + " " + System.currentTimeMillis();
    }

    private static String mimeOf(String fileName) {
        int dot = fileName.lastIndexOf('.');
        String type = dot < 0 ? null : MimeTypeMap.getSingleton().getMimeTypeFromExtension(fileName.substring(dot + 1).toLowerCase(java.util.Locale.ROOT));
        return type != null ? type : "application/octet-stream";
    }
}
