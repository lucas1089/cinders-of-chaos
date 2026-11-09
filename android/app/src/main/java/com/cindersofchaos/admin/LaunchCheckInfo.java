package com.cindersofchaos.admin;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Conferir lançamento (O440): the reading of chaos-ctl.sh launch-check (one line per check: OK, WARN or FAIL, a short
 * name and one sentence, then a summary line), the one-line summary in Portuguese and the order of the lines (FAIL
 * first, then WARN, then OK; the order of the tool inside each group). The command exits 1 when a check is FAIL, so the
 * lines are read whatever the exit code was. Pure Java, tested by LaunchCheckInfoTest on a plain JVM. server/README.md
 * "Launch check (O440)".
 */
final class LaunchCheckInfo {
    static final String COMMAND = "launch-check";
    private static final Pattern LINE = Pattern.compile("^(OK|WARN|FAIL)\\s+(\\S+)\\s+(.*)$");

    private LaunchCheckInfo() {
    }

    /** One check of the report. */
    static final class Line {
        final String status;
        final String name;
        final String text;

        Line(String status, String name, String text) {
            this.status = status;
            this.name = name;
            this.text = text;
        }

        /** "FALHA", "AVISO" or "OK". */
        String label() {
            return status.equals("FAIL") ? "FALHA" : status.equals("WARN") ? "AVISO" : "OK";
        }
    }

    /** The checks of one report, in the order of the tool, with their counts. */
    static final class Report {
        final List<Line> lines;
        final int fails;
        final int warns;
        final int oks;

        Report(List<Line> lines) {
            this.lines = lines;
            int f = 0;
            int w = 0;
            int o = 0;
            for (Line l : lines) {
                if (l.status.equals("FAIL")) {
                    f++;
                } else if (l.status.equals("WARN")) {
                    w++;
                } else {
                    o++;
                }
            }
            fails = f;
            warns = w;
            oks = o;
        }
    }

    /** The report in the command's output, or null when it has no check line (a refusal, an ssh error). */
    static Report parse(String out) {
        if (out == null) {
            return null;
        }
        List<Line> lines = new ArrayList<>();
        for (String raw : out.split("\n")) {
            Matcher m = LINE.matcher(raw.trim());
            if (m.find()) {
                lines.add(new Line(m.group(1), m.group(2), m.group(3).trim()));
            }
        }
        return lines.isEmpty() ? null : new Report(lines);
    }

    /** "3 falhas, 2 avisos", "1 falha", "2 avisos", or "Tudo certo para o lançamento" when nothing is FAIL or WARN. */
    static String summary(Report r) {
        if (r == null) {
            return "";
        }
        if (r.fails == 0 && r.warns == 0) {
            return "Tudo certo para o lançamento";
        }
        StringBuilder b = new StringBuilder();
        if (r.fails > 0) {
            b.append(r.fails).append(r.fails == 1 ? " falha" : " falhas");
        }
        if (r.warns > 0) {
            if (b.length() > 0) {
                b.append(", ");
            }
            b.append(r.warns).append(r.warns == 1 ? " aviso" : " avisos");
        }
        return b.toString();
    }

    /** The lines, FAIL first, then WARN, then OK; the order of the tool is kept inside each group. */
    static List<Line> ordered(Report r) {
        List<Line> out = new ArrayList<>();
        if (r == null) {
            return out;
        }
        for (String s : new String[] {"FAIL", "WARN", "OK"}) {
            for (Line l : r.lines) {
                if (l.status.equals(s)) {
                    out.add(l);
                }
            }
        }
        return out;
    }

    /** The text under the summary: one line per check, "FALHA  name  sentence", in the order of ordered(). */
    static String render(Report r) {
        StringBuilder b = new StringBuilder();
        for (Line l : ordered(r)) {
            if (b.length() > 0) {
                b.append('\n');
            }
            b.append(l.label()).append("  ").append(l.name).append("  ").append(l.text);
        }
        return b.toString();
    }
}
