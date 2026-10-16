// Unit test of the failed-login limits of engine patch 0047 (server/src-patches/0047-login-failure-limit.patch,
// src/loginlimit.h). CI takes loginlimit.h out of the patch and builds it alone:
//   g++ -std=c++17 -Wall -I DIR/src server/tools/loginlimit_test.cpp -o loginlimit_test   (exit status 0 = all passed)
#include "loginlimit.h"
#include <iostream>
#include <string>
using namespace LoginLimit;
static int fails = 0;
#define CHECK(c) do { if (!(c)) { std::cout << "FAIL line " << __LINE__ << ": " #c << std::endl; ++fails; } } while (0)

int main()
{
	Settings s; s.maxPerIp = 5; s.maxPerAccount = 8; s.windowSec = 600; s.blockSec = 900;
	const uint32_t a = 0x0100007f, b = 0x0200007f;

	{   // per IP: the 5th failure blocks the IP for blockSec, other IPs are not touched
		Limiter l;
		for (int i = 0; i < 4; ++i) { CHECK(l.record(a, "acc" + std::to_string(i), false, 1000, s).empty()); }
		CHECK(l.blockedFor(a, "x", 1000, s) == 0);
		CHECK(l.record(a, "acc9", false, 1001, s) == "ip");
		CHECK(l.blockedFor(a, "anything", 1001, s) == 900);
		CHECK(l.blockedFor(b, "anything", 1001, s) == 0);
		CHECK(l.blockedFor(a, "x", 1901, s) == 0);           // over after blockSec
		// a success on the attacker's own account does not reset the IP count
		Limiter m;
		for (int i = 0; i < 4; ++i) { m.record(a, "victim", false, 10, s); }
		m.record(a, "mine", true, 11, s);
		CHECK(m.record(a, "victim", false, 12, s) == "ip");
	}
	{   // per account, from many IPs; case-insensitive; a success clears the account's count
		Limiter l;
		for (uint32_t i = 0; i < 7; ++i) { l.record(1000 + i, i % 2 ? "Victim" : "VICTIM", false, 50, s); }
		CHECK(l.blockedFor(9, "victim", 50, s) == 0);
		l.record(9, "victim", true, 51, s);                   // the owner logs in
		for (uint32_t i = 0; i < 7; ++i) { l.record(2000 + i, "victim", false, 52, s); }
		CHECK(l.blockedFor(9, "victim", 52, s) == 0);
		CHECK(l.record(3000, "victim", false, 53, s) == "account");
		CHECK(l.blockedFor(9, "ViCtIm", 53, s) == 900);
		CHECK(l.blockedFor(9, "other", 53, s) == 0);
	}
	{   // the window: failures spread wider than windowSec never block
		Limiter l;
		for (int i = 0; i < 50; ++i) { CHECK(l.record(a, "x", false, i * 200, s).empty() || i % 5 == 4); }
		Limiter m;
		bool blocked = false;
		for (int i = 0; i < 50; ++i) { blocked |= !m.record(a, "x" + std::to_string(i), false, i * 150, s).empty(); }
		CHECK(!blocked);                                       // 4 failures per 600 s at most
	}
	{   // limits off
		Settings off = s; off.maxPerIp = 0; off.maxPerAccount = 0;
		Limiter l;
		for (int i = 0; i < 100; ++i) { CHECK(l.record(a, "x", false, 1, off).empty()); }
		CHECK(l.blockedFor(a, "x", 1, off) == 0 && l.size() == 0);
	}
	{   // bounded memory: long names are cut, the maps never grow past MAX_ENTRIES
		Limiter l;
		const std::string longName(5000, 'q');
		CHECK(Limiter::key(longName).size() == Limiter::MAX_NAME);
		Settings big = s; big.maxPerIp = 1000000; big.maxPerAccount = 1000000;
		for (uint32_t i = 0; i < Limiter::MAX_ENTRIES + 500; ++i) { l.record(i, std::to_string(i), false, 5, big); }
		CHECK(l.size() <= 2 * Limiter::MAX_ENTRIES);
		// expired entries are swept to make room
		l.record(7, "late", false, 5 + 601, big);
		CHECK(l.size() <= 2 * Limiter::MAX_ENTRIES);
	}
	CHECK(refusal(61).find("2 minutes") != std::string::npos);
	CHECK(refusal(30).find("1 minute ") != std::string::npos);
	if (fails) { std::cout << fails << " failure(s)" << std::endl; return 1; }
	std::cout << "loginlimit_test: ok" << std::endl;
	return 0;
}
