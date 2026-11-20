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


ROADMAP = """| # | Item | Status | Notes |
|---|---|---|---|
| O101 | one | done in code and tests | x |
| O102 | two | done | y |
| O103 | three | in progress | z |
| O104 | four | phases a, b done | w |
| O105 | five | superseded by O104 | v |
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
    check(real["weeks"][0]["entries"][0]["date"] == real["latest"], "the newest entry is the latest date")
    print("gen_changelog_test: %d checks, %d failed" % (checks, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
