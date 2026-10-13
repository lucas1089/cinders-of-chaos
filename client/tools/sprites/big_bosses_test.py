#!/usr/bin/env python3
"""Unit tests of big_bosses.py (the post-processing of the bigger guardian looks). python3 -I big_bosses_test.py
Builds one look from made-up raw results and base frames in a temporary folder (no pair, no PixelLab), then checks the
committed spec, sheets and rows."""
import base64, csv, io, json, os, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
import big_bosses as BB

fails = 0


def ok(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL', what)


def blob(size, box, rgb):
    a = np.zeros((size, size, 4), np.uint8)
    x0, y0, x1, y1 = box
    a[y0:y1, x0:x1, :3] = rgb
    a[y0:y1, x0:x1, 3] = 255
    return a


def png(a):
    b = io.BytesIO()
    Image.fromarray(a, 'RGBA').save(b, 'PNG')
    return {'type': 'base64', 'base64': base64.b64encode(b.getvalue()).decode()}


# the layout: idle 4, walk 8, 4x4, exact 128, 300 ms per phase
lay = BB.layout()
ok([g['phases'] for g in lay['groups']] == [4, 8] and [g['type'] for g in lay['groups']] == [0, 1], 'groups')
ok(all(g['w'] == 4 and g['h'] == 4 and g['exact'] == 128 for g in lay['groups']), '4x4, exact 128')
r = BB.things_row({'key': 'k', 'name': 'N'})
ok(r['phases'] == '4+8' and r['w'] == 4 and r['atlas'] == 'big_bosses/k', 'things row: ' + str(r))
ok(r['extra'].startswith('layers=1|gtypes=0+1|exact=128+128|durs0=300:300/300:300/300:300/300:300|anim0=0:0:0'),
   'things row extra: ' + r['extra'])

# on_canvas anchors bottom-right
c = BB.on_canvas(blob(96, (10, 10, 20, 20), (50, 60, 70)))
ok(c.shape == (128, 128, 4) and c[42, 42, 3] == 255 and c[41, 41, 3] == 0, 'a 96 px frame lands bottom-right')

# a whole look from made-up results: a 3x3 base, a repaint, walk / idle results that drift 2 px right
with tempfile.TemporaryDirectory() as t:
    base, raw = os.path.join(t, 'base'), os.path.join(t, 'raw')
    os.makedirs(os.path.join(base, '9001'))
    os.makedirs(raw)
    blay = {'look': 9001, 'flags': {}, 'groups': [
        {'type': 0, 'w': 3, 'h': 3, 'exact': 32, 'phases': 1, 'anim': None},
        {'type': 1, 'w': 3, 'h': 3, 'exact': 32, 'phases': 2, 'anim': [0, 0, 0, [300] * 4]}]}
    json.dump(blay, open(os.path.join(base, '9001', 'layout.json'), 'w'))
    for g, n in ((0, 1), (1, 2)):
        for d in range(4):
            for p in range(n):
                Image.fromarray(blob(96, (30, 30, 80, 90), (90, 40, 30))).save(
                    os.path.join(base, '9001', f'g{g}_d{d}_p{p}.png'))
    src = blob(128, (30, 20, 100, 118), (120, 120, 130))
    src[50:54, 60:64, :3] = (60, 240, 250)          # a glowing eye (accent)
    json.dump({'last_response': {'images': [png(src)] * 4}}, open(os.path.join(raw, 'up.json'), 'w'))
    drift = BB.RV.shift(src, 2, 0)
    for d in range(4):
        json.dump({'last_response': {'images': [png(src)] + [png(drift)] * 8}}, open(os.path.join(raw, f'w{d}.json'), 'w'))
        json.dump({'last_response': {'images': [png(src)] + [png(drift)] * 4}}, open(os.path.join(raw, f'i{d}.json'), 'w'))
    v = {'key': 'test', 'look': 9100, 'base': 9001, 'name': 'Test', 'colours': 16, 'accents': 2, 'outline': 80,
         'up': {'tag': 'up'}, 'walk': [{'tag': f'w{d}'} for d in range(4)], 'idle': [{'tag': f'i{d}'} for d in range(4)]}
    frames, rep = BB.process(v, base, raw)
    ok(len(frames) == 4 * 12, 'every direction has 4 idle and 8 walk frames')
    ok(all(rep['shift'][d] == (-2, 0) for d in range(4)), 'the drift is undone per direction: %s' % rep['shift'])
    ok(BB.RV.feet(frames[(1, 2, 0)]) == BB.feet_line(base, 9001), 'the lowest row is the base feet line')
    ok(set(np.unique(frames[(0, 0, 0)][..., 3]).tolist()) <= {0, 255}, 'alpha 0 / 255')
    cols = {tuple(x) for f in frames.values() for x in f[f[..., 3] > 0][:, :3].tolist()}
    ok(len(cols) <= 18, 'one small palette: %d colours' % len(cols))
    near = min(sum((a - b) ** 2 for a, b in zip(c, (60, 240, 250))) for c in cols)
    ok(near < 400, 'the glowing eye survives the palette')
    sh = BB.RV.sheet(BB.layout(), frames)
    ok(sh.shape == (12 * 128, 4 * 128, 4), 'sheet: 12 rows of 4 directions')

# a stride walk: frames 0, 2, 4, 6 of each half, the halves' first frames are the key poses
with tempfile.TemporaryDirectory() as t:
    for tag, base_v in (('A', 10), ('B', 100)):
        fr = [blob(128, (40, 40, 90, 120), (base_v + i, 0, 0)) for i in range(9)]
        json.dump({'last_response': {'images': [png(f) for f in fr]}}, open(os.path.join(t, tag + '.json'), 'w'))
    w, keys = BB.walk_frames({'stride': [{'tag': 'A'}, {'tag': 'B'}]}, t)
    ok([int(f[60, 60, 0]) for f in w] == [10, 12, 14, 16, 100, 102, 104, 106], 'stride frame order')
    ok([int(k[60, 60, 0]) for k in keys] == [10, 100], 'stride key poses')
    w, keys = BB.walk_frames({'tag': 'A'}, t)
    ok([int(f[60, 60, 0]) for f in w] == list(range(11, 19)) and keys == [], 'plain walk: frames 1-8')

# loose props away from the body are dropped, the body and what is near it stay
body = blob(128, (40, 40, 90, 120), (100, 100, 100))
a = body.copy()
a[2:10, 2:10] = (250, 250, 250, 255)      # a stray moon in the corner
a[36:39, 50:60] = (200, 200, 255, 255)    # a spark touching the top of the body (inside the reach)
c = BB.clip_to(a, body, 8)
ok(not c[2:10, 2:10, 3].any(), 'a far prop is dropped')
ok(c[37, 55, 3] == 255 and c[80, 60, 3] == 255, 'the body and a spark next to it stay')
ok(BB.grow(np.eye(5, dtype=bool), 1)[0, 1], 'grow dilates')

# the committed spec, sheets and rows agree (no pair or raw results needed)
if os.path.exists(BB.SPEC):
    ok(BB.cmd_check(type('A', (), {'spec': BB.SPEC})()) == 0, 'big_bosses.py check passes')
    spec = BB.load_spec()
    with open(BB.OUT_CSV, newline='') as fh:
        rows = list(csv.DictReader(fh))
    ok([x['key'] for x in rows] == [v['key'] for v in sorted(spec['looks'], key=lambda v: v['look'])], 'rows in look order')

print('big_bosses tests:', 'ok' if not fails else f'{fails} failed')
sys.exit(1 if fails else 0)
