// Tests of src/chaosfxoffsets.h (server src-patch 0060): send offsets of the effects redrawn in place, applied by the
// engine to every effect packet.
// Build (CI): the header is cut out of the patch, then
//   g++ -std=c++17 -Wall -Wextra -I DIR server/tools/chaosfxoffsets_test.cpp && ./a.out
#include "chaosfxoffsets.h"

#include <cstdio>

static int failures = 0;

static void check(bool ok, const char* what)
{
	if (!ok) {
		++failures;
		std::printf("FAIL %s\n", what);
	}
}

// what ProtocolGame::sendMagicEffect does with the table: -> sent?, and the x, y it is sent at
struct Sent {
	bool sent;
	uint16_t x;
	uint16_t y;
};

static Sent send(const ChaosFxSendOffsets& t, uint16_t x, uint16_t y, uint16_t effect, uint32_t w, uint32_t h,
                 bool seesTarget, bool seesShifted)
{
	const ChaosFxOffset* o = t.get(effect);
	if (!o) {
		return {seesTarget, x, y};
	}
	const uint16_t sx = chaosFxShiftAxis(x, o->dx, w), sy = chaosFxShiftAxis(y, o->dy, h);
	switch (chaosFxSendAt(seesTarget, seesShifted)) {
		case CHAOS_FX_SEND_SHIFTED:
			return {true, sx, sy};
		case CHAOS_FX_SEND_TARGET:
			return {true, x, y};
		default:
			return {false, x, y};
	}
}

int main()
{
	// empty by default: every effect at its tile, as an engine without the patch
	check(chaosFxSendOffsets().size() == 0, "the server table starts empty");
	check(chaosFxSendOffsets().get(405) == nullptr, "405 at its tile before Lua sets the table");

	ChaosFxSendOffsets t;
	// rows of data/lib/chaos_fx_send_offsets.lua: 405 (4x4) two tiles, 15 (3x3) one, 173 (2x3) one down
	check(t.set(405, 2, 2), "405 stored");
	check(t.set(15, 1, 1), "15 stored");
	check(t.set(173, 0, 1), "173 stored");
	// refused: effect 0, an id past uint16, no offset, an offset past the limit
	check(!t.set(0, 1, 1), "effect 0 refused");
	check(!t.set(0x10000, 1, 1), "id past 65535 refused");
	check(!t.set(40, 0, 0), "0, 0 not stored (stock placement)");
	check(!t.set(41, CHAOS_FX_MAX_OFFSET + 1, 0), "dx past the limit refused");
	check(!t.set(42, 0, -CHAOS_FX_MAX_OFFSET - 1), "dy past the limit refused");
	check(t.size() == 3, "three ids stored");
	const ChaosFxOffset* o = t.get(405);
	check(o && o->dx == 2 && o->dy == 2, "405 is 2, 2");
	check(t.get(40) == nullptr, "40 (2x2) not shifted");

	// the owner's report (Banner Call's holy_spiral 405): two tiles right and down, a viewer seeing both tiles
	Sent s = send(t, 100, 200, 405, 2048, 2048, true, true);
	check(s.sent && s.x == 102 && s.y == 202, "405 sent two tiles right and down");
	s = send(t, 100, 200, 173, 2048, 2048, true, true);
	check(s.sent && s.x == 100 && s.y == 201, "173 (crit) one tile down");
	s = send(t, 100, 200, 7777, 2048, 2048, true, true);
	check(s.sent && s.x == 100 && s.y == 200, "an unlisted id at its tile");
	// a viewer at the edge of the view: sees the target, not the centring tile -> the target tile, as before
	s = send(t, 100, 200, 405, 2048, 2048, true, false);
	check(s.sent && s.x == 100 && s.y == 200, "viewer at the edge still gets it, at the target");
	// a viewer that sees only the centring tile gets it there; one that sees neither gets nothing
	s = send(t, 100, 200, 405, 2048, 2048, false, true);
	check(s.sent && s.x == 102 && s.y == 202, "viewer of the centring tile only gets it there");
	s = send(t, 100, 200, 405, 2048, 2048, false, false);
	check(!s.sent, "a viewer that sees neither tile gets nothing");
	s = send(t, 100, 200, 7777, 2048, 2048, false, true);
	check(!s.sent, "an unlisted id: the stock canSee of its tile");

	// kept on the map: the last row / column of a 2048 x 1024 map, and 65535 without a map size
	s = send(t, 2047, 1023, 405, 2048, 1024, true, true);
	check(s.x == 2047 && s.y == 1023, "clamped at the map's last tile");
	s = send(t, 2046, 1022, 405, 2048, 1024, true, true);
	check(s.x == 2047 && s.y == 1023, "clamped one tile short of the edge");
	check(chaosFxShiftAxis(65535, 2, 0) == 65535, "no map size: clamped at 65535");
	check(chaosFxShiftAxis(1, -3, 2048) == 0, "a negative offset stops at 0");
	check(chaosFxShiftAxis(10, -3, 2048) == 7, "a negative offset");
	check(chaosFxShiftAxis(10, 2, 0x20000) == 12, "a bogus map size: 65535 bound");

	// replaced as a whole (Game.setFxSendOffsets clears first)
	t.clear();
	check(t.size() == 0 && t.get(405) == nullptr, "clear: every effect at its tile again");

	std::printf("chaosfxoffsets_test: %d failures\n", failures);
	return failures == 0 ? 0 : 1;
}
