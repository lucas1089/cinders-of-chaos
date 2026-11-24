// Unit test of a pack wing's lift while its wearer walks (base patch 0211, client/BASE.md "0211", O762).
//   d=$(mktemp -d); cut chaospiece.h out of base patch 0209 and chaospiecewalk.h out of 0211 into $d (CLAUDE.md line), then
//   g++ -std=c++17 -I $d client/tools/chaospiecewalk_test.cpp -o t
// Checks: standing, the body takes the lift of the frame (the float of 0209, unchanged); walking, it holds the row's mean in
// every frame, so the body's place moves only with the walk; the mean rounds to the nearest pixel; a look without a row (the
// Float option off) lifts nothing standing or walking; the walk lift lies within the row's range.
#include "chaospiece.h"
#include "chaospiecewalk.h"
#include <cstdio>

using namespace chaos::piece;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    clear();
    // a row like wear_pieces.lua's (x = y, the oblique height): 1 to 3 px up and left
    CHECK(setLift(2385, "-1 -1 -1 -1 -2 -2 -2 -2 -3 -3 -3 -3 -2 -2 -1 -1"), "a lift row");
    // standing: the frame's lift, as 0209
    for (int f = 0; f < 16; ++f) {
        const Point2 a = drawnLift(2385, f, false), b = lift(2385, f);
        CHECK(a.x == b.x && a.y == b.y, "standing, frame %d: the float", f);
    }
    // walking: one steady lift in every frame (mean of -1 -1 -2 -2 -3 -3 -2 -1 = -15 / 8 = -1.875 -> -2)
    const Point2 w0 = drawnLift(2385, 0, true);
    CHECK(w0.x == -2 && w0.y == -2, "walking: the row's mean, got %d,%d", w0.x, w0.y);
    for (int f = 0; f < 64; ++f) {
        const Point2 w = drawnLift(2385, f, true);
        CHECK(w.x == w0.x && w.y == w0.y, "walking, frame %d: no move but the walk's", f);
    }
    // the body's place over a step: the walk offset plus a constant, so each frame moves it by the walk alone
    int last = 0;
    for (int px = 0; px <= 32; ++px) {
        const int drawn = px + drawnLift(2385, px % 16, true).x;
        if (px > 0)
            CHECK(drawn - last == 1, "walking east: one pixel of walk is one pixel on screen (px %d)", px);
        last = drawn;
    }
    // the steady lift lies within the row
    CHECK(w0.y >= -3 && w0.y <= -1, "inside the row's range");
    // rounding: half away from zero, both signs
    CHECK(roundedMean(-3, 2) == -2 && roundedMean(3, 2) == 2 && roundedMean(-1, 3) == 0 && roundedMean(5, 3) == 2, "rounding");
    CHECK(roundedMean(7, 0) == 0, "no values");
    // a look without a row (the Float option off, or a drawn wing): nothing, walking or not
    for (int f = 0; f < 8; ++f) {
        const Point2 s = drawnLift(3555, f, false), w = drawnLift(3555, f, true);
        CHECK(s.x == 0 && s.y == 0 && w.x == 0 && w.y == 0, "no row: no lift (frame %d)", f);
    }
    clear();
    CHECK(steadyLift(2385).x == 0 && steadyLift(2385).y == 0, "clear: no steady lift either");

    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("chaospiecewalk_test OK\n");
    return 0;
}
