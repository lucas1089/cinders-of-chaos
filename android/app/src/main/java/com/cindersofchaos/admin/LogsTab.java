package com.cindersofchaos.admin;

import android.graphics.Typeface;
import android.text.InputType;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.style.ForegroundColorSpan;
import android.text.style.StyleSpan;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.button.MaterialButtonToggleGroup;
import com.google.android.material.card.MaterialCardView;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.android.material.materialswitch.MaterialSwitch;
import com.google.android.material.textfield.TextInputLayout;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Logs: the engine console, the errors since the last server start (counted, per start), the update log, and a
 * terminal on the VPS. Monospace, scrollable, a line count, follow (every 5 s), copy.
 */
final class LogsTab {
    private static final int CONSOLE = 0;
    private static final int ERRORS = 1;
    private static final int UPDATE = 2;
    private static final int GM = 3;
    private static final int TERMINAL = 4;
    private static final int[] LINE_CHOICES = {50, 100, 200, 500};
    /** The logs behind "Updates": the server update, the client update publish, the site install. */
    private static final String[] UPD_LOGS = {"update-log", "publish-log", "site-log"};
    private static final String[] UPD_NAMES = {"Atualização do servidor", "Publicação do client", "Instalação do site"};

    final View root;
    private final MainActivity a;
    private final Ui ui;
    private final MaterialButtonToggleGroup modes;
    private final int[] modeIds = new int[5];
    private final MaterialButton lines;
    private final MaterialButton which;
    private int updLog = 0;
    private String staff = "";
    private String[] staffNames = new String[0];
    private final MaterialSwitch follow;
    private final MaterialSwitch older;
    private final LinearLayout errorBar;
    private final TextView info;
    private final TextView out;
    private final ScrollView outScroll;
    private final LinearLayout termBar;
    private final TextInputLayout termIn;
    private int mode = CONSOLE;
    private int seq = 0;
    private int inflightMode = -1;
    private String plain = "";
    private String cwd = "~";
    private String lastCommand = "";
    private final StringBuilder term = new StringBuilder(
            "Terminal na VPS. Cada comando roda no shell do usuário ssh; o 'cd' fica guardado. Sem programas "
                    + "interativos (use top -bn1 no lugar de top).\n");

    LogsTab(MainActivity a) {
        this.a = a;
        this.ui = a.ui;
        LinearLayout page = ui.column();
        page.setPadding(ui.dp(14), ui.dp(10), ui.dp(14), ui.dp(10));

        modes = new MaterialButtonToggleGroup(a);
        modes.setSingleSelection(true);
        modes.setSelectionRequired(true);
        String[] names = {"Console", "Erros", "Updates", "GM", "Terminal"};
        for (int i = 0; i < names.length; i++) {
            MaterialButton b = ui.secondary(names[i], 0);
            b.setId(View.generateViewId());
            b.setTextSize(12);
            b.setPadding(ui.dp(4), 0, ui.dp(4), 0);
            b.setCheckable(true);
            modeIds[i] = b.getId();
            modes.addView(b, Ui.weight(1f));
        }
        modes.check(modeIds[CONSOLE]);
        modes.addOnButtonCheckedListener((g, id, checked) -> {
            if (!checked) {
                return;
            }
            for (int i = 0; i < modeIds.length; i++) {
                if (modeIds[i] == id) {
                    setMode(i, true);
                }
            }
        });
        page.addView(modes, Ui.matchWrap());

        // ---- tools: line count, follow, refresh, copy
        LinearLayout tools = ui.row();
        lines = ui.flat(a.store.logLines() + " linhas", 0);
        lines.setOnClickListener(v -> pickLines());
        tools.addView(lines);
        // Updates: which log; GM: which staff member
        which = ui.flat("", 0);
        which.setOnClickListener(v -> pickWhich());
        which.setVisibility(View.GONE);
        tools.addView(which);
        follow = new MaterialSwitch(a);
        follow.setText("Acompanhar");
        follow.setTextColor(ui.text);
        follow.setOnCheckedChangeListener((s, on) -> {
            if (on) {
                load(false);
            }
        });
        tools.addView(follow, Ui.weight(1f));
        MaterialButton refresh = ui.flat("", R.drawable.ic_refresh);
        refresh.setContentDescription("Atualizar");
        refresh.setOnClickListener(v -> load(true));
        tools.addView(refresh);
        MaterialButton copy = ui.flat("", R.drawable.ic_copy);
        copy.setContentDescription("Copiar");
        copy.setOnClickListener(v -> {
            if (plain.isEmpty()) {
                a.snack("Nada para copiar.", false);
            } else {
                a.copy(plain, "Copiado (" + plain.split("\n").length + " linhas).");
            }
        });
        tools.addView(copy);
        page.addView(tools, ui.gap(4));

        older = new MaterialSwitch(a);
        older.setText("Incluir inícios anteriores do servidor");
        older.setTextColor(ui.text);
        older.setOnCheckedChangeListener((s, on) -> load(true));
        // Erros: the switch and "Limpar lista" (chaos-ctl.sh errors clear: a marker in the log, nothing deleted)
        errorBar = ui.row();
        errorBar.addView(older, Ui.weight(1f));
        MaterialButton clearErrors = ui.flat("Limpar lista", 0);
        clearErrors.setOnClickListener(v -> a.confirm("Limpar a lista de erros?", "A lista passa a mostrar só os "
                + "erros que aparecerem daqui pra frente. O log do servidor não é apagado (Console ainda mostra tudo).",
                "Limpar", true, () -> a.ctlAction("errors clear", 30, f -> {
                    a.snack(f.ok ? "Lista de erros limpa." : f.title, f.ok);
                    if (f.ok) {
                        load(true);
                    }
                })));
        errorBar.addView(clearErrors);
        errorBar.setVisibility(View.GONE);
        page.addView(errorBar, Ui.matchWrap());

        info = ui.hint("");
        info.setTextSize(12);
        info.setPadding(ui.dp(2), 0, 0, ui.dp(6));
        page.addView(info);

        // ---- the text
        MaterialCardView card = ui.card();
        card.setCardBackgroundColor(ui.iron0);
        LinearLayout cb = Ui.body(card);
        cb.setPadding(ui.dp(10), ui.dp(8), ui.dp(10), ui.dp(8));
        out = ui.mono("");
        outScroll = new ScrollView(a);
        outScroll.addView(out, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        cb.addView(outScroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        page.addView(card, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        // ---- terminal input
        termBar = ui.column();
        termIn = ui.field("Comando", null, "", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        if (termIn.getEditText() != null) {
            termIn.getEditText().setTypeface(Typeface.MONOSPACE);
            termIn.getEditText().setImeOptions(EditorInfo.IME_ACTION_SEND);
            termIn.getEditText().setOnEditorActionListener((v, act, ev) -> {
                if (act == EditorInfo.IME_ACTION_SEND
                        || (ev != null && ev.getKeyCode() == KeyEvent.KEYCODE_ENTER && ev.getAction() == KeyEvent.ACTION_DOWN)) {
                    terminalRun();
                    return true;
                }
                return false;
            });
        }
        termBar.addView(termIn, ui.gap(8));
        MaterialButton send = ui.primary("Enviar", R.drawable.ic_send);
        send.setOnClickListener(v -> terminalRun());
        MaterialButton again = ui.secondary("Repetir", 0);
        again.setOnClickListener(v -> Ui.setValue(termIn, lastCommand));
        MaterialButton sudo = ui.secondary("sudo -n", 0);
        sudo.setOnClickListener(v -> {
            String t = Ui.value(termIn);
            if (!t.startsWith("sudo ")) {
                Ui.setValue(termIn, "sudo -n " + t);
            }
            if (termIn.getEditText() != null) {
                termIn.getEditText().setSelection(termIn.getEditText().getText().length());
            }
        });
        MaterialButton clear = ui.secondary("Limpar", 0);
        clear.setOnClickListener(v -> {
            term.setLength(0);
            render();
        });
        termBar.addView(ui.evenRow(send, again, sudo, clear), ui.gap(4));
        termBar.setVisibility(View.GONE);
        page.addView(termBar, Ui.matchWrap());

        root = page;
        setMode(CONSOLE, false);
    }

    /** The tab came on screen. */
    void shown() {
        if (mode != TERMINAL && plain.isEmpty()) {
            load(false);
        }
    }

    /** Every 5 s from the activity: reload when Acompanhar is on. */
    void tick() {
        if (follow.isChecked() && mode != TERMINAL) {
            load(false);
        }
    }

    void openErrors() {
        modes.check(modeIds[ERRORS]);
        setMode(ERRORS, true);
    }

    void openUpdate() {
        openUpdate("update-log");
    }

    /** Updates with one of its logs: update-log, publish-log or site-log. */
    void openUpdate(String log) {
        for (int i = 0; i < UPD_LOGS.length; i++) {
            if (UPD_LOGS[i].equals(log)) {
                updLog = i;
            }
        }
        plain = "";
        modes.check(modeIds[UPDATE]);
        setMode(UPDATE, true);
    }

    private void pickWhich() {
        if (mode == UPDATE) {
            new MaterialAlertDialogBuilder(a).setTitle("Qual log").setItems(UPD_NAMES, (d, w) -> {
                updLog = w;
                setWhich();
                load(true);
            }).show();
        } else if (mode == GM) {
            String[] items = new String[staffNames.length + 1];
            items[0] = "Todos";
            System.arraycopy(staffNames, 0, items, 1, staffNames.length);
            new MaterialAlertDialogBuilder(a).setTitle(staffNames.length == 0 ? "Nenhum log de staff ainda" : "Staff")
                    .setItems(items, (d, w) -> {
                        staff = w == 0 ? "" : items[w];
                        setWhich();
                        load(true);
                    }).show();
        }
    }

    private void setWhich() {
        which.setVisibility(mode == UPDATE || mode == GM ? View.VISIBLE : View.GONE);
        which.setText(mode == UPDATE ? UPD_NAMES[updLog] : "Staff: " + (staff.isEmpty() ? "todos" : staff));
    }

    private void setMode(int m, boolean fetch) {
        boolean changed = m != mode;
        mode = m;
        termBar.setVisibility(m == TERMINAL ? View.VISIBLE : View.GONE);
        errorBar.setVisibility(m == ERRORS ? View.VISIBLE : View.GONE);
        lines.setVisibility(m == TERMINAL ? View.GONE : View.VISIBLE);
        follow.setVisibility(m == TERMINAL ? View.GONE : View.VISIBLE);
        setWhich();
        if (m == TERMINAL) {
            info.setText("Como o usuário " + a.store.user() + ". Pasta: " + cwd);
            render();
        } else if (changed || plain.isEmpty()) {
            plain = "";
            out.setText("");
            info.setText("");
            if (fetch && a.store.configured()) {
                load(false);
            }
        }
    }

    private void pickLines() {
        String[] labels = new String[LINE_CHOICES.length];
        for (int i = 0; i < labels.length; i++) {
            labels[i] = LINE_CHOICES[i] + " linhas";
        }
        new MaterialAlertDialogBuilder(a).setTitle("Quantas linhas").setItems(labels, (d, w) -> {
            a.store.put("loglines", String.valueOf(LINE_CHOICES[w]));
            lines.setText(labels[w]);
            load(true);
        }).show();
    }

    private void load(boolean manual) {
        if (mode == TERMINAL) {
            return;
        }
        if (!a.store.configured()) {
            info.setText("Configure o servidor na aba Config.");
            return;
        }
        if (inflightMode == mode && !manual) {
            return;
        }
        inflightMode = mode;
        final int mine = ++seq;
        final int forMode = mode;
        int n = a.store.logLines();
        String args = forMode == CONSOLE ? "logs " + n
                : forMode == ERRORS ? "errors " + n + (older.isChecked() ? " all" : "")
                : forMode == GM ? "gm-logs " + n + (staff.isEmpty() ? "" : " " + Ssh.sq(staff))
                : UPD_LOGS[updLog] + " " + n;
        boolean atBottom = !outScroll.canScrollVertically(1);
        a.remote(a.ctl(args), 40, (r, e) -> {
            if (mine != seq) {
                return;
            }
            inflightMode = -1;
            if (forMode != mode) {
                return;
            }
            Friendly f = e != null ? Friendly.ofException(e) : Friendly.ofResult(r.out, r.code);
            if (!f.ok) {
                info.setText(f.title);
                out.setText(f.detail + "\n\n" + f.raw);
                plain = f.raw;
                if (manual) {
                    a.snack(f.title, false);
                }
                return;
            }
            plain = r.out;
            if (forMode == ERRORS) {
                renderErrors(r.out);
            } else if (forMode == GM) {
                renderGm(r.out);
            } else {
                out.setText(colourLog(r.out));
                int count = r.out.isEmpty() ? 0 : r.out.split("\n").length;
                info.setText(count == 0 ? (forMode == UPDATE ? "Nenhuma atualização registrada." : "Log vazio.")
                        : "Últimas " + count + " linhas" + (follow.isChecked() ? "  ·  acompanhando" : ""));
            }
            if (forMode != ERRORS && forMode != GM && (atBottom || manual || follow.isChecked())) {
                outScroll.post(() -> outScroll.fullScroll(View.FOCUS_DOWN));
            }
        });
    }

    /**
     * "chaos-ctl.sh gm-logs": "@staff" names, "@files" (date, size, name), "@commands NAME" (newest first) and "@panel"
     * (date, player, action, target, status, message; newest first).
     */
    private void renderGm(String text) {
        SpannableStringBuilder b = new SpannableStringBuilder();
        java.util.List<String> names = new java.util.ArrayList<>();
        String section = "";
        int rows = 0;
        for (String line : text.split("\n")) {
            if (line.startsWith("@")) {
                section = line;
                String head = line.equals("@staff") ? null
                        : line.equals("@files") ? "Arquivos em data/logs"
                        : line.startsWith("@commands ") ? "Comandos de " + line.substring(10) + " (mais novo primeiro)"
                        : line.equals("@panel") ? "Painel de admin (mais novo primeiro)" : line;
                if (head != null) {
                    if (b.length() > 0) {
                        b.append('\n');
                    }
                    int st = b.length();
                    b.append(head).append('\n');
                    b.setSpan(new ForegroundColorSpan(ui.goldLight), st, b.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                    b.setSpan(new StyleSpan(Typeface.BOLD), st, b.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                }
                continue;
            }
            if (line.trim().isEmpty()) {
                continue;
            }
            if (section.equals("@staff")) {
                names.add(line.trim());
            } else if (section.equals("@panel")) {
                String[] p = line.split("\t");
                int st = b.length();
                if (p.length >= 6) {
                    b.append(p[0]).append("  ").append(p[1]).append("  ").append(p[2])
                            .append(p[3].isEmpty() ? "" : " → " + p[3]).append("  [").append(p[4]).append("] ")
                            .append(p[5]).append('\n');
                    if (!p[4].equals("ok")) {
                        b.setSpan(new ForegroundColorSpan(ui.ember), st, b.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                    }
                } else {
                    b.append(line).append('\n');
                }
                rows++;
            } else if (section.equals("@files")) {
                String[] p = line.split("\t");
                b.append(p.length >= 3 ? p[0] + "  " + p[2] + "  (" + (UpdateInfo.num(p[1]) / 1024) + " KB)" : line).append('\n');
            } else {
                b.append(line).append('\n');
                rows++;
            }
        }
        staffNames = names.toArray(new String[0]);
        out.setText(b);
        info.setText(rows + " linhas" + (staff.isEmpty() ? " de todo o staff" : " de " + staff)
                + "  ·  " + staffNames.length + " com log");
        outScroll.post(() -> outScroll.fullScroll(View.FOCUS_UP));
    }

    /** Error lines in ember, warnings in gold. */
    private CharSequence colourLog(String text) {
        SpannableStringBuilder b = new SpannableStringBuilder();
        for (String line : text.split("\n", -1)) {
            int start = b.length();
            b.append(line).append('\n');
            String low = line.toLowerCase(Locale.ROOT);
            int colour = 0;
            if (low.contains("error") || low.contains("exception") || low.contains("segfault")) {
                colour = ui.ember;
            } else if (low.contains("warning") || low.contains("[warn")) {
                colour = ui.goldLight;
            } else if (low.contains("server online") || low.contains("starting the game server")) {
                colour = ui.ok;
            }
            if (colour != 0) {
                b.setSpan(new ForegroundColorSpan(colour), start, b.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
        }
        return b;
    }

    /**
     * "chaos-ctl.sh errors": "@run DATE [current]" per server start, "56x text [stamp]" per distinct error, "@older K".
     */
    private void renderErrors(String text) {
        SpannableStringBuilder b = new SpannableStringBuilder();
        Pattern entry = Pattern.compile("^(\\d+)x (.*)$");
        int total = 0;
        int distinct = 0;
        int olderRuns = 0;
        boolean currentEmpty = false;
        String lastRun = null;
        for (String line : text.split("\n")) {
            if (line.startsWith("@run ")) {
                if (lastRun != null && distinct == 0 && lastRun.endsWith(" current")) {
                    currentEmpty = true;
                }
                String r = line.substring(5).trim();
                boolean cur = r.endsWith(" current");
                String when = cur ? r.substring(0, r.length() - 8) : r;
                String head = (cur ? "Início atual do servidor: " : "Início anterior: ")
                        + (when.equals("unknown") ? "data desconhecida" : when);
                if (b.length() > 0) {
                    b.append('\n');
                }
                int s = b.length();
                b.append("── ").append(head).append(" ──\n");
                b.setSpan(new ForegroundColorSpan(ui.gold), s, b.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                b.setSpan(new StyleSpan(Typeface.BOLD), s, b.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                lastRun = r;
                distinct = 0;
                continue;
            }
            if (line.startsWith("@older ")) {
                try {
                    olderRuns = Integer.parseInt(line.substring(7).trim());
                } catch (NumberFormatException ignored) {
                    olderRuns = 0;
                }
                continue;
            }
            Matcher m = entry.matcher(line);
            if (m.find()) {
                int n = Integer.parseInt(m.group(1));
                total += n;
                distinct++;
                int s = b.length();
                String count = n > 1 ? "×" + n + " " : "";
                b.append(count);
                b.setSpan(new ForegroundColorSpan(ui.goldLight), s, b.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                b.setSpan(new StyleSpan(Typeface.BOLD), s, b.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
                int t = b.length();
                b.append(m.group(2).replace(" | ", "\n    ")).append("\n\n");
                b.setSpan(new ForegroundColorSpan(ui.ember), t, b.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            } else if (!line.trim().isEmpty()) {
                b.append(line).append('\n');
            }
        }
        if (lastRun != null && distinct == 0 && lastRun.endsWith(" current")) {
            currentEmpty = true;
        }
        if (currentEmpty) {
            b.append("Nenhum erro desde este início.\n");
        }
        out.setText(b);
        outScroll.post(() -> outScroll.scrollTo(0, 0));
        String summary = older.isChecked() ? total + " linhas de erro no log"
                : (total == 0 ? "Nenhum erro desde o último início" : total + " linhas de erro desde o último início");
        if (!older.isChecked() && olderRuns > 0) {
            summary += "  ·  " + olderRuns + (olderRuns == 1 ? " início anterior teve erros" : " inícios anteriores tiveram erros");
        }
        info.setText(summary);
    }

    // ------------------------------------------------------------------------------------------------ terminal

    private void terminalRun() {
        String c = Ui.value(termIn);
        if (c.isEmpty()) {
            return;
        }
        if (!a.store.configured()) {
            a.snack("Configure o servidor na aba Config.", false);
            return;
        }
        lastCommand = c;
        Ui.setValue(termIn, "");
        term.append("\n$ ").append(c).append('\n');
        render();
        String wrapped = "cd " + (cwd.equals("~") ? "~" : Ssh.sq(cwd)) + " 2>/dev/null\n" + c
                + "\nprintf '\\n__CWD__%s\\n' \"$(pwd)\"";
        a.remote(wrapped, 300, (r, e) -> {
            String o;
            if (e != null) {
                Friendly f = Friendly.ofException(e);
                o = f.title + ": " + f.detail;
            } else {
                o = r.out;
                int at = o.lastIndexOf("__CWD__");
                if (at >= 0) {
                    String dir = o.substring(at + 7).trim();
                    if (!dir.isEmpty()) {
                        cwd = dir;
                    }
                    o = o.substring(0, at).replaceAll("\\s+$", "");
                }
                if (r.code > 0) {
                    o += "\n[código " + r.code + "]";
                }
            }
            if (o.length() > 20000) {
                o = "..." + o.substring(o.length() - 20000);
            }
            term.append(o).append("\n[").append(cwd).append("]\n");
            if (term.length() > 60000) {
                term.delete(0, term.length() - 40000);
            }
            if (mode == TERMINAL) {
                info.setText("Como o usuário " + a.store.user() + ". Pasta: " + cwd);
                render();
            }
        });
    }

    private void render() {
        if (mode != TERMINAL) {
            return;
        }
        plain = term.toString();
        SpannableStringBuilder b = new SpannableStringBuilder();
        for (String line : plain.split("\n", -1)) {
            int s = b.length();
            b.append(line).append('\n');
            if (line.startsWith("$ ")) {
                b.setSpan(new ForegroundColorSpan(ui.goldLight), s, b.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            } else if (line.startsWith("[") && line.endsWith("]")) {
                b.setSpan(new ForegroundColorSpan(ui.muted), s, b.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            }
        }
        out.setText(b);
        outScroll.post(() -> outScroll.fullScroll(View.FOCUS_DOWN));
    }
}
