// Tests of src/chaostesters.h (server src-patch 0059): tester bots are never counted online.
// Build (CI): the header is cut out of the patch, then
//   g++ -std=c++17 -Wall -Wextra -I DIR server/tools/chaostesters_test.cpp && ./a.out
#include "chaostesters.h"

#include <cstdio>
#include <map>
#include <string>
#include <unordered_map>
#include <vector>

struct FakePlayer {
	std::string name;
	uint32_t level;
	std::map<uint32_t, int32_t> storage;
	bool isTester() const {
		auto it = storage.find(CHAOS_TESTER_STORAGE);
		return chaosIsTesterStorage(it != storage.end(), it == storage.end() ? -1 : it->second);
	}
};

static int failures = 0;

static void check(bool ok, const char* what)
{
	if (!ok) {
		++failures;
		std::printf("FAIL %s\n", what);
	}
}

// the status protocol's answers, as protocolstatus.cpp builds them with the patch
struct StatusAnswer {
	std::size_t online;
	std::vector<std::string> list;
	bool nameOnline;
};

static StatusAnswer statusOf(const std::unordered_map<uint32_t, FakePlayer*>& players, const std::string& asked)
{
	auto isTester = [](const FakePlayer* p) { return p->isTester(); };
	StatusAnswer a{chaosCountedPlayers(players, isTester), {}, false};
	chaosForEachCounted(players, isTester, [&a](const FakePlayer* p) { a.list.push_back(p->name); });
	for (const auto& it : players) {
		if (it.second->name == asked && !it.second->isTester()) {
			a.nameOnline = true;
		}
	}
	return a;
}

int main()
{
	check(CHAOS_TESTER_STORAGE == 7102900, "the storage key is Chaos.storage.tester");
	check(chaosIsTesterStorage(true, 1), "storage 1: a tester");
	check(!chaosIsTesterStorage(true, 0), "storage 0: not a tester");
	check(!chaosIsTesterStorage(true, 2), "storage 2: not a tester");
	check(!chaosIsTesterStorage(false, 1), "no storage: not a tester");

	FakePlayer ana{"Ana", 120, {}};
	FakePlayer bob{"Bob", 40, {{CHAOS_TESTER_STORAGE, 0}}};
	FakePlayer t1{"Tester Aab", 300, {{CHAOS_TESTER_STORAGE, 1}}};
	FakePlayer t2{"Tester Aac", 600, {{CHAOS_TESTER_STORAGE, 1}, {7100000, 5}}};
	std::unordered_map<uint32_t, FakePlayer*> players{{1, &ana}, {2, &bob}, {3, &t1}, {4, &t2}};

	StatusAnswer a = statusOf(players, "Tester Aab");
	check(a.online == 2, "status: 2 players online of 4 (2 testers)");
	check(a.list.size() == 2, "status: the online list has 2 names");
	for (const auto& n : a.list) {
		check(n.rfind("Tester ", 0) != 0, "status: no tester in the online list");
	}
	check(!a.nameOnline, "status: a tester's name answers offline");
	check(statusOf(players, "Ana").nameOnline, "status: a player's name answers online");

	std::unordered_map<uint32_t, FakePlayer*> onlyTesters{{3, &t1}, {4, &t2}};
	check(statusOf(onlyTesters, "").online == 0, "status: 0 online when only testers are in");
	check(!chaosIsNewRecord(chaosCountedPlayers(onlyTesters, [](const FakePlayer* p) { return p->isTester(); }), 0),
	      "record: testers alone never beat a record of 0");
	check(chaosIsNewRecord(2, 1), "record: 2 counted players beat 1");
	check(!chaosIsNewRecord(2, 2), "record: 2 do not beat 2");

	std::unordered_map<uint32_t, FakePlayer*> withNull{{1, &ana}, {9, nullptr}};
	check(chaosCountedPlayers(withNull, [](const FakePlayer* p) { return p->isTester(); }) == 1, "a null entry is skipped");

	std::printf("chaostesters_test: %d failures\n", failures);
	return failures ? 1 : 0;
}
