#!/usr/bin/env python3
"""Merge our brushes and palettes into the editor's data folder (O514).

    python3 -I mapeditor/tools/merge_brushes.py DATA_DIR [--fragments DIR]

DATA_DIR is the editor's data/1098 folder (brushes.json, tilesets.json). --fragments is the folder with
cinders_brushes.json and cinders_tilesets.json (default: mapeditor/data/1098/cinders, written by
server/tools/gen_editor_brushes.py).

The editor reads one brushes.json and one tilesets.json per client version and has no include for a second file, so
our entries go into them (no change of the editor's program):
  - "borders" and "grounds" of the fragment are set by key / name; an entry of an earlier run is replaced, stock
    entries are never touched or removed
  - each palette of the fragment's tilesets is set by category and name
It stops (exit 1, nothing written) when one of our grounds lists an item id that a stock ground already owns, when
a key of ours is a stock key we did not write (no "cinders" prefix), or when a file is missing or not JSON.
Idempotent: a second run changes nothing. The build workflow runs it on the release folder (so the self-updater's zip
carries it) and the Windows package runs it again on whatever editor it unpacks. Test: merge_brushes_test.py."""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FRAGMENTS = os.path.join(os.path.dirname(HERE), 'data', '1098', 'cinders')
PREFIXES = ('cinders ', 'cinders_')


def load(path):
    try:
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        raise SystemExit('%s: %s' % (path, e))
    if not isinstance(data, dict):
        raise SystemExit('%s: not a JSON object' % path)
    return data


def merge_brushes(stock, ours):
    """the merged brushes object; raises SystemExit on a clash with a stock entry"""
    out = dict(stock)
    borders = dict(stock.get('borders', {}))
    grounds = dict(stock.get('grounds', {}))
    owned = {}
    for name, g in grounds.items():
        if name.startswith(PREFIXES[0]):
            continue
        for item in g.get('items', []):
            owned.setdefault(int(item[0]), name)
        if g.get('lookid'):
            owned.setdefault(int(g['lookid']), name)
    for key, arr in ours.get('borders', {}).items():
        if key in borders and not key.startswith(PREFIXES[1]):
            raise SystemExit('border set %r is a stock key' % key)
        borders[key] = arr
    for name, g in ours.get('grounds', {}).items():
        if name in grounds and not name.startswith(PREFIXES[0]):
            raise SystemExit('ground %r is a stock ground' % name)
        ids = [int(i[0]) for i in g.get('items', [])] + [int(g.get('lookid', 0))]
        for i in ids:
            if i in owned:
                raise SystemExit('ground %r: item %d already belongs to the stock ground %r' % (name, i, owned[i]))
        for b in g.get('borders', []):
            if b['border'] not in borders:
                raise SystemExit('ground %r: border set %r is not defined' % (name, b['border']))
        grounds[name] = g
    out['borders'] = borders
    out['grounds'] = grounds
    return out


def merge_tilesets(stock, ours):
    out = {cat: dict(v) if isinstance(v, dict) else v for cat, v in stock.items()}
    for cat, palettes in ours.items():
        if not isinstance(out.get(cat), dict):
            out[cat] = {}
        for name, ids in palettes.items():
            out[cat][name] = ids
    return out


def dump(obj):
    return json.dumps(obj, separators=(',', ':'), ensure_ascii=True)


def write_if_changed(path, text):
    try:
        with open(path, encoding='utf-8') as f:
            if f.read() == text:
                return False
    except OSError:
        pass
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8', newline='') as f:
        f.write(text)
    os.replace(tmp, path)
    return True


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('data_dir')
    ap.add_argument('--fragments', default=FRAGMENTS)
    a = ap.parse_args(argv)
    sb, st = os.path.join(a.data_dir, 'brushes.json'), os.path.join(a.data_dir, 'tilesets.json')
    brushes = merge_brushes(load(sb), load(os.path.join(a.fragments, 'cinders_brushes.json')))
    tilesets = merge_tilesets(load(st), load(os.path.join(a.fragments, 'cinders_tilesets.json')))
    ch = [write_if_changed(sb, dump(brushes)), write_if_changed(st, dump(tilesets))]
    print('brushes.json %s, tilesets.json %s (%d of our grounds)' % (
        'changed' if ch[0] else 'unchanged', 'changed' if ch[1] else 'unchanged',
        sum(1 for n in brushes['grounds'] if n.startswith(PREFIXES[0]))))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
