// RmlUi layer, pure input logic (no engine, no RmlUi). Unit test: rmlinputlogic_test.cpp (CI job "native").
//  - Router: which input events go to RmlUi and which fall through to OTUI.
//  - TouchScroll: a finger drag scrolls an overflow element, a short fling goes on after the release, and the hover
//    is cleared when the finger is gone (RmlUi has no touch input, the engine turns a tap into a left click).
// Docs: docs/RMLUI_SPIKE.md "Phase 2".
#ifndef CHAOS_RMLINPUTLOGIC_H
#define CHAOS_RMLINPUTLOGIC_H

#include <cmath>

namespace chaosrml {

// ---------------------------------------------------------------------------------------------------------------
// Routing between OTUI and RmlUi. RmlUi documents are drawn above every OTUI widget, so a pointer over a visible
// RmlUi element belongs to RmlUi. A press that started inside RmlUi keeps its move and release events (a drag that
// leaves the window). Keys go to RmlUi only while one of its text fields has the focus.
// ---------------------------------------------------------------------------------------------------------------
enum class Event { Move, Press, Release, Wheel, KeyDown, KeyUp, KeyPress, KeyText };

struct RouteState {
    bool overRml = false;       // the pointer is over a visible RmlUi element (pointer-events auto)
    bool textFocus = false;     // the focused RmlUi element is an input, textarea or select
    bool pressedInside = false; // a button went down over RmlUi and is still down
};

inline bool consumes(Event e, const RouteState& s)
{
    switch (e) {
        case Event::Move: return s.overRml || s.pressedInside;
        case Event::Press: return s.overRml;
        case Event::Release: return s.pressedInside;
        case Event::Wheel: return s.overRml;
        case Event::KeyDown:
        case Event::KeyUp:
        case Event::KeyPress:
        case Event::KeyText: return s.textFocus;
    }
    return false;
}

// A press that RmlUi does not take, while one of its text fields has the focus, takes the focus away (RmlUi never
// saw the click, so it would keep the caret and eat the keys of the OTUI field the player just clicked).
inline bool blursOnPress(const RouteState& s) { return !s.overRml && s.textFocus; }

// OTUI must not show a hover or a tooltip for a widget that lies under an RmlUi element.
inline bool blocksOtuiHover(const RouteState& s) { return s.overRml || s.pressedInside; }

// ---------------------------------------------------------------------------------------------------------------
// Touch scrolling. All distances are interface pixels (what RmlUi's ScrollTop counts), times are seconds.
// Android sends: Move, Press(Touch), [more Moves; after the slop a synthetic Press(Left) at the start point], then
// Release(Touch) and a Release(Left) (drag), or Press+Release(Left) (tap) or of the Right button (long press).
// So the hover is cleared at the first release of Left or Right that follows the release of the finger.
// ---------------------------------------------------------------------------------------------------------------
struct Delta {
    int x = 0, y = 0; // whole pixels to add to scrollLeft / scrollTop
    bool any() const { return x != 0 || y != 0; }
};

class TouchScroll
{
public:
    float slop = 8.f;            // distance before a touch is a drag
    float flingMinSpeed = 150.f; // px/s at the release for a fling
    float flingStopSpeed = 20.f; // px/s where the fling ends
    float flingTau = 0.30f;      // s, exponential decay of the fling speed
    double flingWindow = 0.08;   // s: the last move must be this fresh at the release

    bool active() const { return m_active; }
    bool dragging() const { return m_dragging; }
    bool flinging() const { return m_fling; }

    // finger down; scrollable = it landed on an RmlUi element (otherwise the gesture belongs to OTUI)
    void begin(float x, float y, double now, bool scrollable)
    {
        m_active = scrollable;
        m_dragging = false;
        m_fling = false;
        m_leavePending = false;
        m_startX = m_lastX = x;
        m_startY = m_lastY = y;
        m_lastT = now;
        m_vx = m_vy = 0.f;
        m_remX = m_remY = 0.f;
    }

    // finger moved: how far the scrollable content has to move. Content follows the finger: finger up = scrollTop grows.
    Delta move(float x, float y, double now)
    {
        if (!m_active)
            return {};
        if (!m_dragging) {
            if (std::hypot(x - m_startX, y - m_startY) < slop)
                return {};
            m_dragging = true; // the slop distance itself is scrolled too, so the content does not lag behind the finger
            m_lastX = m_startX;
            m_lastY = m_startY;
            m_lastT = now;
        }
        const float dx = m_lastX - x, dy = m_lastY - y;
        const double dt = now - m_lastT;
        if (dt > 0.0005) {
            const float k = 0.5f; // smoothing of the speed
            m_vx = m_vx * (1.f - k) + static_cast<float>(dx / dt) * k;
            m_vy = m_vy * (1.f - k) + static_cast<float>(dy / dt) * k;
            m_lastT = now;
        }
        m_lastX = x;
        m_lastY = y;
        return whole(dx, dy);
    }

    // finger up
    void end(double now)
    {
        const bool wasActive = m_active;
        m_active = false;
        m_leavePending = true;
        m_fling = wasActive && m_dragging && (now - m_lastT) <= flingWindow &&
                  std::hypot(m_vx, m_vy) >= flingMinSpeed;
        if (!m_fling)
            m_vx = m_vy = 0.f;
        m_dragging = false;
        m_flingT = now;
        m_remX = m_remY = 0.f;
    }

    // the fling after the release: call once per frame, any frame rate
    Delta tick(double now)
    {
        if (!m_fling)
            return {};
        double dt = now - m_flingT;
        m_flingT = now;
        if (dt <= 0.0)
            return {};
        if (dt > 0.1)
            dt = 0.1;
        const float decay = std::exp(static_cast<float>(-dt / flingTau));
        // distance of an exponential decay over dt: v * tau * (1 - decay)
        const float dist = flingTau * (1.f - decay);
        const float dx = m_vx * dist, dy = m_vy * dist;
        m_vx *= decay;
        m_vy *= decay;
        if (std::hypot(m_vx, m_vy) < flingStopSpeed) {
            m_fling = false;
            m_vx = m_vy = 0.f;
        }
        return whole(dx, dy);
    }

    // the scroll hit the end of the content: stop the fling
    void stopFling()
    {
        m_fling = false;
        m_vx = m_vy = 0.f;
    }

    // A button release arrived. True once after a finger release: the caller clears the RmlUi hover (ProcessMouseLeave).
    bool buttonReleased()
    {
        const bool leave = m_leavePending;
        m_leavePending = false;
        return leave;
    }
    bool leavePending() const { return m_leavePending; }

private:
    Delta whole(float dx, float dy)
    {
        m_remX += dx;
        m_remY += dy;
        Delta d;
        d.x = static_cast<int>(m_remX);
        d.y = static_cast<int>(m_remY);
        m_remX -= static_cast<float>(d.x);
        m_remY -= static_cast<float>(d.y);
        return d;
    }

    bool m_active = false, m_dragging = false, m_fling = false, m_leavePending = false;
    float m_startX = 0, m_startY = 0, m_lastX = 0, m_lastY = 0;
    float m_vx = 0, m_vy = 0, m_remX = 0, m_remY = 0;
    double m_lastT = 0, m_flingT = 0;
};

// ---------------------------------------------------------------------------------------------------------------
// Repaint signature. The engine paints the UI again only on input or at a fixed interval; RmlUi must ask for a repaint
// when its frame differs from the last one (hover colour, animation, text change, scroll). The render interface feeds
// every draw call (and every geometry or texture it compiled) in, the manager compares frames.
// ---------------------------------------------------------------------------------------------------------------
class FrameSignature
{
public:
    void beginFrame() { m_cur = 1469598103934665603ull; m_calls = 0; }
    void add(unsigned long long v)
    {
        m_cur = (m_cur ^ v) * 1099511628211ull;
        ++m_calls;
    }
    // true when this frame differs from the previous one (the first frame always does)
    bool endFrame()
    {
        const bool changed = !m_have || m_cur != m_prev || m_calls != m_prevCalls;
        m_prev = m_cur;
        m_prevCalls = m_calls;
        m_have = true;
        return changed;
    }
    void forget() { m_have = false; }

private:
    unsigned long long m_cur = 0, m_prev = 0;
    unsigned m_calls = 0, m_prevCalls = 0;
    bool m_have = false;
};

} // namespace chaosrml

#endif
