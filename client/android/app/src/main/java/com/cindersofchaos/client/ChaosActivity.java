package com.cindersofchaos.client;

import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;

import java.util.concurrent.Semaphore;

/**
 * The Java shell of the game client (O313, docs/ANDROID_CLIENT.md). A NativeActivity: the engine is libcinders.so
 * (client base patch 0163), which runs android_main. The shell does what the engine cannot do without Java: system
 * bars, the soft keyboard, a text dialog for text fields, a fatal error dialog and opening a link. The engine calls
 * showTextEdit, displayFatalError, openUrl, showKeyboard and hideKeyboard by name through JNI
 * (src/framework/platform/androidwindow.cpp); commitText is the way back (patch 0164 names its C function).
 */
public class ChaosActivity extends android.app.NativeActivity {
    static {
        System.loadLibrary("cinders");
    }

    private AlertDialog activeDialog = null;
    private final Semaphore fatalClosed = new Semaphore(0, true);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            getWindow().getAttributes().layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        }
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

    public void openUrl(String url) {
        if (!url.contains("://")) {
            url = "https://" + url;
        }
        startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
    }

    public static native void commitText(String text);
}
