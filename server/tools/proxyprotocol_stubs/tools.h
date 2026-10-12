// Stand-in for the engine's tools.h, for server/tools/proxyprotocol_test.cpp only.
#include <cstdint>
#include <string>

inline std::string convertIPToString(uint32_t ip)
{
	const uint8_t* b = reinterpret_cast<const uint8_t*>(&ip);
	return std::to_string(b[0]) + "." + std::to_string(b[1]) + "." + std::to_string(b[2]) + "." + std::to_string(b[3]);
}
