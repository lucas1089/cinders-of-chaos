package com.cindersofchaos.admin;

/**
 * Plain-JVM check of TimezoneInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/TimezoneInfo.java
 * app/src/test/java/com/cindersofchaos/admin/TimezoneInfoTest.java && java -cp out com.cindersofchaos.admin.TimezoneInfoTest
 */
public final class TimezoneInfoTest {
    private static int fails = 0;
    private static int count = 0;

    private static void expect(boolean ok, String what) {
        count++;
        if (!ok) {
            fails++;
            System.out.println("FAIL " + what);
        }
    }

    static final String WRONG = "zone=Etc/UTC\nlocal_time=2026-11-09 20:30:23\nutc_offset=+00:00\nexpected_zone=America/Sao_Paulo\n"
            + "expected_offset=-03:00\nresult=WRONG\ndetail=wrong clock zone: UTC+00:00, expected UTC-03:00. Fix: chaos-ctl.sh timezone set\n";
    static final String RIGHT = "zone=America/Sao_Paulo\nlocal_time=2026-11-09 17:30:23\nutc_offset=-03:00\n"
            + "expected_zone=America/Sao_Paulo\nexpected_offset=-03:00\nresult=OK\ndetail=zone America/Sao_Paulo, UTC-03:00\n";

    public static void main(String[] args) {
        TimezoneInfo w = TimezoneInfo.parse(WRONG);
        expect(w != null && !w.ok, "wrong zone parses as not ok");
        expect(w.zone.equals("Etc/UTC") && w.utcOffset.equals("+00:00") && w.expectedZone.equals("America/Sao_Paulo")
                && w.expectedOffset.equals("-03:00") && w.localTime.equals("2026-11-09 20:30:23"), "fields");
        String s = w.summary();
        expect(s.startsWith("Fuso ERRADO: a VPS está em Etc/UTC (UTC+00:00); o jogo precisa de America/Sao_Paulo (UTC-03:00)."),
                "wrong summary start: " + s);
        expect(s.contains("sairiam 3 horas fora do horário") && s.contains("Ajustar para São Paulo")
                && s.contains("Painel > Servidor"), "wrong summary names the gap, the button and where to restart: " + s);
        TimezoneInfo r = TimezoneInfo.parse(RIGHT);
        expect(r != null && r.ok, "right zone parses as ok");
        expect(r.summary().equals("Fuso certo: America/Sao_Paulo (UTC-03:00). Hora na VPS: 2026-11-09 17:30:23."),
                "right summary: " + r.summary());
        // after a set: the same lines plus timezone_set, restart_needed and a note
        TimezoneInfo a = TimezoneInfo.parse("timezone_set=America/Sao_Paulo\n" + RIGHT + "restart_needed=yes\nnote=restart it now\n");
        expect(a != null && a.ok && a.setZone.equals("America/Sao_Paulo"), "set result parses");
        String t = a.afterSet();
        expect(t.startsWith("Fuso ajustado para America/Sao_Paulo.") && t.contains("Painel > Servidor")
                && t.contains("Nada foi reiniciado") && t.contains("UTC-03:00"), "after set (ok): " + t);
        TimezoneInfo b = TimezoneInfo.parse("timezone_set=America/Sao_Paulo\n" + WRONG + "restart_needed=yes\n");
        expect(b != null && !b.ok && b.afterSet().contains("ainda aparece como Etc/UTC"), "after set (still wrong): " + b.afterSet());
        // no result line: not a timezone answer
        expect(TimezoneInfo.parse("chaos-ctl: no /opt/chaos/repo/server/tools/chaos_timezone.py") == null, "a refusal is not parsed");
        expect(TimezoneInfo.parse("") == null && TimezoneInfo.parse(null) == null, "empty is not parsed");
        expect(TimezoneInfo.parse("result=MAYBE\n") == null, "an unknown result is not parsed");
        // the first value of a key wins (the detail text may hold an = sign)
        TimezoneInfo d = TimezoneInfo.parse("zone=A/B\nzone=C/D\nresult=OK\n");
        expect(d != null && d.zone.equals("A/B"), "first value wins");
        // offsets
        expect(TimezoneInfo.minutes("-03:00") == -180 && TimezoneInfo.minutes("+05:30") == 330 && TimezoneInfo.minutes("UTC+00:00") == 0,
                "minutes");
        expect(TimezoneInfo.minutes("x") == Integer.MIN_VALUE && TimezoneInfo.minutes(null) == Integer.MIN_VALUE, "bad offset");
        expect(TimezoneInfo.gap("+00:00", "-03:00").equals("3 horas") && TimezoneInfo.gap("-02:00", "-03:00").equals("1 hora")
                && TimezoneInfo.gap("+05:30", "-03:00").equals("510 minutos") && TimezoneInfo.gap("-03:00", "-03:00").isEmpty()
                && TimezoneInfo.gap("?", "-03:00").isEmpty(), "gap");
        System.out.println("TimezoneInfoTest: " + count + " checks, " + fails + " failures");
        if (fails > 0) {
            System.exit(1);
        }
    }
}
