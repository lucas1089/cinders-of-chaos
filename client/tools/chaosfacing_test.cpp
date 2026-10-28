// Tests of src/client/chaosfacing.h (base patch 0160): the column a creature's body is drawn from.
// Build (CI): the header is cut out of the patch, then
//   g++ -std=c++17 -Wall -Wextra -I DIR client/tools/chaosfacing_test.cpp && ./a.out
#include "chaosfacing.h"

#include <cstdio>
#include <initializer_list>

using chaos::facing::bodyColumn;

static int failures = 0;

static void check(bool ok, const char* what)
{
    if (!ok) {
        ++failures;
        std::printf("FAIL %s\n", what);
    }
}

// Otc::Direction
enum { North, East, South, West, NorthEast, SouthEast, SouthWest, NorthWest };

// Outfit::draw's direction correction (unchanged): a diagonal is drawn east or west
static int fold(int d)
{
    if (d == NorthEast || d == SouthEast)
        return East;
    if (d == NorthWest || d == SouthWest)
        return West;
    return d;
}

int main()
{
    // a look with 4 columns draws what the stock client drew, for all 8 facings, riding or not
    for (int d = North; d <= NorthWest; ++d) {
        check(bodyColumn(d, fold(d), 4, false) == fold(d), "4 columns: the folded direction");
        check(bodyColumn(d, fold(d), 4, true) == fold(d), "4 columns riding: the folded direction");
        check(bodyColumn(d, fold(d), 1, false) == fold(d), "1 column: the folded direction");
    }

    // a look with 8 columns: straight facings keep their column, diagonals their own (4-7, Otc::Direction order)
    check(bodyColumn(North, North, 8, false) == North, "8 columns: north");
    check(bodyColumn(East, East, 8, false) == East, "8 columns: east");
    check(bodyColumn(South, South, 8, false) == South, "8 columns: south");
    check(bodyColumn(West, West, 8, false) == West, "8 columns: west");
    check(bodyColumn(NorthEast, East, 8, false) == 4, "8 columns: north-east is column 4");
    check(bodyColumn(SouthEast, East, 8, false) == 5, "8 columns: south-east is column 5");
    check(bodyColumn(SouthWest, West, 8, false) == 6, "8 columns: south-west is column 6");
    check(bodyColumn(NorthWest, West, 8, false) == 7, "8 columns: north-west is column 7");

    // a rider stays four-way (mounts, wings and auras have 4 columns)
    for (int d = NorthEast; d <= NorthWest; ++d)
        check(bodyColumn(d, fold(d), 8, true) == fold(d), "8 columns riding: the folded direction");

    // every column the function gives exists in the look
    for (int cols : {1, 4, 8, 12}) {
        for (int d = North; d <= NorthWest; ++d) {
            for (int riding = 0; riding < 2; ++riding) {
                const int c = bodyColumn(d, fold(d), cols, riding != 0);
                check(c >= 0 && (c < cols || (cols < 4 && c == fold(d))), "the column is inside the look");
            }
        }
    }

    // anything outside 0-7 (Otc::InvalidDirection) is passed through as the stock client did
    check(bodyColumn(8, 8, 8, false) == 8, "an invalid direction is not a diagonal");
    check(bodyColumn(-1, -1, 8, false) == -1, "a negative direction is not a diagonal");

    std::printf("chaosfacing_test: %d failures\n", failures);
    return failures == 0 ? 0 : 1;
}
