// Tests of src/chaosdisplay.h (engine src-patch 0037, the display scale; server/README.md "Display scale").
// CI cuts the header out of the patch and builds this file against it:
//   g++ -std=c++17 -Wall -Wextra -I <dir with chaosdisplay.h> server/tools/chaosdisplay_test.cpp
// Checks: no table means factor 1 everywhere; the table's lookup (level 0, past the end = the cap, a 0 entry); the
// uint32 clamp of the packet fields (negative, overflow, the exact limit); the text rule (only numbers followed by
// hitpoints / mana / energy shield / health, names and other numbers untouched, a sum stays a sum); 2^53 in texts.
#include "chaosdisplay.h"

#include <cstdio>
#include <cstdlib>
#include <string>

static int failures = 0;
static int checks = 0;

template <typename A, typename B>
static void eq(const A& got, const B& want, const char* what)
{
	++checks;
	if (!(got == want)) {
		++failures;
		std::printf("FAIL %s\n", what);
	}
}

static void eqs(const std::string& got, const std::string& want, const char* what)
{
	++checks;
	if (got != want) {
		++failures;
		std::printf("FAIL %s: got \"%s\" want \"%s\"\n", what, got.c_str(), want.c_str());
	}
}

int main()
{
	using namespace ChaosDisplay;
	const uint32_t U32 = 4294967295u;

	// no table (an engine whose Lua never called Game.setDisplayScale): everything as before
	table().clear();
	eq(factorOf(1), 1u, "no table: level 1");
	eq(factorOf(1000), 1u, "no table: level 1000");
	eqs(scaleText("You lose 120 hitpoints.", factorOf(1000)), "You lose 120 hitpoints.", "no table: text unchanged");

	// a table like display_scale.lua's: 1 up to 100, 1000 at 1000, 10000 at the last entry (the cap)
	std::vector<uint32_t> t(1500, 1);
	for (size_t level = 101; level <= 1500; ++level) {
		t[level - 1] = level < 1000 ? static_cast<uint32_t>(level / 10) : (level < 1500 ? 1000 : 10000);
	}
	t[1199] = 0; // a bad entry reads as 1
	table() = t;
	eq(factorOf(0), 1u, "level 0 is level 1");
	eq(factorOf(1), 1u, "level 1");
	eq(factorOf(100), 1u, "level 100");
	eq(factorOf(700), 70u, "level 700");
	eq(factorOf(1000), 1000u, "level 1000");
	eq(factorOf(1200), 1u, "a 0 entry is 1");
	eq(factorOf(1500), 10000u, "the last entry");
	eq(factorOf(5000), 10000u, "past the table: the cap");
	eq(factorOf(4294967295u), 10000u, "the largest level");

	// packet fields (uint32)
	eq(scaleU32(0, 1000), 0u, "zero");
	eq(scaleU32(-5, 1000), 0u, "a negative value is 0");
	eq(scaleU32(2600, 1000), 2600000u, "2600 x 1000");
	eq(scaleU32(2600, 1), 2600u, "factor 1");
	eq(scaleU32(2147483647, 1), 2147483647u, "int32 max, factor 1");
	eq(scaleU32(4294967, 1000), 4294967000u, "just below the limit");
	eq(scaleU32(4294968, 1000), U32, "just above the limit: clamped");
	eq(scaleU32(2147483647, 10000), U32, "int32 max x cap: clamped");
	eq(scale(9007199254740992ULL, 2, TEXT_MAX), TEXT_MAX, "text bound");
	eq(scale(5, 0, 100), 5u, "factor 0 reads as 1");

	// texts of Game::combatChangeHealth / combatChangeMana / the conditions / the energy shield (patch 0015)
	eqs(scaleText("A dragon loses 120 hitpoints due to your attack.", 1000),
		"A dragon loses 120000 hitpoints due to your attack.", "damage dealt");
	eqs(scaleText("You lose 1 hitpoint due to an attack by a rat.", 22), "You lose 22 hitpoints due to an attack by a rat.",
		"one hitpoint shown as 22: plural");
	eqs(scaleText("You lose 1 hitpoint due to an attack by a rat.", 1), "You lose 1 hitpoint due to an attack by a rat.",
		"factor 1: as it was");
	eqs(scaleText("You lose 1 hitpoint.", 5), "You lose 5 hitpoints.", "plural at the end of the text");
	eqs(scaleText("You heal Knight for 300 hitpoints.", 5), "You heal Knight for 1500 hitpoints.", "heal");
	eqs(scaleText("You gained 45 mana.", 100), "You gained 4500 mana.", "mana gain");
	eqs(scaleText("You lose 80 mana due to an attack by a demon.", 3), "You lose 240 mana due to an attack by a demon.",
		"mana drain");
	eqs(scaleText("Knight loses 70 energy shield due to your attack.", 10), "Knight loses 700 energy shield due to your attack.",
		"energy shield");
	eqs(scaleText("A training dummy 2 loses 10 hitpoints.", 10), "A training dummy 2 loses 100 hitpoints.",
		"a number in a name stays");
	eqs(scaleText("Level 500 Orc loses 7 hitpoints.", 10), "Level 500 Orc loses 70 hitpoints.", "a level stays");
	eqs(scaleText("You gained 1500 experience points.", 1000), "You gained 1500 experience points.", "experience stays");
	eqs(scaleText("x12 hitpoints and 1.5 mana", 10), "x12 hitpoints and 1.5 mana", "glued to a letter or a decimal: stays");
	eqs(scaleText("You lose 4294967 hitpoints.", 10000), "You lose 42949670000 hitpoints.", "a text is not uint32 bound");
	eqs(scaleText("You lose 99999999999999999999 hitpoints.", 10), "You lose 99999999999999999999 hitpoints.",
		"too long to read: stays");
	eqs(scaleText("", 10), "", "empty");
	// the text shows primary + secondary; with a whole factor the scaled parts still add up to the scaled text
	eq(static_cast<uint64_t>(scaleU32(97, 464)) + scaleU32(31, 464), scale(97 + 31, 464, TEXT_MAX), "parts add up");

	std::printf("chaosdisplay_test: %d checks, %d failures\n", checks, failures);
	return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
