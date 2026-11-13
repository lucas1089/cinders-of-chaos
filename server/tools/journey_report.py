#!/usr/bin/env python3
"""Journey bot report (O542, unity/README.md "Journey bots (O542)").

Reads the metrics JSON of the journey bots (unity/Core.LiveCheck, `--journey --journey-out FILE`) and writes one report:
per bot the level reached, minutes per level against the expectation of server/tools/progression_model.lua (a tolerance band,
outliers flagged), deaths with cause and position, stuck events with position, kills / xp / gold per hour, potions, trips, and the
coverage table (systems, client opcodes, towns, hunts, map areas: touched / not touched / failed with the error).

  python3 -I server/tools/journey_report.py BOT.json [BOT.json ...] [--curve FILE | --model-dir SERVER_DIR]
                                            [--tolerance 3] [--block 5] [--out report.md] [--json summary.json]

The expectation (minutes a level, level L to L + 1) comes from `luajit tools/progression_model.lua --curve-json N` (run in SERVER_DIR,
default: the server folder of this checkout, luajit or lua5.3) or from a file of that output (--curve). The model is computed, not measured,
and counts no walking, no loot and no town trips: the band is wide on purpose (default x3 each way) and the check is made per block of
levels (default 5), since a level of a tenth of a minute cannot be timed by a bot. A block outside the band is an outlier: the point of
the report is to find the levels where a real player's pace and the model's part ways, not to pass or fail a run.
Exit 0 always for a readable report; 2 on a usage error or an unreadable file.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

DEFAULT_TOLERANCE = 3.0
DEFAULT_BLOCK = 5


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def expected_curve(model_dir, max_level):
    """The model's minutes per level as {level: minutes}, from progression_model.lua. None when no Lua is installed."""
    for exe in ("luajit", "lua5.3", "lua"):
        if shutil.which(exe) is None:
            continue
        try:
            out = subprocess.run([exe, "tools/progression_model.lua", "--curve-json", str(max_level)], cwd=model_dir, capture_output=True,
                                 text=True, timeout=120, check=True).stdout
            return parse_curve(out)
        except (subprocess.SubprocessError, OSError, ValueError):
            continue
    return None


def parse_curve(text):
    data = json.loads(text)
    return {int(k): float(v) for k, v in data["levels"].items()}


def compare(per_level, expected, tolerance=DEFAULT_TOLERANCE, block=DEFAULT_BLOCK):
    """Minutes per level of one bot against the model.

    per_level: {level: minutes} of the completed levels. expected: {level: minutes}. Returns a list of rows, one per block of `block`
    levels the bot completed whole (or the last partial block): {levels: (a, b), actual, expected, ratio, status}, status is "ok",
    "slow" (actual above expected x tolerance), "fast" (below expected / tolerance) or "no model" (the model has no number)."""
    rows = []
    levels = sorted(per_level)
    i = 0
    while i < len(levels):
        grp = [levels[i]]
        while len(grp) < block and i + len(grp) < len(levels) and levels[i + len(grp)] == grp[-1] + 1:
            grp.append(levels[i + len(grp)])
        i += len(grp)
        actual = sum(per_level[lv] for lv in grp)
        exp = sum(expected[lv] for lv in grp if lv in expected) if expected else 0.0
        have_model = bool(expected) and all(lv in expected for lv in grp)
        if not have_model or exp <= 0:
            rows.append({"levels": (grp[0], grp[-1] + 1), "actual": actual, "expected": exp if have_model else None, "ratio": None, "status": "no model"})
            continue
        ratio = actual / exp
        status = "slow" if ratio > tolerance else "fast" if ratio < 1.0 / tolerance else "ok"
        rows.append({"levels": (grp[0], grp[-1] + 1), "actual": actual, "expected": exp, "ratio": ratio, "status": status})
    return rows


def pos_text(p):
    return ",".join(str(int(v)) for v in p) if isinstance(p, (list, tuple)) and len(p) == 3 else str(p)


def coverage_summary(bots):
    """Merged coverage over the bots: per group {name: (state, detail)}; a touch by any bot counts, else a failure, else not touched."""
    groups = {}
    order = {"touched": 2, "failed": 1, "not touched": 0}
    for bot in bots:
        for row in bot.get("coverage", []):
            g = groups.setdefault(row["group"], {})
            cur = g.get(row["name"])
            if cur is None or order[row["state"]] > order[cur[0]]:
                g[row["name"]] = (row["state"], row.get("detail", ""))
    return groups


def bot_section(bot, expected, tolerance, block):
    out = []
    pl = {int(k): float(v) for k, v in bot.get("minutesPerLevel", {}).items()}
    out.append("## %s (%s, vocation %s)" % (bot.get("name", "?"), bot.get("class", "?"), bot.get("vocation", "?")))
    out.append("")
    out.append("Level %s to %s in %.1f minutes. Stop: %s." % (bot.get("startLevel"), bot.get("level"), bot.get("minutes", 0), bot.get("stop", "") or "-"))
    out.append("")
    out.append("| Number | Value |")
    out.append("|---|---|")
    for label, key, fmt in (("Kills", "kills", "%d"), ("Kills per hour", "killsPerHour", "%.0f"), ("Experience gained", "xp", "%d"),
                            ("Experience per hour", "xpPerHour", "%.0f"), ("Gold earned", "goldEarned", "%d"), ("Gold spent", "goldSpent", "%d"),
                            ("Gold per hour", "goldPerHour", "%.0f"), ("Potions used", "potionsUsed", "%d"), ("Potions bought", "potionsBought", "%d"),
                            ("Trips to town", None, "%d"), ("Deaths", None, "%d"), ("Stuck events", None, "%d"), ("Reconnects", "reconnects", "%d"),
                            ("Hunts given up", "gaveUpHunts", "%d")):
        if key is not None:
            val = bot.get(key, 0)
        elif label == "Trips to town":
            val = len(bot.get("trips", []))
        elif label == "Deaths":
            val = len(bot.get("deaths", []))
        else:
            val = len(bot.get("stuck", []))
        out.append("| %s | %s |" % (label, fmt % val))
    out.append("")
    out.append("### Minutes per level against the model")
    out.append("")
    rows = compare(pl, expected, tolerance, block)
    if not rows:
        out.append("No level was completed.")
    else:
        out.append("| Levels | Minutes (bot) | Minutes (model) | Ratio | Status |")
        out.append("|---|---|---|---|---|")
        for r in rows:
            out.append("| %d-%d | %.2f | %s | %s | %s |" % (r["levels"][0], r["levels"][1], r["actual"], "-" if r["expected"] is None else "%.2f" % r["expected"],
                                                          "-" if r["ratio"] is None else "%.1f" % r["ratio"], r["status"]))
        bad = [r for r in rows if r["status"] in ("slow", "fast")]
        out.append("")
        out.append("Tolerance: the bot's block time within x%.1f of the model's (and not under 1/%.1f). Outliers: %s." % (
            tolerance, tolerance, ", ".join("%d-%d %s" % (r["levels"][0], r["levels"][1], r["status"]) for r in bad) if bad else "none"))
    out.append("")
    out.append("### Deaths")
    out.append("")
    deaths = bot.get("deaths", [])
    if not deaths:
        out.append("None.")
    for d in deaths:
        out.append("- minute %.1f, level %s, at %s, cause: %s" % (d.get("minute", 0), d.get("level"), pos_text(d.get("pos")), d.get("cause")))
    out.append("")
    out.append("### Stuck events")
    out.append("")
    stuck = bot.get("stuck", [])
    if not stuck:
        out.append("None.")
    for d in stuck:
        out.append("- minute %.1f, at %s, %s%s" % (d.get("minute", 0), pos_text(d.get("pos")), d.get("what"), " (hunt: %s)" % d["hunt"] if d.get("hunt") else ""))
    out.append("")
    trips = bot.get("trips", [])
    out.append("### Trips to town")
    out.append("")
    if not trips:
        out.append("None.")
    for t in trips:
        out.append("- minute %.1f, level %s, reason %s, %.1f minutes, sold for %s gold" % (t.get("minute", 0), t.get("level"), t.get("reason"), t.get("minutes", 0), t.get("sold", 0)))
    out.append("")
    hunts = bot.get("hunts", [])
    if hunts:
        out.append("### Hunts picked")
        out.append("")
        for h in hunts:
            out.append("- " + h)
        out.append("")
    return out


def report(bots, expected, tolerance=DEFAULT_TOLERANCE, block=DEFAULT_BLOCK):
    out = ["# Journey bots report (O542)", ""]
    out.append("Expectation: server/tools/progression_model.lua, minutes a level%s. Band: x%.1f each way, blocks of %d levels." % (
        "" if expected else " (not available: no Lua found, the comparison is skipped)", tolerance, block))
    out.append("")
    out.append("| Bot | Class | Level | Minutes | Kills | Deaths | Stuck | Outlier blocks |")
    out.append("|---|---|---|---|---|---|---|---|")
    for b in bots:
        pl = {int(k): float(v) for k, v in b.get("minutesPerLevel", {}).items()}
        bad = [r for r in compare(pl, expected, tolerance, block) if r["status"] in ("slow", "fast")]
        out.append("| %s | %s | %s to %s | %.1f | %s | %d | %d | %d |" % (b.get("name", "?"), b.get("class", "?"), b.get("startLevel"), b.get("level"), b.get("minutes", 0),
                                                                        b.get("kills", 0), len(b.get("deaths", [])), len(b.get("stuck", [])), len(bad)))
    out.append("")
    for b in bots:
        out.extend(bot_section(b, expected, tolerance, block))
    out.append("## Coverage of the bots together")
    out.append("")
    groups = coverage_summary(bots)
    for g in sorted(groups):
        rows = groups[g]
        n = {"touched": 0, "not touched": 0, "failed": 0}
        for st, _ in rows.values():
            n[st] += 1
        out.append("### %s: %d touched, %d not touched, %d failed" % (g, n["touched"], n["not touched"], n["failed"]))
        out.append("")
        if g in ("area",):
            out.append("%d map cells of 64x64 tiles visited." % n["touched"])
            out.append("")
            continue
        for name in sorted(rows):
            st, detail = rows[name]
            if g in ("hunt", "opcode") and st == "touched" and not detail:
                continue
            out.append("- %s: %s%s" % (name, st, " (%s)" % detail if detail else ""))
        out.append("")
    return "\n".join(out) + "\n"


def summary(bots, expected, tolerance=DEFAULT_TOLERANCE, block=DEFAULT_BLOCK):
    s = {"tolerance": tolerance, "block": block, "bots": []}
    for b in bots:
        pl = {int(k): float(v) for k, v in b.get("minutesPerLevel", {}).items()}
        rows = compare(pl, expected, tolerance, block)
        s["bots"].append({"name": b.get("name"), "class": b.get("class"), "level": b.get("level"), "minutes": b.get("minutes"), "deaths": len(b.get("deaths", [])),
                          "stuck": len(b.get("stuck", [])), "outliers": [{"levels": list(r["levels"]), "status": r["status"], "ratio": r["ratio"]} for r in rows if r["status"] in ("slow", "fast")]})
    return s


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("bots", nargs="+", help="metrics JSON of journey bots")
    ap.add_argument("--curve", help="output of progression_model.lua --curve-json (default: run it)")
    ap.add_argument("--model-dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."), help="the server folder (tools/progression_model.lua)")
    ap.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE)
    ap.add_argument("--block", type=int, default=DEFAULT_BLOCK)
    ap.add_argument("--out", help="write the markdown report here (else stdout)")
    ap.add_argument("--json", help="write a short JSON summary here")
    a = ap.parse_args(argv)
    if a.tolerance <= 1 or a.block < 1:
        print("tolerance must be above 1 and block at least 1", file=sys.stderr)
        return 2
    try:
        bots = [load_json(p) for p in a.bots]
        top = max([int(b.get("level", 1)) for b in bots] + [30]) + 5
        expected = parse_curve(open(a.curve, encoding="utf-8").read()) if a.curve else expected_curve(a.model_dir, top)
    except (OSError, ValueError, KeyError) as e:
        print("journey_report: " + str(e), file=sys.stderr)
        return 2
    text = report(bots, expected, a.tolerance, a.block)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(summary(bots, expected, a.tolerance, a.block), f, indent=1)
            f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
