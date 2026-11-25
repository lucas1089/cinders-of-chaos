package com.cindersofchaos.admin;

import android.text.InputType;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.textfield.TextInputLayout;

/**
 * Painel > Atualização automática (O767): chaos-ctl.sh auto-update status | on | off | time HH:MM|game | run-prep |
 * run-save [--now] | log. One update a day at the server save: the builds 3 hours before it, the install at the save
 * (the save is the only restart), rollback and a Discord DM on failure. docs/ADMIN_APP.md "Atualização automática".
 */
final class AutoUpdateCard {
    final MaterialCardView card;
    private final MainActivity a;
    private final Ui ui;
    private final TextView headline;
    private final TextView details;
    private final MaterialButton toggle;
    private final TextInputLayout timeField;
    private final MainActivity.ResultCard result;
    private AutoUpdateInfo last;
    private boolean seen = false;

    AutoUpdateCard(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        card = ui.titledCard("Atualização automática");
        LinearLayout b = Ui.body(card);
        b.addView(ui.hint("Uma atualização por dia, no server save: as builds que mudaram começam 3 horas antes, a "
                + "instalação entra no próprio save (sem reinício extra). CI vermelho pula o dia; falha volta a versão "
                + "anterior e avisa no Discord."));
        headline = ui.title("Toque em Ver estado.");
        headline.setTextSize(14);
        headline.setPadding(0, ui.dp(8), 0, 0);
        b.addView(headline);
        details = ui.text("");
        details.setTextIsSelectable(true);
        details.setVisibility(View.GONE);
        b.addView(details);

        toggle = ui.primary("Ligar", R.drawable.ic_play);
        toggle.setOnClickListener(v -> onOff());
        MaterialButton state = ui.secondary("Ver estado", R.drawable.ic_refresh);
        state.setOnClickListener(v -> status(true));
        b.addView(ui.evenRow(toggle, state), ui.gap(8));

        timeField = ui.field("Horário do server save", "HH:MM. Vazio = o horário do jogo (globalevents.xml).", "",
                InputType.TYPE_CLASS_DATETIME | InputType.TYPE_DATETIME_VARIATION_TIME);
        b.addView(timeField, ui.gap(4));
        MaterialButton saveTime = ui.secondary("Salvar horário", R.drawable.ic_save);
        saveTime.setOnClickListener(v -> setTime());
        MaterialButton log = ui.flat("Ver log", 0);
        log.setOnClickListener(v -> run("Log da atualização automática", "auto-update log 80", 60));
        b.addView(ui.evenRow(saveTime, log), ui.gap(4));

        MaterialButton prep = ui.flat("Rodar preparo agora", R.drawable.ic_play);
        prep.setOnClickListener(v -> a.confirm("Rodar o preparo agora?", AutoUpdateInfo.confirmPrepText(), "Rodar", false,
                () -> run("Preparo", "auto-update run-prep", 60)));
        MaterialButton save = ui.flat("Rodar no próximo save", R.drawable.ic_play);
        save.setOnClickListener(v -> a.confirm("Atualizar no próximo save?", AutoUpdateInfo.confirmSaveText(), "Rodar", false,
                () -> run("Atualização no save", "auto-update run-save", 60)));
        b.addView(ui.evenRow(prep, save), ui.gap(4));
        MaterialButton now = ui.flat("Rodar agora (reinicia já)", R.drawable.ic_play);
        now.setOnClickListener(v -> a.confirm("Atualizar e reiniciar agora?", AutoUpdateInfo.confirmNowText(), "Reiniciar",
                true, () -> run("Atualização agora", "auto-update run-save --now", 60)));
        b.addView(now, ui.gap(2));

        result = a.new ResultCard();
        b.addView(result.card, ui.gap(8));
    }

    /** The panel came on screen: read the state once per app start. */
    void shown() {
        if (seen || !a.store.configured()) {
            return;
        }
        seen = true;
        status(false);
    }

    private boolean ready() {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return false;
        }
        return true;
    }

    private void status(boolean manual) {
        if (!ready()) {
            return;
        }
        if (manual) {
            headline.setText("Lendo o estado…");
        }
        a.remote(a.ctl("auto-update status"), 60, (r, e) -> {
            if (e != null || r == null) {
                Friendly f = Friendly.ofException(e == null ? new RuntimeException("sem resposta") : e);
                headline.setText(f.title);
                details.setText(f.detail);
                details.setVisibility(View.VISIBLE);
                return;
            }
            AutoUpdateInfo s = AutoUpdateInfo.parse(r.out);
            if (s == null) {
                Friendly f = Friendly.ofResult(r.out, r.code == 0 ? 1 : r.code);
                headline.setText(f.title);
                details.setText(f.detail);
                details.setVisibility(View.VISIBLE);
                return;
            }
            last = s;
            headline.setText(s.headline());
            headline.setTextColor(s.enabled() ? ui.ok : ui.text);
            details.setText(s.details());
            details.setVisibility(View.VISIBLE);
            toggle.setText(s.enabled() ? "Desligar" : "Ligar");
            if ("set".equals(s.get("save_time_source"))) {
                Ui.setValue(timeField, s.get("save_time"));
            }
        });
    }

    private void onOff() {
        if (!ready()) {
            return;
        }
        if (last != null && last.enabled()) {
            a.confirm("Desligar a atualização automática?", "As atualizações voltam a ser à mão (Atualizar servidor e "
                    + "Recompilar engine).", "Desligar", true, () -> run("Desligar", "auto-update off", 60));
        } else {
            String t = last == null ? "06:00" : last.get("save_time");
            a.confirm("Ligar a atualização automática?", AutoUpdateInfo.confirmOnText(t), "Ligar", false,
                    () -> run("Ligar", "auto-update on", 60));
        }
    }

    private void setTime() {
        if (!ready()) {
            return;
        }
        String raw = Ui.value(timeField).trim();
        String t = raw.isEmpty() ? "game" : AutoUpdateInfo.normalTime(raw);
        if (t.isEmpty()) {
            timeField.setError("Use HH:MM, de 00:00 a 23:59.");
            return;
        }
        timeField.setError(null);
        run("Horário", "auto-update time " + t, 60);
    }

    private void run(String title, String command, int timeout) {
        if (!ready()) {
            return;
        }
        result.running(title);
        a.ctlAction(command, timeout, f -> {
            result.show(title, f);
            a.snack(title + ": " + (f.ok ? "ok" : f.title), f.ok);
            if (f.ok && !command.startsWith("auto-update log")) {
                status(false);
            }
        });
    }
}
