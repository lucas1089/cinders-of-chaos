// Tests of src/chaossave.h from engine src-patch 0026 (the incremental save's pure parts: the tick budget, the pass
// queue, the house signatures and the change test). CI takes the header out of the patch (the step "Incremental save,
// pure parts" in .github/workflows/ci.yml), then:
//   g++ -std=c++17 -Wall -Wextra -I "$d" server/tools/chaossave_test.cpp -o "$d/chaossave_test" && "$d/chaossave_test"
#include "chaossave.h"

#include <cstdio>
#include <string>
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

using namespace ChaosSave;

int main()
{
	// FNV-1a 64 test vectors (the published ones)
	ok(fnv1a("", 0) == 0xcbf29ce484222325ULL, "fnv1a of nothing");
	ok(fnv1a("a", 1) == 0xaf63dc4c8601ec8cULL, "fnv1a of a");
	ok(fnv1a(std::string("foobar")) == 0x85944171f73967e8ULL, "fnv1a of foobar");

	// tick budget: the first piece always runs; then count and time (with the last piece's time) decide
	TickBudget budget{10, 25};
	ok(budget.allows(0, 1000, 1000), "the first piece always runs, even over the budget");
	ok(budget.allows(1, 5, 5), "time left for another piece like the last");
	ok(!budget.allows(1, 21, 5), "no time for another piece like the last");
	ok(budget.allows(1, 20, 5), "exactly at the budget is still allowed");
	ok(!budget.allows(10, 0, 0), "at most maxItems pieces");
	ok(budget.allows(9, 0, 0), "below maxItems with time left");
	ok(budget.allows(3, 10, -4), "a negative last time counts as zero");
	{
		// a simulated tick: 6 ms per player fits 4 players in 25 ms (0, 6, 12, 18 -> the 5th would end at 30)
		uint32_t done = 0;
		int64_t elapsed = 0, last = 0;
		while (budget.allows(done, elapsed, last)) {
			elapsed += 6;
			last = 6;
			++done;
		}
		ok(done == 4, "6 ms players: 4 per tick");
		// 1 ms players: the count limit
		done = 0;
		elapsed = 0;
		last = 0;
		while (budget.allows(done, elapsed, last)) {
			elapsed += 1;
			last = 1;
			++done;
		}
		ok(done == 10, "1 ms players: 10 per tick");
		// one slow player (60 ms) still runs alone
		done = 0;
		elapsed = 0;
		last = 60;
		while (budget.allows(done, elapsed, last)) {
			elapsed += 60;
			++done;
		}
		ok(done == 1, "a slow player runs alone in its tick");
	}

	// the pass: players in order, then houses in chunks, then done
	SavePass pass;
	ok(!pass.running() && pass.getPhase() == SavePass::IDLE, "idle before the start");
	pass.start({5, 7, 9});
	ok(pass.running() && pass.getPhase() == SavePass::PLAYERS, "players first");
	ok(pass.playerCount() == 3 && pass.playersLeft() == 3, "three players queued");
	ok(pass.hasPlayer() && pass.takePlayer() == 5, "first player");
	ok(pass.takePlayer() == 7 && pass.takePlayer() == 9, "the others in order");
	ok(!pass.hasPlayer() && pass.playersDone(), "players done");
	pass.setHouses({1, 2, 3, 4, 5});
	ok(pass.getPhase() == SavePass::HOUSES && !pass.playersDone(), "houses next");
	std::vector<uint32_t> chunk = pass.takeHouses(2);
	ok(chunk.size() == 2 && chunk[0] == 1 && chunk[1] == 2, "first house chunk");
	chunk = pass.takeHouses(2);
	ok(chunk.size() == 2 && chunk[0] == 3, "second house chunk");
	chunk = pass.takeHouses(2);
	ok(chunk.size() == 1 && chunk[0] == 5, "last chunk is shorter");
	ok(!pass.hasHouses() && pass.running(), "no houses left, still running until finished");
	pass.finish();
	ok(!pass.running() && pass.getPhase() == SavePass::DONE, "finished");
	pass.start({});
	ok(pass.running() && !pass.hasPlayer() && pass.playersDone(), "no players online: straight to the houses");
	pass.setHouses({});
	ok(!pass.hasHouses(), "no changed houses");
	pass.abort();
	ok(!pass.running(), "aborted");

	// house tile signature: the order of the rows does not matter, their content does
	const std::string a("\x01\x02\x03\x04\x07\x01\x00\x00\x00item-a", 15), b("\x05\x02\x03\x04\x07\x01\x00\x00\x00item-b", 15);
	ok(houseTilesSignature({a, b}) == houseTilesSignature({b, a}), "row order does not matter");
	ok(houseTilesSignature({a, b}) != houseTilesSignature({a}), "a row less is a change");
	std::string a2 = a;
	a2[10] = 'X';
	ok(houseTilesSignature({a2, b}) != houseTilesSignature({a, b}), "a changed byte is a change");
	ok(houseTilesSignature({"ab", "c"}) != houseTilesSignature({"a", "bc"}), "bytes moved between rows are a change");
	ok(houseTilesSignature({}) == houseTilesSignature({}), "no rows is stable");
	ok(houseTilesSignature({}) != houseTilesSignature({std::string()}), "an empty row is not no row");

	// lists: order free, empty lists do not count
	ok(houseListsSignature({{256, "Alpha"}, {1, "Beta"}}) == houseListsSignature({{1, "Beta"}, {256, "Alpha"}}),
		"list order does not matter");
	ok(houseListsSignature({{256, "Alpha"}, {257, ""}}) == houseListsSignature({{256, "Alpha"}}), "empty lists do not count");
	ok(houseListsSignature({{256, "Alpha"}}) != houseListsSignature({{257, "Alpha"}}), "the list id counts");
	ok(houseListsSignature({{256, "Alpha"}}) != houseListsSignature({{256, "Alpha\nBeta"}}), "the text counts");
	ok(houseListsSignature({}) != houseTilesSignature({}), "lists and tiles never compare equal by accident");

	// info key: every column counts
	const std::string info = houseInfoKey(7, 1700000000, 0, "Harbour Street 1", 2, 5000, 40, 2);
	ok(info == houseInfoKey(7, 1700000000, 0, "Harbour Street 1", 2, 5000, 40, 2), "same row, same key");
	ok(info != houseInfoKey(8, 1700000000, 0, "Harbour Street 1", 2, 5000, 40, 2), "owner");
	ok(info != houseInfoKey(7, 1700000001, 0, "Harbour Street 1", 2, 5000, 40, 2), "paid");
	ok(info != houseInfoKey(7, 1700000000, 1, "Harbour Street 1", 2, 5000, 40, 2), "warnings");
	ok(info != houseInfoKey(7, 1700000000, 0, "Harbour Street 2", 2, 5000, 40, 2), "name");
	ok(info != houseInfoKey(7, 1700000000, 0, "Harbour Street 1", 3, 5000, 40, 2), "town");
	ok(info != houseInfoKey(7, 1700000000, 0, "Harbour Street 1", 2, 5001, 40, 2), "rent");
	ok(info != houseInfoKey(7, 1700000000, 0, "Harbour Street 1", 2, 5000, 41, 2), "size");
	ok(info != houseInfoKey(7, 1700000000, 0, "Harbour Street 1", 2, 5000, 40, 3), "beds");
	ok(houseInfoKey(1, 23, 0, "x", 0, 0, 0, 0) != houseInfoKey(12, 3, 0, "x", 0, 0, 0, 0), "separators keep columns apart");

	// the change test
	SavedHouse unknown;
	HouseDiff d = compareHouse(unknown, info, 1, 2);
	ok(d.info && d.lists && d.tiles, "an unknown house is written in full (first save without a startup read)");
	SavedHouse saved;
	saved.known = true;
	saved.hasRow = true;
	saved.info = info;
	saved.lists = 1;
	saved.tiles = 2;
	ok(!compareHouse(saved, info, 1, 2).any(), "unchanged house: nothing to write");
	d = compareHouse(saved, info, 1, 3);
	ok(d.tiles && !d.info && !d.lists, "only the tiles changed");
	d = compareHouse(saved, info, 4, 2);
	ok(d.lists && !d.info && !d.tiles, "only a list changed");
	d = compareHouse(saved, houseInfoKey(9, 1700000000, 0, "Harbour Street 1", 2, 5000, 40, 2), 1, 2);
	ok(d.info && !d.lists && !d.tiles, "only the owner changed");
	saved.hasRow = false;
	ok(compareHouse(saved, info, 1, 2).info, "no row in the database: the row is written");

	std::printf("chaossave_test: %d checks, %d failed\n", checks, fails);
	return fails == 0 ? 0 : 1;
}
