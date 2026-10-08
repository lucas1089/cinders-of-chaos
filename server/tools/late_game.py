#!/usr/bin/env python3
"""Late game (levels 700-1000): experience stages and spawns of the level-scaled Chaos monsters.

usage: python3 -I late_game.py DATA_DIR [--config PATH] [--spawn PATH] [--csv PATH] [--dry-run] [--remove]

1. config.lua (default DATA_DIR/../config.lua): replaces the experienceStages table with STAGES below. Up to level 700
   nothing changes; after it the base server dropped by 3 every 50 levels to x3 from 851, now it goes 15, 15, 14, 14,
   13, 13 (x13 from 951). See server/README.md "Late game" for the leveling model behind it.
2. The spawn file of the loaded map (default DATA_DIR/world/<mapName>-spawn.xml, mapName read from config.lua):
   every row of late_game_spawns.csv (next to this script) renames one existing spawn entry (spawn block centre +
   offset, and the monster it replaces) to a level-scaled Chaos monster. The entries are existing spawn positions,
   so they are walkable and inside the existing hunting areas; nothing is added, a share of the weaker monsters is
   replaced. Each changed entry carries lategame="<old name>".

Idempotent: a run syncs the file to the CSV (entries already marked are updated or left alone, marked entries that
are no longer in the CSV get their old monster back). --remove restores every marked entry and the stock stage table.
The monsters themselves (levels, health, speed, damage) are tuned in data/monster/monsters/chaos/*.xml.
"""
import csv, os, re, sys

MARK = 'lategame'
STAGES_MARK = '-- Chaos late game stages (server/tools/late_game.py)'
# (minlevel, maxlevel or None, multiplier). The last stage needs an explicit maxlevel: this engine's loadLuaStages reads a
# missing maxlevel as 0, so a stage without one never matches and those levels fall back to rateExp (5). The stock
# table's "{ minlevel = 851, multiplier = 3 }" therefore gave x5, not x3, from level 851.
OPEN_END = 999999
BASE_STAGES = [(1, 20, 10), (21, 50, 50), (51, 100, 45), (101, 150, 43), (151, 200, 41), (201, 300, 39),
               (301, 350, 36), (351, 400, 33), (401, 450, 30), (451, 500, 27), (501, 550, 24), (551, 600, 21),
               (601, 650, 18), (651, 700, 15)]
STAGES = BASE_STAGES + [(701, 750, 15), (751, 800, 15), (801, 850, 14), (851, 900, 14), (901, 950, 13), (951, OPEN_END, 13)]
STOCK_STAGES = BASE_STAGES + [(701, 750, 12), (751, 800, 9), (801, 850, 6), (851, None, 3)]


def stages_lua(stages, marker, eol='\n'):
    rows = []
    for lo, hi, mult in stages:
        rows.append('\t{ minlevel = %d, %smultiplier = %d }' % (lo, '' if hi is None else 'maxlevel = %d, ' % hi, mult))
    return (marker + eol if marker else '') + 'experienceStages = {' + eol + (',' + eol).join(rows) + eol + '}'


def patch_config(text, remove):
    """returns (new text, status)"""
    m = re.search(r'(?:%s\r?\n)?experienceStages\s*=\s*\{.*?\n\}' % re.escape(STAGES_MARK), text, re.S)
    if not m:
        return text, 'experienceStages table not found'
    eol = '\r\n' if '\r\n' in m.group(0) else '\n'
    new = stages_lua(STOCK_STAGES, None, eol) if remove else stages_lua(STAGES, STAGES_MARK, eol)
    if m.group(0) == new:
        return text, 'already'
    if remove and STAGES_MARK not in m.group(0):
        return text, 'not patched'
    return text[:m.start()] + new + text[m.end():], 'restored' if remove else 'patched'


def map_name(config_text):
    m = re.search(r'^\s*mapName\s*=\s*"([^"]+)"', config_text, re.M)
    return m.group(1) if m else None


def load_csv(path):
    rows = {}
    with open(path, newline='', encoding='utf-8') as f:
        for r in csv.DictReader(f):
            key = (int(r['centerx']), int(r['centery']), int(r['centerz']), int(r['x']), int(r['y']), int(r['z']))
            rows[key] = (r['replaces'], r['monster'])
    return rows


SPAWN_RE = re.compile(r'(<spawn\s+centerx="(\d+)"\s+centery="(\d+)"\s+centerz="(\d+)"[^>]*>)(.*?)(</spawn>)', re.S)
MON_RE = re.compile(r'<monster\s[^>]*?/>')


def attr(tag, name):
    m = re.search(r'\b%s="([^"]*)"' % name, tag)
    return m.group(1) if m else None


def set_attr(tag, name, value):
    if value is None:
        return re.sub(r'\s%s="[^"]*"' % name, '', tag)
    if attr(tag, name) is not None:
        return re.sub(r'(\b%s=")[^"]*(")' % name, lambda m: m.group(1) + value + m.group(2), tag, count=1)
    return re.sub(r'\s*/>$', ' %s="%s" />' % (name, value), tag)


def patch_spawns(text, rows, remove):
    """returns (new text, counts, problems)"""
    counts = {'replaced': 0, 'already': 0, 'updated': 0, 'restored': 0}
    problems = []
    seen = set()

    def monster(tag, center):
        name, old = attr(tag, 'name'), attr(tag, MARK)
        key = center + (int(attr(tag, 'x') or 0), int(attr(tag, 'y') or 0), int(attr(tag, 'z') or center[2]))
        want = None if remove else rows.get(key)
        if want:
            seen.add(key)
        if old is not None:
            if want is None:
                counts['restored'] += 1
                return set_attr(set_attr(tag, 'name', old), MARK, None)
            if old.lower() != want[0].lower():
                problems.append('%s: marked as replacing %r, the CSV says %r' % (key, old, want[0]))
                return tag
            if name == want[1]:
                counts['already'] += 1
                return tag
            counts['updated'] += 1
            return set_attr(tag, 'name', want[1])
        if want is None:
            return tag
        if name.lower() != want[0].lower():
            problems.append('%s: expected %r, found %r' % (key, want[0], name))
            return tag
        counts['replaced'] += 1
        return set_attr(set_attr(tag, 'name', want[1]), MARK, name)

    def block(m):
        center = (int(m.group(2)), int(m.group(3)), int(m.group(4)))
        body = MON_RE.sub(lambda mm: monster(mm.group(0), center), m.group(5))
        return m.group(1) + body + m.group(6)

    out = SPAWN_RE.sub(block, text)
    if not remove:
        for key in sorted(set(rows) - seen):
            problems.append('%s: no spawn entry (%s)' % (key, rows[key][0]))
    return out, counts, problems


def main():
    argv = sys.argv[1:]
    opts = {}
    for k in ('--config', '--spawn', '--csv'):
        if k in argv:
            i = argv.index(k)
            opts[k] = argv[i + 1]
            del argv[i:i + 2]
    args = [a for a in argv if not a.startswith('--')]
    if len(args) != 1:
        print(__doc__)
        return 1
    dry, remove = '--dry-run' in argv, '--remove' in argv
    data = args[0]
    cfg_path = opts.get('--config', os.path.join(data, '..', 'config.lua'))
    csv_path = opts.get('--csv', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'late_game_spawns.csv'))
    ok = True

    cfg = open(cfg_path, encoding='utf-8', errors='surrogateescape', newline='').read()
    new_cfg, status = patch_config(cfg, remove)
    if new_cfg != cfg and not dry:
        open(cfg_path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(new_cfg)
    print(f'{cfg_path}: experienceStages {status}{" (dry run)" if dry and new_cfg != cfg else ""}')
    ok = status in ('patched', 'restored', 'already', 'not patched')

    spawn_path = opts.get('--spawn')
    if not spawn_path:
        name = map_name(cfg)
        if not name:
            print(f'{cfg_path}: mapName not found, pass --spawn')
            return 1
        spawn_path = os.path.join(data, 'world', name + '-spawn.xml')
    text = open(spawn_path, encoding='utf-8', errors='surrogateescape', newline='').read()
    rows = {} if remove else load_csv(csv_path)
    out, counts, problems = patch_spawns(text, rows, remove)
    if out != text and not dry:
        open(spawn_path, 'w', encoding='utf-8', errors='surrogateescape', newline='').write(out)
    for p in problems[:20]:
        print('  ' + p)
    if len(problems) > 20:
        print(f'  ... {len(problems) - 20} more')
    print(f'{spawn_path}: ' + ', '.join(f'{v} {k}' for k, v in counts.items()) +
          (f', {len(problems)} problem(s)' if problems else '') + (' (dry run)' if dry else ''))
    return 0 if ok and not problems else 1


if __name__ == '__main__':
    sys.exit(main())
