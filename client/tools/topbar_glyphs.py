"""Glyph shapes of the hub menu (O550) on a 24 x 24 grid: white on a black mask, plain polygons, arcs and circles.

Our own shapes, nothing copied. gen_topbar_icons.py draws them into the glyph atlas; NAMES below is the list the checks
read (tools/ci/check_topbar_tree.py reads it as text, so keep one quoted name per entry)."""
import math
from PIL import Image, ImageDraw

K = 12          # mask pixels per grid unit
N = 24 * K


class G:
    def __init__(self):
        self.im = Image.new('L', (N, N), 0)
        self.d = ImageDraw.Draw(self.im)

    def _p(self, pts):
        return [(x * K, y * K) for x, y in pts]

    def poly(self, pts, cut=False):
        self.d.polygon(self._p(pts), fill=0 if cut else 255)

    def line(self, pts, w=2.0, cut=False, round_ends=True):
        fill = 0 if cut else 255
        pp = self._p(pts)
        self.d.line(pp, fill=fill, width=int(w * K), joint='curve')
        if round_ends:
            r = w * K / 2
            for (x, y) in (pp[0], pp[-1]):
                self.d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

    def circ(self, cx, cy, r, cut=False):
        self.d.ellipse([(cx - r) * K, (cy - r) * K, (cx + r) * K, (cy + r) * K], fill=0 if cut else 255)

    def ell(self, x0, y0, x1, y1, cut=False):
        self.d.ellipse([x0 * K, y0 * K, x1 * K, y1 * K], fill=0 if cut else 255)

    def rect(self, x0, y0, x1, y1, cut=False):
        self.d.rectangle([x0 * K, y0 * K, x1 * K, y1 * K], fill=0 if cut else 255)

    def ring(self, cx, cy, r, w, cut=False):
        self.circ(cx, cy, r, cut)
        self.circ(cx, cy, r - w, not cut)

    def arc(self, x0, y0, x1, y1, a0, a1, w=2.0, cut=False):
        self.d.arc([x0 * K, y0 * K, x1 * K, y1 * K], a0, a1, fill=0 if cut else 255, width=int(w * K))

    def carve_poly(self, pts, grow=0.9):
        """clear a margin around a polygon so a shape drawn next stands out from what is behind it"""
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        big = []
        for x, y in pts:
            dx, dy = x - cx, y - cy
            l = math.hypot(dx, dy) or 1
            big.append((x + dx / l * grow, y + dy / l * grow))
        self.poly(big, cut=True)

    def star(self, cx, cy, ro, ri, n=5, rot=-90, cut=False):
        pts = []
        for i in range(n * 2):
            a = math.radians(rot + i * 180 / n)
            r = ro if i % 2 == 0 else ri
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        self.poly(pts, cut)

    def arrow(self, x0, y0, x1, y1, w=2.0, head=3.6):
        self.line([(x0, y0), (x1, y1)], w)
        a = math.atan2(y1 - y0, x1 - x0)
        p = (x1 + math.cos(a) * 1.2, y1 + math.sin(a) * 1.2)
        l = (x1 - math.cos(a) * head + math.cos(a + math.pi / 2) * head * 0.85, y1 - math.sin(a) * head + math.sin(a + math.pi / 2) * head * 0.85)
        r = (x1 - math.cos(a) * head + math.cos(a - math.pi / 2) * head * 0.85, y1 - math.sin(a) * head + math.sin(a - math.pi / 2) * head * 0.85)
        self.poly([p, l, r])

    def gear(self, cx, cy, r, teeth=8, hole=0.42):
        self.circ(cx, cy, r * 0.78)
        for k in range(teeth):
            a = 2 * math.pi * k / teeth
            ca, sa = math.cos(a), math.sin(a)
            hw = r * 0.22
            pts = []
            for (u, v) in ((r * 0.6, -hw), (r * 1.0, -hw * 0.8), (r * 1.0, hw * 0.8), (r * 0.6, hw)):
                pts.append((cx + u * ca - v * sa, cy + u * sa + v * ca))
            self.poly(pts)
        self.circ(cx, cy, r * hole, cut=True)


def helm(g):
    g.poly([(5, 12), (5, 8), (8, 4.5), (12, 3.5), (16, 4.5), (19, 8), (19, 12), (19, 19.5), (15.2, 20.5), (15.2, 15.5), (8.8, 15.5), (8.8, 20.5), (5, 19.5)])
    g.poly([(5, 8.5), (1.5, 2.5), (8, 5.5)])
    g.poly([(19, 8.5), (22.5, 2.5), (16, 5.5)])
    g.rect(7.6, 9.4, 16.4, 11.6, cut=True)
    g.rect(11.2, 11.6, 12.8, 15.5, cut=True)


def claws(g):
    for o in (0, 5, 10):
        g.poly([(4 + o, 2.5), (8 + o, 2.5), (11 + o, 21.5)])


def peaks(g):
    g.poly([(1.5, 21), (9.5, 7), (13.5, 13), (16, 9.5), (22.5, 21)])
    g.line([(9.5, 7), (9.5, 1.8)], 1.3)
    g.poly([(9.5, 1.8), (15.5, 3.4), (9.5, 5)])
    g.poly([(8, 11), (9.5, 9), (11, 11), (10, 12.2), (9.5, 11.2), (8.8, 12.2)], cut=True)


def swords(g):
    g.line([(4, 4), (19, 19)], 2.6)
    g.line([(20, 4), (5, 19)], 2.6)
    g.line([(12.2, 19), (19, 12.2)], 2.2)
    g.line([(11.8, 19), (5, 12.2)], 2.2)
    g.circ(20.2, 20.2, 1.8)
    g.circ(3.8, 20.2, 1.8)
    g.poly([(2, 2), (6, 3), (3, 6)])
    g.poly([(22, 2), (18, 3), (21, 6)])


def coins(g):
    for y in (15.5, 10.5, 5.5):
        g.ell(4.2, y - 0.9, 19.8, y + 4.6, cut=True)
        g.rect(4.2, y + 2, 19.8, y + 5.6, cut=True)
        g.ell(4.2, y + 3.2, 19.8, y + 8.7, cut=True)
        g.ell(5, y, 19, y + 4.6)
        g.rect(5, y + 2.3, 19, y + 5)
        g.ell(5, y + 2.6, 19, y + 7.4)
        g.ell(7.5, y + 0.9, 16.5, y + 3.7, cut=True)
    g.star(18.5, 3.5, 3, 0.8, n=4, rot=-90)


def heads(g):
    g.circ(15.5, 8, 3.6)
    g.ell(9.5, 13.5, 21.5, 26)
    g.circ(9, 10, 4.6, cut=True)
    g.ell(1, 15, 17, 29, cut=True)
    g.circ(8.8, 9.6, 3.9)
    g.ell(2.2, 15.8, 15.4, 28)
    g.rect(0, 22, 24, 24, cut=True)


def book(g):
    g.poly([(2.5, 5.5), (11, 7.5), (11, 19.5), (2.5, 17.5)])
    g.poly([(21.5, 5.5), (13, 7.5), (13, 19.5), (21.5, 17.5)])
    g.line([(2.5, 19.6), (11, 21.6), (13, 21.6), (21.5, 19.6)], 1.6)
    for y in (10.5, 13.5):
        g.line([(4.4, y - 0.4), (9, y + 0.5)], 0.9, cut=True)
        g.line([(19.6, y - 0.4), (15, y + 0.5)], 0.9, cut=True)


def gear(g):
    g.gear(12, 12, 10, 8, 0.38)


def anvil(g):
    g.poly([(1.5, 7.5), (21.5, 7.5), (21.5, 10.4), (15.5, 11.4), (15.5, 15), (18.5, 19), (18.5, 21.5), (5.5, 21.5), (5.5, 19), (8.5, 15), (8.5, 11.4), (1.5, 10.6)])
    g.line([(5, 9.2), (19.5, 9.2)], 0.9, cut=True)
    g.star(18.5, 3.6, 2.8, 0.8, n=4)


def dividers(g):
    g.line([(12, 4.5), (5, 21)], 2.4)
    g.line([(12, 4.5), (19, 21)], 2.4)
    g.circ(12, 4.5, 2.6)
    g.circ(12, 4.5, 1.0, cut=True)
    g.line([(8.2, 14), (15.8, 14)], 1.8)
    g.line([(12, 4.5), (12, 14)], 1.4)


def shirt(g):
    g.poly([(8, 3), (10.4, 5.6), (13.6, 5.6), (16, 3), (22.5, 7.5), (19.5, 11.5), (17, 10), (17, 21), (7, 21), (7, 10), (4.5, 11.5), (1.5, 7.5)])


def house(g):
    g.poly([(1.5, 12.5), (12, 2.5), (22.5, 12.5), (20, 12.5), (20, 21), (4, 21), (4, 12.5)])
    g.rect(9.8, 14.4, 14.2, 21.2, cut=True)
    g.rect(15, 5, 18, 8.5)


def bag(g):
    g.ell(4, 9, 20, 22.5)
    g.poly([(8.5, 10), (15.5, 10), (17, 4.5), (7, 4.5)])
    g.poly([(7, 4.5), (9.5, 2.5), (14.5, 2.5), (17, 4.5)])
    g.line([(8, 10.2), (16, 10.2)], 1.1, cut=True)
    g.line([(11, 14.5), (13, 14.5)], 0.9, cut=True)
    g.line([(7.5, 14), (11, 20)], 0.9, cut=True)


def bars(g):
    g.rect(2.5, 20, 21.5, 21.8)
    g.rect(4, 12, 8, 19)
    g.rect(10, 5, 14, 19)
    g.rect(16, 9, 20, 19)


def mapg(g):
    g.poly([(1.5, 6), (8, 4), (8, 19), (1.5, 21)])
    g.poly([(9, 4), (15, 6), (15, 21), (9, 19)])
    g.poly([(16, 6), (22.5, 4), (22.5, 19), (16, 21)])
    g.circ(12, 11, 4.4, cut=True)
    g.poly([(8.3, 12.2), (15.7, 12.2), (12, 18.5)], cut=True)
    g.circ(12, 10.6, 3.1)
    g.poly([(9.2, 11.8), (14.8, 11.8), (12, 16.8)])
    g.circ(12, 10.6, 1.1, cut=True)


def trio(g):
    for cx, cy, s in ((4.6, 8, 2.6), (12, 6.5, 3.0), (19.4, 8, 2.6)):
        g.circ(cx, cy, s)
    g.ell(1, 11.5, 8.4, 22.5)
    g.ell(15.6, 11.5, 23, 22.5)
    g.ell(7.6, 10, 16.4, 24.5, cut=True)
    g.ell(8.2, 10.6, 15.8, 23.5)
    g.rect(0, 21, 24, 24, cut=True)


def rift(g):
    g.poly([(11.5, 1.2), (16.2, 7), (12.4, 10.2), (17.2, 14.2), (12.8, 18), (14.2, 22.8), (7.6, 17), (11.8, 14), (6.8, 10), (10.6, 6.5)])
    for (x, y, s) in ((5.5, 7, 1.8), (18.5, 16, 1.8), (5, 17, 1.5), (19, 6, 1.5)):
        g.poly([(x, y - s), (x + s, y), (x, y + s), (x - s, y)])


def tower(g):
    g.poly([(6, 21.5), (6, 10), (4, 10), (4, 3.5), (7.2, 3.5), (7.2, 6), (10.4, 6), (10.4, 3.5), (13.6, 3.5), (13.6, 6), (16.8, 6), (16.8, 3.5), (20, 3.5), (20, 10), (18, 10), (18, 21.5)])
    g.rect(10.4, 15.5, 13.6, 21.6, cut=True)
    g.ell(10.4, 13.6, 13.6, 17.6, cut=True)
    g.rect(11.2, 8.4, 12.8, 12, cut=True)


def laurel(g):
    g.arc(2.5, 2.5, 21.5, 21.5, 115, 245, 1.8)
    g.arc(2.5, 2.5, 21.5, 21.5, -65, 65, 1.8)
    for (x, y) in ((5.2, 6.2), (3.4, 10.5), (3.6, 15.4), (6.4, 19.2), (18.8, 6.2), (20.6, 10.5), (20.4, 15.4), (17.6, 19.2)):
        g.ell(x - 2.0, y - 1.3, x + 2.0, y + 1.3)
    g.star(12, 12, 5.2, 2.2)


def scroll(g):
    g.rect(6.5, 4.5, 17.5, 19.5)
    g.ell(4.5, 2.2, 19.5, 7)
    g.ell(4.5, 17, 19.5, 21.8)
    g.ell(6.2, 3.2, 12, 6.2, cut=True)
    g.line([(9, 10), (15, 10)], 1.3, cut=True)
    g.line([(9, 13.5), (15, 13.5)], 1.3, cut=True)
    g.line([(9, 17), (12.5, 17)], 1.3, cut=True)


def hammer(g):
    g.line([(11, 11), (19, 21)], 3.4)
    g.poly([(3.5, 6.5), (14.5, 2), (19, 7), (8, 12)])
    g.line([(5.5, 8.4), (16.4, 4.4)], 0.9, cut=True)


def stall(g):
    g.poly([(1.5, 9.5), (5, 3.5), (19, 3.5), (22.5, 9.5)])
    for x in (7.2, 12, 16.8):
        g.line([(x, 3.8), (x - 0.6, 9)], 1.1, cut=True)
    for x in (3.5, 8.2, 12, 15.8, 20.5):
        g.circ(x, 9.8, 1.9)
    g.rect(3.8, 11.5, 5.6, 21.5)
    g.rect(18.4, 11.5, 20.2, 21.5)
    g.rect(3, 15.5, 21, 17.6)
    g.ell(8.5, 13, 15.5, 15.6)


def sliders(g):
    for y, x in ((5.5, 7), (12, 16), (18.5, 10)):
        g.line([(2.5, y), (21.5, y)], 2.0)
        g.circ(x, y, 3.8, cut=True)
        g.circ(x, y, 2.9)


def lifebuoy(g):
    g.ring(12, 12, 10, 4.8)
    for a in (45, 135, 225, 315):
        r = math.radians(a)
        g.line([(12 + 6 * math.cos(r), 12 + 6 * math.sin(r)), (12 + 11 * math.cos(r), 12 + 11 * math.sin(r))], 2.0, cut=True, round_ends=False)


def terminal(g):
    g.line([(4, 6), (11, 12), (4, 18)], 2.8)
    g.line([(13, 19), (21, 19)], 2.8)


def stopwatch(g):
    g.ring(12, 13.5, 8.6, 2.5)
    g.rect(10.2, 1.8, 13.8, 3.6)
    g.rect(11.2, 3.4, 12.8, 5.2)
    g.line([(12, 13.5), (15.8, 9.4)], 2.0)
    g.circ(12, 13.5, 1.6)
    g.line([(18.6, 5.4), (20.2, 3.8)], 1.8)


def listg(g):
    for y in (6.5, 12, 17.5):
        g.circ(4.6, y, 1.9)
        g.line([(9, y), (21, y)], 2.6)


def compass(g):
    g.ring(12, 12, 10, 1.9)
    g.poly([(12, 3.8), (14.2, 9.8), (20.2, 12), (14.2, 14.2), (12, 20.2), (9.8, 14.2), (3.8, 12), (9.8, 9.8)])
    g.circ(12, 12, 1.2, cut=True)


def horns(g):
    g.poly([(7, 10), (17, 10), (18.5, 16), (14.2, 21.5), (9.8, 21.5), (5.5, 16)])
    g.poly([(7.2, 11.5), (3.6, 10.5), (1.8, 3), (8.6, 7.8)])
    g.poly([(16.8, 11.5), (20.4, 10.5), (22.2, 3), (15.4, 7.8)])
    g.circ(9.4, 14.2, 1.5, cut=True)
    g.circ(14.6, 14.2, 1.5, cut=True)
    g.line([(11, 18.5), (13, 18.5)], 1.0, cut=True)


def cross(g):
    g.circ(12, 14.2, 7.6)
    g.poly([(12, 2.2), (6.2, 11.8), (17.8, 11.8)])
    g.rect(10.8, 10, 13.2, 18.4, cut=True)
    g.rect(7.8, 13, 16.2, 15.4, cut=True)


def magnifier(g):
    g.ring(10, 10, 7.2, 2.5)
    g.line([(15.6, 15.6), (21.5, 21.5)], 3.4)
    g.circ(10, 8.6, 1.5)
    g.ell(7, 10.6, 13, 14.2)


def pack(g):
    g.ring(12, 5.6, 3.4, 1.3)
    g.ell(4.5, 5.5, 19.5, 13)
    g.rect(4.5, 9, 19.5, 21.5)
    g.rect(7.6, 14, 16.4, 20, cut=True)
    g.rect(8.6, 15, 15.4, 19, )
    g.line([(8.8, 17), (15.2, 17)], 0.9, cut=True)
    g.line([(2.5, 11.5), (2.5, 19)], 1.6)
    g.line([(21.5, 11.5), (21.5, 19)], 1.6)


def bolt(g):
    g.poly([(14.5, 1.8), (4.8, 13.2), (10.8, 13.2), (8.6, 22.2), (19.4, 9.6), (13, 9.6)])


def tome(g):
    g.rect(5, 3, 19, 21.5)
    g.line([(8.2, 3), (8.2, 21.5)], 1.0, cut=True)
    g.star(13.8, 12, 4, 1.7, cut=True)
    g.line([(5, 19), (19, 19)], 1.0, cut=True)


def tree(g):
    g.line([(12, 19), (12, 6)], 1.7)
    g.line([(12, 14.5), (6, 9)], 1.7)
    g.line([(12, 14.5), (18, 9)], 1.7)
    g.line([(12, 10.5), (12, 5)], 1.7)
    for (x, y, r) in ((6, 8, 2.4), (18, 8, 2.4), (12, 4.6, 2.4), (12, 20, 2.8)):
        g.circ(x, y, r)
    g.circ(12, 11.4, 1.9)


def info(g):
    g.rect(5.5, 3, 18.5, 21)
    g.poly([(18.5, 3), (18.5, 8), (13.5, 3)], cut=True)
    g.circ(12, 8.6, 1.4, cut=True)
    g.rect(10.9, 11.2, 13.1, 17.6, cut=True)


def trophy(g):
    g.poly([(6.5, 3), (17.5, 3), (16.5, 11), (13.2, 14.2), (10.8, 14.2), (7.5, 11)])
    g.rect(10.9, 14, 13.1, 17.4)
    g.rect(7.6, 17.2, 16.4, 20.6)
    g.arc(1.6, 3.8, 9.4, 11.6, 80, 280, 1.7)
    g.arc(14.6, 3.8, 22.4, 11.6, -100, 100, 1.7)
    g.star(12, 8, 2.6, 1.1, cut=True)


def star(g):
    g.star(11, 13, 9.8, 4.2)
    g.star(19.6, 4.4, 3.0, 0.9, n=4)
    g.star(4, 4.4, 2.2, 0.7, n=4)


def cards(g):
    back = [(3, 6), (13, 3.2), (16.4, 16.6), (6.4, 19.4)]
    g.poly(back)
    g.carve_poly([(8, 5.8), (19.5, 5.8), (19.5, 21.2), (8, 21.2)], 1.0)
    g.poly([(8, 5.8), (19.5, 5.8), (19.5, 21.2), (8, 21.2)])
    g.circ(13.8, 13.5, 2.6, cut=True)


def gem(g):
    g.poly([(6.5, 3), (17.5, 3), (22.5, 9), (12, 21.5), (1.5, 9)])
    g.line([(1.8, 9), (22.2, 9)], 0.9, cut=True)
    g.line([(6.5, 3.2), (9.4, 9)], 0.9, cut=True)
    g.line([(17.5, 3.2), (14.6, 9)], 0.9, cut=True)
    g.line([(9.4, 9), (12, 21)], 0.9, cut=True)
    g.line([(14.6, 9), (12, 21)], 0.9, cut=True)


def swirl(g):
    g.ring(12, 12, 10, 2.0)
    g.arc(6.5, 6.5, 17.5, 17.5, 20, 300, 2.0)
    g.arc(9.5, 9.5, 14.5, 14.5, 200, 480, 1.6)
    g.circ(12, 12, 1.2)


def funnel(g):
    g.poly([(2.5, 3.5), (21.5, 3.5), (14.2, 13), (14.2, 21), (9.8, 18.5), (9.8, 13)])
    g.line([(5.5, 6.5), (18.5, 6.5)], 1.0, cut=True)


def split(g):
    g.circ(8, 12, 6)
    g.circ(8, 12, 3.6, cut=True)
    g.circ(8, 12, 2.2)
    g.arrow(14, 8.5, 21, 4.5, 1.9, 3.4)
    g.arrow(14, 15.5, 21, 19.5, 1.9, 3.4)


def sellcoin(g):
    g.circ(8.5, 14.5, 6.4)
    g.circ(8.5, 14.5, 4.2, cut=True)
    g.circ(8.5, 14.5, 2.4)
    g.arrow(13.5, 9.5, 21, 3.5, 2.2, 3.6)


def lootarrow(g):
    g.ell(3, 11.5, 17, 22.5)
    g.poly([(6.8, 12.2), (13.2, 12.2), (14.6, 8), (5.4, 8)])
    g.line([(6.5, 12.4), (13.5, 12.4)], 1.0, cut=True)
    g.arrow(18.5, 2.8, 18.5, 12, 2.3, 3.8)


def orbs(g):
    g.circ(6.8, 13.5, 4.8)
    g.circ(17.2, 13.5, 4.8)
    g.circ(5.4, 12, 1.3, cut=True)
    g.circ(15.8, 12, 1.3, cut=True)
    g.arrow(7, 4.2, 17, 4.2, 1.7, 3.0)
    g.arrow(17, 22.6, 7, 22.6, 1.7, 3.0)


def pick(g):
    g.arc(2.5, 2.5, 21.5, 20.5, 198, 342, 3.2)
    g.poly([(1.6, 11), (4.4, 7.8), (5.6, 11.4)])
    g.poly([(22.4, 11), (19.6, 7.8), (18.4, 11.4)])
    g.line([(12, 6), (12, 22)], 2.8)
    g.im = g.im.rotate(-40, resample=Image.BICUBIC)


def salvage(g):
    g.gear(12, 12, 9.4, 8, 0.36)
    g.line([(3, 21), (9.5, 14.5), (13, 16.5), (21.5, 3)], 1.5, cut=True)


def scales(g):
    g.rect(10.9, 4, 13.1, 20.5)
    g.rect(6.5, 20, 17.5, 22.2)
    g.line([(3, 7), (21, 7)], 1.9)
    g.circ(12, 4.4, 1.8)
    for cx in (4.6, 19.4):
        g.line([(cx, 7), (cx - 3.2, 14.5)], 0.9)
        g.line([(cx, 7), (cx + 3.2, 14.5)], 0.9)
        g.poly([(cx - 3.9, 14.2), (cx + 3.9, 14.2), (cx, 18.2)])


def columns(g):
    g.poly([(1.5, 8.2), (12, 2), (22.5, 8.2)])
    g.rect(3, 9, 21, 10.8)
    for x in (4.6, 10.4, 16.2):
        g.rect(x, 11.8, x + 3.2, 19)
    g.rect(2, 19.8, 22, 22.2)


def chest(g):
    g.rect(3, 10.5, 21, 21.5)
    g.ell(3, 3.5, 21, 17)
    g.rect(3, 10, 21, 12, cut=True)
    g.rect(3, 12.2, 21, 13.2, cut=False)
    g.rect(10.4, 11, 13.6, 17.4, cut=True)
    g.rect(10.9, 12.5, 13.1, 16.9)


def pouch(g):
    g.ell(4, 8, 20, 22.5)
    g.poly([(8, 9), (16, 9), (18.4, 4), (5.6, 4)])
    g.poly([(5.6, 4), (7.5, 2.2), (9.5, 4), (12, 2.2), (14.5, 4), (16.5, 2.2), (18.4, 4)])
    g.line([(8, 9.4), (16, 9.4)], 1.1, cut=True)
    g.ring(12, 16, 3.3, 1.1, cut=True)


def door(g):
    g.poly([(5, 21.5), (5, 5), (14.5, 2.5), (14.5, 21.5)])
    g.circ(11.6, 12.4, 1.1, cut=True)
    g.arrow(21.5, 12, 15.8, 12, 2.0, 3.4)


def power(g):
    g.ring(12, 13, 8.4, 2.4)
    g.rect(8.4, 2, 15.6, 11, cut=True)
    g.line([(12, 2.4), (12, 12)], 2.6)


def note(g):
    g.ell(3.5, 14.5, 11.5, 21.5)
    g.line([(10.6, 17.5), (10.6, 4)], 2.0, round_ends=False)
    g.poly([(10.6, 3.6), (20, 6.4), (20, 10.4), (10.6, 8)])
    g.line([(15.2, 12.5), (21.5, 12.5)], 1.4)


NAMES = (
    'anvil', 'bag', 'bars', 'bolt', 'book', 'cards', 'chest', 'claws', 'columns', 'compass', 'coins', 'cross', 'dividers', 'door',
    'funnel', 'gear', 'gem', 'hammer', 'heads', 'helm', 'horns', 'house', 'info', 'laurel', 'list', 'lootarrow', 'magnifier', 'map',
    'note', 'orbs', 'pack', 'peaks', 'pick', 'pouch', 'power', 'rift', 'salvage', 'scales', 'scroll', 'sellcoin', 'shirt', 'sliders',
    'split', 'stall', 'star', 'stopwatch', 'swirl', 'swords', 'terminal', 'tome', 'tower', 'tree', 'trio', 'trophy',
)

_SHAPES = {
    'anvil': anvil, 'bag': bag, 'bars': bars, 'bolt': bolt, 'book': book, 'cards': cards, 'chest': chest, 'claws': claws,
    'columns': columns, 'compass': compass, 'coins': coins, 'cross': cross, 'dividers': dividers, 'door': door, 'funnel': funnel,
    'gear': gear, 'gem': gem, 'hammer': hammer, 'heads': heads, 'helm': helm, 'horns': horns, 'house': house, 'info': info,
    'laurel': laurel, 'list': listg, 'lootarrow': lootarrow, 'magnifier': magnifier, 'map': mapg, 'note': note, 'orbs': orbs,
    'pack': pack, 'peaks': peaks, 'pick': pick, 'pouch': pouch, 'power': power, 'rift': rift, 'salvage': salvage, 'scales': scales,
    'scroll': scroll, 'sellcoin': sellcoin, 'shirt': shirt, 'sliders': sliders, 'split': split, 'stall': stall, 'star': star,
    'stopwatch': stopwatch, 'swirl': swirl, 'swords': swords, 'terminal': terminal, 'tome': tome, 'tower': tower, 'tree': tree,
    'trio': trio, 'trophy': trophy,
}


def mask(name, size):
    """the glyph as an L image of size x size (LANCZOS from the 12x supersampled grid)"""
    g = G()
    _SHAPES[name](g)
    return g.im.resize((size, size), Image.LANCZOS)
