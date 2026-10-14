// Tests of the big creature click maths (src/client/creaturehit.h, added by
// client/base-patches/0051-big-creature-click.patch). Header only, no engine; build against an assembled client tree:
//   g++ -std=c++17 -Wall -Wextra -I <game-dir>/src/client client/tools/creaturehit_test.cpp -o /tmp/creaturehit_test && /tmp/creaturehit_test
// The numbers are in map framebuffer pixels with 32 px sprites, as MapView records them.
#include "creaturehit.h"

#include <cstdio>
#include <vector>

using namespace CreatureHit;

static int fails = 0, checks = 0;
static void check(bool ok, const char* what)
{
    ++checks;
    if (!ok) {
        std::printf("FAIL %s\n", what);
        ++fails;
    }
}

static Candidate cand(bool ownTile, bool pixels, bool localPlayer = false)
{
    Candidate c;
    c.ownTile = ownTile;
    c.pixels = pixels;
    c.localPlayer = localPlayer;
    return c;
}

int main()
{
    // drawn box: a 4x4 guardian on the tile at (320, 256) covers the 4x4 tiles up and left of it
    {
        const Box b = drawnBox(320, 256, 0, 0, 4, 4, 32);
        check(b.x == 224 && b.y == 160 && b.w == 128 && b.h == 128, "4x4 box");
        check(b.contains(224, 160), "4x4 top-left pixel");
        check(b.contains(351, 287), "4x4 bottom-right pixel");
        check(!b.contains(352, 287) && !b.contains(351, 288), "4x4 right and bottom edges are outside");
        // a 2x2 with displacement 8 (up and left)
        const Box d = drawnBox(320, 256, 8, 8, 2, 2, 32);
        check(d.x == 280 && d.y == 216 && d.w == 64 && d.h == 64, "2x2 displaced box");
        // one tile, no displacement: the stock click box
        const Box o = drawnBox(320, 256, 0, 0, 1, 1, 32);
        check(o.x == 320 && o.y == 256 && o.w == 32 && o.h == 32, "own tile box");
        check(!Box{ 0, 0, 0, 5 }.contains(0, 0), "empty box contains nothing");
    }

    // big: wider or taller than one tile
    check(!isBig(1, 1) && isBig(2, 1) && isBig(1, 2) && isBig(4, 4), "isBig");

    // unscale: the inverse of a scale around the feet (draw scale 2 around (336, 288))
    {
        int x = 336 + 40, y = 288 - 60;
        unscale(2.f, 336, 288, x, y);
        check(x == 356 && y == 258, "unscale 2x");
        int a = 100, b = 50;
        unscale(1.f, 0, 0, a, b);
        check(a == 100 && b == 50, "unscale 1x leaves the point");
        unscale(0.f, 0, 0, a, b);
        check(a == 100 && b == 50, "unscale 0 is ignored");
        // round trip of p' = c + (p - c) * f
        int px = 300, py = 200;
        const int cx = 336, cy = 288;
        const float f = 1.5f;
        int sx = cx + (int)((px - cx) * f), sy = cy + (int)((py - cy) * f);
        unscale(f, cx, cy, sx, sy);
        check(sx == px && sy == py, "unscale round trip 1.5x");
    }

    // texelAt: dest and src of the same size, scaled, flipped
    {
        int tx = 0, ty = 0;
        check(texelAt(Box{ 100, 100, 64, 64 }, Box{ 32, 0, 64, 64 }, 0, 110, 120, tx, ty) && tx == 42 && ty == 20, "texel 1:1");
        check(!texelAt(Box{ 100, 100, 64, 64 }, Box{ 32, 0, 64, 64 }, 0, 164, 120, tx, ty), "texel outside dest");
        check(texelAt(Box{ 0, 0, 128, 128 }, Box{ 0, 0, 64, 64 }, 0, 127, 64, tx, ty) && tx == 63 && ty == 32, "texel 2x dest");
        check(texelAt(Box{ 100, 100, 64, 64 }, Box{ 32, 0, 64, 64 }, 1, 100, 100, tx, ty) && tx == 95 && ty == 0, "texel flipped x");
        check(texelAt(Box{ 100, 100, 64, 64 }, Box{ 32, 0, 64, 64 }, 2, 100, 100, tx, ty) && tx == 32 && ty == 63, "texel flipped y");
        check(!texelAt(Box{ 0, 0, 10, 10 }, Box{ 0, 0, 0, 0 }, 0, 1, 1, tx, ty), "texel of an empty src");
    }

    // alpha mask: bits per pixel, out of range reads false and writes nothing
    {
        AlphaMask m;
        m.reset(13, 7);
        check(m.bits.size() == (13 * 7 + 7) / 8, "mask size");
        m.set(0, 0);
        m.set(12, 6);
        m.set(5, 3);
        m.set(-1, 0);
        m.set(13, 0);
        check(m.get(0, 0) && m.get(12, 6) && m.get(5, 3), "mask set bits");
        check(!m.get(1, 0) && !m.get(4, 3) && !m.get(12, 5), "mask clear bits");
        check(!m.get(-1, 0) && !m.get(0, 7) && !m.get(13, 0), "mask out of range");
        AlphaMask empty;
        check(!empty.get(0, 0), "empty mask");
    }

    // partHit: a 64x64 part whose texture has one opaque 8x8 block at (16..23, 40..47)
    {
        AlphaMask m;
        m.reset(64, 64);
        for (int y = 40; y < 48; ++y)
            for (int x = 16; x < 24; ++x)
                m.set(x, y);
        const Box dest{ 224, 160, 64, 64 }, src{ 0, 0, 64, 64 };
        check(partHit(dest, src, 0, &m, 224 + 16, 160 + 40), "pixel hit on the opaque block");
        check(partHit(dest, src, 0, &m, 224 + 23, 160 + 47), "pixel hit on the block's last pixel");
        check(!partHit(dest, src, 0, &m, 224 + 24, 160 + 40), "transparent pixel next to the block");
        check(!partHit(dest, src, 0, &m, 224, 160), "transparent corner of the box");
        check(partHit(dest, src, 0, nullptr, 224, 160), "no mask: the box counts");
        check(!partHit(dest, src, 0, nullptr, 223, 160), "no mask: outside the box");
        // the same part drawn at 2x (draw scale handled by unscale, a stretched quad by texelAt)
        check(partHit(Box{ 0, 0, 128, 128 }, src, 0, &m, 33, 81), "stretched part hit");
        check(!partHit(Box{ 0, 0, 128, 128 }, src, 0, &m, 31, 81), "stretched part miss");
    }

    // pick: draw order, the last one is on top
    {
        check(pick({}) == -1, "nothing drawn");
        check(pick({ cand(false, false), cand(false, false) }) == -1, "nothing hit");
        check(pick({ cand(true, false), cand(false, false) }) == 0, "a small creature on its tile");
        check(pick({ cand(true, false), cand(false, true) }) == 1, "a big creature drawn over a small one wins");
        check(pick({ cand(false, true), cand(true, false) }) == 1, "a small one drawn over a big one wins");
        check(pick({ cand(false, true), cand(false, true) }) == 1, "two big ones: the topmost");
        // the own character
        check(pick({ cand(true, false, true) }) == 0, "the own character alone");
        check(pick({ cand(true, false, true), cand(false, true) }) == 0, "a big overhang never steals the own character");
        check(pick({ cand(false, true), cand(true, false, true) }) == 1, "a big overhang under the own character");
        check(pick({ cand(true, false, true), cand(true, true) }) == 1, "a creature standing on the own tile keeps the stock order");
        check(pick({ cand(true, false), cand(true, false, true) }) == 0, "stock order: another creature before the own character");
        check(pick({ cand(false, true, true), cand(false, true) }) == 0, "a big own look against a big overhang");
        check(pick({ cand(false, false, true), cand(false, true) }) == 1, "the own character not hit: the big creature");
    }

    std::printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
