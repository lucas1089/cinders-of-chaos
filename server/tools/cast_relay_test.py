#!/usr/bin/env python3
"""Tests of server/tools/cast_relay.py (the live cast relay; server/README.md "Live spectator", phase 2).

A synthetic pair (client/tools/sprites/check_pair_test.py writers) and synthetic frames as the engine sends them
(src-patch 0064): the hello, the map (0x64 and the per-floor 0x4B of our client), every map move, tile changes,
creature moves / turns / health / light / outfit / speed / skull / shield / type, effects, missiles, animated text,
the player's stats, speech, the damage / heal / experience numbers, floor changes up and down (both layouts), the
sheets (items with patterns and frames, outfits coloured with idle and walking frames, effects, missiles), the lines,
the loop against a local port, and a fuzz: random frames never raise anything but ParseError.

Run: python3 -I server/tools/cast_relay_test.py (needs python3-numpy and python3-pil)
"""
import base64
import io
import json
import os
import random
import socket
import struct
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, 'client', 'tools', 'sprites'))
from PIL import Image  # noqa: E402
import cast_relay as cr  # noqa: E402
import check_pair_test as cpt  # noqa: E402

FAILS = []
COUNT = [0]


def expect(cond, what):
    COUNT[0] += 1
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


def full(col):
    return cpt.record({k: col for k in range(1024)})


GREEN, RED, BLUE, WHITE, BROWN = (0, 160, 0, 255), (220, 0, 0, 255), (0, 0, 220, 255), (200, 200, 200, 255), \
    (120, 80, 40, 255)
MASK_HEAD = (255, 255, 0, 255)
GREY = (128, 128, 128, 255)
GROUND, TOP, COMMON, ELEV, STACK, FLUID, ANIM, LAMP, WALL, GLASS, CLOSED = 100, 101, 102, 103, 104, 105, 106, 107, \
    108, 109, 110


def make_pair(d):
    recs = [full(GREEN), full(RED), full(BLUE), full(BROWN), full(WHITE), full(MASK_HEAD), full(GREY)]
    recs += [full((k * 20 + 20, 0, 0, 255)) for k in range(8)]          # 8..15 stack patterns
    ground = bytes([0]) + struct.pack('<H', 100)                          # ground, speed 100
    items = [cpt.entry(ground, [cpt.group([1])]),                         # 100 ground
             cpt.entry(bytes([3]), [cpt.group([2])]),                     # 101 top
             cpt.entry(b'', [cpt.group([3])]),                            # 102 common
             cpt.entry(bytes([26]) + struct.pack('<H', 8), [cpt.group([4])]),   # 103 elevation 8
             cpt.entry(bytes([5]), [cpt.group(list(range(8, 16)), px=4, py=2)]),  # 104 stackable
             cpt.entry(bytes([10]), [cpt.group([5] * 8, px=4, py=2)]),    # 105 fluid container
             cpt.entry(b'', [cpt.group([3, 4], phases=2)]),               # 106 two phases
             cpt.entry(bytes([22]) + struct.pack('<HH', 6, 206), [cpt.group([3])]),   # 107 a lamp: light 6, colour 206
             cpt.entry(bytes([2, 14]), [cpt.group([2])]),                 # 108 a wall: bottom, blocks the view
             cpt.entry(bytes([0]) + struct.pack('<H', 100) + bytes([23]), [cpt.group([1])]),   # 109 ground, don't hide
             cpt.entry(bytes([14]), [cpt.group([3])])]                    # 110 blocks the view, nothing else
    # look 1: idle group (1 phase), walking group (2 phases); 4 directions, art + template
    idle = [5, 6] * 4
    walk = [5, 6] * 8
    outfits = [cpt.entry(b'', [cpt.group(idle, layers=2, px=4, gtype=0),
                               cpt.group(walk, layers=2, px=4, phases=2, gtype=1)], outfit=True)]
    effects = [cpt.entry(bytes([22]) + struct.pack('<HH', 3, 215), [cpt.group([2, 3, 4], phases=3)])]
    missiles = [cpt.entry(b'', [cpt.group([7] * 9, px=3, py=3)])]
    os.makedirs(d, exist_ok=True)
    dat, spr = os.path.join(d, 'Tibia.dat'), os.path.join(d, 'Tibia.spr')
    with open(dat, 'wb') as f:
        f.write(cpt.dat_bytes(items, outfits, effects, missiles))
    with open(spr, 'wb') as f:
        f.write(cpt.spr_bytes(recs))
    return dat, spr


# ------------------------------------------------------------------------------------------------ frame writers
def u8(v):
    return bytes([v & 0xFF])


def u16(v):
    return struct.pack('<H', v)


def u32(v):
    return struct.pack('<I', v)


def text(s):
    b = s.encode('latin-1')
    return u16(len(b)) + b


def pos(x, y, z):
    return u16(x) + u16(y) + u8(z)


class Enc:
    """writes things as the server does for one hello's feature set"""

    def __init__(self, marker=0, attrs=False):
        self.marker, self.attrs = marker, attrs

    def item(self, cid, sub=None):
        b = u16(cid) + u8(0xFF)
        if cid in (STACK, FLUID):
            b += u8(sub or 0)
        if cid == ANIM:
            b += u8(0xFE)
        if self.attrs:
            b += u16(1) + u16(7) + struct.pack('<Q', 5)
        return b

    def outfit(self, look=1, colours=(10, 20, 30, 40), addons=0, mount=0, ex=0):
        b = u16(look)
        b += bytes(colours) + u8(addons) if look else u16(ex)
        b += u16(mount)
        if self.marker:
            b += u16(0) + u16(0) + text('')
        return b

    def creature(self, cid, name='Bob', known=False, hp=100, d=2, ctype=0, speed=110, **o):
        if known:
            b = u16(0x62) + u32(cid)
        else:
            b = u16(0x61) + u32(0) + u32(cid) + u8(ctype) + text(name)
        b += u8(hp) + u8(d) + self.outfit(**o) + u8(0) + u8(0) + u16(speed) + u8(0) + u8(0)
        if not known:
            b += u8(0)
        return b + u8(ctype) + u8(0) + u8(0xFF) + u16(0) + u8(1)

    def floor(self, tiles, x, y, z, w, h, offset, skip):
        out = b''
        for nx in range(w):
            for ny in range(h):
                things = tiles.get((x + nx + offset, y + ny + offset, z))
                if things is not None:
                    if skip >= 0:
                        out += u8(skip) + u8(0xFF)
                    skip = 0
                    out += u16(0) + b''.join(things)
                elif skip == 0xFE:
                    out += u8(0xFF) + u8(0xFF)
                    skip = -1
                else:
                    skip += 1
        return out, skip

    def area(self, tiles, x, y, z, w, h):
        if z > 7:
            floors = range(z - 2, min(15, z + 2) + 1)
        else:
            floors = range(7, -1, -1)
        out, skip = b'', -1
        for nz in floors:
            b, skip = self.floor(tiles, x, y, nz, w, h, z - nz, skip)
            out += b
        if skip >= 0:
            out += u8(skip) + u8(0xFF)
        return out

    def one_floor(self, tiles, x, y, z, w, h, offset):
        b, skip = self.floor(tiles, x, y, z, w, h, offset, -1)
        if skip >= 0:
            b += u8(skip) + u8(0xFF)
        return b


def hello(name='Bob', pid=0x10000001, marker=0, flags=0, w=17, h=13):
    return u8(0) + b'CAST' + u8(1) + u32(pid) + u16(marker) + u8(flags) + u8(w) + u8(h) + text(name)


def framed(body):
    return u16(len(body)) + body


PX, PY, PZ = 1000, 1000, 7
PID = 0x10000001


def base_tiles(enc, z=PZ, around=(PX, PY)):
    """a ground on every tile of the aware range on floor z, the player in the middle"""
    tiles = {}
    for x in range(around[0] - 8, around[0] + 10):
        for y in range(around[1] - 6, around[1] + 8):
            tiles[(x, y, z)] = [enc.item(GROUND)]
    tiles[(around[0], around[1], z)] = [enc.item(GROUND), enc.creature(PID)]
    return tiles


def start(world, enc, tiles=None):
    tiles = tiles or base_tiles(enc)
    body = u8(0x64) + pos(PX, PY, PZ) + enc.area(tiles, PX - 8, PY - 6, PZ, 18, 14)
    world.hello(hello(marker=enc.marker, flags=1 if enc.attrs else 0))
    expect(world.frame(body), 'the map frame parses to the end')


# ------------------------------------------------------------------------------------------------ tests
def test_map_and_moves(items, dims):
    enc = Enc()
    w = cr.World(items, dims)
    start(w, enc)
    expect(w.central == (PX, PY, PZ), 'the map sets the camera')
    expect(w.tiles[(PX, PY, PZ)] == [('i', GROUND, None), ('c', PID)], 'ground, then the player')
    expect(w.creatures[PID]['p'] == (PX, PY, PZ) and w.creatures[PID]['n'] == 'Bob', 'the player is placed')
    expect(len([p for p in w.tiles if p[2] == PZ]) == 18 * 14, 'every tile of the aware range')
    expect(w.full, 'a map asks for a full line')
    v = cr.View(w, None, dims)
    lines = v.lines()
    expect(lines and lines[0]['t'] == 'full' and lines[0]['c'] == [PX, PY, PZ], 'a full line')
    expect(len(lines[0]['tiles']) == 18 * 14 and str(PID) in lines[0]['cr'], 'with the tiles and the player')
    expect(not w.dirty(), 'the changes start again')

    # the player steps east: 0x6D then the east slice of the aware range
    east = {(PX + 10, PY - 6 + k, PZ): [enc.item(GROUND)] for k in range(14)}
    body = u8(0x6D) + pos(PX, PY, PZ) + u8(1) + pos(PX + 1, PY, PZ) + u8(0x66) + \
        enc.area(east, PX + 1 + 9, PY - 6, PZ, 1, 14)
    expect(w.frame(body), 'move + east slice')
    expect(w.central == (PX + 1, PY, PZ), 'the camera follows east')
    expect(w.creatures[PID]['p'] == (PX + 1, PY, PZ), 'the player is on its new tile')
    expect(w.tiles[(PX, PY, PZ)] == [('i', GROUND, None)], 'and off the old one')
    expect(w.walks and w.walks[0][:5] == [PID, PX, PY, PX + 1, PY], 'a walk')
    expect(w.walks[0][5] == cr.step_ms(110, 100, False, True), 'its duration (ground speed of the new tile)')
    expect(w.creatures[PID]['d'] == 1, 'facing east')
    expect((PX + 10, PY, PZ) in w.tiles, 'the new column')
    lines = v.lines()
    expect(lines[-1]['t'] == 'd' and lines[-1]['c'] == [PX + 1, PY, PZ] and 'walk' in lines[-1], 'a delta line')

    # north, south, west slices
    x, y = PX + 1, PY
    n = {(x - 8 + k, y - 1 - 6, PZ): [enc.item(GROUND)] for k in range(18)}
    expect(w.frame(u8(0x65) + enc.area(n, x - 8, y - 1 - 6, PZ, 18, 1)), 'north slice')
    expect(w.central == (x, y - 1, PZ), 'camera north')
    s = {(x - 8 + k, y - 1 + 7, PZ): [enc.item(GROUND)] for k in range(18)}
    expect(w.frame(u8(0x67) + enc.area(s, x - 8, y - 1 + 7, PZ, 18, 1)), 'south slice')
    expect(w.central == (x, y, PZ), 'camera south')
    wcol = {(x - 1 - 8, y - 6 + k, PZ): [enc.item(GROUND)] for k in range(14)}
    expect(w.frame(u8(0x68) + enc.area(wcol, x - 1 - 8, y - 6, PZ, 1, 14)), 'west slice')
    expect(w.central == (x - 1, y, PZ), 'camera west')
    return w, enc


def test_tiles(items, dims):
    enc = Enc(attrs=True)
    w = cr.World(items, dims)
    start(w, enc)
    t = (PX + 1, PY, PZ)
    expect(w.frame(u8(0x6A) + pos(*t) + u8(255) + enc.item(COMMON)), 'add a common item')
    expect(w.frame(u8(0x6A) + pos(*t) + u8(255) + enc.item(STACK, 7)), 'add a stack of 7')
    expect(w.tiles[t] == [('i', GROUND, None), ('i', STACK, 7), ('i', COMMON, None)], 'common items go first')
    expect(w.frame(u8(0x6A) + pos(*t) + u8(255) + enc.item(TOP)), 'add a top item')
    expect(w.tiles[t][1] == ('i', TOP, None), 'a top item right after the ground')
    expect(w.frame(u8(0x6B) + pos(*t) + u8(2) + enc.item(FLUID, 2)), 'change the stack into a fluid')
    expect(w.tiles[t][2] == ('i', FLUID, 2), 'changed in place')
    expect(w.frame(u8(0x6C) + pos(*t) + u8(1)), 'remove the top item')
    expect(w.tiles[t] == [('i', GROUND, None), ('i', FLUID, 2), ('i', COMMON, None)], 'removed')
    expect(w.frame(u8(0x6A) + pos(*t) + u8(255) + enc.item(ANIM)), 'an item with a phase byte')
    for _ in range(12):
        w.frame(u8(0x6A) + pos(*t) + u8(255) + enc.item(COMMON))
    expect(len(w.tiles[t]) == cr.MAX_THINGS, 'a tile keeps 10 things')
    expect(w.frame(u8(0x69) + pos(*t) + u16(0) + enc.item(GROUND) + enc.item(COMMON) + enc.item(ELEV) + u8(0) +
                   u8(0xFF)), 'a whole tile')
    expect(w.tiles[t] == [('i', GROUND, None), ('i', COMMON, None), ('i', ELEV, None)], 'replaced')
    v = cr.View(w, None, dims)
    tile = v.tile(t, [])
    expect([e[0] for e in tile[2]] == ['i100', 'i103', 'i102'] and tile[4] == 8, 'common items newest first, elevation')
    expect(tile[2][2][2] == 8, 'the item over the elevation is lifted')
    expect(w.frame(u8(0x69) + pos(*t) + u8(1) + u8(0xFF)), 'an empty tile')
    expect(not w.tiles.get(t), 'emptied')
    # patterns
    expect(v.item_pattern(STACK, 7, t) == 1 * 4 + 0, 'a stack of 7: the 5-9 pattern')
    expect(v.item_pattern(STACK, 3, t) == 2, 'a stack of 3')
    expect(v.item_pattern(FLUID, 2, t) == 1 * 4 + 3, 'fluid byte 2 is read as mana: purple')
    expect(v.item_pattern(GROUND, None, t) == 0, 'a 1 x 1 pattern')
    v.lines()
    w.frame(u8(0x6A) + pos(*t) + u8(255) + enc.item(COMMON))
    expect([ln['t'] for ln in v.lines()] == ['d'], 'tile changes make a delta')


def replacing(creature, gone):
    """an unknown creature (0x61) that makes the client forget a known one"""
    return creature[:2] + u32(gone) + creature[6:]


def test_creatures(items, dims):
    enc = Enc(marker=1100)
    w = cr.World(items, dims)
    tiles = base_tiles(enc)
    tiles[(PX + 2, PY, PZ)] = [enc.item(GROUND), enc.creature(0x40000001, name='Rat', ctype=1, speed=80)]
    start(w, enc, tiles)
    rat = 0x40000001
    expect(w.creatures[rat]['n'] == 'Rat' and w.creatures[rat]['p'] == (PX + 2, PY, PZ), 'a monster on the map')
    w.reset_changes()
    expect(w.frame(u8(0x6D) + u16(0xFFFF) + u32(rat) + pos(PX + 3, PY + 1, PZ)), 'a move by creature id')
    expect(w.creatures[rat]['p'] == (PX + 3, PY + 1, PZ), 'moved')
    expect(w.walks[0][5] == cr.step_ms(80, 100, True, False), 'a diagonal monster step')
    expect(w.frame(u8(0x6B) + pos(PX + 3, PY + 1, PZ) + u8(1) + u16(0x63) + u32(rat) + u8(3) + u8(1)), 'a turn')
    expect(w.creatures[rat]['d'] == 3 and w.creatures[rat]['p'] == (PX + 3, PY + 1, PZ), 'faces west, same tile')
    for byte, col in ((4, 1), (5, 1), (6, 3), (7, 3)):
        expect(w.frame(u8(0x6B) + pos(PX + 3, PY + 1, PZ) + u8(1) + u16(0x63) + u32(rat) + u8(byte) + u8(1)),
               'a diagonal turn (src-patch 0077)')
        expect(w.creatures[rat]['d'] == col, 'diagonal %d draws as column %d' % (byte, col))
    expect(w.frame(u8(0x8C) + u32(rat) + u8(40)), 'health')
    expect(w.creatures[rat]['hp'] == 40, 'health 40')
    expect(w.frame(u8(0x8D) + u32(rat) + u8(3) + u8(215)), 'creature light')
    expect(w.frame(u8(0x8E) + u32(rat) + enc.outfit(look=0, ex=COMMON)), 'outfit: an item look')
    expect(w.creatures[rat]['o'].get('x') == COMMON, 'look type ex')
    expect(w.frame(u8(0x8F) + u32(rat) + u16(80) + u16(300)), 'speed')
    expect(w.creatures[rat]['sp'] == 300, 'speed 300')
    for op, key in ((0x90, 'sk'), (0x91, 'sh'), (0x92, None), (0x95, 'ty')):
        expect(w.frame(u8(op) + u32(rat) + u8(4)), 'byte field %#x' % op)
        if key:
            expect(w.creatures[rat][key] == 4, key + ' set')
    expect(w.frame(u8(0x93) + u32(rat) + u8(1) + u8(180)), 'square')
    expect(w.frame(u8(0x8C) + u32(0x7777) + u8(1)), 'an unknown creature id is ignored')
    expect(w.frame(u8(0x6C) + u16(0xFFFF) + u32(rat)), 'removed by id')
    expect(w.creatures[rat]['p'] is None, 'off the map, still known')
    # a known creature comes back in full (0x62)
    expect(w.frame(u8(0x6A) + pos(PX + 1, PY + 1, PZ) + u8(255) + enc.creature(rat, known=True, hp=10)), 'known again')
    expect(w.creatures[rat]['p'] == (PX + 1, PY + 1, PZ) and w.creatures[rat]['hp'] == 10, 'back')
    # 0x61 replacing a known creature
    expect(w.frame(u8(0x6A) + pos(PX - 1, PY, PZ) + u8(255) + replacing(enc.creature(0x40000002, name='Wolf', ctype=1), rat)),
           'a new creature that replaces a known one')
    expect(rat not in w.creatures and w.creatures[0x40000002]['n'] == 'Wolf', 'the old one is forgotten')
    v = cr.View(w, None, dims)
    lines = v.lines()
    expect(any('cr' in ln for ln in lines), 'creature changes go out')


def test_events(items, dims):
    enc = Enc()
    w = cr.World(items, dims)
    w.impact = True
    start(w, enc)
    w.impact = True
    w.reset_changes()
    w.full = False
    expect(w.frame(u8(0x82) + u8(40) + u8(215)), 'world light')
    expect(w.light == [40, 215], 'light kept')
    expect(w.frame(u8(0x83) + pos(PX, PY, PZ) + u16(1)), 'an effect (u16 type)')
    expect(w.frame(u8(0x83) + pos(PX, PY, PZ - 1) + u16(1)), 'an effect on another floor')
    expect(w.fx == [[PX, PY, 1]], 'only the camera floor')
    expect(w.frame(u8(0x85) + pos(PX, PY, PZ) + pos(PX + 3, PY - 3, PZ) + u8(1)), 'a missile')
    expect(w.mi == [[PX, PY, PX + 3, PY - 3, 1]], 'kept')
    expect(w.frame(u8(0x84) + pos(PX, PY, PZ) + u8(180) + text('+12')), 'animated text')
    expect(w.frame(u8(0xB4) + u8(23) + pos(PX, PY, PZ) + u32(50) + u8(180) + u32(7) + u8(35) + u16(100) + u8(1) +
                   u32(PID) + text('You deal 57 damage.')), 'damage numbers with the typed fields')
    expect(w.frame(u8(0xB4) + u8(25) + pos(PX, PY, PZ) + u32(9) + u8(30) + u16(0) + u8(0) + u32(0) + text('heal')),
           'a heal')
    expect(w.frame(u8(0xB4) + u8(26) + pos(PX, PY, PZ) + u32(1000) + u8(215) + u16(0) + u8(0) + u32(0) + text('xp')),
           'experience')
    expect(w.frame(u8(0xB4) + u8(33) + u16(5) + text('guild')), 'a channel text message')
    expect(w.frame(u8(0xB4) + u8(19) + text('look')), 'another text message')
    expect([t[3] for t in w.tx] == ['+12', '50', '7', '9', '1000'], 'the numbers over the tiles')
    expect(w.frame(u8(0xAA) + u32(1) + text('Bob') + u16(8) + u8(1) + pos(PX, PY, PZ) + text('hello')), 'speech')
    expect(w.say == [[PX, PY, 1, 'Bob', 'hello']], 'speech kept')
    try:
        w.frame(u8(0xAA) + u32(1) + text('Bob') + u16(8) + u8(4) + pos(PX, PY, PZ) + text('x'))
        expect(False, 'a private speech type is refused')
    except cr.ParseError:
        pass
    stats = (u8(0xA0) + u32(150) + u32(200) + u32(12345) + u32(40000) + struct.pack('<Q', 999) + u16(30) + u8(50) +
             u16(100) + u16(0) * 3 + u16(100) + u32(70) + u32(90) + u8(5) + u8(5) + u8(10) + u8(100) + u16(2520) +
             u16(110) + u16(0) + u16(0) + u16(0) + u8(0))
    expect(w.frame(stats), 'stats')
    expect(w.stats == {'hp': 150, 'mhp': 200, 'mp': 70, 'mmp': 90, 'lvl': 30, 'cap': 123, 'spd': 220}, 'stats read')
    v = cr.View(w, None, dims)
    d = v.lines()[-1]
    expect(all(k in d for k in ('fx', 'mi', 'tx', 'say', 'st', 'light')), 'all events in the delta')
    expect(d['mi'][0][5] == 2 and d['mi'][0][6] == int(150 * (18 ** 0.5)), 'missile pattern (north-east), duration')


def test_floors(items, dims):
    for marker in (0, 1100):
        enc = Enc(marker=marker)
        w = cr.World(items, dims)
        under = base_tiles(enc, z=8)
        body = u8(0x64) + pos(PX, PY, 8) + enc.area(under, PX - 8, PY - 6, 8, 18, 14)
        w.hello(hello(marker=marker))
        expect(w.frame(body), 'an underground map (%d)' % marker)
        # up to the surface: 0xBE (floors 5..0 only without the marker), then the west and north slices
        up = u8(0xBE)
        if not marker:
            body6 = b''
            skip = -1
            for fl in range(5, -1, -1):
                b, skip = enc.floor({}, PX - 8, PY - 6, fl, 18, 14, 8 - fl, skip)
                body6 += b
            if skip >= 0:
                body6 += u8(skip) + u8(0xFF)
            up += body6
        cx, cy = PX + 1, PY + 1
        west = {(cx - 1 - 8, cy - 6 + k, 7): [enc.item(GROUND)] for k in range(14)}
        up += u8(0x68) + enc.area(west, cx - 1 - 8, cy - 6, 7, 1, 14)
        north = {(cx - 1 - 8 + k, cy - 1 - 6, 7): [enc.item(GROUND)] for k in range(18)}
        up += u8(0x65) + enc.area(north, cx - 1 - 8, cy - 1 - 6, 7, 18, 1)
        expect(w.frame(up), 'floor up to the surface (%d)' % marker)
        expect(w.central == (PX, PY, 7), 'camera on floor 7 (%d)' % marker)
        expect(w.full, 'a new floor asks for a full line')
        # and down again: 0xBF (floors 8..10 only without the marker), east and south slices
        down = u8(0xBF)
        if not marker:
            skip = -1
            for j, fl in enumerate(range(8, 11)):
                b, skip = enc.floor({}, PX - 8, PY - 6, fl, 18, 14, -1 - j, skip)
                down += b
            if skip >= 0:
                down += u8(skip) + u8(0xFF)
        cx, cy = PX - 1, PY - 1
        down += u8(0x66) + enc.area({}, cx + 1 + 9, cy - 6, 8, 1, 14)
        down += u8(0x67) + enc.area({}, cx + 1 - 8, cy + 7, 8, 18, 1)
        expect(w.frame(down), 'floor down (%d)' % marker)
        expect(w.central == (PX, PY, 8), 'camera on floor 8 (%d)' % marker)
        # deeper: one floor more each way
        expect(w.frame(u8(0xBF) + enc.one_floor({}, PX - 9, PY - 7, 11, 18, 14, -3)), 'floor 9')
        expect(w.central == (PX - 1, PY - 1, 9), 'camera on floor 9')
        expect(w.frame(u8(0xBE) + enc.one_floor({}, PX - 9, PY - 7, 6, 18, 14, 3)), 'back to floor 8')
        expect(w.central == (PX, PY, 8), 'camera on floor 8 again')
    # our client's floors: 0x4B, the player's floor sets the camera
    enc = Enc(marker=1100)
    w = cr.World(items, dims)
    w.hello(hello(marker=1100))
    expect(w.frame(u8(0x42) + u8(17) + u8(13)), 'aware range')
    tiles = base_tiles(enc)
    for fl in range(7, -1, -1):
        body = u8(0x4B) + pos(PX, PY, PZ) + u8(fl) + enc.one_floor(tiles, PX - 8, PY - 6, fl, 18, 14, PZ - fl)
        expect(w.frame(body), 'floor %d as 0x4B' % fl)
    expect(w.central == (PX, PY, PZ) and w.creatures[PID]['p'] == (PX, PY, PZ), 'the view from 0x4B floors')


# ------------------------------------------------------------------------------------------------ phase 3
def tile_msg(enc, x, y, z, *things):
    return u8(0x69) + pos(x, y, z) + u16(0) + b''.join(things) + u16(0xFF00)


def floor_world(items, dims, extra=None, z=PZ):
    """a world with ground under the player and `extra` {(x, y, z): [things]} on other floors"""
    enc = Enc()
    w = cr.World(items, dims)
    tiles = base_tiles(enc, z=z)
    for p, things in (extra or {}).items():
        tiles[p] = things
    body = u8(0x64) + pos(PX, PY, z) + enc.area(tiles, PX - 8, PY - 6, z, 18, 14)
    w.hello(hello())
    w.frame(body)
    return enc, w


def test_visible_floors(items, dims):
    enc = Enc()
    g = [enc.item(GROUND)]
    _e, w = floor_world(items, dims)
    expect(w.floors() == [0, 7], 'open sky: floors 0..7, got %s' % w.floors())
    _e, w = floor_world(items, dims, extra={(PX, PY, 6): g})
    expect(w.floors() == [7, 7], 'a roof directly above: only the camera floor, got %s' % w.floors())
    _e, w = floor_world(items, dims, extra={(PX + 2, PY + 2, 5): g})
    expect(w.floors() == [6, 7], 'a roof two floors up (geometrically above): floors 6..7, got %s' % w.floors())
    _e, w = floor_world(items, dims, extra={(PX + 3, PY + 3, 5): g})
    expect(w.floors() == [0, 7], 'a roof that is not above the player hides nothing, got %s' % w.floors())
    _e, w = floor_world(items, dims, extra={(PX, PY, 6): [enc.item(GLASS)]})
    expect(w.floors() == [0, 7], "a don't-hide ground: floors stay, got %s" % w.floors())
    _e, w = floor_world(items, dims, extra={(PX, PY, 6): [enc.item(WALL)]})
    expect(w.floors() == [7, 7], 'a wall above the player closes it, got %s' % w.floors())
    _e, w = floor_world(items, dims, extra={(PX + 1, PY, 6): g})
    expect(w.floors() == [7, 7], 'a roof above the open east neighbour closes the view, got %s' % w.floors())
    t = base_tiles(enc)
    t[(PX, PY - 1, 6)] = g
    w2 = cr.World(items, dims)
    w2.hello(hello())
    w2.frame(u8(0x64) + pos(PX, PY, PZ) + enc.area(t, PX - 8, PY - 6, PZ, 18, 14))
    expect(w2.floors() == [7, 7], 'a roof above the open north neighbour closes the view, got %s' % w2.floors())
    t[(PX, PY - 1, PZ)] = [enc.item(GROUND), enc.item(CLOSED)]
    w2 = cr.World(items, dims)
    w2.hello(hello())
    w2.frame(u8(0x64) + pos(PX, PY, PZ) + enc.area(t, PX - 8, PY - 6, PZ, 18, 14))
    expect(w2.floors() == [0, 7], 'a neighbour tile that blocks the view is not looked through, got %s' % w2.floors())
    # underground: two floors up and two down of the camera, a ceiling closes it
    t = base_tiles(enc, z=10)
    w = cr.World(items, dims)
    w.hello(hello())
    w.frame(u8(0x64) + pos(PX, PY, 10) + enc.area(t, PX - 8, PY - 6, 10, 18, 14))
    expect(w.floors() == [8, 12], 'underground: camera - 2 .. camera + 2, got %s' % w.floors())
    t[(PX, PY, 9)] = g
    w = cr.World(items, dims)
    w.hello(hello())
    w.frame(u8(0x64) + pos(PX, PY, 10) + enc.area(t, PX - 8, PY - 6, 10, 18, 14))
    expect(w.floors() == [10, 12], 'underground ceiling: from the camera floor down, got %s' % w.floors())
    t = base_tiles(enc, z=15)
    w = cr.World(items, dims)
    w.hello(hello())
    w.frame(u8(0x64) + pos(PX, PY, 15) + enc.area(t, PX - 8, PY - 6, 15, 18, 14))
    expect(w.floors() == [13, 15], 'the lowest floor: no floor below 15, got %s' % w.floors())


def test_floor_lines(dat, spr, items, dims):
    enc = Enc()
    g = [enc.item(GROUND)]
    extra = {(PX + 3, PY + 1, 6): [enc.item(GROUND), enc.item(LAMP)], (PX - 3, PY - 1, 3): g,
             (PX + 1, PY + 5, 6): [enc.item(GROUND), enc.creature(0x20000001, name='Rat')]}
    _e, w = floor_world(items, dims, extra=extra)
    lines = cr.View(w, cr.Sheets(dat, spr), dims).lines()
    full_line = [ln for ln in lines if ln['t'] == 'full'][0]
    expect(full_line['fl'] == [0, 7], 'the full line names the floors: %s' % full_line['fl'])
    zs = sorted((t[0], t[1], t[2]) for t in full_line['ft'])
    expect(zs == [(3, PX - 3, PY - 1), (6, PX + 1, PY + 5), (6, PX + 3, PY + 1)], 'the other floors tiles: %s' % zs)
    expect(all(len(t) == 5 for t in full_line['tiles']), 'tiles stays the camera floor, five fields')
    lamp = [t for t in full_line['ft'] if t[:3] == [6, PX + 3, PY + 1]][0]
    expect([e[0] for e in lamp[3]] == ['i100', 'i107'], 'under entries of a floor tile: %s' % lamp[3])
    expect(full_line['cr'].get(str(0x20000001), {}).get('p') == [PX + 1, PY + 5, 6], 'a creature on another floor')
    keys = {ln['key']: ln for ln in lines if ln['t'] == 'spr'}
    expect(keys['i100'].get('gr') == 1 and 'gr' not in keys['i107'], 'ground flag in the item sheet')
    expect(keys['i107'].get('lt') == [6, 206] and 'lt' not in keys['i100'], 'item light in the sheet')
    # the window: a tile far away on floor 6 is not sent
    _e, w = floor_world(items, dims, extra={(PX + 40, PY, 6): g})
    expect('ft' not in cr.View(w, None, dims).lines()[-1], 'a far tile is left out')
    # a change on another floor: d line with ft; outside the window or on a hidden floor nothing is sent
    _e, w = floor_world(items, dims, extra=extra)
    v = cr.View(w, None, dims)
    v.lines()
    w.frame(tile_msg(enc, PX + 3, PY + 1, 6, enc.item(GROUND)))
    d = v.lines()[-1]
    expect(d['t'] == 'd' and d['ft'] == [[6, PX + 3, PY + 1, [['i100', 0, 0]], [], 0]] and 'fl' not in d
           and 'fc' not in d, 'a tile change on floor 6: %s' % d)
    expect(w.ch_ftiles == set(), 'changes start again')
    w.frame(tile_msg(enc, PX + 3, PY + 1, 6))
    d = v.lines()[-1]
    expect(d['ft'] == [[6, PX + 3, PY + 1, [], [], 0]], 'a tile that became empty is sent empty (the app clears it)')
    w.frame(tile_msg(enc, PX + 50, PY, 6, enc.item(GROUND)))
    expect(v.lines() == [], 'a tile outside the window changes nothing in the line')
    # a roof appears over the player: floors 0..6 leave, the camera floor stays
    w.frame(u8(0x6A) + pos(PX, PY, 6) + u8(255) + enc.item(GROUND))
    d = v.lines()[-1]
    expect(d['fl'] == [7, 7] and 'ft' not in d, 'a roof: only floor 7 now: %s' % d)
    w.frame(tile_msg(enc, PX + 3, PY + 1, 6, enc.item(GROUND)))
    expect(v.lines() == [], 'a change on a hidden floor is not sent')
    # the roof goes: the floors come back whole, the app clears them first
    w.frame(u8(0x6C) + pos(PX, PY, 6) + u8(0))
    d = v.lines()[-1]
    expect(d['fl'] == [0, 7] and d['fc'] == [0, 1, 2, 3, 4, 5, 6], 'the roof goes: floors back, cleared first: %s' % d)
    got = sorted((t[0], t[1], t[2]) for t in d['ft'])
    expect((6, PX + 3, PY + 1) in got and (3, PX - 3, PY - 1) in got and (6, PX + 1, PY + 5) in got,
           'the whole floors are sent again: %s' % got)
    json.dumps(d)
    # an old app keeps working: tiles / fx / mi still hold the camera floor only, the rest are new keys
    expect(set(d) <= {'t', 'fl', 'fc', 'ft', 'tiles', 'c', 'cr', 'st', 'light'}, 'only known or new keys: %s' % set(d))


def test_floor_events(dat, spr, items, dims):
    enc = Enc()
    _e, w = floor_world(items, dims)
    w.reset_changes()
    w.full = False
    w.frame(u8(0x83) + pos(PX + 1, PY, 6) + u16(1))
    w.frame(u8(0x83) + pos(PX + 1, PY, PZ) + u16(1))
    w.frame(u8(0x85) + pos(PX, PY, 5) + pos(PX + 3, PY, 5) + u8(1))
    w.frame(u8(0x85) + pos(PX, PY, PZ) + pos(PX + 3, PY, PZ) + u8(1))
    expect(w.fx == [[PX + 1, PY, 1]] and w.fxf == [[PX + 1, PY, 1, 6]], 'effects: camera floor and others apart')
    expect(w.mi == [[PX, PY, PX + 3, PY, 1]] and w.mif == [[PX, PY, PX + 3, PY, 1, 5]], 'missiles likewise')
    lines = cr.View(w, cr.Sheets(dat, spr), dims).lines()
    d = lines[-1]
    expect(d['fx'] == [[PX + 1, PY, 'e1', 0]] and d['fxf'] == [[PX + 1, PY, 'e1', 0, 6]], 'fx and fxf lines: %s' % d)
    expect(d['mi'][0][:5] == [PX, PY, PX + 3, PY, 'm1'] and d['mif'][0][7] == 5 and d['mif'][0][5] == 5,
           'mi and mif lines: %s' % d)
    sp = {ln['key']: ln for ln in lines if ln['t'] == 'spr'}
    expect(sp['e1'].get('lt') == [3, 215] and 'lt' not in sp['m1'], 'an effect that shines carries its light')
    # floors hidden by a roof: their effects are dropped
    _e, w = floor_world(items, dims, extra={(PX, PY, 6): [enc.item(GROUND)]})
    v = cr.View(w, None, dims)
    v.lines()
    w.frame(u8(0x83) + pos(PX + 1, PY, 3) + u16(1))
    w.frame(u8(0x85) + pos(PX, PY, 3) + pos(PX + 3, PY, 3) + u8(1))
    expect(v.lines() == [], 'effects on floors hidden by a roof are not sent')
    for _ in range(300):
        w.frame(u8(0x83) + pos(PX, PY, 2) + u16(1))
    expect(len(w.fxf) <= 200, 'bounded')


def test_light_lines(dat, spr, items, dims):
    enc = Enc()
    w = cr.World(items, dims)
    w.hello(hello())
    tiles = base_tiles(enc)
    w.frame(u8(0x64) + pos(PX, PY, PZ) + enc.area(tiles, PX - 8, PY - 6, PZ, 18, 14))
    w.frame(u8(0x82) + u8(40) + u8(215))
    v = cr.View(w, None, dims)
    full_line = [ln for ln in v.lines() if ln['t'] == 'full'][0]
    expect(full_line['light'] == [40, 215], 'world light in the full line')
    expect('lt' not in full_line['cr'][str(PID)], 'no light, no key')
    w.frame(u8(0x8D) + u32(PID) + u8(7) + u8(206))
    d = v.lines()[-1]
    expect(d['cr'][str(PID)]['lt'] == [7, 206], 'creature light in the delta: %s' % d)
    w.frame(u8(0x8D) + u32(PID) + u8(0) + u8(0))
    d = v.lines()[-1]
    expect('lt' not in d['cr'][str(PID)], 'the light went out: the key is gone')
    s = cr.Session(items, dims, None)
    out = s.feed(framed(hello()))
    expect(out[0]['v'] == cr.PROTOCOL == 3 and out[0]['t'] == 'hello', 'the hello line carries the version')
    expect(cr.light_of({'light': (0, 5)}) is None and cr.light_of({}) is None
           and cr.light_of({'light': (8, 215)}) == [8, 215], 'light_of')


def test_errors(items, dims):
    enc = Enc()
    w = cr.World(items, dims)
    start(w, enc)
    expect(w.frame(u8(0x83) + pos(PX, PY, PZ) + u16(1) + u8(0xEE) + b'junk') is False, 'an unknown opcode ends a frame')
    for bad in (u8(0x83) + pos(PX, PY, PZ), u8(0x6A) + pos(PX, PY, PZ) + u8(255) + u16(9999) + u8(0xFF),
                u8(0x65), u8(0xAA) + u32(1) + u16(5000)):
        try:
            w.frame(bad)
            expect(False, 'a broken frame raises ParseError: %r' % bad[:8])
        except cr.ParseError:
            pass
    w2 = cr.World(items, dims)
    try:
        w2.frame(u8(0x65))
        expect(False, 'a move before the map')
    except cr.ParseError:
        pass
    s = cr.Session(items, dims, None, 'Alice')
    try:
        s.feed(framed(hello('Bob')))
        expect(False, 'another target is refused')
    except cr.WrongTarget:
        pass
    s = cr.Session(items, dims, None, 'bob')
    lines = s.feed(framed(hello('Bob'))[:5])
    expect(lines == [], 'half a frame waits')
    lines = s.feed(framed(hello('Bob'))[5:])
    expect(lines and lines[0]['t'] == 'hello' and lines[0]['name'] == 'Bob', 'a hello line (name case blind)')
    try:
        cr.Session(items, dims, None).feed(framed(u8(0x83) + pos(1, 1, 7) + u16(1)))
        expect(False, 'no hello first')
    except cr.ParseError:
        pass
    try:
        cr.Frames().feed(b'\x00\x00')
        expect(False, 'an empty frame')
    except cr.ParseError:
        pass
    for good in ('Bob', "Sir O'Neil", 'Anna-Lee Smith'):
        expect(cr.valid_name(good), 'name ok: ' + good)
    for bad in ('ab', 'a' * 30, 'Bob ', 'Bo  b', '1bc', 'Bob;id', 'B$(id)', 'Bób', ' Bob'):
        expect(not cr.valid_name(bad), 'name refused: ' + bad)


def test_fuzz(items, dims):
    rnd = random.Random(1098)
    enc = Enc()
    ops = list(cr.OPS) + [0x00, 0x17, 0xEE]
    n = 0
    for _ in range(3000):
        w = cr.World(items, dims)
        start(w, enc)
        for _k in range(3):
            body = bytes([rnd.choice(ops)]) + bytes(rnd.randrange(256) for _ in range(rnd.randrange(0, 40)))
            try:
                w.frame(body)
            except cr.ParseError:
                n += 1
            except Exception as e:  # noqa: BLE001
                expect(False, 'fuzz: %s on %s' % (type(e).__name__, body[:12].hex()))
                return
        try:
            cr.View(w, None, dims).lines()
        except Exception as e:  # noqa: BLE001
            expect(False, 'fuzz lines: %s' % type(e).__name__)
            return
    expect(n > 0, 'the fuzz hit broken frames')
    s = cr.Session(items, dims, None)
    for _ in range(500):
        try:
            s.feed(bytes(rnd.randrange(256) for _ in range(rnd.randrange(1, 64))))
        except (cr.ParseError, cr.WrongTarget):
            s = cr.Session(items, dims, None)
        except Exception as e:  # noqa: BLE001
            expect(False, 'stream fuzz: %s' % type(e).__name__)
            return


def png(line):
    return Image.open(io.BytesIO(base64.b64decode(line['png']))).convert('RGBA')


def test_sheets(dat, spr, items, dims):
    sh = cr.Sheets(dat, spr)
    st = sh.item(STACK)
    expect(st['np'] == 8 and st['nf'] == 1 and png(st).size == (32, 8 * 32), 'stack sheet: 8 patterns')
    expect(png(st).getpixel((5, 32 * 3 + 5))[:3] == (80, 0, 0), 'row 3 is the fourth stack pattern')
    an = sh.item(ANIM)
    expect(an['nf'] == 2 and png(an).size == (64, 32) and an['fd'] == 100, 'two frames side by side')
    el = sh.item(ELEV)
    expect(el['el'] == 8, 'the elevation in the meta')
    fx = sh.effect(1)
    expect(fx['nf'] == 3 and png(fx).getpixel((70, 5))[:3] == BROWN[:3], 'effect frames')
    mi = sh.missile(1)
    expect(mi['np'] == 9 and png(mi).size == (32, 9 * 32), 'missile: 9 direction patterns')
    expect(sh.effect(9) is None and sh.missile(0) is None and sh.item(5) is None, 'unknown things: nothing')
    o = {'t': 1, 'h': 0, 'b': 0, 'l': 0, 'f': 0, 'a': 0, 'm': 0}
    ol = sh.outfit(o)
    expect(ol['ni'] == 1 and ol['nw'] == 2 and png(ol).size == (3 * 32, 4 * 32), 'outfit: 4 rows, idle + 2 walking')
    white = png(ol).getpixel((5, 5))[:3]
    red = png(sh.outfit(dict(o, h=94))).getpixel((5, 5))[:3]
    expect(white != red, 'the head colour tints the template')
    import gen_sprite_images as gsi
    c = gsi.outfit_colour(94)
    expect(red == tuple((200 * v + 127) // 255 for v in c), 'tinted as the client does')
    expect(sh.outfit(dict(o, t=9)) is None, 'an unknown look: nothing')
    expect(sh.need('x', lambda: {'t': 'spr'}) == {'t': 'spr'} and sh.need('x', lambda: {}) is None, 'once per run')
    bad = sh.need('y', lambda: 1 / 0)
    expect(bad['t'] == 'sprerr' and bad['key'] == 'y' and 'ZeroDivisionError' in bad['why'], 'a broken thing is said')
    expect(sh.need('y', lambda: 1 / 0) is None, 'and said once')
    expect(sh.need('z', lambda: None) == {'t': 'sprerr', 'key': 'z', 'why': 'none'}, 'no such thing in the pair: said')
    expect(sh.errors == 2, 'the errors are counted')
    lim = cr.Sheets(dat, spr)
    lim.sent = set('k%d' % n for n in range(cr.MAX_SHEETS))
    expect(lim.need('over', lambda: {'t': 'spr'}) == {'t': 'sprerr', 'key': 'over', 'why': 'limit'}, 'the limit is said')
    # a full line names its sheets first
    enc = Enc()
    w = cr.World(items, dims)
    tiles = base_tiles(enc)
    tiles[(PX + 1, PY, PZ)] = [enc.item(GROUND), enc.item(STACK, 30)]
    start(w, enc, tiles)
    w.frame(u8(0x83) + pos(PX, PY, PZ) + u16(1))
    lines = cr.View(w, cr.Sheets(dat, spr), dims).lines()
    kinds = [ln['t'] for ln in lines]
    keys = [ln.get('key') for ln in lines if ln['t'] == 'spr']
    expect(kinds.index('full') > kinds.index('spr'), 'sheets before the full line')
    expect({'i100', 'i104', 'o1.10.20.30.40.0.0', 'e1'} <= set(keys), 'the sheets it needs: %s' % keys)
    full_line = [ln for ln in lines if ln['t'] == 'full'][0]
    t = [tl for tl in full_line['tiles'] if tl[:2] == [PX + 1, PY]][0]
    expect(t[2][1][:2] == ['i104', 6], 'a stack of 30: pattern 2,1')
    expect(full_line['cr'][str(PID)]['o'] == 'o1.10.20.30.40.0.0', 'the player names its outfit sheet')
    json.dumps(lines)


def test_black_view_is_not_silent(dat, spr, items, dims):
    """2026-10-26 owner report: names and health bars but no ground, items or outfits. A sheet that fails to draw (a
    missing PIL, a broken thing) used to vanish without a line, so the app could not tell it from a dark map."""
    enc = Enc()
    w = cr.World(items, dims)
    start(w, enc, base_tiles(enc))
    real = cr.png_b64

    def broken(_arr):
        raise ImportError('No module named PIL')
    cr.png_b64 = broken
    try:
        lines = cr.View(w, cr.Sheets(dat, spr), dims).lines()
    finally:
        cr.png_b64 = real
    errs = [ln for ln in lines if ln['t'] == 'sprerr']
    expect(not [ln for ln in lines if ln['t'] == 'spr'], 'no sheet could be drawn')
    expect(errs and all('ImportError' in e['why'] for e in errs), 'every failed sheet is a sprerr line: %s' % errs[:1])
    expect({'i100', 'o1.10.20.30.40.0.0'} <= {e['key'] for e in errs}, 'the ground and the outfit are named')
    expect([ln for ln in lines if ln['t'] == 'full'], 'the full line still goes out')
    json.dumps(lines)


def serve(frames, hold=0.3):
    srv = socket.socket()
    srv.bind(('127.0.0.1', 0))
    srv.listen(1)
    port = srv.getsockname()[1]

    def go():
        try:
            c, _ = srv.accept()
            c.sendall(b''.join(frames))
            threading.Event().wait(hold)
            c.close()
        finally:
            srv.close()
    threading.Thread(target=go, daemon=True).start()
    return port


def test_loop(dat_path, spr_path, dat, spr, items, dims):
    enc = Enc()
    tiles = base_tiles(enc)
    body = u8(0x64) + pos(PX, PY, PZ) + enc.area(tiles, PX - 8, PY - 6, PZ, 18, 14)
    port = serve([framed(hello()), framed(body), framed(u8(0x83) + pos(PX, PY, PZ) + u16(1))])
    buf = io.StringIO()
    why = cr.run(port, items, dims, cr.Sheets(dat, spr), cr.Out(buf), 'Bob', max_seconds=1)
    lines = [json.loads(ln) for ln in buf.getvalue().splitlines()]
    kinds = [ln['t'] for ln in lines]
    expect(why == 'time', 'the run ends at its time limit')
    expect(kinds[0] == 'hello' and 'full' in kinds and 'spr' in kinds, 'hello, sheets, full: %s' % kinds[:6])
    expect(any(ln['t'] == 'd' and 'fx' in ln for ln in lines), 'the effect after the map')
    # no port: wait lines, and stdin closing ends it
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    free = s.getsockname()[1]
    s.close()
    r, wfd = os.pipe()
    os.close(wfd)
    buf = io.StringIO()
    why = cr.run(free, items, dims, None, cr.Out(buf), None, max_seconds=5, stdin_fd=r)
    os.close(r)
    expect(why == 'stdin', 'stdin closed: the relay stops')
    expect(json.loads(buf.getvalue().splitlines()[0]) == {'t': 'wait', 'why': 'port'}, 'a wait line')
    # a broken stream: resync, then it connects again
    port = serve([framed(hello()), framed(u8(0x65))])
    buf = io.StringIO()
    cr.run(port, items, dims, None, cr.Out(buf), None, max_seconds=1)
    expect('"t":"resync"' in buf.getvalue(), 'a broken frame: resync')
    # main: a bad name or port never connects
    for args in (['--port', '0'], ['--name', 'x;id']):
        out = io.StringIO()
        old = sys.stdout
        sys.stdout = out
        try:
            rc = cr.main(['--port', '7179', '--dat', dat_path, '--spr', spr_path] + args)
        finally:
            sys.stdout = old
        expect(rc == 2 and '"t":"end"' in out.getvalue(), 'refused: %s' % args)


def test_numbers():
    expect(cr.step_ms(110, 150, False, True) % 10 == 0 and cr.step_ms(110, 150, False, False) % 50 == 0,
           'steps round to the server beat')
    expect(cr.step_ms(110, 150, True, True) > cr.step_ms(110, 150, False, True), 'diagonal steps are slower')
    expect(cr.step_ms(1000, 150, False, True) < cr.step_ms(110, 150, False, True), 'faster with more speed')
    expect(cr.step_ms(0, 0, False, True) >= 10, 'never zero')
    expect(cr.missile_pattern(0, 0, 1, 0) == (2, 1) and cr.missile_pattern(0, 0, 0, -1) == (1, 0), 'east, north')
    expect(cr.missile_pattern(0, 0, -1, 1) == (0, 2) and cr.missile_pattern(0, 0, 0, 0) == (1, 1), 'south-west, none')
    expect(cr.stack_xy(1) == (0, 0) and cr.stack_xy(4) == (3, 0) and cr.stack_xy(100) == (3, 1), 'stack patterns')


def main():
    with tempfile.TemporaryDirectory() as tmp:
        dat_path, spr_path = make_pair(os.path.join(tmp, 'pair'))
        dat, spr, items, dims = cr.load_pair(dat_path, spr_path)
        expect(items[STACK].sub and items[FLUID].sub and items[ANIM].phase and not items[GROUND].sub, 'wire rules')
        expect(items[GROUND].prio == 0 and items[TOP].prio == 3 and items[GROUND].speed == 100, 'priorities, speed')
        nodes = [(2000, ANIM, 0, 0), (2001, COMMON, 0, cr.FLAG_ANIMATION)]
        srv = cr.item_types(dat, nodes)
        expect(not srv[ANIM].phase and srv[COMMON].phase, 'items.otb rules win when given')
        test_numbers()
        test_map_and_moves(items, dims)
        test_tiles(items, dims)
        test_creatures(items, dims)
        test_events(items, dims)
        test_floors(items, dims)
        test_visible_floors(items, dims)
        test_floor_lines(dat, spr, items, dims)
        test_floor_events(dat, spr, items, dims)
        test_light_lines(dat, spr, items, dims)
        test_errors(items, dims)
        test_sheets(dat, spr, items, dims)
        test_black_view_is_not_silent(dat, spr, items, dims)
        test_loop(dat_path, spr_path, dat, spr, items, dims)
        test_fuzz(items, dims)
    print('cast_relay_test: %d checks, %d failures' % (COUNT[0], len(FAILS)))
    return 1 if FAILS else 0


if __name__ == '__main__':
    sys.exit(main())
