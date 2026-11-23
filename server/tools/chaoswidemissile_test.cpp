// Tests of src/chaoswidemissile.h (engine src-patch 0094, missile ids above 255; server/README.md "Missile ids above 255 (O737)").
// CI cuts the header out of the patch and builds this file against it:
//   g++ -std=c++17 -Wall -Wextra -I <dir with chaoswidemissile.h> server/tools/chaoswidemissile_test.cpp
// Checks: the "W" block of the login is read only inside the RSA block and only the exact marker with bit 0 asks (zero padding of an
// older client and random padding of another client never ask, 100000 random blocks); the client adds the block only when it fits; the
// wire of one missile per kind of client (u16 when told feature 77, one byte up to 255, the fallback or nothing above it); the fallback
// table's limits; a missile written as a number; and the 0x85 bodies the server writes read back the way the client reads them.
#include "chaoswidemissile.h"

#include <cstdio>
#include <random>
#include <vector>

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

using Bytes = std::vector<uint8_t>;
using namespace ChaosWideMissile;

// the read of ProtocolGame::onRecvFirstMessage after the capability byte, on a decrypted block (position: right after the byte)
static bool serverAsks(const Bytes& block, size_t position)
{
	const size_t end = block.size();
	if (!markerFits(position, end)) {
		return false;
	}
	const uint16_t length = static_cast<uint16_t>(block[position] | (block[position + 1] << 8));
	if (length != 1) {
		return false;
	}
	return markerAsks(length, block[position + 2], block[position + 3]);
}

// the client's write (base patch 0208): the "W" block when it fits, then the padding (zeros) up to 128 bytes
static Bytes clientBlock(size_t payload, uint8_t caps, bool randomPad, std::mt19937& rng)
{
	Bytes b(payload, 0x11);
	if (clientFits(static_cast<int>(payload), 128)) {
		b.push_back(1);
		b.push_back(0);
		b.push_back(static_cast<uint8_t>(MARKER));
		b.push_back(caps);
	}
	while (b.size() < 128) {
		b.push_back(randomPad ? static_cast<uint8_t>(rng() & 0xFF) : 0);
	}
	return b;
}

// the 0x85 body the server writes for one decision
static Bytes body(const Send& s)
{
	Bytes b{0x85, 1, 0, 2, 0, 7, 3, 0, 4, 0, 7};
	if (s.wire == Wire::WORD) {
		b.push_back(static_cast<uint8_t>(s.id & 0xFF));
		b.push_back(static_cast<uint8_t>(s.id >> 8));
	} else if (s.wire == Wire::BYTE) {
		b.push_back(static_cast<uint8_t>(s.id));
	}
	return b;
}

// the client's parseDistanceMissile: u16 under feature 77, else u8; -1 when the body is not exactly one missile
static long long clientReads(const Bytes& b, bool feature77)
{
	const size_t need = 11 + (feature77 ? 2 : 1);
	if (b.size() != need || b[0] != 0x85) {
		return -1;
	}
	return feature77 ? (b[11] | (b[12] << 8)) : b[11];
}

int main()
{
	std::mt19937 rng(737);

	// constants the other side holds too
	eq(MARKER, 'W', "the marker is W");
	eq(CAPABILITY_MISSILE_U16, 1, "bit 0 asks");
	eq(MARKER_BYTES, 4, "u16 length, letter, byte");
	eq(FEATURE_DISTANCE_EFFECT_U16, 77, "the engine's GameDistanceEffectU16");
	eq(WEAPON_TYPE, 254, "CONST_ANI_WEAPONTYPE");
	eq(FIRST_WIDE, 256, "new missiles start at 256");

	// markerFits: inside the block only
	eq(markerFits(124, 128), 1, "four bytes left fit");
	eq(markerFits(125, 128), 0, "three bytes left do not");
	eq(markerFits(128, 128), 0, "nothing left");
	eq(markerFits(200, 128), 0, "past the end");
	eq(clientFits(124, 128), 1, "the client adds the block with four bytes of room");
	eq(clientFits(125, 128), 0, "not with three");
	eq(clientFits(10, 0), 0, "no RSA block: nothing");

	// markerAsks: the exact marker and bit 0
	eq(markerAsks(1, 'W', 1), 1, "the marker with bit 0");
	eq(markerAsks(1, 'W', 0xFF), 1, "other bits do not matter");
	eq(markerAsks(1, 'W', 0xFE), 0, "without bit 0");
	eq(markerAsks(0, 0, 0), 0, "zero padding");
	eq(markerAsks(1, 'C', 1), 0, "another letter");
	eq(markerAsks(2, 'W', 1), 0, "another length");

	// a typical login: payload of 80 bytes, the block added and read back
	Bytes b = clientBlock(80, CAPABILITY_MISSILE_U16, false, rng);
	eq(b.size(), 128, "one RSA block");
	eq(serverAsks(b, 80), 1, "our client asks");
	// an older client of ours: the byte after the capability byte is zero padding
	Bytes old(80, 0x11);
	old.resize(128, 0);
	eq(serverAsks(old, 80), 0, "an older client (zero padding) does not ask");
	// a long session key: no room, the client leaves the block out and the server reads nothing
	b = clientBlock(126, CAPABILITY_MISSILE_U16, false, rng);
	eq(b.size(), 128, "a full block stays one block");
	eq(serverAsks(b, 126), 0, "no room: no ask, nothing read past the block");
	b = clientBlock(124, CAPABILITY_MISSILE_U16, false, rng);
	eq(serverAsks(b, 124), 1, "exactly four bytes of room: asks");

	// random padding (a client that pads its block with random bytes) never asks
	long long randomAsks = 0;
	for (int i = 0; i < 100000; ++i) {
		Bytes r(60, 0x11);
		while (r.size() < 128) {
			r.push_back(static_cast<uint8_t>(rng() & 0xFF));
		}
		randomAsks += serverAsks(r, 60) ? 1 : 0;
	}
	eq(randomAsks, 0, "100000 blocks of random padding: none asks");

	// decide
	Send s = decide(100, true, 0);
	eq(static_cast<int>(s.wire), static_cast<int>(Wire::WORD), "told: WORD");
	eq(s.id, 100, "told: the id");
	s = decide(300, true, 7);
	eq(static_cast<int>(s.wire), static_cast<int>(Wire::WORD), "told: WORD above 255, the fallback is not used");
	eq(s.id, 300, "told: 300");
	s = decide(255, false, 0);
	eq(static_cast<int>(s.wire), static_cast<int>(Wire::BYTE), "not told: 255 is a byte");
	eq(s.id, 255, "255 as it is");
	s = decide(300, false, 7);
	eq(static_cast<int>(s.wire), static_cast<int>(Wire::BYTE), "not told: 300 with a fallback is a byte");
	eq(s.id, 7, "the fallback");
	s = decide(300, false, 0);
	eq(static_cast<int>(s.wire), static_cast<int>(Wire::DROP), "not told, no fallback: dropped");
	s = decide(300, false, 999);
	eq(static_cast<int>(s.wire), static_cast<int>(Wire::DROP), "a fallback above 255 is never written as a byte");

	// the packets read back by the client
	eq(clientReads(body(decide(300, true, 0)), true), 300, "u16 300 read with feature 77");
	eq(clientReads(body(decide(42, true, 0)), true), 42, "u16 42 read with feature 77");
	eq(clientReads(body(decide(42, false, 0)), false), 42, "byte 42 read without it");
	eq(clientReads(body(decide(300, false, 7)), false), 7, "the fallback read without it");
	for (uint32_t id = 1; id <= 0xFFFF; ++id) {
		const Send w = decide(static_cast<uint16_t>(id), true, 0);
		const Send n = decide(static_cast<uint16_t>(id), false, id > 0xFF ? 9 : 0);
		if (clientReads(body(w), true) != static_cast<long long>(id) || clientReads(body(n), false) != (id > 0xFF ? 9 : static_cast<long long>(id))) {
			eq(id, -1, "every id reads back");
			break;
		}
	}
	++checks;

	// the fallback table
	Fallbacks f;
	eq(f.set(300, 7), 1, "a row");
	eq(f.get(300), 7, "read back");
	eq(f.get(301), 0, "no row");
	eq(f.get(7), 0, "an id up to 255 has no fallback");
	eq(f.set(255, 7), 0, "an id up to 255 is refused");
	eq(f.set(65536, 7), 0, "an id above 65535 is refused");
	eq(f.set(400, 256), 0, "a fallback above 255 is refused");
	eq(f.set(400, -1), 0, "a negative fallback is refused");
	eq(f.set(65535, 255), 1, "the top id and the top byte");
	eq(f.size(), 2, "two rows");
	eq(f.set(300, 0), 1, "0 removes");
	eq(f.get(300), 0, "removed");
	f.clear();
	eq(f.size(), 0, "cleared");

	// a missile written as a number
	eq(parseId("300"), 300, "300");
	eq(parseId("65535"), 65535, "the top id");
	eq(parseId("65536"), 0, "above the top");
	eq(parseId("99999999999"), 0, "far above the top");
	eq(parseId(""), 0, "empty");
	eq(parseId(nullptr), 0, "no text");
	eq(parseId("fire"), 0, "a name is not a number");
	eq(parseId("12a"), 0, "digits then a letter");
	eq(parseId("-5"), 0, "a sign");

	std::printf("chaoswidemissile_test: %d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
