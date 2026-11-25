#!/usr/bin/env python3
"""The game's angle for generated monster art (O728; docs/SPRITE_STYLE.md "Lean of generated art").

The camera is oblique: a standing figure leans up and to the left, its feet right of its head. Stock monster looks lean a median
12 px (bodies 32-48 px tall), the purchased looks of O540 14, the class redraws of O618 17-21 (gen_class_redraw.lean: the centroid
of the bottom quarter of the cropped picture right of the top quarter's). Art drawn straight up (lean near 0) stands wrong on the map.

Rule (`lean_ok`): the standing picture (the first idle picture) of south or of east leans LEAN px (9 to 26: gen_class_redraw.LEAN
widened at the top).
New art is drawn at the angle (PixelLab standard mode, view "oblique", the O618 recipe). Pack art that stands straight is sheared
here, as a step of the build that places it (gen_drive_monsters.py, the wolf and the crab):

    shear   every row above the feet line moves left by floor(k * (feet_y - y) + 0.5) px, a row under it right by the same rule; the
            feet row stays. Whole pixels only: nothing is resampled, the alpha stays hard, no colour is made, no pixel is dropped.
    feet    the lowest opaque row of the standing picture of each direction, taken once and used for every idle and walk picture of
            that direction (a step that lifts a foot does not move the line: no jitter).
    k       K (0.25) by default. A picture whose pixel would leave its canvas is refused (LostPixel); the caller then lowers k for that
            look only, a hundredth at a time, never under K_MIN (0.15), and records the k it used.
    guard   art that already leans (south or east at LEANING px or more) is left as drawn: `lean_frames` refuses to shear it twice
            unless forced.

`align_to_standing` puts dropped idle and walk frames on their standing picture: one whole pixel shift per group and direction, the
median feet point of its frames onto the feet point of the standing picture (gen_outfit_anchors.measure, the O585 measure), so the
motion inside the animation stays as drawn.

    python3 -I oblique_lean.py lean PNG...     # the lean of each picture, px
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_class_redraw as CR  # noqa: E402

K = 0.25            # px of shift a row of height (the coordinator's measure: the plague doctor 0 -> 15 px south)
K_MIN = 0.15        # the least k a look may fall back to when its canvas is too tight
LEAN = (CR.LEAN[0], 26.0)   # px: the O618 band (9 to 22) widened at the top for monster art (owner / coordinator 2026-11-23: the
                            # oblique drops of PixelLab lean 20 to 24 px in some directions; the rule reads south or east)
LEANING = LEAN[0]   # a picture leaning this much already is at the angle
SOUTH, EAST = 2, 1  # engine order north, east, south, west


class LostPixel(ValueError):
    """a sheared pixel would leave its canvas"""


def opaque_rows(a):
    import numpy as np
    return np.nonzero((a[..., 3] > 0).any(axis=1))[0]


def feet_row(a):
    """the lowest opaque row of a picture, None when it is empty"""
    ys = opaque_rows(a)
    return int(ys.max()) if len(ys) else None


def shift_of(y, feet_y, k=K):
    """px row y moves left (a negative value: right)"""
    return int(math.floor(k * (feet_y - y) + 0.5))


def shear(a, k=K, feet_y=None):
    """a with every row moved left by shift_of(y, feet_y, k); feet_y defaults to the picture's own lowest row. LostPixel when an opaque
    pixel would leave the canvas."""
    import numpy as np
    if feet_y is None:
        feet_y = feet_row(a)
    out = np.zeros_like(a)
    if feet_y is None:
        return out
    w = a.shape[1]
    for y in opaque_rows(a):
        s = shift_of(int(y), feet_y, k)
        xs = np.nonzero(a[y, :, 3] > 0)[0]
        if xs.min() - s < 0 or xs.max() - s > w - 1:
            raise LostPixel('row %d moved %d px leaves the %d px canvas' % (y, s, w))
        out[y, xs - s] = a[y, xs]
    return out


def pad(a, left, right=0):
    """a widened by clear columns (room for the shear before a fit)"""
    import numpy as np
    h, w = a.shape[:2]
    out = np.zeros((h, w + left + right, 4), a.dtype)
    out[:, left:left + w] = a
    return out


def lean(a):
    """gen_class_redraw.lean of one picture (px), None when it has under 30 opaque pixels"""
    if int((a[..., 3] > 0).sum()) < 30:
        return None
    return CR.lean(a)


def leans(frames):
    """[lean of the standing picture of north, east, south, west] of {(group, direction): [pictures]}"""
    return [lean(frames[('idle', d)][0]) for d in range(4)]


def leaning(frames):
    """True when the standing picture of south or east leans LEANING px or more already"""
    ln = leans(frames)
    return any(v is not None and v >= LEANING for v in (ln[SOUTH], ln[EAST]))


def lean_ok(frames, band=LEAN):
    """the rule: the standing picture of south or of east leans band[0] to band[1] px"""
    ln = leans(frames)
    return any(v is not None and band[0] <= v <= band[1] for v in (ln[SOUTH], ln[EAST]))


def lean_text(frames):
    return '/'.join('-' if v is None else '%.1f' % v for v in leans(frames))


def lean_problem(name, frames, band=LEAN):
    """None, or the problem line of a look whose south and east both miss the band"""
    if lean_ok(frames, band):
        return None
    return '%s: lean %s px (north / east / south / west), the game\'s angle is %g to %g px in south or east (O728)' % (
        name, lean_text(frames), band[0], band[1])


def shear_frames(frames, k=K):
    """{(group, direction): [pictures]} sheared, the feet line of each direction from its standing picture (the first idle one)"""
    out = {}
    for d in range(4):
        fy = feet_row(frames[('idle', d)][0])
        for g in sorted({g for g, dd in frames if dd == d}):
            out[(g, d)] = [shear(a, k, fy) for a in frames[(g, d)]]
    return out


def lean_frames(frames, k=K, k_min=K_MIN, force=False, fits=None):
    """(sheared frames, k used): k first, then a hundredth less each time a pixel leaves the canvas or fits(frames) is False, down to
    k_min. Refused (ValueError) for art that leans already, unless forced, and when no k from k down to k_min holds."""
    if leaning(frames) and not force:
        raise ValueError('leans %s px already (south or east at %g px or more): left as drawn' % (lean_text(frames), LEANING))
    hund = int(round(k * 100))
    while hund >= int(round(k_min * 100)):
        try:
            out = shear_frames(frames, hund / 100.0)
            if fits is None or fits(out):
                return out, hund / 100.0
        except LostPixel:
            pass
        hund -= 1
    raise LostPixel('no k from %.2f down to %.2f keeps every pixel on the canvas' % (k, k_min))


def feet_point(a):
    """(x, y) feet point of a picture (gen_outfit_anchors.measure, the O585 measure)"""
    from gen_outfit_anchors import measure
    m = measure(a[..., 3])
    return float(m[0]), float(m[1])


def moved(a, dx, dy):
    """a moved by whole pixels; LostPixel when an opaque pixel would leave the canvas"""
    import numpy as np
    out = np.zeros_like(a)
    ys, xs = np.nonzero(a[..., 3] > 0)
    h, w = a.shape[:2]
    if len(xs) and (xs.min() + dx < 0 or xs.max() + dx >= w or ys.min() + dy < 0 or ys.max() + dy >= h):
        raise LostPixel('a move of %d, %d leaves the canvas' % (dx, dy))
    out[ys + dy, xs + dx] = a[ys, xs]
    return out


def align_to_standing(standing, frames):
    """[pictures] of one group and direction moved by one whole pixel shift: the median feet point of the frames onto the standing
    picture's; returns (moved pictures, (dx, dy))"""
    import numpy as np
    if not frames:
        return [], (0, 0)
    sx, sy = feet_point(standing)
    pts = [feet_point(a) for a in frames]
    dx = int(math.floor(sx - float(np.median([p[0] for p in pts])) + 0.5))
    dy = int(math.floor(sy - float(np.median([p[1] for p in pts])) + 0.5))
    return [moved(a, dx, dy) for a in frames], (dx, dy)


# ---------------------------------------------------------------- PixelLab oblique drops (the O618 recipe)

DROP_DIRS = ('north', 'east', 'south', 'west')
DROP_IDLE = 4       # the breath of gen_class_redraw (`idle` 4): the standing picture one row taller in the middle phases
DROP_WALK = 8       # the v3 walk: frame_000 is the standing reference, frame_001..008 the walk


def hard(a):
    """alpha cut at 128: opaque or nothing, no colour under a clear pixel"""
    import numpy as np
    b = a.copy()
    op = b[..., 3] >= 128
    b[..., 3] = np.where(op, 255, 0)
    b[~op] = 0
    return b


def _load_hard(path):
    import numpy as np
    from PIL import Image
    return hard(np.array(Image.open(path).convert('RGBA')))


def _on(a, side):
    import numpy as np
    c = np.zeros((side, side, 4), np.uint8)
    oy, ox = (side - a.shape[0]) // 2, (side - a.shape[1]) // 2
    c[oy:oy + a.shape[0], ox:ox + a.shape[1]] = a
    return c


def drop_walk_dir(state, d):
    """the folder of the walk in direction d of a PixelLab state: animations/walk*/d (one animation, or one per direction)"""
    base = os.path.join(state, 'animations')
    for n in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        if n.lower().startswith('walk') and os.path.isdir(os.path.join(base, n, d)):
            return os.path.join(base, n, d)
    raise ValueError('%s: no walk animation for %s' % (state, d))


def read_drop(path, margin=0):
    """{'stand': {d: picture}, 'idle': {d: [4]}, 'walk': {d: [8]}, 'id': PixelLab character id or ''} of an unzipped PixelLab download
    (STATE/rotations/DIR.png, STATE/animations/walk*/DIR/frame_NNN.png; STATE is the folder that holds rotations/): hard alpha cut at
    128, every picture on one square canvas (the largest, centred: PixelLab grows a canvas around one middle), the walk without its
    standing reference frame_000 when it has 9, its colours pulled to the standing pictures (fun_costume_motion.lock_palette) and moved
    by one whole pixel shift onto the standing picture by the feet (align_to_standing); the idle a breath of DROP_IDLE pictures made
    from the standing picture (fun_costume_motion.breath_cycle). margin: clear px round the canvas on every side (room for the move
    onto the standing picture of a figure that fills its canvas, O768)."""
    import json
    from fun_costume_motion import find_state, lock_palette, breath_cycle
    st = find_state(path)
    stand = {d: _load_hard(os.path.join(st, 'rotations', d + '.png')) for d in DROP_DIRS}
    walk = {}
    for d in DROP_DIRS:
        wd = drop_walk_dir(st, d)
        names = sorted(n for n in os.listdir(wd) if n.lower().endswith('.png'))
        if len(names) == DROP_WALK + 1:
            names = names[1:]
        if len(names) != DROP_WALK:
            raise ValueError('%s: %d walk pictures, %d (or %d with the standing frame_000) wanted' % (wd, len(names), DROP_WALK,
                                                                                                  DROP_WALK + 1))
        walk[d] = [_load_hard(os.path.join(wd, n)) for n in names]
    every = list(stand.values()) + [x for v in walk.values() for x in v]
    side = max(max(a.shape[0], a.shape[1]) for a in every) + 2 * margin
    stand = {d: _on(a, side) for d, a in stand.items()}
    refs = list(stand.values())
    out = {'stand': stand, 'idle': {}, 'walk': {}, 'id': ''}
    for d in DROP_DIRS:
        w = lock_palette([_on(a, side) for a in walk[d]], refs, 1)
        out['walk'][d] = align_to_standing(stand[d], w)[0]
        out['idle'][d] = [hard(a) for a in breath_cycle(stand[d], DROP_IDLE)]
    meta = os.path.join(path, 'metadata.json')
    if os.path.isfile(meta):
        try:
            j = json.load(open(meta, encoding='utf-8'))
            out['id'] = (j.get('states') or [{}])[0].get('character', {}).get('id', '') or j.get('id', '')
        except (ValueError, AttributeError):
            pass
    return out


def drop_frames(drop):
    """{(group, direction index): [pictures]} of read_drop's result, engine order"""
    out = {}
    for i, d in enumerate(DROP_DIRS):
        out[('idle', i)] = drop['idle'][d]
        out[('walk', i)] = drop['walk'][d]
    return out


def main(argv):
    if argv[:1] == ['lean'] and len(argv) > 1:
        import numpy as np
        from PIL import Image
        for p in argv[1:]:
            v = lean(np.array(Image.open(p).convert('RGBA')))
            print('%s %s' % (p, '-' if v is None else '%.1f' % v))
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
