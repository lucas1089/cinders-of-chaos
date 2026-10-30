package com.cindersofchaos.client;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Downloads the APK of the app update (O313 step 8, docs/ANDROID_CLIENT.md section 4) to a file: HTTP range resume of a
 * partial file, the exact size and the SHA-256 of the manifest checked, the file in place only when both match. No
 * Android classes, so client/android/tests/ApkFetcherTest.java runs it on a plain JVM against a local server.
 * Failures carry a short code that the first-start screen turns into text: net, size, hash, storage, aborted.
 */
final class ApkFetcher {
    interface Listener {
        void downloading(long done, long total);
        void verifying();
    }

    static final class Failure extends Exception {
        final String code;

        Failure(String code, String detail) {
            super(code + ": " + detail);
            this.code = code;
        }
    }

    static final int ATTEMPTS = 4;
    static final long SPACE_MARGIN = 16L * 1024 * 1024;
    static final int CONNECT_TIMEOUT_MS = 15000;
    static final int READ_TIMEOUT_MS = 20000;

    private ApkFetcher() {
    }

    static String hex(byte[] bytes) {
        StringBuilder b = new StringBuilder(bytes.length * 2);
        for (byte x : bytes) {
            b.append(Character.forDigit((x >> 4) & 15, 16)).append(Character.forDigit(x & 15, 16));
        }
        return b.toString();
    }

    static String sha256(File f) throws IOException {
        try (InputStream in = new FileInputStream(f)) {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] buf = new byte[1 << 16];
            int n;
            while ((n = in.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
            return hex(md.digest());
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IOException(e);
        }
    }

    /**
     * Brings dest into place: a file of exactly size bytes with the SHA-256 sha (lowercase hex). A finished dest is kept
     * as it is when it matches; a partial dest.part is resumed. Returns dest.
     */
    static File download(String url, File dest, long size, String sha, AtomicBoolean cancel, Listener listener)
            throws Failure {
        if (!url.startsWith("https://") && !url.startsWith("http://")) {
            throw new Failure("net", "not an http(s) url");
        }
        File part = new File(dest.getPath() + ".part");
        try {
            if (dest.isFile() && dest.length() == size && sha256(dest).equals(sha)) {
                listener.downloading(size, size);
                return dest;
            }
            if (dest.exists() && !dest.delete()) {
                throw new Failure("storage", "cannot replace " + dest);
            }
            if (part.length() > size && !part.delete()) {
                throw new Failure("storage", "cannot reset " + part);
            }
            File dir = dest.getParentFile();
            if (dir != null && dir.getUsableSpace() < size - part.length() + SPACE_MARGIN) {
                throw new Failure("storage", "not enough free space");
            }
            IOException last = null;
            for (int attempt = 0; attempt < ATTEMPTS && part.length() < size; attempt++) {
                if (cancel.get()) {
                    throw new Failure("aborted", "canceled");
                }
                try {
                    fetch(url, part, size, cancel, listener);
                } catch (IOException e) {
                    last = e;
                    sleep(attempt * 1000L);
                }
            }
            if (cancel.get()) {
                throw new Failure("aborted", "canceled");
            }
            if (part.length() < size) {
                throw new Failure("net", last != null ? String.valueOf(last.getMessage()) : "the server stopped early");
            }
            listener.verifying();
            if (part.length() != size) {
                part.delete();
                throw new Failure("size", part.length() + " bytes, expected " + size);
            }
            if (!sha256(part).equals(sha)) {
                part.delete();
                throw new Failure("hash", "SHA-256 differs");
            }
            if (!part.renameTo(dest)) {
                throw new Failure("storage", "cannot move the file into place");
            }
            return dest;
        } catch (IOException e) {
            throw new Failure("storage", String.valueOf(e.getMessage()));
        }
    }

    // one request: from the end of part to the end of the file (or to size, whichever comes first)
    private static void fetch(String url, File part, long size, AtomicBoolean cancel, Listener listener)
            throws IOException, Failure {
        long have = part.length();
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        try {
            c.setConnectTimeout(CONNECT_TIMEOUT_MS);
            c.setReadTimeout(READ_TIMEOUT_MS);
            c.setRequestProperty("Accept-Encoding", "identity");
            if (have > 0) {
                c.setRequestProperty("Range", "bytes=" + have + "-");
            }
            int code = c.getResponseCode();
            boolean append;
            if (code == 206) {
                String range = c.getHeaderField("Content-Range");
                if (range == null || !range.startsWith("bytes " + have + "-")) {
                    throw new IOException("the server answered another range: " + range);
                }
                append = true;
            } else if (code == 200) {
                // no range support (or a fresh start): the whole file again
                long length = c.getContentLengthLong();
                if (length >= 0 && length != size) {
                    throw new Failure("size", "the server sends " + length + " bytes, expected " + size);
                }
                have = 0;
                append = false;
            } else if (code == 416) {
                // the partial file is not usable as it is: start over
                part.delete();
                throw new IOException("HTTP 416");
            } else {
                throw new IOException("HTTP " + code);
            }
            long done = have;
            try (InputStream in = c.getInputStream(); FileOutputStream out = new FileOutputStream(part, append)) {
                byte[] buf = new byte[1 << 16];
                int n;
                long lastReport = 0;
                while ((n = in.read(buf)) > 0) {
                    if (done + n > size) {
                        out.close();
                        part.delete();
                        throw new Failure("size", "the server sends more than " + size + " bytes");
                    }
                    out.write(buf, 0, n);
                    done += n;
                    long now = System.nanoTime();
                    if (now - lastReport > 250_000_000L) {
                        lastReport = now;
                        listener.downloading(done, size);
                    }
                    if (cancel.get()) {
                        return;
                    }
                }
                out.getFD().sync();
            }
            listener.downloading(done, size);
        } finally {
            c.disconnect();
        }
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
