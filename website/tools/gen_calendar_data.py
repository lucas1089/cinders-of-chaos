#!/usr/bin/env python3
"""Generates website/overlay/plugins/chaos/calendar/calendar_data.json, the data of the public calendar page
(page?plugin=chaos&p=calendar; website/README.md "Calendar"), from the game server's own files, so the page cannot
drift from them:

  - server/data/scripts/chaos/season_config.lua          the seasons (id, name, tag, start, finish, hour)
  - server/data/scripts/chaos/battleground_config.lua    the PvP season cycle (weeks, epoch)
  - server/data/scripts/chaos/chaos_constants.lua        the Infinity Tower cycle (seasonEpoch, seasonLengthDays)
  - server/data/patchnotes/*.md                          the patch notes that exist (a note a week)
  - website/tools/calendar_source.json                   the events (betas, wipe, launch), Season 2, the patch weekday, the
                                                         wipe rules, the open questions: the only hand-written file, in
                                                         pt-BR and en

It also checks the source's dates against docs/OWNER_TODO.md and docs/BETA.md (the `verify` rules): when the owner
changes a date there, this tool fails until calendar_source.json follows. It also fails when Season 1 or the PvP
season 1 does not start with the launch, or when the launch is not marked confirmed (owner decision 2026-10-29).
Season 2 starts the day after Season 1 ends (planned); the patch note day is Wednesday (weekday 3, ISO).
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


def seasons(problems):
    text = read(os.path.join(CHAOS, "season_config.lua"))
    body = block(text, "seasons")
    out = []
    # each entry starts at "id ="; its modifier block is inside, so split on the id fields
    parts = re.split(r"(?=\bid\s*=\s*\d+\s*,)", body)[1:]
    for part in parts:
        sid, name, tag = field(part, "id"), field(part, "name"), field(part, "tag")
        start, finish, hour = field(part, "start"), field(part, "finish"), field(part, "hour") or 0
        if None in (sid, name, tag, start, finish):
            problems.append("season_config.lua: a season entry lacks id, name, tag, start or finish")
            continue

        def when(v):
            s = str(v)
            return datetime.datetime(int(s[0:4]), int(s[4:6]), int(s[6:8]), hour, 0, tzinfo=TZ)

        a, b = when(start), when(finish)
        out.append({"id": sid, "name": name, "tag": tag, "start": iso(a), "finish": iso(b),
                    "lengthDays": (b - a).days, "lengthWeeks": (b - a).days // 7})
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


def build():
    problems = []
    src = json.loads(read(SOURCE))
    for rule in src["verify"]:
        path = os.path.join(REPO, rule["file"])
        if not os.path.isfile(path) or rule["has"] not in read(path):
            problems.append("%s no longer says: %s (update calendar_source.json)" % (rule["file"], rule["has"]))

    notes = sorted(f[:-3] for f in os.listdir(os.path.join(REPO, "server", "data", "patchnotes"))
                   if f.endswith(".md") and not f.endswith(".pt-br.md") and f != "README.md" and not f.startswith("_"))
    events = []
    for e in src["events"]:
        e = dict(e)
        start = datetime.datetime.strptime(e["date"] + " " + (e["time"] or "00:00"), "%Y-%m-%d %H:%M").replace(tzinfo=TZ)
        e["start"] = iso(start)
        e["hasTime"] = bool(e["time"])
        if e["endDate"]:
            e["end"] = iso(datetime.datetime.strptime(e["endDate"] + " " + e["endTime"], "%Y-%m-%d %H:%M").replace(tzinfo=TZ))
        e["patchnoteReady"] = bool(e["patchnote"]) and e["patchnote"] in notes
        for k in ("date", "time", "endDate", "endTime"):
            del e[k]
        events.append(e)
    events.sort(key=lambda x: x["start"])

    launch = next(e for e in events if e["kind"] == "launch")
    launch_dt = datetime.datetime.strptime(launch["start"], "%Y-%m-%dT%H:%M:%S-03:00").replace(tzinfo=TZ)
    seas = seasons(problems)
    for s in seas:
        s["startsAtLaunch"] = s["start"] == launch["start"]
        # the season is the one that the launch opens (the first one); its dates are "a definir" until the
        # config starts it with the launch. The proposal is the launch plus the length the config gives.
        s["proposed"] = {"start": launch["start"], "finish": iso(launch_dt + datetime.timedelta(days=s["lengthDays"]))}
        s["firstSeason"] = s["id"] == 1
    if not seas:
        problems.append("season_config.lua has no season")
    elif not (seas[0]["firstSeason"] and seas[0]["startsAtLaunch"]):
        problems.append("owner decision 2026-10-29: Season 1 starts with the launch (%s); season_config.lua says %s"
                        % (launch["start"], seas[0]["start"]))
    if launch.get("status") != "confirmed":
        problems.append("calendar_source.json: the launch is confirmed by the owner (2026-10-29), its status must be confirmed")

    # Season 2: the day after Season 1 ends, at the time of the source (planned, owner decision 2026-10-29)
    nxt = None
    if seas:
        ns = src["nextSeason"]
        day = datetime.datetime.strptime(seas[0]["finish"], "%Y-%m-%dT%H:%M:%S-03:00").replace(tzinfo=TZ) + datetime.timedelta(days=1)
        hh, mm = (int(x) for x in ns["time"].split(":"))
        nxt = {"id": ns["id"], "status": ns["status"], "title": ns["title"], "text": ns["text"],
               "start": iso(day.replace(hour=hh, minute=mm))}

    bg = read(os.path.join(CHAOS, "battleground_config.lua"))
    pvp = block(bg, "season")
    constants = read(os.path.join(CHAOS, "chaos_constants.lua"))
    pvp_epoch, pvp_weeks = epoch_of(pvp), field(pvp, "weeks")
    tower_epoch = re.search(r"seasonEpoch\s*=\s*\{year\s*=\s*(\d+),\s*month\s*=\s*(\d+),\s*day\s*=\s*(\d+),\s*hour\s*=\s*(\d+)\}", constants)
    tower_days = field(constants, "seasonLengthDays")
    if not (pvp_epoch and pvp_weeks and tower_epoch and tower_days):
        problems.append("the PvP or Tower season cycle was not found in battleground_config.lua or chaos_constants.lua")
        return None, problems
    cycles = [
        {"id": "pvp", "lengthDays": pvp_weeks * 7, "windows": cycle_windows(pvp_epoch, pvp_weeks * 7)},
        {"id": "tower", "lengthDays": tower_days,
         "windows": cycle_windows(tuple(int(x) for x in tower_epoch.groups()), tower_days)},
    ]
    if launch_dt != datetime.datetime(*pvp_epoch, tzinfo=TZ).replace(minute=0):
        problems.append("owner decision 2026-10-29: PvP season 1 starts with the launch; battleground_config.lua epoch is %s" % (pvp_epoch,))
    for c in cycles:
        c.update(src["cycleTexts"][c["id"]])
    cycles.append(dict({"id": "weekly", "lengthDays": 7, "windows": []}, **src["cycleTexts"]["weekly"]))

    # the first regular patch note: the first patch weekday after the launch day (Monday = 0, as datetime)
    pc = src["patchCadence"]
    first_note = launch_dt + datetime.timedelta(days=1)
    while first_note.weekday() != pc["weekday"] - 1:
        first_note += datetime.timedelta(days=1)

    data = {
        "generatedBy": "website/tools/gen_calendar_data.py (do not edit by hand)",
        "sources": ["server/data/scripts/chaos/season_config.lua", "server/data/scripts/chaos/battleground_config.lua",
                    "server/data/scripts/chaos/chaos_constants.lua", "server/data/patchnotes/*.md",
                    "website/tools/calendar_source.json"],
        "timezone": src["timezone"],
        "timezoneName": src["timezoneName"],
        "events": events,
        "seasons": seas,
        "cycles": cycles,
        "nextSeason": nxt,
        "patchnotes": {"cadence": "weekly", "weekday": pc["weekday"], "weekdayName": pc["weekdayName"],
                       "firstRegular": first_note.strftime("%Y-%m-%d"), "count": len(notes), "latest": notes[-1] if notes else "",
                       "title": pc["title"], "text": pc["text"]},
        "wipe": src["wipe"],
        "open": src["open"],
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
