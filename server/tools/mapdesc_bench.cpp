// Offline benchmark of the map description (patch 0072, server/README.md "Cheaper map description (O213)").
//   g++ -std=c++17 -O2 -I DIR -I server/tools server/tools/mapdesc_bench.cpp -o mapdesc_bench   (DIR holds chaosmapdesc.h, see chaosmapdesc_test.cpp)
//   mapdesc_bench [--seconds N] [--check]
// Runs the stock GetFloorDescription (one Map::getTile, a full quad tree walk, per tile) and the new describeFloor
// (src/chaosmapdesc.h, one walk per 8x8 block) on the same synthetic world (server/tools/mapdesc_world.h: the quad tree,
// the leaf floors and the loops of the engine, a stand-in tile writer) for the descriptions a server sends:
//   login / teleport / floor change in a city (18 x 14 tiles, z 7 and the 7 floors above ground, mostly empty up there),
//   the same in a cave (z 11: floors 9 to 13), a step (a row of 18 or a column of 14 tiles on every floor), a boat at sea
//   (a map that is nearly all empty: the quad tree answers nullptr early).
// Each scenario draws random positions (the map is bigger than the caches, so the leaves are not all warm), times both
// versions on the same positions, interleaved, best of several rounds, and compares every byte produced. --check (CI):
// exit 1 on any byte difference or when a full description is not at least 1.15x faster.
// What it leaves out: the real tile writer also writes creatures (player->canSeeCreature, the known creature list,
// outfits) and goes through NetworkMessage::canAdd on every write; that work is the same before and after, so the share
// of a whole description the patch saves is lower in the engine than the table here. See the README.
#include "chaosmapdesc.h"
#include "mapdesc_world.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <string>
#include <vector>

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
			t->n = uint8_t(rng() % 4);
			t->itemBase = uint8_t(rng());
			map.setTile(uint16_t(x), uint16_t(y), uint8_t(z), t);
		}
	}
}

struct Scenario {
	const char* name;
	int w, h, z;
	bool required; // --check demands the 1.15x
	int x0, y0, span; // positions are drawn in [x0, x0 + span)
};

static void stockDesc(const Map& map, Msg& m, int32_t x, int32_t y, int32_t z, int32_t w, int32_t h)
{
	mapDescription(m, x, y, z, w, h, [&map](Msg& mm, int32_t X, int32_t Y, int32_t Z, int32_t W, int32_t H, int32_t O, int32_t& s) { stockFloor(map, mm, X, Y, Z, W, H, O, s); });
}

static void newDesc(const Map& map, Msg& m, int32_t x, int32_t y, int32_t z, int32_t w, int32_t h)
{
	mapDescription(m, x, y, z, w, h, [&map](Msg& mm, int32_t X, int32_t Y, int32_t Z, int32_t W, int32_t H, int32_t O, int32_t& s) {
		ChaosMapDesc::describeFloor<Floor>(mm, X, Y, Z, W, H, O, s,
			[&map](uint16_t tx, uint16_t ty, uint8_t tz) { return map.getFloorAt(tx, ty, tz); },
			[&mm](const Tile* t) { emitTile(t, mm); });
	});
}

int main(int argc, char** argv)
{
	double budget = 1.0;
	bool check = false;
	for (int i = 1; i < argc; ++i) {
		if (!std::strcmp(argv[i], "--check")) { check = true; }
		else if (!std::strcmp(argv[i], "--seconds") && i + 1 < argc) { budget = std::atof(argv[++i]); }
		else { std::printf("usage: mapdesc_bench [--seconds N] [--check]\n"); return 2; }
	}

	std::mt19937 rng(2026);
	Map map;
	// a city: 400 x 400, solid on the ground floor, sparse above it
	for (int z = 7; z >= 0; --z) { fillRect(map, rng, 30000, 30000, 400, 400, z, z == 7 ? 95 : 12); }
	// a cave system: 400 x 400 at 55% on floors 9 to 13
	for (int z = 9; z <= 13; ++z) { fillRect(map, rng, 32000, 30000, 400, 400, z, 55); }
	// sea: two islands far apart, nothing between
	fillRect(map, rng, 40000, 40000, 30, 30, 7, 90);
	fillRect(map, rng, 20000, 50000, 30, 30, 7, 90);

	const Scenario scs[] = {
		{"city, full description 18x14", 18, 14, 7, true, 30020, 30020, 360},
		{"cave, full description 18x14", 18, 14, 11, true, 32020, 30020, 360},
		{"city, step: row 18x1", 18, 1, 7, false, 30020, 30020, 360},
		{"city, step: column 1x14", 1, 14, 7, false, 30020, 30020, 360},
		{"sea, full description 18x14", 18, 14, 7, false, 36000, 36000, 4000},
	};

	std::printf("%-32s %12s %12s %8s %10s\n", "scenario", "stock ns", "new ns", "speedup", "bytes");
	for (const Scenario& sc : scs) {
		const int N = 2000;
		std::vector<std::pair<int, int>> pos(N);
		for (auto& p : pos) { p = {sc.x0 + int(rng() % sc.span), sc.y0 + int(rng() % sc.span)}; }

		Msg a, b;
		uint64_t bytes = 0;
		for (const auto& p : pos) { // the bytes must be the same, every position
			a.clear(); b.clear();
			stockDesc(map, a, p.first, p.second, sc.z, sc.w, sc.h);
			newDesc(map, b, p.first, p.second, sc.z, sc.w, sc.h);
			if (a.buf != b.buf) { std::printf("bytes differ in %s at %d,%d\n", sc.name, p.first, p.second); ++g_bad; break; }
			bytes += a.buf.size();
		}

		double bestStock = 1e30, bestNew = 1e30;
		uint64_t sink = 0;
		auto t0 = Clock::now();
		int rounds = 0;
		do {
			auto s0 = Clock::now();
			for (const auto& p : pos) { a.clear(); stockDesc(map, a, p.first, p.second, sc.z, sc.w, sc.h); sink += a.buf.size(); }
			auto s1 = Clock::now();
			for (const auto& p : pos) { b.clear(); newDesc(map, b, p.first, p.second, sc.z, sc.w, sc.h); sink += b.buf.size(); }
			auto s2 = Clock::now();
			bestStock = std::min(bestStock, std::chrono::duration<double, std::nano>(s1 - s0).count() / N);
			bestNew = std::min(bestNew, std::chrono::duration<double, std::nano>(s2 - s1).count() / N);
			++rounds;
		} while (rounds < 7 || std::chrono::duration<double>(Clock::now() - t0).count() < budget);
		double speed = bestStock / bestNew;
		std::printf("%-32s %12.0f %12.0f %7.2fx %10llu%s\n", sc.name, bestStock, bestNew, speed, (unsigned long long)(bytes / N), sink == 1 ? " " : "");
		if (check && sc.required && speed < 1.15) { std::printf("not at least 1.15x faster: %s\n", sc.name); ++g_bad; }
		if (check && speed < 0.95) { std::printf("slower: %s\n", sc.name); ++g_bad; }
	}
	std::printf("%s\n", g_bad ? "some checks failed" : "ok");
	return g_bad ? 1 : 0;
}
