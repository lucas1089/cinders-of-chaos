"""The humanoid under every outfit: bones, the bare body (male or female, chibi proportions like the client's player
looks: a big head, short legs) and the poses every outfit shares (standing, an 8-step walk, riding).

A design (warrior_line.py ...) builds on it: Body(sex) gives the bones and anchor points; the design lists its parts
(the skin it shows, cloth, armour, weapon) on those bones, and may change the stance of the arms.
"""
import math

import numpy as np

from rig import Part, cone, ell, rot

FWD, RIGHT, UP = (1, 0, 0), (0, 1, 0), (0, 0, 1)


class Body:
    SCALE = (1.5, 1.5, 1.2)   # u, v, h: the client's player looks are stocky, wider than tall

    def __init__(self, sex="male", bulk=1.0, height=0.0):
        """bulk widens shoulders and chest (heavy armour builds); height adds to the trunk (ascended classes)."""
        f = sex == "female"
        self.sex = sex
        self.f = f
        hb = height
        self.sw = (4.3 if not f else 3.8) * bulk        # half width at the shoulders
        self.hipw = 2.0 if not f else 2.1                # hip joint offset
        self.H = dict(knee=6.0, hip=11.4, waist=13.2 + hb * 0.4, chest=17.0 + hb * 0.7, shoulder=19.6 + hb,
                      neck=21.4 + hb, head=25.0 + hb)
        H = self.H
        self.bones = {
            "root": (None, (0, 0, 0)),
            "pelvis": ("root", (0, 0, H["hip"])),
            "torso": ("pelvis", (0, 0, H["waist"])),
            "head": ("torso", (0.3, 0, H["neck"])),
            "arm_r": ("torso", (0, self.sw, H["shoulder"])),
            "fore_r": ("arm_r", (0.1, self.sw + 0.6, H["shoulder"] - 4.2)),
            "arm_l": ("torso", (0, -self.sw, H["shoulder"])),
            "fore_l": ("arm_l", (0.1, -self.sw - 0.6, H["shoulder"] - 4.2)),
            "thigh_r": ("pelvis", (0, self.hipw, H["hip"])),
            "shin_r": ("thigh_r", (0.2, self.hipw + 0.1, H["knee"])),
            "thigh_l": ("pelvis", (0, -self.hipw, H["hip"])),
            "shin_l": ("thigh_l", (0.2, -self.hipw - 0.1, H["knee"])),
        }

    # anchor points ------------------------------------------------------------------------------------------
    def joint(self, b):
        return np.asarray(self.bones[b][1], float)

    def side(self, s):
        return 1.0 if s == "r" else -1.0

    def wrist(self, s):
        sg = self.side(s)
        sh = self.H["shoulder"]
        return np.array((0.3, sg * (self.sw + 0.9), sh - 8.0))

    def hand(self, s):
        sg = self.side(s)
        return self.wrist(s) + np.array((0.2, 0.1 * sg, -1.0))

    def ankle(self, s):
        sg = self.side(s)
        return np.array((0.2, sg * (self.hipw + 0.15), 1.7))

    # the bare body ------------------------------------------------------------------------------------------
    def parts(self, skin="skin", shirt="skin", pants="skin", shoe="skin", sleeve=None, head=True):
        """The body's own parts, each with the material given (a design covers some with gear)."""
        H, f = self.H, self.f
        P = []
        tw = 3.6 if f else 4.0
        if f:
            P.append(Part("chest", "torso", shirt, ell((0.1, 0, H["chest"] - 0.2), (2.5, tw, 3.6))))
            P.append(Part("bust", "torso", shirt, ell((1.2, 0, H["chest"] - 0.4), (1.7, 2.6, 1.5))))
            P.append(Part("waist", "torso", shirt, ell((0, 0, H["waist"] + 0.8), (2.0, 2.9, 2.2))))
            P.append(Part("hips", "pelvis", pants, ell((0, 0, H["hip"] - 0.3), (2.4, 3.6, 2.0))))
        else:
            P.append(Part("chest", "torso", shirt, ell((0, 0, H["chest"]), (2.7, tw * (self.sw / 4.3), 3.8))))
            P.append(Part("waist", "torso", shirt, ell((0, 0, H["waist"] + 0.8), (2.3, 3.2, 2.4))))
            P.append(Part("hips", "pelvis", pants, ell((0, 0, H["hip"] - 0.2), (2.3, 3.3, 2.0))))
        P.append(Part("neck", "torso", skin, cone((0.2, 0, H["neck"] - 2.5), (0.3, 0, H["neck"] + 0.5), 1.3, 1.2)))
        if head:
            P.append(Part("skull", "head", skin, ell((0.5, 0, H["head"]), (3.6, 3.45, 3.7))))
        for s in "rl":
            sg = self.side(s)
            sh = self.joint("arm_" + s)
            el = self.joint("fore_" + s)
            ar = 1.45 if not f else 1.25
            P.append(Part("upper_" + s, "arm_" + s, sleeve or skin, cone(sh + (0, 0, -0.3), el, ar, ar * 0.9)))
            P.append(Part("fore_" + s, "fore_" + s, skin, cone(el, self.wrist(s), ar * 0.9, ar * 0.8)))
            P.append(Part("hand_" + s, "fore_" + s, skin, ell(self.hand(s), (1.2, 1.0, 1.25))))
            hip, kn, an = self.joint("thigh_" + s), self.joint("shin_" + s), self.ankle(s)
            lr = 1.75 if not f else 1.6
            P.append(Part("thigh_" + s, "thigh_" + s, pants, cone(hip, kn, lr, lr * 0.85)))
            P.append(Part("shin_" + s, "shin_" + s, pants, cone(kn, an, lr * 0.85, lr * 0.72)))
            P.append(Part("foot_" + s, "shin_" + s, shoe, ell(an + (0.9, 0, -0.75), (2.2, 1.25, 1.05))))
        return P

    def eyes(self, mat="eye", forward=0.0):
        H = self.H
        return [Part("eye_" + s, "head", mat, ell((3.62 + forward, self.side(s) * 1.3, H["head"] + 0.4), (0.7, 0.62, 0.9)))
                for s in "rl"]


# ------------------------------------------------------------------------------------------------ poses
def swing(deg):
    """About the figure's right axis: +deg brings what hangs below the pivot FORWARD."""
    return rot(RIGHT, -deg)


def spread(deg, s):
    """About the forward axis: +deg lifts a limb of side s outward."""
    return rot(FWD, deg if s == "r" else -deg)


def twist(deg):
    """About the vertical: +deg turns the front toward the figure's right."""
    return rot(UP, deg)


def R_(*rs):
    out = np.eye(3)
    for r in rs:
        out = out @ r
    return out


def lift(px):
    """A whole-pixel move up the diagonal (1.5 of height per pixel)."""
    return (np.eye(3), np.array((0, 0, 1.5 * px)))


class Stance:
    """The rest of the arms and how the walk moves them; a design passes its own."""

    def __init__(self, arm_r=(8, 6), fore_r=(30, 0), arm_l=(6, 6), fore_l=(20, 0), swing_r=0.5, swing_l=1.0,
                 torso_twist=0.0, nod=-10.0, extra=None):
        self.arm_r, self.fore_r, self.arm_l, self.fore_l = arm_r, fore_r, arm_l, fore_l
        self.swing_r, self.swing_l, self.torso_twist, self.nod = swing_r, swing_l, torso_twist, nod
        self.extra = extra or {}


def pose(st, k=None, mount=False):
    """k None: standing; k 0..7: the walk; mount: riding (legs over the saddle, raised)."""
    s = 0.0 if k is None else math.sin(2 * math.pi * k / 8)
    c = 0.0 if k is None else math.cos(2 * math.pi * k / 8)
    P = {}
    bob = 1 if (k is not None and k % 4 == 0) else 0
    if mount:
        P["root"] = (np.eye(3), np.array((0, 0, 1.5 * (8 + (1 if k is not None and k % 4 == 2 else 0)))))
        for side in "rl":
            P["thigh_" + side] = (R_(spread(18, side), swing(78)), np.zeros(3))
            P["shin_" + side] = (swing(-82), np.zeros(3))
        s = 0.0
    else:
        P["root"] = lift(bob)
        a = 24
        P["thigh_r"] = (swing(a * s), np.zeros(3))
        P["thigh_l"] = (swing(-a * s), np.zeros(3))
        P["shin_r"] = (swing(-30 * max(0.0, c) - 6 * max(0.0, -s)), np.zeros(3))
        P["shin_l"] = (swing(-30 * max(0.0, -c) - 6 * max(0.0, s)), np.zeros(3))
    P["torso"] = (twist(st.torso_twist + (3 * s if k is not None else 0)), np.zeros(3))
    P["head"] = (swing(-st.nod), np.zeros(3))       # the face bowed toward the viewer (a level face looks up)
    ar = 20 * s
    P["arm_r"] = (R_(spread(st.arm_r[1], "r"), swing(st.arm_r[0] - ar * st.swing_r)), np.zeros(3))
    P["fore_r"] = (R_(spread(st.fore_r[1], "r"), swing(st.fore_r[0])), np.zeros(3))
    P["arm_l"] = (R_(spread(st.arm_l[1], "l"), swing(st.arm_l[0] + ar * st.swing_l)), np.zeros(3))
    P["fore_l"] = (R_(spread(st.fore_l[1], "l"), swing(st.fore_l[0])), np.zeros(3))
    for b, fn in st.extra.items():
        P[b] = fn(k, mount)
    return P


def check_signs():
    def apply(R, piv, X):
        return R @ (np.asarray(X, float) - piv) + piv
    assert apply(swing(30), np.zeros(3), (0, 0, -5))[0] > 0, "swing + must bring the foot forward"
    assert apply(spread(30, "r"), np.zeros(3), (0, 0, -5))[1] > 0, "spread + must lift the right arm outward (+v)"
    assert apply(spread(30, "l"), np.zeros(3), (0, 0, -5))[1] < 0, "spread + must lift the left arm outward (-v)"
    assert apply(twist(30), np.zeros(3), (5, 0, 0))[1] > 0, "twist + turns the front to the right"


check_signs()
