"""RIFT BESTIARY (trial, not imported: the rift looks are donor creatures, see NOTES.md): new-art creatures for the rift
families (four families x minion / brute / elite / guardian; only the Ashen Crypt four were started). Asked on 2026-10-10 (owner): "Make sprites for the monsters that don't have one. Rift monsters
must be exclusive and custom." Style reference only (never their pixels): chibi proportions, thick dark outline, rich
shading, rim light; the families follow the owner's orc/undead/eldritch/fungus/elemental sheets.

    python creatures/rift_bestiary.py list                      # every creature, its family, frame and archetype
    python creatures/rift_bestiary.py <key> shape               # out/rift/<key>/<key>_python.png (north | south) + 4 views
    python creatures/rift_bestiary.py <key> preview             # the idle and the walk on the shape (no PixelLab)
    python creatures/rift_bestiary.py <key> edit [n]            # PixelLab repaints the shape (spends balance)
    python creatures/rift_bestiary.py <key> review
    python creatures/rift_bestiary.py <key> pick <edit_vN.png>  # -> <key>_pixellab.png
    python creatures/rift_bestiary.py <key> animate [shape]     # <key>_idle8_walking8.png from the pick (or the shape)
    python creatures/rift_bestiary.py board                     # out/rift/board_<family>.png, every final sheet

One file for all of them (the /creature way, shared builders): the SHAPE from signed distances in the Tibia
projection, PixelLab only repaints it (Edit images Pro), the animation dresses the posed shape in the painting.
`animate shape` uses the shape's own render as the painting (the Python-only path, no PixelLab).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

KIT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "kit")
sys.path.insert(0, KIT)
import creature_anim as ca  # noqa: E402
import creature_kit as ck  # noqa: E402
from tibia_view import sd_ellipsoid, sd_cone, sd_box, smin  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "rift")
OUT = os.path.normpath(OUT)
VIEWS = ("north", "east", "south", "west")

# ------------------------------------------------------------------ upright creatures
# The kit draws a point of height h h/1.5 up AND h/1.5 left (the floor rule): a standing biped then leans 45 degrees and
# reads as lying down. Creature sprites stand upright: here the body is sheared so that height goes up with only
# (1 - UPRIGHT) of that drift to the left. The projection is then no longer symmetric about the diagonal, so all FOUR
# views are rendered and painted (no east = transposed south). Only this script is affected (the patch is local).
import tibia_view as pt  # noqa: E402
UPRIGHT = 0.8
_LEAN = UPRIGHT / 1.5
_to_body, _dir_to_body, _rest_pixel = pt.Facing.to_body, pt.Facing.dir_to_body, ca.rest_pixel


def _sheared_to_body(self, W):
    W = np.array(W, float)
    W[:, 0] -= _LEAN * W[:, 2]
    return _to_body(self, W)


def _sheared_dir_to_body(self, D):
    D = np.array(D, float)
    D[:, 0] -= _LEAN * D[:, 2]
    return _dir_to_body(self, D)


def _sheared_rest_pixel(model, fc, Xr):
    wx = model.ground[0] + Xr[..., 0] * fc.F[0] + Xr[..., 1] * fc.R[0] - Xr[..., 2] / 1.5 + _LEAN * Xr[..., 2]
    wy = model.ground[1] + Xr[..., 0] * fc.F[1] + Xr[..., 1] * fc.R[1] - Xr[..., 2] / 1.5
    return np.floor(wx).astype(int), np.floor(wy).astype(int)


pt.Facing.to_body, pt.Facing.dir_to_body, ca.rest_pixel = _sheared_to_body, _sheared_dir_to_body, _sheared_rest_pixel


# ------------------------------------------------------------------ builders
class B:
    """Collects the parts of one creature: name -> (material, sdf), plus the rig (hinges) the poses use."""

    def __init__(self, K):
        self.K = K
        self.P = {}
        self.legs = {}      # name -> (hinge, end, phase group 0/1)
        self.arms = {}      # name -> (hinge, end, phase group)
        self.tent = {}      # name -> (root, tip, phase offset)
        self.wings = {}     # name -> (hinge, side)
        self.attach = {}    # part -> limb it moves with
        self.head = []      # parts that move with the head (idle nod)
        self.float = False

    def p(self, u, v, h):
        return np.array((u, v, h), float) * self.K

    def r(self, x):
        return x * self.K

    def add(self, name, mat, f):
        self.P[name] = (mat, f)

    def ell(self, name, mat, c, r):
        c, r = self.p(*c), self.p(*r)
        self.add(name, mat, lambda X, c=c, r=r: sd_ellipsoid(X, c, r))

    def cone(self, name, mat, a, b, ra, rb):
        a, b = self.p(*a), self.p(*b)
        ra, rb = self.r(ra), self.r(rb)
        self.add(name, mat, lambda X, a=a, b=b, ra=ra, rb=rb: sd_cone(X, a, b, ra, rb))

    def chain(self, name, mat, pts, radii, k=0.4):
        """A bent limb / tentacle: cones through pts with radii at each point (smooth inside the part)."""
        P = [self.p(*q) for q in pts]
        R = [self.r(x) for x in radii]

        def f(X, P=P, R=R):
            d = sd_cone(X, P[0], P[1], R[0], R[1])
            for i in range(1, len(P) - 1):
                d = smin(d, sd_cone(X, P[i], P[i + 1], R[i], R[i + 1]), k)
            return d
        self.add(name, mat, f)
        return P[0], P[-1]


def nod(f, pivot, degrees):
    R = ca.rotation((0, 1, 0), math.radians(degrees))
    return lambda X: f((X - pivot) @ R + pivot)


SIDES = (("r", 1), ("l", -1))


def biped(b, mats, hip_h, leg_r, stance, foot):
    """Two short legs (chibi): hip height, thickness, half stance, foot length."""
    for s, sg in SIDES:
        hip, knee, ank = (-0.6, sg * stance, hip_h), (0.6, sg * (stance + 0.4), hip_h * 0.5), (-0.2, sg * (stance + 0.4), 1.2)
        a, _ = b.chain("leg_" + s, mats[0], [hip, knee, ank], [leg_r, leg_r * 0.85, leg_r * 0.75])
        b.ell("foot_" + s, mats[1], (0.6 + foot * 0.3, sg * (stance + 0.4), 0.8), (foot, leg_r * 0.85, 0.8))
        b.legs["leg_" + s] = (a, b.p(0.6 + foot * 0.3, sg * (stance + 0.4), 0.8), 0 if sg > 0 else 1)
        b.attach["foot_" + s] = "leg_" + s


def quadruped(b, mats, body_c, body_r, leg_r, hip_h, spread, reach):
    """Four legs under a body (front pair at +reach, back at -reach)."""
    for end, uu in (("f", reach), ("b", -reach)):
        for s, sg in SIDES:
            nm = "leg_%s%s" % (end, s)
            hip = (body_c[0] + uu, sg * spread, hip_h)
            knee = (body_c[0] + uu + (0.8 if end == "f" else -0.8), sg * (spread + 0.5), hip_h * 0.5)
            paw = (body_c[0] + uu + 0.3, sg * (spread + 0.6), 0.9)
            a, _ = b.chain(nm, mats[0], [hip, knee, paw], [leg_r, leg_r * 0.8, leg_r * 0.75])
            b.ell("paw_%s%s" % (end, s), mats[1], (paw[0] + 0.7, paw[1], 0.8), (1.4 * leg_r, leg_r, 0.75))
            b.attach["paw_%s%s" % (end, s)] = nm
            # diagonal pairs: front right + back left together
            grp = 0 if (end == "f") == (sg > 0) else 1
            b.legs[nm] = (a, b.p(paw[0], paw[1], 0.9), grp)


# ------------------------------------------------------------------ the creatures
# each builder: b = B(K); ... ; returns b. CREATURES[key] = dict(family, rank, frame, K, build, ramps, outline,
# classes, what, design)

def undead_minion(b):          # ASHEN THRALL: a hunched ash-grey corpse, ember eyes, ribs, long arms
    neck = b.p(3.4, 0, 15.8)
    b.ell("pelvis", "skin", (-1.6, 0, 8.6), (3.0, 3.8, 2.8))
    b.ell("chest", "skin", (0.8, 0, 12.2), (4.6, 5.2, 4.2))
    b.chain("spine", "bone", [(-2.6, 0, 14.0), (-0.4, 0, 16.2), (1.8, 0, 16.6)], [1.3, 1.3, 1.1])
    head = lambda X, c=b.p(5.0, 0, 17.6), r=b.p(4.8, 4.6, 4.4): sd_ellipsoid(X, c, r)  # noqa: E731
    b.add("head", "skin", nod(head, neck, 22))
    b.add("jaw", "mouth", nod(lambda X, c=b.p(8.7, 0, 15.4), r=b.p(1.0, 2.0, 0.9): sd_ellipsoid(X, c, r), neck, 22))
    for s, sg in SIDES:
        b.add("eye_" + s, "eye", nod(lambda X, c=b.p(8.7, sg * 1.6, 17.7), r=b.p(1.0, 1.0, 1.0): sd_ellipsoid(X, c, r), neck, 22))
        sh, el, wr = (2.0, sg * 5.0, 13.2), (3.6, sg * 6.6, 8.2), (4.6, sg * 6.4, 3.0)
        a, _ = b.chain("arm_" + s, "limb", [sh, el, wr], [1.6, 1.2, 1.0])
        b.ell("claw_" + s, "claw", (5.6, sg * 6.4, 1.6), (1.9, 1.4, 1.2))
        b.arms["arm_" + s] = (a, b.p(5.6, sg * 6.4, 1.4), 0 if sg > 0 else 1)
        b.attach["claw_" + s] = "arm_" + s
    b.head = ["head", "jaw", "eye_r", "eye_l"]
    biped(b, ("limb", "limb"), 8.0, 1.8, 3.0, 1.6)
    return b


def undead_brute(b):           # BONE HOUND: a skeletal hound, rib cage, skull with cyan eye-fire, spine ridge
    quadruped(b, ("bone", "bone"), (0, 0, 9), None, 1.4, 8.0, 3.8, 4.6)
    b.ell("hips", "bone", (-4.4, 0, 9.0), (2.8, 3.4, 2.4))
    b.add("ribs", "bone", lambda X, c=b.p(1.2, 0, 10.0), r=b.p(5.2, 4.6, 3.6), c2=b.p(1.2, 0, 10.0), r2=b.p(4.4, 3.6, 2.8):
          np.maximum(sd_ellipsoid(X, c, r), -sd_ellipsoid(X, c2, r2)))
    b.ell("void", "dark", (1.2, 0, 10.0), (4.6, 3.8, 3.0))
    b.chain("spine", "bone", [(-6.8, 0, 10.4), (-2.0, 0, 13.6), (3.6, 0, 13.4), (6.0, 0, 13.0)], [1.0, 1.4, 1.3, 1.1])
    for i, u in enumerate((-4.0, -1.2, 1.6, 4.2)):
        b.cone("spike%d" % i, "horn", (u, 0, 13.8), (u - 1.4, 0, 17.2), 0.9, 0.35)
    b.ell("skull", "bone", (8.0, 0, 13.6), (3.4, 2.8, 2.6))
    b.ell("snout", "bone", (10.8, 0, 12.4), (2.4, 1.7, 1.4))
    b.ell("maw", "dark", (11.4, 0, 11.4), (1.8, 1.3, 0.7))
    for s, sg in SIDES:
        b.ell("eye_" + s, "eye", (9.4, sg * 1.5, 14.6), (0.9, 0.8, 0.8))
        b.cone("horn_" + s, "horn", (7.0, sg * 2.0, 15.4), (5.0, sg * 3.6, 18.6), 0.9, 0.35)
    b.cone("tail", "bone", (-6.8, 0, 10.0), (-11.0, 0, 6.6), 0.9, 0.5)
    b.head = ["skull", "snout", "maw", "eye_r", "eye_l", "horn_r", "horn_l"]
    return b


def undead_elite(b):           # CRYPT WRAITH: a hovering hooded wraith in tattered ash robes, a lantern of soul-fire
    b.float = True
    b.add("robe", "cloth", lambda X, a=b.p(0, 0, 4.0), c=b.p(0, 0, 15.0): smin(sd_cone(X, a, c, b.r(6.0), b.r(3.6)),
                                                                             sd_ellipsoid(X, b.p(0, 0, 4.5), b.p(5.0, 5.6, 2.4)), 1.0))
    for i, (u, v) in enumerate(((3.0, 3.6), (-1.0, 5.4), (-4.4, 1.4), (1.0, -5.0), (-3.6, -3.6))):
        b.cone("tatter%d" % i, "cloth", (u * 0.8, v * 0.8, 4.4), (u * 1.05, v * 1.05, 1.2), 1.4, 0.6)
    neck = b.p(0.6, 0, 16.8)
    b.add("hood", "hood", nod(lambda X, c=b.p(1.0, 0, 19.0), r=b.p(4.4, 4.1, 4.2), a=b.p(-1.0, 0, 21.0), t=b.p(-4.6, 0, 23.4):
                              smin(sd_ellipsoid(X, c, r), sd_cone(X, a, t, b.r(2.6), b.r(0.6)), 0.8), neck, 18))
    b.add("face", "dark", nod(lambda X, c=b.p(4.4, 0, 18.6), r=b.p(1.6, 2.6, 2.6): sd_ellipsoid(X, c, r), neck, 18))
    for s, sg in SIDES:
        b.add("eye_" + s, "eye", nod(lambda X, c=b.p(5.2, sg * 1.1, 19.0), r=b.p(0.8, 0.7, 0.7): sd_ellipsoid(X, c, r), neck, 18))
        sh, el, hd = (1.4, sg * 4.4, 14.6), (3.8, sg * 6.0, 11.6), (6.2, sg * 5.8, 10.4)
        a, _ = b.chain("arm_" + s, "cloth", [sh, el, hd], [1.7, 1.4, 1.2])
        b.ell("hand_" + s, "limb", (7.0, sg * 5.8, 10.2), (1.4, 1.0, 1.0))
        b.arms["arm_" + s] = (a, b.p(7.0, sg * 5.8, 10.2), 0 if sg > 0 else 1)
        b.attach["hand_" + s] = "arm_" + s
    b.ell("lantern", "glow", (8.2, 5.8, 7.6), (1.6, 1.6, 1.9))
    b.cone("chainl", "metal", (7.2, 5.8, 9.8), (8.2, 5.8, 9.4), 0.5, 0.5)
    b.attach["lantern"] = "arm_r"
    b.attach["chainl"] = "arm_r"
    b.head = ["hood", "face", "eye_r", "eye_l"]
    return b


def undead_guardian(b):        # OSSUARY KNIGHT: a hulking skeletal knight in rusted black plate, ash cape, a great
    neck = b.p(1.4, 0, 22.6)   # bone-handled cleaver hanging from the right hand, ember eyes under a horned helm
    b.ell("pelvis", "metal", (-0.6, 0, 11.0), (4.0, 5.0, 3.2))
    b.ell("torso", "metal", (0.4, 0, 16.6), (5.4, 6.8, 5.6))
    b.ell("ribs", "bone", (3.2, 0, 16.0), (3.0, 4.4, 4.0))
    b.ell("cape", "cloth", (-3.6, 0, 15.0), (2.6, 7.2, 7.6))
    b.add("helm", "metal", nod(lambda X, c=b.p(1.8, 0, 24.6), r=b.p(3.6, 3.4, 3.6): sd_ellipsoid(X, c, r), neck, 18))
    b.add("visor", "dark", nod(lambda X, c=b.p(4.8, 0, 24.0), r=b.p(1.2, 2.4, 1.4): sd_ellipsoid(X, c, r), neck, 18))
    for s, sg in SIDES:
        b.add("eye_" + s, "eye", nod(lambda X, c=b.p(5.6, sg * 1.2, 24.4), r=b.p(0.7, 0.7, 0.6): sd_ellipsoid(X, c, r), neck, 18))
        b.add("horn_" + s, "bone", nod(lambda X, a=b.p(1.6, sg * 2.8, 26.2), c=b.p(-0.6, sg * 5.6, 30.6):
                                       sd_cone(X, a, c, b.r(1.3), b.r(0.5)), neck, 18))
        b.ell("pauldron_" + s, "metal", (0.4, sg * 6.6, 19.8), (3.2, 2.8, 2.4))
        sh, el, hd = (0.8, sg * 7.4, 18.0), (2.8, sg * 8.4, 13.0), (5.0, sg * 8.0, 10.4)
        a, _ = b.chain("arm_" + s, "bone", [sh, el, hd], [1.8, 1.5, 1.4])
        b.ell("gaunt_" + s, "metal", (5.6, sg * 8.0, 10.0), (1.9, 1.7, 1.7))
        b.arms["arm_" + s] = (a, b.p(5.6, sg * 8.0, 10.0), 0 if sg > 0 else 1)
        b.attach["gaunt_" + s] = "arm_" + s
    # the cleaver: by the handle, the blade hanging straight down (in the plane of the front-right diagonal)
    b.cone("haft", "bone", (5.6, 8.0, 10.0), (9.4, 8.0, 9.6), 0.8, 0.8)
    b.add("blade", "steel", lambda X, c=b.p(10.4, 8.0, 5.6), hh=b.p(1.8, 0.6, 4.4): sd_box(X, c, hh, b.r(0.4)))
    b.attach["haft"] = "arm_r"
    b.attach["blade"] = "arm_r"
    b.arms["arm_r"] = b.arms["arm_r"][:2] + (-1,)          # the weapon arm does not swing
    b.head = ["helm", "visor", "eye_r", "eye_l", "horn_r", "horn_l"]
    biped(b, ("metal", "metal"), 11.0, 2.4, 3.4, 2.0)
    return b


R = ck.ramp
ASH = [(34, 30, 34), (66, 60, 62), (100, 94, 90), (136, 128, 120), (172, 164, 150), (206, 198, 180), (236, 230, 212)]
BONE = [(30, 24, 18), (74, 62, 46), (130, 116, 88), (186, 174, 140), (230, 222, 196)]
EMBER = [(110, 30, 8), (200, 80, 18), (255, 150, 50), (255, 222, 150)]
SOUL = [(10, 60, 70), (30, 140, 150), (110, 230, 220), (220, 255, 250)]
RUST = [(22, 18, 24), (46, 40, 48), (74, 64, 70), (108, 92, 88), (146, 120, 98), (186, 160, 128), (220, 200, 168)]

CREATURES = {
    "ashen_thrall": dict(family="crypt", rank="minion", frame=64, K=1.45, build=undead_minion,
                         ramps={"skin": R(ASH, 11), "limb": R(ASH, 9), "bone": R(BONE, 7), "claw": R(RUST[:4], 5),
                                "mouth": R([(8, 2, 4), (30, 6, 10), (60, 14, 18)], 3), "eye": R(EMBER, 4)},
                         classes=dict(mottle=("skin",), gloss=("bone", "claw"), glow=("eye",), painter=("limb",)),
                         what="ash ghoul",
                         design="A hunched starved ghoul made of grey ash and cinders: cracked ash-grey corpse skin "
                                "with faint ember glow in the cracks, a knobbed yellowed spine, a big bald head bowed "
                                "slightly forward and DOWN (the face looks down toward the viewer, never up), two small "
                                "glowing ember-orange eyes, a dark maw, very long thin arms with black hooked claws, "
                                "short crouched legs."),
    "bone_hound": dict(family="crypt", rank="brute", frame=64, anim_frame=96, K=2.05, build=undead_brute,
                       ramps={"bone": R(BONE, 9), "horn": R(RUST[:5], 6), "dark": R([(6, 4, 8), (20, 14, 22), (40, 30, 40)], 3),
                              "eye": R(SOUL, 4)},
                       classes=dict(gloss=("bone", "horn"), glow=("eye",), painter=("horn",)),
                       what="skeletal hound",
                       design="A skeletal hound of old yellowed bone: an open rib cage with darkness inside, a "
                              "long horned canine skull with cyan soul-fire eyes, a ridge of black iron spikes along "
                              "the spine, thin bony legs with clawed paws, a short bony tail."),
    "crypt_wraith": dict(family="crypt", rank="elite", frame=64, K=1.66, build=undead_elite,
                         ramps={"cloth": R([(26, 28, 38), (52, 56, 70), (84, 90, 104), (120, 126, 136), (160, 164, 170), (200, 202, 204)], 9),
                                "hood": R([(30, 30, 44), (60, 62, 80), (96, 100, 118), (136, 140, 154), (180, 184, 192)], 8), "dark": R([(4, 4, 8), (14, 14, 20), (28, 26, 34)], 3),
                                "limb": R(BONE, 6), "eye": R(SOUL, 4), "glow": R(SOUL, 5), "metal": R(RUST, 5)},
                         classes=dict(mottle=("cloth", "hood"), gloss=("metal",), glow=("eye", "glow"), painter=("limb",)),
                         what="hooded wraith",
                         design="A hovering wraith in a tattered ash-grey hooded robe that ends in ragged strips "
                                "above the ground, a black void under the hood with two cyan soul-fire eyes, bony "
                                "pale hands; the right hand holds a small iron lantern of cyan soul-fire by a short "
                                "chain. Hood bowed slightly forward and DOWN."),
    "ossuary_knight": dict(family="crypt", rank="guardian", frame=96, K=1.75, build=undead_guardian,
                           ramps={"metal": R(RUST, 9), "bone": R(BONE, 8), "cloth": R([(24, 20, 22), (48, 40, 40), (76, 64, 60), (104, 92, 84)], 6),
                                  "dark": R([(4, 2, 4), (16, 10, 12), (30, 20, 22)], 3), "eye": R(EMBER, 4),
                                  "steel": R([(30, 30, 36), (70, 70, 78), (120, 120, 128), (176, 176, 184), (220, 220, 226)], 7)},
                           classes=dict(mottle=("cloth",), gloss=("metal", "steel", "bone"), glow=("eye",), painter=("bone",)),
                           what="skeletal knight",
                           design="A hulking undead knight: a skeleton in rusted black plate armour with big "
                                  "pauldrons and a tattered dark ash cape, bone arms, a horned black helm with two "
                                  "glowing ember eyes in the visor slit, head bowed slightly DOWN; the right hand holds "
                                  "a great notched iron cleaver by its bone handle, the blade hanging straight down."),
}


# ------------------------------------------------------------------ shape, motion, sheet

class Creature:
    def __init__(self, key):
        c = CREATURES[key]
        self.key, self.c = key, c
        self.frame = c["frame"]
        b = c["build"](B(c["K"]))
        self.b = b
        self.parts = b.P
        self.out = os.path.join(OUT, key)
        os.makedirs(self.out, exist_ok=True)
        ground = (self.frame - 24.5, self.frame - 24.0)
        top = c.get("top", (30.0 if self.frame <= 64 else 44.0) * max(c["K"], 1.0))
        outline = {m: tuple(int(x * 0.35) for x in rp[0]) for m, rp in c["ramps"].items()}
        outline.update(c.get("outline", {}))
        self.shape = ck.Shape(key, self.parts, c["ramps"], outline, frame=self.frame, ground=ground, top=top,
                              folder=os.path.join("rift", key), **c["classes"])
        # the animation may run in a bigger frame than the painting (anim_frame): a painting that fills its cell gets
        # room to be registered on the shape; the painted cells are padded on the top and left (the ground keeps its
        # place relative to the bottom-right tile), so nothing is scaled
        self.aframe = c.get("anim_frame", self.frame)
        A = self.aframe
        self.ashape = self.shape if A == self.frame else ck.Shape(
            key, self.parts, c["ramps"], outline, frame=A, ground=(A - 24.5, A - 24.0), top=top + (A - self.frame),
            folder=os.path.join("rift", key), **c["classes"])
        self.model = ca.Model(self.parts, list(self.parts), frame=A, ground=self.ashape.ground,
                              top=self.ashape.top, ss=4)

    def padded(self, img):
        """The four painted cells (frame n) moved into cells of the animation frame (top-left padding)."""
        a = np.asarray(img.convert("RGBA"))
        n, A = self.frame, self.aframe
        if a.shape[1] == 4 * A and A != n:
            return a.copy()
        # PixelLab does not keep to the cells: a tail may cross into the next one. Each connected piece goes to the
        # view whose cell holds most of it, at its place relative to that cell.
        from scipy import ndimage
        on = a[..., 3] >= 128
        lab, k = ndimage.label(on, structure=np.ones((3, 3), int))
        out = np.zeros((A, 4 * A, 4), np.uint8)
        off = A - n
        for j in range(1, k + 1):
            ys, xs = np.nonzero(lab == j)
            cell = int(np.clip(np.bincount(xs // n, minlength=4).argmax(), 0, 3))
            ty, tx = ys + off, xs - cell * n + off
            ok = (ty >= 0) & (ty < A) & (tx >= 0) & (tx < A)
            out[ty[ok], cell * A + tx[ok]] = a[ys[ok], xs[ok]]
        return out

    # the rig ---------------------------------------------------------
    def owner(self, name):
        return self.b.attach.get(name, name)

    def pose(self, bob=0, legs=None, arms=None, tent=0.0, wing=0.0, nod_deg=0.0):
        b = self.b
        body = ca.lifted(bob)
        T = {}
        for name in self.parts:
            o = self.owner(name)
            if o in b.legs:
                T[name] = ca.turn((0, 1, 0), -(legs or {}).get(o, 0.0), b.legs[o][0], then=body)
            elif o in b.arms:
                T[name] = ca.turn((0, 1, 0), -(arms or {}).get(o, 0.0), b.arms[o][0], then=body)
            elif o in b.tent:
                root, tip, ph = b.tent[o]
                T[name] = ca.turn((1, 0, 0), tent * math.sin(ph), root, then=body)
            else:
                T[name] = body
        return T

    def walk_poses(self, n=8):
        out = []
        for k in range(n):
            s = math.sin(2 * math.pi * k / n)
            if self.b.float:
                bob = (0, 1, 1, 1, 0, 0, 0, 0)[k]
                arms = {a: 6 * s * (1 if g == 0 else -1) for a, (_, _, g) in self.b.arms.items() if g >= 0}
                out.append(self.pose(bob=bob + 1, arms=arms))
                continue
            amp = self.c.get("step", 16)
            legs = {l: amp * s * (1 if g == 0 else -1) for l, (_, _, g) in self.b.legs.items()}
            arms = {a: -0.8 * amp * s * (1 if g == 0 else -1) for a, (_, _, g) in self.b.arms.items() if g >= 0}
            out.append(self.pose(bob=1 if k % (n // 2) == 0 else 0, legs=legs, arms=arms))
        return out

    def idle_poses(self, n=8):
        out = []
        for k in range(n):
            if self.b.float:
                out.append(self.pose(bob=(1, 1, 2, 2, 2, 1, 1, 1)[k]))
                continue
            reach = {5: 7, 6: 7}.get(k, 0)
            arms = {a: reach * (1 if g == 0 else 0.6) for a, (_, _, g) in self.b.arms.items() if g >= 0}
            out.append(self.pose(bob=1 if k in (2, 3) else 0, arms=arms))
        return out

    def check_signs(self):
        T = self.pose(legs={n: 20 for n in self.b.legs}, arms={n: 20 for n in self.b.arms})
        for name, (hinge, end, _g) in list(self.b.legs.items()) + list(self.b.arms.items()):
            Rm, c, t = T[name]
            assert (Rm @ (end - c) + c + t)[0] > end[0] - 1e-6, name + ": +degrees must swing the end FORWARD"

    # commands ---------------------------------------------------------
    def shape_png(self):
        return os.path.join(self.out, self.key + "_python.png")

    def cmd(self, what, args):
        self.check_signs()
        idle_ms = [400, 140, 160, 160, 140, 110, 110, 200]
        walk_ms = [110] * 8
        if what == "shape":
            self.shape.save_shape(views=VIEWS)
        elif what == "preview":
            if not os.path.exists(self.shape_png()):
                self.shape.save_shape(views=VIEWS)
            self.sheet(Image.open(self.shape_png()).convert("RGBA"), self.key + "_shape", idle_ms, walk_ms, exact=False)
        elif what == "edit":
            ck.pixellab_edit(self.shape_png(), ck.edit_prompt(self.c["what"], self.c["design"], views=VIEWS,
                                                              size=self.frame),
                             os.path.join(self.out, "edit"), int(args[0]) if args else 3)
            ck.review(self.shape_png(), os.path.join(self.out, "edit"), self.frame, views=VIEWS)
        elif what == "review":
            ck.review(self.shape_png(), os.path.join(self.out, "edit"), self.frame, views=VIEWS)
        elif what == "pick":
            ck.pick(args[0], os.path.join(self.out, self.key + "_pixellab.png"))
        elif what == "fit":
            self.fit()
        elif what == "animate":
            shape_only = bool(args) and args[0] == "shape"
            if shape_only:
                painting = np.concatenate([self.ashape.view(v) for v in VIEWS], 1)
            else:
                painting = np.asarray(Image.open(os.path.join(self.out, self.key + "_pixellab.png")).convert("RGBA"))
                if painting.shape[0] != self.aframe:
                    painting = self.padded(Image.fromarray(painting))
            self.sheet(Image.fromarray(painting), self.key, idle_ms, walk_ms, exact=not shape_only)
        else:
            print(__doc__)

    def fit(self):
        """PixelLab often repaints the creature a little bigger than the shape. Prints the scale of the painting
        against the shape (set K in CREATURES to K x scale and run `shape` again), then registers each painted view on
        the shape by the whole-pixel shift with the best overlap (writes <key>_pixellab.png back, the source kept as
        <key>_pixellab_src.png). The painting's pixels are never scaled."""
        n = self.aframe
        src = os.path.join(self.out, self.key + "_pixellab_src.png")
        dst = os.path.join(self.out, self.key + "_pixellab.png")
        if not os.path.exists(src):
            os.replace(dst, src)
        pa = self.padded(Image.open(src))
        sa = np.concatenate([self.ashape.view(v) for v in VIEWS], 1)
        out = np.zeros_like(pa)
        ratios = []
        for i, v in enumerate(VIEWS):
            p = pa[:, i * n:(i + 1) * n]
            s = sa[:, i * n:(i + 1) * n, 3] > 0
            on = p[..., 3] >= 128
            ys, xs = np.nonzero(on)
            ys2, xs2 = np.nonzero(s)
            ratios.append(math.sqrt(on.sum() / max(s.sum(), 1)))
            best = (-1, 0, 0)
            cy, cx = int(np.mean(ys2) - np.mean(ys)), int(np.mean(xs2) - np.mean(xs))
            def window(c, lo, hi):          # shifts that keep every painted pixel inside, near c
                a, b = max(c - 8, lo), min(c + 8, hi)
                return range(a, b + 1) if a <= b else range(min(max(c, lo), hi), min(max(c, lo), hi) + 1)
            for dy in window(cy, -ys.min(), n - 1 - ys.max()):
                for dx in window(cx, -xs.min(), n - 1 - xs.max()):
                    sh = np.roll(np.roll(on, dy, 0), dx, 1)          # the range keeps every painted pixel inside
                    iou = (sh & s).sum() / max((sh | s).sum(), 1)
                    if iou > best[0]:
                        best = (iou, dy, dx)
            iou, dy, dx = best
            out[:, i * n:(i + 1) * n] = np.roll(np.roll(p, dy, 0), dx, 1)
            print("%-5s scale %.2f  shift (%d, %d)  overlap %.2f" % (v, ratios[-1], dx, dy, iou))
        Image.fromarray(out, "RGBA").save(dst)
        print("scale %.2f: K %.2f -> %.2f" % (float(np.mean(ratios)), self.c["K"], self.c["K"] * float(np.mean(ratios))))

    def sheet(self, painting, name, idle_ms, walk_ms, exact=True):
        """The four painted views (north, east, south, west side by side) dressed on the posed shape."""
        n = self.aframe
        a = np.asarray(painting).copy()
        a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)
        a[a[..., 3] == 0, :3] = 0
        thin = self.c.get("thin", ())
        cols = {}
        for i, v in enumerate(VIEWS):
            view = np.ascontiguousarray(a[:, i * n:(i + 1) * n])
            idle = ca.animate(self.model, v, view, self.idle_poses(), exact, thin)
            walk = ca.animate(self.model, v, view, self.walk_poses(), exact, thin)
            cols[v] = idle + walk
            print(v, "idle frame 1 vs the painting: %d px differ" % int((idle[0] != view).any(-1).sum()))
        sheet = "%s_idle8_walking8" % name
        ca.save_sheet(self.out, cols, sheet, cell=128 if n <= 64 else 144)
        zoom = 4 if n <= 64 else 3
        ca.save_gif(self.out, {v: cols[v][:8] for v in VIEWS}, name + "_idle8", idle_ms, zoom=zoom)
        ca.save_gif(self.out, {v: cols[v][8:] for v in VIEWS}, name + "_walking8", walk_ms, zoom=zoom)
        return os.path.join(self.out, sheet + ".png")


def board(family):
    """One board per family: the final sheets' first idle frame (4 directions) at 1x and 3x, on dark floor."""
    keys = [k for k, c in CREATURES.items() if c["family"] == family]
    tiles = []
    for k in keys:
        p = os.path.join(OUT, k, k + "_idle8_walking8.png")
        if os.path.exists(p):
            tiles.append((k, Image.open(p).convert("RGBA"), CREATURES[k]["frame"]))
    if not tiles:
        return
    W = sum(4 * f * 3 + 20 for _, _, f in tiles)
    H = max(f for _, _, f in tiles) * 3 + max(f for _, _, f in tiles) + 40
    im = Image.new("RGBA", (W, H), (28, 26, 30, 255))
    d = ImageDraw.Draw(im)
    x = 10
    for k, sh, f in tiles:
        row = sh.crop((0, 0, 4 * f, f))
        im.alpha_composite(row, (x, 20))
        im.alpha_composite(row.resize((4 * f * 3, f * 3), Image.NEAREST), (x, f + 30))
        d.text((x, 4), "%s (%s)" % (k, CREATURES[k]["rank"]), fill=(240, 200, 120))
        x += 4 * f * 3 + 20
    im.save(os.path.join(OUT, "board_%s.png" % family))
    print(os.path.join(OUT, "board_%s.png" % family))


def main():
    a = sys.argv[1:]
    if not a or a[0] == "list":
        for k, c in CREATURES.items():
            print("%-18s %-8s %-8s frame %d" % (k, c["family"], c["rank"], c["frame"]))
        return
    if a[0] == "board":
        for fam in sorted({c["family"] for c in CREATURES.values()}):
            board(fam)
        return
    Creature(a[0]).cmd(a[1] if len(a) > 1 else "", a[2:])


if __name__ == "__main__":
    main()
