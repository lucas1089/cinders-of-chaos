// Unit test of the eased creature bars (base patch 0146, client/BASE.md "0146").
//   g++ -std=c++17 -I DIR client/tools/chaosbars_test.cpp -o t   (DIR holds chaosbars.h, extracted from the patch)
// Checks: the constants; the first value and a stale bar are taken at once; the ease (150 ms, monotone, exact at the end);
// the chip (none at rest, holds 250 ms, slides 300 ms, never below the bar, gone at 550 ms); a second hit while the chip
// shows; heals ease up with no chip and drop an open chip; reset (appear or return into view); the clock jumping back;
// the pixel widths at rest equal the stock ones for every percent (double for health, float for mana).
#include "chaosbars.h"
#include <cstdio>

using namespace chaos::bars;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    CHECK(kEaseMs >= 100 && kEaseMs <= 200, "about 150 ms: %d", kEaseMs);
    CHECK(kHoldMs >= 200 && kHoldMs <= 300, "about 250 ms: %d", kHoldMs);
    CHECK(kSlideMs >= 250 && kSlideMs <= 350, "about 300 ms: %d", kSlideMs);
    CHECK(kStaleMs > kHoldMs + kSlideMs, "stale %d", kStaleMs);

    // curves
    CHECK(easeOut(0.0f) == 0.0f && easeOut(1.0f) == 1.0f && easeOut(-3.0f) == 0.0f && easeOut(9.0f) == 1.0f, "easeOut ends");
    CHECK(easeOut(0.5f) > 0.5f, "easeOut is fast first");
    CHECK(smoothStep(0.0f) == 0.0f && smoothStep(1.0f) == 1.0f && smoothStep(0.5f) == 0.5f, "smoothStep");

    // first value: taken at once, no chip, settled
    Track t;
    CHECK(!t.valid(), "new track has no value");
    t.observe(80.0f, 1000);
    CHECK(t.shown(1000) == 80.0f && t.chipAt(1000) == 80.0f && t.settled(1000), "first value is a start value");
    CHECK(t.shown(1000 + 5000) == 80.0f && t.settled(1000 + 5000), "stays");

    // a hit from 80 to 50 at 2000 (the bar was drawn the frame before)
    t.observe(80.0f, 1990);
    t.observe(50.0f, 2000);
    CHECK(t.shown(2000) == 80.0f, "starts where it stood: %f", t.shown(2000));
    CHECK(t.chipAt(2000) == 80.0f, "chip starts at the old level: %f", t.chipAt(2000));
    float prev = 80.0f;
    for (int ms = 0; ms <= kEaseMs; ++ms) {
        const float s = t.shown(2000 + ms);
        CHECK(s <= prev && s >= 50.0f, "bar monotone down at %d: %f", ms, s);
        CHECK(prev - s < 4.0f, "no jump at %d", ms);
        prev = s;
    }
    CHECK(t.shown(2000 + kEaseMs) == 50.0f && t.shown(2000 + kEaseMs + 1) == 50.0f, "exact at the end");
    CHECK(t.shown(2000 + kEaseMs / 2) < 65.0f, "ease-out: past half way at half time: %f", t.shown(2000 + kEaseMs / 2));
    // chip: holds until kHoldMs, slides, gone at hold + slide
    for (int ms = 0; ms <= kHoldMs; ms += 10)
        CHECK(t.chipAt(2000 + ms) == 80.0f, "chip holds at %d: %f", ms, t.chipAt(2000 + ms));
    prev = 80.0f;
    for (int ms = kHoldMs; ms <= kHoldMs + kSlideMs; ++ms) {
        const float c = t.chipAt(2000 + ms);
        CHECK(c <= prev && c >= 50.0f, "chip slides down at %d: %f", ms, c);
        CHECK(c >= t.shown(2000 + ms), "chip never below the bar at %d", ms);
        prev = c;
    }
    CHECK(t.chipAt(2000 + kHoldMs + kSlideMs) == 50.0f, "chip gone: %f", t.chipAt(2000 + kHoldMs + kSlideMs));
    CHECK(t.chipAt(2000 + kHoldMs + kSlideMs + 1) == 50.0f && t.settled(2000 + kHoldMs + kSlideMs), "settled");
    CHECK(!t.settled(2000 + 100), "not settled while it moves");
    CHECK(!t.settled(2000 + kHoldMs + kSlideMs - 5), "not settled while the chip slides");

    // a second hit while the chip stands: the chip starts from the level on screen (the old chip), hold restarts
    Track h;
    h.observe(100.0f, 0);
    h.observe(70.0f, 10);
    h.observe(70.0f, 200);  // drawn on, the chip still holds at 100
    h.observe(40.0f, 210);
    CHECK(h.chipAt(210) == 100.0f, "second hit keeps the chip level: %f", h.chipAt(210));
    CHECK(h.shown(210) == 70.0f, "bar had arrived at 70: %f", h.shown(210));
    CHECK(h.chipAt(210 + kHoldMs) == 100.0f, "hold restarted");
    CHECK(h.chipAt(210 + kHoldMs + kSlideMs) == 40.0f, "gone after the slide: %f", h.chipAt(210 + kHoldMs + kSlideMs));
    // a hit while the chip slides: from the chip level that is on screen
    Track s;
    s.observe(100.0f, 0);
    s.observe(60.0f, 10);
    for (int ms = 20; ms < 10 + kHoldMs + 150; ms += 16) s.observe(60.0f, ms);
    const int64_t mid = 10 + kHoldMs + 150;
    s.observe(60.0f, mid);
    const float chipMid = s.chipAt(mid);
    CHECK(chipMid < 100.0f && chipMid > 60.0f, "chip is sliding: %f", chipMid);
    s.observe(30.0f, mid + 16);
    CHECK(s.chipAt(mid + 16) <= chipMid && s.chipAt(mid + 16) > 60.0f - 1.0f, "new hit continues from the chip on screen: %f", s.chipAt(mid + 16));

    // heals: ease up, no chip; an open chip is dropped
    Track g;
    g.observe(30.0f, 0);
    g.observe(90.0f, 5);
    CHECK(g.shown(5) == 30.0f && g.chipAt(5) == 30.0f, "heal starts at the old level, no chip: %f %f", g.shown(5), g.chipAt(5));
    prev = 30.0f;
    for (int ms = 5; ms <= 5 + kEaseMs; ++ms) {
        const float v = g.shown(ms);
        CHECK(v >= prev && v <= 90.0f, "heal monotone up at %d", ms);
        CHECK(g.chipAt(ms) == v, "no chip while healing at %d", ms);
        prev = v;
    }
    CHECK(g.shown(5 + kEaseMs) == 90.0f && g.settled(5 + kEaseMs), "heal ends exact");
    g.observe(90.0f, 400);
    g.observe(50.0f, 410);  // hit: chip 90
    g.observe(50.0f, 420);
    g.observe(95.0f, 430);  // heal during the chip
    for (int ms = 430; ms <= 430 + 700; ms += 7)
        CHECK(g.chipAt(ms) == g.shown(ms), "heal drops the chip at %d", ms);

    // reset: the next value is a start value, the bar never slides in from the old one
    Track r;
    r.observe(100.0f, 0);
    r.reset();
    CHECK(!r.valid(), "reset");
    r.observe(15.0f, 50);
    CHECK(r.shown(50) == 15.0f && r.chipAt(50) == 15.0f && r.settled(50), "appears at 15, no slide");

    // stale: not drawn for kStaleMs and then drawn at another value: taken at once
    Track st;
    st.observe(100.0f, 0);
    st.observe(100.0f, 16);
    st.observe(20.0f, 16 + kStaleMs + 1);
    CHECK(st.shown(16 + kStaleMs + 1) == 20.0f && st.settled(16 + kStaleMs + 1), "stale bar snaps");
    Track ok;
    ok.observe(100.0f, 0);
    ok.observe(20.0f, kStaleMs);  // exactly the limit still counts as drawn
    CHECK(ok.shown(kStaleMs) == 100.0f, "at the limit it still eases: %f", ok.shown(kStaleMs));

    // the clock jumps back: the bar takes the value, nothing is left half way
    Track b;
    b.observe(100.0f, 5000);
    b.observe(40.0f, 5010);
    b.observe(40.0f, 100);
    CHECK(b.shown(100) == 40.0f && b.settled(100), "clock back snaps");
    CHECK(b.shown(-50) >= 0.0f, "no crash before the start");

    // the same value again changes nothing
    Track same;
    same.observe(60.0f, 0);
    same.observe(60.0f, 16);
    same.observe(60.0f, 32);
    CHECK(same.settled(32) && same.shown(32) == 60.0f, "no change, no animation");

    // 0 health and full
    Track z;
    z.observe(100.0f, 0);
    z.observe(0.0f, 10);
    CHECK(z.shown(10 + kEaseMs) == 0.0f && z.chipAt(10 + kHoldMs + kSlideMs) == 0.0f, "down to 0");

    // pixel widths at rest are the stock ones, for every percent
    for (int p = 0; p <= 100; ++p) {
        Track w;
        w.observe(static_cast<float>(p), 0);
        const int stock = static_cast<int>((p / 100.0) * 25);
        CHECK(widthPx(w.shown(0), 25) == stock, "health width at %d%%: %d vs %d", p, widthPx(w.shown(0), 25), stock);
        const int stockF = static_cast<int>((static_cast<float>(p) / 100.f) * 25);
        CHECK(widthPxF(w.shown(0), 25) == stockF, "mana width at %d%%", p);
        CHECK(widthPx(w.chipAt(0), 25) - widthPx(w.shown(0), 25) == 0, "no chip pixels at rest at %d%%", p);
    }

    if (failures == 0)
        std::printf("chaosbars: all checks passed\n");
    return failures == 0 ? 0 : 1;
}
