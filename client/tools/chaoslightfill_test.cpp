// Unit test of the light map fill (base patch 0140, client/BASE.md "0140").
//   g++ -std=c++17 -I DIR client/tools/chaoslightfill_test.cpp -o t   (DIR holds chaoslightfill.h, extracted from the patch)
// Random maps (sizes, sprite sizes), random light lists (positions inside, at the border and far outside the map, every
// intensity 0..255, every colour byte, duplicates of one place) and random tile starts: the buffer of chaoslight::fill must
// equal the buffer of the stock per-tile loop (chaoslight_ref.h) byte for byte, alpha included. Also the edge cases of the
// reach box (negative coordinates, a light on a tile centre, intensity 0, an empty light list) and a guard around the buffer.
#include "chaoslightfill.h"
#include "chaoslight_ref.h"
#include <cstdio>
#include <cstdlib>
#include <random>

using namespace reflight;

static int failures = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL line %d: %s\n", __LINE__, #c); ++failures; } } while (0)

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

static bool sameAsStock(int w, int h, int S, const Color& g, const std::vector<Light>& lights, const std::vector<TileLight>& tiles)
{
    std::vector<uint8_t> a, b(size_t(w) * h * 4 + 8, 0xAB); // 8 guard bytes behind the buffer
    stockFill(a, w, h, S, g, lights, tiles);
    newFill(b, w, h, S, g, lights, tiles);
    for (int i = 0; i < 8; ++i)
        if (b[size_t(w) * h * 4 + i] != 0xAB) return false;
    return std::equal(a.begin(), a.begin() + size_t(w) * h * 4, b.begin());
}

int main()
{
    std::mt19937 rng(222);
    auto rnd = [&](int lo, int hi) { return std::uniform_int_distribution<int>(lo, hi)(rng); };
    const int sprite[] = { 16, 32, 48, 64 };
    long cases = 0, pairs = 0;
    for (int iter = 0; iter < 3000; ++iter) {
        const int S = sprite[rnd(0, 3)];
        const int w = rnd(1, 45), h = rnd(1, 35);
        const int count = rnd(0, iter % 7 == 0 ? 600 : 120);
        std::vector<Light> lights;
        for (int i = 0; i < count; ++i) {
            Light l;
            const int mode = rnd(0, 5);
            if (mode == 0) { l.pos.x = rnd(-3000, w * S + 3000); l.pos.y = rnd(-3000, h * S + 3000); }
            else if (mode == 1) { l.pos.x = rnd(0, w) * S + S / 2; l.pos.y = rnd(0, h) * S + S / 2; } // on a tile centre
            else if (mode == 2 && !lights.empty()) { l = lights.back(); l.color = uint8_t(rnd(0, 255)); }
            else { l.pos.x = rnd(-S, w * S + S); l.pos.y = rnd(-S, h * S + S); }
            l.color = uint8_t(rnd(0, 255));
            const int im = rnd(0, 3);
            l.intensity = uint8_t(im == 0 ? rnd(0, 255) : im == 1 ? rnd(0, 3) : rnd(0, 12));
            lights.push_back(l);
        }
        std::vector<TileLight> tiles(size_t(w) * h, TileLight{ 0, 0 });
        for (auto& t : tiles) t.start = rnd(0, 3) == 0 ? size_t(rnd(0, count + 2)) : (rnd(0, 2) ? 0 : size_t(count / 2));
        const Color g = Color::from8bit(rnd(0, 255)) * (rnd(0, 255) / 255.0f);
        ++cases;
        pairs += long(count) * w * h;
        if (!sameAsStock(w, h, S, g, lights, tiles)) {
            std::printf("MISMATCH iter %d (map %dx%d, sprite %d, %d lights)\n", iter, w, h, S, count);
            ++failures;
            if (failures > 5) return 1;
        }
    }
    // edges
    {
        std::vector<Light> none;
        std::vector<TileLight> t(12, TileLight{ 0, 0 });
        CHECK(sameAsStock(4, 3, 32, Color(10, 20, 30), none, t));
        std::vector<Light> far{ Light{ { -20000, 20000 }, 100, 255 }, Light{ { 16, 16 }, 100, 0 }, Light{ { 16, 16 }, 100, 1 } };
        CHECK(sameAsStock(4, 3, 32, Color(10, 20, 30), far, t));
        std::vector<Light> big{ Light{ { 48, 48 }, 215, 255 }, Light{ { 48, 48 }, 36, 255 } };
        CHECK(sameAsStock(4, 3, 32, Color(0, 0, 0), big, t));
        CHECK(chaoslight::floorDiv(-1, 32) == -1 && chaoslight::floorDiv(-32, 32) == -1 && chaoslight::floorDiv(-33, 32) == -2);
        CHECK(chaoslight::floorDiv(0, 32) == 0 && chaoslight::floorDiv(31, 32) == 0 && chaoslight::floorDiv(32, 32) == 1);
        CHECK(chaoslight::reach(-5000, 0, 3, 32, 10, 10).empty());
    }
    std::printf("%s: %ld random maps, %ld light/tile pairs compared, %d failure(s)\n", failures ? "FAIL" : "ok", cases, pairs, failures);
    return failures ? 1 : 0;
}
