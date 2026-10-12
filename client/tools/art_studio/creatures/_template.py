"""BEETLE (the template's example: replace it): <what the creature is, in one line>. Asked on <date>: "<the user's words>".

    python creatures/<name>.py shape              # the shape: <name>_python.png (north | south) + the 4 views
    python creatures/<name>.py preview            # the idle and the walk on the SHAPE itself (no PixelLab):
                                                          #   judge the motion before spending generations
    python creatures/<name>.py edit [3]           # PixelLab repaints the shape: edit/edit_v<k>.png (20 gen. each)
    python creatures/<name>.py review             # how much of each variant's silhouette is the shape's
    python creatures/<name>.py pick <edit_vN.png> # the chosen one -> <name>_pixellab.png
    python creatures/<name>.py animate            # <name>_idle<N>_walking<N>.png and the GIFs, from the pick

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
from tibia_view import sd_ellipsoid, sd_cone, sd_box, smin  # noqa: E402

NAME = "beetle"       # the files: <NAME>_idle8_walking8.png (the sheet rule); the folder out/<NAME>/
FRAME = 64            # one tile; 96 for a bigger creature (it stands in the bottom-right tile and grows up-left)
K = 1.0               # every length: tune until `shape` prints the size asked (~40 px tall for a 64 frame, ~60 for a 96)
WALKS = "forward"     # "forward": it faces where it goes; "sideways": the crab (its right flank leads)


def P3(u, v, h):
    """Body coordinates: u forward, v its right, h up -- pixels of the frame before K."""
    return np.array((u, v, h), float) * K


# ------------------------------------------------------------------ the shape
# One distance per part, and PLAIN min between parts (the animation moves parts apart: no smin across them).
# A HUMANOID FACE (two eyes, a mouth) nods ~22 degrees DOWN about the top of the neck, the whole head with it, or it
# reads as looking up the diagonal: wrap every head part's distance in nodded() (and tilt a hat back ~40 on top of it).
# A part's material picks its ramp. Keep every part >= 2 px thick on screen, or it becomes a line of outline.

LEGS = {}           # leg -> (hip, foot): where it hinges on the body, where it touches the ground


def nodded(sdf, pivot, degrees=22.0):
    """A part of a head nodded DOWN by `degrees` about `pivot` (the top of the neck): the face looks down toward the
    viewer. Usage: P["eye_r"] = ("eye", nodded(lambda X: sd_ellipsoid(X, ...), NECK))."""
    R = ca.rotation((0, 1, 0), math.radians(degrees))    # about its right: the front goes DOWN (check_signs)
    return lambda X: sdf((X - pivot) @ R + pivot)


def parts():
    P = {}
    P["body"] = ("shell", lambda X: np.maximum(sd_ellipsoid(X, P3(-1, 0, 4.5), P3(9, 7, 4.5)), P3(0, 0, 2.5)[2] - X[:, 2]))
    P["head"] = ("skin", lambda X: sd_ellipsoid(X, P3(8.5, 0, 4.0), P3(3.2, 3.6, 2.6)))
    for side, sg in (("r", 1), ("l", -1)):
        P["eye_" + side] = ("eye", lambda X, sg=sg: sd_ellipsoid(X, P3(10.6, sg * 1.9, 5.2), P3(0.9, 0.9, 0.9)))
        for i, (u, fwd) in enumerate(((4.0, 0.8), (-1.0, 0.0), (-6.0, -0.8))):
            hip, foot = P3(u, sg * 5.5, 3.0), P3(u + fwd * 4, sg * 11.0, 0.4)
            LEGS["leg%d_%s" % (i, side)] = (hip, foot)
            P["leg%d_%s" % (i, side)] = ("leg", lambda X, a=hip, b=foot: sd_cone(X, a, b, 1.3 * K, 0.6 * K))
    return P


PARTS = parts()
RAMPS = {                                               # dark -> light, hue-shifted (cold shade, warm light)
    "shell": ck.ramp([(10, 16, 30), (20, 36, 64), (34, 62, 104), (56, 96, 146), (90, 136, 184), (140, 182, 220),
                      (200, 226, 246)], 11),
    "skin": ck.ramp([(18, 12, 10), (40, 28, 22), (70, 52, 40), (104, 82, 64), (140, 116, 92)], 7),
    "leg": ck.ramp([(14, 10, 10), (34, 26, 24), (62, 50, 44), (96, 82, 70), (132, 116, 100)], 7),
    "eye": ck.ramp([(4, 4, 8), (20, 20, 26), (50, 50, 60)], 3),
}
OUTLINE = {"shell": (6, 10, 22), "skin": (10, 6, 4), "leg": (8, 6, 6), "eye": (2, 2, 4)}
SHAPE = ck.Shape(NAME, PARTS, RAMPS, OUTLINE, frame=FRAME, top=30.0 * max(K, 1.0),
                 mottle=("shell",), gloss=("shell", "eye"), painter=("leg",), glint=("eye",))

# what PixelLab is told the creature is (the shape keeps the silhouette; this says the materials and the details)
WHAT = "giant beetle"
DESIGN = ("A giant beetle with a glossy dark-blue shell with a lighter sheen on its upper-left, small dark head with "
          "two shiny black eyes, six thin jointed black legs.")


# ------------------------------------------------------------------ the motion
# A pose = one rigid transform per part (creature_anim: X -> R (X - c) + c + t). Move whole bodies by WHOLE pixels
# (ca.lifted): they come out identical, only shifted. Turn limbs about their hinge (ca.turn) and TEST the sign.

def pose(bob=0, legs=None):
    """bob: the body up, whole pixels. legs: leg name -> degrees swung forward."""
    body = ca.lifted(bob)
    T = {}
    for name in PARTS:
        if name in LEGS:
            hip, _ = LEGS[name]
            sg = -1 if name.endswith("_r") else 1          # about the vertical, +angle turns forward -> right:
            T[name] = ca.turn((0, 0, 1), sg * (legs or {}).get(name, 0.0), hip, then=body)   # so a right leg is -
        else:
            T[name] = body
    return T


def walk_pose(k, n=8):
    s = 18 * math.sin(2 * math.pi * k / n)              # the alternating tripod: legs 0 and 2 of one side with 1 of
    a = {"leg0_r": s, "leg2_r": s, "leg1_l": s, "leg1_r": -s, "leg0_l": -s, "leg2_l": -s}   # the other
    return pose(bob=1 if k % (n // 2) == 1 else 0, legs=a)


IDLE = [pose() for _ in range(2)] + [pose(bob=1), pose(bob=1)] + [pose() for _ in range(4)]
IDLE_MS = [400, 120, 120, 120, 120, 120, 120, 200]
WALK = [walk_pose(k) for k in range(8)]
WALK_MS = [110] * 8
THIN = ()            # parts PixelLab may draw a little off the shape's (thin legs): no gaps, nearest painted colour

def check_signs():
    """Every rotation's sign, TESTED and not trusted (a wing with the sign swapped became an EAR; a leg that should go
    forward went back). Add one assert per new kind of move."""
    T = pose(legs={n: 20 for n in LEGS})
    for name, (hip, foot) in LEGS.items():
        R, c, t = T[name]
        assert (R @ (foot - c) + c + t)[0] > foot[0], name + ": +degrees must swing the foot FORWARD"
    face = P3(10, 0, 4)
    moved = nodded(lambda X: X[:, 2], P3(7, 0, 5))      # the height a point of the LEVEL head lands at, read back
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
