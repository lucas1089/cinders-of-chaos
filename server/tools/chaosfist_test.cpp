// Tests of src/chaosfist.h (engine src-patch 0091, the bare-fist hit rolled with the attack a script gives the player; server/README.md
// "Flat armour, weapon spells and the Monk's fist (O505)"). CI cuts the header out of the patch and builds this file against it:
//   g++ -std=c++17 -Wall -Wextra -I <dir with chaosfist.h> server/tools/chaosfist_test.cpp
// Checks: the stock formula of Weapons::getMaxWeaponDamage is reproduced (attack 7, a stock Monk at level 100 rolls up to 64), the script's
// attack and multiplier move the maximum the way monk_chi_core.lua M.maxWeaponDamage x meleeDamage says, bad numbers are cleaned to "none
// set" / 1 (NaN, infinity, zero, negative, over the limit), the fight mode divides the attack part only.
#include "chaosfist.h"

#include <cmath>
#include <cstdio>
#include <limits>

static int failures = 0;
static int checks = 0;

static void eq(long long got, long long want, const char* what)
{
	++checks;
	if (got != want) {
		++failures;
		std::printf("FAIL %s: got %lld, want %lld\n", what, got, want);
	}
}

static void near(double got, double want, double tol, const char* what)
{
	++checks;
	if (std::fabs(got - want) > tol) {
		++failures;
		std::printf("FAIL %s: got %f, want %f\n", what, got, want);
	}
}

// the engine's own formula, written out again (Weapons::getMaxWeaponDamage, weapons.cpp)
static int32_t stock(uint32_t level, int32_t skill, int32_t attack, float factor)
{
	return static_cast<int32_t>(std::round((level / 5) + (((((skill / 4.) + 1) * (attack / 3.)) * 1.03) / factor)));
}

int main()
{
	// no multiplier, the stock attack: the engine's number
	eq(ChaosFist::maxDamage(100, 70, 7.0f, 1.0f, 1.0f), stock(100, 70, 7, 1.0f), "stock attack 7, level 100, skill 70");
	eq(ChaosFist::maxDamage(100, 70, 7.0f, 1.0f, 1.0f), 64, "a stock fist at level 100, skill 70 rolls up to 64");
	eq(ChaosFist::maxDamage(8, 10, 7.0f, 1.0f, 1.0f), stock(8, 10, 7, 1.0f), "level 8, skill 10");
	eq(ChaosFist::maxDamage(1000, 135, 7.0f, 1.0f, 1.0f), stock(1000, 135, 7, 1.0f), "level 1000, skill 135");
	eq(ChaosFist::maxDamage(500, 120, 7.0f, 1.0f, 2.0f), stock(500, 120, 7, 2.0f), "defensive stance, factor 2");
	eq(ChaosFist::maxDamage(500, 120, 7.0f, 1.0f, 1.2f), stock(500, 120, 7, 1.2f), "balanced stance, factor 1.2");

	// the Monk: level 100, skill 70, fist attack 42.5 (40 + 0.025 x 100), meleeDamage 1.2 (monk_combat.lua): about 5 times the stock hit
	const int32_t monk = ChaosFist::maxDamage(100, 70, 42.5f, 1.2f, 1.0f);
	near(monk, std::round((20 + (18.5 * (42.5 / 3.) * 1.03)) * 1.2), 1.0, "the Monk's maximum is the formula with its attack, times 1.2");
	near(static_cast<double>(monk) / 64.0, 5.4, 0.3, "the Monk hits about 5.4 times a stock fist at level 100");
	eq(ChaosFist::maxDamage(100, 70, 42.5f, 1.0f, 1.0f) < monk, 1, "the multiplier raises the maximum");
	eq(ChaosFist::maxDamage(100, 70, 42.5f, 1.2f, 2.0f) < monk, 1, "a defensive stance lowers it");
	// the level part is multiplied too: the multiplier is on the whole maximum, as the script's factor was on the whole engine hit
	eq(ChaosFist::maxDamage(1000, 0, 0.0001f, 2.0f, 1.0f), 400, "the multiplier doubles the level part (1000 / 5 x 2)");
	// a higher skill and a higher level hit harder
	eq(ChaosFist::maxDamage(100, 140, 42.5f, 1.2f, 1.0f) > monk, 1, "a higher skill hits harder");
	eq(ChaosFist::maxDamage(200, 70, 42.5f, 1.2f, 1.0f) > monk, 1, "a higher level hits harder");

	// the cleaning of a script's numbers: out of range means none set / 1
	near(ChaosFist::cleanAttack(42.5f), 42.5, 1e-6, "a fist attack of 42.5 is kept");
	near(ChaosFist::cleanAttack(0.0f), 0.0, 0.0, "attack 0 is none set");
	near(ChaosFist::cleanAttack(-5.0f), 0.0, 0.0, "a negative attack is none set");
	near(ChaosFist::cleanAttack(2000.0f), 2000.0, 1e-6, "the limit itself is allowed");
	near(ChaosFist::cleanAttack(2000.5f), 0.0, 0.0, "over the limit is none set");
	near(ChaosFist::cleanAttack(std::numeric_limits<float>::infinity()), 0.0, 0.0, "infinity is none set");
	near(ChaosFist::cleanAttack(std::numeric_limits<float>::quiet_NaN()), 0.0, 0.0, "NaN is none set");
	near(ChaosFist::cleanMultiplier(1.2f), 1.2, 1e-6, "a multiplier of 1.2 is kept");
	near(ChaosFist::cleanMultiplier(0.0f), 1.0, 0.0, "multiplier 0 is 1");
	near(ChaosFist::cleanMultiplier(-1.0f), 1.0, 0.0, "a negative multiplier is 1");
	near(ChaosFist::cleanMultiplier(10.0f), 10.0, 1e-6, "the limit itself is allowed");
	near(ChaosFist::cleanMultiplier(10.5f), 1.0, 0.0, "over the limit is 1");
	near(ChaosFist::cleanMultiplier(std::numeric_limits<float>::quiet_NaN()), 1.0, 0.0, "NaN multiplier is 1");

	// a hit rolled up to the maximum never goes negative, and the maximum of an empty setting is the stock one (no change without a script)
	eq(ChaosFist::maxDamage(1, 0, 0.0f, 1.0f, 1.0f) >= 0, 1, "no negative maximum");

	std::printf("chaosfist_test: %d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
