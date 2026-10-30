package com.cindersofchaos.client;

import android.content.Context;
import android.content.Intent;
import android.content.IntentSender;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.content.pm.SigningInfo;
import android.app.PendingIntent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.security.MessageDigest;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * The app updating itself (O313 step 8, docs/ANDROID_CLIENT.md section 4, client base patch 0169). The first-start
 * screen (Lua) reads the signed manifest and calls start with the manifest's "android_apk" entry; this class downloads
 * the APK to the cache (ApkFetcher: resume, size and SHA-256), checks the file (same package name, a higher version
 * code, exactly the signing certificate the manifest names), and hands it to the PackageInstaller. Lua polls status().
 *
 * Status text: "state TAB done TAB total TAB message". States: idle, downloading, verifying, permission (the player has
 * to allow installs from this app), installing, confirm (the system asks the player), failed (message = code: net, size,
 * hash, signer, package, storage, aborted, blocked, other), done. When the install succeeds Android ends this process.
 */
final class ApkUpdater {
    static final String ACTION_RESULT = "com.cindersofchaos.client.APK_INSTALL_RESULT";
    private static final String CACHE_DIR = "apk-update";
    private static final long MAX_SIZE = 1024L * 1024 * 1024;

    private static ApkUpdater instance;

    static synchronized ApkUpdater get(Context context) {
        if (instance == null) {
            instance = new ApkUpdater(context.getApplicationContext());
        }
        return instance;
    }

    private final Context context;
    private final AtomicBoolean cancel = new AtomicBoolean(false);
    private Thread worker = null;
    private String state = "idle";
    private long done = 0;
    private long total = 0;
    private String message = "";

    private ApkUpdater(Context context) {
        this.context = context;
    }

    synchronized String status() {
        return state + "\t" + done + "\t" + total + "\t" + message;
    }

    synchronized void set(String newState, String newMessage) {
        state = newState;
        message = newMessage == null ? "" : newMessage;
    }

    private synchronized void progress(String newState, long d, long t) {
        state = newState;
        done = d;
        total = t;
        message = "";
    }

    private synchronized void fail(String code) {
        state = "failed";
        message = code;
    }

    synchronized void cancel() {
        cancel.set(true);
    }

    static boolean isHex64(String s) {
        if (s == null || s.length() != 64) {
            return false;
        }
        for (int i = 0; i < 64; i++) {
            char c = s.charAt(i);
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
                return false;
            }
        }
        return true;
    }

    /** Starts (or restarts after a failure or the permission step) the update. False when the arguments are refused. */
    synchronized boolean start(String url, String sha256, long size, String signerSha256) {
        if (url == null || !(url.startsWith("https://") || url.startsWith("http://")) || !isHex64(sha256)
                || !isHex64(signerSha256) || size < 1 || size > MAX_SIZE) {
            return false;
        }
        if (worker != null && worker.isAlive()) {
            return true;
        }
        // Android 8 and newer: installing needs the permission "install unknown apps" for this app, set by the player
        if (!context.getPackageManager().canRequestPackageInstalls()) {
            state = "permission";
            message = "";
            done = 0;
            total = 0;
            Intent settings = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + context.getPackageName()));
            settings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                context.startActivity(settings);
            } catch (RuntimeException e) {
                // the screen still says what to do
            }
            return true;
        }
        cancel.set(false);
        state = "downloading";
        message = "";
        done = 0;
        total = size;
        final String fUrl = url;
        final String fSha = sha256;
        final long fSize = size;
        final String fSigner = signerSha256;
        worker = new Thread(() -> run(fUrl, fSha, fSize, fSigner), "apk-update");
        worker.setDaemon(true);
        worker.start();
        return true;
    }

    private void run(String url, String sha256, long size, String signer) {
        try {
            File dir = new File(context.getCacheDir(), CACHE_DIR);
            if (!dir.isDirectory() && !dir.mkdirs()) {
                fail("storage");
                return;
            }
            File dest = new File(dir, sha256 + ".apk");
            File[] old = dir.listFiles();
            if (old != null) {
                for (File f : old) {
                    // earlier updates and their partial files; this update's own files are kept (resume)
                    if (!f.getName().startsWith(sha256)) {
                        f.delete();
                    }
                }
            }
            ApkFetcher.download(url, dest, size, sha256, cancel, new ApkFetcher.Listener() {
                @Override
                public void downloading(long d, long t) {
                    progress("downloading", d, t);
                }

                @Override
                public void verifying() {
                    progress("verifying", size, size);
                }
            });
            progress("verifying", size, size);
            String bad = checkPackage(dest, signer);
            if (bad != null) {
                dest.delete();
                fail(bad);
                return;
            }
            install(dest);
        } catch (ApkFetcher.Failure f) {
            fail(f.code);
        } catch (Exception e) {
            fail("other");
        }
    }

    /** null when the file is an update of this app signed with exactly the certificate the manifest named, else the code. */
    @SuppressWarnings("deprecation")
    private String checkPackage(File apk, String signerSha256) throws Exception {
        PackageManager pm = context.getPackageManager();
        int flags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ? PackageManager.GET_SIGNING_CERTIFICATES : PackageManager.GET_SIGNATURES;
        PackageInfo archive = pm.getPackageArchiveInfo(apk.getAbsolutePath(), flags);
        if (archive == null || !context.getPackageName().equals(archive.packageName)) {
            return "package";
        }
        PackageInfo running = pm.getPackageInfo(context.getPackageName(), 0);
        long newCode = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? archive.getLongVersionCode() : archive.versionCode;
        long oldCode = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? running.getLongVersionCode() : running.versionCode;
        if (newCode <= oldCode) {
            return "package";
        }
        Signature[] signers;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            SigningInfo info = archive.signingInfo;
            signers = info == null ? null : info.getApkContentsSigners();
        } else {
            signers = archive.signatures;
        }
        // exactly one signing certificate, and it is the one the signed manifest names
        if (signers == null || signers.length != 1) {
            return "signer";
        }
        String got = ApkFetcher.hex(MessageDigest.getInstance("SHA-256").digest(signers[0].toByteArray()));
        return got.equals(signerSha256) ? null : "signer";
    }

    private void install(File apk) throws Exception {
        PackageInstaller installer = context.getPackageManager().getPackageInstaller();
        for (PackageInstaller.SessionInfo s : installer.getMySessions()) {
            try {
                installer.abandonSession(s.getSessionId());
            } catch (RuntimeException e) {
                // already gone
            }
        }
        PackageInstaller.SessionParams params = new PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        params.setAppPackageName(context.getPackageName());
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12 and newer: no confirmation when this app installed the running version
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED);
        }
        int id = installer.createSession(params);
        try (PackageInstaller.Session session = installer.openSession(id)) {
            try (InputStream in = new FileInputStream(apk); OutputStream out = session.openWrite("base.apk", 0, apk.length())) {
                byte[] buf = new byte[1 << 16];
                int n;
                while ((n = in.read(buf)) > 0) {
                    out.write(buf, 0, n);
                }
                session.fsync(out);
            }
            set("installing", "");
            Intent result = new Intent(context, InstallResultReceiver.class).setAction(ACTION_RESULT);
            int pending = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                pending |= PendingIntent.FLAG_MUTABLE; // the installer adds the status extras
            }
            IntentSender sender = PendingIntent.getBroadcast(context, id, result, pending).getIntentSender();
            session.commit(sender);
        }
    }
}
