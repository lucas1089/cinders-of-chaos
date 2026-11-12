"""Tile rules shared by the map tile audit and the area planner's QA (server/README.md "Map tile audit (O511)").

Pure Python, no numpy: the planner's QA (area_plan_compile.py) and the whole-map audit (audit_map_tiles.py) call the
same functions, so a rule is written once.

  no_ground_below(ground, items, is_ground)           an item stands on a tile whose ground slot is empty or not a ground
  blocking_on_special(items, special, is_blocking,    a door or a teleport shares its tile with a blocking item, or the
                      walkable)                       tile cannot be walked on
  border_pieces(n, e, s, w, ne, nw, se, sw)           the 12 piece names of one border tile: a port of
                                                      ChaosAreaGenCore.borderPieces (areagen_core.lua)
  wall_piece(n, e, s, w)                              the wall piece type of one wall tile: a port of
                                                      ChaosAreaGenCore.wallPiece
  PIECE_SIDES                                         the neighbour offsets each border piece name stands for

The two ports are held to the Lua originals by audit_map_tiles_test.py (all 256 and all 16 neighbour patterns, when luajit
or lua5.3 is on the PATH).
"""

# the neighbours a border piece names: the piece lies on the lower ground, the higher ground in these directions
PIECE_SIDES = {
    'n': ((0, -1),), 'e': ((1, 0),), 's': ((0, 1),), 'w': ((-1, 0),),
    'cnw': ((-1, -1),), 'cne': ((1, -1),), 'csw': ((-1, 1),), 'cse': ((1, 1),),
    'dnw': ((0, -1), (-1, 0), (-1, -1)), 'dne': ((0, -1), (1, 0), (1, -1)),
    'dsw': ((0, 1), (-1, 0), (-1, 1)), 'dse': ((0, 1), (1, 0), (1, 1)),
}


def no_ground_below(ground, items, is_ground=None):
    """True when the tile holds items (or a ground slot that is not a ground) with no ground under them.
    ground: the id of the ground slot (None or 0 when empty); items: the other ids of the tile;
    is_ground: optional predicate on an id, so a non-ground in the ground slot counts as no ground"""
    if not ground:
        return bool(items)
    if is_ground is not None and not is_ground(ground):
        return True
    return False


def blocking_on_special(items, special, is_blocking, walkable=True):
    """[(special id, blocking id or None)] for a tile that holds a door or teleport (an id of `special`).
    A blocking id is another item of the stack that blocks (is_blocking(id)); None stands for a tile that cannot be
    walked on at all (walkable False) although it holds the special item. Empty list: the tile is fine."""
    out = []
    marks = [i for i in items if i in special]
    if not marks:
        return out
    for s in marks:
        blockers = [i for i in items if i not in special and is_blocking(i)]
        if blockers:
            out.append((s, blockers[0]))
        elif not walkable:
            out.append((s, None))
    return out


def border_pieces(n, e, s, w, ne, nw, se, sw):
    """port of ChaosAreaGenCore.borderPieces: which of the 8 neighbours belong to the higher ground -> piece names"""
    out, used = [], set()

    def pair(name, a, b):
        out.append(name)
        used.add(a)
        used.add(b)
    if n and w:
        pair('dnw', 'n', 'w')
    if n and e and 'n' not in used:
        pair('dne', 'n', 'e')
    if s and e and 'e' not in used:
        pair('dse', 's', 'e')
    if s and w and 's' not in used and 'w' not in used:
        pair('dsw', 's', 'w')
    for side, flag in (('n', n), ('e', e), ('s', s), ('w', w)):
        if flag and side not in used:
            out.append(side)
            used.add(side)
    if nw and 'n' not in used and 'w' not in used:
        out.append('cnw')
    if ne and 'n' not in used and 'e' not in used:
        out.append('cne')
    if sw and 's' not in used and 'w' not in used:
        out.append('csw')
    if se and 's' not in used and 'e' not in used:
        out.append('cse')
    return out


def wall_piece(n, e, s, w):
    """port of ChaosAreaGenCore.wallPiece: which of the 4 neighbours are walls -> horizontal, vertical, corner or pole"""
    h, v = e or w, n or s
    if not h and not v:
        return 'pole'
    if n and w:
        return 'corner'
    if h and v:
        if e and s and not n and not w:
            return 'pole'
        if n and e and not w:
            return 'vertical'
        if s and w and not n:
            return 'horizontal'
        return 'corner'
    return 'horizontal' if h else 'vertical'
