// Tests of src/chaosbotsignals.h (engine src-patch 0093, the counts and times the bot detection reads; server/README.md "Bot detection
// events and scores (O722)"). CI cuts the header out of the patch and builds this file against it:
//   g++ -std=c++17 -Wall -Wextra -I <dir with chaosbotsignals.h> server/tools/chaosbotsignals_test.cpp
// Checks: key steps and path commands count and drain to zero, a path command adds its length (capped), a creature that came into view
// gives a reaction time at its first attack only, one that was never seen gives none, one seen too long ago gives none, the lists are
// bounded (64 waiting, 32 reaction times), counters saturate, an empty drain is empty.
#include "chaosbotsignals.h"

#include <cstdio>

static int failures = 0;
static int checks = 0;

static void eq(long long got, long long want, const char* what)
{
	++checks;
	if (got != want) {
		++failures;
		std::printf("FAIL %s: got %lld, want %lld\n", what, got, want);
	}
}

int main()
{
	using namespace ChaosBotSignals;
	{
		Signals s;
		eq(s.drain().empty(), 1, "a new player has nothing");
		s.keyStep();
		s.keyStep();
		s.pathCommand(12);
		s.pathCommand(0);
		Drained d = s.drain();
		eq(d.keySteps, 2, "two key steps");
		eq(d.pathCommands, 1, "one path command (a command of no steps is not one)");
		eq(d.pathSteps, 12, "twelve path steps");
		eq(d.empty(), 0, "not empty");
		eq(s.drain().empty(), 1, "the drain went back to zero");
		s.pathCommand(100000);
		eq(s.drain().pathSteps, MAX_PATH_STEPS, "one command adds at most MAX_PATH_STEPS");
	}
	{
		Signals s;
		s.seen(77, 1000);
		eq(s.waiting(), 1, "one creature waiting");
		s.attacked(77, 1230);
		Drained d = s.drain();
		eq(d.reactions.size(), 1, "one reaction time");
		eq(d.reactions[0].first, 77, "its creature");
		eq(d.reactions[0].second, 230, "230 ms from view to attack");
		eq(s.waiting(), 0, "no longer waiting");
		s.attacked(77, 5000);
		eq(s.drain().reactions.size(), 0, "the second attack on it is no reaction");
		s.attacked(88, 5000);
		eq(s.drain().reactions.size(), 0, "a creature that was never seen is no reaction");
		s.seen(5, 0);
		s.attacked(5, SEEN_MAX_AGE_MS + 1);
		eq(s.drain().reactions.size(), 0, "a creature in view for over 30 s is no reaction");
		eq(s.waiting(), 0, "and it stops waiting");
		s.seen(6, 100);
		s.seen(6, 400);
		eq(s.waiting(), 1, "seen twice is listed once");
		s.attacked(6, 450);
		eq(s.drain().reactions[0].second, 50, "the later time counts");
		s.seen(9, 500);
		s.attacked(9, 400);
		eq(s.drain().reactions.size(), 0, "an attack before the time it was seen (a clock step) is nothing");
	}
	{
		Signals s;
		for (uint32_t i = 1; i <= 100; ++i) {
			s.seen(i, 1000 + i);
		}
		eq(s.waiting(), SEEN_CAP, "at most 64 creatures wait");
		s.attacked(1, 2000);
		eq(s.drain().reactions.size(), 0, "the oldest was pushed out: no reaction for it");
		s.attacked(100, 2000);
		Drained d = s.drain();
		eq(d.reactions.size(), 1, "the newest is still there");
		eq(d.reactions[0].second, 2000 - 1100, "with its own time");
		// removing an entry in the middle keeps the others findable
		Signals t;
		for (uint32_t i = 1; i <= 10; ++i) {
			t.seen(i, 100 * i);
		}
		t.attacked(4, 5000);
		t.attacked(10, 5000);
		t.attacked(1, 5000);
		eq(t.drain().reactions.size(), 3, "three attacks found their creatures");
		eq(t.waiting(), 7, "seven left");
		for (uint32_t i = 100; i < 140; ++i) {
			t.seen(i, 6000);
			t.attacked(i, 6100);
		}
		Drained e = t.drain();
		eq(e.reactions.size(), REACTION_CAP, "at most 32 reaction times wait for a poll");
		eq(e.reactions.back().first, 139, "the newest are kept");
	}
	{
		Signals s;
		for (int i = 0; i < 3; ++i) {
			s.pathCommand(MAX_PATH_STEPS);
		}
		eq(s.drain().pathSteps, 3 * MAX_PATH_STEPS, "path steps add up");
	}
	if (failures) {
		std::printf("%d of %d checks failed\n", failures, checks);
		return 1;
	}
	std::printf("chaosbotsignals_test: %d checks ok\n", checks);
	return 0;
}
