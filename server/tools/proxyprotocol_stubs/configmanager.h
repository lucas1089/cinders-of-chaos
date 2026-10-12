// Stand-in for the engine's ConfigManager, for server/tools/proxyprotocol_test.cpp only: the two keys of patch 0025.
#include <string>

struct ConfigManager {
	enum string_config_t { PROXY_PROTOCOL_TRUSTED };
	enum boolean_config_t { PROXY_PROTOCOL_REQUIRED };
	std::string trusted;
	bool required = false;
	const std::string& getString(string_config_t) const { return trusted; }
	bool getBoolean(boolean_config_t) const { return required; }
};
