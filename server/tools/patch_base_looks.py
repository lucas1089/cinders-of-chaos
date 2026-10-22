#!/usr/bin/env python3
"""New looks for base server monsters (idempotent). install_all.py step `baselooks`.

usage: python3 -I patch_base_looks.py DATA_DIR [--picks CSV] [--dry-run]

DATA_DIR is the base server's data folder. Every row of client/tools/sprites/monster_looks/picks.csv with family
"base" names one base monster (column `monsters`, the exact <monster name> of its XML file under DATA_DIR/monster;
the Chaos folders monster/monsters/chaos and monster/lua/chaos are never touched). Its <look> gets type="LOOK" (column
`look`, an outfit of the live client pair). A look of a sheet (lib "pack30", server/data/items/pack30_outfits.csv) has a
colour mask: head, body, legs and feet become the look's first tint scheme. Any other look loses head, body, legs,
feet and addons. The corpse and every other attribute stay. Owner 2026-10-22: "pode sobrescrever os nossos sprites
por aqueles" (server/README.md "Pack 30 monsters in the hunts").

Only the look changes; the monster's name, stats, loot and spawns stay. A name that matches no file is reported (exit
1 with --strict). A second run changes nothing. --dry-run writes nothing.
"""
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PICKS = os.path.join(REPO, 'client', 'tools', 'sprites', 'monster_looks', 'picks.csv')
SHEETS = os.path.join(REPO, 'server', 'data', 'items', 'pack30_outfits.csv')
OWN = (os.path.join('monsters', 'chaos'), os.path.join('lua', 'chaos'))
COLOURS = ('head', 'body', 'legs', 'feet', 'addons')
SHEET_COLOURS = ('head', 'body', 'legs', 'feet')


def wanted(picks_path=PICKS, sheets_path=SHEETS):
    """{monster name: (look, {colour: value})} of the family "base" rows."""
    sheets = {int(r['look_type']): r for r in csv.DictReader(open(sheets_path, newline=''))}
    out = {}
    for r in csv.DictReader(open(picks_path, newline='')):
        if r['family'] != 'base':
            continue
        look = int(r['look'])
        colours = {}
        if r['lib'] == 'pack30':
            s = sheets[look]
            colours = {c: s[c] for c in SHEET_COLOURS}
        out[r['monsters']] = (look, colours)
    return out


def new_look_tag(tag, look, colours):
    tag = re.sub(r'\btype\s*=\s*"\d+"', 'type="%d"' % look, tag, count=1)
    for c in COLOURS:
        tag = re.sub(r'\s+%s\s*=\s*"[^"]*"' % c, '', tag)
    if colours:
        extra = ''.join(' %s="%s"' % (c, colours[c]) for c in SHEET_COLOURS)
        tag = re.sub(r'(\btype="\d+")', r'\1' + extra, tag, count=1)
    return tag


def patch(data_dir, want, dry_run=False, log=print):
    mdir = os.path.join(data_dir, 'monster')
    found, changed = set(), 0
    for root, dirs, files in os.walk(mdir):
        rel = os.path.relpath(root, mdir)
        if any(rel == o or rel.startswith(o + os.sep) for o in OWN):
            dirs[:] = []
            continue
        for f in sorted(files):
            if not f.endswith('.xml'):
                continue
            p = os.path.join(root, f)
            with open(p, encoding='utf-8', errors='surrogateescape', newline='') as fh:
                t = fh.read()
            m = re.search(r'<monster\s+name="([^"]+)"', t)
            lk = re.search(r'<look\s[^>]*>', t)
            if not m or not lk or m.group(1) not in want:
                continue
            found.add(m.group(1))
            look, colours = want[m.group(1)]
            tag = new_look_tag(lk.group(0), look, colours)
            if tag == lk.group(0):
                continue
            changed += 1
            log('%s %s: %s -> %s' % ('would update' if dry_run else 'updated', os.path.relpath(p, mdir), lk.group(0), tag))
            if not dry_run:
                with open(p, 'w', encoding='utf-8', errors='surrogateescape', newline='') as fh:
                    fh.write(t[:lk.start()] + tag + t[lk.end():])
    missing = sorted(set(want) - found)
    for name in missing:
        log('no base monster file for "%s"' % name)
    log('baselooks: %d monsters matched, %d %s, %d missing' % (len(found), changed,
                                                            'to update' if dry_run else 'updated', len(missing)))
    return changed, missing


def main(argv):
    args = list(argv)
    dry = '--dry-run' in args
    strict = '--strict' in args
    args = [a for a in args if a not in ('--dry-run', '--strict')]
    picks = PICKS
    if '--picks' in args:
        i = args.index('--picks')
        picks = args[i + 1]
        del args[i:i + 2]
    if len(args) != 1:
        print(__doc__)
        return 2
    _, missing = patch(args[0], wanted(picks), dry)
    return 1 if strict and missing else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
