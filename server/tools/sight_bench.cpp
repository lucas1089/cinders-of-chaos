// Offline benchmark of the line of sight (patch 0074, server/README.md "Cheaper line of sight (O218)").
//   g++ -std=c++17 -O2 -I DIR -I server/tools server/tools/sight_bench.cpp -o sight_bench   (DIR holds chaossight.h, see chaossight_test.cpp)
//   sight_bench [--seconds N] [--check]
// Runs the stock Map::checkSightLine (one quad tree walk per tile of the line) and ChaosSight::Line (one walk per 8x8
// block entered) on the same synthetic world (server/tools/sight_world.h: the quad tree, the leaf floors, the stock
// functions, a stand-in Tile::hasProperty) for the lines a server asks about:
//   a monster shooting at a player (4 to 7 tiles), a caster or archer at range (7 to 10), a long line (11 to 15, a spell
//   or a ranged player across a screen), in a city (solid ground, a tile in 20 has a blocking item), in a cave, and on a
//   sparse map (islands: the quad tree answers nullptr early).
// Each scenario draws random line ends, times both versions on the same lines, interleaved, best of several rounds,
// and compares every answer. --check (CI): exit 1 on any difference of answer, when a line of 7 or more tiles is not at
// least 1.15x faster or any scenario is slower than 0.95x.
// What it leaves out: the real Tile::hasProperty walks the item list of every tile (a cache miss per item), the same work
// before and after, so the share of a whole sight check the patch saves is lower in the engine than the table here.
#include "chaossight.h"
#include "sight_world.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

using namespace world;
using Clock = std::chrono::steady_clock;

static int g_bad = 0;

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

static bool newCheck(const Map& map, uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint8_t z)
{
	auto floorAt = [&map](uint16_t x, uint16_t y, uint8_t fz) { return map.getFloorAt(x, y, fz); };
	auto blocks = [](const Tile* t) { return hasBlock(t); };
	auto line = ChaosSight::makeLine<Floor>(z, floorAt, blocks);
	return line.check(x0, y0, x1, y1);
}

struct Scenario {
	const char* name;
	int minLen, maxLen, z;
	bool required; // --check demands the 1.15x
	int x0, y0, span; // positions are drawn in [x0, x0 + span)
};

struct Ends { uint16_t x0, y0, x1, y1; };

int main(int argc, char** argv)
{
	double budget = 1.0;
	bool check = false;
	for (int i = 1; i < argc; ++i) {
		if (!std::strcmp(argv[i], "--check")) { check = true; }
		else if (!std::strcmp(argv[i], "--seconds") && i + 1 < argc) { budget = std::atof(argv[++i]); }
		else { std::printf("usage: sight_bench [--seconds N] [--check]\n"); return 2; }
	}

	std::mt19937 rng(2026);
	Map map;
	fillRect(map, rng, 30000, 30000, 400, 400, 7, 96);   // a city
	fillRect(map, rng, 32000, 30000, 400, 400, 11, 55);  // a cave
	fillRect(map, rng, 40000, 40000, 30, 30, 7, 90);     // two islands
	fillRect(map, rng, 20000, 50000, 30, 30, 7, 90);

	const Scenario scs[] = {
		{"city, monster shot 4-7 tiles", 4, 7, 7, false, 30020, 30020, 360},
		{"city, ranged 7-10 tiles", 7, 10, 7, true, 30020, 30020, 360},
		{"city, long 11-15 tiles", 11, 15, 7, true, 30020, 30020, 360},
		{"cave, ranged 7-10 tiles", 7, 10, 11, true, 32020, 30020, 360},
		{"sea, ranged 7-10 tiles", 7, 10, 7, false, 36000, 36000, 4000},
	};

	std::printf("%-32s %12s %12s %8s\n", "scenario", "stock ns", "new ns", "speedup");
	for (const Scenario& sc : scs) {
		const int N = 4000;
		std::vector<Ends> lines(N);
		for (auto& l : lines) {
			int x = sc.x0 + int(rng() % sc.span), y = sc.y0 + int(rng() % sc.span);
			int len = sc.minLen + int(rng() % (sc.maxLen - sc.minLen + 1));
			int dx = int(rng() % (2 * len + 1)) - len;
			int rest = len * len - dx * dx;
			int dy = int(std::lround(std::sqrt(double(rest > 0 ? rest : 0)))) * (rng() & 1 ? 1 : -1);
			l = {uint16_t(x), uint16_t(y), uint16_t(x + dx), uint16_t(y + dy)};
		}

		long open = 0;
		for (const auto& l : lines) { // the answers must be the same, every line
			bool a = stockCheckSightLine(map, l.x0, l.y0, l.x1, l.y1, uint8_t(sc.z));
			bool b = newCheck(map, l.x0, l.y0, l.x1, l.y1, uint8_t(sc.z));
			if (a != b) { std::printf("answers differ in %s at %d,%d -> %d,%d\n", sc.name, l.x0, l.y0, l.x1, l.y1); ++g_bad; break; }
			open += a;
		}

		double bestStock = 1e30, bestNew = 1e30;
		uint64_t sink = 0;
		auto t0 = Clock::now();
		int rounds = 0;
		do {
			auto s0 = Clock::now();
			for (const auto& l : lines) { sink += stockCheckSightLine(map, l.x0, l.y0, l.x1, l.y1, uint8_t(sc.z)); }
			auto s1 = Clock::now();
			for (const auto& l : lines) { sink += newCheck(map, l.x0, l.y0, l.x1, l.y1, uint8_t(sc.z)); }
			auto s2 = Clock::now();
			bestStock = std::min(bestStock, std::chrono::duration<double, std::nano>(s1 - s0).count() / N);
			bestNew = std::min(bestNew, std::chrono::duration<double, std::nano>(s2 - s1).count() / N);
			++rounds;
		} while (rounds < 7 || std::chrono::duration<double>(Clock::now() - t0).count() < budget);
		double speed = bestStock / bestNew;
		std::printf("%-32s %12.1f %12.1f %7.2fx  (%ld%% clear)%s\n", sc.name, bestStock, bestNew, speed, open * 100 / N, sink == 1 ? " " : "");
		if (check && sc.required && speed < 1.15) { std::printf("not at least 1.15x faster: %s\n", sc.name); ++g_bad; }
		if (check && speed < 0.95) { std::printf("slower: %s\n", sc.name); ++g_bad; }
	}
	std::printf("%s\n", g_bad ? "some checks failed" : "ok");
	return g_bad ? 1 : 0;
}
