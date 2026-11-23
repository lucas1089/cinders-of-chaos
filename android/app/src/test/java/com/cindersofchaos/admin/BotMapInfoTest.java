package com.cindersofchaos.admin;

/**
 * Plain-JVM check of BotMapInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/BotMapInfo.java
 * app/src/test/java/com/cindersofchaos/admin/BotMapInfoTest.java && java -cp out com.cindersofchaos.admin.BotMapInfoTest
 */
public final class BotMapInfoTest {
    private static int fails = 0;

    private static void expect(boolean ok, String what) {
        if (!ok) {
            fails++;
            System.out.println("FAIL " + what);
        }
    }

    static final String BUILT = "bots=4\nstale=1\nmap=yes\nbuilt=2026-11-23 10:15:00\nfloors=9\nsize_mb=412\nfolder=botmap-0123456789abcdef0123456789abcdef\n"
            + "page=https://www.example.org/page?plugin=chaos&p=botmap\n";
    static final String EMPTY = "bots=0\nstale=0\nmap=no\nbuilt=\nfloors=0\nsize_mb=\nfolder=\npage=\n";

    public static void main(String[] args) {
        BotMapInfo b = BotMapInfo.parse(BUILT);
        expect(b != null && b.bots == 4 && b.stale == 1 && b.map && b.floors == 9 && b.sizeMb.equals("412") && b.built.equals("2026-11-23 10:15:00"), "fields");
        expect(b.page.equals("https://www.example.org/page?plugin=chaos&p=botmap"), "the page address: " + b.page);
        String s = b.summary();
        expect(s.startsWith("4 bots no mapa (1 sem notícia há mais de 2 minutos, em cinza).\n"), "summary, bots: " + s);
        expect(s.contains("Mapa montado em 2026-11-23 10:15:00, 9 andares, 412 MB."), "summary, map: " + s);
        expect(!s.contains("CHAOS_SITE_URL"), "no site warning when the page is known");
        BotMapInfo e = BotMapInfo.parse(EMPTY);
        expect(e != null && e.bots == 0 && !e.map && e.page.isEmpty(), "an empty state parses");
        String es = e.summary();
        expect(es.startsWith("Nenhum bot publicando agora.\n") && es.contains("O mapa ainda não foi montado") && es.contains("CHAOS_SITE_URL"), "empty summary: " + es);
        expect(BotMapInfo.parse("bots=1\nstale=0\nmap=yes\nfloors=1\n").summary().contains("1 bot no mapa.") && BotMapInfo.parse("bots=1\nmap=yes\nfloors=1\n").summary().contains("1 andar."), "singular");
        expect(BotMapInfo.parse(null) == null && BotMapInfo.parse("") == null && BotMapInfo.parse("chaos-ctl: unknown command: botmap-status\n") == null, "no lines, no info");
        expect(BotMapInfo.parse("bots=x\nstale=-4\nmap=maybe\nfloors=\n").bots == 0 && !BotMapInfo.parse("bots=x\nstale=-4\nmap=maybe\nfloors=\n").map, "bad numbers are 0, the map flag is yes or no");
        // only the staff page over https is ever opened
        for (String bad : new String[] {"", null, "http://www.example.org/page?plugin=chaos&p=botmap", "https://evil.example/x", "https://www.example.org/page?plugin=chaos&p=reports",
                "https://www.example.org/page?plugin=chaos&p=botmap&x=1", "javascript:alert(1)", "file:///etc/passwd", "https://exa mple.org/page?plugin=chaos&p=botmap",
                "https://user:pw@www.example.org/page?plugin=chaos&p=botmap", "https://www.example.org/page?plugin=chaos&p=botmap\nhttps://evil.example"}) {
            expect(BotMapInfo.safePage(bad).isEmpty(), "refused address: " + bad);
        }
        expect(BotMapInfo.safePage("https://www.example.org:8443/sub/page?plugin=chaos&p=botmap").equals("https://www.example.org:8443/sub/page?plugin=chaos&p=botmap"), "a port and a path are fine");
        expect(BotMapInfo.parse("bots=1\nmap=no\npage=http://www.example.org/page?plugin=chaos&p=botmap\n").page.isEmpty(), "an http address from the command is dropped");
        if (fails > 0) {
            System.exit(1);
        }
        System.out.println("BotMapInfoTest ok");
    }
}
