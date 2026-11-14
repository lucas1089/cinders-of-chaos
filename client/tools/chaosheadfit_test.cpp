// Unit test of the head accessory placing maths (base patch 0200, client/BASE.md "0200").
//   g++ -std=c++17 -I DIR client/tools/chaosheadfit_test.cpp -o t   (DIR holds chaosheadfit.h, extracted from the patch)
// Checks: the shift is head(body) - head(reference look) per direction, so a piece keeps its place on look 128's head and
// follows the wearer's head; no reference, no row, an aura outside the piece range, a bad direction and a bad row give no
// shift; the limits of a row; a later set replaces a row; clearing the tables.
#include "chaosheadfit.h"
#include <cstdio>

using namespace chaos::headfit;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    clearHeads();
    CHECK(shift(2073, 2486, 2).x == 0 && shift(2073, 2486, 2).y == 0, "no tables: no shift");

    CHECK(setBodyHead(2073, 2, -3, -9), "body row");
    CHECK(setHeadRef(2, -1, -5), "reference");
    CHECK(shift(2073, 2486, 2).x == 0 && shift(2073, 2486, 2).y == 0, "no piece range yet: no shift");
    CHECK(!setHeadPieces(0, 5) && !setHeadPieces(10, 9), "bad piece range");
    CHECK(setHeadPieces(2477, 2568), "piece range");

    // a class head 2 px left of and 4 px above the reference head: the piece moves 2 left and 4 up
    Point2 s = shift(2073, 2486, 2);
    CHECK(s.x == -2 && s.y == -4, "shift %d, %d", s.x, s.y);
    // where the piece lands: its place on the reference head plus the shift is the same offset from the wearer's head
    {
        const int pieceOnRef = 6;                       // the piece's centre, px right of the reference head (authored on look 128)
        const int landed = -1 + pieceOnRef + s.x;       // the reference head x, the offset, the shift
        CHECK(landed - (-3) == pieceOnRef, "the offset to the wearer's head is kept: %d", landed + 3);
    }
    // the reference look itself: no shift
    CHECK(setBodyHead(128, 2, -1, -5), "reference body row");
    CHECK(shift(128, 2486, 2).x == 0 && shift(128, 2486, 2).y == 0, "look 128 needs none");

    // outside the range: the first and last piece in, a wings look, a cape and 0 out
    CHECK(shift(2073, 2477, 2).x == -2 && shift(2073, 2568, 2).x == -2, "range ends are in");
    CHECK(shift(2073, 2476, 2).x == 0 && shift(2073, 2569, 2).x == 0 && shift(2073, 0, 2).x == 0, "outside the range");
    CHECK(isHeadPiece(2500) && !isHeadPiece(2414), "isHeadPiece");

    // another direction has no row / no reference yet
    CHECK(shift(2073, 2486, 0).x == 0 && shift(2073, 2486, 0).y == 0, "north has no row");
    CHECK(setBodyHead(2073, 0, 4, 1), "north row");
    CHECK(shift(2073, 2486, 0).x == 0, "north without a reference");
    CHECK(setHeadRef(0, 0, -4), "north reference");
    s = shift(2073, 2486, 0);
    CHECK(s.x == 4 && s.y == 5, "north shift %d, %d", s.x, s.y);
    CHECK(shift(2073, 2486, 2).x == -2, "south untouched by north rows");

    // a body that is not in the table
    CHECK(shift(9999, 2486, 2).x == 0 && shift(9999, 2486, 2).y == 0, "unknown look");

    // bad directions and rows are refused
    CHECK(!setBodyHead(5, 4, 0, 0) && !setBodyHead(5, -1, 0, 0), "direction range");
    CHECK(!setBodyHead(0, 0, 0, 0) && !setBodyHead(-3, 0, 0, 0), "look range");
    CHECK(!setBodyHead(5, 0, kMaxCentrePx + 1, 0) && !setBodyHead(5, 0, 0, -kMaxCentrePx - 1), "centre range");
    CHECK(!setHeadRef(4, 0, 0) && !setHeadRef(1, kMaxCentrePx + 1, 0), "reference range");
    CHECK(shift(2073, 2486, 4).x == 0 && shift(2073, 2486, -1).x == 0, "direction lookup");

    // a row that asks for a huge shift is ignored (x or y)
    CHECK(setBodyHead(7, 2, 60, -5) && shift(7, 2486, 2).x == 0 && shift(7, 2486, 2).y == 0, "x over the limit");
    CHECK(setBodyHead(7, 2, -1, 40) && shift(7, 2486, 2).x == 0 && shift(7, 2486, 2).y == 0, "y over the limit");
    CHECK(setBodyHead(7, 2, 30, -5 - 20) && shift(7, 2486, 2).x == 31 && shift(7, 2486, 2).y == -20, "inside the limit");

    // a half set row (x only is impossible through the setters, but an unset slot gives no shift)
    {
        Tables& t = tables();
        t.bodies[8] = emptyRow();
        t.bodies[8][4] = 3;
        CHECK(shift(8, 2486, 2).x == 0 && shift(8, 2486, 2).y == 0, "half row");
    }

    // a later set replaces the row; clear empties everything
    CHECK(setBodyHead(7, 2, -1, -5) && shift(7, 2486, 2).x == 0 && shift(7, 2486, 2).y == 0, "replaced");
    clearHeads();
    CHECK(shift(2073, 2486, 2).x == 0 && shift(2073, 2486, 0).x == 0 && !isHeadPiece(2486), "cleared");

    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("chaosheadfit_test: all checks passed\n");
    return 0;
}
