// Unit test of the wings' draw plan (base patch 0203, client/BASE.md "0203").
//   g++ -std=c++17 -I DIR client/tools/chaoswinglayers_test.cpp -o t   (DIR holds chaoswinglayers.h, extracted from the patch)
// Checks: a wings look with one y pattern is drawn once, before the body facing south or east and after it facing
// north or west (the engine's old order); a look with two y patterns is drawn twice in every direction, the whole
// wing before the body and the front part after it; odd pattern counts.
#include "chaoswinglayers.h"
#include <cstdio>

using namespace chaos::winglayers;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    // directions: 0 north, 1 east, 2 south, 3 west
    for (int dir = 0; dir < 4; ++dir) {
        const Plan one = plan(1, dir);
        const bool before = dir == 1 || dir == 2;
        CHECK(one.before == (before ? kWhole : kNone), "one pattern, direction %d: before", dir);
        CHECK(one.after == (before ? kNone : kWhole), "one pattern, direction %d: after", dir);
        CHECK((one.before == kNone) != (one.after == kNone), "one pattern: drawn exactly once");

        const Plan two = plan(2, dir);
        CHECK(two.before == kWhole && two.after == kFront, "two patterns, direction %d: whole then front", dir);
        const Plan more = plan(3, dir);
        CHECK(more.before == kWhole && more.after == kFront, "more patterns count as layered");
        const Plan none = plan(0, dir);
        CHECK(none.before == one.before && none.after == one.after, "a count under one is a plain wing");
    }
    CHECK(!layered(1) && layered(2), "layered from two y patterns");
    CHECK(kWhole == 0 && kFront == 1, "the pattern numbers the pair writes");

    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("chaoswinglayers_test OK\n");
    return 0;
}
