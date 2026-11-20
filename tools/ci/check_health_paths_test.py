#!/usr/bin/env python3
"""Tests of check_health_paths.py (O686 phase 3): a path without the door is refused, a new health-setting file must choose, a stale
row is refused, comments and strings do not count, and the committed scripts pass."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_health_paths as C  # noqa: E402

failures = 0


def check(cond, msg):
    global failures
    if not cond:
        failures += 1
        print("FAIL " + msg)


PATHS = {"a.lua": (1, "a hunt")}
ALLOWED = {"b.lua": "a player"}


def run(files):
    return C.check_files(files, PATHS, ALLOWED)


ok = "m:setMaxHealth(Chaos.scaleHealth(hp, level))\n"
check(run({"a.lua": ok, "b.lua": "p:setMaxHealth(1)\n"}) == [], "a path with the door and an allowed file pass")
check(len(run({"a.lua": "m:setMaxHealth(hp)\n", "b.lua": "p:setMaxHealth(1)\n"})) == 1, "a path without the door is refused")
check(len(run({"a.lua": ok, "b.lua": "p:setMaxHealth(1)\n", "c.lua": "m:setMaxHealth(hp)\n"})) == 1, "a new file with a call must choose")
check(run({"a.lua": ok, "b.lua": "p:setMaxHealth(1)\n", "c.lua": "local x = 1\n"}) == [], "a file with no call is free")
check(len(run({"a.lua": "local x = 1\n", "b.lua": "p:setMaxHealth(1)\n"})) == 1, "a stale PATHS row is refused")
check(len(run({"a.lua": ok, "b.lua": "local x = 1\n"})) == 1, "a stale ALLOWED row is refused")
check(len(run({"a.lua": ok})) == 1, "a listed file that is gone is refused")
# comments and strings are not code
check(len(run({"a.lua": "-- Chaos.scaleHealth(hp, level)\nm:setMaxHealth(hp)\n", "b.lua": "p:setMaxHealth(1)\n"})) == 1,
      "the door in a comment does not count")
check(len(run({"a.lua": 'local s = "Chaos.healthFactor(1)"\nm:setMaxHealth(hp)\n', "b.lua": "p:setMaxHealth(1)\n"})) == 1,
      "the door in a string does not count")
check(run({"a.lua": "-- m:setMaxHealth(hp)\n" + ok, "b.lua": "p:setMaxHealth(1)\n"}) == [], "a call in a comment is no call")
check(run({"a.lua": "m:setMaxHealth(Chaos.healthFactor(level) * hp)\n", "b.lua": "p:setMaxHealth(1)\n"}) == [], "healthFactor counts too")
# the door needed twice
check(len(C.check_files({"a.lua": ok}, {"a.lua": (2, "two")}, {})) == 1, "the count of reads is held")

# the committed scripts
bad = C.check_files(C.load())
check(bad == [], "the committed scripts: " + "; ".join(bad))

print("check_health_paths_test: %s" % ("FAILED %d" % failures if failures else "ok"))
sys.exit(1 if failures else 0)
