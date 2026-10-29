#!/usr/bin/env python3
"""Tests of gen_calendar_data.py: the Lua readers, the cycle maths and the generated file (python3 -I website/tools/gen_calendar_data_test.py)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_calendar_data as g  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print("FAIL: " + what)


text = 'seasons = { { id = 7, name = "X", start = 20270101, finish = 20270401, hour = 9, modifier = { name = "M" } } }'
check(g.field(g.block(text, "seasons"), "start") == 20270101, "field reads a number")
check(g.field(g.block(text, "seasons"), "name") == "X", "field reads a string")
check(g.block("a = { b = { 1 } }", "a") == " b = { 1 } ", "block is balanced")
check(g.block("none", "a") == "", "a missing block is empty")
w = g.cycle_windows((2026, 10, 5, 6), 56, 2)
check(w[0]["end"] == "2026-11-30T06:00:00-03:00" and w[1]["start"] == w[0]["end"], "cycle windows follow each other")
check(g.epoch_of("epoch = {year = 2026, month = 10, day = 5, hour = 6}") == (2026, 10, 5, 6), "epoch_of")

data, problems = g.build()
check(not problems, "the sources agree: %s" % problems)
check(data is not None and [e["kind"] for e in data["events"]] == ["beta", "beta", "wipe", "launch", "sale"], "events in order")
fe = data["events"][-1] if data is not None else {}
check(fe.get("id") == "founder" and fe.get("start") == "2026-11-20T15:00:00-03:00" and fe.get("end") == "2026-12-18T15:00:00-03:00",
      "the Founder Pack sale runs from the launch to 18 Dec 15:00 (the server's founder_config.lua)")
check(data is not None and data["events"][0]["start"] == "2026-10-31T15:00:00-03:00", "beta 1 starts 31 Oct 15:00")
check(data is not None and data["events"][-1]["start"] == "2026-11-20T15:00:00-03:00", "launch 20 Nov 15:00")
check(data is not None and all(s["lengthWeeks"] * 7 <= s["lengthDays"] for s in data["seasons"]), "season length in weeks")
s1 = data["seasons"][0]
check(s1["start"] == "2026-11-20T15:00:00-03:00" and s1["finish"] == "2027-02-19T15:00:00-03:00" and s1["lengthWeeks"] == 13,
      "Season 1: launch 20 Nov 2026 15:00 to 19 Feb 2027, 13 weeks")
check(s1["startsAtLaunch"] and s1["firstSeason"], "Season 1 starts at the launch")
check(data["nextSeason"]["start"] == "2027-02-20T15:00:00-03:00" and data["nextSeason"]["status"] == "plan",
      "Season 2: 20 Feb 2027 15:00, planned")
check(next(e for e in data["events"] if e["kind"] == "launch")["status"] == "confirmed", "the launch is confirmed")
check(data["cycles"][0]["windows"][0]["start"] == "2026-11-20T15:00:00-03:00", "PvP season 1 starts at the launch")
check(data["cycles"][0]["windows"][0]["end"] == "2027-01-15T15:00:00-03:00", "PvP season 1 ends 15 Jan 2027 15:00")
check(data["patchnotes"]["weekday"] == 3 and data["patchnotes"]["firstRegular"] == "2026-11-25", "patch notes on Wednesday, the first on 25 Nov")
check(set(data["wipe"]) == {"betaToLaunch", "afterLaunch", "seasonToSeason"}, "three wipe rules")
check(all(q["id"] in ("season2", "beta-bans") for q in data["open"]), "only the open questions left")
check(data is not None and g.render(data) == g.render(data), "rendering is stable")
check(g.main(["--check"]) == 0, "the committed file is up to date")
print("gen_calendar_data_test: %s" % ("FAILED" if failed else "OK"))
sys.exit(1 if failed else 0)
