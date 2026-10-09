"""GHOUL: a hunched, starved corpse-eater, half on all fours -- big bald head bowed down, glowing red eyes, a dark
maw, pointed ears, a knobbed spine, long arms whose claws nearly drag on the ground, crouched short legs. Asked on
2026-10-09: "one small creature shape + idle/walk preview, e.g. a bone-golem-like or ghoul creature".

    python creatures/ghoul.py shape              # the shape: ghoul_python.png (north | south) + the 4 views
    python creatures/ghoul.py preview            # the idle and the walk on the SHAPE itself (no PixelLab)
    python creatures/ghoul.py edit [3]           # PixelLab repaints the shape (spends balance; needs the token)
    python creatures/ghoul.py review             # how much of each variant's silhouette is the shape's
    python creatures/ghoul.py pick <edit_vN.png> # the chosen one -> ghoul_pixellab.png
    python creatures/ghoul.py animate            # ghoul_idle8_walking8.png and the GIFs, from the pick

The way (the skill /creature): the SHAPE here, in the Tibia projection; PixelLab only repaints it; the painting is
put on the posed shape frame by frame. Kit: kit/creature_kit.py (shape, PixelLab) and kit/creature_anim.py (motion,
sheet); the projection and the distance primitives in kit/tibia_view.py.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

KIT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "kit")
sys.path.insert(0, KIT)
import creature_anim as ca  # noqa: E402
import creature_kit as ck  # noqa: E402
from tibia_view import sd_ellipsoid, sd_cone, smin  # noqa: E402

NAME = "ghoul"
FRAME = 64
K = 1.15
WALKS = "forward"


def P3(u, v, h):
    """Body coordinates: u forward, v its right, h up -- pixels of the frame before K."""
    return np.array((u, v, h), float) * K


# ------------------------------------------------------------------ the shape
# One distance per part, and PLAIN min between parts. The whole head (skull, ears, eyes, maw) nods down about the top
# of the neck. Arms and legs are upright thin parts: material in `painter`.

NECK = P3(3.6, 0, 16.4)
LEGS = {}           # leg -> (hip, foot)
ARMS = {}           # arm -> (shoulder, hand)


def nodded(sdf, pivot=NECK, degrees=22.0):
    """A part of a head nodded DOWN by `degrees` about `pivot` (the top of the neck): the face looks down."""
    R = ca.rotation((0, 1, 0), math.radians(degrees))
    return lambda X: sdf((X - pivot) @ R + pivot)


def parts():
    P = {}
    P["pelvis"] = ("skin", lambda X: sd_ellipsoid(X, P3(-1.6, 0, 9.0), P3(3.0, 4.0, 3.0)))
    P["chest"] = ("skin", lambda X: sd_ellipsoid(X, P3(1.0, 0, 12.6), P3(4.8, 5.4, 4.4)))
    P["spine"] = ("bone", lambda X: smin(smin(sd_ellipsoid(X, P3(-2.4, 0, 14.6), P3(1.3, 1.1, 1.1)),
                                              sd_ellipsoid(X, P3(-0.4, 0, 16.6), P3(1.3, 1.1, 1.1)), 0.3),
                                         sd_ellipsoid(X, P3(1.8, 0, 17.0), P3(1.2, 1.0, 1.0)), 0.3))
    P["head"] = ("skin", nodded(lambda X: sd_ellipsoid(X, P3(5.6, 0, 17.4), P3(4.2, 4.0, 3.8))))
    P["maw"] = ("mouth", nodded(lambda X: sd_ellipsoid(X, P3(9.1, 0, 15.8), P3(1.1, 2.2, 1.0))))
    for side, sg in (("r", 1), ("l", -1)):
        P["eye_" + side] = ("eye", nodded(lambda X, sg=sg: sd_ellipsoid(X, P3(9.1, sg * 1.7, 18.1), P3(1.0, 1.0, 1.0))))
        P["ear_" + side] = ("limb", nodded(lambda X, sg=sg: sd_cone(X, P3(4.6, sg * 3.2, 18.6), P3(2.8, sg * 5.6, 20.2),
                                                                   1.0 * K, 0.5 * K)))
        sh, el, wr = P3(2.2, sg * 5.2, 13.6), P3(3.8, sg * 6.8, 8.4), P3(4.8, sg * 6.6, 3.0)
        hand = P3(5.8, sg * 6.6, 1.4)
        ARMS["arm_" + side] = (sh, hand)
        P["arm_" + side] = ("limb", lambda X, a=sh, b=el, c=wr: smin(sd_cone(X, a, b, 1.6 * K, 1.2 * K),
                                                                   sd_cone(X, b, c, 1.2 * K, 1.0 * K), 0.4))
        P["claw_" + side] = ("claw", lambda X, h=hand: sd_ellipsoid(X, h, P3(1.9, 1.4, 1.2)))
        hip, knee, ank = P3(-1.6, sg * 3.0, 8.0), P3(1.4, sg * 4.2, 5.0), P3(-0.4, sg * 4.2, 1.4)
        foot = P3(0.8, sg * 4.2, 0.8)
        LEGS["leg_" + side] = (hip, foot)
        P["leg_" + side] = ("limb", lambda X, a=hip, b=knee, c=ank, f=foot: np.minimum(
            smin(sd_cone(X, a, b, 1.9 * K, 1.4 * K), sd_cone(X, b, c, 1.4 * K, 1.1 * K), 0.4),
            sd_ellipsoid(X, f, P3(2.0, 1.3, 0.8))))
    return P


PARTS = parts()
SKIN = [(18, 22, 22), (40, 48, 42), (66, 78, 62), (98, 110, 84), (134, 142, 108), (172, 174, 136), (212, 206, 168)]
RAMPS = {                                               # dark -> light: cold grave-green shade, warm sallow light
    "skin": ck.ramp(SKIN, 11),
    "limb": ck.ramp(SKIN, 9),
    "bone": ck.ramp([(30, 24, 18), (74, 62, 46), (130, 116, 88), (186, 174, 140), (226, 218, 190)], 7),
    "claw": ck.ramp([(10, 8, 10), (30, 26, 28), (60, 54, 54), (96, 90, 84)], 5),
    "mouth": ck.ramp([(8, 2, 4), (30, 6, 10), (60, 14, 18)], 3),
    "eye": ck.ramp([(110, 12, 8), (200, 40, 18), (255, 128, 64), (255, 210, 150)], 4),
}
OUTLINE = {"skin": (8, 10, 10), "limb": (8, 10, 10), "bone": (22, 16, 12), "claw": (4, 4, 6), "mouth": (4, 0, 2),
           "eye": (60, 6, 4)}
SHAPE = ck.Shape(NAME, PARTS, RAMPS, OUTLINE, frame=FRAME, top=30.0 * max(K, 1.0),
                 mottle=("skin",), gloss=("bone", "claw"), glow=("eye",), painter=("limb",))

# what PixelLab is told the creature is (the shape keeps the silhouette; this says the materials and the details)
WHAT = "ghoul"
DESIGN = ("A starved hunched ghoul: sallow grey-green corpse skin stretched over visible ribs and a knobbed yellowed "
          "spine, big bald head bowed slightly forward and DOWN (the face looks down toward the viewer, never up), "
          "two small glowing red eyes, a dark open maw with a few jagged teeth, long pointed ears, very long thin "
          "arms ending in black hooked claws that nearly touch the ground, short crouched legs.")


# ------------------------------------------------------------------ the motion

def swing(name, hinge, degrees, body):
    """A limb turned about its hinge, its end going FORWARD for +degrees (tested in check_signs)."""
    return ca.turn((0, 1, 0), -degrees, hinge, then=body)


def pose(bob=0, legs=None, arms=None):
    body = ca.lifted(bob)
    T = {}
    for name in PARTS:
        side = name[-1]
        if name in LEGS:
            T[name] = swing(name, LEGS[name][0], (legs or {}).get(name, 0.0), body)
        elif name.startswith(("arm_", "claw_")):
            arm = "arm_" + side
            T[name] = swing(arm, ARMS[arm][0], (arms or {}).get(arm, 0.0), body)
        else:
            T[name] = body
    return T


def walk_pose(k, n=8):
    s = 16 * math.sin(2 * math.pi * k / n)                 # biped: alternating legs, the arms against them
    return pose(bob=1 if k % (n // 2) == 0 else 0, legs={"leg_r": s, "leg_l": -s},
                arms={"arm_r": -0.8 * s, "arm_l": 0.8 * s})


def idle_pose(k):
    """A rest pause, a breath (the body up 1 px), then the claws twitch forward and back. The face never moves."""
    reach = {5: 7, 6: 7}.get(k, 0)
    return pose(bob=1 if k in (2, 3) else 0, arms={"arm_r": reach, "arm_l": reach * 0.6})


IDLE = [idle_pose(k) for k in range(8)]
IDLE_MS = [400, 140, 160, 160, 140, 110, 110, 200]
WALK = [walk_pose(k) for k in range(8)]
WALK_MS = [110] * 8
THIN = ()


def check_signs():
    """Every rotation's sign, TESTED."""
    T = pose(legs={n: 20 for n in LEGS}, arms={n: 20 for n in ARMS})
    for name, (hinge, end) in list(LEGS.items()) + list(ARMS.items()):
        R, c, t = T[name]
        assert (R @ (end - c) + c + t)[0] > end[0], name + ": +degrees must swing the end FORWARD"
    face = P3(9, 0, 17)
    moved = nodded(lambda X: X[:, 2])
    assert moved(face[None])[0] > face[2], "the nod must bring the face DOWN (a level point is found higher up)"


MODEL = ca.Model(PARTS, list(PARTS), frame=FRAME, ground=SHAPE.ground, top=SHAPE.top, ss=4)


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else ""
    out = SHAPE.out
    check_signs()
    shape_png = os.path.join(out, NAME + "_python.png")
    if what == "shape":
        SHAPE.save_shape()
    elif what == "preview":                 # the motion on the shape's own render: no PixelLab spent
        if not os.path.exists(shape_png):
            SHAPE.save_shape()
        ca.make_sheet(MODEL, Image.open(shape_png).convert("RGBA"), IDLE, WALK, NAME + "_shape", out,
                      IDLE_MS, WALK_MS, walks=WALKS, exact=False)
    elif what == "edit":
        ck.pixellab_edit(shape_png, ck.edit_prompt(WHAT, DESIGN, size=FRAME), os.path.join(out, "edit"),
                         int(sys.argv[2]) if len(sys.argv) > 2 else 3)
        ck.review(shape_png, os.path.join(out, "edit"), FRAME)
    elif what == "review":
        ck.review(shape_png, os.path.join(out, "edit"), FRAME)
    elif what == "pick":
        ck.pick(sys.argv[2], os.path.join(out, NAME + "_pixellab.png"))
    elif what == "animate":
        painting = Image.open(os.path.join(out, NAME + "_pixellab.png")).convert("RGBA")
        ca.make_sheet(MODEL, painting, IDLE, WALK, NAME, out, IDLE_MS, WALK_MS, walks=WALKS, exact=True, thin=THIN)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
