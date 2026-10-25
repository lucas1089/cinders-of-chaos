// Chaos (O211): an experiment that was measured and NOT shipped (server/README.md "Cheaper monster pathfinding (O211)").
// A monster that follows a creature remembers its last search. When the target has not moved and the remembered answer
// still holds, the next search is skipped: a path that is still being walked (the rest of the walk list still leads to the
// same goal) for reuseMs, a failed search from the same tile for failMs. path_bench.cpp plays it as the third row of each
// chase; chaospathing_test.cpp tests the decisions. On the real map it saved 3-20% of the searches and changed how a pack
// reroutes around its own members, so the engine patch leaves it out.
#ifndef PATH_MEMO_EXPERIMENT_H
#define PATH_MEMO_EXPERIMENT_H

#include <cstdint>
#include <vector>

namespace ChaosPath {

struct Spot {
	uint16_t x = 0, y = 0;
	uint8_t z = 0;
	bool operator==(const Spot& o) const { return x == o.x && y == o.y && z == o.z; }
	bool operator!=(const Spot& o) const { return !(*this == o); }
};

// the engine's Direction numbering (position.h): N 0, E 1, S 2, W 3, SW 4, SE 5, NW 6, NE 7
inline int dirDx(int d)
{
	static const int dx[8] = {0, 1, 0, -1, -1, 1, -1, 1};
	return d >= 0 && d < 8 ? dx[d] : 0;
}

inline int dirDy(int d)
{
	static const int dy[8] = {-1, 0, 1, 0, 1, 1, -1, -1};
	return d >= 0 && d < 8 ? dy[d] : 0;
}

// the tile a walk list ends on: the last element is the first step (Creature::getNextStep pops from the back)
template<typename List>
Spot walkEnd(Spot from, const List& list)
{
	for (auto it = list.rbegin(); it != list.rend(); ++it) {
		from.x = static_cast<uint16_t>(from.x + dirDx(static_cast<int>(*it)));
		from.y = static_cast<uint16_t>(from.y + dirDy(static_cast<int>(*it)));
	}
	return from;
}

// every field of FindPathParams that changes what a search answers, in one number
inline uint64_t paramsKey(bool fullPathSearch, bool clearSight, bool allowDiagonal, bool keepDistance,
                          int32_t maxSearchDist, int32_t minTargetDist, int32_t maxTargetDist)
{
	uint64_t k = (fullPathSearch ? 1u : 0u) | (clearSight ? 2u : 0u) | (allowDiagonal ? 4u : 0u) | (keepDistance ? 8u : 0u);
	k |= static_cast<uint64_t>(static_cast<uint8_t>(maxSearchDist)) << 8;
	k |= static_cast<uint64_t>(static_cast<uint8_t>(minTargetDist)) << 16;
	k |= static_cast<uint64_t>(static_cast<uint8_t>(maxTargetDist)) << 24;
	return k;
}

struct Settings {
	int64_t reuseMs = 1500; // a path that is still being walked to an unmoved target: no new search for this long (0 = always search)
	int64_t failMs = 3000;  // a failed search from the same tile to an unmoved target: no new search for this long (0 = always search)
};

struct Memo {
	bool valid = false;
	bool ok = false;
	uint64_t params = 0;
	Spot start, target, goal;
	int64_t time = 0;

	void clear() { valid = false; }

	template<typename List>
	void record(bool found, uint64_t paramsKey, Spot from, Spot to, const List& walkList, int64_t now)
	{
		valid = true;
		ok = found;
		params = paramsKey;
		start = from;
		target = to;
		goal = found ? walkEnd(from, walkList) : from;
		time = now;
	}
};

enum class Verdict { Search, KeepPath, KeepFailure };

// What a monster that wants a path to `target` does. Search = run the A*; KeepPath = the walk list stays as it is
// (hasFollowPath stays true); KeepFailure = no path stays no path.
template<typename List>
Verdict decide(const Memo& m, int64_t now, Spot start, Spot target, uint64_t paramsKey, const List& walkList,
               bool hasFollowPath, const Settings& s)
{
	if (!m.valid || m.params != paramsKey || m.target != target) {
		return Verdict::Search;
	}

	const int64_t age = now - m.time;
	if (age < 0) {
		return Verdict::Search;
	}

	if (!m.ok) {
		if (s.failMs > 0 && age < s.failMs && !hasFollowPath && start == m.start) {
			return Verdict::KeepFailure;
		}
		return Verdict::Search;
	}

	if (s.reuseMs <= 0 || age >= s.reuseMs || !hasFollowPath) {
		return Verdict::Search;
	}

	if (walkList.empty()) {
		// standing where the last search ended (or started, with an empty path): the same answer
		return start == m.start && m.goal == m.start ? Verdict::KeepPath : Verdict::Search;
	}
	return walkEnd(start, walkList) == m.goal ? Verdict::KeepPath : Verdict::Search;
}

} // namespace ChaosPath

#endif
