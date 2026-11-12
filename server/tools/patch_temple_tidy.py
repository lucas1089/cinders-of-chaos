#!/usr/bin/env python3
"""Tidy Cinderhold's temple (owner 2026-11-03, O386; server/README.md "Temple tidy (O386)"), idempotent.

usage: python3 -I server/tools/patch_temple_tidy.py DATA_DIR [--dry-run] [--map FILE] [--out FILE] [--config FILE]

DATA_DIR is the server's data folder (world/<map>.otbm, items/items.otb, scripts/customs/actions/messages_text.lua).
The list is data/scripts/chaos/temple_portals_config.lua `tidy`: per town a floor, the base map items to take off
(`remove`: x, y and the item id) and the base floating texts to drop (`texts`: x, y and the text). Two parts:
  map    each listed item that is on its tile goes (every item of that id on the tile; the rest of the tile is kept).
         An item with an action id or a unique id is never taken (listed, left alone); a teleport's destination does
         not hold it back (the list names it on purpose). A tile we cannot write back unchanged, or a house tile, is
         listed and left alone. The map goes through <map>.otbm.tmp, its tile count is checked, and <map>.otbm.bak
         is written first when missing (patch_map_fixes.py's helpers).
  texts  the base script scripts/customs/actions/messages_text.lua floats a text over fixed spots every 4 seconds;
         a line with `Position(x, y, z)` of a listed spot and its text (case does not matter) is cut out, line ending
         and all. A missing script is left alone.
Install step `templetidy` (after startchest, before poi). A second run finds nothing and writes nothing. --dry-run
lists what would change and writes nothing; --out writes the new map there instead (the dry run of install_all.py).
Exit 0 on success, 1 on a refusal (no map, compressed map, a bad config).
Python 3 and numpy (tools/map/otbm.py). Test: tools/patch_temple_tidy_test.py (synthetic map and script).
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'map'))

import install_content_areas as IC  # noqa: E402
import patch_map_fixes as F  # noqa: E402

CONFIG = F.TEMPLE_CONFIG
MESSAGES = os.path.join('scripts', 'customs', 'actions', 'messages_text.lua')
POS = re.compile(r'Position\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)')


class TidyError(Exception):
    pass


def entries(cfg):
    """[(town name, [(pos, item id)], [(pos, text)])] of the config's `tidy`; refuses a malformed entry"""
    out = []
    for e in (cfg.get('tidy') if isinstance(cfg, dict) else None) or ():
        try:
            z = int(e['z'])
            rem = [((int(r['x']), int(r['y']), z), int(r['item'])) for r in e.get('remove') or ()]
            txt = [((int(r['x']), int(r['y']), z), str(r['text'])) for r in e.get('texts') or ()]
        except (KeyError, TypeError, ValueError) as ex:
            raise TidyError('temple_portals_config.lua tidy: a bad entry (%s)' % ex)
        out.append((str(e.get('name') or e.get('town')), rem, txt))
    return out


# ------------------------------------------------------------------------------------------------ map
def plan_map(tiles, rem, name, log):
    """take the listed items off the parsed tiles; returns how many go"""
    tiles.load([p for p, _i in rem])
    n = 0
    for p, iid in rem:
        if p in tiles.bad:
            log('%s: %d,%d,%d is %s; left alone' % ((name,) + p + (tiles.bad[p],)))
            continue
        t = tiles.get(p)
        if t is None:
            continue
        items = list(t['items'])
        hits = [k for k, (j, _a) in enumerate(items) if j == iid]
        if not hits:
            if t.get('ground') == iid:
                log('%s: item %d at %d,%d,%d is the ground; left alone' % ((name, iid) + p))
            continue  # gone already (a second run) or never there
        keep = [k for k in hits if items[k][1].get('aid') or items[k][1].get('uid')]
        if keep:
            log('%s: item %d at %d,%d,%d has an action id or a unique id; left alone' % ((name, iid) + p))
        gone = [k for k in hits if k not in keep]
        if not gone:
            continue
        items = [it for k, it in enumerate(items) if k not in gone]
        tiles.set(p, dict(t, items=items))
        log('%s: item %d at %d,%d,%d taken off%s' % ((name, iid) + p + (' (%d of them)' % len(gone) if len(gone) > 1 else '',)))
        n += len(gone)
    return n


# ------------------------------------------------------------------------------------------------ texts
def drop_texts(text, spots):
    """(new text, [(pos, text)] dropped): the lines of messages_text.lua at a listed spot with its text"""
    want = {(p, t.strip().lower()) for p, t in spots}
    out, dropped = [], []
    for line in text.splitlines(True):
        m = POS.search(line)
        if m and 'text' in line:
            p = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
            low = line.lower()
            hit = next((t for (q, t) in want if q == p and ("'%s'" % t in low or '"%s"' % t in low)), None)
            if hit is not None:
                dropped.append((p, hit))
                continue
        out.append(line)
    return ''.join(out), dropped


def plan_texts(data_dir, spots, dry, log):
    path = os.path.join(data_dir, MESSAGES)
    if not spots:
        return 0
    if not os.path.isfile(path):
        log('%s: not there; no floating text to drop' % MESSAGES)
        return 0
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as f:
        text = f.read()
    new, dropped = drop_texts(text, spots)
    for p, t in dropped:
        log('%s: the floating text "%s" at %d,%d,%d dropped%s' % ((MESSAGES, t) + p + (' (dry run)' if dry else '',)))
    if new != text and not dry:
        with open(path + '.tmp', 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
            f.write(new)
        os.replace(path + '.tmp', path)
    return len(dropped)


# ------------------------------------------------------------------------------------------------ run
def run(data_dir, dry=False, map_path=None, out=None, config=CONFIG, log=print):
    try:
        cfg = IC.load_config(config)
    except IC.InstallError as e:
        raise TidyError(str(e))
    todo = entries(cfg)
    rem = [(name, r) for name, r, _t in todo if r]
    spots = [s for _n, _r, t in todo for s in t]
    summary = dict(items=0, texts=0)
    if rem:
        if map_path is None:
            import patch_base_towns
            map_path = patch_base_towns.map_path(data_dir)
        if not map_path or not os.path.isfile(map_path):
            raise TidyError('no world map in %s/world' % data_dir)
        if open(map_path, 'rb').read(2) == b'\x1f\x8b':
            raise TidyError('the world map is compressed; unpack it first')
        import otbm
        world = IC.World(otbm.load_otbm(map_path))
        tiles = F.Tiles(world, map_path)
        for name, r in rem:
            summary['items'] += plan_map(tiles, r, name, log)
        changed = dict(tiles.changed)
        if not changed:
            log('temple tidy: the map has nothing to take off')
        elif dry and not out:
            log('temple tidy: %d tile(s) to rewrite (dry run)' % len(changed))
        else:
            target = out or map_path
            tmp = target + '.tmp'
            IC.write_map(map_path, tmp, list(changed), changed, log=log)
            m2 = otbm.load_otbm(tmp)
            if len(m2.tiles['x']) != world.count():
                os.remove(tmp)
                raise TidyError('internal: the new map has %d tiles, not %d; nothing written'
                                % (len(m2.tiles['x']), world.count()))
            if not out:
                bak = map_path + '.bak'
                if not os.path.exists(bak):
                    shutil.copyfile(map_path, bak)
                    log('backup %s' % bak)
            os.replace(tmp, target)
            log('temple tidy: %d tile(s) written to %s' % (len(changed), target))
    summary['texts'] = plan_texts(data_dir, spots, dry, log)
    if not summary['texts'] and spots:
        log('temple tidy: no floating text to drop')
    return summary


def main(argv):
    opts, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a == '--dry-run':
            opts[a] = True
        elif a in ('--map', '--out', '--config'):
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
            config=opts.get('--config', CONFIG))
    except (TidyError, IC.InstallError) as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
