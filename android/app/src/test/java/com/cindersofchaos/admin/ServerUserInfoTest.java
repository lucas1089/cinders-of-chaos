package com.cindersofchaos.admin;

/**
 * Plain-JVM check of ServerUserInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/ServerUserInfo.java
 * app/src/test/java/com/cindersofchaos/admin/ServerUserInfoTest.java && java -cp out com.cindersofchaos.admin.ServerUserInfoTest
 */
public final class ServerUserInfoTest {
    private static int fails = 0;
    private static int count = 0;

    private static void expect(boolean ok, String what) {
        count++;
        if (!ok) {
            fails++;
            System.out.println("FAIL " + what);
        }
    }

    private static String status(String unitUser, String engineUser, String exists, String foreign, String db, String repo,
                                 String needsFix, String restart) {
        return "unit=chaos-server\nlayout=kit\nunit_user=" + unitUser + "\nengine_pid=" + (engineUser.isEmpty() ? "" : "123")
                + "\nengine_user=" + engineUser + "\nruns_as_root=" + (engineUser.equals("root") || (engineUser.isEmpty() && unitUser.equals("root")) ? "yes" : "no")
                + "\ntarget_user=chaos\nuser_exists=" + exists + "\nforeign_files=" + foreign + "\nrepo_root_owned=" + repo
                + "\ndb_admin=" + db + "\nneeds_fix=" + needsFix + "\nrestart_needed=" + restart + "\n";
    }

    public static void main(String[] args) {
        String before = status("root", "root", "no", "-1", "no", "yes", "yes", "yes");
        expect(ServerUserInfo.verdict(before).equals("fix"), "root unit: fix");
        String s = ServerUserInfo.summary(before);
        expect(s.contains("Motor: roda como root") && s.contains("User=root") && s.contains("ainda não existe")
                && s.contains("Banco do kit: admin chaos: falta") && s.contains("Precisa corrigir"), "summary before: " + s);

        String ready = status("chaos", "root", "yes", "0", "yes", "yes", "no", "yes");
        expect(ServerUserInfo.verdict(ready).equals("restart"), "unit ready, engine old: restart");
        expect(ServerUserInfo.summary(ready).contains("Falta reiniciar") && ServerUserInfo.summary(ready).contains("Pastas do servidor: todas de chaos"),
                "summary ready: " + ServerUserInfo.summary(ready));

        String done = status("chaos", "chaos", "yes", "0", "yes", "yes", "no", "no");
        expect(ServerUserInfo.verdict(done).equals("ok") && ServerUserInfo.summary(done).endsWith("Tudo certo."), "done: ok");

        String stopped = status("chaos", "", "yes", "3", "unknown", "yes", "yes", "no");
        expect(ServerUserInfo.summary(stopped).contains("Motor: parado") && ServerUserInfo.summary(stopped).contains("3 arquivo(s) de outro dono")
                && ServerUserInfo.summary(stopped).contains("banco parado"), "stopped server: " + ServerUserInfo.summary(stopped));

        String blocked = status("root", "root", "yes", "0", "n/a", "no", "yes", "yes");
        expect(ServerUserInfo.verdict(blocked).equals("blocked") && ServerUserInfo.summary(blocked).contains("Corrigir recusa")
                && !ServerUserInfo.summary(blocked).contains("Banco do kit"), "repo not root-owned blocks, repo layout has no database line");

        expect(ServerUserInfo.verdict("").equals("unknown") && ServerUserInfo.summary(null).equals("Toque em Ver."), "empty");
        expect(ServerUserInfo.verdict("garbage\nx=y\n").equals("unknown"), "no needs_fix key");

        String fix = "user: chaos created\ndatabase: socket admin chaos ready\nfolders owned by chaos: /a /b\nunit: installed /e/chaos-server.service with User=chaos (the old one: /x)\n"
                + "restart: needed. The engine runs as root\nRESULT ok: prepared\n";
        String f = ServerUserInfo.fixSummary(fix);
        expect(f.contains("Usuário criado") && f.contains("Banco do kit") && f.contains("Pastas") && f.contains("Unidade nova instalada")
                && f.contains("Falta reiniciar") && !f.contains("RESULT"), "fix summary: " + f);
        expect(ServerUserInfo.fixSummary("RESULT ok: nothing to change\n").equals("Nada a mudar."), "nothing to change");
        expect(ServerUserInfo.fixSummary("restart: in 300 seconds, as chaos (follow it)\n").contains("Reinício marcado"), "restart scheduled");
        expect(ServerUserInfo.fixSummary("something else").equals("something else"), "unknown text kept");

        String[] codes = {"repo-not-root-owned: x", "kit-not-traversable: x", "layout-mismatch: x", "layout-unsupported: x",
            "unit-verify-failed: x", "unit-user-not-applied: x", "database-down: the kit's database ... start the server first",
            "server-user-running: x", "unit-file-not-found: x", "no-unit-template: x", "no-backup: x"};
        for (String c : codes) {
            expect(ServerUserInfo.translateError(c) != null, "translated: " + c);
        }
        expect(ServerUserInfo.translateError("database-down: the database did not answer") == null, "the generic database-down is not ours");
        expect(ServerUserInfo.translateError("something") == null && ServerUserInfo.translateError(null) == null, "not ours");
        System.out.println("ServerUserInfoTest: " + count + " checks, " + fails + " failures");
        System.exit(fails == 0 ? 0 : 1);
    }
}
