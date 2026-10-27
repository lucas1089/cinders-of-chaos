package com.cindersofchaos.admin;

/**
 * Plain-JVM check of DiscordInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/DiscordInfo.java
 * app/src/test/java/com/cindersofchaos/admin/DiscordInfoTest.java && java -cp out com.cindersofchaos.admin.DiscordInfoTest
 */
public final class DiscordInfoTest {
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
        String tok = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-aBcD";
        expect(DiscordInfo.valid("https://discord.com/api/webhooks/123456789012345678/" + tok), "discord.com");
        expect(DiscordInfo.valid("https://discordapp.com/api/webhooks/12345/" + tok), "discordapp.com");
        expect(DiscordInfo.valid("https://canary.discord.com/api/webhooks/12345/" + tok), "canary");
        expect(DiscordInfo.valid("https://ptb.discord.com/api/webhooks/12345/" + tok), "ptb");
        String[] bad = {"", "http://discord.com/api/webhooks/12345/" + tok, "https://evil.com/api/webhooks/12345/" + tok,
            "https://discord.com.evil.com/api/webhooks/12345/" + tok, "https://discord.com/api/webhooks/1234/" + tok,
            "https://discord.com/api/webhooks/12345/short", "https://discord.com/api/webhooks/12345/" + tok + "?wait=true",
            "https://discord.com/api/webhooks/12345/" + tok + "\nX=1", " https://discord.com/api/webhooks/12345/" + tok,
            "https://discord.com/api/webhooks/12345/" + tok + "/x", "https://u@discord.com/api/webhooks/12345/" + tok};
        for (String b : bad) {
            expect(!DiscordInfo.valid(b), "refused: " + b.replace("\n", "\\n"));
        }
        expect(!DiscordInfo.valid(null), "null");
        expect(DiscordInfo.CHANNELS.size() == 8 && DiscordInfo.CHANNELS.containsKey("default"), "eight channels");

        String out = "channel_records=yes id_end=5432\nchannel_bosses=no\nchannel_default=yes id_end=1111\ntimer_enabled=enabled\n"
                + "timer_active=active\n@log\nchannel_bosses=yes id_end=0000\n";
        expect(DiscordInfo.summary(out).equals("Postagem: ligado. Webhooks salvos: records, default."), "summary: " + DiscordInfo.summary(out));
        expect(DiscordInfo.idEnd(out, "records").equals("5432") && DiscordInfo.idEnd(out, "bosses").isEmpty()
                && DiscordInfo.idEnd(out, "status").isEmpty(), "id end");
        expect(DiscordInfo.summary("timer_enabled=disabled\ntimer_active=inactive\n").equals("Postagem: desligado. Webhooks salvos: nenhum."), "off");
        expect(DiscordInfo.summary("timer_enabled=enabled\ntimer_active=inactive\n").contains("ativado, mas parado"), "enabled but stopped");
        expect(DiscordInfo.summary("").equals("Toque em Atualizar status."), "empty");
        System.out.println("DiscordInfoTest: " + count + " checks, " + fails + " failures");
        System.exit(fails == 0 ? 0 : 1);
    }
}
