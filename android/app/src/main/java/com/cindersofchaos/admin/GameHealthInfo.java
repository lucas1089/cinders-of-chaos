package com.cindersofchaos.admin;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Saúde do jogo (O397) and Relatório de equilíbrio (O398): the command lines of the cards and the reading of
 * chaos-ctl.sh game-health --kv (key=value lines of server/tools/game_health.py). Pure Java, no Android classes, tested
 * by GameHealthInfoTest on a plain JVM. Counts of 1 to 4 characters come as "<5" (SMALL here).
 * server/README.md "Game health panel (O397)", "Season balance report (O398)".
 */
final class GameHealthInfo {
    static final int DEFAULT_DAYS = 7;
    static final int MAX_DAYS = 90;
    static final int BALANCE_DAYS = 30;
    static final int BALANCE_MAX_DAYS = 730;
    private static final Locale PT = Locale.forLanguageTag("pt-BR");
    /** A count the server hides (1 to 4 characters). */
    static final long SMALL = -1;

    /** One hour of the window: mean and peak online (-1 when no sample), deaths. */
    static final class Hour {
        long at;
        String day = "";
        int hour;
        double mean = -1;
        long peak = -1;
        long deaths;
    }

    /** A hunt: character-hours (SMALL hidden), hunting hours, kills, deaths, name. */
    static final class Hunt {
        long visits;
        double hours;
        long kills;
        long deaths;
        String name = "";
    }

    /** A labelled count with its share (-1: none): funnel rows, gold rows. */
    static final class Row {
        String label = "";
        long count;
        double pct = -1;
        long extra;
    }

    boolean ok;
    String error = "";
    int days;
    String onlineMean = "-";
    String onlinePeak = "-";
    String onlinePeakAt = "-";
    int busiestHour = -1;
    int quietestHour = -1;
    long deathsTotal;
    String deathsPerHour = "-";
    String deathsPerPlayHour = "-";
    int huntsKnown;
    int huntsUnvisited;
    long goldIn;
    long goldOut;
    long goldNet;
    String funnelCharacters = "0";
    int funnelDays = 30;
    String funnelStopped = "";
    final List<Hour> hours = new ArrayList<>();
    final List<Hunt> top = new ArrayList<>();
    final List<Hunt> low = new ArrayList<>();
    final List<Row> gold = new ArrayList<>();
    final List<Row> reached = new ArrayList<>();
    final List<Row> stopLevel = new ArrayList<>();
    final List<Row> stopSystem = new ArrayList<>();

    private GameHealthInfo() {
    }

    /** The days field: 1 to max, else -1. */
    static int days(String s, int max) {
        if (s == null || !s.trim().matches("[0-9]{1,4}")) {
            return -1;
        }
        int n = Integer.parseInt(s.trim());
        return n >= 1 && n <= max ? n : -1;
    }

    static String healthArgs(int days) {
        String cmd = "game-health --kv --pt --days " + days;
        return cmd;
    }

    /** balance-report over the last N days (text in Portuguese); save: also keep it on the server and DM the owner. */
    static String balanceDaysArgs(int days, boolean dm) {
        String cmd = "balance-report --pt --days " + days;
        return dm ? cmd + " --dm" : cmd;
    }

    static String balanceSeasonArgs(boolean dm) {
        return "balance-report --pt --season current" + (dm ? " --dm" : "");
    }

    /** The newest report saved on the server (season end or --dm). */
    static String balanceLastArgs() {
        return "balance-report last";
    }

    /** The daily timer that writes the report when a season ends: on, off or status. */
    static String balanceTimerArgs(String what) {
        return "balance-report timer " + (what.equals("on") || what.equals("off") ? what : "status");
    }

    static long count(String s) {
        if (s == null || s.startsWith("<")) {
            return SMALL;
        }
        try {
            return Long.parseLong(s.trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    static double dbl(String s) {
        if (s == null || s.equals("-")) {
            return -1;
        }
        try {
            return Double.parseDouble(s.trim());
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    static int small(String s) {
        try {
            return Integer.parseInt(s.trim());
        } catch (NumberFormatException | NullPointerException e) {
            return -1;
        }
    }

    /** "<5" for a hidden count. */
    static String n(long v) {
        return v == SMALL ? "<5" : String.valueOf(v);
    }

    /** 1234567 -> "1.234.567" (pt-BR digit groups). */
    static String gold(long v) {
        String s = String.valueOf(Math.abs(v));
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            if (i > 0 && (s.length() - i) % 3 == 0) {
                b.append('.');
            }
            b.append(s.charAt(i));
        }
        return (v < 0 ? "-" : "") + b;
    }

    /** "12,5%" or "" when there is no share. */
    static String pct(double v) {
        if (v < 0) {
            return "";
        }
        return String.format(PT, "%.1f%%", v);
    }

    /** The parts of "a b c rest of the line": the first n-1 split on spaces, the last one keeps its spaces. */
    static String[] fields(String v, int n) {
        String[] p = v.trim().split(" ", n);
        if (p.length < n) {
            return null;
        }
        return p;
    }

    private static Row row(String label, String count, String pct) {
        Row r = new Row();
        r.label = label;
        r.count = count(count);
        r.pct = dbl(pct);
        return r;
    }

    /** chaos-ctl.sh game-health --kv; null when the output is no report at all. */
    static GameHealthInfo parse(String out) {
        if (out == null) {
            return null;
        }
        GameHealthInfo g = new GameHealthInfo();
        boolean any = false;
        for (String line : out.split("\n")) {
            int eq = line.indexOf('=');
            if (eq <= 0) {
                continue;
            }
            String k = line.substring(0, eq).trim();
            String v = line.substring(eq + 1).trim();
            String[] p;
            switch (k) {
                case "ok":
                    any = true;
                    g.ok = v.equals("1");
                    break;
                case "error":
                    g.error = v;
                    break;
                case "days":
                    g.days = small(v);
                    break;
                case "online_mean":
                    g.onlineMean = v;
                    break;
                case "online_peak":
                    g.onlinePeak = v;
                    break;
                case "online_peak_at":
                    g.onlinePeakAt = v;
                    break;
                case "online_busiest_hour":
                    g.busiestHour = small(v);
                    break;
                case "online_quietest_hour":
                    g.quietestHour = small(v);
                    break;
                case "deaths_total":
                    g.deathsTotal = Math.max(0, count(v));
                    break;
                case "deaths_per_hour":
                    g.deathsPerHour = v;
                    break;
                case "deaths_per_play_hour":
                    g.deathsPerPlayHour = v;
                    break;
                case "hour":
                    p = fields(v, 6);
                    if (p != null) {
                        Hour h = new Hour();
                        h.at = Math.max(0, count(p[0]));
                        h.day = p[1];
                        h.hour = small(p[2]);
                        h.mean = dbl(p[3]);
                        h.peak = p[4].equals("-") ? -1 : count(p[4]);
                        h.deaths = Math.max(0, count(p[5]));
                        g.hours.add(h);
                    }
                    break;
                case "hunts_known":
                    g.huntsKnown = small(v);
                    break;
                case "hunts_unvisited":
                    g.huntsUnvisited = small(v);
                    break;
                case "hunt_top":
                case "hunt_low":
                    p = fields(v, 5);
                    if (p != null) {
                        Hunt h = new Hunt();
                        h.visits = count(p[0]);
                        h.hours = Math.max(0, dbl(p[1]));
                        h.kills = Math.max(0, count(p[2]));
                        h.deaths = Math.max(0, count(p[3]));
                        h.name = p[4];
                        (k.equals("hunt_top") ? g.top : g.low).add(h);
                    }
                    break;
                case "gold_in":
                    g.goldIn = count(v);
                    break;
                case "gold_out":
                    g.goldOut = count(v);
                    break;
                case "gold_net":
                    g.goldNet = v.startsWith("-") ? -count(v.substring(1)) : count(v);
                    break;
                case "gold":
                    p = fields(v, 4);
                    if (p != null) {
                        Row r = row((p[0].equals("faucet") ? "entra: " : "sai: ") + p[3], p[1], "-");
                        r.extra = Math.max(0, count(p[2]));
                        g.gold.add(r);
                    }
                    break;
                case "funnel_days":
                    g.funnelDays = small(v);
                    break;
                case "funnel_characters":
                    g.funnelCharacters = v;
                    break;
                case "funnel_reached":
                    p = fields(v, 3);
                    if (p != null) {
                        g.reached.add(row("Nível " + p[0], p[1], p[2]));
                    }
                    break;
                case "funnel_stopped":
                    p = fields(v, 3);
                    if (p != null) {
                        g.funnelStopped = p[0] + " de " + p[1] + (dbl(p[2]) < 0 ? "" : " (" + pct(dbl(p[2])) + ")");
                    }
                    break;
                case "funnel_stop_level":
                    p = fields(v, 3);
                    if (p != null) {
                        g.stopLevel.add(row("Nível " + p[2], p[0], p[1]));
                    }
                    break;
                case "funnel_stop_system":
                    p = fields(v, 3);
                    if (p != null) {
                        g.stopSystem.add(row(p[2], p[0], p[1]));
                    }
                    break;
                default:
                    break;
            }
        }
        return any ? g : null;
    }

    /** The highest peak of the window (for the chart's scale), at least 1. */
    long maxPeak() {
        long m = 1;
        for (Hour h : hours) {
            m = Math.max(m, Math.max(h.peak, (long) Math.ceil(h.mean)));
        }
        return m;
    }

    /** Mean online per hour of the day (0 to 23) over the window; -1 where no sample. */
    double[] byHourOfDay() {
        double[] sum = new double[24];
        int[] n = new int[24];
        for (Hour h : hours) {
            if (h.mean >= 0 && h.hour >= 0 && h.hour < 24) {
                sum[h.hour] += h.mean;
                n[h.hour]++;
            }
        }
        double[] out = new double[24];
        for (int i = 0; i < 24; i++) {
            out[i] = n[i] == 0 ? -1 : sum[i] / n[i];
        }
        return out;
    }

    /** The summary line under the button. */
    String headline() {
        if (!ok) {
            return errorText();
        }
        return "Últimos " + days + " dias: média de " + onlineMean.replace('.', ',') + " online, pico de " + onlinePeak
                + " (" + onlinePeakAt + "); " + deathsTotal + " mortes ("
                + deathsPerPlayHour.replace('.', ',') + " por hora de jogo).";
    }

    String errorText() {
        if (error.equals("no-table")) {
            return "As tabelas da telemetria ainda não existem: rode o passo sql do install_all.py (ou reinicie o servidor).";
        }
        if (error.equals("database")) {
            return "Não deu para ler o banco de dados (está no ar?).";
        }
        return "Erro: " + (error.isEmpty() ? "resposta vazia" : error);
    }
}
