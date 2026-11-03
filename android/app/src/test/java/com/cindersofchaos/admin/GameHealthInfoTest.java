package com.cindersofchaos.admin;

/**
 * Plain-JVM check of GameHealthInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/GameHealthInfo.java
 * app/src/test/java/com/cindersofchaos/admin/GameHealthInfoTest.java && java -cp out com.cindersofchaos.admin.GameHealthInfoTest
 */
public final class GameHealthInfoTest {
    private static int fails = 0;
    private static int count = 0;

    private static void expect(boolean ok, String what) {
        count++;
        if (!ok) {
            fails++;
            System.out.println("FAIL " + what);
        }
    }

    public static void main(String[] args) {
        expect(GameHealthInfo.days("7", 90) == 7 && GameHealthInfo.days(" 90 ", 90) == 90, "days");
        expect(GameHealthInfo.days("91", 90) == -1 && GameHealthInfo.days("0", 90) == -1, "days out of range");
        expect(GameHealthInfo.days("1;id", 90) == -1 && GameHealthInfo.days(null, 90) == -1, "days not a number");
        expect(GameHealthInfo.healthArgs(7).equals("game-health --kv --pt --days 7"), "health args");
        expect(GameHealthInfo.balanceDaysArgs(30, false).equals("balance-report --pt --days 30"), "balance args");
        expect(GameHealthInfo.balanceDaysArgs(30, true).equals("balance-report --pt --days 30 --dm"), "balance dm");
        expect(GameHealthInfo.balanceSeasonArgs(false).equals("balance-report --pt --season current"), "season args");
        expect(GameHealthInfo.balanceTimerArgs("on").equals("balance-report timer on")
                && GameHealthInfo.balanceTimerArgs("x; id").equals("balance-report timer status"), "timer args");
        expect(GameHealthInfo.balanceLastArgs().equals("balance-report last"), "last args");

        String out = "ok=1\ndays=7\nnow=1791001800\nsince=1790398800\nonline_mean=11.7\nonline_peak=25\n"
                + "online_peak_at=03/11 14h\nonline_busiest_hour=14\nonline_quietest_hour=5\nonline_sampled_hours=3\n"
                + "deaths_total=10\ndeaths_per_hour=3.33\ndeaths_per_play_hour=0.286\n"
                + "hour=1790989200 03/11 13 10.0 14 4\nhour=1790992800 03/11 14 20.0 25 6\n"
                + "hour=1790996400 03/11 15 - - 0\nhour=bad\n"
                + "hunts_known=5\nhunts_unvisited=2\n"
                + "hunt_top=40 10.0 900 7 Ashen Caves\nhunt_top=<5 0.3 50 0 Rift\nhunt_low=0 0.0 0 0 Bone Pits\n"
                + "gold_in=520000\ngold_out=120000\ngold_net=400000\n"
                + "gold=faucet 500000 300 loot\ngold=sink 120000 280 suprimentos\n"
                + "funnel_days=30\nfunnel_characters=60\nfunnel_reached=10 20 33.3\nfunnel_reached=20 <5 -\n"
                + "funnel_stopped=48 60 80.0\nfunnel_stop_level=40 83.3 1-5\n"
                + "funnel_stop_system=8 16.7 Fenda\n";
        GameHealthInfo g = GameHealthInfo.parse(out);
        expect(g != null && g.ok && g.days == 7, "parsed");
        expect(g.hours.size() == 3, "hour lines (a broken one skipped): " + g.hours.size());
        expect(g.hours.get(1).mean == 20.0 && g.hours.get(1).peak == 25 && g.hours.get(1).deaths == 6
                && g.hours.get(1).hour == 14 && g.hours.get(1).day.equals("03/11"), "an hour");
        expect(g.hours.get(2).mean == -1 && g.hours.get(2).peak == -1, "an hour without samples");
        expect(g.maxPeak() == 25, "chart scale");
        double[] hod = g.byHourOfDay();
        expect(hod[14] == 20.0 && hod[15] == -1 && hod[0] == -1, "mean by hour of day");
        expect(g.top.size() == 2 && g.top.get(0).name.equals("Ashen Caves") && g.top.get(0).kills == 900
                && g.top.get(0).deaths == 7 && g.top.get(0).hours == 10.0, "top hunt");
        expect(g.top.get(1).visits == GameHealthInfo.SMALL && GameHealthInfo.n(g.top.get(1).visits).equals("<5"),
                "small groups");
        expect(g.low.size() == 1 && g.low.get(0).name.equals("Bone Pits"), "least used hunt, a name with spaces");
        expect(g.goldIn == 520000 && g.goldNet == 400000 && g.gold.size() == 2
                && g.gold.get(1).label.equals("sai: suprimentos") && g.gold.get(1).extra == 280, "gold");
        expect(GameHealthInfo.gold(1234567).equals("1.234.567") && GameHealthInfo.gold(-1000).equals("-1.000")
                && GameHealthInfo.gold(12).equals("12"), "gold digits");
        expect(g.funnelCharacters.equals("60") && g.reached.size() == 2 && g.reached.get(1).count == GameHealthInfo.SMALL
                && g.reached.get(1).pct == -1, "funnel reached");
        expect(g.funnelStopped.equals("48 de 60 (80,0%)"), "funnel stopped: " + g.funnelStopped);
        expect(g.stopLevel.get(0).label.equals("Nível 1-5") && g.stopSystem.get(0).label.equals("Fenda"), "stops");
        expect(g.headline().startsWith("Últimos 7 dias: média de 11,7 online, pico de 25 (03/11 14h); 10 mortes"),
                "headline: " + g.headline());

        GameHealthInfo e = GameHealthInfo.parse("ok=0\nerror=no-table\n");
        expect(e != null && !e.ok && e.headline().contains("passo sql"), "no table");
        expect(GameHealthInfo.parse("chaos-ctl: database-down") == null && GameHealthInfo.parse(null) == null,
                "no report");
        System.out.println("GameHealthInfoTest: " + count + " checks, " + fails + " failures");
        if (fails > 0) {
            System.exit(1);
        }
    }
}
