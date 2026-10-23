package com.cindersofchaos.admin;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.drawable.BitmapDrawable;
import android.text.InputType;
import android.util.Base64;
import android.view.View;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.textfield.TextInputLayout;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.Locale;
import java.util.regex.Pattern;

/**
 * Comandos > Ações rápidas > Assistir jogador: the live view of one character, drawn on the VPS with the game's own
 * sprites (chaos-ctl.sh spectate NAME, server/README.md "Live spectator"). Polls about once a second over the open ssh
 * session, shows the PNG scaled without smoothing (the pixels stay sharp) and the character's level, health and mana
 * under it. Stops on Parar, when the tab or the app is left, and after repeated failures. Read only: the player is not
 * told and nothing in the game changes. docs/ADMIN_APP.md "Assistir jogador".
 */
final class SpectateCard {
    /** The same rule as chaos-ctl.sh and the engine: a letter, then letters, single spaces, ' and -, 3 to 29. */
    private static final Pattern NAME = Pattern.compile("^[A-Za-z][A-Za-z '-]{2,28}$");
    private static final long EVERY_MS = 1000L;
    private static final long OFFLINE_EVERY_MS = 4000L;
    private static final int MAX_FAILURES = 6;

    final MaterialCardView card;
    private final MainActivity a;
    private final Ui ui;
    private final TextInputLayout name;
    private final MaterialButton startB;
    private final MaterialButton stopB;
    private final ImageView view;
    private final TextView info;
    private final TextView state;
    private boolean running = false;
    private boolean first = true;
    private int generation = 0;
    private int failures = 0;
    private String who = "";

    SpectateCard(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        card = ui.titledCard("Assistir jogador");
        LinearLayout b = Ui.body(card);
        b.addView(ui.hint("A tela do personagem ao vivo, com os sprites do jogo, mais ou menos uma vez por segundo. Só "
                + "leitura: o jogador não é avisado e nada muda no jogo. Para sozinho ao sair desta aba ou do app."));
        name = ui.field("Nome do personagem", "Precisa estar online.", "",
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_WORDS);
        b.addView(name, ui.gap(8));
        startB = ui.primary("Iniciar", R.drawable.ic_play);
        startB.setOnClickListener(v -> start());
        stopB = ui.secondary("Parar", R.drawable.ic_stop);
        stopB.setOnClickListener(v -> stop("Parado."));
        stopB.setEnabled(false);
        b.addView(ui.evenRow(startB, stopB), ui.gap(8));

        view = new ImageView(a);
        view.setAdjustViewBounds(true);
        view.setScaleType(ImageView.ScaleType.FIT_CENTER);
        view.setBackgroundColor(ui.iron0);
        view.setContentDescription("Visão do personagem");
        view.setVisibility(View.GONE);
        b.addView(view, ui.gap(10));
        info = ui.text("");
        info.setTextColor(ui.bright);
        info.setVisibility(View.GONE);
        b.addView(info, ui.gap(6));
        state = ui.hint("");
        state.setVisibility(View.GONE);
        b.addView(state, ui.gap(4));

        MaterialButton pairStatus = ui.flat("Sprites na VPS", R.drawable.ic_search);
        pairStatus.setOnClickListener(v -> pairStatus());
        MaterialButton fetch = ui.flat("Baixar sprites", R.drawable.ic_backup);
        fetch.setOnClickListener(v -> a.confirm("Baixar os sprites na VPS?",
                "A VPS baixa o par Tibia.dat / Tibia.spr do ramo windows-assets (centenas de MB), confere as somas e "
                        + "troca a pasta do par. Leva alguns minutos; acompanhe em Log do download.", "Baixar", false,
                () -> pairCmd("spectate-pair fetch", "Download dos sprites")));
        b.addView(ui.evenRow(pairStatus, fetch), ui.gap(8));
        MaterialButton log = ui.flat("Log do download", R.drawable.ic_nav_logs);
        log.setOnClickListener(v -> pairCmd("spectate-pair log 40", "Log do download"));
        b.addView(log, ui.gap(2));
    }

    // ------------------------------------------------------------------------------------------------ watching

    private void start() {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        String n = Ui.value(name).replaceAll("\\s+", " ");
        if (!NAME.matcher(n).matches()) {
            name.setError("Um nome de personagem: letras, espaços, ' e -, de 3 a 29.");
            return;
        }
        name.setError(null);
        who = n;
        running = true;
        first = true;
        failures = 0;
        generation++;
        startB.setEnabled(false);
        stopB.setEnabled(true);
        say("Conectando a " + n + "...");
        poll(generation);
    }

    /** Stops the polling (Parar, leaving the tab or the app); the last picture stays on screen. */
    void stop(String why) {
        if (!running) {
            return;
        }
        running = false;
        generation++;
        startB.setEnabled(true);
        stopB.setEnabled(false);
        say(why);
    }

    boolean isRunning() {
        return running;
    }

    private void poll(final int gen) {
        if (!running || gen != generation) {
            return;
        }
        final String cmd = a.ctl("spectate " + Ssh.sq(who));
        if (first) {
            // the first call goes through remote(): the progress bar, and the first-connection fingerprint dialog
            first = false;
            a.remote(cmd, 40, (r, e) -> answered(gen, r, e));
            return;
        }
        a.pool.execute(() -> {
            Ssh.Result r = null;
            Exception err = null;
            try {
                r = Ssh.exec(a.store, cmd, 40);
            } catch (Exception e) {
                err = e;
            }
            final Ssh.Result fr = r;
            final Exception fe = err;
            a.main.post(() -> {
                if (!a.isFinishing() && !a.isDestroyed()) {
                    answered(gen, fr, fe);
                }
            });
        });
    }

    private void answered(int gen, Ssh.Result r, Exception e) {
        if (!running || gen != generation) {
            return;
        }
        long next = EVERY_MS;
        if (e != null) {
            Friendly f = Friendly.ofException(e);
            fail(f.title + ". " + f.detail);
        } else {
            JSONObject j = lastJson(r.out);
            if (j == null) {
                Friendly f = Friendly.ofResult(r.out, r.code);
                fail(f.ok ? "Resposta inesperada da VPS." : f.title + ". " + f.detail);
            } else if (j.optBoolean("ok", false)) {
                if (show(j)) {
                    failures = 0;
                } else {
                    fail("A imagem não pôde ser lida.");
                }
            } else {
                next = error(j.optString("error"), j.optString("message"));
            }
        }
        if (running && gen == generation) {
            a.main.postDelayed(() -> poll(gen), next);
        }
    }

    /** an error answer of the script: what to tell, and when to ask again (stops for the ones that will not pass) */
    private long error(String code, String message) {
        switch (code) {
            case "offline":
                failures = 0;
                say(who + " não está online. Tentando de novo a cada 4 s.");
                return OFFLINE_EVERY_MS;
            case "busy":
                return EVERY_MS;
            case "no-pair":
                stop("A VPS não tem os sprites do client. Toque em Baixar sprites e tente de novo quando o download "
                        + "terminar.");
                return EVERY_MS;
            case "timeout":
                fail("A VPS demorou para desenhar (a primeira vez prepara o índice dos sprites).");
                return EVERY_MS;
            case "no-answer":
                fail("O servidor não respondeu: ele está ligado? (" + message + ")");
                return 2000L;
            case "stale":
                fail("A visão de " + who + " ainda não chegou; esperando a próxima.");
                return EVERY_MS;
            default:
                fail(code + ": " + message);
                return EVERY_MS;
        }
    }

    private void fail(String text) {
        failures++;
        if (failures >= MAX_FAILURES) {
            stop("Parado depois de " + failures + " falhas seguidas. " + text);
        } else {
            say(text);
        }
    }

    private boolean show(JSONObject j) {
        byte[] png;
        try {
            png = Base64.decode(j.optString("png"), Base64.DEFAULT);
        } catch (IllegalArgumentException ex) {
            return false;
        }
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inScaled = false;
        Bitmap bmp = BitmapFactory.decodeByteArray(png, 0, png.length, o);
        if (bmp == null) {
            return false;
        }
        BitmapDrawable d = new BitmapDrawable(a.getResources(), bmp);
        // nearest neighbour: the pixel art is scaled up without smoothing
        d.setFilterBitmap(false);
        d.setAntiAlias(false);
        d.setDither(false);
        view.setImageDrawable(d);
        view.setVisibility(View.VISIBLE);

        StringBuilder s = new StringBuilder();
        s.append(j.optString("name", who)).append("  ·  nível ").append(j.optInt("level"));
        String voc = j.optString("voc");
        if (!voc.isEmpty()) {
            s.append("  ·  ").append(voc);
        }
        s.append("\nVida ").append(j.optInt("hp")).append(" / ").append(j.optInt("maxhp"))
                .append(" (").append(pct(j.optInt("hp"), j.optInt("maxhp"))).append("%)")
                .append("  ·  Mana ").append(j.optInt("mp")).append(" / ").append(j.optInt("maxmp"));
        JSONArray pos = j.optJSONArray("pos");
        if (pos != null && pos.length() == 3) {
            s.append("\nPosição ").append(pos.optInt(0)).append(", ").append(pos.optInt(1)).append(", ")
                    .append(pos.optInt(2));
        }
        info.setText(s.toString());
        info.setVisibility(View.VISIBLE);
        int age = j.optInt("age");
        say(age > 2 ? String.format(Locale.ROOT, "Ao vivo (atraso de %d s).", age) : "Ao vivo.");
        return true;
    }

    private static int pct(int v, int max) {
        return max <= 0 ? 0 : Math.max(0, Math.min(100, Math.round(v * 100f / max)));
    }

    /** the last line of the output that is a JSON object (the script prints one; ssh merges stderr into it) */
    static JSONObject lastJson(String out) {
        if (out == null) {
            return null;
        }
        String[] lines = out.split("\n");
        for (int i = lines.length - 1; i >= 0; i--) {
            String l = lines[i].trim();
            if (l.startsWith("{") && l.endsWith("}")) {
                try {
                    return new JSONObject(l);
                } catch (Exception ignored) {
                    // not JSON: keep looking
                }
            }
        }
        return null;
    }

    private void say(String text) {
        state.setText(text);
        state.setVisibility(text.isEmpty() ? View.GONE : View.VISIBLE);
    }

    // ------------------------------------------------------------------------------------------------ the pair

    private void pairStatus() {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        a.ctlAction("spectate-pair status", 60, f -> {
            if (!f.ok) {
                say("Sprites na VPS: " + f.title + ". " + f.detail);
                return;
            }
            String out = f.raw;
            boolean pair = out.contains("pair=yes");
            boolean fetching = out.contains("fetching=yes");
            String idx = out.contains("index=yes") ? "pronto" : "será feito no primeiro desenho";
            say((pair ? "A VPS tem os sprites do client (índice " + idx + ")."
                    : "A VPS ainda não tem os sprites do client: toque em Baixar sprites.")
                    + (fetching ? " Um download está em andamento." : ""));
        });
    }

    private void pairCmd(String args, String what) {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        a.ctlAction(args, 30, f -> {
            String text = f.ok ? (f.raw.isEmpty() ? f.detail : f.raw) : f.title + ". " + f.detail;
            say(what + ": " + text.trim());
        });
    }
}
