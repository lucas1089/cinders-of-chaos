package com.cindersofchaos.admin;

/**
 * Staff rights and config reload of the Comandos tab (O765): the checks chaos-ctl.sh makes again on its side, so a bad
 * value is refused on the phone with a Portuguese line. gm-set NAME GROUP (character name of 3 to 29 letters, spaces, '
 * and -; group 1 to 6) and reload-file ACTOR CONFIG (a bare name like pace_config). Pure Java, tested by StaffInfoTest on
 * a plain JVM.
 */
final class StaffInfo {
    static final String[] GROUPS = {"", "jogador", "tutor", "tutor sênior", "gamemaster", "community manager", "god"};

    private StaffInfo() {
    }

    /** Shell single quotes, as Ssh.sq (kept here so this class needs no ssh library). */
    static String sq(String s) {
        return "'" + s.replace("'", "'\\''") + "'";
    }

    /** A character name as chaos-ctl.sh gm-set takes it. */
    static boolean validName(String n) {
        return n != null && n.matches("[A-Za-z][A-Za-z '-]{2,28}") && !n.endsWith(" ") && !n.contains("  ");
    }

    /** The group's name in Portuguese, "" outside 1..6. */
    static String group(int g) {
        return g >= 1 && g <= 6 ? GROUPS[g] : "";
    }

    /** The gm-set command, or null when a value is bad. The name goes quoted (it may hold a space or a '). */
    static String gmSet(String name, int g) {
        if (!validName(name) || group(g).isEmpty()) {
            return null;
        }
        return "gm-set " + sq(name) + " " + g;
    }

    /** A config table name as reload-file takes it (pace_config). */
    static boolean validConfig(String c) {
        return c != null && c.matches("[a-z][a-z0-9_]{0,63}");
    }

    /** The reload-file command for the admin character, or null when a value is bad. */
    static String reloadFile(String actor, String config) {
        if (config == null) {
            config = "";
        }
        if (!validName(actor) || !(config.isEmpty() || validConfig(config))) {
            return null;
        }
        return "reload-file " + sq(actor) + (config.isEmpty() ? "" : " " + config);
    }

    /** The config names of reload-files' output (one per line, nothing else kept). */
    static java.util.List<String> configs(String out) {
        java.util.List<String> l = new java.util.ArrayList<>();
        if (out == null) {
            return l;
        }
        for (String line : out.split("\n")) {
            String t = line.trim();
            if (t.endsWith("_config") && validConfig(t)) {
                l.add(t);
            }
        }
        return l;
    }
}
