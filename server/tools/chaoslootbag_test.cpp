// Tests of src/chaoslootbag.h (engine src-patch 0089, the loot bag instead of monster bodies; server/README.md "Loot bag
// instead of corpses"). CI cuts the header out of the patch and builds this file against it:
//   g++ -std=c++17 -Wall -Wextra -I <dir with chaoslootbag.h> server/tools/chaoslootbag_test.cpp
// Checks: off (bag id 0) changes nothing; a monster with a corpse leaves the bag; a monster with no corpse (0) leaves
// nothing; the kept corpse ids stay; the bag itself is not mapped again; the table can be replaced and switched off.
#include "chaoslootbag.h"

#include <cstdio>

static int failures = 0;
static int checks = 0;

static void eq(unsigned got, unsigned want, const char* what)
{
	++checks;
	if (got != want) {
		++failures;
		std::printf("FAIL %s: got %u, want %u\n", what, got, want);
	}
}

int main()
{
	// nothing set (Game.setMonsterLootBag never called): the engine behaves as before
	eq(ChaosLootBag::corpseOf(ChaosLootBag::current(), 5972), 5972, "unset: a dragon keeps its corpse");
	eq(ChaosLootBag::corpseOf(ChaosLootBag::current(), 0), 0, "unset: no corpse stays none");

	ChaosLootBag::Config on;
	on.bagId = 6068;
	on.keep = {8967, 8969, 12545};
	eq(ChaosLootBag::corpseOf(on, 5972), 6068, "a monster with a corpse leaves the bag");
	eq(ChaosLootBag::corpseOf(on, 65535), 6068, "the highest corpse id too");
	eq(ChaosLootBag::corpseOf(on, 1), 6068, "the lowest corpse id too");
	eq(ChaosLootBag::corpseOf(on, 0), 0, "a monster with corpse 0 leaves nothing");
	eq(ChaosLootBag::corpseOf(on, 6068), 6068, "the bag stays the bag");
	eq(ChaosLootBag::corpseOf(on, 8967), 8967, "a kept corpse stays (quest)");
	eq(ChaosLootBag::corpseOf(on, 12545), 12545, "a kept corpse stays (quest 2)");
	eq(ChaosLootBag::corpseOf(on, 8966), 6068, "a corpse next to a kept id is not kept");

	ChaosLootBag::Config off;
	off.keep = {8967};
	eq(ChaosLootBag::corpseOf(off, 5972), 5972, "bag id 0: switched off");

	// the table the engine reads is replaced as a whole
	ChaosLootBag::current() = on;
	eq(ChaosLootBag::corpseOf(ChaosLootBag::current(), 5972), 6068, "current(): on");
	ChaosLootBag::current() = ChaosLootBag::Config();
	eq(ChaosLootBag::corpseOf(ChaosLootBag::current(), 5972), 5972, "current(): reset is off");

	std::printf("chaoslootbag_test: %d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
