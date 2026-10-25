// Unit test of the floating number motion maths (base patch 0134, client/BASE.md "0134").
//   g++ -std=c++17 -I DIR client/tools/chaostextmotion_test.cpp -o t   (DIR holds chaostextmotion.h, extracted from the patch)
// Checks: the rise starts quicker than the stock linear one and ends flat, never overshoots; the pop starts small, peaks at
// kPopPeak and is exactly 1 after the settle and stays there (continuous, no jumps); the fade is 1 until its start, falls
// monotonically to 0; the sideways spread stays inside +-kSpreadPixels, uses both sides and keeps texts that appear one
// after the other apart.
#include "chaostextmotion.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

using namespace chaos::textmotion;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

int main()
{
    const int N = 1000;

    // rise: 0 at 0, 1 at 1, monotone, never above 1, ahead of the linear rise, flat at the end
    CHECK(riseProgress(0.0f) == 0.0f, "rise 0");
    CHECK(riseProgress(1.0f) == 1.0f, "rise 1");
    CHECK(riseProgress(-1.0f) == 0.0f && riseProgress(2.0f) == 1.0f, "rise clamps");
    float prev = 0.0f;
    for (int i = 1; i <= N; ++i) {
        const float u = static_cast<float>(i) / N;
        const float r = riseProgress(u);
        CHECK(r >= prev, "rise monotone at %f", u);
        CHECK(r <= 1.0f, "rise <= 1 at %f", u);
        CHECK(r >= u, "rise ahead of linear at %f", u);
        prev = r;
    }
    CHECK(riseProgress(0.1f) > 0.2f, "quick start: %f", riseProgress(0.1f));
    CHECK(1.0f - riseProgress(0.95f) < 0.001f, "flat end: %f", riseProgress(0.95f));

    // pop: start, peak, settle, steady
    CHECK(popScale(0.0f) == kPopStart, "pop start");
    CHECK(std::fabs(popScale(kPopUpEnd) - kPopPeak) < 1e-5f, "pop peak %f", popScale(kPopUpEnd));
    CHECK(std::fabs(popScale(kPopSettleEnd) - 1.0f) < 1e-5f, "pop settled");
    CHECK(popScale(0.5f) == 1.0f && popScale(1.0f) == 1.0f, "pop steady at 1");
    float maxScale = 0.0f, minScale = 99.0f, last = popScale(0.0f), maxStep = 0.0f;
    for (int i = 0; i <= N; ++i) {
        const float s = popScale(static_cast<float>(i) / N);
        maxScale = std::max(maxScale, s);
        minScale = std::min(minScale, s);
        maxStep = std::max(maxStep, std::fabs(s - last));
        last = s;
    }
    CHECK(maxScale <= kPopPeak + 1e-5f, "never above the peak: %f", maxScale);
    CHECK(minScale >= kPopStart - 1e-5f, "never below the start: %f", minScale);
    CHECK(maxStep < 0.05f, "no jumps: %f per 1/1000", maxStep);
    // up to the peak it only grows, after the peak it only shrinks
    prev = popScale(0.0f);
    for (int i = 1; i <= N; ++i) {
        const float u = static_cast<float>(i) / N;
        const float s = popScale(u);
        if (u <= kPopUpEnd) CHECK(s >= prev - 1e-6f, "grows at %f", u);
        else CHECK(s <= prev + 1e-6f, "shrinks at %f", u);
        prev = s;
    }

    // fade: 1 until the start, monotone to 0
    const float starts[] = { 0.0f, 0.5f, 1.0f / 1.2f, 0.95f, 1.0f };
    for (float fs : starts) {
        CHECK(fadeAlpha(0.0f, fs) == 1.0f || fs == 0.0f, "fade at 0, start %f", fs);
        if (fs < 1.0f)
            CHECK(fadeAlpha(1.0f, fs) == 0.0f, "fade ends at 0, start %f", fs);
        float a = 1.0f;
        for (int i = 0; i <= N; ++i) {
            const float u = static_cast<float>(i) / N;
            const float v = fadeAlpha(u, fs);
            CHECK(v >= 0.0f && v <= 1.0f, "alpha range");
            CHECK(v <= a + 1e-6f, "fade monotone at %f start %f", u, fs);
            if (u <= fs) CHECK(v == 1.0f, "no fade before start");
            a = v;
        }
    }

    // spread: range, both sides, an even use of the range, texts one after the other are apart
    int left = 0, right = 0;
    float lo = 9.0f, hi = -9.0f;
    for (uint32_t n = 0; n < 5000; ++n) {
        const float s = spreadUnit(n);
        CHECK(s >= -1.0f && s < 1.0f, "unit range %f", s);
        if (s < 0) ++left; else ++right;
        lo = std::min(lo, s);
        hi = std::max(hi, s);
        const float px = spreadOffset(n, 1.0f);
        CHECK(std::fabs(px) <= kSpreadPixels + 1e-4f, "pixels %f", px);
        CHECK(spreadOffset(n, 0.0f) == 0.0f, "no spread at the start");
    }
    CHECK(std::abs(left - right) < 200, "both sides: %d / %d", left, right);
    CHECK(lo < -0.99f && hi > 0.99f, "uses the whole range: %f .. %f", lo, hi);
    // any 6 texts in a row (a hit with several targets) are at least 0.1 apart (in -1 .. 1) pairwise
    float worst = 9.0f;
    for (uint32_t n = 0; n < 20000; ++n) {
        for (uint32_t a = 0; a < 6; ++a)
            for (uint32_t b = a + 1; b < 6; ++b)
                worst = std::min(worst, std::fabs(spreadUnit(n + a) - spreadUnit(n + b)));
    }
    CHECK(worst >= 0.1f, "six in a row stay apart: %f", worst);
    // the number n is the number n, whenever it is asked
    CHECK(spreadUnit(77) == spreadUnit(77), "deterministic");
    // wrap around at 2^32 keeps the range
    CHECK(spreadUnit(0xFFFFFFFFu) >= -1.0f && spreadUnit(0xFFFFFFFFu) < 1.0f, "wrap");

    if (failures) {
        std::printf("%d failures\n", failures);
        return 1;
    }
    std::printf("chaostextmotion_test ok (worst spread gap %.3f)\n", worst);
    return 0;
}
