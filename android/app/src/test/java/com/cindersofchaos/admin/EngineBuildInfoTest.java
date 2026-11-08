package com.cindersofchaos.admin;

/**
 * Plain-JVM check of EngineBuildInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/EngineBuildInfo.java
 * app/src/test/java/com/cindersofchaos/admin/EngineBuildInfoTest.java && java -cp out com.cindersofchaos.admin.EngineBuildInfoTest
 */
public final class EngineBuildInfoTest {
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
        String tok = "github_pat_11ABCDEFG0aBcDeFgHiJkL_mNoPqRsTuVwXyZ0123456789aBcDeFgHiJkLmNoPqRsTuVwXyZ01234";
        expect(EngineBuildInfo.validToken(tok), "fine-grained token");
        expect(EngineBuildInfo.validToken("ghp_" + "a1B2c3D4e5".repeat(4)), "classic token");
        String[] bad = {"", "github_pat_short", tok + "$(id)", tok + "\nX=1", " " + tok, "ghp_short", "not a token",
            "github_pat_" + "x".repeat(300)};
        for (String b : bad) {
            expect(!EngineBuildInfo.validToken(b), "refused: " + b.replace("\n", "\\n"));
        }
        expect(!EngineBuildInfo.validToken(null), "null");

        EngineBuildInfo none = EngineBuildInfo.parse("token=yes\nrepo=o/r\nbranch=main\nstate=none\nclient_build=30\n"
                + "installed_release=100\nrelease_newer=no\n");
        expect(none.valid() && none.state().equals("none") && !none.running() && none.hasToken() && !none.newer(), "none");
        expect(none.headline().equals("Nenhuma recompilação feita ainda."), "none headline");

        EngineBuildInfo queued = EngineBuildInfo.parse("token=yes\nstate=queued\nrun_id=5\nrun_number=101\ncommit=a1b2c3d\n"
                + "client_build=30\nelapsed_s=12\nrelease_newer=no\ninstalled_release=100\n");
        expect(queued.running() && queued.headline().equals("Na fila do GitHub."), "queued");

        EngineBuildInfo run = EngineBuildInfo.parse("token=yes\nstate=in_progress\nrun_number=101\ncommit=a1b2c3d\nclient_build=30\n"
                + "elapsed_s=2232\njob=engine-linux\nstep=Build the engine\njobs_done=1/3\ninstalled_release=100\nrelease_newer=no\n");
        expect(run.running(), "running");
        expect(run.headline().equals("Compilando no GitHub há 37 min."), "in progress headline: " + run.headline());
        expect(run.details().contains("Rodada 101, código a1b2c3d, client build 30")
                && run.details().contains("Etapa: engine-linux > Build the engine")
                && run.details().contains("Etapas prontas: 1/3") && run.details().contains("O jogo segue no ar"),
                "in progress details: " + run.details());

        EngineBuildInfo ok = EngineBuildInfo.parse("token=yes\nstate=success\nrun_number=101\ncommit=a1b2c3d\nelapsed_s=3900\n"
                + "release_tag=winpkg-101\nrelease_ready=yes\nrelease_newer=yes\ninstalled_release=100\nclient_build=30\n");
        expect(ok.newer() && !ok.running() && ok.headline().equals("Pronto: winpkg-101 tem o engine novo."), "success newer");
        expect(ok.details().contains("Levou 1 h 05 min.") && ok.details().contains("Atualizar servidor")
                && ok.details().contains("Instalado no servidor: winpkg-100"), "success details: " + ok.details());

        EngineBuildInfo same = EngineBuildInfo.parse("state=success\nrun_number=100\nrelease_tag=winpkg-100\nrelease_ready=yes\n"
                + "release_newer=no\ninstalled_release=100\ntoken=yes\n");
        expect(!same.newer() && same.headline().equals("Pronto, mas winpkg-100 é a versão que já está instalada."), "success not newer");
        EngineBuildInfo notReady = EngineBuildInfo.parse("state=success\nrun_number=101\nrelease_tag=winpkg-101\nrelease_ready=no\n"
                + "release_newer=no\ntoken=yes\n");
        expect(!notReady.newer() && notReady.headline().contains("ainda não mostra o engine"), "release not ready");

        EngineBuildInfo fail = EngineBuildInfo.parse("token=yes\nstate=failure\nconclusion=failure\nrun_number=101\nfailed_job=engine-linux\n"
                + "failed_step=Compile the engine\nrelease_newer=no\n");
        expect(fail.headline().equals("A recompilação falhou no GitHub."), "failure headline");
        expect(fail.details().contains("Parou em engine-linux > Compile the engine")
                && fail.details().contains("Nada foi trocado no servidor"), "failure details: " + fail.details());
        EngineBuildInfo cancelled = EngineBuildInfo.parse("state=failure\nconclusion=cancelled\ntoken=yes\n");
        expect(cancelled.headline().equals("A recompilação foi cancelada no GitHub."), "cancelled");

        EngineBuildInfo notoken = EngineBuildInfo.parse("token=no\nstate=none\n");
        expect(notoken.details().contains("Definir token do GitHub"), "no token hint");

        // a dash is "nothing"; the lines after "@" are not read
        EngineBuildInfo log = EngineBuildInfo.parse("state=failure\nfailed_job=-\nfailed_step=-\n@jobs\nstate=success\n");
        expect(log.get("failed_job").isEmpty() && log.state().equals("failure"), "dash and @ section");
        expect(!EngineBuildInfo.parse("chaos-ctl: token-missing: no token").valid() && !EngineBuildInfo.parse(null).valid(), "invalid");

        expect(EngineBuildInfo.elapsed(40).equals("40 s") && EngineBuildInfo.elapsed(125).equals("2 min")
                && EngineBuildInfo.elapsed(3600).equals("1 h 00 min"), "elapsed");

        expect(EngineBuildInfo.confirmText().contains("20 a 60 minutos") && EngineBuildInfo.confirmText().contains("Atualizar servidor")
                && EngineBuildInfo.confirmText().contains("segue no ar"), "confirmation text");
        expect(EngineBuildInfo.startText("started=yes\nrun_id=101\nclient_build=30\n")
                .equals("A recompilação começou no GitHub (rodada 101), client build 30."), "start text");
        expect(EngineBuildInfo.startText("note: client build 31 is a new client number\nstarted=yes\nrun_id=unknown\nclient_build=31\n")
                .contains("APK") && !EngineBuildInfo.startText("started=yes\nrun_id=unknown\nclient_build=31\n").contains("rodada"),
                "start text with a new number");
        expect(EngineBuildInfo.startText("nothing").equals("Não começou."), "start text without a start");

        EngineBuildInfo ch = EngineBuildInfo.parse("token=yes\nstate=success\nrelease_newer=yes\nclient_next=31\nclient_changed=yes\n");
        expect(ch.clientChanged() && ch.clientNext().equals("31") && ch.newClientLabel().equals("Recompilar com client novo (build 31)"),
                "client changed and next");
        expect(ch.details().contains("Recompilar com client novo (build 31)"), "details offer the new client: " + ch.details());
        expect(!EngineBuildInfo.parse("token=yes\nstate=none\nclient_next=31\nclient_changed=no\n").clientChanged()
                && !EngineBuildInfo.parse("token=yes\nstate=none\nclient_next=31\nclient_changed=no\n").details().contains("client novo"),
                "client unchanged: no offer");
        expect(!EngineBuildInfo.parse("token=yes\nstate=queued\nclient_changed=yes\nclient_next=31\n").details().contains("client novo"),
                "no offer while running");
        String nc = EngineBuildInfo.confirmNewClientText("31");
        expect(nc.contains("build 31") && nc.contains("clientGuardBuilds") && nc.contains("atualizador") && nc.contains("APK")
                && nc.contains("20 a 60 minutos") && nc.contains("Atualizar servidor"), "new client confirmation: " + nc);
        expect(EngineBuildInfo.startText("started=yes\nrun_id=7\nclient_build=31\nnew_client=yes\nguard=added\n").contains("entrou na lista clientGuardBuilds")
                && EngineBuildInfo.startText("started=yes\nrun_id=7\nclient_build=31\nguard=missing\n").contains("coloque o build nele"),
                "start text tells the guard list");
        expect(!EngineBuildInfo.refusal("chaos-ctl: update-running: x").isEmpty()
                && EngineBuildInfo.refusal("chaos-ctl: client-changed: x").contains("client novo"), "refusals offer the new client");
        String[] words = {"token-missing", "token-refused", "no-access", "build-running", "client-changed", "client-build-backwards",
            "client-build-unknown", "client-check-failed", "fetch-failed", "workflow-refused", "dispatch-failed", "github-unreachable"};
        for (String w : words) {
            expect(!EngineBuildInfo.refusal("chaos-ctl: " + w + ": whatever").isEmpty(), "refusal of " + w);
        }
        expect(EngineBuildInfo.refusal("chaos-ctl: something else").isEmpty() && EngineBuildInfo.refusal(null).isEmpty(), "unknown refusal");
                System.out.println("EngineBuildInfoTest: " + count + " checks, " + fails + " failures");
        System.exit(fails == 0 ? 0 : 1);
    }
}
