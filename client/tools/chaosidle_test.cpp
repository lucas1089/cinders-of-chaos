// Unit test of the idle state of the window (base patch 0143, client/BASE.md "0143").
//   g++ -std=c++17 -I DIR client/tools/chaosidle_test.cpp -o t   (DIR holds chaosidle.h, extracted from the patch)
// Checks: the three states, the frame limit of an unfocused window (never above the option), that a hidden window draws and
// builds nothing but still polls (and not slower than kMaxHiddenPollUs), the sleeps of the graphics thread, and the
// hidden -> shown change that asks for a repaint exactly once.
#include "chaosidle.h"
#include <cstdio>

using namespace chaos::idle;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    // states
    CHECK(classify(true, true) == State::Active, "shown and focused");
    CHECK(classify(true, false) == State::Unfocused, "shown, other window in front");
    CHECK(classify(false, false) == State::Hidden, "minimized");
    CHECK(classify(false, true) == State::Hidden, "hidden wins over a stale focus flag");

    // unfocused frame limit: the lower of the option and kUnfocusedFps
    CHECK(unfocusedCap(0) == kUnfocusedFps, "no option (vsync / unlimited) -> %d", unfocusedCap(0));
    CHECK(unfocusedCap(-5) == kUnfocusedFps, "negative option");
    CHECK(unfocusedCap(100) == kUnfocusedFps, "high option capped");
    CHECK(unfocusedCap(kUnfocusedFps) == kUnfocusedFps, "equal");
    CHECK(unfocusedCap(20) == 20, "a lower option wins: %d", unfocusedCap(20));
    CHECK(unfocusedCap(1) == 1, "one fps");
    for (int cap = -3; cap <= 300; ++cap)
        CHECK(unfocusedCap(cap) >= 1 && unfocusedCap(cap) <= kUnfocusedFps && (cap <= 0 || unfocusedCap(cap) <= cap),
              "range for %d", cap);

    // hidden: nothing drawn, nothing built; shown states unchanged
    CHECK(!rendersFrames(State::Hidden) && !buildsDrawQueues(State::Hidden), "hidden does no visual work");
    CHECK(rendersFrames(State::Active) && buildsDrawQueues(State::Active), "active draws");
    CHECK(rendersFrames(State::Unfocused) && buildsDrawQueues(State::Unfocused), "unfocused draws");

    // polling never stops and never gets much slower
    CHECK(logicPollIntervalUs(State::Active) == kActivePollUs && logicPollIntervalUs(State::Unfocused) == kActivePollUs,
          "shown windows poll as before (1 ms)");
    CHECK(kActivePollUs == 1000, "the base polled every millisecond");
    CHECK(logicPollIntervalUs(State::Hidden) == kHiddenPollUs, "hidden poll");
    CHECK(kHiddenPollUs > kActivePollUs, "hidden is lighter");
    CHECK(kHiddenPollUs <= kMaxHiddenPollUs && kMaxHiddenPollUs <= 10000, "a packet waits at most 10 ms: %lld", static_cast<long long>(kHiddenPollUs));
    for (State s : {State::Active, State::Unfocused, State::Hidden})
        CHECK(logicPollIntervalUs(s) > 0 && logicPollIntervalUs(s) <= kMaxHiddenPollUs, "poll interval positive and bounded");

    // graphics thread sleeps: the shown ones as in the base, the hidden one much longer but short enough for window events
    CHECK(mainSleepUs(State::Active) == kMaxMainSleepUs && mainSleepUs(State::Unfocused) == kMaxMainSleepUs, "shown sleep");
    CHECK(kMaxMainSleepUs == 2000, "the base cap");
    CHECK(mainSleepUs(State::Hidden) >= 10 * kMaxMainSleepUs, "at least 10x fewer wake-ups hidden");
    CHECK(mainSleepUs(State::Hidden) <= 50000, "restoring the window is seen within 50 ms: %lld", static_cast<long long>(mainSleepUs(State::Hidden)));

    // tracker: repaint once when the window comes back
    Tracker t;
    CHECK(!t.update(State::Active), "start active");
    CHECK(!t.update(State::Unfocused), "focus lost is not a resume");
    CHECK(!t.update(State::Active), "focus back is not a resume");
    CHECK(!t.update(State::Hidden) && t.last() == State::Hidden, "minimize");
    CHECK(!t.update(State::Hidden), "still hidden");
    CHECK(t.update(State::Active), "restore asks for a repaint");
    CHECK(!t.update(State::Active), "only once");
    t.update(State::Hidden);
    CHECK(t.update(State::Unfocused), "restored behind another window also repaints");
    CHECK(!t.update(State::Unfocused), "and only once");
    t.update(State::Hidden);
    t.update(State::Hidden);
    t.update(State::Hidden);
    CHECK(t.update(State::Active) && !t.update(State::Active), "a long minimize gives one repaint");

    // a flickering window (hidden / shown every poll) repaints on every shown poll, never twice for one change
    Tracker f;
    int repaints = 0;
    for (int i = 0; i < 100; ++i) {
        f.update(State::Hidden);
        if (f.update(State::Active)) ++repaints;
    }
    CHECK(repaints == 100, "one repaint per restore: %d", repaints);

    if (failures == 0)
        std::printf("chaosidle_test: ok\n");
    return failures ? 1 : 0;
}
