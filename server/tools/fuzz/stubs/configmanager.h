// Stand-in for the engine's ConfigManager, for the fuzz harnesses of server/tools/fuzz/ only: the keys that
// proxyprotocol.cpp (src-patch 0025) and clientguard.cpp (src-patch 0021) read, set by the harness.
#ifndef CHAOS_FUZZ_CONFIGMANAGER_H
#define CHAOS_FUZZ_CONFIGMANAGER_H
#include <cstdint>
#include <map>
#include <string>

struct ConfigManager {
	enum string_config_t {
		PROXY_PROTOCOL_TRUSTED,
		CLIENT_GUARD_MODE,
		CLIENT_GUARD_KEY,
		CLIENT_GUARD_KEY_FILE,
		CLIENT_GUARD_BUILDS,
		CLIENT_GUARD_MANIFEST,
		CLIENT_GUARD_DOWNLOAD_URL,
		CLIENT_GUARD_STAFF_IPS,
		CLIENT_GUARD_LOG_FILE,
	};
	enum boolean_config_t { PROXY_PROTOCOL_REQUIRED, CLIENT_GUARD_ALLOW_DEV_KEY };
	enum integer_config_t { CLIENT_GUARD_TIMEOUT };

	std::map<int, std::string> strings;
	std::map<int, bool> booleans;
	std::map<int, int32_t> numbers;

	const std::string& getString(string_config_t what) const {
		static const std::string empty;
		auto it = strings.find(what);
		return it == strings.end() ? empty : it->second;
	}
	bool getBoolean(boolean_config_t what) const {
		auto it = booleans.find(what);
		return it != booleans.end() && it->second;
	}
	int32_t getNumber(integer_config_t what) const {
		auto it = numbers.find(what);
		return it == numbers.end() ? 0 : it->second;
	}
};
#endif
