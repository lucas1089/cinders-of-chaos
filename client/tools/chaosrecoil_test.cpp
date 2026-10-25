// Unit test of the spawn fade and hit recoil maths (base patch 0151, client/BASE.md "0151").
//   g++ -std=c++17 -I DIR client/tools/chaosrecoil_test.cpp -o t   (DIR holds chaosrecoil.h, extracted from the patch)
// Checks: the fade curve (0 at the start, 1 at 180 ms, monotone, smooth, inside 0..1, a clock that jumps back); who fades
// (not the local player, not with the option off); the recoil share (1 at the start, 0 at 120 ms, monotone, ease-out);
// the offset (1-2 px, away from the attacker, back to 0, never above the peak); the unknown direction (always one of 8
// neighbours, spread over all of them); who recoils (not heals, not the first health, not off the map, not a death);
// the per-creature gap.
#include "chaosrecoil.h"
#include <cstdio>
#include <cstdlib>

using namespace chaos::recoil;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    // constants
    CHECK(kFadeMs >= 150 && kFadeMs <= 220, "about 180 ms: %d", kFadeMs);
    CHECK(kRecoilMs >= 100 && kRecoilMs <= 150, "about 120 ms: %d", kRecoilMs);
    CHECK(kMinGapMs > 0 && kMinGapMs <= kRecoilMs, "gap %d", kMinGapMs);
    CHECK(kSmallPx >= 1 && kSmallPx <= kBigPx && kBigPx <= 2, "pixels %d %d", kSmallPx, kBigPx);

    // fade curve
    CHECK(fadeAlpha(-50) == 0.0f && fadeAlpha(0) == 0.0f, "starts invisible");
    CHECK(fadeAlpha(kFadeMs) == 1.0f && fadeAlpha(kFadeMs + 100000) == 1.0f, "ends opaque");
    CHECK(fadeAlpha(INT64_MIN) == 0.0f && fadeAlpha(INT64_MAX) == 1.0f, "extreme values");
    float prev = 0.0f;
    for (int ms = 0; ms <= kFadeMs; ++ms) {
        const float a = fadeAlpha(ms);
        CHECK(a >= 0.0f && a <= 1.0f, "range at %d", ms);
        CHECK(a >= prev, "monotone at %d", ms);
        CHECK(a - prev < 0.04f, "no jump at %d: %f -> %f", ms, prev, a);
        prev = a;
    }
    CHECK(fadeAlpha(kFadeMs / 2) > 0.49f && fadeAlpha(kFadeMs / 2) < 0.51f, "half way at half the time: %f", fadeAlpha(kFadeMs / 2));

    // who fades
    CHECK(wantsFade(true, false), "a spawn");
    CHECK(!wantsFade(true, true), "never the local player");
    CHECK(!wantsFade(false, false), "option off");

    // pixels by hit size
    CHECK(pixelsForDrop(1) == kSmallPx && pixelsForDrop(kBigDrop - 1) == kSmallPx, "small hit");
    CHECK(pixelsForDrop(kBigDrop) == kBigPx && pixelsForDrop(100) == kBigPx, "big hit");
    CHECK(pixelsForDrop(0) == kSmallPx && pixelsForDrop(-4) == kSmallPx, "junk drop is small");

    // recoil share
    CHECK(recoilShare(-5) == 1.0f && recoilShare(0) == 1.0f, "starts full");
    CHECK(recoilShare(kRecoilMs) == 0.0f && recoilShare(INT64_MAX) == 0.0f, "ends at 0");
    float ps = 1.0f;
    for (int ms = 0; ms <= kRecoilMs; ++ms) {
        const float s = recoilShare(ms);
        CHECK(s >= 0.0f && s <= 1.0f, "range at %d", ms);
        CHECK(s <= ps, "monotone at %d", ms);
        ps = s;
    }
    CHECK(recoilShare(kRecoilMs / 2) > 0.2f && recoilShare(kRecoilMs / 2) < 0.3f, "ease-out at half: %f", recoilShare(kRecoilMs / 2));

    // direction away from the attacker
    {
        Offset d = pushDirection(true, 5, 0, 1);
        CHECK(d.x == 1 && d.y == 0, "east of the attacker is pushed east");
        d = pushDirection(true, -3, 7, 1);
        CHECK(d.x == -1 && d.y == 1, "diagonal");
        d = pushDirection(true, 0, -2, 99);
        CHECK(d.x == 0 && d.y == -1, "north");
        d = pushDirection(true, 0, 0, 7);
        CHECK(d.x != 0 || d.y != 0, "same tile falls back to random, never (0,0)");
        d = pushDirection(false, 4, 4, 7);
        const Offset r = randomDirection(7);
        CHECK(d.x == r.x && d.y == r.y, "unknown attacker is the random direction");
    }

    // random direction: valid, deterministic, spread over all 8 neighbours
    {
        int seen[3][3] = {};
        for (uint32_t s = 0; s < 4000; ++s) {
            const Offset a = randomDirection(s * 2654435761u + 12345u);
            const Offset b = randomDirection(s * 2654435761u + 12345u);
            CHECK(a.x == b.x && a.y == b.y, "deterministic");
            CHECK(a.x >= -1 && a.x <= 1 && a.y >= -1 && a.y <= 1 && (a.x != 0 || a.y != 0), "valid %d %d", a.x, a.y);
            ++seen[a.x + 1][a.y + 1];
        }
        int kinds = 0;
        for (int x = 0; x < 3; ++x)
            for (int y = 0; y < 3; ++y)
                if (seen[x][y] > 0) {
                    ++kinds;
                    CHECK(seen[x][y] > 300 && seen[x][y] < 700, "even spread %d,%d: %d", x - 1, y - 1, seen[x][y]);
                }
        CHECK(kinds == 8 && seen[1][1] == 0, "all 8 neighbours, never the centre: %d", kinds);
    }

    // offset: 1-2 px, away, back to 0
    for (int px = kSmallPx; px <= kBigPx; ++px) {
        for (int scale = 1; scale <= 4; ++scale) {
            for (int dx = -1; dx <= 1; ++dx) {
                for (int dy = -1; dy <= 1; ++dy) {
                    const Offset dir{ dx, dy };
                    const Offset first = offsetAt(0, dir, px, scale);
                    CHECK(first.x == dx * px * scale && first.y == dy * px * scale, "peak %d,%d px %d scale %d", dx, dy, px, scale);
                    int prevAbs = 1 << 20;
                    for (int ms = 0; ms <= kRecoilMs + 5; ++ms) {
                        const Offset o = offsetAt(ms, dir, px, scale);
                        CHECK(std::abs(o.x) <= px * scale && std::abs(o.y) <= px * scale, "bounded at %d", ms);
                        CHECK(dx == 0 ? o.x == 0 : (o.x * dx >= 0), "x keeps its side at %d", ms);
                        CHECK(dy == 0 ? o.y == 0 : (o.y * dy >= 0), "y keeps its side at %d", ms);
                        const int a = std::max(std::abs(o.x), std::abs(o.y));
                        CHECK(a <= prevAbs, "never grows at %d", ms);
                        prevAbs = a;
                    }
                    const Offset end = offsetAt(kRecoilMs, dir, px, scale);
                    CHECK(end.x == 0 && end.y == 0, "back on the tile");
                    const Offset late = offsetAt(100000, dir, px, scale);
                    CHECK(late.x == 0 && late.y == 0, "stays on the tile");
                }
            }
        }
    }
    {
        // junk input stays harmless
        const Offset o = offsetAt(10, Offset{ 5, -9 }, -3, 0);
        CHECK(o.x == 0 && o.y == 0, "negative px gives no nudge");
        const Offset p = offsetAt(0, Offset{ 5, -9 }, 2, 0);
        CHECK(p.x == 2 && p.y == -2, "direction is clamped to a sign, scale to 1: %d %d", p.x, p.y);
    }

    // who recoils: option, on a map tile, already shown, health down, not dead
    CHECK(wantsRecoil(true, true, true, 100, 80), "a hit");
    CHECK(wantsRecoil(true, true, true, 3, 1), "a hit that leaves 1%%");
    CHECK(!wantsRecoil(false, true, true, 100, 80), "option off");
    CHECK(!wantsRecoil(true, false, true, 100, 80), "not on the map");
    CHECK(!wantsRecoil(true, true, false, 100, 80), "first health after appearing");
    CHECK(!wantsRecoil(true, true, true, 50, 80), "heal");
    CHECK(!wantsRecoil(true, true, true, 80, 80), "no change");
    CHECK(!wantsRecoil(true, true, true, 20, 0), "death");

    // gap
    CHECK(gapPassed(0, 5000), "never recoiled");
    CHECK(!gapPassed(1000, 1000 + kMinGapMs - 1), "too soon");
    CHECK(gapPassed(1000, 1000 + kMinGapMs), "gap over");
    CHECK(gapPassed(5000, 4000), "clock ran backwards");

    if (failures == 0)
        std::printf("chaosrecoil_test: all checks passed\n");
    return failures == 0 ? 0 : 1;
}
