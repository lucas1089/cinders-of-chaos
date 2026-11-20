#!/usr/bin/env python3
"""The news page "Novidades" / "News" of the website (O687; website/README.md "News and changelog (O687)").

Writes website/overlay/plugins/chaos/news/news_data.json, the one data file the page reads. Two sources, one list:

  1. The patch notes: server/data/patchnotes/YYYY-MM-DD.md and the pt-BR twin YYYY-MM-DD.pt-br.md (the notes the game
     and the Discord bot publish). One entry per note: its title, its first paragraph and the lead words of the first
     bullets of its first section.
  2. website/tools/changelog_source.json: player-facing entries for what reached the game since the last note (or
     what a note did not say). Each entry names its ROADMAP row (`ref`, never shown): the row must exist and not be open (todo, in progress, superseded).
     Its date is the day of the latest git commit whose subject holds the entry's `match` text (default: the ref and a
     colon). A clone without that history (CI checks out one commit) keeps the date the data file already has, so
     `--check` needs no history; with the history it also holds every date to git.

A curated entry may also be featured (O688, website/README.md "Featured news (O688)"): `featured: true` and an optional
`feature` block (headline, one-line pitch in both languages, a `clip` slot id of the mechanics clips, a `target` section
of the guide or the server info page, a `rank` 1..99 that orders entries of the same day, lower first). The site shows a fresh featured entry as a banner, a NEW badge and a tag on its
target section. `live_when` gates an entry: `flag:<key>` (the site reads the key, off until the owner switches the
system on) or `date:YYYY-MM-DD`; a gated entry is in the file but the site hides it until the gate opens, and its ROADMAP
row need only exist (the system may not be built yet).

Entries are grouped by week (Monday to Sunday), newest first. The page shows the last `recent_weeks` weeks and puts the
older ones in an archive. Player words only: a text with a file name, a roadmap number, an opcode, the tester bots, an
address or a name that check_names.py refuses is an error (a patch note bullet that breaks the rule is left out).

  python3 -I website/tools/gen_changelog.py            write the data file
  python3 -I website/tools/gen_changelog.py --check    the file is what the sources give (exit 1 when not)
  python3 -I website/tools/gen_changelog.py --print    the JSON on stdout

Stdlib only. Tests: website/tools/gen_changelog_test.py.
"""
import datetime
import importlib.util
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
FORMAT = 1
LANGS = ("en", "pt-BR")
KINDS = ("new", "change", "balance", "fix", "patch")
MAX_TITLE = 90
MAX_TEXT = 520
MAX_POINT = 90
MAX_POINTS = 4
MAX_INTRO = 300
DEFAULT_RECENT = 8
OUT = os.path.join(REPO, "website", "overlay", "plugins", "chaos", "news", "news_data.json")
SOURCE = os.path.join(HERE, "changelog_source.json")
NOTES = os.path.join(REPO, "server", "data", "patchnotes")
ROADMAP = os.path.join(REPO, "ROADMAP.md")
GUIDE = os.path.join(REPO, "website", "overlay", "plugins", "chaos", "guide", "guide_data.json")
SERVERINFO = os.path.join(REPO, "website", "overlay", "layouts", "chaos", "views", "serverinfo.php")
MEDIA = os.path.join(HERE, "gen_site_media.py")
MAX_HEADLINE = 60
MAX_PITCH = 140
DEFAULT_FEATURED_DAYS = 30
DEFAULT_FEATURED_MAX = 3

NOTE_ID = re.compile(r"^(\d{4}-\d{2}-\d{2})\.md$")
SLUG = re.compile(r"^[a-z0-9][a-z0-9-]{1,48}$")
REF = re.compile(r"^O\d{2,4}$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
TARGET = re.compile(r"^(guide|serverinfo):([a-z0-9_-]{2,40})$")
LIVE_WHEN = re.compile(r"^(?:date:(\d{4}-\d{2}-\d{2})|flag:([a-z][a-z0-9_]{1,40}))$")
# words for the team, not for players
INTERNAL = re.compile(
    r"\b[\w-]+\.(?:lua|py|json|md|php|sh|otui|otmod|xml|csv|patch|sql|ya?ml|rs|java|cpp|h|txt)\b|\bO\d{2,4}\b|"
    r"\bopcodes?\b|\btesters?\b|\bbots?\b|src-patch|base patch|windows-assets|\bCI\b|workflow|pull request|\bgit(?:hub)?\b|"
    r"\broadmap\b|\breadme\b|\bpairs? \d|https?://|www\.|@\w|\bpixellab\b|\bclaude\b|\bAI\b", re.I)


# a ROADMAP status that says the work did not ship (anything else, "done ..." or the phases of a row, counts as built)
NOT_DONE = ("todo", "in progress", "superseded", "not started", "dropped", "blocked", "waits", "tool, table")


class Error(Exception):
    pass


def load_names():
    path = os.path.join(REPO, "tools", "ci", "check_names.py")
    try:
        spec = importlib.util.spec_from_file_location("chaos_check_names", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.name_hit
    except Exception:  # noqa: BLE001 - without the names check nothing may be published
        return None


NAME_HIT = load_names()


def player_text(text, where):
    """The text when it is fit for players, else an Error naming where."""
    if not isinstance(text, str) or not text.strip():
        raise Error("%s: empty text" % where)
    if INTERNAL.search(text):
        raise Error("%s: reads as internal (%s): %s" % (where, INTERNAL.search(text).group(0), text[:80]))
    if NAME_HIT is None or NAME_HIT(text):
        raise Error("%s: a name check_names.py refuses (or no names check): %s" % (where, text[:80]))
    return text.strip()


def plain(s):
    """One line of Markdown as plain text."""
    s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)
    s = re.sub(r"[`*]+", "", s)
    return re.sub(r"\s+", " ", s).strip()


def clip(s, n):
    if len(s) <= n:
        return s
    cut = s[:n]
    stop = max(cut.rfind(". "), cut.rfind("; "))
    if stop > n // 2:
        return cut[:stop + 1]
    return cut[:cut.rfind(" ")].rstrip(",;:") + "..."


# ---------------------------------------------------------------- patch notes
def parse_note(text):
    """title, header {Key: value}, intro paragraphs, sections [(name, [bullet text])] of a patch note."""
    lines = text.replace("\r\n", "\n").split("\n")
    if not lines or not lines[0].startswith("# "):
        raise Error("a patch note must start with '# Title'")
    title = plain(lines[0][2:])
    i = 1
    header = {}
    while i < len(lines) and re.match(r"^[A-Za-z][A-Za-z-]*:\s", lines[i]):
        k, v = lines[i].split(":", 1)
        header[k.strip()] = v.strip()
        i += 1
    intro, para, sections, cur = [], [], [], None
    for line in lines[i:]:
        if line.startswith("## "):
            if para and cur is None:
                intro.append(" ".join(para))
                para = []
            cur = [plain(line[3:]), []]
            sections.append(cur)
        elif cur is None:
            if line.strip():
                para.append(line.strip())
            elif para:
                intro.append(" ".join(para))
                para = []
        elif line.startswith("- "):
            cur[1].append(line[2:].strip())
        elif line.startswith("  ") and cur[1] and line.strip() and not line.lstrip().startswith("- "):
            cur[1][-1] += " " + line.strip()
    if para and cur is None:
        intro.append(" ".join(para))
    return title, header, [plain(p) for p in intro], [(n, b) for n, b in sections]


def lead(bullet):
    """The bold lead of a bullet ("**A forge window.** text" -> "A forge window"), '' when it has none."""
    m = re.match(r"^\*\*(.+?)\*\*", bullet)
    return m.group(1).strip().rstrip(".:") if m else ""


def note_entries(notes_dir):
    out = []
    for name in sorted(os.listdir(notes_dir)):
        m = NOTE_ID.match(name)
        if not m:
            continue
        nid = m.group(1)
        loaded = {}
        for lang, fname in (("en", name), ("pt-BR", nid + ".pt-br.md")):
            path = os.path.join(notes_dir, fname)
            if not os.path.isfile(path):
                if lang == "en":
                    raise Error("%s: unreadable" % path)
                loaded[lang] = loaded["en"]  # a note without a twin shows its English text
                continue
            with open(path, encoding="utf-8") as f:
                title, header, intro, sections = parse_note(f.read())
            if header.get("Date") != nid:
                raise Error("%s: Date line %r, the file says %s" % (fname, header.get("Date"), nid))
            loaded[lang] = (title, intro, sections)
        entry = {"id": "patch-" + nid, "date": nid, "kind": "patch", "patch": nid,
                 "title": {}, "text": {}, "points": {}}
        for lang in LANGS:
            title, intro, sections = loaded[lang]
            where = "patch note %s (%s)" % (nid, lang)
            entry["title"][lang] = player_text(clip(title, MAX_TITLE), where + " title")
            entry["text"][lang] = player_text(clip(intro[0], MAX_INTRO), where + " intro") if intro else ""
            pts = []
            for b in (sections[0][1] if sections else []):
                s = lead(b)
                if not s or len(s) > MAX_POINT or INTERNAL.search(s) or NAME_HIT is None or NAME_HIT(s):
                    continue  # left out, not an error: the note itself was written for players
                pts.append(s)
                if len(pts) == MAX_POINTS:
                    break
            entry["points"][lang] = pts
        out.append(entry)
    return out


# ---------------------------------------------------------------- roadmap and git
def roadmap_status(path):
    """ref -> status text of the ROADMAP rows `| O123 | item | status | notes |`."""
    rows = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\| (O\d{2,4}) \| (.*)$", line)
            if m:
                cells = m.group(2).split(" | ")
                rows[m.group(1)] = (cells[1] if len(cells) > 1 else "").strip().lower()
    return rows


def git_subjects(repo):
    """[(date, subject)] of the non-merge commits of HEAD, newest first; [] without a repository."""
    try:
        r = subprocess.run(["git", "-C", repo, "log", "--no-merges", "--format=%ad%x09%s", "--date=short", "HEAD"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
    except (OSError, subprocess.CalledProcessError):
        return []
    return [tuple(l.split("\t", 1)) for l in r.stdout.decode("utf-8", "replace").split("\n") if "\t" in l]


def is_shallow(repo):
    try:
        r = subprocess.run(["git", "-C", repo, "rev-parse", "--is-shallow-repository"], stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, check=True)
        return r.stdout.decode().strip() != "false"
    except (OSError, subprocess.CalledProcessError):
        return True


def monday(date):
    d = datetime.date.fromisoformat(date)
    return (d - datetime.timedelta(days=d.weekday())).isoformat()


# ---------------------------------------------------------------- featured news (O688)
def feature_refs(guide_path=GUIDE, serverinfo_path=SERVERINFO, media_path=MEDIA):
    """What a feature block may point at: guide card keys, server info section ids, mechanics clip ids."""
    with open(guide_path, encoding="utf-8") as f:
        guide = set((json.load(f).get("cards") or {}).keys())
    with open(serverinfo_path, encoding="utf-8") as f:
        info = set(re.findall(r"^\t'([a-z0-9_]+)' => array\(", f.read(), re.M))
    with open(media_path, encoding="utf-8") as f:
        text = f.read()
    block = text[text.index("CLIPS = ("):]
    block = block[:block.index("\n)")]
    clips = set(re.findall(r'^\s+\("([a-z0-9-]+)",', block, re.M))
    return {"guide": guide, "serverinfo": info, "clips": clips}


def gate(eid, raw):
    """(live_when text or None, gate date or None) of a source entry."""
    live = raw.get("live_when")
    if live is None:
        return None, None
    m = LIVE_WHEN.match(live) if isinstance(live, str) else None
    if not m:
        raise Error("%s: live_when must be flag:<key> or date:YYYY-MM-DD" % eid)
    if m.group(1):
        try:
            datetime.date.fromisoformat(m.group(1))
        except ValueError:
            raise Error("%s: live_when date %s is not a date" % (eid, m.group(1)))
    return live, m.group(1)


def feature_block(eid, raw, refs):
    """The `feature` block of the data file: {clip, target, headline, pitch}; clip and target only when given."""
    fb = raw.get("feature") or {}
    if not isinstance(fb, dict):
        raise Error("%s: feature must be an object" % eid)
    for k in fb:
        if k not in ("clip", "target", "rank", "en", "pt-BR"):
            raise Error("%s: feature key %r" % (eid, k))
    out = {}
    if fb.get("clip") is not None:
        if fb["clip"] not in refs["clips"]:
            raise Error("%s: feature clip %r is not a clip slot (%s)" % (eid, fb["clip"], ", ".join(sorted(refs["clips"]))))
        out["clip"] = fb["clip"]
    if fb.get("target") is not None:
        m = TARGET.match(fb["target"]) if isinstance(fb["target"], str) else None
        if not m or m.group(2) not in refs[m.group(1)]:
            raise Error("%s: feature target %r is no guide card or server info section" % (eid, fb.get("target")))
        out["target"] = fb["target"]
    if fb.get("rank") is not None:
        if isinstance(fb["rank"], bool) or not isinstance(fb["rank"], int) or not 1 <= fb["rank"] <= 99:
            raise Error("%s: feature rank is a whole number 1..99 (lower shows first on the same day)" % eid)
        out["rank"] = fb["rank"]
    headline, pitch = {}, {}
    for lang in LANGS:
        block = fb.get(lang) or {}
        where = "%s feature (%s)" % (eid, lang)
        headline[lang] = player_text(block.get("headline"), where + " headline")
        pitch[lang] = player_text(block.get("pitch"), where + " pitch")
        if len(headline[lang]) > MAX_HEADLINE or len(pitch[lang]) > MAX_PITCH:
            raise Error("%s: headline over %d or pitch over %d characters" % (where, MAX_HEADLINE, MAX_PITCH))
    out["headline"] = headline
    out["pitch"] = pitch
    return out


# ---------------------------------------------------------------- build
def curated_entries(source, roadmap, subjects, cached, shallow, refs=None):
    entries = []
    seen = set()
    for raw in source.get("entries", []):
        eid, ref, kind = raw.get("id"), raw.get("ref"), raw.get("kind")
        if not isinstance(eid, str) or not SLUG.match(eid) or eid in seen:
            raise Error("entry id %r: a lower-case slug, once" % (eid,))
        seen.add(eid)
        if not isinstance(ref, str) or not REF.match(ref):
            raise Error("%s: ref must look like O123" % eid)
        status = roadmap.get(ref)
        if status is None:
            raise Error("%s: ROADMAP has no row %s" % (eid, ref))
        live_when, gate_date = gate(eid, raw)
        # a gated entry is written before its system is built: its row need only exist
        if live_when is None and status.startswith(NOT_DONE):
            raise Error("%s: ROADMAP row %s is not done (%s)" % (eid, ref, status[:40]))
        if kind not in KINDS or kind == "patch":
            raise Error("%s: kind %r" % (eid, kind))
        explicit = raw.get("date")
        if live_when is None:
            if explicit is not None:
                raise Error("%s: date is only for a gated entry (the others are dated by git)" % eid)
            match = raw.get("match") or ref + ":"
            git_date = next((d for d, s in subjects if match in s), None)
            # a shallow clone sees only the newest commits: the date the data file has is the truth there
            date = cached.get(eid) if shallow and eid in cached else (git_date or cached.get(eid))
            if date is None:
                raise Error("%s: no commit subject holds %r and the data file has no date for it" % (eid, match))
        elif gate_date:
            if explicit is not None:
                raise Error("%s: a date: gate dates the entry, drop `date`" % eid)
            date = gate_date
        else:
            if not isinstance(explicit, str) or not DATE.match(explicit):
                raise Error("%s: a flag: gate needs `date` (YYYY-MM-DD, the day it was written)" % eid)
            try:
                datetime.date.fromisoformat(explicit)
            except ValueError:
                raise Error("%s: date %s is not a date" % (eid, explicit))
            date = explicit
        entry = {"id": eid, "date": date, "kind": kind, "patch": None, "title": {}, "text": {}, "points": {}}
        for lang in LANGS:
            block = raw.get(lang) or {}
            where = "%s (%s)" % (eid, lang)
            entry["title"][lang] = player_text(block.get("title"), where + " title")
            entry["text"][lang] = player_text(block.get("text"), where + " text")
            if len(entry["title"][lang]) > MAX_TITLE or len(entry["text"][lang]) > MAX_TEXT:
                raise Error("%s: title over %d or text over %d characters" % (where, MAX_TITLE, MAX_TEXT))
            entry["points"][lang] = []
        featured = raw.get("featured", False)
        if not isinstance(featured, bool):
            raise Error("%s: featured is true or false" % eid)
        if raw.get("feature") is not None and not featured:
            raise Error("%s: a feature block needs featured: true" % eid)
        if featured:
            entry["featured"] = True
            entry["feature"] = feature_block(eid, raw, refs or feature_refs())
        if live_when is not None:
            entry["live_when"] = live_when
        entries.append(entry)
    return entries


def build(repo=REPO, notes_dir=NOTES, source_path=SOURCE, roadmap_path=ROADMAP, out_path=OUT, guide_path=GUIDE,
          serverinfo_path=SERVERINFO, media_path=MEDIA):
    with open(source_path, encoding="utf-8") as f:
        source = json.load(f)
    cached = {}
    if os.path.isfile(out_path):
        try:
            with open(out_path, encoding="utf-8") as f:
                for w in json.load(f).get("weeks", []):
                    for e in w.get("entries", []):
                        cached[e["id"]] = e["date"]
        except (OSError, ValueError, KeyError, TypeError):
            cached = {}
    subjects = git_subjects(repo)
    refs = feature_refs(guide_path, serverinfo_path, media_path)
    entries = note_entries(notes_dir) + curated_entries(source, roadmap_status(roadmap_path), subjects, cached, is_shallow(repo), refs)
    # a patch note and a curated entry of the same id cannot clash (prefix), the order is date, then the file order
    entries = [e for _, e in sorted(enumerate(entries), key=lambda p: (p[1]["date"], -p[0]), reverse=True)]
    weeks = []
    for e in entries:
        start = monday(e["date"])
        if not weeks or weeks[-1]["start"] != start:
            weeks.append({"start": start, "entries": []})
        weeks[-1]["entries"].append(e)
    recent = int(source.get("recent_weeks", DEFAULT_RECENT))
    if not 1 <= recent <= 26:
        raise Error("recent_weeks must be 1..26")
    days = int(source.get("featured_days", DEFAULT_FEATURED_DAYS))
    most = int(source.get("featured_max", DEFAULT_FEATURED_MAX))
    if not 1 <= days <= 120 or not 1 <= most <= 6:
        raise Error("featured_days must be 1..120 and featured_max 1..6")
    return {"format": FORMAT, "recent_weeks": recent, "featured_days": days, "featured_max": most,
            "latest": entries[0]["date"] if entries else "", "weeks": weeks}


def encode(data):
    return json.dumps(data, ensure_ascii=False, indent=1) + "\n"


def check(repo=REPO, **kw):
    """Problems (a list of text): the data file differs from the sources, or a date differs from git."""
    out_path = kw.get("out_path", OUT)
    data = build(repo=repo, **kw)
    problems = []
    try:
        with open(out_path, encoding="utf-8") as f:
            have = f.read()
    except OSError:
        return ["%s: missing (run gen_changelog.py)" % out_path]
    if have != encode(data):
        problems.append("%s is not what the sources give (run python3 -I website/tools/gen_changelog.py)" % out_path)
    if not is_shallow(repo):
        # with the whole history every curated date must come from git, not from the data file
        with open(kw.get("source_path", SOURCE), encoding="utf-8") as f:
            source = json.load(f)
        subjects = git_subjects(repo)
        for raw in source.get("entries", []):
            if raw.get("live_when"):
                continue  # a gated entry is dated by its gate, not by a commit
            match = raw.get("match") or raw["ref"] + ":"
            if not any(match in s for _, s in subjects):
                problems.append("%s: no commit subject holds %r" % (raw["id"], match))
    return problems


def main(argv):
    try:
        if argv == ["--check"]:
            problems = check()
            if problems:
                print("gen_changelog: %d problem(s)" % len(problems))
                for p in problems:
                    print("  " + p)
                return 1
            data = build()
            n = sum(len(w["entries"]) for w in data["weeks"])
            print("gen_changelog: %d entries in %d weeks, up to date" % (n, len(data["weeks"])))
            return 0
        if argv == ["--print"]:
            sys.stdout.write(encode(build()))
            return 0
        if not argv:
            data = build()
            os.makedirs(os.path.dirname(OUT), exist_ok=True)
            blob = encode(data)
            old = None
            if os.path.isfile(OUT):
                with open(OUT, encoding="utf-8") as f:
                    old = f.read()
            if old != blob:
                with open(OUT, "w", encoding="utf-8") as f:
                    f.write(blob)
            print("gen_changelog: %d entries in %d weeks%s" % (sum(len(w["entries"]) for w in data["weeks"]), len(data["weeks"]),
                                                                " (written)" if old != blob else " (unchanged)"))
            return 0
    except Error as e:
        print("gen_changelog: " + str(e))
        return 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
