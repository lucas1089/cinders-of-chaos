package com.cindersofchaos.admin;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * The progress metrics in Portuguese: what chaos-ctl.sh metrics --json reports (anonymous aggregate counters: churn
 * by level band, deaths by area and by monster, first session, median time to level). Read only. Pure Java apart from
 * org.json, no views.
 */
final class MetricsInfo {
    static final Locale PT = new Locale("pt", "BR");

    /** A count the server hides because fewer than 5 players are behind it (it sends the text "<5"). */
    static final long SMALL = -1;

    static long count(JSONObject o, String key) {
        return o.opt(key) instanceof String ? SMALL : o.optLong(key, 0);
    }

    /** The count as text: "<5" for a hidden one. */
    static String n(long v) {
        return v == SMALL ? "<5" : String.valueOf(v);
    }

    static final class Band {
        String band = "";
        long gone;
        long active;
        double gonePct;
    }

    static final class Killer {
        String name = "";
        long deaths;
        String topBand = "";
    }

    static final class Bucket {
        String bucket = "";
        long characters;
        double pct;
    }

    static final class Milestone {
        int level;
        double medianMinutes = -1;
        long characters;
    }

    /** O258: a cohort week of new characters and how many came back on day 1 / 3 / 7 or later (pN: share, -1 hidden). */
    static final class Week {
        String week = "";
        long cohort;
        final long[] back = new long[3];
        final double[] pct = {-1, -1, -1};
    }

    /** O437: the retention windows in the order of the report: day 1, days 2-7, days 8-30, any of 1-7, any of 1-30. */
    static final String[] RETAIN_KEYS = {"d1", "d2_7", "d8_30", "in7", "in30"};
    static final String[] RETAIN_LABELS = {"dia 1", "dias 2-7", "dias 8-30", "algum dia de 1-7", "algum dia de 1-30"};

    /** O437: a cohort day (first-login day) and how many came back per window (pct -1: hidden, unfinished or partial). */
    static final class CohortDay {
        String day = "";
        long cohort;
        boolean covered = true;
        final long[] back = new long[5];
        final double[] pct = {-1, -1, -1, -1, -1};
    }

    /** O437: the total of one window over every cohort day that qualifies. */
    static final class RetainTotal {
        String window = "";
        long cohort;
        long back;
        double pct = -1;
    }

    /** O258: the first use of one system (characters, share of all characters, median played minutes, top band). */
    static final class FirstUse {
        String system = "";
        long characters;
        double pct = -1;
        double medianMinutes = -1;
        String topBand = "";
    }

    boolean ok;
    String error = "";
    boolean empty;
    int churnDays;
    long churnAt;
    long gone;
    long active;
    final List<Band> bands = new ArrayList<>();
    final List<Killer> areas = new ArrayList<>();
    final List<Killer> monsters = new ArrayList<>();
    final List<Bucket> sessions = new ArrayList<>();
    long sessionCharacters;
    final List<Milestone> milestones = new ArrayList<>();
    final List<Week> weeks = new ArrayList<>();
    final List<CohortDay> cohortDays = new ArrayList<>();
    final List<RetainTotal> retainTotals = new ArrayList<>();
    String retainSince = "";
    final List<FirstUse> firstUses = new ArrayList<>();
    final List<Killer> stops = new ArrayList<>();

    /** Parses the one JSON line (other lines, such as ssh banners, are skipped); null when there is none. */
    static MetricsInfo parse(String out) {
        if (out == null) {
            return null;
        }
        for (String line : out.split("\n")) {
            String t = line.trim();
            if (!t.startsWith("{")) {
                continue;
            }
            try {
                return fromJson(new JSONObject(t));
            } catch (JSONException ignored) {
                // not the answer; try the next line
            }
        }
        return null;
    }

    static MetricsInfo fromJson(JSONObject o) {
        MetricsInfo m = new MetricsInfo();
        m.ok = o.optBoolean("ok", false);
        m.error = o.optString("error", "");
        if (!m.ok) {
            return m;
        }
        m.empty = o.optBoolean("empty", false);
        JSONObject churn = o.optJSONObject("churn");
        if (churn != null) {
            m.churnDays = churn.optInt("days", 0);
            m.churnAt = churn.optLong("at", 0);
            m.gone = count(churn, "gone");
            m.active = count(churn, "active");
            JSONArray arr = churn.optJSONArray("bands");
            for (int i = 0; arr != null && i < arr.length(); i++) {
                JSONObject b = arr.optJSONObject(i);
                if (b == null) {
                    continue;
                }
                Band x = new Band();
                x.band = b.optString("band", "");
                x.gone = count(b, "gone");
                x.active = count(b, "active");
                x.gonePct = b.isNull("gonePct") ? -1 : b.optDouble("gonePct", 0);
                m.bands.add(x);
            }
        }
        killers(o.optJSONArray("deathAreas"), m.areas, "deaths");
        killers(o.optJSONArray("deathMonsters"), m.monsters, "deaths");
        killers(o.optJSONArray("stops"), m.stops, "gone");
        JSONArray wk = o.optJSONArray("returns");
        for (int i = 0; wk != null && i < wk.length(); i++) {
            JSONObject b = wk.optJSONObject(i);
            if (b == null) {
                continue;
            }
            Week x = new Week();
            x.week = b.optString("week", "");
            x.cohort = count(b, "cohort");
            String[] keys = {"d1", "d3", "d7"};
            for (int k = 0; k < 3; k++) {
                x.back[k] = count(b, keys[k]);
                x.pct[k] = b.isNull(keys[k] + "Pct") ? -1 : b.optDouble(keys[k] + "Pct", -1);
            }
            m.weeks.add(x);
        }
        m.retainSince = o.isNull("retentionSince") ? "" : o.optString("retentionSince", "");
        JSONArray rt = o.optJSONArray("retention");
        for (int i = 0; rt != null && i < rt.length(); i++) {
            JSONObject b = rt.optJSONObject(i);
            if (b == null) {
                continue;
            }
            CohortDay x = new CohortDay();
            x.day = b.optString("day", "");
            x.cohort = count(b, "cohort");
            x.covered = b.optBoolean("covered", true);
            for (int k = 0; k < RETAIN_KEYS.length; k++) {
                x.back[k] = count(b, RETAIN_KEYS[k]);
                x.pct[k] = b.isNull(RETAIN_KEYS[k] + "Pct") ? -1 : b.optDouble(RETAIN_KEYS[k] + "Pct", -1);
            }
            m.cohortDays.add(x);
        }
        JSONArray ra = o.optJSONArray("retentionAll");
        for (int i = 0; ra != null && i < ra.length(); i++) {
            JSONObject b = ra.optJSONObject(i);
            if (b == null) {
                continue;
            }
            RetainTotal x = new RetainTotal();
            x.window = b.optString("window", "");
            x.cohort = count(b, "cohort");
            x.back = count(b, "back");
            x.pct = b.isNull("pct") ? -1 : b.optDouble("pct", -1);
            m.retainTotals.add(x);
        }
        JSONArray fu = o.optJSONArray("firstUse");
        for (int i = 0; fu != null && i < fu.length(); i++) {
            JSONObject b = fu.optJSONObject(i);
            if (b == null) {
                continue;
            }
            FirstUse x = new FirstUse();
            x.system = b.optString("system", "");
            x.characters = count(b, "characters");
            x.pct = b.isNull("pct") ? -1 : b.optDouble("pct", -1);
            x.medianMinutes = b.isNull("medianMinutes") ? -1 : b.optDouble("medianMinutes", -1);
            x.topBand = b.optString("topBand", "");
            m.firstUses.add(x);
        }
        m.sessionCharacters = count(o, "firstSessionCharacters");
        JSONArray fs = o.optJSONArray("firstSession");
        for (int i = 0; fs != null && i < fs.length(); i++) {
            JSONObject b = fs.optJSONObject(i);
            if (b == null) {
                continue;
            }
            Bucket x = new Bucket();
            x.bucket = b.optString("bucket", "");
            x.characters = count(b, "characters");
            x.pct = b.isNull("pct") ? -1 : b.optDouble("pct", 0);
            m.sessions.add(x);
        }
        JSONArray ms = o.optJSONArray("milestones");
        for (int i = 0; ms != null && i < ms.length(); i++) {
            JSONObject b = ms.optJSONObject(i);
            if (b == null) {
                continue;
            }
            Milestone x = new Milestone();
            x.level = b.optInt("level", 0);
            x.medianMinutes = b.isNull("medianMinutes") ? -1 : b.optDouble("medianMinutes", -1);
            x.characters = count(b, "characters");
            m.milestones.add(x);
        }
        return m;
    }

    private static void killers(JSONArray arr, List<Killer> into, String field) {
        for (int i = 0; arr != null && i < arr.length(); i++) {
            JSONObject b = arr.optJSONObject(i);
            if (b == null) {
                continue;
            }
            Killer k = new Killer();
            k.name = b.optString("name", "");
            k.deaths = count(b, field);
            k.topBand = b.optString("topBand", "");
            into.add(k);
        }
    }

    /** Why the numbers could not be read, in Portuguese. */
    String errorText() {
        switch (error) {
            case "no-table":
                return "A tabela de métricas ainda não existe. Atualize o servidor (passo sql do install_all.py) e "
                        + "reinicie; ela se enche com o jogo.";
            case "database":
                return "Não consegui ler o banco de dados do servidor.";
            default:
                return "Resposta inesperada do servidor" + (error.isEmpty() ? "." : " (" + error + ").");
        }
    }

    /** A system of the first-use list in Portuguese; an unknown key is shown as it is. */
    static String systemName(String key) {
        switch (key) {
            case "dungeon": return "Masmorra";
            case "rift": return "Fenda";
            case "waystone": return "Pedra-guia";
            case "tower": return "Torre Infinita";
            case "pocketboss": return "Chefe de bolso";
            case "worldboss": return "Chefe mundial";
            case "invasion": return "Invasão";
            case "party": return "Grupo";
            case "guild": return "Guilda";
            case "market": return "Mercado";
            case "bounty": return "Contrato de caça";
            case "craft": return "Criação";
            default: return key;
        }
    }

    /** A bar's length from 0 to 100 for value out of max. */
    static int percent(long value, long max) {
        if (max <= 0 || value <= 0) {
            return 0;
        }
        return (int) Math.min(100, Math.round(value * 100.0 / max));
    }

    static String pct(double v) {
        if (v < 0) {
            return "<5";
        }
        return String.format(PT, "%.1f%%", v);
    }

    /** 15 min, 3,5 h, 2,0 dias; "sem dados" for none. */
    static String minutes(double m) {
        if (m < 0) {
            return "sem dados";
        }
        if (m < 90) {
            return Math.round(m) + " min";
        }
        if (m < 48 * 60) {
            return String.format(PT, "%.1f h", m / 60.0);
        }
        return String.format(PT, "%.1f dias", m / 1440.0);
    }

    /** "até 30 min" or "mais de 480 min" for a first-session bucket (the last one is "inf"). */
    static String bucketText(String bucket, String previous) {
        if (bucket.equals("inf")) {
            return previous.isEmpty() ? "mais longa" : "mais de " + previous + " min";
        }
        return "até " + bucket + " min";
    }

    /** The label of a retention window key in Portuguese; an unknown key is shown as it is. */
    static String retainLabel(String key) {
        for (int i = 0; i < RETAIN_KEYS.length; i++) {
            if (RETAIN_KEYS[i].equals(key)) {
                return RETAIN_LABELS[i];
            }
        }
        return key;
    }

    /** "2026-11-10" as "10/11/2026"; anything else as it is. */
    static String dayText(String iso) {
        if (iso.length() == 10 && iso.charAt(4) == '-' && iso.charAt(7) == '-') {
            return iso.substring(8) + "/" + iso.substring(5, 7) + "/" + iso.substring(0, 4);
        }
        return iso;
    }

    static String when(long unix) {
        if (unix <= 0) {
            return "";
        }
        return new java.text.SimpleDateFormat("dd/MM/yyyy HH:mm", PT).format(new java.util.Date(unix * 1000L));
    }
}
