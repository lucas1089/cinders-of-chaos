#!/usr/bin/env python3
"""Spawn density and respawn tuning of the loaded map's spawn file, driven by tools/spawn_tuning.json (idempotent).

usage: python3 -I patch_base_spawns.py DATA_DIR [--config PATH] [--spawn PATH] [--tuning PATH] [--dry-run] [--remove]
                                       [--report]

DATA_DIR is the base server's data folder. The spawn file is DATA_DIR/world/<mapName>-spawn.xml (mapName read from
config.lua, default DATA_DIR/../config.lua) or --spawn PATH. The monster definitions (DATA_DIR/monster/monsters.xml and
the Lua monsters) give each monster its hunting level, as tools/gen_bounty_pool.py estimates it.

What spawn_tuning.json asks for, in this order (server/README.md "Spawn density and respawn"):
  fixDeadRegistrations  DATA_DIR/monster/monsters.xml: the engine keeps the first line of a monster name. When that
                   line's file does not exist (a wrong-case path: the base server was made on Windows) and another line
                   of the same name points to a file that does, the dead line is commented out. Before, those monsters
                   never loaded on Linux and every spawn entry of them stayed empty
  glitchSpawntime  an entry whose spawntime is at least `min` seconds (the map editor wrote ~31000-32800 s for a few
                   hundred ordinary monsters) gets the median spawntime of the same monster elsewhere on the map, when
                   that monster has at least `minOthers` other entries
  bandRespawn      per level band: entries of a monster whose hunting level is in [from, to) and whose spawntime is
                   above `spawntime` and at most `onlyUpTo` get `spawntime` (rare spawns with long timers stay)
  move             {"at": [x, y, z], "to": [x, y]}: the entry at that absolute position moves to another tile of the same
                   floor (entries on a blocking tile, found against the map when the list was made)
  remove           {"at": [x, y, z]}: the entry at that position is taken out (kept as an XML comment)
  dungeons         {"id", "boxes": [[x1, y1, z1, x2, y2, z2], ...], "keep": n}: a base dungeon keeps at most n of its
                   hunting monsters (pack combat: runs of 10-15 minutes, server/README.md "Pack combat (pace)"); the
                   others are taken out like `remove`, spread evenly (by floor, y, x); no fill spawn lands inside
  add              {"area": id, "at": [x, y, z], "like": [x, y, z]}: a new one-monster spawn at `at` with the monster
                   and the final spawntime of the existing entry at `like`; `at` must lie in the area's box. The
                   positions were checked against the map (walkable, no protection zone, no house, no floor change)
  fill             the name of a JSON file next to this one (tools/spawn_density.json, written by
                   tools/gen_spawn_density.py from the map): per hunt {"id", "z", "likes": [[x, y], ...], "add":
                   [[x, y, index in likes, dx, dy, ...], ...]}; each add is a new spawn block on floor z (marked
                   chaosadd="<id>") with the monster and final spawntime of the like entry at its centre and at each
                   further dx, dy (the pack fill's blocks of 3), so every base-map hunt reaches the density of
                   server/README.md "Fill" and "Pack combat (pace)"
Monster names are never written in the JSON: an entry is named by its position, a new one copies an existing one.

Every change carries a marker, so a run first undoes the previous run and then applies the JSON again: a second run
changes nothing, an edited JSON is synced, --remove restores the stock entries. Markers: chaosst="<old spawntime>" and
chaosxy="<old x>,<old y>" on a changed <monster>, <!-- chaosremoved: ... --> for a removed one, chaosadd="<area>" on an
added <spawn>. A stock <spawn> whose every entry was removed becomes <!-- chaosemptied: <spawn ...>...</spawn> --> (the
stock block as it was): the engine warns "Empty spawn" for a <spawn> with no entry left (2026-10-16 start log, 339 lines).
tools/late_game.py marks its own entries with lategame=""; both tools can run in any order.

--report prints the level band table of the README (spawn entries, respawn, kills per hour the respawn can feed and how
many hunters that holds) from the file as it would be written. Exit status 1 when a listed position is not found.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_bounty_pool as pool  # noqa: E402  (map_name, load_monsters, estimate_level, attr)

DEFAULT_TUNING = os.path.join(HERE, 'spawn_tuning.json')
SPAWN_RE = re.compile(r'(<spawn\s[^>]*>)(.*?)(</spawn>)', re.S)
MON_RE = re.compile(r'<monster\s[^>]*?/>')
ADDED_RE = re.compile(r'[ \t]*<spawn\s[^>]*\bchaosadd="[^"]*"[^>]*>.*?</spawn>[ \t]*\r?\n?', re.S)
REMOVED_RE = re.compile(r'<!-- chaosremoved: (<monster\s[^>]*?/>) -->')
EMPTIED_RE = re.compile(r'<!-- chaosemptied: (<spawn\s[^>]*>.*?</spawn>) -->', re.S)
LIVE_RE = re.compile(r'<(?:monster|npc)\s')
MARKS = ('chaosst', 'chaosxy')
DEADREG_RE = re.compile(r'<!-- chaosdeadreg: (<monster\s[^>]*?/>) -->')
COMMENT_RE = re.compile(r'<!--.*?-->', re.S)


def read(path):
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


def attr(tag, name):
    m = re.search(r'\s%s="([^"]*)"' % name, tag)
    return m.group(1) if m else None


def set_attr(tag, name, value):
    if attr(tag, name) is None:
        return re.sub(r'\s*/>$', ' %s="%s" />' % (name, value), tag)
    return re.sub(r'(\s%s=")[^"]*(")' % name, lambda m: m.group(1) + str(value) + m.group(2), tag, count=1)


def add_mark(tag, name, value):
    """markers go right after "<monster", so taking them out gives the tag back byte for byte"""
    if attr(tag, name) is not None:
        return tag
    return tag.replace('<monster', '<monster %s="%s"' % (name, value), 1)


def num(v, default=0):
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


# ------------------------------------------------------------------------------------------------ restore
def restore(text):
    """the spawn file without anything this tool did"""
    text = ADDED_RE.sub('', text)
    text = EMPTIED_RE.sub(lambda m: m.group(1), text)
    text = REMOVED_RE.sub(lambda m: m.group(1), text)

    def mon(m):
        tag = m.group(0)
        st, xy = attr(tag, 'chaosst'), attr(tag, 'chaosxy')
        if st is None and xy is None:
            return tag
        for name in MARKS:
            tag = re.sub(r' %s="[^"]*"' % name, '', tag, count=1)
        if st is not None:
            tag = set_attr(tag, 'spawntime', st)
        if xy is not None:
            x, y = xy.split(',')
            tag = set_attr(set_attr(tag, 'x', x), 'y', y)
        return tag
    return MON_RE.sub(mon, text)


# ------------------------------------------------------------------------------------------------ monsters.xml
def restore_registry(text):
    return DEADREG_RE.sub(lambda m: m.group(1), text)


def fix_registry(text, monster_dir):
    """returns (new text, names of the monsters whose dead first line was commented out); text must be restored"""
    comments = [(m.start(), m.end()) for m in COMMENT_RE.finditer(text)]

    def commented(pos):
        return any(a <= pos < b for a, b in comments)
    lines = {}
    for m in re.finditer(r'<monster\s[^>]*?/>', text):
        if commented(m.start()):
            continue
        name, f = attr(m.group(0), 'name'), attr(m.group(0), 'file')
        if name and f:
            lines.setdefault(name.lower(), []).append((m.start(), m.end(), name, os.path.isfile(os.path.join(monster_dir, f))))
    cut, names = [], []
    for key, found in lines.items():
        if len(found) > 1 and not found[0][3] and any(ok for _, _, _, ok in found[1:]):
            for start, end, name, ok in found:
                if ok:
                    break
                cut.append((start, end))
            names.append(found[0][2])
    for start, end in sorted(cut, reverse=True):
        text = text[:start] + '<!-- chaosdeadreg: %s -->' % text[start:end] + text[end:]
    return text, sorted(names)


# ------------------------------------------------------------------------------------------------ model
def parse(text):
    """[(block index, center (x, y, z), [monster tag, ...])] of the file"""
    out = []
    for i, m in enumerate(SPAWN_RE.finditer(text)):
        head = m.group(1)
        center = (num(attr(head, 'centerx')), num(attr(head, 'centery')), num(attr(head, 'centerz')))
        out.append((i, center, MON_RE.findall(m.group(2))))
    return out


def entry_pos(center, tag):
    # the engine uses the spawn's floor; the monster's own z is ignored
    return (center[0] + num(attr(tag, 'x')), center[1] + num(attr(tag, 'y')), center[2])


def hunt_level(m, factor):
    """the level that hunts this monster: the middle of a level-scaled monster's range, else factor x the bounty
    pool's 'fair hunt' estimate (calibrated so the README's leveling model hunts land in their band)"""
    if m.get('minLevel', 0) > 0 and m.get('maxLevel', 0) >= m['minLevel']:
        return (m['minLevel'] + m['maxLevel']) // 2
    return int(round(pool.estimate_level(m) * factor))


def huntable(m):
    return m is not None and m.get('hostile', True) and m.get('attackable', True) and m.get('exp', 0) > 0 \
        and not m.get('boss')


def median(values):
    v = sorted(values)
    n = len(v)
    if not n:
        return None
    return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) // 2


# ------------------------------------------------------------------------------------------------ apply
def plan_spawntimes(blocks, tuning, monsters):
    """{(block, index in block): new spawntime} and counts"""
    counts = {'glitch': 0, 'band': 0}
    out = {}
    glitch = tuning.get('glitchSpawntime') or {}
    gmin = num(glitch.get('min'), 0)
    others = {}
    for b, center, tags in blocks:
        for tag in tags:
            st = num(attr(tag, 'spawntime'))
            if not gmin or st < gmin:
                others.setdefault((attr(tag, 'name') or '').lower(), []).append(st)
    factor = float(tuning.get('huntLevelFactor', 2.0))
    bands = tuning.get('bandRespawn') or []
    for b, center, tags in blocks:
        for j, tag in enumerate(tags):
            name = (attr(tag, 'name') or '').lower()
            st = num(attr(tag, 'spawntime'))
            new = st
            if gmin and st >= gmin and len(others.get(name, ())) >= num(glitch.get('minOthers'), 10):
                new = median(others[name])
                counts['glitch'] += 1
            m = monsters.get(name)
            if bands and huntable(m):
                lvl = hunt_level(m, factor)
                for band in bands:
                    if num(band['from']) <= lvl < num(band['to']) and band['spawntime'] < new <= band['onlyUpTo']:
                        new = band['spawntime']
                        counts['band'] += 1
                        break
            if new != st:
                out[(b, j)] = new
    return out, counts


def apply(text, tuning, monsters):
    """returns (new text, counts, problems); text must be a restored file"""
    blocks = parse(text)
    times, counts = plan_spawntimes(blocks, tuning, monsters)
    counts.update({'moved': 0, 'removed': 0, 'emptied': 0, 'added': 0, 'filled': 0})
    problems = []
    by_pos = {}
    for b, center, tags in blocks:
        for j, tag in enumerate(tags):
            by_pos.setdefault(entry_pos(center, tag), []).append((b, j))
    moves, removes = {}, set()
    for mv in tuning.get('move') or []:
        at = tuple(mv['at'])
        hits = by_pos.get(at, [])
        if len(hits) != 1:
            problems.append('move %s: %d entries there (needs exactly one)' % (list(at), len(hits)))
            continue
        moves[hits[0]] = tuple(mv['to'])
    for rm in tuning.get('remove') or []:
        at = tuple(rm['at'])
        hits = by_pos.get(at, [])
        if not hits:
            problems.append('remove %s: no entry there' % list(at))
        removes.update(hits)
    dungeon_boxes, dungeon_out = [], set()
    for dg in tuning.get('dungeons') or []:
        boxes = [tuple(b) for b in dg['boxes']]
        dungeon_boxes += boxes
        thin = plan_dungeon(blocks, boxes, int(dg['keep']), monsters, removes)
        removes.update(thin)
        dungeon_out.update(thin)
        counts['dungeon'] = counts.get('dungeon', 0) + len(thin)
    final = {}  # (b, j) -> final spawntime, for the adds
    counter = [0]

    def block_sub(m):
        b = counter[0]
        counter[0] += 1
        center = blocks[b][1]
        j_box = [0]

        def mon(mm):
            j = j_box[0]
            j_box[0] += 1
            tag = mm.group(0)
            key = (b, j)
            final[key] = num(attr(tag, 'spawntime'))
            if key in removes:
                if key not in dungeon_out:
                    counts['removed'] += 1
                return '<!-- chaosremoved: %s -->' % tag
            new = tag
            if key in times:
                new = add_mark(new, 'chaosst', attr(tag, 'spawntime'))
                new = set_attr(new, 'spawntime', times[key])
                final[key] = times[key]
            if key in moves:
                to = moves[key]
                new = add_mark(new, 'chaosxy', '%s,%s' % (attr(tag, 'x') or '0', attr(tag, 'y') or '0'))
                new = set_attr(set_attr(new, 'x', to[0] - center[0]), 'y', to[1] - center[1])
                counts['moved'] += 1
            return new
        body = MON_RE.sub(mon, m.group(2))
        if body != m.group(2) and not LIVE_RE.search(COMMENT_RE.sub('', body)) and '--' not in m.group(0):
            # every entry removed: the whole stock block goes into one comment (the engine warns on an empty <spawn>)
            counts['emptied'] += 1
            return '<!-- chaosemptied: %s -->' % m.group(0)
        return m.group(1) + body + m.group(3)
    out = SPAWN_RE.sub(block_sub, text)

    areas = {a['id']: a for a in tuning.get('areas') or []}
    eol = '\r\n' if '\r\n' in text else '\n'
    added = []
    for ad in tuning.get('add') or []:
        at, like = tuple(ad['at']), tuple(ad['like'])
        area = areas.get(ad.get('area'))
        if area is None:
            problems.append('add %s: unknown area %r' % (list(at), ad.get('area')))
            continue
        x0, y0, z0, x1, y1, z1 = area['box']
        if not (x0 <= at[0] <= x1 and y0 <= at[1] <= y1 and z0 <= at[2] <= z1):
            problems.append('add %s: outside the box of area %s' % (list(at), area['id']))
            continue
        hits = by_pos.get(like, [])
        hits = [h for h in hits if h not in removes or h in dungeon_out]
        if not hits:
            problems.append('add %s: no entry at like %s' % (list(at), list(like)))
            continue
        b, j = hits[0]
        name = attr(blocks[b][2][j], 'name')
        st = ad.get('spawntime', final.get((b, j), 60))
        added.append('\t<spawn centerx="%d" centery="%d" centerz="%d" radius="%d" chaosadd="%s">%s'
                     '\t\t<monster name="%s" x="0" y="0" z="%d" spawntime="%d" />%s\t</spawn>%s'
                     % (at[0], at[1], at[2], num(ad.get('radius'), 2), area['id'], eol, name, at[2], st, eol, eol))
        counts['added'] += 1
    for area in tuning.get('_fill') or []:
        z = area['z']
        likes = []
        for lx, ly in area['likes']:
            hits = [h for h in by_pos.get((lx, ly, z), []) if h not in removes or h in dungeon_out]
            if not hits:
                problems.append('fill %s: no entry at like %s' % (area['id'], [lx, ly, z]))
            likes.append(hits[0] if hits else None)
        for row in area['add']:
            x, y, li = row[0], row[1], row[2]
            if in_boxes(dungeon_boxes, x, y, z):
                continue  # a base dungeon keeps its own count (tuning "dungeons")
            offs = [(0, 0)] + [(row[k], row[k + 1]) for k in range(3, len(row) - 1, 2)]
            hit = likes[li] if 0 <= li < len(likes) else None
            if hit is None:
                continue
            b, j = hit
            name = attr(blocks[b][2][j], 'name')
            st = final.get((b, j), 60)
            mons = ''.join('\t\t<monster name="%s" x="%d" y="%d" z="%d" spawntime="%d" />%s' % (name, dx, dy, z, st, eol)
                           for dx, dy in offs)
            added.append('\t<spawn centerx="%d" centery="%d" centerz="%d" radius="2" chaosadd="%s">%s%s\t</spawn>%s'
                         % (x, y, z, area['id'], eol, mons, eol))
            counts['filled'] += len(offs)
    if added:
        k = out.rfind('</spawns>')
        if k < 0:
            problems.append('no </spawns> in the file')
        else:
            out = out[:k] + ''.join(added) + out[k:]
    return out, counts, problems


def in_boxes(boxes, x, y, z):
    return any(b[0] <= x <= b[3] and b[1] <= y <= b[4] and b[2] <= z <= b[5] for b in boxes)


def plan_dungeon(blocks, boxes, keep, monsters, removes):
    """{(block, index)} of the entries to take out of a base dungeon: its hunting monsters (huntable, not a boss) inside
    the boxes, beyond `keep`, spread evenly over the dungeon (sorted by floor, y, x), so the run model fits 15 minutes
    (server/README.md "Pack combat (pace)", base dungeons). Bosses, NPCs and non-hunting monsters stay."""
    found = []
    for b, center, tags in blocks:
        for j, tag in enumerate(tags):
            if (b, j) in removes:
                continue
            x, y, z = entry_pos(center, tag)
            if in_boxes(boxes, x, y, z) and huntable(monsters.get((attr(tag, 'name') or '').lower())):
                found.append(((z, y, x, b, j), (b, j)))
    found.sort()
    n = len(found)
    if n <= keep:
        return set()
    out = set()
    for i, (_k, key) in enumerate(found):
        if (i + 1) * keep // n == i * keep // n:
            out.add(key)
    return out


# ------------------------------------------------------------------------------------------------ report
def report(text, tuning, monsters, rate_spawn):
    """per band: entries, blocks, average spawntime, the respawn's kills per hour and the hunters it holds"""
    model = tuning.get('model') or {}
    factor = float(tuning.get('huntLevelFactor', 2.0))
    bands = model.get('bands') or [[1, 50], [50, 150], [150, 300], [300, 600], [600, 1000], [1000, 100000]]
    (l1, d1), (l2, d2) = model.get('dpsPoints') or [[300, 1804.0], [1000, 4337.0]]
    eff = float(model.get('efficiency', 0.47))
    kcap = float(model.get('maxKillsPerHour', 900))
    view = float(model.get('viewBlockFactor', 1.25))
    tier_hp = float(model.get('tierHealth', 1.11))
    hp_bonus = float(model.get('levelHealthBonus', 0.0074))

    # pack combat (pace, README "Pack combat (pace)"): one hunter's kills per hour by hunting level, the pack-cycle
    # model of the median class (base monsters / level-scaled sets), in place of the 0.47-efficiency formula
    pace = model.get('paceKillsPerHour')

    def lin(points, x):
        if x <= points[0][0]:
            return points[0][1]
        for (xa, ya), (xb, yb) in zip(points, points[1:]):
            if x <= xb:
                return ya + (yb - ya) * (x - xa) / float(xb - xa)
        return points[-1][1]

    def dps(level):
        if level < 100:
            return max(60.0, (d1 + (d2 - d1) * (100 - l1) / (l2 - l1)) * level / 100.0)
        return d1 + (d2 - d1) * (level - l1) / (l2 - l1)
    rows = [dict(entries=0, blocks=0, st=0.0, supply=0.0, hunters=0.0) for _ in bands]
    for b, center, tags in parse(text):
        per_band = {}
        all_st = [max(10, num(attr(t, 'spawntime'))) for t in tags]
        if not all_st:
            continue
        for tag in tags:
            m = monsters.get((attr(tag, 'name') or '').lower())
            if not huntable(m):
                continue
            lvl = hunt_level(m, factor)
            k = next((i for i, (lo, hi) in enumerate(bands) if lo <= lvl < hi), len(bands) - 1)
            per_band.setdefault(k, []).append((m, lvl, max(10, num(attr(tag, 'spawntime')))))
        for k, items in per_band.items():
            r = rows[k]
            r['entries'] += len(items)
            r['blocks'] += 1
            # the engine respawns at most rateSpawn monsters of a spawn per check (every shortest interval of it)
            rate = min(sum(1.0 / st for _, _, st in items), rate_spawn / min(all_st) * len(items) / len(tags))
            supply = rate * 3600.0 / view
            r['supply'] += supply
            for m, lvl, st in items:
                r['st'] += st
                scaled = m.get('maxLevel', 0) > 0
                hp = m.get('health', 1) * (1 + hp_bonus * (m['minLevel'] + m['maxLevel']) / 2 if scaled else 1) * tier_hp
                aoe = 0.75 if scaled and lvl >= 600 else 1.0
                kills = min(kcap, 3600.0 * eff * dps(lvl) * aoe / max(1.0, hp))
                if pace:
                    kills = lin(pace['scaled' if scaled else 'base'], lvl)
                r['hunters'] += supply / len(items) / kills
    lines = ['| Band | Spawn blocks | Monsters | Avg respawn s | Respawn kills/h | Hunters it holds |', '|---|---|---|---|---|---|']
    for (lo, hi), r in zip(bands, rows):
        lines.append('| %d-%s | %d | %d | %.0f | %s | %.0f |' % (
            lo, hi if hi < 100000 else '', r['blocks'], r['entries'], r['st'] / max(1, r['entries']),
            '{:,.0f}'.format(r['supply']), r['hunters']))
    return lines


# ------------------------------------------------------------------------------------------------ main
def rate_spawn_of(config_text):
    m = re.search(r'^\s*rateSpawn\s*=\s*(\d+)', config_text or '', re.M)
    return int(m.group(1)) if m else 1


def main(argv):
    opts, args, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--config', '--spawn', '--tuning'):
            if i + 1 >= len(argv):
                sys.exit('%s needs a value' % a)
            opts[a] = argv[i + 1]
            i += 1
        elif a in ('--dry-run', '--remove', '--report'):
            opts[a] = True
        elif a.startswith('-'):
            sys.exit('unknown option %s' % a)
        else:
            args.append(a)
        i += 1
    if len(args) != 1:
        print(__doc__)
        return 1
    data = args[0]
    cfg_path = opts.get('--config', os.path.join(data, '..', 'config.lua'))
    cfg = read(cfg_path) if os.path.isfile(cfg_path) else ''
    spawn_path = opts.get('--spawn')
    if not spawn_path:
        name = pool.map_name(cfg)
        if not name:
            print('%s: mapName not found, pass --spawn' % cfg_path)
            return 1
        spawn_path = os.path.join(data, 'world', name + '-spawn.xml')
    tuning_path = opts.get('--tuning', DEFAULT_TUNING)
    tuning = json.loads(read(tuning_path))
    if tuning.get('fill'):
        tuning['_fill'] = json.loads(read(os.path.join(os.path.dirname(os.path.abspath(tuning_path)), tuning['fill'])))['areas']
    dry = opts.get('--dry-run')
    reg_path = os.path.join(data, 'monster', 'monsters.xml')
    if os.path.isfile(reg_path):
        reg = read(reg_path)
        new_reg = restore_registry(reg)
        names = []
        if tuning.get('fixDeadRegistrations') and not opts.get('--remove'):
            new_reg, names = fix_registry(new_reg, os.path.join(data, 'monster'))
        if new_reg != reg and not dry:
            write(reg_path, new_reg)
        print('monsters.xml: %d dead first line(s) commented out%s (%s)' % (
            len(names), (': ' + ', '.join(names)) if names else '',
            'unchanged' if new_reg == reg else ('would change' if dry else 'written')))
    monsters = pool.load_monsters(data)
    text = read(spawn_path)
    base = restore(text)
    if opts.get('--remove'):
        out, counts, problems = base, {}, []
    else:
        out, counts, problems = apply(base, tuning, monsters)
    if out != text and not dry:
        write(spawn_path, out)
    for p in problems[:20]:
        print('  ' + p)
    if len(problems) > 20:
        print('  ... %d more' % (len(problems) - 20))
    what = ', '.join('%d %s' % (v, k) for k, v in counts.items()) if counts else 'restored'
    state = 'unchanged' if out == text else ('would change' if dry else 'written')
    print('%s: %s (%s)%s' % (os.path.basename(spawn_path), what, state,
                             ', %d problem(s)' % len(problems) if problems else ''))
    if opts.get('--report'):
        for line in report(out, tuning, monsters, rate_spawn_of(cfg)):
            print(line)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
