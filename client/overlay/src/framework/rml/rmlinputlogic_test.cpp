// Unit test of rmlinputlogic.h. Build: g++ -std=c++17 -Wall -Wextra rmlinputlogic_test.cpp -o t && ./t
#include "rmlinputlogic.h"

#include <cstdio>
#include <cstdlib>

using namespace chaosrml;

static int failures = 0;
#define CHECK(cond)                                                                   \
    do {                                                                              \
        if (!(cond)) {                                                                \
            std::printf("FAIL line %d: %s\n", __LINE__, #cond);                       \
            ++failures;                                                               \
        }                                                                             \
    } while (0)

static void testRouter()
{
    RouteState outside, over, drag, text;
    over.overRml = true;
    drag.pressedInside = true;
    text.textFocus = true;

    CHECK(!consumes(Event::Move, outside));
    CHECK(consumes(Event::Move, over));
    CHECK(consumes(Event::Move, drag)); // a drag that left the window
    CHECK(!consumes(Event::Press, outside));
    CHECK(consumes(Event::Press, over));
    CHECK(!consumes(Event::Release, over));  // no press started inside: OTUI gets the release
    CHECK(consumes(Event::Release, drag));
    CHECK(!consumes(Event::Wheel, outside));
    CHECK(consumes(Event::Wheel, over));
    // keys: only with a text field focused, wherever the pointer is
    CHECK(!consumes(Event::KeyDown, over));
    CHECK(!consumes(Event::KeyText, outside));
    CHECK(consumes(Event::KeyDown, text));
    CHECK(consumes(Event::KeyUp, text));
    CHECK(consumes(Event::KeyPress, text));
    CHECK(consumes(Event::KeyText, text));

    CHECK(blursOnPress(text));      // clicked an OTUI widget while an RmlUi field had the caret
    CHECK(!blursOnPress(over));
    RouteState both;
    both.overRml = both.textFocus = true;
    CHECK(!blursOnPress(both));     // clicked inside RmlUi: RmlUi moves the focus itself

    CHECK(!blocksOtuiHover(outside));
    CHECK(blocksOtuiHover(over));
    CHECK(blocksOtuiHover(drag));
}

static void testDragScroll()
{
    TouchScroll t;
    double now = 0;
    t.begin(100, 300, now, true);
    CHECK(t.active());
    // below the slop: nothing
    now += 0.016;
    CHECK(!t.move(100, 296, now).any());
    CHECK(!t.dragging());
    // past the slop: the whole distance from the start, once (finger up 12 px = content up 12 px)
    now += 0.016;
    Delta d = t.move(100, 288, now);
    CHECK(t.dragging());
    CHECK(d.y == 12 && d.x == 0);
    // then step by step
    now += 0.016;
    d = t.move(100, 278, now);
    CHECK(d.y == 10);
    // dragging down scrolls back
    now += 0.016;
    d = t.move(100, 283, now);
    CHECK(d.y == -5);
    // total scrolled equals the finger's travel from the start
    CHECK(12 + 10 - 5 == 300 - 283);
}

static void testSubPixelCarry()
{
    TouchScroll t;
    t.begin(0, 0, 0, true);
    t.move(0, -20, 0.01); // into the drag (20 px)
    int total = 0;
    double now = 0.01;
    for (int i = 0; i < 40; ++i) { // 0.25 px per event
        now += 0.01;
        total += t.move(0, -20 - 0.25f * (i + 1), now).y;
    }
    CHECK(total == 10); // 40 * 0.25
}

static void testFling()
{
    TouchScroll t;
    double now = 0;
    t.begin(50, 400, now, true);
    int total = 0;
    float y = 400;
    for (int i = 0; i < 10; ++i) { // 2000 px/s upward
        now += 0.016;
        y -= 32;
        total += t.move(50, y, now).y;
    }
    t.end(now + 0.005);
    CHECK(t.flinging());
    CHECK(t.leavePending());
    // the fling goes on and slows down
    double tt = now + 0.005;
    int fl = 0, last = 1 << 30;
    bool monotone = true;
    int frames = 0;
    while (t.flinging() && frames < 1000) {
        tt += 0.016;
        const int step = t.tick(tt).y;
        fl += step;
        if (step > last + 1) monotone = false;
        if (step > 0) last = step;
        ++frames;
    }
    CHECK(!t.flinging());
    CHECK(fl > 100);
    CHECK(monotone);
    CHECK(frames < 120); // stops in under 2 seconds
    // a finger that rested before the release does not fling
    TouchScroll u;
    now = 0;
    u.begin(50, 400, now, true);
    y = 400;
    for (int i = 0; i < 5; ++i) {
        now += 0.016;
        y -= 32;
        u.move(50, y, now);
    }
    u.end(now + 0.5);
    CHECK(!u.flinging());
    // a slow drag does not fling
    TouchScroll w;
    now = 0;
    w.begin(50, 400, now, true);
    y = 400;
    for (int i = 0; i < 10; ++i) {
        now += 0.05;
        y -= 2; // 40 px/s
        w.move(50, y, now);
    }
    w.end(now);
    CHECK(!w.flinging());
    // a new touch stops a fling
    t.begin(0, 0, tt, true);
    CHECK(!t.flinging());
    CHECK(!t.tick(tt + 0.1).any());
}

static void testNotScrollable()
{
    TouchScroll t;
    t.begin(10, 10, 0, false); // the finger landed on OTUI
    CHECK(!t.active());
    CHECK(!t.move(10, 200, 0.1).any());
    t.end(0.2);
    CHECK(!t.flinging());
}

static void testLeaveAfterRelease()
{
    TouchScroll t;
    t.begin(10, 10, 0, true);
    CHECK(!t.buttonReleased()); // a mouse button release without a finger: no leave
    // tap: Release(Touch), then Press+Release(Left)
    t.end(0.05);
    CHECK(t.buttonReleased());  // after the Left release the hover is cleared
    CHECK(!t.buttonReleased()); // only once
    // drag: the Left release comes after the finger release too
    t.begin(10, 10, 1.0, true);
    t.move(10, 40, 1.016);
    t.end(1.03);
    CHECK(t.buttonReleased());
    // a new finger before the release of the old one cancels the pending leave
    t.end(2.0);
    t.begin(5, 5, 2.01, true);
    CHECK(!t.buttonReleased());
}

static void testSignature()
{
    FrameSignature s;
    s.beginFrame();
    s.add(1);
    s.add(2);
    CHECK(s.endFrame());  // first frame
    s.beginFrame();
    s.add(1);
    s.add(2);
    CHECK(!s.endFrame()); // same frame: no repaint
    s.beginFrame();
    s.add(1);
    s.add(3);
    CHECK(s.endFrame());  // a draw call changed (hover colour = new geometry)
    s.beginFrame();
    s.add(1);
    s.add(3);
    s.add(4);
    CHECK(s.endFrame());  // a draw call more
    s.beginFrame();
    s.add(1);
    s.add(3);
    CHECK(s.endFrame());  // a draw call less
    s.beginFrame();
    s.add(1);
    s.add(3);
    CHECK(!s.endFrame());
    s.forget();
    s.beginFrame();
    s.add(1);
    s.add(3);
    CHECK(s.endFrame());  // after forget (resize): paint
}

int main()
{
    testRouter();
    testDragScroll();
    testSubPixelCarry();
    testFling();
    testNotScrollable();
    testLeaveAfterRelease();
    testSignature();
    if (failures) {
        std::printf("%d failed\n", failures);
        return 1;
    }
    std::printf("rmlinputlogic_test: ok\n");
    return 0;
}
