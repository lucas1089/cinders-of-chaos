"""Pieces of gear any class can wear: hair, cloth, belts, boots, plates, shields and weapons, on the bones of a Body.

Every function returns a list of rig.Part. Positions are in the body's plain units (rig.Rig scales the whole figure).
`s` is a side: "r" (the figure's right, the weapon hand) or "l".
"""
import numpy as np

from rig import Part, box, clip, cone, cut, cyl, ell, halfspace, union

DOWN = np.array((0, 0, -1.0))


def above(h):
    """Points with height >= h."""
    return halfspace((0, 0, -1), -h)


def below(h):
    return halfspace((0, 0, 1), h)


def v3(*a):
    return np.array(a, float)


# ------------------------------------------------------------------------------------------------ head
def hair_short(B, mat="hair"):
    h = B.H["head"]
    cap = ell((-0.1, 0, h + 0.55), (3.85, 3.75, 3.8))
    face = box((3.4, 0, h - 0.4), (2.9, 3.0, 3.1))
    tufts = [ell((-0.4 + 1.6 * i, (-1) ** i * 1.4, h + 3.6 - 0.25 * i), (1.3, 1.2, 0.9)) for i in range(3)]
    tufts.append(ell((1.9, 0.3, h + 2.9), (1.4, 2.8, 0.9)))
    return [Part("hair", "head", mat, union(cut(cap, face), *tufts))]


def hair_long(B, mat="hair", length=6.0):
    h = B.H["head"]
    cap = ell((0.0, 0, h + 0.5), (3.9, 3.8, 3.85))
    face = box((3.4, 0, h - 0.4), (2.9, 2.9, 3.1))
    fall = ell((-2.6, 0, h - 2.4), (1.7, 3.5, length * 0.7))
    locks = [ell((1.9, sg * 3.25, h - 1.5), (1.4, 0.95, 2.5)) for sg in (1, -1)]
    return [Part("hair", "head", mat, union(cut(cap, face), *locks)), Part("hair_fall", "head", mat, fall)]


def braid(B, mat="hair", length=8.0):
    h = B.H["head"]
    a, b, c = v3(-3.0, 0, h - 0.6), v3(-3.8, 0, h - length * 0.55), v3(-3.6, 0, h - length)
    return [Part("braid", "head", mat, union(cone(a, b, 1.05, 0.85), cone(b, c, 0.85, 0.6), ell(c, (0.8, 0.8, 0.9))))]


def mane(B, mat="hair"):
    """Wild hair pouring from under a helm down the back."""
    h = B.H["head"]
    return [Part("mane", "head", mat, union(ell((-2.3, 0, h - 0.8), (2.3, 3.9, 3.6)),
                                            ell((-3.0, 0, h - 4.4), (1.6, 3.2, 2.6)), k=0.8))]


# ------------------------------------------------------------------------------------------------ trunk
def skirt(B, mat, to=4.4, flare=1.0, front=0.0):
    hip = B.H["hip"]
    e = ell((0.1 + front, 0, hip - 0.9), (2.85 * flare, (3.85 if not B.f else 4.0) * flare, 3.6))
    return [Part("skirt", "pelvis", mat, clip(e, above(hip - to)))]


def belt(B, mat="leather", buckle="iron"):
    w = B.H["waist"] - 0.3
    ru, rv = (2.55, 3.45) if not B.f else (2.2, 3.15)
    P = [Part("belt", "pelvis", mat, ell((0, 0, w), (ru, rv, 0.8)))]
    if buckle:
        P.append(Part("buckle", "pelvis", buckle, ell((ru - 0.1, 0, w), (0.55, 0.85, 0.7))))
    return P


def pauldron(B, s, mat="iron", size=1.0, lame=False):
    sg = B.side(s)
    j = B.joint("arm_" + s)
    P = [Part("pauldron_" + s, "arm_" + s, mat, ell(j + (-0.05, sg * 0.45, 0.7), np.array((2.35, 2.1, 1.6)) * size))]
    if lame:
        P.append(Part("lame_" + s, "arm_" + s, mat, ell(j + (0, sg * 0.9 * size, -0.9 * size),
                                                      np.array((2.15, 1.8, 1.15)) * size)))
    return P


def bracer(B, s, mat="leather", r=1.4, start=0.35):
    el, wr = B.joint("fore_" + s), B.wrist(s)
    return [Part("bracer_" + s, "fore_" + s, mat, cone(el + (wr - el) * start, wr + (0, 0, 0.2), r, r * 0.95))]


def gauntlet(B, s, mat="iron"):
    return [Part("gauntlet_" + s, "fore_" + s, mat, ell(B.hand(s) + (0, 0, 0.2), (1.45, 1.25, 1.45)))]


def boots(B, mat="boot", top=4.3, r=1.62):
    P = []
    for s in "rl":
        sg = B.side(s)
        an = B.ankle(s)
        P.append(Part("cuff_" + s, "shin_" + s, mat, cone(an + (0, 0, -0.3), (0.2, sg * (B.hipw + 0.12), top), r, r * 1.04)))
    return P


def greaves(B, mat="iron", knee="iron"):
    P = []
    for s in "rl":
        sg = B.side(s)
        an, kn = B.ankle(s), B.joint("shin_" + s)
        P.append(Part("greave_" + s, "shin_" + s, mat, cone(an + (0.15, 0, 0.2), kn + (0.25, 0, -0.4), 1.6, 1.72)))
        P.append(Part("kneecop_" + s, "shin_" + s, knee, ell(kn + (0.9, 0, 0.1), (1.2, 1.45, 1.25))))
    return P


# ------------------------------------------------------------------------------------------------ weapons
def sword(B, s="r", blade="steel", guard="iron", grip="leather", length=6.6, width=0.95):
    """Held in the hand, the blade going on from the forearm (posed forward it points ahead and down)."""
    hd = B.hand(s)
    b = "fore_" + s
    tip = hd + DOWN * (2.0 + length)
    return [
        Part("grip_" + s, b, grip, cone(hd + (0, 0, 1.15), hd + (0, 0, -1.0), 0.48, 0.48)),
        Part("pommel_" + s, b, guard, ell(hd + (0, 0, 1.45), (0.6, 0.6, 0.55))),
        Part("guard_" + s, b, guard, box(hd + (0, 0, -1.35), (0.5, 1.75, 0.42), 0.15)),
        Part("blade_" + s, b, blade, union(box(hd + DOWN * (1.7 + length * 0.42), (width, 0.42, length * 0.42), 0.12),
                                           cone(hd + DOWN * (1.7 + length * 0.8), tip, width * 0.95, 0.25))),
    ]


def mace(B, s="r", head="iron", haft="wood", glow="ember"):
    hd = B.hand(s)
    b = "fore_" + s
    c = hd + DOWN * 6.4
    P = [Part("haft_" + s, b, haft, cone(hd + (0, 0, 1.2), c, 0.5, 0.5)),
         Part("mhead_" + s, b, head, ell(c + DOWN * 0.4, (1.5, 1.5, 1.85)))]
    for k, (du, dv) in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1))):
        P.append(Part("flange%d_%s" % (k, s), b, head, box(c + DOWN * 0.4 + (du * 1.3, dv * 1.3, 0),
                                                            (0.35 + 0.45 * abs(du), 0.35 + 0.45 * abs(dv), 1.6), 0.2)))
    if glow:
        P.append(Part("mglow_" + s, b, glow, ell(c + DOWN * 2.35, (0.7, 0.7, 0.45))))
    return P


def round_shield(B, s="l", face="wood", rim="iron", boss="iron", r=3.8):
    sg = B.side(s)
    el, wr = B.joint("fore_" + s), B.wrist(s)
    c = (el + wr) / 2 + (0.2, sg * 1.3, 0.2)
    ax = np.array((0, sg, 0.0))
    ring = cut(cyl(c - ax * 0.15, c + ax * 0.75, r + 0.25), cyl(c - ax * 0.4, c + ax * 1.2, r - 0.45))
    b = "fore_" + s
    return [Part("sface_" + s, b, face, cyl(c, c + ax * 0.6, r)),
            Part("srim_" + s, b, rim, ring),
            Part("sboss_" + s, b, boss, ell(c + ax * 0.75, (1.05, 0.65, 1.05)))]


def tower_shield(B, s="l", face="obsidian", rim="iron", crack="ember"):
    sg = B.side(s)
    el, wr = B.joint("fore_" + s), B.wrist(s)
    c = (el + wr) / 2 + (0.6, sg * 1.5, 0.6)
    b = "fore_" + s
    out = sg * 0.62
    P = [Part("tface_" + s, b, face, box(c + (0, sg * 0.12, 0), (2.9, 0.42, 4.7), 0.45)),
         Part("trim_" + s, b, rim, box(c + (0, -sg * 0.22, 0), (3.25, 0.4, 5.05), 0.5)),
         Part("tboss_" + s, b, rim, ell(c + (0.3, out, 0.8), (1.0, 0.45, 1.0)))]
    if crack:
        pts = [c + (1.9, out, 3.3), c + (0.9, out, 1.6), c + (1.3, out, 0.2), c + (-0.2, out, -1.6), c + (0.4, out, -3.4)]
        segs = [cone(a, b2, 0.36, 0.33) for a, b2 in zip(pts, pts[1:])]
        P.append(Part("tcrack_" + s, b, crack, union(*segs)))
    return P
