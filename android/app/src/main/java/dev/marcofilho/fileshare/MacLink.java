package dev.marcofilho.fileshare;

import android.content.Context;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.LongConsumer;

/**
 * Conexão permanente e criptografada com o Mac pareado: acha o Mac por NSD, autentica com a chave
 * do pareamento (AUTH + HELLO cifrado), manda PING a cada 20 s e reconecta sozinha (espera
 * crescente até 30 s) quando a conexão cai.
 */
final class MacLink {
    interface Listener {
        void onClip(String mime, byte[] data);

        /** Cópia que o Mac guardou enquanto o tablet estava fora, feita em copiedAt (ms). */
        void onHeld(String mime, byte[] data, long copiedAt);

        void onState(String state);

        /** Arquivo enviado pelo Mac, já salvo em Download/FileShare. */
        void onFile(android.net.Uri uri, String name, String mime, String macName);

        /** Pasta enviada pelo Mac, já desfeita em Download/FileShare/<folder>. */
        void onFolder(String folder, int files, String macName);

        /** Arquivo grande chegando do Mac: andamento para a notificação com Cancelar. */
        void onReceiving(String name, long received, long size);

        /** O arquivo grande que chegava terminou, foi recusado ou cancelado. */
        void onReceivingEnded();

        /** Conexão pronta (depois do HELLO): hora de mandar o que ficou guardado. Roda na thread da conexão. */
        void onConnected();
    }

    /** Recursos que o Mac pode anunciar no HELLO. */
    static final class Capability {
        /** Aceita HELD: a cópia que o tablet guardou enquanto o Mac estava longe. */
        static final String HELD = "held";
        /** Mostra a bateria do tablet (BATT) no painel. */
        static final String BATTERY = "batt";
        /** Abre no navegador do Mac os links de Compartilhar → Abrir no Mac (OPEN). */
        static final String OPEN = "open";
        /** Sem limite fixo de tamanho, só o espaço livre (antes, 100 MB). */
        static final String BIG_FILES = "big";
        /** Entende STOP: quem envia desistiu no meio. */
        static final String STOP = "stop";
        /** Desfaz pastas compactadas (Wire.FOLDER_MIME); só o tablet anuncia. */
        static final String FOLDERS = "folder";
        /** Entende SEND/FROM: arquivos continuam de onde pararam se a conexão cair. */
        static final String RESUME = "resume";
        /** Entende PARZ: pedaços comprimidos durante a viagem. */
        static final String COMPRESSED_PARTS = "zpart";

        private Capability() {
        }
    }

    private static final int PING_MS = 20_000;
    private static final int READ_TIMEOUT_MS = 60_000;
    private static final long MAX_BACKOFF_MS = 30_000;
    /**
     * Sem o Mac, o tablet fica escutando a rede quase o tempo todo (janelas de 45 s com 1 s de
     * pausa), para pegar o anúncio do Mac assim que ele volta. O Android espaça sozinho as
     * perguntas na rede, então escutar custa pouco.
     */
    private static final long FIND_MS = 45_000;
    private static final long UNPAIRED_WAIT_MS = 60_000;

    static volatile MacLink current;

    /** O Mac recusou o arquivo (FAIL), com o motivo dele. */
    static final class RefusedException extends IOException {
        RefusedException(String reason) {
            super(reason);
        }
    }

    private final Context ctx;
    private final Listener listener;
    private final AtomicInteger nextId = new AtomicInteger(1);
    /** Versão e recursos que o Mac anunciou no HELLO (vazio até a 2.3). */
    private volatile Wire.Peer macPeer = Wire.Peer.NONE;
    /** Pedido para recomeçar a busca agora (rede mudou, tela ligou). */
    private volatile boolean wakeRequested;
    /**
     * Arquivos que chegavam do Mac quando a conexão caiu, pelo transferId: continuam de onde
     * pararam quando ele mandar o SEND de novo. Só a thread da conexão mexe. Esquecidos em 24 h.
     */
    private final Map<String, Incoming> partials = new HashMap<>();
    private static final long PARTIAL_LIFETIME_MS = 24 * 60 * 60_000L;
    /** SEND mandado ao Mac, esperando o FROM com a posição para continuar. */
    private final Map<Integer, CompletableFuture<Long>> fromWaiters = new ConcurrentHashMap<>();
    /** Botão Cancelar da notificação "Recebendo do Mac": tratado no próximo pedaço que chegar. */
    private volatile boolean cancelIncoming;
    /** Arquivos menores que isto chegam rápido demais para valer uma notificação de andamento. */
    private static final long SHOW_PROGRESS_FROM = 4L * Wire.PART_SIZE;
    /** A última sessão chegou a conectar: a próxima tentativa começa rápida, mesmo se ela caiu com erro. */
    private volatile boolean connectedOnce;
    private final Map<Integer, CompletableFuture<Void>> pending = new ConcurrentHashMap<>();
    private final Object sleepLock = new Object();
    private volatile boolean running;
    private volatile Socket socket;
    private volatile OutputStream out;
    private volatile SecureChannel channel;
    private volatile boolean ready;
    private volatile long lastReceivedAt;
    private Thread loop;

    MacLink(Context ctx, Listener listener) {
        this.ctx = ctx.getApplicationContext();
        this.listener = listener;
    }

    void start() {
        if (running) return;
        running = true;
        current = this;
        loop = new Thread(this::run, "fileshare-link");
        loop.start();
    }

    void stop() {
        running = false;
        if (current == this) current = null;
        closeSocket();
        wake();
    }

    /** Rede mudou: tenta de novo agora em vez de esperar o fim da espera. */
    void wake() {
        wakeRequested = true;
        synchronized (sleepLock) {
            sleepLock.notifyAll();
        }
    }

    /** Pareamento novo: larga a conexão atual (chave antiga) e conecta de novo. */
    void repair() {
        closeSocket();
        wake();
    }

    /**
     * Tela ligou. Sem conexão: tenta agora. Com conexão, mas sem notícias do Mac há mais de um ciclo
     * de PING (o tablet dormiu e a rede foi cortada): ela provavelmente morreu, então refaz.
     */
    void onScreenOn() {
        if (ready && android.os.SystemClock.elapsedRealtime() - lastReceivedAt > PING_MS + 5_000) {
            Log.i(BridgeService.TAG, "stale connection after sleep; reconnecting");
            repair();
        } else if (!ready) {
            wake();
        }
    }

    boolean isConnected() {
        return ready;
    }

    /** O Mac desta conexão anunciou o recurso? Até a 2.3 ele não anuncia nenhum. */
    boolean macSupports(String capability) {
        return macPeer.supports(capability);
    }

    /** Envia ao Mac e espera a confirmação. */
    void send(String mime, byte[] data, long timeoutMs) throws Exception {
        sendAndWait(id -> Wire.Message.clip(id, mime, data), timeoutMs);
    }

    /** Pede ao Mac para abrir o link no navegador e espera a confirmação (ou o FAIL, com o motivo). */
    void sendOpen(String url, long timeoutMs) throws Exception {
        try {
            sendAndWait(id -> Wire.Message.open(id, url), timeoutMs);
        } catch (ExecutionException e) {
            throw e.getCause() instanceof Exception cause ? cause : e;
        }
    }

    /** Nível da bateria para o painel do Mac; sem confirmação, e só se ele anunciou Capability.BATTERY. */
    void sendBattery(int level, boolean charging) {
        if (!ready || !macSupports(Capability.BATTERY)) return;
        try {
            write(Wire.Message.battery(level, charging));
        } catch (IOException e) {
            Log.w(BridgeService.TAG, "battery not sent: " + e);
        }
    }

    /** Cópia guardada com o Mac longe, feita em copiedAt (ms); só para um Mac com Capability.HELD. */
    void sendHeld(String mime, byte[] data, long copiedAt, long timeoutMs) throws Exception {
        sendAndWait(id -> Wire.Message.held(id, copiedAt, mime, data), timeoutMs);
    }

    private void sendAndWait(java.util.function.IntFunction<Wire.Message> message, long timeoutMs) throws Exception {
        if (!ready) throw new IOException("Mac não conectado");
        int id = nextId.getAndIncrement();
        CompletableFuture<Void> ack = new CompletableFuture<>();
        pending.put(id, ack);
        try {
            write(message.apply(id));
            ack.get(timeoutMs, TimeUnit.MILLISECONDS);
        } finally {
            pending.remove(id);
        }
    }

    /**
     * Envia um arquivo do menu Compartilhar: FILE com nome e tamanho, depois o conteúdo em PARTs, e
     * espera o Mac confirmar que salvou. O arquivo nunca fica inteiro na memória.
     */
    /**
     * Com um Mac 2.6+ e um arquivo que dá para reler de qualquer ponto (FileInputStream), vai como
     * SEND com transferId: se a conexão cair, a próxima tentativa com o mesmo transferId continua de
     * onde o Mac parou.
     */
    /** Devolve quantos bytes do arquivo passaram pela rede (menos que o tamanho, se a compressão ajudou). */
    long sendFile(String name, String mime, long size, InputStream in, String transferId, LongConsumer progress,
                  java.util.function.BooleanSupplier cancelled, long timeoutMs) throws Exception {
        if (!ready) throw new IOException("Mac não conectado");
        int id = nextId.getAndIncrement();
        CompletableFuture<Void> ack = new CompletableFuture<>();
        pending.put(id, ack);
        Awake.acquire(ctx);
        try {
            long sent = 0;
            if (transferId != null && in instanceof java.io.FileInputStream file && macSupports(Capability.RESUME)) {
                CompletableFuture<Long> from = new CompletableFuture<>();
                fromWaiters.put(id, from);
                try {
                    write(Wire.Message.send(id, size, transferId, mime, name));
                    sent = from.get(timeoutMs, TimeUnit.MILLISECONDS);
                } finally {
                    fromWaiters.remove(id);
                }
                if (sent > size) throw new IOException("o Mac pediu uma posição inválida");
                file.getChannel().position(sent);
                if (sent > 0) Log.i(BridgeService.TAG, "Mac already had " + sent + " B; continuing");
                progress.accept(sent);
            } else {
                write(Wire.Message.file(id, size, mime, name));
            }
            byte[] buf = new byte[Wire.PART_SIZE];
            // compressão: liga se o Mac entende PARZ e o tipo não vem comprimido; desliga sozinha
            // depois de alguns pedaços seguidos sem ganho
            boolean squeeze = macSupports(Capability.COMPRESSED_PARTS) && PartCompression.worthTrying(name, mime);
            int misses = 0;
            long wireBytes = 0;
            while (sent < size && !ack.isDone()) { // o Mac pode recusar no meio do caminho
                if (cancelled.getAsBoolean()) {
                    // Mac 2.6+ apaga o que chegou ao receber STOP; um mais antigo, ao perder a conexão
                    if (macSupports(Capability.STOP)) write(Wire.Message.stop(id)); else repair();
                    throw new CancelledException();
                }
                int n = in.read(buf, 0, (int) Math.min(buf.length, size - sent));
                if (n < 0) throw new IOException("o arquivo acabou antes do tamanho informado");
                byte[] small = squeeze ? PartCompression.compress(buf, n) : null;
                if (small != null) {
                    write(Wire.Message.partZ(id, small));
                    wireBytes += small.length;
                    misses = 0;
                } else {
                    write(Wire.Message.part(id, Arrays.copyOf(buf, n)));
                    wireBytes += n;
                    if (squeeze && ++misses >= PartCompression.GIVE_UP_AFTER) squeeze = false;
                }
                sent += n;
                progress.accept(sent);
            }
            ack.get(timeoutMs, TimeUnit.MILLISECONDS);
            return wireBytes;
        } catch (ExecutionException e) {
            throw e.getCause() instanceof Exception cause ? cause : e;
        } finally {
            pending.remove(id);
            Awake.release();
        }
    }

    /** Você cancelou o envio no meio. */
    static final class CancelledException extends IOException {
        CancelledException() {
            super("cancelado");
        }
    }

    /** Cancelar da notificação de recebimento. */
    void cancelReceiving() {
        cancelIncoming = true;
    }

    private void run() {
        long backoff = 1000;
        while (running) {
            long wait;
            boolean found = false;
            PairingStore.Pairing pairing = PairingStore.load(ctx);
            if (pairing == null) {
                listener.onState("Não pareado: no Mac, use \"Parear tablet…\" e leia o QR");
                wait = UNPAIRED_WAIT_MS;
            } else {
                try {
                    listener.onState("Procurando o " + pairing.macName() + " no Wi-Fi…");
                    wakeRequested = false;
                    MacFinder.Found mac = MacFinder.find(ctx, pairing.macId(), FIND_MS, () -> wakeRequested || !running);
                    found = mac != null;
                    if (found) session(mac, pairing);
                    if (running) listener.onState(pairing.macName() + " não encontrado; tentando de novo");
                } catch (SecureChannel.DecryptException e) {
                    Log.w(BridgeService.TAG, "pairing key rejected");
                    listener.onState("O Mac não reconheceu este tablet: pareie de novo pelo QR");
                    backoff = MAX_BACKOFF_MS;
                } catch (InterruptedException e) {
                    return;
                } catch (Exception e) {
                    Log.w(BridgeService.TAG, "link error: " + e);
                    if (running) listener.onState(pairing.macName() + " não encontrado; tentando de novo");
                }
                if (connectedOnce) { // estava conectado: a próxima tentativa começa rápida
                    connectedOnce = false;
                    backoff = 1000;
                    wait = 1000;
                } else if (!found) {
                    wait = 1000; // a busca já esperou: volta a escutar logo
                } else { // achou o Mac, mas não conseguiu conectar: espera mais a cada vez
                    wait = backoff;
                    backoff = Math.min(backoff * 2, MAX_BACKOFF_MS);
                }
            }
            if (!running) return;
            synchronized (sleepLock) {
                try {
                    sleepLock.wait(wait);
                } catch (InterruptedException e) {
                    return;
                }
            }
        }
    }

    private void session(MacFinder.Found mac, PairingStore.Pairing pairing) throws Exception {
        Socket s = new Socket();
        Map<Integer, Incoming> incoming = new HashMap<>(); // arquivos do Mac chegando, pelo id
        Map<Integer, Integer> reported = new HashMap<>(); // último percentual avisado, pelo id
        try {
            s.connect(new InetSocketAddress(mac.host(), mac.port()), 5000);
            s.setSoTimeout(READ_TIMEOUT_MS);
            s.setKeepAlive(true);
            s.setTcpNoDelay(true);
            socket = s;
            out = new BufferedOutputStream(s.getOutputStream(), 1 << 16);
            DataInputStream in = new DataInputStream(new BufferedInputStream(s.getInputStream(), 1 << 16));

            // Handshake: troca de nonces em claro e prova mútua de que os dois têm a chave.
            byte[] tabletNonce = SecureChannel.randomBytes(16);
            write(Wire.Message.auth(tabletNonce));
            Wire.Message auth = Wire.decode(Wire.readFrame(in));
            if (auth.type != Wire.Type.AUTH) throw new IOException("expected AUTH");
            channel = new SecureChannel(pairing.key(), tabletNonce, auth.data);
            write(Wire.Message.hello(deviceName(), localPeer()));
            Wire.Message hello = Wire.decode(channel.open(Wire.readFrame(in)));
            if (hello.type != Wire.Type.HELLO) throw new IOException("expected HELLO");
            macPeer = hello.peer;
            Log.i(BridgeService.TAG, "Mac version " + (macPeer.version.isEmpty() ? "<= 2.3" : macPeer.version)
                    + ", capabilities " + macPeer.capabilities);
            ready = true;
            connectedOnce = true;
            lastReceivedAt = android.os.SystemClock.elapsedRealtime();
            Log.i(BridgeService.TAG, "connected (encrypted) to " + hello.text + " at " + mac.host() + ":" + mac.port());
            listener.onState("Conectado ao " + hello.text + " (criptografado)");
            listener.onConnected();

            Thread pinger = new Thread(() -> {
                try {
                    while (socket == s) {
                        Thread.sleep(PING_MS);
                        write(Wire.Message.ping());
                    }
                } catch (Exception ignored) {
                    // a sessão acabou
                }
            }, "fileshare-ping");
            pinger.start();

            while (running) {
                Wire.Message m = Wire.decode(channel.open(Wire.readFrame(in)));
                lastReceivedAt = android.os.SystemClock.elapsedRealtime();
                if (m.type == Wire.Type.PARZ) {
                    // pedaço comprimido: descomprime e segue como um PART comum
                    try {
                        m = Wire.Message.part(m.id, PartCompression.decompress(m.data, Wire.PART_SIZE));
                    } catch (IOException e) {
                        if (incoming.containsKey(m.id)) {
                            dropIncoming(m.id, incoming, reported);
                            write(Wire.Message.fail(m.id, e.getMessage()));
                        }
                        continue;
                    }
                }
                switch (m.type) {
                    case HELD:
                        listener.onHeld(m.text, m.data, m.copiedAt);
                        write(Wire.Message.ack(m.id));
                        break;
                    case CLIP:
                        listener.onClip(m.text, m.data);
                        write(Wire.Message.ack(m.id));
                        break;
                    case ACK: {
                        CompletableFuture<Void> f = pending.remove(m.id);
                        if (f != null) f.complete(null);
                        break;
                    }
                    case FAIL: {
                        CompletableFuture<Void> f = pending.remove(m.id);
                        if (f != null) f.completeExceptionally(new RefusedException(m.text));
                        break;
                    }
                    case PING:
                        write(Wire.Message.pong());
                        break;
                    case FILE:
                        try {
                            Incoming file = Wire.FOLDER_MIME.equals(m.text)
                                    ? new IncomingFolder(ctx, m.name, m.size, null)
                                    : new IncomingDownload(ctx, m.name, m.text, m.size, null);
                            incoming.put(m.id, file);
                            Awake.acquire(ctx);
                            if (file.isComplete()) finishDownload(m.id, incoming, hello.text);
                        } catch (IOException e) {
                            write(Wire.Message.fail(m.id, e.getMessage()));
                        }
                        break;
                    case PART: {
                        Incoming file = incoming.get(m.id);
                        if (file == null) break; // já recusado
                        if (cancelIncoming) {
                            cancelIncoming = false;
                            dropIncoming(m.id, incoming, reported);
                            write(Wire.Message.fail(m.id, "cancelado no tablet"));
                            break;
                        }
                        try {
                            file.append(m.data);
                            if (file.isComplete()) {
                                reported.remove(m.id);
                                finishDownload(m.id, incoming, hello.text);
                            } else if (file.size() >= SHOW_PROGRESS_FROM) {
                                int percent = (int) (file.received() * 100 / file.size());
                                Integer last = reported.put(m.id, percent);
                                if (last == null || last != percent) listener.onReceiving(file.name(), file.received(), file.size());
                            }
                        } catch (IOException e) {
                            dropIncoming(m.id, incoming, reported);
                            write(Wire.Message.fail(m.id, e.getMessage()));
                        }
                        break;
                    }
                    case SEND:
                        prunePartials();
                        try {
                            Incoming file = partials.get(m.transferId);
                            if (file != null && file.size() == m.size) {
                                Log.i(BridgeService.TAG, "continuing " + file.name() + " from " + file.received() + " B");
                            } else {
                                if (file != null) file.discard();
                                file = Wire.FOLDER_MIME.equals(m.text)
                                        ? new IncomingFolder(ctx, m.name, m.size, m.transferId)
                                        : new IncomingDownload(ctx, m.name, m.text, m.size, m.transferId);
                                partials.put(m.transferId, file);
                            }
                            incoming.put(m.id, file);
                            Awake.acquire(ctx);
                            write(Wire.Message.from(m.id, file.received()));
                            if (file.isComplete()) finishDownload(m.id, incoming, hello.text);
                        } catch (IOException e) {
                            write(Wire.Message.fail(m.id, e.getMessage()));
                        }
                        break;
                    case FROM: {
                        CompletableFuture<Long> f = fromWaiters.get(m.id);
                        if (f != null) f.complete(m.size);
                        break;
                    }
                    case STOP:
                        // o Mac cancelou o envio deste arquivo
                        if (incoming.containsKey(m.id)) {
                            Log.i(BridgeService.TAG, "Mac cancelled file " + m.id);
                            dropIncoming(m.id, incoming, reported);
                        }
                        break;
                    case UNKNOWN:
                        Log.i(BridgeService.TAG, "message " + m.text + " from a newer Mac; ignored");
                        break;
                    default:
                        break;
                }
            }
        } catch (IOException e) {
            // o Mac fecha a conexão sem responder ao HELLO quando a chave não confere
            if (!ready && channel != null && e instanceof EOFException) throw new SecureChannel.DecryptException();
            throw e;
        } finally {
            for (Map.Entry<Integer, Incoming> e : incoming.entrySet()) {
                // com transferId, o pedaço fica guardado para continuar quando o Mac voltar
                if (e.getValue().transferId() == null) e.getValue().discard();
                if (reported.containsKey(e.getKey())) listener.onReceivingEnded();
                Awake.release();
            }
            incoming.clear();
            cancelIncoming = false;
            for (CompletableFuture<Long> f : fromWaiters.values()) f.completeExceptionally(new IOException("conexão caiu"));
            closeSocket();
            for (CompletableFuture<Void> f : pending.values()) f.completeExceptionally(new IOException("conexão caiu"));
            pending.clear();
            Log.i(BridgeService.TAG, "disconnected");
        }
    }

    /** Tira o arquivo da lista de chegando, apaga o que chegou e solta o "acordado". */
    private void dropIncoming(int id, Map<Integer, Incoming> incoming, Map<Integer, Integer> reported) {
        Incoming file = incoming.remove(id);
        if (file == null) return;
        if (file.transferId() != null) partials.remove(file.transferId());
        file.discard();
        if (reported.remove(id) != null) listener.onReceivingEnded();
        Awake.release();
    }

    /** Esquece (e apaga) os pedaços guardados há mais de 24 h. */
    private void prunePartials() {
        long now = android.os.SystemClock.elapsedRealtime();
        partials.values().removeIf(f -> {
            if (now - f.startedAt() <= PARTIAL_LIFETIME_MS) return false;
            f.discard();
            return true;
        });
    }

    private void finishDownload(int id, Map<Integer, Incoming> incoming, String macName) throws IOException {
        Incoming file = incoming.remove(id);
        if (file.transferId() != null) partials.remove(file.transferId());
        try {
            if (file.size() >= SHOW_PROGRESS_FROM) listener.onReceivingEnded();
            if (file instanceof IncomingFolder folder) {
                IncomingFolder.Result r = folder.finish();
                write(Wire.Message.ack(id));
                Log.i(BridgeService.TAG, "folder from Mac saved: " + r.files() + " files, "
                        + Wire.speed(file.size(), file.startedAt(), android.os.SystemClock.elapsedRealtime()));
                listener.onFolder(r.folder(), r.files(), macName);
            } else {
                IncomingDownload download = (IncomingDownload) file;
                android.net.Uri uri = download.finish();
                write(Wire.Message.ack(id));
                Log.i(BridgeService.TAG, "file from Mac saved: " + download.mime + " "
                        + Wire.speed(download.size, download.startedAt(), android.os.SystemClock.elapsedRealtime()));
                listener.onFile(uri, download.name, download.mime, macName);
            }
        } catch (IOException e) {
            file.discard();
            write(Wire.Message.fail(id, "não consegui salvar no tablet (" + e.getMessage() + ")"));
        } finally {
            Awake.release();
        }
    }

    /** Cifra quando o canal já existe; só o AUTH vai em claro. */
    private synchronized void write(Wire.Message m) throws IOException {
        OutputStream o = out;
        if (o == null) throw new IOException("Mac não conectado");
        byte[] bytes = Wire.messageBytes(m);
        SecureChannel ch = channel;
        try {
            Wire.writeFrame(o, ch != null ? ch.seal(bytes) : bytes);
        } catch (java.security.GeneralSecurityException e) {
            throw new IOException(e);
        }
    }

    private void closeSocket() {
        ready = false;
        out = null;
        channel = null;
        Socket s = socket;
        socket = null;
        if (s != null) {
            try {
                s.close();
            } catch (IOException ignored) {
            }
        }
    }

    /** O que o tablet anuncia no HELLO. Cada recurso novo entra aqui quando estiver pronto. */
    private Wire.Peer localPeer() {
        String version = "dev";
        try {
            version = ctx.getPackageManager().getPackageInfo(ctx.getPackageName(), 0).versionName;
        } catch (android.content.pm.PackageManager.NameNotFoundException ignored) {
        }
        return new Wire.Peer(version, java.util.Set.of(Capability.BIG_FILES, Capability.STOP, Capability.FOLDERS, Capability.RESUME, Capability.COMPRESSED_PARTS));
    }

    private String deviceName() {
        String name = Settings.Global.getString(ctx.getContentResolver(), "device_name");
        return name != null && !name.isEmpty() ? name : Build.MODEL;
    }
}
