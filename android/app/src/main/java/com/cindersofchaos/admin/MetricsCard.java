package com.cindersofchaos.admin;

import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.progressindicator.LinearProgressIndicator;

import java.util.List;

/**
 * Painel > Métricas dos jogadores (read only): chaos-ctl.sh metrics --json. Where players stop playing (churn by level
 * band), where and by what they die (top 10 areas and monsters), how long the first session lasts and the median time
 * to levels 10 / 25 / 50 / 100 / 200. The numbers are anonymous aggregate counters (server/README.md "Progress metrics
 * (O253)"): no names, accounts or IPs reach the phone. docs/ADMIN_APP.md. The funnel card (O258) shows the return per
 * cohort week, the first use of each system and where the gone characters stood, from the same report.
 */
final class MetricsCard {
    final MaterialCardView card;
    /** O258: the funnel card (return, first use, where they stop), filled by the same load. */
    final MaterialCardView funnelCard;
    private final TextView funnelNote;
    private final LinearLayout funnelOut;
    private final MainActivity a;
    private final Ui ui;
    private final TextView summary;
    private final MaterialButton load;
    private final LinearLayout out;

    MetricsCard(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        card = ui.titledCard("Métricas dos jogadores");
        LinearLayout b = Ui.body(card);
        b.addView(ui.hint("Contadores anônimos (sem nomes, contas nem IPs) para ajustar o balanceamento: onde os "
                + "jogadores param de jogar, onde e por quem morrem, quanto dura a primeira sessão e em quanto tempo "
                + "chegam aos níveis 10, 25, 50, 100 e 200. Só leitura; testers e GMs ficam de fora."));
        summary = ui.text("Toque em Atualizar.");
        summary.setPadding(0, ui.dp(8), 0, 0);
        b.addView(summary);
        load = ui.secondary("Atualizar métricas", R.drawable.ic_refresh);
        load.setOnClickListener(v -> load());
        b.addView(load, ui.gap(8));
        out = ui.column();
        b.addView(out, ui.gap(4));

        funnelCard = ui.titledCard("Funil dos jogadores");
        LinearLayout fb = Ui.body(funnelCard);
        fb.addView(ui.hint("Volta no dia 1, 3 e 7 por semana de entrada, retenção por dia de criação, quando cada sistema é usado pela primeira vez "
                + "e onde ficam os personagens que pararam. Contadores anônimos, só leitura; atualize no card de métricas."));
        funnelNote = ui.text("Toque em Atualizar métricas acima.");
        funnelNote.setPadding(0, ui.dp(8), 0, 0);
        fb.addView(funnelNote);
        funnelOut = ui.column();
        fb.addView(funnelOut, ui.gap(4));
    }

    private void load() {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        load.setEnabled(false);
        summary.setText("Lendo as métricas…");
        a.remote(a.ctl("metrics --json"), 60, (r, e) -> {
            load.setEnabled(true);
            if (e != null || r == null) {
                out.removeAllViews();
                Friendly f = Friendly.ofException(e != null ? e : new IllegalStateException("sem resposta"));
                summary.setText(f.title + ". " + f.detail);
                return;
            }
            MetricsInfo m = MetricsInfo.parse(r.out);
            out.removeAllViews();
            funnelOut.removeAllViews();
            if (m == null) {
                Friendly f = Friendly.ofResult(r.out, r.code);
                summary.setText(f.title + ". " + f.detail);
                return;
            }
            if (!m.ok) {
                summary.setText(m.errorText());
                funnelNote.setText(m.errorText());
                return;
            }
            show(m);
            showFunnel(m);
        });
    }

    private void show(MetricsInfo m) {
        if (m.empty) {
            summary.setText("Ainda não há dados. Os contadores se enchem com o jogo (a cada 5 minutos) e o retrato de "
                    + "abandono é feito 1 minuto depois de ligar o servidor e a cada 24 horas.");
            return;
        }
        boolean hidden = m.gone == MetricsInfo.SMALL || m.active == MetricsInfo.SMALL;
        long total = hidden ? 0 : m.gone + m.active;
        String when = MetricsInfo.when(m.churnAt);
        if (hidden) {
            summary.setText("Retrato de abandono" + (when.isEmpty() ? "" : " de " + when) + ": " + MetricsInfo.n(m.gone)
                    + " personagens sem entrar há mais de " + m.churnDays + " dias, " + MetricsInfo.n(m.active)
                    + " ativos (grupos com menos de 5 não são mostrados).");
        } else {
            summary.setText(total == 0 ? "Sem retrato de abandono ainda."
                    : "Retrato de abandono" + (when.isEmpty() ? "" : " de " + when) + ": " + m.gone + " de " + total
                    + " personagens sem entrar há mais de " + m.churnDays + " dias ("
                    + MetricsInfo.pct(100.0 * m.gone / total) + ").");
        }

        section("Onde os jogadores param (sem login há " + m.churnDays + "+ dias, por faixa de nível)");
        boolean any = false;
        for (MetricsInfo.Band x : m.bands) {
            if (x.gone == MetricsInfo.SMALL || x.active == MetricsInfo.SMALL || x.gonePct < 0) {
                any = true;
                bar("Nível " + x.band, 0, "<5 personagens", ui.text2);
                continue;
            }
            long t = x.gone + x.active;
            if (t == 0) {
                continue;
            }
            any = true;
            bar("Nível " + x.band, (int) Math.round(x.gonePct), MetricsInfo.pct(x.gonePct) + "  ·  " + x.gone + " de " + t,
                    x.gonePct >= 60 ? ui.warn : ui.text2);
        }
        if (!any) {
            note("Sem dados de abandono.");
        }

        killers("Onde morrem (10 áreas com mais mortes)", m.areas);
        killers("Quem mata (10 monstros com mais mortes)", m.monsters);

        section("Primeira sessão de um personagem novo (" + MetricsInfo.n(m.sessionCharacters) + ")");
        if (m.sessions.isEmpty()) {
            note("Sem dados.");
        }
        String prev = "";
        for (MetricsInfo.Bucket x : m.sessions) {
            bar(MetricsInfo.bucketText(x.bucket, prev), x.pct < 0 ? 0 : (int) Math.round(x.pct),
                    MetricsInfo.pct(x.pct) + "  ·  " + MetricsInfo.n(x.characters), ui.text2);
            if (!x.bucket.equals("inf")) {
                prev = x.bucket;
            }
        }

        section("Tempo mediano jogado até o nível");
        if (m.milestones.isEmpty()) {
            note("Sem dados.");
        }
        for (MetricsInfo.Milestone x : m.milestones) {
            TextView t = ui.text("Nível " + x.level + ":  " + MetricsInfo.minutes(x.medianMinutes) + "   ("
                    + MetricsInfo.n(x.characters) + (x.characters == 1 ? " personagem)" : " personagens)"));
            t.setPadding(0, ui.dp(2), 0, ui.dp(2));
            out.addView(t);
        }
    }

    /** O258: return per cohort week, first use of each system, and the areas where the gone characters stood last. */
    private void showFunnel(MetricsInfo m) {
        boolean any = !m.weeks.isEmpty() || !m.firstUses.isEmpty() || !m.stops.isEmpty() || !m.cohortDays.isEmpty();
        funnelNote.setText(any ? "Dados do servidor (grupos com menos de 5 não são mostrados)."
                : "Ainda não há dados do funil. Eles se enchem com o jogo.");
        funnelSection("Volta por semana de entrada (dia 1 / 3 / 7 ou depois)");
        if (m.weeks.isEmpty()) {
            funnelOut.addView(ui.hint("Sem dados."));
        }
        String[] days = {"dia 1", "dia 3", "dia 7"};
        for (MetricsInfo.Week w : m.weeks) {
            StringBuilder sb = new StringBuilder();
            for (int k = 0; k < 3; k++) {
                sb.append(days[k]).append(": ").append(MetricsInfo.n(w.back[k])).append(" (")
                        .append(w.pct[k] < 0 ? "—" : MetricsInfo.pct(w.pct[k])).append(")");
                if (k < 2) {
                    sb.append("  ·  ");
                }
            }
            TextView head = ui.text("Semana de " + w.week + ":  " + MetricsInfo.n(w.cohort) + " novos");
            head.setPadding(0, ui.dp(4), 0, 0);
            funnelOut.addView(head);
            TextView v = ui.hint(sb.toString());
            v.setTextSize(12);
            funnelOut.addView(v);
        }
        showRetention(m);
        funnelSection("Primeiro uso de cada sistema");
        if (m.firstUses.isEmpty()) {
            funnelOut.addView(ui.hint("Sem dados."));
        }
        for (MetricsInfo.FirstUse f : m.firstUses) {
            funnelBar(MetricsInfo.systemName(f.system), f.pct < 0 ? 0 : (int) Math.round(f.pct),
                    MetricsInfo.n(f.characters) + " personagens" + (f.pct < 0 ? "" : "  ·  " + MetricsInfo.pct(f.pct))
                            + (f.medianMinutes < 0 ? "" : "  ·  mediana " + MetricsInfo.minutes(f.medianMinutes))
                            + (f.topBand.isEmpty() ? "" : "  ·  mais no nível " + f.topBand));
        }
        funnelSection("Onde pararam (últimos locais, 10 áreas com mais personagens)");
        if (m.stops.isEmpty()) {
            funnelOut.addView(ui.hint("Sem dados."));
            return;
        }
        long max = 0;
        for (MetricsInfo.Killer k : m.stops) {
            max = Math.max(max, k.deaths);
        }
        for (MetricsInfo.Killer k : m.stops) {
            funnelBar(k.name, MetricsInfo.percent(k.deaths, max),
                    MetricsInfo.n(k.deaths) + " personagens" + (k.topBand.isEmpty() ? "" : "  ·  mais no nível " + k.topBand));
        }
    }

    /**
     * O437: return by creation day. Day 1 is the next calendar day (server time); "algum dia de 1-7 / 1-30" is at
     * least one login in that range. A percent shows only for a finished window on a day the counters covered.
     */
    private void showRetention(MetricsInfo m) {
        funnelSection("Retenção por dia de criação (dia 1, dias 2-7, dias 8-30)");
        if (m.cohortDays.isEmpty()) {
            funnelOut.addView(ui.hint("Sem dados."));
            return;
        }
        funnelOut.addView(ui.hint("Cada personagem conta uma vez por janela. Dia 1 é o dia seguinte à criação; "
                + "dia 1 + dias 2-7 não é igual a \"algum dia de 1-7\" (o mesmo personagem pode estar nos dois). "
                + "Porcentagem só com a janela terminada e a partir de "
                + (m.retainSince.isEmpty() ? "o início da contagem" : MetricsInfo.dayText(m.retainSince)) + "."));
        if (!m.retainTotals.isEmpty()) {
            StringBuilder sb = new StringBuilder("Total dos dias com janela terminada: ");
            for (int i = 0; i < m.retainTotals.size(); i++) {
                MetricsInfo.RetainTotal t = m.retainTotals.get(i);
                if (i > 0) {
                    sb.append("  ·  ");
                }
                sb.append(MetricsInfo.retainLabel(t.window)).append(" ")
                        .append(t.pct < 0 ? "—" : MetricsInfo.pct(t.pct));
            }
            TextView tot = ui.text(sb.toString());
            tot.setTextSize(13);
            tot.setPadding(0, ui.dp(4), 0, ui.dp(4));
            funnelOut.addView(tot);
        }
        for (int i = m.cohortDays.size() - 1; i >= 0; i--) {
            MetricsInfo.CohortDay c = m.cohortDays.get(i);
            StringBuilder sb = new StringBuilder();
            for (int k = 0; k < MetricsInfo.RETAIN_KEYS.length; k++) {
                if (k > 0) {
                    sb.append("  ·  ");
                }
                sb.append(MetricsInfo.RETAIN_LABELS[k]).append(": ").append(MetricsInfo.n(c.back[k])).append(" (")
                        .append(c.pct[k] < 0 ? "—" : MetricsInfo.pct(c.pct[k])).append(")");
            }
            TextView head = ui.text(MetricsInfo.dayText(c.day) + ":  " + MetricsInfo.n(c.cohort) + " novos"
                    + (c.covered ? "" : "  (parcial: antes da contagem)"));
            head.setPadding(0, ui.dp(4), 0, 0);
            funnelOut.addView(head);
            TextView v = ui.hint(sb.toString());
            v.setTextSize(12);
            funnelOut.addView(v);
        }
    }

    private void funnelSection(String title) {
        funnelOut.addView(new View(a), ui.gap(12));
        TextView h = ui.heading(title);
        h.setTextSize(13);
        funnelOut.addView(h);
    }

    private void funnelBar(String label, int percent, String value) {
        LinearLayout row = ui.column();
        row.setPadding(0, ui.dp(4), 0, ui.dp(4));
        TextView l = ui.text(label);
        l.setTextSize(13);
        row.addView(l);
        LinearProgressIndicator bar = new LinearProgressIndicator(a);
        bar.setMax(100);
        bar.setTrackThickness(ui.dp(4));
        bar.setTrackCornerRadius(ui.dp(2));
        bar.setTrackColor(ui.input);
        bar.setIndicatorColor(ui.text2);
        bar.setProgressCompat(Math.max(0, Math.min(100, percent)), false);
        row.addView(bar, ui.gap(4));
        TextView v = ui.hint(value);
        v.setTextSize(12);
        row.addView(v);
        funnelOut.addView(row);
    }

    private void killers(String title, List<MetricsInfo.Killer> list) {
        section(title);
        if (list.isEmpty()) {
            note("Sem mortes registradas.");
            return;
        }
        long max = list.get(0).deaths;
        for (MetricsInfo.Killer k : list) {
            max = Math.max(max, k.deaths);
        }
        for (MetricsInfo.Killer k : list) {
            bar(k.name, MetricsInfo.percent(k.deaths, max),
                    MetricsInfo.n(k.deaths) + (k.deaths == 1 ? " morte" : " mortes")
                            + (k.topBand.isEmpty() ? "" : "  ·  mais no nível " + k.topBand), ui.text2);
        }
    }

    private void section(String title) {
        View gap = new View(a);
        out.addView(gap, ui.gap(12));
        TextView h = ui.heading(title);
        h.setTextSize(13);
        out.addView(h);
    }

    private void note(String s) {
        out.addView(ui.hint(s));
    }

    /** One row of a bar list: a label, a bar from 0 to 100 and a value text under it. */
    private void bar(String label, int percent, String value, int color) {
        LinearLayout row = ui.column();
        row.setPadding(0, ui.dp(4), 0, ui.dp(4));
        TextView l = ui.text(label);
        l.setTextSize(13);
        row.addView(l);
        LinearProgressIndicator bar = new LinearProgressIndicator(a);
        bar.setMax(100);
        bar.setTrackThickness(ui.dp(4));
        bar.setTrackCornerRadius(ui.dp(2));
        bar.setTrackColor(ui.input);
        bar.setIndicatorColor(color);
        bar.setProgressCompat(Math.max(0, Math.min(100, percent)), false);
        row.addView(bar, ui.gap(4));
        TextView v = ui.hint(value);
        v.setTextSize(12);
        row.addView(v);
        out.addView(row);
    }
}
