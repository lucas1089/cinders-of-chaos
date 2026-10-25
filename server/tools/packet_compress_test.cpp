// Chaos (patch 0069): round trip of src/chaospacketcompress.h against the client's way of inflating
// (framework/net/protocol.cpp: inflateInit2 -15, the four bytes 00 00 FF FF appended, Z_SYNC_FLUSH, one stream for all
// flagged packets). Build and run in the server source root after applying patch 0069:
//   g++ -std=c++17 -O1 -Isrc packet_compress_test.cpp -lz -o packet_compress_test && ./packet_compress_test
#include "chaospacketcompress.h"

#include <cstdio>
#include <random>
#include <vector>

int main()
{
	ChaosPacketCompress::Deflater d;
	if (!d.init(3)) { std::puts("init failed"); return 1; }

	z_stream in;
	std::memset(&in, 0, sizeof(in));
	inflateInit2(&in, -15);
	std::vector<uint8_t> inflated(327680);

	std::mt19937 rng(7);
	size_t rawTotal = 0, packedTotal = 0;
	for (int i = 0; i < 4000; ++i) {
		size_t n = 16 + rng() % 4000;
		if (i % 500 == 0) n = ChaosPacketCompress::MAX_BODY;
		std::vector<uint8_t> body(n);
		const bool noisy = i % 7 == 0; // some packets that do not shrink
		for (size_t k = 0; k < n; ++k) body[k] = noisy ? rng() : (k % 13 < 9 ? 0xFF : static_cast<uint8_t>(k / 31));
		const uint8_t* out = nullptr;
		size_t outLen = 0;
		if (!d.compress(body.data(), n, out, outLen)) { std::printf("compress failed at %d\n", i); return 1; }
		std::vector<uint8_t> wire(out, out + outLen);
		wire.insert(wire.end(), {0x00, 0x00, 0xFF, 0xFF}); // InputMessage::addZlibFooter
		in.next_in = wire.data();
		in.avail_in = static_cast<uInt>(wire.size());
		in.next_out = inflated.data();
		in.avail_out = static_cast<uInt>(inflated.size());
		if (inflate(&in, Z_SYNC_FLUSH) != Z_OK) { std::printf("inflate failed at %d\n", i); return 1; }
		const size_t got = inflated.size() - in.avail_out;
		if (in.avail_in != 0 || got != n || std::memcmp(inflated.data(), body.data(), n) != 0) {
			std::printf("mismatch at %d (%zu of %zu bytes)\n", i, got, n);
			return 1;
		}
		if (outLen + 3 > n + 16 + n / 1000) { std::printf("expansion too big at %d\n", i); return 1; }
		rawTotal += n;
		packedTotal += outLen;
	}
	inflateEnd(&in);
	std::printf("ok: 4000 packets, %zu bytes in, %zu bytes out\n", rawTotal, packedTotal);
	return 0;
}
