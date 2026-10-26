// Unit test of the creature shadow placement maths (base patch 0155, client/BASE.md "0155").
//   g++ -std=c++17 -I DIR client/tools/chaosshadow_test.cpp -o t   (DIR holds chaosshadow.h, extracted from the patch)
// Checks: the shadow is centred on the drawn body and sits at its lowest row (a 1x1 look with displacement 8 and a 2x2 look,
// against the old tile-centred formula); the width by tiles; scale and jump; the placement worked out without pieces equals
// the frame ThingType::draw makes.
#include "chaosshadow.h"
#include <cstdio>

using namespace chaos::shadow;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

// the middle of the ellipse
static int midX(const Ellipse& e) { return e.x + e.w / 2; }
static int midY(const Ellipse& e) { return e.y + e.h / 2; }

// the frame ThingType::draw makes for an untrimmed look: dest - displacement - (tiles - 1) * s, tiles * s wide and high
static void frameOf(int destX, int destY, int disp, int tiles, int s, int& left, int& right, int& bottom)
{
    left = destX - disp - (tiles - 1) * s;
    right = left + tiles * s;
    bottom = destY - disp - (tiles - 1) * s + tiles * s;
}

int main()
{
    const int s = 32;
    const float unit = 1.0f;
    const int destX = 320, destY = 192;  // tile corner

    // old formula: the middle of the tile, 5 px over its bottom
    const int oldX = destX + s / 2, oldY = destY + s - 5;

    // 1x1 look, displacement 8: the body is 8 px left and up of the tile
    {
        int l, r, b;
        frameOf(destX, destY, 8, 1, s, l, r, b);
        const Ellipse e = place((l + r) / 2.0f, static_cast<float>(b), 1, unit, 1.0f, 0, 0);
        CHECK(midX(e) == oldX - 8, "x %d", midX(e));
        CHECK(midY(e) == oldY - 8, "y %d", midY(e));
        CHECK(e.w == 22, "w %d", e.w);
        CHECK(e.h == 9, "h %d", e.h);
    }
    // 2x2 look, displacement 8: the body starts one tile further up-left, so its middle is 24 px left, the feet 8 px up
    {
        int l, r, b;
        frameOf(destX, destY, 8, 2, s, l, r, b);
        const Ellipse e = place((l + r) / 2.0f, static_cast<float>(b), 2, unit, 1.0f, 0, 0);
        CHECK(midX(e) == oldX - 24, "x %d", midX(e));
        CHECK(midY(e) == oldY - 8, "y %d", midY(e));
        CHECK(e.w == 48, "w %d", e.w);
        CHECK(e.h == 20, "h %d", e.h);
    }
    // the pieces' middle wins over the tile: a trimmed body that is off the frame middle is followed
    {
        const Ellipse e = place(500.0f, 400.0f, 1, unit, 1.0f, 0, 0);
        CHECK(midX(e) == 500 && midY(e) == 395, "followed %d %d", midX(e), midY(e));
    }

    // width by tiles, capped at 4, at least 1
    CHECK(place(0, 0, 0, unit, 1.0f, 0, 0).w == 22, "0 tiles");
    CHECK(place(0, 0, 1, unit, 1.0f, 0, 0).w == 22, "1 tile");
    CHECK(place(0, 0, 3, unit, 1.0f, 0, 0).w == 74, "3 tiles");
    CHECK(place(0, 0, 4, unit, 1.0f, 0, 0).w == 100, "4 tiles");
    CHECK(place(0, 0, 9, unit, 1.0f, 0, 0).w == 100, "capped");
    // a larger sprite size scales the shadow and the lift
    {
        const Ellipse e = place(100.0f, 200.0f, 1, 2.0f, 1.0f, 0, 0);
        CHECK(e.w == 44 && midY(e) == 190, "unit 2: %d %d", e.w, midY(e));
    }

    // drawn scaled around a point: the shadow is scaled around it too (the point itself stays)
    {
        const Ellipse a = place(100.0f, 200.0f, 1, unit, 1.5f, 100.0f, 200.0f);
        CHECK(midX(a) == 100 && midY(a) == 192, "scale on the centre: %d %d", midX(a), midY(a));  // the lift 5 grows to 7.5 -> 192.5 -> 192
        CHECK(a.w == 33, "scaled width %d", a.w);
        const Ellipse b = place(132.0f, 200.0f, 1, unit, 2.0f, 100.0f, 200.0f);
        CHECK(midX(b) == 164, "scale away from the centre: %d", midX(b));
    }

    // without pieces: the same middle and lower edge as the frame, for 1x1 and 2x2 looks and a walk offset
    for (int tiles = 1; tiles <= 3; ++tiles) {
        for (int disp : { 0, 8 }) {
            int l, r, b;
            frameOf(destX + 5, destY - 3, disp, tiles, s, l, r, b);
            float cx, by;
            bodyFromPlacement(static_cast<float>(destX + 5), static_cast<float>(destY - 3), static_cast<float>(disp),
                              static_cast<float>(disp), tiles, s, cx, by);
            CHECK(cx == (l + r) / 2.0f && by == static_cast<float>(b), "fallback %d tiles disp %d: %f %f", tiles, disp, cx, by);
        }
    }

    if (failures == 0)
        std::printf("chaosshadow_test: ok\n");
    return failures == 0 ? 0 : 1;
}
