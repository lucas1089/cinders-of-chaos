// Tests of src/chaoscast.h (server src-patch 0064): which game messages the live cast keeps, the frames, the hello.
// Build (CI): the header is cut out of the patch, then
//   g++ -std=c++17 -Wall -Wextra -I DIR server/tools/chaoscast_test.cpp && ./a.out
#include "chaoscast.h"

#include <cstdio>
#include <string>
#include <vector>

static int failures = 0;

static void check(bool ok, const char* what)
{
	if (!ok) {
		++failures;
		std::printf("FAIL %s\n", what);
	}
}

using Bytes = std::vector<uint8_t>;

static void u16(Bytes& b, uint16_t v)
{
	b.push_back(v & 0xFF);
	b.push_back(v >> 8);
}

static void str(Bytes& b, const std::string& s)
{
	u16(b, static_cast<uint16_t>(s.size()));
	b.insert(b.end(), s.begin(), s.end());
}

static bool keep(const Bytes& b)
{
	return ChaosCast::keepMessage(b.data(), b.size());
}

// 0xAA as ProtocolGame::sendCreatureSay builds it (position) or sendToChannel / sendPrivateMessage (no position)
static Bytes talk(uint8_t type, bool withPosition, const std::string& text)
{
	Bytes b{0xAA, 1, 0, 0, 0};
	str(b, "Someone");
	u16(b, 42);
	b.push_back(type);
	if (withPosition) {
		u16(b, 1000);
		u16(b, 1000);
		b.push_back(7);
	} else {
		u16(b, 5); // channel id
	}
	str(b, text);
	return b;
}

int main()
{
	// the game view goes out
	const uint8_t kept[] = {0x42, 0x4B, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x82, 0x83, 0x84,
	                        0x85, 0x8C, 0x8D, 0x8E, 0x8F, 0x90, 0x91, 0x92, 0x93, 0x95, 0xA0, 0xBE, 0xBF};
	for (uint8_t op : kept) {
		check(keep(Bytes{op, 0, 0}), "a map / creature / stats message is kept");
	}
	// the rest stays private: chat, channels, VIP, modal windows, containers, inventory, trade, outfit window,
	// extended opcodes, pings, store, market, login messages
	const uint8_t dropped[] = {0x0A, 0x0B, 0x0F, 0x14, 0x15, 0x16, 0x17, 0x1D, 0x1E, 0x28, 0x32, 0x6E, 0x6F, 0x70,
	                           0x71, 0x72, 0x78, 0x79, 0x7D, 0x7E, 0x7F, 0x96, 0x9F, 0xA1, 0xA2, 0xA3, 0xAB, 0xAC,
	                           0xAD, 0xAE, 0xAF, 0xB0, 0xB1, 0xB2, 0xB3, 0xB5, 0xB6, 0xC8, 0xD2, 0xD3, 0xD4, 0xDC,
	                           0xF0, 0xF2, 0xF3, 0xF5, 0xFA, 0xFB, 0x00};
	for (uint8_t op : dropped) {
		check(!keep(Bytes{op, 0, 0, 0, 0}), "a private message stays in the engine");
	}
	check(!ChaosCast::keepMessage(nullptr, 3), "no body");
	check(!keep(Bytes{}), "empty body");

	// speech: say, yell and monster speech on the map only
	check(keep(talk(1, true, "hi")), "say on the map");
	check(keep(talk(3, true, "HI")), "yell on the map");
	check(keep(talk(36, true, "grr")), "monster say");
	check(keep(talk(37, true, "GRR")), "monster yell");
	check(!keep(talk(2, true, "psst")), "whisper type dropped");
	check(!keep(talk(4, false, "secret")), "private message dropped");
	check(!keep(talk(7, false, "channel")), "channel message dropped");
	check(!keep(talk(1, false, "abcde")), "a kept type in a channel layout is dropped");
	Bytes cut = talk(1, true, "hello");
	cut.pop_back();
	check(!keep(cut), "a short speech message is dropped");
	Bytes longer = talk(1, true, "hello");
	longer.push_back(0);
	check(!keep(longer), "a speech message with bytes after it is dropped");
	check(!keep(Bytes{0xAA, 1, 0}), "a speech header alone is dropped");
	Bytes hugeName{0xAA, 1, 0, 0, 0, 0xFF, 0xFF};
	check(!keep(hugeName), "a name length past the end is dropped");

	// text messages: only the numbers over creatures
	for (uint8_t t = 23; t <= 29; ++t) {
		check(keep(Bytes{0xB4, t, 0}), "damage / heal / experience numbers kept");
	}
	const uint8_t privateText[] = {17, 18, 19, 20, 21, 22, 30, 31, 32, 33, 34, 35, 36};
	for (uint8_t t : privateText) {
		check(!keep(Bytes{0xB4, t, 0}), "other text messages dropped");
	}
	check(!keep(Bytes{0xB4}), "a text message without its type is dropped");

	// frames
	std::string out;
	const uint8_t body[] = {0x83, 1, 2, 3};
	check(ChaosCast::appendFrame(out, body, sizeof(body)), "a frame is written");
	check(out.size() == 6 && out[0] == 4 && out[1] == 0 && static_cast<uint8_t>(out[2]) == 0x83, "u16 LE length + body");
	std::vector<uint8_t> big(ChaosCast::MAX_FRAME_BODY + 1, 0x83);
	std::string none;
	check(!ChaosCast::appendFrame(none, big.data(), big.size()) && none.empty(), "too big for a frame: nothing");
	check(ChaosCast::appendFrame(none, big.data(), ChaosCast::MAX_FRAME_BODY) && none.size() == 0xFFFF + 2,
	      "the largest frame");
	check(!ChaosCast::appendFrame(none, body, 0), "an empty body is no frame");

	// hello
	const std::string h = ChaosCast::helloFrame(0x10000001, 1100, 3, 17, 13, "Some Name");
	const size_t bodyLen = static_cast<uint8_t>(h[0]) | (static_cast<uint8_t>(h[1]) << 8);
	check(bodyLen + 2 == h.size(), "hello is one frame");
	check(h[2] == 0 && h.compare(3, 4, "CAST") == 0 && h[7] == ChaosCast::HELLO_VERSION, "hello opcode, magic, version");
	check(static_cast<uint8_t>(h[8]) == 0x01 && static_cast<uint8_t>(h[11]) == 0x10, "hello player id LE");
	check((static_cast<uint8_t>(h[12]) | (static_cast<uint8_t>(h[13]) << 8)) == 1100, "hello marker");
	check(h[14] == 3 && h[15] == 17 && h[16] == 13, "hello flags and aware range");
	check(h[17] == 9 && h[18] == 0 && h.compare(19, 9, "Some Name") == 0 && h.size() == 28, "hello name");
	check(ChaosCast::helloFrame(1, 0, 0, 17, 13, std::string(200, 'a')).size() == 19 + 64, "hello name capped at 64");

	// config bounds
	check(!ChaosCast::portOn(0) && !ChaosCast::portOn(-1) && !ChaosCast::portOn(65536), "port off");
	check(ChaosCast::portOn(1) && ChaosCast::portOn(7179) && ChaosCast::portOn(65535), "port on");
	check(ChaosCast::clampSpectators(0) == 1 && ChaosCast::clampSpectators(3) == 3 &&
	          ChaosCast::clampSpectators(100) == 8,
	      "spectators 1..8");
	check(ChaosCast::clampQueueBytes(1) == 256 * 1024 && ChaosCast::clampQueueBytes(1024) == 1024 * 1024 &&
	          ChaosCast::clampQueueBytes(1 << 30) == 16384u * 1024,
	      "queue 256 KiB..16 MiB");

	if (failures) {
		std::printf("%d failure(s)\n", failures);
		return 1;
	}
	std::printf("chaoscast: all checks passed\n");
	return 0;
}
