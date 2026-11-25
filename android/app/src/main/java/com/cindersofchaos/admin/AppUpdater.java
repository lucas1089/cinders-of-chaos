package com.cindersofchaos.admin;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Self-update of the admin app (O765, docs/ADMIN_APP.md "Atualização do app"): at start (at most once a day, after the
 * lock screen) and from Config > Atualização do app > Procurar atualização. Reads the public GitHub releases list (no
 * token, no account data: only a User-Agent), picks the newest adminapp-N (AppUpdateInfo), asks, downloads
 * CindersAdmin.apk with resume, size and SHA-256 (AppApkFetcher, the .sha256 file of the release) into the app's cache
 * and hands it to the system installer through the FileProvider. When the phone does not allow this app to install, the
 * "install unknown apps" settings page opens and the install runs again when the owner comes back. The installer keeps
 * the app's data (ssh key, settings) when the new APK has the same signature (the ANDROID_KEYSTORE_B64 secret of
 * admin-app.yml).
 */
final class AppUpdater {
    private static final String K_CHECKED = "appUpdateChecked";
    private static final int MAX_JSON = 4 * 1024 * 1024;
    private final MainActivity a;
    private final AtomicBoolean busy = new AtomicBoolean(false);
    private volatile AtomicBoolean cancel = new AtomicBoolean(false);
    private File pendingInstall;
    private boolean checkedThisRun = false;
    /** The status line of the Config card (null until the card exists). */
    TextView status;

    AppUpdater(MainActivity a) {
        this.a = a;
    }

    static long versionCode(Context c) {
        try {
            PackageInfo p = c.getPackageManager().getPackageInfo(c.getPackageName(), 0);
            if (Build.VERSION.SDK_INT >= 28) {
                return p.getLongVersionCode();
            }
            return legacyCode(p);
        } catch (PackageManager.NameNotFoundException e) {
            return 0;
        }
    }

    @SuppressWarnings("deprecation")
    private static long legacyCode(PackageInfo p) {
        return p.versionCode;
    }

    /** The installed version as the app shows it. */
    String installed() {
        return "2." + versionCode(a);
    }

    private void say(String s) {
        if (status != null) {
            status.setText(s);
        }
    }

    /** After the lock screen: a quiet check when the last one is a day old; only a newer version says anything. */
    void checkAtStart() {
        if (checkedThisRun) {
            return;
        }
        checkedThisRun = true;
        long last = 0;
        try {
            last = Long.parseLong(a.store.get(K_CHECKED, "0"));
        } catch (NumberFormatException e) {
            last = 0;
        }
        if (AppUpdateInfo.due(last, System.currentTimeMillis())) {
            check(false);
        }
    }

    /** Looks for a newer version; manual = the button (the answer is always shown). */
    void check(boolean manual) {
        if (busy.get()) {
            if (manual) {
                a.snack("A atualização do app já está em andamento.", false);
            }
            return;
        }
        if (manual) {
            say("Procurando no GitHub...");
        }
        a.pool.execute(() -> {
            String json;
            try {
                json = get(AppUpdateInfo.API, MAX_JSON, true);
            } catch (IOException e) {
                a.main.post(() -> {
                    say("Não deu para procurar agora (" + e.getMessage() + ").");
                    if (manual) {
                        a.snack("Não deu para procurar a atualização: " + e.getMessage(), false);
                    }
                });
                return;
            }
            AppUpdateInfo.Release r = AppUpdateInfo.pick(json);
            long code = versionCode(a);
            a.main.post(() -> {
                a.store.put(K_CHECKED, String.valueOf(System.currentTimeMillis()));
                String text = AppUpdateInfo.summary(r, code);
                say(text);
                if (AppUpdateInfo.newer(r, code)) {
                    offer(r, code);
                } else if (manual) {
                    a.snack(text, true);
                }
            });
        });
    }

    private void offer(AppUpdateInfo.Release r, long code) {
        a.confirm("Atualizar o app para " + r.versionName() + "?", AppUpdateInfo.summary(r, code) + " Baixa do GitHub "
                + "(release " + r.tag + "), confere o tamanho e o SHA-256 e abre o instalador do Android. A chave SSH e as "
                + "configurações ficam.", "Baixar e instalar", false, () -> download(r));
    }

    private void download(AppUpdateInfo.Release r) {
        if (!busy.compareAndSet(false, true)) {
            a.snack("A atualização do app já está em andamento.", false);
            return;
        }
        cancel = new AtomicBoolean(false);
        say("Baixando " + r.versionName() + "...");
        a.snack("Baixando o app " + r.versionName() + "...", true);
        AtomicBoolean stop = cancel;
        a.pool.execute(() -> {
            try {
                String sha = AppUpdateInfo.shaOf(get(r.shaUrl, 4096, false));
                if (sha.isEmpty()) {
                    throw new AppApkFetcher.Failure("hash", "no SHA-256 in " + AppUpdateInfo.SHA);
                }
                File dir = new File(a.getCacheDir(), "update");
                if (!dir.isDirectory() && !dir.mkdirs()) {
                    throw new AppApkFetcher.Failure("storage", "no cache folder");
                }
                String keep = "CindersAdmin-" + r.number + ".apk";
                File[] old = dir.listFiles();
                if (old != null) {
                    for (File f : old) {
                        if (!f.getName().startsWith(keep)) {
                            f.delete();
                        }
                    }
                }
                File dest = new File(dir, keep);
                AppApkFetcher.download(r.apkUrl, dest, r.apkSize, sha, stop, new AppApkFetcher.Listener() {
                    @Override
                    public void downloading(long done, long total) {
                        int pct = total > 0 ? (int) (done * 100 / total) : 0;
                        a.main.post(() -> say(String.format(Locale.ROOT, "Baixando %s: %d%%", r.versionName(), pct)));
                    }

                    @Override
                    public void verifying() {
                        a.main.post(() -> say("Conferindo o SHA-256..."));
                    }
                });
                a.main.post(() -> {
                    busy.set(false);
                    say("Baixado e conferido: " + r.versionName() + ". Abrindo o instalador.");
                    install(dest);
                });
            } catch (AppApkFetcher.Failure f) {
                a.main.post(() -> {
                    busy.set(false);
                    String text = AppUpdateInfo.failure(f.code);
                    say(text);
                    a.snack(text, false);
                });
            } catch (IOException e) {
                a.main.post(() -> {
                    busy.set(false);
                    String text = AppUpdateInfo.failure("net");
                    say(text);
                    a.snack(text, false);
                });
            }
        });
    }

    /** Back on the screen: an install that waited for the "install unknown apps" permission runs now. */
    void resumed() {
        if (pendingInstall != null && a.getPackageManager().canRequestPackageInstalls()) {
            File f = pendingInstall;
            pendingInstall = null;
            install(f);
        }
    }

    private void install(File f) {
        if (!a.getPackageManager().canRequestPackageInstalls()) {
            pendingInstall = f;
            a.confirm("Permitir que o Cinders Admin instale atualizações?", "O Android pede uma vez: na tela que abre, "
                    + "ligue \"Permitir desta fonte\" e volte. A instalação continua sozinha.", "Abrir configuração", false,
                    () -> {
                        try {
                            a.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:" + a.getPackageName())));
                        } catch (RuntimeException e) {
                            a.snack("Abra Configurações > Apps > Cinders Admin > Instalar apps desconhecidos.", false);
                        }
                    });
            return;
        }
        try {
            Uri uri = androidx.core.content.FileProvider.getUriForFile(a, a.getPackageName() + ".files", f);
            Intent i = new Intent(Intent.ACTION_VIEW);
            i.setDataAndType(uri, "application/vnd.android.package-archive");
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            a.startActivity(i);
        } catch (RuntimeException e) {
            a.snack("Não deu para abrir o instalador: " + e.getMessage(), false);
        }
    }

    /** One https GET of a public address, at most max bytes; no token, no cookie, only a User-Agent. */
    private static String get(String url, int max, boolean api) throws IOException {
        if (!url.startsWith("https://")) {
            throw new IOException("not https");
        }
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        try {
            c.setConnectTimeout(15000);
            c.setReadTimeout(20000);
            c.setUseCaches(false);
            c.setRequestProperty("User-Agent", "CindersAdmin");
            if (api) {
                c.setRequestProperty("Accept", "application/vnd.github+json");
            }
            int code = c.getResponseCode();
            if (code != 200) {
                throw new IOException("HTTP " + code);
            }
            try (InputStream in = c.getInputStream()) {
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                byte[] buf = new byte[1 << 14];
                int n;
                while ((n = in.read(buf)) > 0) {
                    if (out.size() + n > max) {
                        throw new IOException("answer too big");
                    }
                    out.write(buf, 0, n);
                }
                return new String(out.toByteArray(), StandardCharsets.UTF_8);
            }
        } finally {
            c.disconnect();
        }
    }
}
