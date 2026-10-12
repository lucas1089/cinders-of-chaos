#!/usr/bin/env python3
"""Generated areas outside the server: OTBM pieces for the map editor, item checks against the live data, previews.

The areas come from the Lua generator itself (data/scripts/chaos/areagen_core.lua and areagen_config.lua), run by
LuaJIT through tools/areagen_dump.lua, so the server and these files always show the same tiles.

    python3 -I server/tools/areagen_export.py summary [--area ID] [--dark]
    python3 -I server/tools/areagen_export.py otbm OUT_DIR [--area ID] [--dark]
    python3 -I server/tools/areagen_export.py check ITEMS.otb ITEMS.xml Tibia.dat [--dark]
    python3 -I server/tools/areagen_export.py preview OUT_DIR ITEMS.otb ITEMS.xml Tibia.dat Tibia.spr [--area ID] [--dark]
                                              [--scale 0.5] [--sheet]

ID may also name a rift layout (rift_layout_core.lua): rift:<theme>:<band>:<seed>[:<kind>[:<floors>]], e.g.
"rift:Ashen Crypt:3:1234"; its minimap marks the sections the packs stand in (orange) and the arena (magenta).

summary  tiles, walkable tiles, monsters, density and the validator's problems per area.
otbm     OUT_DIR/<id>.otbm (OTBM 2, items 3.57, the live map's size, every tile of the area with its items; the exit
         portal carries its action id) and OUT_DIR/<id>-spawn.xml (the spawn points; packs on the free tiles next to
         them). Open the .otbm in the map editor, or import it into a copy of the world map to place it by hand.
         The server does not load these files: areagen.lua builds the same tiles at startup.
check    every item id the palettes can use (stock and, with --dark, the dark tile set): known in items.otb, a client
         id with an entry in Tibia.dat, the right kind (grounds are grounds, border pieces are borders, wall pieces
         walls, obstacles and lights block, lights give light, the hole changes the floor, the portal is a
         teleport). Exit code 1 on a problem.
preview  OUT_DIR/<id>_z<z>.jpg per floor drawn with the client sprites (tools/map/render.py, scaled), OUT_DIR/<id>_map.png
         in minimap colours with the spawns (red), the boss (magenta), holes (blue), ladders (cyan), the arrival
         (green) and the exit (white), and with --sheet OUT_DIR/contact_sheet.jpg of all of them.

summary and otbm need only LuaJIT; check and preview need numpy and Pillow (tools/map). Deterministic: the same
config gives the same bytes.
"""
import os, sys, struct, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.dirname(HERE)
ROOT = os.path.dirname(SERVER)
MAPTOOLS = os.path.join(ROOT, 'tools', 'map')

ITEMS_MAJOR, ITEMS_MINOR = 3, 57      # items.otb of the live server
MAP_W, MAP_H = 34800, 34200           # the live map's header size
ACTION_EXIT = 47951                   # areagen_config.lua aid.exit


# ------------------------------------------------------------------------------------------------ the model
def run_dump(area='all', dark=False, lua=None):
    lua = lua or os.environ.get('LUAJIT', 'luajit')
    args = [lua, 'tools/areagen_dump.lua', area] + (['dark'] if dark else [])
    out = subprocess.run(args, cwd=SERVER, check=True, capture_output=True, text=True).stdout
    return parse_dump(out)


def parse_dump(text):
    areas, cur = [], None
    for line in text.splitlines():
        if not line:
            continue
        k, rest = line[0], line[2:]
        p = rest.split(' ')
        if k == 'A':
            cur = dict(id=p[0], kind=p[1], origin=tuple(map(int, p[2:5])), w=int(p[5]), h=int(p[6]),
                       floors=int(p[7]), name=' '.join(p[8:]), floor_stats=[], tiles=[], spawns=[], boss=None,
                       links=[], problems=[], entrance=None)
            areas.append(cur)
        elif k == 'F':
            cur['floor_stats'].append(dict(z=int(p[0]), walkable=int(p[1]), hunt=int(p[2]), monsters=int(p[3])))
        elif k == 'T':
            v = list(map(int, p))
            cur['tiles'].append(dict(x=v[0], y=v[1], z=v[2], walk=v[3] == 1, ground=v[4], items=v[5:]))
        elif k == 'S':
            cur['spawns'].append(dict(x=int(p[0]), y=int(p[1]), z=int(p[2]), level=int(p[3]), count=int(p[4]),
                                      spawntime=int(p[5]), monster=' '.join(p[6:])))
        elif k == 'B':
            mon, shown = ' '.join(p[6:]).split('|', 1)
            cur['boss'] = dict(x=int(p[0]), y=int(p[1]), z=int(p[2]), level=int(p[3]), health=int(p[4]),
                               spawntime=int(p[5]), monster=mon, name=shown)
        elif k == 'L':
            v = list(map(int, p))
            cur['links'].append(dict(hole=tuple(v[0:3]), ladder=tuple(v[3:6]), up=tuple(v[6:9])))
        elif k == 'R':
            v = list(map(int, p))
            cur['arrival'], cur['exit'] = tuple(v[0:3]), tuple(v[3:6])
        elif k == 'E':
            v = list(map(int, p))
            cur['entrance'], cur['back'] = tuple(v[0:3]), tuple(v[3:6])
        elif k == 'X':
            cur['problems'].append(rest)
        elif k == 'Q':
            v = list(map(int, p))
            cur.setdefault('rooms', []).append(dict(x1=v[0], y1=v[1], x2=v[2], y2=v[3], z=v[4]))
        elif k == 'P':
            v = list(map(int, p))
            cur.setdefault('sections', []).append(dict(x=v[0], y=v[1], z=v[2], dist=v[3], cells=v[4]))
        elif k == 'W':
            v = list(map(int, p))
            cur['rift'] = dict(walkable=v[0], route=v[1], items=v[2])
        elif k == 'C':
            cur['checksum'] = int(p[0])
    return areas


# ------------------------------------------------------------------------------------------------ OTBM
def _esc(b):
    out = bytearray()
    for c in b:
        if c in (0xFD, 0xFE, 0xFF):
            out.append(0xFD)
        out.append(c)
    return bytes(out)


class Node:
    def __init__(self, kind, payload=b''):
        self.kind, self.payload, self.children = kind, payload, []

    def add(self, n):
        self.children.append(n)
        return n

    def write(self, out):
        out += b'\xFE' + _esc(bytes([self.kind]) + self.payload)
        for c in self.children:
            c.write(out)
        out += b'\xFF'


def _str_attr(attr, s):
    b = s.encode('latin-1', 'replace')
    return bytes([attr]) + struct.pack('<H', len(b)) + b


def otbm_bytes(area, spawn_name=None, description=None):
    """the OTBM file of one area (tiles grouped in 256 x 256 tile areas, sorted)"""
    root = Node(0, struct.pack('<IHHII', 2, MAP_W, MAP_H, ITEMS_MAJOR, ITEMS_MINOR))
    md = root.add(Node(2, _str_attr(1, description or ('Cinders of Chaos generated area: ' + area['name']))
                       + _str_attr(11, spawn_name or (area['id'] + '-spawn.xml'))
                       + _str_attr(13, area['id'] + '-house.xml')))
    tiles = sorted(area['tiles'], key=lambda t: (t['z'], t['y'] & 0xFF00, t['x'] & 0xFF00, t['y'], t['x']))
    cur_key, cur = None, None
    ex = area.get('exit')
    for t in tiles:
        key = (t['x'] & 0xFF00, t['y'] & 0xFF00, t['z'])
        if key != cur_key:
            cur_key = key
            cur = md.add(Node(4, struct.pack('<HHB', key[0], key[1], key[2])))
        tile = cur.add(Node(5, bytes([t['x'] & 0xFF, t['y'] & 0xFF]) + b'\x09' + struct.pack('<H', t['ground'])))
        for iid in t['items']:
            payload = struct.pack('<H', iid)
            if ex and (t['x'], t['y'], t['z']) == ex and iid == 1387:
                payload += b'\x04' + struct.pack('<H', ACTION_EXIT)
            tile.add(Node(6, payload))
    md.add(Node(12))
    md.add(Node(15))
    out = bytearray(b'\x00\x00\x00\x00')
    root.write(out)
    return bytes(out)


def read_otbm(data):
    """a small reader for the files written above (tests): {(x, y, z): [ground, item, ...]}, header tuple"""
    i, n = 4, len(data)
    stack, tiles, header = [], {}, None
    area_base = None
    cur_tile = None
    while i < n:
        c = data[i]
        if c == 0xFE:
            kind = data[i + 1]
            i += 2
            buf = bytearray()
            while i < n and data[i] not in (0xFE, 0xFF):
                if data[i] == 0xFD:
                    i += 1
                buf.append(data[i])
                i += 1
            stack.append(kind)
            if kind == 0:
                header = struct.unpack_from('<IHHII', buf, 0)
            elif kind == 4:
                area_base = struct.unpack_from('<HHB', buf, 0)
            elif kind == 5:
                x, y = area_base[0] + buf[0], area_base[1] + buf[1]
                cur_tile = (x, y, area_base[2])
                tiles[cur_tile] = [struct.unpack_from('<H', buf, 3)[0]] if len(buf) >= 5 and buf[2] == 9 else []
            elif kind == 6:
                tiles[cur_tile].append(struct.unpack_from('<H', buf, 0)[0])
        elif c == 0xFF:
            stack.pop()
            i += 1
        else:
            raise ValueError('bad OTBM byte at %d' % i)
    return tiles, header


def spawn_xml(area):
    """the spawn points as a map editor spawn file (packs on free walkable tiles next to the point)"""
    walk = {(t['x'], t['y'], t['z']) for t in area['tiles'] if t['walk']}
    lines = ['<?xml version="1.0"?>', '<spawns>']
    pts = list(area['spawns'])
    if area['boss']:
        b = dict(area['boss'])
        b['count'] = 1
        pts.append(b)
    for s in pts:
        used = []
        for dx, dy in ((0, 0), (1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            if len(used) >= s['count']:
                break
            if (s['x'] + dx, s['y'] + dy, s['z']) in walk:
                used.append((dx, dy))
        lines.append('\t<spawn centerx="%d" centery="%d" centerz="%d" radius="1">' % (s['x'], s['y'], s['z']))
        for dx, dy in used:
            lines.append('\t\t<monster name="%s" x="%d" y="%d" z="%d" spawntime="%d" />'
                         % (s['monster'], dx, dy, s['z'], max(10, s['spawntime'] or 60)))
        lines.append('\t</spawn>')
    lines.append('</spawns>')
    return '\n'.join(lines) + '\n'


# ------------------------------------------------------------------------------------------------ checks
def palette_ids(dark):
    """(id, role) pairs of every item the palettes may use, from the Lua config"""
    code = r'''
dofile("data/lib/chaos_dark_tiles.lua")
local cfg = dofile("data/scripts/chaos/areagen_config.lua")
local dark = arg[1] == "dark"
local function id(v) if type(v) == "number" then return v end return dark and ChaosDarkTiles.ids[v] or nil end
local seen = {}
local function put(v, role) local i = id(v) if i and not seen[i .. role] then seen[i .. role] = true print(i .. " " .. role) end end
for _, f in pairs(cfg.families) do for _, row in ipairs(f.grounds) do put(row[1], f.walk == false and "ground_block" or "ground") end end
for name, set in pairs(cfg.pieces) do local role = (name == "dirt_wall" or name == "gravel") and "edge_block" or "border" for _, v in pairs(set) do put(v, role) end end
for _, w in pairs(cfg.walls) do for _, rows in pairs(w) do for _, row in ipairs(rows) do put(row[1], "wall") end end end
local function theme(t)
  local d = t.decor or {}
  for _, row in ipairs(d.scatter or {}) do put(row[1], "decor") end
  for _, cl in ipairs(d.clusters or {}) do for _, row in ipairs(cl.items) do put(row[1], "decor") end end
  for _, row in ipairs(t.obstacles and t.obstacles.items or {}) do put(row[1], "obstacle") end
  for _, row in ipairs(t.lights and t.lights.items or {}) do put(row[1], "light") end
  for _, row in ipairs(t.props and t.props.items or {}) do put(row[1], "obstacle") end
end
local function themeAll(t)
  theme(t)
  for _, k in pairs(t.byKind or {}) do theme(k) end
end
for _, t in pairs(cfg.themes) do themeAll(t) if dark and t.dark then themeAll(t.dark) end end
put(cfg.items.hole, "hole") put(cfg.items.ladder, "ladder") put(cfg.items.portal, "portal")
'''
    lua = os.environ.get('LUAJIT', 'luajit')
    out = subprocess.run([lua, '-e', code.replace('arg[1]', '"%s"' % ('dark' if dark else ''))], cwd=SERVER,
                         check=True, capture_output=True, text=True).stdout
    return [(int(a), b) for a, b in (l.split() for l in out.splitlines() if l.strip())]


def check(items_otb, items_xml, dat, dark):
    sys.path.insert(0, MAPTOOLS)
    from itemdb import ItemDB, C
    db = ItemDB(items_otb, items_xml, dat)
    things = db.dat.items
    tele = set()
    import re
    s = open(items_xml, encoding='latin-1').read()
    for m in re.finditer(r'<item\b([^>]*?)(/?)>', s):
        if m.group(2):
            continue
        body = s[m.end():s.find('</item>', m.end())]
        if 'value="teleport"' not in body:
            continue
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        if 'id' in a:
            tele.add(int(a['id']))
        elif 'fromid' in a and 'toid' in a:
            tele.update(range(int(a['fromid']), int(a['toid']) + 1))
    bad = 0
    rows = palette_ids(dark)
    for iid, role in rows:
        why = []
        if not db.known[iid]:
            why.append('not in items.otb')
        else:
            c = int(db.cid[iid])
            if not c or c - 100 >= len(things):
                why.append('client id %d has no entry in Tibia.dat' % c)
            ground = db.group[iid] == 1 or db.dground[iid]
            if role.startswith('ground') and not ground:
                why.append('not a ground')
            if role == 'ground' and db.block[iid]:
                why.append('a walkable ground that blocks')
            if role == 'ground_block' and not db.block[iid]:
                why.append('a blocking ground that does not block')
            if role == 'border' and not (db.order[iid] == 1 or db.dclip[iid]):
                why.append('not a border (top order %d)' % db.order[iid])
            if role in ('edge_block', 'wall') and not db.block[iid]:
                why.append('a wall piece that does not block')
            if role in ('obstacle', 'light') and not db.block[iid] and role == 'obstacle':
                why.append('an obstacle that does not block')
            if role == 'light' and not db.light[iid]:
                why.append('gives no light')
            if role == 'decor' and db.block[iid]:
                why.append('walkable decoration that blocks')
            if role == 'hole' and not (db.floorchange[iid] or (db.flags[iid] >> 8) & 1):
                why.append('no floor change')
            if role == 'portal' and iid not in tele:
                why.append('not a teleport in items.xml')
        status = 'OK' if not why else 'BAD: ' + '; '.join(why)
        if why:
            bad += 1
        print('%6d %-12s %-28s %s' % (iid, role, db.name[iid][:28], status))
    print('%d ids, %d problem(s)' % (len(rows), bad))
    return bad == 0


# ------------------------------------------------------------------------------------------------ previews
class _ModelMap:
    """what tools/map/render.py needs: find(x, y, z) and stack(i)"""

    def __init__(self, area):
        self.stacks, self.index = [], {}
        for t in area['tiles']:
            self.index[(t['x'], t['y'], t['z'])] = len(self.stacks)
            self.stacks.append([t['ground']] + t['items'])

    def find(self, x, y, z):
        return self.index.get((x, y, z), -1)

    def stack(self, i):
        return self.stacks[i]


def _minimap_rgb(c):
    return ((c // 36) % 6 * 51, (c // 6) % 6 * 51, c % 6 * 51)


def preview(out_dir, items_otb, items_xml, dat, spr_path, area_id='all', dark=False, scale=0.5, sheet=False):
    sys.path.insert(0, MAPTOOLS)
    from PIL import Image, ImageDraw
    from itemdb import ItemDB
    from datspr import Spr
    import render as rd
    os.makedirs(out_dir, exist_ok=True)
    db = ItemDB(items_otb, items_xml, dat)
    spr = Spr(spr_path)
    shots = []
    for area in run_dump(area_id, dark):
        m = _ModelMap(area)
        ox, oy, oz = area['origin']
        for fl in area['floor_stats']:
            z = fl['z']
            img, miss = rd.render(m, db, spr, ox, oy, ox + area['w'] - 1, oy + area['h'] - 1, z)
            if scale != 1:
                img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
            path = os.path.join(out_dir, '%s_z%d.jpg' % (area['id'], z))
            img.save(path, quality=82)
            shots.append((path, '%s z%d' % (area['name'], z)))
            print(path, img.size, 'skipped items', miss)
        # minimap overview, every floor side by side, 4 px per tile
        px = 4
        W, H = area['w'] * px, area['h'] * px
        mm = Image.new('RGB', (W * len(area['floor_stats']) + 8 * (len(area['floor_stats']) - 1), H), (0, 0, 0))
        d = ImageDraw.Draw(mm)
        zs = [f['z'] for f in area['floor_stats']]
        for t in area['tiles']:
            k = zs.index(t['z'])
            col = (0, 0, 0)
            for iid in [t['ground']] + t['items']:
                c = int(db.minimap[iid])
                if c:
                    col = _minimap_rgb(c)
            if not t['walk'] and col == (0, 0, 0):
                col = (40, 40, 40)
            x0 = k * (W + 8) + (t['x'] - ox) * px
            y0 = (t['y'] - oy) * px
            d.rectangle([x0, y0, x0 + px - 1, y0 + px - 1], fill=col)

        def mark(p, col, r=2):
            if p and p[2] in zs:
                k = zs.index(p[2])
                cx = k * (W + 8) + (p[0] - ox) * px + px // 2
                cy = (p[1] - oy) * px + px // 2
                d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
        for s in area['spawns']:
            mark((s['x'], s['y'], s['z']), (230, 30, 30), 2 + s['count'])
        for s in area.get('sections', []):  # a rift layout: the sections packs stand in
            mark((s['x'], s['y'], s['z']), (255, 150, 30), 2)
        if area['boss']:
            b = area['boss']
            mark((b['x'], b['y'], b['z']), (230, 40, 230), 6)
        for l in area['links']:
            mark(l['hole'], (40, 90, 255), 4)
            mark(l['ladder'], (40, 230, 255), 4)
        mark(area['arrival'], (40, 230, 40), 5)
        mark(area['exit'], (255, 255, 255), 3)
        path = os.path.join(out_dir, '%s_map.png' % area['id'])
        mm.save(path)
        shots.append((path, '%s (minimap, all floors)' % area['name']))
        print(path, mm.size)
    if sheet:
        thumbs = []
        for path, label in shots:
            im = Image.open(path).convert('RGB')
            im.thumbnail((560, 440))
            thumbs.append((im, label))
        cols = 3
        cw, ch = 580, 480
        rows = (len(thumbs) + cols - 1) // cols
        sh = Image.new('RGB', (cols * cw, rows * ch), (24, 24, 28))
        d = ImageDraw.Draw(sh)
        for k, (im, label) in enumerate(thumbs):
            x, y = (k % cols) * cw + 10, (k // cols) * ch + 30
            sh.paste(im, (x, y))
            d.text((x, y - 22), label, fill=(235, 225, 200))
        path = os.path.join(out_dir, 'contact_sheet.jpg')
        sh.save(path, quality=85)
        print(path, sh.size)


# ------------------------------------------------------------------------------------------------ main
def _opt(args, name, default=None):
    if name in args:
        k = args.index(name)
        v = args[k + 1]
        del args[k:k + 2]
        return v
    return default


def main(argv):
    args = list(argv)
    dark = '--dark' in args
    if dark:
        args.remove('--dark')
    sheet = '--sheet' in args
    if sheet:
        args.remove('--sheet')
    area = _opt(args, '--area', 'all')
    scale = float(_opt(args, '--scale', '0.5'))
    if not args:
        print(__doc__)
        return 2
    cmd = args[0]
    if cmd == 'summary':
        ok = True
        for a in run_dump(area, dark):
            mons = sum(s['count'] for s in a['spawns'])
            walk = sum(f['walkable'] for f in a['floor_stats'])
            hunt = sum(f['hunt'] for f in a['floor_stats'])
            print('%-11s %-20s %-8s %3dx%-3d floors %d  tiles %6d  walkable %5d  monsters %3d (%d points) + boss %s  '
                  '%.2f per 100  links %d  checksum %d' % (a['id'], a['name'], a['kind'], a['w'], a['h'], a['floors'],
                                                          len(a['tiles']), walk, mons, len(a['spawns']),
                                                          a['boss']['name'] if a['boss'] else '-',
                                                          100.0 * mons / max(1, hunt), len(a['links']), a['checksum']))
            for p in a['problems']:
                ok = False
                print('   PROBLEM', p)
        return 0 if ok else 1
    if cmd == 'otbm':
        out = args[1]
        os.makedirs(out, exist_ok=True)
        for a in run_dump(area, dark):
            p = os.path.join(out, a['id'] + '.otbm')
            open(p, 'wb').write(otbm_bytes(a))
            open(os.path.join(out, a['id'] + '-spawn.xml'), 'w').write(spawn_xml(a))
            print(p, len(a['tiles']), 'tiles')
        return 0
    if cmd == 'check':
        return 0 if check(args[1], args[2], args[3], dark) else 1
    if cmd == 'preview':
        preview(args[1], args[2], args[3], args[4], args[5], area, dark, scale, sheet)
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
