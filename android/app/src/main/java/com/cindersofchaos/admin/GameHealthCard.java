package com.cindersofchaos.admin;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.text.InputType;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.progressindicator.LinearProgressIndicator;
import com.google.android.material.textfield.TextInputLayout;

import java.util.List;
import java.util.Locale;

/**
 * Painel > Saúde do jogo (O397, read only): chaos-ctl.sh game-health --kv --pt. Characters online per hour of the last
 * N days (a bar per hour, mean and peak), the mean per hour of the day, deaths per hour, the most and least used hunts,
 * gold in and out, and the new player funnel of the last 30 days (O374). Aggregate telemetry only: no names, accounts
 * or IPs; counts of 1 to 4 characters show as "<5".
 * Painel > Relatório de equilíbrio (O398): chaos-ctl.sh balance-report (classes compared over the last N days or the
 * current season, with suggested changes), "Enviar por DM" (saved on the server and sent to the owner by the Discord
 * bot), the newest saved report, and the daily timer that writes it when a season ends. Command lines and parsing:
 * GameHealthInfo. docs/ADMIN_APP.md.
 */
final class GameHealthCard {
    private static final Locale PT = Locale.forLanguageTag("pt-BR");
    final MaterialCardView card;
    final MaterialCardView balanceCard;
    private final MainActivity a;
    private final Ui ui;
    private final TextInputLayout days;
    private final MaterialButton load;
    private final TextView summary;
    private final LinearLayout out;
    private final TextInputLayout bDays;
    private final MaterialButton bRun;
    private final MaterialButton bSeason;
    private final MaterialButton bDm;
    private final MaterialButton bLast;
    private final MaterialButton bTimerOn;
    private final MaterialButton bTimerOff;
    private final MaterialButton bCopy;
    private final TextView bSummary;
    private final TextView bOut;
    private String bText = "";

    /** Bars of equal width, one per value (-1: no sample, drawn as a gap), scaled to max. */
    static final class Bars extends View {
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint base = new Paint();
        private double[] values = new double[0];
        private double max = 1;

        Bars(Context c, int color, int baseColor) {
            super(c);
            fill.setColor(color);
            base.setColor(baseColor);
        }

        void set(double[] v, double m) {
            values = v;
            max = Math.max(1, m);
            invalidate();
        }

        @Override
        protected void onDraw(Canvas c) {
            super.onDraw(c);
            int w = getWidth();
            int h = getHeight();
            c.drawRect(0, h - 2, w, h, base);
            if (values.length == 0) {
                return;
            }
            float step = (float) w / values.length;
            float gap = step > 4 ? 1 : 0;
            for (int i = 0; i < values.length; i++) {
                if (values[i] < 0) {
                    continue;
                }
                float top = (float) (h - 2 - (h - 4) * Math.min(1, values[i] / max));
                c.drawRect(i * step, top, (i + 1) * step - gap, h - 2, fill);
            }
        }
    }

    GameHealthCard(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        card = ui.titledCard("Saúde do jogo");
        LinearLayout b = Ui.body(card);
        b.addView(ui.hint("Jogadores online por hora, mortes por hora, as hunts mais e menos usadas, o ouro que entra e "
                + "sai, e onde os novos jogadores param. Números agregados da telemetria (sem nomes, contas nem IPs); "
                + "grupos com menos de 5 personagens aparecem como <5. Só leitura."));
        days = ui.field("Últimos dias", "1 a 90.", String.valueOf(GameHealthInfo.DEFAULT_DAYS), InputType.TYPE_CLASS_NUMBER);
        b.addView(days, ui.gap(8));
        load = ui.secondary("Atualizar saúde do jogo", R.drawable.ic_refresh);
        load.setOnClickListener(v -> load());
        b.addView(load, ui.gap(8));
        summary = ui.text("Toque em Atualizar.");
        summary.setPadding(0, ui.dp(8), 0, 0);
        b.addView(summary);
        out = ui.column();
        b.addView(out, ui.gap(4));

        balanceCard = ui.titledCard("Relatório de equilíbrio");
        LinearLayout bb = Ui.body(balanceCard);
        bb.addView(ui.hint("Compara as classes por faixa de nível: minutos por nível, mortes por hora de caça, dano por "
                + "hora e os feitiços mais usados, e sugere mudanças para quem passa de 15% da mediana. Enviar por DM "
                + "guarda o relatório no servidor e o bot do Discord manda para você. Com o automático ligado, o "
                + "relatório da season sai sozinho no dia seguinte ao fim dela."));
        bDays = ui.field("Últimos dias", "1 a 730.", String.valueOf(GameHealthInfo.BALANCE_DAYS),
                InputType.TYPE_CLASS_NUMBER);
        bb.addView(bDays, ui.gap(8));
        bRun = ui.secondary("Últimos dias", R.drawable.ic_refresh);
        bRun.setOnClickListener(v -> balanceDays(false));
        bSeason = ui.secondary("Season atual", R.drawable.ic_refresh);
        bSeason.setOnClickListener(v -> balance(GameHealthInfo.balanceSeasonArgs(false), "Lendo a season…"));
        bb.addView(ui.evenRow(bRun, bSeason), ui.gap(8));
        bDm = ui.secondary("Enviar por DM", R.drawable.ic_send);
        bDm.setOnClickListener(v -> balanceDays(true));
        bLast = ui.secondary("Último salvo", R.drawable.ic_save);
        bLast.setOnClickListener(v -> balance(GameHealthInfo.balanceLastArgs(), "Lendo o último relatório…"));
        bb.addView(ui.evenRow(bDm, bLast), ui.gap(4));
        bTimerOn = ui.secondary("Ligar automático", R.drawable.ic_timer);
        bTimerOn.setOnClickListener(v -> balance(GameHealthInfo.balanceTimerArgs("on"), "Ligando…"));
        bTimerOff = ui.secondary("Desligar", R.drawable.ic_stop);
        bTimerOff.setOnClickListener(v -> balance(GameHealthInfo.balanceTimerArgs("off"), "Desligando…"));
        bb.addView(ui.evenRow(bTimerOn, bTimerOff), ui.gap(4));
        bCopy = ui.secondary("Copiar", R.drawable.ic_copy);
        bCopy.setEnabled(false);
        bCopy.setOnClickListener(v -> a.copy(bText, "Copiado: cole no Claude."));
        bb.addView(bCopy, ui.gap(4));
        bSummary = ui.text("Toque em Últimos dias ou Season atual.");
        bSummary.setPadding(0, ui.dp(8), 0, 0);
        bb.addView(bSummary);
        bOut = ui.text("");
        bOut.setTypeface(Typeface.MONOSPACE);
        bOut.setTextSize(12);
        bOut.setTextIsSelectable(true);
        bb.addView(bOut, ui.gap(4));
    }

    // ------------------------------------------------------------------------------------------------ health
    private void load() {
        int d = GameHealthInfo.days(Ui.value(days), GameHealthInfo.MAX_DAYS);
        if (d < 0) {
            days.setError("Digite de 1 a 90.");
            return;
        }
        days.setError(null);
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        load.setEnabled(false);
        summary.setText("Lendo a saúde do jogo…");
        a.remote(a.ctl(GameHealthInfo.healthArgs(d)), 90, (r, e) -> {
            load.setEnabled(true);
            out.removeAllViews();
            if (e != null || r == null) {
                Friendly f = Friendly.ofException(e != null ? e : new IllegalStateException("sem resposta"));
                summary.setText(f.title + ". " + f.detail);
                return;
            }
            GameHealthInfo g = GameHealthInfo.parse(r.out);
            if (g == null) {
                Friendly f = Friendly.ofResult(r.out, r.code == 0 ? 1 : r.code);
                summary.setText(f.title + ". " + f.detail);
                return;
            }
            summary.setText(g.headline());
            if (g.ok) {
                show(g);
            }
        });
    }

    private void show(GameHealthInfo g) {
        section("Online por hora (últimos " + g.days + " dias; barras = média de cada hora)");
        double[] v = new double[g.hours.size()];
        for (int i = 0; i < v.length; i++) {
            v[i] = g.hours.get(i).mean;
        }
        chart(v, g.maxPeak(), ui.ember);
        if (!g.hours.isEmpty()) {
            note(g.hours.get(0).day + " a " + g.hours.get(g.hours.size() - 1).day + ", hora do servidor. Pico: "
                    + g.onlinePeak + " em " + g.onlinePeakAt + ". Vazios: horas sem amostra (servidor fora).");
        }
        section("Média por hora do dia (0h a 23h)");
        double[] hod = g.byHourOfDay();
        double hmax = 1;
        for (double x : hod) {
            hmax = Math.max(hmax, x);
        }
        chart(hod, hmax, ui.text2);
        note("Mais cheia: " + hourText(g.busiestHour) + ". Mais vazia: " + hourText(g.quietestHour) + ".");

        section("Mortes por hora (" + g.deathsTotal + " no período; " + g.deathsPerHour.replace('.', ',')
                + " por hora, " + g.deathsPerPlayHour.replace('.', ',') + " por hora de jogo)");
        double[] dv = new double[g.hours.size()];
        double dmax = 1;
        for (int i = 0; i < dv.length; i++) {
            dv[i] = g.hours.get(i).deaths;
            dmax = Math.max(dmax, dv[i]);
        }
        chart(dv, dmax, ui.warn);

        section("Hunts mais usadas (" + g.huntsKnown + " conhecidas, " + g.huntsUnvisited + " sem visita)");
        hunts(g.top, "Ainda sem amostras de caça: a tabela se enche a partir desta atualização.");
        section("Hunts menos usadas");
        hunts(g.low, "Sem dados.");

        section("Ouro: entrou " + GameHealthInfo.gold(g.goldIn) + ", saiu " + GameHealthInfo.gold(g.goldOut)
                + ", saldo " + GameHealthInfo.gold(g.goldNet));
        long gmax = 1;
        for (GameHealthInfo.Row r : g.gold) {
            gmax = Math.max(gmax, r.count);
        }
        for (GameHealthInfo.Row r : g.gold) {
            bar(r.label, (int) (100 * r.count / gmax), GameHealthInfo.gold(r.count) + " ouro  ·  " + r.extra + " vezes",
                    ui.gold);
        }
        if (g.gold.isEmpty()) {
            note("Sem movimento de ouro registrado.");
        }

        section("Novos jogadores (últimos " + g.funnelDays + " dias): " + g.funnelCharacters + " personagens");
        for (GameHealthInfo.Row r : g.reached) {
            bar(r.label, r.pct < 0 ? 0 : (int) Math.round(r.pct), GameHealthInfo.n(r.count) + " personagens"
                    + (r.pct < 0 ? "" : "  ·  " + GameHealthInfo.pct(r.pct)), ui.text2);
        }
        if (!g.funnelStopped.isEmpty()) {
            note("Pararam (sem login há 7+ dias): " + g.funnelStopped + ".");
        }
        for (GameHealthInfo.Row r : g.stopLevel) {
            bar("Pararam no " + r.label.toLowerCase(PT), r.pct < 0 ? 0 : (int) Math.round(r.pct),
                    GameHealthInfo.n(r.count) + (r.pct < 0 ? "" : "  ·  " + GameHealthInfo.pct(r.pct)), ui.warn);
        }
        for (GameHealthInfo.Row r : g.stopSystem) {
            bar("Último sistema: " + r.label, r.pct < 0 ? 0 : (int) Math.round(r.pct),
                    GameHealthInfo.n(r.count) + (r.pct < 0 ? "" : "  ·  " + GameHealthInfo.pct(r.pct)), ui.text2);
        }
    }

    private static String hourText(int h) {
        return h < 0 ? "-" : h + "h";
    }

    private void hunts(List<GameHealthInfo.Hunt> list, String empty) {
        if (list.isEmpty()) {
            note(empty);
            return;
        }
        double max = 0.1;
        for (GameHealthInfo.Hunt h : list) {
            max = Math.max(max, h.hours);
        }
        for (GameHealthInfo.Hunt h : list) {
            bar(h.name, (int) Math.round(100 * h.hours / max), String.format(PT, "%.1f h caçando", h.hours)
                    + "  ·  " + GameHealthInfo.n(h.visits) + " personagem-horas  ·  " + h.kills + " abates  ·  "
                    + h.deaths + " mortes", ui.text2);
        }
    }

    // ------------------------------------------------------------------------------------------------ balance
    private void balanceDays(boolean dm) {
        int d = GameHealthInfo.days(Ui.value(bDays), GameHealthInfo.BALANCE_MAX_DAYS);
        if (d < 0) {
            bDays.setError("Digite de 1 a 730.");
            return;
        }
        bDays.setError(null);
        balance(GameHealthInfo.balanceDaysArgs(d, dm), dm ? "Gerando e enviando…" : "Gerando o relatório…");
    }

    private void balance(String args, String busy) {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        setBalanceEnabled(false);
        bSummary.setText(busy);
        a.remote(a.ctl(args), 120, (r, e) -> {
            setBalanceEnabled(true);
            if (e != null || r == null) {
                Friendly f = Friendly.ofException(e != null ? e : new IllegalStateException("sem resposta"));
                bSummary.setText(f.title + ". " + f.detail);
                return;
            }
            String text = NewPlayerInfo.clean(r.out);
            bOut.setText(text);
            if (r.code != 0) {
                bCopy.setEnabled(false);
                if (text.startsWith("Erro: no-table")) {
                    bSummary.setText("As tabelas da telemetria ainda não existem: rode o passo sql do install_all.py.");
                } else if (text.startsWith("no-report")) {
                    bSummary.setText("Ainda não há relatório salvo.");
                } else {
                    Friendly f = Friendly.ofResult(r.out, r.code);
                    bSummary.setText(f.title + ". " + f.detail);
                }
                return;
            }
            bText = text;
            bCopy.setEnabled(!text.isEmpty());
            if (text.contains("dm=queued")) {
                bSummary.setText("Salvo no servidor; o bot do Discord manda por DM em até 1 minuto.");
            } else if (text.contains("dm=no-bot")) {
                bSummary.setText("Salvo no servidor. O bot do Discord não está instalado: nada foi enviado.");
            } else {
                bSummary.setText(NewPlayerInfo.headline(text));
            }
        });
    }

    private void setBalanceEnabled(boolean on) {
        for (MaterialButton m : new MaterialButton[] {bRun, bSeason, bDm, bLast, bTimerOn, bTimerOff}) {
            m.setEnabled(on);
        }
    }

    // ------------------------------------------------------------------------------------------------ views
    private void chart(double[] values, double max, int color) {
        Bars bars = new Bars(a, color, ui.edge);
        bars.set(values, max);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, ui.dp(72));
        lp.topMargin = ui.dp(6);
        out.addView(bars, lp);
    }

    private void section(String title) {
        out.addView(new View(a), ui.gap(12));
        TextView h = ui.heading(title);
        h.setTextSize(13);
        out.addView(h);
    }

    private void note(String s) {
        out.addView(ui.hint(s));
    }

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
