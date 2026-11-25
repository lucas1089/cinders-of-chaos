package com.cindersofchaos.admin;

/**
 * Plain-JVM check of AutoUpdateInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/AutoUpdateInfo.java
 * app/src/test/java/com/cindersofchaos/admin/AutoUpdateInfoTest.java && java -cp out com.cindersofchaos.admin.AutoUpdateInfoTest
 */
public final class AutoUpdateInfoTest {
    private static int fails = 0;
    private static int count = 0;

    private static void expect(boolean ok, String what) {
        count++;
        if (!ok) {
            fails++;
            System.out.println("FAIL " + what);
        }
    }

    static final String ON = "installed=yes\nenabled=yes\nsave_time=06:00\ngame_save_time=06:00\nsave_time_source=game\n"
            + "prep_at=03:00\nsave_run_at=05:15\nnext_prep=Thu 2026-11-26 03:00:00 -03\nnext_save=Thu 2026-11-26 05:15:00 -03\n"
            + "running=no\nprep_time=2026-11-25 03:00:02\nprep_result=dispatched\nprep_text=engine dispatched run 9\n"
            + "prep_commit=a1b2c3d\nprep_engine=dispatched run 9 client build 31\nprep_android=dispatched android-31\n"
            + "prep_admin=current\nsave_time_run=2026-11-25 05:15:01\nsave_result=ok\nsave_text=updated\n"
            + "applied_time=2026-11-25 06:03:10\napplied_commit=a1b2c3d\napplied_release=winpkg-140\n"
            + "applied_pair=pair 83 -> 84 (its items install at the next save)\napplied_client=140\napplied_apk=31\n"
            + "client_pair=84\nstop_request=no\n";
    static final String OFF = "installed=no\nenabled=no\nsave_time=06:00\ngame_save_time=unknown\nsave_time_source=game\n"
            + "prep_at=03:00\nsave_run_at=05:15\nrunning=no\nprep_time=\nprep_result=\nprep_text=\nprep_commit=\n"
            + "prep_engine=\nprep_android=\nprep_admin=\nsave_time_run=\nsave_result=\nsave_text=\napplied_time=\n"
            + "applied_commit=\napplied_release=\napplied_pair=\napplied_client=\napplied_apk=\nclient_pair=80\nstop_request=no\n";

    public static void main(String[] args) {
        AutoUpdateInfo on = AutoUpdateInfo.parse(ON);
        expect(on != null && on.enabled() && !on.running(), "on parses");
        expect(on.headline().equals("Ligada: atualiza no server save das 06:00."), "on headline: " + on.headline());
        String d = on.details();
        expect(d.contains("Server save: 06:00 (do jogo)") && d.contains("Builds às 03:00, instalação começa às 05:15"),
                "on details times: " + d);
        expect(d.contains("Próximo save: Thu 2026-11-26 05:15:00 -03") && d.contains("Último preparo: builds disparadas")
                && d.contains("Android: dispatched android-31") && d.contains("Último save: atualizado"), "on details runs: " + d);
        expect(d.contains("commit a1b2c3d, engine winpkg-140, pair 83 -> 84") && d.contains("APK 31")
                && d.contains("Par do client agora: 84"), "on details applied: " + d);
        expect(!d.contains("confira o horário"), "same game time: no warning");

        AutoUpdateInfo off = AutoUpdateInfo.parse(OFF);
        expect(off != null && !off.enabled(), "off parses");
        expect(off.headline().startsWith("Desligada."), "off headline");
        String o = off.details();
        expect(o.contains("Último preparo: nunca rodou") && o.contains("Último save: nunca rodou") && !o.contains("Próximo")
                && !o.contains("Instalado em"), "off details: " + o);

        AutoUpdateInfo set = AutoUpdateInfo.parse(ON.replace("enabled=yes\nsave_time=06:00", "enabled=yes\nsave_time=07:00")
                .replace("save_time_source=game", "save_time_source=set").replace("running=no", "running=yes"));
        expect(set.running() && set.headline().contains("(rodando agora)"), "running headline");
        expect(set.details().contains("(definido aqui)") && set.details().contains("o jogo salva às 06:00: confira o horário"),
                "set time differs from the game's: " + set.details());

        expect(AutoUpdateInfo.parse("chaos-ctl: kit-not-found\n") == null, "a refusal is no status");
        expect(AutoUpdateInfo.parse(null) == null, "null is no status");

        expect(AutoUpdateInfo.validTime("06:00") && AutoUpdateInfo.validTime("23:59") && AutoUpdateInfo.validTime("00:00"),
                "valid times");
        expect(!AutoUpdateInfo.validTime("24:00") && !AutoUpdateInfo.validTime("6:00") && !AutoUpdateInfo.validTime("06:60")
                && !AutoUpdateInfo.validTime("06:00;id") && !AutoUpdateInfo.validTime(null), "invalid times");
        expect(AutoUpdateInfo.normalTime("6:00").equals("06:00") && AutoUpdateInfo.normalTime(" 0615 ").equals("06:15")
                && AutoUpdateInfo.normalTime("25:00").isEmpty() && AutoUpdateInfo.normalTime("game").isEmpty(), "normal times");

        expect(AutoUpdateInfo.resultWord("rolled-back").equals("revertido") && AutoUpdateInfo.resultWord("skipped").equals("pulado"),
                "result words");
        expect(AutoUpdateInfo.confirmNowText().contains("REINICIA"), "now confirm warns of the restart");

        System.out.println("AutoUpdateInfoTest: " + count + " checks, " + fails + " failures");
        if (fails > 0) {
            System.exit(1);
        }
    }
}
