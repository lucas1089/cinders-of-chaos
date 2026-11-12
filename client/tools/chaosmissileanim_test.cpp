// Unit test of the missile animation phase (base patch 0194, client/BASE.md "0194").
//   g++ -std=c++17 -I DIR client/tools/chaosmissileanim_test.cpp -o t   (DIR holds chaosmissileanim.h, extracted from the patch)
// Checks: 1 phase and 0 phases are phase 0, the fixed 50 ms step, per-phase durations (uneven, with a 0 meaning the fixed step),
// the phase never leaves 0..n-1, wrap of a long flight, negative and huge elapsed time, more phases than the cap, and the
// step through a whole flight of the pair's missiles (8 phases of 50 and of 83 ms, 1 to 9 tiles: every phase is shown).
#include "chaosmissileanim.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

using namespace chaos::missileanim;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    CHECK(kFixedMs == 50, "fixed step is 50 ms");

    // one phase or none: always phase 0 (the draw before the patch)
    for (long t : {-5L, 0L, 49L, 50L, 1000L, 100000000L}) {
        CHECK(phaseFixed(t, 1) == 0, "1 phase at %ld", t);
        CHECK(phaseFixed(t, 0) == 0, "0 phases at %ld", t);
        CHECK(phaseFixed(t, -3) == 0, "negative count at %ld", t);
    }

    // fixed 50 ms: 8 phases
    CHECK(phaseFixed(0, 8) == 0 && phaseFixed(49, 8) == 0, "first phase");
    CHECK(phaseFixed(50, 8) == 1 && phaseFixed(99, 8) == 1, "second phase");
    CHECK(phaseFixed(350, 8) == 7 && phaseFixed(399, 8) == 7, "last phase");
    CHECK(phaseFixed(400, 8) == 0 && phaseFixed(450, 8) == 1, "wraps after 400 ms");
    CHECK(phaseFixed(-1, 8) == 0 && phaseFixed(-100000, 8) == 0, "negative time is phase 0");
    CHECK(phaseFixed(2000000000L, 8) >= 0 && phaseFixed(2000000000L, 8) < 8, "huge time stays inside");

    // durations from the dat: 83 ms each, and uneven ones
    auto d83 = [](int) { return 83; };
    CHECK(phaseAt(0, 8, d83) == 0 && phaseAt(82, 8, d83) == 0 && phaseAt(83, 8, d83) == 1, "83 ms steps");
    CHECK(phaseAt(83 * 8, 8, d83) == 0, "83 ms wrap");
    std::vector<int> uneven = {10, 20, 30, 40};
    auto du = [&](int i) { return uneven[i]; };
    CHECK(phaseAt(9, 4, du) == 0 && phaseAt(10, 4, du) == 1 && phaseAt(29, 4, du) == 1 && phaseAt(30, 4, du) == 2, "uneven steps");
    CHECK(phaseAt(59, 4, du) == 2 && phaseAt(60, 4, du) == 3 && phaseAt(99, 4, du) == 3 && phaseAt(100, 4, du) == 0, "uneven wrap");
    // a duration of 0 or less is the fixed step
    auto dz = [](int i) { return i == 1 ? 0 : 20; };
    CHECK(phaseAt(19, 3, dz) == 0 && phaseAt(20, 3, dz) == 1 && phaseAt(69, 3, dz) == 1 && phaseAt(70, 3, dz) == 2, "0 ms is the fixed step");
    auto dn = [](int) { return -7; };
    CHECK(phaseAt(50, 4, dn) == 1, "negative duration is the fixed step");
    // all zero is the fixed step as well
    CHECK(phaseAt(120, 3, [](int) { return 0; }) == 2, "no durations");

    // more phases than the dat can hold: capped, still inside
    CHECK(phaseFixed(99999, 1000) < kMaxPhases, "capped");

    // the phase is always in range and non-decreasing inside one cycle, for a flight of 1..9 tiles
    for (int step : {50, 83}) {
        auto d = [step](int) { return step; };
        for (int tiles = 1; tiles <= 9; ++tiles) {
            const long flight = std::lround(150.0 * std::sqrt(static_cast<double>(tiles)));
            int last = 0;
            bool seen[8] = {false};
            for (long t = 0; t <= flight; ++t) {
                const int p = phaseAt(t, 8, d);
                CHECK(p >= 0 && p < 8, "range");
                if (t < 8L * step)
                    CHECK(p >= last, "monotone in the first cycle at %ld", t);
                last = p;
                seen[p] = true;
            }
            int shown = 0;
            for (bool s : seen)
                shown += s ? 1 : 0;
            // a flight of 150 ms (1 tile) shows 3 to 4 phases at 50 ms; from 3 tiles on (260 ms) 6 or more; all 8 from 7 tiles at 50 ms
            CHECK(shown >= static_cast<int>(std::min<long>(8, flight / step)), "phases shown over %d tiles at %d ms: %d", tiles, step, shown);
        }
    }

    if (failures == 0)
        std::printf("chaosmissileanim_test: all ok\n");
    return failures == 0 ? 0 : 1;
}
