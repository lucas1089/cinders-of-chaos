package com.cindersofchaos.client;

import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import java.util.concurrent.Semaphore;

/**
 * The Java shell of the game client (O313, docs/ANDROID_CLIENT.md). A NativeActivity: the engine is libcinders.so
 * (client base patch 0163), which runs android_main. The shell does what the engine cannot do without Java: system
 * bars, the soft keyboard, a text dialog for text fields, a fatal error dialog and opening a link. The engine calls
 * showTextEdit, displayFatalError, openUrl, showKeyboard and hideKeyboard by name through JNI
 * (src/framework/platform/androidwindow.cpp); commitText is the way back (patch 0164 names its C function).
 * restartApp is called after the game data download (patch 0167): it starts the game again in a new process.
 * splashProgress and splashHide drive the loading screen shown until the first frame (patch 0168).
 */
public class ChaosActivity extends android.app.NativeActivity {
    static {
        System.loadLibrary("cinders");
    }

    private AlertDialog activeDialog = null;
    private final Semaphore fatalClosed = new Semaphore(0, true);
    private Dialog splash = null;
    private ProgressBar splashBar = null;
    private TextView splashText = null;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            getWindow().getAttributes().layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        }
        showSplash();
    }

    // The loading screen (client base patch 0168). The first load takes a while before the engine draws a frame.
    // A dialog window over the game: never focusable or touchable, so the game window keeps the focus the engine
    // needs to draw at all. The engine hides it after its first frame.
    @SuppressWarnings("deprecation")
    private void showSplash() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setBackgroundColor(Color.BLACK);
        int pad = (int) (24 * getResources().getDisplayMetrics().density);
        box.setPadding(pad, pad, pad, pad);
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.splash_logo);
        logo.setAdjustViewBounds(true);
        logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
        int logoHeight = getResources().getDisplayMetrics().heightPixels / 2;
        box.addView(logo, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, logoHeight));
        splashText = new TextView(this);
        splashText.setText(R.string.splash_loading);
        splashText.setTextColor(Color.rgb(0xe8, 0xc8, 0x8a));
        splashText.setTextSize(20);
        splashText.setGravity(Gravity.CENTER);
        splashText.setPadding(0, pad, 0, pad / 2);
        box.addView(splashText, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT));
        splashBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        splashBar.setMax(100);
        splashBar.setProgress(0);
        int barWidth = getResources().getDisplayMetrics().widthPixels / 3;
        box.addView(splashBar, new LinearLayout.LayoutParams(barWidth, LinearLayout.LayoutParams.WRAP_CONTENT));
        splash = new Dialog(this, android.R.style.Theme_Black_NoTitleBar_Fullscreen);
        splash.setCancelable(false);
        splash.setContentView(box);
        splash.getWindow().addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            | WindowManager.LayoutParams.FLAG_FULLSCREEN);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            splash.getWindow().getAttributes().layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        }
        splash.getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            | View.SYSTEM_UI_FLAG_FULLSCREEN);
        splash.show();
    }

    // engine thread: the module progress of the start (stage text is English and only logged)
    public void splashProgress(final int percent, final String stage) {
        runOnUiThread(new Runnable() {
            public void run() {
                if (splashBar != null) {
                    splashBar.setProgress(Math.max(0, Math.min(100, percent)));
                }
            }
        });
    }

    // engine thread: after the first frame, and when the engine shuts down
    public void splashHide() {
        runOnUiThread(new Runnable() {
            public void run() {
                dismissSplash();
            }
        });
    }

    private void dismissSplash() {
        if (splash != null) {
            splash.dismiss();
            splash = null;
            splashBar = null;
            splashText = null;
        }
    }

    @Override
    protected void onDestroy() {
        dismissSplash();
        super.onDestroy();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            hideSystemUI();
        }
    }

    // immersive mode: the game covers the whole screen, a swipe from the edge shows the bars for a moment
    @SuppressWarnings("deprecation")
    private void hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WindowInsetsController c = getWindow().getInsetsController();
            if (c != null) {
                c.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_FULLSCREEN);
        }
    }

    public void showKeyboard() {
        InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
        imm.showSoftInput(getWindow().getDecorView(), InputMethodManager.SHOW_FORCED);
    }

    public void hideKeyboard() {
        InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
        imm.hideSoftInputFromWindow(getWindow().getDecorView().getWindowToken(), 0);
    }

    // blocks the calling (engine) thread until the player closes the dialog
    public void displayFatalError(final String message) {
        final ChaosActivity activity = this;
        runOnUiThread(new Runnable() {
            public void run() {
                dismissSplash();
                AlertDialog.Builder builder = new AlertDialog.Builder(activity);
                builder.setTitle(R.string.fatal_title);
                builder.setMessage(message);
                builder.setPositiveButton(R.string.fatal_close, new DialogInterface.OnClickListener() {
                    public void onClick(DialogInterface dialog, int id) {
                        fatalClosed.release();
                    }
                });
                builder.setCancelable(false);
                builder.create().show();
            }
        });
        try {
            fatalClosed.acquire();
        } catch (InterruptedException e) {
            // the engine exits next
        }
    }

    // flags: bit 0 = multi line
    public void showTextEdit(final String title, final String description, final String text, final int flags) {
        final ChaosActivity activity = this;
        runOnUiThread(new Runnable() {
            public void run() {
                if (activeDialog != null) {
                    activeDialog.dismiss();
                    activeDialog = null;
                }
                AlertDialog.Builder builder = new AlertDialog.Builder(activity);
                builder.setTitle(title);
                int layout = (flags & 0x01) > 0 ? R.layout.multiline_editor : R.layout.editor;
                View content = LayoutInflater.from(activity).inflate(
                    layout, (ViewGroup) findViewById(android.R.id.content), false);
                final EditText input = (EditText) content.findViewById(R.id.input);
                input.setText(text);
                input.setSelection(text.length());
                if (!description.isEmpty()) {
                    builder.setMessage(description);
                }
                builder.setView(content);
                builder.setPositiveButton(R.string.edit_ok, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        commitText(input.getText().toString());
                        if (dialog == activeDialog) {
                            activeDialog = null;
                        }
                    }
                });
                builder.setNegativeButton(R.string.edit_cancel, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        dialog.cancel();
                        if (dialog == activeDialog) {
                            activeDialog = null;
                        }
                    }
                });
                activeDialog = builder.show();
            }
        });
    }

    // The restart (client base patch 0167). The engine ends its process after every thread is joined (g_app.restart on
    // Android only asks for it and closes the client the normal way, then main() calls this over JNI). A new
    // process has to be started by someone who outlives this one, so a helper activity in its own process
    // (RestartActivity) starts the game again and ends this process. Called on the engine thread, which exits right
    // after: nothing here waits for the UI thread.
    public void restartApp() {
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launch == null) {
            return;
        }
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        Intent helper = new Intent(this, RestartActivity.class);
        helper.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
        helper.putExtra(RestartActivity.EXTRA_NEXT, launch);
        helper.putExtra(RestartActivity.EXTRA_PID, android.os.Process.myPid());
        startActivity(helper);
    }

    public void openUrl(String url) {
        if (!url.contains("://")) {
            url = "https://" + url;
        }
        startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
    }

    public static native void commitText(String text);
}
