package com.cindersofchaos.client;

import android.app.Activity;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.Process;

/**
 * The restart helper (O313, docs/ANDROID_CLIENT.md section 4, client base patch 0167). It has no screen and runs in its
 * own process (":restart" in AndroidManifest.xml), so it survives the game process: ChaosActivity.restartApp starts it,
 * it ends the game process, starts the game's launch intent again and ends itself. The game needs this after the first
 * start download, because the engine on Android only exits and the new data folder is mounted at the next start.
 */
public class RestartActivity extends Activity {
    public static final String EXTRA_NEXT = "next";
    public static final String EXTRA_PID = "pid";

    @SuppressWarnings("deprecation")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Intent source = getIntent();
        Intent next = Build.VERSION.SDK_INT >= 33
            ? source.getParcelableExtra(EXTRA_NEXT, Intent.class)
            : (Intent) source.getParcelableExtra(EXTRA_NEXT);
        int pid = source.getIntExtra(EXTRA_PID, -1);
        if (pid > 0 && pid != Process.myPid()) {
            Process.killProcess(pid);
        }
        if (next != null) {
            startActivity(next);
        }
        finish();
        Runtime.getRuntime().exit(0);
    }
}
