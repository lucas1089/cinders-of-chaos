// Unit test of the head and cape layer's table and order (base patch 0210, client/BASE.md "0210").
//   g++ -std=c++17 -I DIR client/tools/chaoswear_test.cpp -o t   (DIR holds chaoswear.h, extracted from the patch)
// Checks: names in any case find the same row, both 0 removes it, bad looks and empty names are refused, the cap on rows,
// clear; the draw order: the cape's and the head piece's backs before the body, their fronts after it.
#include "chaoswear.h"
#include <cstdio>

using namespace chaos::wear;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    clear();
    CHECK(of("Nobody").head == 0 && of("Nobody").cape == 0, "an empty table");
    CHECK(set("Ash Walker", 3590, 3660), "a row");
    CHECK(of("ash walker").head == 3590 && of("ASH WALKER").cape == 3660, "any case finds it");
    CHECK(set("Ash Walker", 0, 3661) && of("Ash Walker").head == 0 && of("Ash Walker").cape == 3661, "a change");
    CHECK(set("Ash Walker", 0, 0) && tables().byName.empty(), "both 0 removes the row");
    CHECK(!set("", 1, 1), "no name");
    CHECK(!set("X", -1, 0) && !set("X", 0, 70000), "bad looks");
    CHECK(of("").head == 0, "no name reads nothing");

    for (size_t i = 0; i < kMaxNames; ++i)
        set("n" + std::to_string(i), 1, 0);
    CHECK(!set("one more", 1, 0), "the cap on rows");
    CHECK(set("n0", 2, 0), "a known row still changes at the cap");
    clear();
    CHECK(tables().byName.empty(), "clear");

    // the order: steps 0-1 before the body (cape back, head back), 2-3 after it (cape front, head front)
    CHECK(step(0).cape && step(0).yPattern == 0, "cape back first");
    CHECK(!step(1).cape && step(1).yPattern == 0, "head back second");
    CHECK(step(2).cape && step(2).yPattern == 1, "cape front after the body");
    CHECK(!step(3).cape && step(3).yPattern == 1, "head front last");

    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("chaoswear_test OK\n");
    return 0;
}
