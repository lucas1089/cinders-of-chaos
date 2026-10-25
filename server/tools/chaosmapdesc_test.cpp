// Unit test of src/chaosmapdesc.h (patch 0072, server/README.md "Cheaper map description (O213)").
//   g++ -std=c++17 -O1 -Wall -Wextra -I DIR -I server/tools server/tools/chaosmapdesc_test.cpp -o chaosmapdesc_test
// DIR holds chaosmapdesc.h, cut out of the patch (.github/workflows/ci.yml, step "Map description"). Builds many synthetic
// maps (dense, sparse, one tile per leaf, empty, rows of more than 254 empty tiles, edges of the 16 bit coordinates) and
// compares the bytes of the new describeFloor / a whole description with a copy of the stock loop, for random rectangles,
// floors and offsets (including negative and past 65535, as the engine's uint16_t narrowing), and checks that the quad
// tree is walked once per 8x8 block, not per tile.
#include "chaosmapdesc.h"
#include "mapdesc_world.h"
#include <cstdio>
#include <random>

using namespace world;

static int g_bad = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAILED %s:%d: %s\n", __FILE__, __LINE__, #c); ++g_bad; } } while (0)

static void newFloor(const Map& map, Msg& msg, int32_t x, int32_t y, int32_t z, int32_t w, int32_t h, int32_t off, int32_t& skip)
{
	ChaosMapDesc::describeFloor<Floor>(msg, x, y, z, w, h, off, skip,
		[&map](uint16_t tx, uint16_t ty, uint8_t tz) { return map.getFloorAt(tx, ty, tz); },
		[&msg](const Tile* t) { emitTile(t, msg); });
}

// fills a rectangle of the map with a density of tiles; ground-less and item-less tiles are possible
static void fill(Map& map, std::mt19937& rng, int x0, int y0, int w, int h, int z, int percent)
{
	for (int x = x0; x < x0 + w; ++x) {
		for (int y = y0; y < y0 + h; ++y) {
			if (x < 0 || y < 0 || x > 65535 || y > 65535) { continue; }
			if (int(rng() % 100) >= percent) { continue; }
			Tile* t = new Tile();
			t->ground = rng() % 5 ? uint16_t(1 + rng() % 4000) : 0;
			t->n = uint8_t(rng() % 4);
			t->itemBase = uint8_t(rng());
			map.setTile(uint16_t(x), uint16_t(y), uint8_t(z), t);
		}
	}
}

int main()
{
	std::mt19937 rng(12345);
	long compared = 0;
	for (int round = 0; round < 60; ++round) {
		Map map;
		int density = round % 6 == 0 ? 100 : round % 6 == 1 ? 2 : round % 6 == 2 ? 50 : round % 6 == 3 ? 0 : round % 6 == 4 ? 90 : 15;
		int cx = 31000, cy = 31000;
		if (round % 7 == 3) { cx = 5; cy = 9; }                  // top-left edge
		if (round % 7 == 5) { cx = 65500; cy = 65510; }          // bottom-right edge
		for (int z = 0; z < MAP_MAX_LAYERS; ++z) {
			if (z % 3 == round % 3) { continue; }                 // some floors do not exist
			fill(map, rng, cx - 20, cy - 20, 60, 60, z, density);
		}
		for (int iter = 0; iter < 400; ++iter) {
			int32_t w = 1 + int32_t(rng() % 20), h = 1 + int32_t(rng() % 16);
			if (iter % 50 == 0) { w = 1; h = 300 + int32_t(rng() % 100); } // runs past 254 empty tiles in a column
			int32_t x = cx - 25 + int32_t(rng() % 70), y = cy - 25 + int32_t(rng() % 70);
			int32_t z = int32_t(rng() % 20);                               // 16..19 do not exist
			if (iter % 97 == 0) { z = -1; }
			int32_t off = int32_t(rng() % 9) - 4;
			if (iter % 11 == 0) { x = -3 + int32_t(rng() % 6); y = 65530 + int32_t(rng() % 12); } // wrapping coordinates
			Msg a, b;
			int32_t sa = int32_t(rng() % 3) - 1, sb = sa;                  // a skip carried over from a previous floor
			stockFloor(map, a, x, y, z, w, h, off, sa);
			newFloor(map, b, x, y, z, w, h, off, sb);
			CHECK(a.buf == b.buf);
			CHECK(sa == sb);
			++compared;

			// the whole description, every floor, the trailing skip
			Msg c, d;
			int32_t dw = 1 + int32_t(rng() % 18), dh = 1 + int32_t(rng() % 14);
			int32_t pz = int32_t(rng() % 16);
			mapDescription(c, x, y, pz, dw, dh, [&map](Msg& m, int32_t X, int32_t Y, int32_t Z, int32_t W, int32_t H, int32_t O, int32_t& s) { stockFloor(map, m, X, Y, Z, W, H, O, s); });
			mapDescription(d, x, y, pz, dw, dh, [&map](Msg& m, int32_t X, int32_t Y, int32_t Z, int32_t W, int32_t H, int32_t O, int32_t& s) { newFloor(map, m, X, Y, Z, W, H, O, s); });
			CHECK(c.buf == d.buf);
			++compared;
		}
	}

	// the quad tree is walked once per block: count the lookups on a full 18 x 14 floor
	{
		Map map;
		fill(map, rng, 31000, 31000, 64, 64, 7, 100);
		long lookups = 0;
		Msg m;
		int32_t skip = -1;
		ChaosMapDesc::describeFloor<Floor>(m, 31003, 31003, 7, 18, 14, 0, skip,
			[&](uint16_t tx, uint16_t ty, uint8_t tz) { ++lookups; return map.getFloorAt(tx, ty, tz); },
			[&m](const Tile* t) { emitTile(t, m); });
		CHECK(lookups <= 12);
		CHECK(lookups < 18 * 14 / 16);
		std::printf("lookups for a full 18 x 14 floor: %ld (stock: %d)\n", lookups, 18 * 14);
	}

	std::printf("compared %ld descriptions\n%s\n", compared, g_bad ? "some checks failed" : "ok");
	return g_bad ? 1 : 0;
}
