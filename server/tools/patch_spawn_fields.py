#!/usr/bin/env python3
"""The burning fire fields under nine base spawn entries become the small fire that does no damage (idempotent).

usage: python3 -I server/tools/patch_spawn_fields.py DATA_DIR [--dry-run] [--map FILE] [--out FILE]

Why (start log 2026-10-21, server/README.md "Spawns on fire fields"): since C7 no monster is immune to fire
(tools/monster_fire_resist.py, install step basemonsters). At start the engine places a spawn's monster with
Map::placeCreature, not forced: Tile::queryAdd refuses a monster a tile with a magic field that does damage of an element
it is not immune to, and the search then tries the 12 tiles around (extendedPos). Eight entries of three formerly
fire-immune monsters sit in fire lairs where the spot and every one of those tiles hold a burning fire field (1487,
1488) or block (wall, lava, hole), so each printed "Couldn't spawn monster" (twice: Spawn::spawnMonster(spawnBlock_t)
tries a one-monster block a second time when the first try fails). The respawn places them forced 60 s later anyway.
With the stock monsters (fire-immune) none of the eight fails; no other entry of the map fails this way (measured on
the base map and spawn file: TFS 1.4 placement rules, damaging fields only, 2026-10-21). A ninth spot, (32078, 32605,
5), is a neighbour of the eight whose own tile burns too: it found a free tile further out before, but once the eight
are free its search takes (32078, 32603) first (the inner ring is tried before the outer one) and the entry of that
tile ends up without a place (a simulation of the start order, 3000 runs: one entry failed every time without it,
none with it).

What changes: on the world map, a burning fire field (FIELD_FROM) on one of the SPOTS becomes FIELD_TO, the small fire
(items.xml type magicfield, field fire, no damage: MagicField::getDamage() is 0, so queryAdd lets every monster in).
Only the item id of those nodes is rewritten; the tile and everything else stay, the lair keeps its fire elsewhere.
The ids are checked in DATA_DIR/items/items.xml first (FIELD_FROM: fire fields with damage, FIELD_TO: a fire field
without), else nothing is written. A spot without a burning field is listed and left alone.

Idempotent: a second run finds no burning field on the spots and writes nothing. The map is written through
<map>.otbm.tmp and <map>.otbm.bak is written first when missing. --dry-run lists the fields and writes nothing; --out
FILE writes the patched map there instead. Exit 0 on success, 1 on a refusal. Python 3 standard library.
Test: tools/patch_spawn_fields_test.py (synthetic map).
"""
import os, re, shutil, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # python -I leaves the script's folder off sys.path

import gen_poi as G  # noqa: E402

FIELD_FROM = (1487, 1488)  # the burning fire fields of the base items.xml (initdamage / damage)
FIELD_TO = 1489            # the small fire: field fire without damage
# The base spawn entries that cannot be placed at start (absolute positions; measured 2026-10-21, see above), and the
# neighbour that would take one of their tiles
SPOTS = (
    (33085, 32589, 4), (33090, 32588, 4),
    (32076, 32603, 5), (32075, 32604, 5), (32078, 32603, 5), (32076, 32605, 5), (32079, 32610, 5),
    (33248, 31598, 12),
    (32078, 32605, 5),
)


class FieldError(Exception):
    pass


def fire_fields(items_xml):
    """{id: does damage} of every items.xml item of type magicfield with field fire"""
    out = {}
    text = open(items_xml, encoding='latin-1').read()
    for m in re.finditer(r'<item\b([^>]*?)(/?)>', text):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        body = '' if m.group(2) else text[m.end():text.find('</item>', m.end())]
        kv = re.findall(r'key="(\w+)"\s+value="([^"]*)"', body)
        keys = {k.lower(): v for k, v in kv}
        if keys.get('type', '').lower() != 'magicfield' or keys.get('field', '').lower() != 'fire':
            continue
        damage = any(k in keys and keys[k] not in ('', '0') for k in ('damage', 'initdamage'))
        if 'id' in a:
            ids = [int(a['id'])]
        elif 'fromid' in a and 'toid' in a:
            ids = range(int(a['fromid']), int(a['toid']) + 1)
        else:
            continue
        for i in ids:
            out[i] = damage
    return out


def check_items(items_xml, from_ids=FIELD_FROM, to_id=FIELD_TO):
    if not os.path.isfile(items_xml):
        raise FieldError('no %s' % items_xml)
    fields = fire_fields(items_xml)
    if fields.get(to_id) is not False:
        raise FieldError('%d is not a fire field without damage in %s; nothing changed' % (to_id, items_xml))
    for i in from_ids:
        if fields.get(i) is not True:
            raise FieldError('%d is not a fire field with damage in %s; nothing changed' % (i, items_xml))


def find_fields(data, ids, spots):
    """[(node offset, id, (x, y, z))] of every item node with one of these ids on one of these tiles"""
    spots, out = set(spots), []
    for iid in sorted(ids):
        needle = bytes([G.START, G.T_ITEM]) + G.esc(struct.pack('<H', iid))
        i = data.find(needle)
        while i >= 0:
            if G.real(data, i):
                parsed = G.parse_item(G.payload(data, i + 2))
                if parsed and parsed[0] == iid:
                    p = G.tile_position(data, i)
                    if p in spots:
                        out.append((i, iid, p))
            i = data.find(needle, i + 1)
    return out


def patch(data, hits, new_id):
    """the map bytes with the item id of these nodes set to new_id (the id is the node's first two payload bytes)"""
    out, pos = bytearray(), 0
    new = G.esc(struct.pack('<H', new_id))
    for off, iid, _p in sorted(hits):
        head = off + 2
        old = G.esc(struct.pack('<H', iid))
        if data[head:head + len(old)] != old:
            raise FieldError('internal: no item id at offset %d' % off)
        out += data[pos:head] + new
        pos = head + len(old)
    out += data[pos:]
    return bytes(out)


def run(data_dir, dry=False, map_path=None, out=None, spots=SPOTS, from_ids=FIELD_FROM, to_id=FIELD_TO, log=print):
    check_items(os.path.join(data_dir, 'items', 'items.xml'), from_ids, to_id)
    if map_path is None:
        import patch_base_towns
        map_path = patch_base_towns.map_path(data_dir)
    if not map_path or not os.path.isfile(map_path):
        raise FieldError('no world map in %s/world' % data_dir)
    data = open(map_path, 'rb').read()
    if data[:2] == b'\x1f\x8b':
        raise FieldError('the world map is compressed; unpack it first')
    hits = find_fields(data, from_ids, spots)
    for _off, iid, p in hits:
        log('fire field %d at %d,%d,%d -> %d' % ((iid,) + p + (to_id,)))
    done = {p for _o, _i, p in hits}
    for p in spots:
        if p not in done:
            log('no burning fire field at %d,%d,%d (already patched or not on this map)' % p)
    if not hits:
        log('spawn fields: nothing to do')
        return dict(changed=0, spots=[])
    new = patch(data, hits, to_id)
    if find_fields(new, from_ids, spots) or len(find_fields(new, (to_id,), spots)) < len(hits):
        raise FieldError('internal: the patched map does not hold the new fields; nothing written')
    summary = dict(changed=len(hits), spots=sorted(done))
    if dry and not out:
        log('spawn fields: would replace %d' % len(hits))
        return summary
    if out:
        open(out, 'wb').write(new)
        log('spawn fields: %d replaced in %s' % (len(hits), out))
        return summary
    bak = map_path + '.bak'
    if not os.path.exists(bak):
        shutil.copyfile(map_path, bak)
        log('backup %s' % bak)
    tmp = map_path + '.tmp'
    open(tmp, 'wb').write(new)
    os.replace(tmp, map_path)
    log('spawn fields: %d replaced in %s' % (len(hits), map_path))
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
    except FieldError as e:
        print('refused: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
