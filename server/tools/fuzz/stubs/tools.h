// Stand-in for the engine's tools.h, for the fuzz harnesses of server/tools/fuzz/ only.
#ifndef CHAOS_FUZZ_TOOLS_H
#define CHAOS_FUZZ_TOOLS_H
#include <algorithm>
#include <cctype>
#include <cstdint>
#include <string>

inline std::string convertIPToString(uint32_t ip)
{
	const uint8_t* b = reinterpret_cast<const uint8_t*>(&ip);
	return std::to_string(b[0]) + "." + std::to_string(b[1]) + "." + std::to_string(b[2]) + "." + std::to_string(b[3]);
}

inline std::string asLowerCaseString(std::string s)
{
	std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
	return s;
}
#endif
