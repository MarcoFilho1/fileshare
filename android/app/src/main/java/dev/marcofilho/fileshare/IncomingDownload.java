package dev.marcofilho.fileshare;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.net.Uri;
import android.os.Environment;
import android.provider.MediaStore;

import java.io.IOException;
import java.io.OutputStream;

/**
 * Arquivo chegando do Mac: vai direto para Download/FileShare pelo MediaStore (sem permissão de
 * armazenamento), marcado como pendente até o último pedaço, para não aparecer pela metade.
 */
final class IncomingDownload {
    static final String FOLDER = Environment.DIRECTORY_DOWNLOADS + "/FileShare";

    final String name;
    final String mime;
    final long size;
    private final ContentResolver resolver;
    private final Uri uri;
    private OutputStream out;
    private long received;

    IncomingDownload(Context ctx, String rawName, String mime, long size) throws IOException {
        if (size > Wire.MAX_FILE_SIZE) throw new IOException("arquivo maior que 100 MB");
        this.name = safeName(rawName);
        this.mime = mime;
        this.size = size;
        resolver = ctx.getContentResolver();
        ContentValues values = new ContentValues();
        values.put(MediaStore.Downloads.DISPLAY_NAME, name);
        values.put(MediaStore.Downloads.MIME_TYPE, mime);
        values.put(MediaStore.Downloads.RELATIVE_PATH, FOLDER);
        values.put(MediaStore.Downloads.IS_PENDING, 1);
        uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
        if (uri == null) throw new IOException("não consegui criar o arquivo no tablet");
        out = resolver.openOutputStream(uri);
        if (out == null) {
            discard();
            throw new IOException("não consegui abrir o arquivo no tablet");
        }
    }

    boolean isComplete() {
        return received == size;
    }

    void append(byte[] data) throws IOException {
        if (received + data.length > size) {
            discard();
            throw new IOException("chegou mais do que o anunciado");
        }
        try {
            out.write(data);
        } catch (IOException e) {
            discard();
            throw new IOException("não consegui salvar no tablet (" + e.getMessage() + ")");
        }
        received += data.length;
    }

    /** Fecha e libera o arquivo para os outros apps; devolve o endereço para abrir. */
    Uri finish() throws IOException {
        out.close();
        out = null;
        ContentValues done = new ContentValues();
        done.put(MediaStore.Downloads.IS_PENDING, 0);
        resolver.update(uri, done, null, null);
        return uri;
    }

    /** Conexão caiu no meio ou o arquivo foi recusado: apaga o que chegou. */
    void discard() {
        try {
            if (out != null) out.close();
        } catch (IOException ignored) {
        }
        out = null;
        resolver.delete(uri, null, null);
    }

    /** O nome vem do Mac: sem barras, quebras de linha ou ponto no começo. */
    static String safeName(String raw) {
        String name = raw.replaceAll("[\\p{Cntrl}]", "").replace('/', '-').replace(':', '-').trim();
        while (name.startsWith(".")) name = name.substring(1);
        if (name.isEmpty()) name = "arquivo";
        return name.length() > 200 ? name.substring(name.length() - 200) : name;
    }
}
