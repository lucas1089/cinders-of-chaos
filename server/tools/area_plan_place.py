#!/usr/bin/env python3
"""Placing and installing a compiled planned area (area_planner.py place / install; docs/MAP_GUIDE.md "Area planner").

place    pastes a compiled area (OUT/<id>.otbm and its <id>.json manifest) into a COPY of a world map at given
         coordinates: every tile, item and attribute shifted, teleport destinations inside the area shifted with it.
         It refuses when a tile of the area lands on a tile the world already has, and it never writes the world file
         itself (the output must be another path). The view frame (OUT/<id>-frame.otbm) goes in only where the world
         has no tile. With the world's spawn file it writes a copy with the area's spawn
         blocks shifted and added, and it rewrites the ORIGIN of the area's chest script to the new place. The owner opens
         the copy in the map editor, or uses it as the server's map after a review.
install  copies the area's server files (OUT/data/...: the chest script, new NPCs) into a server's data folder.
         Idempotent: a file that is already there with the same text is left alone; a different file of the same
         name, or another planned area's chest script that uses the same action id or storages, stops it.
Python 3 standard library and numpy (tools/map/otbm.py reads the world).
"""
import json, os, re, shutil, struct, sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import area_plan_compile as PC
import areagen_export as AX

T_TOWNS = 12


class PlaceError(Exception):
    pass


def _markers(a):
    """raw offsets of the unescaped node markers, whether each starts a node, and the depth after it"""
    fd = np.flatnonzero(a == 0xFD)
    escaped = np.zeros(len(a) + 1, bool)
    if len(fd):
        new_run = np.ones(len(fd), bool)
        new_run[1:] = fd[1:] != fd[:-1] + 1
        run_start = fd[new_run][np.cumsum(new_run) - 1]
        esc = fd[((fd - run_start) & 1) == 0]
        escaped[esc + 1] = True
    mk = np.flatnonzero(((a == 0xFE) | (a == 0xFF)) & ~escaped[:len(a)])
    mk = mk[mk >= 4]
    is_start = a[mk] == 0xFE
    depth = np.cumsum(np.where(is_start, 1, -1))
    return mk, is_start, depth


def insertion_point(data):
    """raw offset where new tile area nodes go: before the towns node of the map data, else before its end"""
    a = np.frombuffer(data, np.uint8)
    mk, is_start, depth = _markers(a)
    for k in np.flatnonzero(is_start & (depth == 3)):
        if a[mk[k] + 1] == T_TOWNS:
            return int(mk[k])
    ends = np.flatnonzero(~is_start & (depth == 1))
    if not len(ends):
        raise PlaceError('the world file has no map data node')
    return int(mk[ends[0]])


def area_nodes(tiles):
    """the escaped bytes of tile area nodes holding these tiles (the planner's OTBM writer)"""
    out = bytearray()
    keys = sorted(tiles, key=lambda t: (t[2], t[1] & 0xFF00, t[0] & 0xFF00, t[1], t[0]))
    cur_key, cur, nodes = None, None, []
    for k in keys:
        t = tiles[k]
        akey = (k[0] & 0xFF00, k[1] & 0xFF00, k[2])
        if akey != cur_key:
            cur_key = akey
            cur = AX.Node(4, struct.pack('<HHB', akey[0], akey[1], akey[2]))
            nodes.append(cur)
        payload = bytes([k[0] & 0xFF, k[1] & 0xFF])
        if t['flags']:
            payload += bytes([PC.ATTR_TILE_FLAGS]) + struct.pack('<I', t['flags'])
        payload += bytes([PC.ATTR_ITEM]) + struct.pack('<H', t['ground'])
        node = cur.add(AX.Node(5, payload))
        for iid, attrs in t['items']:
            p = struct.pack('<H', iid)
            if attrs.get('aid'):
                p += bytes([PC.ATTR_ACTION]) + struct.pack('<H', attrs['aid'])
            if attrs.get('uid'):
                p += bytes([PC.ATTR_UNIQUE]) + struct.pack('<H', attrs['uid'])
            if attrs.get('tele'):
                p += bytes([PC.ATTR_TELE]) + struct.pack('<HHB', *attrs['tele'])
            node.add(AX.Node(6, p))
    for n in nodes:
        n.write(out)
    return bytes(out)


def shifted(tiles, manifest, at):
    """the area's tiles moved so its top-left tile of floor 1 lands on `at`"""
    ox, oy, oz = manifest['origin']
    dx, dy, dz = at[0] - ox, at[1] - oy, at[2] - oz
    xs = [k[0] for k in tiles]
    ys = [k[1] for k in tiles]
    zs = [k[2] for k in tiles]
    box = (min(xs), min(ys), min(zs), max(xs), max(ys), max(zs))
    inside = lambda p: box[0] <= p[0] <= box[3] and box[1] <= p[1] <= box[4] and box[2] <= p[2] <= box[5]
    out = {}
    for (x, y, z), t in tiles.items():
        items = []
        for iid, attrs in t['items']:
            a = dict(attrs)
            if a.get('tele') and inside(a['tele']):
                a['tele'] = (a['tele'][0] + dx, a['tele'][1] + dy, a['tele'][2] + dz)
            items.append((iid, a))
        nz = z + dz
        if not 0 <= nz <= 15 or not 0 <= x + dx <= 65535 or not 0 <= y + dy <= 65535:
            raise PlaceError('the area does not fit at %s: floor %d would be %d' % (at, z, nz))
        out[(x + dx, y + dy, nz)] = dict(ground=t['ground'], items=items, flags=t['flags'])
    return out, (dx, dy, dz)


def shift_spawns(xml, d):
    def f(m):
        return '<spawn centerx="%d" centery="%d" centerz="%d"' % (int(m.group(1)) + d[0], int(m.group(2)) + d[1],
                                                                  int(m.group(3)) + d[2])
    xml = re.sub(r'<spawn centerx="(\d+)" centery="(\d+)" centerz="(\d+)"', f, xml)
    return re.sub(r'(<(?:monster|npc)\b[^>]*\bz=")(\d+)"', lambda m: '%s%d"' % (m.group(1), int(m.group(2)) + d[2]), xml)


def place(area_otbm, world_otbm, out_otbm, at, world_spawn=None, out_spawn=None, log=print):
    """paste the area into a copy of the world; returns a summary dict. Never writes world_otbm."""
    if os.path.realpath(out_otbm) == os.path.realpath(world_otbm):
        raise PlaceError('the output must be a copy, not the world map itself')
    if world_spawn and out_spawn and os.path.realpath(out_spawn) == os.path.realpath(world_spawn):
        raise PlaceError('the spawn output must be a copy, not the world spawn file itself')
    man_path = area_otbm[:-5] + '.json'
    manifest = json.load(open(man_path, encoding='utf-8'))
    _h, tiles, problems = PC.read_otbm_full(open(area_otbm, 'rb').read())
    if problems:
        raise PlaceError('the area file is not a planner OTBM: %s' % problems[0])
    moved, d = shifted(tiles, manifest, at)
    sys.path.insert(0, os.path.join(PC.C.ROOT, 'tools', 'map'))
    from otbm import load_otbm
    world = load_otbm(world_otbm)
    key = (world.tiles['z'].astype(np.int64) << 32) | (world.tiles['y'].astype(np.int64) << 16) | world.tiles['x'].astype(np.int64)
    mine = np.array(sorted((z << 32) | (y << 16) | x for x, y, z in moved), np.int64)
    clash = np.intersect1d(key, mine)
    if len(clash):
        c = int(clash[0])
        raise PlaceError('%d tile(s) of the area land on tiles the world map has (first %d,%d,%d); pick other coordinates'
                         % (len(clash), c & 0xFFFF, (c >> 16) & 0xFFFF, c >> 32))
    # tiles of the world right next to the area: the area's rock rim then meets them (a warning only)
    ring = set()
    for x, y, z in moved:
        for ddx in (-1, 0, 1):
            for ddy in (-1, 0, 1):
                n = (x + ddx, y + ddy, z)
                if n not in moved:
                    ring.add((n[2] << 32) | (n[1] << 16) | n[0])
    touching = len(np.intersect1d(key, np.array(sorted(ring), np.int64)))
    # the view frame (<id>-frame.otbm): bare rock where a player of the area would see void, only where the world has
    # no tile (it never replaces one)
    frame = {}
    fp = area_otbm[:-5] + '-frame.otbm'
    if os.path.isfile(fp):
        _h, ftiles, problems = PC.read_otbm_full(open(fp, 'rb').read())
        if problems:
            raise PlaceError('the view frame is not a planner OTBM: %s' % problems[0])
        fmoved = {(x + d[0], y + d[1], z + d[2]): t for (x, y, z), t in ftiles.items()}
        fmoved = {p: t for p, t in fmoved.items() if p not in moved}
        if fmoved:
            fk = np.array(sorted((z << 32) | (y << 16) | x for x, y, z in fmoved), np.int64)
            taken = set(int(c) for c in np.intersect1d(key, fk))
            frame = {p: t for p, t in fmoved.items() if ((p[2] << 32) | (p[1] << 16) | p[0]) not in taken}
    allt = dict(moved)
    allt.update(frame)
    data = open(world_otbm, 'rb').read()
    if data[:2] == b'\x1f\x8b':
        raise PlaceError('the world map is compressed; unpack it first')
    k = insertion_point(data)
    with open(out_otbm, 'wb') as f:
        f.write(data[:k])
        f.write(area_nodes(allt))
        f.write(data[k:])
    check = load_otbm(out_otbm)
    if len(check.tiles['x']) != len(world.tiles['x']) + len(allt):
        raise PlaceError('the copy holds %d tiles, %d expected' % (len(check.tiles['x']), len(world.tiles['x']) + len(allt)))
    out = dict(tiles=len(moved), frame=len(frame), shift=d, world_tiles=len(world.tiles['x']), touching=touching, out=out_otbm)
    if manifest.get('kind') == 'dungeon' and at[2] <= 7 and not manifest['stats'].get('roof_tiles'):
        out['roof'] = ('the area was compiled underground and has no roof; set "origin" in the plan to z %d and '
                       'compile again for a roof over floors above ground' % at[2])
    if world_spawn and out_spawn:
        text = open(world_spawn, encoding='latin-1').read()
        ours = open(area_otbm[:-5] + '-spawn.xml', encoding='latin-1').read()
        blocks = re.findall(r'\t<spawn\b.*?</spawn>\n', shift_spawns(ours, d), re.S)
        cut = text.rfind('</spawns>')
        if cut < 0:
            raise PlaceError('the world spawn file has no </spawns>')
        open(out_spawn, 'w', encoding='latin-1').write(text[:cut] + ''.join(blocks) + text[cut:])
        out['spawn_blocks'] = len(blocks)
    # the chest script follows the area
    src = os.path.join(os.path.dirname(area_otbm), 'data', 'scripts', 'chaos_areaplan', manifest['id'] + '_chests.lua')
    if os.path.isfile(src):
        dst_dir = os.path.join(os.path.dirname(os.path.abspath(out_otbm)), 'data', 'scripts', 'chaos_areaplan')
        os.makedirs(dst_dir, exist_ok=True)
        text = re.sub(r'local ORIGIN = \{x = \d+, y = \d+, z = \d+\}',
                      'local ORIGIN = {x = %d, y = %d, z = %d}' % tuple(at), open(src, encoding='utf-8').read())
        open(os.path.join(dst_dir, manifest['id'] + '_chests.lua'), 'w', encoding='utf-8').write(text)
        out['chest_script'] = os.path.join(dst_dir, manifest['id'] + '_chests.lua')
    return out


def _ids_of(text):
    aid = re.search(r'action:aid\((\d+)\)', text)
    return (int(aid.group(1)) if aid else None), set(int(s) for s in re.findall(r'storage = (\d+)', text))


def _chest_scripts(out_dir):
    """{file name: text} of the chest scripts under OUT/data/scripts/chaos_areaplan/"""
    d = os.path.join(out_dir, 'data', 'scripts', 'chaos_areaplan')
    if not os.path.isdir(d):
        return {}
    return {f: open(os.path.join(d, f), encoding='utf-8').read() for f in sorted(os.listdir(d)) if f.endswith('_chests.lua')}


def _clash(name, ids, others):
    aid, sts = ids
    for f, (a2, s2) in sorted(others.items()):
        if f == name:
            continue
        if aid is not None and a2 == aid:
            raise PlaceError('%s uses action id %d like %s; set "chest_action" in the plan' % (name, aid, f))
        if sts & s2:
            raise PlaceError('%s shares storage %s with %s; rename the quest key' % (name, sorted(sts & s2)[0], f))


def _installed_ids(server_dir):
    plan_dir = os.path.join(server_dir, 'data', 'scripts', 'chaos_areaplan')
    others = {}
    if os.path.isdir(plan_dir):
        for f in sorted(os.listdir(plan_dir)):
            if f.endswith('_chests.lua'):
                others[f] = _ids_of(open(os.path.join(plan_dir, f), encoding='utf-8').read())
    return others


def check_batch(out_dirs, server_dir):
    """refuse (PlaceError) before anything is written when the chest scripts of several compiled areas share an
    action id or a storage with each other or with a chest script already installed (one of the batch's own files,
    installed by an earlier run, stands for itself and is left out). install() alone only sees what is installed,
    so a clash between two new areas got through a dry run and stopped a real run after the map was written."""
    batch = {}
    for d in out_dirs:
        for f, text in _chest_scripts(d).items():
            batch[f] = _ids_of(text)
    others = {f: v for f, v in _installed_ids(server_dir).items() if f not in batch}
    seen = {}
    for f, ids in sorted(batch.items()):
        _clash(f, ids, others)
        _clash(f, ids, seen)
        seen[f] = ids


def install(out_dir, server_dir, dry_run=False, log=print):
    """copy OUT/data/... into SERVER/data/...; returns the list of (action, path)"""
    data_src = os.path.join(out_dir, 'data')
    data_dst = os.path.join(server_dir, 'data')
    if not os.path.isdir(data_dst):
        raise PlaceError('%s has no data folder' % server_dir)
    if not os.path.isdir(data_src):
        return []
    todo = []
    for root, _dirs, files in os.walk(data_src):
        for f in sorted(files):
            src = os.path.join(root, f)
            todo.append((src, os.path.join(data_dst, os.path.relpath(src, data_src))))
    # other planned areas' chest scripts: no shared action id or storage
    others = _installed_ids(server_dir)
    done = []
    for src, dst in todo:
        text = open(src, encoding='utf-8').read()
        name = os.path.basename(dst)
        if name.endswith('_chests.lua'):
            _clash(name, _ids_of(text), others)
        if os.path.exists(dst):
            if open(dst, encoding='utf-8').read() == text:
                done.append(('same', dst))
                continue
            if not name.endswith('_chests.lua'):
                raise PlaceError('%s exists with other content; not overwritten' % dst)
        done.append(('write', dst))
        if not dry_run:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
    for act, p in done:
        log('%-5s %s' % (act if not dry_run or act == 'same' else 'would', p))
    return done
