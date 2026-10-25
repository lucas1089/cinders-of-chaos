// Unit test of src/chaossight.h (patch 0074, server/README.md "Cheaper line of sight (O218)").
//   g++ -std=c++17 -O1 -Wall -Wextra -I DIR -I server/tools server/tools/chaossight_test.cpp -o chaossight_test
// DIR holds chaossight.h, cut out of the patch (.github/workflows/ci.yml, step "Line of sight"). Builds many synthetic
// maps (dense, sparse, with many blockers, one tile per leaf, empty, floors that do not exist, the edges of the 16 bit
// coordinates) and compares the answer of ChaosSight::Line::check with a copy of the stock checkSightLine for random
// lines of every slope and length in both directions (also zero length, straight, diagonal, and endpoints given in
// the other order), checks the quad tree is walked once per 8x8 block the line enters, and that a tile set after a
// line was checked is seen by the next one (nothing is kept between calls).
#include "chaossight.h"
#include "sight_world.h"
#include <cstdio>
#include <random>

using namespace world;

static int g_bad = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAILED %s:%d: %s\n", __FILE__, __LINE__, #c); ++g_bad; } } while (0)

static bool newCheck(const Map& map, uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint8_t z, long* walks = nullptr)
{
	auto floorAt = [&map, walks](uint16_t x, uint16_t y, uint8_t fz) { if (walks) { ++*walks; } return map.getFloorAt(x, y, fz); };
	auto blocks = [](const Tile* t) { return hasBlock(t); };
	auto line = ChaosSight::makeLine<Floor>(z, floorAt, blocks);
	return line.check(x0, y0, x1, y1);
}

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
	std::mt19937 rng(777);
	long compared = 0, blocked = 0, open = 0;
	for (int round = 0; round < 60; ++round) {
		Map map;
		int density = round % 6 == 0 ? 100 : round % 6 == 1 ? 3 : round % 6 == 2 ? 50 : round % 6 == 3 ? 0 : round % 6 == 4 ? 90 : 20;
		int cx = 31000, cy = 31000;
		if (round % 7 == 3) { cx = 40; cy = 50; }               // top-left edge
		if (round % 7 == 5) { cx = 65490; cy = 65490; }         // bottom-right edge
		for (int z = 0; z < MAP_MAX_LAYERS; ++z) {
			if (z % 3 == round % 3) { continue; }                // some floors do not exist
			fill(map, rng, cx - 40, cy - 40, 90, 90, z, density);
		}
		for (int iter = 0; iter < 600; ++iter) {
			int reach = iter % 5 == 0 ? 60 : 12;
			int x0 = cx - 30 + int(rng() % 60), y0 = cy - 30 + int(rng() % 60);
			int x1 = x0 + int(rng() % (2 * reach + 1)) - reach, y1 = y0 + int(rng() % (2 * reach + 1)) - reach;
			if (iter % 13 == 0) { y1 = y0; }                     // straight lines
			if (iter % 17 == 0) { x1 = x0; }
			if (iter % 19 == 0) { x1 = x0 + (y1 - y0); }         // diagonal
			if (iter % 23 == 0) { x1 = x0; y1 = y0; }           // zero length
			uint8_t z = uint8_t(rng() % 18);                      // 16 and 17 are out of range
			bool a = stockCheckSightLine(map, uint16_t(x0), uint16_t(y0), uint16_t(x1), uint16_t(y1), z);
			bool b = newCheck(map, uint16_t(x0), uint16_t(y0), uint16_t(x1), uint16_t(y1), z);
			CHECK(a == b);
			bool c = stockCheckSightLine(map, uint16_t(x1), uint16_t(y1), uint16_t(x0), uint16_t(y0), z);
			bool d = newCheck(map, uint16_t(x1), uint16_t(y1), uint16_t(x0), uint16_t(y0), z);
			CHECK(c == d);
			compared += 2;
			(a ? open : blocked)++;
		}
	}
	CHECK(blocked > 2000 && open > 2000); // both outcomes are well covered

	// the quad tree is walked once per block, not per tile: a straight run of 40 tiles
	{
		Map map;
		fill(map, rng, 31000, 31000, 64, 64, 7, 100);
		long walks = 0;
		(void)newCheck(map, 31002, 31010, 31042, 31010, 7, &walks);
		CHECK(walks <= 6);
		CHECK(walks >= 1);
		std::printf("lookups for a 40 tile line: %ld (stock: 39)\n", walks);
		// a block that is missing (no leaf) is looked up once, not for each tile
		long w2 = 0;
		bool r = newCheck(map, 100, 100, 130, 100, 7, &w2);
		CHECK(r && w2 <= 5);
	}

	// nothing is kept between calls: a blocker placed after a check is seen by the next one
	{
		Map map;
		fill(map, rng, 31000, 31000, 32, 32, 7, 100);
		for (int x = 31000; x < 31032; ++x) { for (int y = 31000; y < 31032; ++y) { Tile* t = const_cast<Tile*>(map.getTile(x, y, 7)); t->ground = 0; t->n = 0; } }
		CHECK(newCheck(map, 31001, 31005, 31020, 31005, 7));
		// find an item id that blocks and put it in the middle of the line
		int blockId = 1;
		while (!blockTable()[blockId]) { ++blockId; }
		Tile* mid = const_cast<Tile*>(map.getTile(31010, 31005, 7));
		mid->ground = uint16_t(blockId);
		CHECK(!newCheck(map, 31001, 31005, 31020, 31005, 7));
		CHECK(!stockCheckSightLine(map, 31001, 31005, 31020, 31005, 7));
		// a floor that is created later is seen too
		CHECK(newCheck(map, 31001, 31100, 31020, 31100, 6));
		for (int x = 31001; x < 31021; ++x) { Tile* u = new Tile(); u->ground = uint16_t(blockId); map.setTile(uint16_t(x), 31100, 6, u); }
		CHECK(!newCheck(map, 31001, 31100, 31030, 31100, 6));
	}

	std::printf("compared %ld lines\n%s\n", compared, g_bad ? "some checks failed" : "ok");
	return g_bad ? 1 : 0;
}
