package com.cindersofchaos.client;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Random;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Plain JVM test of ApkFetcher (the download of the app update): no Android classes.
 *   javac -d /tmp/apkt client/android/app/src/main/java/com/cindersofchaos/client/ApkFetcher.java \
 *         client/android/tests/com/cindersofchaos/client/ApkFetcherTest.java && java -cp /tmp/apkt com.cindersofchaos.client.ApkFetcherTest
 */
public final class ApkFetcherTest {
    static int failures = 0;
    static int checks = 0;

    static void check(boolean ok, String what) {
        checks++;
        if (!ok) {
            failures++;
            System.out.println("FAIL " + what);
        }
    }

    // the behaviour of the fake server, set per case
    static volatile boolean ranges = true;
    static volatile int cutAfter = -1;          // the first response stops after this many bytes (a dropped connection)
    static volatile int extraBytes = 0;         // sends this many bytes more than the file
    static volatile boolean lie = false;        // Content-Length of another size on a 200
    static volatile int status = 0;             // a fixed error status when not 0
    static final AtomicInteger requests = new AtomicInteger();
    static volatile String lastRange = null;
    static byte[] body;

    static void handle(HttpExchange ex) throws IOException {
        requests.incrementAndGet();
        lastRange = ex.getRequestHeaders().getFirst("Range");
        if (status != 0) {
            ex.sendResponseHeaders(status, -1);
            ex.close();
            return;
        }
        byte[] data = body;
        if (extraBytes > 0) {
            data = Arrays.copyOf(body, body.length + extraBytes);
        }
        int from = 0;
        int code = 200;
        if (ranges && lastRange != null && lastRange.startsWith("bytes=")) {
            from = Integer.parseInt(lastRange.substring(6, lastRange.indexOf('-')));
            code = 206;
            ex.getResponseHeaders().add("Content-Range", "bytes " + from + "-" + (data.length - 1) + "/" + data.length);
        }
        int len = data.length - from;
        long declared = lie && code == 200 ? len + 7 : len;
        ex.sendResponseHeaders(code, declared);
        try (OutputStream out = ex.getResponseBody()) {
            int stop = cutAfter >= 0 && cutAfter < len ? cutAfter : len;
            out.write(data, from, stop);
            if (stop < len) {
                cutAfter = -1;
                out.flush();
                ex.getHttpContext();
                throw new IOException("cut");
            }
        } catch (IOException e) {
            // the client sees a dropped connection
        }
    }

    static String sha(byte[] b) throws Exception {
        return ApkFetcher.hex(MessageDigest.getInstance("SHA-256").digest(b));
    }

    static final class Quiet implements ApkFetcher.Listener {
        long last = -1;
        boolean verified = false;

        public void downloading(long done, long total) {
            last = done;
        }

        public void verifying() {
            verified = true;
        }
    }

    static String code(File dest, String url, long size, String sha, AtomicBoolean cancel) {
        try {
            ApkFetcher.download(url, dest, size, sha, cancel, new Quiet());
            return "ok";
        } catch (ApkFetcher.Failure f) {
            return f.code;
        }
    }

    static void reset() {
        ranges = true;
        cutAfter = -1;
        extraBytes = 0;
        lie = false;
        status = 0;
        requests.set(0);
        lastRange = null;
    }

    public static void main(String[] args) throws Exception {
        body = new byte[3 * 1024 * 1024 + 123];
        new Random(7).nextBytes(body);
        String good = sha(body);
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/app.apk", ApkFetcherTest::handle);
        server.start();
        String url = "http://127.0.0.1:" + server.getAddress().getPort() + "/app.apk";
        File dir = Files.createTempDirectory("apkt").toFile();
        File dest = new File(dir, "app.apk");
        File part = new File(dir, "app.apk.part");
        AtomicBoolean never = new AtomicBoolean(false);
        try {
            // a plain download
            reset();
            Quiet q = new Quiet();
            ApkFetcher.download(url, dest, body.length, good, never, q);
            check(Arrays.equals(Files.readAllBytes(dest.toPath()), body), "plain: the file is the body");
            check(!part.exists(), "plain: no .part left");
            check(q.verified && q.last == body.length, "plain: progress and the verifying step");
            check(lastRange == null, "plain: no Range on a fresh start");

            // a finished file is kept without a request
            reset();
            check(code(dest, url, body.length, good, never).equals("ok") && requests.get() == 0, "kept: no request for a good file");

            // a wrong finished file is replaced
            Files.write(dest.toPath(), new byte[]{1, 2, 3});
            reset();
            check(code(dest, url, body.length, good, never).equals("ok") && Arrays.equals(Files.readAllBytes(dest.toPath()), body),
                    "replaced: a wrong old file is downloaded again");
            dest.delete();

            // resume from a partial file: only the rest is requested
            reset();
            Files.write(part.toPath(), Arrays.copyOf(body, 1000000));
            check(code(dest, url, body.length, good, never).equals("ok"), "resume: ok");
            check(("bytes=1000000-").equals(lastRange), "resume: Range from the end of the partial file: " + lastRange);
            check(Arrays.equals(Files.readAllBytes(dest.toPath()), body), "resume: the file is the body");
            dest.delete();

            // a server without ranges sends everything again
            reset();
            ranges = false;
            Files.write(part.toPath(), Arrays.copyOf(body, 5000));
            check(code(dest, url, body.length, good, never).equals("ok") && Arrays.equals(Files.readAllBytes(dest.toPath()), body),
                    "no ranges: the whole file again");
            dest.delete();

            // a dropped connection: the next request resumes
            reset();
            cutAfter = 700000;
            check(code(dest, url, body.length, good, never).equals("ok"), "cut: ok after a retry");
            check(requests.get() >= 2 && Arrays.equals(Files.readAllBytes(dest.toPath()), body), "cut: resumed and complete");
            dest.delete();

            // a partial file bigger than the file is dropped
            reset();
            Files.write(part.toPath(), new byte[body.length + 10]);
            check(code(dest, url, body.length, good, never).equals("ok"), "oversize part: dropped, downloaded");
            dest.delete();

            // wrong SHA-256: refused, nothing in place, nothing left
            reset();
            check(code(dest, url, body.length, sha(new byte[]{9}), never).equals("hash"), "hash: refused");
            check(!dest.exists() && !part.exists(), "hash: no file left");

            // wrong size
            reset();
            check(code(dest, url, body.length + 1, good, never).equals("net") || !dest.exists(), "size: the shorter file is not accepted");
            check(!dest.exists(), "size: nothing in place");
            part.delete();

            // a server that sends more than the manifest says
            reset();
            extraBytes = 50;
            check(code(dest, url, body.length, good, never).equals("size"), "more bytes than signed: refused");
            check(!dest.exists() && !part.exists(), "more bytes: nothing left");

            // a Content-Length of another size on a 200
            reset();
            ranges = false;
            lie = true;
            check(code(dest, url, body.length, good, never).equals("size"), "content-length of another size: refused");

            // HTTP errors
            reset();
            status = 404;
            check(code(dest, url, body.length, good, never).equals("net"), "404: net");
            part.delete();

            // not http
            check(code(dest, "file:///etc/passwd", 10, good, never).equals("net"), "file url refused");
            check(code(dest, "ftp://example.org/a.apk", 10, good, never).equals("net"), "ftp url refused");

            // canceled before the start keeps nothing wrong
            reset();
            check(code(dest, url, body.length, good, new AtomicBoolean(true)).equals("aborted"), "canceled: aborted");
            check(!dest.exists(), "canceled: nothing in place");

            // no space: the check comes before any request
            reset();
            check(code(dest, url, Long.MAX_VALUE / 4, good, never).equals("storage") && requests.get() == 0,
                    "storage: refused before the request");
        } finally {
            server.stop(0);
            for (File f : dir.listFiles()) {
                f.delete();
            }
            dir.delete();
        }
        System.out.println("ApkFetcherTest: " + checks + " checks, " + (failures == 0 ? "OK" : failures + " FAILED"));
        System.exit(failures == 0 ? 0 : 1);
    }
}
