package com.cindersofchaos.admin;

import android.text.InputType;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.checkbox.MaterialCheckBox;
import com.google.android.material.textfield.TextInputLayout;

import java.util.ArrayList;
import java.util.List;

/**
 * Painel > Bugs e sugestões: chaos-ctl.sh feedback (the bug reports and suggestions players sent from System > Report a
 * Bug, plain text, newest first) and feedback-close. "Copiar tudo" puts the list on the clipboard to paste into a chat
 * with Claude. No names, accounts or IPs reach the phone (the card never asks for --names). Parsing and the command
 * lines are in FeedbackInfo (plain-JVM test). docs/ADMIN_APP.md.
 */
final class FeedbackCard {
    final MaterialCardView card;
    private final MainActivity a;
    private final Ui ui;
    private final TextView summary;
    private final TextInputLayout days;
    private final TextInputLayout note;
    private final MaterialCheckBox all;
    private final MaterialButton load;
    private final MaterialButton copy;
    private final LinearLayout out;
    private List<FeedbackInfo.Item> items = new ArrayList<>();

    FeedbackCard(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        card = ui.titledCard("Bugs e sugestões");
        LinearLayout b = Ui.body(card);
        b.addView(ui.hint("O que os jogadores mandaram em System > Report a Bug (sugestões: o texto começa com "
                + "\"sugestão:\"). Os mais novos primeiro, sem nomes, contas nem IPs. \"Copiar tudo\" copia a lista para "
                + "você colar no Claude. \"Fechar\" tira o relato da lista de abertos."));
        days = ui.field("Últimos dias", "1 a 3650.", String.valueOf(FeedbackInfo.DEFAULT_DAYS), InputType.TYPE_CLASS_NUMBER);
        b.addView(days, ui.gap(8));
        all = new MaterialCheckBox(a);
        all.setText("Incluir os já fechados");
        all.setTextColor(ui.bright);
        b.addView(all);
        note = ui.field("Nota ao fechar (opcional)", "Fica gravada no relato (até 200 letras).", "", 0);
        b.addView(note, ui.gap(4));
        load = ui.secondary("Atualizar", R.drawable.ic_refresh);
        load.setOnClickListener(v -> load());
        copy = ui.secondary("Copiar tudo", R.drawable.ic_copy);
        copy.setEnabled(false);
        copy.setOnClickListener(v -> a.copy(FeedbackInfo.copyAll(items), "Copiado: cole no Claude."));
        b.addView(ui.evenRow(load, copy), ui.gap(8));
        summary = ui.text("Toque em Atualizar.");
        summary.setPadding(0, ui.dp(8), 0, 0);
        b.addView(summary);
        out = ui.column();
        b.addView(out, ui.gap(4));
    }

    private void load() {
        int d = FeedbackInfo.days(Ui.value(days));
        if (d < 0) {
            days.setError("Digite de 1 a 3650.");
            return;
        }
        days.setError(null);
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        load.setEnabled(false);
        summary.setText("Lendo os relatos…");
        a.remote(a.ctl(FeedbackInfo.listArgs(d, all.isChecked(), "")), 60, (r, e) -> {
            load.setEnabled(true);
            out.removeAllViews();
            if (e != null || r == null) {
                Friendly f = Friendly.ofException(e != null ? e : new IllegalStateException("sem resposta"));
                summary.setText(f.title + ". " + f.detail);
                return;
            }
            if (r.code != 0) {
                Friendly f = Friendly.ofResult(r.out, r.code);
                summary.setText(f.title + ". " + f.detail);
                return;
            }
            items = FeedbackInfo.parse(r.out);
            copy.setEnabled(!items.isEmpty());
            summary.setText(FeedbackInfo.summary(items));
            for (FeedbackInfo.Item i : items) {
                add(i);
            }
        });
    }

    private void add(FeedbackInfo.Item i) {
        LinearLayout row = ui.column();
        row.setPadding(0, ui.dp(8), 0, ui.dp(4));
        out.addView(ui.divider());
        TextView head = ui.heading("#" + i.id + "  ·  " + FeedbackInfo.categoryLabel(i.category) + "  ·  "
                + (i.closed ? "fechado" : "aberto"));
        head.setTextSize(11);
        row.addView(head);
        TextView t = ui.text(i.text.isEmpty() ? "-" : i.text);
        t.setTextIsSelectable(true);
        row.addView(t, ui.gap(2));
        TextView meta = ui.hint(i.when + "  ·  posição " + i.pos.replace(",", ", ")
                + (i.who.isEmpty() ? "" : "  ·  " + i.who) + (i.closedNote.isEmpty() ? "" : "  ·  nota: " + i.closedNote));
        meta.setTextSize(12);
        row.addView(meta);
        if (!i.closed) {
            MaterialButton close = ui.flat("Fechar", R.drawable.ic_stop);
            close.setOnClickListener(v -> close(i));
            row.addView(close, ui.gap(2));
        }
        out.addView(row);
    }

    private void close(FeedbackInfo.Item i) {
        String n = Ui.value(note);
        if (n.length() > 200) {
            note.setError("Até 200 letras.");
            return;
        }
        note.setError(null);
        a.confirm("Fechar o relato #" + i.id + "?", n.isEmpty() ? "Sem nota." : "Nota: " + n, "Fechar", false, () ->
                a.ctlAction(FeedbackInfo.closeArgs(i.id, n.isEmpty() ? "" : Ssh.sq(n)), 30, f -> {
                    a.snack(f.ok ? "Relato #" + i.id + " fechado." : f.title + ". " + f.detail, f.ok);
                    if (f.ok) {
                        Ui.setValue(note, "");
                        load();
                    }
                }));
    }
}
