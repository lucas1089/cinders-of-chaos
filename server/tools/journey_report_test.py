#!/usr/bin/env python3
"""Tests for server/tools/journey_report.py (server/README.md "Journey bots (O542)"): the curve reader, the minutes per level
against the model in blocks (ok, slow, fast, no model, a gap in the levels), the merged coverage, the markdown report and the JSON
summary, the command line, the real model curve of progression_model.lua when a Lua is installed. All bot data is synthetic.

usage: python3 -I server/tools/journey_report_test.py
"""
import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import journey_report as jr  # noqa: E402

failures = 0


def check(cond, label):
    global failures
    if not cond:
        failures += 1
        print('FAIL', label)


def bot(**kw):
    b = {"name": "Bot One", "class": "warrior", "vocation": 4, "startLevel": 8, "level": 13, "minutes": 9.5, "stop": "time", "kills": 120, "killsPerHour": 700,
         "xp": 5000, "xpPerHour": 30000, "goldEarned": 300, "goldSpent": 100, "goldPerHour": 1900, "potionsUsed": 2, "potionsBought": 20, "reconnects": 1,
         "gaveUpHunts": 1, "minutesPerLevel": {"8": 1.0, "9": 1.0, "10": 1.0, "11": 1.0, "12": 1.0}, "deaths": [{"cause": "Troll", "pos": [1, 2, 7], "minute": 4.2, "level": 10}],
         "stuck": [{"what": "no way toward 1,2,3", "pos": [32390, 32226, 7], "minute": 1.5, "hunt": "Rat"}], "trips": [{"reason": "cap", "minute": 5, "level": 10, "minutes": 1.2, "sold": 55}],
         "hunts": ["Rat (1-10) at 1,2,8"], "coverage": []}
    b.update(kw)
    return b


def main():
    exp = jr.parse_curve('{"source":"x","levels":{"8":0.15,"9":0.21,"10":0.38,"11":0.47,"12":0.57,"13":0.62}}')
    check(exp[8] == 0.15 and len(exp) == 6 and isinstance(list(exp)[0], int), "curve parsed to int levels")

    pl = {8: 1.0, 9: 1.0, 10: 1.0, 11: 1.0, 12: 1.0}
    rows = jr.compare(pl, exp, 3.0, 5)
    check(len(rows) == 1 and rows[0]["levels"] == (8, 13) and abs(rows[0]["expected"] - 1.78) < 1e-9 and rows[0]["status"] == "ok", "one block of five: 5 min against 1.78 is inside x3")
    rows = jr.compare({8: 3.0, 9: 3.0, 10: 3.0, 11: 3.0, 12: 3.0}, exp, 3.0, 5)
    check(rows[0]["status"] == "slow" and rows[0]["ratio"] > 3, "a block over three times the model is slow")
    rows = jr.compare({8: 0.1, 9: 0.1, 10: 0.1, 11: 0.1, 12: 0.1}, exp, 3.0, 5)
    check(rows[0]["status"] == "fast", "a block under a third of the model is fast")
    rows = jr.compare({8: 1.0, 9: 1.0, 10: 1.0, 11: 1.0, 12: 1.0, 13: 1.0, 14: 1.0}, exp, 3.0, 5)
    check(len(rows) == 2 and rows[0]["levels"] == (8, 13) and rows[1]["levels"] == (13, 15) and rows[1]["status"] == "no model", "the next block has levels the model lacks: no model")
    rows = jr.compare({8: 1.0, 9: 1.0, 12: 1.0}, exp, 3.0, 5)
    check([r["levels"] for r in rows] == [(8, 10), (12, 13)], "a gap in the levels splits the block")
    check(jr.compare({}, exp) == [] and jr.compare({8: 1.0}, None)[0]["status"] == "no model", "no levels: no rows; no model: no model")

    a = bot(coverage=[{"group": "opcode", "name": "60 bank", "state": "touched", "detail": "open"}, {"group": "opcode", "name": "65 passivetree", "state": "failed", "detail": "no reply"},
                      {"group": "town", "name": "Cinderhold", "state": "not touched", "detail": ""}])
    b = bot(name="Bot Two", coverage=[{"group": "opcode", "name": "65 passivetree", "state": "touched", "detail": ""}, {"group": "town", "name": "Cinderhold", "state": "failed", "detail": "no way"}])
    cov = jr.coverage_summary([a, b])
    check(cov["opcode"]["65 passivetree"][0] == "touched" and cov["opcode"]["60 bank"][0] == "touched" and cov["town"]["Cinderhold"] == ("failed", "no way"), "coverage merges: touched beats failed beats not touched")

    text = jr.report([a, b], exp, 3.0, 5)
    for want in ("# Journey bots report (O542)", "## Bot One (warrior, vocation 4)", "| 8-13 | 5.00 | 1.78 | 2.8 | ok |", "cause: Troll", "at 32390,32226,7", "no way toward 1,2,3 (hunt: Rat)",
                 "reason cap", "### opcode: 2 touched, 0 not touched, 0 failed", "- Cinderhold: failed (no way)", "Outlier blocks"):
        check(want in text, "report has: " + want)
    text2 = jr.report([bot()], None, 3.0, 5)
    check("not available: no Lua found" in text2 and "no model" in text2, "report without a model says so")
    s = jr.summary([bot(minutesPerLevel={"8": 9.0, "9": 9.0})], exp, 3.0, 5)
    check(s["bots"][0]["outliers"][0]["status"] == "slow" and s["bots"][0]["outliers"][0]["levels"] == [8, 10], "summary lists the outlier blocks")

    d = tempfile.mkdtemp()
    try:
        p1 = os.path.join(d, "a.json")
        pc = os.path.join(d, "curve.json")
        out = os.path.join(d, "r.md")
        js = os.path.join(d, "s.json")
        json.dump(a, open(p1, "w"))
        open(pc, "w").write('{"source":"x","levels":{"8":0.15,"9":0.21,"10":0.38,"11":0.47,"12":0.57}}')
        check(jr.main([p1, "--curve", pc, "--out", out, "--json", js]) == 0 and "Journey bots report" in open(out).read() and json.load(open(js))["bots"][0]["name"] == "Bot One", "command line writes the report and the summary")
        check(jr.main([p1, "--curve", pc, "--tolerance", "1"]) == 2, "a tolerance of 1 or less is refused")
        check(jr.main([os.path.join(d, "missing.json"), "--curve", pc]) == 2, "an unreadable file is a usage error")
    finally:
        shutil.rmtree(d)

    server = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    if shutil.which("luajit") or shutil.which("lua5.3"):
        curve = jr.expected_curve(server, 40)
        check(curve is not None and 8 in curve and 25 in curve and all(v > 0 for v in curve.values()) and curve[25] < 5, "the real model curve: levels 8 to 40, minutes positive and small at 25")
        check(abs(sum(curve[lv] for lv in range(8, 20)) - 5.8) < 3.0, "the real model curve: 8 to 20 in a few minutes (README table: 0.35-0.60 a level)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
