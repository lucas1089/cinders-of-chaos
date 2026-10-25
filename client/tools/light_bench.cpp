// Offline benchmark of the light map fill (base patch 0140, client/BASE.md "0140").
//   g++ -std=c++17 -O2 -I DIR -I client/tools client/tools/light_bench.cpp -o light_bench   (DIR holds chaoslightfill.h)
//   light_bench [--seconds N] [--check]
// Old path: the per-tile loop of LightView::draw, every tile against every light added after its floor started
// (chaoslight_ref.h, transcribed from the base client). New path: chaoslight::fill, light by light over the tiles each light
// reaches. Same inputs, same buffer; the buffers are compared byte for byte on every frame that is timed. The upload of the
// texture and the quad (identical after the patch) are not part of either side.
// Scenarios (map in tiles, lights per frame; intensities as the game gives them: most 2..6 from items, creatures and loot
// beams, some 6..10 from spell effects and a few strong ones; 30% of the tiles start after the first third of the list, as
// the tiles of an upper floor do):
//   small   19x15 map,  40 lights   a quiet screen
//   hunt    31x23 map, 150 lights   a busy hunt, wide screen
//   packed  31x23 map, 400 lights   a boss fight with many spell lights
//   wide    55x41 map, 250 lights   a 4K screen, zoomed out
// --check (CI): exit 1 on a buffer difference or when a scenario is under 1.5x faster than the old loop.
#include "chaoslightfill.h"
#include "chaoslight_ref.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>

using namespace reflight;
using Clock = std::chrono::steady_clock;

struct Scenario { const char* name; int w, h, lights; };

static void newFill(std::vector<uint8_t>& out, int w, int h, int S, const Color& g, const std::vector<Light>& lights,
                    const std::vector<TileLight>& tiles)
{
    chaoslight::fill(out.data(), w, h, S, g.r(), g.g(), g.b(), lights.data(), lights.size(), tiles.data(),
                     [](const Light& l) { return Color::from8bit(l.color); },
                     [](const Color& base, float k, int* rgb) {
                         const Color c = base * k;
                         rgb[0] = c.r(); rgb[1] = c.g(); rgb[2] = c.b();
                     });
}

int main(int argc, char** argv)
{
    double seconds = 0.5;
    bool check = false;
    for (int i = 1; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--check")) check = true;
        else if (!std::strcmp(argv[i], "--seconds") && i + 1 < argc) seconds = std::atof(argv[++i]);
    }
    const Scenario scenarios[] = { { "small", 19, 15, 40 }, { "hunt", 31, 23, 150 }, { "packed", 31, 23, 400 }, { "wide", 55, 41, 250 } };
    const int S = 32;
    int bad = 0;
    std::printf("%-8s %12s %12s %8s\n", "scenario", "stock us/fr", "reach us/fr", "ratio");
    for (const Scenario& sc : scenarios) {
        std::mt19937 rng(222);
        auto rnd = [&](int lo, int hi) { return std::uniform_int_distribution<int>(lo, hi)(rng); };
        const int frames = 64; // different light lists, repeated
        std::vector<std::vector<Light>> lightSets(frames);
        std::vector<std::vector<TileLight>> tileSets(frames);
        for (int f = 0; f < frames; ++f) {
            for (int i = 0; i < sc.lights; ++i) {
                Light l;
                l.pos.x = rnd(-S, sc.w * S + S);
                l.pos.y = rnd(-S, sc.h * S + S);
                l.color = uint8_t(rnd(1, 215));
                const int k = rnd(0, 9);
                l.intensity = uint8_t(k < 6 ? rnd(2, 6) : k < 9 ? rnd(6, 10) : rnd(10, 18));
                lightSets[f].push_back(l);
            }
            tileSets[f].assign(size_t(sc.w) * sc.h, TileLight{ 0, 0 });
            for (auto& t : tileSets[f]) t.start = rnd(0, 9) < 3 ? size_t(sc.lights / 3) : 0;
        }
        const Color global = Color::from8bit(36) * 0.4f; // a dark ambient
        std::vector<uint8_t> a(size_t(sc.w) * sc.h * 4), b(size_t(sc.w) * sc.h * 4);
        double bestOld = 1e18, bestNew = 1e18;
        bool same = true;
        double spent = 0;
        for (int round = 0; round < 8 || spent < seconds * 1000; ++round) {
            auto t0 = Clock::now();
            uint64_t sa = 0, sb = 0;
            for (int f = 0; f < frames; ++f) { stockFill(a, sc.w, sc.h, S, global, lightSets[f], tileSets[f]); sa += a[(f * 37) % a.size()]; }
            auto t1 = Clock::now();
            for (int f = 0; f < frames; ++f) { newFill(b, sc.w, sc.h, S, global, lightSets[f], tileSets[f]); sb += b[(f * 37) % b.size()]; }
            auto t2 = Clock::now();
            const double ms0 = std::chrono::duration<double, std::milli>(t1 - t0).count();
            const double ms1 = std::chrono::duration<double, std::milli>(t2 - t1).count();
            bestOld = std::min(bestOld, ms0);
            bestNew = std::min(bestNew, ms1);
            spent += ms0 + ms1;
            if (sa != sb) same = false;
            // full compare of the last frame of the round, and of every frame in the first round
            for (int f = (round == 0 ? 0 : frames - 1); f < frames; ++f) {
                stockFill(a, sc.w, sc.h, S, global, lightSets[f], tileSets[f]);
                newFill(b, sc.w, sc.h, S, global, lightSets[f], tileSets[f]);
                if (std::memcmp(a.data(), b.data(), a.size()) != 0) same = false;
            }
            if (round >= 40) break;
        }
        const double ratio = bestOld / bestNew;
        std::printf("%-8s %12.2f %12.2f %7.2fx  %s\n", sc.name, bestOld * 1000 / frames, bestNew * 1000 / frames, ratio,
                    same ? "same buffer" : "BUFFERS DIFFER");
        if (!same) ++bad;
        if (check && ratio < 1.5) { std::printf("  below 1.5x\n"); ++bad; }
    }
    if (bad) { std::printf("FAIL\n"); return 1; }
    std::printf("ok\n");
    return 0;
}
