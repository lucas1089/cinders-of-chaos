package com.cindersofchaos.admin;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Bugs e sugestões dos jogadores: the reading of chaos-ctl.sh feedback (plain text, one block per report, written by
 * server/tools/feedback_format.py), the command lines the card sends (only a checked number of days and a fixed
 * category word, an id from a parsed block) and the text copied for pasting to Claude. Pure Java, no Android classes.
 * The server never prints account ids, IPs or e-mails, and the character name only with --names (the card never asks).
 */
final class FeedbackInfo {
    static final int DEFAULT_DAYS = 30;
    static final int MAX_DAYS = 3650;

    /** Category word of the server -> label in the app, in the order of the filter. */
    static final String[] CATEGORIES = {"map", "typo", "technical", "other", "suggestion"};

    static final class Item {
        int id;
        String when = "";
        String category = "other";
        boolean closed;
        String pos = "";
        String who = "";
        String text = "";
        String closedNote = "";
        /** The block as the server printed it (what "Copiar tudo" pastes). */
        String raw = "";
    }

    private static final Pattern HEAD = Pattern.compile(
            "^#(\\d{1,9}) \\| (\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2} UTC) \\| ([a-z]{3,12}) \\| (open|closed) \\| pos (\\d+,\\d+,\\d+)"
                    + "(?: \\| (.{1,60}))?$");

    /** Control and format characters out (a second line of defence; the server strips them too), one line. */
    static String clean(String s) {
        if (s == null) {
            return "";
        }
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            int t = Character.getType(c);
            if (c == '\t' || c == '\r' || c == '\n') {
                b.append(' ');
            } else if (t == Character.CONTROL || t == Character.FORMAT) {
                continue;
            } else {
                b.append(c);
            }
        }
        return b.toString().replaceAll(" +", " ").trim();
    }

    /** The reports of a feedback output, in the order printed. Lines that are no block (the footer, an error) are ignored. */
    static List<Item> parse(String out) {
        List<Item> list = new ArrayList<>();
        if (out == null) {
            return list;
        }
        Item cur = null;
        StringBuilder raw = null;
        boolean haveText = false;
        for (String line : out.split("\n", -1)) {
            line = line.replace("\r", "");
            Matcher m = HEAD.matcher(line);
            if (m.matches()) {
                finish(list, cur, raw);
                cur = new Item();
                cur.id = Integer.parseInt(m.group(1));
                cur.when = m.group(2);
                cur.category = m.group(3);
                cur.closed = m.group(4).equals("closed");
                cur.pos = m.group(5);
                cur.who = m.group(6) == null ? "" : clean(m.group(6));
                raw = new StringBuilder(line);
                haveText = false;
            } else if (cur != null && line.startsWith("  ")) {
                String body = line.substring(2);
                raw.append('\n').append(line);
                if (haveText && body.startsWith("closed: ")) {
                    cur.closedNote = clean(body.substring(8));
                } else if (haveText && body.startsWith("from: ")) {
                    continue; // never shown: the app does not ask for names
                } else if (!haveText) {
                    cur.text = clean(body);
                    haveText = true;
                }
            } else if (line.startsWith("--")) {
                finish(list, cur, raw);
                cur = null;
                raw = null;
            }
        }
        finish(list, cur, raw);
        return list;
    }

    private static void finish(List<Item> list, Item cur, StringBuilder raw) {
        if (cur != null) {
            cur.raw = raw.toString();
            list.add(cur);
        }
    }

    static String categoryLabel(String c) {
        switch (c) {
            case "map": return "Mapa";
            case "typo": return "Texto errado";
            case "technical": return "Técnico";
            case "suggestion": return "Sugestão";
            default: return "Outro";
        }
    }

    /** The days field: 1 to 3650, else -1. */
    static int days(String s) {
        if (s == null || !s.trim().matches("[0-9]{1,4}")) {
            return -1;
        }
        int n = Integer.parseInt(s.trim());
        return n >= 1 && n <= MAX_DAYS ? n : -1;
    }

    /** Arguments of chaos-ctl.sh for the list; category "" or "all" = every one. */
    static String listArgs(int days, boolean all, String category) {
        StringBuilder b = new StringBuilder("feedback --days ").append(days);
        if (all) {
            b.append(" --all");
        }
        for (String c : CATEGORIES) {
            if (c.equals(category)) {
                b.append(" --category ").append(c);
            }
        }
        return b.toString();
    }

    /** Arguments to close one report; the note (already shell quoted by the caller) is optional. */
    static String closeArgs(int id, String quotedNote) {
        return "feedback-close " + id + (quotedNote == null || quotedNote.isEmpty() ? "" : " " + quotedNote);
    }

    /** One line over the list: "3 abertos, 1 sugestão." */
    static String summary(List<Item> list) {
        if (list.isEmpty()) {
            return "Nenhum relato neste período.";
        }
        int open = 0;
        int sug = 0;
        for (Item i : list) {
            if (!i.closed) {
                open++;
            }
            if (i.category.equals("suggestion")) {
                sug++;
            }
        }
        return list.size() + (list.size() == 1 ? " relato" : " relatos") + ", " + open
                + (open == 1 ? " aberto" : " abertos") + ", " + sug + (sug == 1 ? " sugestão." : " sugestões.");
    }

    /** What "Copiar tudo" puts on the clipboard: a short ask for Claude, then the blocks as the server printed them. */
    static String copyAll(List<Item> list) {
        StringBuilder b = new StringBuilder("Relatos de bugs e sugestões dos jogadores do Cinders of Chaos ("
                + list.size() + ", mais novos primeiro; sem nomes de jogadores). Classifique cada um (bug real, "
                + "sugestão, duplicado, descartar), priorize e proponha os próximos passos.\n\n");
        for (Item i : list) {
            b.append(i.raw).append('\n');
        }
        return b.toString();
    }
}
