#!/usr/bin/env python3
"""Offline benchmark for the game packet compression (server/README.md "Packet compression (O209)").

What it measures: the bytes and the CPU time of deflating server-to-client game packets the way
src-patches/0069-packet-compression.patch does it: one raw deflate stream per connection (windowBits -14 by default),
Z_SYNC_FLUSH after every packet, the 4 byte 00 00 FF FF tail cut off, only bodies of at least --min bytes.

Where the packets come from: the byte layouts below are copied from src/protocolgame.cpp of the patched server
(GetTileDescription, GetFloorDescription, AddItem with the Chaos item attribute word, AddCreature, sendFloorDescription,
sendMoveCreature, magic effects, distance shots, text messages, extended opcodes). With --map and --items the tiles are
the real tiles of an installed server's .otbm and items.otb (items go through their client ids and their stackable /
splash flags); without them a synthetic map is used, so the tool also runs on a machine without the base server.
It is NOT a capture of a live session: creature positions, effect ids and JSON payloads are generated.

Run (the numbers in server/README.md came from this):
    python3 -I server/tools/packet_compress_bench.py --map DIR/data/world/WORLD.otbm --items DIR/data/items/items.otb
    python3 -I server/tools/packet_compress_bench.py            # synthetic map
    python3 -I server/tools/packet_compress_bench.py --check    # exit 1 when the gain on map traffic is below --min-gain

Options: --level N (zlib level, default 3), --window N (window bits, default 14), --mem N (memLevel, default 7),
--min N (smallest body that is compressed, default 128), --seed N, --samples N (view centres), --repeat N (timing).
"""

import argparse
import json
import random
import re
import struct
import sys
import time
import zlib

MAX_BODY = 65522  # NetworkMessage::MAX_PROTOCOL_BODY_LENGTH of the patched server (90459 byte buffer, 64 KB packet)
VIEW_W, VIEW_H = 18, 14  # awareRange: left 8, right 9, top 6, bottom 7


# ---------------------------------------------------------------------------------------------------- map and items
_TOKEN = re.compile(rb"\xfd.|\xfe|\xff", re.S)


def _unescape(data):
    return re.sub(rb"\xfd(.)", rb"\1", data, flags=re.S) if b"\xfd" in data else data


def _nodes(blob):
    """Yield (depth, type, data) for every node of an OTB / OTBM tree. data stops at the first child or the end."""
    stack = []
    pos = 0
    pending = None  # (depth, type, start)
    for m in _TOKEN.finditer(blob):
        tok = m.group()
        if tok[0] == 0xFD:
            continue
        if pending is not None:
            depth, ty, start = pending
            yield depth, ty, _unescape(blob[start:m.start()])
            pending = None
        if tok == b"\xfe":
            stack.append(1)
            pending = (len(stack), blob[m.end()], m.end() + 1)
        else:
            if stack:
                stack.pop()


def load_items(path):
    """server id -> (client id, stackable, splash or fluid) from items.otb."""
    blob = open(path, "rb").read()
    table = {}
    for depth, group, data in _nodes(blob):
        if depth != 2 or len(data) < 4:
            continue
        flags = struct.unpack_from("<I", data, 0)[0]
        pos = 4
        server = client = None
        while pos + 3 <= len(data):
            attr, ln = data[pos], struct.unpack_from("<H", data, pos + 1)[0]
            body = data[pos + 3:pos + 3 + ln]
            if attr == 0x10 and ln == 2:
                server = struct.unpack("<H", body)[0]
            elif attr == 0x11 and ln == 2:
                client = struct.unpack("<H", body)[0]
            pos += 3 + ln
        if server and client:
            table[server] = (client, bool(flags & (1 << 7)), group in (11, 12))
    return table


def load_map(path, items, sample_mod):
    """tiles[(x, y, z)] = list of server item ids (ground first) for a deterministic sample of 256x256 areas."""
    blob = open(path, "rb").read()
    tiles = {}
    area = None
    keep = False
    tile = None
    for depth, ty, data in _nodes(blob):
        if ty == 4 and len(data) >= 5:
            ax, ay, az = struct.unpack_from("<HHB", data, 0)
            area = (ax, ay, az)
            keep = ((ax >> 8) * 7 + (ay >> 8) * 13) % sample_mod == 0 and az <= 7
        elif ty in (5, 14) and keep and len(data) >= 2:
            tile = (area[0] + data[0], area[1] + data[1], area[2])
            ids = []
            pos = 6 if ty == 14 else 2
            while pos < len(data):
                attr = data[pos]
                pos += 1
                if attr == 3:
                    pos += 4
                elif attr == 9 and pos + 2 <= len(data):
                    ids.append(struct.unpack_from("<H", data, pos)[0])
                    pos += 2
                else:
                    break
            tiles[tile] = ids
        elif ty == 6 and keep and tile is not None and len(data) >= 2 and depth == 5:
            tiles[tile].append(struct.unpack_from("<H", data, 0)[0])
    return {k: [i for i in v if i in items][:10] for k, v in tiles.items() if v}


def synthetic_map(rng, items):
    """A town-like and a wilderness-like block: ground, borders, some walls, trees, loot. Deterministic by rng."""
    tiles = {}
    for x in range(0, 120):
        for y in range(0, 120):
            for z in range(0, 8):
                if z == 7:
                    ids = [rng.choice((1, 2, 3, 4))]
                    if rng.random() < 0.15:
                        ids.append(rng.choice((10, 11, 12, 13)))
                    if rng.random() < 0.05:
                        ids.append(rng.randint(20, 60))
                    if (x // 12 + y // 12) % 3 == 0 and rng.random() < 0.6:
                        ids = [5, rng.choice((70, 71, 72)), rng.randint(80, 140)]
                    tiles[(x + 1000, y + 1000, z)] = ids
                elif x % 30 < 18 and y % 30 < 18 and rng.random() < 0.5:
                    tiles[(x + 1000, y + 1000, z)] = [rng.randint(200, 230), rng.randint(231, 260)]
    return tiles


# ---------------------------------------------------------------------------------------------------- byte layouts
def pos(x, y, z):
    return struct.pack("<HHB", x & 0xFFFF, y & 0xFFFF, z)


def add_item(items, item_id, chaos_attr=True, rng=None):
    client, stack, fluid = items.get(item_id, (item_id, False, False))
    out = struct.pack("<H", client) + b"\xff"
    if stack:
        out += bytes([rng.choice((1, 1, 1, 2, 5, 20, 100))])
    elif fluid:
        out += bytes([rng.randint(0, 11)])
    if chaos_attr:
        out += b"\x00\x00"  # AddItem: u16 custom attribute word (chaosItemAttributes)
    return out


CREATURE_NAMES = ["Rotworm", "Cyclops", "Dragon", "Troll", "Wolf", "Ember Priest", "Ashen Knight", "Bone Hound"]


def add_creature(rng, known, ids):
    cid = rng.choice(ids)
    out = struct.pack("<H", 0x62 if known else 0x61)
    if known:
        out += struct.pack("<I", cid)
    else:
        name = rng.choice(CREATURE_NAMES)
        name += " [%d]" % rng.randint(20, 400)
        out += struct.pack("<II", 0, cid) + bytes([2]) + struct.pack("<H", len(name)) + name.encode()
    out += bytes([rng.randint(1, 100), rng.randint(0, 3)])  # health percent, direction
    out += struct.pack("<H", rng.randint(1, 400)) + bytes([rng.randint(0, 132) for _ in range(5)]) + struct.pack("<H", 0)
    out += bytes([0, 0]) + struct.pack("<H", 220)  # light level, colour, step speed / 2
    out += bytes([0, 0]) + (bytes([0]) if not known else b"") + bytes([1, 0, 0xFF]) + struct.pack("<H", 0) + b"\x01"
    return out


def tile_bytes(tiles, items, key, rng, crowd, ids):
    out = b"\x00\x00"  # environmental effects
    for item_id in tiles[key][:10]:
        out += add_item(items, item_id, rng=rng)
    if crowd and rng.random() < crowd:
        out += add_creature(rng, rng.random() < 0.7, ids)
    return out


def floor_description(tiles, items, x, y, z, w, h, offset, skip, rng, crowd, ids):
    out = bytearray()
    for nx in range(w):
        for ny in range(h):
            key = (x + nx + offset, y + ny + offset, z)
            if key in tiles:
                if skip >= 0:
                    out += bytes([skip, 0xFF])
                skip = 0
                out += tile_bytes(tiles, items, key, rng, crowd, ids)
            elif skip == 0xFE:
                out += b"\xff\xff"
                skip = -1
            else:
                skip += 1
    return bytes(out), skip


def map_description(tiles, items, x, y, z, w, h, rng, crowd, ids):
    out = bytearray()
    skip = -1
    for nz in range(7, -1, -1):
        part, skip = floor_description(tiles, items, x, y, nz, w, h, z - nz, skip, rng, crowd, ids)
        out += part
    if skip >= 0:
        out += bytes([skip, 0xFF])
    return bytes(out)


def full_view(tiles, items, cx, cy, rng, ids):
    """sendMapDescription for this client family: one 0x4B message per floor 7..0."""
    msgs = []
    for nz in range(7, -1, -1):
        body, skip = floor_description(tiles, items, cx - 8, cy - 6, nz, VIEW_W, VIEW_H, 7 - nz, -1, rng, 0.02, ids)
        if skip >= 0:
            body += bytes([skip, 0xFF])
        msgs.append(b"\x4b" + pos(cx, cy, 7) + bytes([nz]) + body)
    return msgs


def step(tiles, items, cx, cy, d, rng, ids):
    """sendMoveCreature of the player: 0x6D plus the new row or column of the view."""
    nx, ny = cx + (d == 3) - (d == 1), cy + (d == 2) - (d == 0)
    msg = b"\x6d" + pos(cx, cy, 7) + b"\x01" + pos(nx, ny, 7)
    if d == 0:
        msg += b"\x65" + map_description(tiles, items, cx - 8, ny - 6, 7, VIEW_W, 1, rng, 0.03, ids)
    elif d == 2:
        msg += b"\x67" + map_description(tiles, items, cx - 8, ny + 7, 7, VIEW_W, 1, rng, 0.03, ids)
    elif d == 3:
        msg += b"\x66" + map_description(tiles, items, nx + 9, ny - 6, 7, 1, VIEW_H, rng, 0.03, ids)
    else:
        msg += b"\x68" + map_description(tiles, items, nx - 8, ny - 6, 7, 1, VIEW_H, rng, 0.03, ids)
    return msg, nx, ny


def combat_tick(cx, cy, rng, ids, effects):
    """what one 10 ms flush of a hunt can hold: effects, shots, health, damage text, stats, a creature move."""
    msgs = []
    for _ in range(rng.randint(1, 4)):
        msgs.append(b"\x83" + pos(cx + rng.randint(-5, 5), cy + rng.randint(-4, 4), 7) + struct.pack("<H", rng.choice(effects)))
    if rng.random() < 0.6:
        msgs.append(b"\x85" + pos(cx, cy, 7) + pos(cx + rng.randint(-6, 6), cy + rng.randint(-5, 5), 7) + bytes([rng.randint(1, 40)]))
    for _ in range(rng.randint(0, 3)):
        msgs.append(b"\x8c" + struct.pack("<I", rng.choice(ids)) + bytes([rng.randint(1, 100)]))
    if rng.random() < 0.8:
        text = "A %s loses %d hitpoints due to your attack." % (rng.choice(CREATURE_NAMES).lower(), rng.randint(100, 90000))
        msgs.append(b"\xb4\x15" + pos(cx + 1, cy, 7) + struct.pack("<IB", rng.randint(100, 90000), rng.randint(1, 20))
                    + struct.pack("<IB", 0, 0) + struct.pack("<HBI", rng.randint(0, 10000), rng.randint(0, 3), rng.choice(ids))
                    + struct.pack("<H", len(text)) + text.encode())
    if rng.random() < 0.5:
        msgs.append(b"\x6d" + pos(cx + rng.randint(-5, 5), cy + rng.randint(-4, 4), 7) + b"\x01" + pos(cx + rng.randint(-5, 5), cy + rng.randint(-4, 4), 7))
    if rng.random() < 0.4:
        msgs.append(b"\xa0" + struct.pack("<IIII", rng.randint(1, 10**6), 10**6, rng.randint(1, 5000), 5000) + struct.pack("<Q", rng.randint(10**9, 10**10))
                    + struct.pack("<HHH", rng.randint(100, 900), rng.randint(0, 100), rng.randint(100, 900)) + bytes(rng.randint(0, 255) for _ in range(40)))
    return msgs


def extended_json(rng, kind):
    """0x32 opcode string: the shapes of the cooldown, stash/store list and hud modules (generated values)."""
    if kind == 0:
        obj = {"cd": [{"id": rng.randint(1, 600), "g": rng.randint(0, 3), "left": rng.randint(100, 9000), "total": 9000} for _ in range(rng.randint(3, 10))]}
    elif kind == 1:
        obj = {"page": rng.randint(1, 9), "items": [{"id": rng.randint(2000, 40000), "count": rng.randint(1, 500), "name": "Chaos Shard %d" % rng.randint(1, 40),
                                                      "rarity": rng.choice(("common", "rare", "epic")), "locked": False} for _ in range(rng.randint(8, 24))]}
    else:
        obj = {"hud": {"hp": rng.randint(1, 10**6), "mp": rng.randint(1, 5000), "buffs": [{"k": "buff_%d" % rng.randint(1, 30), "t": rng.randint(1, 600)} for _ in range(rng.randint(0, 6))]}}
    text = json.dumps(obj, separators=(",", ":")).encode()
    return b"\x32" + bytes([rng.randint(100, 200)]) + struct.pack("<H", len(text)) + text


# ---------------------------------------------------------------------------------------------------- measuring
class Stream:
    """One connection: what Protocol::compressBody does."""

    def __init__(self, level, window, mem, minimum):
        self.z = zlib.compressobj(level, zlib.DEFLATED, -window, mem)
        self.minimum = minimum
        self.raw = self.wire = self.packets = self.compressed = 0
        self.seconds = 0.0

    @staticmethod
    def wire_size(body):
        return 2 + 4 + ((2 + body + 7) // 8) * 8  # u16 length, u32 adler / zero flag, XTEA blob (u16 inner length, padded)

    def send(self, body):
        self.packets += 1
        self.raw += self.wire_size(len(body))
        if len(body) < self.minimum:
            self.wire += self.wire_size(len(body))
            return
        t = time.perf_counter()
        out = self.z.compress(body) + self.z.flush(zlib.Z_SYNC_FLUSH)
        self.seconds += time.perf_counter() - t
        assert out.endswith(b"\x00\x00\xff\xff")
        self.compressed += 1
        self.wire += self.wire_size(len(out) - 4)


def packets(msgs):
    """the output buffer: messages are appended until the next one would pass MAX_BODY, then it is sent."""
    cur = b""
    for m in msgs:
        if cur and len(cur) + len(m) > MAX_BODY:
            yield cur
            cur = b""
        cur += m
    if cur:
        yield cur


def run(args):
    rng = random.Random(args.seed)
    items = {}
    if args.map and args.items:
        items = load_items(args.items)
        tiles = load_map(args.map, items, args.sample_mod)
        source = "real map (%d tiles of sampled areas)" % len(tiles)
    else:
        tiles = synthetic_map(rng, items)
        source = "synthetic map (%d tiles)" % len(tiles)
    ground = [k for k in tiles if k[2] == 7]
    centres = []
    rng.shuffle(ground)
    for (x, y, _) in ground:
        window = sum(1 for dx in range(-8, 10, 3) for dy in range(-6, 8, 3) if (x + dx, y + dy, 7) in tiles)
        if window >= 20 and all((x + dx, y + dy, 7) in tiles for dx, dy in ((-30, 0), (30, 0), (0, -30), (0, 30))):
            centres.append((x, y))
        if len(centres) == args.samples:
            break
    if not centres:
        sys.exit("no view centre found in the map sample")
    ids = [0x10000000 + i for i in range(30)]
    effects = [rng.randint(1, 900) for _ in range(40)]

    def make():
        return Stream(args.level, args.window, args.mem, args.min)

    scen = {}
    # 1. entering the game / a teleport: the 8 floors of one view
    s = make()
    for cx, cy in centres:
        s = s if s.packets == 0 else s
        for p in packets(full_view(tiles, items, cx, cy, rng, ids)):
            s.send(p)
    scen["full view (login, teleport): 8 floors"] = s
    # 2. walking: 40 steps in one direction per centre, one packet per step (the 10 ms flush)
    s = make()
    for cx, cy in centres:
        x, y, d = cx, cy, rng.randint(0, 3)
        for _ in range(40):
            msg, x, y = step(tiles, items, x, y, d, rng, ids)
            s.send(msg)
    scen["walking: one step per packet"] = s
    # 3. fighting: 10 ms flushes
    s = make()
    for cx, cy in centres:
        for _ in range(300):
            msgs = combat_tick(cx, cy, rng, ids, effects)
            for p in packets(msgs):
                s.send(p)
    scen["fighting: one 10 ms flush per packet"] = s
    # 4. extended opcode JSON of the modules
    s = make()
    for _ in range(600):
        s.send(extended_json(rng, rng.randint(0, 2)))
    scen["module JSON (extended opcodes)"] = s
    # 5. hunt minute: 1 full view, 200 steps, 3000 fight flushes, 120 module messages (assumed mix, see README)
    s = make()
    cx, cy = centres[0]
    for p in packets(full_view(tiles, items, cx, cy, rng, ids)):
        s.send(p)
    x, y = cx, cy
    for i in range(200):
        msg, x, y = step(tiles, items, x, y, i // 50 % 4, rng, ids)
        s.send(msg)
    for _ in range(3000):
        for p in packets(combat_tick(cx, cy, rng, ids, effects)):
            s.send(p)
    for _ in range(120):
        s.send(extended_json(rng, rng.randint(0, 2)))
    scen["mixed hunt minute (assumed mix)"] = s
    return source, scen


def report(source, scen, args):
    print("packet compression benchmark: %s" % source)
    print("level %d, window bits %d, memLevel %d, minimum body %d; wire bytes count length, checksum and XTEA padding" %
          (args.level, args.window, args.mem, args.min))
    print("%-42s %8s %10s %10s %7s %9s %9s" % ("scenario", "packets", "plain B", "wire B", "saved", "us/pkt", "compr."))
    worst = 100.0
    for name, s in scen.items():
        saved = 100.0 * (1 - s.wire / s.raw) if s.raw else 0.0
        per = 1e6 * s.seconds / max(s.compressed, 1)
        print("%-42s %8d %10d %10d %6.1f%% %9.1f %9d" % (name, s.packets, s.raw, s.wire, saved, per, s.compressed))
        if name.startswith(("full view", "walking")):
            worst = min(worst, saved)
    return worst


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--map")
    ap.add_argument("--items")
    ap.add_argument("--sample-mod", type=int, default=40, help="every Nth 256x256 area pair is loaded from --map")
    ap.add_argument("--level", type=int, default=3)
    ap.add_argument("--window", type=int, default=14)
    ap.add_argument("--mem", type=int, default=7)
    ap.add_argument("--min", type=int, default=128)
    ap.add_argument("--seed", type=int, default=209)
    ap.add_argument("--samples", type=int, default=12)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--min-gain", type=float, default=20.0, help="--check: smallest saving in percent on map traffic")
    args = ap.parse_args()
    source, scen = run(args)
    worst = report(source, scen, args)
    if args.check and worst < args.min_gain:
        print("FAIL: map traffic saves %.1f%%, below %.1f%%" % (worst, args.min_gain))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
