package com.cindersofchaos.admin;

import android.graphics.Typeface;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.android.material.progressindicator.LinearProgressIndicator;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/** Painel: the server's state as cards, and the big buttons (start, stop, save, restart, timed restart, backup). */
final class PanelTab {
    final View root;
    private final MainActivity a;
    private final Ui ui;
    private final SwipeRefreshLayout swipe;

    private final TextView badge;
    private final TextView uptime;
    private final TextView updated;
    private final MaterialCardView notice;
    private final TextView noticeTitle;
    private final TextView noticeText;
    private final Tile players;
    private final Tile load;
    private final Tile mem;
    private final Tile disk;
    private final Tile backup;
    private final Tile errors;
    private final MainActivity.ResultCard result;
    private final UpdateCard update;
    private boolean updateSeen = false;
    private final List<MaterialButton> actionButtons = new ArrayList<>();
    private boolean loading = false;

    /** One number of the dashboard: a small label, a big value, an optional bar. */
    private final class Tile {
        final MaterialCardView card;
        final TextView value;
        final TextView sub;
        final LinearProgressIndicator bar;

        Tile(String label, boolean withBar) {
            card = ui.card();
            LinearLayout b = Ui.body(card);
            b.setPadding(ui.dp(14), ui.dp(12), ui.dp(14), ui.dp(12));
            TextView l = ui.heading(label);
            l.setPadding(0, 0, 0, ui.dp(4));
            l.setTextSize(11);
            b.addView(l);
            value = new TextView(a);
            value.setTextColor(ui.bright);
            value.setTextSize(20);
            value.setTypeface(Typeface.create(Typeface.SERIF, Typeface.BOLD));
            value.setText("·");
            b.addView(value);
            sub = ui.hint("");
            sub.setTextSize(12);
            sub.setVisibility(View.GONE);
            b.addView(sub);
            if (withBar) {
                bar = new LinearProgressIndicator(a);
                bar.setMax(100);
                bar.setTrackThickness(ui.dp(5));
                bar.setTrackCornerRadius(ui.dp(3));
                bar.setTrackColor(ui.iron0);
                bar.setIndicatorColor(ui.gold);
                b.addView(bar, ui.gap(8));
            } else {
                bar = null;
            }
        }

        void set(String v, String subText, int percent) {
            value.setText(v);
            sub.setText(subText == null ? "" : subText);
            sub.setVisibility(subText == null || subText.isEmpty() ? View.GONE : View.VISIBLE);
            if (bar != null) {
                bar.setVisibility(percent < 0 ? View.INVISIBLE : View.VISIBLE);
                if (percent >= 0) {
                    bar.setProgressCompat(percent, true);
                    bar.setIndicatorColor(percent >= 90 ? ui.ember : percent >= 75 ? ui.goldLight : ui.gold);
                }
            }
        }
    }

    PanelTab(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        LinearLayout page = ui.page();

        // ---- state
        MaterialCardView head = ui.card();
        LinearLayout hb = Ui.body(head);
        LinearLayout top = ui.row();
        TextView name = ui.title("Servidor do jogo");
        top.addView(name, Ui.weight(1f));
        badge = ui.badge("…", ui.muted);
        top.addView(badge);
        hb.addView(top);
        uptime = ui.text("Puxe para baixo para atualizar.");
        uptime.setPadding(0, ui.dp(8), 0, 0);
        hb.addView(uptime);
        updated = ui.hint("");
        updated.setTextSize(12);
        updated.setPadding(0, ui.dp(2), 0, 0);
        hb.addView(updated);
        page.addView(head, Ui.matchWrap());

        // ---- a problem that needs the owner (no unit, no connection)
        notice = ui.card();
        notice.setStrokeColor(ui.blood);
        notice.setCardBackgroundColor(ui.bloodDark);
        LinearLayout nb = Ui.body(notice);
        noticeTitle = ui.title("");
        noticeTitle.setTextSize(15);
        noticeTitle.setTextColor(ui.goldLight);
        noticeText = ui.text("");
        noticeText.setPadding(0, ui.dp(6), 0, 0);
        noticeText.setTextIsSelectable(true);
        nb.addView(noticeTitle);
        nb.addView(noticeText);
        notice.setVisibility(View.GONE);
        page.addView(notice, ui.gap(10));

        // ---- numbers
        players = new Tile("Jogadores", false);
        players.card.setOnClickListener(v -> showPlayers());
        load = new Tile("Carga (1 · 5 · 15 min)", false);
        mem = new Tile("Memória", true);
        disk = new Tile("Disco", true);
        backup = new Tile("Último backup", false);
        errors = new Tile("Erros desde o início", false);
        errors.card.setOnClickListener(v -> {
            a.showTab(MainActivity.TAB_LOGS, true);
            a.logs.openErrors();
        });
        page.addView(ui.evenRow(players.card, errors.card), ui.gap(10));
        page.addView(ui.evenRow(mem.card, disk.card), ui.gap(8));
        page.addView(ui.evenRow(load.card, backup.card), ui.gap(8));

        // ---- actions
        MaterialCardView actions = ui.titledCard("Ações");
        LinearLayout ab = Ui.body(actions);
        MaterialButton start = ui.big(ui.primary("Ligar", R.drawable.ic_play));
        start.setOnClickListener(v -> run("Ligar", "start", 90));
        MaterialButton stop = ui.big(ui.danger("Desligar", R.drawable.ic_stop));
        stop.setOnClickListener(v -> a.confirm("Desligar o servidor?",
                "O jogo salva todos e desconecta os jogadores. Ele só volta quando você tocar em Ligar.",
                "Desligar", true, () -> run("Desligar", "stop", 240)));
        MaterialButton save = ui.big(ui.secondary("Salvar", R.drawable.ic_save));
        save.setOnClickListener(v -> run("Salvar", "save", 30));
        MaterialButton restart = ui.big(ui.danger("Reiniciar", R.drawable.ic_restart));
        restart.setOnClickListener(v -> a.confirm("Reiniciar agora?",
                "Os jogadores são desconectados sem aviso (o jogo salva antes). Para avisar antes, use Reiniciar em…",
                "Reiniciar", true, () -> run("Reiniciar", "restart", 240)));
        MaterialButton later = ui.big(ui.secondary("Reiniciar em…", R.drawable.ic_timer));
        later.setOnClickListener(v -> restartLater());
        MaterialButton bk = ui.big(ui.secondary("Backup", R.drawable.ic_backup));
        bk.setOnClickListener(v -> a.confirm("Fazer backup agora?",
                "O jogo salva e o banco é copiado (pode levar alguns minutos). Os jogadores não são desconectados.",
                "Fazer backup", false, () -> run("Backup", "backup", 600)));
        actionButtons.add(start);
        actionButtons.add(stop);
        actionButtons.add(save);
        actionButtons.add(restart);
        actionButtons.add(later);
        actionButtons.add(bk);
        ab.addView(ui.evenRow(start, stop));
        ab.addView(ui.evenRow(save, restart), ui.gap(4));
        ab.addView(ui.evenRow(later, bk), ui.gap(4));
        page.addView(actions, ui.gap(10));

        result = a.new ResultCard();
        page.addView(result.card, ui.gap(10));

        update = new UpdateCard(a);
        page.addView(update.card, ui.gap(10));

        ScrollView sv = new ScrollView(a);
        sv.addView(page, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        swipe = new SwipeRefreshLayout(a);
        swipe.setColorSchemeColors(ui.gold, ui.ember);
        swipe.setProgressBackgroundColorSchemeColor(ui.iron3);
        swipe.addView(sv);
        swipe.setOnRefreshListener(() -> refresh(true));
        root = swipe;
    }

    /** Asks chaos-ctl.sh status; manual refreshes show failures, automatic ones only update the badge. */
    void refresh(boolean manual) {
        if (!a.store.configured()) {
            swipe.setRefreshing(false);
            showNotice("Falta configurar", "Preencha o endereço e gere a chave na aba Config.");
            return;
        }
        if (loading) {
            swipe.setRefreshing(false);
            return;
        }
        loading = true;
        a.remote(a.ctl("status"), 30, (r, e) -> {
            loading = false;
            swipe.setRefreshing(false);
            if (e != null) {
                Friendly f = Friendly.ofException(e);
                a.ui.setBadge(badge, "SEM CONEXÃO", ui.muted);
                showNotice(f.title, f.detail);
                if (manual) {
                    a.snack(f.title, false);
                }
                return;
            }
            StatusInfo s = StatusInfo.parse(r.out);
            if (!s.valid()) {
                Friendly f = Friendly.ofResult(r.out, r.code == 0 ? 1 : r.code);
                a.ui.setBadge(badge, "ERRO", ui.ember);
                showNotice(f.title, f.detail);
                return;
            }
            show(s);
            // once per app start (and on a manual refresh): an update still running is followed again
            if (!updateSeen || manual) {
                updateSeen = true;
                update.shown();
            }
        });
    }

    private void show(StatusInfo s) {
        long now = System.currentTimeMillis();
        String unit = s.get("unit").isEmpty() ? "chaos-server" : s.get("unit");
        hideNotice();
        switch (s.state()) {
            case ONLINE:
                ui.setBadge(badge, "NO AR", ui.ok);
                break;
            case ONLINE_NO_UNIT:
                ui.setBadge(badge, "NO AR · SEM SERVIÇO", ui.goldLight);
                showNotice("Rodando fora do systemd",
                        "O jogo está rodando (pid " + s.get("pid") + "), mas não pela unidade '" + unit + "'. Ligar, "
                                + "Desligar e Reiniciar só funcionam com a unidade instalada: "
                                + "server/deploy/chaos-trial-server.service como /etc/systemd/system/chaos-server.service, "
                                + "ou o nome certo em /etc/chaos/ctl.conf (CHAOS_UNIT=nome).");
                break;
            case STARTING:
                ui.setBadge(badge, "LIGANDO", ui.goldLight);
                break;
            case STOPPING:
                ui.setBadge(badge, "DESLIGANDO", ui.goldLight);
                break;
            case FAILED:
                ui.setBadge(badge, "FALHOU", ui.ember);
                showNotice("O serviço caiu", "O systemd marcou o servidor como falho. Veja os erros na aba Logs e "
                        + "toque em Ligar.");
                break;
            case NO_UNIT:
                ui.setBadge(badge, "SEM SERVIÇO", ui.ember);
                Friendly f = Friendly.ofResult("chaos-ctl: unit-not-found: the systemd unit " + unit
                        + " does not exist", 5);
                showNotice(f.title, f.detail);
                break;
            case OFFLINE:
                ui.setBadge(badge, "PARADO", ui.ember);
                break;
            default:
                ui.setBadge(badge, s.get("service").toUpperCase(Locale.ROOT), ui.muted);
        }
        long up = s.uptimeSec(now);
        Date since = s.since();
        boolean on = s.state() == StatusInfo.State.ONLINE;
        if (on && up >= 0 && since != null) {
            uptime.setText("No ar há " + Friendly.duration(up) + "  ·  desde "
                    + new SimpleDateFormat("dd/MM HH:mm", Locale.getDefault()).format(since));
        } else if (on) {
            uptime.setText("No ar.");
        } else if (s.state() == StatusInfo.State.ONLINE_NO_UNIT) {
            uptime.setText("Rodando pelo start-server.sh.");
        } else {
            uptime.setText("O servidor não está rodando.");
        }
        updated.setText("Unidade " + unit + "  ·  atualizado às "
                + new SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(new Date(now)));

        players.set(s.playersText(), s.playersText().equals("?") ? "banco indisponível" : "online agora", -1);
        int e = s.errors();
        errors.set(e < 0 ? "?" : String.valueOf(e), e > 0 ? "toque para ver" : "nenhum", -1);
        errors.value.setTextColor(e > 0 ? ui.ember : ui.bright);
        mem.set(s.memText(), null, s.memPercent());
        disk.set(s.diskText(), null, s.diskPercent());
        load.set(s.loadText(), null, -1);
        load.value.setTextSize(16);
        backup.set(s.backupText(), null, -1);
        backup.value.setTextSize(16);
    }

    private void showNotice(String title, String text) {
        notice.setVisibility(View.VISIBLE);
        noticeTitle.setText(title);
        noticeText.setText(text);
    }

    private void hideNotice() {
        notice.setVisibility(View.GONE);
    }

    private void run(String what, String args, int timeout) {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        setButtons(false);
        result.running(what);
        a.ctlAction(args, timeout, f -> {
            setButtons(true);
            result.show(what, f);
            a.snack(f.ok ? what + ": " + firstLine(f.detail) : what + ": " + f.title, f.ok);
            refresh(false);
        });
    }

    private void setButtons(boolean on) {
        for (MaterialButton b : actionButtons) {
            b.setEnabled(on);
            b.setAlpha(on ? 1f : 0.5f);
        }
    }

    private void restartLater() {
        final String[] labels = {"1 minuto", "2 minutos", "5 minutos", "10 minutos", "15 minutos"};
        final int[] secs = {60, 120, 300, 600, 900};
        new MaterialAlertDialogBuilder(a).setTitle("Reiniciar com aviso")
                .setItems(labels, (d, which) -> a.confirm("Reiniciar em " + labels[which] + "?",
                        "Os jogadores recebem o aviso agora e o servidor reinicia sozinho no fim da contagem (salvando "
                                + "todos).", "Agendar", true,
                        () -> run("Reiniciar em " + labels[which], "restart " + secs[which], 30)))
                .setNegativeButton("Cancelar", null).show();
    }

    private void showPlayers() {
        if (!a.store.configured()) {
            return;
        }
        a.ctlAction("players", 30, f -> {
            if (!f.ok) {
                result.show("Jogadores", f);
                a.snack(f.title, false);
                return;
            }
            List<String> rows = new ArrayList<>();
            for (String line : f.raw.split("\n")) {
                String[] p = line.split("\t");
                if (p.length >= 3) {
                    rows.add(p[0] + "\n" + "nível " + p[1] + "  ·  " + p[2]);
                } else if (!line.trim().isEmpty()) {
                    rows.add(line.trim());
                }
            }
            MaterialAlertDialogBuilder d = new MaterialAlertDialogBuilder(a)
                    .setTitle("Online agora (" + rows.size() + ")").setPositiveButton("Fechar", null);
            if (rows.isEmpty()) {
                d.setMessage("Ninguém online.");
            } else {
                d.setItems(rows.toArray(new String[0]), null);
            }
            d.show();
        });
    }

    private static String firstLine(String s) {
        int nl = s.indexOf('\n');
        return nl < 0 ? s : s.substring(0, nl);
    }
}
