// Fuzz harness: the client guard of engine src-patch 0021 (src/clientguard.cpp). Input byte 0 picks the part:
//   0-159    ClientGuard::checkAnswer: the answer the client sends on extended opcode 189 ("cg1:<build>:<64 hex>"),
//            with the nonce, account and character it is checked against (fields split at '\n', u16 build first)
//   160-223  ClientGuard::gateReason: the u32 client version field of a login packet against clientGuardBuilds
//            (taken from the input)
//   224-255  the same against a clientGuardManifest file with the input as its text (min_package)
// Built by server/tools/fuzz/build_fuzz.sh (libFuzzer, or the regression driver standalone_main.cpp).
#include "clientguard.h"
#include "configmanager.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <unistd.h>
#include <vector>

ConfigManager g_config;

namespace {

std::vector<std::string> fields(const std::string& s, size_t count)
{
	std::vector<std::string> out;
	size_t start = 0;
	while (out.size() + 1 < count) {
		const size_t nl = s.find('\n', start);
		if (nl == std::string::npos) {
			break;
		}
		out.push_back(s.substr(start, nl - start));
		start = nl + 1;
	}
	out.push_back(start <= s.size() ? s.substr(start) : std::string());
	while (out.size() < count) {
		out.emplace_back();
	}
	return out;
}

std::string manifestPath()
{
	static const std::string path = "/tmp/chaos_fuzz_manifest_" + std::to_string(getpid()) + ".json";
	return path;
}

} // namespace

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
	g_config.strings[ConfigManager::CLIENT_GUARD_MODE] = "enforce";
	// a fixed test key (not a real one) and the development key allowed: every compare path runs
	g_config.strings[ConfigManager::CLIENT_GUARD_KEY] =
	    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f, zz-not-hex";
	g_config.booleans[ConfigManager::CLIENT_GUARD_ALLOW_DEV_KEY] = true;
	std::cout.setstate(std::ios::failbit); // the key report lines; nothing the harness checks
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	if (size < 1) {
		return 0;
	}
	const uint8_t which = data[0];
	const std::string rest(reinterpret_cast<const char*>(data + 1), size - 1);
	if (which < 160) {
		if (rest.size() < 2) {
			return 0;
		}
		const uint16_t build = static_cast<uint8_t>(rest[0]) | static_cast<uint8_t>(rest[1]) << 8;
		const auto f = fields(rest.substr(2), 4);
		const ClientGuard::Answer a = ClientGuard::checkAnswer(f[0], f[1], f[2], f[3], build);
		ClientGuard::answerText(a);
		// a well-formed answer made with the configured key must pass
		std::string key;
		for (size_t i = 0; i < 32; ++i) {
			key.push_back(static_cast<char>(i));
		}
		const std::string good = ClientGuard::mac(key, f[1], f[2], f[3], build);
		static const char digits[] = "0123456789abcdef";
		std::string hex;
		for (unsigned char c : good) {
			hex.push_back(digits[c >> 4]);
			hex.push_back(digits[c & 15]);
		}
		if (ClientGuard::checkAnswer("cg1:" + std::to_string(build) + ":" + hex, f[1], f[2], f[3], build) !=
		    ClientGuard::Answer::Ok) {
			__builtin_trap();
		}
	} else {
		uint32_t clientId = 0;
		if (rest.size() >= 4) {
			std::memcpy(&clientId, rest.data(), 4);
		}
		if (which & 1) {
			clientId = (ClientGuard::CLIENT_ID_TAG << 16) | (clientId & 0xFFFF);
		}
		const std::string text = rest.size() >= 4 ? rest.substr(4) : std::string();
		if (which < 224) {
			g_config.strings[ConfigManager::CLIENT_GUARD_BUILDS] = text;
			g_config.strings[ConfigManager::CLIENT_GUARD_MANIFEST].clear();
		} else {
			g_config.strings[ConfigManager::CLIENT_GUARD_BUILDS].clear();
			{
				std::ofstream out(manifestPath(), std::ios::binary | std::ios::trunc);
				out << text;
			}
			g_config.strings[ConfigManager::CLIENT_GUARD_MANIFEST] = manifestPath();
		}
		ClientGuard::gateReason(clientId);
	}
	return 0;
}
