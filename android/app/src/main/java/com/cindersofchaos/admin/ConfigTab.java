package com.cindersofchaos.admin;

import android.text.InputType;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.android.material.textfield.TextInputLayout;

import java.nio.charset.StandardCharsets;

/** Config: the server (address, port, user, script path, admin character), the ssh key, and the host fingerprint. */
final class ConfigTab {
    private static final int[] REFRESH = {0, 15, 30, 60, 120};

    final View root;
    private final MainActivity a;
    private final Ui ui;
    private final TextInputLayout fHost;
    private final TextInputLayout fPort;
    private final TextInputLayout fUser;
    private final TextInputLayout fCtl;
    private final TextInputLayout fActor;
    private final MaterialButton refreshPick;
    private final TextView keyState;
    private final TextView fpText;
    private final MainActivity.ResultCard result;

    ConfigTab(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        Store st = a.store;
        LinearLayout page = ui.page();

        result = a.new ResultCard();
        page.addView(result.card, Ui.matchWrap());

        // ---- server
        MaterialCardView srv = ui.titledCard("Servidor");
        LinearLayout sb = Ui.body(srv);
        fHost = ui.field("Endereço da VPS", "IP ou nome, ex.: 203.0.113.10", st.host(), InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_VARIATION_URI);
        sb.addView(fHost);
        fPort = ui.field("Porta SSH", "Normalmente 22.", String.valueOf(st.port()), InputType.TYPE_CLASS_NUMBER);
        fUser = ui.field("Usuário SSH", "Criado pelo comando de instalação.", st.user(), 0);
        sb.addView(ui.evenRow(fPort, fUser), ui.gap(8));
        fCtl = ui.field("Caminho do chaos-ctl.sh", "Na VPS. Padrão: /opt/chaos/repo/server/deploy/chaos-ctl.sh", st.ctl(), 0);
        sb.addView(fCtl, ui.gap(8));
        fActor = ui.field("Personagem admin", "Nome de um personagem seu com grupo de admin (pode estar offline). "
                + "Os comandos do painel do jogo rodam como ele.", st.actor(), InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_CAP_WORDS);
        sb.addView(fActor, ui.gap(8));
        LinearLayout rr = ui.row();
        rr.addView(ui.text("Atualizar o painel sozinho"), Ui.weight(1f));
        refreshPick = ui.secondary(refreshLabel(st.refreshSec()) + "  ▾", 0);
        refreshPick.setOnClickListener(v -> pickRefresh());
        rr.addView(refreshPick);
        sb.addView(rr, ui.gap(10));
        MaterialButton save = ui.primary("Salvar", 0);
        save.setOnClickListener(v -> save());
        MaterialButton test = ui.secondary("Testar conexão", 0);
        test.setOnClickListener(v -> test());
        sb.addView(ui.evenRow(test, save), ui.gap(12));
        page.addView(srv, ui.gap(10));

        // ---- screen
        MaterialCardView scr = ui.titledCard("Tela");
        LinearLayout scb = Ui.body(scr);
        com.google.android.material.materialswitch.MaterialSwitch cap =
                new com.google.android.material.materialswitch.MaterialSwitch(a);
        cap.setText("Permitir captura de tela");
        cap.setTextColor(ui.bright);
        cap.setChecked(st.allowCapture());
        cap.setOnCheckedChangeListener((v, on) -> {
            a.store.put("capture", on ? "1" : "0");
            a.applySecure();
        });
        scb.addView(cap);
        scb.addView(ui.hint("Ligado: dá para tirar print e a tela aparece nos apps recentes. Desligado: o Android "
                + "bloqueia os dois. A tela sempre fica bloqueada enquanto você digita uma senha."), ui.gap(4));
        page.addView(scr, ui.gap(10));

        // ---- key
        MaterialCardView key = ui.titledCard("Chave SSH deste celular");
        LinearLayout kb = Ui.body(key);
        kb.addView(ui.hint("A chave nasce e fica só neste celular, criptografada pelo Android. A VPS recebe só a parte "
                + "pública. O comando de instalação cria o usuário, instala a chave e libera o sudo só para o "
                + "chaos-ctl.sh."));
        keyState = ui.text("");
        keyState.setPadding(0, ui.dp(8), 0, 0);
        kb.addView(keyState);
        MaterialButton gen = ui.secondary("Gerar chave", R.drawable.ic_key);
        gen.setOnClickListener(v -> {
            if (!a.store.publicKey().isEmpty()) {
                a.confirm("Gerar outra chave?", "A atual é apagada e o app perde o acesso até você instalar a nova na "
                        + "VPS.", "Gerar", true, this::generate);
            } else {
                generate();
            }
        });
        MaterialButton show = ui.secondary("Mostrar", 0);
        show.setOnClickListener(v -> showKey());
        kb.addView(ui.evenRow(gen, show), ui.gap(10));
        MaterialButton install = ui.primary("Copiar comando de instalação", R.drawable.ic_copy);
        install.setOnClickListener(v -> {
            if (needKey()) {
                return;
            }
            a.copy(installCommand(), "Comando copiado. Cole no terminal da VPS (como root ou com sudo).");
        });
        kb.addView(install, ui.gap(4));
        MaterialButton copyPub = ui.flat("Copiar chave pública", R.drawable.ic_copy);
        copyPub.setOnClickListener(v -> {
            if (!needKey()) {
                a.copy(a.store.publicKey(), "Chave pública copiada.");
            }
        });
        MaterialButton sharePub = ui.flat("Compartilhar", R.drawable.ic_share);
        sharePub.setOnClickListener(v -> {
            if (!needKey()) {
                a.share("Chave pública do Cinders Admin", a.store.publicKey());
            }
        });
        kb.addView(ui.evenRow(copyPub, sharePub), ui.gap(2));
        page.addView(key, ui.gap(10));

        // ---- host fingerprint
        MaterialCardView fp = ui.titledCard("Impressão digital da VPS");
        LinearLayout fb = Ui.body(fp);
        fb.addView(ui.hint("Guardada na primeira conexão. Depois o app recusa qualquer outro servidor no mesmo endereço "
                + "(proteção contra alguém no meio do caminho). Confira na VPS com: "
                + "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"));
        fpText = ui.mono("");
        fpText.setPadding(0, ui.dp(8), 0, 0);
        fb.addView(fpText);
        MaterialButton forget = ui.danger("Esquecer impressão digital", 0);
        forget.setOnClickListener(v -> a.confirm("Esquecer a impressão digital?",
                "Faça isso só se você reinstalou a VPS ou trocou a chave dela. A próxima conexão guarda a nova.",
                "Esquecer", true, () -> {
                    a.store.put("hostfp", "");
                    a.pool.execute(Ssh::close);
                    refreshInfo();
                    a.snack("Esquecida. A próxima conexão guarda a nova.", true);
                }));
        fb.addView(forget, ui.gap(10));
        page.addView(fp, ui.gap(10));

        // ---- help
        MaterialCardView help = ui.titledCard("Primeira vez");
        LinearLayout hb = Ui.body(help);
        hb.addView(ui.text("1. Preencha o endereço e salve.\n2. Gere a chave.\n3. Copiar comando de instalação e cole na "
                + "VPS como root.\n4. Testar conexão. Confira a impressão digital.\n\nOutro layout na VPS (o kit em "
                + "/opt/chaos-trial, outra unidade systemd)? Escreva os caminhos em /etc/chaos/ctl.conf "
                + "(server/deploy/ctl.conf.trial.example). Variáveis de ambiente não chegam ao chaos-ctl.sh."));
        page.addView(help, ui.gap(10));

        refreshInfo();
        ScrollView sv = new ScrollView(a);
        sv.addView(page, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        root = sv;
    }

    void refreshInfo() {
        String pub = a.store.publicKey();
        keyState.setText(pub.isEmpty() ? "Nenhuma chave ainda." : "Chave pronta: " + shortKey(pub));
        keyState.setTextColor(pub.isEmpty() ? ui.goldLight : ui.ok);
        String fp = a.store.hostFingerprint();
        fpText.setText(fp.isEmpty() ? "Ainda não conectou." : fp);
    }

    private String installCommand() {
        return "echo " + Ssh.sq(a.store.publicKey()) + " | sudo " + Ssh.sq(a.store.ctl()) + " install-admin -";
    }

    private boolean needKey() {
        if (a.store.publicKey().isEmpty()) {
            a.snack("Gere a chave primeiro.", false);
            return true;
        }
        return false;
    }

    private void save() {
        String host = Ui.value(fHost);
        String port = Ui.value(fPort);
        fHost.setError(host.matches("[A-Za-z0-9.:\\-\\[\\]]*") ? null : "Só o endereço, sem espaços nem ssh://");
        fPort.setError(port.matches("\\d{1,5}") && Integer.parseInt(port) > 0 && Integer.parseInt(port) < 65536
                ? null : "1 a 65535");
        if (fHost.getError() != null || fPort.getError() != null) {
            return;
        }
        boolean hostChanged = !host.equals(a.store.host()) || !port.equals(String.valueOf(a.store.port()));
        a.store.put("host", host);
        a.store.put("port", port);
        a.store.put("user", Ui.value(fUser));
        a.store.put("ctl", Ui.value(fCtl));
        a.store.put("actor", Ui.value(fActor));
        a.pool.execute(Ssh::close);
        a.updateSubtitle();
        refreshInfo();
        a.snack(hostChanged && !a.store.hostFingerprint().isEmpty()
                ? "Salvo. Endereço novo: se for outra VPS, esqueça a impressão digital antes de conectar." : "Salvo.", true);
    }

    private void test() {
        if (!a.store.configured()) {
            a.snack("Salve o endereço e gere a chave primeiro.", false);
            return;
        }
        result.running("Testar conexão");
        a.remote("echo \"conectado como $(whoami) em $(hostname)\"; test -x " + Ssh.sq(a.store.ctl())
                + " && echo 'chaos-ctl.sh: ok' || echo 'chaos-ctl.sh: não encontrado em " + a.store.ctl().replace("'", "")
                + "'", 30, (r, e) -> {
            Friendly f = e != null ? Friendly.ofException(e) : Friendly.ofResult(r.out, r.code);
            if (f.ok) {
                boolean ctlOk = r.out.contains("chaos-ctl.sh: ok");
                f = ctlOk ? Friendly.ok("Conectado", r.out.trim(), r.out)
                        : Friendly.fail("Conectou, mas sem chaos-ctl.sh", "A conexão funciona, mas o script não está no "
                        + "caminho configurado. Confira o campo Caminho do chaos-ctl.sh.", r.out);
            }
            result.show("Testar conexão", f);
            refreshInfo();
        });
    }

    private void generate() {
        keyState.setText("Gerando chave (alguns segundos)...");
        a.pool.execute(() -> {
            String msg;
            boolean good;
            try {
                String[] k = Ssh.generateKey();
                a.store.saveKey(k[0].getBytes(StandardCharsets.UTF_8), k[1]);
                Ssh.close();
                msg = "Chave gerada. Agora copie o comando de instalação e rode na VPS.";
                good = true;
            } catch (Exception e) {
                msg = "Não deu para gerar a chave: " + e.getMessage();
                good = false;
            }
            final String m = msg;
            final boolean g = good;
            a.main.post(() -> {
                refreshInfo();
                a.snack(m, g);
            });
        });
    }

    private void showKey() {
        if (needKey()) {
            return;
        }
        TextView t = ui.mono(a.store.publicKey());
        t.setPadding(ui.dp(22), ui.dp(8), ui.dp(22), 0);
        ScrollView sv = new ScrollView(a);
        sv.addView(t);
        new MaterialAlertDialogBuilder(a).setTitle("Chave pública").setView(sv)
                .setNeutralButton("Compartilhar", (d, w) -> a.share("Chave pública do Cinders Admin", a.store.publicKey()))
                .setPositiveButton("Copiar", (d, w) -> a.copy(a.store.publicKey(), "Chave pública copiada."))
                .setNegativeButton("Fechar", null).show();
    }

    private void pickRefresh() {
        String[] labels = new String[REFRESH.length];
        for (int i = 0; i < REFRESH.length; i++) {
            labels[i] = refreshLabel(REFRESH[i]);
        }
        new MaterialAlertDialogBuilder(a).setTitle("Atualizar o painel").setItems(labels, (d, w) -> {
            a.store.put("refresh", String.valueOf(REFRESH[w]));
            refreshPick.setText(labels[w] + "  ▾");
        }).show();
    }

    private static String refreshLabel(int s) {
        return s == 0 ? "Desligado" : s < 60 ? "a cada " + s + " s" : "a cada " + (s / 60) + " min";
    }

    private static String shortKey(String pub) {
        String[] p = pub.split(" ");
        if (p.length >= 2 && p[1].length() > 20) {
            return p[0] + " …" + p[1].substring(p[1].length() - 16);
        }
        return pub;
    }
}
