// Unit test of src/chaosstrip.h (patch 0076, server/README.md "Cheaper walk map refresh (O225)").
//   g++ -std=c++17 -O1 -Wall -Wextra -I DIR -I server/tools server/tools/chaosstrip_test.cpp -o chaosstrip_test
// DIR holds chaosstrip.h, cut out of the patch (.github/workflows/ci.yml, step "Walk map refresh"). Builds many synthetic
// maps (dense, sparse, empty, floors that do not exist, the edges of the 16 bit coordinates) and compares what the stock
// refresh reads, Map::getTile for each tile, with TileReader::at: the edge refresh of every direction of a step (a column
// of 25, a row of 33), the full grid of updateMapCache, other floors, floors out of range, positions that wrap past 16
// bits. Also checks the quad tree is walked once per 8x8 block, and that a tile set after a read is seen by the next
// reader (nothing is kept between refreshes).
#include "chaosstrip.h"
#include "sight_world.h"
#include <cstdio>
#include <random>

using namespace world;

static int g_bad = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAILED %s:%d: %s\n", __FILE__, __LINE__, #c); ++g_bad; } } while (0)

constexpr int W = 16, H = 12; // maxWalkCacheWidth / Height: Map::maxViewportX 16, maxViewportY 12 (a grid of 33 x 25)

static void fill(Map& map, std::mt19937& rng, int x0, int y0, int w, int h, int z, int percent)
{
	for (int x = x0; x < x0 + w; ++x) {
		for (int y = y0; y < y0 + h; ++y) {
			if (x < 0 || y < 0 || x > 65535 || y > 65535) { continue; }
			if (int(rng() % 100) >= percent) { continue; }
			Tile* t = new Tile();
			t->ground = uint16_t(1 + rng() % 4000);
			t->n = uint8_t(rng() % 4);
			map.setTile(uint16_t(x), uint16_t(y), uint8_t(z), t);
		}
	}
}

struct Counter {
	const Map& map;
	long* walks;
	const Floor* operator()(uint16_t x, uint16_t y, uint8_t z) const { if (walks) { ++*walks; } return map.getFloorAt(x, y, z); }
};

int main()
{
	std::mt19937 rng(225);
	long compared = 0;
	for (int round = 0; round < 60; ++round) {
		Map map;
		int density = round % 6 == 0 ? 100 : round % 6 == 1 ? 3 : round % 6 == 2 ? 50 : round % 6 == 3 ? 0 : round % 6 == 4 ? 90 : 20;
		int cx = 31000, cy = 31000;
		if (round % 7 == 3) { cx = 5; cy = 8; }                // top-left edge: x - W wraps below 0
		if (round % 7 == 5) { cx = 65530; cy = 65530; }        // bottom-right edge: x + W wraps past 65535
		for (int z = 0; z < MAP_MAX_LAYERS; ++z) {
			if (z % 3 == round % 3) { continue; }               // some floors do not exist
			fill(map, rng, cx - 40, cy - 40, 90, 90, z, density);
		}
		for (int iter = 0; iter < 300; ++iter) {
			int px = cx - 30 + int(rng() % 60), py = cy - 30 + int(rng() % 60);
			uint8_t z = uint8_t(rng() % 18); // 16 and 17 are out of range
			Counter counter{map, nullptr};
			auto reader = ChaosStrip::makeReader<Floor, Tile>(counter);
			auto stock = [&](int x, int y) { return map.getTile(uint16_t(x), uint16_t(y), z); };

			switch (iter % 5) {
				case 0: // north / south edge: a row
					for (int x = -W; x <= W; ++x) { CHECK(reader.at(px + x, py - H, z) == stock(px + x, py - H)); ++compared; }
					break;
				case 1: // east edge: a column
					for (int y = -H; y <= H; ++y) { CHECK(reader.at(px + W, py + y, z) == stock(px + W, py + y)); ++compared; }
					break;
				case 2: // west edge, going down
					for (int y = H; y >= -H; --y) { CHECK(reader.at(px - W, py + y, z) == stock(px - W, py + y)); ++compared; }
					break;
				case 3: // the full grid of updateMapCache, row by row
					for (int y = -H; y <= H; ++y) { for (int x = -W; x <= W; ++x) { CHECK(reader.at(px + x, py + y, z) == stock(px + x, py + y)); ++compared; } }
					break;
				default: // random reads: a block change in any order
					for (int i = 0; i < 80; ++i) {
						int x = px + int(rng() % 41) - 20, y = py + int(rng() % 41) - 20;
						CHECK(reader.at(x, y, z) == stock(x, y)); ++compared;
					}
					break;
			}
		}
	}

	// ints that do not fit 16 bits are narrowed as the stock call narrowed them
	{
		Map map;
		fill(map, rng, 0, 0, 40, 40, 7, 100);
		fill(map, rng, 65500, 65500, 36, 36, 7, 100);
		Counter counter{map, nullptr};
		auto reader = ChaosStrip::makeReader<Floor, Tile>(counter);
		for (int x = -20; x < 60; ++x) { for (int y = -20; y < 60; ++y) { CHECK(reader.at(x, y, 7) == map.getTile(uint16_t(x), uint16_t(y), 7)); } }
		for (int x = 65500; x < 65600; ++x) { CHECK(reader.at(x, 65510, 7) == map.getTile(uint16_t(x), uint16_t(65510), 7)); }
		CHECK(reader.at(10, 10, 7 + 256) == map.getTile(10, 10, 7)); // z narrowed to 8 bits
	}

	// the quad tree is walked once per block, not per tile
	{
		Map map;
		fill(map, rng, 31000, 31000, 64, 64, 7, 100);
		long walks = 0;
		Counter counter{map, &walks};
		auto reader = ChaosStrip::makeReader<Floor, Tile>(counter);
		for (int y = 31010; y < 31035; ++y) { (void)reader.at(31020, y, 7); }
		std::printf("walks for a column of 25 tiles: %ld (stock: 25)\n", walks);
		CHECK(walks >= 1 && walks <= 4);
		walks = 0;
		auto reader2 = ChaosStrip::makeReader<Floor, Tile>(counter);
		for (int x = 31010; x < 31043; ++x) { (void)reader2.at(x, 31020, 7); }
		std::printf("walks for a row of 33 tiles: %ld (stock: 33)\n", walks);
		CHECK(walks >= 1 && walks <= 5);
		walks = 0;
		auto reader3 = ChaosStrip::makeReader<Floor, Tile>(counter);
		for (int y = 31010; y < 31035; ++y) { for (int x = 31010; x < 31043; ++x) { (void)reader3.at(x, y, 7); } }
		std::printf("walks for the grid of 33 x 25 tiles: %ld (stock: 825)\n", walks);
		CHECK(walks <= 5 * 25);
	}

	// nothing is kept between refreshes: a tile or floor added after a read is seen by the next reader
	{
		Map map;
		fill(map, rng, 31000, 31000, 32, 32, 7, 100);
		Counter counter{map, nullptr};
		{
			auto reader = ChaosStrip::makeReader<Floor, Tile>(counter);
			CHECK(reader.at(31010, 31010, 6) == nullptr);
		}
		Tile* t = new Tile();
		map.setTile(31010, 31010, 6, t);
		{
			auto reader = ChaosStrip::makeReader<Floor, Tile>(counter);
			CHECK(reader.at(31010, 31010, 6) == t);
		}
		// the same z and block in two floors do not share a cached floor
		auto reader = ChaosStrip::makeReader<Floor, Tile>(counter);
		CHECK(reader.at(31011, 31011, 7) == map.getTile(31011, 31011, 7));
		CHECK(reader.at(31010, 31010, 6) == t);
		CHECK(reader.at(31011, 31011, 7) == map.getTile(31011, 31011, 7));
	}

	std::printf("compared %ld tiles\n%s\n", compared, g_bad ? "some checks failed" : "ok");
	return g_bad ? 1 : 0;
}
