// Unit test of the purchased pieces' place and the wings' lift (base patch 0209, client/BASE.md "0209").
//   g++ -std=c++17 -I DIR client/tools/chaospiece_test.cpp -o t   (DIR holds chaospiece.h, extracted from the patch)
// Checks: the point handed to ThingType::draw puts the anchor tile on the wearer's tile for the frame sizes and anchors of the
// pack (4x4 at 2,2; 5x4 at 2,2 and 3,2; 3x3 at 1,1; 2x2 at 0,0; 3x2 at 1,0), against the engine's own rule (top left = dest -
// (size - 1) tiles); the lift table (parse, bounds, bad texts, wrap, a look without a row), the frame of a loop, clear.
#include "chaospiece.h"
#include <cstdio>

using namespace chaos::piece;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

// ThingType::draw: a look of w x h tiles without displacement has its picture's top left at dest - (w - 1, h - 1) tiles
static Point2 topLeft(const Point2& dest, int w, int h) { return Point2{ dest.x - (w - 1) * kTile, dest.y - (h - 1) * kTile }; }

int main()
{
    // the wearer's tile: the creature's place minus a body displacement of 8, 8 (the common one)
    const int tileX = -8, tileY = -8;
    const int sizes[][4] = { { 4, 4, 2, 2 }, { 5, 4, 2, 2 }, { 5, 4, 3, 2 }, { 3, 3, 1, 1 }, { 2, 2, 0, 0 }, { 3, 2, 1, 0 }, { 2, 3, 0, 1 } };
    for (const auto& s : sizes) {
        const Piece p{ s[2], s[3] };
        const Point2 at = place(tileX, tileY, s[0], s[1], p);
        const Point2 tl = topLeft(at, s[0], s[1]);
        CHECK(tl.x == tileX - s[2] * kTile && tl.y == tileY - s[3] * kTile, "%dx%d anchor %d,%d: top left %d,%d", s[0], s[1], s[2], s[3], tl.x, tl.y);
        // the anchor tile covers the wearer's tile
        CHECK(tl.x + s[2] * kTile == tileX && tl.y + s[3] * kTile == tileY, "anchor tile on the wearer's tile");
    }
    // an anchor outside the picture: as if it were the bottom right tile (the stock place)
    const Point2 bad = place(0, 0, 2, 2, Piece{ 5, 7 });
    CHECK(bad.x == 0 && bad.y == 0, "anchor outside: bottom right tile, got %d,%d", bad.x, bad.y);

    // pieces
    clear();
    CHECK(setPiece(3600, 1, 1), "a piece row");
    CHECK(!setPiece(0, 1, 1) && !setPiece(3601, -1, 0) && !setPiece(3601, 9, 0), "bad rows refused");
    Piece got;
    CHECK(piece(3600, got) && got.ax == 1 && got.ay == 1, "the row reads back");
    CHECK(!piece(3601, got), "no row");

    // lifts: the first pack wing's table
    CHECK(setLift(2385, "-1 -1 -1 -1 -2 -2 -3 -3"), "a lift row");
    CHECK(lift(2385, 0).x == -1 && lift(2385, 0).y == -1, "frame 0");
    CHECK(lift(2385, 3).x == -3 && lift(2385, 3).y == -3, "frame 3");
    CHECK(lift(2385, 5).x == -1 && lift(2385, 5).y == -1, "a longer animation wraps");
    CHECK(lift(9999, 2).x == 0 && lift(9999, 2).y == 0, "no row: no lift");
    CHECK(lift(2385, -1).x == 0, "a bad frame: no lift");
    CHECK(!setLift(2386, "-1"), "an odd count is refused");
    CHECK(!setLift(2386, "-1 x"), "a word is refused");
    CHECK(!setLift(2386, ""), "an empty row is refused");
    CHECK(!setLift(2386, "-40 0"), "a lift over the bound is refused");
    CHECK(lift(2386, 0).x == 0, "a refused row sets nothing");
    CHECK(setLift(2387, "  -2   -1  "), "spaces are fine");
    CHECK(lift(2387, 0).x == -2 && lift(2387, 0).y == -1, "spaces read");

    // the frame of a loop at 83 ms
    CHECK(phase(0, 16) == 0 && phase(82, 16) == 0 && phase(83, 16) == 1, "frame edges");
    CHECK(phase(83 * 16, 16) == 0 && phase(83 * 17, 16) == 1, "the loop closes");
    CHECK(phase(1000, 1) == 0 && phase(1000, 0) == 0 && phase(-5, 16) == 0, "one frame, none, a bad clock");
    CHECK(phase(1000, 20, 50) == 0 && phase(1050, 20, 50) == 1, "another frame time");

    clear();
    CHECK(!piece(3600, got) && lift(2385, 0).x == 0, "clear empties both tables");

    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("chaospiece_test OK\n");
    return 0;
}
