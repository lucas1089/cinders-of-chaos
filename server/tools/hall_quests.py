#!/usr/bin/env python3
"""The quest hall of Cinderhold (server/README.md "Hall order", "Quest hall").

The base server's entry floor (z 7) of the teleport hall is a quest room: 16 alcoves, each with a teleport to the start
of a base quest, the quest's name on the sign behind it and its rewards on show on the cell row beside it (both cells
and the counter between them). The hall order (hall_order.py) treated them like hunts and rewrote them. With the
owner's rule (2026-10-18: the ground floor is for the hunts of levels 1-500) the quests leave the level-ordered
floors: install_content_areas.py moves each quest alcove, tile for tile (teleport with its destination and attributes,
sign with its text, the rewards on show), into the plaza south of the hall where the daily and weekly reward chests
stood (two rows of alcoves round the plaza's aisle, layout_rows; owner 2026-10-20), and the old alcoves become hunt
slots. The quest hall of 2026-10-18 over the pond (layout_grid, config `previous`) is taken away once its quests have
moved on from it (install_content_areas.plan_prev_cleanup).

This module is the part that knows about the quests (the rows of hall_hunts.csv of kind `quest`):
  layout   where each alcove goes (two rows of alcoves with a three-row corridor between, the same shape the hall has
           them, joined to the aisle by a connector, the corridor's far end closed by a wall; the north alcoves of the
           base room in the upper row, the south ones in the lower row, west to east)
  moves    the new tiles: the alcove's 4 columns x 3 rows copied with every attribute (rewards on show included), the
           corridor, and the old alcove made a hunt alcove (its cell row the model hunt alcove's: bare cells without
           protection zone for the display monsters and the counter between, so no reward stays behind; the quest's
           teleport and the sign's text gone). A quest whose teleport an earlier install lost (a hunt's took its
           alcove) is moved all the same and its teleport made again from the CSV (beta 2026-10-20: "the quest
           rewards stayed and the quests are gone")
  ways     the way back from every hunt and quest (ways_back): a teleport outside the hall that leads in front of one
           of its teleports belongs to the hunt or quest whose arrival is nearest among those it leads in front of
           (where the base server had it or where it stands now), or, leading in front of any slot, to the hunt whose
           arrival is within WAY_BACK_NEAR tiles; it leads in front of the teleport it has now
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
        self.optional, self.bad = set(), set()

    def need(self, *positions, optional=False):
        """ask for tiles before load(); an optional one (a repair, a way back) that cannot be read (a house tile, an
        attribute we cannot write back) is left out (bad()) instead of refusing the install"""
        for p in positions:
            p = tuple(p)
            if p not in self.new:
                self.want.add(p)
                if optional:
                    self.optional.add(p)
                else:
                    self.optional.discard(p)

    def load(self):
        import install_content_areas as T
        todo = sorted(p for p in self.want if self.world.has(p) and p not in self.orig and p not in self.bad)
        if not todo:
            return
        data = open(self.map_path, 'rb').read()
        houses = set()
        ranges = T.tile_ranges(data, todo, houses=houses)
        for p in houses:
            if p not in self.optional:
                raise T.InstallError('the tile %d,%d,%d is a house tile; not replaced' % p)
            self.bad.add(p)
        for p in todo:
            if p in houses:
                continue
            s, e = ranges[p]
            try:
                self.orig[p] = H.parse_tile(data[s:e + 1], p)
            except H.HallError as ex:
                if p not in self.optional:
                    raise T.InstallError(str(ex))
                self.bad.add(p)

    def is_bad(self, p):
        return tuple(p) in self.bad

    def has(self, p):
        p = tuple(p)
        if p in self.bad:
            return True
        return p in self.new or p in self.cur or p in self.orig or (p not in self.want and self.world.has(p))

    def get(self, p):
        """the tile now (a dict), None when the map has none there or it could not be read (is_bad)"""
        p = tuple(p)
        if p in self.bad:
            return None
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
        if p in self.bad:
            raise QuestError('internal: tile %d,%d,%d could not be read and is not written' % p)
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
    """Where each quest alcove goes (layout_rows for a config with `north` and `south` rows of columns, else layout_grid,
    the quest hall of 2026-10-18), with `previous` (an earlier placement, layout_grid's config) as each alcove's `prev`
    and `prev_tiles` and the earlier hall's tiles as 'prev' (those the new placement does not take)."""
    lay = layout_rows(qcfg, room, quests) if qcfg.get('north') else layout_grid(qcfg, room, quests)
    lay['prev'] = []
    pc = qcfg.get('previous')
    if pc:
        old = layout_grid(dict(pc, z=qcfg['z']), room, quests)
        by = {a['id']: a for a in old['alcoves']}
        for a in lay['alcoves']:
            o = by[a['id']]
            a['prev'], a['front_prev'], a['prev_tiles'] = o['new'], o['front_new'], o['tiles']
        mine = set(lay['rect']) | set(lay['endwall']) | {p for r in lay['connector'].values() for p in r}
        spots = set(old['rect']) | set(old['endwall']) | {p for r in old['connector'].values() for p in r}
        lay['prev'] = sorted(spots - mine)
    return lay


def layout_rows(qcfg, room, quests):
    """The quests in two rows of alcoves facing each other across a corridor of the plaza (owner, 2026-10-20: "you can
    overwrite this green region"): `north` {y: its sign row (the teleport row is y + 2), x: the teleport columns, west
    to east}, the base room's north alcoves in it; `south` {y: its teleport row (the sign row is y + 2), x: ...}, the
    south alcoves; `corridor` {x: [x0, x1], y: [y0, y1]}: the floor between them, the hall's carpet (its top row the
    corridor's top edge, its bottom row the bottom edge). An alcove is its 4 columns x-1 .. x+2 (cells, teleport and
    the divider after them) and, where the column 4 to the west is not one of the row's, its west divider x-2 too.
    Same return as layout_grid; no connector or end wall (the corridor is part of the plaza)."""
    z = qcfg['z']
    rows = [sorted((q for q in quests if side_of(room, q['y']) == s), key=lambda q: q['x']) for s in (0, 1)]
    out = []
    for s, (key, qs) in enumerate(zip(('north', 'south'), rows)):
        r = qcfg[key]
        cols = list(r['x'])
        if len(cols) < len(qs):
            raise QuestError('quests.%s has %d columns for %d quests' % (key, len(cols), len(qs)))
        top = r['y']
        for k, q in enumerate(qs):
            old = (q['x'], q['y'], q['z'])
            cx = cols[k]
            new = (cx, top + 2 if s == 0 else top, z)
            tiles = {}
            for dx in list(range(-1, 3)) + ([-2] if cx - 4 not in cols else []):
                for o_row, n_row in zip(alcove_rows(room, old), (top, top + 1, top + 2)):
                    tiles[(old[0] + dx, o_row, old[2])] = (cx + dx, n_row, z)
            out.append(dict(id=q['id'], old=old, new=new, front_old=front_of(room, old),
                            front_new=(cx, new[1] + (1 if s == 0 else -1), z),
                            dest=(q['dest_x'], q['dest_y'], q['dest_z']), tiles=tiles, side=s))
    c = qcfg['corridor']
    (x0, x1), (y0, y1) = c['x'], c['y']
    corr = [(x, y, z) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
    rect = sorted({p for a in out for p in a['tiles'].values()} | set(corr))
    label = ((x0 + x1) // 2, (y0 + y1) // 2, z)
    return dict(alcoves=sorted(out, key=lambda a: a['id']), rect=rect, corridor={0: corr, 1: [], 2: []},
                connector={0: [], 1: [], 2: []}, label=label, endwall=[], entrance=None, x1=None, oy=None,
                corridor_rows=(y0, y1))


def layout_grid(qcfg, room, quests):
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
    # the corridor's far end is closed by a wall (before, it ran out into the unmapped tiles east of the hall)
    endwall = [(x1 + 1, oy + 3 + r, z) for r in range(3)]
    # where the aisle meets the connector: a second "Quests" label shows the way in from the plaza
    entrance = (cx, oy + 4, z) if cx is not None else None
    return dict(alcoves=sorted(out, key=lambda a: a['id']), rect=rect, corridor=corridor, connector=connector, label=label,
                endwall=endwall, entrance=entrance, x1=x1, oy=oy)


def model_cells(qcfg, room):
    """{side: [3 positions]}: the cell row (cell, counter, cell) of the hunt alcove `quests.model` ({x, z}: its
    teleport column and floor) on the north (0) and south (1) side; None without a model"""
    m = qcfg.get('model')
    if not m:
        return None
    return {s: [(m['x'] + dx, room['cellRows'][s], m['z']) for dx in (-1, 0, 1)] for s in (0, 1)}


def need_positions(lay, models=None):
    """the map tiles the quest steps read: the old alcoves' tiles (cells, sign and teleport tile among them), the
    quest hall's rectangle, its connector and end wall, and the model cell rows"""
    out = set(lay['rect']) | set(lay['endwall']) | set(lay.get('prev') or ())
    for r in lay['connector'].values():
        out.update(r)
    for a in lay['alcoves']:
        out.update(a['tiles'])
        if a.get('prev_tiles'):
            out.update(a['prev_tiles'].values())
    for ps in (models or {}).values():
        out.update(ps)
    return out


def old_parts(room, old):
    """the old alcove's cell row (x-1, x, x+1: the two cells and the counter between them, all three holding the
    rewards on show) and its sign tile (x on the sign row)"""
    x, y, z = old
    n = side_of(room, y)
    return [(x + dx, room['cellRows'][n], z) for dx in (-1, 0, 1)], (x, room['signRows'][n], z)


def state(ed, lay, log=None):
    """per quest 'old' (still in its old alcove), 'annex' (in the quest hall) or 'lost' (neither holds its teleport:
    an earlier install put a hunt's teleport in its alcove; the alcove is moved all the same and its teleport made
    again from hall_hunts.csv). Raises when the old alcove's teleport tile is not on the map (another map)."""
    out = {}
    for a in lay['alcoves']:
        t_new = ed.get(a['new']) if ed.has(a['new']) else None
        t_old = ed.get(a['old']) if ed.has(a['old']) else None
        t_prev = ed.get(a['prev']) if a.get('prev') and ed.has(a['prev']) else None
        if t_new and tele_item(t_new, a['dest']) is not None:
            out[a['id']] = 'annex'
        elif t_prev and tele_item(t_prev, a['dest']) is not None:
            out[a['id']] = 'moved'  # in the quest hall of an earlier placement (`previous`): it moves on from there
        elif t_old and tele_item(t_old, a['dest']) is not None:
            out[a['id']] = 'old'
        elif t_old is not None:
            out[a['id']] = 'lost'
            if log:
                log('%s: no teleport to %s at %s or in the quest hall at %s: made again in the quest hall'
                    % (a['id'], a['dest'], a['old'], a['new']))
        else:
            raise QuestError('%s: no tile at %s for the quest alcove (hall_hunts.csv is for another map?)'
                             % (a['id'], a['old']))
    return out


def floor_tile(templates, lay, p):
    """the plain floor at p of the quest hall: its corridor row's tile from the hall's own corridor (carpet edges and
    middle), a bare plank floor elsewhere"""
    if lay.get('corridor_rows'):
        y0, y1 = lay['corridor_rows']
        off = 0 if p[1] == y0 else 2 if p[1] == y1 else 1 if y0 < p[1] < y1 else -1
    else:
        off = p[1] - (lay['rect'][0][1] if lay['rect'] else 0) - 3
    t = templates[off] if 0 <= off < 3 else bare(templates[1])
    return dict(flags=t['flags'], ground=t['ground'], items=list(t['items']))


def check_free(ed, lay, st):
    """the quest hall, its corridor and end wall may only take the place of decoration: a tile with an action id, a
    unique id or a teleport that is not one of the quests' own is refused; on a corridor of the plaza (layout_rows) a
    tile with another teleport (no unique id) is a stray of an older layout (lay['strays']; owner, 2026-10-22, "lost
    teleports" on the carpet): plan_move takes it off and gives the tile the carpet again"""
    mine = set()
    for a in lay['alcoves']:
        if st[a['id']] == 'annex':
            mine.update(a['tiles'].values())
    quest_dest = {tuple(a['dest']) for a in lay['alcoves']}
    spots = list(lay['rect']) + [p for r in lay['connector'].values() for p in r] + list(lay['endwall'])
    corr = set(lay['corridor'][0]) if lay.get('corridor_rows') else set()
    alc = {p for a in lay['alcoves'] for p in a['tiles'].values()}
    lay['strays'] = set()
    for p in spots:
        if p in mine:
            continue
        t = ed.get(p)
        for _iid, at in (t['items'] if t else []):
            foreign = at.get('tele') and tuple(at['tele']) not in quest_dest
            if foreign and p in corr and p not in alc and not at.get('uid'):
                lay['strays'].add(p)
                continue
            if at.get('aid') or at.get('uid') or foreign:
                raise QuestError('the quest hall would replace a tile with an action id, unique id or teleport at '
                                 '%d,%d,%d; move the quest hall (hall.quests)' % p)


def text_of(attrs):
    """the text (attribute 6) of an item, b'' without"""
    raw, j = attrs.get('raw', b''), 0
    import struct
    while j < len(raw):
        a = raw[j]
        if a in H.ITEM_STRING_ATTRS:
            n = struct.unpack_from('<H', raw, j + 1)[0]
            if a == 6:
                return raw[j + 3:j + 3 + n]
            j += 3 + n
        else:
            j += 1 + H.ITEM_FIXED_ATTRS[a]
    return b''


def with_text(attrs, text):
    import struct
    b = text.encode('latin-1', 'replace')
    a2 = strip_text(attrs)
    a2['raw'] = a2.get('raw', b'') + bytes([6]) + struct.pack('<H', len(b)) + b
    return a2


def remade(tile, a, item, grounds=None):
    """a lost quest's teleport tile: every teleport item off, the quest's own on (item `item` to its destination),
    after the ground"""
    items = [(i, at) for i, at in tile['items'] if not at.get('tele')]
    at = 1 if (not tile['ground'] and items and (grounds is None or items[0][0] in grounds)) else 0
    items.insert(at, (item, {'tele': tuple(a['dest'])}))
    return dict(flags=tile['flags'], ground=tile['ground'], items=items)


def plan_move(ed, lay, room, portal, sign_id, templates, forward=True, models=None, items=None, names=None,
              grounds=None, log=None):
    """The quests to the quest hall (forward) or back to their old alcoves. Returns ({pos: tile} to write, notes).
    Forward: every tile of the hall's rectangle comes from the alcove that belongs there (read from the old alcove, or
    from the hall when the quest moved before) or is the floor, with the connector corridor to the aisle and the wall
    that closes the corridor's far end; the old alcoves become hunt alcoves: the cell row (both cells and the counter
    between them, where the rewards stood on show) is the model hunt alcove's (`models`, model_cells: bare cells
    without protection zone, so the display monsters can stand there, and the counter), else the cells bare; a quest
    teleport that is not the hall's own item off and the sign blank (the hunt that takes the alcove writes its own
    text). A 'lost' quest (state) gets its teleport made again (item `items[id]`, else `portal`) and, when the sign
    is blank, the quest's name (`names[id]`) on it. Back: the old alcoves get the hall's tiles and the hall is floor
    again."""
    st = state(ed, lay, log)
    check_free(ed, lay, st)
    writes, notes = {}, []
    items, names = items or {}, names or {}
    if forward:
        src = {}
        for a in lay['alcoves']:
            for old, new in a['tiles'].items():
                if st[a['id']] == 'annex':
                    src[new] = ed.get(new)
                elif st[a['id']] == 'moved':  # a tile the earlier hall did not take (a west divider): the old one
                    src[new] = ed.get(a['prev_tiles'].get(old, old))
                else:
                    src[new] = ed.get(old)
            if st[a['id']] == 'lost':
                t = src.get(a['new'])
                if t is not None:
                    src[a['new']] = remade(t, a, items.get(a['id']) or portal, grounds)
                _cells, sign = old_parts(room, a['old'])
                ns = a['tiles'].get(sign)
                t = src.get(ns) if ns else None
                if t is not None and names.get(a['id']):
                    its = [(i, with_text(at, names[a['id']]) if i == sign_id and not text_of(at) else at)
                           for i, at in t['items']]
                    src[ns] = dict(flags=t['flags'], ground=t['ground'], items=its)
        for p in lay['rect']:
            t = src.get(p)
            writes[p] = t if t is not None else floor_tile(templates, lay, p)
        for r in range(3):
            for p in lay['connector'][r]:
                writes[p] = floor_tile(templates, lay, p)
        # the far end of the corridor: the hall's divider wall on the corridor's floor
        div = writes.get((lay['x1'], lay['oy'] + 2, lay['rect'][0][2])) if (lay['rect'] and lay['endwall']) else None
        if div is not None:
            walls = list(div['items'] if div['ground'] else div['items'][1:])
            for r, p in enumerate(lay['endwall']):
                f = floor_tile(templates, lay, (p[0], lay['oy'] + 3 + r, p[2]))
                g, first = (f['ground'], []) if f['ground'] else (None, f['items'][:1])
                writes[p] = dict(flags=f['flags'], ground=g, items=first + walls)
        for a in lay['alcoves']:
            if st[a['id']] in ('old', 'lost', 'moved'):
                notes.append('%s: %s -> %s%s' % (a['id'], a['prev'] if st[a['id']] == 'moved' else a['old'], a['new'],
                                                 ' (teleport made again)' if st[a['id']] == 'lost' else ''))
            cells, sign = old_parts(room, a['old'])
            model = (models or {}).get(side_of(room, a['old'][1]))
            for k, c in enumerate(cells):
                t = ed.get(c)
                if t is None:
                    continue
                m = ed.get(model[k]) if model else None
                if m is not None:
                    writes[c] = dict(flags=m['flags'], ground=m['ground'], items=list(m['items']))
                elif k != 1:
                    writes[c] = bare(t)
            t = ed.get(a['old'])
            i = tele_item(t)
            if i is not None and t['items'][i][0] != portal:
                writes[a['old']] = dict(flags=t['flags'], ground=t['ground'], items=[it for k, it in enumerate(t['items']) if k != i])
            t = ed.get(sign)
            if t is not None:
                writes[sign] = blank_sign(t, sign_id)
        for p in sorted(lay['strays']):
            notes.append('stray teleport at %d,%d,%d taken off the carpet' % p)
    else:
        back = [a for a in lay['alcoves'] if st[a['id']] in ('annex', 'moved')]
        for a in back:
            at = a['new'] if st[a['id']] == 'annex' else a['prev']
            notes.append('%s: %s -> %s' % (a['id'], at, a['old']))
            for old, new in a['tiles'].items():
                if st[a['id']] == 'annex' or old in a['prev_tiles']:
                    writes[old] = ed.get(new if st[a['id']] == 'annex' else a['prev_tiles'][old])
        if any(st[a['id']] == 'annex' for a in back):
            for p in lay['rect']:
                writes[p] = floor_tile(templates, lay, p)
    return writes, notes


def audit(ed, lay, grounds=None):
    """[problem text] for the quest hall as `ed` holds it: a teleport on a corridor row that is not an alcove's own, a
    teleport tile with no ground (first item a ground in `grounds`, else the ground attribute), a quest teleport that
    leads anywhere but its quest's destination (the plan: hall_hunts.csv)"""
    bad = []
    own = {tuple(a['new']): tuple(a['dest']) for a in lay['alcoves']}
    corr = set(lay['corridor'][0]) if lay.get('corridor_rows') else set()
    for p in lay['rect']:
        t = ed.get(p)
        if t is None:
            continue
        tele = [(i, at) for i, at in t['items'] if at.get('tele')]
        if not tele:
            continue
        if p in corr and p not in own:
            bad.append('stray teleport on the carpet at %d,%d,%d' % p)
        elif p not in own:
            bad.append('teleport at %d,%d,%d is not a quest\'s' % p)
        if grounds is not None and not (t['ground'] or (t['items'] and t['items'][0][0] in grounds)):
            bad.append('teleport without ground at %d,%d,%d' % p)
        if p in own and any(tuple(at['tele']) != own[p] for _i, at in tele):
            bad.append('quest teleport at %d,%d,%d leads to %s, not its quest\'s destination' % (p + (tele[0][1]['tele'],)))
    return bad


# ------------------------------------------------------------------------------------------------ the ways back
def distance(a, b):
    """how far a tile is from a hunt's arrival: tiles on the floor, a floor counted as 30"""
    return max(abs(a[0] - b[0]), abs(a[1] - b[1])) + 30 * abs(a[2] - b[2])


WAY_BACK_NEAR = 4  # the base server's ways back stand one to three tiles from the arrival


def ways_back(tele, owners, skip=lambda p: False, slot_fronts=(), near=WAY_BACK_NEAR):
    """[(pos, dest, owner)]: the teleports of the map (tele {pos: dest}, outside the hall: skip) that lead in front of
    one of the hall's teleports - the way back from a hunt or a quest. owners: [{id, dest, fronts, want}], the tile in
    front of the owner's teleport where the base server had it and where it stands now (fronts), and where its way
    back should lead (want). A way back belongs to the owner whose arrival (dest) is nearest among those it leads in
    front of: a way back that already leads in front of a hunt's new slot (the old slot of another hunt) stays with its
    own hunt, so a second run changes nothing.
    slot_fronts: the tiles in front of every hunt slot of the hall. A teleport that leads in front of one of them and
    stands within `near` tiles of an owner's arrival (same floor) is that owner's way back, whatever slot it leads to:
    an earlier install with another order (a hunt's level or a new hunt changed it) left it in front of a slot that is
    neither where the base server had its hunt nor where it stands now (beta report 2026-10-22: the order changed and
    seven ways back led in front of another hunt's teleport)."""
    by_front = {}
    for o in owners:
        for f in o['fronts']:
            by_front.setdefault(tuple(f), []).append(o)
    slots = {tuple(f) for f in slot_fronts}
    out = []
    for pos, d in sorted(tele.items()):
        claim = by_front.get(tuple(d))
        if (not claim and tuple(d) not in slots) or skip(pos):
            continue
        close = [o for o in owners if o['dest'][2] == pos[2] and distance(pos, o['dest']) <= near]
        if close:
            o = min(close, key=lambda o: (distance(pos, o['dest']), o['id']))
        elif claim:
            o = min(claim, key=lambda o: (distance(pos, o['dest']), o['id']))
        else:
            continue
        out.append((tuple(pos), tuple(d), o))
    return out


def plan_ways_back(ed, found):
    """{pos: tile}: each way back (ways_back) leading to its owner's `want`; a tile that could not be read is left"""
    writes = {}
    for pos, d, o in found:
        if ed.is_bad(pos):
            continue
        t = writes.get(pos) or ed.get(pos)
        if t is None:
            continue
        items = [(iid, dict(at, tele=tuple(o['want'])) if at.get('tele') and tuple(at['tele']) == d else at)
                 for iid, at in t['items']]
        nt = dict(flags=t['flags'], ground=t['ground'], items=items)
        if nt != t:
            writes[pos] = nt
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
