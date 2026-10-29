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
check(data is not None and g.render(data) == g.render(data), "rendering is stable")
check(g.main(["--check"]) == 0, "the committed file is up to date")
print("gen_calendar_data_test: %s" % ("FAILED" if failed else "OK"))
sys.exit(1 if failed else 0)
