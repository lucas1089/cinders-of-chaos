package com.cindersofchaos.admin;

/**
 * Plain-JVM check of CastMath (no JUnit needed): javac -d out app/src/main/java/com/cindersofchaos/admin/CastMath.java
 * app/src/test/java/com/cindersofchaos/admin/CastMathTest.java && java -cp out com.cindersofchaos.admin.CastMathTest
 * 2026-10-26 owner report: the live view was black except names and health bars.
 */
public final class CastMathTest {
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
        // the cause: the game's own darkness leaves the map (nearly) black
        int night = CastMath.ambient(40, 215, 7);
        int cave = CastMath.ambient(250, 215, 9);
        expect(CastMath.dark(night), "night (world light 40) is dark: " + Integer.toHexString(night));
        expect(cave == 0 && CastMath.dark(cave), "underground has no ambient light at all");
        expect(!CastMath.dark(CastMath.ambient(250, 215, 7)), "day is not dark");
        // the fix: a readable minimum
        int n2 = CastMath.ambient(40, 215, 7, CastMath.READABLE);
        int c2 = CastMath.ambient(0, 215, 9, CastMath.READABLE);
        expect(!CastMath.dark(n2) && !CastMath.dark(c2), "the readable minimum lifts night and caves");
        expect((c2 >> 16 & 0xFF) == CastMath.READABLE && (c2 & 0xFF) == CastMath.READABLE, "a cave is a grey of the minimum");
        expect(CastMath.ambient(250, 215, 7, CastMath.READABLE) == CastMath.ambient(250, 215, 7), "day is untouched");
        expect(CastMath.ambient(40, 215, 7, 0) == night, "minimum 0 is the game's light");
        expect(CastMath.ambient(300, 215, 7, 999) == 0xFFFFFF, "clamped");
        expect(CastMath.cell(10, 7, 6) == 9 && CastMath.world(9, 7, 6) == 10, "floor shift");
        System.out.println("CastMathTest: " + count + " checks, " + fails + " failures");
        System.exit(fails == 0 ? 0 : 1);
    }
}
