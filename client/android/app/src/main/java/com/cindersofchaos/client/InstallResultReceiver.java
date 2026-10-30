package com.cindersofchaos.client;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.os.Build;

/**
 * The answer of the PackageInstaller to the app update (ApkUpdater.install): the system asks the player to confirm
 * (STATUS_PENDING_USER_ACTION: the confirmation window is started from here), or the install failed, or it worked (then
 * Android ends the process and the player opens the new app).
 */
public class InstallResultReceiver extends BroadcastReceiver {
    @SuppressWarnings("deprecation")
    @Override
    public void onReceive(Context context, Intent intent) {
        ApkUpdater updater = ApkUpdater.get(context);
        int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
        switch (status) {
            case PackageInstaller.STATUS_PENDING_USER_ACTION: {
                Intent confirm = Build.VERSION.SDK_INT >= 33
                        ? intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent.class)
                        : (Intent) intent.getParcelableExtra(Intent.EXTRA_INTENT);
                updater.set("confirm", "");
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    try {
                        context.startActivity(confirm);
                    } catch (RuntimeException e) {
                        updater.set("failed", "blocked");
                    }
                }
                break;
            }
            case PackageInstaller.STATUS_SUCCESS:
                updater.set("done", "");
                break;
            case PackageInstaller.STATUS_FAILURE_ABORTED:
                updater.set("failed", "aborted");
                break;
            case PackageInstaller.STATUS_FAILURE_BLOCKED:
                updater.set("failed", "blocked");
                break;
            case PackageInstaller.STATUS_FAILURE_STORAGE:
                updater.set("failed", "storage");
                break;
            case PackageInstaller.STATUS_FAILURE_CONFLICT:
            case PackageInstaller.STATUS_FAILURE_INCOMPATIBLE:
            case PackageInstaller.STATUS_FAILURE_INVALID:
                // a conflict is most often another signing key than the installed app
                updater.set("failed", "signer");
                break;
            default:
                updater.set("failed", "other");
        }
    }
}
