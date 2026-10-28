#!/usr/bin/env python3
"""Point monster definitions at the new looks of client/tools/sprites/monster_looks/picks.csv.

usage: python3 -I apply_monster_looks.py [MONSTER_DIR] [--picks CSV] [--check]

MONSTER_DIR defaults to server/data/monster. Rows of picks.csv with family "world", "omen", "raid", "hunt", "dungeonboss" or
"catacombs" (the Hollow Rider of pair 27, client/tools/sprites/monster_looks/assets_art_picks.csv), "harvest" (the
Haunted Harvest of pair 33, client/tools/sprites/monster_looks/harvest_picks.csv, appended when ChaosHarvestArt.PAIR33 goes on),
"lairboss" (Vharzul the Verdant Eye of pair 54, client/tools/sprites/monster_looks/autosprite_picks.csv, appended when
ChaosAutospriteArt.PAIR54 goes on)
(the owner's art of pair 26, client/tools/sprites/monster_looks/owner_art_picks.csv) name one monster (column
`monsters`, the exact <monster name>); its XML gets <look type="LOOK" .../> with LOOK from the `look` column. The
colour attributes (head, body, legs, feet, addons) are removed: these looks have no colour template, so the client
ignores them. The corpse and every other attribute stay. The rift family rows (abyss, obsidian, crypt, sanctum) belong
to no monster file (rift.lua puts them on the rift's monsters); --check makes sure no file uses them, and that
rift_config.lua `looks.families` holds exactly these ids. Rows of family "faction" (mounts and auras) belong to no
monster file either (mounts.xml / auras.xml, factions_config.lua), nor do rows of family "exclusive" (the achievement
wings of exclusives_config.lua, wings.xml); --check makes sure no monster file uses them. Rows of family "riftvariant"
(rank variants of the rift looks, client/tools/sprites/monster_looks/rift_variant_picks.csv) belong to no monster file
either; --check makes sure rift_config.lua `looks.variants` lists each. Rows of family "bigguardian" (the bigger
guardian looks, client/tools/sprites/monster_looks/big_boss_picks.csv) belong to no monster file either; --check makes
sure rift_config.lua `looks.bigGuardians` maps a guardian look to each. Rows of family "storewings" (the store wings of
pair 26, data/lib/chaos_owner_art.lua) belong to no monster file either, and so do the rows of family "gallery" (pair 30
looks no monster file uses, shown by the admin gallery) and "sheetlook" (pair 30 sheet looks that keep their colour
template, for NPCs and decoration). Rows of family "base" name a base server monster: server/tools/patch_base_looks.py
(install step baselooks) writes them into the base files; a "base" row of a sheet look (lib "pack30") belongs to no
file here either, while a "base" row of a kit look (lib "set33") shares the look of its harvest monster. A look of a sheet (rows with lib "pack30", client/tools/sprites/monster_looks/
pack30_picks.csv) has a colour mask: when a `hunt` row names one, head, body, legs and feet of the monster's <look>
stay (only addons go); the other looks lose all five.
Idempotent: a second run changes nothing. --check changes nothing and exits 1 when a file is not up to date.
"""
import csv, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PICKS = os.path.join(REPO, 'client', 'tools', 'sprites', 'monster_looks', 'picks.csv')
RIFT_CONFIG = os.path.join(REPO, 'server', 'data', 'scripts', 'chaos', 'rift_config.lua')
COLOURS = ('head', 'body', 'legs', 'feet', 'addons')
# families whose rows name one monster file each (column `monsters`, the exact <monster name>)
MONSTER_FAMILIES = ('world', 'omen', 'raid', 'hunt', 'dungeonboss', 'catacombs', 'harvest', 'lairboss')
SHEET_LIB = 'pack30'  # looks cut from 4-direction sheets: colour mask, so head/body/legs/feet are kept
SHEET_COLOURS = ('head', 'body', 'legs', 'feet')
FAMILY_THEME = {'abyss': 'Abyssal Rift', 'obsidian': 'Obsidian Hall', 'crypt': 'Ashen Crypt', 'sanctum': 'Forsaken Sanctum'}


def new_look_tag(tag, look, keep=()):
    tag = re.sub(r'\btype\s*=\s*"\d+"', 'type="%d"' % look, tag, count=1)
    for c in COLOURS:
        if c in keep:
            continue
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
    want = {r['monsters']: int(r['look']) for r in rows if r['family'] in MONSTER_FAMILIES}
    keep = {r['monsters']: SHEET_COLOURS for r in rows if r['family'] in MONSTER_FAMILIES and r['lib'] == SHEET_LIB}
    rift = {int(r['look']): r['key'] for r in rows
            if r['family'] in FAMILY_THEME or r['family'] in ('faction', 'exclusive', 'riftvariant', 'bigguardian',
                                                              'storewings', 'gallery', 'sheetlook')
            or (r['family'] == 'base' and r['lib'] == SHEET_LIB)}
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
            tag = new_look_tag(lk.group(0), want[name], keep.get(name, ()))
            if tag != lk.group(0):
                changed += 1
                print(f'{"would update" if check else "updated"} {os.path.relpath(p, mdir)}: {lk.group(0)} -> {tag}')
                if not check:
                    open(p, 'w', encoding='utf-8', errors='surrogateescape').write(t.replace(lk.group(0), tag, 1))
    for name in sorted(set(want) - found):
        problems.append(f'no monster file for "{name}"')
    # rift_config.lua: the families hold exactly the rift rows of picks.csv
    cfg = open(RIFT_CONFIG, encoding='utf-8').read()
    # only the looks block: other tables of rift_config.lua are keyed by theme too (layouts, palettes)
    fam = re.search(r'\blooks\s*=\s*\{.*?\bfamilies\s*=\s*\{', cfg, re.S)
    cfg = cfg[fam.end():] if fam else cfg
    for r in rows:
        if r['family'] in FAMILY_THEME:
            line = re.search(r'\["%s"\]\s*=\s*\{([^}]*)\}' % re.escape(FAMILY_THEME[r['family']]), cfg)
            v = line and re.search(r'\b%s\s*=\s*(\d+)' % r['rank'], line.group(1))
            if not v or int(v.group(1)) != int(r['look']):
                problems.append(f"rift_config.lua looks.families[\"{FAMILY_THEME[r['family']]}\"].{r['rank']} is not {r['look']}")
    # rank variants (family riftvariant, appended from client/tools/sprites/monster_looks/rift_variant_picks.csv with
    # pair 24): each look is in rift_config.lua looks.variants
    var = re.search(r'\bvariants\s*=\s*\{', cfg)
    vcfg = cfg[var.end():] if var else ''
    for r in rows:
        if r['family'] == 'riftvariant' and not re.search(r'\blook\s*=\s*%d\b' % int(r['look']), vcfg):
            problems.append(f"rift_config.lua looks.variants has no look {r['look']} ({r['key']})")
    # bigger guardians (family bigguardian, appended from monster_looks/big_boss_picks.csv with pair 24): each look is
    # the big look of its source look (column lib_id) in rift_config.lua looks.bigGuardians
    big = re.search(r'\bbigGuardians\s*=\s*\{([^}]*)\}', cfg)
    bmap = {int(k): int(v) for k, v in re.findall(r'\[(\d+)\]\s*=\s*(\d+)', big.group(1))} if big else {}
    for r in rows:
        if r['family'] == 'bigguardian' and bmap.get(int(r['lib_id'])) != int(r['look']):
            problems.append(f"rift_config.lua looks.bigGuardians[{r['lib_id']}] is not {r['look']} ({r['key']})")
    for p in problems:
        print('PROBLEM', p)
    print(f'{len(found)} monster files matched, {changed} {"to update" if check else "updated"}, {len(problems)} problems')
    sys.exit(1 if problems or (check and changed) else 0)


if __name__ == '__main__':
    main()
