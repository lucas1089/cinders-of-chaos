// Unit test of the pathfinding parts of engine patch 0070 (server/src-patches/0070-cheaper-pathfinding.patch,
// src/chaospathing.h). CI takes chaospathing.h out of the patch and builds the test against it:
//   g++ -std=c++17 -O1 -Wall -Wextra -I DIR server/tools/chaospathing_test.cpp -o chaospathing_test   (exit 0 = all passed)
// What it proves: on thousands of random grids the new node store gives the same answer as the stock one (found or not,
// the same walk list, the same end tile, the same nodes taken from the open list, the same tile tests); the memo
// decisions of ChaosPath::decide for every case the engine meets (moved target, failed search, a walk list that no
// longer leads to the goal, the clock).
#include "path_memo_experiment.h"
#include "path_search_ref.h"
#include <iostream>
#include <random>

using namespace PathRef;
using ChaosPath::Spot;
using ChaosPath::Verdict;

static int fails = 0;
#define CHECK(c) do { if (!(c)) { if (++fails <= 30) std::cout << "FAIL line " << __LINE__ << ": " #c << std::endl; } } while (0)

static Grid randomGrid(std::mt19937& rng, int w, int h, double wall, bool crowd)
{
	Grid g;
	g.init(w, h);
	std::uniform_real_distribution<double> u(0, 1);
	for (int y = 0; y < h; ++y) {
		for (int x = 0; x < w; ++x) {
			g.at(x, y) = u(rng) < wall ? 2 : 1;
			if (crowd && u(rng) < 0.08) {
				g.creature[size_t(y) * w + x] = 1;
			}
		}
	}
	return g;
}

static Params randomParams(std::mt19937& rng)
{
	Params p;
	switch (rng() % 6) {
		case 0: p.fullPathSearch = true; p.maxSearchDist = 12; p.minTargetDist = 1; p.maxTargetDist = 1; break; // melee monster
		case 1: p.fullPathSearch = false; p.maxSearchDist = 12; p.minTargetDist = 1; p.maxTargetDist = 1; break;
		case 2: p.fullPathSearch = true; p.maxSearchDist = 12; p.minTargetDist = 1; p.maxTargetDist = 4 + rng() % 4; break; // ranged
		case 3: p.fullPathSearch = false; p.maxSearchDist = 0; p.minTargetDist = 0; p.maxTargetDist = 1 + rng() % 3; break; // 100 closed nodes
		case 4: p.fullPathSearch = false; p.clearSight = false; p.keepDistance = true; p.maxSearchDist = 12; p.minTargetDist = 1; p.maxTargetDist = 30; break; // fleeing
		default: p.fullPathSearch = true; p.allowDiagonal = false; p.maxSearchDist = 20; p.minTargetDist = 1; p.maxTargetDist = 1; break;
	}
	return p;
}

static void equivalence()
{
	std::mt19937 rng(20261022);
	uint64_t compared = 0, found = 0, capped = 0;
	for (int round = 0; round < 400; ++round) {
		const int w = 20 + rng() % 70, h = 20 + rng() % 70;
		const double wall = (rng() % 100) / 100.0 * 0.5;
		Grid g = randomGrid(rng, w, h, wall, rng() % 2);
		for (int q = 0; q < 40; ++q) {
			Pos a = g.pos(rng() % w, rng() % h), b = g.pos(rng() % w, rng() % h);
			g.at(g.gx(a), g.gy(a)) = 1;
			Params fpp = randomParams(rng);
			Condition cond{g, b};
			std::vector<int> d1, d2;
			Stats s1, s2;
			Pos e1, e2;
			const bool r1 = getPathMatching<StockNodes>(g, a, cond, fpp, d1, s1, &e1);
			const bool r2 = getPathMatching<FastNodes>(g, a, cond, fpp, d2, s2, &e2);
			++compared;
			found += r1;
			CHECK(r1 == r2);
			CHECK(d1 == d2);
			CHECK(!r1 || (e1.x == e2.x && e1.y == e2.y));
			CHECK(s1.expanded == s2.expanded);
			CHECK(s1.created == s2.created);
			CHECK(s1.tileTests == s2.tileTests);
			capped += s1.created >= MAX_NODES - 1;
			if (fails > 30) {
				return;
			}
		}
	}
	std::cout << "equivalence: " << compared << " searches, " << found << " found, " << capped << " hit the node cap" << std::endl;
	CHECK(found > compared / 5 && found < compared); // the mix has both answers
	CHECK(capped > 50);                              // and the node cap is reached often
}

static void store()
{
	using S = ChaosPath::NodeStore<Node, 512>;
	{   // the lowest f first, the lowest index among equals, a lowered f competes again
		S s;
		s.reset(10, 10);
		Node* start = s.getBestNode();
		CHECK(start && start->x == 10 && start->y == 10 && start->f == 0);
		Node* a = s.createOpenNode(start, 11, 10, 30);
		Node* b = s.createOpenNode(start, 12, 10, 20);
		Node* c = s.createOpenNode(start, 13, 10, 20);
		s.closeNode(start);
		CHECK(s.getClosedNodes() == 1);
		CHECK(s.getBestNode() == b); // 20 and 20: the lower index
		s.closeNode(b);
		CHECK(s.getBestNode() == c);
		s.closeNode(c);
		a->f = 5; // lowered while open
		s.openNode(a);
		CHECK(s.getBestNode() == a);
		s.closeNode(a);
		CHECK(s.getBestNode() == nullptr);
		b->f = 1; // reopened after it was closed
		s.openNode(b);
		CHECK(s.getClosedNodes() == 3);
		CHECK(s.getBestNode() == b);
		CHECK(s.getNodeByPosition(13, 10) == c && s.getNodeByPosition(14, 10) == nullptr);
	}
	{   // a reset forgets everything; positions that hash alike are told apart; the cap
		S s;
		for (int round = 0; round < 3; ++round) {
			s.reset(100, 100);
			Node* parent = s.getBestNode();
			int made = 0;
			for (int x = 0; x < 600; ++x) {
				Node* n = s.createOpenNode(parent, 200 + x * 17, 300 + (x * 31) % 97, 10 + x);
				if (n) { ++made; }
			}
			CHECK(made == 511); // MAX_NODES 512 with the start node
			CHECK(s.createOpenNode(parent, 1, 1, 1) == nullptr);
			for (int x = 0; x < 511; ++x) {
				Node* n = s.getNodeByPosition(200 + x * 17, 300 + (x * 31) % 97);
				CHECK(n && n->x == 200 + x * 17 && n->y == 300 + (x * 31) % 97);
			}
			s.reset(5, 5);
			CHECK(s.getNodeByPosition(200, 300) == nullptr);
		}
	}
	{   // the lease: the same store again and again, a second lease at the same time gets another one
		using L = ChaosPath::Lease<S>;
		S* first;
		{
			L a;
			first = &*a;
			L b;
			CHECK(&*b != &*a);
		}
		L c;
		CHECK(&*c == first);
	}
}

static void policy()
{
	using ChaosPath::Memo; using ChaosPath::Settings; using ChaosPath::decide; using ChaosPath::walkEnd;
	const Settings s;
	const Spot a{1000, 1000, 7}, t{1010, 1000, 7};
	const std::vector<int> none;
	const uint64_t pk = ChaosPath::paramsKey(true, true, true, false, 12, 1, 1);
	CHECK(pk != ChaosPath::paramsKey(false, true, true, false, 12, 1, 1));
	CHECK(pk != ChaosPath::paramsKey(true, true, true, false, 12, 1, 4));
	CHECK(pk != ChaosPath::paramsKey(true, true, true, false, 0, 1, 1));

	// walk lists run from the back: {E, E, S} = south first then two east
	const std::vector<int> l1 = {E, E, S};
	const Spot end = walkEnd(a, l1);
	CHECK(end.x == 1002 && end.y == 1001 && end.z == 7);
	const std::vector<int> diag = {NE, SW, W};
	const Spot dEnd = walkEnd(a, diag);
	CHECK(dEnd.x == 999 && dEnd.y == 1000);

	Memo m;
	CHECK(decide(m, 100, a, t, pk, l1, true, s) == Verdict::Search); // nothing remembered

	m.record(true, pk, a, t, l1, 1000);
	CHECK(decide(m, 1900, a, t, pk, l1, true, s) == Verdict::KeepPath);
	CHECK(decide(m, 2500, a, t, pk, l1, true, s) == Verdict::Search);          // older than reuseMs
	CHECK(decide(m, 1900, a, Spot{1011, 1000, 7}, pk, l1, true, s) == Verdict::Search); // the target moved
	CHECK(decide(m, 1900, a, Spot{1010, 1000, 6}, pk, l1, true, s) == Verdict::Search); // another floor
	CHECK(decide(m, 1900, a, t, pk + 1, l1, true, s) == Verdict::Search);      // other search rules
	CHECK(decide(m, 1900, a, t, pk, l1, false, s) == Verdict::Search);         // the walk was dropped (hasFollowPath false)
	CHECK(decide(m, 900, a, t, pk, l1, true, s) == Verdict::Search);           // the clock went back
	{   // one step walked: the rest still leads to the goal
		const std::vector<int> rest = {E, E};
		CHECK(decide(m, 1900, Spot{1000, 1001, 7}, t, pk, rest, true, s) == Verdict::KeepPath);
		// pushed one tile aside: the rest ends elsewhere
		CHECK(decide(m, 1900, Spot{1001, 1001, 7}, t, pk, rest, true, s) == Verdict::Search);
		// the list was cleared by something else
		CHECK(decide(m, 1900, Spot{1000, 1001, 7}, t, pk, none, true, s) == Verdict::Search);
	}
	{   // switched off
		Settings off;
		off.reuseMs = 0;
		CHECK(decide(m, 1100, a, t, pk, l1, true, off) == Verdict::Search);
	}
	{   // a path of no steps: the monster stands where the search ended
		Memo e;
		e.record(true, pk, a, t, none, 1000);
		CHECK(decide(e, 1500, a, t, pk, none, true, s) == Verdict::KeepPath);
		CHECK(decide(e, 1500, Spot{1001, 1000, 7}, t, pk, none, true, s) == Verdict::Search); // it was moved
	}
	{   // a failed search: the same tile, the same target, no path yet
		Memo f;
		f.record(false, pk, a, t, none, 1000);
		CHECK(decide(f, 3500, a, t, pk, none, false, s) == Verdict::KeepFailure);
		CHECK(decide(f, 4500, a, t, pk, none, false, s) == Verdict::Search);
		CHECK(decide(f, 3500, Spot{1001, 1000, 7}, t, pk, none, false, s) == Verdict::Search); // moved (pushed)
		CHECK(decide(f, 3500, a, Spot{1010, 1001, 7}, pk, none, false, s) == Verdict::Search);
		CHECK(decide(f, 3500, a, t, pk, none, true, s) == Verdict::Search); // somehow a path exists now
		Settings off;
		off.failMs = 0;
		CHECK(decide(f, 1100, a, t, pk, none, false, off) == Verdict::Search);
		f.clear();
		CHECK(decide(f, 1100, a, t, pk, none, false, s) == Verdict::Search);
	}
	// the memo records what a real search returned
	{
		Grid g;
		g.init(30, 5);
		for (int y = 0; y < 5; ++y) { for (int x = 0; x < 30; ++x) { g.at(x, y) = 1; } }
		const Pos from = g.pos(2, 2), to = g.pos(20, 2);
		Params fpp;
		fpp.maxSearchDist = 25; fpp.minTargetDist = 1; fpp.maxTargetDist = 1;
		std::vector<int> list;
		Stats st;
		CHECK(getPathMatching<FastNodes>(g, from, Condition{g, to}, fpp, list, st));
		Memo r;
		r.record(true, pk, Spot{from.x, from.y, 7}, Spot{to.x, to.y, 7}, list, 5);
		CHECK(list.size() == 17);
		CHECK(r.goal.x == to.x - 1 && r.goal.y == to.y); // stops next to the target
	}
}

int main()
{
	equivalence();
	store();
	policy();
	if (fails) {
		std::cout << fails << " checks failed" << std::endl;
		return 1;
	}
	std::cout << "chaospathing_test: all passed" << std::endl;
	return 0;
}
