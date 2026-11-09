package com.cindersofchaos.admin;

import android.graphics.Typeface;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;

/**
 * Comandos > Ações rápidas > Conferir lançamento (O440, read only): chaos-ctl.sh launch-check reads the INSTALLED server
 * (beta switches, the beta coins cron, payments, test files, the clock zone, maxPlayers, the dates of Season 1 and the
 * Founder Pack, the client guard, the launch patch notes, counts of the database, the newest backup, the checkout) and
 * changes nothing. The card shows a one-line summary ("3 falhas, 2 avisos" or "Tudo certo para o lançamento") and the
 * lines with the failures first. The command exits 1 when a check fails, so the lines are read whatever the exit code
 * was. Reading and order: LaunchCheckInfo. docs/ADMIN_APP.md.
 */
final class LaunchCheckCard {
    final MaterialCardView card;
    private final MainActivity a;
    private final Ui ui;
    private final MaterialButton run;
    private final MaterialButton copy;
    private final TextView summary;
    private final TextView out;
    private String last = "";

    LaunchCheckCard(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        card = ui.titledCard("Conferir lançamento");
        LinearLayout b = Ui.body(card);
        b.addView(ui.hint("Lê o servidor instalado e não muda nada: o beta e o cron das moedas de teste desligados, "
                + "pagamentos sem mock, arquivos de teste, o fuso horário, as datas da Season 1 e do Founder Pack, a "
                + "chave do client, os patch notes, contagens do banco, o último backup e a versão instalada. As "
                + "falhas vêm primeiro."));
        run = ui.secondary("Conferir", R.drawable.ic_refresh);
        run.setOnClickListener(v -> load());
        b.addView(run, ui.gap(8));
        copy = ui.secondary("Copiar", R.drawable.ic_copy);
        copy.setEnabled(false);
        copy.setOnClickListener(v -> a.copy(last, "Copiado."));
        b.addView(copy, ui.gap(4));
        summary = ui.text("Toque em Conferir.");
        summary.setPadding(0, ui.dp(8), 0, 0);
        b.addView(summary);
        out = ui.text("");
        out.setTypeface(Typeface.MONOSPACE);
        out.setTextSize(12);
        out.setTextIsSelectable(true);
        b.addView(out, ui.gap(4));
    }

    private void load() {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        run.setEnabled(false);
        summary.setText("Conferindo…");
        out.setText("");
        a.remote(a.ctl(LaunchCheckInfo.COMMAND), 120, (r, e) -> {
            run.setEnabled(true);
            if (e != null || r == null) {
                Friendly f = Friendly.ofException(e != null ? e : new IllegalStateException("sem resposta"));
                summary.setText(f.title + ". " + f.detail);
                copy.setEnabled(false);
                return;
            }
            LaunchCheckInfo.Report rep = LaunchCheckInfo.parse(r.out);
            if (rep == null) {
                Friendly f = Friendly.ofResult(r.out, r.code);
                summary.setText(f.title + ". " + f.detail);
                out.setText(f.raw);
                copy.setEnabled(false);
                return;
            }
            last = LaunchCheckInfo.summary(rep) + "\n\n" + LaunchCheckInfo.render(rep);
            copy.setEnabled(true);
            summary.setText(LaunchCheckInfo.summary(rep));
            out.setText(LaunchCheckInfo.render(rep));
        });
    }
}
