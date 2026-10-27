#!/usr/bin/env python3
"""Removes the base server's starter chest (owner request 2026-10-27; server/README.md "Starter chest removed"), idempotent.

usage: python3 -I server/tools/patch_start_chest.py DATA_DIR [--dry-run] [--map FILE] [--out FILE]

The base server's "Collect First Items!" chest (data/scripts/customs/actions/first_chest.lua) hands out a stock class kit
once per character (action id and storage key 33735, old vocation ids only). The Chaos new-player kit (newplayer.lua)
gives every new character the kit of its class automatically, so the chest is not needed. Two parts:
  map      every item node with action id 33735 (the chest, whatever look it wears: the stock reward chest 21584 or the
           reward chest look of patch_reward_chests.py) is cut out of its tile, with whatever is inside it. The rest of
           the tile and the map keep their bytes.
  script   DATA_DIR/scripts/customs/actions/first_chest.lua (the chest's use script and, in the base, its floating text)
           is renamed to first_chest.lua.chaos-off, so it is not registered. Any other .lua / .xml file of DATA_DIR that
           still holds the text "Collect First Items" is only listed (a hint, never changed).
The map goes through <map>.otbm.tmp and <map>.otbm.bak is written first when missing. A second run finds nothing and
writes nothing. --dry-run lists what would change and writes nothing; --out writes the new map there instead (the dry
run of install_all.py). Exit 0 on success, 1 on a refusal (compressed map, no map). Python 3 standard library.
Test: tools/patch_start_chest_test.py (synthetic map).
"""
import os, shutil, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # python -I leaves the script's folder off sys.path

import gen_poi as G  # noqa: E402

CHEST_AID = 33735
SCRIPT = os.path.join('scripts', 'customs', 'actions', 'first_chest.lua')
OFF = '.chaos-off'
TEXT = b'collect first items'


class ChestError(Exception):
    pass


def node_end(data, start):
    """index of the byte after the END marker of the node that starts at `start`"""
    depth, i, n = 0, start, len(data)
    while i < n:
        c = data[i]
        if c == G.ESC:
            i += 2
            continue
        if c == G.START:
            depth += 1
        elif c == G.END:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ChestError('unterminated node at %d' % start)


def find_chests(data, aid=CHEST_AID):
    """[(node start, node end, (x, y, z))] of every item node with this action id"""
    out = []
    needle = bytes([G.A_ACTION]) + G.esc(struct.pack('<H', aid))
    i = data.find(needle)
    while i >= 0:
        s = G.last_node_start(data, i)
        if s >= 0 and data[s + 1] == G.T_ITEM:
            parsed = G.parse_item(G.payload(data, s + 2))
            if parsed and G.A_ACTION in parsed[1] and struct.unpack('<H', parsed[1][G.A_ACTION])[0] == aid \
                    and not any(s == o[0] for o in out):
                out.append((s, node_end(data, s), G.tile_position(data, s)))
        i = data.find(needle, i + 1)
    return sorted(out)


def cut(data, chests):
    out, pos = bytearray(), 0
    for s, e, _p in chests:
        if s < pos:
            raise ChestError('internal: nested chests')
        out += data[pos:s]
        pos = e
    out += data[pos:]
    return bytes(out)


def text_files(data_dir):
    """relative paths of the .lua / .xml files that hold the chest's floating text"""
    found = []
    for root, dirs, files in os.walk(data_dir):
        dirs[:] = sorted(d for d in dirs if d != 'world')
        for name in sorted(files):
            if name.endswith(('.lua', '.xml')):
                try:
                    if TEXT in open(os.path.join(root, name), 'rb').read().lower():
                        found.append(os.path.relpath(os.path.join(root, name), data_dir).replace(os.sep, '/'))
                except OSError:
                    pass
    return found


def run(data_dir, dry=False, map_path=None, out=None, log=print):
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise ChestError('no world map in %s/world' % data_dir)
    data = open(map_path, 'rb').read()
    if data[:2] == b'\x1f\x8b':
        raise ChestError('the world map is compressed; unpack it first')
    chests = find_chests(data)
    summary = dict(chests=[c[2] for c in chests], script=False, text_files=[])
    for _s, _e, p in chests:
        log('starter chest (action id %d) at %d,%d,%d: removed' % ((CHEST_AID,) + p))
    if chests:
        new = cut(data, chests)
        if find_chests(new) or len(new) >= len(data):
            raise ChestError('internal: the patched map still holds the starter chest; nothing written')
        if out:
            open(out, 'wb').write(new)
            log('starter chest: %d removed, map written to %s' % (len(chests), out))
        elif dry:
            log('starter chest: would remove %d from the map' % len(chests))
        else:
            bak = map_path + '.bak'
            if not os.path.exists(bak):
                shutil.copyfile(map_path, bak)
                log('backup %s' % bak)
            tmp = map_path + '.tmp'
            open(tmp, 'wb').write(new)
            os.replace(tmp, map_path)
            log('starter chest: %d removed from %s' % (len(chests), map_path))
    else:
        log('starter chest: none on the map; nothing to do')
    src = os.path.join(data_dir, SCRIPT)
    if os.path.isfile(src):
        summary['script'] = True
        if dry:
            log('starter chest script: would disable %s' % SCRIPT)
        else:
            os.replace(src, src + OFF)
            log('starter chest script: %s disabled (renamed to %s)' % (SCRIPT, os.path.basename(src) + OFF))
    elif os.path.isfile(src + OFF):
        log('starter chest script: already disabled')
    else:
        log('starter chest script: %s not found' % SCRIPT)
    summary['text_files'] = text_files(data_dir)
    for rel in summary['text_files']:
        log('hint: %s still holds the text "Collect First Items" (not changed; check it by hand)' % rel)
    return summary


def main(argv):
    args, pos, i = {}, [], 0
    while i < len(argv):
        a = argv[i]
        if a == '--dry-run':
            args[a] = True
        elif a in ('--map', '--out'):
            if i + 1 >= len(argv):
                sys.exit('%s needs a value' % a)
            args[a] = argv[i + 1]
            i += 1
        elif a in ('-h', '--help'):
            print(__doc__)
            return 0
        elif a.startswith('-'):
            sys.exit('unknown option %s' % a)
        else:
            pos.append(a)
        i += 1
    if len(pos) != 1:
        print(__doc__)
        return 1
    try:
        run(pos[0], dry=args.get('--dry-run', False), map_path=args.get('--map'), out=args.get('--out'))
    except ChestError as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
