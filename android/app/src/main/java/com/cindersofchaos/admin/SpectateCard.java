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
 * Comandos > Ações rápidas > Assistir jogador: one character's screen, with the game's own sprites
 * (server/README.md "Live spectator", docs/ADMIN_APP.md "Assistir jogador").
 * Ao vivo: chaos-ctl.sh cast NAME over one long ssh channel. The engine mirrors the player's game messages to the cast
 * port (src-patch 0064), cast_relay.py turns them into JSON lines and CastView draws them at about 30 frames a second.
 * Foto: one picture drawn on the VPS (chaos-ctl.sh spectate NAME), scaled without smoothing.
 * Stops on Parar, when the tab or the app is left, and on an error. Read only: the player is not told and nothing in
 * the game changes.
 */
final class SpectateCard {
    /** The same rule as chaos-ctl.sh and the engine: a letter, then letters, single spaces, ' and -, 3 to 29. */
    private static final Pattern NAME = Pattern.compile("^[A-Za-z][A-Za-z '-]{2,28}$");

    final MaterialCardView card;
    private final MainActivity a;
    private final Ui ui;
    private final TextInputLayout name;
    private final MaterialButton liveB;
    private final MaterialButton photoB;
    private final MaterialButton stopB;
    private final MaterialButton lightB;
    private boolean readable = true;
    private final CastView live;
    private final ImageView view;
    private final TextView info;
    private final TextView state;
    private boolean running = false;
    private volatile int generation = 0;
    private Ssh.Stream stream;
    private String who = "";

    SpectateCard(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        card = ui.titledCard("Assistir jogador");
        LinearLayout b = Ui.body(card);
        b.addView(ui.hint("A tela do personagem com os sprites do jogo. Ao vivo: movimento, magias e falas em tempo "
                + "real (precisa da porta de cast ligada). Foto: uma imagem só. Só leitura: o jogador não é avisado e "
                + "nada muda no jogo. Para sozinho ao sair desta aba ou do app."));
        name = ui.field("Nome do personagem", "Precisa estar online.", "",
                InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_WORDS);
        b.addView(name, ui.gap(8));
        liveB = ui.primary("Ao vivo", R.drawable.ic_play);
        liveB.setOnClickListener(v -> startLive());
        photoB = ui.secondary("Foto", R.drawable.ic_search);
        photoB.setOnClickListener(v -> photo());
        stopB = ui.secondary("Parar", R.drawable.ic_stop);
        stopB.setOnClickListener(v -> stop("Parado."));
        stopB.setEnabled(false);
        b.addView(ui.evenRow(liveB, photoB, stopB), ui.gap(8));
        lightB = ui.flat("Luz clara", R.drawable.ic_search);
        lightB.setOnClickListener(v -> {
            readable = !readable;
            live.readableLight(readable);
            lightB.setText(readable ? "Luz clara" : "Luz do jogo");
            lastHealth = "";
            health();
        });
        b.addView(lightB, ui.gap(2));

        live = new CastView(a);
        live.setVisibility(View.GONE);
        b.addView(live, ui.gap(10));
        view = new ImageView(a);
        view.setAdjustViewBounds(true);
        view.setScaleType(ImageView.ScaleType.FIT_CENTER);
        view.setBackgroundColor(ui.iron0);
        view.setContentDescription("Foto do personagem");
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

    /** the name in the field, or null (with the field's error shown) */
    private String readName() {
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return null;
        }
        String n = Ui.value(name).trim().replaceAll("\\s+", " ");
        if (!NAME.matcher(n).matches()) {
            name.setError("Um nome de personagem: letras, espaços, ' e -, de 3 a 29.");
            return null;
        }
        name.setError(null);
        return n;
    }

    private void busy(boolean on) {
        running = on;
        liveB.setEnabled(!on);
        photoB.setEnabled(!on);
        stopB.setEnabled(on);
    }

    /** Stops the live view (Parar, leaving the tab or the app, an error); the last picture stays on screen. */
    void stop(String why) {
        if (!running) {
            return;
        }
        generation++;
        Ssh.Stream s = stream;
        stream = null;
        if (s != null) {
            // disconnecting blocks on the network: not on the screen thread
            a.pool.execute(s::cancel);
        }
        live.animate(false);
        busy(false);
        say(why);
    }

    boolean isRunning() {
        return running;
    }

    // ------------------------------------------------------------------------------------------------ ao vivo

    private void startLive() {
        String n = readName();
        if (n == null) {
            return;
        }
        who = n;
        final int gen = ++generation;
        busy(true);
        view.setVisibility(View.GONE);
        info.setVisibility(View.GONE);
        live.reset();
        live.readableLight(readable);
        lastHealth = "";
        live.setVisibility(View.VISIBLE);
        live.animate(true);
        say("Conectando a " + n + "...");
        final Ssh.Stream s = new Ssh.Stream();
        stream = s;
        final String cmd = a.ctl("cast " + Ssh.sq(n));
        a.pool.execute(() -> {
            final boolean[] fingerprint = {true};
            final String[] last = {""};
            int code;
            Exception err = null;
            try {
                code = Ssh.stream(a.store, cmd, line -> {
                    if (fingerprint[0]) {
                        fingerprint[0] = false;
                        a.main.post(a::newHostDialog);
                    }
                    String t = line(gen, line);
                    if (t != null) {
                        last[0] = t;
                    }
                }, s);
            } catch (Exception e) {
                code = -1;
                err = e;
            }
            final int fc = code;
            final Exception fe = err;
            final String ft = last[0];
            a.main.post(() -> {
                if (a.isFinishing() || a.isDestroyed()) {
                    return;
                }
                a.newHostDialog();
                ended(gen, fc, fe, ft);
            });
        });
    }

    /**
     * One line of the relay, on the streaming thread: the drawing state takes it at once, the texts go to the screen
     * thread. Returns its type for the end of the stream, or null for a line that is not JSON.
     */
    private String line(final int gen, String text) {
        if (gen != generation || text.isEmpty() || text.charAt(0) != '{') {
            return null;
        }
        final JSONObject j;
        try {
            j = new JSONObject(text);
        } catch (Exception e) {
            return null;
        }
        if (j.has("ok") && !j.optBoolean("ok", true)) {
            // a chaos-ctl.sh failure before the relay starts
            a.main.post(() -> {
                if (gen == generation) {
                    stop(castError(j.optString("error"), j.optString("message")));
                }
            });
            return "fail";
        }
        final String t;
        try {
            t = live.apply(j);
        } catch (RuntimeException e) {
            return null;    // one broken line does not end the view
        }
        if ("spr".equals(t) || "hb".equals(t)) {
            return t;
        }
        if ("sprerr".equals(t)) {
            a.main.post(() -> {
                if (gen == generation) {
                    health();
                }
            });
            return t;
        }
        final JSONObject st = live.stats();
        a.main.post(() -> {
            if (gen != generation) {
                return;
            }
            switch (t) {
                case "wait":
                    say("port".equals(j.optString("why"))
                            ? "A porta de cast não respondeu: o servidor está ligado? Tentando de novo..."
                            : who + " não está online (ou outro personagem está no cast). Esperando...");
                    break;
                case "hello":
                    say("Ao vivo.");
                    break;
                case "resync":
                    say("Recomeçando a visão (" + j.optString("why") + ")...");
                    break;
                case "full":
                case "d":
                    stats(st);
                    health();
                    break;
                case "end":
                    stop(endText(j.optString("why")));
                    break;
                default:
                    break;
            }
        });
        return t;
    }

    private String lastHealth = "";

    /** The state line while live: a sprite problem or darkness is said at once, never left as a black view. */
    private void health() {
        String p = live.problem();
        String text = p != null ? "Sprites: " + p
                : live.dark() ? "Escuro como no jogo (noite ou subsolo). Toque em Luz clara para ver o mapa." : "Ao vivo.";
        if (!text.equals(lastHealth)) {
            lastHealth = text;
            say(text);
        }
    }

    private void ended(int gen, int code, Exception e, String last) {
        if (gen != generation || !running) {
            return;
        }
        if (e != null) {
            Friendly f = Friendly.ofException(e);
            stop(f.title + ". " + f.detail);
        } else if (code == -1) {
            stop("A conexão caiu.");
        } else if (last.isEmpty()) {
            stop("O comando cast falhou (código " + code + "). A VPS tem a versão nova do chaos-ctl.sh? "
                    + "Atualize em Comandos > Versão do servidor.");
        } else {
            stop("Fim da visão ao vivo.");
        }
    }

    /** the error codes of chaos-ctl.sh cast */
    private String castError(String code, String message) {
        switch (code) {
            case "cast-off":
                return "A porta de cast está desligada. Ligue com install_all.py (passo castport) e reinicie o "
                        + "servidor; veja docs/ADMIN_APP.md.";
            case "busy":
                return "Outra visão ao vivo já está aberta. Pare a outra e tente de novo.";
            case "no-pair":
                return "A VPS não tem os sprites do client. Toque em Baixar sprites e tente de novo quando o "
                        + "download terminar.";
            case "no-tool":
                return "A VPS não tem o cast_relay.py: atualize o repositório na VPS.";
            default:
                return code + ": " + message;
        }
    }

    private String endText(String why) {
        switch (why) {
            case "time":
                return "Parado depois de 30 minutos. Toque em Ao vivo para continuar.";
            case "no-pair":
                return "A VPS não tem os sprites do client. Toque em Baixar sprites.";
            case "bad-port":
                return "A porta de cast está errada em config.lua (castPort).";
            case "bad-name":
                return "Nome de personagem inválido.";
            default:
                return "Fim da visão ao vivo (" + why + ").";
        }
    }

    private void stats(JSONObject st) {
        if (st == null) {
            return;
        }
        int hp = st.optInt("hp"), mhp = st.optInt("mhp");
        info.setText(String.format(Locale.ROOT, "%s  ·  nível %d\nVida %d / %d (%d%%)  ·  Mana %d / %d",
                who, st.optInt("lvl"), hp, mhp, pct(hp, mhp), st.optInt("mp"), st.optInt("mmp")));
        info.setVisibility(View.VISIBLE);
    }

    // ------------------------------------------------------------------------------------------------ foto

    /** One picture drawn on the VPS (chaos-ctl.sh spectate NAME). */
    private void photo() {
        String n = readName();
        if (n == null) {
            return;
        }
        who = n;
        say("Pedindo a foto de " + n + "...");
        photoB.setEnabled(false);
        a.remote(a.ctl("spectate " + Ssh.sq(n)), 40, (r, e) -> {
            photoB.setEnabled(!running);
            if (running) {
                return;
            }
            if (e != null) {
                Friendly f = Friendly.ofException(e);
                say(f.title + ". " + f.detail);
                return;
            }
            JSONObject j = lastJson(r.out);
            if (j == null) {
                Friendly f = Friendly.ofResult(r.out, r.code);
                say(f.ok ? "Resposta inesperada da VPS." : f.title + ". " + f.detail);
            } else if (j.optBoolean("ok", false)) {
                if (!show(j)) {
                    say("A imagem não pôde ser lida.");
                }
            } else {
                say(photoError(j.optString("error"), j.optString("message")));
            }
        });
    }

    private String photoError(String code, String message) {
        switch (code) {
            case "offline":
                return who + " não está online.";
            case "busy":
                return "A VPS está desenhando outra foto. Tente de novo em um segundo.";
            case "no-pair":
                return "A VPS não tem os sprites do client. Toque em Baixar sprites e tente de novo quando o "
                        + "download terminar.";
            case "timeout":
                return "A VPS demorou para desenhar (a primeira vez prepara o índice dos sprites). Tente de novo.";
            case "no-answer":
                return "O servidor não respondeu: ele está ligado? (" + message + ")";
            case "stale":
                return "A visão de " + who + " ainda não chegou. Tente de novo.";
            default:
                return code + ": " + message;
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
        live.setVisibility(View.GONE);
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
        say(age > 2 ? String.format(Locale.ROOT, "Foto (de %d s atrás).", age) : "Foto.");
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
