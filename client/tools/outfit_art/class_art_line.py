"""New class looks drawn with the outfit rig (rig.py, body.py), for the slots that have no usable donor art:
the Lich woman, the Inquisitor woman, a matched Necromancer pair, and alternatives for the Thief, the Ninja and the
Templar (both sexes each). Each look has two addons that carry the class identity; class_art.py renders them into the
import_art_things.py outfit layout.

A design returns Look(rig of the base outfit, stance, addon 1 parts, addon 2 parts). The addons are drawn as the full
figure with the addon's parts; the addon pattern holds only the pixels that change (the client draws an addon pattern
over pattern 0).

Template regions (the player's colours), the same in every look: head = hair / hood / headband, body = robe / tunic /
tabard / scarf, legs = trousers / the robe's skirt, feet = boots. Untinted: skin, metal, bone, leather, the glows.
Glows follow the classes' effects: soul green (Necromancer), void violet (Lich), holy gold (Templar, Inquisitor),
embers (the season's fire).
"""
import numpy as np

import gear as G
from body import Body, Stance, pose
from palette import base_mats
from rig import Mat, Part, Rig, box, clip, cone, cut, cyl, ell, grey, moved, ramp, rot, union

DOWN = np.array((0, 0, -1.0))


class Look:
    def __init__(self, rig, stance, addon1, addon2):
        self.rig, self.stance, self.addons = rig, stance, (list(addon1), list(addon2))

    def with_addons(self, which):
        """The rig with the base parts plus addon parts of `which` (a tuple of 1 and / or 2)."""
        parts = list(self.rig.parts)
        for a in which:
            parts += self.addons[a - 1]
        return Rig(self.rig.bones, parts, self.rig.mats, self.rig.scale)


def mats():
    M = base_mats()
    M.update({
        "gold": Mat(ramp([(34, 22, 10), (82, 56, 22), (140, 100, 40), (196, 156, 72), (236, 208, 128)], 6), (20, 12, 6),
                    kind="metal", spec=0.35),
        "soul": Mat(ramp([(22, 64, 34), (58, 150, 70), (130, 226, 112), (214, 255, 196)], 4), (10, 34, 16), kind="glow"),
        "void": Mat(ramp([(62, 22, 92), (124, 54, 186), (190, 122, 242), (240, 212, 255)], 4), (28, 8, 44), kind="glow"),
        "holy": Mat(ramp([(150, 104, 30), (222, 172, 60), (255, 226, 132), (255, 250, 222)], 4), (74, 46, 10), kind="glow"),
        "gaunt": Mat(ramp([(38, 38, 50), (78, 80, 96), (126, 128, 142), (172, 174, 182), (212, 212, 216)], 6), (16, 14, 22)),
        "wrap": Mat(ramp([(10, 9, 12), (24, 22, 28), (40, 37, 44), (62, 58, 66), (90, 84, 92)], 5), (5, 4, 6), grain=0.4),
        "crimson": Mat(ramp([(34, 6, 8), (78, 14, 16), (126, 26, 24), (170, 48, 36), (204, 86, 62)], 5), (18, 4, 4)),
        # tinted
        "hood": Mat(grey(6, 50, 236), (14, 13, 14), "head"),
        "robe": Mat(grey(6, 46, 238), (14, 13, 14), "body", grain=0.3),
        "skirt": Mat(grey(6, 42, 232), (14, 13, 14), "legs", grain=0.3),
        "sash": Mat(grey(5, 56, 240), (14, 13, 14), "body", grain=0.5),
    })
    return M


def _rig(B, parts):
    return Rig(B.bones, parts, mats(), Body.SCALE)


# ------------------------------------------------------------------------------------------------ shared pieces
def in_torso(B, st, s, point_fn):
    """Where a point of the hand (fore_<s> bone, rest coords) is, in the torso's rest frame, in the standing pose:
    weapons held upright are placed on the torso so they stay upright."""
    rg = Rig(B.bones, [], mats(), Body.SCALE)
    W = rg.world(pose(st))
    R, c, t = W["fore_" + s]
    p = R @ (point_fn - c) + c + t
    Rt, ct, tt = W["torso"]
    return (p - ct - tt) @ Rt + ct


def upright_sword(B, st, s, blade="steel", guard="gold", grip="leather", length=6.6, width=0.9, lean=(0.25, 0.1)):
    """A sword held up before the body, the blade pointing up (held low, a blade crosses the frame's bottom edge in
    the views where the weapon hand is toward the viewer)."""
    hand = in_torso(B, st, s, B.hand(s))
    d = np.array((lean[0], B.side(s) * lean[1], 1.0))
    d /= np.linalg.norm(d)
    q = np.cross(d, (1.0, 0, 0))
    q /= np.linalg.norm(q)
    P = [Part("grip_" + s, "torso", grip, cone(hand - d * 1.1, hand + d * 1.0, 0.48, 0.48)),
         Part("pommel_" + s, "torso", guard, ell(hand - d * 1.4, (0.6, 0.6, 0.6))),
         Part("guard_" + s, "torso", guard, cone(hand + d * 1.3 - q * 1.8, hand + d * 1.3 + q * 1.8, 0.45, 0.45)),
         Part("blade_" + s, "torso", blade, union(cone(hand + d * 1.5, hand + d * (1.5 + length * 0.8), width, width * 0.85),
                                                  cone(hand + d * (1.5 + length * 0.8), hand + d * (1.7 + length), width * 0.85, 0.2)))]
    return P


def upright_mace(B, st, s, head="gold", haft="wood", glow="holy", lean=(0.3, 0.15)):
    hand = in_torso(B, st, s, B.hand(s))
    d = np.array((lean[0], B.side(s) * lean[1], 1.0))
    d /= np.linalg.norm(d)
    c = hand + d * 5.6
    P = [Part("haft_" + s, "torso", haft, cone(hand - d * 1.2, c, 0.5, 0.5)),
         Part("mhead_" + s, "torso", head, ell(c, (1.5, 1.5, 1.7)))]
    for k, (du, dv) in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1))):
        P.append(Part("flange%d_%s" % (k, s), "torso", head, box(c + (du * 1.3, dv * 1.3, 0),
                                                                 (0.35 + 0.45 * abs(du), 0.35 + 0.45 * abs(dv), 1.5), 0.2)))
    if glow:
        P.append(Part("mglow_" + s, "torso", glow, ell(c + d * 1.9, (0.75, 0.75, 0.55))))
    return P


def robe(B, mat="skirt", hem=1.6, flare=1.18, front=0.0):
    """A long skirt from the hips to just above the feet (legs region)."""
    hip = B.H["hip"]
    to = hip - hem
    e = ell((0.1 + front, 0, hip - 1.4), (3.0 * flare, (3.9 if not B.f else 4.05) * flare, to + 0.6))
    return [Part("robe", "pelvis", mat, clip(e, G.above(hem)))]


def hem_trim(B, mat, hem=1.6, flare=1.18, band=0.9):
    hip = B.H["hip"]
    to = hip - hem
    e = ell((0.1, 0, hip - 1.4), (3.0 * flare + 0.25, (3.9 if not B.f else 4.05) * flare + 0.25, to + 0.85))
    return [Part("hem_trim", "pelvis", mat, clip(clip(e, G.above(hem - 0.1)), G.below(hem + band)))]


def hood(B, mat="hood", peak=1.6, drape=True, open_face=True):
    h = B.H["head"]
    shell = ell((-0.2, 0, h + 0.5), (4.2, 4.1, 4.3))
    if open_face:
        shell = cut(shell, box((4.0, 0, h - 0.6), (1.6, 2.5, 2.7), 0.6))
    parts = [shell]
    if peak:
        parts.append(cone((-1.0, 0, h + 3.0), (-3.4 - peak, 0, h + 3.4 + peak), 2.2, 0.35))
    P = [Part("hood", "head", mat, union(*parts, k=0.6))]
    if drape:
        P.append(Part("hood_drape", "torso", mat, clip(ell((-0.6, 0, B.H["shoulder"] + 0.4), (3.4, B.sw + 0.9, 2.6)),
                                                       G.above(B.H["shoulder"] - 1.4))))
    return P


def skull(c, mat="bone", eyes="soul", r=1.25, bone_name="torso", name="skull", face=(1, 0, 0)):
    c = np.asarray(c, float)
    f = np.asarray(face, float)
    side = np.cross((0, 0, 1.0), f)
    P = [Part(name, bone_name, mat, union(ell(c, (r, r * 0.95, r * 1.05)),
                                          ell(c + f * r * 0.45 - (0, 0, r * 0.75), (r * 0.6, r * 0.55, r * 0.45))))]
    for k, sg in enumerate((1, -1)):
        P.append(Part("%s_eye%d" % (name, k), bone_name, eyes, ell(c + f * r * 0.8 + side * sg * r * 0.42, (0.36, 0.36, 0.4))))
    return P


def staff(B, st, s, mat="bone", up=13.0, down=10.0, tilt=(0.12, 0.05), name="staff"):
    """An upright staff in the hand (on the torso, see in_torso): returns (parts, top point)."""
    hand = in_torso(B, st, s, B.hand(s))
    d = np.array((tilt[0], B.side(s) * tilt[1], 1.0))
    d /= np.linalg.norm(d)
    if down is None:                       # held mid-shaft, the foot well above the ground (low, it crosses the
        down = (hand[2] - 7.0) / d[2]      # frame's bottom edge in the views where the hand is toward the viewer)
    lo, hi = hand - d * down, hand + d * up
    return [Part(name, "torso", mat, cone(lo, hi, 0.55, 0.5))], hi, d


def dagger(B, s, blade="steel", grip="leather", guard="iron", length=3.4, name="dagger"):
    P = G.sword(B, s, blade=blade, guard=guard, grip=grip, length=length, width=0.75)
    for p in P:
        p.name = name + "_" + p.name
    return P


def mantle(B, mat, drop=1.7, wide=1.5, name="mantle"):
    H = B.H
    return [Part(name, "torso", mat, clip(ell((-0.4, 0, H["shoulder"] + 0.2), (3.3, B.sw + wide, 2.5)),
                                         G.above(H["shoulder"] - drop)))]


def tabard(B, mat="robe", length=7.4, width=2.2):
    H = B.H
    top = H["waist"] + 0.6
    return [Part("tabard_f", "pelvis", mat, box((2.75 if not B.f else 2.4, 0, top - length / 2), (0.36, width, length / 2), 0.25)),
            Part("tabard_b", "pelvis", mat, box((-2.5, 0, top - length / 2), (0.34, width + 0.1, length / 2), 0.25))]


def cross(c, mat, size=1.4, axis="u", name="cross", bone="torso"):
    """A small cross standing out along +u (on a chest or a shield face)."""
    c = np.asarray(c, float)
    if axis == "u":
        return [Part(name, bone, mat, union(box(c, (0.25, 0.32, size), 0.08), box(c + (0, 0, size * 0.35), (0.25, size * 0.7, 0.3), 0.08)))]
    return [Part(name, bone, mat, union(box(c, (0.32, 0.25, size), 0.08), box(c + (0, 0, size * 0.35), (size * 0.7, 0.25, 0.3), 0.08)))]


def kite_shield(B, s="l", face="steel", rim="gold", emblem="holy"):
    sg = B.side(s)
    el, wr = B.joint("fore_" + s), B.wrist(s)
    c = (el + wr) / 2 + (0.5, sg * 1.45, 0.9)
    b = "fore_" + s
    out = sg * 0.66
    body_ = union(box(c + (0, sg * 0.1, 1.0), (2.6, 0.4, 2.6), 0.5), cone(c + (0, sg * 0.1, -0.8), c + (0, sg * 0.1, -4.6), 2.5, 0.3))
    rim_ = union(box(c + (0, -sg * 0.2, 1.0), (2.95, 0.36, 2.95), 0.55), cone(c + (0, -sg * 0.2, -0.8), c + (0, -sg * 0.2, -5.0), 2.85, 0.35))
    P = [Part("kface_" + s, b, face, body_), Part("krim_" + s, b, rim, rim_)]
    e = c + (0.0, out, 0.6)
    P.append(Part("kemblem_" + s, b, emblem, union(box(e, (0.38, 0.3, 2.3), 0.1), box(e + (0, 0, 0.8), (1.7, 0.3, 0.38), 0.1))))
    return P


# ------------------------------------------------------------------------------------------------ Lich (female)
def lich(sex):
    """The curse caster: gaunt and grey-skinned, violet eyes, a tattered robe, a void flame in the open left hand.
    Addon 1: a bone crown with violet gems. Addon 2: a phylactery at the hip and gold trim on the robe and collar."""
    B = Body(sex, height=0.6)
    H = B.H
    h = H["head"]
    P = B.parts(skin="gaunt", shirt="robe", pants="skirt", shoe="boot", sleeve="robe")
    P += B.eyes("void")
    P += G.hair_long(B, length=8.5) if B.f else G.hair_long(B, length=6.0)
    P += robe(B, hem=1.4, flare=1.22)
    P.append(Part("collar", "torso", "wrap", clip(ell((-1.2, 0, H["neck"] + 0.2), (2.6, 3.6, 2.6)), G.above(H["neck"] - 0.8))))
    P += G.belt(B, "wrap", "bone")
    for s in "rl":
        sg = B.side(s)
        P.append(Part("sleeve_" + s, "fore_" + s, "robe", cone(B.joint("fore_" + s), B.wrist(s) + (0, 0, 0.6), 1.35, 1.9)))
    # the void flame over the left palm
    hl = B.hand("l")
    P.append(Part("vflame", "fore_l", "void", union(ell(hl + (0.6, -0.4, -1.6), (1.0, 1.0, 1.1)),
                                                     cone(hl + (0.6, -0.4, -1.2), hl + (0.4, -0.5, -3.8), 0.8, 0.15))))
    st = Stance(arm_r=(4, 10), fore_r=(24, 0), arm_l=(10, 14), fore_l=(80, -10), swing_r=0.5, swing_l=0.2, nod=-12)
    rg = _rig(B, P)
    # addon 1: the bone crown (a ring of spikes) with violet gems
    top = h + 2.9
    ring = cut(cyl((0.4, 0, top - 0.6), (0.4, 0, top + 0.6), 3.3, 0.2), cyl((0.4, 0, top - 1.0), (0.4, 0, top + 1.0), 2.6, 0.1))
    spikes = []
    for k in range(7):
        a = np.radians(-90 + 30 * k)
        base_ = np.array((0.4 + 3.0 * np.cos(a), 3.0 * np.sin(a), top + 0.4))
        tall = 3.6 if k == 3 else (2.8 if k in (2, 4) else 2.2)
        spikes.append(cone(base_, base_ + (0.35 * np.cos(a), 0.35 * np.sin(a), tall), 0.65, 0.12))
    A1 = [Part("crown", "head", "iron", union(ring, *spikes)),
          Part("crown_gem", "head", "void", ell((3.65, 0, top + 0.2), (0.5, 0.65, 0.6)))]
    for sg in (1, -1):
        A1.append(Part("crown_gem%+d" % sg, "head", "void", ell((2.5, sg * 2.45, top + 0.2), (0.45, 0.45, 0.5))))
    # addon 2: the phylactery on a chain at the right hip, gold trim on the hem and the collar
    w = H["waist"] - 0.6
    vial = np.array((3.2, 1.7, w - 2.0))
    A2 = [Part("phyl_chain", "pelvis", "gold", cone((2.4, 1.6, w), vial + (0, 0, 1.6), 0.25, 0.25)),
          Part("phyl_cap", "pelvis", "gold", ell(vial + (0, 0, 1.3), (0.9, 0.9, 0.55))),
          Part("phyl", "pelvis", "void", ell(vial, (1.05, 1.0, 1.45)))]
    A2 += hem_trim(B, "gold", hem=1.4, flare=1.22, band=0.8)
    A2.append(Part("collar_trim", "torso", "gold", clip(clip(ell((-1.2, 0, H["neck"] + 0.2), (2.85, 3.85, 2.85)),
                                                             G.above(H["neck"] + 1.3)), G.below(H["neck"] + 2.2))))
    return Look(rg, st, A1, A2)


# ------------------------------------------------------------------------------------------------ Inquisitor
def inquisitor(sex):
    """Holy fire: a long coat over plate, a flanged mace with a burning head (the brand).
    Addon 1: a censer swinging on a chain from the left hand, holy smoke. Addon 2: a pointed hood with a gold seal."""
    B = Body(sex, bulk=1.05, height=0.4)
    H = B.H
    P = B.parts(skin="skin", shirt="robe", pants="pants", shoe="boot", sleeve="robe")
    P += B.eyes()
    P += G.hair_long(B, length=9.0) + G.braid(B, length=10.0) if B.f else G.hair_short(B)
    P += robe(B, mat="robe", hem=2.4, flare=1.1, front=-0.2)          # the coat's long skirts (body region)
    P += G.skirt(B, "pants", to=3.0)
    P.append(Part("gorget", "torso", "iron", ell((0.2, 0, H["neck"] - 0.7), (2.4, 3.0, 1.1))))
    P += G.pauldron(B, "r", "iron", size=1.05) + G.pauldron(B, "l", "iron", size=1.05)
    P += G.belt(B, "leather", "gold")
    P += cross((2.95 if not B.f else 2.75, 0, H["chest"] + 0.2), "gold", size=1.3)
    P += G.bracer(B, "r", "iron") + G.bracer(B, "l", "iron")
    P += G.boots(B, "boot", top=3.8)
    st = Stance(arm_r=(10, 10), fore_r=(64, 0), arm_l=(4, 12), fore_l=(48, -6), swing_r=0.0, swing_l=0.2, nod=-10)
    P += upright_mace(B, st, "r")
    rg = _rig(B, P)
    # addon 1: the censer, hanging straight down from the left hand
    hand = in_torso(B, st, "l", B.hand("l"))
    c = hand + (0.5, -0.2, -4.6)
    A1 = [Part("cens_chain", "torso", "iron", cone(hand + (0, 0, -0.6), c + (0, 0, 1.2), 0.2, 0.2)),
          Part("cens_body", "torso", "gold", clip(ell(c, (1.4, 1.4, 1.2)), G.below(c[2] + 0.5))),
          Part("cens_lid", "torso", "gold", cone(c + (0, 0, 0.5), c + (0, 0, 1.8), 1.15, 0.3)),
          Part("cens_fire", "torso", "holy", ell(c + (0.55, 0, 0.55), (0.9, 1.0, 0.45))),
          Part("cens_smoke", "torso", "ash", union(ell(c + (-0.6, 0.4, 2.6), (0.75, 0.75, 0.8)),
                                                   ell(c + (-1.3, 0.9, 3.8), (0.6, 0.6, 0.65))))]
    # addon 2: the inquisitor's pointed hood (tinted, head region), a gold seal on the brow
    h = H["head"]
    A2 = hood(B, mat="hood", peak=2.4, drape=True)
    A2.append(Part("hood_seal", "head", "gold", ell((3.85, 0, h + 2.3), (0.45, 0.8, 0.75))))
    return Look(rg, st, A1, A2)


# ------------------------------------------------------------------------------------------------ Necromancer
def necromancer(sex):
    """The summoner: a long robe with a ragged hem, bone fetishes at the belt, soul-green eyes and a green wisp in the
    left hand. Addon 1: a bone staff topped with a skull with green eyes. Addon 2: a dark mantle with a skull on each
    shoulder and a high collar."""
    B = Body(sex, height=0.3)
    H = B.H
    P = B.parts(skin="ashskin", shirt="robe", pants="skirt", shoe="boot", sleeve="robe")
    P += B.eyes("soul")
    P += hood(B, mat="hood", peak=0.8, drape=True)
    if B.f:   # long locks fall from the hood over the chest (untinted: they read as hair under any hood colour)
        h = H["head"]
        for s in "rl":
            sg = B.side(s)
            P.append(Part("lock_" + s, "head", "ash", union(ell((2.5, sg * 3.0, h - 2.0), (1.0, 0.9, 2.2)),
                                                            ell((2.2, sg * 3.3, h - 4.4), (0.9, 0.85, 1.8)), k=0.5)))
    P += robe(B, hem=1.5, flare=1.16)
    # the ragged hem: dark notches cut in a band at the bottom
    P.append(Part("rags", "pelvis", "wrap", clip(clip(ell((0.1, 0, B.H["hip"] - 1.4), (3.65, (3.9 if not B.f else 4.05) * 1.16 + 0.2, 10.6)),
                                                     G.above(1.4)), G.below(2.4))))
    P += G.belt(B, "leather", "bone")
    w = H["waist"] - 0.3
    for k, (u, v) in enumerate(((1.5, -2.6), (0.4, -3.3))):
        P.append(Part("fetish%d" % k, "pelvis", "bone", cone((u, v, w - 0.5), (u + 0.1, v - 0.2, w - 2.8), 0.4, 0.25)))
    hl = B.hand("l")
    P.append(Part("wisp", "fore_l", "soul", union(ell(hl + (0.6, -0.4, -1.5), (0.95, 0.95, 1.0)),
                                                   cone(hl + (0.6, -0.4, -1.2), hl + (0.3, -0.6, -3.4), 0.7, 0.12))))
    st = Stance(arm_r=(4, 10), fore_r=(30, 0), arm_l=(10, 14), fore_l=(78, -10), swing_r=0.4, swing_l=0.2, nod=-12)
    rg = _rig(B, P)
    # addon 1: the bone staff with a skull head
    sp, top, d = staff(B, st, "r", mat="bone", up=17.5, down=None, tilt=(0.0, 0.04))
    A1 = sp + [Part("staff_knot", "torso", "bone", ell(top - d * 4.0, (0.75, 0.75, 0.6)))]
    A1 += skull(top + d * 1.0, mat="bone", eyes="soul", r=1.6, name="staff_skull")
    # addon 2: the skull mantle
    A2 = mantle(B, "wrap", drop=1.9, wide=1.7, name="smantle")
    A2.append(Part("scollar", "torso", "wrap", clip(ell((-1.4, 0, H["neck"] + 0.4), (2.4, 3.7, 3.0)), G.above(H["neck"] - 0.6))))
    for s in "rl":
        sg = B.side(s)
        A2 += skull((0.1, sg * (B.sw + 0.6), H["shoulder"] + 1.8), mat="bone", eyes="soul", r=1.3, name="mskull_" + s)
    return Look(rg, st, A1, A2)


# ------------------------------------------------------------------------------------------------ Thief
def thief(sex):
    """Fast and light: a leather jerkin over a tinted tunic, a short cape, a dagger in the right hand.
    Addon 1: a deep hood with a face scarf. Addon 2: a second dagger in the left hand and a bandolier of knives."""
    B = Body(sex, bulk=0.95)
    H = B.H
    P = B.parts(skin="skin", shirt="robe", pants="pants", shoe="boot", sleeve="robe")
    P += B.eyes()
    P += G.hair_short(B) if not B.f else G.hair_long(B, length=7.0) + G.braid(B, length=9.0)
    P.append(Part("jerkin", "torso", "leather", clip(ell((0.15, 0, H["chest"] - 0.6), (2.85, B.sw * 0.9, 3.3)), G.above(H["waist"] - 0.2))))
    P += G.skirt(B, "robe", to=3.4, flare=0.98)
    P += G.belt(B, "leather", "iron")
    P.append(Part("cape", "torso", "wrap", moved(box((-3.0, 0, H["waist"] + 1.2), (0.36, B.sw * 0.78, 5.0), 0.3),
                                                rot((0, 1, 0), -12), about=(-2.6, 0, H["shoulder"]))))
    P += G.bracer(B, "r") + G.bracer(B, "l")
    P += G.boots(B, "boot", top=4.6, r=1.55)
    P += dagger(B, "r", name="dag_r")
    st = Stance(arm_r=(14, 12), fore_r=(70, 0), arm_l=(10, 14), fore_l=(60, -6), swing_r=0.5, swing_l=0.5, nod=-8)
    rg = _rig(B, P)
    h = H["head"]
    A1 = hood(B, mat="hood", peak=0.6, drape=True)
    A1.append(Part("facescarf", "head", "wrap", clip(ell((1.3, 0, h - 1.1), (3.0, 3.35, 1.7)), G.below(h - 0.1))))
    A2 = dagger(B, "l", name="dag_l", length=2.6)
    A2.append(Part("bandolier", "torso", "leather", cone((2.75, -B.sw * 0.55, H["shoulder"] - 0.4),
                                                         (2.65, B.sw * 0.6, H["waist"] + 0.9), 0.45, 0.45)))
    for k in range(3):
        t = 0.25 + 0.22 * k
        p = np.array((2.75, -B.sw * 0.55, H["shoulder"] - 0.4)) * (1 - t) + np.array((2.65, B.sw * 0.6, H["waist"] + 0.9)) * t
        A2.append(Part("knife%d" % k, "torso", "steel", cone(p + (0.5, 0, 0.9), p + (0.5, 0, -0.6), 0.32, 0.15)))
    return Look(rg, st, A1, A2)


# ------------------------------------------------------------------------------------------------ Ninja
def ninja(sex):
    """The shadow: close black wraps over a tinted gi, a tinted sash, reversed blades in both hands.
    Addon 1: a face mask and a headband whose tails fly back. Addon 2: a long scarf trailing from the neck."""
    B = Body(sex, bulk=0.92)
    H = B.H
    h = H["head"]
    P = B.parts(skin="skin", shirt="robe", pants="pants", shoe="wrap", sleeve="wrap")
    P += B.eyes()
    # a close cowl (the player's head colour); hers lets a long braid out at the back
    P += hood(B, mat="hood", peak=0.0, drape=False)
    if B.f:
        P += G.braid(B, mat="wrap", length=12.0)
    P.append(Part("gi_wrap", "torso", "wrap", clip(ell((0.3, 0, H["chest"] + 0.3), (2.7, B.sw * 0.82, 2.6)), G.above(H["chest"] - 0.6))))
    P.append(Part("sash", "pelvis", "sash", ell((0, 0, H["waist"] - 0.4), (2.7 if not B.f else 2.35, 3.6 if not B.f else 3.3, 1.1))))
    P.append(Part("sash_tail", "pelvis", "sash", cone((-2.2, -1.4, H["waist"] - 0.8), (-2.9, -2.0, H["waist"] - 4.6), 0.6, 0.4)))
    for s in "rl":
        sg = B.side(s)
        sh, kn = B.joint("shin_" + s), B.ankle(s)
        P.append(Part("legwrap_" + s, "shin_" + s, "wrap", cone(kn + (0, 0, 0.6), sh + (0.1, 0, -1.0), 1.4, 1.45)))
    for s in "rl":
        hd = B.hand(s)
        b = "fore_" + s
        P.append(Part("armwrap_" + s, b, "wrap", cone(B.joint(b) + (0, 0, -0.6), B.wrist(s) + (0, 0, 0.3), 1.25, 1.15)))
        P.append(Part("kgrip_" + s, b, "wrap", cone(hd + (0, 0, -0.9), hd + (0, 0, 0.9), 0.42, 0.42)))
        sg = B.side(s)
        P.append(Part("kblade_" + s, b, "steel", cone(hd + (0.1, sg * 0.4, 0.9), hd + (0.6, sg * 2.6, 4.6), 0.62, 0.12)))
    st = Stance(arm_r=(18, 14), fore_r=(84, 0), arm_l=(16, 16), fore_l=(80, -4), swing_r=0.6, swing_l=0.6, nod=-8,
                torso_twist=0.0)
    rg = _rig(B, P)
    A1 = [Part("nmask", "head", "wrap", clip(ell((1.0, 0, h - 0.6), (3.15, 3.6, 2.4)), G.below(h + 0.25))),
          Part("headband", "head", "crimson", clip(clip(ell((0.2, 0, h + 0.6), (4.4, 4.3, 4.4)), G.above(h + 1.0)), G.below(h + 2.1))),
          Part("hb_tail1", "head", "crimson", cone((-3.8, 0.4, h + 1.6), (-7.0, 1.4, h + 0.4), 0.6, 0.3)),
          Part("hb_tail2", "head", "crimson", cone((-3.8, -0.4, h + 1.6), (-6.4, -1.6, h - 0.6), 0.6, 0.3))]
    A2 = [Part("scarf", "torso", "crimson", ell((0.3, 0, H["neck"] - 0.4), (2.9, 3.4, 1.4)))]
    pts = [np.array((-2.2, 1.0, H["neck"] - 0.6)), np.array((-4.8, 1.8, H["neck"] - 1.4)), np.array((-7.0, 2.6, H["neck"] - 3.2))]
    A2.append(Part("scarf_tail", "torso", "crimson", union(cone(pts[0], pts[1], 1.1, 0.9), cone(pts[1], pts[2], 0.9, 0.6))))
    return Look(rg, st, A1, A2)


# ------------------------------------------------------------------------------------------------ Templar
def templar(sex):
    """Holy plate: bright steel and gold, a tinted tabard with a gold cross, an arming sword.
    Addon 1: a great helm with a cross-shaped visor and a gold crest. Addon 2: a kite shield with a burning holy cross."""
    B = Body(sex, bulk=1.1, height=0.5)
    H = B.H
    h = H["head"]
    P = B.parts(skin="skin", shirt="steel", pants="pants", shoe="bootmetal", sleeve="steel")
    P += B.eyes()
    P += G.hair_short(B) if not B.f else G.hair_long(B, length=8.0) + G.braid(B, length=9.0)
    cu = clip(ell((0.25, 0, H["chest"] + 0.2), (3.0, B.sw * 0.95, 4.2)), G.above(H["waist"] - 0.6))
    P.append(Part("cuirass", "torso", "steel", cu))
    P += tabard(B, "robe", length=8.2, width=2.15)
    P.append(Part("tabard_top", "torso", "robe", box((2.85 if not B.f else 2.55, 0, H["chest"]), (0.4, 2.15, 2.6), 0.3)))
    P += cross((3.3 if not B.f else 3.0, 0, H["chest"] + 0.3), "gold", size=1.5)
    P += G.belt(B, "leather", "gold")
    for s in "rl":
        P += G.pauldron(B, s, "steel", size=1.15, lame=True)
        P += G.bracer(B, s, "steel", r=1.5, start=0.1) + G.gauntlet(B, s, "steel")
    P += G.greaves(B, "steel", "gold")
    st = Stance(arm_r=(10, 10), fore_r=(66, 0), arm_l=(6, 14), fore_l=(36, -6), swing_r=0.0, swing_l=0.3, nod=-10)
    P += upright_sword(B, st, "r")
    rg = _rig(B, P)
    helm = box((0.45, 0, h + 0.3), (3.5, 3.35, 3.8), 1.8)
    A1 = [Part("thelm", "head", "steel", helm),
          Part("tvisor", "head", "wrap", union(box((3.8, 0, h + 0.6), (0.5, 2.3, 0.4), 0.1), box((3.8, 0, h - 0.3), (0.5, 0.42, 1.6), 0.1))),
          Part("tcrest", "head", "gold", union(box((0.2, 0, h + 4.2), (3.4, 0.45, 0.8), 0.3), ell((3.2, 0, h + 3.6), (0.7, 0.6, 1.0)))),
          Part("thelm_rim", "head", "gold", clip(clip(ell((0.45, 0, h + 0.3), (3.75, 3.6, 4.05)), G.above(h - 3.2)), G.below(h - 2.4)))]
    A2 = kite_shield(B, "l", face="steel", rim="gold", emblem="holy")
    return Look(rg, st, A1, A2)


# ------------------------------------------------------------------------------------------------ Archmage
def archmage(sex):
    """The Mystic line's class outfit (pair 29, replaces the donor look 1559): an old battle mage in a long tinted robe,
    a white beard (his) or long white hair (hers), an ember orb on a tall wooden staff with a gold claw.
    Addon 1: a tall pointed hat with a gold band. Addon 2: a dark mantle, gold hem trim and a floating ember sigil over
    the open left hand."""
    B = Body(sex, height=0.4)
    H = B.H
    h = H["head"]
    P = B.parts(skin="skin", shirt="robe", pants="skirt", shoe="boot", sleeve="robe")
    P += B.eyes()
    if B.f:
        P += G.hair_long(B, mat="ash", length=9.0)
    else:
        P += G.hair_short(B, mat="ash")
        P.append(Part("beard", "head", "ash", union(ell((2.9, 0, h - 2.2), (1.5, 2.3, 1.6)),
                                                     ell((3.1, 0, h - 4.2), (1.3, 1.8, 2.0)),
                                                     cone((3.2, 0, h - 5.0), (3.4, 0, h - 8.6), 1.3, 0.3), k=0.6)))
    P += robe(B, hem=1.3, flare=1.2)
    P += G.belt(B, "leather", "gold")
    for s in "rl":
        P.append(Part("sleeve_" + s, "fore_" + s, "robe", cone(B.joint("fore_" + s), B.wrist(s) + (0, 0, 0.6), 1.35, 2.0)))
    st = Stance(arm_r=(6, 10), fore_r=(60, 0), arm_l=(8, 12), fore_l=(40, -6), swing_r=0.0, swing_l=0.3, nod=-10)
    sp, top, d = staff(B, st, "r", mat="wood", up=14.0, down=None, tilt=(0.0, 0.04))
    P += sp
    P.append(Part("staff_claw", "torso", "gold", cone(top - d * 0.4, top + d * 0.9, 0.9, 1.2)))
    P.append(Part("staff_orb", "torso", "ember", ell(top + d * 1.6, (1.15, 1.15, 1.15))))
    rg = _rig(B, P)
    # addon 1: the pointed hat, bent back at the tip, gold band
    A1 = [Part("hat_brim", "head", "hood", clip(ell((0.2, 0, h + 2.4), (4.9, 4.9, 0.7)), G.above(h + 2.0))),
          Part("hat_cone", "head", "hood", union(cone((-0.1, 0, h + 2.4), (-0.9, 0, h + 7.0), 3.2, 1.2),
                                                cone((-0.9, 0, h + 7.0), (-3.0, 0, h + 9.0), 1.25, 0.25), k=0.5)),
          Part("hat_band", "head", "gold", clip(clip(cyl((-0.1, 0, h + 2.4), (-0.25, 0, h + 3.6), 3.25, 0.1),
                                                     G.above(h + 2.6)), G.below(h + 3.4)))]
    # addon 2: the mantle with gold trim and a floating ember sigil over the open left hand
    A2 = mantle(B, "wrap", drop=1.9, wide=1.6, name="amantle")
    A2 += hem_trim(B, "gold", hem=1.3, flare=1.2, band=0.8)
    hl = B.hand("l")
    A2.append(Part("sigil", "fore_l", "ember", union(ell(hl + (0.6, -0.4, -1.4), (0.9, 0.9, 0.9)),
                                                      cone(hl + (0.6, -0.4, -1.0), hl + (0.4, -0.5, -3.2), 0.7, 0.12))))
    return Look(rg, st, A1, A2)


# the looks of this line: key -> (design, sexes, name)
LOOKS = {
    "lich": (lich, ("female",), "Lich"),
    "inquisitor": (inquisitor, ("female",), "Inquisitor"),
    "necromancer": (necromancer, ("male", "female"), "Necromancer"),
    "thief": (thief, ("male", "female"), "Thief"),
    "ninja": (ninja, ("male", "female"), "Ninja"),
    "templar": (templar, ("male", "female"), "Templar"),
    "archmage": (archmage, ("male", "female"), "Archmage"),
}
# default colours per look (the outfits csv; the players choose their own): head, body, legs, feet
COLOURS = {"lich": (0, 128, 127, 114), "inquisitor": (132, 132, 114, 114), "necromancer": (95, 121, 114, 114),
           "thief": (114, 116, 95, 114), "ninja": (114, 95, 114, 114), "templar": (40, 0, 95, 95),
           "archmage": (0, 94, 94, 114)}
