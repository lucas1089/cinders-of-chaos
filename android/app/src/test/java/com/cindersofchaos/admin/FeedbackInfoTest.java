package com.cindersofchaos.admin;

import java.util.List;

/**
 * Plain-JVM check of FeedbackInfo (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/FeedbackInfo.java
 * app/src/test/java/com/cindersofchaos/admin/FeedbackInfoTest.java && java -cp out com.cindersofchaos.admin.FeedbackInfoTest
 */
public final class FeedbackInfoTest {
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
        String out = "#12 | 2026-10-27 14:03 UTC | map | open | pos 1010,990,7 | lvl 120 Mystic\n"
                + "  Wall \\x missing near the gate\n"
                + "#11 | 2026-10-26 07:33 UTC | suggestion | closed | pos 1,2,7\n"
                + "  more depots please\n"
                + "  from: Bobby\n"
                + "  closed: done; thanks\u0007\n"
                + "#9 | 2026-10-25 01:00 UTC | other | open | pos 5,6,7 | lvl 8 Iron Sage\n"
                + "  -\n"
                + "-- 3 reports\n";
        List<FeedbackInfo.Item> l = FeedbackInfo.parse(out);
        expect(l.size() == 3, "three blocks: " + l.size());
        FeedbackInfo.Item a = l.get(0);
        expect(a.id == 12 && a.category.equals("map") && !a.closed && a.pos.equals("1010,990,7")
                && a.who.equals("lvl 120 Mystic") && a.when.equals("2026-10-27 14:03 UTC"), "first block fields");
        expect(a.text.equals("Wall \\x missing near the gate"), "first text: " + a.text);
        FeedbackInfo.Item b = l.get(1);
        expect(b.closed && b.category.equals("suggestion") && b.who.isEmpty() && b.closedNote.equals("done; thanks"),
                "closed block with a note, control char dropped: " + b.closedNote);
        expect(b.raw.contains("from: Bobby"), "raw keeps the server text");
        expect(!b.text.contains("Bobby") && !b.closedNote.contains("Bobby"), "name never shown");
        expect(FeedbackInfo.parse("No bug reports or suggestions.\n").isEmpty(), "nothing to show");
        expect(FeedbackInfo.parse("chaos-ctl: database-down: x").isEmpty() && FeedbackInfo.parse(null).isEmpty(), "errors give none");
        expect(FeedbackInfo.parse("#1 | evil\n  text\n").isEmpty(), "a malformed header is no block");
        expect(FeedbackInfo.parse("#1; rm -rf | 2026-10-27 14:03 UTC | map | open | pos 1,2,3\n  x\n").isEmpty(), "a bad id is no block");

        expect(FeedbackInfo.days("30") == 30 && FeedbackInfo.days(" 7 ") == 7 && FeedbackInfo.days("3650") == 3650, "days ok");
        String[] bad = {"", "0", "3651", "-1", "x", "1;id", "1 2", "99999", "1e3", null};
        for (String s : bad) {
            expect(FeedbackInfo.days(s) == -1, "days refuses " + s);
        }
        expect(FeedbackInfo.listArgs(30, false, "").equals("feedback --days 30"), "list args default");
        expect(FeedbackInfo.listArgs(7, true, "suggestion").equals("feedback --days 7 --all --category suggestion"), "list args all");
        expect(FeedbackInfo.listArgs(7, false, "map; id").equals("feedback --days 7"), "an unknown category is dropped");
        expect(FeedbackInfo.closeArgs(12, "").equals("feedback-close 12") && FeedbackInfo.closeArgs(12, "'ok'").equals("feedback-close 12 'ok'"),
                "close args");
        expect(FeedbackInfo.summary(l).equals("3 relatos, 2 abertos, 1 sugestão."), "summary: " + FeedbackInfo.summary(l));
        expect(FeedbackInfo.summary(new java.util.ArrayList<FeedbackInfo.Item>()).startsWith("Nenhum"), "summary empty");
        String copy = FeedbackInfo.copyAll(l);
        expect(copy.startsWith("Relatos de bugs e sugestões") && copy.contains("#12 | 2026-10-27") && copy.contains("(3,"), "copy text");
        expect(FeedbackInfo.categoryLabel("suggestion").equals("Sugestão") && FeedbackInfo.categoryLabel("zzz").equals("Outro"), "labels");
        System.out.println("FeedbackInfoTest: " + count + " checks, " + fails + " failed");
        System.exit(fails == 0 ? 0 : 1);
    }
}
