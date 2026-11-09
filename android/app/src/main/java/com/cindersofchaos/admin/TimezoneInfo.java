package com.cindersofchaos.admin;

import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Saúde e espaço > Ver fuso horário / Ajustar para São Paulo (O439): the reading of the key=value lines of
 * chaos-ctl.sh timezone [set] (zone, local_time, utc_offset, expected_zone, expected_offset, result=OK|WRONG, detail,
 * and after a set timezone_set, restart_needed, note) and their wording in Portuguese. The command exits 1 when the
 * zone is wrong, so the lines are read whatever the exit code was. Pure Java, tested by TimezoneInfoTest on a plain JVM.
 * server/README.md "Timezone guard (O439)".
 */
final class TimezoneInfo {
    final boolean ok;
    final String zone;
    final String localTime;
    final String utcOffset;
    final String expectedZone;
    final String expectedOffset;
    /** The zone a "timezone set" put in place, "" for a plain read. */
    final String setZone;

    private TimezoneInfo(Map<String, String> kv) {
        ok = "OK".equals(kv.get("result"));
        zone = kv.getOrDefault("zone", "?");
        localTime = kv.getOrDefault("local_time", "");
        utcOffset = kv.getOrDefault("utc_offset", "?");
        expectedZone = kv.getOrDefault("expected_zone", "America/Sao_Paulo");
        expectedOffset = kv.getOrDefault("expected_offset", "-03:00");
        setZone = kv.getOrDefault("timezone_set", "");
    }

    /** The lines of the command's output, or null when it has no result line (a refusal, an ssh error). */
    static TimezoneInfo parse(String out) {
        if (out == null) {
            return null;
        }
        Map<String, String> kv = new HashMap<>();
        for (String line : out.split("\n")) {
            int eq = line.indexOf('=');
            if (eq <= 0) {
                continue;
            }
            String k = line.substring(0, eq).trim();
            if (k.matches("[a-z_]+") && !kv.containsKey(k)) {
                kv.put(k, line.substring(eq + 1).trim());
            }
        }
        String r = kv.get("result");
        if (!"OK".equals(r) && !"WRONG".equals(r)) {
            return null;
        }
        return new TimezoneInfo(kv);
    }

    /** Minutes east of UTC from "+05:30" or "-03:00" (also with a "UTC" before), or Integer.MIN_VALUE. */
    static int minutes(String offset) {
        Matcher m = Pattern.compile("^(?:UTC)?([+-])(\\d{2}):(\\d{2})$").matcher(offset == null ? "" : offset.trim());
        if (!m.find()) {
            return Integer.MIN_VALUE;
        }
        int v = Integer.parseInt(m.group(2)) * 60 + Integer.parseInt(m.group(3));
        return m.group(1).equals("-") ? -v : v;
    }

    /** "3 horas", "1 hora", "30 minutos": how far apart two offsets are, "" when one is unknown. */
    static String gap(String a, String b) {
        int x = minutes(a);
        int y = minutes(b);
        if (x == Integer.MIN_VALUE || y == Integer.MIN_VALUE) {
            return "";
        }
        int d = Math.abs(x - y);
        if (d == 0) {
            return "";
        }
        if (d % 60 == 0) {
            return (d / 60) + (d == 60 ? " hora" : " horas");
        }
        return d + " minutos";
    }

    /** The result of "Ver fuso horário" (or the state after a set), in Portuguese. */
    String summary() {
        String now = localTime.isEmpty() ? "" : " Hora na VPS: " + localTime + ".";
        if (ok) {
            return "Fuso certo: " + zone + " (UTC" + utcOffset + ")." + now;
        }
        String gap = gap(utcOffset, expectedOffset);
        return "Fuso ERRADO: a VPS está em " + zone + " (UTC" + utcOffset + "); o jogo precisa de " + expectedZone
                + " (UTC" + expectedOffset + ")." + now + " O Founder Pack, a Season 1, o bônus de lançamento dos criadores "
                + "e o salvamento das 06:00 usam a hora da VPS" + (gap.isEmpty() ? "" : " e sairiam " + gap + " fora do horário")
                + ". Toque em Ajustar para São Paulo e depois reinicie o jogo (Painel > Servidor).";
    }

    /** The result of "Ajustar para São Paulo": what was set, and that the running game must restart. */
    String afterSet() {
        String done = "Fuso ajustado para " + (setZone.isEmpty() ? expectedZone : setZone) + ".";
        String restart = " O jogo que já está rodando continua com o fuso antigo até reiniciar: reinicie em Painel > Servidor. "
                + "Nada foi reiniciado.";
        if (ok) {
            return done + " Agora a VPS está em UTC" + utcOffset + "." + restart;
        }
        return done + " Mas a VPS ainda aparece como " + zone + " (UTC" + utcOffset + "): confira com Ver fuso horário." + restart;
    }
}
