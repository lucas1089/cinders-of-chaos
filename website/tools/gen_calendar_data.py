#!/usr/bin/env python3
"""Generates website/overlay/plugins/chaos/calendar/calendar_data.json, the data of the public calendar page
(page?plugin=chaos&p=calendar; website/README.md "Calendar"), from the game server's own files, so the page cannot
drift from them:

  - server/data/scripts/chaos/launch_config.lua          THE launch value (O463): "open" (no date yet) or "YYYY-MM-DD HH:MM"
  - server/data/scripts/chaos/season_config.lua          the seasons (id, name, tag, lengthDays; start and finish follow the launch)
  - server/data/scripts/chaos/battleground_config.lua    the PvP season cycle (weeks; the epoch follows the launch)
  - server/data/scripts/chaos/chaos_constants.lua        the Infinity Tower cycle (seasonLengthDays; the epoch follows the launch)
  - server/data/patchnotes/*.md                          the patch notes that exist (a note a week)
  - website/tools/calendar_source.json                   the events (betas, wipe, launch), Season 2, the patch weekday, the
                                                         wipe rules, the open questions: the only hand-written file, in
                                                         pt-BR and en. The dated betas have dates; the wipe, the launch and the
                                                         Founder Pack sale are `launchDays` from the launch (O463)

While the launch is "open" the wipe, the launch, the Founder Pack sale, Season 1, PvP season 1, the Tower season, Season 2 and the
first regular patch note have no date: they are listed with `soon: true` (the page says "Coming soon" / "Em breve"), never dropped
and never shown with a made-up date. With a date they follow it: wipe = launch - 2 days, Founder Pack end = launch + 28 days (the
offsets of launch_config.lua), Season 1 = lengthDays, PvP = weeks, Tower = days.
It also checks the source's dates against docs/OWNER_TODO.md and docs/BETA.md (the `verify` rules): when the owner changes a
date there, this tool fails until calendar_source.json follows. It also fails when a config holds its own launch date instead of
reading the one value, when Season 1 or the PvP season 1 does not start with the launch, or when a launch date is set and the
launch is not marked confirmed. Season 2 starts the day after Season 1 ends (planned); the patch note day is Wednesday (weekday 3, ISO).
Run:  python3 -I website/tools/gen_calendar_data.py            write the file
      python3 -I website/tools/gen_calendar_data.py --check    exit 1 when the file differs from the sources (CI)
No clock and no network: the output depends on the files only. Times are server time, UTC-3 (no daylight saving).
"""
import datetime
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
CHAOS = os.path.join(REPO, "server", "data", "scripts", "chaos")
SOURCE = os.path.join(HERE, "calendar_source.json")
OUT = os.path.join(REPO, "website", "overlay", "plugins", "chaos", "calendar", "calendar_data.json")
TZ = datetime.timezone(datetime.timedelta(hours=-3))

sys.path.insert(0, os.path.join(REPO, "server", "deploy"))
import launch_check as LCK  # noqa: E402  the one reader of launch_config.lua


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S-03:00")


def block(text, name):
    """The body of `name = { ... }` (balanced braces), or ''."""
    m = re.search(r"\b" + re.escape(name) + r"\s*=\s*\{", text)
    if not m:
        return ""
    depth, i = 1, m.end()
    while i < len(text) and depth:
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        i += 1
    return text[m.end():i - 1]


def field(text, name):
    m = re.search(r"\b" + re.escape(name) + r"\s*=\s*(\"[^\"]*\"|[0-9]+)", text)
    if not m:
        return None
    v = m.group(1)
    return v.strip('"') if v.startswith('"') else int(v)


def follow_days(text, name):
    """`name = X.ymd(N)` / `X.stamp(N)` / `X.parts(N)` (the one launch value plus N days): N, or None when it is not that form."""
    m = re.search(r"\b" + re.escape(name) + r"\s*=\s*[\w.\"()/-]*?\.(?:ymd|stamp|parts)\(\s*(-?\d+)\s*\)", text)
    return int(m.group(1)) if m else None


def launch_value(problems, text=None):
    """The launch as (datetime | None, config). text: a launch_config.lua text (tests); default the repository's file."""
    if text is None:
        text = read(os.path.join(CHAOS, "launch_config.lua"))
    c = LCK.read_launch_config(text)
    if c is None or c["raw"] is None:
        problems.append("launch_config.lua: no launch value (launch = \"open\" or \"YYYY-MM-DD HH:MM\")")
        return None, {"offsets": dict(LCK.OFFSETS)}
    if not c["open"] and c["launch"] is None:
        problems.append("launch_config.lua: launch = \"%s\" is neither \"open\" nor a date" % c["raw"])
        return None, c
    if c["launch"] is not None and c["launch"].minute != 0:
        problems.append("launch_config.lua: the launch must be on the hour (Season 1, PvP and the Tower start at an hour)")
    launch = c["launch"].replace(tzinfo=TZ) if c["launch"] is not None else None
    return launch, c


def seasons(problems, launch):
    text = LCK.strip_comments(read(os.path.join(CHAOS, "season_config.lua")))
    body = block(text, "seasons")
    out = []
    # each entry starts at "id ="; its modifier block is inside, so split on the id fields
    parts = re.split(r"(?=\bid\s*=\s*\d+\s*,)", body)[1:]
    for part in parts:
        sid, name, tag = field(part, "id"), field(part, "name"), field(part, "tag")
        if None in (sid, name, tag):
            problems.append("season_config.lua: a season entry lacks id, name or tag")
            continue
        length = field(part, "lengthDays")
        start_d, finish_d = follow_days(part, "start"), follow_days(part, "finish")
        if start_d is not None or finish_d is not None:
            # follows the one launch value: start = launch, finish = launch + lengthDays (hour of the launch)
            if length is None or finish_d != length:
                problems.append("season_config.lua: Season %d must read finish = start + lengthDays (finish = LC.ymd(lengthDays))" % sid)
                continue
            if launch is None:
                out.append({"id": sid, "name": name, "tag": tag, "start": None, "finish": None, "lengthDays": length,
                            "lengthWeeks": length // 7, "soon": True})
            else:
                a = launch + datetime.timedelta(days=start_d or 0)
                b = launch + datetime.timedelta(days=finish_d)
                out.append({"id": sid, "name": name, "tag": tag, "start": iso(a), "finish": iso(b),
                            "lengthDays": (b - a).days, "lengthWeeks": (b - a).days // 7, "soon": False})
            continue
        start, finish, hour = field(part, "start"), field(part, "finish"), field(part, "hour") or 0
        if None in (start, finish):
            problems.append("season_config.lua: season %d lacks start or finish" % sid)
            continue
        if launch is None:
            problems.append("season_config.lua: Season %d has its own date while the launch is open: read the one launch value" % sid)

        def when(v):
            s = str(v)
            return datetime.datetime(int(s[0:4]), int(s[4:6]), int(s[6:8]), hour, 0, tzinfo=TZ)

        a, b = when(start), when(finish)
        out.append({"id": sid, "name": name, "tag": tag, "start": iso(a), "finish": iso(b),
                    "lengthDays": (b - a).days, "lengthWeeks": (b - a).days // 7, "soon": False})
    return out


def cycle_windows(epoch, days, count=3):
    a = datetime.datetime(epoch[0], epoch[1], epoch[2], epoch[3], 0, tzinfo=TZ)
    out = []
    for n in range(1, count + 1):
        b = a + datetime.timedelta(days=days)
        out.append({"n": n, "start": iso(a), "end": iso(b)})
        a = b
    return out


def epoch_of(text):
    m = re.search(r"epoch\s*=\s*\{year\s*=\s*(\d+),\s*month\s*=\s*(\d+),\s*day\s*=\s*(\d+),\s*hour\s*=\s*(\d+)\}", text)
    return tuple(int(x) for x in m.groups()) if m else None


def launch_epoch(launch):
    return (launch.year, launch.month, launch.day, launch.hour) if launch is not None else None


def cycle_epoch(text, name, launch, problems, what):
    """(epoch tuple | None while open, follows: bool) of an `epoch = ...` / `seasonEpoch = ...` assignment of a config."""
    d = follow_days(text, name)
    if d is not None:
        if d != 0:
            problems.append("%s: the epoch must be the launch itself (parts(0)), not launch + %d days" % (what, d))
        return launch_epoch(launch), True
    m = re.search(r"\b" + name + r"\s*=\s*\{year\s*=\s*(\d+),\s*month\s*=\s*(\d+),\s*day\s*=\s*(\d+),\s*hour\s*=\s*(\d+)\}", text)
    if not m:
        return None, False
    if launch is None:
        problems.append("%s: has its own epoch while the launch is open: read the one launch value" % what)
    return tuple(int(x) for x in m.groups()), False


def fill_tokens(text, launch, offsets):
    """{founderEnd} in a source text: the Founder Pack end date in that language; texts that use it have a textOpen twin."""
    def date_of(lang):
        d = launch + datetime.timedelta(days=offsets["founderEnd"])
        return d.strftime("%d/%m/%Y às %H:%M") if lang == "pt-BR" else d.strftime("%d %b %Y at %H:%M")
    if isinstance(text, dict):
        return {lang: v.replace("{founderEnd}", date_of(lang)) if "{founderEnd}" in v else v for lang, v in text.items()}
    return text


def build(launch_text=None):
    """(data, problems). launch_text: a launch_config.lua text instead of the repository's (tests)."""
    problems = []
    src = json.loads(read(SOURCE))
    for rule in src["verify"]:
        path = os.path.join(REPO, rule["file"])
        if not os.path.isfile(path) or rule["has"] not in read(path):
            problems.append("%s no longer says: %s (update calendar_source.json)" % (rule["file"], rule["has"]))
    launch, lcfg = launch_value(problems, launch_text)
    offsets = lcfg.get("offsets") or dict(LCK.OFFSETS)
    is_open = launch is None

    notes = sorted(f[:-3] for f in os.listdir(os.path.join(REPO, "server", "data", "patchnotes"))
                   if f.endswith(".md") and not f.endswith(".pt-br.md") and f != "README.md" and not f.startswith("_"))
    dated, soon = [], []
    for e in src["events"]:
        e = dict(e)
        rel = e.pop("launchDays", None)
        end_rel = e.pop("endLaunchDays", None)
        e["patchnoteReady"] = False
        if rel is None:
            # a dated event (the betas): fixed date in the source
            start = datetime.datetime.strptime(e["date"] + " " + (e["time"] or "00:00"), "%Y-%m-%d %H:%M").replace(tzinfo=TZ)
            e["start"] = iso(start)
            e["hasTime"] = bool(e["time"])
            if e["endDate"]:
                e["end"] = iso(datetime.datetime.strptime(e["endDate"] + " " + e["endTime"], "%Y-%m-%d %H:%M").replace(tzinfo=TZ))
            e["patchnoteReady"] = bool(e["patchnote"]) and e["patchnote"] in notes
            for k in ("date", "time", "endDate", "endTime", "textOpen", "titleOpen"):
                e.pop(k, None)
            dated.append(e)
            continue
        # an event worked out from the launch (the wipe, the launch, the Founder Pack sale)
        with_time = e.get("time") == "launch"
        text_open, title_open = e.pop("textOpen", None), e.pop("titleOpen", None)
        if is_open:
            e.update({"start": None, "soon": True, "hasTime": False, "status": "open", "patchnote": "", "patchnoteReady": False,
                      "text": text_open or e.get("text")})
            if title_open:
                e["title"] = title_open
            for k in ("date", "time", "endDate", "endTime"):
                e.pop(k, None)
            soon.append(e)
            continue
        start = launch + datetime.timedelta(days=rel)
        if not with_time:
            start = start.replace(hour=0, minute=0)
        e["start"] = iso(start)
        e["hasTime"] = with_time
        e["soon"] = False
        if end_rel is not None:
            e["end"] = iso(launch + datetime.timedelta(days=end_rel if end_rel != "founderEnd" else offsets["founderEnd"]))
        e["text"] = fill_tokens(e.get("text"), launch, offsets)
        if e["patchnote"] == "launch":
            e["patchnote"] = launch.strftime("%Y-%m-%d")
        e["patchnoteReady"] = bool(e["patchnote"]) and e["patchnote"] in notes
        for k in ("date", "time", "endDate", "endTime"):
            e.pop(k, None)
        dated.append(e)
    dated.sort(key=lambda x: x["start"])
    events = dated + soon

    seas = seasons(problems, launch)
    for s in seas:
        s["firstSeason"] = s["id"] == 1
        s["startsAtLaunch"] = bool(s["soon"]) or (launch is not None and s["start"] == iso(launch))
        if launch is not None and not s["soon"]:
            # the proposal of a season that the config does not start with the launch: the launch plus the length
            s["proposed"] = {"start": iso(launch), "finish": iso(launch + datetime.timedelta(days=s["lengthDays"]))}
    if not seas:
        problems.append("season_config.lua has no season")
    elif not (seas[0]["firstSeason"] and seas[0]["startsAtLaunch"]):
        problems.append("owner decision 2026-10-29: Season 1 starts with the launch (%s); season_config.lua says %s"
                        % (iso(launch) if launch else "open", seas[0]["start"]))
    launch_event = next((e for e in events if e["kind"] == "launch"), None)
    if launch_event is None:
        problems.append("calendar_source.json has no launch event")
    elif not is_open and launch_event.get("status") != "confirmed":
        problems.append("calendar_source.json: the launch date is set, so the launch is confirmed by the owner: its status must be confirmed")

    # Season 2: the day after Season 1 ends, at the time of the source (planned, owner decision 2026-10-29); no date while open
    nxt = None
    if seas:
        ns = src["nextSeason"]
        if seas[0]["soon"]:
            nxt = {"id": ns["id"], "status": "open", "title": ns["title"], "text": ns.get("textOpen", ns["text"]), "start": None, "soon": True}
        else:
            day = datetime.datetime.strptime(seas[0]["finish"], "%Y-%m-%dT%H:%M:%S-03:00").replace(tzinfo=TZ) + datetime.timedelta(days=1)
            hh, mm = (int(x) for x in ns["time"].split(":"))
            nxt = {"id": ns["id"], "status": ns["status"], "title": ns["title"], "text": ns["text"],
                   "start": iso(day.replace(hour=hh, minute=mm)), "soon": False}

    bg = LCK.strip_comments(read(os.path.join(CHAOS, "battleground_config.lua")))
    pvp = block(bg, "season")
    constants = LCK.strip_comments(read(os.path.join(CHAOS, "chaos_constants.lua")))
    pvp_weeks = field(pvp, "weeks")
    tower_days = field(constants, "seasonLengthDays")
    pvp_epoch, pvp_follows = cycle_epoch(pvp, "epoch", launch, problems, "battleground_config.lua")
    tower_epoch, tower_follows = cycle_epoch(constants, "seasonEpoch", launch, problems, "chaos_constants.lua")
    if not (pvp_weeks and tower_days) or (pvp_epoch is None and not (pvp_follows and is_open)) or \
            (tower_epoch is None and not (tower_follows and is_open)):
        problems.append("the PvP or Tower season cycle was not found in battleground_config.lua or chaos_constants.lua")
        return None, problems
    cycles = [
        {"id": "pvp", "lengthDays": pvp_weeks * 7, "soon": pvp_epoch is None,
         "windows": cycle_windows(pvp_epoch, pvp_weeks * 7) if pvp_epoch else []},
        {"id": "tower", "lengthDays": tower_days, "soon": tower_epoch is None,
         "windows": cycle_windows(tower_epoch, tower_days) if tower_epoch else []},
    ]
    if launch is not None and pvp_epoch is not None and \
            launch != datetime.datetime(*pvp_epoch, tzinfo=TZ).replace(minute=launch.minute):
        problems.append("owner decision 2026-10-29: PvP season 1 starts with the launch; battleground_config.lua epoch is %s" % (pvp_epoch,))
    for c in cycles:
        c.update(src["cycleTexts"][c["id"]])
    cycles.append(dict({"id": "weekly", "lengthDays": 7, "windows": [], "soon": False}, **src["cycleTexts"]["weekly"]))

    # the first regular patch note: the first patch weekday after the launch day (Monday = 0, as datetime); none while open
    pc = src["patchCadence"]
    first_note = None
    if launch is not None:
        first_note = launch + datetime.timedelta(days=1)
        while first_note.weekday() != pc["weekday"] - 1:
            first_note += datetime.timedelta(days=1)

    open_questions = [q for q in src["open"] if not q.get("whenOpen") or is_open]
    for q in open_questions:
        q.pop("whenOpen", None)

    data = {
        "generatedBy": "website/tools/gen_calendar_data.py (do not edit by hand)",
        "sources": ["server/data/scripts/chaos/launch_config.lua", "server/data/scripts/chaos/season_config.lua",
                    "server/data/scripts/chaos/battleground_config.lua", "server/data/scripts/chaos/chaos_constants.lua",
                    "server/data/patchnotes/*.md", "website/tools/calendar_source.json"],
        "timezone": src["timezone"],
        "timezoneName": src["timezoneName"],
        "launch": {"open": is_open, "at": iso(launch) if launch else None},
        "events": events,
        "seasons": seas,
        "cycles": cycles,
        "nextSeason": nxt,
        "patchnotes": {"cadence": "weekly", "weekday": pc["weekday"], "weekdayName": pc["weekdayName"],
                       "firstRegular": first_note.strftime("%Y-%m-%d") if first_note else None, "count": len(notes),
                       "latest": notes[-1] if notes else "", "title": pc["title"], "text": pc["text"]},
        "wipe": src["wipe"],
        "open": open_questions,
    }
    return data, problems


def render(data):
    return json.dumps(data, ensure_ascii=False, indent=1) + "\n"


def main(argv):
    data, problems = build()
    for p in problems:
        print("calendar: " + p, file=sys.stderr)
    if data is None or problems:
        return 1
    text = render(data)
    if "--check" in argv:
        have = read(OUT) if os.path.isfile(OUT) else ""
        if have != text:
            print("calendar: %s is out of date; run python3 -I website/tools/gen_calendar_data.py" % os.path.relpath(OUT, REPO),
                  file=sys.stderr)
            return 1
        print("calendar: up to date")
        return 0
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("calendar: wrote %s" % os.path.relpath(OUT, REPO))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
