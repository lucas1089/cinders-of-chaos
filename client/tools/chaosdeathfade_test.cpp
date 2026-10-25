// Unit test of the death fade bookkeeping (base patch 0139, client/BASE.md "0139").
//   g++ -std=c++17 -I DIR client/tools/chaosdeathfade_test.cpp -o t   (DIR holds chaosdeathfade.h, extracted from the patch)
// Checks: the alpha curve (1 at the start, 0 at the end, monotone, inside 0..1, soft at both ends); who gets a ghost (not
// the local player, only at 0 health, only with the option); the queue (cap with the oldest dropped, no second ghost for one
// id, expiry, clear, copies that stay valid, a clock that jumps back).
#include "chaosdeathfade.h"
#include <cstdio>
#include <memory>
#include <string>

using namespace chaos::deathfade;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    // alpha
    CHECK(alphaAt(-50) == 1.0f && alphaAt(0) == 1.0f, "starts at 1");
    CHECK(alphaAt(kDurationMs) == 0.0f && alphaAt(kDurationMs + 1000) == 0.0f, "ends at 0");
    CHECK(kDurationMs >= 300 && kDurationMs <= 400, "about 300-400 ms: %d", kDurationMs);
    float prev = 1.0f;
    for (int ms = 0; ms <= kDurationMs; ++ms) {
        const float a = alphaAt(ms);
        CHECK(a >= 0.0f && a <= 1.0f, "range at %d", ms);
        CHECK(a <= prev, "monotone at %d", ms);
        CHECK(prev - a < 0.02f, "no jump at %d: %f -> %f", ms, prev, a);
        prev = a;
    }
    CHECK(alphaAt(1) > 0.999f, "soft start %f", alphaAt(1));
    CHECK(alphaAt(kDurationMs - 1) < 0.001f, "soft end %f", alphaAt(kDurationMs - 1));
    CHECK(alphaAt(kDurationMs / 2) > 0.49f && alphaAt(kDurationMs / 2) < 0.51f, "half way is half");

    // who gets a ghost
    CHECK(wantsGhost(true, false, true, 0, true), "a monster at 0 health");
    CHECK(!wantsGhost(false, false, true, 0, true), "option off");
    CHECK(!wantsGhost(true, true, true, 0, true), "never the local player");
    CHECK(!wantsGhost(true, false, false, 0, true), "invisible");
    CHECK(!wantsGhost(true, false, true, 1, true), "still alive (walks out of view)");
    CHECK(!wantsGhost(true, false, true, 100, true), "full health");
    CHECK(!wantsGhost(true, false, true, 0, false), "not on a map tile");

    // queue: cap, oldest out
    GhostQueue<int> q;
    for (uint32_t i = 1; i <= kMaxGhosts + 10; ++i)
        CHECK(q.push(i, static_cast<int>(i), static_cast<int64_t>(i)), "push %u", i);
    CHECK(q.size() == kMaxGhosts, "cap %zu", q.size());
    CHECK(q.entries().front().id == 11 && q.entries().back().id == kMaxGhosts + 10, "oldest 10 dropped");
    CHECK(q.entries().front().value == 11, "value kept");

    // no second ghost for one id
    CHECK(!q.push(20, 99, 1000), "same id twice");
    CHECK(q.size() == kMaxGhosts, "size unchanged");
    CHECK(q.push(0, 1, 5) && q.push(0, 2, 6), "id 0 is not deduplicated");

    // expiry
    GhostQueue<std::string> s;
    s.push(1, "a", 1000);
    s.push(2, "b", 1200);
    s.push(3, "c", 1340);
    s.expire(1349);
    CHECK(s.size() == 3, "none over at 1349");
    s.expire(1350);
    CHECK(s.size() == 2 && s.entries().front().value == "b", "first over at 1350");
    s.expire(1549);
    CHECK(s.size() == 2, "second not over at 1549");
    s.expire(1550);
    CHECK(s.size() == 1 && s.entries().front().value == "c", "second over at 1550");
    s.expire(5000);
    CHECK(s.empty(), "all over");
    s.push(7, "x", 9000);
    s.expire(8000);
    CHECK(s.empty(), "a clock that went back drops the ghost");

    // a ghost holds a copy: the source can die first
    GhostQueue<std::shared_ptr<std::string>> p;
    {
        auto src = std::make_shared<std::string>("outfit");
        p.push(1, src, 0);
        *src = "changed";
    }
    CHECK(p.entries().front().value.use_count() == 1 && *p.entries().front().value == "changed", "shared copy outlives its source");

    // clear
    q.clear();
    CHECK(q.empty() && q.size() == 0, "clear");
    CHECK(q.push(20, 1, 0), "an id is free again after clear");

    if (failures == 0)
        std::printf("chaosdeathfade_test: ok\n");
    return failures == 0 ? 0 : 1;
}
