package com.cindersofchaos.admin;

import android.app.KeyguardManager;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.Menu;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.bottomnavigation.BottomNavigationView;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.android.material.navigation.NavigationBarView;
import com.google.android.material.progressindicator.LinearProgressIndicator;
import com.google.android.material.snackbar.Snackbar;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Cinders Admin: control of the live server over ssh. Four tabs at the bottom: Painel (state, numbers and the main
 * buttons), Comandos (quick admin actions and every action of the in-game admin panel), Logs (console, errors, update
 * log and a terminal) and Config (server, key, host fingerprint). Every action is a chaos-ctl.sh command
 * (server/deploy/chaos-ctl.sh) or, in the terminal, whatever the ssh user may run.
 */
public class MainActivity extends AppCompatActivity {
    static final int TAB_PANEL = 0;
    static final int TAB_COMMANDS = 1;
    static final int TAB_LOGS = 2;
    static final int TAB_CONFIG = 3;
    private static final long LOCK_AFTER_MS = 60_000L;
    private static final int REQ_UNLOCK = 17;

    final ExecutorService pool = Executors.newCachedThreadPool();
    final Handler main = new Handler(Looper.getMainLooper());
    Store store;
    Ui ui;

    private FrameLayout content;
    private LinearLayout shell;
    private TextView subtitle;
    private LinearProgressIndicator progress;
    private BottomNavigationView nav;
    private final View[] tabs = new View[4];
    private int current = TAB_PANEL;
    private int running = 0;
    private boolean resumed = false;

    PanelTab panel;
    CommandsTab commands;
    LogsTab logs;
    ConfigTab config;

    private long unlockedAt = 0;
    private boolean unlocking = false;

    /** Refreshes the dashboard every few seconds (Config) while it is on screen. */
    private final Runnable panelTick = new Runnable() {
        @Override
        public void run() {
            int every = store.refreshSec();
            if (every > 0 && resumed && current == TAB_PANEL && store.configured() && isUnlocked()) {
                panel.refresh(false);
            }
            main.postDelayed(this, Math.max(5, every > 0 ? every : 30) * 1000L);
        }
    };
    /** Follows the log every 5 s while the Logs tab shows it with Acompanhar on. */
    private final Runnable logTick = new Runnable() {
        @Override
        public void run() {
            if (resumed && current == TAB_LOGS && store.configured() && isUnlocked()) {
                logs.tick();
            }
            main.postDelayed(this, 5000);
        }
    };

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        // no screenshots and no preview in the recent apps list: the screen shows the server's data
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE);
        store = new Store(this);
        ui = new Ui(this);

        shell = ui.column();
        shell.setBackgroundColor(ui.iron1);
        shell.setFitsSystemWindows(true);
        shell.addView(topBar(), Ui.matchWrap());

        progress = new LinearProgressIndicator(this);
        progress.setIndeterminate(true);
        progress.setIndicatorColor(ui.ember, ui.gold);
        progress.setTrackColor(ui.iron0);
        progress.setTrackThickness(ui.dp(3));
        progress.setVisibility(View.INVISIBLE);
        shell.addView(progress, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ui.dp(3)));

        content = new FrameLayout(this);
        // hidden until the phone's lock screen is passed (onResume)
        content.setVisibility(View.INVISIBLE);
        shell.addView(content, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        nav = new BottomNavigationView(this);
        nav.setBackgroundColor(ui.iron2);
        nav.setLabelVisibilityMode(NavigationBarView.LABEL_VISIBILITY_LABELED);
        nav.setItemIconTintList(getColorStateList(R.color.nav_item));
        nav.setItemTextColor(getColorStateList(R.color.nav_item));
        nav.setItemActiveIndicatorColor(ColorStateList.valueOf(Color.argb(90, 107, 74, 20)));
        Menu m = nav.getMenu();
        m.add(Menu.NONE, TAB_PANEL, 0, "Painel").setIcon(R.drawable.ic_nav_panel);
        m.add(Menu.NONE, TAB_COMMANDS, 1, "Comandos").setIcon(R.drawable.ic_nav_commands);
        m.add(Menu.NONE, TAB_LOGS, 2, "Logs").setIcon(R.drawable.ic_nav_logs);
        m.add(Menu.NONE, TAB_CONFIG, 3, "Config").setIcon(R.drawable.ic_nav_config);
        nav.setOnItemSelectedListener(item -> {
            showTab(item.getItemId(), false);
            return true;
        });
        View rule = ui.divider();
        shell.addView(rule);
        shell.addView(nav, Ui.matchWrap());
        setContentView(shell);

        panel = new PanelTab(this);
        commands = new CommandsTab(this);
        logs = new LogsTab(this);
        config = new ConfigTab(this);
        tabs[TAB_PANEL] = panel.root;
        tabs[TAB_COMMANDS] = commands.root;
        tabs[TAB_LOGS] = logs.root;
        tabs[TAB_CONFIG] = config.root;
        for (View v : tabs) {
            content.addView(v, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT));
        }
        updateSubtitle();
        showTab(store.configured() ? TAB_PANEL : TAB_CONFIG, true);
    }

    private View topBar() {
        LinearLayout bar = ui.row();
        bar.setBackgroundColor(ui.iron0);
        bar.setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(12));
        ImageView flame = new ImageView(this);
        flame.setImageResource(R.drawable.ic_flame);
        bar.addView(flame, new LinearLayout.LayoutParams(ui.dp(28), ui.dp(28)));
        LinearLayout names = ui.column();
        names.setPadding(ui.dp(12), 0, 0, 0);
        TextView t = new TextView(this);
        t.setText("Cinders Admin");
        t.setTextColor(ui.goldLight);
        t.setTextSize(19);
        t.setLetterSpacing(0.04f);
        t.setTypeface(Typeface.create(Typeface.SERIF, Typeface.BOLD));
        names.addView(t);
        subtitle = new TextView(this);
        subtitle.setTextColor(ui.muted);
        subtitle.setTextSize(12);
        names.addView(subtitle);
        bar.addView(names, Ui.weight(1f));
        return bar;
    }

    void updateSubtitle() {
        subtitle.setText(store.host().isEmpty() ? "nenhum servidor configurado"
                : store.user() + "@" + store.host() + (store.port() == 22 ? "" : ":" + store.port()));
    }

    void showTab(int idx, boolean syncNav) {
        current = idx;
        for (int i = 0; i < tabs.length; i++) {
            tabs[i].setVisibility(i == idx ? View.VISIBLE : View.GONE);
        }
        if (syncNav && nav.getSelectedItemId() != idx) {
            nav.setSelectedItemId(idx);
        }
        if (!isUnlocked()) {
            return;
        }
        if (idx == TAB_PANEL && store.configured()) {
            panel.refresh(false);
        } else if (idx == TAB_LOGS && store.configured()) {
            logs.shown();
        }
    }

    // ------------------------------------------------------------------------------------------------ lock

    @Override
    protected void onResume() {
        super.onResume();
        resumed = true;
        if (System.currentTimeMillis() - unlockedAt > LOCK_AFTER_MS && !unlocking) {
            KeyguardManager km = (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
            if (km.isDeviceSecure()) {
                unlocking = true;
                content.setVisibility(View.INVISIBLE);
                Intent i = km.createConfirmDeviceCredentialIntent("Cinders Admin", "Confirme que é você.");
                if (i != null) {
                    startActivityForResult(i, REQ_UNLOCK);
                } else {
                    unlocked();
                }
            } else {
                unlocked();
                snack("Aviso: o celular não tem bloqueio de tela. Ative um: este app controla o servidor.", false);
            }
        }
        main.removeCallbacks(panelTick);
        main.removeCallbacks(logTick);
        main.postDelayed(panelTick, Math.max(5, store.refreshSec() > 0 ? store.refreshSec() : 30) * 1000L);
        main.postDelayed(logTick, 5000);
    }

    @Override
    protected void onPause() {
        super.onPause();
        resumed = false;
        main.removeCallbacks(panelTick);
        main.removeCallbacks(logTick);
    }

    @Override
    @SuppressWarnings("deprecation")
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == REQ_UNLOCK) {
            unlocking = false;
            if (res == RESULT_OK) {
                unlocked();
            } else {
                finish();
            }
        }
    }

    private boolean isUnlocked() {
        return !unlocking && content.getVisibility() == View.VISIBLE;
    }

    private void unlocked() {
        unlockedAt = System.currentTimeMillis();
        unlocking = false;
        content.setVisibility(View.VISIBLE);
        showTab(current, false);
    }

    @Override
    protected void onStop() {
        super.onStop();
        // the connection is closed when the app leaves the screen; the next action opens it again
        pool.execute(Ssh::close);
    }

    // ------------------------------------------------------------------------------------------------ remote

    interface Done {
        /** On the screen thread: the result, or the exception when the command could not run. */
        void done(Ssh.Result r, Exception e);
    }

    /** A chaos-ctl.sh command line with the path from Config. */
    String ctl(String args) {
        return Ssh.sq(store.ctl()) + " " + args;
    }

    /** Runs a command on the server in the background; the progress bar shows while anything runs. */
    void remote(String cmd, int timeoutSec, Done done) {
        setBusy(+1);
        pool.execute(() -> {
            Ssh.Result r = null;
            Exception err = null;
            try {
                r = Ssh.exec(store, cmd, timeoutSec);
            } catch (Exception e) {
                err = e;
            }
            final Ssh.Result fr = r;
            final Exception fe = err;
            main.post(() -> {
                setBusy(-1);
                if (isFinishing() || isDestroyed()) {
                    return;
                }
                done.done(fr, fe);
                String fp = Ssh.newHostFingerprint;
                if (!fp.isEmpty()) {
                    Ssh.newHostFingerprint = "";
                    config.refreshInfo();
                    new MaterialAlertDialogBuilder(this).setTitle("Primeira conexão")
                            .setMessage("Impressão digital do servidor (guardada agora):\n\n" + fp
                                    + "\n\nConfira na VPS com:\nssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub\n\n"
                                    + "Daqui em diante o app recusa outro servidor com o mesmo endereço.")
                            .setPositiveButton("Ok", null).show();
                }
            });
        });
    }

    /** remote() for a chaos-ctl.sh command whose answer is shown as a Friendly outcome. */
    void ctlAction(String args, int timeoutSec, java.util.function.Consumer<Friendly> done) {
        remote(ctl(args), timeoutSec, (r, e) -> done.accept(e != null ? Friendly.ofException(e)
                : Friendly.ofResult(r.out, r.code)));
    }

    private void setBusy(int d) {
        running = Math.max(0, running + d);
        progress.setVisibility(running > 0 ? View.VISIBLE : View.INVISIBLE);
    }

    // ------------------------------------------------------------------------------------------------ feedback

    void snack(String s, boolean good) {
        Snackbar sb = Snackbar.make(content, s, s.length() > 60 ? Snackbar.LENGTH_LONG : Snackbar.LENGTH_SHORT);
        sb.setAnchorView(nav);
        sb.setBackgroundTint(good ? ui.iron3 : ui.bloodDark);
        sb.setTextColor(ui.bright);
        sb.setTextMaxLines(4);
        sb.show();
    }

    void confirm(String title, String message, String yes, boolean danger, Runnable go) {
        MaterialAlertDialogBuilder d = new MaterialAlertDialogBuilder(this).setTitle(title).setMessage(message)
                .setNegativeButton("Cancelar", null).setPositiveButton(yes, (x, w) -> go.run());
        androidx.appcompat.app.AlertDialog dlg = d.show();
        if (danger) {
            dlg.getButton(androidx.appcompat.app.AlertDialog.BUTTON_POSITIVE).setTextColor(ui.ember);
        }
    }

    void copy(String text, String done) {
        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        cm.setPrimaryClip(ClipData.newPlainText("cinders", text));
        snack(done, true);
    }

    void share(String subject, String text) {
        Intent i = new Intent(Intent.ACTION_SEND);
        i.setType("text/plain");
        i.putExtra(Intent.EXTRA_SUBJECT, subject);
        i.putExtra(Intent.EXTRA_TEXT, text);
        startActivity(Intent.createChooser(i, subject));
    }

    /** The card that shows the last answer: a coloured title, a sentence, and the raw output behind "Detalhes". */
    final class ResultCard {
        final MaterialCardView card;
        private final TextView head;
        private final TextView detail;
        private final TextView raw;
        private final TextView toggle;

        ResultCard() {
            card = ui.card();
            LinearLayout b = Ui.body(card);
            head = ui.title("");
            head.setTextSize(15);
            detail = ui.text("");
            detail.setPadding(0, ui.dp(4), 0, 0);
            toggle = new TextView(MainActivity.this);
            toggle.setText("Ver detalhes");
            toggle.setTextColor(ui.gold);
            toggle.setTextSize(13);
            toggle.setPadding(0, ui.dp(10), 0, ui.dp(2));
            raw = ui.mono("");
            raw.setBackgroundColor(ui.iron0);
            raw.setPadding(ui.dp(10), ui.dp(8), ui.dp(10), ui.dp(8));
            raw.setVisibility(View.GONE);
            toggle.setOnClickListener(v -> {
                boolean show = raw.getVisibility() != View.VISIBLE;
                raw.setVisibility(show ? View.VISIBLE : View.GONE);
                toggle.setText(show ? "Esconder detalhes" : "Ver detalhes");
            });
            b.addView(head);
            b.addView(detail);
            b.addView(toggle);
            b.addView(raw, ui.gap(6));
            card.setVisibility(View.GONE);
        }

        void running(String what) {
            card.setVisibility(View.VISIBLE);
            card.setStrokeColor(ui.goldDark);
            head.setTextColor(ui.goldLight);
            head.setText(what + "...");
            detail.setText("Executando na VPS.");
            toggle.setVisibility(View.GONE);
            raw.setVisibility(View.GONE);
        }

        void show(String what, Friendly f) {
            card.setVisibility(View.VISIBLE);
            card.setStrokeColor(f.ok ? ui.iron4 : ui.blood);
            head.setTextColor(f.ok ? ui.ok : ui.ember);
            head.setText((f.ok ? "✓  " : "✕  ") + what + (f.ok ? "" : ": " + f.title));
            detail.setText(f.detail.isEmpty() ? (f.ok ? "Sem resposta do comando." : "") : f.detail);
            detail.setVisibility(detail.getText().length() == 0 ? View.GONE : View.VISIBLE);
            boolean hasRaw = !f.raw.isEmpty() && !f.raw.equals(f.detail);
            toggle.setVisibility(hasRaw ? View.VISIBLE : View.GONE);
            raw.setText(f.raw);
            raw.setVisibility(View.GONE);
            toggle.setText("Ver detalhes");
        }
    }

    /** A centred empty-state line. */
    TextView emptyLine(String s) {
        TextView t = ui.hint(s);
        t.setGravity(Gravity.CENTER);
        t.setPadding(ui.dp(12), ui.dp(16), ui.dp(12), ui.dp(16));
        return t;
    }
}
