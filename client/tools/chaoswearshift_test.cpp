// Unit test of a head piece's or cape's picture moved per direction onto the body (base patch 0219, client/BASE.md "0219",
// O785).
//   d=$(mktemp -d); cut chaospiece.h out of base patch 0209, chaospieceshift.h out of 0217, chaospiecesides.h out of 0218 and
//   chaoswearshift.h out of 0219 into $d (CLAUDE.md line), then g++ -std=c++17 -I $d client/tools/chaoswearshift_test.cpp -o t
// Checks: placed() adds the look's move of the drawn direction to the anchor place of 0209 (Antelope Horns 3590 and Mermaid
// Scale Train 3697 of pack_wear_layer_shift.csv, pair 90); south and a direction without a row stay; a diagonal or a bad
// direction, a look of 0 and a look without a row draw at the anchor place; a head look's row and a wing look's row live side
// by side in the one table of 0217 without touching each other; the rows come in through setShifts of 0218 or setShift of 0217
// alike; a bad text sets nothing; clearShifts puts every piece back on its anchor place.
#include "chaospiece.h"
#include "chaospieceshift.h"
#include "chaospiecesides.h"
#include "chaoswearshift.h"
#include <cstdio>

using chaos::piece::Point2;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

static bool is(const Point2& p, int x, int y)
{
    return p.x == x && p.y == y;
}

int main()
{
    chaos::piece::clear();
    chaos::piece::clearShifts();
    // Antelope Horns 3590: 2 x 2 tiles, anchor tile 1, 1; the wearer's tile at -6, -6 (a class body's displacement 6)
    CHECK(chaos::piece::setPiece(3590, 1, 1), "the head piece");
    chaos::piece::Piece horns;
    CHECK(chaos::piece::piece(3590, horns), "its anchor tile");
    const Point2 at = chaos::piece::place(-6, -6, 2, 2, horns);
    CHECK(is(at, -6, -6), "anchor place %d %d", at.x, at.y);
    CHECK(is(chaos::wear::placed(at, 3590, 0), -6, -6), "no row yet: the anchor place");
    // its rows (north 1 -3, east 3 -5, west 0 -2) handed in at once (0218)
    CHECK(chaos::piece::setShifts(3590, "1 -3 3 -5 0 0 0 -2"), "the head's four moves");
    Point2 p = chaos::wear::placed(at, 3590, 0);
    CHECK(is(p, -5, -9), "north 1 right, 3 up: %d %d", p.x, p.y);
    p = chaos::wear::placed(at, 3590, 1);
    CHECK(is(p, -3, -11), "east 3 right, 5 up: %d %d", p.x, p.y);
    CHECK(is(chaos::wear::placed(at, 3590, 2), -6, -6), "south stays");
    CHECK(is(chaos::wear::placed(at, 3590, 3), -6, -8), "west 2 up");
    for (int dir : { -1, 4, 5, 7, 99 })
        CHECK(is(chaos::wear::placed(at, 3590, dir), -6, -6), "direction %d: no move", dir);
    CHECK(is(chaos::wear::placed(at, 0, 0), -6, -6) && is(chaos::wear::placed(at, -3590, 0), -6, -6), "no look: no move");
    CHECK(is(chaos::wear::placed(at, 3591, 0), -6, -6), "a look without a row: no move");

    // a cape's rows one by one (0217): Mermaid Scale Train 3697 facing north 3 right, 20 up; east and west 9 and 5 up only
    CHECK(chaos::piece::setShift(3697, 0, 3, -20) && chaos::piece::setShift(3697, 1, 0, -9) && chaos::piece::setShift(3697, 3, 0, -5),
          "the cape's rows");
    CHECK(is(chaos::wear::placed(Point2{ -38, -70 }, 3697, 0), -35, -90), "cape north");
    CHECK(is(chaos::wear::placed(Point2{ -38, -70 }, 3697, 1), -38, -79), "cape east, height only");
    CHECK(is(chaos::wear::placed(Point2{ -38, -70 }, 3697, 3), -38, -75), "cape west, height only");

    // a wing look's row beside them (O779 / O784): each look keeps its own
    CHECK(chaos::piece::setShifts(2442, "2 -9 0 -6 0 0 0 -3"), "a wing's moves");
    CHECK(is(chaos::piece::shift(2442, 0), 2, -9) && is(chaos::wear::placed(at, 3590, 0), -5, -9), "a wing and a head side by side");
    CHECK(chaos::piece::shiftsText(3590) == "1 -3 3 -5 0 0 0 -2", "the head reads back: %s", chaos::piece::shiftsText(3590).c_str());

    // a bad text sets nothing and keeps the row; a move over 24 px is refused
    CHECK(!chaos::piece::setShifts(3590, "1 -3 3"), "too few numbers");
    CHECK(!chaos::piece::setShifts(3590, "0 -25 0 0 0 0 0 0"), "over 24 px");
    CHECK(is(chaos::wear::placed(at, 3590, 1), -3, -11), "the row kept");
    // eight zeros remove a look's row
    CHECK(chaos::piece::setShifts(3590, "0 0 0 0 0 0 0 0") && is(chaos::wear::placed(at, 3590, 1), -6, -6), "eight zeros: no move");

    chaos::piece::clearShifts();
    CHECK(is(chaos::wear::placed(Point2{ -38, -70 }, 3697, 0), -38, -70) && is(chaos::piece::shift(2442, 0), 0, 0), "cleared: no moves");

    if (failures) {
        std::printf("%d failures\n", failures);
        return 1;
    }
    std::printf("chaoswearshift_test: all checks passed\n");
    return 0;
}
