// Tests of src/chaoszones.h from engine src-patch 0027 (the dynamic respawn's zones through a spawn index). CI takes the
// header out of the patch (the step "Respawn zones index" in .github/workflows/ci.yml), then:
//   g++ -std=c++17 -Wall -Wextra -I "$d" server/tools/chaoszones_test.cpp -o "$d/chaoszones_test" && "$d/chaoszones_test"
// The index must give every spawn the same percent as the old way (every spawn to the global percent, then each zone in
// turn over every spawn) while touching only the spawns of the new and the last zones.
#include "chaoszones.h"

#include <cstdio>
#include <forward_list>
#include <random>
#include <vector>

static int checks = 0, fails = 0;
static void ok(bool cond, const char* what)
{
	++checks;
	if (!cond) {
		++fails;
		std::printf("FAIL %s\n", what);
	}
}

struct Pos {
	uint16_t x, y;
	uint8_t z;
};

struct FakeSpawn {
	Pos centre;
	uint16_t percent = 100;
	int calls = 0;   // setIntervalPercent calls
	int changes = 0; // calls that changed the percent

	explicit FakeSpawn(Pos c) : centre(c) {}
	const Pos& getCenterPos() const {
		return centre;
	}
	void setIntervalPercent(uint16_t p) {
		++calls;
		if (p != percent) {
			percent = p;
			++changes;
		}
	}
};

using ChaosZones::Zone;

// the old way: Game.setSpawnIntervalPercent(global), then one box call per zone
static std::vector<uint16_t> reference(const std::forward_list<FakeSpawn>& spawns, uint16_t global, const std::vector<Zone>& zones)
{
	std::vector<uint16_t> out;
	for (const FakeSpawn& s : spawns) {
		uint16_t p = ChaosZones::clampPercent(global);
		for (const Zone& z : zones) {
			const Pos& c = s.centre;
			if (c.x >= z.x0 && c.x <= z.x1 && c.y >= z.y0 && c.y <= z.y1 && c.z == z.z) {
				p = ChaosZones::clampPercent(z.percent);
			}
		}
		out.push_back(p);
	}
	return out;
}

static std::vector<uint16_t> current(const std::forward_list<FakeSpawn>& spawns)
{
	std::vector<uint16_t> out;
	for (const FakeSpawn& s : spawns) {
		out.push_back(s.percent);
	}
	return out;
}

static int totalCalls(const std::forward_list<FakeSpawn>& spawns)
{
	int n = 0;
	for (const FakeSpawn& s : spawns) {
		n += s.calls;
	}
	return n;
}

int main()
{
	ok(ChaosZones::clampPercent(5) == 10 && ChaosZones::clampPercent(5000) == 1000 && ChaosZones::clampPercent(55) == 55,
		"percents are held in 10-1000");

	// a small map: spawns on a 4 sqm grid over 0..199 x 0..199, floors 7 and 8
	std::forward_list<FakeSpawn> spawns;
	int count = 0;
	for (uint16_t x = 0; x < 200; x += 4) {
		for (uint16_t y = 0; y < 200; y += 4) {
			for (uint8_t z = 7; z <= 8; ++z) {
				spawns.emplace_front(Pos{x, y, z});
				++count;
			}
		}
	}

	ChaosZones::Index<FakeSpawn> index;
	ok(!index.built(), "not built before build()");
	index.build(spawns);
	ok(index.built(), "built");

	// first call: every spawn is set once (the index does not know what they hold)
	std::vector<Zone> zones = {{32 - 8, 32 - 8, 47 + 8, 47 + 8, 7, 70}, {40, 40, 70, 70, 7, 50}};
	size_t inZones = index.apply(100, zones);
	ok(current(spawns) == reference(spawns, 100, zones), "first call: the same percents as the old way");
	ok(totalCalls(spawns) >= count, "first call: every spawn set");
	ok(inZones > 0, "first call: spawns in the zones counted");
	{
		// the later zone wins where they overlap: (44, 44, 7) lies in both
		bool found = false;
		for (const FakeSpawn& s : spawns) {
			if (s.centre.x == 44 && s.centre.y == 44 && s.centre.z == 7) {
				found = s.percent == 50;
			}
		}
		ok(found, "overlap: the later zone's percent");
	}

	// second call, one zone moved: only the spawns of the old and the new zones are touched
	for (FakeSpawn& s : spawns) {
		s.calls = 0;
	}
	std::vector<Zone> moved = {{100, 100, 131, 131, 8, 55}};
	inZones = index.apply(100, moved);
	ok(current(spawns) == reference(spawns, 100, moved), "moved zone: the same percents as the old way");
	ok(totalCalls(spawns) < count / 4, "moved zone: only a few spawns touched, not every one");
	ok(inZones == 64, "moved zone: 8 x 8 spawns on floor 8 in 100..131");

	// the same zones again: only those spawns are touched (no change), nothing else
	for (FakeSpawn& s : spawns) {
		s.calls = 0;
		s.changes = 0;
	}
	index.apply(100, moved);
	int changes = 0;
	for (const FakeSpawn& s : spawns) {
		changes += s.changes;
	}
	ok(changes == 0, "same zones: no percent changes");
	ok(totalCalls(spawns) == 64, "same zones: only the zone's spawns are touched");

	// no zones: every spawn back to the global percent
	index.apply(100, {});
	ok(current(spawns) == reference(spawns, 100, {}), "no zones: every spawn at the global percent");

	// a new global percent: every spawn set again
	for (FakeSpawn& s : spawns) {
		s.calls = 0;
	}
	index.apply(80, moved);
	ok(current(spawns) == reference(spawns, 80, moved), "new global percent: the same percents as the old way");
	ok(totalCalls(spawns) >= count, "new global percent: every spawn set");

	// another script set percents directly: invalidate() makes the next call set every spawn
	for (FakeSpawn& s : spawns) {
		s.setIntervalPercent(300);
		s.calls = 0;
	}
	index.invalidate();
	index.apply(80, moved);
	ok(current(spawns) == reference(spawns, 80, moved), "after invalidate: the same percents as the old way");
	ok(totalCalls(spawns) >= count, "after invalidate: every spawn set");

	// an inverted box and a box off the map are ignored; percents out of range are clamped
	std::vector<Zone> odd = {{50, 50, 40, 40, 7, 50}, {5000, 5000, 5100, 5100, 7, 50}, {0, 0, 10, 10, 7, 1}};
	index.apply(80, odd);
	ok(current(spawns) == reference(spawns, 80, odd), "odd zones: the same percents as the old way");

	// random zone lists against the old way, many rounds in a row (the index keeps its state between them)
	std::mt19937 rng(12345);
	bool same = true;
	for (int round = 0; round < 300 && same; ++round) {
		std::vector<Zone> list;
		const int n = static_cast<int>(rng() % 12);
		for (int i = 0; i < n; ++i) {
			const int32_t cx = static_cast<int32_t>(rng() % 13), cy = static_cast<int32_t>(rng() % 13);
			const int32_t margin = static_cast<int32_t>(rng() % 9);
			list.push_back({cx * 16 - margin, cy * 16 - margin, cx * 16 + 15 + margin, cy * 16 + 15 + margin,
				static_cast<int32_t>(7 + rng() % 2), static_cast<uint16_t>(50 + 5 * (rng() % 11))});
		}
		const uint16_t global = (round % 50 == 49) ? 90 : 100;
		index.apply(global, list);
		same = current(spawns) == reference(spawns, global, list);
	}
	ok(same, "300 random zone lists: the same percents as the old way");

	std::printf("chaoszones_test: %d checks, %d failed\n", checks, fails);
	return fails == 0 ? 0 : 1;
}
