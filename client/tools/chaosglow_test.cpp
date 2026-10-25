// Unit test of the glowing effect bookkeeping (base patch 0152, client/BASE.md "69zs").
//   g++ -std=c++17 -I DIR client/tools/chaosglow_test.cpp -o t   (DIR holds chaosglow.h, extracted from the patch)
// Checks: the id set (bounds, clear, junk ids), the one decision wantsGlow (option, collecting, listed), the batch (order kept,
// cap, refusal when full, clear and reuse, move-only items), and the flush count (none for none, two for one or for the cap).
#include "chaosglow.h"
#include <cstdio>
#include <memory>
#include <string>

using namespace chaos::glow;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    // id set: bounds and junk
    IdSet ids;
    CHECK(ids.size() == 0, "starts empty");
    CHECK(!ids.contains(12), "nothing listed");
    ids.add(12);
    ids.add(16);
    ids.add(12);
    CHECK(ids.size() == 2, "a repeat is one: %zu", ids.size());
    CHECK(ids.contains(12) && ids.contains(16) && !ids.contains(13), "contains");
    ids.add(0);
    ids.add(-5);
    ids.add(65536);
    ids.add(1 << 30);
    ids.add(-(1 << 30));
    CHECK(ids.size() == 2, "junk ids are ignored: %zu", ids.size());
    CHECK(!ids.contains(0) && !ids.contains(-5) && !ids.contains(65536) && !ids.contains(1 << 30), "junk is never contained");
    ids.add(65535);
    CHECK(ids.contains(65535), "the last id fits");
    ids.clear();
    CHECK(ids.size() == 0 && !ids.contains(12) && !ids.contains(65535), "clear");

    // the decision
    ids.add(12);
    CHECK(wantsGlow(true, true, ids, 12), "on, collecting, listed");
    CHECK(!wantsGlow(false, true, ids, 12), "option off");
    CHECK(!wantsGlow(true, false, ids, 12), "not collecting (a draw outside a floor stays normal)");
    CHECK(!wantsGlow(true, true, ids, 13), "unlisted effect stays normal");
    CHECK(!wantsGlow(true, true, ids, 0), "id 0");
    CHECK(!wantsGlow(true, true, ids, -1), "negative id");
    IdSet none;
    CHECK(!wantsGlow(true, true, none, 12), "empty list: nothing glows");

    // batch: order kept, cap
    Batch<int> batch;
    CHECK(batch.empty() && batch.size() == 0 && batch.items().empty(), "starts empty");
    for (int i = 0; i < static_cast<int>(kMaxDeferred); ++i)
        CHECK(batch.add(i), "room for %d", i);
    CHECK(batch.size() == kMaxDeferred, "full: %zu", batch.size());
    CHECK(!batch.add(999), "full refuses");
    CHECK(batch.size() == kMaxDeferred, "a refusal adds nothing");
    bool ordered = true;
    for (size_t i = 0; i < batch.items().size(); ++i)
        ordered = ordered && batch.items()[i] == static_cast<int>(i);
    CHECK(ordered, "handed-over order is kept");
    batch.clear();
    CHECK(batch.empty() && batch.size() == 0, "clear");
    CHECK(batch.add(7) && batch.size() == 1 && batch.items()[0] == 7, "reuse after clear");

    // move-only items (the engine holds shared pointers; any owner type works)
    Batch<std::unique_ptr<std::string>> owned;
    CHECK(owned.add(std::make_unique<std::string>("a")), "move-only add");
    CHECK(owned.size() == 1 && *owned.items()[0] == "a", "move-only kept");

    // flushes: one group however many effects
    CHECK(flushCount(0) == 0, "no effects, no flush");
    CHECK(flushCount(1) == kFlushesPerGroup, "one effect: %d", flushCount(1));
    CHECK(flushCount(kMaxDeferred) == kFlushesPerGroup, "a full batch costs the same");
    CHECK(flushCount(1) == flushCount(37), "independent of the count");
    CHECK(kFlushesPerGroup == 2, "start and end");
    CHECK(kMaxDeferred >= 16 && kMaxDeferred <= 256, "a sane cap");

    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("chaosglow_test: ok\n");
    return 0;
}
