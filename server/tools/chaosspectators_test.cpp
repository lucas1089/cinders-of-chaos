// Unit test of src/chaosspectators.h (patch 0071, server/README.md "Cheaper spectator queries (O212)").
//   g++ -std=c++17 -O1 -Wall -Wextra -I DIR server/tools/chaosspectators_test.cpp -o chaosspectators_test
// DIR holds chaosspectators.h, cut out of the patch (.github/workflows/ci.yml, step "Spectator queries").
// Checks the three pieces against plain std containers on random input: SmallVec (copy, move, growth past the inline room),
// appendMissing (the stock addSpectators loop: both of its paths, duplicates inside the second list), Cache (against a
// std::map model through stores, lookups, O(1) clears, growth and the burst limits) and SpectatorList (erase swaps with the
// last element, as the stock one).
#include "chaosspectators.h"
#include <algorithm>
#include <cstdio>
#include <map>
#include <random>
#include <vector>

struct Creature { int id; };

static int g_bad = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAILED %s:%d: %s\n", __FILE__, __LINE__, #c); ++g_bad; } } while (0)

using SV = ChaosSpec::SpectatorList<Creature>;

static std::vector<Creature*> toVec(const SV& v) { return std::vector<Creature*>(v.begin(), v.end()); }

// the stock loop of spectators.h
static void stockAdd(std::vector<Creature*>& dst, const std::vector<Creature*>& src)
{
	for (Creature* s : src) {
		if (std::find(dst.begin(), dst.end(), s) != dst.end()) { continue; }
		dst.push_back(s);
	}
}

int main()
{
	std::mt19937 rng(2024);
	std::vector<Creature> pool(400);
	for (size_t i = 0; i < pool.size(); ++i) { pool[i].id = int(i); }

	// SmallVec
	{
		ChaosSpec::SmallVec<int, 4> a;
		for (int i = 0; i < 4; ++i) { a.push_back(i); }
		CHECK(!a.heap());
		a.push_back(4);
		CHECK(a.heap() && a.size() == 5);
		for (int i = 5; i < 100; ++i) { a.push_back(i); }
		bool ok = a.size() == 100;
		for (int i = 0; i < 100; ++i) { ok = ok && a[size_t(i)] == i; }
		CHECK(ok);
		ChaosSpec::SmallVec<int, 4> b(a);
		CHECK(b.size() == 100 && b[99] == 99 && b.heap());
		b.clear();
		b = a; // assign into a vector that has its room already
		CHECK(b.size() == 100 && b[50] == 50);
		ChaosSpec::SmallVec<int, 4> c(std::move(b));
		CHECK(c.size() == 100 && c[99] == 99 && b.size() == 0 && !b.heap());
		ChaosSpec::SmallVec<int, 4> d;
		d.push_back(7);
		d = c;
		CHECK(d.size() == 100);
		ChaosSpec::SmallVec<int, 4> e;
		e.push_back(1);
		e.push_back(2);
		ChaosSpec::SmallVec<int, 4> f(e);
		CHECK(f.size() == 2 && !f.heap() && f[1] == 2);
		d = e; // a long one assigned a short one
		CHECK(d.size() == 2 && d[0] == 1);
		d = d;
		CHECK(d.size() == 2);
		ChaosSpec::SmallVec<int, 4> g;
		g = std::move(a);
		CHECK(g.size() == 100 && a.size() == 0);
	}

	// appendMissing: both paths, against the stock loop
	for (int round = 0; round < 3000; ++round) {
		size_t na = rng() % 70, nb = rng() % 70;
		SV a, b;
		std::vector<Creature*> ra, rb;
		unsigned span = 10 + rng() % 380;
		for (size_t i = 0; i < na; ++i) { Creature* c = &pool[rng() % span]; a.emplace_back(c); ra.push_back(c); }
		for (size_t i = 0; i < nb; ++i) { Creature* c = &pool[rng() % span]; b.emplace_back(c); rb.push_back(c); }
		a.addSpectators(b);
		stockAdd(ra, rb);
		CHECK(toVec(a) == ra);
	}

	// SpectatorList erase
	for (int round = 0; round < 2000; ++round) {
		SV a;
		std::vector<Creature*> r;
		size_t n = rng() % 80;
		for (size_t i = 0; i < n; ++i) { Creature* c = &pool[i]; a.emplace_back(c); r.push_back(c); }
		for (int k = 0; k < 5; ++k) {
			Creature* x = &pool[rng() % 90];
			a.erase(x);
			auto it = std::find(r.begin(), r.end(), x);
			if (it != r.end()) { std::iter_swap(it, r.end() - 1); r.pop_back(); }
			CHECK(toVec(a) == r);
		}
		SV copy = a;
		CHECK(toVec(copy) == r);
	}

	// Cache against a std::map
	{
		ChaosSpec::Cache<SV> cache;
		std::map<uint64_t, std::vector<Creature*>> model;
		for (int op = 0; op < 60000; ++op) {
			unsigned k = rng() % 100;
			if (k < 55) {
				uint64_t key = ChaosSpec::posKey(31000 + rng() % 90, 31000 + rng() % 90, rng() % 3 + 6);
				const SV* got = cache.find(key);
				auto it = model.find(key);
				CHECK((got != nullptr) == (it != model.end()));
				if (got && it != model.end()) { CHECK(toVec(*got) == it->second); }
				if (!got) {
					SV& v = cache.store(key);
					CHECK(v.empty());
					std::vector<Creature*> r;
					size_t n = rng() % 60;
					for (size_t i = 0; i < n; ++i) { Creature* c = &pool[rng() % pool.size()]; v.emplace_back(c); r.push_back(c); }
					model[key] = r;
				}
			} else if (k < 57) {
				cache.clear();
				model.clear();
				CHECK(cache.size() == 0);
			} else if (k < 58) { // a burst of distinct centres
				for (int i = 0; i < 6000; ++i) {
					uint64_t key = ChaosSpec::posKey(i, 20000 + op % 50, 7);
					if (!cache.find(key)) {
						SV& v = cache.store(key);
						v.emplace_back(&pool[size_t(i) % pool.size()]);
						model[key] = {&pool[size_t(i) % pool.size()]};
					}
				}
			} else {
				uint64_t key = ChaosSpec::posKey(31000 + rng() % 90, 31000 + rng() % 90, rng() % 3 + 6);
				const SV* got = cache.find(key);
				auto it = model.find(key);
				CHECK((got != nullptr) == (it != model.end()));
			}
			CHECK(cache.size() == model.size());
		}
	}

	// the generation counter wrapping is not reachable in a test (2^32 clears); the explicit reset path is exercised by a full burst above
	std::printf("%s\n", g_bad ? "some checks failed" : "ok");
	return g_bad ? 1 : 0;
}
