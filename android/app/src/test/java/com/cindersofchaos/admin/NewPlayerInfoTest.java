package com.cindersofchaos.admin;

/**
 * Plain-JVM check of NewPlayerInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/NewPlayerInfo.java
 * app/src/test/java/com/cindersofchaos/admin/NewPlayerInfoTest.java && java -cp out com.cindersofchaos.admin.NewPlayerInfoTest
 */
public final class NewPlayerInfoTest {
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
        expect(NewPlayerInfo.days("30") == 30, "days 30");
        expect(NewPlayerInfo.days(" 7 ") == 7, "days trimmed");
        expect(NewPlayerInfo.days("0") == -1, "days 0");
        expect(NewPlayerInfo.days("3651") == -1, "days too many");
        expect(NewPlayerInfo.days("1;id") == -1, "days not a number");
        expect(NewPlayerInfo.days("") == -1 && NewPlayerInfo.days(null) == -1, "days empty");
        expect(NewPlayerInfo.funnelArgs(30).equals("newplayer-funnel --pt --days 30"), "funnel args");
        expect(NewPlayerInfo.surveyArgs(90).equals("survey --pt --texts 100 --days 90"), "survey args");
        expect(NewPlayerInfo.headline("\n  Funil de novos jogadores\nPersonagens: 5\n").equals("Funil de novos jogadores"),
                "headline");
        expect(NewPlayerInfo.headline(null).isEmpty(), "headline of nothing");
        expect(NewPlayerInfo.clean("a\u0007b‮c\nd ").equals("abc\nd"), "clean");
        System.out.println("NewPlayerInfoTest: " + count + " checks, " + fails + " failures");
        if (fails > 0) {
            System.exit(1);
        }
    }
}
