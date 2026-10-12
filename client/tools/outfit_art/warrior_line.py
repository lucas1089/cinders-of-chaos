"""The Warrior line: Warrior (base), Juggernaut (the wall: plate and a tower shield), Berserker (the fury: bare skin,
a horned skull, fur and a great axe). Both ascensions are bigger and carry more metal and embers than the Warrior;
their silhouettes part at a glance: the Juggernaut is a block with a tall shield, the Berserker has horns and an axe
head over the shoulder.

Template regions (the player's colours): head = hair / crest, body = tunic / tabard / fur, legs = trousers / kilt,
feet = boots / sabatons.
"""
import numpy as np

import gear as G
from body import Body, Stance, pose, swing
from palette import base_mats
from rig import Part, Rig, box, clip, cone, cut, ell, moved, rot, union


def _rig(B, parts, mats=None):
    return Rig(B.bones, parts, mats or base_mats(), Body.SCALE)


# ------------------------------------------------------------------------------------------------ Warrior
def warrior(sex):
    B = Body(sex)
    P = B.parts(skin="skin", shirt="cloth", pants="pants", shoe="boot", sleeve="cloth")
    P += B.eyes()
    P += G.hair_short(B) if not B.f else G.hair_long(B, length=8.5) + G.braid(B, length=9.0)
    P += G.skirt(B, "cloth", to=4.6)
    P += G.belt(B)
    P += G.pauldron(B, "l", "iron")
    P += G.bracer(B, "r") + G.bracer(B, "l")
    P += G.boots(B)
    P += G.sword(B, "r")
    P += G.round_shield(B, "l")
    st = Stance(arm_r=(8, 9), fore_r=(72, 0), arm_l=(6, 12), fore_l=(52, -8), swing_r=0.4, swing_l=0.35)
    return _rig(B, P), st


# ------------------------------------------------------------------------------------------------ Juggernaut
def juggernaut(sex):
    B = Body(sex, bulk=1.18, height=0.8)
    H = B.H
    P = B.parts(skin="skin", shirt="iron", pants="pants", shoe="bootmetal", sleeve="iron", head=False)
    h = H["head"]
    # the great helm: a charred bucket with a burning slit, the crest in the player's colour
    helm = box((0.45, 0, h + 0.1), (3.45, 3.3, 3.7), 1.7)
    if not B.f:
        P.append(Part("helm", "head", "iron", helm))
        P.append(Part("slit", "head", "ember", box((3.7, 0, h - 0.1), (0.55, 2.2, 0.45), 0.1)))
    else:
        # hers is open-faced: the face under a burning brow band, the long braid behind
        P.append(Part("skull", "head", "skin", ell((0.5, 0, h), (3.3, 3.15, 3.4))))
        P += B.eyes(forward=-0.3)
        P.append(Part("helm", "head", "iron", cut(helm, box((3.6, 0, h - 1.2), (2.0, 2.5, 2.2), 0.6))))
        P.append(Part("brand", "head", "ember", box((3.75, 0, h + 1.35), (0.5, 2.3, 0.32), 0.1)))
    P.append(Part("crest", "head", "plume", union(ell((-0.3, 0, h + 3.8), (3.7, 1.0, 1.55)),
                                                  cone((-3.1, 0, h + 3.4), (-4.2, 0, h - 1.2), 1.05, 0.65))))
    sw = B.sw
    cape = box((-3.15, 0, H["waist"] - 1.6), (0.42, sw * 0.82, 6.6), 0.35)
    P.append(Part("cape", "torso", "cloth", moved(cape, rot((0, 1, 0), -9), about=(-2.6, 0, H["shoulder"]))))
    if B.f:
        P += G.braid(B, length=11.0)
    P.append(Part("gorget", "torso", "iron", ell((0.2, 0, H["neck"] - 0.9), (2.6, 3.1, 1.2))))
    cu = clip(ell((0.25, 0, H["chest"] + 0.2), (3.25, B.sw * 0.98, 4.4)), G.above(H["waist"] - 0.6))
    P.append(Part("cuirass", "torso", "iron", cu))
    c = H["chest"]
    P.append(Part("seam", "torso", "ember", union(cone((3.05, 0.9, c + 2.2), (3.42, -0.2, c + 0.2), 0.34, 0.34),
                                                  cone((3.42, -0.2, c + 0.2), (3.0, 0.7, c - 2.3), 0.34, 0.3))))
    P.append(Part("tabard_f", "pelvis", "cloth", box((2.85, 0, H["hip"] - 1.9), (0.4, 2.2, 3.6), 0.25)))
    P.append(Part("tabard_b", "pelvis", "cloth", box((-2.55, 0, H["hip"] - 2.0), (0.36, 2.3, 3.6), 0.25)))
    P.append(Part("fauld", "pelvis", "iron", clip(ell((0.1, 0, H["hip"] + 0.6), (3.0, 4.15, 2.1)), G.above(H["hip"] - 1.0))))
    P += G.belt(B, "leather", "iron")
    for s in "rl":
        P += G.pauldron(B, s, "iron", size=1.3, lame=True)
        P += G.bracer(B, s, "iron", r=1.55, start=0.1) + G.gauntlet(B, s)
    P += G.greaves(B)
    P += G.mace(B, "r")
    P += G.tower_shield(B, "l")
    st = Stance(arm_r=(6, 12), fore_r=(66, 0), arm_l=(8, 16), fore_l=(18, 0), swing_r=0.3, swing_l=0.15)
    return _rig(B, P), st


# ------------------------------------------------------------------------------------------------ Berserker
def berserker(sex):
    B = Body(sex, bulk=1.1, height=0.6)
    H = B.H
    h = H["head"]
    P = B.parts(skin="ashskin", shirt="ashskin", pants="kilt", shoe="boot", sleeve="ashskin")
    if not B.f:
        P += [Part("eye_" + s, "head", "ember", ell((4.0, B.side(s) * 1.35, h + 1.25), (0.62, 0.72, 0.68))) for s in "rl"]
    else:
        P += B.eyes("ember")
    # the horned skull worn as a helm (the beast's brow over his own face), the hair (player's colour) pouring out
    cap_from = h + 0.9 if not B.f else h + 1.9
    P.append(Part("skullcap", "head", "bone", clip(ell((0.45, 0, h + 0.5), (3.85, 3.7, 3.85)), G.above(cap_from))))
    P.append(Part("brow", "head", "bone", ell((3.4, 0, h + 1.0), (0.9, 3.0, 0.75))))
    P.append(Part("snout", "head", "bone", ell((3.9, 0, h + 1.9), (1.2, 0.9, 0.7))))
    for s in "rl":
        sg = B.side(s)
        a, b, c = np.array((0.4, sg * 2.9, h + 2.2)), np.array((-0.3, sg * 5.3, h + 3.2)), np.array((0.9, sg * 5.8, h + 7.0))
        P.append(Part("horn_" + s, "head", "horn", union(cone(a, b, 1.0, 0.72), cone(b, c, 0.72, 0.3))))
    P += G.mane(B)
    if B.f:
        P += G.hair_long(B, length=10.0)
    if B.f:
        P.append(Part("wrap", "torso", "fur", clip(ell((0.2, 0, H["chest"] - 0.2), (2.75, 3.85, 1.9)), G.above(H["chest"] - 1.9))))
    # the fur mantle over the shoulders
    P.append(Part("mantle", "torso", "fur", clip(ell((-0.5, 0, H["shoulder"] + 0.2), (3.3, B.sw + 1.7, 2.4)),
                                               G.above(H["shoulder"] - 1.6))))
    P.append(Part("strap", "torso", "leather", cone((2.75, B.sw * 0.55, H["shoulder"] - 0.6), (2.6, -B.sw * 0.6, H["waist"] + 1.2), 0.42, 0.42)))
    P += G.belt(B, "leather", "bone")
    P += G.skirt(B, "kilt", to=5.2, flare=1.06)
    for s in "rl":
        P += G.bracer(B, s, "iron", r=1.5, start=0.3)
        sg = B.side(s)
        el = B.joint("fore_" + s)
        P.append(Part("spike_" + s, "fore_" + s, "iron", cone(el + (0, sg * 1.1, -1.6), el + (-0.2, sg * 2.6, -1.2), 0.5, 0.2)))
    P += G.boots(B, "boot", top=4.6, r=1.75)
    st = Stance(arm_r=(34, 16), fore_r=(96, -6), arm_l=(4, 14), fore_l=(30, 0), swing_r=0.0, swing_l=1.25, nod=16)
    rg = _rig(B, P)
    # the great axe: carried in the right fist, the haft up over the shoulder, the head behind it
    W = rg.world(pose(st))
    R, cc, t = W["fore_r"]
    hand = R @ (B.hand("r") - cc) + cc + t
    Rt, ct, tt = W["torso"]
    hand_t = (hand - ct - tt) @ Rt + ct
    d = np.array((-0.5, 0.18, 1.0))
    d /= np.linalg.norm(d)
    lo, hi = hand_t - d * 3.2, hand_t + d * 11.5
    P2 = [Part("axe_haft", "torso", "wood", cone(lo, hi, 0.52, 0.5)),
          Part("axe_pom", "torso", "iron", ell(lo, (0.7, 0.7, 0.7)))]
    side = np.cross(d, (0, 1, 0))
    side /= np.linalg.norm(side)
    hc = hand_t + d * 9.6
    for k, sg in enumerate((1, -1)):
        bc = hc + side * sg * 2.4
        blade = clip(ell(bc, (2.6, 0.5, 3.3)), ell(hc + side * sg * 0.4, (4.6, 0.8, 4.4)))
        P2.append(Part("axe_bit%d" % k, "torso", "iron", union(blade, cone(hc, bc, 0.9, 0.7))))
        P2.append(Part("axe_edge%d" % k, "torso", "ember", clip(ell(bc + side * sg * 0.9, (1.5, 0.62, 3.0)),
                                                                 ell(hc + side * sg * 0.4, (4.85, 0.9, 4.5)))))
    rg = _rig(B, P + P2)
    return rg, st


CLASSES = {"warrior": warrior, "juggernaut": juggernaut, "berserker": berserker}
