#!/usr/bin/env python3
"""Point monster definitions at the new looks of client/tools/sprites/monster_looks/picks.csv.

usage: python3 -I apply_monster_looks.py [MONSTER_DIR] [--picks CSV] [--check]

MONSTER_DIR defaults to server/data/monster. Rows of picks.csv with family "world", "omen" or "raid" name one monster (column
`monsters`, the exact <monster name>); its XML gets <look type="LOOK" .../> with LOOK from the `look` column. The
colour attributes (head, body, legs, feet, addons) are removed: these looks have no colour template, so the client
ignores them. The corpse and every other attribute stay. The rift family rows (abyss, obsidian, crypt, sanctum) belong
to no monster file (rift.lua puts them on the rift's monsters); --check makes sure no file uses them, and that
rift_config.lua `looks.families` holds exactly these ids. Rows of family "faction" (mounts and auras) belong to no
monster file either (mounts.xml / auras.xml, factions_config.lua), nor do rows of family "exclusive" (the achievement
wings of exclusives_config.lua, wings.xml); --check makes sure no monster file uses them.
Idempotent: a second run changes nothing. --check changes nothing and exits 1 when a file is not up to date.
"""
import csv, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PICKS = os.path.join(REPO, 'client', 'tools', 'sprites', 'monster_looks', 'picks.csv')
RIFT_CONFIG = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'rift_config.lua')
COLOURS = ('head', 'body', 'legs', 'feet', 'addons')
FAMILY_THEME = {'abyss': 'Abyssal Rift', 'obsidian': 'Obsidian Hall', 'crypt': 'Ashen Crypt', 'sanctum': 'Forsaken Sanctum'}


def new_look_tag(tag, look):
    tag = re.sub(r'\btype\s*=\s*"\d+"', 'type="%d"' % look, tag, count=1)
    for c in COLOURS:
        tag = re.sub(r'\s+%s\s*=\s*"[^"]*"' % c, '', tag)
    return tag


def main():
    args = sys.argv[1:]
    check = '--check' in args
    if check:
        args.remove('--check')
    picks = PICKS
    if '--picks' in args:
        i = args.index('--picks'); picks = args[i + 1]; del args[i:i + 2]
    mdir = args[0] if args else os.path.join(REPO, 'server', 'data', 'monster')
    rows = list(csv.DictReader(open(picks, newline='')))
    want = {r['monsters']: int(r['look']) for r in rows if r['family'] in ('world', 'omen', 'raid')}
    rift = {int(r['look']): r['key'] for r in rows if r['family'] in FAMILY_THEME or r['family'] in ('faction', 'exclusive')}
    found, changed, problems = set(), 0, []
    for root, _, files in os.walk(mdir):
        for f in sorted(files):
            if not f.endswith('.xml'):
                continue
            p = os.path.join(root, f)
            t = open(p, encoding='utf-8', errors='surrogateescape').read()
            m = re.search(r'<monster\s+name="([^"]+)"', t)
            lk = re.search(r'<look\s[^>]*>', t)
            if not m or not lk:
                continue
            look = re.search(r'\btype\s*=\s*"(\d+)"', lk.group(0))
            if look and int(look.group(1)) in rift:
                problems.append(f'{p}: uses the rift / faction / exclusive look {look.group(1)} ({rift[int(look.group(1))]})')
            name = m.group(1)
            if name not in want:
                continue
            found.add(name)
            tag = new_look_tag(lk.group(0), want[name])
            if tag != lk.group(0):
                changed += 1
                print(f'{"would update" if check else "updated"} {os.path.relpath(p, mdir)}: {lk.group(0)} -> {tag}')
                if not check:
                    open(p, 'w', encoding='utf-8', errors='surrogateescape').write(t.replace(lk.group(0), tag, 1))
    for name in sorted(set(want) - found):
        problems.append(f'no monster file for "{name}"')
    # rift_config.lua: the families hold exactly the rift rows of picks.csv
    cfg = open(RIFT_CONFIG, encoding='utf-8').read()
    for r in rows:
        if r['family'] in FAMILY_THEME:
            line = re.search(r'\["%s"\]\s*=\s*\{([^}]*)\}' % re.escape(FAMILY_THEME[r['family']]), cfg)
            v = line and re.search(r'\b%s\s*=\s*(\d+)' % r['rank'], line.group(1))
            if not v or int(v.group(1)) != int(r['look']):
                problems.append(f"rift_config.lua looks.families[\"{FAMILY_THEME[r['family']]}\"].{r['rank']} is not {r['look']}")
    for p in problems:
        print('PROBLEM', p)
    print(f'{len(found)} monster files matched, {changed} {"to update" if check else "updated"}, {len(problems)} problems')
    sys.exit(1 if problems or (check and changed) else 0)


if __name__ == '__main__':
    main()
