package dev.marcofilho.fileshare;

import java.io.IOException;

/** Arquivo chegando do Mac, em pedaços: um arquivo comum (IncomingDownload) ou uma pasta (IncomingFolder). */
interface Incoming {
    String name();

    long size();

    long received();

    default boolean isComplete() {
        return received() == size();
    }

    void append(byte[] data) throws IOException;

    /** Identificador do SEND (2.6+), ou null para um FILE: com ele, continua de onde parou. */
    String transferId();

    /** Quando o FILE chegou (relógio do aparelho), para medir a velocidade. */
    long startedAt();

    /** Conexão caiu, foi recusado ou cancelado: apaga o que chegou. */
    void discard();
}
