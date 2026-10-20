#!/usr/bin/env python3
"""The quest hall of Cinderhold (server/README.md "Hall order", "Quest hall").

The base server's entry floor (z 7) of the teleport hall is a quest room: 16 alcoves, each with a teleport to the start
of a base quest, the quest's name on the sign behind it and its rewards on show in the two cells beside it. The hall
order (hall_order.py) treated them like hunts and rewrote them. With the owner's rule (2026-10-18: the ground floor is
for the hunts of levels 1-500) the quests leave the level-ordered floors: install_content_areas.py moves each quest
alcove, tile for tile (teleport with its destination and attributes, sign with its text, the rewards on show), to
the quest hall east of the plaza's aisle (a little below the hall, where the daily and weekly reward chests stood),
and the old alcoves become hunt slots.

This module is the part that knows about the quests (the rows of hall_hunts.csv of kind `quest`):
  layout   where each alcove goes (two rows of alcoves with a three-row corridor between, the same shape the hall has
           them, joined to the aisle by a connector; the north alcoves of the base room in the upper row, the south
           ones in the lower row, west to east)
  moves    the new tiles: the alcove's 4 columns x 3 rows copied with every attribute (rewards on show included), the
           corridor, and the old alcove cleared (cells bare, the quest's teleport and the sign's text gone)
  returns  the quest sites' own way back: the teleport at the end of each quest leads to the tile in front of the
           old alcove; it is rewritten to lead to the tile in front of the new one (found on the map by its
           destination, within `returnRadius` of the quest's destination)
  chests   the daily and weekly reward chests of the base plaza (royal chest, unique ids 34801-34804, their booths)
           are taken away (owner, 2026-10-18) where the config lists them, after checking the chest is there
and TileEditor, which reads map tiles once (tile_ranges), lets the steps change them in turn and reports only what
differs from the file, so a second run changes nothing.
Python 3 standard library.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hall_order as H  # noqa: E402


class QuestError(Exception):
    pass


# ------------------------------------------------------------------------------------------------ tile editor
class TileEditor:
    """Map tiles read once (parse_tile), changed in turn by the install steps, reported when they differ.
    new_tiles: the tiles the run adds anyway (the grown room); get() sees them and set() changes them in place."""

    def __init__(self, world, map_path, new_tiles):
        self.world, self.map_path, self.new = world, map_path, new_tiles
        self.want, self.orig, self.cur = set(), {}, {}

    def need(self, *positions):
        for p in positions:
            if p not in self.new:
                self.want.add(tuple(p))

    def load(self):
        import install_content_areas as T
        todo = sorted(p for p in self.want if self.world.has(p) and p not in self.orig)
        if not todo:
            return
        data = open(self.map_path, 'rb').read()
        ranges = T.tile_ranges(data, todo)
        for p in todo:
            s, e = ranges[p]
            try:
                self.orig[p] = H.parse_tile(data[s:e + 1], p)
            except H.HallError as ex:
                raise T.InstallError(str(ex))

    def has(self, p):
        return p in self.new or p in self.cur or p in self.orig or (p not in self.want and self.world.has(p))

    def get(self, p):
        """the tile now (a dict), None when the map has none there"""
        p = tuple(p)
        if p in self.cur:
            return self.cur[p]
        if p in self.new:
            return self.new[p]
        if p in self.orig:
            return self.orig[p]
        if self.world.has(p):
            raise QuestError('internal: tile %d,%d,%d was not asked for (need) before load' % p)
        return None

    def set(self, p, tile):
        p = tuple(p)
        if p in self.new:
            self.new[p] = tile
        else:
            self.cur[p] = tile

    def changed(self):
        """{pos: tile} of the map's own tiles that differ from the file, and the positions to cut for them"""
        out = {p: t for p, t in self.cur.items() if t != self.orig.get(p)}
        return out


# ------------------------------------------------------------------------------------------------ item helpers
def tele_item(tile, dest=None):
    """the index of the item of `tile` that carries a teleport destination (the one leading to dest when given)"""
    for i, (iid, a) in enumerate(tile['items']):
        if a.get('tele') and (dest is None or tuple(a['tele']) == tuple(dest)):
            return i
    return None


def bare(tile):
    """a cell with only its ground (the ground may be a tile attribute or the first item)"""
    items = [] if tile['ground'] else tile['items'][:1]
    return dict(flags=tile['flags'], ground=tile['ground'], items=items)


def strip_text(attrs):
    """item attributes without the text (attribute 6) of a sign"""
    raw, out, j = attrs.get('raw', b''), bytearray(), 0
    while j < len(raw):
        a = raw[j]
        if a in H.ITEM_STRING_ATTRS:
            import struct
            n = 3 + struct.unpack_from('<H', raw, j + 1)[0]
        else:
            n = 1 + H.ITEM_FIXED_ATTRS[a]
        if a != 6:
            out += raw[j:j + n]
        j += n
    a2 = {k: v for k, v in attrs.items() if k != 'raw'}
    if out:
        a2['raw'] = bytes(out)
    return a2


def blank_sign(tile, sign_id):
    items = [(i, strip_text(a) if i == sign_id else a) for i, a in tile['items']]
    return dict(flags=tile['flags'], ground=tile['ground'], items=items)


# ------------------------------------------------------------------------------------------------ the layout
def side_of(room, row):
    """0 for the alcoves of the north teleport row, 1 for the south"""
    return room['teleportRows'].index(row)


def front_of(room, pos):
    """the corridor tile in front of an alcove's teleport (players stand there to step in, and come back to it)"""
    x, y, z = pos
    return (x, y + 1, z) if side_of(room, y) == 0 else (x, y - 1, z)


def alcove_rows(room, pos):
    """the three rows of an alcove, from its sign row to its teleport row (north) or from the teleport row to the sign
    row (south): the order of the map, top to bottom"""
    y = pos[1]
    return [y - 2, y - 1, y] if side_of(room, y) == 0 else [y, y + 1, y + 2]


def layout(qcfg, room, quests):
    """Where each quest alcove goes: a copy of the hall's own shape east of the plaza's aisle, joined to it by a corridor
    of the same three rows. Upper row: the north alcoves west to east; lower row: the south ones. quests: the CSV rows
    of kind quest (x, y, z of the old teleport, dest_*). An alcove is 4 columns wide (x-1 .. x+2: the cells and the
    divider after them), the first of a row has its west divider too.
    Returns {'alcoves': [{id, old, new, front_old, front_new, dest, side, tiles: {old pos: new pos}}], 'rect': [pos]
    (the hall's tiles), 'corridor': {row offset 0-2: [pos]} (its three rows), 'connector': [pos] (the corridor from the
    aisle to the hall), 'label': pos}. The rows from the top: sign, cells, teleport (upper alcoves), the 3 corridor rows,
    teleport, cells, sign (lower alcoves): 9 rows from origin.y."""
    z = qcfg['z']
    ox, oy, step = qcfg['origin']['x'], qcfg['origin']['y'], qcfg.get('step', 4)
    if step != 4:
        raise QuestError('quests.step must be 4 (the alcove is 4 columns wide)')
    rows = [sorted((q for q in quests if side_of(room, q['y']) == s), key=lambda q: q['x']) for s in (0, 1)]
    n = max(len(rows[0]), len(rows[1]), 1)
    out = []
    for s, qs in enumerate(rows):
        top = oy if s == 0 else oy + 6  # the alcove's first row (sign row of the upper, teleport row of the lower)
        for k, q in enumerate(qs):
            old = (q['x'], q['y'], q['z'])
            new = (ox + step * k, top + 2 if s == 0 else top, z)
            tiles = {}
            for dx in list(range(-1, 3)) + ([-2] if k == 0 else []):
                for o_row, n_row in zip(alcove_rows(room, old), (top, top + 1, top + 2)):
                    tiles[(old[0] + dx, o_row, old[2])] = (new[0] + dx, n_row, z)
            out.append(dict(id=q['id'], old=old, new=new, front_old=front_of(room, old),
                            front_new=(new[0], new[1] + (1 if s == 0 else -1), z),
                            dest=(q['dest_x'], q['dest_y'], q['dest_z']), tiles=tiles, side=s))
    x0, x1 = ox - 2, ox + step * (n - 1) + 2
    rect = [(x, y, z) for y in range(oy, oy + 9) for x in range(x0, x1 + 1)]
    cx = qcfg.get('connector', {}).get('x')
    corridor = {r: [(x, oy + 3 + r, z) for x in range(x0, x1 + 1)] for r in range(3)}
    connector = {r: [(x, oy + 3 + r, z) for x in range(cx, x0)] for r in range(3)} if cx is not None else {r: [] for r in range(3)}
    label = (ox + step * (n - 1) // 2 + 1, oy + 4, z)
    return dict(alcoves=sorted(out, key=lambda a: a['id']), rect=rect, corridor=corridor, connector=connector, label=label)


def need_positions(lay):
    """the map tiles the quest steps read: the old alcoves' tiles (cells, sign and teleport tile among them) and the
    quest hall's rectangle"""
    out = set(lay['rect'])
    for r in lay['connector'].values():
        out.update(r)
    for a in lay['alcoves']:
        out.update(a['tiles'])
    return out


def old_parts(room, old):
    """the old alcove's cells (x-1, x+1 on the cell row) and its sign tile (x on the sign row)"""
    x, y, z = old
    n = side_of(room, y)
    return [(x - 1, room['cellRows'][n], z), (x + 1, room['cellRows'][n], z)], (x, room['signRows'][n], z)


def find_returns(tele, lay, radius):
    """[(alcove, pos)]: teleports of the map within `radius` tiles of an alcove's destination (same floor) that lead
    to the tile in front of its old alcove or of its new one - the way back from the quest"""
    out = []
    for a in lay['alcoves']:
        dx, dy, dz = a['dest']
        for pos, d in tele.items():
            if pos[2] == dz and abs(pos[0] - dx) <= radius and abs(pos[1] - dy) <= radius \
                    and tuple(d) in (a['front_old'], a['front_new']):
                out.append((a, pos))
    return out


def state(ed, lay):
    """per quest 'old' (still in its old alcove) or 'annex' (in the quest hall); raises when neither holds its teleport"""
    out = {}
    for a in lay['alcoves']:
        t_new = ed.get(a['new']) if ed.has(a['new']) else None
        t_old = ed.get(a['old'])
        if t_new and tele_item(t_new, a['dest']) is not None:
            out[a['id']] = 'annex'
        elif t_old and tele_item(t_old, a['dest']) is not None:
            out[a['id']] = 'old'
        else:
            raise QuestError('%s: no teleport to %s at %s or in the quest hall at %s (hall_hunts.csv is for another map, '
                             'or the tiles were changed by hand)' % (a['id'], a['dest'], a['old'], a['new']))
    return out


def floor_tile(templates, lay, p):
    """the plain floor at p of the quest hall: its corridor row's tile from the hall's own corridor (carpet edges and
    middle), a bare plank floor elsewhere"""
    off = p[1] - (lay['rect'][0][1] if lay['rect'] else 0) - 3
    t = templates[off] if 0 <= off < 3 else bare(templates[1])
    return dict(flags=t['flags'], ground=t['ground'], items=list(t['items']))


def check_free(ed, lay, st):
    """the quest hall and its corridor may only take the place of decoration: a tile with an action id, a unique id or
    a teleport that is not one of the quests' own is refused"""
    mine = set()
    for a in lay['alcoves']:
        if st[a['id']] == 'annex':
            mine.update(a['tiles'].values())
    quest_dest = {tuple(a['dest']) for a in lay['alcoves']}
    spots = list(lay['rect']) + [p for r in lay['connector'].values() for p in r]
    for p in spots:
        if p in mine:
            continue
        t = ed.get(p)
        for _iid, at in (t['items'] if t else []):
            if at.get('aid') or at.get('uid') or (at.get('tele') and tuple(at['tele']) not in quest_dest):
                raise QuestError('the quest hall would replace a tile with an action id, unique id or teleport at '
                                 '%d,%d,%d; move quests.origin' % p)


def plan_move(ed, lay, room, portal, sign_id, templates, forward=True):
    """The quests to the quest hall (forward) or back to their old alcoves. Returns ({pos: tile} to write, notes).
    Forward: every tile of the hall's rectangle comes from the alcove that belongs there (read from the old alcove, or
    from the hall when the quest moved before) or is the floor, with the connector corridor to the aisle; the old
    alcoves are cleared (cells bare, a quest teleport that is not the hall's own item off, the sign blank: the hunt that
    takes the alcove writes its own text). Back: the old alcoves get the hall's tiles and the hall is floor again."""
    st = state(ed, lay)
    check_free(ed, lay, st)
    writes, notes = {}, []
    if forward:
        src = {}
        for a in lay['alcoves']:
            for old, new in a['tiles'].items():
                src[new] = ed.get(new) if st[a['id']] == 'annex' else ed.get(old)
        for p in lay['rect']:
            t = src.get(p)
            writes[p] = t if t is not None else floor_tile(templates, lay, p)
        for r in range(3):
            for p in lay['connector'][r]:
                writes[p] = floor_tile(templates, lay, p)
        for a in lay['alcoves']:
            if st[a['id']] == 'old':
                notes.append('%s: %s -> %s' % (a['id'], a['old'], a['new']))
            cells, sign = old_parts(room, a['old'])
            for c in cells:
                t = ed.get(c)
                if t is not None:
                    writes[c] = bare(t)
            t = ed.get(a['old'])
            i = tele_item(t)
            if i is not None and t['items'][i][0] != portal:
                writes[a['old']] = dict(flags=t['flags'], ground=t['ground'], items=[it for k, it in enumerate(t['items']) if k != i])
            t = ed.get(sign)
            if t is not None:
                writes[sign] = blank_sign(t, sign_id)
    else:
        back = [a for a in lay['alcoves'] if st[a['id']] == 'annex']
        for a in back:
            notes.append('%s: %s -> %s' % (a['id'], a['new'], a['old']))
            for old, new in a['tiles'].items():
                writes[old] = ed.get(new)
        if back:
            for p in lay['rect']:
                writes[p] = floor_tile(templates, lay, p)
    return writes, notes


def plan_returns(ed, found, forward):
    """{pos: tile} with the way back of each quest pointing in front of its new alcove (forward) or old one"""
    writes = {}
    for a, pos in found:
        t = writes.get(pos) or ed.get(pos)
        want = a['front_new'] if forward else a['front_old']
        items = []
        for iid, at in t['items']:
            if at.get('tele') and tuple(at['tele']) in (a['front_old'], a['front_new']):
                at = dict(at, tele=want)
            items.append((iid, at))
        writes[pos] = dict(flags=t['flags'], ground=t['ground'], items=items)
    return writes


def plan_chests(ed, chests):
    """{pos: tile} bare booths for the reward chests of the config ([{x, y, item, uid, rows: [y0, y1]}]): the chest tile
    must hold the item with that unique id (else it is gone already: nothing to do) and a chest item without it is
    refused; the booth's tiles (x, y0..y1) get only their ground"""
    writes, notes = {}, []
    for c in chests:
        pos = (c['x'], c['y'], c['z'])
        t = ed.get(pos)
        if t is None:
            continue
        mine = [(iid, a) for iid, a in t['items'] if iid == c['item']]
        if not mine:
            continue
        if not any(a.get('uid') == c['uid'] for _i, a in mine):
            raise QuestError('chest %s: item %d there has not the unique id %d: not removed' % (pos, c['item'], c['uid']))
        notes.append('chest %d at %s removed with its booth' % (c['uid'], pos))
        for y in range(c['rows'][0], c['rows'][1] + 1):
            b = ed.get((c['x'], y, c['z']))
            if b is not None:
                writes[(c['x'], y, c['z'])] = bare(b)
    return writes, notes
