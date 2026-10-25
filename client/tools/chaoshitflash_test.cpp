// Unit test of the hit flash tint bookkeeping (base patch 0142, client/BASE.md "0142").
//   g++ -std=c++17 -I DIR client/tools/chaoshitflash_test.cpp -o t   (DIR holds chaoshitflash.h, extracted from the patch)
// Checks: the strength curve (the peak at the start, 0 at 120 ms, monotone, ease-out, inside 0..peak); the peak by hit size;
// who flashes (not heals, not the first health, not off the map, not a death); the per-creature gap; the budget (cap of
// alive flashes, slots freed when a flash is over, a clock that jumps back); the alpha byte.
#include "chaoshitflash.h"
#include <cstdio>

using namespace chaos::hitflash;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    // duration and constants
    CHECK(kDurationMs >= 100 && kDurationMs <= 150, "about 120 ms: %d", kDurationMs);
    CHECK(kMinGapMs > 0 && kMinGapMs <= kDurationMs, "gap %d", kMinGapMs);
    CHECK(kMaxActive >= 8 && kMaxActive <= 32, "cap %zu", kMaxActive);
    CHECK(kPeakMin > 0.0f && kPeakMin < kPeakMax && kPeakMax <= 1.0f, "peaks %f %f", kPeakMin, kPeakMax);

    // strength curve
    const float peak = 0.6f;
    CHECK(strengthAt(-10, peak) == peak && strengthAt(0, peak) == peak, "starts at the peak");
    CHECK(strengthAt(kDurationMs, peak) == 0.0f && strengthAt(kDurationMs + 5000, peak) == 0.0f, "ends at 0");
    float prev = peak;
    for (int ms = 0; ms <= kDurationMs; ++ms) {
        const float s = strengthAt(ms, peak);
        CHECK(s >= 0.0f && s <= peak, "range at %d", ms);
        CHECK(s <= prev, "monotone at %d", ms);
        CHECK(prev - s < 0.06f, "no jump at %d: %f -> %f", ms, prev, s);
        prev = s;
    }
    // ease-out: it falls fast first, so half the time is well under half the peak, and it is soft at the end
    CHECK(strengthAt(kDurationMs / 2, peak) < peak * 0.30f, "ease-out at half %f", strengthAt(kDurationMs / 2, peak));
    CHECK(strengthAt(kDurationMs / 2, peak) > peak * 0.20f, "not a cliff at half %f", strengthAt(kDurationMs / 2, peak));
    CHECK(strengthAt(kDurationMs - 1, peak) < 0.001f, "soft end %f", strengthAt(kDurationMs - 1, peak));

    // peak by hit size
    CHECK(peakForDrop(1) == kPeakMin, "1%% hit");
    CHECK(peakForDrop(0) == kPeakMin && peakForDrop(-5) == kPeakMin, "junk drop is the smallest");
    CHECK(peakForDrop(kBigDrop) == kPeakMax && peakForDrop(100) == kPeakMax, "big hit is capped");
    float pp = 0.0f;
    for (int d = 1; d <= 100; ++d) {
        const float p = peakForDrop(d);
        CHECK(p >= kPeakMin && p <= kPeakMax, "range at drop %d", d);
        CHECK(p >= pp, "monotone at drop %d", d);
        pp = p;
    }

    // alpha byte
    CHECK(alphaByte(0.0f) == 0 && alphaByte(1.0f) == 255, "bytes at the ends");
    CHECK(alphaByte(-1.0f) == 0 && alphaByte(5.0f) == 255, "bytes are clamped");
    CHECK(alphaByte(kPeakMax) <= 192 && alphaByte(kPeakMax) >= 188, "75%% is about 191: %d", alphaByte(kPeakMax));

    // who flashes: option, on a map tile, already shown, health down, not dead
    CHECK(wantsFlash(true, true, true, 100, 80), "a hit");
    CHECK(wantsFlash(true, true, true, 3, 1), "a hit that leaves 1%%");
    CHECK(!wantsFlash(false, true, true, 100, 80), "option off");
    CHECK(!wantsFlash(true, false, true, 100, 80), "not on the map");
    CHECK(!wantsFlash(true, true, false, 100, 80), "the first health after it appears");
    CHECK(!wantsFlash(true, true, true, 80, 100), "a heal");
    CHECK(!wantsFlash(true, true, true, 80, 80), "no change");
    CHECK(!wantsFlash(true, true, true, 20, 0), "a death (the death fade has it)");

    // gap per creature
    CHECK(gapPassed(0, 1000), "never flashed");
    CHECK(!gapPassed(1000, 1000) && !gapPassed(1000, 1000 + kMinGapMs - 1), "inside the gap");
    CHECK(gapPassed(1000, 1000 + kMinGapMs), "gap over");
    CHECK(gapPassed(5000, 1000), "the clock ran backwards: allow");

    // budget
    {
        Budget b;
        const int64_t t = 10000;
        for (size_t i = 0; i < kMaxActive; ++i)
            CHECK(b.tryAcquire(t), "slot %zu", i);
        CHECK(b.active(t) == kMaxActive, "full %zu", b.active(t));
        CHECK(!b.tryAcquire(t), "over the cap");
        CHECK(!b.tryAcquire(t + kDurationMs - 1), "one ms before they end");
        CHECK(b.active(t + kDurationMs - 1) == kMaxActive, "still full");
        CHECK(b.tryAcquire(t + kDurationMs), "free as they end");
        CHECK(b.active(t + kDurationMs) == 1, "only the new one: %zu", b.active(t + kDurationMs));
        // a steady stream never exceeds the cap
        Budget s;
        size_t most = 0;
        for (int64_t now = 20000; now < 25000; now += 3) {
            s.tryAcquire(now);
            if (s.active(now) > most)
                most = s.active(now);
        }
        CHECK(most <= kMaxActive, "stream never over the cap: %zu", most);
        CHECK(most == kMaxActive, "stream does reach the cap: %zu", most);
        // clock jumps back: stale far-future slots do not block
        Budget j;
        for (size_t i = 0; i < kMaxActive; ++i)
            j.tryAcquire(900000);
        CHECK(j.tryAcquire(1000), "clock went back");
        j.clear();
        CHECK(j.active(1000) == 0 && j.tryAcquire(1000), "clear");
    }

    if (failures == 0)
        std::printf("chaoshitflash_test: all ok\n");
    return failures == 0 ? 0 : 1;
}
