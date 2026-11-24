package com.cindersofchaos.admin;

/**
 * Plain-JVM check of HouseFixInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/HouseFixInfo.java
 * app/src/test/java/com/cindersofchaos/admin/HouseFixInfoTest.java && java -cp out com.cindersofchaos.admin.HouseFixInfoTest
 */
public final class HouseFixInfoTest {
    private static int fails = 0;
    private static int count = 0;

    private static void expect(boolean ok, String what) {
        count++;
        if (!ok) {
            fails++;
            System.out.println("FAIL " + what);
        }
    }

    // made-up outputs of chaos-ctl.sh house-fix, in the command's order
    static final String DRY = "house_fix=dry-run\nmap=/opt/chaos/server/data/world/chaos.otbm\n"
            + "PZ_ADD               2 tile(s) in 1 house(s)\nPVP_CLEAR            3 tile(s) in 2 house(s)\n"
            + "5 tile(s) to rewrite; 1 finding(s) for a human; 1 known and left\nHUMAN NO_DOOR house=7: no door\n"
            + "house fixer: dry run, nothing written (--write applies the plan)\n";
    static final String WRITTEN = "house_fix=written\nmap=/w/chaos.otbm\nbackup=/w/chaos.otbm.house-fix-20261124-180000\n"
            + "server=started\n5 tile(s) to rewrite; 0 finding(s) for a human; 0 known and left\n"
            + "house fixer: 5 tile(s) rewritten in /w/chaos.otbm\n";
    static final String REFUSED = "house_fix=refused\nmap=/w/chaos.otbm\nbackup=/w/chaos.otbm.house-fix-1\nserver=start-failed\n"
            + "refused: map write guard: a far tile changed\n";

    public static void main(String[] args) {
        HouseFixInfo.Result d = HouseFixInfo.parse(DRY);
        expect(d != null && d.state.equals("dry-run") && d.tiles == 5 && d.human == 1 && d.known == 1, "dry run fields");
        String s = HouseFixInfo.summary(d);
        expect(s.startsWith("Simulação: 5 tiles") && s.contains("Nada foi gravado") && s.contains("1 caso fica"), "dry run: " + s);
        HouseFixInfo.Result w = HouseFixInfo.parse(WRITTEN);
        expect(w.state.equals("written") && w.backup.endsWith("house-fix-20261124-180000") && w.server.equals("started"),
                "written fields");
        s = HouseFixInfo.summary(w);
        expect(s.contains("5 tiles gravados") && s.contains("house-fix-20261124-180000") && !s.contains("NÃO"), "written: " + s);
        HouseFixInfo.Result r = HouseFixInfo.parse(REFUSED);
        s = HouseFixInfo.summary(r);
        expect(r.refusal.equals("map write guard: a far tile changed") && s.contains("recusou") && s.contains("ficou como estava")
                && s.contains("NÃO ligou"), "refused: " + s);
        s = HouseFixInfo.summary(HouseFixInfo.parse("house_fix=nothing\nmap=/w/m.otbm\nhouse fixer: nothing to fix\n"));
        expect(s.equals("Nenhuma flag de casa a corrigir."), "nothing: " + s);
        expect(HouseFixInfo.parse("chaos-ctl: house-fix [--write]\n") == null, "a chaos-ctl refusal has no result");
        expect(HouseFixInfo.parse(null) == null, "null");
        expect(HouseFixInfo.summary(null).contains("não respondeu"), "no result");
        expect(HouseFixInfo.summary(HouseFixInfo.parse("house_fix=dry-run\n5 tile(s) to rewrite; 0 finding(s) for a human; 0 known and left\n"))
                .equals("Simulação: 5 tiles de casas a corrigir (flags de zona). Nada foi gravado."), "no human case");
        expect(HouseFixInfo.DRY_RUN.equals("house-fix") && HouseFixInfo.WRITE.equals("house-fix --write"), "the commands");
        System.out.println("HouseFixInfoTest: " + count + " checks, " + fails + " failed");
        if (fails > 0) {
            System.exit(1);
        }
    }
}
