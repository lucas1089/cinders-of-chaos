// Unit test of the missile trail and arc maths (base patch 0147, client/BASE.md "69zn").
//   g++ -std=c++17 -I DIR client/tools/chaosmissile_test.cpp -o t   (DIR holds chaosmissile.h, extracted from the patch)
// Checks: trail fractions and opacities (falling, inside 0..1, none before the path start, at most the cap), the distance
// gate, the arc (0 at both ends, h in the middle, symmetric, never negative, capped, 0 for a missile outside the list),
// junk input (NaN, negative, huge), and the id set (bounds, clear).
#include "chaosmissile.h"
#include <cmath>
#include <cstdio>
#include <limits>

using namespace chaos::missile;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    CHECK(kTrailCount >= 3 && kTrailCount <= kMaxTrail, "3-4 trail copies: %d", kTrailCount);
    CHECK(kTrailStep > 0.0f && kTrailStep * kMaxTrail < 0.5f, "short trail");

    // opacity falls with k and stays inside (0, 1)
    float prev = 1.0f;
    for (int k = 1; k <= kMaxTrail; ++k) {
        const float o = trailOpacity(k);
        CHECK(o > 0.0f && o < 1.0f, "range at %d: %f", k, o);
        CHECK(o < prev, "falls at %d: %f", k, o);
        prev = o;
    }
    CHECK(trailOpacity(0) == trailOpacity(1) && trailOpacity(-3) == trailOpacity(1), "junk k is the first copy");
    CHECK(trailOpacity(99) == trailOpacity(kMaxTrail), "k over the cap is the last copy");

    // fractions: f - k * 0.05, none before the start
    CHECK(std::fabs(trailFraction(0.5f, 1) - 0.45f) < 1e-6f, "k=1 %f", trailFraction(0.5f, 1));
    CHECK(std::fabs(trailFraction(0.5f, 3) - 0.35f) < 1e-6f, "k=3 %f", trailFraction(0.5f, 3));
    CHECK(trailFraction(0.02f, 1) < 0.0f, "before the start is negative");
    CHECK(trailCount(0.0f) == 0, "at the start no trail");
    CHECK(trailCount(0.04f) == 0, "just left: none");
    CHECK(trailCount(0.06f) == 1, "one copy fits at 0.06: %d", trailCount(0.06f));
    CHECK(trailCount(0.11f) == 2, "two at 0.11: %d", trailCount(0.11f));
    CHECK(trailCount(0.16f) == kTrailCount, "all at 0.16: %d", trailCount(0.16f));
    CHECK(trailCount(0.5f) == kTrailCount && trailCount(1.0f) == kTrailCount, "all in flight");
    CHECK(trailCount(5.0f) == kTrailCount, "fraction over 1 is clamped");
    CHECK(trailCount(-1.0f) == 0, "negative fraction");
    CHECK(trailCount(std::numeric_limits<float>::quiet_NaN()) == 0, "NaN fraction");
    int last = 0;
    for (int i = 0; i <= 1000; ++i) {
        const int n = trailCount(i / 1000.0f);
        CHECK(n >= last && n <= kTrailCount, "monotone count at %d", i);
        last = n;
        for (int k = 1; k <= n; ++k)
            CHECK(trailFraction(i / 1000.0f, k) >= 0.0f, "no copy before the start at %d", i);
    }

    // distance gate
    CHECK(!wantsEffect(0.0f) && !wantsEffect(1.0f) && !wantsEffect(1.99f), "short shot");
    CHECK(wantsEffect(2.0f) && wantsEffect(7.0f), "long shot");
    CHECK(!wantsEffect(std::numeric_limits<float>::quiet_NaN()), "NaN distance");

    // arc height
    CHECK(arcHeight(5.0f, false) == 0.0f, "not in the list: straight");
    CHECK(arcHeight(0.0f, true) == 0.0f && arcHeight(-3.0f, true) == 0.0f, "no distance");
    CHECK(arcHeight(std::numeric_limits<float>::quiet_NaN(), true) == 0.0f, "NaN distance");
    float hp = 0.0f;
    for (int t = 1; t <= 60; ++t) {
        const float h = arcHeight(static_cast<float>(t), true);
        CHECK(h > 0.0f && h <= kArcMax, "range at %d tiles: %f", t, h);
        CHECK(h >= hp, "grows with distance at %d", t);
        hp = h;
    }
    CHECK(arcHeight(1000.0f, true) == kArcMax, "capped");
    CHECK(arcHeight(2.0f, true) < arcHeight(7.0f, true), "scaled by distance");

    // arc lift: 4 h f (1 - f)
    const float h = 10.0f;
    CHECK(arcLift(0.0f, h) == 0.0f && arcLift(1.0f, h) == 0.0f, "flat at both ends");
    CHECK(std::fabs(arcLift(0.5f, h) - h) < 1e-5f, "top is h: %f", arcLift(0.5f, h));
    CHECK(std::fabs(arcLift(0.25f, h) - 7.5f) < 1e-5f, "quarter %f", arcLift(0.25f, h));
    for (int i = 0; i <= 100; ++i) {
        const float f = i / 100.0f;
        const float a = arcLift(f, h);
        CHECK(a >= 0.0f && a <= h + 1e-5f, "range at %d", i);
        CHECK(std::fabs(a - arcLift(1.0f - f, h)) < 1e-4f, "symmetric at %d", i);
    }
    CHECK(arcLift(-2.0f, h) == 0.0f && arcLift(9.0f, h) == 0.0f, "outside the path");
    CHECK(arcLift(std::numeric_limits<float>::quiet_NaN(), h) == 0.0f, "NaN fraction");
    CHECK(arcLift(0.5f, 0.0f) == 0.0f, "h 0 is straight");

    // id set
    IdSet ids;
    CHECK(ids.size() == 0 && !ids.contains(3), "empty");
    ids.add(3);
    ids.add(2);
    ids.add(3);
    CHECK(ids.size() == 2 && ids.contains(2) && ids.contains(3) && !ids.contains(4), "added");
    ids.add(0);
    ids.add(-5);
    ids.add(65536);
    ids.add(1 << 30);
    CHECK(ids.size() == 2, "out of range ids are ignored");
    CHECK(!ids.contains(0) && !ids.contains(-1) && !ids.contains(65536) && !ids.contains(1 << 30), "out of range lookups");
    ids.add(65535);
    CHECK(ids.contains(65535) && ids.size() == 3, "highest id");
    ids.clear();
    CHECK(ids.size() == 0 && !ids.contains(3), "cleared");

    if (failures == 0)
        std::printf("chaosmissile_test: all ok\n");
    return failures == 0 ? 0 : 1;
}
