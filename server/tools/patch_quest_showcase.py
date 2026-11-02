#!/usr/bin/env python3
"""Make the rewards on show in the quest hall match what each quest gives (server/README.md "Quest hall showcase"),
idempotent.

usage: python3 -I server/tools/patch_quest_showcase.py DATA_DIR [--dry-run] [--map FILE] [--out FILE] [--rows FILE]

Owner, 2026-11-02 ("Veja se as quests estao dando os mesmos rewards que estao nas vitrines dos teleports"; "Sim pra
todos"): the base map's quest alcoves (moved to the plaza by install_content_areas.py, tools/hall_quests.py) show items
some quests do not give and miss items they do give. tools/quest_showcase.json lists per quest (a row of kind `quest` in
tools/hall_hunts.csv):
  replace  [on show, given]: the item on show swapped for the one the quest gives, in place (same cell, same attributes)
  add      item ids the quest gives that are not on show: put on the alcove's cell with the fewest items (middle first)
  sign     the alcove sign's new text (the boss-loot quests: their items on show come from a loot bag by chance)
The alcove is found from the map: the teleport item (magic forcefield 1387, or 5023 / 11796, the base quests' own) whose
destination is the quest's in the CSV and that has the sign (5360) two tiles behind it; its cell row is the one between
(x - 1 .. x + 1). A quest with no such alcove (the hall not installed) is listed and skipped; two are refused.
Install step `questshowcase`, after `contentareas` (which moves the alcoves) and `mapfixes`, before poi. An item that is
on show already (or a sign with the text already) is left alone, so a second run changes nothing. The map goes through
<map>.otbm.tmp, its tile count is checked, and <map>.otbm.bak is written first when missing. --dry-run lists and writes
nothing; --out writes the new map there. Exit 0 on success, 1 on a refusal.
Python 3 and numpy (tools/map/otbm.py). Test: tools/patch_quest_showcase_test.py (synthetic map).
"""
import json, os, shutil, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import install_content_areas as IC  # noqa: E402
import hall_order as H  # noqa: E402
import patch_map_fixes as PM  # noqa: E402

ROWS = os.path.join(HERE, 'quest_showcase.json')
PORTALS = (1387, 5023, 11796)  # hunt_teleports_config.lua items.portal, items.questPortals
SIGN = 5360  # hunt_teleports_config.lua items.sign
ATTR_TEXT = 6


class ShowcaseError(Exception):
    pass


def read_rows(path=ROWS, csv_rows=None):
    """[dict(quest, dest, replace=[(old, new)], add=[id], sign=text or None)]; every quest must be a CSV quest row"""
    with open(path, encoding='utf-8') as f:
        doc = json.load(f)
    quests = {r['name']: r for r in (csv_rows if csv_rows is not None else H.read_csv()) if r.get('kind') == 'quest'}
    out, seen = [], set()
    for q in doc['quests']:
        name = q['quest']
        if name in seen:
            raise ShowcaseError('quest_showcase.json names %s twice' % name)
        seen.add(name)
        if name not in quests:
            raise ShowcaseError('quest_showcase.json: %s is no quest row of hall_hunts.csv' % name)
        r = quests[name]
        rep = [tuple(int(v) for v in p) for p in q.get('replace', ())]
        if any(len(p) != 2 or p[0] == p[1] for p in rep):
            raise ShowcaseError('quest_showcase.json: %s: a replace row is not [on show, given]' % name)
        sign = q.get('sign')
        if sign is not None and (not sign.strip() or len(sign.encode('latin-1')) > 1000):
            raise ShowcaseError('quest_showcase.json: %s: the sign text is empty or too long' % name)
        out.append(dict(quest=name, dest=(r['dest_x'], r['dest_y'], r['dest_z']), replace=rep, add=[int(i) for i in q.get('add', ())],
                        sign=sign))
    return out


def raw_attrs(raw):
    """[(attr, bytes with the attr byte)] of an item's kept attributes (hall_order.parse_tile's 'raw')"""
    out, j = [], 0
    while j < len(raw):
        a = raw[j]
        if a in H.ITEM_STRING_ATTRS:
            n = 3 + struct.unpack_from('<H', raw, j + 1)[0]
        elif a in H.ITEM_FIXED_ATTRS:
            n = 1 + H.ITEM_FIXED_ATTRS[a]
        else:
            raise ShowcaseError('internal: unknown kept attribute %d' % a)
        out.append((a, bytes(raw[j:j + n])))
        j += n
    return out


def sign_text(attrs):
    for a, b in raw_attrs(attrs.get('raw', b'')):
        if a == ATTR_TEXT:
            return b[3:].decode('latin-1')
    return None


def with_text(attrs, text):
    enc = text.encode('latin-1')
    keep = [b for a, b in raw_attrs(attrs.get('raw', b'')) if a != ATTR_TEXT]
    raw = bytes([ATTR_TEXT]) + struct.pack('<H', len(enc)) + enc + b''.join(keep)
    return dict(attrs, raw=raw)


def find_alcoves(world, teleports, rows):
    """{quest: (teleport pos, cell row y)}: the hall's alcove of each quest (a teleport to its destination with the sign
    two tiles behind it); a quest with none is left out, one with two is refused"""
    by_dest = {}
    for pos, dest in teleports:
        by_dest.setdefault(tuple(dest), []).append(tuple(pos))
    out = {}
    for r in rows:
        found = []
        for x, y, z in by_dest.get(r['dest'], ()):
            for s in (-1, 1):
                st = world.stack((x, y + 2 * s, z))
                if st and SIGN in st:
                    found.append(((x, y, z), y + s))
        if len(found) > 1:
            raise ShowcaseError('%s: %d alcoves lead to %s' % (r['quest'], len(found), r['dest']))
        if found:
            out[r['quest']] = found[0]
    return out


def plan(tiles, rows, alcoves, log):
    """change the parsed tiles; returns dict(done, kept, skipped)"""
    res = dict(done=0, kept=0, skipped=0)
    want = []
    for (x, y, z), cy in alcoves.values():
        want += [(x + dx, cy, z) for dx in (-1, 0, 1)] + [(x, y + 2 * (cy - y), z)]
    tiles.load(want)
    for r in rows:
        if r['quest'] not in alcoves:
            log('%s: no alcove in the quest hall; skipped' % r['quest'])
            res['skipped'] += 1
            continue
        (x, y, z), cy = alcoves[r['quest']]
        cells = [(x, cy, z), (x - 1, cy, z), (x + 1, cy, z)]  # the middle first
        bad = [p for p in cells + [(x, 2 * cy - y, z)] if p in tiles.bad or tiles.get(p) is None]
        if bad:
            log('%s: the tile %s cannot be rewritten (%s); skipped' % (r['quest'], bad[0], tiles.bad.get(bad[0], 'no tile')))
            res['skipped'] += 1
            continue

        def shown(iid):
            return any(i == iid for p in cells for i, _a in tiles.get(p)['items'])

        for old, new in r['replace']:
            if shown(new) and not shown(old):
                res['kept'] += 1
                continue
            hit = next((p for p in cells if any(i == old for i, _a in tiles.get(p)['items'])), None)
            if hit is None:
                raise ShowcaseError('%s: item %d is not on show (to become %d)' % (r['quest'], old, new))
            t = tiles.get(hit)
            items, done = [], False
            for i, a in t['items']:
                if i == old and not done:
                    items.append((new, a))
                    done = True
                else:
                    items.append((i, a))
            tiles.set(hit, dict(t, items=items))
            log('%s: %d on show is now %d at %s' % (r['quest'], old, new, hit))
            res['done'] += 1
        for new in r['add']:
            if shown(new):
                res['kept'] += 1
                continue
            p = min(cells, key=lambda c: len(tiles.get(c)['items']))
            t = tiles.get(p)
            tiles.set(p, dict(t, items=list(t['items']) + [(new, {})]))
            log('%s: %d added at %s' % (r['quest'], new, p))
            res['done'] += 1
        if r['sign'] is not None:
            sp = (x, 2 * cy - y, z)
            t = tiles.get(sp)
            k = next(n for n, (i, _a) in enumerate(t['items']) if i == SIGN)
            if sign_text(t['items'][k][1]) == r['sign']:
                res['kept'] += 1
                continue
            items = list(t['items'])
            items[k] = (SIGN, with_text(items[k][1], r['sign']))
            tiles.set(sp, dict(t, items=items))
            log('%s: sign text written at %s' % (r['quest'], sp))
            res['done'] += 1
    return res


def run(data_dir, dry=False, map_path=None, out=None, rows_path=ROWS, csv_rows=None, log=print):
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise ShowcaseError('no world map in %s/world' % data_dir)
    if open(map_path, 'rb').read(2) == b'\x1f\x8b':
        raise ShowcaseError('the world map is compressed; unpack it first')
    rows = read_rows(rows_path, csv_rows)
    import otbm
    m = otbm.load_otbm(map_path)
    world = IC.World(m)
    tele = [((int(m.tiles['x'][ti]), int(m.tiles['y'][ti]), int(m.tiles['z'][ti])), d)
            for ti, _iid, d in otbm.teleports(m, set(PORTALS))]
    alcoves = find_alcoves(world, tele, rows)
    tiles = PM.Tiles(world, map_path)
    res = plan(tiles, rows, alcoves, log)
    log('quest showcase: %d change(s), %d there already, %d quest(s) skipped' % (res['done'], res['kept'], res['skipped']))
    changed = dict(tiles.changed)
    if not changed:
        log('quest showcase: nothing to do')
        return res
    if dry and not out:
        return res
    target = out or map_path
    tmp = target + '.tmp'
    IC.write_map(map_path, tmp, list(changed), dict(changed))
    m2 = otbm.load_otbm(tmp)
    if len(m2.tiles['x']) != world.count():
        os.remove(tmp)
        raise ShowcaseError('internal: the new map has %d tiles, not %d; nothing written' % (len(m2.tiles['x']), world.count()))
    if not out:
        bak = map_path + '.bak'
        if not os.path.exists(bak):
            shutil.copyfile(map_path, bak)
            log('backup %s' % bak)
    os.replace(tmp, target)
    log('quest showcase: written to %s' % target)
    return res


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a == '--dry-run':
            opts[a] = True
        elif a in ('--map', '--out', '--rows'):
            if i + 1 >= len(argv):
                print('%s needs a value' % a)
                return 1
            opts[a] = argv[i + 1]
            i += 1
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        elif a.startswith('-'):
            print('unknown option %s' % a)
            return 1
        else:
            pos.append(a)
        i += 1
    if len(pos) != 1:
        print(__doc__)
        return 1
    try:
        run(pos[0], dry=opts.get('--dry-run', False), map_path=opts.get('--map'), out=opts.get('--out'),
            rows_path=opts.get('--rows', ROWS))
    except (ShowcaseError, PM.FixError, IC.InstallError, H.HallError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
