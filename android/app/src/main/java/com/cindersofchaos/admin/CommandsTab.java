package com.cindersofchaos.admin;

import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.View;
import android.view.ViewGroup;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.button.MaterialButtonToggleGroup;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.checkbox.MaterialCheckBox;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.android.material.textfield.TextInputLayout;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Comandos: the quick admin actions (message to everyone, kick, login, server version) and every action of the in-game
 * admin panel, as a searchable list grouped by category with a form per action. The panel actions go through
 * chaos-ctl.sh catalog / panel and run as the admin character set in Config, with that character's group.
 */
final class CommandsTab {
    final View root;
    private final MainActivity a;
    private final Ui ui;
    private final LinearLayout quick;
    private final LinearLayout catalogPage;
    private final MainActivity.ResultCard result;
    private final TextView catInfo;
    private final TextInputLayout search;
    private final LinearLayout list;
    private JSONArray catalog = new JSONArray(); // flat list of {cat, id, name, description, params, confirm, dangerous}
    private final Set<String> open = new HashSet<>();
    private SpectateCard spectate; // Ações rápidas > Assistir jogador (set in buildQuick)

    CommandsTab(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        LinearLayout page = ui.page();

        MaterialButtonToggleGroup seg = new MaterialButtonToggleGroup(a);
        seg.setSingleSelection(true);
        seg.setSelectionRequired(true);
        MaterialButton bQuick = ui.secondary("Ações rápidas", 0);
        bQuick.setId(View.generateViewId());
        bQuick.setCheckable(true);
        MaterialButton bPanel = ui.secondary("Painel do jogo", 0);
        bPanel.setId(View.generateViewId());
        bPanel.setCheckable(true);
        seg.addView(bQuick, Ui.weight(1f));
        seg.addView(bPanel, Ui.weight(1f));
        page.addView(seg, Ui.matchWrap());

        result = a.new ResultCard();
        page.addView(result.card, ui.gap(10));

        quick = ui.column();
        buildQuick();
        page.addView(quick, Ui.matchWrap());

        catalogPage = ui.column();
        MaterialCardView head = ui.titledCard("Painel de admin do jogo");
        LinearLayout hb = Ui.body(head);
        hb.addView(ui.hint("Tudo o que o painel de admin faz dentro do jogo: banir, itens, premium, spawn, eventos. Roda "
                + "como o personagem admin da aba Config (pode estar offline), com o grupo dele."));
        catInfo = ui.text("");
        catInfo.setPadding(0, ui.dp(8), 0, 0);
        hb.addView(catInfo);
        search = ui.field("Buscar (ex.: ban, item, spawn)", null, "", 0);
        search.setStartIconDrawable(R.drawable.ic_search);
        search.setStartIconTintList(android.content.res.ColorStateList.valueOf(ui.muted));
        hb.addView(search, ui.gap(10));
        MaterialButton reload = ui.secondary("Atualizar lista", R.drawable.ic_refresh);
        reload.setOnClickListener(v -> fetchCatalog());
        hb.addView(reload, ui.gap(6));
        catalogPage.addView(head, Ui.matchWrap());
        list = ui.column();
        catalogPage.addView(list, ui.gap(10));
        page.addView(catalogPage, Ui.matchWrap());

        if (search.getEditText() != null) {
            search.getEditText().addTextChangedListener(new TextWatcher() {
                @Override
                public void beforeTextChanged(CharSequence s, int st, int c, int af) {
                }

                @Override
                public void onTextChanged(CharSequence s, int st, int b, int c) {
                    fillList();
                }

                @Override
                public void afterTextChanged(Editable e) {
                }
            });
        }

        seg.addOnButtonCheckedListener((g, id, checked) -> {
            if (checked) {
                quick.setVisibility(id == bQuick.getId() ? View.VISIBLE : View.GONE);
                catalogPage.setVisibility(id == bPanel.getId() ? View.VISIBLE : View.GONE);
                if (id == bPanel.getId()) {
                    stopSpectate();
                }
            }
        });
        seg.check(bQuick.getId());
        quick.setVisibility(View.VISIBLE);
        catalogPage.setVisibility(View.GONE);

        loadCachedCatalog();
        ScrollView sv = new ScrollView(a);
        sv.addView(page, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        root = sv;
    }

    // ------------------------------------------------------------------------------------------------ quick actions

    /** Stops the live view (the tab, the segment or the app was left). */
    void stopSpectate() {
        if (spectate != null) {
            spectate.stop("Parado ao sair da tela.");
        }
    }

    private void buildQuick() {
        // message to everyone
        MaterialCardView msgCard = ui.titledCard("Aviso para todos");
        LinearLayout mb = Ui.body(msgCard);
        TextInputLayout msg = ui.field("Mensagem", "Aparece para todos os jogadores online (até 200 letras).", "",
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        mb.addView(msg);
        MaterialButton send = ui.primary("Enviar aviso", R.drawable.ic_send);
        send.setOnClickListener(v -> {
            String t = Ui.value(msg);
            if (t.isEmpty()) {
                msg.setError("Escreva a mensagem.");
                return;
            }
            msg.setError(null);
            ctl("Aviso", "broadcast " + Ssh.sq(t), 20, () -> Ui.setValue(msg, ""));
        });
        mb.addView(send, ui.gap(8));
        quick.addView(msgCard, ui.gap(10));

        // kick
        MaterialCardView kickCard = ui.titledCard("Expulsar um personagem");
        LinearLayout kb = Ui.body(kickCard);
        TextInputLayout kickName = ui.field("Nome do personagem", "Ele é desconectado; pode entrar de novo.", "",
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_WORDS);
        kb.addView(kickName);
        MaterialButton kick = ui.danger("Expulsar", 0);
        kick.setOnClickListener(v -> {
            String n = Ui.value(kickName);
            if (n.isEmpty()) {
                kickName.setError("Escreva o nome.");
                return;
            }
            kickName.setError(null);
            a.confirm("Expulsar " + n + "?", "O personagem é desconectado do jogo.", "Expulsar", true,
                    () -> ctl("Expulsar " + n, "kick " + Ssh.sq(n), 20, null));
        });
        kb.addView(kick, ui.gap(8));
        quick.addView(kickCard, ui.gap(10));

        // live view of a character (server/README.md "Live spectator")
        spectate = new SpectateCard(a);
        quick.addView(spectate.card, ui.gap(10));

        // login
        MaterialCardView loginCard = ui.titledCard("Login");
        LinearLayout lb = Ui.body(loginCard);
        lb.addView(ui.hint("Fechar impede novos logins; quem está online continua jogando."));
        MaterialButton close = ui.danger("Fechar login", 0);
        close.setOnClickListener(v -> a.confirm("Fechar o login?", "Ninguém mais entra até você abrir de novo.",
                "Fechar", true, () -> ctl("Fechar login", "close", 20, null)));
        MaterialButton openB = ui.secondary("Abrir login", 0);
        openB.setOnClickListener(v -> ctl("Abrir login", "open", 20, null));
        lb.addView(ui.evenRow(openB, close), ui.gap(8));
        quick.addView(loginCard, ui.gap(10));

        // version
        MaterialCardView upCard = ui.titledCard("Versão do servidor");
        LinearLayout ub = Ui.body(upCard);
        TextInputLayout tag = ui.field("Versão (tag)", "Uma versão pronta do GitHub, ex.: winpkg-41.", "", 0);
        ub.addView(tag);
        MaterialButton now = ui.danger("Atualizar agora", 0);
        now.setOnClickListener(v -> update(tag, "now"));
        MaterialButton atSave = ui.secondary("No save diário", 0);
        atSave.setOnClickListener(v -> update(tag, "at-save"));
        ub.addView(ui.evenRow(atSave, now), ui.gap(8));
        MaterialButton progress = ui.secondary("Ver andamento", R.drawable.ic_nav_logs);
        progress.setOnClickListener(v -> {
            a.showTab(MainActivity.TAB_LOGS, true);
            a.logs.openUpdate();
        });
        MaterialButton rollback = ui.danger("Voltar versão", 0);
        rollback.setOnClickListener(v -> a.confirm("Voltar para a versão anterior?",
                "O servidor para, volta para a versão anterior e liga de novo.", "Voltar agora", true,
                () -> ctl("Voltar versão", "rollback now", 30, null)));
        ub.addView(ui.evenRow(progress, rollback), ui.gap(4));
        ub.addView(ui.hint("Por tag: o layout padrão (/opt/chaos). No kit Linux (/opt/chaos-trial) use Atualizar "
                + "servidor no Painel."), ui.gap(6));
        quick.addView(upCard, ui.gap(10));

        buildXp();
        buildBeta();
        buildClientServicesImpl();
        buildAccounts();
        buildHealth();
        buildVps();
        buildServices();
        buildTesters();
        buildSiteClient();
    }

    // XP rate: config.lua experienceStages = the release's stages x N (chaos-ctl.sh xp-rate)
    private void buildXp() {
        MaterialCardView c = ui.titledCard("Taxa de XP");
        LinearLayout b = Ui.body(c);
        TextView now = ui.text("Toque em Ver para ler o config.lua.");
        b.addView(now);
        TextInputLayout mult = ui.field("Multiplicador", "1 a 100. x10 = os estágios de XP da release vezes 10. "
                + "Atualizar servidor mantém o valor.", "", InputType.TYPE_CLASS_NUMBER);
        b.addView(mult, ui.gap(8));
        MaterialButton see = ui.secondary("Ver", R.drawable.ic_refresh);
        see.setOnClickListener(v -> a.ctlAction("xp-rate show", 30, f -> {
            if (!f.ok) {
                result.show("Taxa de XP", f);
                return;
            }
            String xp = "", exp = "";
            for (String line : f.raw.split("\n")) {
                if (line.startsWith("xp=")) {
                    xp = line.substring(3);
                } else if (line.startsWith("rateExp=")) {
                    exp = line.substring(8);
                }
            }
            now.setText("Agora: " + (xp.equals("custom") ? "tabela editada à mão" : xp.equals("x1") ? "x1 (padrão)" : xp)
                    + (exp.isEmpty() ? "" : "  ·  rateExp " + exp));
        }));
        MaterialButton later = ui.secondary("Gravar (próximo reinício)", 0);
        later.setOnClickListener(v -> xpSet(mult, false));
        MaterialButton nowB = ui.danger("Gravar e reiniciar", 0);
        nowB.setOnClickListener(v -> xpSet(mult, true));
        MaterialButton reset = ui.flat("Voltar ao padrão (x1)", 0);
        reset.setOnClickListener(v -> a.confirm("Voltar a XP ao padrão?", "Os estágios da release, sem multiplicador. "
                + "Vale no próximo reinício.", "Voltar", false, () -> ctl("Taxa de XP padrão", "xp-rate reset", 30, null)));
        b.addView(ui.evenRow(see, reset), ui.gap(6));
        b.addView(ui.evenRow(later, nowB), ui.gap(4));
        quick.addView(c, ui.gap(10));
    }

    private void xpSet(TextInputLayout mult, boolean restart) {
        int n = UpdateInfo.num(Ui.value(mult));
        if (n < 1 || n > 100) {
            mult.setError("De 1 a 100.");
            return;
        }
        mult.setError(null);
        String args = "xp-rate set " + n + (restart ? " restart" : "");
        if (restart) {
            a.confirm("XP x" + n + " e reiniciar?", "O servidor reinicia agora: os jogadores são desconectados (o jogo "
                    + "salva antes).", "Reiniciar", true, () -> ctl("XP x" + n, args, 240, null));
        } else {
            ctl("XP x" + n, args, 30, null);
        }
    }

    // beta test mode: lifts the weekly / daily gameplay limits for testers, never the store's (chaos-ctl.sh beta-mode)
    private void buildBeta() {
        MaterialCardView c = ui.titledCard("Modo beta (testes)");
        LinearLayout b = Ui.body(c);
        TextView now = ui.text("Toque em Ver para ler o estado.");
        b.addView(now);
        b.addView(ui.hint("Ligado: sem os limites semanais e diários do jogo (trava do raide e do chefe da guilda, "
                + "tarefas de caça, ofertas semanais do Candlemarks e das facções, teto de honra e da comunidade, "
                + "espera das masmorras). Os limites da loja (dinheiro real, ex.: Poção de XP em dobro) continuam. "
                + "Vale no próximo reinício, ou já com reiniciar."), ui.gap(4));
        MaterialButton see = ui.secondary("Ver", R.drawable.ic_refresh);
        see.setOnClickListener(v -> a.ctlAction("beta-mode status", 30, f -> {
            if (!f.ok) {
                result.show("Modo beta", f);
                return;
            }
            String state = f.raw.contains("beta_mode=on") ? "LIGADO" : f.raw.contains("beta_mode=off") ? "desligado" : "?";
            now.setText("Agora (arquivo do servidor): " + state);
        }));
        MaterialButton on = ui.secondary("Ligar (próximo reinício)", 0);
        on.setOnClickListener(v -> ctl("Modo beta ligado", "beta-mode on", 30, null));
        MaterialButton off = ui.secondary("Desligar (próximo reinício)", 0);
        off.setOnClickListener(v -> ctl("Modo beta desligado", "beta-mode off", 30, null));
        MaterialButton onNow = ui.danger("Ligar e reiniciar", 0);
        onNow.setOnClickListener(v -> a.confirm("Ligar o modo beta e reiniciar?", "O servidor reinicia agora: os "
                + "jogadores são desconectados (o jogo salva antes).", "Reiniciar", true,
                () -> ctl("Modo beta ligado", "beta-mode on restart", 240, null)));
        MaterialButton offNow = ui.danger("Desligar e reiniciar", 0);
        offNow.setOnClickListener(v -> a.confirm("Desligar o modo beta e reiniciar?", "O servidor reinicia agora: os "
                + "jogadores são desconectados (o jogo salva antes).", "Reiniciar", true,
                () -> ctl("Modo beta desligado", "beta-mode off restart", 240, null)));
        b.addView(see, ui.gap(6));
        b.addView(ui.evenRow(on, off), ui.gap(4));
        b.addView(ui.evenRow(onNow, offNow), ui.gap(4));
        quick.addView(c, ui.gap(10));
    }

    // the login-screen services (port 8090): the Python program (default) or the Rust port, opt-in
    // (chaos-ctl.sh clientservices-impl; server/README.md "Rust services (O153)")
    private void buildClientServicesImpl() {
        MaterialCardView c = ui.titledCard("Serviços da tela de login (Rust)");
        LinearLayout b = Ui.body(c);
        TextView now = ui.text("Toque em Ver para ler o estado.");
        b.addView(now);
        b.addView(ui.hint("Quem responde a porta 8090 da tela de login (criatura do dia, eventos, jogadores online): "
                + "o programa em Python (padrão) ou a versão em Rust. Ligar o Rust compila no servidor (precisa do "
                + "cargo; leva alguns minutos), troca o serviço e reinicia só ele; se a compilação falhar nada muda, "
                + "e se o serviço não subir volta sozinho para o Python. O jogo não reinicia. Atualizar servidor "
                + "recompila enquanto o Rust estiver ligado."), ui.gap(4));
        MaterialButton see = ui.secondary("Ver", R.drawable.ic_refresh);
        see.setOnClickListener(v -> a.ctlAction("clientservices-impl status", 30, f -> {
            if (!f.ok) {
                result.show("Serviços da tela de login", f);
                return;
            }
            String state = f.raw.contains("clientservices_impl=rust") ? "RUST" : f.raw.contains(
                    "clientservices_impl=python") ? "Python (padrão)" : "?";
            now.setText("Agora: " + state + (f.raw.contains("binary=present") ? " (binário instalado)" : ""));
        }));
        MaterialButton rust = ui.secondary("Ligar Rust", 0);
        rust.setOnClickListener(v -> a.confirm("Ligar o Rust?", "Compila no servidor e reinicia o serviço da tela de "
                + "login (alguns segundos fora do ar). O jogo não reinicia.", "Ligar", false,
                () -> ctl("Rust ligado", "clientservices-impl rust", 900, null)));
        MaterialButton py = ui.secondary("Voltar ao Python", 0);
        py.setOnClickListener(v -> ctl("Python ligado", "clientservices-impl python", 60, null));
        b.addView(see, ui.gap(6));
        b.addView(ui.evenRow(rust, py), ui.gap(4));
        quick.addView(c, ui.gap(10));
    }

    // accounts: the password goes on stdin, never on the command line (chaos-ctl.sh account-create / account-password)
    private void buildAccounts() {
        MaterialCardView c = ui.titledCard("Contas");
        LinearLayout b = Ui.body(c);
        TextInputLayout name = ui.field("Conta", "3 a 32 letras ou números.", "", InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        TextInputLayout pass = ui.field("Senha", "6 a 64 caracteres. Vai pelo SSH, nunca na linha de comando.", "",
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        b.addView(name);
        b.addView(pass, ui.gap(6));
        MaterialButton create = ui.primary("Criar conta", 0);
        create.setOnClickListener(v -> account("account-create", "Criar conta", name, pass));
        MaterialButton change = ui.secondary("Trocar senha", 0);
        change.setOnClickListener(v -> account("account-password", "Trocar senha", name, pass));
        b.addView(ui.evenRow(create, change), ui.gap(8));
        b.addView(ui.hint("Chaos Coins e grupo (GM): Painel do jogo > Store > Give Chaos Coins e Players > Set group."),
                ui.gap(6));
        quick.addView(c, ui.gap(10));
    }

    private void account(String cmd, String label, TextInputLayout name, TextInputLayout pass) {
        String n = Ui.value(name);
        String p = pass.getEditText() == null ? "" : pass.getEditText().getText().toString();
        if (!n.matches("[A-Za-z0-9]{3,32}")) {
            name.setError("3 a 32 letras ou números.");
            return;
        }
        name.setError(null);
        if (p.length() < 6 || p.length() > 64 || p.contains("\n")) {
            pass.setError("6 a 64 caracteres.");
            return;
        }
        pass.setError(null);
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        result.running(label + " " + n);
        a.ctlAction(cmd + " " + n, 40, p + "\n", f -> {
            result.show(label + " " + n, f);
            a.snack(label + ": " + (f.ok ? "feito" : f.title), f.ok);
            if (f.ok) {
                Ui.setValue(pass, "");
            }
        });
    }

    // tester bots on the live server (chaos-ctl.sh testers, server/README.md "Tester bots")
    private void buildTesters() {
        MaterialCardView c = ui.titledCard("Testers");
        LinearLayout b = Ui.body(c);
        b.addView(ui.hint("Personagens \"Tester\" jogam de verdade e anotam bugs. Precisam da chave do client em "
                + "/etc/chaos/tester-client-key. Param sozinhos no fim do tempo."));
        TextInputLayout count = ui.field("Quantos", "1 a 150.", "100", InputType.TYPE_CLASS_NUMBER);
        TextInputLayout minutes = ui.field("Minutos", "1 a 1440.", "60", InputType.TYPE_CLASS_NUMBER);
        b.addView(ui.evenRow(count, minutes), ui.gap(8));
        MaterialButton start = ui.primary("Iniciar", R.drawable.ic_play);
        start.setOnClickListener(v -> {
            int n = number(count, 1, 150), m = number(minutes, 1, 1440);
            if (n < 0 || m < 0) {
                return;
            }
            a.confirm("Iniciar " + n + " testers por " + m + " min?", "Se o ajudante de teste ainda não carregou, o "
                    + "servidor reinicia com 5 minutos de aviso e os testers entram 30 s depois.", "Iniciar", true,
                    () -> ctl("Iniciar testers", "testers start " + n + " " + m + " --restart 300", 180, null));
        });
        MaterialButton stop = ui.danger("Parar", R.drawable.ic_stop);
        stop.setOnClickListener(v -> a.confirm("Parar os testers?", "Eles saem do jogo e o ajudante de teste é "
                + "removido.", "Parar", true, () -> ctl("Parar testers", "testers stop", 60, null)));
        b.addView(ui.evenRow(start, stop), ui.gap(8));
        MaterialButton status = ui.secondary("Status", R.drawable.ic_refresh);
        status.setOnClickListener(v -> a.ctlAction("testers status", 30, f -> {
            if (!f.ok) {
                result.show("Testers", f);
                return;
            }
            StringBuilder t = new StringBuilder();
            for (String line : f.raw.split("\n")) {
                int eq = line.indexOf('=');
                if (eq <= 0) {
                    continue;
                }
                String k = line.substring(0, eq), val = line.substring(eq + 1);
                switch (k) {
                    case "running": t.append("Rodando: ").append(val.equals("yes") ? "sim" : "não").append('\n'); break;
                    case "started": if (!val.isEmpty()) t.append("Início: ").append(val).append('\n'); break;
                    case "bots": t.append("Testers: ").append(val).append('\n'); break;
                    case "minutes": t.append("Minutos: ").append(val).append('\n'); break;
                    case "online": t.append("Online agora: ").append(val).append('\n'); break;
                    case "online_peak": t.append("Pico online: ").append(val).append('\n'); break;
                    case "online_server": if (!val.isEmpty()) t.append("Online no servidor: ").append(val).append('\n'); break;
                    case "logins": t.append("Logins: ").append(val).append('\n'); break;
                    case "deaths": t.append("Mortes: ").append(val).append('\n'); break;
                    case "helper_loaded": t.append("Ajudante carregado: ").append(val.equals("yes") ? "sim" : "não").append('\n'); break;
                    default: break;
                }
            }
            result.show("Testers", Friendly.ok("Feito", t.toString().trim(), f.raw));
        }));
        MaterialButton report = ui.secondary("Relatório", R.drawable.ic_search);
        report.setOnClickListener(v -> ctl("Relatório dos testers", "testers report", 120, null));
        b.addView(ui.evenRow(status, report), ui.gap(6));
        MaterialButton actions = ui.flat("Log das ações", R.drawable.ic_nav_logs);
        actions.setOnClickListener(v -> ctl("Log dos testers", "testers log 400", 60, null));
        b.addView(actions, ui.gap(6));
        b.addView(ui.hint("Cada rodada grava sozinha o log de tudo o que os testers fizeram e os erros que receberam, e "
                + "o relatório no fim. Ficam as 20 últimas rodadas na VPS."), ui.gap(4));
        MaterialButton clean = ui.flat("Apagar os testers", 0);
        clean.setOnClickListener(v -> a.confirm("Apagar todas as contas de tester?", "Apaga as contas, os "
                + "personagens e tudo deles. Precisa de 2 minutos desde que pararam (se rodando, para agora: toque "
                + "de novo depois). O próximo Iniciar cria novos, com os níveis atuais.", "Apagar", true,
                () -> ctl("Apagar testers", "testers cleanup --yes", 120, null)));
        b.addView(clean, ui.gap(6));
        quick.addView(c, ui.gap(10));
    }

    // the machine: info, system updates, reboot (chaos-ctl.sh vps)
    private void buildVps() {
        MaterialCardView c = ui.titledCard("VPS");
        LinearLayout b = Ui.body(c);
        b.addView(ui.hint("A máquina: memória, disco, atualizações do sistema e reinício. Para o resto, Logs > Terminal."));
        MaterialButton info = ui.secondary("Informações", R.drawable.ic_refresh);
        info.setOnClickListener(v -> a.ctlAction("vps info", 90, f -> {
            if (!f.ok) {
                result.show("VPS", f);
                return;
            }
            Map<String, String> m = new LinkedHashMap<>();
            for (String line : f.raw.split("\n")) {
                int eq = line.indexOf('=');
                if (eq > 0) {
                    m.put(line.substring(0, eq), line.substring(eq + 1));
                }
            }
            StringBuilder t = new StringBuilder();
            t.append("Máquina: ").append(m.getOrDefault("host", "?")).append('\n');
            t.append("Sistema: ").append(m.getOrDefault("os", "?")).append('\n');
            t.append("Ligada há: ").append(m.getOrDefault("uptime", "?")).append('\n');
            t.append("Carga: ").append(m.getOrDefault("load", "?")).append(" (").append(m.getOrDefault("cpus", "?"))
                    .append(" CPUs)\n");
            t.append("Memória: ").append(m.getOrDefault("mem_used_mb", "?")).append(" de ")
                    .append(m.getOrDefault("mem_total_mb", "?")).append(" MB\n");
            t.append("Disco: ").append(m.getOrDefault("disk_free_gb", "?")).append(" GB livres de ")
                    .append(m.getOrDefault("disk_total_gb", "?")).append(" GB\n");
            String up = m.getOrDefault("upgrades", "-1");
            t.append("Atualizações do sistema: ").append(up.equals("-1") ? "não sei" : up).append('\n');
            String php = m.getOrDefault("php", "");
            if (!php.isEmpty()) {
                t.append("PHP: ").append(php).append('\n');
            }
            String phpUp = m.getOrDefault("php_upgrades", "-1");
            if (!phpUp.equals("-1") && !phpUp.equals("0")) {
                t.append("Atualizações do PHP pendentes: ").append(phpUp).append(" (toque em Atualizar sistema)\n");
            }
            t.append("Precisa reiniciar: ").append("yes".equals(m.get("reboot_required")) ? "sim" : "não").append('\n');
            String at = m.getOrDefault("reboot_at", "");
            if (!at.isEmpty()) {
                t.append("Reinício marcado: ").append(at).append('\n');
            }
            result.show("VPS", Friendly.ok("Feito", t.toString().trim(), f.raw));
        }));
        MaterialButton upgrade = ui.secondary("Atualizar sistema", R.drawable.ic_backup);
        upgrade.setOnClickListener(v -> a.confirm("Atualizar o sistema da VPS?", "apt-get update e upgrade, em "
                + "segundo plano. O jogo continua rodando. Veja o andamento em Log da atualização.", "Atualizar", false,
                () -> ctl("Atualizar sistema", "vps upgrade", 30, null)));
        b.addView(ui.evenRow(info, upgrade), ui.gap(6));
        MaterialButton upLog = ui.flat("Log da atualização", R.drawable.ic_nav_logs);
        upLog.setOnClickListener(v -> ctl("Log da atualização", "vps upgrade-log 200", 30, null));
        b.addView(upLog, ui.gap(6));
        TextInputLayout minutes = ui.field("Reiniciar em (min)", "1 a 60.", "5", InputType.TYPE_CLASS_NUMBER);
        b.addView(minutes, ui.gap(6));
        MaterialButton reboot = ui.danger("Reiniciar VPS", R.drawable.ic_restart);
        reboot.setOnClickListener(v -> {
            int m = number(minutes, 1, 60);
            if (m < 0) {
                return;
            }
            a.confirm("Reiniciar a VPS em " + m + " min?", "Os jogadores são avisados e o jogo é salvo. A máquina "
                    + "inteira reinicia (jogo, site, banco). Pode cancelar até lá.", "Reiniciar", true,
                    () -> ctl("Reiniciar VPS", "vps reboot " + m, 30, null));
        });
        MaterialButton cancel = ui.secondary("Cancelar reinício", R.drawable.ic_stop);
        cancel.setOnClickListener(v -> ctl("Cancelar reinício", "vps reboot-cancel", 30, null));
        b.addView(ui.evenRow(reboot, cancel), ui.gap(6));
        quick.addView(c, ui.gap(10));
    }

    // the chaos-* systemd units: list, start / stop / restart, log (chaos-ctl.sh services, service, service-log)
    private void buildServices() {
        MaterialCardView c = ui.titledCard("Serviços");
        LinearLayout b = Ui.body(c);
        b.addView(ui.hint("Os serviços do jogo na VPS (servidor, backup, ajuda, Discord, pagamentos...). Toque em "
                + "Ver serviços e escolha um para ligar, desligar, reiniciar ou ver o log."));
        MaterialButton list = ui.secondary("Ver serviços", R.drawable.ic_search);
        list.setOnClickListener(v -> a.ctlAction("services", 30, f -> {
            if (!f.ok) {
                result.show("Serviços", f);
                return;
            }
            List<String> names = new ArrayList<>();
            List<String> labels = new ArrayList<>();
            for (String line : f.raw.split("\n")) {
                String[] p = line.trim().split("\\s+");
                if (p.length < 3 || !p[0].startsWith("chaos-")) {
                    continue;
                }
                names.add(p[0]);
                String state = p[1].equals("active") ? "ligado" : p[1].equals("inactive") ? "desligado"
                        : p[1].equals("failed") ? "FALHOU" : p[1];
                labels.add(p[0].replace(".service", "") + "  ·  " + state);
            }
            if (names.isEmpty()) {
                result.show("Serviços", Friendly.ok("Feito", "Nenhum serviço chaos-* nesta VPS.", f.raw));
                return;
            }
            new MaterialAlertDialogBuilder(a).setTitle("Serviços")
                    .setItems(labels.toArray(new String[0]), (d, w) -> serviceActions(names.get(w))).show();
        }));
        b.addView(list, ui.gap(6));
        quick.addView(c, ui.gap(10));
    }

    private void serviceActions(String unit) {
        String q = Ssh.sq(unit);
        String[] acts = {"Ver log", "Reiniciar", "Ligar", "Desligar"};
        new MaterialAlertDialogBuilder(a).setTitle(unit).setItems(acts, (d, w) -> {
            switch (w) {
                case 0: ctl("Log de " + unit, "service-log " + q + " 200", 30, null); break;
                case 1: a.confirm("Reiniciar " + unit + "?", "O serviço para e liga de novo.", "Reiniciar", true,
                        () -> ctl("Reiniciar " + unit, "service " + q + " restart", 240, null)); break;
                case 2: ctl("Ligar " + unit, "service " + q + " start", 120, null); break;
                default: a.confirm("Desligar " + unit + "?", "Ele fica parado até você ligar de novo (ou até a "
                        + "VPS reiniciar).", "Desligar", true,
                        () -> ctl("Desligar " + unit, "service " + q + " stop", 240, null)); break;
            }
        }).show();
    }

    // a whole number in [lo, hi] from the field, or -1 with the field's error set
    private static int number(TextInputLayout l, int lo, int hi) {
        int n;
        try {
            n = Integer.parseInt(Ui.value(l).trim());
        } catch (NumberFormatException e) {
            n = -1;
        }
        if (n < lo || n > hi) {
            l.setError(lo + " a " + hi + ".");
            return -1;
        }
        l.setError(null);
        return n;
    }

    // health, disk cleanup and backups
    private void buildHealth() {
        MaterialCardView c = ui.titledCard("Saúde e espaço");
        LinearLayout b = Ui.body(c);
        b.addView(ui.hint("Servidor, banco, site (nginx / PHP), disco e as sobras de atualizações em /var/tmp e "
                + "tfs.antes-* antigos."));
        MaterialButton health = ui.secondary("Verificar", R.drawable.ic_refresh);
        health.setOnClickListener(v -> a.ctlAction("health", 40, f -> {
            if (!f.ok) {
                result.show("Saúde", f);
                return;
            }
            StringBuilder s = new StringBuilder();
            for (String line : f.raw.split("\n")) {
                int eq = line.indexOf('=');
                if (eq <= 0) {
                    continue;
                }
                String k = line.substring(0, eq), val = line.substring(eq + 1);
                switch (k) {
                    case "service": s.append("Servidor: ").append(Friendly.state(val)).append('\n'); break;
                    case "database": s.append("Banco: ").append(val.equals("ok") ? "respondendo" : "fora do ar").append('\n'); break;
                    case "web": s.append("Site: ").append(val.equals("none") ? "nenhum serviço web achado" : val).append('\n'); break;
                    case "disk": s.append("Disco: ").append(val).append('\n'); break;
                    case "disk_free": s.append("Livre em /var/tmp: ").append(val).append('\n'); break;
                    case "mem": s.append("Memória: ").append(val).append('\n'); break;
                    case "cleanup": s.append("Para limpar: ").append(val.replace("item(s)", "itens")).append('\n'); break;
                    default: break;
                }
            }
            result.show("Saúde", Friendly.ok("Feito", s.toString().trim(), f.raw));
        }));
        MaterialButton clean = ui.danger("Limpar sobras", 0);
        clean.setOnClickListener(v -> a.ctlAction("cleanup", 40, f -> {
            if (!f.ok) {
                result.show("Limpar", f);
                return;
            }
            if (f.raw.contains("nothing to clean up")) {
                a.snack("Nada para limpar.", true);
                return;
            }
            a.confirm("Apagar estes arquivos?", f.raw.replace("would remove ", "").replace("(cleanup --yes removes them)", ""),
                    "Apagar", true, () -> ctl("Limpar sobras", "cleanup --yes", 120, null));
        }));
        b.addView(ui.evenRow(health, clean), ui.gap(8));
        MaterialButton backups = ui.secondary("Ver backups", R.drawable.ic_backup);
        backups.setOnClickListener(v -> a.ctlAction("backups", 30, f -> {
            if (!f.ok) {
                result.show("Backups", f);
                return;
            }
            StringBuilder s = new StringBuilder();
            for (String line : f.raw.split("\n")) {
                String[] p = line.split("\t");
                if (line.startsWith("dir=")) {
                    s.append("Pasta: ").append(line.substring(4)).append("\n\n");
                } else if (p.length == 4) {
                    long bytes;
                    try {
                        bytes = Long.parseLong(p[2].trim());
                    } catch (NumberFormatException e) {
                        bytes = 0;
                    }
                    String size = bytes >= 1048576 ? (bytes / 1048576) + " MB" : (bytes / 1024) + " KB";
                    s.append(p[0].equals("db") ? "Banco  " : "Arquivos  ").append(p[1]).append("  ").append(size)
                            .append('\n');
                }
            }
            result.show("Backups", Friendly.ok("Feito", s.toString().trim()
                    + "\n\nRestaurar é pela VPS (docs/LAUNCH.md, Incident runbook): o app não restaura banco.", f.raw));
        }));
        b.addView(backups, ui.gap(4));
        quick.addView(c, ui.gap(10));
    }

    // the site and the client update on their own
    private void buildSiteClient() {
        MaterialCardView c = ui.titledCard("Site e update do client");
        LinearLayout b = Ui.body(c);
        MaterialButton site = ui.secondary("Reinstalar o site", 0);
        site.setOnClickListener(v -> a.confirm("Reinstalar o site?", "Roda o website/install_site.sh (idempotente: "
                + "copia o overlay, refaz a config e as tabelas). O site fica no ar.", "Reinstalar", false,
                () -> ctl("Reinstalar o site", "site-install", 30, null)));
        MaterialButton siteLog = ui.flat("Log do site", R.drawable.ic_nav_logs);
        siteLog.setOnClickListener(v -> {
            a.showTab(MainActivity.TAB_LOGS, true);
            a.logs.openUpdate("site-log");
        });
        b.addView(ui.evenRow(site, siteLog));
        TextInputLayout tag = ui.field("Release do client", "Ex.: winpkg-47. Publica o update assinado que os clients "
                + "baixam ao abrir (precisa ser mais nova que a publicada).", "", 0);
        b.addView(tag, ui.gap(8));
        MaterialButton pub = ui.primary("Publicar update", R.drawable.ic_send);
        pub.setOnClickListener(v -> {
            String t = Ui.value(tag);
            if (!t.matches("[A-Za-z0-9][A-Za-z0-9._-]{0,63}") || t.contains("..")) {
                tag.setError("Uma tag de release, ex.: winpkg-47.");
                return;
            }
            tag.setError(null);
            a.confirm("Publicar o update do client " + t + "?", "Os jogadores recebem os arquivos novos na próxima vez "
                    + "que abrirem o client.", "Publicar", false,
                    () -> ctl("Publicar " + t, "publish-update " + Ssh.sq(t), 30, null));
        });
        MaterialButton pubLog = ui.flat("Log da publicação", R.drawable.ic_nav_logs);
        pubLog.setOnClickListener(v -> {
            a.showTab(MainActivity.TAB_LOGS, true);
            a.logs.openUpdate("publish-log");
        });
        b.addView(ui.evenRow(pub, pubLog), ui.gap(6));
        MaterialButton dl = ui.secondary("Trocar os downloads do site", 0);
        dl.setOnClickListener(v -> a.confirm("Trocar os downloads do site?", "Baixa o pacote Windows e o Linux da release "
                + "mais nova para a página de downloads. Não reinicia o servidor e não mexe no update do client. "
                + "Os arquivos de antes ficam como .prev.", "Trocar", false,
                () -> ctl("Trocar os downloads", "update-downloads", 30, null)));
        MaterialButton dlLog = ui.flat("Log da atualização", R.drawable.ic_nav_logs);
        dlLog.setOnClickListener(v -> {
            a.showTab(MainActivity.TAB_LOGS, true);
            a.logs.openUpdate("update-log");
        });
        b.addView(ui.evenRow(dl, dlLog), ui.gap(6));
        b.addView(ui.hint("A versão publicada, a release mais nova e a release dos downloads aparecem em Painel > "
                + "Atualizar servidor > Verificar. Quem baixou o pacote do site e vê um update por cima dele precisa "
                + "deste botão: o pacote do site é o que ele baixa."), ui.gap(6));
        quick.addView(c, ui.gap(10));
    }

    private void update(TextInputLayout tag, String mode) {
        String t = Ui.value(tag);
        if (t.isEmpty()) {
            tag.setError("Digite a versão (tag).");
            return;
        }
        tag.setError(null);
        boolean now = mode.equals("now");
        a.confirm("Atualizar para " + t + "?", now ? "O servidor para agora, atualiza e liga de novo."
                        : "A atualização acontece no próximo save diário.", now ? "Atualizar agora" : "Agendar", now,
                () -> ctl("Atualizar para " + t, "update " + Ssh.sq(t) + " " + mode, 30, null));
    }

    private void ctl(String what, String args, int timeout, Runnable onOk) {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        result.running(what);
        a.ctlAction(args, timeout, f -> {
            result.show(what, f);
            a.snack(what + ": " + (f.ok ? "feito" : f.title), f.ok);
            if (f.ok && onOk != null) {
                onOk.run();
            }
        });
    }

    // ------------------------------------------------------------------------------------------------ catalog

    private void loadCachedCatalog() {
        try {
            flatten(new JSONObject(a.store.get("catalog", "{}")));
        } catch (Exception e) {
            catalog = new JSONArray();
        }
        catInfo.setText(catalog.length() == 0
                ? "Lista vazia: toque em Atualizar lista. O personagem admin precisa existir e ter grupo de admin."
                : catalog.length() + " comandos (lista guardada).");
        fillList();
    }

    private void flatten(JSONObject o) throws Exception {
        JSONArray flat = new JSONArray();
        JSONArray cats = o.getJSONArray("categories");
        for (int i = 0; i < cats.length(); i++) {
            JSONObject c = cats.getJSONObject(i);
            JSONArray acts = c.getJSONArray("actions");
            for (int j = 0; j < acts.length(); j++) {
                JSONObject act = acts.getJSONObject(j);
                act.put("cat", c.optString("label", c.optString("id")));
                flat.put(act);
            }
        }
        catalog = flat;
    }

    private boolean needActor() {
        if (a.store.actor().isEmpty()) {
            a.snack("Defina o personagem admin na aba Config.", false);
            return true;
        }
        return false;
    }

    private void fetchCatalog() {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        if (needActor()) {
            return;
        }
        catInfo.setText("Pedindo a lista ao jogo (até 15 s)...");
        a.remote(a.ctl("catalog " + Ssh.sq(a.store.actor())), 40, (r, e) -> {
            Friendly f = e != null ? Friendly.ofException(e) : Friendly.ofResult(r.out, r.code);
            if (f.ok) {
                try {
                    String t = r.out.trim();
                    JSONObject o = new JSONObject(t.substring(t.indexOf('{')));
                    flatten(o);
                    a.store.put("catalog", o.toString());
                    catInfo.setText(catalog.length() + " comandos (grupo " + o.optInt("group") + ").");
                    fillList();
                    return;
                } catch (Exception ex) {
                    f = Friendly.fail("Resposta inesperada", "O jogo respondeu algo que não é a lista.", r.out);
                }
            }
            catInfo.setText("Sem lista: " + f.title + ".");
            result.show("Atualizar lista", f);
        });
    }

    private void fillList() {
        list.removeAllViews();
        String q = Ui.value(search).toLowerCase(Locale.ROOT);
        Map<String, List<JSONObject>> groups = new LinkedHashMap<>();
        for (int i = 0; i < catalog.length(); i++) {
            JSONObject act = catalog.optJSONObject(i);
            if (act == null) {
                continue;
            }
            String hay = (act.optString("cat") + " " + act.optString("name") + " " + act.optString("id") + " "
                    + act.optString("description")).toLowerCase(Locale.ROOT);
            if (!q.isEmpty() && !hay.contains(q)) {
                continue;
            }
            groups.computeIfAbsent(act.optString("cat"), k -> new ArrayList<>()).add(act);
        }
        if (groups.isEmpty()) {
            list.addView(a.emptyLine(catalog.length() == 0 ? "Nenhum comando ainda." : "Nada encontrado para \"" + q + "\"."));
            return;
        }
        for (Map.Entry<String, List<JSONObject>> g : groups.entrySet()) {
            final String cat = g.getKey();
            final boolean expanded = !q.isEmpty() || open.contains(cat);
            MaterialCardView card = ui.card();
            LinearLayout b = Ui.body(card);
            b.setPadding(0, 0, 0, 0);
            LinearLayout header = ui.row();
            header.setPadding(ui.dp(16), ui.dp(14), ui.dp(16), ui.dp(14));
            TextView name = ui.title(cat);
            name.setTextSize(15);
            name.setTextColor(ui.goldLight);
            header.addView(name, Ui.weight(1f));
            TextView count = ui.hint(g.getValue().size() + (expanded ? "  ▾" : "  ▸"));
            header.addView(count);
            header.setOnClickListener(v -> {
                if (!open.remove(cat)) {
                    open.add(cat);
                }
                fillList();
            });
            b.addView(header);
            if (expanded) {
                for (JSONObject act : g.getValue()) {
                    b.addView(ui.divider());
                    b.addView(actionRow(act));
                }
            }
            list.addView(card, ui.gap(8));
        }
    }

    private View actionRow(JSONObject act) {
        LinearLayout row = ui.column();
        row.setPadding(ui.dp(16), ui.dp(10), ui.dp(16), ui.dp(10));
        android.util.TypedValue tv = new android.util.TypedValue();
        a.getTheme().resolveAttribute(android.R.attr.selectableItemBackground, tv, true);
        row.setBackgroundResource(tv.resourceId);
        LinearLayout top = ui.row();
        TextView n = ui.text(act.optString("name"));
        n.setTextColor(ui.bright);
        n.setTypeface(Typeface.DEFAULT_BOLD);
        top.addView(n, Ui.weight(1f));
        if (act.optBoolean("dangerous")) {
            TextView tag = new TextView(a);
            tag.setText("perigoso");
            tag.setTextSize(11);
            tag.setTextColor(ui.ember);
            tag.setPadding(ui.dp(8), ui.dp(2), ui.dp(8), ui.dp(2));
            GradientDrawable bg = new GradientDrawable();
            bg.setCornerRadius(ui.dp(10));
            bg.setStroke(ui.dp(1), ui.blood);
            tag.setBackground(bg);
            top.addView(tag);
        }
        row.addView(top);
        String d = act.optString("description");
        if (!d.isEmpty()) {
            TextView dt = ui.hint(d);
            dt.setMaxLines(2);
            row.addView(dt);
        }
        row.setOnClickListener(v -> actionForm(act));
        return row;
    }

    private void actionForm(final JSONObject act) {
        final JSONArray params = act.optJSONArray("params") == null ? new JSONArray() : act.optJSONArray("params");
        final View[] inputs = new View[params.length()];
        final String[] picked = new String[params.length()];
        LinearLayout box = ui.column();
        box.setPadding(ui.dp(22), ui.dp(4), ui.dp(22), 0);
        if (!act.optString("description").isEmpty()) {
            box.addView(ui.hint(act.optString("description")));
        }
        if (params.length() == 0) {
            box.addView(ui.text("Sem parâmetros."), ui.gap(8));
        }
        for (int i = 0; i < params.length(); i++) {
            final int idx = i;
            JSONObject p = params.optJSONObject(i);
            if (p == null) {
                p = new JSONObject();
            }
            String type = p.optString("type", "string");
            String lab = p.optString("label", p.optString("name")) + (p.optBoolean("required") ? " *" : "");
            String hint = p.optString("hint", "");
            String def = p.isNull("default") || !p.has("default") ? "" : String.valueOf(p.opt("default"));
            if (type.equals("bool")) {
                MaterialCheckBox cb = new MaterialCheckBox(a);
                cb.setText(lab + (hint.isEmpty() ? "" : " (" + hint + ")"));
                cb.setTextColor(ui.text);
                cb.setChecked(def.equals("true") || def.equals("1"));
                inputs[i] = cb;
                box.addView(cb, ui.gap(6));
            } else if (type.equals("select")) {
                final JSONArray opts = p.optJSONArray("options") == null ? new JSONArray() : p.optJSONArray("options");
                final String[] labels = new String[opts.length()];
                final String[] values = new String[opts.length()];
                for (int k = 0; k < opts.length(); k++) {
                    Object o = opts.opt(k);
                    if (o instanceof JSONObject) {
                        values[k] = String.valueOf(((JSONObject) o).opt("value"));
                        labels[k] = ((JSONObject) o).optString("label", values[k]);
                    } else {
                        values[k] = String.valueOf(o);
                        labels[k] = values[k];
                    }
                    if (picked[i] == null && (def.isEmpty() || def.equals(values[k]))) {
                        picked[i] = values[k];
                    }
                }
                TextView l = ui.hint(lab + (hint.isEmpty() ? "" : " (" + hint + ")"));
                box.addView(l, ui.gap(10));
                final MaterialButton pick = ui.secondary("Escolher ▾", 0);
                for (int k = 0; k < values.length; k++) {
                    if (values[k].equals(picked[i])) {
                        pick.setText(labels[k] + "  ▾");
                    }
                }
                pick.setOnClickListener(v -> new MaterialAlertDialogBuilder(a).setTitle(lab)
                        .setItems(labels, (d, which) -> {
                            picked[idx] = values[which];
                            pick.setText(labels[which] + "  ▾");
                        }).show());
                inputs[i] = pick;
                box.addView(pick, Ui.matchWrap());
            } else {
                int it = InputType.TYPE_CLASS_TEXT;
                if (type.equals("int")) {
                    it = InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_SIGNED;
                } else if (type.equals("text")) {
                    it = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE;
                }
                String help = hint.isEmpty() ? (type.equals("pos") ? "x,y,z" : "") : hint;
                TextInputLayout f = ui.field(lab, help, def, it);
                inputs[i] = f;
                box.addView(f, ui.gap(10));
            }
        }
        final boolean risky = act.optBoolean("dangerous") || act.optBoolean("confirm");
        ScrollView sv = new ScrollView(a);
        sv.addView(box);
        final String title = act.optString("cat") + " › " + act.optString("name");
        androidx.appcompat.app.AlertDialog dlg = new MaterialAlertDialogBuilder(a).setTitle(act.optString("name"))
                .setView(sv).setNegativeButton("Cancelar", null).setPositiveButton("Executar", null).show();
        dlg.getButton(androidx.appcompat.app.AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            JSONObject data = new JSONObject();
            try {
                for (int i = 0; i < params.length(); i++) {
                    JSONObject p = params.optJSONObject(i);
                    if (p == null) {
                        continue;
                    }
                    String type = p.optString("type", "string");
                    String name = p.optString("name");
                    if (type.equals("bool")) {
                        data.put(name, ((CheckBox) inputs[i]).isChecked());
                    } else if (type.equals("select")) {
                        if (picked[i] != null) {
                            data.put(name, picked[i]);
                        }
                    } else {
                        TextInputLayout f = (TextInputLayout) inputs[i];
                        String val = Ui.value(f);
                        f.setError(null);
                        if (val.isEmpty()) {
                            if (p.optBoolean("required")) {
                                f.setError("Obrigatório.");
                                return;
                            }
                            continue;
                        }
                        if (type.equals("int")) {
                            try {
                                data.put(name, Long.parseLong(val));
                            } catch (NumberFormatException e) {
                                f.setError("Precisa ser um número inteiro.");
                                return;
                            }
                        } else {
                            data.put(name, val);
                        }
                    }
                }
            } catch (Exception e) {
                a.snack("Valor inválido: " + e.getMessage(), false);
                return;
            }
            dlg.dismiss();
            final String json = data.toString();
            Runnable go = () -> runAction(act.optString("id"), json, title);
            if (risky) {
                a.confirm(act.optBoolean("dangerous") ? "Ação perigosa" : "Confirmar",
                        "Executar " + title + "?\n\n" + json, "Executar", act.optBoolean("dangerous"), go);
            } else {
                go.run();
            }
        });
    }

    private void runAction(String id, String json, String title) {
        if (needActor()) {
            return;
        }
        result.running(title);
        a.remote(a.ctl("panel " + Ssh.sq(a.store.actor()) + " " + Ssh.sq(id) + " " + Ssh.sq(json)), 40, (r, e) -> {
            Friendly f = e != null ? Friendly.ofException(e) : Friendly.ofResult(r.out, r.code);
            if (f.ok) {
                try {
                    String t = r.out.trim();
                    JSONObject res = new JSONObject(t.substring(t.indexOf('{')));
                    StringBuilder sb = new StringBuilder(res.optString("message"));
                    JSONArray lines = res.optJSONArray("lines");
                    for (int i = 0; lines != null && i < lines.length(); i++) {
                        sb.append('\n').append(lines.optString(i));
                    }
                    f = res.optBoolean("ok") ? Friendly.ok("Feito", sb.toString().trim(), r.out)
                            : Friendly.fail("O jogo recusou", sb.toString().trim(), r.out);
                } catch (Exception ex) {
                    f = Friendly.ok("Feito", r.out.trim(), r.out);
                }
            }
            result.show(title, f);
            a.snack(title + ": " + (f.ok ? "feito" : f.title), f.ok);
        });
    }
}
