#!/usr/bin/env python3
"""Tests of gen_calendar_data.py: the Lua readers, the cycle maths and the generated file, with the launch open (the shipped
state, O463) and with an example launch date (python3 -I website/tools/gen_calendar_data_test.py)."""
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
check(g.follow_days("start = LC.ymd(0), finish = LC.ymd(91)", "finish") == 91 and g.follow_days("start = LC.ymd(0)", "start") == 0,
      "follow_days reads the launch plus N days")
check(g.follow_days('epoch = dofile("data/scripts/chaos/launch_core.lua").parts(0)', "epoch") == 0, "follow_days reads a dofile form")
check(g.follow_days("start = 20261120", "start") is None, "a literal date does not follow")

# ---------------------------------------------------------------- the shipped state: the launch is open (owner, 2026-11-10)
data, problems = g.build()
check(not problems, "the sources agree: %s" % problems)
check(data is not None and data["launch"] == {"open": True, "at": None}, "the shipped launch is open")
evs = {e["id"]: e for e in data["events"]} if data is not None else {}
check(data is not None and [e["kind"] for e in data["events"]] == ["beta", "beta", "wipe", "launch", "sale"],
      "open: the wipe, the launch and the sale are listed (not dropped), after the dated betas")
for k in ("wipe", "launch", "founder"):
    e = evs.get(k, {})
    check(e.get("soon") is True and e.get("start") is None and e.get("status") == "open" and "end" not in e,
          "open: %s is coming soon, with no date and no end" % k)
check(evs["launch"]["patchnote"] == "" and evs["launch"]["patchnoteReady"] is False, "open: no launch patch note is linked")
check("ainda não foi definida" in evs["launch"]["text"]["pt-BR"] and "not set yet" in evs["launch"]["text"]["en"],
      "open: the launch text says the date is not set")
check(evs["beta1"]["start"] == "2026-10-31T15:00:00-03:00", "beta 1 starts 31 Oct 15:00")
s1 = data["seasons"][0]
check(s1["soon"] is True and s1["start"] is None and s1["finish"] is None and s1["lengthWeeks"] == 13 and s1["lengthDays"] == 91,
      "open: Season 1 has no dates, 13 weeks long")
check(s1["startsAtLaunch"] and s1["firstSeason"] and "proposed" not in s1, "open: Season 1 starts at the launch, no made-up proposal")
check(data["nextSeason"]["soon"] is True and data["nextSeason"]["start"] is None, "open: Season 2 has no date")
check(all(c["soon"] and c["windows"] == [] for c in data["cycles"][:2]) and data["cycles"][2]["soon"] is False,
      "open: the PvP and Tower cycles have no windows, the weekly reset does")
check(data["patchnotes"]["weekday"] == 3 and data["patchnotes"]["firstRegular"] is None, "open: patch notes on Wednesday, no first date")
check(set(data["wipe"]) == {"betaToLaunch", "afterLaunch", "seasonToSeason"}, "three wipe rules")
check([q["id"] for q in data["open"]] == ["launch-date", "season2", "beta-bans"], "open: the launch date is an open question")
check("whenOpen" not in str(data["open"]), "the flag of a question is not in the data")
check(g.render(data) == g.render(data), "rendering is stable")
check(g.main(["--check"]) == 0, "the committed file is up to date")

# ---------------------------------------------------------------- with an example launch (never the owner's date)
EXAMPLE = 'return {\n\tlaunch = "2031-03-14 15:00",\n\toffsets = {freeze = -5, wipe = -2, rehearsal = -1, founderEnd = 28}\n}\n'
d2, p2 = g.build(EXAMPLE)
check(not p2, "set: the sources agree: %s" % p2)
check(d2["launch"] == {"open": False, "at": "2031-03-14T15:00:00-03:00"}, "set: the launch")
ev2 = {e["id"]: e for e in d2["events"]}
check([e["id"] for e in d2["events"]] == ["beta1", "beta2", "wipe", "launch", "founder"], "set: events in order")
check(ev2["wipe"]["start"] == "2031-03-12T00:00:00-03:00" and ev2["wipe"]["hasTime"] is False and ev2["wipe"]["soon"] is False,
      "set: the wipe is launch - 2 days, a date without a time")
check(ev2["launch"]["start"] == "2031-03-14T15:00:00-03:00" and ev2["launch"]["hasTime"] is True and ev2["launch"]["status"] == "confirmed",
      "set: the launch is confirmed, at the launch hour")
check(ev2["founder"]["start"] == "2031-03-14T15:00:00-03:00" and ev2["founder"]["end"] == "2031-04-11T15:00:00-03:00",
      "set: the Founder Pack sale runs from the launch to launch + 28 days")
check("11 Apr 2031 at 15:00" in ev2["founder"]["text"]["en"] and "11/04/2031 às 15:00" in ev2["founder"]["text"]["pt-BR"],
      "set: the sale text names the end date in both languages")
check(ev2["launch"]["patchnote"] == "2031-03-14", "set: the launch patch note is named after the launch")
s2 = d2["seasons"][0]
check(s2["start"] == "2031-03-14T15:00:00-03:00" and s2["finish"] == "2031-06-13T15:00:00-03:00" and s2["lengthWeeks"] == 13 and not s2["soon"],
      "set: Season 1 runs from the launch for 13 weeks")
check(s2["startsAtLaunch"] and s2["proposed"]["start"] == s2["start"], "set: Season 1 starts at the launch")
check(d2["nextSeason"]["start"] == "2031-06-14T15:00:00-03:00" and d2["nextSeason"]["status"] == "plan" and not d2["nextSeason"]["soon"],
      "set: Season 2 starts the day after Season 1 ends, planned")
check(d2["cycles"][0]["windows"][0]["start"] == "2031-03-14T15:00:00-03:00" and d2["cycles"][0]["windows"][0]["end"] == "2031-05-09T15:00:00-03:00"
      and not d2["cycles"][0]["soon"], "set: PvP season 1 starts at the launch and runs 8 weeks")
check(d2["cycles"][1]["windows"][0]["end"] == "2031-04-13T15:00:00-03:00", "set: Tower season 1 runs 30 days from the launch")
check(d2["patchnotes"]["firstRegular"] == "2031-03-19", "set: the first regular patch note is the Wednesday after the launch")
check([q["id"] for q in d2["open"]] == ["season2", "beta-bans"], "set: the launch date is no open question any more")
check(d2["wipe"] == data["wipe"], "set: the wipe rules do not change")
# the offsets of the file move the sale
d3, p3 = g.build(EXAMPLE.replace("founderEnd = 28", "founderEnd = 35"))
check(not p3 and {e["id"]: e for e in d3["events"]}["founder"]["end"] == "2031-04-18T15:00:00-03:00", "set: the founderEnd offset moves the sale end")
# a broken or off-the-hour launch is a problem, never a guess
for bad, why in (('return {launch = "soon"}', "not a date"), ('return {launch = "2031-03-14 15:30"}', "off the hour"), ('return {}', "no value")):
    dd, pp = g.build(bad)
    check(pp, "a bad launch value is a problem: " + why)

print("gen_calendar_data_test: %s" % ("FAILED" if failed else "OK"))
sys.exit(1 if failed else 0)
