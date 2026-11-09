package com.cindersofchaos.admin;

import java.util.List;

/**
 * Plain-JVM check of LaunchCheckInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/LaunchCheckInfo.java
 * app/src/test/java/com/cindersofchaos/admin/LaunchCheckInfoTest.java && java -cp out com.cindersofchaos.admin.LaunchCheckInfoTest
 */
public final class LaunchCheckInfoTest {
    private static int fails = 0;
    private static int count = 0;

    private static void expect(boolean ok, String what) {
        count++;
        if (!ok) {
            fails++;
            System.out.println("FAIL " + what);
        }
    }

    // made-up report, in the tool's order
    static final String OUT = "OK   beta_config     beta_config.lua enabled = false: no free starter coins.\n"
            + "WARN max_players     maxPlayers = 400 (owner decision: 300 or 400).\n"
            + "FAIL beta_cron       /etc/cron.d/chaos-beta-coins exists: it refills every account.\n"
            + "OK   timezone        zone America/Sao_Paulo, UTC-03:00.\n"
            + "FAIL payments        a mock payment provider is on.\n"
            + "WARN backup          the newest backup is 30.0 hours old (limit 24).\n"
            + "FAIL test_files      2 test only file(s): data/scripts/zz_a.lua, data/scripts/zz_b.lua. Remove them.\n"
            + "launch check: 3 FAIL, 2 WARN, 2 OK\n";

    public static void main(String[] args) {
        LaunchCheckInfo.Report r = LaunchCheckInfo.parse(OUT);
        expect(r != null && r.lines.size() == 7, "seven check lines, the summary line is not one");
        expect(r.fails == 3 && r.warns == 2 && r.oks == 2, "counts");
        expect(r.lines.get(0).status.equals("OK") && r.lines.get(0).name.equals("beta_config")
                && r.lines.get(0).text.equals("beta_config.lua enabled = false: no free starter coins."), "first line fields");
        expect(LaunchCheckInfo.summary(r).equals("3 falhas, 2 avisos"), "summary: " + LaunchCheckInfo.summary(r));
        List<LaunchCheckInfo.Line> o = LaunchCheckInfo.ordered(r);
        StringBuilder names = new StringBuilder();
        for (LaunchCheckInfo.Line l : o) {
            names.append(l.name).append(' ');
        }
        expect(names.toString().equals("beta_cron payments test_files max_players backup beta_config timezone "),
                "FAIL first, then WARN, then OK, the tool's order inside each: " + names);
        String text = LaunchCheckInfo.render(r);
        expect(text.startsWith("FALHA  beta_cron  /etc/cron.d/chaos-beta-coins exists") && text.contains("\nAVISO  max_players  ")
                && text.endsWith("OK  timezone  zone America/Sao_Paulo, UTC-03:00."), "render: " + text);
        expect(text.split("\n").length == 7, "render has one line per check");
        // singular and plural
        LaunchCheckInfo.Report one = LaunchCheckInfo.parse("FAIL a x\nWARN b y\nOK c z\n");
        expect(LaunchCheckInfo.summary(one).equals("1 falha, 1 aviso"), "one and one: " + LaunchCheckInfo.summary(one));
        expect(LaunchCheckInfo.summary(LaunchCheckInfo.parse("FAIL a x\nOK c z\n")).equals("1 falha"), "one failure");
        expect(LaunchCheckInfo.summary(LaunchCheckInfo.parse("WARN a x\nWARN b y\nOK c z\n")).equals("2 avisos"), "two warnings");
        // everything fine
        LaunchCheckInfo.Report good = LaunchCheckInfo.parse("OK a x\nOK b y\nlaunch check: 0 FAIL, 0 WARN, 2 OK\n");
        expect(good != null && LaunchCheckInfo.summary(good).equals("Tudo certo para o lançamento"), "all fine");
        expect(good.fails == 0 && good.warns == 0 && good.oks == 2, "all fine counts");
        // not a report: a refusal, an ssh error, nothing
        expect(LaunchCheckInfo.parse("chaos-ctl: no /opt/chaos/repo/server/deploy/launch_check.py") == null, "a refusal is not parsed");
        expect(LaunchCheckInfo.parse("") == null && LaunchCheckInfo.parse(null) == null, "empty is not parsed");
        expect(LaunchCheckInfo.summary(null).isEmpty() && LaunchCheckInfo.ordered(null).isEmpty()
                && LaunchCheckInfo.render(null).isEmpty(), "null report");
        // a sentence with several spaces and a status word inside keeps its text
        LaunchCheckInfo.Report sp = LaunchCheckInfo.parse("WARN  dates_pvp   PvP Season 1 starts 2026-11-21 15:00, FAIL is not here.\n");
        expect(sp != null && sp.lines.get(0).name.equals("dates_pvp") && sp.lines.get(0).text.startsWith("PvP Season 1 starts"),
                "extra spaces are cut");
        expect(LaunchCheckInfo.parse("FAILURE x y\nOKAY x y\nWARNING x y\n") == null, "words that only start like a status are not lines");
        expect(LaunchCheckInfo.COMMAND.equals("launch-check"), "the command name");
        System.out.println("LaunchCheckInfoTest: " + count + " checks, " + fails + " failures");
        if (fails > 0) {
            System.exit(1);
        }
    }
}
