// Tests of src/chaosfacing.h (server src-patch 0077): the eight-direction facing the creature packets carry.
// Build (CI): the header is cut out of the patch, then
//   g++ -std=c++17 -Wall -Wextra -I DIR server/tools/chaosfacing_test.cpp && ./a.out
#include "chaosfacing.h"

#include <cstdio>

using namespace ChaosFacing;

static int failures = 0;

static void check(bool ok, const char* what)
{
	if (!ok) {
		++failures;
		std::printf("FAIL %s\n", what);
	}
}

// the four-way direction Map::moveCreature gives a step (y first, then x wins)
static uint8_t straightOf(int dx, int dy, uint8_t before)
{
	uint8_t d = before;
	if (dy < 0) {
		d = NORTH;
	} else if (dy > 0) {
		d = SOUTH;
	}
	if (dx > 0) {
		d = EAST;
	} else if (dx < 0) {
		d = WEST;
	}
	return d;
}

// what the client draws for a direction byte without diagonal columns (Outfit::draw: north-east and south-east
// east, north-west and south-west west)
static uint8_t clientFold(uint8_t wireByte)
{
	if (wireByte == 4 || wireByte == 5) {
		return 1;
	}
	if (wireByte == 6 || wireByte == 7) {
		return 3;
	}
	return wireByte;
}

int main()
{
	// steps: the eight neighbours
	check(ofStep(0, -1, NORTH) == NORTH, "a step north faces north");
	check(ofStep(1, 0, EAST) == EAST, "a step east faces east");
	check(ofStep(0, 1, SOUTH) == SOUTH, "a step south faces south");
	check(ofStep(-1, 0, WEST) == WEST, "a step west faces west");
	check(ofStep(1, -1, EAST) == NORTHEAST, "a step north-east");
	check(ofStep(1, 1, EAST) == SOUTHEAST, "a step south-east");
	check(ofStep(-1, 1, WEST) == SOUTHWEST, "a step south-west");
	check(ofStep(-1, -1, WEST) == NORTHWEST, "a step north-west");
	check(ofStep(0, 0, SOUTH) == SOUTH, "no step keeps the direction");

	// a diagonal step still leaves the four-way direction the engine gives (east or west), so combat is unchanged
	for (int dx = -1; dx <= 1; ++dx) {
		for (int dy = -1; dy <= 1; ++dy) {
			if (dx == 0 || dy == 0) {
				continue;
			}
			const uint8_t d = straightOf(dx, dy, SOUTH);
			check(d == (dx > 0 ? EAST : WEST), "the direction of a diagonal step is east or west");
			const uint8_t f = ofStep(dx, dy, d);
			check(f >= SOUTHWEST && f <= NORTHEAST, "the facing of a diagonal step is a diagonal");
			// a client without diagonal columns draws what it drew before the patch
			check(clientFold(wire(f)) == d, "an old look draws the direction it drew before");
		}
	}

	// toward a target: the axis when the target lies near it, the diagonal between
	check(toward(1, -1, NORTH) == NORTHEAST, "a target on the diagonal");
	check(toward(-3, 3, WEST) == SOUTHWEST, "a target far on the diagonal");
	check(toward(2, 1, EAST) == SOUTHEAST, "2 by 1 is nearer the diagonal (26.6 degrees)");
	check(toward(-1, -2, NORTH) == NORTHWEST, "1 by 2 is nearer the diagonal");
	check(toward(3, 1, EAST) == EAST, "3 by 1 is nearer the axis (18.4 degrees)");
	check(toward(1, 3, SOUTH) == SOUTH, "1 by 3 is nearer the axis");
	check(toward(5, 2, EAST) == EAST, "5 by 2 is on the line (0.4): the axis");
	check(toward(5, 3, EAST) == SOUTHEAST, "5 by 3 is past the line: the diagonal");
	check(toward(4, 0, EAST) == EAST, "a target on the row");
	check(toward(0, -4, NORTH) == NORTH, "a target on the column");
	check(toward(0, 0, WEST) == WEST, "a target on the same tile keeps the turn");
	// every offset: the diagonal toward agrees with the quadrant, the straight fallback is passed through
	for (int dx = -8; dx <= 8; ++dx) {
		for (int dy = -8; dy <= 8; ++dy) {
			const uint8_t f = toward(dx, dy, EAST);
			if (f == EAST) {
				continue;
			}
			check(f == ofStep(dx, dy, EAST), "a diagonal toward the target's quadrant");
		}
	}

	// the wire byte in the client's order
	check(wire(NORTH) == 0 && wire(EAST) == 1 && wire(SOUTH) == 2 && wire(WEST) == 3, "straight bytes unchanged");
	check(wire(NORTHEAST) == 4, "north-east is the client's 4");
	check(wire(SOUTHEAST) == 5, "south-east is the client's 5");
	check(wire(SOUTHWEST) == 6, "south-west is the client's 6");
	check(wire(NORTHWEST) == 7, "north-west is the client's 7");
	check(wire(NONE) == 2 && wire(200) == 2, "anything else is sent as south");

	std::printf("chaosfacing_test: %d failures\n", failures);
	return failures == 0 ? 0 : 1;
}
