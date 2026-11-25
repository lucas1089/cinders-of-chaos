package com.cindersofchaos.admin;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.file.Files;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Plain-JVM check of the admin app's self-update (O765, no JUnit needed): the release pick, the version compare, the
 * .sha256 file and the download with resume, size and SHA-256 against a local server.
 * javac -d out app/src/main/java/com/cindersofchaos/admin/AppUpdateInfo.java
 * app/src/main/java/com/cindersofchaos/admin/AppApkFetcher.java app/src/test/java/com/cindersofchaos/admin/AppUpdateInfoTest.java
 * && java -cp out com.cindersofchaos.admin.AppUpdateInfoTest
 */
public final class AppUpdateInfoTest {
    private static int fails = 0;
    private static int count = 0;

    private static void expect(boolean ok, String what) {
        count++;
        if (!ok) {
            fails++;
            System.out.println("FAIL " + what);
        }
    }

    private static final String DL = "https://github.com/lucas1089/cinders-of-chaos/releases/download/";

    private static String rel(String tag, boolean draft, boolean prerelease, long size, boolean sha) {
        return "{\"tag_name\": \"" + tag + "\", \"draft\": " + draft + ", \"prerelease\": " + prerelease
                + ", \"name\": \"Cinders Admin \\\"x\\\" \\u00e9\", \"assets\": ["
                + "{\"name\": \"CindersAdmin.apk\", \"size\": " + size + ", \"browser_download_url\": \"" + DL + tag
                + "/CindersAdmin.apk\"}"
                + (sha ? ", {\"name\": \"CindersAdmin.apk.sha256\", \"size\": 82, \"browser_download_url\": \"" + DL + tag
                + "/CindersAdmin.apk.sha256\"}" : "")
                + "]}";
    }

    // a small file server: /a.apk with range support, counts the requests
    static byte[] body;
    static final AtomicInteger hits = new AtomicInteger();

    private static void handle(HttpExchange x) throws IOException {
        hits.incrementAndGet();
        String range = x.getRequestHeaders().getFirst("Range");
        int from = 0;
        if (range != null && range.startsWith("bytes=")) {
            from = Integer.parseInt(range.substring(6, range.indexOf('-')));
        }
        int len = body.length - from;
        if (from > 0) {
            x.getResponseHeaders().add("Content-Range", "bytes " + from + "-" + (body.length - 1) + "/" + body.length);
            x.sendResponseHeaders(206, len);
        } else {
            x.sendResponseHeaders(200, len);
        }
        try (OutputStream o = x.getResponseBody()) {
            o.write(body, from, len);
        } catch (IOException e) {
            x.close();
        }
    }

    public static void main(String[] args) throws Exception {
        // pick: the highest adminapp-N wins (prereleases count), drafts, other tags, releases without the .sha256 or the
        // APK, foreign addresses are skipped
        String list = "[" + rel("adminapp-139", false, true, 5_000_000, false) + ", "
                + rel("adminapp-150", false, true, 6_291_456, true) + ", "
                + rel("adminapp-160", true, true, 6_000_000, true) + ", "
                + rel("adminapp-151x", false, true, 6_000_000, true) + ", "
                + rel("winpkg-90", false, false, 9, true) + ", "
                + rel("adminapp-149", false, false, 6_000_000, true) + ", "
                + rel("adminapp-155", false, true, 0, true) + "]";
        AppUpdateInfo.Release r = AppUpdateInfo.pick(list);
        expect(r != null && r.number == 150 && r.tag.equals("adminapp-150") && r.apkSize == 6_291_456
                && r.apkUrl.equals(DL + "adminapp-150/CindersAdmin.apk")
                && r.shaUrl.equals(DL + "adminapp-150/CindersAdmin.apk.sha256") && r.versionName().equals("2.150"),
                "pick: adminapp-150 (139 has no .sha256, 160 is a draft, 155 has size 0)");
        String foreign = "[{\"tag_name\": \"adminapp-170\", \"draft\": false, \"assets\": [{\"name\": \"CindersAdmin.apk\", "
                + "\"size\": 10, \"browser_download_url\": \"https://example.com/CindersAdmin.apk\"}, {\"name\": "
                + "\"CindersAdmin.apk.sha256\", \"size\": 1, \"browser_download_url\": \"http://github.com/lucas1089/"
                + "cinders-of-chaos/releases/download/adminapp-170/CindersAdmin.apk.sha256\"}]}]";
        expect(AppUpdateInfo.pick(foreign) == null, "pick: an address off this repository on github.com over https is refused");
        expect(AppUpdateInfo.pick("[]") == null && AppUpdateInfo.pick("{\"message\": \"rate limit\"}") == null
                && AppUpdateInfo.pick("not json") == null && AppUpdateInfo.pick(null) == null
                && AppUpdateInfo.pick("[1, \"x\", null, {\"tag_name\": 5}]") == null, "pick: nothing usable gives null");

        // compare
        expect(AppUpdateInfo.newer(r, 149) && !AppUpdateInfo.newer(r, 150) && !AppUpdateInfo.newer(r, 151)
                && !AppUpdateInfo.newer(null, 1), "newer: only a higher run number");
        expect(AppUpdateInfo.summary(r, 140).equals("Versão nova: 2.150 (instalada: 2.140), 6,0 MB.")
                && AppUpdateInfo.summary(r, 150).equals("O app está na versão mais nova (2.150).")
                && AppUpdateInfo.summary(null, 150).startsWith("Nenhuma"), "summary in Portuguese");
        long day = AppUpdateInfo.DAY_MS;
        expect(AppUpdateInfo.due(0, 1000) && !AppUpdateInfo.due(1000, 1000 + day - 1) && AppUpdateInfo.due(1000, 1000 + day)
                && AppUpdateInfo.due(5000, 1000), "due: once a day, a clock set back checks again");

        // the .sha256 file
        String hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        expect(AppUpdateInfo.shaOf(hex + "\n").equals(hex) && AppUpdateInfo.shaOf(hex.toUpperCase() + "  CindersAdmin.apk\n").equals(hex)
                && AppUpdateInfo.shaOf("abc").isEmpty() && AppUpdateInfo.shaOf(hex + "0").isEmpty()
                && AppUpdateInfo.shaOf(null).isEmpty(), "shaOf: sha256sum's format, nothing else");
        expect(AppUpdateInfo.failure("hash").contains("SHA-256") && AppUpdateInfo.failure("x").startsWith("Não deu"),
                "failure words");

        // the download: whole, resumed after a cut, a wrong SHA-256, a wrong size
        body = new byte[300_000];
        for (int i = 0; i < body.length; i++) {
            body[i] = (byte) (i * 31 + 7);
        }
        File tmp = Files.createTempDirectory("appupd").toFile();
        File src = new File(tmp, "src.bin");
        try (FileOutputStream o = new FileOutputStream(src)) {
            o.write(body);
        }
        String sha = AppApkFetcher.sha256(src);
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/a.apk", AppUpdateInfoTest::handle);
        server.start();
        String url = "http://127.0.0.1:" + server.getAddress().getPort() + "/a.apk";
        AppApkFetcher.Listener quiet = new AppApkFetcher.Listener() {
            public void downloading(long done, long total) {
            }

            public void verifying() {
            }
        };
        try {
            File dest = new File(tmp, "CindersAdmin.apk");
            AppApkFetcher.download(url, dest, body.length, sha, new AtomicBoolean(false), quiet);
            expect(dest.length() == body.length && AppApkFetcher.sha256(dest).equals(sha), "download: whole file");
            dest.delete();
            // a partial file is resumed with a range request
            File part = new File(dest.getPath() + ".part");
            try (FileOutputStream o = new FileOutputStream(part)) {
                o.write(body, 0, 100_000);
            }
            hits.set(0);
            AppApkFetcher.download(url, dest, body.length, sha, new AtomicBoolean(false), quiet);
            expect(dest.length() == body.length && AppApkFetcher.sha256(dest).equals(sha) && hits.get() == 1,
                    "download: a partial file resumed in one request");
            dest.delete();
            String wrong = sha.replace(sha.charAt(0), sha.charAt(0) == 'a' ? 'b' : 'a');
            String code = "";
            try {
                AppApkFetcher.download(url, dest, body.length, wrong, new AtomicBoolean(false), quiet);
            } catch (AppApkFetcher.Failure f) {
                code = f.code;
            }
            expect(code.equals("hash") && !dest.exists(), "download: a wrong SHA-256 is refused, nothing kept");
            code = "";
            try {
                AppApkFetcher.download(url, dest, body.length - 5, sha, new AtomicBoolean(false), quiet);
            } catch (AppApkFetcher.Failure f) {
                code = f.code;
            }
            expect(code.equals("size") && !dest.exists(), "download: a wrong size is refused");
            code = "";
            try {
                AppApkFetcher.download("file:///etc/passwd", dest, 10, sha, new AtomicBoolean(false), quiet);
            } catch (AppApkFetcher.Failure f) {
                code = f.code;
            }
            expect(code.equals("net"), "download: only http(s)");
        } finally {
            server.stop(0);
        }
        System.out.println("AppUpdateInfoTest: " + count + " checks, " + fails + " failures");
        if (fails > 0) {
            System.exit(1);
        }
    }
}
