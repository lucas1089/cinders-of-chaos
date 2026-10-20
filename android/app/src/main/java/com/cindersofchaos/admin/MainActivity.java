package com.cindersofchaos.admin;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.KeyguardManager;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Cinders Admin: control of the live server over ssh. Four tabs: Painel (status and the main buttons), Admin (messages,
 * kick, updates), Terminal (any command, the working folder is kept) and Config (server, key). Every action is a
 * chaos-ctl.sh command (server/deploy/chaos-ctl.sh) or, in the terminal, whatever the ssh user may run.
 */
public class MainActivity extends Activity {
    private static final int BG = Color.rgb(26, 20, 18);
    private static final int CARD = Color.rgb(42, 33, 29);
    private static final int TEXT = Color.rgb(236, 226, 214);
    private static final int DIM = Color.rgb(160, 146, 132);
    private static final int ACCENT = Color.rgb(232, 89, 12);
    private static final int DANGER = Color.rgb(176, 38, 38);
    private static final long LOCK_AFTER_MS = 60_000L;
    private static final int REQ_UNLOCK = 17;

    private final ExecutorService pool = Executors.newCachedThreadPool();
    private final Handler ui = new Handler(Looper.getMainLooper());
    private Store store;

    private FrameLayout content;
    private final View[] tabs = new View[4];
    private final Button[] tabButtons = new Button[4];
    private int current = 0;

    private TextView statusView;
    private TextView adminOut;
    private TextView termOut;
    private EditText termIn;
    private String cwd = "~";
    private String lastCommand = "";
    private TextView cfgInfo;
    private EditText fHost;
    private EditText fPort;
    private EditText fUser;
    private EditText fCtl;

    private long unlockedAt = 0;
    private boolean unlocking = false;
    private final Runnable refresh = new Runnable() {
        @Override
        public void run() {
            if (current == 0 && store.configured()) {
                status();
            }
            ui.postDelayed(this, 20_000);
        }
    };

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        // no screenshots and no preview in the recent apps list: the screen shows the server's data
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE);
        store = new Store(this);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        content = new FrameLayout(this);
        root.addView(content, new LinearLayout.LayoutParams(-1, 0, 1f));

        LinearLayout bar = new LinearLayout(this);
        bar.setBackgroundColor(CARD);
        String[] names = {"Painel", "Admin", "Terminal", "Config"};
        for (int i = 0; i < 4; i++) {
            final int idx = i;
            Button t = button(names[i], false);
            t.setOnClickListener(v -> show(idx));
            tabButtons[i] = t;
            bar.addView(t, new LinearLayout.LayoutParams(0, -2, 1f));
        }
        root.addView(bar, new LinearLayout.LayoutParams(-1, -2));
        setContentView(root);
        root.setFitsSystemWindows(true);

        tabs[0] = buildPanel();
        tabs[1] = buildAdmin();
        tabs[2] = buildTerminal();
        tabs[3] = buildConfig();
        for (View v : tabs) {
            content.addView(v, new FrameLayout.LayoutParams(-1, -1));
        }
        show(store.configured() ? 0 : 3);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (System.currentTimeMillis() - unlockedAt > LOCK_AFTER_MS && !unlocking) {
            KeyguardManager km = (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
            if (km.isDeviceSecure()) {
                unlocking = true;
                content.setVisibility(View.INVISIBLE);
                Intent i = km.createConfirmDeviceCredentialIntent("Cinders Admin", "Confirme que e voce.");
                if (i != null) {
                    startActivityForResult(i, REQ_UNLOCK);
                } else {
                    unlocked();
                }
            } else {
                unlocked();
                toast("Aviso: o celular nao tem bloqueio de tela. Ative um: este app controla o servidor.");
            }
        }
        ui.postDelayed(refresh, 500);
    }

    @Override
    protected void onPause() {
        super.onPause();
        ui.removeCallbacks(refresh);
    }

    @Override
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

    private void unlocked() {
        unlockedAt = System.currentTimeMillis();
        unlocking = false;
        content.setVisibility(View.VISIBLE);
    }

    @Override
    protected void onStop() {
        super.onStop();
        // the connection is closed when the app leaves the screen; the next action opens it again
        pool.execute(Ssh::close);
    }

    // ------------------------------------------------------------------------------------------------ small helpers

    private void toast(String s) {
        Toast.makeText(this, s, Toast.LENGTH_LONG).show();
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    private TextView label(String s, boolean dim) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextColor(dim ? DIM : TEXT);
        t.setTextSize(14);
        t.setPadding(0, dp(6), 0, dp(2));
        return t;
    }

    private TextView mono() {
        TextView t = new TextView(this);
        t.setTypeface(Typeface.MONOSPACE);
        t.setTextSize(12);
        t.setTextColor(TEXT);
        t.setBackgroundColor(CARD);
        t.setPadding(dp(10), dp(10), dp(10), dp(10));
        t.setTextIsSelectable(true);
        return t;
    }

    private Button button(String s, boolean accent) {
        Button b = new Button(this);
        b.setText(s);
        b.setAllCaps(false);
        b.setTextColor(accent ? Color.WHITE : TEXT);
        b.setBackgroundColor(accent ? ACCENT : CARD);
        return b;
    }

    private Button danger(String s) {
        Button b = button(s, false);
        b.setBackgroundColor(DANGER);
        b.setTextColor(Color.WHITE);
        return b;
    }

    private EditText field(String hint, String value, boolean numeric) {
        EditText e = new EditText(this);
        e.setHint(hint);
        e.setText(value);
        e.setTextColor(TEXT);
        e.setHintTextColor(DIM);
        e.setSingleLine(true);
        if (numeric) {
            e.setInputType(InputType.TYPE_CLASS_NUMBER);
        }
        return e;
    }

    private LinearLayout column(View... kids) {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        l.setPadding(dp(14), dp(12), dp(14), dp(12));
        for (View k : kids) {
            l.addView(k, new LinearLayout.LayoutParams(-1, -2));
        }
        return l;
    }

    private LinearLayout row(View... kids) {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.HORIZONTAL);
        for (View k : kids) {
            l.addView(k, new LinearLayout.LayoutParams(0, -2, 1f));
        }
        return l;
    }

    private ScrollView scroll(LinearLayout inner) {
        ScrollView s = new ScrollView(this);
        s.addView(inner, new ViewGroup.LayoutParams(-1, -2));
        return s;
    }

    private void show(int idx) {
        current = idx;
        for (int i = 0; i < 4; i++) {
            tabs[i].setVisibility(i == idx ? View.VISIBLE : View.GONE);
            tabButtons[i].setBackgroundColor(i == idx ? ACCENT : CARD);
        }
        if (idx == 0 && store.configured()) {
            status();
        }
    }

    private void confirm(String question, Runnable yes) {
        new AlertDialog.Builder(this).setMessage(question).setNegativeButton("Cancelar", null)
                .setPositiveButton("Sim", (d, w) -> yes.run()).show();
    }

    /** Runs a command on the server in the background and gives the output to the screen thread. */
    private void remote(String cmd, int timeoutSec, java.util.function.Consumer<String> done) {
        pool.execute(() -> {
            String text;
            try {
                Ssh.Result r = Ssh.exec(store, cmd, timeoutSec);
                text = r.out + (r.code > 0 ? "\n[codigo " + r.code + "]" : "");
            } catch (Exception e) {
                text = "Erro: " + (e.getMessage() == null ? e.toString() : e.getMessage());
            }
            final String result = text;
            ui.post(() -> {
                done.accept(result);
                String fp = Ssh.newHostFingerprint;
                if (!fp.isEmpty()) {
                    Ssh.newHostFingerprint = "";
                    new AlertDialog.Builder(this).setTitle("Primeira conexao")
                            .setMessage("Impressao digital do servidor (guardada agora):\n\n" + fp
                                    + "\n\nConfira no servidor com: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
                            .setPositiveButton("Ok", null).show();
                }
            });
        });
    }

    private String ctl(String args) {
        return Ssh.sq(store.ctl()) + " " + args;
    }

    // ------------------------------------------------------------------------------------------------ Painel

    private View buildPanel() {
        statusView = mono();
        statusView.setText("Toque em Atualizar.");
        Button refreshBtn = button("Atualizar", true);
        refreshBtn.setOnClickListener(v -> status());
        Button start = button("Ligar", false);
        start.setOnClickListener(v -> run("start", 60));
        Button stop = danger("Desligar");
        stop.setOnClickListener(v -> confirm("Desligar o servidor? O jogo salva todos e desconecta os jogadores.",
                () -> run("stop", 240)));
        Button restart = danger("Reiniciar");
        restart.setOnClickListener(v -> confirm("Reiniciar agora? Os jogadores sao desconectados.", () -> run("restart", 240)));
        Button save = button("Salvar", false);
        save.setOnClickListener(v -> run("save", 30));
        Button backup = button("Backup", false);
        backup.setOnClickListener(v -> confirm("Fazer backup agora?", () -> run("backup", 600)));
        Button logs = button("Logs", false);
        logs.setOnClickListener(v -> run("logs 80", 30));
        Button errors = button("Erros", false);
        errors.setOnClickListener(v -> run("errors 60", 30));
        Button players = button("Jogadores", false);
        players.setOnClickListener(v -> run("players", 30));
        return scroll(column(label("Servidor", true), statusView, refreshBtn, row(start, stop, restart),
                row(save, backup, players), row(logs, errors)));
    }

    private void run(String args, int timeout) {
        statusView.setText("Executando...");
        remote(ctl(args), timeout, out -> {
            statusView.setText(out.trim());
            adminOut.setText(out.trim());
        });
    }

    private void status() {
        remote(ctl("status"), 30, out -> {
            Map<String, String> kv = new LinkedHashMap<>();
            for (String line : out.split("\n")) {
                int eq = line.indexOf('=');
                if (eq > 0) {
                    kv.put(line.substring(0, eq), line.substring(eq + 1));
                }
            }
            if (kv.isEmpty()) {
                statusView.setText(out.trim());
                return;
            }
            String svc = kv.getOrDefault("service", "?");
            statusView.setText(("active".equals(svc) ? "NO AR" : "FORA DO AR (" + svc + ")") + "\n"
                    + "Desde:      " + kv.getOrDefault("since", "?") + "\n"
                    + "Jogadores:  " + kv.getOrDefault("players", "?") + "\n"
                    + "Carga:      " + kv.getOrDefault("load", "?") + "\n"
                    + "Memoria:    " + kv.getOrDefault("mem", "?") + "\n"
                    + "Disco:      " + kv.getOrDefault("disk", "?") + "\n"
                    + "Backup:     " + kv.getOrDefault("backup", "?") + "\n"
                    + "Erros Lua:  " + kv.getOrDefault("errors", "?"));
        });
    }

    // ------------------------------------------------------------------------------------------------ Admin

    private View buildAdmin() {
        adminOut = mono();
        adminOut.setText("");
        EditText msg = field("Mensagem para todos", "", false);
        Button send = button("Enviar aviso", true);
        send.setOnClickListener(v -> {
            String t = msg.getText().toString().trim();
            if (t.isEmpty()) {
                return;
            }
            remote(ctl("broadcast " + Ssh.sq(t)), 20, out -> {
                adminOut.setText(out.trim());
                msg.setText("");
            });
        });
        EditText kickName = field("Nome do personagem", "", false);
        Button kick = danger("Expulsar");
        kick.setOnClickListener(v -> {
            String n = kickName.getText().toString().trim();
            if (n.isEmpty()) {
                return;
            }
            confirm("Expulsar " + n + "?", () -> remote(ctl("kick " + Ssh.sq(n)), 20, out -> adminOut.setText(out.trim())));
        });
        Button close = button("Fechar login", false);
        close.setOnClickListener(v -> confirm("Fechar o servidor para novos logins?",
                () -> remote(ctl("close"), 20, out -> adminOut.setText(out.trim()))));
        Button open = button("Abrir login", false);
        open.setOnClickListener(v -> remote(ctl("open"), 20, out -> adminOut.setText(out.trim())));
        EditText secs = field("Segundos de contagem", "60", true);
        Button countdown = danger("Reiniciar com aviso");
        countdown.setOnClickListener(v -> {
            String s = secs.getText().toString().trim();
            if (s.isEmpty()) {
                return;
            }
            confirm("Avisar os jogadores e reiniciar em " + s + " segundos?",
                    () -> remote(ctl("restart " + Ssh.sq(s)), 20, out -> adminOut.setText(out.trim())));
        });
        EditText tag = field("Versao (tag), ex.: winpkg-41", "", false);
        Button updNow = danger("Atualizar agora");
        updNow.setOnClickListener(v -> update(tag, "now"));
        Button updSave = button("Atualizar no save", false);
        updSave.setOnClickListener(v -> update(tag, "at-save"));
        Button updLog = button("Ver andamento", false);
        updLog.setOnClickListener(v -> remote(ctl("update-log 80"), 30, out -> adminOut.setText(out.trim())));
        Button rollback = danger("Voltar versao");
        rollback.setOnClickListener(v -> confirm("Voltar para a versao anterior, agora?",
                () -> remote(ctl("rollback now"), 30, out -> adminOut.setText(out.trim()))));
        return scroll(column(label("Aviso para todos os jogadores", true), msg, send,
                label("Expulsar um personagem", true), kickName, kick,
                label("Login", true), row(close, open),
                label("Reinicio com contagem", true), secs, countdown,
                label("Atualizar o servidor (so a versao pronta do GitHub)", true), tag, row(updNow, updSave),
                row(updLog, rollback), label("Resposta", true), adminOut));
    }

    private void update(EditText tag, String mode) {
        String t = tag.getText().toString().trim();
        if (t.isEmpty()) {
            toast("Digite a versao (tag).");
            return;
        }
        confirm("Atualizar para " + t + (mode.equals("now") ? " AGORA (o servidor para)?" : " no proximo save diario?"),
                () -> remote(ctl("update " + Ssh.sq(t) + " " + mode), 30, out -> adminOut.setText(out.trim())));
    }

    // ------------------------------------------------------------------------------------------------ Terminal

    private View buildTerminal() {
        termOut = mono();
        termOut.setText("Terminal no servidor. Cada comando roda no shell do usuario ssh; 'cd' fica guardado.\n");
        termIn = field("comando", "", false);
        termIn.setTypeface(Typeface.MONOSPACE);
        termIn.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        Button go = button("Enviar", true);
        go.setOnClickListener(v -> terminalRun(termIn.getText().toString()));
        Button again = button("Repetir", false);
        again.setOnClickListener(v -> termIn.setText(lastCommand));
        Button clear = button("Limpar", false);
        clear.setOnClickListener(v -> termOut.setText(""));
        Button sudo = button("sudo -n ", false);
        sudo.setOnClickListener(v -> {
            termIn.setText("sudo -n " + termIn.getText());
            termIn.setSelection(termIn.getText().length());
        });
        return scroll(column(termOut, termIn, row(go, again, sudo, clear)));
    }

    private void terminalRun(String command) {
        String c = command.trim();
        if (c.isEmpty()) {
            return;
        }
        lastCommand = c;
        termIn.setText("");
        termOut.append("\n$ " + c + "\n");
        String wrapped = "cd " + (cwd.equals("~") ? "~" : Ssh.sq(cwd)) + " 2>/dev/null\n" + c
                + "\nprintf '\\n__CWD__%s\\n' \"$(pwd)\"";
        remote(wrapped, 300, out -> {
            int at = out.lastIndexOf("__CWD__");
            if (at >= 0) {
                String dir = out.substring(at + 7).trim();
                if (!dir.isEmpty()) {
                    cwd = dir;
                }
                out = out.substring(0, at).replaceAll("\\s+$", "");
            }
            if (out.length() > 20000) {
                out = "..." + out.substring(out.length() - 20000);
            }
            termOut.append(out + "\n[" + cwd + "]\n");
            if (termOut.length() > 60000) {
                CharSequence t = termOut.getText();
                termOut.setText(t.subSequence(t.length() - 40000, t.length()));
            }
        });
    }

    // ------------------------------------------------------------------------------------------------ Config

    private View buildConfig() {
        fHost = field("Endereco do servidor (IP ou nome)", store.host(), false);
        fPort = field("Porta ssh", String.valueOf(store.port()), true);
        fUser = field("Usuario ssh", store.user(), false);
        fCtl = field("Caminho do chaos-ctl.sh", store.ctl(), false);
        cfgInfo = mono();
        Button saveCfg = button("Salvar", true);
        saveCfg.setOnClickListener(v -> {
            store.put("host", fHost.getText().toString().trim());
            store.put("port", fPort.getText().toString().trim());
            store.put("user", fUser.getText().toString().trim());
            store.put("ctl", fCtl.getText().toString().trim());
            Ssh.close();
            cfgRefresh();
            toast("Salvo.");
        });
        Button gen = button("Gerar chave", false);
        gen.setOnClickListener(v -> {
            if (store.configured() || !store.publicKey().isEmpty()) {
                confirm("Ja existe uma chave. Gerar outra apaga a atual e voce tera que instalar a nova no servidor.",
                        this::generate);
            } else {
                generate();
            }
        });
        Button copyKey = button("Copiar chave publica", false);
        copyKey.setOnClickListener(v -> copy(store.publicKey(), "Chave publica copiada."));
        Button copyCmd = button("Copiar comando do servidor", true);
        copyCmd.setOnClickListener(v -> {
            if (store.publicKey().isEmpty()) {
                toast("Gere a chave primeiro.");
                return;
            }
            copy("echo " + Ssh.sq(store.publicKey()) + " | sudo " + Ssh.sq(store.ctl()) + " install-admin -",
                    "Comando copiado: cole no terminal da VPS (como root ou com sudo).");
        });
        Button test = button("Testar conexao", false);
        test.setOnClickListener(v -> remote("echo conectado como $(whoami) em $(hostname)", 30, out -> {
            cfgInfo.setText(out.trim());
            cfgRefresh();
        }));
        Button forget = button("Esquecer impressao digital do servidor", false);
        forget.setOnClickListener(v -> confirm("Esquecer a impressao digital? A proxima conexao guarda a nova.", () -> {
            store.put("hostfp", "");
            Ssh.close();
            cfgRefresh();
        }));
        cfgRefresh();
        return scroll(column(label("Servidor", true), fHost, row(fPort, fUser), fCtl, saveCfg,
                label("Chave ssh (fica so neste celular)", true), row(gen, copyKey), copyCmd,
                label("Conexao", true), test, forget, cfgInfo,
                label("Passo a passo: 1) salve o endereco. 2) gere a chave. 3) 'Copiar comando do servidor' e cole na VPS. "
                        + "4) Testar conexao.", true)));
    }

    private void generate() {
        cfgInfo.setText("Gerando chave (alguns segundos)...");
        pool.execute(() -> {
            String msg;
            try {
                String[] k = Ssh.generateKey();
                store.saveKey(k[0].getBytes("UTF-8"), k[1]);
                Ssh.close();
                msg = "Chave gerada.";
            } catch (Exception e) {
                msg = "Erro: " + e;
            }
            final String m = msg;
            ui.post(() -> {
                cfgInfo.setText(m);
                cfgRefresh();
            });
        });
    }

    private void cfgRefresh() {
        String pub = store.publicKey();
        String fp = store.hostFingerprint();
        cfgInfo.setText("Chave: " + (pub.isEmpty() ? "nenhuma" : "instalada neste celular") + "\n"
                + "Servidor: " + (fp.isEmpty() ? "ainda nao conectou" : fp));
    }

    private void copy(String text, String done) {
        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        cm.setPrimaryClip(ClipData.newPlainText("cinders", text));
        toast(done);
    }
}
