#!/usr/bin/env python3
"""The live cast relay (server/README.md "Live spectator", phases 2 and 3; docs/ADMIN_APP.md "Assistir jogador").

The engine (src-patch 0064) mirrors the game messages of one player to a port on 127.0.0.1 (config.lua castPort):
u16 length + one message body per frame, plain 10.98 protocol as our client reads it. This tool reads that port, keeps
the world the client would keep (map, creatures, the player's stats) and writes JSON lines for the admin app on
stdout. chaos-ctl.sh cast NAME runs it over the app's ssh channel; it stops when stdin closes, when stdout breaks or
after --max-seconds.

    python3 -I server/tools/cast_relay.py --port 7179 --dat P/Tibia.dat --spr P/Tibia.spr [--otb SERVER/items.otb]
        [--name NAME] [--max-seconds 1800]

Lines (each a JSON object with "t"):
  wait     {"t":"wait","why":...}: no view yet (port closed, target offline, another target); it tries again each second
  hello    {"t":"hello","id","name","aware":[w,h]}: a new view starts
  spr      a sprite sheet, before the first line that uses it, once per run: "k" i (item), o (outfit, coloured),
           e (effect), m (missile); "key"; "png" base64; cell "cw","ch"; anchor "ax","ay" (the cell's top-left from the
           tile's top-left); items / effects / missiles: "np" patterns (rows), "nf" frames (columns), "fd" ms per
           frame; outfits: rows north, east, south, west; "ni" idle then "nw" walking frames (columns), "fd"
  full     the whole view: "c" [x, y, z] the camera, "tiles", "cr", "st", "light"; protocol 3: "fl" [first, last]
           (the floors the client draws), "ft" (tiles of the other floors)
  d        changes since the last line (at most ~20 a second): "c", "tiles", "cr", "walk", "fx", "mi", "tx", "say",
           "st", "light", only the keys that changed; protocol 3: "fl" (when the range changed), "fc" (floors that
           came into view whole: forget their tiles first), "ft", "fxf", "mif" (effects / missiles of other floors)
  sprerr   {"t":"sprerr","key","why"}: a sheet that could not be drawn (the pair lacks the thing, the MAX_SHEETS
           limit, or the error text); the app counts them and says so instead of showing black
  hb       nothing happened for a second
  end      {"t":"end","why"}: the relay stops
Protocol 3 (phase 3, the hello's "v"; older lines are read as 2): every addition is a new key, so an older app keeps
working. "ft" tiles are [z, x, y, under, over, elevation] (an empty tile clears the app's) for the floors in "fl" and
the cells the app can show: floor f is drawn (camera z - f) tiles up and left. An effect on another floor is
[x, y, sheet key, pattern, z], a missile [fx, fy, tx, ty, key, pattern, ms, z]. Light: the "light" key [intensity,
colour], a creature's "lt" [intensity, colour] (absent: none), an item / effect / missile sheet's "lt" when it shines
and "gr" 1 on a ground. The floors follow the client's rule for floors covered by a roof or ceiling (World.floors).
A tile is [x, y, under, over, elevation] on the camera's floor: under / over are lists of [sheet key, pattern, lift]
in drawing order (ground, borders, bottom, common items oldest first; then the creatures; then the top items). A
creature is {"n","hp","d","o" (outfit sheet key or null),"p" [x, y, z] or null,"sk","sh","ty","sp"}. A walk is
[id, from x, from y, to x, to y, ms]; an effect [x, y, sheet key, pattern]; a missile [fx, fy, tx, ty, key, pattern,
ms]; a number [x, y, colour 0-215, text]; speech [x, y, type, name, text].

The parser follows our client (protocolgameparse.cpp of the client base): the same floors, the same stack rules, the
same feature set (thing marks, item phases, our item attributes and typed numbers when the hello frame says so,
outfit wings / aura / shader with the client version marker). An unknown opcode ends that frame; a broken frame
(read past its end, an unknown thing) starts the view again (a new connection). Bounded everywhere: a frame is at most
65535 bytes, a tile 10 things, the map the aware range on 16 floors, the sheets of one run 600.

Needs python3-numpy and python3-pil (sprites drawn with client/tools/sprites/datspr.py and the outfit colour maths of
website/tools/gen_sprite_images.py). Tests: cast_relay_test.py (synthetic frames for every opcode, sheets, fuzz).
"""
import argparse
import base64
import io
import json
import math
import os
import select
import socket
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'client', 'tools', 'sprites'))
sys.path.insert(0, os.path.join(REPO, 'website', 'tools'))

PROTOCOL = 3            # the hello line's "v": 2 = phase 2 (camera floor only); 3 adds floors, light, other-floor effects
MAX_THINGS = 10
SEA_FLOOR = 7
UNDERGROUND = 8
AWARE_UNDER = 2
MAX_Z = 15
MAX_SHEETS = 4000       # sheets per run; a death trip to the temple with every floor in view passed 600 (2026-10-29)
MAX_CELLS = 256
FLUSH_MS = 50
CREATURE_OPS = (0x61, 0x62, 0x63)
FLAG_STACKABLE = 1 << 7
FLAG_ANIMATION = 1 << 24
GROUP_SPLASH, GROUP_FLUID = 11, 12
QUIVER_CATEGORY = 25
# the client's colour of a fluid byte (GameNewFluids: the byte is read as a fluid kind)
NEW_FLUID = (0, 1, 7, 3, 3, 2, 4, 3, 5, 6, 7, 2, 5, 3, 5, 6, 3, 3)
PUBLIC_TALK = (1, 3, 36, 37)


class ParseError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ reading
class Msg:
    __slots__ = ('b', 'p')

    def __init__(self, body, pos=0):
        self.b = body
        self.p = pos

    def left(self):
        return len(self.b) - self.p

    def need(self, n):
        if self.p + n > len(self.b):
            raise ParseError('read past the end of the frame')

    def u8(self):
        self.need(1)
        v = self.b[self.p]
        self.p += 1
        return v

    def u16(self):
        self.need(2)
        v = self.b[self.p] | (self.b[self.p + 1] << 8)
        self.p += 2
        return v

    def peek16(self):
        self.need(2)
        return self.b[self.p] | (self.b[self.p + 1] << 8)

    def u32(self):
        self.need(4)
        v = struct.unpack_from('<I', self.b, self.p)[0]
        self.p += 4
        return v

    def u64(self):
        self.need(8)
        v = struct.unpack_from('<Q', self.b, self.p)[0]
        self.p += 8
        return v

    def skip(self, n):
        self.need(n)
        self.p += n

    def text(self, limit=4096):
        n = self.u16()
        if n > limit:
            raise ParseError('string too long')
        self.need(n)
        s = bytes(self.b[self.p:self.p + n]).decode('latin-1')
        self.p += n
        return s

    def pos(self):
        return (self.u16(), self.u16(), self.u8())


# ------------------------------------------------------------------------------------------------ thing types
class ItemType:
    """what the relay needs of one client item: stack priority, wire bytes, pattern rules, elevation, ground speed"""
    __slots__ = ('prio', 'sub', 'phase', 'stack', 'fluid', 'elev', 'speed', 'block', 'dont_hide', 'light')

    def __init__(self, prio=5, sub=False, phase=False, stack=False, fluid=False, elev=0, speed=0, block=False,
                 dont_hide=False, light=None):
        self.prio, self.sub, self.phase, self.stack, self.fluid = prio, sub, phase, stack, fluid
        self.elev, self.speed = elev, speed
        self.block, self.dont_hide, self.light = block, dont_hide, light    # blocks the view / is never hidden / [i, c]


def light_of(flags):
    """[intensity, colour] of a dat thing that shines (the client's light flag), else None"""
    v = flags.get('light')
    if not v:
        return None
    try:
        i, c = int(v[0]), int(v[1])
    except (TypeError, ValueError, IndexError):
        return None
    return [min(i, 255), min(c, 255)] if i > 0 else None


def item_types(dat, otb_nodes=None):
    """{client id: ItemType} from the dat (the client's rules); with items.otb nodes [(server id, client id, group,
    flags)] the count / phase bytes follow the server (the two agree when server/tools/check_item_wire.py passes)."""
    out = {}
    for t in dat.items:
        f = t.flags
        if 'ground' in f:
            prio = 0
        elif 'clip' in f:
            prio = 1
        elif 'bottom' in f:
            prio = 2
        elif 'top' in f:
            prio = 3
        else:
            prio = 5
        market = f.get('market')
        quiver = market is not None and market[0] == QUIVER_CATEGORY   # base patch 0174: no hard-coded quiver ids
        stack = 'stackable' in f
        fluid = 'fluid' in f or 'splash' in f
        out[t.id] = ItemType(prio, stack or quiver or fluid, t.phases > 1, stack, fluid and not stack,
                             int(f.get('elevation', 0) or 0), int(f.get('ground', 0) or 0) if 'ground' in f else 0,
                             'blockmissile' in f, 'donthide' in f, light_of(f))
    if otb_nodes:
        seen = set()
        for _sid, cid, group, flags in otb_nodes:
            it = out.get(cid)
            if not cid or it is None or cid in seen:
                continue
            seen.add(cid)
            it.sub = bool(flags & FLAG_STACKABLE or group in (GROUP_SPLASH, GROUP_FLUID))
            it.phase = bool(flags & FLAG_ANIMATION)
    return out


def otb_nodes(path):
    try:
        from install_gems import scan
        kids, _ = scan(open(path, 'rb').read())
        return [(k[2], k[3], k[4], k[5]) for k in kids]
    except Exception:   # noqa: BLE001 - a broken otb: the dat's rules
        return None


# ------------------------------------------------------------------------------------------------ the world
def step_ms(speed_half, ground, diagonal, player):
    """the server's step duration (patch 0018) for a creature of wire speed speed_half on a ground of that speed"""
    calc = math.floor(857.36 * math.log(max(0, speed_half) + 261.29) - 4795.01 + 0.5)
    calc = max(1, calc)
    ms = (1000 * (ground or 150)) // calc
    if diagonal:
        ms = ms * 7 // 5 if player else ms * 3 // 2
    step = 10 if player else 50
    return max(step, min(5000, int(-(-ms // step) * step)))


def facing4(d):
    """the column of a creature's direction byte in the viewer's four-direction looks: the client's diagonals
    (4 north-east, 5 south-east, 6 south-west, 7 north-west; server src-patch 0077 sends them) draw east or west, as the
    client draws a look without diagonal columns"""
    if d <= 3:
        return d
    return 1 if d in (4, 5) else 3


def missile_pattern(fx, fy, tx, ty):
    """(x, y) pattern of a missile flying from (fx, fy) to (tx, ty): the client's eight directions"""
    dx, dy = tx - fx, ty - fy
    if dx == 0 and dy == 0:
        return 1, 1
    a = math.degrees(math.atan2(-dy, dx)) % 360
    if a < 22.5 or a >= 337.5:
        return 2, 1     # east
    if a < 67.5:
        return 2, 0     # north-east
    if a < 112.5:
        return 1, 0     # north
    if a < 157.5:
        return 0, 0     # north-west
    if a < 202.5:
        return 0, 1     # west
    if a < 247.5:
        return 0, 2     # south-west
    if a < 292.5:
        return 1, 2     # south
    return 2, 2         # south-east


def stack_xy(count):
    if count <= 0:
        return 0, 0
    if count < 5:
        return count - 1, 0
    for i, n in enumerate((10, 25, 50)):
        if count < n:
            return i, 1
    return 3, 1


class World:
    """the client's map and creatures for one view; changes collected for the next line"""

    def __init__(self, items, dims=None):
        self.items = items              # {client id: ItemType}
        self.dims = dims or {}          # {client id: (px, py, pz)} for the item patterns
        self.player = 0
        self.name = ''
        self.marker = 0
        self.attrs = False
        self.impact = False
        self.aware = (17, 13)
        self.central = None
        self.tiles = {}
        self.creatures = {}
        self.stats = None
        self.light = None
        self.reset_changes()
        self.full = False

    # -------------------------------------------------------- changes
    def reset_changes(self):
        self.ch_tiles = set()
        self.ch_cr = set()
        self.walks = []
        self.fx = []
        self.mi = []
        self.tx = []
        self.say = []
        self.ch_ftiles = set()      # changed tiles on the other floors
        self.fxf = []               # effects and missiles on the other floors (phase 3)
        self.mif = []
        self.ch_stats = False
        self.ch_light = False
        self.ch_central = False

    def dirty(self):
        return bool(self.full or self.ch_tiles or self.ch_cr or self.walks or self.fx or self.mi or self.tx
                    or self.say or self.ch_stats or self.ch_light or self.ch_central or self.ch_ftiles or self.fxf
                    or self.mif)

    def touch(self, pos):
        if self.central is None:
            return
        if pos[2] == self.central[2]:
            self.ch_tiles.add(pos)
        elif len(self.ch_ftiles) < 20000:
            self.ch_ftiles.add(pos)

    # -------------------------------------------------------- the floors the client draws (phase 3)
    def last_floor(self):
        """the lowest floor drawn: 7 above ground, two below the camera underground"""
        z = self.central[2]
        return SEA_FLOOR if z <= SEA_FLOOR else min(MAX_Z, z + AWARE_UNDER)

    def limits_view(self, pos, free):
        """Tile::limitsFloorsView of the client: does this tile hide the floors under it? free: the tile is seen
        through an opening, so only a ground counts; else a ground or a bottom item (walls, window frames) does. A
        thing marked don't-hide never does."""
        for th in self.tiles.get(pos) or ():
            if th[0] != 'i':
                continue
            it = self.items.get(th[1])
            if it is None or it.dont_hide:
                continue
            if it.prio == 0 or (not free and it.prio == 2):
                return True
        return False

    def look_possible(self, pos):
        st = self.tiles.get(pos)
        if not st:
            return False
        return not any(th[0] == 'i' and self.items.get(th[1]) is not None and self.items[th[1]].block for th in st)

    def first_floor(self):
        """the highest floor drawn (MapView::calcFirstVisibleFloor of the client): floor 0 above ground (two above
        the camera underground), raised for every floor a roof or ceiling closes over the camera or the open tiles
        beside it. Each floor up, the tile physically above stays put and the tile geometrically above moves one
        east and one south."""
        cx, cy, cz = self.central
        first = 0 if cz <= SEA_FLOOR else max(0, cz - AWARE_UNDER)
        for ix in (-1, 0, 1):
            for iy in (-1, 0, 1):
                if first >= cz:
                    return cz
                if not ((ix == 0 and iy == 0) or (abs(ix) != abs(iy) and self.look_possible((cx + ix, cy + iy, cz)))):
                    continue
                look = self.look_possible((cx + ix, cy + iy, cz))
                px, py = cx + ix, cy + iy
                k = 0
                while True:
                    k += 1
                    if cz - k < 0 or cz - k < first:
                        break
                    if self.limits_view((px, py, cz - k), not look):
                        first = cz - k + 1
                        break
                    if self.limits_view((px + k, py + k, cz - k), look):
                        first = cz - k + 1
                        break
        return min(first, cz)

    def floors(self):
        """[first, last]: the floors the client draws, the camera's among them"""
        return [self.first_floor(), self.last_floor()]

    # -------------------------------------------------------- aware range
    def left(self):
        return self.aware[0] // 2

    def right(self):
        return 1 + self.aware[0] // 2

    def top(self):
        return self.aware[1] // 2

    def bottom(self):
        return 1 + self.aware[1] // 2

    def horizontal(self):
        return self.aware[0] + 1

    def vertical(self):
        return self.aware[1] + 1

    def set_central(self, pos):
        if self.central is None or pos[2] != self.central[2]:
            self.full = True
        if pos != self.central:
            self.central = pos
            self.ch_central = True
            self.prune()

    def prune(self):
        """tiles far out of the aware range go (the client keeps more; the view never shows them)"""
        if len(self.tiles) < 4 * self.horizontal() * self.vertical() * 8:
            return
        cx, cy, _cz = self.central
        mx, my = self.horizontal() + 8, self.vertical() + 8
        for p in [p for p in self.tiles if abs(p[0] - cx) > mx or abs(p[1] - cy) > my]:
            self.clean(p)

    # -------------------------------------------------------- tiles
    def clean(self, pos):
        st = self.tiles.pop(pos, None)
        if st:
            for th in st:
                if th[0] == 'c':
                    c = self.creatures.get(th[1])
                    if c is not None and c.get('p') == pos:
                        c['p'] = None
                        self.ch_cr.add(th[1])
            self.touch(pos)

    def prio(self, th):
        if th[0] == 'c':
            return 4
        it = self.items.get(th[1])
        return it.prio if it else 5

    def add(self, th, pos, stackpos):
        """Tile::addThing of the client: stackpos -1 / 255 detects the place, -2 appends"""
        st = self.tiles.setdefault(pos, [])
        if th[0] == 'c':
            c = self.creatures.get(th[1])
            old = c.get('p') if c else None
            if old is not None and old != pos:
                self.remove_creature_from(old, th[1])
        if stackpos < 0 or stackpos == 255:
            pr = self.prio(th)
            if stackpos == -2:
                append = True
            else:
                append = pr <= 3
                if pr == 4:
                    append = not append
            i = 0
            while i < len(st):
                op = self.prio(st[i])
                if (append and op > pr) or (not append and op >= pr):
                    break
                i += 1
            stackpos = i
        elif stackpos > len(st):
            stackpos = len(st)
        st.insert(stackpos, th)
        if th[0] == 'c':
            c = self.creatures.get(th[1])
            if c is not None:
                c['p'] = pos
                self.ch_cr.add(th[1])
        while len(st) > MAX_THINGS:
            gone = st.pop(MAX_THINGS)
            if gone[0] == 'c':
                self.unplace(gone[1], pos)
        self.touch(pos)

    def unplace(self, cid, pos):
        c = self.creatures.get(cid)
        if c is not None and c.get('p') == pos:
            c['p'] = None
            self.ch_cr.add(cid)

    def remove_creature_from(self, pos, cid):
        st = self.tiles.get(pos)
        if not st:
            return
        for i, th in enumerate(st):
            if th[0] == 'c' and th[1] == cid:
                del st[i]
                self.touch(pos)
                return

    def thing_at(self, pos, stackpos):
        st = self.tiles.get(pos)
        if not st or stackpos >= len(st):
            return None
        return st[stackpos]

    def remove_thing(self, pos, th):
        st = self.tiles.get(pos)
        if not st:
            return -1
        for i, t in enumerate(st):
            if t is th or t == th:
                del st[i]
                if th[0] == 'c':
                    self.unplace(th[1], pos)
                self.touch(pos)
                return i
        return -1

    def mapped(self, m):
        """getMappedThing: (pos, thing) from position + stack position, or 0xFFFF + creature id"""
        x = m.u16()
        if x != 0xFFFF:
            y, z = m.u16(), m.u8()
            sp = m.u8()
            pos = (x, y, z)
            return pos, self.thing_at(pos, sp)
        cid = m.u32()
        c = self.creatures.get(cid)
        if c is None or c.get('p') is None:
            return None, None
        return c['p'], ('c', cid)

    # -------------------------------------------------------- things on the wire
    def item(self, m, cid=None):
        if cid is None:
            cid = m.u16()
        it = self.items.get(cid)
        if it is None:
            raise ParseError('unknown item %d' % cid)
        m.u8()                          # mark
        sub = None
        if it.sub:
            sub = m.u8()
        if it.phase:
            m.u8()
        if self.attrs:
            n = m.u16()
            if n > 64:
                raise ParseError('too many item attributes')
            m.skip(10 * n)
        return ('i', cid, sub)

    def outfit(self, m):
        o = {'t': m.u16()}
        if o['t']:
            o['h'], o['b'], o['l'], o['f'], o['a'] = m.u8(), m.u8(), m.u8(), m.u8(), m.u8()
        else:
            o['x'] = m.u16()
        o['m'] = m.u16()
        if self.marker:
            m.u16()                     # wings
            m.u16()                     # aura
            m.text(256)                 # shader
        return o

    def creature(self, m, op):
        if op == 0x63:
            cid = m.u32()
            c = self.creatures.get(cid)
            d = m.u8()
            m.u8()                      # unpassable
            if c is None:
                raise ParseError('turn of an unknown creature')
            c['d'] = facing4(d)
            self.ch_cr.add(cid)
            return ('c', cid)
        if op == 0x61:
            gone = m.u32()
            cid = m.u32()
            ctype = m.u8()
            name = m.text(100)
            if gone and gone != cid and gone in self.creatures:
                old = self.creatures.pop(gone)
                if old.get('p') is not None:
                    self.remove_creature_from(old['p'], gone)
            c = self.creatures.get(cid)
            if c is None:
                if len(self.creatures) >= 4000:
                    raise ParseError('too many creatures')
                c = self.creatures[cid] = {'p': None}
            c['n'] = name
            c['ty'] = ctype
        else:
            cid = m.u32()
            c = self.creatures.get(cid)
            if c is None:
                raise ParseError('a known creature the view does not know')
        c['hp'] = min(100, m.u8())
        c['d'] = facing4(m.u8())
        c['o'] = self.outfit(m)
        c['lt'] = [m.u8(), m.u8()]
        c['sp'] = m.u16()
        c['sk'] = m.u8()
        c['sh'] = m.u8()
        if op == 0x61:
            m.u8()                      # guild emblem
        c['ty'] = m.u8()
        m.u8()                          # speech bubble
        m.u8()                          # mark
        m.u16()                         # helpers
        m.u8()                          # unpassable
        self.ch_cr.add(cid)
        return ('c', cid)

    def thing(self, m):
        v = m.u16()
        if v in CREATURE_OPS:
            return self.creature(m, v)
        return self.item(m, v)

    # -------------------------------------------------------- map descriptions (the client's)
    def tile_desc(self, m, pos):
        self.clean(pos)
        if m.peek16() >= 0xFF00:
            return m.u16() & 0xFF
        m.u16()                         # environmental effect
        for sp in range(256):
            if m.peek16() >= 0xFF00:
                return m.u16() & 0xFF
            self.add(self.thing(m), pos, sp)
        return 0

    def floor_desc(self, m, x, y, z, w, h, offset, skip):
        if not 0 <= z <= MAX_Z:
            raise ParseError('floor out of range')
        for nx in range(w):
            for ny in range(h):
                pos = (x + nx + offset, y + ny + offset, z)
                if skip == 0:
                    skip = self.tile_desc(m, pos)
                else:
                    self.clean(pos)
                    skip -= 1
        return skip

    def map_desc(self, m, x, y, z, w, h):
        if z > SEA_FLOOR:
            start, end, step = z - AWARE_UNDER, min(z + AWARE_UNDER, MAX_Z), 1
        else:
            start, end, step = SEA_FLOOR, 0, -1
        skip = 0
        nz = start
        while nz != end + step:
            skip = self.floor_desc(m, x, y, nz, w, h, z - nz, skip)
            nz += step

    # -------------------------------------------------------- messages
    def hello(self, body):
        m = Msg(body, 1)
        if bytes(body[1:5]) != b'CAST':
            raise ParseError('not a cast hello')
        m.p = 5
        if m.u8() != 1:
            raise ParseError('a cast hello of another version')
        self.player = m.u32()
        self.marker = m.u16()
        flags = m.u8()
        self.attrs = bool(flags & 1)
        self.impact = bool(flags & 2)
        w, h = m.u8(), m.u8()
        if w < 1 or h < 1:
            raise ParseError('bad aware range')
        self.aware = (w, h)
        self.name = m.text(64)
        self.full = True

    def frame(self, body, now_ms=0):
        """one frame (a message body); False when an unknown opcode cut it short"""
        m = Msg(body)
        while m.left() > 0:
            op = m.u8()
            h = OPS.get(op)
            if h is None:
                return False
            h(self, m, now_ms)
        return True

    def op_aware(self, m, _now):
        w, h = m.u8(), m.u8()
        if w < 1 or h < 1:
            raise ParseError('bad aware range')
        self.aware = (w, h)
        self.full = True

    def op_floor(self, m, _now):
        pos = m.pos()
        floor = m.u8()
        if pos[2] == floor:
            self.set_central(pos)
            self.full = True
        self.floor_desc(m, pos[0] - self.left(), pos[1] - self.top(), floor, self.horizontal(), self.vertical(),
                        pos[2] - floor, 0)

    def op_map(self, m, _now):
        pos = m.pos()
        self.set_central(pos)
        self.full = True
        self.map_desc(m, pos[0] - self.left(), pos[1] - self.top(), pos[2], self.horizontal(), self.vertical())

    def _need_central(self):
        if self.central is None:
            raise ParseError('a map move before the map')
        return self.central

    def op_north(self, m, _now):
        x, y, z = self._need_central()
        y -= 1
        self.map_desc(m, x - self.left(), y - self.top(), z, self.horizontal(), 1)
        self.set_central((x, y, z))

    def op_east(self, m, _now):
        x, y, z = self._need_central()
        x += 1
        self.map_desc(m, x + self.right(), y - self.top(), z, 1, self.vertical())
        self.set_central((x, y, z))

    def op_south(self, m, _now):
        x, y, z = self._need_central()
        y += 1
        self.map_desc(m, x - self.left(), y + self.bottom(), z, self.horizontal(), 1)
        self.set_central((x, y, z))

    def op_west(self, m, _now):
        x, y, z = self._need_central()
        x -= 1
        self.map_desc(m, x - self.left(), y - self.top(), z, 1, self.vertical())
        self.set_central((x, y, z))

    def op_tile(self, m, _now):
        pos = m.pos()
        self.tile_desc(m, pos)

    def op_add(self, m, _now):
        pos = m.pos()
        sp = m.u8()
        self.add(self.thing(m), pos, sp)

    def op_change(self, m, _now):
        pos, old = self.mapped(m)
        new = self.thing(m)
        if pos is None or old is None:
            return
        i = self.remove_thing(pos, old)
        if i >= 0:
            self.add(new, pos, i)

    def op_remove(self, m, _now):
        pos, th = self.mapped(m)
        if pos is not None and th is not None:
            self.remove_thing(pos, th)

    def op_move(self, m, now):
        pos, th = self.mapped(m)
        to = m.pos()
        if pos is None or th is None or th[0] != 'c':
            return
        self.remove_thing(pos, th)
        self.add(th, to, -1)
        c = self.creatures.get(th[1])
        if c is None:
            return
        dx, dy = to[0] - pos[0], to[1] - pos[1]
        if pos[2] == to[2] and max(abs(dx), abs(dy)) == 1:
            if dx or dy:
                c['d'] = (0 if dy < 0 else 2) if abs(dy) >= abs(dx) and dy else (1 if dx > 0 else 3)
            ground = 150
            st = self.tiles.get(to) or []
            if st and st[0][0] == 'i':
                it = self.items.get(st[0][1])
                if it is not None and it.speed:
                    ground = it.speed
            ms = step_ms(c.get('sp', 110), ground, dx != 0 and dy != 0, th[1] == self.player)
            self.walks.append([th[1], pos[0], pos[1], to[0], to[1], ms])

    def op_world_light(self, m, _now):
        self.light = [m.u8(), m.u8()]
        self.ch_light = True

    def op_effect(self, m, _now):
        pos = m.pos()
        kind = m.u16()
        if not self.central:
            return
        if pos[2] == self.central[2]:
            if len(self.fx) < 200:
                self.fx.append([pos[0], pos[1], kind])
        elif len(self.fxf) < 200:
            self.fxf.append([pos[0], pos[1], kind, pos[2]])

    def op_text(self, m, _now):
        pos = m.pos()
        colour = m.u8()
        text = m.text(200)
        self._number(pos, colour, text)

    def _number(self, pos, colour, text):
        if self.central and pos[2] == self.central[2] and len(self.tx) < 100:
            self.tx.append([pos[0], pos[1], colour, text])

    def op_missile(self, m, _now):
        a = m.pos()
        b = m.pos()
        kind = m.u8()
        if not self.central:
            return
        if a[2] == self.central[2]:
            if len(self.mi) < 200:
                self.mi.append([a[0], a[1], b[0], b[1], kind])
        elif len(self.mif) < 200:
            self.mif.append([a[0], a[1], b[0], b[1], kind, a[2]])

    def _cr(self, m):
        cid = m.u32()
        return cid, self.creatures.get(cid)

    def op_health(self, m, _now):
        cid, c = self._cr(m)
        hp = m.u8()
        if c is not None:
            c['hp'] = min(100, hp)
            self.ch_cr.add(cid)

    def op_creature_light(self, m, _now):
        cid, c = self._cr(m)
        lt = [m.u8(), m.u8()]
        if c is not None:
            c['lt'] = lt
            self.ch_cr.add(cid)

    def op_outfit(self, m, _now):
        cid, c = self._cr(m)
        o = self.outfit(m)
        if c is not None:
            c['o'] = o
            self.ch_cr.add(cid)

    def op_speed(self, m, _now):
        cid, c = self._cr(m)
        m.u16()
        sp = m.u16()
        if c is not None:
            c['sp'] = sp
            self.ch_cr.add(cid)

    def op_square(self, m, _now):
        self._cr(m)
        m.u8()
        m.u8()

    def op_stats(self, m, _now):
        hp, mhp = m.u32(), m.u32()
        free, _cap = m.u32(), m.u32()
        m.u64()
        level = m.u16()
        m.u8()
        m.skip(10)
        mp, mmp = m.u32(), m.u32()
        m.skip(4)
        m.u16()
        speed = m.u16()
        m.skip(7)
        self.stats = {'hp': hp, 'mhp': mhp, 'mp': mp, 'mmp': mmp, 'lvl': level, 'cap': free // 100, 'spd': speed * 2}
        self.ch_stats = True

    def op_up(self, m, _now):
        x, y, z = self._need_central()
        z -= 1
        if z < 0:
            raise ParseError('floor change above floor 0')
        self.set_central((x + 1, y + 1, z))
        if z == SEA_FLOOR:
            if not self.marker:     # our client gets these floors as 0x4B messages before this one
                skip = 0
                for i in range(SEA_FLOOR - AWARE_UNDER, -1, -1):
                    skip = self.floor_desc(m, x - self.left(), y - self.top(), i, self.horizontal(), self.vertical(),
                                           UNDERGROUND - i, skip)
        elif z > SEA_FLOOR:
            self.floor_desc(m, x - self.left(), y - self.top(), z - AWARE_UNDER, self.horizontal(), self.vertical(),
                            3, 0)

    def op_down(self, m, _now):
        x, y, z = self._need_central()
        z += 1
        if z > MAX_Z:
            raise ParseError('floor change below floor 15')
        self.set_central((x - 1, y - 1, z))
        if z == UNDERGROUND:
            if not self.marker:     # our client gets these floors as 0x4B messages before this one
                skip = 0
                j = -1
                for i in range(z, z + AWARE_UNDER + 1):
                    skip = self.floor_desc(m, x - self.left(), y - self.top(), i, self.horizontal(), self.vertical(),
                                           j, skip)
                    j -= 1
        elif UNDERGROUND < z < MAX_Z - 1:
            self.floor_desc(m, x - self.left(), y - self.top(), z + AWARE_UNDER, self.horizontal(), self.vertical(),
                            -3, 0)

    def op_say(self, m, _now):
        m.u32()
        name = m.text(100)
        m.u16()
        kind = m.u8()
        if kind not in PUBLIC_TALK:
            raise ParseError('speech of a kind the cast never sends')
        pos = m.pos()
        text = m.text(1024)
        if self.central and pos[2] == self.central[2] and len(self.say) < 50:
            self.say.append([pos[0], pos[1], kind, name, text[:255]])

    def op_message(self, m, _now):
        kind = m.u8()
        if 23 <= kind <= 29:
            pos = m.pos()
            v1, c1 = m.u32(), m.u8()
            v2 = c2 = 0
            if kind in (23, 24, 27):        # damage: two values; heal (25, 28) and experience (26, 29): one
                v2, c2 = m.u32(), m.u8()
            if self.impact:
                m.u16()
                m.u8()
                m.u32()
            m.text(1024)
            if v1:
                self._number(pos, c1, str(v1))
            if v2:
                self._number(pos, c2, str(v2))
        elif 33 <= kind <= 35:
            m.u16()
            m.text(1024)
        else:
            m.text(1024)


def _byte_field(key):
    """a message of creature id + one byte (skull, party shield, walk-through, creature type)"""
    def op(self, m, _now):
        cid, c = self._cr(m)
        v = m.u8()
        if c is not None and key:
            c[key] = v
            self.ch_cr.add(cid)
    return op


OPS = {
    0x42: World.op_aware, 0x4B: World.op_floor, 0x64: World.op_map, 0x65: World.op_north, 0x66: World.op_east,
    0x67: World.op_south, 0x68: World.op_west, 0x69: World.op_tile, 0x6A: World.op_add, 0x6B: World.op_change,
    0x6C: World.op_remove, 0x6D: World.op_move, 0x82: World.op_world_light, 0x83: World.op_effect,
    0x84: World.op_text, 0x85: World.op_missile, 0x8C: World.op_health, 0x8D: World.op_creature_light,
    0x8E: World.op_outfit, 0x8F: World.op_speed, 0x90: _byte_field('sk'),
    0x91: _byte_field('sh'), 0x92: _byte_field(None), 0x93: World.op_square,
    0x95: _byte_field('ty'), 0xA0: World.op_stats, 0xAA: World.op_say, 0xB4: World.op_message,
    0xBE: World.op_up, 0xBF: World.op_down,
}


# ------------------------------------------------------------------------------------------------ sprite sheets
class GroupView:
    """one frame group of a dat thing, shaped like a datspr.Thing for datspr.sprite_index / draw_thing"""
    __slots__ = ('w', 'h', 'layers', 'px', 'py', 'pz', 'phases', 'sprites', 'flags', 'anim')

    def __init__(self, t, g=0):
        groups = getattr(t, 'groups', None) or []
        if g < len(groups):
            w, h, _exact, layers, px, py, pz, ph, sprites, anim = groups[g]
        else:
            w, h, layers, px, py, pz, ph, sprites, anim = (t.w, t.h, t.layers, t.px, t.py, t.pz, t.phases, t.sprites,
                                                           t.anim)
        self.w, self.h, self.layers, self.px, self.py, self.pz = w, h, layers, px, py, pz
        self.phases, self.sprites, self.flags, self.anim = ph, sprites, t.flags, anim


def frame_ms(view, default):
    """ms per frame of an animation: the dat's first duration when it has one, else the client's default"""
    if view.anim and view.anim[3]:
        v = int(view.anim[3][0])
        if 10 <= v <= 5000:
            return v
    return default


def png_b64(arr):
    from PIL import Image
    buf = io.BytesIO()
    Image.fromarray(arr, 'RGBA').save(buf, 'PNG', optimize=True)
    return base64.b64encode(buf.getvalue()).decode('ascii')


class Sheets:
    """the sheets of one run: drawn on first use, sent once (each key at most once per run)"""

    def __init__(self, dat, spr):
        import numpy as np
        import gen_sprite_images as gsi
        self.np, self.gsi = np, gsi
        self.dat, self.spr = dat, spr
        self.sent = set()
        self.errors = 0
        self.items = {t.id: t for t in dat.items}

    def draw(self, view, x, y, z, layers, phase):
        """gen_sprite_images.draw_thing, faster: the cells of one thing never overlap, so they are pasted"""
        np = self.np
        from datspr import sprite_index
        out = np.zeros((view.h * 32, view.w * 32, 4), np.uint8)
        for layer in (range(view.layers) if layers is None else layers):
            if layer >= view.layers:
                continue
            for hh in range(view.h):
                for ww in range(view.w):
                    i = sprite_index(view, x, y, z, layer, phase, ww, hh)
                    a = self.spr.sprite(view.sprites[i]) if 0 <= i < len(view.sprites) else None
                    if a is not None:
                        self.over(out, a, ((view.w - 1 - ww) * 32, (view.h - 1 - hh) * 32))
        return out

    def over(self, canvas, img, at):
        """the client's blending; a straight copy where the art is fully opaque or fully clear (most sprites)"""
        np = self.np
        x0, y0 = at
        h, w = img.shape[:2]
        alpha = img[..., 3]
        if not alpha.any():
            return
        if np.all((alpha == 0) | (alpha == 255)):
            view = canvas[y0:y0 + h, x0:x0 + w]
            sel = alpha == 255
            view[sel] = img[sel]
            return
        self.gsi.over(canvas, img, at)

    def _grid(self, view, kind, key, default_ms, extra=None):
        np, gsi = self.np, self.gsi
        npat = view.px * view.py * view.pz
        nf = max(1, min(view.phases, MAX_CELLS // max(1, npat)))
        npat = min(npat, MAX_CELLS)
        cw, ch = view.w * 32, view.h * 32
        img = np.zeros((npat * ch, nf * cw, 4), np.uint8)
        for pi in range(npat):
            x = pi % view.px
            y = (pi // view.px) % view.py
            z = pi // (view.px * view.py)
            for f in range(nf):
                cell = self.draw(view, x, y, z, None, f)
                img[pi * ch:(pi + 1) * ch, f * cw:(f + 1) * cw] = cell
        disp = view.flags.get('displacement') or (0, 0)
        dx, dy = gsi.s16(disp[0]), gsi.s16(disp[1])
        line = {'t': 'spr', 'k': kind, 'key': key, 'cw': cw, 'ch': ch, 'ax': -(view.w - 1) * 32 - dx,
                'ay': -(view.h - 1) * 32 - dy, 'np': npat, 'nf': nf, 'fd': frame_ms(view, default_ms)}
        if extra:
            line.update(extra)
        line['png'] = png_b64(img)
        return line

    def item(self, cid):
        t = self.items.get(cid)
        if t is None:
            return None
        extra = {'el': int(t.flags.get('elevation', 0) or 0)}
        if 'ground' in t.flags:
            extra['gr'] = 1
        if light_of(t.flags):
            extra['lt'] = light_of(t.flags)
        return self._grid(GroupView(t), 'i', 'i%d' % cid, 500, extra)

    def effect(self, kind):
        if not 1 <= kind <= len(self.dat.effects):
            return None
        t = self.dat.effects[kind - 1]
        return self._grid(GroupView(t), 'e', 'e%d' % kind, 75, {'lt': light_of(t.flags)} if light_of(t.flags) else None)

    def missile(self, kind):
        if not 1 <= kind <= len(self.dat.missiles):
            return None
        t = self.dat.missiles[kind - 1]
        return self._grid(GroupView(t), 'm', 'm%d' % kind, 100, {'lt': light_of(t.flags)} if light_of(t.flags) else None)

    @staticmethod
    def frames(t):
        """(idle view, idle phases, walk view, walk phases) of an outfit"""
        groups = getattr(t, 'groups', None) or []
        idle = GroupView(t, 0)
        if len(groups) >= 2:
            walk = GroupView(t, 1)
            return idle, list(range(idle.phases)), walk, list(range(walk.phases))
        if idle.phases > 1:
            return idle, [0], idle, list(range(1, idle.phases))
        return idle, [0], idle, [0]

    def _meta(self, view, d):
        gsi = self.gsi
        meta = gsi.outfit_meta(view)
        b = view.flags.get('x39')
        if b and len(bytes(b)) >= 16:
            meta[9], meta[10] = struct.unpack_from('<2h', bytes(b), {0: 0, 1: 8, 2: 4, 3: 12}[d])
        return meta

    def outfit(self, o):
        """the coloured sheet of an outfit {'t','h','b','l','f','a','m'}: rows N, E, S, W; idle then walk columns"""
        np, gsi = self.np, self.gsi
        look = o.get('t', 0)
        if not 1 <= look <= len(self.dat.outfits):
            return None
        t = self.dat.outfits[look - 1]
        mt = self.dat.outfits[o['m'] - 1] if 1 <= o.get('m', 0) <= len(self.dat.outfits) else None
        iv, iph, wv, wph = self.frames(t)
        mframes = self.frames(mt) if mt is not None else None
        places = []
        for d in range(4):
            rm = self._meta(iv, d)
            mm = self._meta(mframes[0], d) if mt is not None else None
            places.append(gsi.place(rm, mm))
        rects = []
        for rxy, mxy, _z in places:
            for v in (iv, wv):
                rects.append((rxy[0], rxy[1], v.w * 32, v.h * 32))
            if mxy is not None:
                for v in (mframes[0], mframes[2]):
                    rects.append((mxy[0], mxy[1], v.w * 32, v.h * 32))
        left = min(r[0] for r in rects)
        top = min(r[1] for r in rects)
        cw = max(r[0] + r[2] for r in rects) - left
        ch = max(r[1] + r[3] for r in rects) - top
        cols = [(iv, p, 0) for p in iph] + [(wv, p, 1) for p in wph]
        cols = cols[:32]
        img = np.zeros((4 * ch, len(cols) * cw, 4), np.uint8)
        colours = (o.get('h', 0), o.get('b', 0), o.get('l', 0), o.get('f', 0))
        addons = o.get('a', 0)
        for d in range(4):
            rxy, mxy, z = places[d]
            for ci, (view, phase, walking) in enumerate(cols):
                cell = np.zeros((ch, cw, 4), np.uint8)
                if mxy is not None:
                    mv = mframes[2] if walking else mframes[0]
                    mph = (mframes[3] if walking else mframes[1])
                    mp = mph[ci % len(mph)] if mph else 0
                    art = self.draw(mv, d if mv.px >= 4 else 0, 0, 0, [0], mp)
                    self.over(cell, art, (mxy[0] - left, mxy[1] - top))
                zz = min(z, view.pz - 1)
                dx = d if view.px >= 4 else 0
                at = (rxy[0] - left, rxy[1] - top)
                for y in range(view.py):
                    if y > 0 and not addons & (1 << (y - 1)):
                        continue
                    self.over(cell, self.draw(view, dx, y, zz, [0], phase), at)
                    if view.layers > 1:
                        gsi.tint(cell, self.draw(view, dx, y, zz, [1], phase), colours, at)
                img[d * ch:(d + 1) * ch, ci * cw:(ci + 1) * cw] = cell
        ni = min(len(iph), len(cols))
        return {'t': 'spr', 'k': 'o', 'key': outfit_key(o), 'cw': cw, 'ch': ch, 'ax': left, 'ay': top, 'ni': ni,
                'nw': len(cols) - ni, 'fd': frame_ms(wv, 100), 'png': png_b64(img)}

    def need(self, key, build):
        """the sheet line for key the first time (None after). A sheet that cannot be had is not silent: the line is
        {"t":"sprerr","key","why"} (why: "none" the pair has no such thing, "limit" the run sent MAX_SHEETS, or the
        error's name and text), so the app can say what is missing instead of drawing black."""
        if key in self.sent:
            return None
        if len(self.sent) >= MAX_SHEETS:
            self.sent.add(key)
            self.errors += 1
            return {'t': 'sprerr', 'key': key, 'why': 'limit'}
        self.sent.add(key)
        try:
            line = build()
        except Exception as e:   # noqa: BLE001 - a broken thing in the pair: drawn as nothing, and said
            self.errors += 1
            return {'t': 'sprerr', 'key': key, 'why': ('%s: %s' % (type(e).__name__, e))[:120]}
        if line is None:
            self.errors += 1
            return {'t': 'sprerr', 'key': key, 'why': 'none'}
        return line


def outfit_key(o):
    return 'o%d.%d.%d.%d.%d.%d.%d' % (o.get('t', 0), o.get('h', 0), o.get('b', 0), o.get('l', 0), o.get('f', 0),
                                    o.get('a', 0), o.get('m', 0))


# ------------------------------------------------------------------------------------------------ the lines
class View:
    """turns the World into the app's JSON lines, with the sheets they need first"""

    def __init__(self, world, sheets=None, dims=None):
        self.w = world
        self.sheets = sheets
        self.dims = dims or {}       # {client id: (px, py, pz)}
        self.fl = None               # [first, last] floor the app was told
        self.floors_sent = set()     # the other floors whose tiles the app holds

    def item_pattern(self, cid, sub, pos):
        px, py, pz = self.dims.get(cid, (1, 1, 1))
        it = self.w.items.get(cid)
        if it is not None and it.stack and px == 4 and py == 2:
            x, y = stack_xy(sub or 0)
            return y * px + x
        if it is not None and it.fluid:
            colour = NEW_FLUID[sub] if sub is not None and sub < len(NEW_FLUID) else 0
            return ((colour // 4) % py) * px + (colour % 4) % px
        return ((pos[2] % pz) * py + pos[1] % py) * px + pos[0] % px

    def tile(self, pos, out):
        st = self.w.tiles.get(pos) or []
        under, over = [], []
        elev = 0
        items = self.w.items

        def entry(th):
            cid = th[1]
            self._sheet(out, 'i%d' % cid, lambda: self.sheets.item(cid))
            return ['i%d' % cid, self.item_pattern(cid, th[2], pos), elev]

        bottoms = [th for th in st if th[0] == 'i' and items.get(th[1]) is not None and items[th[1]].prio <= 2]
        commons = [th for th in st if th[0] == 'i' and (items.get(th[1]) is None or items[th[1]].prio == 5)]
        tops = [th for th in st if th[0] == 'i' and items.get(th[1]) is not None and items[th[1]].prio == 3]
        for th in bottoms + list(reversed(commons)):
            under.append(entry(th))
            it = items.get(th[1])
            if it is not None and it.elev:
                elev = min(24, elev + it.elev)
        for th in tops:
            over.append(entry(th))
        return [pos[0], pos[1], under, over, elev]

    def _sheet(self, out, key, build):
        if self.sheets is None:
            return
        line = self.sheets.need(key, build)
        if line is not None:
            out.append(line)

    def creature(self, cid, out):
        c = self.w.creatures.get(cid)
        if c is None:
            return None
        o = c.get('o') or {}
        key = None
        if o.get('t'):
            key = outfit_key(o)
            self._sheet(out, key, lambda: self.sheets.outfit(o))
        elif o.get('x'):
            key = 'i%d' % o['x']
            self._sheet(out, key, lambda: self.sheets.item(o['x']))
        p = c.get('p')
        v = {'n': c.get('n', ''), 'hp': c.get('hp', 0), 'd': c.get('d', 2), 'o': key,
             'p': list(p) if p is not None else None, 'sk': c.get('sk', 0), 'sh': c.get('sh', 0),
             'ty': c.get('ty', 0), 'sp': c.get('sp', 0)}
        lt = c.get('lt')
        if lt and lt[0]:
            v['lt'] = [lt[0], lt[1]]        # phase 3: the creature's own light [intensity, colour]; absent: none
        return v

    def floor_tiles(self):
        if self.w.central is None:
            return []
        cx, cy, cz = self.w.central
        return [p for p in self.w.tiles if p[2] == cz and abs(p[0] - cx) <= self.w.horizontal()
                and abs(p[1] - cy) <= self.w.vertical()]

    def in_window(self, p):
        """is a tile of another floor inside the cells the app can show? Floor f is drawn shifted (cz - f) tiles
        up and left, so its tile x sits at the cell x - (cz - f)."""
        w = self.w
        cx, cy, cz = w.central
        s = cz - p[2]
        return -(w.left() + 1) <= p[0] - s - cx <= w.right() + 1 and -(w.top() + 1) <= p[1] - s - cy <= w.bottom() + 1

    def other_floors(self, fl):
        cz = self.w.central[2]
        return {f for f in range(fl[0], fl[1] + 1) if f != cz}

    def floor_entries(self, pos_list, out, only=None):
        """[z, x, y, under, over, elevation] of tiles on other floors; an empty tile clears the app's"""
        res = []
        for p in sorted(pos_list):
            if (only is None or p[2] in only) and self.in_window(p):
                x, y, under, over, elev = self.tile(p, out)
                res.append([p[2], x, y, under, over, elev])
        return res

    def fx_line(self, out, x, y, kind):
        self._sheet(out, 'e%d' % kind, lambda k=kind: self.sheets.effect(k))
        t = self.sheets.dat.effects[kind - 1] if self.sheets and 1 <= kind <= len(self.sheets.dat.effects) else None
        pat = (y % t.py) * t.px + x % t.px if t is not None else 0
        return [x, y, 'e%d' % kind, pat]

    def mi_line(self, out, fx_, fy, tx, ty, kind):
        self._sheet(out, 'm%d' % kind, lambda k=kind: self.sheets.missile(k))
        px, py = missile_pattern(fx_, fy, tx, ty)
        t = self.sheets.dat.missiles[kind - 1] if self.sheets and 1 <= kind <= len(self.sheets.dat.missiles) else None
        pat = (py % t.py) * t.px + px % t.px if t is not None else py * 3 + px
        ms = int(150 * math.sqrt(max(1, (tx - fx_) ** 2 + (ty - fy) ** 2)))
        return [fx_, fy, tx, ty, 'm%d' % kind, pat, min(ms, 2000)]

    def lines(self):
        """the lines for what changed (sheets first); the World's changes start again"""
        w = self.w
        out = []
        if w.central is None:
            w.reset_changes()
            return out
        fl = w.floors()
        others = self.other_floors(fl)
        if w.full:
            tiles = [self.tile(p, out) for p in sorted(self.floor_tiles())]
            cr = {}
            for cid in w.creatures:
                v = self.creature(cid, out)
                if v is not None:
                    cr[str(cid)] = v
            line = {'t': 'full', 'c': list(w.central), 'id': w.player, 'tiles': tiles, 'cr': cr, 'fl': fl}
            ft = self.floor_entries([p for p in w.tiles if p[2] in others and w.tiles[p]], out, others)
            if ft:
                line['ft'] = ft
            self.floors_sent = set(others)
            self.fl = fl
            if w.stats:
                line['st'] = w.stats
            if w.light:
                line['light'] = w.light
            out.append(line)
            w.full = False
            fx_only = True
        else:
            fx_only = False
        line = {'t': 'd'}
        if not fx_only:
            if w.ch_central:
                line['c'] = list(w.central)
            if w.ch_tiles:
                line['tiles'] = [self.tile(p, out) for p in sorted(w.ch_tiles)]
            # the other floors: the range, floors that came into view whole (the app clears them first), changes
            if fl != self.fl:
                line['fl'] = fl
                self.fl = fl
            newly = others - self.floors_sent
            self.floors_sent = set(others)
            ft = []
            if newly:
                line['fc'] = sorted(newly)
                ft = self.floor_entries([p for p in w.tiles if p[2] in newly and w.tiles[p]], out, newly)
            ft += self.floor_entries([p for p in w.ch_ftiles if p[2] not in newly], out, others)
            if ft:
                line['ft'] = ft
            if w.ch_cr:
                cr = {}
                for cid in sorted(w.ch_cr):
                    v = self.creature(cid, out)
                    if v is not None:
                        cr[str(cid)] = v
                if cr:
                    line['cr'] = cr
            if w.ch_stats and w.stats:
                line['st'] = w.stats
            if w.ch_light and w.light:
                line['light'] = w.light
        if w.walks:
            line['walk'] = w.walks
        if w.fx:
            line['fx'] = [self.fx_line(out, x, y, kind) for x, y, kind in w.fx]
        if w.mi:
            line['mi'] = [self.mi_line(out, *m) for m in w.mi]
        # phase 3: effects and missiles on the other floors that are drawn (a separate key, an old app ignores it)
        fxf = [self.fx_line(out, x, y, kind) + [z] for x, y, kind, z in w.fxf if z in others]
        if fxf:
            line['fxf'] = fxf
        mif = [self.mi_line(out, a, b, c, d, kind) + [z] for a, b, c, d, kind, z in w.mif if z in others]
        if mif:
            line['mif'] = mif
        if w.tx:
            line['tx'] = w.tx
        if w.say:
            line['say'] = w.say
        if len(line) > 1:
            out.append(line)
        w.reset_changes()
        return out


# ------------------------------------------------------------------------------------------------ the connection
class Frames:
    """splits a byte stream into frame bodies (u16 length + body)"""

    def __init__(self):
        self.buf = bytearray()

    def feed(self, data):
        self.buf += data
        out = []
        while len(self.buf) >= 2:
            n = self.buf[0] | (self.buf[1] << 8)
            if n == 0:
                raise ParseError('an empty frame')
            if len(self.buf) < 2 + n:
                break
            out.append(bytes(self.buf[2:2 + n]))
            del self.buf[:2 + n]
        return out


class Out:
    """stdout lines; BrokenPipeError when the app is gone"""

    def __init__(self, stream=None):
        self.s = stream or sys.stdout
        self.last = time.monotonic()

    def line(self, obj):
        self.s.write(json.dumps(obj, separators=(',', ':'), ensure_ascii=True) + '\n')
        self.s.flush()
        self.last = time.monotonic()


class Session:
    """one connection to the cast port: hello, frames, lines"""

    def __init__(self, items, dims, sheets, name=None):
        self.world = World(items, dims)
        self.view = View(self.world, sheets, dims)
        self.frames = Frames()
        self.name = name
        self.started = False

    def feed(self, data, now_ms=0):
        """bytes from the port -> lines to write; ParseError: start again"""
        out = []
        for body in self.frames.feed(data):
            if not self.started:
                if body[0] != 0x00:
                    raise ParseError('no hello first')
                self.world.hello(body)
                if self.name and self.world.name.lower() != self.name.lower():
                    raise WrongTarget(self.world.name)
                self.started = True
                out.append({'t': 'hello', 'id': self.world.player, 'name': self.world.name,
                            'aware': list(self.world.aware), 'v': PROTOCOL})
                continue
            self.world.frame(body, now_ms)
        return out

    def flush(self):
        return self.view.lines()


class WrongTarget(Exception):
    pass


def load_pair(dat_path, spr_path, otb_path=None):
    import datspr
    dat = datspr.Dat(dat_path)
    spr = datspr.Spr(spr_path)
    items = item_types(dat, otb_nodes(otb_path) if otb_path else None)
    dims = {t.id: (t.px, t.py, t.pz) for t in dat.items}
    return dat, spr, items, dims


def stdin_closed(fd):
    """True when the app's channel closed (EOF on stdin); anything typed is ignored"""
    try:
        data = os.read(fd, 4096)
    except (BlockingIOError, InterruptedError):
        return False
    except OSError:
        return True
    return not data


def run(port, items, dims, sheets, out, name=None, max_seconds=1800, stdin_fd=None):
    """the relay loop; returns the reason it ended"""
    deadline = time.monotonic() + max_seconds
    waited = None
    while True:
        if time.monotonic() >= deadline:
            return 'time'
        try:
            sock = socket.create_connection(('127.0.0.1', port), timeout=2)
        except OSError:
            sock = None
        if sock is None:
            if waited != 'port':
                out.line({'t': 'wait', 'why': 'port'})
                waited = 'port'
            why = idle(1.0, stdin_fd, out)
            if why:
                return why
            continue
        sock.setblocking(False)
        sess = Session(items, dims, sheets, name)
        last_flush = time.monotonic()
        ended = None
        try:
            while True:
                now = time.monotonic()
                if now >= deadline:
                    return 'time'
                fds = [sock] + ([stdin_fd] if stdin_fd is not None else [])
                r, _w, _x = select.select(fds, [], [], FLUSH_MS / 1000.0)
                if stdin_fd is not None and stdin_fd in r and stdin_closed(stdin_fd):
                    return 'stdin'
                if sock in r:
                    try:
                        data = sock.recv(65536)
                    except (BlockingIOError, InterruptedError):
                        data = None
                    except OSError:
                        data = b''
                    if data == b'':
                        ended = 'closed'
                        break
                    if data:
                        for line in sess.feed(data, int(now * 1000)):
                            out.line(line)
                        waited = None
                now = time.monotonic()
                if now - last_flush >= FLUSH_MS / 1000.0:
                    last_flush = now
                    for line in sess.flush():
                        out.line(line)
                if now - out.last >= 1.0:
                    out.line({'t': 'hb'})
        except WrongTarget:
            ended = 'other'
        except ParseError as e:
            out.line({'t': 'resync', 'why': str(e)[:80]})
            ended = 'resync'
        except BrokenPipeError:
            raise
        except Exception as e:  # noqa: BLE001 - never crash on what the port sends: start again
            out.line({'t': 'resync', 'why': type(e).__name__})
            ended = 'resync'
        finally:
            sock.close()
        if not sess.started and waited != 'target':
            out.line({'t': 'wait', 'why': 'target'})
            waited = 'target'
        why = idle(1.0 if ended != 'resync' else 0.5, stdin_fd, out)
        if why:
            return why


def idle(seconds, stdin_fd, out):
    end = time.monotonic() + seconds
    while True:
        left = end - time.monotonic()
        if left <= 0:
            if time.monotonic() - out.last >= 1.0:
                out.line({'t': 'hb'})
            return None
        if stdin_fd is None:
            time.sleep(left)
            continue
        r, _w, _x = select.select([stdin_fd], [], [], left)
        if r and stdin_closed(stdin_fd):
            return 'stdin'


NAME_OK = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz \'-'


def valid_name(name):
    return (3 <= len(name) <= 29 and name[0].isascii() and name[0].isalpha() and all(ch in NAME_OK for ch in name)
            and not name.endswith(' ') and '  ' not in name)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--port', type=int, required=True)
    ap.add_argument('--dat', required=True)
    ap.add_argument('--spr', required=True)
    ap.add_argument('--otb')
    ap.add_argument('--name')
    ap.add_argument('--max-seconds', type=int, default=1800)
    a = ap.parse_args(argv)
    out = Out()
    try:
        if not 1 <= a.port <= 65535:
            out.line({'t': 'end', 'why': 'bad-port'})
            return 2
        if a.name is not None and not valid_name(a.name):
            out.line({'t': 'end', 'why': 'bad-name'})
            return 2
        try:
            dat, spr, items, dims = load_pair(a.dat, a.spr, a.otb)
        except Exception:  # noqa: BLE001
            out.line({'t': 'end', 'why': 'no-pair'})
            return 1
        sheets = Sheets(dat, spr)
        fd = sys.stdin.fileno()
        try:
            os.set_blocking(fd, False)
        except OSError:
            pass
        why = run(a.port, items, dims, sheets, out, a.name, max(1, min(a.max_seconds, 7200)), fd)
        out.line({'t': 'end', 'why': why})
        return 0
    except BrokenPipeError:
        try:
            sys.stdout = open(os.devnull, 'w')
        except OSError:
            pass
        return 0
    except KeyboardInterrupt:
        return 0


if __name__ == '__main__':
    sys.exit(main())
