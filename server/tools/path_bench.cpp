// Offline benchmark of the monster pathfinding costs (patch 0070, server/README.md "Cheaper monster pathfinding (O211)").
//   g++ -std=c++17 -O2 -I DIR server/tools/path_bench.cpp -o path_bench      (DIR holds chaospathing.h, see chaospathing_test.cpp)
//   path_bench [--grid FILE] [--seconds N] [--monsters N] [--reps N] [--check]
// The world is a grid (path_search_ref.h): the windows of --grid (written by server/tools/path_bench_grid.py from a real map) or,
// without it, synthetic rooms and corridors. Part 1 times single searches with the stock node store and the new one
// (same answers, tests: chaospathing_test.cpp). Part 2 plays a chase second by second the way the engine runs it: each
// monster thinks once a second (Creature::onThink: the 2 s refresh, a target or self step sets isUpdatingPath, a failed
// step forces a search), steps every 500 ms, blocks the others, falls back to random steps without a path. It runs the
// stock engine (stock store, always search), the new store (patch 0070), and the new store with the search memo of
// path_memo_experiment.h (measured, not shipped), and counts searches, nodes taken from the open list and the time inside
// the search. --check is the CI mode: the synthetic world, no timing limits, exit 1 when the new store changes the chase.
// What it does not have: the tile costs of the real engine (Tile::queryAdd on an uncached tile, the creature scan of
// getTopVisibleBlockingCreature, isSightClear on the real map) are one grid lookup here, so the share of the search that is
// the node store is larger here than in the server; the numbers are an upper bound for the store, a fair one for the memo.
#include "path_memo_experiment.h"
#include "path_search_ref.h"
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <random>
#include <string>

using namespace PathRef;
using Clock = std::chrono::steady_clock;
using ChaosPath::Spot;
using ChaosPath::Verdict;

static double seconds(Clock::duration d) { return std::chrono::duration<double>(d).count(); }

// ---------------------------------------------------------------------------------------------------- worlds
static std::vector<Grid> loadWindows(const std::string& file)
{
	std::vector<Grid> out;
	std::ifstream in(file);
	int w, h;
	while (in >> w >> h) {
		std::string line;
		std::getline(in, line);
		Grid g;
		g.init(w, h);
		for (int y = 0; y < h; ++y) {
			std::getline(in, line);
			for (int x = 0; x < w && x < int(line.size()); ++x) {
				g.at(x, y) = line[x] == '.' ? 1 : (line[x] == '#' ? 2 : 0);
			}
		}
		out.push_back(g);
	}
	return out;
}

// rooms joined by corridors, a few pillars: the shape of a dungeon floor
static std::vector<Grid> syntheticWindows(int count)
{
	std::vector<Grid> out;
	for (int k = 0; k < count; ++k) {
		std::mt19937 rng(777 + k);
		Grid g;
		g.init(96, 96);
		std::fill(g.cell.begin(), g.cell.end(), 2);
		std::vector<std::pair<int, int>> centres;
		for (int r = 0; r < 14; ++r) {
			const int rw = 6 + rng() % 12, rh = 6 + rng() % 10, rx = 2 + rng() % (96 - rw - 4), ry = 2 + rng() % (96 - rh - 4);
			for (int y = ry; y < ry + rh; ++y) { for (int x = rx; x < rx + rw; ++x) { g.at(x, y) = 1; } }
			for (int p = 0; p < rw * rh / 25; ++p) { g.at(rx + rng() % rw, ry + rng() % rh) = 2; }
			centres.push_back({rx + rw / 2, ry + rh / 2});
		}
		for (size_t i = 1; i < centres.size(); ++i) { // corridors, 1 or 2 wide
			int x = centres[i - 1].first, y = centres[i - 1].second;
			const int tx = centres[i].first, ty = centres[i].second, wide = rng() % 2;
			while (x != tx) { x += x < tx ? 1 : -1; g.at(x, y) = 1; if (wide) { g.at(x, y + 1) = 1; } }
			while (y != ty) { y += y < ty ? 1 : -1; g.at(x, y) = 1; if (wide) { g.at(x + 1, y) = 1; } }
		}
		out.push_back(g);
	}
	return out;
}

// connected pieces of walkable tiles (8 neighbours): label per tile, size per label
static std::vector<int> components(const Grid& g, std::vector<int>& sizes)
{
	std::vector<int> label(size_t(g.w) * g.h, -1);
	for (int y = 0; y < g.h; ++y) {
		for (int x = 0; x < g.w; ++x) {
			if (!g.walkable(x, y) || label[size_t(y) * g.w + x] >= 0) { continue; }
			const int id = int(sizes.size());
			sizes.push_back(0);
			std::vector<std::pair<int, int>> stack{{x, y}};
			label[size_t(y) * g.w + x] = id;
			while (!stack.empty()) {
				auto [cx, cy] = stack.back();
				stack.pop_back();
				++sizes[id];
				for (int dy = -1; dy <= 1; ++dy) {
					for (int dx = -1; dx <= 1; ++dx) {
						const int nx = cx + dx, ny = cy + dy;
						if (g.walkable(nx, ny) && label[size_t(ny) * g.w + nx] < 0) {
							label[size_t(ny) * g.w + nx] = id;
							stack.push_back({nx, ny});
						}
					}
				}
			}
		}
	}
	return label;
}

// ---------------------------------------------------------------------------------------------------- part 1
struct Pair { Pos from, to; };

static Params meleeParams()
{
	Params p; // Monster::getPathSearchParams for a melee monster: fullPathSearch, clearSight, maxSearchDist 12, target distance 1
	p.fullPathSearch = true; p.clearSight = true; p.maxSearchDist = 12; p.minTargetDist = 1; p.maxTargetDist = 1;
	return p;
}

template<typename Store>
static double timeSearches(const Grid& g, const std::vector<Pair>& pairs, int reps, Stats& stats)
{
	double best = 1e9;
	const Params fpp = meleeParams();
	for (int r = 0; r < reps; ++r) {
		Stats st;
		std::vector<int> list;
		const auto t0 = Clock::now();
		for (const Pair& p : pairs) {
			list.clear();
			getPathMatching<Store>(g, p.from, Condition{g, p.to}, fpp, list, st);
		}
		best = std::min(best, seconds(Clock::now() - t0));
		stats = st;
	}
	return best;
}

struct SingleResult { double stockNs = 0, fastNs = 0; double expanded = 0; uint64_t searches = 0; };

static SingleResult singleSearches(const std::vector<Grid>& windows, int reps, const char* label, bool wantFound)
{
	std::mt19937 rng(4242);
	double stockSec = 0, fastSec = 0;
	uint64_t searches = 0, expanded = 0;
	for (const Grid& g : windows) {
		std::vector<int> sizes;
		const std::vector<int> label2 = components(g, sizes);
		std::vector<Pair> pairs;
		for (int tries = 0; tries < 200000 && pairs.size() < 2000; ++tries) {
			const int x = rng() % g.w, y = rng() % g.h, tx = x + int(rng() % 17) - 8, ty = y + int(rng() % 17) - 8;
			if (!g.walkable(x, y) || !g.walkable(tx, ty) || (x == tx && y == ty)) { continue; }
			const bool same = label2[size_t(y) * g.w + x] == label2[size_t(ty) * g.w + tx];
			if (same != wantFound) { continue; }
			pairs.push_back({g.pos(x, y), g.pos(tx, ty)});
		}
		if (pairs.empty()) { continue; }
		Stats a, b;
		stockSec += timeSearches<StockNodes>(g, pairs, reps, a);
		fastSec += timeSearches<FastNodes>(g, pairs, reps, b);
		if (a.expanded != b.expanded) { std::cout << "MISMATCH in expanded nodes" << std::endl; }
		searches += a.searches;
		expanded += a.expanded;
	}
	SingleResult r;
	r.searches = searches;
	if (searches) {
		r.stockNs = stockSec / searches * 1e9;
		r.fastNs = fastSec / searches * 1e9;
		r.expanded = double(expanded) / searches;
		std::printf("  %-34s %7llu searches  %6.0f nodes/search  stock %8.0f ns  new %8.0f ns  x%.2f\n", label,
		            (unsigned long long)searches, r.expanded, r.stockNs, r.fastNs, r.stockNs / r.fastNs);
	}
	return r;
}

// ---------------------------------------------------------------------------------------------------- part 2
struct Monster {
	int x, y;
	std::vector<int> list;
	bool hasFollowPath = false, forceUpdate = false, isUpdating = false;
	int walkUpdateMs = 0;
	int nextThink = 0, nextStep = 0, lastMoveMs = 0;
	ChaosPath::Memo memo;
	std::mt19937 rng;
};

enum class Mode { Hunt, Stand, Blocked };

struct ChaseResult {
	Stats stats;
	double searchSec = 0;
	double adjacentShare = 0; // monster-seconds spent next to the player / all
	double meanDist = 0;
	uint64_t gameSec = 0;
	uint64_t memoKept = 0;
};

template<typename Store>
static ChaseResult chase(const Grid& base, Mode mode, int monsters, int gameSeconds, ChaosPath::Settings policy, uint32_t seed)
{
	Grid g = base;
	std::vector<int> sizes;
	const std::vector<int> label = components(g, sizes);
	int biggest = 0;
	for (size_t i = 0; i < sizes.size(); ++i) { if (sizes[i] > sizes[biggest]) { biggest = int(i); } }
	std::mt19937 rng(seed);

	// player and monsters placed from the seed: all in the biggest piece (Blocked: the player in another piece)
	std::vector<std::pair<int, int>> tiles;
	for (int y = 0; y < g.h; ++y) { for (int x = 0; x < g.w; ++x) { if (g.walkable(x, y) && label[size_t(y) * g.w + x] == biggest) { tiles.push_back({x, y}); } } }
	if (tiles.size() < 200) { return ChaseResult(); }
	int px = 0, py = 0;
	for (int tries = 0; tries < 100000; ++tries) {
		const auto t = tiles[rng() % tiles.size()];
		px = t.first; py = t.second;
		if (mode != Mode::Blocked) { break; }
		// Blocked: a tile of another piece within 9 tiles of the big one
		bool ok = false;
		for (int dy = -9; dy <= 9 && !ok; ++dy) { for (int dx = -9; dx <= 9 && !ok; ++dx) {
			const int nx = px + dx, ny = py + dy;
			if (g.walkable(nx, ny) && label[size_t(ny) * g.w + nx] != biggest && sizes[label[size_t(ny) * g.w + nx]] <= 40) { px = nx; py = ny; ok = true; }
		} }
		if (ok) { break; }
		if (tries == 99999) { return ChaseResult(); }
	}

	std::vector<Monster> mons;
	for (int tries = 0; tries < 100000 && int(mons.size()) < monsters; ++tries) {
		const auto t = tiles[rng() % tiles.size()];
		const int d = std::max(std::abs(t.first - px), std::abs(t.second - py));
		if (d < 4 || d > 11) { continue; }
		bool taken = false;
		for (const Monster& m : mons) { taken |= (m.x == t.first && m.y == t.second); }
		if (taken) { continue; }
		Monster m;
		m.x = t.first; m.y = t.second;
		m.nextThink = int(rng() % 1000);
		m.nextStep = int(rng() % 500);
		m.rng.seed(seed * 31 + unsigned(mons.size()));
		mons.push_back(std::move(m));
	}
	if (mons.empty()) { return ChaseResult(); }

	ChaseResult res;
	std::mt19937 prng(seed + 99);
	int dirX = 1, dirY = 0, playerNextStep = 0;
	const Params fpp = meleeParams();
	const uint64_t keyMelee = ChaosPath::paramsKey(fpp.fullPathSearch, fpp.clearSight, fpp.allowDiagonal, fpp.keepDistance, fpp.maxSearchDist, fpp.minTargetDist, fpp.maxTargetDist);
	const int TICK = 250;
	uint64_t adjacentTicks = 0, ticks = 0;
	double distSum = 0;

	auto occupied = [&](int x, int y) {
		if (x == px && y == py) { return true; }
		for (const Monster& m : mons) { if (m.x == x && m.y == y) { return true; } }
		return false;
	};
	static const int DX[8] = {0, 1, 0, -1, -1, 1, -1, 1}, DY[8] = {-1, 0, 1, 0, 1, 1, -1, -1};

	for (int now = 0; now < gameSeconds * 1000; now += TICK) {
		const int64_t clock = now;
		// the player: Hunt walks (a tile every 500 ms, keeps its way, turns at walls), Stand and Blocked do not move
		bool playerMoved = false;
		if (mode == Mode::Hunt && now >= playerNextStep) {
			playerNextStep = now + 500;
			if (prng() % 5 == 0) { const int d = prng() % 4; dirX = DX[d]; dirY = DY[d]; }
			int nx = px + dirX, ny = py + dirY;
			if (!g.walkable(nx, ny) || occupied(nx, ny)) { const int d = prng() % 4; dirX = DX[d]; dirY = DY[d]; nx = px + dirX; ny = py + dirY; }
			if (g.walkable(nx, ny) && !occupied(nx, ny)) { px = nx; py = ny; playerMoved = true; }
		}
		if (playerMoved) { for (Monster& m : mons) { if (m.hasFollowPath) { m.isUpdating = true; } } }

		for (Monster& m : mons) {
			// Creature::onThink, once a second
			if (now >= m.nextThink) {
				m.nextThink += 1000;
				m.walkUpdateMs += 1000;
				if (m.forceUpdate || m.walkUpdateMs >= 2000) {
					if (m.forceUpdate) { m.memo.clear(); }
					m.walkUpdateMs = 0;
					m.forceUpdate = false;
					m.isUpdating = true;
				}
				if (m.isUpdating) {
					m.isUpdating = false;
					// Creature::goToFollowCreature
					const Spot start{g.pos(m.x, m.y).x, g.pos(m.x, m.y).y, 7}, target{g.pos(px, py).x, g.pos(px, py).y, 7};
					const Verdict v = ChaosPath::decide(m.memo, clock, start, target, keyMelee, m.list, m.hasFollowPath, policy);
					if (v == Verdict::Search) {
						m.list.clear();
						const auto t0 = Clock::now();
						const bool ok = getPathMatching<Store>(g, g.pos(m.x, m.y), Condition{g, g.pos(px, py)}, fpp, m.list, res.stats);
						res.searchSec += seconds(Clock::now() - t0);
						m.hasFollowPath = ok;
						m.memo.record(ok, keyMelee, start, target, m.list, clock);
					} else {
						++res.memoKept;
					}
				}
			}
			// Monster::getNextStep + Creature::onWalk, a step every 500 ms
			if (now >= m.nextStep) {
				m.nextStep = now + 500;
				const int dist = std::max(std::abs(m.x - px), std::abs(m.y - py));
				if (m.hasFollowPath && !m.list.empty()) {
					const int d = m.list.back();
					m.list.pop_back();
					const int nx = m.x + DX[d], ny = m.y + DY[d];
					if (g.walkable(nx, ny) && !occupied(nx, ny)) {
						m.x = nx; m.y = ny; m.lastMoveMs = now;
						g.creature[size_t(m.y) * g.w + m.x] = 0;
						if (m.hasFollowPath) { m.isUpdating = true; } // Creature::onCreatureMove, the monster itself
					} else {
						m.forceUpdate = true;
					}
				} else if (!(m.hasFollowPath && dist <= 1) && now - m.lastMoveMs >= 1000) { // no path: a random step
					const int d = m.rng() % 4;
					const int nx = m.x + DX[d], ny = m.y + DY[d];
					if (g.walkable(nx, ny) && !occupied(nx, ny)) { m.x = nx; m.y = ny; m.lastMoveMs = now; }
				}
			}
		}
		// where the monsters stand costs more to path through (Tile::getTopVisibleBlockingCreature)
		std::fill(g.creature.begin(), g.creature.end(), 0);
		for (const Monster& m : mons) { g.creature[size_t(m.y) * g.w + m.x] = 1; }
		for (const Monster& m : mons) {
			const int d = std::max(std::abs(m.x - px), std::abs(m.y - py));
			adjacentTicks += d <= 1;
			distSum += d;
			++ticks;
		}
	}
	res.gameSec = gameSeconds;
	res.adjacentShare = ticks ? double(adjacentTicks) / ticks : 0;
	res.meanDist = ticks ? distSum / ticks : 0;
	return res;
}

struct Totals { Stats stats; double sec = 0, adjacent = 0, dist = 0; uint64_t gameSec = 0, kept = 0; int runs = 0; };

static void add(Totals& t, const ChaseResult& r)
{
	if (!r.gameSec) { return; }
	t.stats.searches += r.stats.searches; t.stats.expanded += r.stats.expanded; t.stats.failed += r.stats.failed; t.stats.tileTests += r.stats.tileTests;
	t.sec += r.searchSec; t.adjacent += r.adjacentShare; t.dist += r.meanDist; t.gameSec += r.gameSec; t.kept += r.memoKept; ++t.runs;
}

static const char* modeName(Mode m) { return m == Mode::Hunt ? "player walks" : (m == Mode::Stand ? "player stands" : "player unreachable"); }

int main(int argc, char** argv)
{
	std::string gridFile;
	int gameSeconds = 120, monsters = 12, reps = 5;
	bool check = false;
	for (int i = 1; i < argc; ++i) {
		if (!std::strcmp(argv[i], "--grid") && i + 1 < argc) { gridFile = argv[++i]; }
		else if (!std::strcmp(argv[i], "--seconds") && i + 1 < argc) { gameSeconds = std::atoi(argv[++i]); }
		else if (!std::strcmp(argv[i], "--monsters") && i + 1 < argc) { monsters = std::atoi(argv[++i]); }
		else if (!std::strcmp(argv[i], "--reps") && i + 1 < argc) { reps = std::atoi(argv[++i]); }
		else if (!std::strcmp(argv[i], "--check")) { check = true; }
		else { std::cout << "usage: path_bench [--grid FILE] [--seconds N] [--monsters N] [--reps N] [--check]" << std::endl; return 2; }
	}
	std::vector<Grid> windows = gridFile.empty() || check ? syntheticWindows(check ? 3 : 6) : loadWindows(gridFile);
	if (windows.empty()) { std::cout << "no windows" << std::endl; return 2; }
	if (check) { gameSeconds = 90; reps = 1; }
	std::printf("world: %zu windows of %dx%d (%s)\n", windows.size(), windows[0].w, windows[0].h, check || gridFile.empty() ? "synthetic rooms and corridors" : gridFile.c_str());

	int bad = 0;
	if (!check) {
		std::printf("\npart 1: single searches (melee monster, search radius 12), best of %d\n", reps);
		singleSearches(windows, reps, "target reachable", true);
		singleSearches(windows, reps, "target not reachable", false);
	}

	std::printf("\npart 2: %d monsters chase for %d game seconds per window\n", monsters, gameSeconds);
	ChaosPath::Settings off; off.reuseMs = 0; off.failMs = 0;
	const ChaosPath::Settings on; // the experiment's defaults: 1500 ms and 3000 ms
	for (Mode mode : {Mode::Hunt, Mode::Stand, Mode::Blocked}) {
		Totals A, B, C;
		for (size_t w = 0; w < windows.size(); ++w) {
			for (uint32_t seed : {1u, 2u}) {
				add(A, chase<StockNodes>(windows[w], mode, monsters, gameSeconds, off, seed * 100 + uint32_t(w)));
				add(B, chase<FastNodes>(windows[w], mode, monsters, gameSeconds, off, seed * 100 + uint32_t(w)));
				add(C, chase<FastNodes>(windows[w], mode, monsters, gameSeconds, on, seed * 100 + uint32_t(w)));
			}
		}
		if (!A.runs) { std::printf("  %s: no usable window\n", modeName(mode)); continue; }
		auto line = [&](const char* name, const Totals& t) {
			std::printf("  %-34s %6.1f searches/s  %7.0f nodes/s  %7.1f us search time/s  adjacent %4.1f%%  distance %.2f\n", name,
			            double(t.stats.searches) / t.gameSec, double(t.stats.expanded) / t.gameSec, t.sec / t.gameSec * 1e6,
			            100.0 * t.adjacent / t.runs, t.dist / t.runs);
		};
		std::printf(" %s (%d runs, %d monsters each; per game second of all monsters)\n", modeName(mode), A.runs, monsters);
		line("stock (stock store, always search)", A);
		line("new store", B);
		line("new store + search memo (experiment)", C);
		const double fewer = A.stats.searches ? 100.0 * (1.0 - double(C.stats.searches) / A.stats.searches) : 0;
		std::printf("    the new store: search time %.2fx less; the memo on top (not shipped): %.0f%% fewer searches, %.2fx less\n", A.sec / B.sec, fewer, B.sec / C.sec);

		// the new store must not change the chase at all: same searches, same nodes, same distances
		if (A.stats.searches != B.stats.searches || A.stats.expanded != B.stats.expanded || A.dist != B.dist || A.adjacent != B.adjacent) { std::printf("    FAIL: the new store changes the chase\n"); ++bad; }
	}
	if (check && bad) { return 1; }
	std::printf("%s\n", bad ? "some checks failed" : "ok");
	return check ? 0 : (bad ? 1 : 0);
}
