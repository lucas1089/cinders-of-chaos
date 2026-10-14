"""Two auras and a pair of wings for gen_theme_art.py, drawn frame by frame with gen_class_fx.Canvas (shapes on a 4x
supersample, hard material ramps, a dark outline: the look of the class signature effects). Our own procedural art;
no pixel of any reference is read.

    blood_vortex   aura: three blood streams spiral round the wearer's feet, droplets flung off, a dark core
    rune_seal      aura: a pale blue seal on the ground, two rings with turning runes, a six-point star, motes rising
    runic_wings    wings: pale feathered wings with glowing blue runes, a slow beat

Outfit things of 3 x 3 tiles (96 px frames), 4 directions, one frame group, `animateAlways`, 8 phases.
Placement follows the client (client/MANIFEST.md "Aura displacement"):
  aura   a frame pixel lands at (x - dx - 32, y - dy - 32) from the tile's top left (GameBigAurasCenter). With
         displacement 17, 17 the seal's centre, frame (62, 62), sits at (13, 13): 3 px up-left of the tile centre,
         inside the stock ground auras' range. Layer 0 is drawn behind the creature, layer 1 in front of it: the
         part of the art north of the centre line goes to layer 0, the rest to layer 1.
  wings  no displacement: (x - 64, y - 64), plus GameWingOffset (6 px right and down); behind the body facing south
         and east, in front facing north and west. The root sits between the shoulders of a player look.
"""
import math
import random

import numpy as np

import gen_class_fx as FX

N = 96
TAU = 2 * math.pi
PHASES = 8
DIRS = ('north', 'east', 'south', 'west')

AURA_CENTRE = (62.0, 62.0)          # frame px (ground point under the wearer)
AURA_DISP = (17, 17)
WING_ROOT = (66.0, 62.0)            # frame px between the shoulders


def canvas():
    return FX.Canvas(N)


def ground(c, r, a, k=0.5):
    """a point on the ground ellipse (the oblique view squashes depth by k)"""
    return np.array((c[0] + r * math.cos(a), c[1] + k * r * math.sin(a)))


def split_layers(img, cy):
    """-> (back, front): rows above the centre line go behind the creature"""
    back = img.copy()
    front = img.copy()
    back[int(cy):] = 0
    front[:int(cy)] = 0
    return back, front


# ------------------------------------------------------------------------------------------------ blood vortex
def blood_vortex(d, t):
    cv = canvas()
    C = np.array(AURA_CENTRE)
    rot = TAU * t / PHASES + d * 0.21
    # dark pool under the feet
    cv.ellipse('shade', C, 9, 4.2, 0, 0.3, 0.8)
    for k in range(3):
        base = rot + k * TAU / 3
        pts = []
        for j in range(12):
            s = j / 11
            a = base + s * 2.4
            r = 6 + s * 22
            pts.append(ground(C, r, a) - np.array((0, 3 * math.sin(math.pi * s))))
        for j in range(11):
            w0 = 0.6 + 1.9 * (1 - abs(j / 10 - 0.6))
            w1 = 0.6 + 1.9 * (1 - abs((j + 1) / 10 - 0.6))
            cv.capsule('blood', pts[j], pts[j + 1], w0, w1, 0.2 + 0.03 * j, 0.62)
        tip = pts[-1]
        cv.disc('blood', tip, 1.3, 0.55, 0.8, 0)
    R = random.Random(41 + d)
    for j in range(7):
        a0 = R.uniform(0, TAU)
        life = (t / PHASES + j / 7) % 1.0
        r = 16 + life * 16
        p = ground(C, r, a0 + rot * 0.5) - np.array((0, 10 * math.sin(math.pi * life)))
        if life < 0.85:
            cv.disc('blood', p, 1.2 - 0.5 * life, 0.45, 0.75, 0)
    # a thin ring of red mist
    for k in range(5):
        a = rot * 1.5 + k * TAU / 5
        cv.capsule('blood', ground(C, 27, a), ground(C, 27, a + 0.5), 0.55, 0.55, 0.25, 0.25)
    return cv.finish()


# ------------------------------------------------------------------------------------------------ rune seal
RUNES = [  # tiny glyphs: segments in a 4 x 6 box (x, y pairs)
    [((0, 0), (0, 6)), ((0, 0), (3, 2)), ((0, 3), (3, 5))],
    [((0, 6), (2, 0)), ((2, 0), (4, 6)), ((1, 3), (3, 3))],
    [((2, 0), (2, 6)), ((0, 2), (4, 4))],
    [((0, 0), (4, 6)), ((4, 0), (0, 6))],
    [((0, 6), (0, 0)), ((0, 0), (4, 3)), ((4, 3), (0, 6))],
    [((1, 0), (1, 6)), ((3, 0), (3, 6)), ((1, 3), (3, 3))],
]


def rune_seal(d, t):
    cv = canvas()
    C = np.array(AURA_CENTRE)
    pulse = 0.5 + 0.5 * math.cos(TAU * t / PHASES)
    v = 0.55 + 0.35 * pulse
    for r, w in ((28, 1.3), (21, 0.9)):
        for j in range(40):
            a0, a1 = j * TAU / 40, (j + 1) * TAU / 40
            cv.capsule('frost', ground(C, r, a0), ground(C, r, a1), w, w, v, v)
    # turning runes between the rings
    rot = TAU * t / PHASES / 3 + d * 0.05
    for k in range(8):
        a = rot + k * TAU / 8
        c = ground(C, 24.5, a)
        g = RUNES[k % len(RUNES)]
        for p, q in g:
            P = c + np.array(((p[0] - 2) * 0.55, (p[1] - 3) * 0.45))
            Q = c + np.array(((q[0] - 2) * 0.55, (q[1] - 3) * 0.45))
            cv.capsule('prism', P, Q, 0.45, 0.45, 0.85, 0.85)
    # a six-point star, turning the other way
    srot = -TAU * t / PHASES / 6
    for k in range(2):
        pts = [ground(C, 16, srot + k * math.pi / 3 + j * TAU / 3) for j in range(3)]
        for j in range(3):
            cv.capsule('frost', pts[j], pts[(j + 1) % 3], 0.6, 0.6, 0.75, 0.75)
    cv.ellipse('frost', C, 4.5, 2.2, 0, 0.6 + 0.3 * pulse, 1.0)
    if pulse > 0.6:
        cv.disc('core', C, 1.4, 0.8, 1.0, 0)
    # motes rising from the ring
    R = random.Random(77 + d)
    for j in range(5):
        a = R.uniform(0, TAU)
        life = (t / PHASES + j / 5) % 1.0
        p = ground(C, 26, a) - np.array((0, 4 + 20 * life))
        if life < 0.8:
            cv.spark('core' if j % 2 else 'frost', np.round(p) + 0.5, 1.0 + (j == 0), 0.95)
    return cv.finish()


# ------------------------------------------------------------------------------------------------ runic wings
def wing(cv, root, side, spread, beat, scale=1.0, dim=0.0, flat=1.0):
    """one wing from root; side -1 = to the screen left, +1 = right; flat < 1 squashes it sideways (profile)"""
    root = np.asarray(root, float)
    lift = 2.5 * math.sin(beat)
    arm_a = -math.pi / 2 + side * (1.15 + 0.2 * spread)
    elbow = root + np.array((math.cos(arm_a) * 12 * flat, math.sin(arm_a) * 12 - lift)) * scale
    tip_a = -math.pi / 2 + side * (0.6 + 0.2 * spread)
    tip = elbow + np.array((math.cos(tip_a) * 13 * flat, math.sin(tip_a) * 13 - lift)) * scale
    # primaries: long feathers hanging from the arm, longest at the tip
    for k in range(7):
        s = k / 6
        base = elbow + (tip - elbow) * s if k else elbow
        base = root + (elbow - root) * (s * 2) if s < 0.5 else elbow + (tip - elbow) * ((s - 0.5) * 2)
        L = (8 + 12 * s) * scale
        fa = math.pi / 2 + side * (0.15 + 0.55 * s)
        end = base + np.array((math.cos(fa) * L * flat * 0.8, math.sin(fa) * L))
        cv.capsule('steel', base, end, 2.3 * scale, 0.7, 0.55 - dim, 0.95 - dim)
    # coverts over the arm, lighter
    for k in range(5):
        s = k / 4
        base = root + (tip - root) * (0.15 + 0.7 * s)
        end = base + np.array((side * 2.5 * flat, 7 * scale))
        cv.capsule('core', base, end, 2.2 * scale, 1.0, 0.45 - dim * 0.5, 0.8 - dim * 0.5)
    cv.capsule('core', root, elbow, 2.0 * scale, 1.8 * scale, 0.6 - dim, 0.9 - dim)
    cv.capsule('core', elbow, tip, 1.8 * scale, 0.8, 0.6 - dim, 0.95 - dim)
    # runes glowing along the wing
    for k, s in enumerate((0.35, 0.65, 0.9)):
        p = root + (tip - root) * s + np.array((side * 1.5 * flat, 9 * scale))
        g = RUNES[(k * 2 + (side > 0)) % len(RUNES)]
        for a, b in g:
            P = p + np.array(((a[0] - 2) * 0.6 * flat, (a[1] - 3) * 0.55))
            Q = p + np.array(((b[0] - 2) * 0.6 * flat, (b[1] - 3) * 0.55))
            cv.capsule('prism', P, Q, 0.45, 0.45, 0.9 - dim, 0.9 - dim)


def runic_wings(d, t):
    cv = canvas()
    beat = TAU * t / PHASES
    spread = 0.5 + 0.5 * math.sin(beat)
    root = np.array(WING_ROOT)
    name = DIRS[d]
    if name in ('north', 'south'):
        sc = 1.08 if name == 'north' else 1.0
        for side in (-1, 1):
            wing(cv, root + np.array((side * 2.5, 0)), side, spread, beat, sc, 0.0)
    else:   # profile: both wings swept behind (towards the back of the wearer)
        back = -1 if name == 'east' else 1
        wing(cv, root + np.array((back * 1, -1)), back, spread, beat + 0.4, 0.95, 0.15, 0.85)
        wing(cv, root + np.array((back * 4, 1)), back, spread * 0.7, beat, 1.0, 0.0, 0.95)
    return cv.finish()


KINDS = {   # key -> (role, draw function)
    'blood_vortex': ('aura', blood_vortex),
    'rune_seal': ('aura', rune_seal),
    'runic_wings': ('wings', runic_wings),
}


def frames(key):
    """-> [phase][direction] -> list of layers (96 x 96 RGBA uint8): 2 for an aura (back, front), 1 for wings"""
    role, fn = KINDS[key]
    out = []
    for t in range(PHASES):
        row = []
        for d in range(4):
            img = fn(d, t)
            row.append(list(split_layers(img, AURA_CENTRE[1])) if role == 'aura' else [img])
        out.append(row)
    return out


def check(key, fr):
    bad = []
    for t, row in enumerate(fr):
        for d, layers in enumerate(row):
            full = np.zeros((N, N), bool)
            for img in layers:
                a = img[..., 3]
                if ((a != 0) & (a != 255)).any():
                    bad.append('%s t%d d%d: alpha not 0 / 255' % (key, t, d))
                full |= a > 0
            if not full.any():
                bad.append('%s t%d d%d: empty' % (key, t, d))
            if full[0].any() or full[-1].any() or full[:, 0].any() or full[:, -1].any():
                bad.append('%s t%d d%d: touches the frame edge' % (key, t, d))
    return bad
