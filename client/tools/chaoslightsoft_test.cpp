// Unit test of the warmer light map (base patch 0149, client/BASE.md "0149").
//   g++ -std=c++17 -I DIR -I client/tools client/tools/chaoslightsoft_test.cpp -o t
//   (DIR holds chaoslightfill.h from patch 0140 and chaoslightsoft.h from patch 0149, extracted from the patches)
// 0149 changes the output of the light map on purpose, so this does not compare with the stock loop (chaoslight_ref.h stays
// the stock reference, used here for the Color maths and by light_bench.cpp). It checks the new properties:
//   - a naive per-tile loop with the same formulas gives the same bytes as chaoslight::fillSoft (the reach box and the floor
//     starts lose nothing), flicker on and off, on random maps;
//   - the falloff is monotonic with the distance, has the stock radius and a single light over black is its own shaded colour;
//   - the soft clamp: never above 255, never below the larger term, symmetric, neutral with 0 (all 65536 pairs);
//   - many overlapping lights stay at 255 or below and never darker than any single light;
//   - flicker: bounded (the radius stays within +-12%), deterministic for a time and a place, smooth, moves with time, the
//     seed follows the world tile, only warm colours flicker, and with the option off the time has no effect.
#include "chaoslightsoft.h"
#include "chaoslight_ref.h"
#include <cstdio>
#include <cstdlib>
#include <random>

using namespace reflight;

static int failures = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL line %d: %s\n", __LINE__, #c); ++failures; } } while (0)

typedef std::vector<uint8_t> Buf;

static void soft(Buf& out, int w, int h, int S, const Color& g, const std::vector<Light>& lights,
                 const std::vector<TileLight>& tiles, const chaoslight::Flicker& fl)
{
    out.assign(size_t(w) * h * 4 + 8, 0xAB); // 8 guard bytes behind the buffer
    chaoslight::fillSoft(out.data(), w, h, S, g.r(), g.g(), g.b(), lights.data(), lights.size(), tiles.data(), fl,
                         [](const Light& l) { return Color::from8bit(l.color); },
                         [](const Color& base, float k, int* rgb) {
                             const Color c = base * k;
                             rgb[0] = c.r(); rgb[1] = c.g(); rgb[2] = c.b();
                         });
}

static bool guardOk(const Buf& b, int w, int h)
{
    for (int i = 0; i < 8; ++i)
        if (b[size_t(w) * h * 4 + i] != 0xAB) return false;
    return true;
}

// every tile against every light, no reach box: the same formulas, written out
static void naive(Buf& out, int w, int h, int S, const Color& g, const std::vector<Light>& lights,
                  const std::vector<TileLight>& tiles, const chaoslight::Flicker& fl)
{
    out.assign(size_t(w) * h * 4, 0);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            const size_t index = size_t(y) * w + x;
            uint8_t* p = &out[index * 4];
            p[0] = g.r(); p[1] = g.g(); p[2] = g.b(); p[3] = 255;
            for (size_t i = tiles[index].start; i < lights.size(); ++i) {
                const Light& l = lights[i];
                if (l.intensity == 0) continue;
                float radius = float(l.intensity);
                if (fl.on && chaoslight::isWarm(l.color)) {
                    const uint32_t seed = chaoslight::seedOf(chaoslight::floorDiv(l.pos.x, S) + fl.originX,
                                                             chaoslight::floorDiv(l.pos.y, S) + fl.originY, l.color);
                    radius *= 1.0f + chaoslight::kAmplitude * chaoslight::noise(seed, fl.timeMs);
                }
                const int dx = x * S + S / 2 - l.pos.x, dy = y * S + S / 2 - l.pos.y;
                const float d2 = float(int64_t(dx) * dx + int64_t(dy) * dy);
                if (d2 >= radius * S * (radius * S)) continue;
                const float k = chaoslight::soften((radius - std::sqrt(d2) / S) * 0.2f);
                if (k <= 0.0f) continue;
                const Color c = Color::from8bit(l.color) * k;
                p[0] = uint8_t(chaoslight::addSoft(p[0], c.r()));
                p[1] = uint8_t(chaoslight::addSoft(p[1], c.g()));
                p[2] = uint8_t(chaoslight::addSoft(p[2], c.b()));
            }
        }
}

int main()
{
    std::mt19937 rng(228);
    auto rnd = [&](int lo, int hi) { return std::uniform_int_distribution<int>(lo, hi)(rng); };
    const chaoslight::Flicker off;

    // ---- the soft clamp, all pairs
    {
        bool ok = true;
        for (int p = 0; p < 256; ++p)
            for (int c = 0; c < 256; ++c) {
                const int v = chaoslight::addSoft(p, c);
                if (v > 255 || v < std::max(p, c) || v != chaoslight::addSoft(c, p)) ok = false;
                if (c == 0 && v != p) ok = false;
                if (p == 0 && v != c) ok = false;
                if (p == 255 && v != 255) ok = false;
            }
        CHECK(ok);
        CHECK(chaoslight::addSoft(254, 254) == 254 && chaoslight::addSoft(255, 255) == 255); // the rounding goes up, so no overflow
        CHECK(chaoslight::addSoft(128, 128) == 191); // two halves add up to about three quarters
    }

    // ---- smoothstep
    {
        CHECK(chaoslight::soften(-1) == 0.0f && chaoslight::soften(0) == 0.0f && chaoslight::soften(1) == 1.0f && chaoslight::soften(7) == 1.0f);
        float prev = 0;
        bool mono = true;
        for (int i = 0; i <= 1000; ++i) {
            const float v = chaoslight::soften(i / 1000.0f);
            if (v < prev || v < 0 || v > 1) mono = false;
            prev = v;
        }
        CHECK(mono);
        CHECK(chaoslight::soften(0.5f) == 0.5f);
        CHECK(chaoslight::soften(0.1f) < 0.1f && chaoslight::soften(0.9f) > 0.9f); // soft start, soft end
    }

    // ---- warm colours
    {
        CHECK(chaoslight::isWarm(206) && chaoslight::isWarm(198) && chaoslight::isWarm(210));
        CHECK(!chaoslight::isWarm(215) && !chaoslight::isWarm(0) && !chaoslight::isWarm(216) && !chaoslight::isWarm(255));
        CHECK(!chaoslight::isWarm(5) && !chaoslight::isWarm(30) && !chaoslight::isWarm(185)); // blue, green, magenta
        CHECK(!chaoslight::isWarm(1 * 36 + 0 * 6 + 0)); // dim red (level 1)
    }

    // ---- a single light over black: its own colour, stock radius, monotonic, no light beyond the radius
    {
        const int S = 32, w = 41, h = 3;
        std::vector<TileLight> tiles(size_t(w) * h, TileLight{ 0, 0 });
        for (int color : { 215, 206, 198, 5, 30, 180 })
            for (int intensity : { 1, 2, 3, 5, 6, 9, 15, 19 }) {
                std::vector<Light> lights{ Light{ { 20 * S + S / 2, 1 * S + S / 2 }, uint8_t(color), uint8_t(intensity) } };
                Buf b;
                soft(b, w, h, S, Color(0, 0, 0), lights, tiles, off);
                CHECK(guardOk(b, w, h));
                const Color c8 = Color::from8bit(color);
                bool mono = true, edge = true, centre = true;
                for (int x = 20; x < w; ++x) {
                    const int d = x - 20;
                    const uint8_t* p = &b[(size_t(1) * w + x) * 4];
                    const uint8_t* q = &b[(size_t(1) * w + x + 1) * 4];
                    if (x + 1 < w && (q[0] > p[0] || q[1] > p[1] || q[2] > p[2])) mono = false;
                    if (d >= intensity && (p[0] || p[1] || p[2])) edge = false; // the stock radius: nothing at `intensity` tiles
                    if (p[3] != 255) edge = false;
                    // mirror: the left side is the same
                    const uint8_t* m = &b[(size_t(1) * w + (20 - d)) * 4];
                    if (m[0] != p[0] || m[1] != p[1] || m[2] != p[2]) mono = false;
                }
                const float x0 = std::min(1.0f, intensity * 0.2f);
                const Color want = c8 * chaoslight::soften(x0);
                const uint8_t* p = &b[(size_t(1) * w + 20) * 4];
                if (p[0] != want.r() || p[1] != want.g() || p[2] != want.b()) centre = false; // max behaviour: its own shaded colour
                CHECK(mono); CHECK(edge); CHECK(centre);
            }
        // a bright strong light reaches its own colour at the middle
        std::vector<Light> strong{ Light{ { 20 * S + S / 2, S + S / 2 }, 215, 12 } };
        Buf b;
        soft(b, w, h, S, Color(0, 0, 0), strong, tiles, off);
        CHECK(b[(size_t(1) * w + 20) * 4] == 255);
    }

    // ---- overlap: many lights never exceed 255, never darker than one of them, never darker than the global light
    {
        const int S = 32, w = 9, h = 9;
        std::vector<TileLight> tiles(size_t(w) * h, TileLight{ 0, 0 });
        std::vector<Light> lights;
        for (int i = 0; i < 60; ++i)
            lights.push_back(Light{ { 4 * S + S / 2 + rnd(-40, 40), 4 * S + S / 2 + rnd(-40, 40) }, uint8_t(rnd(1, 215)), uint8_t(rnd(3, 9)) });
        const Color g = Color::from8bit(100) * 0.5f;
        Buf all;
        soft(all, w, h, S, g, lights, tiles, off);
        CHECK(guardOk(all, w, h));
        bool ok = true;
        for (size_t i = 0; i < lights.size(); ++i) {
            Buf one;
            soft(one, w, h, S, g, std::vector<Light>{ lights[i] }, tiles, off);
            for (size_t j = 0; j < size_t(w) * h * 4; ++j)
                if (all[j] < one[j]) ok = false;
        }
        CHECK(ok);
        // 30 white lights on top of each other: saturates at 255, not above, and is not a wrap
        std::vector<Light> pile(30, Light{ { 4 * S + S / 2, 4 * S + S / 2 }, 215, 8 });
        Buf p;
        soft(p, w, h, S, Color(0, 0, 0), pile, tiles, off);
        CHECK(p[(size_t(4) * w + 4) * 4] == 255 && p[(size_t(4) * w + 4) * 4 + 1] == 255 && p[(size_t(4) * w + 4) * 4 + 2] == 255);
        // two grey lights on one spot add up: more than one of them, not above 255
        std::vector<Light> two(2, Light{ { 4 * S + S / 2, 4 * S + S / 2 }, uint8_t(36 + 6 + 1), 3 });
        Buf t, one;
        soft(t, w, h, S, Color(0, 0, 0), two, tiles, off);
        soft(one, w, h, S, Color(0, 0, 0), std::vector<Light>{ two[0] }, tiles, off);
        const size_t mid = (size_t(4) * w + 4) * 4;
        CHECK(t[mid] > one[mid] && t[mid] < 255);
    }

    // ---- the naive loop gives the same bytes (reach box and floor starts), flicker on and off
    {
        const int sprite[] = { 16, 32, 48, 64 };
        long cases = 0, pairs = 0;
        for (int iter = 0; iter < 2000; ++iter) {
            const int S = sprite[rnd(0, 3)];
            const int w = rnd(1, 40), h = rnd(1, 30);
            const int count = rnd(0, iter % 7 == 0 ? 400 : 100);
            std::vector<Light> lights;
            for (int i = 0; i < count; ++i) {
                Light l;
                const int mode = rnd(0, 4);
                if (mode == 0) { l.pos.x = rnd(-3000, w * S + 3000); l.pos.y = rnd(-3000, h * S + 3000); }
                else if (mode == 1) { l.pos.x = rnd(0, w) * S + S / 2; l.pos.y = rnd(0, h) * S + S / 2; }
                else { l.pos.x = rnd(-S, w * S + S); l.pos.y = rnd(-S, h * S + S); }
                // half of the lights warm, so the flicker is really tested
                l.color = uint8_t(rnd(0, 1) ? 36 * rnd(3, 5) + 6 * rnd(0, 3) + rnd(0, 1) : rnd(0, 255));
                const int im = rnd(0, 3);
                l.intensity = uint8_t(im == 0 ? rnd(0, 255) : im == 1 ? rnd(0, 3) : rnd(0, 12));
                lights.push_back(l);
            }
            std::vector<TileLight> tiles(size_t(w) * h, TileLight{ 0, 0 });
            for (auto& t : tiles) t.start = rnd(0, 3) == 0 ? size_t(rnd(0, count + 2)) : (rnd(0, 2) ? 0 : size_t(count / 2));
            const Color g = Color::from8bit(rnd(0, 255)) * (rnd(0, 255) / 255.0f);
            chaoslight::Flicker fl;
            fl.on = iter % 2 == 0;
            fl.timeMs = uint32_t(rnd(0, 1 << 30)) * 3u;
            fl.originX = rnd(-30000, 30000);
            fl.originY = rnd(-30000, 30000);
            Buf a, b;
            naive(a, w, h, S, g, lights, tiles, fl);
            soft(b, w, h, S, g, lights, tiles, fl);
            ++cases;
            pairs += long(count) * w * h;
            if (!guardOk(b, w, h) || !std::equal(a.begin(), a.end(), b.begin())) {
                std::printf("MISMATCH iter %d (map %dx%d, sprite %d, %d lights, flicker %d)\n", iter, w, h, S, count, fl.on);
                ++failures;
                if (failures > 5) return 1;
            }
        }
        std::printf("naive loop: %ld random maps, %ld light/tile pairs compared\n", cases, pairs);
    }

    // ---- noise: bounded, deterministic, smooth, moving
    {
        float lo = 9, hi = -9, maxStep = 0;
        bool det = true;
        for (uint32_t seed = 1; seed < 300; seed += 7) {
            float prev = chaoslight::noise(seed, 0);
            for (uint32_t t = 0; t < 4000; ++t) {
                const float n = chaoslight::noise(seed, t);
                if (n != chaoslight::noise(seed, t)) det = false;
                lo = std::min(lo, n); hi = std::max(hi, n);
                if (t > 0) maxStep = std::max(maxStep, std::fabs(n - prev));
                prev = n;
            }
        }
        CHECK(det);
        CHECK(lo >= -1.0f && hi <= 1.0f);
        CHECK(lo < -0.5f && hi > 0.5f); // it really moves
        CHECK(maxStep < 0.08f);         // smooth: no jump between two milliseconds
        // huge times and the wrap of the 32 bit clock stay in range
        bool range = true;
        for (uint32_t t : { 0xFFFFFF00u, 0xFFFFFFFFu, 0x7FFFFFFFu, 1u })
            for (uint32_t s : { 0u, 1u, 0xFFFFFFFFu }) {
                const float n = chaoslight::noise(s, t);
                if (!(n >= -1.0f && n <= 1.0f)) range = false;
            }
        CHECK(range);
        // different places do not all flicker in step
        int same = 0;
        for (uint32_t t = 0; t < 2000; t += 10)
            if (std::fabs(chaoslight::noise(chaoslight::seedOf(3, 4, 206), t) - chaoslight::noise(chaoslight::seedOf(4, 3, 206), t)) < 0.01f) ++same;
        CHECK(same < 60);
    }

    // ---- flicker on the map: bounded radius, deterministic, off = no time, cold lights steady, seed follows the world tile
    {
        const int S = 32, w = 45, h = 3;
        std::vector<TileLight> tiles(size_t(w) * h, TileLight{ 0, 0 });
        auto lit = [&](const Buf& b, int row) { int n = 0; for (int x = 0; x < w; ++x) if (b[(size_t(row) * w + x) * 4] || b[(size_t(row) * w + x) * 4 + 1] || b[(size_t(row) * w + x) * 4 + 2]) ++n; return n; };
        for (int intensity : { 4, 6, 10, 16 }) {
            std::vector<Light> warm{ Light{ { 22 * S + S / 2, S + S / 2 }, 206, uint8_t(intensity) } };
            chaoslight::Flicker on; on.on = true;
            Buf steady;
            soft(steady, w, h, S, Color(0, 0, 0), warm, tiles, off);
            int minLit = 999, maxLit = 0;
            bool beyond = false;
            Buf first;
            for (uint32_t t = 0; t < 6000; t += 13) {
                on.timeMs = t;
                Buf b, again;
                soft(b, w, h, S, Color(0, 0, 0), warm, tiles, on);
                soft(again, w, h, S, Color(0, 0, 0), warm, tiles, on);
                if (b != again) CHECK(false); // deterministic for the same time and place
                CHECK(guardOk(b, w, h));
                const int n = lit(b, 1);
                minLit = std::min(minLit, n); maxLit = std::max(maxLit, n);
                // radius bound: nothing lit at or beyond intensity * 1.12 tiles
                const float bound = intensity * (1.0f + chaoslight::kAmplitude);
                for (int x = 0; x < w; ++x)
                    if (std::fabs(float(x - 22)) >= bound && (b[(size_t(1) * w + x) * 4] || b[(size_t(1) * w + x) * 4 + 1] || b[(size_t(1) * w + x) * 4 + 2])) beyond = true;
                if (t == 0) first = b;
            }
            CHECK(!beyond);
            CHECK(minLit <= lit(steady, 1) + 1 && maxLit >= lit(steady, 1) - 1);
            if (intensity >= 10) CHECK(maxLit > minLit); // the light changes its size over time
            // off: the time does not matter
            chaoslight::Flicker offT; offT.on = false; offT.timeMs = 987654;
            Buf o2;
            soft(o2, w, h, S, Color(0, 0, 0), warm, tiles, offT);
            CHECK(o2 == steady);
            // a cold (white, blue) light does not flicker with the option on
            for (int cold : { 215, 5, 30 }) {
                std::vector<Light> c{ Light{ { 22 * S + S / 2, S + S / 2 }, uint8_t(cold), uint8_t(intensity) } };
                Buf s0, s1;
                soft(s0, w, h, S, Color(0, 0, 0), c, tiles, off);
                on.timeMs = 777;
                soft(s1, w, h, S, Color(0, 0, 0), c, tiles, on);
                CHECK(s0 == s1);
            }
        }
        // the seed is the world tile: the view moves one tile and the origin moves back, same picture one tile over
        std::vector<Light> a{ Light{ { 10 * S + S / 2, S + S / 2 }, 206, 8 } }, b2{ Light{ { 11 * S + S / 2, S + S / 2 }, 206, 8 } };
        chaoslight::Flicker f1, f2;
        f1.on = f2.on = true; f1.timeMs = f2.timeMs = 4242; f1.originX = 100; f2.originX = 99;
        Buf r1, r2;
        soft(r1, w, h, S, Color(0, 0, 0), a, tiles, f1);
        soft(r2, w, h, S, Color(0, 0, 0), b2, tiles, f2);
        bool shifted = true;
        for (int x = 0; x + 1 < w; ++x)
            for (int c = 0; c < 4; ++c)
                if (r1[(size_t(1) * w + x) * 4 + c] != r2[(size_t(1) * w + x + 1) * 4 + c]) shifted = false;
        CHECK(shifted);
        // sub-tile motion of a light inside one tile keeps its seed (a walking creature changes phase once per tile only)
        CHECK(chaoslight::seedOf(chaoslight::floorDiv(10 * S + 3, S), 1, 206) == chaoslight::seedOf(chaoslight::floorDiv(10 * S + 29, S), 1, 206));
    }

    // ---- edges
    {
        std::vector<Light> none;
        std::vector<TileLight> t(12, TileLight{ 0, 0 });
        Buf b;
        chaoslight::Flicker on; on.on = true; on.timeMs = 5;
        soft(b, 4, 3, 32, Color(10, 20, 30), none, t, on);
        CHECK(guardOk(b, 4, 3) && b[0] == 10 && b[1] == 20 && b[2] == 30 && b[3] == 255);
        std::vector<Light> odd{ Light{ { -20000, 20000 }, 206, 255 }, Light{ { 16, 16 }, 206, 0 }, Light{ { 16, 16 }, 206, 1 }, Light{ { 48, 48 }, 215, 255 } };
        Buf a, c;
        naive(a, 4, 3, 32, Color(10, 20, 30), odd, t, on);
        soft(c, 4, 3, 32, Color(10, 20, 30), odd, t, on);
        CHECK(guardOk(c, 4, 3) && std::equal(a.begin(), a.end(), c.begin()));
    }

    std::printf("%s: %d failure(s)\n", failures ? "FAIL" : "ok", failures);
    return failures ? 1 : 0;
}
