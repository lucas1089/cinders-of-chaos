// Unit test of the pre-auth connection limits of engine patch 0067 (server/src-patches/0067-preauth-limits.patch,
// src/chaospreauth.h). CI takes chaospreauth.h out of the patch and builds it alone:
//   g++ -std=c++17 -Wall -Wextra -pthread -I DIR/src server/tools/chaospreauth_test.cpp -o chaospreauth_test   (exit 0 = all passed)
#include "chaospreauth.h"
#include <atomic>
#include <cstring>
#include <iostream>
#include <thread>
#include <vector>
using namespace PreAuth;
static int fails = 0;
#define CHECK(c) do { if (!(c)) { if (++fails <= 20) std::cout << "FAIL line " << __LINE__ << ": " #c << std::endl; } } while (0)

static uint32_t ipOf(uint8_t a, uint8_t b, uint8_t c, uint8_t d)
{
	const uint8_t bytes[4] = {a, b, c, d}; // network byte order as the engine keeps it
	uint32_t ip;
	std::memcpy(&ip, bytes, 4);
	return ip;
}

// distinct addresses whose first byte (in memory) is 10, never 127
static uint32_t flood(uint32_t i) { return (i << 8) | 10u; }

int main()
{
	const uint32_t fresh = ipOf(11, 0, 0, 1);
	Settings s; s.maxPerIp = 3; s.maxTotal = 5; s.rateMax = 100; // rate out of the way
	const uint32_t a = ipOf(10, 0, 0, 1), b = ipOf(10, 0, 0, 2), c = ipOf(10, 0, 0, 3), lo = ipOf(127, 0, 0, 1);

	{   // per IP: the 4th open connection of one IP is refused, others are not; a release gives the slot back
		Limiter l;
		for (int i = 0; i < 3; ++i) { CHECK(l.admit(a, 100, s) == Verdict::Admitted); }
		CHECK(l.admit(a, 100, s) == Verdict::PerIp);
		CHECK(l.admit(b, 100, s) == Verdict::Admitted);
		CHECK(l.active(a) == 3 && l.total() == 4);
		l.release(a);
		CHECK(l.admit(a, 100, s) == Verdict::Admitted);
		CHECK(l.active(a) == 3);
	}
	{   // global: 5 in all, then everyone is refused until one closes
		Limiter l;
		CHECK(l.admit(a, 1, s) == Verdict::Admitted); CHECK(l.admit(a, 1, s) == Verdict::Admitted);
		CHECK(l.admit(b, 1, s) == Verdict::Admitted); CHECK(l.admit(b, 1, s) == Verdict::Admitted);
		CHECK(l.admit(c, 1, s) == Verdict::Admitted);
		CHECK(l.total() == 5);
		CHECK(l.admit(c, 1, s) == Verdict::Total);
		CHECK(l.admit(ipOf(10, 0, 0, 9), 1, s) == Verdict::Total);
		l.release(a);
		CHECK(l.admit(ipOf(10, 0, 0, 9), 1, s) == Verdict::Admitted);
	}
	{   // refused connections are never counted, so they cannot leak: refuse a lot, release what was admitted, back to 0
		Limiter l;
		int admitted = 0;
		for (int i = 0; i < 1000; ++i) { admitted += l.admit(a, 5, s) == Verdict::Admitted; }
		CHECK(admitted == 3);
		for (int i = 0; i < admitted; ++i) { l.release(a); }
		CHECK(l.total() == 0 && l.active(a) == 0);
		l.release(a); // a stray release does not go below 0
		CHECK(l.total() == 0 && l.active(a) == 0);
	}
	{   // loopback is exempt and not counted; with exemptLoopback off it is limited like any IP
		Limiter l;
		for (int i = 0; i < 50; ++i) { CHECK(l.admit(lo, 1, s) == Verdict::Exempt); }
		CHECK(l.total() == 0);
		Settings t = s; t.exemptLoopback = false;
		for (int i = 0; i < 3; ++i) { CHECK(l.admit(lo, 1, t) == Verdict::Admitted); }
		CHECK(l.admit(lo, 1, t) == Verdict::PerIp);
		CHECK(isLoopback(ipOf(127, 9, 9, 9)) && !isLoopback(ipOf(128, 0, 0, 1)) && !isLoopback(ipOf(10, 0, 0, 127)));
	}
	{   // rate: 10 new connections per 10 s, the 11th starts a 30 s cooldown (no matter how many are open), then normal again
		Settings r; r.maxPerIp = 0; r.maxTotal = 0; r.rateMax = 10; r.rateWindowSec = 10; r.cooldownSec = 30;
		Limiter l;
		for (int i = 0; i < 10; ++i) { CHECK(l.admit(a, 1000 + i / 5, r) == Verdict::Admitted); l.release(a); }
		CHECK(l.admit(a, 1001, r) == Verdict::Rate);
		CHECK(l.admit(a, 1020, r) == Verdict::Rate);          // inside the cooldown (until 1031)
		CHECK(l.admit(a, 1030, r) == Verdict::Rate);          // refusals do not extend it
		CHECK(l.admit(b, 1001, r) == Verdict::Admitted);      // others are not touched
		CHECK(l.admit(a, 1031, r) == Verdict::Admitted);
		// a slow client (1 connection per 2 s) never meets the limit
		Limiter m;
		for (int i = 0; i < 200; ++i) { CHECK(m.admit(a, 5000 + i * 2, r) == Verdict::Admitted); m.release(a); }
	}
	{   // every limit off: nothing is counted
		Settings off; off.maxPerIp = 0; off.maxTotal = 0; off.rateMax = 0;
		Limiter l;
		for (int i = 0; i < 500; ++i) { CHECK(l.admit(a, 1, off) == Verdict::Exempt); }
		CHECK(l.total() == 0);
	}
	{   // the table is bounded: expired entries are swept, live ones are not dropped, a flood of new IPs past the bound is refused
		Settings r; r.maxPerIp = 0; r.maxTotal = 0; r.rateMax = 5; r.rateWindowSec = 10;
		Limiter l;
		for (uint32_t i = 0; i < Limiter::MAX_ENTRIES; ++i) { CHECK(l.admit(flood(i), 100, r) == Verdict::Admitted); }
		CHECK(l.entries() == Limiter::MAX_ENTRIES);
		// the open ones are live: no room
		CHECK(l.admit(fresh, 105, r) == Verdict::Full);
		for (uint32_t i = 0; i < Limiter::MAX_ENTRIES; ++i) { l.release(flood(i)); }
		CHECK(l.admit(fresh, 105, r) == Verdict::Full);  // closed, but the rate window is still running
		CHECK(l.admit(fresh, 111, r) == Verdict::Admitted); // window over: swept
		CHECK(l.entries() == 1);
	}
	{   // log throttling: one line per kind per 10 s, with the count of the lines left out
		Limiter l;
		uint32_t n = 99;
		CHECK(l.shouldLog(Verdict::PerIp, 100, n) && n == 0);
		CHECK(!l.shouldLog(Verdict::PerIp, 101, n));
		CHECK(!l.shouldLog(Verdict::PerIp, 105, n));
		CHECK(l.shouldLog(Verdict::Total, 105, n) && n == 0);   // another kind has its own clock
		CHECK(l.shouldLog(Verdict::PerIp, 110, n) && n == 2);
	}
	{   // threads: admit / release from many threads at once; caps hold at every moment and the counts return to 0
		Settings t; t.maxPerIp = 4; t.maxTotal = 10; t.rateMax = 0;
		Limiter l;
		std::vector<std::thread> pool;
		std::atomic<int> over(0);
		for (int th = 0; th < 8; ++th) {
			pool.emplace_back([&, th]() {
				const uint32_t ip = ipOf(10, 1, 0, static_cast<uint8_t>(th % 4));
				for (int i = 0; i < 20000; ++i) {
					if (l.admit(ip, 1, t) == Verdict::Admitted) {
						if (l.total() > t.maxTotal || l.active(ip) > t.maxPerIp) { ++over; }
						l.release(ip);
					}
				}
			});
		}
		for (auto& th : pool) { th.join(); }
		CHECK(over == 0);
		CHECK(l.total() == 0);
		for (int k = 0; k < 4; ++k) { CHECK(l.active(ipOf(10, 1, 0, static_cast<uint8_t>(k))) == 0); }
	}

	if (fails == 0) { std::cout << "chaospreauth_test: all passed" << std::endl; }
	return fails == 0 ? 0 : 1;
}
