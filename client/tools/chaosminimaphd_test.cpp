// Unit test of the HD minimap maths (base patch 0197, client/BASE.md "0197").
//   g++ -std=c++17 -I DIR client/tools/chaosminimaphd_test.cpp -o t   (DIR holds chaosminimaphd.h, extracted from the patch)
// Checks: the index parser (good file, CRLF, every kind of bad line, a swatch outside the atlas), compose on a synthetic atlas
// (explored and unexplored tiles, ground swatch, flat colour fallback for an unknown id and for a tile without a recipe, a solid
// swatch alpha over the ground with the boost, a 2 x 2 item that spills up and left across the block edge, water and lava alpha
// codes and tint, the shadow south east of a tall tile and none north west), downscale (flat colour kept, alpha weighted, alpha
// averaged), the zoom to texel density rule, the sub tile walk shift, the least recently used eviction, the version 1 block
// expansion and the liquid weights the shader decodes.
#include "chaosminimaphd.h"
#include <cstdio>
#include <string>
#include <vector>

using namespace chaos::minimaphd;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

// atlas 64 x 64: id 10 grass (opaque green) at 0,0; 11 stone floor (grey) at 8,0; 12 tree (opaque dark green, tall, solid) at 16,0;
// 13 wall piece (half clear, solid, not tall) at 24,0; 14 water ground at 32,0; 15 lava ground at 40,0; 16 2x2 roof (red, solid)
// at 0,16 (16 x 16 px); 17 flower decor (yellow dot on clear) at 48,0
static std::vector<uint8_t> makeAtlas()
{
    std::vector<uint8_t> a(64 * 64 * 4, 0);
    auto fill = [&](int x0, int y0, int w, int h, uint8_t r, uint8_t g, uint8_t b, uint8_t al) {
        for (int y = y0; y < y0 + h; ++y)
            for (int x = x0; x < x0 + w; ++x) {
                uint8_t* p = &a[((size_t)y * 64 + x) * 4];
                p[0] = r; p[1] = g; p[2] = b; p[3] = al;
            }
    };
    fill(0, 0, 8, 8, 40, 160, 40, 255);
    fill(8, 0, 8, 8, 128, 128, 128, 255);
    fill(16, 0, 8, 8, 10, 70, 10, 255);
    fill(24, 0, 8, 8, 200, 180, 150, 128);
    fill(32, 0, 8, 8, 40, 90, 200, 255);
    fill(40, 0, 8, 8, 230, 90, 20, 255);
    fill(0, 16, 16, 16, 180, 30, 30, 255);
    fill(51, 3, 2, 2, 250, 230, 40, 255);
    return a;
}

static const char* kIndex =
    "chaos-minimap-hd 1\r\n"
    "atlas swatches.png 64 64 8 00ff\r\n"
    "10 0 0 11 0\n"
    "11 8 0 11 0\n"
    "12 16 0 11 3\n"
    "13 24 0 11 1\n"
    "14 32 0 11 4\n"
    "15 40 0 11 8\n"
    "16 0 16 22 1\n"
    "17 48 0 11 0\n";

static std::vector<GridTile> emptyGrid()
{
    return std::vector<GridTile>((size_t)kGrid * kGrid);
}
static GridTile& at(std::vector<GridTile>& g, int tx, int ty) { return g[(size_t)(ty + kMargin) * kGrid + (tx + kMargin)]; }

static const uint8_t* px(const std::vector<uint8_t>& out, int x, int y) { return &out[((size_t)y * kFullPx + x) * 4]; }

static void setTile(std::vector<GridTile>& g, int tx, int ty, uint16_t ground, uint16_t border, uint16_t decor, uint16_t solid, uint8_t color)
{
    GridTile& t = at(g, tx, ty);
    t.seen = true;
    t.color = color;
    t.r.ground = ground;
    t.r.border = border;
    t.r.decor = decor;
    t.r.solid = solid;
}

int main()
{
    // ---- index parser
    Atlas atlas;
    std::string err;
    CHECK(atlas.parseIndex(kIndex, err), "good index: %s", err.c_str());
    CHECK(atlas.count() == 8, "8 swatches, got %zu", atlas.count());
    CHECK(!atlas.ready(), "not ready before the pixels");
    CHECK(atlas.find(10) == nullptr, "find before ready gives nothing");
    CHECK(!atlas.setPixels(std::vector<uint8_t>(10), 64, 64), "wrong pixel size refused");
    CHECK(!atlas.setPixels(makeAtlas(), 32, 64), "wrong atlas size refused");
    CHECK(atlas.setPixels(makeAtlas(), 64, 64), "pixels accepted");
    CHECK(atlas.ready() && atlas.width() == 64 && atlas.file() == "swatches.png", "atlas fields");
    CHECK(atlas.find(16) && atlas.find(16)->w == 2 && atlas.find(16)->h == 2, "2x2 swatch");
    CHECK(atlas.flagsOf(12) == (FlagSolid | FlagTall) && atlas.flagsOf(13) == FlagSolid && atlas.flagsOf(14) == FlagWater && atlas.flagsOf(15) == FlagLava, "flags");
    CHECK(atlas.find(0) == nullptr && atlas.find(99) == nullptr, "no swatch for 0 or an unknown id");
    Atlas bad;
    CHECK(!bad.parseIndex("chaos-minimap-hd 2\n", err), "wrong version");
    CHECK(!bad.parseIndex("chaos-minimap-hd 1\natlas a.png 64 64 4 ff\n", err), "wrong cell size");
    CHECK(!bad.parseIndex("chaos-minimap-hd 1\natlas a.png 64 64 8 ff\n10 0 0 1 0\n", err), "size needs two digits");
    CHECK(!bad.parseIndex("chaos-minimap-hd 1\natlas a.png 64 64 8 ff\n10 60 0 11 0\n", err), "swatch outside the atlas");
    CHECK(!bad.parseIndex("chaos-minimap-hd 1\natlas a.png 64 64 8 ff\n70000 0 0 11 0\n", err), "id above 65535");
    CHECK(!bad.parseIndex("chaos-minimap-hd 1\n", err), "no atlas line");
    CHECK(!bad.ready(), "a bad index leaves the atlas unusable");

    // ---- compose
    std::vector<GridTile> g = emptyGrid();
    setTile(g, 1, 1, 10, 0, 0, 0, 255);          // grass
    setTile(g, 2, 1, 99, 0, 0, 0, 36 * 5);       // unknown ground id: flat colour (red cube 180 -> 255,0,0)
    setTile(g, 3, 1, 0, 0, 0, 0, 6 * 5);         // no recipe at all (an old file): flat (0,255,0)
    setTile(g, 4, 1, 10, 0, 17, 0, 255);         // grass with a flower decor
    setTile(g, 5, 1, 10, 0, 0, 13, 255);         // grass with a half clear wall piece: boost 1.55 -> alpha 0.5 * 1.55
    setTile(g, 7, 7, 10, 0, 0, 12, 255);         // a tree (tall)
    setTile(g, 8, 8, 10, 0, 0, 0, 255);          // grass south east of it: shadowed
    setTile(g, 6, 6, 10, 0, 0, 0, 255);          // grass north west of it: not shadowed
    setTile(g, 10, 10, 14, 0, 0, 0, 51);         // water
    setTile(g, 12, 10, 15, 0, 0, 0, 192);        // lava
    setTile(g, 12, 11, 10, 0, 0, 0, 255);        // grass south of the lava: a touch of its glow
    // a 2x2 roof on the first tile of the block's right neighbour column / lower neighbour row: tile (64, 64) is margin
    setTile(g, 63, 63, 10, 0, 0, 0, 255);
    setTile(g, 64, 64, 10, 0, 0, 16, 255);
    std::vector<uint8_t> out((size_t)kFullPx * kFullPx * 4);
    ComposeStats st = composeBlock(atlas, g.data(), out.data());
    CHECK(px(out, 0, 0)[3] == 0, "an unexplored tile stays clear");
    CHECK(px(out, 8 * 1 + 3, 8 * 1 + 3)[3] == 255, "explored tile is opaque");
    // grass (40,160,40) then the 1.10 saturation about the mean: grey 80, r = 80 + (40-80)*1.1 = 36, g = 80 + 80*1.1 = 168
    const uint8_t* gp = px(out, 8 + 3, 8 + 3);
    CHECK(std::abs(gp[0] - 36) <= 1 && std::abs(gp[1] - 168) <= 1 && std::abs(gp[2] - 36) <= 1, "grass swatch colour %d %d %d", gp[0], gp[1], gp[2]);
    const uint8_t* fp = px(out, 16 + 3, 8 + 3);
    CHECK(fp[0] > 200 && fp[1] < 30 && fp[2] < 30, "unknown id falls back to the flat colour %d %d %d", fp[0], fp[1], fp[2]);
    const uint8_t* np = px(out, 24 + 3, 8 + 3);
    CHECK(np[1] > 200 && np[0] < 30, "tile without a recipe is the flat colour %d %d %d", np[0], np[1], np[2]);
    const uint8_t* dp = px(out, 32 + 3, 8 + 3);
    CHECK(dp[0] > 200 && dp[1] > 200 && dp[2] < 120, "flower decor over grass at its pixel %d %d %d", dp[0], dp[1], dp[2]);
    const uint8_t* gp2 = px(out, 32 + 1, 8 + 1);
    CHECK(std::abs(gp2[1] - 168) <= 1, "grass round the flower");
    // the wall piece: alpha 128/255 * 1.55 = 0.778 over grass (40,160,40): r = 40*.222 + 200*.778 = 164.5, before saturation
    const uint8_t* wp = px(out, 40 + 3, 8 + 3);
    CHECK(wp[0] > 150 && wp[0] < 185, "boosted wall piece red %d", wp[0]);
    CHECK(wp[3] == 255, "tile stays opaque");
    // shadow: the grass south east of the tree is darker than the grass north west of it
    const uint8_t* lit = px(out, 6 * 8 + 4, 6 * 8 + 4);
    const uint8_t* dark = px(out, 8 * 8 + 1, 8 * 8 + 1);
    CHECK(dark[1] < lit[1] - 10, "shadow south east: %d against lit %d", dark[1], lit[1]);
    CHECK(std::abs(lit[1] - 168) <= 4, "north west of the tree is lit (only a touch of contact shadow): %d", lit[1]);
    // water and lava
    const uint8_t* wa = px(out, 10 * 8 + 4, 10 * 8 + 4);
    CHECK(wa[3] == kWaterAlpha && wa[2] > wa[0], "water alpha code and blue tint %d %d %d a%d", wa[0], wa[1], wa[2], wa[3]);
    const uint8_t* la = px(out, 12 * 8 + 4, 10 * 8 + 4);
    CHECK(la[3] == kLavaAlpha && la[0] > la[2], "lava alpha code and orange tint");
    const uint8_t* gl = px(out, 12 * 8 + 4, 11 * 8);
    CHECK(gl[3] == 255 && gl[0] > 36 + 8, "lava glow reddens the tile next to it and stays a plain tile (%d a%d)", gl[0], gl[3]);
    // the roof of tile (64, 64): a 2x2 whose bottom right cell is that tile, so it covers tiles 63..64 and spills into (63, 63)
    const uint8_t* rp = px(out, 63 * 8 + 4, 63 * 8 + 4);
    CHECK(rp[0] > 150 && rp[1] < 60, "a roof of the margin tile spills into the block: %d %d %d", rp[0], rp[1], rp[2]);
    CHECK(st.ground >= 8 && st.solid >= 3 && st.tall == 1 && st.water == 1 && st.lava == 1 && st.flat >= 2,
          "stats ground %d solid %d tall %d water %d lava %d flat %d", st.ground, st.solid, st.tall, st.water, st.lava, st.flat);

    // an empty atlas composes flat squares only
    Atlas none;
    std::vector<uint8_t> out2((size_t)kFullPx * kFullPx * 4);
    ComposeStats st2 = composeBlock(none, g.data(), out2.data());
    CHECK(st2.ground == 0 && st2.solid == 0 && st2.tall == 0, "no atlas, no swatches");
    CHECK(px(out2, 8 + 3, 8 + 3)[3] == 255, "no atlas: the tile is still drawn flat");

    // ---- downscale
    std::vector<uint8_t> small(256 * 256 * 4);
    downscale(out.data(), 256, small.data());
    CHECK(small[((size_t)(1 * 4 + 1) * 256 + (1 * 4 + 1)) * 4 + 3] == 255, "downscale keeps alpha of an opaque area");
    CHECK(small[3] == 0, "downscale keeps a clear area clear");
    std::vector<uint8_t> f2(128 * 128 * 4);
    downscale(out.data(), 128, f2.data());
    // one tile of grass is 2 x 2 px of the 128 picture, all the same colour
    int o = ((1 * 2) * 128 + (1 * 2)) * 4;
    CHECK(std::abs(f2[o + 1] - 168) <= 1 && f2[o + 3] == 255, "flat tile stays flat");
    // a partly clear window: a tile edge between explored and not: alpha averages, colour is not dragged to black
    std::vector<uint8_t> half((size_t)kFullPx * kFullPx * 4, 0);
    for (int y = 0; y < kFullPx; ++y)
        for (int x = 0; x < 4; ++x) {
            uint8_t* p = &half[((size_t)y * kFullPx + x) * 4];
            p[0] = 200; p[1] = 100; p[2] = 50; p[3] = 255;
        }
    std::vector<uint8_t> h2(128 * 128 * 4);
    downscale(half.data(), 128, h2.data());
    CHECK(h2[0] == 200 && h2[1] == 100 && h2[3] == 255, "fully covered texel");
    std::vector<uint8_t> half2((size_t)kFullPx * kFullPx * 4, 0);
    for (int y = 0; y < kFullPx; ++y)
        for (int x = 0; x < 2; ++x) {
            uint8_t* p = &half2[((size_t)y * kFullPx + x) * 4];
            p[0] = 200; p[1] = 100; p[2] = 50; p[3] = 255;
        }
    downscale(half2.data(), 128, h2.data());
    CHECK(h2[0] == 200 && h2[1] == 100 && h2[3] == 128, "half covered texel: colour kept, alpha halves (%d %d a%d)", h2[0], h2[1], h2[3]);

    // ---- zoom rules
    CHECK(lodFor(1.0f, 2.0f) == 0 && lodFor(0.5f, 2.0f) == 0, "scale 1 draws the flat map");
    CHECK(lodFor(2.0f, 2.0f) == 2 && lodFor(3.0f, 2.0f) == 2, "scale 2 gives 2 px per tile");
    CHECK(lodFor(4.0f, 2.0f) == 4 && lodFor(7.0f, 2.0f) == 4, "scale 4 gives 4");
    CHECK(lodFor(8.0f, 2.0f) == 8 && lodFor(32.0f, 2.0f) == 8, "scale 8 and up give 8");
    CHECK(lodFor(2.0f, 4.0f) == 0 && lodFor(4.0f, 4.0f) == 4, "a higher minimum scale turns HD off below it");
    CHECK(subTile(0, 32) == 0.0f && subTile(-16, 32) == -0.5f && subTile(-64, 32) == -1.0f && subTile(5, 0) == 0.0f, "sub tile shift");

    // ---- eviction
    std::vector<uint64_t> stamps = {5, 0, 3, 9, 9, 1};
    std::vector<size_t> drop = evictOldest(stamps, 9, 3);
    CHECK(drop.size() == 2 && drop[0] == 5 && drop[1] == 2, "evict the two oldest of five held (got %zu)", drop.size());
    CHECK(evictOldest(stamps, 9, 5).empty(), "nothing to drop within the limit");
    std::vector<uint64_t> allNow = {9, 9, 9};
    CHECK(evictOldest(allNow, 9, 1).empty(), "pictures used this frame are never dropped");

    // ---- version 1 expansion
    std::vector<uint8_t> v1(kBlockTiles * kBlockTiles * kTileBytesV1);
    for (size_t i = 0; i < v1.size(); ++i)
        v1[i] = (uint8_t)(i * 7 + 1);
    std::vector<uint8_t> v2(kBlockTiles * kBlockTiles * kTileBytesV2, 0xEE);
    expandV1Block(v1.data(), v2.data());
    bool same = true;
    for (int i = 0; i < kBlockTiles * kBlockTiles; ++i) {
        for (int k = 0; k < 3; ++k)
            same = same && v2[(size_t)i * kTileBytesV2 + k] == v1[(size_t)i * kTileBytesV1 + k];
        for (int k = 3; k < kTileBytesV2; ++k)
            same = same && v2[(size_t)i * kTileBytesV2 + k] == 0;
    }
    CHECK(same, "v1 block expands to the old bytes and a clear recipe");

    // ---- liquid weights the shader decodes
    float w, l;
    liquidWeights(1.0f, w, l);
    CHECK(w == 0 && l == 0, "plain tile has no liquid");
    liquidWeights(kWaterAlpha / 255.0f, w, l);
    CHECK(w > 0.9f && l == 0.0f, "water code reads as water (%f %f)", w, l);
    liquidWeights(kLavaAlpha / 255.0f, w, l);
    CHECK(l > 0.9f && w < 0.1f, "lava code reads as lava (%f %f)", w, l);
    liquidWeights(0.98f, w, l);
    CHECK(w > 0.4f && w < 0.6f && l == 0.0f, "half way to water is a weaker effect");
    liquidWeights(0.5f, w, l);
    CHECK(w == 0 && l == 0, "the explored edge is no liquid");

    if (failures) { std::printf("%d failure(s)\n", failures); return 1; }
    std::printf("chaosminimaphd_test: all passed\n");
    return 0;
}
