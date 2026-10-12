"""Item database for map analysis: items.otb + items.xml (+ optional client .dat).

    from itemdb import ItemDB
    db = ItemDB('items.otb', 'items.xml', 'Tibia.dat')    # dat optional
    db.cid[sid]       client id (0 = unknown server id)
    db.group[sid]     otb group (1 ground, 2 container, 7 teleport, 11 splash, 12 fluid, 13 door ...)
    db.flags[sid]     otb flags (bit 0 block solid, 1 block projectile, 2 block path, 8 floor change down, 13 always on top ...)
    db.order[sid]     always-on-top order (1 border, 2 bottom e.g. walls, 3 top e.g. arches/door frames; 0 none)
    db.name[sid]      items.xml name ('' when none)
    db.cls[sid]       derived class, one of CLASSES (see classify())
    db.light[sid]     light level (dat or otb)

The class of an item drives every metric:
    ground   - otb group 1 (or dat 'ground')
    border   - dat 'clip' / otb order 1: ground borders drawn over the ground
    wall     - order 2 (dat 'bottom') and blocking: walls, mountain sides, cave walls, fences
    nature   - trees, bushes, stones, grass tufts, flowers, mushrooms, roots ... (by name)
    furniture- tables, chairs, beds, shelves, barrels, crates, lamps ... (by name)
    floorchg - stairs, ramps, holes, ladders, trapdoors, sewer grates (otb floor change flag or by name)
    door     - otb group 13 or name contains 'door'/'gate'
    light    - light source not covered above (torches, lamps)
    top      - order 3 (arches, door frames, wall lamps)
    splash   - blood/fluids, magic fields
    other    - everything else (loose decoration, items)
"""
import os, re, struct, sys
import numpy as np

# the dat/spr parser lives with the client sprite tools
_SPRITES = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'client', 'tools', 'sprites')
if os.path.isdir(_SPRITES) and _SPRITES not in sys.path:
    sys.path.insert(0, _SPRITES)

FAMILY_ALIASES = {'muddy floor': 'dirt floor', 'flowers': 'grass', 'rutted stone floor': 'rutted stone'}

CLASSES = ['none', 'ground', 'border', 'wall', 'nature', 'furniture', 'floorchg', 'door', 'light', 'top', 'splash', 'other']
C = {c: i for i, c in enumerate(CLASSES)}

NATURE = re.compile(r'\b(tree|trees|bush|bushes|shrub|fern|flower|flowers|grass|stone|stones|rock|rocks|boulder|pebble|'
                    r'mushroom|mushrooms|root|roots|plant|plants|reed|reeds|moss|bones?|skull|stalagmite|stalagmites|'
                    r'stalactite|crystal|crystals|branch|branches|leaves|vine|vines|thorn|cactus|palm|jungle|log|stump|'
                    r'trunk|lily|blossom|daisy|pine|fir|willow|dead tree|coral|seaweed|shell|ice|icicle|snow|lava|'
                    r'puddle|mud|swamp|nettle|weed|weeds|creeper|hedge|tuft|clover|pumpkin|stalks?|termite|anthill|'
                    r'web|cobweb|spider web|sand|dirt|gravel|debris|rubble|bone)\b', re.I)
FURN = re.compile(r'\b(table|chair|bench|bed|shelf|shelves|bookcase|cupboard|chest|wardrobe|barrel|crate|box|drawer|'
                  r'counter|desk|stool|throne|sofa|armchair|cabinet|trough|pillow|carpet|rug|statue|bust|pedestal|'
                  r'altar|coffin|sarcophagus|tapestry|painting|picture|mirror|vase|pot|flowerpot|bucket|cauldron|oven|'
                  r'stove|fireplace|chimney|piano|harp|globe|blackboard|mailbox|depot|locker|anvil|well|fountain|'
                  r'sign|signpost|banner|flag|lamp|lantern|candelabrum|candlestick|torch bearer|brazier|basin|'
                  r'cask|keg|sack|amphora|trunk chest|board|bookshelf|lectern|easel|dresser|bath|tub|toilet|'
                  r'rocking|cradle|telescope|bell|cart|wagon|crane|scarecrow|fence|pillar|column|obelisk|'
                  r'grave|gravestone|tombstone|tomb|cross|monument|machine|engine|pipe|pipes|net|anchor)\b', re.I)
FLOORCHG = re.compile(r'\b(stairs|staircase|ramp|ladder|hole|trapdoor|sewer grate|rope spot|pitfall|ladders?)\b', re.I)
DOOR = re.compile(r'\b(door|gate|portcullis)\b', re.I)
WALLN = re.compile(r'\b(wall|walls|mountain|cliff|rock face|palisade|framework|hedge|railing)\b', re.I)


def _nodes(d, start=4):
    tok = re.compile(rb'\xfd.|\xfe|\xff', re.S)
    pending = None
    for m in tok.finditer(d, start):
        s = m.group()
        if len(s) == 2:
            continue
        pos = m.start()
        if pending is not None:
            yield pending[0], pending[1], pos
            pending = None
        if s == b'\xfe':
            pending = (d[pos + 1], pos + 2)


class ItemDB:
    def __init__(self, otb, xml=None, dat=None):
        N = 65536
        self.cid = np.zeros(N, np.uint16); self.group = np.zeros(N, np.uint8); self.flags = np.zeros(N, np.uint32)
        self.order = np.zeros(N, np.uint8); self.speed = np.zeros(N, np.uint16); self.light = np.zeros(N, np.uint8)
        self.known = np.zeros(N, bool); self.name = [''] * N; self.floorchange = np.zeros(N, bool)
        self.dground = np.zeros(N, bool); self.dclip = np.zeros(N, bool); self.dbottom = np.zeros(N, bool)
        self.dtop = np.zeros(N, bool); self.dblock = np.zeros(N, bool); self.minimap = np.zeros(N, np.uint16)
        self.fullground = np.zeros(N, bool)
        unesc = re.compile(rb'\xfd(.)', re.S)
        d = open(otb, 'rb').read()
        first = True
        for t, a, b in _nodes(d):
            pl = unesc.sub(rb'\1', d[a:b]) if b'\xfd' in d[a:b] else d[a:b]
            if first:
                first = False; continue
            if len(pl) < 4:
                continue
            fl = struct.unpack_from('<I', pl, 0)[0]; k = 4; sid = None; at_ = {}
            while k + 3 <= len(pl):
                at = pl[k]; ln = struct.unpack_from('<H', pl, k + 1)[0]; k += 3
                at_[at] = pl[k:k + ln]; k += ln
            if 0x10 not in at_:
                continue
            sid = struct.unpack_from('<H', at_[0x10])[0]
            self.known[sid] = True; self.group[sid] = t; self.flags[sid] = fl
            if 0x11 in at_: self.cid[sid] = struct.unpack_from('<H', at_[0x11])[0]
            if 0x14 in at_ and len(at_[0x14]) >= 2: self.speed[sid] = struct.unpack_from('<H', at_[0x14])[0]
            if 0x2A in at_ and len(at_[0x2A]) >= 2: self.light[sid] = min(255, struct.unpack_from('<H', at_[0x2A])[0])
            if 0x2B in at_ and len(at_[0x2B]) >= 1: self.order[sid] = at_[0x2B][0]
        if xml:
            s = open(xml, encoding='latin1').read()
            for m in re.finditer(r'<item\b([^>]*?)(/?)>', s):
                attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
                body = '' if m.group(2) else s[m.end():s.find('</item>', m.end())]
                if 'id' in attrs:
                    ids = [int(attrs['id'])]
                elif 'fromid' in attrs and 'toid' in attrs:
                    ids = range(int(attrs['fromid']), int(attrs['toid']) + 1)
                else:
                    continue
                fc = 'floorchange' in body.lower()
                for i in ids:
                    if 0 <= i < N:
                        self.name[i] = attrs.get('name', '')
                        self.floorchange[i] = fc
        self.dat = None
        if dat:
            from datspr import Dat
            self.dat = Dat(dat)
            things = self.dat.items
            for sid in np.flatnonzero(self.cid):
                c = int(self.cid[sid])
                if 100 <= c < 100 + len(things):
                    f = things[c - 100].flags
                    self.dground[sid] = 'ground' in f; self.dclip[sid] = 'clip' in f
                    self.dbottom[sid] = 'bottom' in f; self.dtop[sid] = 'top' in f
                    self.dblock[sid] = 'notwalkable' in f; self.fullground[sid] = 'fullground' in f
                    if 'minimap' in f: self.minimap[sid] = f['minimap']
                    if 'light' in f and not self.light[sid]: self.light[sid] = min(255, f['light'][0])
        self.classify()

    def classify(self):
        N = len(self.cid)
        cls = np.full(N, C['other'], np.uint8)
        g, o, fl = self.group, self.order, self.flags
        block = (fl & 1) > 0
        for sid in range(N):
            if not self.known[sid]:
                cls[sid] = C['none']; continue
            nm = self.name[sid]
            if g[sid] == 1 or self.dground[sid]:
                c = 'ground'
            elif o[sid] == 1 or self.dclip[sid]:
                c = 'border'
            elif (fl[sid] & (1 << 8)) or self.floorchange[sid] or (nm and FLOORCHG.search(nm) and not DOOR.search(nm)):
                c = 'floorchg'
            elif g[sid] == 13 or (nm and DOOR.search(nm) and o[sid] in (2, 3, 0) and not FURN.search(nm)):
                c = 'door'
            elif g[sid] in (11, 12) or g[sid] == 8:
                c = 'splash'
            elif (o[sid] == 2 or self.dbottom[sid]) and (block[sid] or (nm and WALLN.search(nm))):
                c = 'wall'
            elif nm and NATURE.search(nm) and not FURN.search(nm):
                c = 'nature'
            elif nm and FURN.search(nm):
                c = 'furniture'
            elif o[sid] == 3 or self.dtop[sid]:
                c = 'top'
            elif self.light[sid]:
                c = 'light'
            elif (o[sid] == 2 or self.dbottom[sid]):
                c = 'wall'
            else:
                c = 'other'
            cls[sid] = C[c]
        self.cls = cls
        self.block = block
        self.blocks_path = (fl & 5) > 0

    def ground_family(self):
        """family id per server id for grounds: the same name (case-insensitive, after FAMILY_ALIASES) means
        the same family; unnamed grounds are grouped by minimap colour. Ground variants (e.g. 16 grass tiles)
        share a family; a border is expected only where two different families meet. The aliases join
        grounds that the editor's brushes mix without borders (cave floor with muddy floor, flowers in grass)."""
        fam = np.zeros(len(self.cid), np.int32)
        keys = {}
        for sid in np.flatnonzero(self.cls == C['ground']):
            nm = self.name[sid].lower()
            nm = FAMILY_ALIASES.get(nm, nm)
            k = (nm or f'#{self.minimap[sid]}', int(self.minimap[sid]) if not nm else 0)
            fam[sid] = keys.setdefault(k, len(keys) + 1)
        self.fam_names = {v: k[0] for k, v in keys.items()}
        return fam
