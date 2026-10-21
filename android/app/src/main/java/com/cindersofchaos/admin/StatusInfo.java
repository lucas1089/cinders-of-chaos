package com.cindersofchaos.admin;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** The key=value lines of "chaos-ctl.sh status", read for the dashboard. Pure Java, no Android classes. */
final class StatusInfo {
    enum State { ONLINE, ONLINE_NO_UNIT, STARTING, STOPPING, OFFLINE, FAILED, NO_UNIT, UNKNOWN }

    final Map<String, String> kv = new LinkedHashMap<>();

    static StatusInfo parse(String out) {
        StatusInfo s = new StatusInfo();
        for (String line : out.split("\n")) {
            int eq = line.indexOf('=');
            if (eq > 0 && line.substring(0, eq).matches("[a-z_]+")) {
                s.kv.put(line.substring(0, eq), line.substring(eq + 1).trim());
            }
        }
        return s;
    }

    boolean valid() {
        return kv.containsKey("service");
    }

    String get(String k) {
        String v = kv.get(k);
        return v == null ? "" : v;
    }

    State state() {
        String svc = get("service");
        boolean noUnit = "not-found".equals(get("unit_state"));
        boolean pid = !get("pid").isEmpty();
        if (noUnit) {
            return pid ? State.ONLINE_NO_UNIT : State.NO_UNIT;
        }
        switch (svc) {
            case "active":
            case "reloading":
                return State.ONLINE;
            case "activating":
                return State.STARTING;
            case "deactivating":
                return State.STOPPING;
            case "failed":
                return State.FAILED;
            case "inactive":
                return pid ? State.ONLINE_NO_UNIT : State.OFFLINE;
            default:
                return State.UNKNOWN;
        }
    }

    /** Seconds since the unit became active, or -1. systemd prints e.g. "Tue 2026-10-20 06:00:01 UTC". */
    long uptimeSec(long nowMs) {
        Date d = since();
        return d == null ? -1 : Math.max(0, (nowMs - d.getTime()) / 1000);
    }

    Date since() {
        String s = get("since");
        if (s.isEmpty() || s.startsWith("n/a")) {
            return null;
        }
        String[] fmts = {"EEE yyyy-MM-dd HH:mm:ss zzz", "EEE yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss"};
        for (String f : fmts) {
            try {
                SimpleDateFormat p = new SimpleDateFormat(f, Locale.US);
                p.setLenient(false);
                return p.parse(s);
            } catch (Exception ignored) {
                // next format
            }
        }
        return null;
    }

    /** "used/total MB" -> percent 0..100, or -1. */
    int memPercent() {
        Matcher m = Pattern.compile("(\\d+)\\s*/\\s*(\\d+)").matcher(get("mem"));
        if (m.find()) {
            long used = Long.parseLong(m.group(1));
            long total = Long.parseLong(m.group(2));
            return total > 0 ? (int) Math.min(100, used * 100 / total) : -1;
        }
        return -1;
    }

    /** "3.1G/40G (8%)" -> 8, or -1. */
    int diskPercent() {
        Matcher m = Pattern.compile("\\((\\d+)%\\)").matcher(get("disk"));
        return m.find() ? Integer.parseInt(m.group(1)) : -1;
    }

    String memText() {
        Matcher m = Pattern.compile("(\\d+)\\s*/\\s*(\\d+)").matcher(get("mem"));
        if (m.find()) {
            return gb(Long.parseLong(m.group(1))) + " de " + gb(Long.parseLong(m.group(2)));
        }
        return dash(get("mem"));
    }

    String diskText() {
        String d = get("disk");
        int p = d.indexOf(" (");
        String used = p > 0 ? d.substring(0, p) : d;
        String[] parts = used.split("/");
        return parts.length == 2 ? parts[0] + " de " + parts[1] : dash(d);
    }

    /** The 1-minute load and the 5 / 15 minute ones. */
    String loadText() {
        String[] l = get("load").split("\\s+");
        return l.length >= 3 ? l[0] + "  ·  " + l[1] + "  ·  " + l[2] : dash(get("load"));
    }

    String playersText() {
        String p = get("players");
        return p.matches("\\d+") ? p : "?";
    }

    String backupText() {
        String b = get("backup");
        return b.isEmpty() || b.equals("none") ? "nenhum" : b;
    }

    int errors() {
        try {
            return Integer.parseInt(get("errors"));
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    private static String gb(long mb) {
        if (mb >= 1024) {
            return String.format(Locale.US, "%.1f GB", mb / 1024.0);
        }
        return mb + " MB";
    }

    private static String dash(String s) {
        return s.isEmpty() ? "?" : s;
    }
}
