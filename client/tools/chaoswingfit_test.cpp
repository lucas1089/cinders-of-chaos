// Unit test of the wings centring maths (base patch 0193, client/BASE.md "0193").
//   g++ -std=c++17 -I DIR client/tools/chaoswingfit_test.cpp -o t   (DIR holds chaoswingfit.h, extracted from the patch)
// Checks: the shift puts the wings' pair centre on the body's torso as Outfit::draw places them (wings at the creature's
// place, body `lift` px up and left); no row, a half set row, a bad direction and a bad table row give no shift; the
// shift does not depend on the bob (both parts move together); clearing the tables; the limits of a row.
#include "chaoswingfit.h"
#include <cstdio>

using namespace chaos::wingfit;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

// where the torso and the wings' pair centre land, x, for a creature at `dest`, bob `bob` (both parts move up and left by
// it), with the shift applied to the wings
static void landing(int dest, int bob, int bodyC, int wingsC, int shift, int lift, int& torso, int& pair)
{
    torso = dest - lift - bob + bodyC;
    pair = dest - bob + shift + wingsC;
}

int main()
{
    clearCentres();
    CHECK(shiftX(2073, 2414, 2, kLiftPx) == 0, "no tables: no shift");

    // a class look whose torso is at -9 and wings whose pair centre is at +4 (px from the creature's place, displacement out)
    CHECK(setBodyCentre(2073, 2, -9), "body row");
    CHECK(shiftX(2073, 2414, 2, kLiftPx) == 0, "wings without a row: no shift");
    CHECK(setWingsCentre(2414, 2, 4), "wings row");
    const int s = shiftX(2073, 2414, 2, kLiftPx);
    CHECK(s == -9 - 4 - 6, "shift %d", s);
    for (int bob = 0; bob <= 4; ++bob) {
        int torso, pair;
        landing(320, bob, -9, 4, s, kLiftPx, torso, pair);
        CHECK(torso == pair, "bob %d: torso %d pair %d", bob, torso, pair);
    }
    // another direction of the same look has no row yet
    CHECK(shiftX(2073, 2414, 0, kLiftPx) == 0, "north has no row");
    CHECK(setBodyCentre(2073, 0, 3) && setWingsCentre(2414, 0, 5), "north rows");
    CHECK(shiftX(2073, 2414, 0, kLiftPx) == 3 - 5 - 6, "north shift");
    CHECK(shiftX(2073, 2414, 2, kLiftPx) == s, "south untouched by north rows");

    // without the lift feature the shift has no lift term and the parts meet
    {
        const int s0 = shiftX(2073, 2414, 2, 0);
        int torso, pair;
        landing(100, 0, -9, 4, s0, 0, torso, pair);
        CHECK(s0 == -13 && torso == pair, "no lift: %d", s0);
    }

    // the stock reference body: a body at the same centre as the wings' (lifted) needs no shift beyond the lift
    CHECK(setBodyCentre(128, 2, 7) && setWingsCentre(937, 2, 7 - kLiftPx), "reference rows");
    CHECK(shiftX(128, 937, 2, kLiftPx) == 0, "wings already on the body: 0");

    // bad directions and bad rows are refused
    CHECK(!setBodyCentre(5, 4, 0) && !setBodyCentre(5, -1, 0), "direction range");
    CHECK(!setBodyCentre(0, 0, 0) && !setBodyCentre(-3, 0, 0), "look range");
    CHECK(!setWingsCentre(9, 0, kMaxCentrePx + 1) && !setWingsCentre(9, 0, -kMaxCentrePx - 1), "centre range");
    CHECK(shiftX(2073, 2414, 4, kLiftPx) == 0 && shiftX(2073, 2414, -1, kLiftPx) == 0, "direction lookup");
    // a row that asks for a huge shift is ignored
    CHECK(setBodyCentre(7, 1, 200) && setWingsCentre(8, 1, -200), "wide rows");
    CHECK(shiftX(7, 8, 1, kLiftPx) == 0, "over the limit");
    CHECK(setBodyCentre(7, 1, 40) && setWingsCentre(8, 1, -20), "rows");
    CHECK(shiftX(7, 8, 1, kLiftPx) == 40 + 20 - 6, "inside the limit");

    // a later set replaces the row; clear empties both tables
    CHECK(setBodyCentre(7, 1, 0) && shiftX(7, 8, 1, kLiftPx) == 0 + 20 - 6, "replaced");
    clearCentres();
    CHECK(shiftX(7, 8, 1, kLiftPx) == 0 && shiftX(2073, 2414, 2, kLiftPx) == 0, "cleared");

    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("chaoswingfit_test: all checks passed\n");
    return 0;
}
