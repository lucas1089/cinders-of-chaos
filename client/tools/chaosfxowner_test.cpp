// Unit test of the effect owner and opacity maths (base patch 0202, client/BASE.md "0202").
//   g++ -std=c++17 -I DIR client/tools/chaosfxowner_test.cpp -o t   (DIR holds chaosfxowner.h, extracted from the patch)
// Checks: the alpha slot of an effect (a warning, a marked one, an unmarked one with and without a server that sends the source),
// the source numbers a script may give, the alpha byte (own alpha times the missile slider, never out of 0..255, junk is 1.0),
// the reading of a mark list (bad kind, far offset, id out of range, a partial group, the cap), the nearest-first walk around a
// mark (the tile itself, then the rings, each tile once, stops at the first one taken) and the set of warning ids.
#include "chaosfxowner.h"
#include <cstdio>
#include <limits>
#include <set>
#include <utility>
#include <vector>

using namespace chaos::fxowner;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    // the numbers are the engine's Otc::MagicEffectSources
    CHECK(kSourceDefault == 0 && kSourceOwn == 1 && kSourceOther == 2 && kSourceMonster == 3 && kSourceBoss == 4, "source numbers");

    // sanitizeSource: only 1..4 come through
    CHECK(sanitizeSource(1) == 1 && sanitizeSource(2) == 2 && sanitizeSource(3) == 3 && sanitizeSource(4) == 4, "1..4 kept");
    CHECK(sanitizeSource(0) == 0 && sanitizeSource(-1) == 0 && sanitizeSource(5) == 0 && sanitizeSource(255) == 0, "others -> not marked");

    // pickSource: warning first, then the mark, then the default of the server kind
    CHECK(pickSource(kSourceDefault, false, false) == kSourceOther, "unmarked, server without source: other");
    CHECK(pickSource(kSourceDefault, true, false) == kSourceDefault, "unmarked, server with source: slot 0 as the stock path");
    CHECK(pickSource(kSourceOwn, false, false) == kSourceOwn, "marked own");
    CHECK(pickSource(kSourceOwn, true, false) == kSourceOwn, "marked own, server with source");
    CHECK(pickSource(kSourceOther, false, false) == kSourceOther, "marked other");
    CHECK(pickSource(kSourceMonster, false, false) == kSourceMonster, "marked monster");
    for (int tagged = 0; tagged <= 4; ++tagged) {
        CHECK(pickSource(tagged, false, true) == kSourceDefault, "a warning ignores the mark %d", tagged);
        CHECK(pickSource(tagged, true, true) == kSourceDefault, "a warning ignores the mark %d (server with source)", tagged);
    }

    // clamp01 and alphaByte
    CHECK(clamp01(0.5f) == 0.5f && clamp01(-1.0f) == 0.0f && clamp01(7.0f) == 1.0f, "clamp01");
    CHECK(clamp01(std::numeric_limits<float>::quiet_NaN()) == 1.0f, "nan -> 1");
    CHECK(clamp01(std::numeric_limits<float>::infinity()) == 1.0f, "inf -> 1");
    CHECK(alphaByte(1.0f) == 255, "full");
    CHECK(alphaByte(0.0f) == 0, "none");
    CHECK(alphaByte(0.4f) == 102, "40%% -> 102, got %d", alphaByte(0.4f));
    CHECK(alphaByte(1.0f, 0.5f) == 127, "missile slider halves: %d", alphaByte(1.0f, 0.5f));
    CHECK(alphaByte(0.4f, 0.5f) == 51, "40%% of 50%%: %d", alphaByte(0.4f, 0.5f));
    CHECK(alphaByte(0.5f, 0.0f) == 0 && alphaByte(0.0f, 1.0f) == 0, "a zero on either side hides");
    CHECK(alphaByte(9.0f, 9.0f) == 255 && alphaByte(-3.0f) == 0, "never out of range");
    for (int i = 0; i <= 100; ++i) {
        const int b = alphaByte(i / 100.0f);
        CHECK(b >= 0 && b <= 255, "range at %d", i);
        if (i > 0)
            CHECK(b >= alphaByte((i - 1) / 100.0f), "monotonic at %d", i);
    }

    // decode
    std::vector<Mark> marks;
    CHECK(!decode({}, marks) && marks.empty(), "empty list");
    CHECK(!decode({0, 1, 2}, marks) && marks.empty(), "a partial group only");
    CHECK(decode({0, 1, -2, 3000}, marks) && marks.size() == 1, "one effect mark");
    CHECK(marks[0].kind == kKindEffect && marks[0].dx == 1 && marks[0].dy == -2 && marks[0].id == 3000, "fields in order");
    CHECK(decode({1, 0, 0, 12, 0, 5, 5, 40, 7}, marks) && marks.size() == 2, "the partial group at the end is dropped");
    CHECK(marks[0].kind == kKindMissile && marks[1].id == 40, "missile then effect");
    CHECK(decode({2, 0, 0, 5, 0, 0, 0, 5}, marks) && marks.size() == 1 && marks[0].kind == kKindEffect, "a bad kind is skipped");
    CHECK(decode({0, 128, 0, 5, 0, 0, -128, 5, 0, 127, -127, 5}, marks) && marks.size() == 1 && marks[0].dx == 127, "far offsets are skipped");
    CHECK(!decode({0, 0, 0, 0}, marks), "id 0 is no effect");
    CHECK(!decode({0, 0, 0, -4}, marks), "negative id");
    CHECK(!decode({0, 0, 0, 65536}, marks), "id over 16 bit");
    CHECK(decode({0, 0, 0, 65535}, marks) && marks.size() == 1, "id 65535 is fine");
    {
        std::vector<int> big;
        for (int i = 0; i < 1000; ++i) {
            big.push_back(0);
            big.push_back(i % 10);
            big.push_back(-(i % 10));
            big.push_back(1 + i);
        }
        CHECK(decode(big, marks) && static_cast<int>(marks.size()) == kMaxMarks, "capped at %d marks, got %zu", kMaxMarks, marks.size());
        CHECK(marks.back().id == kMaxMarks, "the first marks are the ones kept");
    }
    // a second call replaces the earlier result
    decode({0, 1, 1, 9}, marks);
    decode({1, 2, 2, 8}, marks);
    CHECK(marks.size() == 1 && marks[0].id == 8, "decode clears its output");

    // findNearest: the tile itself first, then the rings, each tile once
    {
        std::vector<std::pair<int, int>> seen;
        const bool took = findNearest(kMatchRadius, [&](int dx, int dy) { seen.push_back({dx, dy}); return false; });
        CHECK(!took, "nothing taken");
        const int side = 2 * kMatchRadius + 1;
        CHECK(static_cast<int>(seen.size()) == side * side, "every tile of the box once: %zu", seen.size());
        CHECK(seen[0].first == 0 && seen[0].second == 0, "the mark's own tile first");
        std::set<std::pair<int, int>> unique(seen.begin(), seen.end());
        CHECK(unique.size() == seen.size(), "no tile twice");
        int last = 0;
        bool ordered = true;
        for (const auto& s : seen) {
            const int d = distance(s.first, s.second);
            if (d < last)
                ordered = false;
            last = d;
            CHECK(d <= kMatchRadius, "inside the radius");
        }
        CHECK(ordered, "nearest rings first");
        CHECK(seen[1].first == -1 && seen[1].second == -1, "ring 1 starts top left");
        CHECK(seen[8].first == 1 && seen[8].second == 1, "ring 1 ends bottom right");
    }
    {
        int calls = 0;
        const bool took = findNearest(kMatchRadius, [&](int dx, int dy) { ++calls; return dx == 0 && dy == 0; });
        CHECK(took && calls == 1, "a hit on the own tile stops the walk at once");
    }
    {
        int calls = 0;
        int hitDx = 99, hitDy = 99;
        const bool took = findNearest(kMatchRadius, [&](int dx, int dy) {
            ++calls;
            if (dx == 2 && dy == -1) {
                hitDx = dx;
                hitDy = dy;
                return true;
            }
            return false;
        });
        CHECK(took && hitDx == 2 && hitDy == -1, "a tile two away is found");
        CHECK(calls == 9 + 5 + 2, "9 tiles of rings 0 and 1, the 5 of the top row of ring 2, then 2 (calls %d)", calls);
    }
    CHECK(!findNearest(-1, [](int, int) { return true; }), "a negative radius walks nothing");
    {
        int calls = 0;
        findNearest(0, [&](int, int) { ++calls; return false; });
        CHECK(calls == 1, "radius 0 is the tile alone");
    }
    CHECK(distance(3, -5) == 5 && distance(-2, 2) == 2 && distance(0, 0) == 0, "chebyshev distance");

    // missileScore: the same id near, another id only on or next to the tile, lower is better
    CHECK(missileScore(true, 0) == 0 && missileScore(true, 2) == 2 && missileScore(true, kMatchRadius) == kMatchRadius, "same id");
    CHECK(missileScore(true, kMatchRadius + 1) == -1, "same id too far");
    CHECK(missileScore(false, 0) == 100 && missileScore(false, 1) == 101, "another id on or next to the tile");
    CHECK(missileScore(false, 2) == -1 && missileScore(false, kMatchRadius) == -1, "another id two away is no match");
    CHECK(missileScore(true, -1) == -1 && missileScore(false, -1) == -1, "a negative distance fits nothing");
    CHECK(missileScore(true, kMatchRadius) < missileScore(false, 0), "the same id wins over another id on the tile");

    // ExemptIds
    {
        ExemptIds ids;
        CHECK(!ids.has(745) && ids.size() == 0, "empty");
        ids.set(745, true);
        ids.set(635, true);
        ids.set(745, true);
        CHECK(ids.has(745) && ids.has(635) && !ids.has(636) && ids.size() == 2, "set twice counts once");
        ids.set(745, false);
        CHECK(!ids.has(745) && ids.has(635), "one removed");
        ids.set(9999, false);
        CHECK(ids.size() == 1, "removing an unknown id does nothing");
        ids.clear();
        CHECK(!ids.has(635) && ids.size() == 0, "cleared");
    }

    if (failures == 0)
        std::printf("chaosfxowner_test: all ok\n");
    return failures == 0 ? 0 : 1;
}
