// Fuzz harness: the PROXY protocol header parser of engine src-patch 0025 (src/proxyprotocol.cpp), fed the way
// Connection::onProxyRead feeds it (8 bytes, then as many as Parse::NeedMore asks for, never more than MAX_HEADER).
// Input byte 0 picks the part: 0-191 the header reader, 192-223 the trusted list (proxyProtocolTrusted) and classify,
// 224-255 looksLikeHeader on a first packet's length bytes. Built by server/tools/fuzz/build_fuzz.sh.
#include "configmanager.h"
#include "proxyprotocol.h"

#include <cstring>
#include <memory>
#include <string>

ConfigManager g_config;

namespace {

void readHeader(const uint8_t* data, size_t size)
{
	// the connection's buffer: the gateway's bytes arrive into it in steps
	std::unique_ptr<uint8_t[]> buffer(new uint8_t[ProxyProtocol::MAX_HEADER]);
	size_t have = ProxyProtocol::FIRST_READ;
	for (int step = 0; step < 200; ++step) {  // a v1 line is read a byte at a time: about 100 steps
		if (have > size) {
			return; // the gateway stopped sending: the connection's read timer closes it
		}
		std::memcpy(buffer.get(), data, have);
		ProxyProtocol::Header header;
		// exactly `have` bytes, at the end of a heap block, so a read past them is a report
		std::unique_ptr<uint8_t[]> view(new uint8_t[have]);
		std::memcpy(view.get(), buffer.get(), have);
		switch (ProxyProtocol::parse(view.get(), have, header)) {
			case ProxyProtocol::Parse::NeedMore:
				if (header.need <= have || header.need > ProxyProtocol::MAX_HEADER) {
					return; // closed by the connection
				}
				have = header.need;
				continue;
			case ProxyProtocol::Parse::Ok:
				if (header.need != have && header.need > have) {
					__builtin_trap(); // the header's length must lie inside what was read
				}
				return;
			case ProxyProtocol::Parse::Invalid:
				return;
		}
	}
	__builtin_trap(); // the reader must end (V1_MAX, MAX_HEADER bound it)
}

} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	if (size == 0) {
		return 0;
	}
	const uint8_t which = data[0];
	++data;
	--size;
	if (which < 192) {
		readHeader(data, size);
	} else if (which < 224) {
		std::string text(reinterpret_cast<const char*>(data), size);
		const size_t cut = text.find('\n');
		g_config.strings[ConfigManager::PROXY_PROTOCOL_TRUSTED] = text.substr(0, cut);
		g_config.booleans[ConfigManager::PROXY_PROTOCOL_REQUIRED] = (which & 1) != 0;
		uint32_t ip = 0, prefix = 0;
		ProxyProtocol::parseIPv4(text, ip, prefix);
		uint32_t peer = 0;
		if (size >= 4) {
			std::memcpy(&peer, data + size - 4, 4);
		}
		ProxyProtocol::classify(peer);
		ProxyProtocol::isTrusted(peer);
	} else if (size >= 2) {
		std::unique_ptr<uint8_t[]> two(new uint8_t[2]);
		std::memcpy(two.get(), data, 2);
		ProxyProtocol::looksLikeHeader(two.get());
	}
	return 0;
}
