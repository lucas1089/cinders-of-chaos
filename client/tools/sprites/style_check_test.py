#!/usr/bin/env python3
"""python3 -I client/tools/sprites/style_check_test.py : style_check.py on synthetic sprites (a good one passes, each
broken one fails for its own reason), the owner's seven sheets against their own themes, the CLI exit codes.
Needs numpy and Pillow (CI: /tmp/fxenv)."""
import contextlib
import io
import os
import shutil
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import style_check as S  # noqa: E402

failed = 0
DATA = S.load_palettes()
THR = DATA['thresholds']
THEME = 'cinderwrought'
PAL = np.array([S.unhex(h) for h in DATA['themes'][THEME]['palette']], dtype=np.uint8)
REF = DATA['themes'][THEME]['light']
OUTLINE = S.unhex(DATA['themes'][THEME]['outline'][0])


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def kinds(reasons):
    return sorted({r.split(':')[0] for r in reasons})


def sprite(light='top', outline=1, palette=PAL):
    """a shaded round shield: 1 px near-black outline, lit from the top, every colour from the palette."""
    yy, xx = np.mgrid[0:32, 0:32]
    disc = (xx - 15.5) ** 2 + (yy - 15.5) ** 2 < 13 ** 2
    target = 200.0 - 6.0 * (yy - 3) if light == 'top' else 200.0 - 6.0 * (28 - yy)
    lum = S.luma(palette)
    idx = np.abs(lum[None, None, :] - target[..., None]).argmin(-1)
    c = np.zeros((32, 32, 4), np.uint8)
    c[disc, :3] = palette[idx][disc]
    c[disc, 3] = 255
    rim = disc & ~S.erode(disc)
    if outline >= 1:
        c[rim, :3] = OUTLINE
    if outline >= 2:
        c[S.erode(disc) & ~S.erode(S.erode(disc)), :3] = OUTLINE
    return c


def judge(c, soft=False, pal=PAL):
    return S.judge(S.measure(c), pal, REF, THR, soft)


# ------------------------------------------------------------------------------------------------- synthetic sprites
good = sprite()
bad, warn = judge(good)
check(bad == [] and warn == [], 'the good sprite passes: %s %s' % (bad, warn))

cases = {}
c = good.copy()
c[10:14, 10:14, 3] = 160                       # semi-transparent pixels
cases['alpha'] = c
cases['light'] = sprite(light='bottom')       # lit from below
c = sprite(outline=0)                          # no outline: the rim keeps the body colours
cases['outline (none)'] = c
cases['outline (thick)'] = sprite(outline=2)  # two pixels thick
blue = good.copy()                             # another theme's colours: the channels swapped (red -> blue)
blue[..., :3] = good[..., [2, 1, 0]]
blue[(good[..., :3] == OUTLINE).all(-1), :3] = OUTLINE
cases['palette'] = blue
c = good.copy()                                # flat: two body colours
body = S.erode(c[..., 3] > 0)
c[body, :3] = PAL[len(PAL) // 2]
c[body & (np.mgrid[0:32, 0:32][0] > 16), :3] = PAL[len(PAL) // 3]
cases['colours'] = c
rng = np.random.default_rng(7)                 # speckle: every body pixel a random palette colour
c = good.copy()
inner = S.erode(body)
mid = PAL[(S.luma(PAL) > 40)]
c[inner, :3] = mid[rng.integers(0, len(mid), (32, 32))][inner]
cases['noise (speckle)'] = c
c = good.copy()                                # stray lone pixels in the corners
for y, x in ((0, 0), (0, 31), (31, 0), (31, 31)):
    c[y, x] = (200, 120, 40, 255)
cases['noise (lone pixels)'] = c
c = good.copy()                                # pinholes in the body
for y, x in ((8, 8), (8, 20), (12, 14), (16, 9), (18, 22), (22, 12), (22, 18), (24, 15)):
    c[y, x, 3] = 0
cases['noise (holes)'] = c

expect = {'alpha': ['alpha'], 'light': ['light'], 'outline (none)': ['outline'], 'outline (thick)': ['outline'],
          'palette': ['palette'], 'colours': ['colours'], 'noise (speckle)': ['noise'],
          'noise (lone pixels)': ['noise'], 'noise (holes)': ['noise']}
for name, c in cases.items():
    bad, _w = judge(c)
    check(kinds(bad) == expect[name], '%s fails for its reason only: %s' % (name, bad))
check('thick' in ' '.join(judge(cases['outline (thick)'])[0]), 'a thick outline says so')
check(any('lone' in r for r in judge(cases['noise (lone pixels)'])[0]), 'lone pixels are named')
check(any('holes' in r for r in judge(cases['noise (holes)'])[0]), 'holes are named')

# soft mode: glow alpha is fine, faint dust is not; the outline rule is off
c = good.copy()
c[S.erode(S.erode(body)), 3] = 140
check(judge(c, soft=True)[0] == [], 'soft: semi-transparent glow passes: %s' % judge(c, soft=True)[0])
c[2, 2] = (200, 120, 40, 5)
check(kinds(judge(c, soft=True)[0]) == ['alpha', 'noise'] or kinds(judge(c, soft=True)[0]) == ['alpha'],
      'soft: a faint stray pixel fails: %s' % judge(c, soft=True)[0])

# snap repairs the palette
fixed = S.snap(blue, PAL)
check('palette' not in kinds(judge(fixed)[0]), 'snap moves the colours onto the theme')
check(np.array_equal(S.snap(good, PAL), good), 'snap leaves on-palette art alone')

# ----------------------------------------------------------------------------------------------- whole images and CLI
tmp = tempfile.mkdtemp(prefix='style_check_test_')


def save(a, name, mode='RGBA'):
    path = os.path.join(tmp, name)
    Image.fromarray(a, 'RGBA').convert(mode).save(path)
    return path


def run(argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = S.main(argv)
    return code, out.getvalue()


def image_kinds(path, **kw):
    res = S.check_image(path, PAL, REF, THR, **kw)
    return sorted({k for where, bad, _w in res for k in kinds(bad)})


sheet = np.zeros((32, 96, 4), np.uint8)      # a 3-cell sheet: good, empty, good
sheet[:, 0:32] = good
sheet[:, 64:96] = good
check(image_kinds(save(sheet, 'sheet.png')) == [], 'a sheet of good sprites passes')
check(image_kinds(save(good[:30, :30].copy(), 'small.png')) == ['size'], 'a 30 x 30 image fails the grid')
big = good.repeat(2, 0).repeat(2, 1)
check('scale' in image_kinds(save(big, 'big.png'), size=64), 'an upscaled sprite fails the scale check')
keyed = good.copy()                          # magenta key colour instead of transparency, saved as RGB
keyed[keyed[..., 3] == 0] = (255, 0, 255, 255)
check(image_kinds(save(keyed, 'keyed.png', 'RGB')) == [], 'a sprite on a clean key colour passes')
dirty = keyed.copy()
dirty[0, 5] = (230, 20, 230, 255)
check(image_kinds(save(dirty, 'dirty.png', 'RGB')) == ['background'], 'a dirty key edge fails the background')
check(image_kinds(save(np.zeros((32, 32, 4), np.uint8), 'empty.png')) == ['empty'], 'an empty image is refused')

code, out = run(['check', save(good, 'good.png'), '--theme', THEME])
check(code == 0 and out.startswith('PASS'), 'CLI: a good sprite exits 0')
code, out = run(['check', save(cases['light'], 'lit.png'), '--theme', THEME])
check(code == 1 and 'FAIL light' in out, 'CLI: a broken sprite exits 1 with its reason')
pal_png = os.path.join(S.GEAR, THEME + '.png')
code, out = run(['check', save(good, 'good.png'), '--palette', pal_png])
check(code == 0, 'CLI: a palette PNG works like the theme')
with open(os.path.join(tmp, 'pal.txt'), 'w') as f:
    f.write(' '.join(S.hexc(c) for c in PAL))
code, out = run(['check', save(good, 'good.png'), '--palette', os.path.join(tmp, 'pal.txt')])
check(code == 0, 'CLI: a hex palette file works')
code, out = run(['snap', save(blue, 'blue.png'), os.path.join(tmp, 'snapped.png'), '--theme', THEME])
code, out = run(['check', os.path.join(tmp, 'snapped.png'), '--theme', THEME])
check('palette' not in out, 'CLI: snap then check: no palette failure')

# ------------------------------------------------------------------------------------------------ the owner's sheets
for key in S.THEMES:
    code, out = run(['check', os.path.join(S.GEAR, key + '.png'), '--theme', key])
    check(code == 0 and '64 cells checked, 0 failed' in out, 'owner sheet %s passes its own theme' % key)
code, out = run(['check', os.path.join(S.GEAR, 'rimewraith.png'), '--theme', 'cinderwrought'])
check(code == 1 and out.count('FAIL palette') >= 60, 'the frost sheet fails the fire palette')
check(set(DATA['themes']) == set(S.THEMES), 'style_palettes.json holds every theme')
check(all(t['cells'] == 64 for t in DATA['themes'].values()), 'every theme measured on 64 cells')

shutil.rmtree(tmp, ignore_errors=True)
print('style_check_test: %s' % ('FAILED (%d)' % failed if failed else 'ok'))
sys.exit(1 if failed else 0)
