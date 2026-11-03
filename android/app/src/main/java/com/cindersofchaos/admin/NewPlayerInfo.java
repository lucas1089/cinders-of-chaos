package com.cindersofchaos.admin;

/**
 * Novos jogadores (O374): the command lines of the card (chaos-ctl.sh newplayer-funnel / survey, always with --pt and a
 * checked number of days) and the reading of their text. Pure Java, tested by NewPlayerInfoTest on a plain JVM.
 * server/README.md "New player funnel and survey (O374)".
 */
final class NewPlayerInfo {
    static final int DEFAULT_DAYS = 30;
    static final int MAX_DAYS = 3650;

    private NewPlayerInfo() {
    }

    /** The days field: 1 to 3650, else -1. */
    static int days(String s) {
        if (s == null || !s.trim().matches("[0-9]{1,4}")) {
            return -1;
        }
        int n = Integer.parseInt(s.trim());
        return n >= 1 && n <= MAX_DAYS ? n : -1;
    }

    /** chaos-ctl.sh arguments of the funnel report (Portuguese text). */
    static String funnelArgs(int days) {
        String cmd = "newplayer-funnel --pt --days " + days;
        return cmd;
    }

    /** chaos-ctl.sh arguments of the survey report (Portuguese text, at most 100 texts per stage). */
    static String surveyArgs(int days) {
        String cmd = "survey --pt --texts 100 --days " + days;
        return cmd;
    }

    /** The first line of a report, for the summary line under the buttons; "" for no output. */
    static String headline(String out) {
        if (out == null) {
            return "";
        }
        for (String line : out.split("\n", -1)) {
            String t = line.trim();
            if (!t.isEmpty()) {
                return t;
            }
        }
        return "";
    }

    /** The report without control characters (the server cleaned the texts already; this keeps the view safe). */
    static String clean(String out) {
        if (out == null) {
            return "";
        }
        StringBuilder b = new StringBuilder(out.length());
        for (int i = 0; i < out.length(); i++) {
            char c = out.charAt(i);
            if (c == '\n' || (c >= 0x20 && c != 0x7f && !(c >= 0x200b && c <= 0x200f) && !(c >= 0x2028 && c <= 0x202e)
                    && !(c >= 0x2060 && c <= 0x2064) && c != 0xfeff)) {
                b.append(c);
            }
        }
        return b.toString().trim();
    }
}
