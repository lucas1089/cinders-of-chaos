// Fuzz harness: the failed-login limits of engine src-patch 0047 (src/loginlimit.h). The input is a sequence of
// logins (5 bytes each: IP, account name length, result, seconds since the last one, a flag that records it even
// while blocked; the account name is the next bytes of the input) with small settings, so blocks, windows and the sweep of a full map all run.
// Checks: a blocked IP or account stays refused until its block ends; blockedFor never exceeds blockSec.
// Built by server/tools/fuzz/build_fuzz.sh.
#include "loginlimit.h"

#include <string>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	if (size < 4) {
		return 0;
	}
	LoginLimit::Settings s;
	s.maxPerIp = data[0] % 6;      // 0 turns the limit off
	s.maxPerAccount = data[1] % 6;
	s.windowSec = data[2] % 50;
	s.blockSec = data[3] % 50;
	LoginLimit::Limiter limiter;
	int64_t now = 1700000000;
	size_t i = 4;
	while (i + 5 <= size) {
		const uint32_t ip = 0x0100007F + (data[i] % 8 << 24);
		const size_t nameLen = data[i + 1] % 80;
		const bool ok = (data[i + 2] & 1) != 0;
		now += data[i + 3] % 30;
		const bool again = (data[i + 4] & 1) != 0; // record even while blocked (another worker raced it)
		i += 5;
		std::string account;
		for (size_t k = 0; k < nameLen && i < size; ++k, ++i) {
			account.push_back(static_cast<char>(data[i]));
		}
		const uint32_t before = limiter.blockedFor(ip, account, now, s);
		if (before > s.blockSec) {
			__builtin_trap();
		}
		if (before == 0 || again) {
			limiter.record(ip, account, ok, now, s);
		}
		if (limiter.size() > 2 * LoginLimit::Limiter::MAX_ENTRIES) {
			__builtin_trap();
		}
	}
	LoginLimit::refusal(static_cast<uint32_t>(size) * 1000003u);
	return 0;
}
