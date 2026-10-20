#!/usr/bin/env python3
"""Tests of compose_outfit.py with small synthetic things (no real pair needed).

python3 -I client/tools/sprites/compose_outfit_test.py      (numpy and Pillow: system packages, python3-numpy python3-pil)
"""
import csv
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402
import compose_outfit as co  # noqa: E402

FAILS = []
A, B, C = (200, 30, 30, 255), (30, 200, 30, 255), (30, 30, 200, 255)
YEL, RED = (255, 255, 0, 255), (255, 0, 0, 255)


def expect(cond, what):
    if not cond:
        FAILS.append(what)
        print('FAIL', what)


class Synth:
    """a source thing drawn by a function f(group, x, y, z, layer, phase) -> RGBA array (h*32, w*32)."""

    def __init__(self, f, w=1, h=1, layers=1, phases=(1,), gtypes=None, py=1, pz=1, px=4, disp=(0, 0), bones=None,
                 label='synth'):
        self.f, self.label, self.disp, self.bones = f, label, disp, bones
        self.light, self.animate_always = None, False
        self.groups = []
        for i, n in enumerate(phases):
            g = co.SGroup()
            g.gtype = (gtypes or list(range(len(phases))))[i]
            g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases = w, h, 32 * max(w, h), layers, px, py, pz, n
            g.anim = (0, 0, 0, (100,) * (2 * n)) if n > 1 else None
            g.sprites = ()
            self.groups.append(g)

    def frame(self, gi, x, y, z, layer, phase):
        g = self.groups[gi]
        return self.f(gi, x, y, z, layer, phase, g.w, g.h)


def block(colour, x0, y0, x1, y1, w=1, h=1):
    a = np.zeros((h * 32, w * 32, 4), np.uint8)
    a[y0:y1, x0:x1] = colour
    return a


class FakePairs:
    def __init__(self, sources):
        self.sources = sources

    def source(self, src, opts, spec_dir, label):
        return self.sources[src]


def compose(spec, sources):
    s = co.validate(spec)
    return co.Composer(s, FakePairs(sources), '.').compose()


def px(comp, key, x, y, which=0):
    return tuple(int(v) for v in comp.frames[key][which][y, x])


def base_src(**kw):
    """1x1 base: an A block at 8..16, mask yellow on it (2 layers)."""
    def f(gi, x, y, z, layer, ph, w, h):
        return block(YEL if layer else A, 8, 8, 16, 16)
    return Synth(f, layers=2, **kw)


def test_offsets():
    lay = Synth(lambda *a: block(B, 8, 8, 12, 12))
    spec = {'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'offset': [4, 2]}]}
    c = compose(spec, {'live:outfit:1': base_src(), 'live:outfit:2': lay})
    expect((c.w, c.h) == (1, 1), f'size stays 1x1: {(c.w, c.h)}')
    expect(px(c, (0, 0, 2, 0, 0), 12, 10) == B and px(c, (0, 0, 2, 0, 0), 9, 9) == A, 'offset [4, 2] moves the layer')
    # per direction offset
    spec['layers'][1]['offset'] = {'north': [-4, 0], 'south': [4, 4]}
    c = compose(spec, {'live:outfit:1': base_src(), 'live:outfit:2': lay})
    expect(px(c, (0, 0, 0, 0, 0), 4, 8) == B and px(c, (0, 0, 2, 0, 0), 12, 12) == B and px(c, (0, 0, 1, 0, 0), 8, 8) == B,
           'per-direction offsets (east has none)')
    # displacement difference: a layer with displacement 8 is drawn 8 px further up / left than the base (0)
    lay8 = Synth(lambda *a: block(B, 16, 16, 20, 20), disp=(8, 8))
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2'}]},
                {'live:outfit:1': base_src(), 'live:outfit:2': lay8})
    expect(px(c, (0, 0, 2, 0, 0), 8, 8) == B, 'layer displacement is honoured')
    # growth up / left
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'offset': [-40, -40]}]},
                {'live:outfit:1': base_src(), 'live:outfit:2': lay})
    expect((c.w, c.h) == (2, 2), f'content up / left grows the size: {(c.w, c.h)}')   # block at -32..-28
    expect(px(c, (0, 0, 2, 0, 0), 32 + 8, 32 + 8) == A and px(c, (0, 0, 2, 0, 0), 0, 0) == B, 'the base keeps its place at the bottom-right tile')
    # past the right edge: auto lowers the displacement, "base" refuses
    spec = {'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'offset': [30, 0]}]}
    c = compose(spec, {'live:outfit:1': base_src(), 'live:outfit:2': lay})
    expect(c.disp == (-10, 0) and c.notes, f'auto displacement lowered by the overflow: {c.disp}')
    spec['displacement'] = 'base'
    try:
        compose(spec, {'live:outfit:1': base_src(), 'live:outfit:2': lay})
        expect(False, 'content past the right edge with displacement "base" must stop')
    except co.SpecError:
        pass
    # fixed size too small
    try:
        compose({'key': 't', 'size': [1, 1], 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'offset': [-40, 0]}]},
                {'live:outfit:1': base_src(), 'live:outfit:2': lay})
        expect(False, 'a fixed size that does not fit must stop')
    except co.SpecError:
        pass


def test_order_and_flip():
    def lay_f(gi, x, y, z, layer, ph, w, h):
        return block(B if x == 1 else C, 4, 4, 20, 20)     # east frame B, others C
    spec = {'key': 't', 'layers': [{'src': 'live:outfit:1'},
                                   {'src': 'live:outfit:2', 'order': {'north': 'front', 'south': 'back'}}]}
    srcs = {'live:outfit:1': base_src(), 'live:outfit:2': Synth(lay_f)}
    c = compose(spec, srcs)
    expect(px(c, (0, 0, 0, 0, 0), 10, 10) == C, 'north: layer in front of the base')
    expect(px(c, (0, 0, 2, 0, 0), 10, 10) == A, 'south: layer behind the base')
    expect(px(c, (0, 0, 2, 0, 0), 5, 5) == C, 'south: the layer shows where the base is transparent')
    # wings role: behind facing south / east, in front north / west, 6 px right / down
    spec = {'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'role': 'wings'}]}
    c = compose(spec, srcs)
    L = c.spec['layers'][1]
    expect(L['order'] == ['front', 'back', 'back', 'front'], f'wings order {L["order"]}')
    expect(c.offset(L, c.sources[1], 2, 0) == (6, 6), 'wings 6 px right / down')
    expect(c.offset(L, c.sources[1], 1, 1) == (0, 4), 'wings mounted east shift')
    # flip: west draws the east frame mirrored about the tile centre
    spec = {'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'flip': {'west': 'east'},
                                                              'order': 'back'}]}
    lay = Synth(lambda gi, x, y, z, layer, ph, w, h: block(B if x == 1 else C, 2, 4, 6, 8))
    c = compose(spec, {'live:outfit:1': base_src(), 'live:outfit:2': lay})
    # axis = disp - 16 in anchor coordinates = pixel 16 of the 1x1 canvas: 2..5 -> 26..29
    expect(px(c, (0, 0, 3, 0, 0), 27, 5) == B and px(c, (0, 0, 3, 0, 0), 3, 5)[3] == 0, 'west = east mirrored')
    expect(px(c, (0, 0, 1, 0, 0), 3, 5) == B, 'east itself is not mirrored')


def test_opacity_and_frames():
    lay = Synth(lambda *a: block(B, 20, 20, 24, 24))
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'opacity': 0.5}]},
                {'live:outfit:1': base_src(), 'live:outfit:2': lay})
    expect(px(c, (0, 0, 2, 0, 0), 21, 21) == (30, 200, 30, 128), f'opacity 0.5: {px(c, (0, 0, 2, 0, 0), 21, 21)}')
    over_base = Synth(lambda *a: block(B, 8, 8, 12, 12))
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'opacity': 0.5}]},
                {'live:outfit:1': base_src(), 'live:outfit:2': over_base})
    got = px(c, (0, 0, 2, 0, 0), 9, 9)
    expect(got[3] == 255 and abs(got[0] - 115) <= 1 and abs(got[1] - 115) <= 1, f'half-transparent layer blends: {got}')
    expect(px(c, (0, 0, 2, 0, 0), 9, 9, 1)[3] == 0, 'half cover (alpha 128) clears the base mask')
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'opacity': 0.4}]},
                {'live:outfit:1': base_src(), 'live:outfit:2': over_base})
    expect(px(c, (0, 0, 2, 0, 0), 9, 9, 1) == YEL, 'below half cover the base mask stays')

    colours = [(10 * (p + 1), 0, 0, 255) for p in range(3)]
    lay = Synth(lambda gi, x, y, z, layer, ph, w, h: block(colours[ph], 0, 0, 4, 4), phases=(3,))
    base4 = base_src(phases=(4,))

    def seq(mode):
        c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'frames': mode}]},
                    {'live:outfit:1': base4, 'live:outfit:2': lay})
        return [colours.index(px(c, (0, p, 2, 0, 0), 1, 1)) for p in range(4)]
    expect(seq('loop') == [0, 1, 2, 0], f'loop {seq("loop")}')
    expect(seq('hold') == [0, 1, 2, 2], f'hold {seq("hold")}')
    expect(seq('repeat') == [0, 0, 1, 2], f'repeat {seq("repeat")}')
    expect(seq('still') == [0, 0, 0, 0], 'still')
    expect(seq([2, 1, 0, 1]) == [2, 1, 0, 1], 'explicit list')
    try:
        seq([0, 1])
        expect(False, 'a phase list of the wrong length must stop')
    except co.SpecError:
        pass
    # per group: the walking group picks the layer's idle group
    lay2 = Synth(lambda gi, x, y, z, layer, ph, w, h: block(B if gi == 0 else C, 0, 0, 4, 4), phases=(1, 2))
    base2 = base_src(phases=(1, 2))
    spec = {'key': 't', 'layers': [{'src': 'live:outfit:1'},
                                   {'src': 'live:outfit:2', 'frames': {'walk': {'group': 'idle', 'phases': 'still'}}}]}
    c = compose(spec, {'live:outfit:1': base2, 'live:outfit:2': lay2})
    expect(px(c, (1, 1, 2, 0, 0), 1, 1) == B and px(c, (0, 0, 2, 0, 0), 1, 1) == B, 'walk group mapped onto the idle group')
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2'}]},
                {'live:outfit:1': base2, 'live:outfit:2': lay2})
    expect(px(c, (1, 1, 2, 0, 0), 1, 1) == C, 'by default each group uses the layer group of its type')
    # output groups from the spec
    c = compose({'key': 't', 'groups': [{'type': 0, 'phases': 6, 'ms': 120}], 'layers': [{'src': 'live:outfit:1'}]},
                {'live:outfit:1': base4})
    expect(c.groups == [(0, 6, (0, 0, 0, (120,) * 12))] and (0, 5, 0, 0, 0) in c.frames, f'spec groups {c.groups}')


def test_masks():
    lay = Synth(lambda *a: block(B, 12, 8, 20, 16))                      # covers the right half of A and beyond
    srcs = {'live:outfit:1': base_src(), 'live:outfit:2': lay}
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2'}]}, srcs)
    k = (0, 0, 2, 0, 0)
    expect(c.layers_out == 2, 'base mask kept: 2 layers')
    expect(px(c, k, 9, 9, 1) == YEL and px(c, k, 13, 9, 1)[3] == 0 and px(c, k, 18, 9, 1)[3] == 0,
           'an uncoloured front layer clears the mask under it')
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'mask': 'keep'}]}, srcs)
    expect(px(c, k, 13, 9, 1) == YEL, 'mask "keep" leaves the base mask')
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'order': 'back'}]}, srcs)
    expect(px(c, k, 13, 9, 1) == YEL and px(c, k, 18, 9, 1)[3] == 0, 'a back layer keeps the base mask, adds none')
    own = Synth(lambda gi, x, y, z, layer, ph, w, h: block(RED if layer else B, 12, 8, 20, 16), layers=2)
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'mask': 'own'}]},
                {'live:outfit:1': base_src(), 'live:outfit:2': own})
    expect(px(c, k, 13, 9, 1) == RED and px(c, k, 18, 9, 1) == RED and px(c, k, 9, 9, 1) == YEL, 'a layer with its own mask')
    one = Synth(lambda *a: block(A, 8, 8, 16, 16))
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2'}]},
                {'live:outfit:1': one, 'live:outfit:2': lay})
    expect(c.layers_out == 1, 'no mask anywhere: 1 layer')
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'mask': 'own'}]},
                {'live:outfit:1': one, 'live:outfit:2': own})
    expect(c.layers_out == 2 and px(c, k, 9, 9, 1)[3] == 0 and px(c, k, 13, 9, 1) == RED,
           'a one-layer base gets a mask layer from a layer with its own mask')
    try:
        compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'mask': 'own'}]}, srcs)
        expect(False, 'mask own on a one-layer source must stop')
    except co.SpecError:
        pass
    # addon patterns: front layers are cut out of them, back layers are not drawn there
    def base_add(gi, x, y, z, layer, ph, w, h):
        return block(YEL if layer else (A if y == 0 else C), 8, 8, 16, 16)
    srcs = {'live:outfit:1': Synth(base_add, layers=2, py=3), 'live:outfit:2': lay}
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2'}]}, srcs)
    expect(px(c, (0, 0, 2, 1, 0), 9, 9) == C and px(c, (0, 0, 2, 1, 0), 13, 9)[3] == 0
           and px(c, (0, 0, 2, 1, 0), 18, 9)[3] == 0, 'addon pattern: cut where a front layer covers, layer not drawn')
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'order': 'back'}]}, srcs)
    expect(px(c, (0, 0, 2, 1, 0), 13, 9) == C, 'addon pattern: a back layer does not cut it')
    # mount patterns: a rider uses its mounted pattern and the base's seat
    rider = Synth(lambda gi, x, y, z, layer, ph, w, h: block(B if z == 1 else C, 4, 4, 8, 8), pz=2)
    mount = Synth(lambda *a: block(A, 0, 24, 32, 32), bones=(1, -2, 3, -4, 5, -6, 7, -8), disp=(0, 0))
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'role': 'rider'}]},
                {'live:outfit:1': mount, 'live:outfit:2': rider})
    top = (c.h - 1) * 32                                   # west's seat (7, -8) grows the look by a tile
    expect(px(c, (0, 0, 2, 0, 0), 4 + 3, top + 4 - 4) == B, 'rider: mounted pattern at the south seat (3, -4)')
    expect(c.offset(c.spec['layers'][1], c.sources[1], 1, 0) == (5, -6), 'rider: east seat')
    expect(c.flags() == 'bones:1:-2:3:-4:5:-6:7:-8', f'flags copy the seat: {c.flags()}')


def test_addon_map():
    """addons {"1": 2}: a layer drawn only on output addon pattern 1, from its own pattern 2 (with its mask)."""
    def base_add(gi, x, y, z, layer, ph, w, h):
        return block(YEL if layer else (A if y == 0 else C), 8, 8, 16, 16) if y < 2 else block(A, 0, 0, 0, 0)

    def part(gi, x, y, z, layer, ph, w, h):                 # pattern 2 holds a hood at 4..8 (mask red), others blank
        return block(RED if layer else B, 4, 4, 8, 8) if y == 2 else block(A, 0, 0, 0, 0)
    srcs = {'live:outfit:1': Synth(base_add, layers=2, py=3), 'live:outfit:2': Synth(part, layers=2, py=3)}
    c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'},
                                        {'src': 'live:outfit:2', 'addons': {'1': 2}, 'mask': 'own'}]}, srcs)
    expect(px(c, (0, 0, 2, 0, 0), 5, 5)[3] == 0, 'addon map: not drawn on pattern 0')
    expect(px(c, (0, 0, 2, 1, 0), 5, 5) == B and px(c, (0, 0, 2, 1, 0), 5, 5, 1) == RED,
           'addon map: drawn on pattern 1 from its pattern 2, with its mask')
    expect(px(c, (0, 0, 2, 1, 0), 9, 9) == C, 'addon map: the base addon pattern is kept')
    expect(px(c, (0, 0, 2, 2, 0), 5, 5)[3] == 0, 'addon map: not drawn on an unlisted pattern')
    for bad in ({'1': 5}, {'x': 1}, {}):
        try:
            compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'addons': bad}]}, srcs)
            expect(False, f'addon map {bad} must stop')
        except co.SpecError:
            pass
    try:
        compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'addons': {'3': 1}}]}, srcs)
        expect(False, 'addon map: an output pattern the base lacks must stop')
    except co.SpecError:
        pass


def test_glow():
    lay = Synth(lambda *a: block(B, 12, 12, 16, 16))
    for radius in (1, 2, 3):
        g = {'palette': 'ember', 'step': 5, 'radius': radius, 'strength': 1.0}
        c = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'glow': g, 'order': 'back'}]},
                    {'live:outfit:1': Synth(lambda *a: block(A, 0, 0, 2, 2)), 'live:outfit:2': lay})
        col, mask = c.frames[(0, 0, 2, 0, 0)]
        PAL, ALPHA = co.palettes()
        ramp = {tuple(v) for v in PAL['ember'][0]}
        allowed_alpha = set(ALPHA['glow'])
        ys, xs = np.nonzero(col[..., 3] > 0)
        glow_px = [(x, y) for x, y in zip(xs, ys) if not (12 <= x < 16 and 12 <= y < 16) and not (x < 2 and y < 2)]
        ok_dist = all(max(0, 12 - x, x - 15) ** 2 + max(0, 12 - y, y - 15) ** 2 <= (radius + 0.5) ** 2 for x, y in glow_px)
        ok_col = all(tuple(col[y, x, :3]) in ramp and col[y, x, 3] in allowed_alpha for x, y in glow_px)
        expect(glow_px and ok_dist, f'glow radius {radius}: within the radius ({len(glow_px)} px)')
        expect(ok_col, f'glow radius {radius}: palette colours and crisp glow alpha levels')
        expect(all(tuple(col[y, x]) == B for y in range(12, 16) for x in range(12, 16)), 'glow never covers the layer')
        expect(not mask[..., 3].any(), 'glow adds nothing to the mask')
    g = {'palette': 'ember', 'step': 5, 'radius': 2, 'strength': 0.4}
    weak = compose({'key': 't', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'glow': g}]},
                   {'live:outfit:1': Synth(lambda *a: block(A, 0, 0, 2, 2)), 'live:outfit:2': lay})
    n_weak = int((weak.frames[(0, 0, 2, 0, 0)][0][..., 3] > 0).sum())
    expect(16 + 4 < n_weak < 16 + 4 + 40, f'lower strength thins the glow ({n_weak} px)')


def test_validation():
    good = {'key': 'ok', 'layers': [{'src': 'live:outfit:1'}]}
    co.validate(good)
    bad = [
        ({'key': 'Bad Key', 'layers': [{'src': 'live:outfit:1'}]}, 'key'),
        ({'key': 'k'}, 'layers'),
        ({'key': 'k', 'layers': [{'src': 'outfit:1'}]}, 'src'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1', 'colour': 1}]}, 'unknown keys'),
        ({'key': 'k', 'bogus': 1, 'layers': [{'src': 'live:outfit:1'}]}, 'unknown keys'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1', 'base': True}, {'src': 'live:outfit:2', 'base': True}]}, 'base'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'order': 'middle'}]}, 'front or back'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'order': {'up': 'front'}}]}, 'direction'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'offset': [1]}]}, '[x, y]'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'opacity': 0}]}, 'opacity'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'glow': {'palette': 'pink'}}]}, 'palette'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'glow': {'palette': 'ember', 'radius': 5}}]}, 'radius'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'frames': 'bounce'}]}, 'mode'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'frames': {'run': 'loop'}}]}, 'keys'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'flip': {'west': 'up'}}]}, 'flip'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'role': 'cape'}]}, 'role'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'role': 'aura', 'mask': 'own'}]}, 'aura'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1', 'role': 'wings'}]}, 'base layer'),
        ({'key': 'k', 'layers': [{'src': 'live:outfit:1', 'order': 'back'}]}, 'base layer'),
        ({'key': 'k', 'size': [9, 1], 'layers': [{'src': 'live:outfit:1'}]}, 'size'),
        ({'key': 'k', 'groups': [{'type': 0, 'phases': 2, 'durs': [[100, 50], [1, 1]]}], 'layers': [{'src': 'live:outfit:1'}]}, 'durs'),
        ({'key': 'k', 'groups': [{'type': 1, 'phases': 2}, {'type': 1, 'phases': 2}], 'layers': [{'src': 'live:outfit:1'}]}, 'same type'),
        ({'key': 'k', 'flags': {'light': [1, 300]}, 'layers': [{'src': 'live:outfit:1'}]}, 'light'),
        ({'key': 'k', 'colours': {'head': 1}, 'layers': [{'src': 'live:outfit:1'}]}, 'colours'),
        ({'key': 'k', 'layers': [{'src': 'png:x.png'}]}, 'png_size'),
    ]
    for spec, needle in bad:
        try:
            co.validate(spec)
            expect(False, f'spec must be refused ({needle}): {spec}')
        except co.SpecError as e:
            expect(needle in str(e), f'error for {needle!r} says so: {e}')
    for f in sorted(os.listdir(os.path.join(HERE, 'compose'))):
        if f.endswith('.json'):
            try:
                co.load_spec(os.path.join(HERE, 'compose', f))
            except co.SpecError as e:
                expect(False, f'example spec {f}: {e}')
    expect(co.outfit_colour(0) == (255, 255, 255) and co.outfit_colour(94)[0] > 200, 'outfit colours')


def test_import_roundtrip(tmp):
    """sheet + row through import_art_things.py onto a tiny pair; the guard and the importer's checks pass."""
    import check_pair_test as cpt
    recs = [cpt.record({0: (1, 2, 3, 255)})]
    items = [cpt.entry(b'', [cpt.group([1])])]
    outfits = [cpt.entry(b'', [cpt.group([1] * 4, px=4, gtype=0)], outfit=True)]
    effects = [cpt.entry(b'', [cpt.group([1])])]
    missiles = [cpt.entry(b'', [cpt.group([1] * 9, px=3, py=3)])]
    pair = os.path.join(tmp, 'pair')
    os.makedirs(pair)
    open(os.path.join(pair, 'Tibia.dat'), 'wb').write(cpt.dat_bytes(items, outfits, effects, missiles))
    open(os.path.join(pair, 'Tibia.spr'), 'wb').write(cpt.spr_bytes(recs))
    # a two-frame-group base with a mask, addons and mount patterns, a glowing layer reaching up / left
    base = base_src(phases=(1, 2), gtypes=[0, 1], py=2, pz=2, disp=(8, 8))
    lay = Synth(lambda gi, x, y, z, layer, ph, w, h: block(B, 0, 0, 10 + x, 10 + ph, w, h), w=2, h=2, phases=(3,), gtypes=[1])
    spec = {'key': 'roundtrip', 'colours': {'head': 1, 'body': 2, 'legs': 3, 'feet': 4},
            'layers': [{'src': 'live:outfit:1'}, {'src': 'live:outfit:2', 'role': 'wings',
                                                  'glow': {'palette': 'void', 'radius': 1}}]}
    comp = compose(spec, {'live:outfit:1': base, 'live:outfit:2': lay})
    out = os.path.join(tmp, 'out')
    os.makedirs(out)
    from PIL import Image
    Image.fromarray(comp.sheet(), 'RGBA').save(os.path.join(out, 'roundtrip.png'))
    co.write_csv(os.path.join(out, 'things.csv'), comp.row('roundtrip'), replace=False)
    comp.preview(os.path.join(out, 'preview.png'))
    expect(os.path.getsize(os.path.join(out, 'preview.png')) > 0, 'preview written')
    res = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'import_art_things.py'),
                          '--ours-dat', os.path.join(pair, 'Tibia.dat'), '--ours-spr', os.path.join(pair, 'Tibia.spr'),
                          '--out-dir', os.path.join(tmp, 'new'), '--things', os.path.join(out, 'things.csv'),
                          '--first-outfit', '3', '--outfits-out', os.path.join(tmp, 'outfits.csv')],
                         capture_output=True, text=True)
    expect(res.returncode == 0 and 'append-only guard passed' in res.stdout,
           f'import_art_things.py takes the composed row: {res.stdout[-800:]} {res.stderr[-1500:]}')
    if res.returncode:
        return
    import check_pair as cp
    data = open(os.path.join(tmp, 'new', 'Tibia.dat'), 'rb').read()
    _, counts, things, _ = cp.parse_dat(data)
    t = things['outfit'][2]
    g = t.groups
    expect(counts[1] == 3 and [x.gtype for x in g] == [0, 1] and [x.phases for x in g] == [1, 2], 'groups kept')
    expect((g[0].w, g[0].h, g[0].layers, g[0].px, g[0].py, g[0].pz) == (comp.w, comp.h, 2, 4, 2, 2), 'layout kept')
    expect(t.flag('displacement') == comp.disp, f'displacement {t.flag("displacement")} == {comp.disp}')
    rows = list(csv.DictReader(open(os.path.join(tmp, 'outfits.csv'))))
    expect(rows and rows[0]['head'] == '1', 'outfits csv has the colours')
    # a second import gives the same bytes (deterministic)
    res2 = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'import_art_things.py'),
                           '--ours-dat', os.path.join(pair, 'Tibia.dat'), '--ours-spr', os.path.join(pair, 'Tibia.spr'),
                           '--out-dir', os.path.join(tmp, 'new2'), '--things', os.path.join(out, 'things.csv'),
                           '--first-outfit', '3'], capture_output=True, text=True)
    expect(res2.returncode == 0 and open(os.path.join(tmp, 'new2', 'Tibia.dat'), 'rb').read() == data,
           'deterministic import')
    # the same row with mode=replace and look=1 rewrites outfit 1 in place: no outfit appended, sprites appended
    rows = list(csv.DictReader(open(os.path.join(out, 'things.csv'), newline='')))

    def replace_run(name, extra):
        r = dict(rows[0], mode='replace', extra=(rows[0]['extra'] + extra).lstrip('|'))
        path = os.path.join(out, name + '.csv')
        with open(path, 'w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator='\n')
            w.writeheader()
            w.writerow(r)
        return subprocess.run([sys.executable, '-I', os.path.join(HERE, 'import_art_things.py'),
                               '--ours-dat', os.path.join(pair, 'Tibia.dat'), '--ours-spr', os.path.join(pair, 'Tibia.spr'),
                               '--out-dir', os.path.join(tmp, name), '--things', path], capture_output=True, text=True)
    res3 = replace_run('rep', '|look=1')
    expect(res3.returncode == 0 and 'replaced 1' in res3.stdout and 'append-only guard passed' in res3.stdout,
           f'mode=replace look=1 rewrites outfit 1: {res3.stdout[-800:]} {res3.stderr[-1500:]}')
    if not res3.returncode:
        rdata = open(os.path.join(tmp, 'rep', 'Tibia.dat'), 'rb').read()
        _, rc, rth, _ = cp.parse_dat(rdata)
        old = open(os.path.join(pair, 'Tibia.dat'), 'rb').read()
        _, oc, oth, _ = cp.parse_dat(old)
        r1, n3 = rth['outfit'][0], things['outfit'][2]
        expect(rc == oc, f'counts unchanged by a replace: {rc} {oc}')
        expect([(x.gtype, x.w, x.h, x.layers, x.px, x.py, x.pz, x.phases) for x in r1.groups] ==
               [(x.gtype, x.w, x.h, x.layers, x.px, x.py, x.pz, x.phases) for x in n3.groups]
               and r1.flag('displacement') == comp.disp, 'outfit 1 has the new layout and flags')
        expect(all(rdata[a.start:a.end] == old[b.start:b.end] for cat in ('item', 'effect', 'missile')
                   for a, b in zip(rth[cat], oth[cat])), 'every other thing byte-identical')
    for name, extra, needle in (('rep_nolook', '', 'needs look=ID'), ('rep_far', '|look=9', 'not an outfit of the input')):
        r = replace_run(name, extra)
        expect(r.returncode != 0 and needle in (r.stdout + r.stderr), f'{name} refused ({needle}): {r.stderr[-400:]}')


def test_png_source(tmp):
    """a sheet this tool wrote is a layer of another spec (png: source)."""
    comp = compose({'key': 'a', 'layers': [{'src': 'live:outfit:1'}]}, {'live:outfit:1': base_src(phases=(1, 2))})
    from PIL import Image
    p = os.path.join(tmp, 'a.png')
    Image.fromarray(comp.sheet(), 'RGBA').save(p)
    spec = {'key': 'b', 'layers': [{'src': 'png:a.png', 'png_size': [1, 1], 'png_phases': '1+2', 'png_layers': 2}]}
    s = co.validate(spec)
    c2 = co.Composer(s, co.Pairs(), tmp).compose()
    expect(all(np.array_equal(c2.frames[k][0], comp.frames[k][0]) and np.array_equal(c2.frames[k][1], comp.frames[k][1])
               for k in comp.frames), 'png source round-trips the frames and the mask')


def main():
    tmp = tempfile.mkdtemp(prefix='compose_outfit_test_')
    try:
        for f in (test_offsets, test_order_and_flip, test_opacity_and_frames, test_masks, test_addon_map, test_glow,
                  test_validation):
            f()
        test_png_source(tmp)
        test_import_roundtrip(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if FAILS:
        print(f'{len(FAILS)} failures')
        return 1
    print('compose_outfit_test: all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
