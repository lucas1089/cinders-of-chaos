package com.cindersofchaos.admin;

import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.textfield.TextInputLayout;

/**
 * Painel > Recompilar engine (O436): chaos-ctl.sh engine-build start (GitHub Actions compiles the server engine with
 * every patch of server/src-patches/), engine-build status read every 20 seconds while the run is queued or in progress,
 * engine-build log (the jobs and the failed step) and engine-build-token-set (the GitHub token, on stdin). When the build
 * is done and newer, the card points to Atualizar servidor, which installs the engine. docs/ADMIN_APP.md.
 */
final class EngineBuildCard {
    private static final long POLL_MS = 20_000;

    final MaterialCardView card;
    private final MainActivity a;
    private final Ui ui;
    private final TextView headline;
    private final TextView details;
    private final MaterialButton build;
    private final MaterialButton refresh;
    private final MaterialButton newClient;
    private String nextBuild = "";
    private final MaterialButton steps;
    private final MaterialButton tokenToggle;
    private final LinearLayout tokenBox;
    private final TextInputLayout tokenField;
    private final MainActivity.ResultCard result;
    private boolean polling = false;
    private boolean seen = false;
    private final Runnable pollTask = () -> {
        if (polling) {
            status(false);
        }
    };

    EngineBuildCard(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        card = ui.titledCard("Recompilar engine");
        LinearLayout b = Ui.body(card);
        b.addView(ui.hint("Manda o GitHub compilar o engine do servidor com todos os patches do código novo (a branch "
                + "que o Atualizar servidor segue). O jogo segue no ar. Quando terminar, Atualizar servidor instala "
                + "o engine novo."));
        headline = ui.title("Toque em Atualizar estado.");
        headline.setTextSize(14);
        headline.setPadding(0, ui.dp(8), 0, 0);
        b.addView(headline);
        details = ui.text("");
        details.setTextIsSelectable(true);
        details.setVisibility(View.GONE);
        b.addView(details);

        build = ui.primary("Recompilar", R.drawable.ic_play);
        build.setOnClickListener(v -> a.confirm("Recompilar o engine agora?", EngineBuildInfo.confirmText(), "Recompilar",
                false, () -> start("engine-build start")));
        refresh = ui.secondary("Atualizar estado", R.drawable.ic_refresh);
        refresh.setOnClickListener(v -> status(true));
        b.addView(ui.evenRow(build, refresh), ui.gap(8));
        newClient = ui.secondary("Recompilar com client novo", R.drawable.ic_play);
        newClient.setOnClickListener(v -> a.confirm("Recompilar com client novo?",
                EngineBuildInfo.confirmNewClientText(nextBuild), "Recompilar", false, () -> start("engine-build start --new-client")));
        newClient.setVisibility(View.GONE);
        b.addView(newClient, ui.gap(4));
        steps = ui.flat("Ver passos", 0);
        steps.setOnClickListener(v -> log());
        tokenToggle = ui.flat("Definir token do GitHub", R.drawable.ic_key);
        b.addView(ui.evenRow(steps, tokenToggle), ui.gap(2));

        tokenBox = ui.column();
        tokenField = ui.field("Token do GitHub", "github_pat_... Vazio + Salvar apaga.", "",
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        final android.widget.EditText pe = tokenField.getEditText();
        if (pe != null) {
            // the window is FLAG_SECURE while the token field is in focus or holds text
            pe.setOnFocusChangeListener((v, focus) -> a.secret("engine-token", focus || pe.length() > 0));
            pe.addTextChangedListener(new TextWatcher() {
                @Override
                public void beforeTextChanged(CharSequence s, int st, int cnt, int af) {
                }

                @Override
                public void onTextChanged(CharSequence s, int st, int bf, int cnt) {
                }

                @Override
                public void afterTextChanged(Editable ed) {
                    a.secret("engine-token", pe.hasFocus() || ed.length() > 0);
                }
            });
        }
        tokenBox.addView(tokenField);
        tokenBox.addView(ui.hint("No GitHub: Settings > Developer settings > Fine-grained tokens. Só este repositório, "
                + "permissão Actions: Read and write. O token vai pelo SSH, fica só na VPS (/etc/chaos/engine-build.token, "
                + "modo 600) e o app não o mostra de volta. Passo a passo: docs/ADMIN_APP.md."));
        MaterialButton save = ui.secondary("Salvar token", R.drawable.ic_save);
        save.setOnClickListener(v -> saveToken());
        tokenBox.addView(save, ui.gap(8));
        tokenBox.setVisibility(View.GONE);
        b.addView(tokenBox, ui.gap(8));
        tokenToggle.setOnClickListener(v -> tokenBox.setVisibility(tokenBox.getVisibility() == View.VISIBLE ? View.GONE
                : View.VISIBLE));

        result = a.new ResultCard();
        b.addView(result.card, ui.gap(8));
    }

    /** The panel came on screen: read the state once per app start and follow a build that is running. */
    void shown() {
        if (seen || polling || !a.store.configured()) {
            return;
        }
        seen = true;
        status(false);
    }

    private void status(boolean manual) {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        if (manual) {
            headline.setText("Perguntando ao GitHub…");
        }
        a.remote(a.ctl("engine-build status"), 90, (r, e) -> {
            if (e != null || r == null) {
                if (polling) { // a dropped connection must not end the follow-up of a running build
                    headline.setText("Sem conexão; tentando de novo…");
                    a.main.removeCallbacks(pollTask);
                    a.main.postDelayed(pollTask, POLL_MS);
                    return;
                }
                Friendly f = Friendly.ofException(e == null ? new RuntimeException("sem resposta") : e);
                headline.setText(f.title);
                details.setText(f.detail);
                details.setVisibility(View.VISIBLE);
                return;
            }
            EngineBuildInfo s = EngineBuildInfo.parse(r.out);
            if (!s.valid()) {
                polling = false;
                String why = EngineBuildInfo.refusal(r.out);
                Friendly f = Friendly.ofResult(r.out, r.code == 0 ? 1 : r.code);
                headline.setText(why.isEmpty() ? f.title : "Não consegui ler o GitHub.");
                details.setText(why.isEmpty() ? f.detail : why);
                details.setVisibility(View.VISIBLE);
                return;
            }
            show(s, r.out);
        });
    }

    private void show(EngineBuildInfo s, String raw) {
        headline.setText(s.headline());
        String why = s.state().equals("unknown") ? EngineBuildInfo.refusal(raw) : "";
        String d = why.isEmpty() ? s.details() : why;
        details.setText(d);
        details.setVisibility(d.isEmpty() ? View.GONE : View.VISIBLE);
        int color = s.state().equals("success") ? ui.ok : s.state().equals("failure") || s.state().equals("unknown")
                ? ui.error : s.running() ? ui.warn : ui.text;
        headline.setTextColor(color);
        boolean busy = s.running();
        build.setEnabled(!busy);
        build.setAlpha(busy ? 0.5f : 1f);
        if (!busy && s.get("client_changed").length() > 0) {
            nextBuild = s.clientNext();
            newClient.setText(s.newClientLabel());
            newClient.setVisibility(s.clientChanged() ? View.VISIBLE : View.GONE);
        }
        newClient.setEnabled(!busy);
        if (busy) {
            if (!polling) {
                polling = true;
            }
            a.main.removeCallbacks(pollTask);
            a.main.postDelayed(pollTask, POLL_MS);
        } else if (polling) {
            polling = false;
            a.snack("Recompilar engine: " + (s.newer() ? "pronto, use Atualizar servidor" : s.headline()),
                    s.state().equals("success"));
        }
    }

    private void start(String command) {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        build.setEnabled(false);
        build.setAlpha(0.5f);
        result.running("Recompilar engine");
        // up to 30 s waiting for GitHub to show the new run
        a.ctlAction(command, 120, f -> {
            String why = f.ok ? "" : EngineBuildInfo.refusal(f.raw);
            Friendly shown = f.ok ? Friendly.ok("Recompilação iniciada", EngineBuildInfo.startText(f.raw), f.raw)
                    : why.isEmpty() ? f : Friendly.fail("Não começou", why, f.raw);
            a.snack("Recompilar engine: " + (f.ok ? "começou" : shown.title), f.ok);
            if (f.ok) {
                result.show("Recompilar engine", shown);
                polling = true;
                status(false);
            } else {
                result.show("Recompilar engine", shown);
                build.setEnabled(true);
                build.setAlpha(1f);
            }
        });
    }

    private void log() {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        result.running("Passos da recompilação");
        a.ctlAction("engine-build log 20", 90, f -> result.show("Passos da recompilação", f));
    }

    private void saveToken() {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        final String value = Ui.value(tokenField).trim();
        if (!value.isEmpty() && !EngineBuildInfo.validToken(value)) {
            tokenField.setError("Cole o token inteiro (começa com github_pat_).");
            return;
        }
        tokenField.setError(null);
        Runnable go = () -> {
            result.running("Token do GitHub");
            // the token is the command's stdin: never on its command line
            a.ctlAction("engine-build-token-set", 60, value + "\n", f -> {
                String why = f.ok ? "" : EngineBuildInfo.refusal(f.raw);
                result.show("Token do GitHub", why.isEmpty() ? f : Friendly.fail("Token não salvo", why, f.raw));
                a.snack("Token do GitHub: " + (f.ok ? (value.isEmpty() ? "apagado" : "salvo") : "não salvo"), f.ok);
                if (f.ok) {
                    Ui.setValue(tokenField, "");
                    tokenBox.setVisibility(View.GONE);
                    status(false);
                }
            });
        };
        if (value.isEmpty()) {
            a.confirm("Apagar o token do GitHub?", "A VPS deixa de poder começar recompilações até um novo token.", "Apagar",
                    true, go);
        } else {
            go.run();
        }
    }
}
