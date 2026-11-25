package com.cindersofchaos.admin;

/**
 * Plain-JVM check of SpawnDataInfo and StaffInfo (O765, no JUnit needed): javac -d out
 * app/src/main/java/com/cindersofchaos/admin/SpawnDataInfo.java app/src/main/java/com/cindersofchaos/admin/StaffInfo.java
 * app/src/test/java/com/cindersofchaos/admin/SpawnDataInfoTest.java && java -cp out com.cindersofchaos.admin.SpawnDataInfoTest
 */
public final class SpawnDataInfoTest {
    private static int fails = 0;
    private static int count = 0;

    private static void expect(boolean ok, String what) {
        count++;
        if (!ok) {
            fails++;
            System.out.println("FAIL " + what);
        }
    }

    // made-up outputs of chaos-ctl.sh spawn-data, in the command's order
    static final String DRY = "bounty_pool=changed\nbounty_pool_repo_copy=differs\nbounty_pool_lines=812\n"
            + "bestiary_spawns=same\nbestiary_spawns_repo_copy=same\nbestiary_spawns_lines=990\nspawn_data=dry-run\n"
            + "/tmp/x/bounty_pool.lua: written\n";
    static final String SAME = "bounty_pool=same\nbounty_pool_repo_copy=same\nbounty_pool_lines=812\n"
            + "bestiary_spawns=same\nbestiary_spawns_repo_copy=same\nbestiary_spawns_lines=990\nspawn_data=nothing\n";
    static final String WRITTEN = "bounty_pool=changed\nbounty_pool_repo_copy=same\nbounty_pool_lines=812\n"
            + "bestiary_spawns=new\nbestiary_spawns_repo_copy=same\nbestiary_spawns_lines=990\npoi=changed\n"
            + "spawn_data=written\nrestart_needed=yes\nchaos_poi.lua: 12 marks\n";
    static final String FAILED = "spawn_data=failed\nconfig.lua: mapName not found, pass --spawn\n";

    public static void main(String[] args) {
        String s = SpawnDataInfo.summary(DRY);
        expect(s != null && s.startsWith("Do mapa carregado: caçadas (bounty) muda, bestiário igual. Nada foi gravado")
                && s.contains("repositório ainda tem a cópia antiga"), "dry run: " + s);
        s = SpawnDataInfo.summary(SAME);
        expect(s != null && s.startsWith("Os dados de spawn já batem") && !s.contains("repositório"), "nothing: " + s);
        s = SpawnDataInfo.summary(WRITTEN);
        expect(s != null && s.startsWith("Gravado: caçadas (bounty) muda, bestiário é novo, marcadores do mapa mudam.")
                && s.contains("próximo reinício"), "written: " + s);
        s = SpawnDataInfo.summary(FAILED);
        expect(s != null && s.startsWith("Um gerador falhou"), "failed: " + s);
        expect(SpawnDataInfo.summary("die: no repo") == null && SpawnDataInfo.summary(null) == null,
                "no spawn_data line: null");
        expect(SpawnDataInfo.value(WRITTEN, "restart_needed").equals("yes") && SpawnDataInfo.value(DRY, "poi").isEmpty(),
                "value");
        expect(SpawnDataInfo.DRY_RUN.equals("spawn-data") && SpawnDataInfo.WRITE.equals("spawn-data --write"), "commands");

        // StaffInfo: gm-set and reload-file as chaos-ctl.sh takes them
        expect(StaffInfo.validName("Lord Ash") && StaffInfo.validName("Ka'el-Dor") && !StaffInfo.validName("Ab")
                && !StaffInfo.validName("Ash ") && !StaffInfo.validName("A  b") && !StaffInfo.validName("1abc")
                && !StaffInfo.validName("x$(id)") && !StaffInfo.validName(null), "validName");
        expect("gm-set 'Lord Ash' 4".equals(StaffInfo.gmSet("Lord Ash", 4))
                && "gm-set 'Ka'\\''el' 6".equals(StaffInfo.gmSet("Ka'el", 6))
                && StaffInfo.gmSet("Lord Ash", 0) == null && StaffInfo.gmSet("Lord Ash", 7) == null
                && StaffInfo.gmSet("x;rm", 4) == null, "gmSet");
        expect(StaffInfo.group(4).equals("gamemaster") && StaffInfo.group(6).equals("god") && StaffInfo.group(9).isEmpty(),
                "group names");
        expect("reload-file 'Lord Ash' pace_config".equals(StaffInfo.reloadFile("Lord Ash", "pace_config"))
                && "reload-file 'Lord Ash'".equals(StaffInfo.reloadFile("Lord Ash", ""))
                && "reload-file 'Lord Ash'".equals(StaffInfo.reloadFile("Lord Ash", null))
                && StaffInfo.reloadFile("Lord Ash", "Pace.lua") == null && StaffInfo.reloadFile("", "pace_config") == null,
                "reloadFile");
        expect(StaffInfo.configs("bestiary_config\npace_config\nnot a config\nx.lua\n\n").equals(
                java.util.Arrays.asList("bestiary_config", "pace_config")) && StaffInfo.configs(null).isEmpty(), "configs");

        System.out.println("SpawnDataInfoTest: " + count + " checks, " + fails + " failures");
        if (fails > 0) {
            System.exit(1);
        }
    }
}
