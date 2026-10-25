// Offline benchmark of the walk map refresh (patch 0076, server/README.md "Cheaper walk map refresh (O225)").
//   g++ -std=c++17 -O2 -I DIR -I server/tools server/tools/strip_bench.cpp -o strip_bench   (DIR holds chaosstrip.h)
//   strip_bench [--seconds N] [--check]
// Runs the stock refresh of Creature::localMapCache (Map::getTile for each tile of the new edge, then updateTileCache) and
// the same loop through ChaosStrip::TileReader, on the synthetic world of server/tools/sight_world.h (the quad tree, the
// leaf floors, the stock Map::getTile, a stand-in for the tile test). The stand-in for updateTileCache's Tile::queryAdd
// is the sight test of that world (the ground and each item looked up in a flag table), so the table is not a free
// predicate; the real queryAdd also walks the item list and the creatures of the tile, the same work before and after.
// Scenarios, each over a monster that walks one step from a random place: north or south (a row of 33 tiles), east or
// west (a column of 25), and the full grid of updateMapCache (825 tiles), in a city (solid ground), a cave (half the
// tiles exist) and on a sparse map (islands: the quad tree answers nullptr early). Times both on the same steps,
// interleaved, best of several rounds, and compares the cache bytes of every step. --check (CI): exit 1 on any
// difference, when a step in the city or the cave is not at least 1.15x faster, or any scenario is slower than 0.95x.
#include "chaosstrip.h"
#include "sight_world.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

using namespace world;
using Clock = std::chrono::steady_clock;

constexpr int W = 16, H = 12; // maxWalkCacheWidth / Height
constexpr int GW = 2 * W + 1, GH = 2 * H + 1;

struct Cache { bool cells[GH][GW] = {}; };

static inline void updateTileCache(Cache& c, const Tile* tile, int dx, int dy)
{
	c.cells[H + dy][W + dx] = tile && !hasBlock(tile);
}

enum Dir { North, South, East, West, Grid };

// the stock loops of Creature::onCreatureMove (edge) and Creature::updateMapCache (grid)
static void stockRefresh(const Map& map, Cache& c, int px, int py, uint8_t z, Dir dir)
{
	switch (dir) {
		case North:
			for (int x = -W; x <= W; ++x) { updateTileCache(c, map.getTile(uint16_t(px + x), uint16_t(py - H), z), x, -H); }
			break;
		case South:
			for (int x = -W; x <= W; ++x) { updateTileCache(c, map.getTile(uint16_t(px + x), uint16_t(py + H), z), x, H); }
			break;
		case East:
			for (int y = -H; y <= H; ++y) { updateTileCache(c, map.getTile(uint16_t(px + W), uint16_t(py + y), z), W, y); }
			break;
		case West:
			for (int y = -H; y <= H; ++y) { updateTileCache(c, map.getTile(uint16_t(px - W), uint16_t(py + y), z), -W, y); }
			break;
		case Grid:
			for (int y = -H; y <= H; ++y) { for (int x = -W; x <= W; ++x) { updateTileCache(c, map.getTile(uint16_t(px + x), uint16_t(py + y), z), x, y); } }
			break;
	}
}

static void newRefresh(const Map& map, Cache& c, int px, int py, uint8_t z, Dir dir)
{
	auto floorAt = [&map](uint16_t x, uint16_t y, uint8_t fz) { return map.getFloorAt(x, y, fz); };
	auto reader = ChaosStrip::makeReader<Floor, Tile>(floorAt);
	switch (dir) {
		case North:
			for (int x = -W; x <= W; ++x) { updateTileCache(c, reader.at(px + x, py - H, z), x, -H); }
			break;
		case South:
			for (int x = -W; x <= W; ++x) { updateTileCache(c, reader.at(px + x, py + H, z), x, H); }
			break;
		case East:
			for (int y = -H; y <= H; ++y) { updateTileCache(c, reader.at(px + W, py + y, z), W, y); }
			break;
		case West:
			for (int y = -H; y <= H; ++y) { updateTileCache(c, reader.at(px - W, py + y, z), -W, y); }
			break;
		case Grid:
			for (int y = -H; y <= H; ++y) { for (int x = -W; x <= W; ++x) { updateTileCache(c, reader.at(px + x, py + y, z), x, y); } }
			break;
	}
}

static void fillRect(Map& map, std::mt19937& rng, int x0, int y0, int w, int h, int z, int percent)
{
	for (int x = x0; x < x0 + w; ++x) {
		for (int y = y0; y < y0 + h; ++y) {
			if (int(rng() % 100) >= percent) { continue; }
			Tile* t = new Tile();
			t->ground = uint16_t(1 + rng() % 4000);
			t->n = uint8_t(rng() % 3);
			t->itemBase = uint8_t(rng());
			map.setTile(uint16_t(x), uint16_t(y), uint8_t(z), t);
		}
	}
}

struct Scenario { const char* name; Dir dir; int z; bool required; int x0, y0, span; };
struct Pos { int x, y; };

static int g_bad = 0;

int main(int argc, char** argv)
{
	double budget = 1.0;
	bool check = false;
	for (int i = 1; i < argc; ++i) {
		if (!std::strcmp(argv[i], "--check")) { check = true; }
		else if (!std::strcmp(argv[i], "--seconds") && i + 1 < argc) { budget = std::atof(argv[++i]); }
		else { std::printf("usage: strip_bench [--seconds N] [--check]\n"); return 2; }
	}

	std::mt19937 rng(225);
	Map map;
	fillRect(map, rng, 30000, 30000, 400, 400, 7, 96);   // a city
	fillRect(map, rng, 32000, 30000, 400, 400, 11, 55);  // a cave
	fillRect(map, rng, 40000, 40000, 30, 30, 7, 90);     // two islands
	fillRect(map, rng, 20000, 50000, 30, 30, 7, 90);

	const Scenario scs[] = {
		{"city, step north (row of 33)", North, 7, true, 30040, 30040, 320},
		{"city, step east (column of 25)", East, 7, true, 30040, 30040, 320},
		{"cave, step south (row of 33)", South, 11, true, 32040, 30040, 320},
		{"cave, step west (column of 25)", West, 11, true, 32040, 30040, 320},
		{"city, whole grid (825 tiles)", Grid, 7, true, 30040, 30040, 320},
		{"sea, step north (row of 33)", North, 7, false, 36000, 36000, 4000},
	};

	std::printf("%-34s %12s %12s %8s\n", "scenario", "stock ns", "new ns", "speedup");
	for (const Scenario& sc : scs) {
		const int N = 3000;
		std::vector<Pos> pos(N);
		for (auto& p : pos) { p = {sc.x0 + int(rng() % sc.span), sc.y0 + int(rng() % sc.span)}; }

		for (const auto& p : pos) { // the cache must be the same, every step
			Cache a, b;
			stockRefresh(map, a, p.x, p.y, uint8_t(sc.z), sc.dir);
			newRefresh(map, b, p.x, p.y, uint8_t(sc.z), sc.dir);
			if (std::memcmp(&a, &b, sizeof(Cache)) != 0) { std::printf("cache differs in %s at %d,%d\n", sc.name, p.x, p.y); ++g_bad; break; }
		}

		double bestStock = 1e30, bestNew = 1e30;
		auto t0 = Clock::now();
		int rounds = 0;
		Cache cs, cn;
		uint64_t sink = 0;
		do {
			auto s0 = Clock::now();
			for (const auto& p : pos) { stockRefresh(map, cs, p.x, p.y, uint8_t(sc.z), sc.dir); sink += cs.cells[0][0]; }
			auto s1 = Clock::now();
			for (const auto& p : pos) { newRefresh(map, cn, p.x, p.y, uint8_t(sc.z), sc.dir); sink += cn.cells[0][0]; }
			auto s2 = Clock::now();
			bestStock = std::min(bestStock, std::chrono::duration<double, std::nano>(s1 - s0).count() / N);
			bestNew = std::min(bestNew, std::chrono::duration<double, std::nano>(s2 - s1).count() / N);
			++rounds;
		} while (rounds < 7 || std::chrono::duration<double>(Clock::now() - t0).count() < budget);
		double speed = bestStock / bestNew;
		std::printf("%-34s %12.1f %12.1f %7.2fx%s\n", sc.name, bestStock, bestNew, speed, sink == 1 ? " " : "");
		if (check && sc.required && speed < 1.15) { std::printf("not at least 1.15x faster: %s\n", sc.name); ++g_bad; }
		if (check && speed < 0.95) { std::printf("slower: %s\n", sc.name); ++g_bad; }
	}
	std::printf("%s\n", g_bad ? "some checks failed" : "ok");
	return g_bad ? 1 : 0;
}
