// Unit test of a pack wing's picture moved per direction (base patch 0217, client/BASE.md "0217", O779).
//   d=$(mktemp -d); cut chaospiece.h out of base patch 0209 and chaospieceshift.h out of 0217 into $d (CLAUDE.md line), then
//   g++ -std=c++17 -I $d client/tools/chaospieceshift_test.cpp -o t
// Checks: a row moves only its look facing its direction; the other directions, diagonals and other looks stay at 0, 0; the
// anchor place of 0209 plus the move is where the picture goes; bad rows (look, direction, more than 24 px) set nothing; a later
// row replaces an earlier one; clearShifts empties the table and leaves the anchor tiles and lifts of 0209.
#include "chaospiece.h"
#include "chaospieceshift.h"
#include <cstdio>

using namespace chaos::piece;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    clear();
    clearShifts();
    // Pearl Scallop Wings 2442 (pair 90): 3 x 3 tiles, anchor tile 2, 2; its north view hung 9.2 px low and 2 px left
    CHECK(setPiece(2442, 2, 2), "the piece");
    CHECK(setLift(2442, "-2 -2 -2 -2 -3 -3"), "its lift");
    CHECK(setShift(2442, 0, 2, -9), "the north move");
    const Point2 n = shift(2442, 0);
    CHECK(n.x == 2 && n.y == -9, "north: 2 right, 9 up, got %d,%d", n.x, n.y);
    for (int dir = 1; dir < 4; ++dir) {
        const Point2 o = shift(2442, dir);
        CHECK(o.x == 0 && o.y == 0, "direction %d does not move", dir);
    }
    for (int dir : { -1, 4, 5, 7, 99 }) {
        const Point2 o = shift(2442, dir);
        CHECK(o.x == 0 && o.y == 0, "no move outside north..west (%d)", dir);
    }
    const Point2 other = shift(2390, 0);
    CHECK(other.x == 0 && other.y == 0, "a look without a row does not move");

    // where ThingType::draw gets the picture: the anchor place of 0209 plus the move (the body's own place untouched)
    Piece p;
    CHECK(piece(2442, p), "the anchor tile is still there");
    const Point2 at = place(-8, -8, 3, 3, p);
    CHECK(at.x == -8 && at.y == -8, "anchor 2, 2 of a 3 x 3 piece: the wearer's tile, got %d,%d", at.x, at.y);
    const Point2 north = Point2{ at.x + n.x, at.y + n.y };
    CHECK(north.x == -6 && north.y == -17, "facing north the picture goes 2 right and 9 up, got %d,%d", north.x, north.y);
    const Point2 body = lift(2442, 2);
    CHECK(body.x == -3 && body.y == -3, "the body's lift is the row's, not moved");

    // bad rows set nothing
    CHECK(!setShift(0, 0, 1, 1) && !setShift(-5, 0, 1, 1), "a look must be positive");
    CHECK(!setShift(2390, -1, 1, 1) && !setShift(2390, 4, 1, 1), "north..west only");
    CHECK(!setShift(2390, 0, 25, 0) && !setShift(2390, 0, 0, -25) && !setShift(2390, 0, -25, 0), "at most 24 px");
    CHECK(shift(2390, 0).x == 0 && shift(2390, 0).y == 0, "a refused row left nothing");
    CHECK(setShift(2390, 0, -24, 24), "24 px is allowed");

    // a later row replaces the earlier one; another direction of the same look is kept
    CHECK(setShift(2442, 0, 3, -12) && setShift(2442, 3, -1, 0), "two rows of a look");
    CHECK(shift(2442, 0).x == 3 && shift(2442, 0).y == -12, "the later row wins");
    CHECK(shift(2442, 3).x == -1 && shift(2442, 0).y == -12, "west kept beside north");

    // clear: no move; the tables of 0209 stay (wingfit.lua clears them on its own)
    clearShifts();
    CHECK(shift(2442, 0).x == 0 && shift(2442, 0).y == 0 && shift(2442, 3).x == 0, "cleared");
    CHECK(piece(2442, p) && lift(2442, 2).y == -3, "the anchor tile and lift of 0209 stay");
    clear();

    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("chaospieceshift_test OK\n");
    return 0;
}
