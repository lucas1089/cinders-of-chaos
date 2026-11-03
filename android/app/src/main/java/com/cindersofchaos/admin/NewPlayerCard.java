package com.cindersofchaos.admin;

import android.graphics.Typeface;
import android.text.InputType;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.textfield.TextInputLayout;

/**
 * Painel > Novos jogadores (O374, read only): chaos-ctl.sh newplayer-funnel --pt (of the characters created in the last
 * N days: levels 10 / 20 / 30 / 50 / 100 reached, hours played, and where the ones with no login for 7+ days stopped:
 * level, played minutes, last system) and chaos-ctl.sh survey --pt (the in-game survey of level 20 and 50: fun score,
 * would recommend, the "what confused you" texts). Plain text from the server, no names, accounts or IPs. "Copiar"
 * puts the report on the clipboard to paste into a chat with Claude. Command lines: NewPlayerInfo. docs/ADMIN_APP.md.
 */
final class NewPlayerCard {
    final MaterialCardView card;
    private final MainActivity a;
    private final Ui ui;
    private final TextInputLayout days;
    private final MaterialButton funnel;
    private final MaterialButton survey;
    private final MaterialButton copy;
    private final TextView summary;
    private final TextView out;
    private String last = "";

    NewPlayerCard(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        card = ui.titledCard("Novos jogadores");
        LinearLayout b = Ui.body(card);
        b.addView(ui.hint("Funil: dos personagens criados no período, quantos chegaram aos níveis 10, 20, 30, 50 e 100 e "
                + "jogaram 1, 5 e 10 horas; dos que pararam (sem login há 7 dias ou mais), em que nível, depois de quantos "
                + "minutos e depois de qual sistema. Pesquisa: as respostas da janela dos níveis 20 e 50 (diversão de 1 a 5, "
                + "recomendaria, o que confundiu). Sem nomes, contas nem IPs; grupos com menos de 5 não são mostrados no funil."));
        days = ui.field("Últimos dias", "1 a 3650.", String.valueOf(NewPlayerInfo.DEFAULT_DAYS), InputType.TYPE_CLASS_NUMBER);
        b.addView(days, ui.gap(8));
        funnel = ui.secondary("Funil", R.drawable.ic_refresh);
        funnel.setOnClickListener(v -> load(true));
        survey = ui.secondary("Pesquisa", R.drawable.ic_refresh);
        survey.setOnClickListener(v -> load(false));
        b.addView(ui.evenRow(funnel, survey), ui.gap(8));
        copy = ui.secondary("Copiar", R.drawable.ic_copy);
        copy.setEnabled(false);
        copy.setOnClickListener(v -> a.copy(last, "Copiado: cole no Claude."));
        b.addView(copy, ui.gap(4));
        summary = ui.text("Toque em Funil ou Pesquisa.");
        summary.setPadding(0, ui.dp(8), 0, 0);
        b.addView(summary);
        out = ui.text("");
        out.setTypeface(Typeface.MONOSPACE);
        out.setTextSize(12);
        out.setTextIsSelectable(true);
        b.addView(out, ui.gap(4));
    }

    private void load(boolean isFunnel) {
        int d = NewPlayerInfo.days(Ui.value(days));
        if (d < 0) {
            days.setError("Digite de 1 a 3650.");
            return;
        }
        days.setError(null);
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        funnel.setEnabled(false);
        survey.setEnabled(false);
        summary.setText(isFunnel ? "Lendo o funil…" : "Lendo a pesquisa…");
        String cmd = isFunnel ? NewPlayerInfo.funnelArgs(d) : NewPlayerInfo.surveyArgs(d);
        a.remote(a.ctl(cmd), 60, (r, e) -> {
            funnel.setEnabled(true);
            survey.setEnabled(true);
            if (e != null || r == null) {
                Friendly f = Friendly.ofException(e != null ? e : new IllegalStateException("sem resposta"));
                summary.setText(f.title + ". " + f.detail);
                return;
            }
            String text = NewPlayerInfo.clean(r.out);
            if (r.code != 0) {
                out.setText(text);
                Friendly f = Friendly.ofResult(r.out, r.code);
                summary.setText(text.startsWith("Erro: no-table")
                        ? "A tabela ainda não existe: rode o passo sql do install_all.py (ou reinicie o servidor)."
                        : f.title + ". " + f.detail);
                copy.setEnabled(false);
                return;
            }
            last = text;
            copy.setEnabled(!text.isEmpty());
            summary.setText(NewPlayerInfo.headline(text));
            out.setText(text);
        });
    }
}
