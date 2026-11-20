#!/usr/bin/env python3
"""Test of gen_changelog.py (O687) on a throwaway repository, patch notes, source file and ROADMAP: the patch note parser
(title, intro, leads, the pt-BR twin), the dates from git subjects, the cache of a clone without history, the week
grouping, the roadmap rule, the player-words rule (file names, roadmap numbers, tester bots, other names), --check and its
failures, and the committed data file against the committed sources (the notes of server/data/patchnotes, the real source).

  python3 -I website/tools/gen_changelog_test.py
"""
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_changelog as g  # noqa: E402

checks = 0
failed = 0


def check(ok, what):
    global checks, failed
    checks += 1
    if not ok:
        failed += 1
        print("FAIL: " + what)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def git(repo, date, *args):
    env = dict(os.environ, GIT_AUTHOR_DATE=date + "T12:00:00", GIT_COMMITTER_DATE=date + "T12:00:00", GIT_CONFIG_GLOBAL="/dev/null",
               GIT_CONFIG_SYSTEM="/dev/null")
    subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t.invalid", "-c", "commit.gpgsign=false"] + list(args),
                   env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


NOTE_EN = """# A forge and a fix
Date: 2026-11-04
Kind: news

First paragraph that
wraps two lines.

Second paragraph.

## New

- **A forge window.** The bench has a new window.
  More text on a second line.
- **Orbs from the stash.** Counted at the bench.
- **Uses lua_core.lua inside.** A file name: left out of the points.
- plain bullet without a lead

## Fixes

- **Not shown.** Second section.
"""
NOTE_PT = """# Uma forja e uma correção
Date: 2026-11-04
Kind: news

Primeiro parágrafo.

## Novidades

- **Uma janela de forja.** A bancada tem uma janela nova.
"""


def source(entries, recent=8):
    return {"recent_weeks": recent, "entries": entries}


def entry(eid, ref, en_title="A thing", text="Players can do a thing now.", match=None, kind="new"):
    e = {"id": eid, "ref": ref, "kind": kind, "en": {"title": en_title, "text": text}, "pt-BR": {"title": "Uma coisa", "text": "Agora dá para fazer uma coisa."}}
    if match:
        e["match"] = match
    return e


def featured(e, clip="rift", target="guide:rift", rank=None, headline="A headline", pitch="One line for players."):
    """A curated entry made featured, with a feature block."""
    fb = {"en": {"headline": headline, "pitch": pitch}, "pt-BR": {"headline": "Uma manchete", "pitch": "Uma linha para jogadores."}}
    if clip:
        fb["clip"] = clip
    if target:
        fb["target"] = target
    if rank is not None:
        fb["rank"] = rank
    e["featured"] = True
    e["feature"] = fb
    return e


def gated(eid, ref, when, date=None, **kw):
    e = entry(eid, ref, **kw)
    e["live_when"] = when
    if date:
        e["date"] = date
    return e


ROADMAP = """| # | Item | Status | Notes |
|---|---|---|---|
| O101 | one | done in code and tests | x |
| O102 | two | done | y |
| O103 | three | in progress | z |
| O104 | four | phases a, b done | w |
| O105 | five | superseded by O104 | v |
| O106 | six | design written, waits for review | u |
"""


def main():
    tmp = tempfile.mkdtemp()
    try:
        repo = os.path.join(tmp, "repo")
        os.makedirs(repo)
        subprocess.run(["git", "-C", repo, "init", "-q"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        notes = os.path.join(tmp, "notes")
        write(os.path.join(notes, "2026-11-04.md"), NOTE_EN)
        write(os.path.join(notes, "2026-11-04.pt-br.md"), NOTE_PT)
        write(os.path.join(notes, "README.md"), "# readme\n")
        roadmap = os.path.join(tmp, "ROADMAP.md")
        write(roadmap, ROADMAP)
        src = os.path.join(tmp, "source.json")
        out = os.path.join(tmp, "out", "news_data.json")
        # commits: O101 on a Monday, O102 twice (the later one counts), O104 phases
        write(os.path.join(repo, "a.txt"), "1")
        git(repo, "2026-11-09", "add", "-A")
        git(repo, "2026-11-09", "commit", "-q", "-m", "O101: first thing")
        git(repo, "2026-11-11", "commit", "-q", "--allow-empty", "-m", "O102: second thing, part 1")
        git(repo, "2026-11-19", "commit", "-q", "--allow-empty", "-m", "O102: second thing, part 2")
        git(repo, "2026-11-16", "commit", "-q", "--allow-empty", "-m", "O104 phase B: more")
        kw = dict(repo=repo, notes_dir=notes, source_path=src, roadmap_path=roadmap, out_path=out)

        # parser
        title, header, intro, sections = g.parse_note(NOTE_EN)
        check(title == "A forge and a fix" and header == {"Date": "2026-11-04", "Kind": "news"}, "title and header")
        check(intro == ["First paragraph that wraps two lines.", "Second paragraph."], "intro paragraphs, wrapped lines joined")
        check([n for n, _ in sections] == ["New", "Fixes"] and len(sections[0][1]) == 4, "two sections, four bullets in the first")
        check(sections[0][1][0].endswith("second line."), "a continuation line joins its bullet")
        check(g.lead("**A forge window.** text") == "A forge window" and g.lead("plain") == "", "the lead of a bullet")
        check(g.monday("2026-11-15") == "2026-11-09" and g.monday("2026-11-16") == "2026-11-16" and g.monday("2026-11-22") == "2026-11-16", "weeks run Monday to Sunday")
        check(g.clip("a. b. c", 40) == "a. b. c" and len(g.clip("word " * 100, 60)) <= 63, "clip")

        # a full build
        write(src, json.dumps(source([entry("first-thing", "O101"), entry("second-thing", "O102"), entry("phased", "O104", match="O104 phase B")])))
        data = g.build(**kw)
        flat = [(w["start"], e["id"], e["date"]) for w in data["weeks"] for e in w["entries"]]
        check(flat == [("2026-11-16", "second-thing", "2026-11-19"), ("2026-11-16", "phased", "2026-11-16"),
                       ("2026-11-09", "first-thing", "2026-11-09"), ("2026-11-02", "patch-2026-11-04", "2026-11-04")], "newest first, grouped by week: %s" % flat)
        check(data["latest"] == "2026-11-19" and data["recent_weeks"] == 8 and data["format"] == 1, "latest, recent weeks, format")
        patch = [e for w in data["weeks"] for e in w["entries"] if e["kind"] == "patch"][0]
        check(patch["title"]["pt-BR"] == "Uma forja e uma correção" and patch["patch"] == "2026-11-04", "the patch note keeps its pt-BR twin and its id")
        check(patch["points"]["en"] == ["A forge window", "Orbs from the stash"], "points: the leads of the first section, a file name left out: %s" % patch["points"]["en"])
        check(patch["points"]["pt-BR"] == ["Uma janela de forja"] and patch["text"]["en"] == "First paragraph that wraps two lines.", "pt-BR points and the intro")
        check(all(e["ref"] if "ref" in e else True for w in data["weeks"] for e in w["entries"]) and "ref" not in json.dumps(data), "the roadmap row is never in the data")

        # write, check, stale
        with contextlib.redirect_stdout(io.StringIO()):
            check(g.check(**kw) == ["%s: missing (run gen_changelog.py)" % out], "no data file: a problem")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        blob = g.encode(data)
        write(out, blob)
        check(g.check(**kw) == [], "the file the build gives passes")
        write(out, blob.replace("second-thing", "other-thing"))
        check(len(g.check(**kw)) >= 1, "a changed file is stale")
        write(out, blob)

        # a clone without history keeps the dates of the data file
        bare = os.path.join(tmp, "nohistory")
        os.makedirs(bare)
        data2 = g.build(**dict(kw, repo=bare))
        check(data2 == data, "no history: the dates come from the data file")
        os.remove(out)
        try:
            g.build(**dict(kw, repo=bare))
            check(False, "no history and no data file: refused")
        except g.Error as e:
            check("no commit subject" in str(e), "no history and no data file: refused (%s)" % str(e)[:60])
        write(out, blob)

        # refusals
        def refuses(entries, needle, what):
            write(src, json.dumps(source(entries)))
            try:
                g.build(**kw)
                check(False, what + ": refused")
            except g.Error as e:
                check(needle in str(e), "%s: %s" % (what, str(e)[:90]))

        refuses([entry("x1", "O999")], "no row O999", "a roadmap row that does not exist")
        refuses([entry("x1", "O103")], "not done", "a row in progress")
        refuses([entry("x1", "O105")], "not done", "a superseded row")
        write(src, json.dumps(source([entry("phases", "O104", match="O104 phase B")])))
        check(g.build(**kw)["weeks"][0]["entries"][0]["id"] == "phases", "a status that is not open counts as built")
        refuses([entry("x1", "O101"), entry("x1", "O102")], "once", "a repeated id")
        refuses([entry("X 1", "O101")], "slug", "a bad id")
        refuses([entry("x1", "O101", kind="patch")], "kind", "the patch kind is for notes")
        refuses([entry("x1", "O101", match="no such subject")], "no commit subject", "a match no commit holds")
        refuses([entry("x1", "O101", text="See server/tools/gen_x.py for it")], "internal", "a file name")
        refuses([entry("x1", "O101", text="The tester bots play it now.")], "internal", "the tester bots")
        refuses([entry("x1", "O101", en_title="O687 news")], "internal", "a roadmap number")
        refuses([entry("x1", "O101", text="Opcode 230 carries it.")], "internal", "an opcode")
        refuses([entry("x1", "O101", text="x" * 600)], "characters", "a text too long")
        refuses([entry("x1", "O101", text="")], "empty", "an empty text")
        bad = entry("x1", "O101")
        del bad["pt-BR"]
        refuses([bad], "empty", "a missing pt-BR block")

        # featured news and gates (O688)
        write(src, json.dumps(source([featured(entry("first-thing", "O101"), rank=7), entry("second-thing", "O102")])))
        d4 = g.build(**kw)
        by = {e["id"]: e for w in d4["weeks"] for e in w["entries"]}
        check(by["first-thing"]["featured"] is True and by["first-thing"]["feature"] == {
            "clip": "rift", "target": "guide:rift", "rank": 7,
            "headline": {"en": "A headline", "pt-BR": "Uma manchete"}, "pitch": {"en": "One line for players.", "pt-BR": "Uma linha para jogadores."}},
            "a featured entry carries its feature block into the data")
        check("featured" not in by["second-thing"] and "feature" not in by["second-thing"] and "live_when" not in by["second-thing"], "a plain entry gets none of the new keys")
        check(d4["featured_days"] == 30 and d4["featured_max"] == 3, "the window defaults: 30 days, 3 cards")
        src_cfg = source([entry("first-thing", "O101")])
        src_cfg["featured_days"] = 14
        src_cfg["featured_max"] = 2
        write(src, json.dumps(src_cfg))
        d5 = g.build(**kw)
        check(d5["featured_days"] == 14 and d5["featured_max"] == 2, "featured_days and featured_max come from the source file")
        for key, val in (("featured_days", 0), ("featured_days", 121), ("featured_max", 0), ("featured_max", 7)):
            bad_cfg = source([entry("first-thing", "O101")])
            bad_cfg[key] = val
            write(src, json.dumps(bad_cfg))
            try:
                g.build(**kw)
                check(False, "%s %s refused" % (key, val))
            except g.Error as e:
                check("featured_days" in str(e), "%s %s refused" % (key, val))
        # a featured entry needs its headline and pitch; a block without featured is refused
        plain_feat = entry("first-thing", "O101")
        plain_feat["featured"] = True
        write(src, json.dumps(source([plain_feat])))
        try:
            g.build(**kw)
            check(False, "featured with no feature block: headline refused")
        except g.Error as e:
            check("headline" in str(e), "featured with no feature block needs its headline and pitch (%s)" % str(e)[:60])
        loose = entry("first-thing", "O101")
        loose["feature"] = featured(entry("x", "O101"))["feature"]
        refuses([loose], "featured: true", "a feature block without featured")
        e1 = featured(entry("first-thing", "O101"))
        e1["featured"] = "yes"
        refuses([e1], "true or false", "featured as text")
        refuses([featured(entry("x1", "O101"), clip="no-such-clip")], "not a clip slot", "an unknown clip")
        refuses([featured(entry("x1", "O101"), target="guide:no-such-card")], "no guide card", "an unknown guide card")
        refuses([featured(entry("x1", "O101"), target="serverinfo:nothing")], "no guide card", "an unknown server info section")
        refuses([featured(entry("x1", "O101"), target="wiki:start")], "no guide card", "another kind of target")
        refuses([featured(entry("x1", "O101"), rank=0)], "rank", "rank 0")
        refuses([featured(entry("x1", "O101"), rank=100)], "rank", "rank 100")
        refuses([featured(entry("x1", "O101"), headline="h" * 61)], "characters", "a headline over 60")
        refuses([featured(entry("x1", "O101"), pitch="p" * 141)], "characters", "a pitch over 140")
        refuses([featured(entry("x1", "O101"), pitch="See server/tools/x.py")], "internal", "a file name in the pitch")
        refuses([featured(entry("x1", "O101"), headline="O687 news")], "internal", "a roadmap number in the headline")
        nopt = featured(entry("x1", "O101"))
        del nopt["feature"]["pt-BR"]
        refuses([nopt], "empty", "a feature block without pt-BR")
        odd = featured(entry("x1", "O101"))
        odd["feature"]["colour"] = "red"
        refuses([odd], "feature key", "an unknown feature key")
        none = featured(entry("x1", "O101"), clip=None, target=None)
        write(src, json.dumps(source([none])))
        check("clip" not in g.build(**kw)["weeks"][0]["entries"][0]["feature"], "a feature block may have no clip and no target")

        # gated entries: the row must exist, not be built; a flag needs the day it was written, a date gate dates the entry
        write(src, json.dumps(source([gated("future", "O106", "flag:spell_upgrades", date="2026-11-20"), entry("second-thing", "O102")])))
        d6 = g.build(**kw)
        by6 = {e["id"]: e for w in d6["weeks"] for e in w["entries"]}
        check(by6["future"]["live_when"] == "flag:spell_upgrades" and by6["future"]["date"] == "2026-11-20", "a flag gated entry keeps its written date and its gate")
        check(by6["second-thing"]["date"] == "2026-11-19", "the others are still dated by git")
        write(src, json.dumps(source([gated("dated", "O106", "date:2026-12-01")])))
        check(g.build(**kw)["weeks"][0]["entries"][0]["date"] == "2026-12-01", "a date gate dates the entry by its gate")
        write(src, json.dumps(source([gated("future", "O103", "flag:spell_upgrades", date="2026-11-20")])))
        check(g.build(**kw)["weeks"][0]["entries"][0]["id"] == "future", "a gated entry may name a row that is not done yet")
        refuses([gated("future", "O999", "flag:spell_upgrades", date="2026-11-20")], "no row O999", "a gated entry still needs its row")
        refuses([gated("future", "O106", "flag:spell_upgrades")], "needs `date`", "a flag gate without a date")
        refuses([gated("future", "O106", "flag:spell_upgrades", date="20-11-2026")], "needs `date`", "a flag gate with a bad date")
        refuses([gated("future", "O106", "flag:spell_upgrades", date="2026-13-45")], "not a date", "a flag gate with an impossible date")
        refuses([gated("future", "O106", "date:2026-12-01", date="2026-11-20")], "drop `date`", "a date gate with a date")
        refuses([gated("future", "O106", "date:2026-02-31")], "not a date", "a date gate with an impossible date")
        refuses([gated("future", "O106", "soon", date="2026-11-20")], "live_when", "a gate that is neither flag nor date")
        refuses([gated("future", "O106", "flag:Bad Name", date="2026-11-20")], "live_when", "a bad flag name")
        refuses([gated("future", "O106", "flag:x", date="2026-11-20")], "live_when", "a one letter flag name")
        refuses([entry("x1", "O101"), dict(entry("x2", "O102"), date="2026-11-20")], "only for a gated", "a date on an ungated entry")
        refuses([gated("future", "O106", "flag:spell_upgrades", date="2026-11-20", text="Opcode 168 carries it.")], "internal", "a gated entry is held to the player words too")
        # a clean check with gated entries: no commit is asked for them, the file is what the build gives
        write(src, json.dumps(source([gated("future", "O106", "flag:spell_upgrades", date="2026-11-20"), featured(gated("gfeat", "O106", "date:2026-12-01"), rank=3), entry("second-thing", "O102")])))
        blob2 = g.encode(g.build(**kw))
        write(out, blob2)
        check(g.check(**kw) == [], "a gated entry needs no commit subject (check passes)")
        write(out, blob)

        # the archive: weeks past recent_weeks
        write(src, json.dumps(source([entry("first-thing", "O101"), entry("second-thing", "O102")], recent=2)))
        d3 = g.build(**kw)
        check(d3["recent_weeks"] == 2 and len(d3["weeks"]) == 3, "recent_weeks 2 of 3 weeks: the page's archive holds the third")
        write(src, json.dumps(source([], recent=0)))
        try:
            g.build(**kw)
            check(False, "recent_weeks 0 refused")
        except g.Error:
            check(True, "recent_weeks 0 refused")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # the committed data file is what the committed sources give; every text is bilingual and fit for players
    with contextlib.redirect_stdout(io.StringIO()):
        problems = g.check()
    check(problems == [], "the committed news data is up to date: %s" % problems)
    with open(g.OUT, encoding="utf-8") as f:
        real = json.load(f)
    ids = []
    for w in real["weeks"]:
        check(g.monday(w["start"]) == w["start"], "week %s starts on a Monday" % w["start"])
        for e in w["entries"]:
            ids.append(e["id"])
            check(g.monday(e["date"]) == w["start"], "%s sits in its week" % e["id"])
            for lang in g.LANGS:
                check(e["title"][lang].strip() != "" and (e["kind"] == "patch" or e["text"][lang].strip() != ""), "%s has %s text" % (e["id"], lang))
                for s in [e["title"][lang], e["text"][lang]] + e["points"][lang]:
                    check(not g.INTERNAL.search(s) and not g.NAME_HIT(s) and "—" not in s and "–" not in s, "%s (%s) reads as player words: %s" % (e["id"], lang, s[:50]))
    check(len(ids) == len(set(ids)) and len(ids) >= 20, "at least twenty distinct entries (%d)" % len(ids))
    # O688: the featured and gated entries of the real source
    entries = {e["id"]: e for w in real["weeks"] for e in w["entries"]}
    check(real["featured_days"] == 30 and real["featured_max"] == 3, "the shipped window: 30 days, 3 cards")
    for eid in ("loot-explosion", "pinnacle", "greater-rift", "waystone-endgame"):
        check(entries[eid].get("featured") is True and "live_when" not in entries[eid], "%s is featured and live" % eid)
    gate_ids = [i for i, e in entries.items() if "live_when" in e]
    check(sorted(gate_ids) == ["spell-awakening", "spell-combos", "spell-forms", "spell-ranks"], "the four spell entries are the gated ones: %s" % gate_ids)
    for eid in gate_ids:
        check(entries[eid]["live_when"] == "flag:spell_upgrades" and g.DATE.match(entries[eid]["date"]), "%s: flag spell_upgrades and a written date" % eid)
    for eid, e in entries.items():
        if not e.get("featured"):
            continue
        fb = e["feature"]
        check(set(fb) <= {"clip", "target", "rank", "headline", "pitch"} and "headline" in fb and "pitch" in fb, "%s: feature block keys" % eid)
        for lang in g.LANGS:
            check(0 < len(fb["headline"][lang]) <= g.MAX_HEADLINE and 0 < len(fb["pitch"][lang]) <= g.MAX_PITCH, "%s (%s): headline and pitch fit" % (eid, lang))
            for t in (fb["headline"][lang], fb["pitch"][lang]):
                check(not g.INTERNAL.search(t) and not g.NAME_HIT(t) and "—" not in t and "–" not in t, "%s (%s) feature reads as player words: %s" % (eid, lang, t[:50]))
        check(fb["headline"]["en"] != fb["headline"]["pt-BR"], "%s: the headline is translated" % eid)
    check(real["weeks"][0]["entries"][0]["date"] == real["latest"], "the newest entry is the latest date")
    print("gen_changelog_test: %d checks, %d failed" % (checks, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
