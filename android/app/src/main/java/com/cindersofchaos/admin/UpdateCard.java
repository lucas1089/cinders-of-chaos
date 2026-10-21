package com.cindersofchaos.admin;

import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.checkbox.MaterialCheckBox;
import com.google.android.material.progressindicator.LinearProgressIndicator;

/**
 * Painel > Atualizar servidor: chaos-ctl.sh update-check (what GitHub has that the server does not), update-apply
 * (the update with a restart, then the client update, the site's downloads and the site) and update-rollback, with
 * the progress read from update-log every 4 seconds until its RESULT line. docs/ADMIN_APP.md.
 */
final class UpdateCard {
    final MaterialCardView card;
    private final MainActivity a;
    private final Ui ui;
    private final TextView summary;
    private final TextView last;
    private final MaterialCheckBox client;
    private final MaterialCheckBox downloads;
    private final MaterialCheckBox site;
    private final MaterialButton check;
    private final MaterialButton apply;
    private final MaterialButton rollback;
    private final LinearLayout prog;
    private final TextView stepText;
    private final LinearProgressIndicator bar;
    private final TextView tail;
    private final MainActivity.ResultCard result;
    private boolean polling = false;
    private String what = "Atualização";

    UpdateCard(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        card = ui.titledCard("Atualizar servidor");
        LinearLayout b = Ui.body(card);
        b.addView(ui.hint("Busca no GitHub o código novo e a release mais nova (winpkg-N). Se houver, faz backup, "
                + "instala, reinicia e confere se o servidor ligou; se não ligar, volta sozinho para a versão anterior. "
                + "As taxas de XP do config.lua são mantidas."));
        summary = ui.text("Toque em Verificar.");
        summary.setPadding(0, ui.dp(8), 0, 0);
        summary.setTextIsSelectable(true);
        b.addView(summary);
        last = ui.hint("");
        last.setTextSize(12);
        last.setPadding(0, ui.dp(4), 0, 0);
        last.setVisibility(View.GONE);
        b.addView(last);

        client = box("Publicar o update do client (quando a release é mais nova)");
        downloads = box("Trocar os downloads do site (Windows e Linux)");
        site = box("Reinstalar o site se o código dele mudou");
        b.addView(client, ui.gap(6));
        b.addView(downloads);
        b.addView(site);

        check = ui.secondary("Verificar", R.drawable.ic_refresh);
        check.setOnClickListener(v -> check());
        apply = ui.danger("Aplicar e reiniciar", R.drawable.ic_restart);
        apply.setOnClickListener(v -> confirmApply());
        b.addView(ui.evenRow(check, apply), ui.gap(8));
        rollback = ui.flat("Voltar à versão anterior", 0);
        rollback.setOnClickListener(v -> a.confirm("Voltar à versão anterior?",
                "O servidor desliga (os jogadores são desconectados), volta o engine, o config.lua, o data/ e o código "
                        + "de antes da última atualização, e liga de novo. Os downloads do site voltam também. O banco "
                        + "não é mexido.", "Voltar", true, () -> start("update-rollback", "Voltar versão")));
        b.addView(rollback, ui.gap(2));

        prog = ui.column();
        stepText = ui.text("");
        stepText.setTextColor(ui.goldLight);
        prog.addView(stepText);
        bar = new LinearProgressIndicator(a);
        bar.setMax(100);
        bar.setTrackThickness(ui.dp(5));
        bar.setTrackCornerRadius(ui.dp(3));
        bar.setTrackColor(ui.iron0);
        bar.setIndicatorColor(ui.gold);
        prog.addView(bar, ui.gap(6));
        tail = ui.mono("");
        tail.setBackgroundColor(ui.iron0);
        tail.setPadding(ui.dp(8), ui.dp(6), ui.dp(8), ui.dp(6));
        tail.setTextSize(11);
        prog.addView(tail, ui.gap(6));
        prog.setVisibility(View.GONE);
        b.addView(prog, ui.gap(8));

        result = a.new ResultCard();
        b.addView(result.card, ui.gap(8));
    }

    private MaterialCheckBox box(String label) {
        MaterialCheckBox c = new MaterialCheckBox(a);
        c.setText(label);
        c.setTextColor(ui.text);
        c.setChecked(true);
        return c;
    }

    /** The panel came on screen: pick up an update that is still running. */
    void shown() {
        if (polling || !a.store.configured()) {
            return;
        }
        a.ctlAction("update-status", 30, f -> {
            UpdateInfo u = UpdateInfo.parse(f.raw);
            if (f.ok && u.running()) {
                what = "Atualização";
                prog.setVisibility(View.VISIBLE);
                poll();
            } else if (f.ok && !u.lastRun().isEmpty()) {
                last.setText(u.lastRun());
                last.setVisibility(View.VISIBLE);
            }
        });
    }

    private void check() {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        check.setEnabled(false);
        summary.setText("Perguntando ao GitHub…");
        a.ctlAction("update-check", 120, f -> {
            check.setEnabled(true);
            UpdateInfo u = UpdateInfo.parse(f.raw);
            if (!f.ok || !u.valid()) {
                summary.setText(f.ok ? "Resposta inesperada do servidor." : f.title + ". " + f.detail);
                return;
            }
            summary.setText((u.available() ? "Há atualização.\n\n" : "Tudo em dia.\n\n") + u.summary());
            String lr = u.lastRun();
            last.setText(lr);
            last.setVisibility(lr.isEmpty() ? View.GONE : View.VISIBLE);
            if (u.running() && !polling) {
                prog.setVisibility(View.VISIBLE);
                poll();
            }
        });
    }

    private void confirmApply() {
        a.confirm("Aplicar a atualização agora?",
                "O servidor é desligado e ligado de novo: todos os jogadores são desconectados (o jogo salva antes). "
                        + "Leva alguns minutos (backup, instalação, carga do mapa). Se a versão nova não ligar, o "
                        + "servidor volta sozinho para a anterior.", "Aplicar e reiniciar", true, () -> {
                    StringBuilder args = new StringBuilder("update-apply");
                    if (!client.isChecked()) {
                        args.append(" --no-client");
                    }
                    if (!downloads.isChecked()) {
                        args.append(" --no-downloads");
                    }
                    if (!site.isChecked()) {
                        args.append(" --no-site");
                    }
                    start(args.toString(), "Atualização");
                });
    }

    private void start(String args, String label) {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        what = label;
        setButtons(false);
        result.running(label);
        a.ctlAction(args, 30, f -> {
            if (!f.ok) {
                setButtons(true);
                result.show(label, f);
                a.snack(label + ": " + f.title, false);
                return;
            }
            result.card.setVisibility(View.GONE);
            prog.setVisibility(View.VISIBLE);
            stepText.setText("Começou…");
            bar.setProgressCompat(0, false);
            tail.setText("");
            poll();
        });
    }

    private void poll() {
        polling = true;
        setButtons(false);
        a.remote(a.ctl("update-log 200"), 40, (r, e) -> {
            if (e != null || r == null) {
                stepText.setText("Sem conexão; tentando de novo…");
                a.main.postDelayed(this::poll, 8000);
                return;
            }
            UpdateInfo.Progress p = UpdateInfo.progress(r.out);
            if (p.steps > 0) {
                stepText.setText("Passo " + p.step + " de " + p.steps + ": " + UpdateInfo.stepWord(p.name));
                bar.setProgressCompat(Math.min(100, (p.step - 1) * 100 / p.steps + (p.status.isEmpty() ? 5 : 100 / p.steps)),
                        true);
            }
            tail.setText(lastLines(r.out, 6));
            if (p.status.isEmpty()) {
                a.main.postDelayed(this::poll, 4000);
                return;
            }
            polling = false;
            setButtons(true);
            bar.setProgressCompat(100, true);
            bar.setIndicatorColor(p.status.equals("ok") ? ui.ok : p.status.equals("warn") ? ui.goldLight : ui.ember);
            boolean ok = p.status.equals("ok") || p.status.equals("warn");
            Friendly f = ok ? Friendly.ok(UpdateInfo.statusWord(p.status), UpdateInfo.resultText(p), r.out.trim())
                    : Friendly.fail(UpdateInfo.statusWord(p.status), UpdateInfo.resultText(p), r.out.trim());
            result.show(what, f);
            a.snack(what + ": " + UpdateInfo.statusWord(p.status), ok);
            a.panel.refresh(false);
        });
    }

    private void setButtons(boolean on) {
        for (MaterialButton btn : new MaterialButton[]{apply, rollback}) {
            btn.setEnabled(on);
            btn.setAlpha(on ? 1f : 0.5f);
        }
    }

    private static String lastLines(String s, int n) {
        String[] lines = s.trim().split("\n");
        StringBuilder b = new StringBuilder();
        for (int i = Math.max(0, lines.length - n); i < lines.length; i++) {
            b.append(lines[i]).append('\n');
        }
        return b.toString().trim();
    }
}
