// Unit test of a pack wing's four moves handed in at once, the side views included (base patch 0218, client/BASE.md "0218",
// O784).
//   d=$(mktemp -d); cut chaospiece.h out of base patch 0209, chaospieceshift.h out of 0217 and chaospiecesides.h out of 0218
//   into $d (CLAUDE.md line), then g++ -std=c++17 -I $d client/tools/chaospiecesides_test.cpp -o t
// Checks: setShifts puts the four moves of a look in the table Outfit::draw reads (shift(look, dir) of 0217), east and west
// included; the anchor place of 0209 plus the side move is where the picture goes, the body's lift untouched; the text reads
// back; a bad text (too few or too many numbers, a part px, a word, more than 24 px, a bad look) sets nothing and keeps the
// earlier row; a new text replaces the whole row (no stale direction); eight zeros remove it; the one-row call of 0217 still
// works beside it; clearShifts empties both.
#include "chaospiece.h"
#include "chaospieceshift.h"
#include "chaospiecesides.h"
#include <cstdio>
#include <string>

using namespace chaos::piece;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

static bool at(int look, int dir, int x, int y)
{
    const Point2 s = shift(look, dir);
    return s.x == x && s.y == y;
}

int main()
{
    clear();
    clearShifts();
    // Pearl Scallop Wings 2442 (pair 90): 3 x 3 tiles, anchor tile 2, 2; north 9.2 px low and 2 px left, east 6 px low,
    // west 3 px low (the rows of pack_wear_shift.csv: north 2 -9, east 0 -6, west 0 -3)
    CHECK(setPiece(2442, 2, 2), "the piece");
    CHECK(setLift(2442, "-2 -2 -2 -2 -3 -3"), "its lift");
    CHECK(setShifts(2442, "2 -9 0 -6 0 0 0 -3"), "the four moves");
    CHECK(at(2442, 0, 2, -9), "north 2 right, 9 up");
    CHECK(at(2442, 1, 0, -6), "east 6 up, not across");
    CHECK(at(2442, 2, 0, 0), "south stays");
    CHECK(at(2442, 3, 0, -3), "west 3 up, not across");
    CHECK(shiftsText(2442) == "2 -9 0 -6 0 0 0 -3", "reads back, got %s", shiftsText(2442).c_str());
    CHECK(shiftsText(2390) == "0 0 0 0 0 0 0 0", "a look without a row reads eight zeros");

    // where ThingType::draw gets the picture facing east: the anchor place of 0209 plus the move; the body's lift stays
    Piece p;
    CHECK(piece(2442, p), "the anchor tile is still there");
    const Point2 a = place(-8, -8, 3, 3, p);
    const Point2 east = shift(2442, 1);
    CHECK(a.x + east.x == -8 && a.y + east.y == -14, "facing east the picture goes 6 up and stays across, got %d,%d",
          a.x + east.x, a.y + east.y);
    CHECK(lift(2442, 2).x == -3 && lift(2442, 2).y == -3, "the body's lift is the row's, not moved");

    // bad texts set nothing and keep the earlier row
    const char* bad[] = { "", "1 2 3 4 5 6 7", "1 2 3 4 5 6 7 8 9", "1 2 3 4 5 6 7 x", "1 2 3 4 5 6 7 8 x", "1.5 0 0 0 0 0 0 0",
                          "0 0 25 0 0 0 0 0", "0 0 0 0 0 0 0 -25", "a b c d e f g h" };
    for (const char* t : bad)
        CHECK(!setShifts(2442, t), "refused: '%s'", t);
    CHECK(shiftsText(2442) == "2 -9 0 -6 0 0 0 -3", "a refused text left the row, got %s", shiftsText(2442).c_str());
    CHECK(!setShifts(0, "0 -1 0 -1 0 0 0 -1") && !setShifts(-3, "0 -1 0 -1 0 0 0 -1"), "a look must be positive");
    CHECK(setShifts(2390, " -24 24  0 0\t0 0 24 -24 "), "24 px and any blanks are allowed");
    CHECK(at(2390, 0, -24, 24) && at(2390, 3, 24, -24), "the edges kept");

    // a new text replaces the whole row: an old north-only row of 0217 gets its sides, an old side goes when a text drops it
    CHECK(setShift(2400, 0, 3, -11), "a north row of 0217");
    CHECK(setShifts(2400, "3 -11 0 -8 0 0 0 -4"), "the four moves of 0218");
    CHECK(at(2400, 0, 3, -11) && at(2400, 1, 0, -8) && at(2400, 3, 0, -4), "north kept, sides added");
    CHECK(setShifts(2400, "3 -11 0 0 0 0 0 0"), "a text without sides");
    CHECK(at(2400, 1, 0, 0) && at(2400, 3, 0, 0) && at(2400, 0, 3, -11), "no stale side");
    CHECK(setShifts(2400, "0 0 0 0 0 0 0 0") && shifts().count(2400) == 0, "eight zeros remove the row");

    // the one-row call of 0217 still works beside it (an older wingfit.lua), the other directions kept
    CHECK(setShift(2442, 3, 0, -5), "one row of 0217");
    CHECK(at(2442, 3, 0, -5) && at(2442, 1, 0, -6) && at(2442, 0, 2, -9), "west replaced, north and east kept");

    // clear: no move; the tables of 0209 stay
    clearShifts();
    CHECK(shiftsText(2442) == "0 0 0 0 0 0 0 0" && shiftsText(2390) == "0 0 0 0 0 0 0 0", "cleared");
    CHECK(piece(2442, p) && lift(2442, 2).y == -3, "the anchor tile and lift of 0209 stay");
    clear();

    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("chaospiecesides_test OK\n");
    return 0;
}
