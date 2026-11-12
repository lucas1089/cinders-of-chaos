// Unit test of the HD sprite overlay maths (base patch 0196, client/BASE.md "0196").
//   g++ -std=c++17 -I DIR client/tools/chaoshdoverlay_test.cpp -o t   (DIR holds chaoshdoverlay.h, extracted from the patch)
// Checks: crc32 against the known vector, the index parser (good file, comments, CRLF, every kind of bad line, an atlas that
// is not declared, a repeated sprite), cropTile bounds, and resample: same size is a copy, 2x down is the mean of 2 x 2 with
// colour weighted by alpha (a clear pixel does not tint an edge), 4x down, a fractional ratio keeps the total and a flat
// colour, up is nearest, an empty tile stays empty.
#include "chaoshdoverlay.h"
#include <cstdio>
#include <string>
#include <vector>

using namespace chaos::hdoverlay;

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { ++failures; std::printf("FAIL line %d: %s  ", __LINE__, #cond); std::printf(__VA_ARGS__); std::printf("\n"); } } while (0)

static std::vector<uint8_t> flat(int size, uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    std::vector<uint8_t> v(static_cast<size_t>(size) * size * 4);
    for (size_t i = 0; i < v.size(); i += 4) { v[i] = r; v[i + 1] = g; v[i + 2] = b; v[i + 3] = a; }
    return v;
}

int main()
{
    // crc32 of "123456789" is cbf43926
    const char* s = "123456789";
    CHECK(crc32(reinterpret_cast<const uint8_t*>(s), 9) == 0xCBF43926u, "crc vector");
    CHECK(crc32(nullptr, 0) == 0, "crc of nothing");

    // a good index
    const std::string good =
        "# made by gen_hd_overlay.py\n"
        "chaos-hd-overlay 1\r\n"
        "\n"
        "atlas 0 hd_0.png\n"
        "atlas 1 hd_1.png\n"
        "sprite 815931 0 0 0 2 deadbeef\n"
        "sprite 815932 0 64 0 2 00000000\n"
        "sprite 4000000000 1 128 64 4 0000ABCD\n"
        "slot 1 3019 57 0 0 192 0 2\n"
        "slot 1 3019 58 815931 1 0 64 4\n";
    Index idx = parseIndex(good);
    CHECK(idx.ok(), "good index: %s", idx.error.c_str());
    CHECK(idx.atlases.size() == 2 && idx.atlases[1] == "hd_1.png", "atlases");
    CHECK(idx.sprites.size() == 3, "3 sprites, got %zu", idx.sprites.size());
    CHECK(idx.sprites.count(815931) && idx.sprites[815931].crc == 0xDEADBEEFu && idx.sprites[815931].scale == 2, "first entry");
    CHECK(idx.sprites[815932].x == 64 && idx.sprites[815932].crc == 0, "second entry");
    CHECK(idx.sprites[4000000000u].atlas == 1 && idx.sprites[4000000000u].y == 64 && idx.sprites[4000000000u].scale == 4 &&
              idx.sprites[4000000000u].crc == 0xABCDu, "u32 id, atlas 1, scale 4");

    CHECK(idx.slots.size() == 2, "2 slots, got %zu", idx.slots.size());
    {
        auto it = idx.slots.find(slotKey(1, 3019, 57));
        CHECK(it != idx.slots.end() && it->second.sprite == 0 && it->second.tile.x == 192 && it->second.tile.scale == 2, "slot of a place with no sprite");
        auto it2 = idx.slots.find(slotKey(1, 3019, 58));
        CHECK(it2 != idx.slots.end() && it2->second.sprite == 815931u && it2->second.tile.atlas == 1 && it2->second.tile.scale == 4, "slot with a sprite and a 4x tile");
        CHECK(idx.slots.find(slotKey(1, 3019, 59)) == idx.slots.end() && idx.slots.find(slotKey(2, 3019, 57)) == idx.slots.end() &&
                  idx.slots.find(slotKey(1, 3020, 57)) == idx.slots.end(), "other places have no slot");
        CHECK(slotKey(1, 2, 3) != slotKey(1, 3, 2) && slotKey(0, 65535, 65535) != slotKey(1, 0, 0), "slot keys differ");
    }

    // a later line for the same id wins
    Index twice = parseIndex("chaos-hd-overlay 1\natlas 0 a.png\nsprite 5 0 0 0 2 00000001\nsprite 5 0 64 0 2 00000002\n");
    CHECK(twice.ok() && twice.sprites.size() == 1 && twice.sprites[5].x == 64, "repeated id");

    // bad files
    const char* bad[] = {
        "",                                                        // empty
        "# only a comment\n",                                      // no header
        "chaos-hd-overlay 2\n",                                    // other version
        "atlas 0 a.png\n",                                         // no header first
        "chaos-hd-overlay 1\natlas 1 a.png\n",                     // atlas numbers must count from 0
        "chaos-hd-overlay 1\natlas 0 ../a.png\n",                  // path out of the folder
        "chaos-hd-overlay 1\natlas 0 sub/a.png\n",                 // subfolder
        "chaos-hd-overlay 1\natlas 0 .hidden.png\n",
        "chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 1 0 0 2 00000000\n",   // atlas not declared
        "chaos-hd-overlay 1\natlas 0 a.png\nsprite 0 0 0 0 2 00000000\n",   // id 0
        "chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 0 00000000\n",   // scale 0
        "chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 9 00000000\n",   // scale over the cap
        "chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 2 0\n",          // crc not 8 digits
        "chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 2 0000000g\n",   // crc not hex
        "chaos-hd-overlay 1\natlas 0 a.png\nsprite -1 0 0 0 2 00000000\n",  // negative
        "chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 70000 0 2 00000000\n", // x over u16
        "chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 2\n",            // short line
        "chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 2 00000000 x\n", // long line
        "chaos-hd-overlay 1\nwhat 1\n",                                    // unknown record
        "chaos-hd-overlay 1\natlas 0 a.png\nslot 1 5 0 0 1 0 0 2\n",          // slot atlas not declared
        "chaos-hd-overlay 1\natlas 0 a.png\nslot 4 5 0 0 0 0 0 2\n",          // category 4
        "chaos-hd-overlay 1\natlas 0 a.png\nslot 1 0 0 0 0 0 0 2\n",          // thing 0
        "chaos-hd-overlay 1\natlas 0 a.png\nslot 1 5 70000 0 0 0 0 2\n",      // index over u16
        "chaos-hd-overlay 1\natlas 0 a.png\nslot 1 5 0 0 0 0 0 0\n",          // scale 0
        "chaos-hd-overlay 1\natlas 0 a.png\nslot 1 5 0 0 0 0 0\n",            // short line
        "chaos-hd-overlay 1\natlas 0 a.png\nslot 1 5 0 0 0 0 0 2 1\n",        // long line
    };
    for (const char* b : bad) {
        Index r = parseIndex(b);
        CHECK(!r.ok(), "bad index accepted: %s", b);
    }
    // what came before the bad line stays, the error names the line
    Index partial = parseIndex("chaos-hd-overlay 1\natlas 0 a.png\nsprite 1 0 0 0 2 00000000\nsprite x\n");
    CHECK(!partial.ok() && partial.sprites.size() == 1 && partial.error.find("line 4") == 0, "partial: %s", partial.error.c_str());

    // cropTile
    std::vector<uint8_t> atlas(8 * 8 * 4);
    for (int y = 0; y < 8; ++y)
        for (int x = 0; x < 8; ++x) {
            uint8_t* p = &atlas[(static_cast<size_t>(y) * 8 + x) * 4];
            p[0] = static_cast<uint8_t>(x); p[1] = static_cast<uint8_t>(y); p[2] = 7; p[3] = 255;
        }
    std::vector<uint8_t> tile;
    CHECK(cropTile(atlas.data(), 8, 8, 4, 2, 4, tile) && tile.size() == 64, "crop inside");
    CHECK(tile[0] == 4 && tile[1] == 2 && tile[(3 * 4 + 3) * 4] == 7 && tile[(3 * 4 + 3) * 4 + 1] == 5, "crop corners");
    CHECK(!cropTile(atlas.data(), 8, 8, 5, 0, 4, tile), "crop past the right edge");
    CHECK(!cropTile(atlas.data(), 8, 8, 0, 5, 4, tile), "crop past the bottom");
    CHECK(!cropTile(atlas.data(), 8, 8, -1, 0, 4, tile), "crop negative");
    CHECK(!cropTile(atlas.data(), 8, 8, 0, 0, 0, tile), "crop of nothing");
    CHECK(!cropTile(nullptr, 8, 8, 0, 0, 4, tile), "crop of no atlas");
    CHECK(cropTile(atlas.data(), 8, 8, 4, 4, 4, tile), "crop exactly at the corner");

    // resample
    std::vector<uint8_t> out;
    std::vector<uint8_t> a64 = flat(64, 10, 20, 30, 255);
    resample(a64.data(), 64, out, 64);
    CHECK(out == a64, "same size is a copy");
    resample(a64.data(), 64, out, 32);
    CHECK(out.size() == 32 * 32 * 4 && out == flat(32, 10, 20, 30, 255), "flat 2x down");
    resample(a64.data(), 64, out, 16);
    CHECK(out == flat(16, 10, 20, 30, 255), "flat 4x down");
    resample(a64.data(), 64, out, 48);
    CHECK(out == flat(48, 10, 20, 30, 255), "flat fractional down");
    resample(a64.data(), 64, out, 128);
    CHECK(out.size() == 128 * 128 * 4 && out == flat(128, 10, 20, 30, 255), "flat up");

    // a 2 x 2 block of (red, clear, green, blue) averaged to one pixel: alpha 3/4, colour weighted by alpha, not tinted by the clear one
    uint8_t quad[2 * 2 * 4] = { 200, 0, 0, 255,   99, 99, 99, 0,
                                0, 200, 0, 255,   0, 0, 200, 255 };
    resample(quad, 2, out, 1);
    CHECK(out.size() == 4 && out[3] == 191, "alpha 3/4, got %d", out[3]);
    CHECK(out[0] == 67 && out[1] == 67 && out[2] == 67, "colour mean of the three opaque, got %d %d %d", out[0], out[1], out[2]);
    // all clear stays clear (and black, no stray colour)
    std::vector<uint8_t> clear = flat(4, 9, 9, 9, 0);
    resample(clear.data(), 4, out, 2);
    CHECK(out == flat(2, 0, 0, 0, 0), "clear stays clear");

    // up is nearest: each source pixel becomes a 2 x 2 block, edges hard
    uint8_t two[2 * 2 * 4] = { 1, 1, 1, 255,   2, 2, 2, 255,
                               3, 3, 3, 255,   4, 4, 4, 0 };
    resample(two, 2, out, 4);
    CHECK(out[0] == 1 && out[4] == 1 && out[8] == 2 && out[12] == 2, "up row 0");
    CHECK(out[(2 * 4 + 0) * 4] == 3 && out[(3 * 4 + 3) * 4 + 3] == 0 && out[(2 * 4 + 2) * 4 + 3] == 0, "up row 2 and 3");

    // 64 -> 32 of a sharp vertical edge keeps a hard column pair: left half opaque white, right half clear
    std::vector<uint8_t> edge(64 * 64 * 4, 0);
    for (int y = 0; y < 64; ++y)
        for (int x = 0; x < 32; ++x) { uint8_t* p = &edge[(static_cast<size_t>(y) * 64 + x) * 4]; p[0] = p[1] = p[2] = 255; p[3] = 255; }
    resample(edge.data(), 64, out, 32);
    CHECK(out[(5 * 32 + 15) * 4 + 3] == 255 && out[(5 * 32 + 16) * 4 + 3] == 0, "edge stays on the pixel boundary");

    // crc of the 32 x 32 RGBA run: one changed byte changes the crc
    std::vector<uint8_t> sp = flat(32, 1, 2, 3, 255);
    uint32_t c0 = crc32(sp.data(), sp.size());
    sp[1000] ^= 1;
    CHECK(crc32(sp.data(), sp.size()) != c0, "crc sees one byte");

    // spriteCrc: same as crc32 of the bytes when nothing is clear; the colour under alpha 0 does not count
    std::vector<uint8_t> op = flat(32, 5, 6, 7, 255);
    CHECK(spriteCrc(op.data(), 32 * 32) == crc32(op.data(), op.size()), "opaque sprite crc is the plain crc");
    std::vector<uint8_t> t1 = flat(32, 5, 6, 7, 0);
    std::vector<uint8_t> t2 = flat(32, 200, 100, 50, 0);
    CHECK(spriteCrc(t1.data(), 1024) == spriteCrc(t2.data(), 1024), "colour under alpha 0 is ignored");
    CHECK(spriteCrc(t1.data(), 1024) == crc32(flat(32, 0, 0, 0, 0).data(), 4096), "clear is zero bytes");
    t2[3] = 255;
    CHECK(spriteCrc(t1.data(), 1024) != spriteCrc(t2.data(), 1024), "one opaque pixel counts");

    if (failures) { std::printf("%d failure(s)\n", failures); return 1; }
    std::printf("chaoshdoverlay_test: all passed\n");
    return 0;
}
