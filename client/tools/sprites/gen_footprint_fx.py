#!/usr/bin/env python3
"""The 20 footprint effects of the footprint source (O649, joins client pair 75): cut, treated, appended after the effects of pair 74.

    python3 -I gen_footprint_fx.py build DAT SPR OUT_DIR --src DIR            # DIR: the footprint source's Tibia.dat and Tibia.spr;
                                                                               # OUT_DIR gets Tibia.dat, Tibia.spr and strips/
    python3 -I gen_footprint_fx.py build DAT SPR OUT_DIR --src DIR --write    # also writes art_import/footprint_fx.csv and .sums
    python3 -I gen_footprint_fx.py check                                       # CI, no art, no pair: table, sums, ids file agree
    python3 -I gen_footprint_fx.py ids [--check]                               # server/data/lib/chaos_footprint_fx_ids.lua
    python3 -I gen_footprint_fx.py live DAT SPR                                # the pair holds every effect at its id, pixel for pixel

The owner supplied the footprint source: the client of another server that he downloaded ("pode importar todos assim mesmo",
O649; the 20 were chosen from its 34 store footprints by numbers, O648 / O648b). Its art is never in the repository, never
shown, never sent to a web or AI service: this script reads its two files locally. Committed are this script, the table
art_import/footprint_fx.csv (one row per effect: our id and name, src = the first 12 hex of the sha256 of the source's
Tibia.dat, the source effect id, raw = the first 12 hex of the digest of the untreated strip, size, phases, durations, the
treatment keys) and art_import/footprint_fx.sums (the digest of every treated strip). `build` needs the two files;
`check` and `live` work from the table and the pair alone.

Input pair: exactly 5,333 effects (pair 74: the last effect is 5333, Malgrath's). Any other pair is refused. The 20 effects are
appended at the fixed ids 5334..5353. Each keeps its size, its phases and its per phase durations; nothing is redrawn. The
treatments (only where a measure of sprite_quality.py or of the foot point said it helps, the keys of each row in the table):
  alpha=cut   the soft alpha becomes 0 / 255 with one glow level (144): alpha >= 0.5 is 255, 0.2 up to 0.5 is 144, the rest gone
  alpha=4     a soft pulse or fade that a cut would empty: alpha snapped to 96 / 144 / 192 / 255 (below 48 gone)
  black       pure black (0, 0, 0) of a solid pixel becomes one tinted near-black, #050305 (docs/SPRITE_STYLE.md: no pure black fill)
  palette=N   the colours of all frames reduced to N (median cut), so one frame holds fewer colours
  shift=X/Y   the art moved by whole pixels toward the foot point of the target tile (x 16.5, y 20 of the tile, as the outfits
              of O585); never past the canvas
  fade=K/F    the last K phases fade linearly to F of their alpha, the alpha snapped to 255 / 192 / 144 / 96 / 64, so the print
              ends soft instead of cutting off
The send offset (dx, dy) puts the target tile, the one the footprint lies on, where the art's weight is (the client draws the bottom
right tile of an effect on the tile it is sent to, so the canvas starts w - 1 - dx tiles up and left of it).

Needs numpy and Pillow (the fx venv of CI). Deterministic: the same files give the same strips.
"""
import argparse
import csv
import hashlib
import io
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
ART = os.path.join(HERE, 'art_import')
SPEC = os.path.join(ART, 'footprint_fx.csv')
SUMS = os.path.join(ART, 'footprint_fx.sums')
LUA = os.path.join(ROOT, 'server', 'data', 'lib', 'chaos_footprint_fx_ids.lua')

NEED_EFFECTS = 5333     # the input pair (pair 74)
FIRST = 5334            # this step's effect ids, FIRST.. in table order
PAIR = 75
PREFIX = 'fp_'
SOLID = 128             # a solid pixel (sprite_quality.py counts it so for the black rule)
CUT, HALO, GLOW = 0.5, 0.2, 144
LEVELS4 = (96, 144, 192, 255)
FADE_LEVELS = (255, 192, 144, 96, 64)
NEAR_BLACK = (5, 3, 5)
FOOT = (16.5, 20.0)     # px in the target tile: where an effect's weight should lie (the O585 standing point)
FIELDS = ['id', 'name', 'title', 'src', 'eid', 'raw', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'durs', 'treat', 'note']

# (our name, our title, source effect id, treatment keys, note). The order is the order of ids (5334 first) and of O648's
# ranking. The numbers of shift= and fade= are the ones measured in O648b (foot distance, end mass against the peak).
PICKS = [
    ('fp_heart', 'Lovestruck Steps', 36, 'black;palette=64;shift=3/3;fade=6/0.74', 'heart, 1x1'),
    ('fp_note_purple', 'Violet Melody', 23, 'black', 'purple note, 1x1'),
    ('fp_note_white', 'Silver Melody', 25, 'black', 'white note, 1x1'),
    ('fp_shrine_fire', 'Shrine Flame', 80, 'shift=-6/-2', 'fire shrine, 1x1'),
    ('fp_ghost', 'Wandering Ghost', 66, 'palette=64', 'ghost, 1x1'),
    ('fp_bleeding', 'Bleeding Steps', 94, 'alpha=cut', 'bleeding, 2x2'),
    ('fp_death', "Death's Mark", 200, '', 'death, 1x1'),
    ('fp_void_steps', 'Void Steps', 668, 'black', 'void steps, 2x2'),
    ('fp_dice', 'Lucky Dice', 27, '', 'dice, 1x1'),
    ('fp_rainbow', 'Rainbow Road', 148, 'alpha=cut;shift=5/1', 'rainbow, 3x3'),
    ('fp_fairy', 'Fairy Dust', 81, 'fade=2/0.61', 'fairy, 1x1'),
    ('fp_smoke', 'Smoke Trail', 96, 'shift=6/3', 'smoke, 2x2'),
    ('fp_ice', 'Ice Patch', 42, '', 'ice, 2x2'),
    ('fp_shrine_angel', "Angel's Rest", 78, 'shift=-7/-4', 'angel shrine, 1x1'),
    ('fp_void_skull', 'Void Skulls', 666, 'black', 'void skull, 2x2'),
    ('fp_poison', 'Toxic Puddles', 21, '', 'poison, 1x1'),
    ('fp_holy_rain', 'Holy Rain', 261, '', 'holy rain, 2x2'),
    ('fp_pentagram', 'Pentagram Seals', 85, 'alpha=4;palette=64;shift=5/1;fade=4/0.58', 'pentagram, 2x2'),
    ('fp_plants', 'Overgrowth', 46, 'palette=96', 'plants, 2x2'),
    ('fp_coin', 'Coin Trail', 405, 'alpha=4;shift=6/7', 'gold coin, 2x2'),
]


def parse_treat(text):
    """'black;palette=64;shift=3/3' -> {'black': True, 'palette': 64, 'shift': (3, 3), ...}"""
    out = {}
    for tok in [t for t in text.split(';') if t]:
        k, _, v = tok.partition('=')
        if k in ('black',) and not v:
            out[k] = True
        elif k == 'alpha' and v in ('cut', '4'):
            out[k] = v
        elif k == 'palette' and v.isdigit() and 2 <= int(v) <= 256:
            out[k] = int(v)
        elif k == 'shift' and len(v.split('/')) == 2:
            out[k] = tuple(int(x) for x in v.split('/'))
        elif k == 'fade' and len(v.split('/')) == 2 and int(v.split('/')[0]) >= 1 and 0 < float(v.split('/')[1]) < 1:
            out[k] = (int(v.split('/')[0]), float(v.split('/')[1]))
        else:
            raise ValueError('treatment key %r' % tok)
    return out


def pieces():
    """the table rows that need no art"""
    out = []
    for i, (name, title, eid, treat, note) in enumerate(PICKS):
        out.append(dict(id=FIRST + i, name=name, title=title, eid=eid, treat=treat, note=note))
    return out


def table_errors(rows):
    errs = []
    ids = [int(r['id']) for r in rows]
    if ids != list(range(FIRST, FIRST + len(ids))):
        errs.append('ids are not %d.. in order' % FIRST)
    names = [r['name'] for r in rows]
    if len(set(names)) != len(names) or any(not n.startswith(PREFIX) or len(n) > 24 for n in names):
        errs.append('names: not unique or not %s* (24 characters at most)' % PREFIX)
    if len({r['eid'] for r in rows}) != len(rows):
        errs.append('a source effect is used twice')
    titles = [r['title'] for r in rows]
    if len(set(titles)) != len(titles):
        errs.append('titles are not unique')
    for r in rows:
        try:
            parse_treat(r['treat'])
        except ValueError as e:
            errs.append('%s: %s' % (r['name'], e))
    return errs


# ------------------------------------------------------------------------------------------------- the art
def digest(strip):
    import numpy as np
    return hashlib.sha256(np.ascontiguousarray(strip).tobytes() + repr(strip.shape).encode()).hexdigest()


def sha12(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()[:12]


def durs_text(anim, phases):
    if not anim:
        return '100'
    d = anim[3]
    return ';'.join(str(d[2 * i]) if d[2 * i] == d[2 * i + 1] else '%d:%d' % (d[2 * i], d[2 * i + 1]) for i in range(phases))


def snap(alpha, levels, floor):
    """alpha (uint8 array) -> the nearest of levels; below floor gone"""
    import numpy as np
    lv = np.array(levels, np.int32)
    a = alpha.astype(np.int32)
    out = lv[np.abs(a[..., None] - lv[None, None, :]).argmin(-1)]
    return np.where(a >= floor, out, 0).astype(np.uint8)


def t_alpha_cut(frames):
    import numpy as np
    out = []
    for f in frames:
        a = f[..., 3].astype(np.float64) / 255.0
        al = np.where(a >= CUT - 1e-9, 255, np.where(a >= HALO - 1e-9, GLOW, 0)).astype(np.uint8)
        g = f.copy()
        g[..., 3] = al
        g[al == 0] = 0
        out.append(g)
    return out


def t_alpha4(frames):
    out = []
    for f in frames:
        g = f.copy()
        g[..., 3] = snap(f[..., 3], LEVELS4, 48)
        g[g[..., 3] == 0] = 0
        out.append(g)
    return out


def t_black(frames):
    import numpy as np
    out = []
    for f in frames:
        g = f.copy()
        m = (f[..., 3] >= SOLID) & (f[..., :3].max(-1) == 0)
        g[m, 0], g[m, 1], g[m, 2] = NEAR_BLACK
        out.append(g)
    return out


def t_palette(frames, n):
    """the colours of the visible pixels of all frames reduced to n (median cut), every pixel to its nearest"""
    import numpy as np
    from PIL import Image
    px = np.concatenate([f[f[..., 3] > 0][:, :3] for f in frames])
    if len(px) > 60000:
        px = px[np.linspace(0, len(px) - 1, 60000).astype(int)]
    im = Image.fromarray(px.astype(np.uint8).reshape(-1, 1, 3), 'RGB')
    q = im.quantize(colors=n, method=Image.Quantize.MEDIANCUT)
    used = sorted(set(np.asarray(q).ravel().tolist()))
    pal = np.array(q.getpalette()[:3 * 256], np.int32).reshape(-1, 3)[used]
    out = []
    for f in frames:
        g = f.copy()
        m = f[..., 3] > 0
        d = ((f[m][:, None, :3].astype(np.int32) - pal[None, :, :]) ** 2).sum(-1)
        g[m, :3] = pal[d.argmin(-1)].astype(np.uint8)
        out.append(g)
    return out


def t_shift(frames, sx, sy):
    import numpy as np
    out = []
    for f in frames:
        h, w = f.shape[:2]
        g = np.zeros_like(f)
        ys, xs = np.nonzero(f[..., 3])
        if len(ys) and (xs.min() + sx < 0 or xs.max() + sx >= w or ys.min() + sy < 0 or ys.max() + sy >= h):
            raise ValueError('shift (%d, %d) moves the art out of the canvas' % (sx, sy))
        g[max(0, sy):h + min(0, sy), max(0, sx):w + min(0, sx)] = f[max(0, -sy):h - max(0, sy), max(0, -sx):w - max(0, sx)]
        out.append(g)
    return out


def t_fade(frames, k, factor):
    """the last k phases: alpha times a ramp from just under 1 down to factor on the last, snapped to FADE_LEVELS"""
    import numpy as np
    n = len(frames)
    out = list(frames)
    for j in range(k):
        i = n - k + j
        m = 1.0 - (1.0 - factor) * (j + 1) / k
        f = frames[i]
        g = f.copy()
        a = np.rint(f[..., 3].astype(np.float64) * m).astype(np.int32)
        g[..., 3] = snap(np.clip(a, 0, 255).astype(np.uint8), FADE_LEVELS, 32)
        g[g[..., 3] == 0] = 0
        out[i] = g
    return out


def treat(frames, spec):
    """the treatments in the order of the O648b report: alpha, black, palette, shift, fade"""
    if spec.get('alpha') == 'cut':
        frames = t_alpha_cut(frames)
    elif spec.get('alpha') == '4':
        frames = t_alpha4(frames)
    if spec.get('black'):
        frames = t_black(frames)
    if 'palette' in spec:
        frames = t_palette(frames, spec['palette'])
    if 'shift' in spec:
        frames = t_shift(frames, *spec['shift'])
    if 'fade' in spec:
        frames = t_fade(frames, *spec['fade'])
    return frames


def weight_centre(frames):
    """(x, y) px of the alpha weighted centre of the solid pixels over all phases"""
    import numpy as np
    pts = []
    for f in frames:
        m = f[..., 3] >= SOLID
        if m.any():
            y, x = np.nonzero(m)
            pts.append((x.mean(), y.mean()))
    return tuple(float(v) for v in np.mean(pts, 0)) if pts else (frames[0].shape[1] / 2.0, frames[0].shape[0] / 2.0)


def fit_offset(cx, cy, w, h):
    """(dx, dy): the whole tiles past the target tile that put FOOT of the target tile nearest the art's centre"""
    best = None
    for dy in range(h):
        for dx in range(w):
            tx, ty = w - 1 - dx, h - 1 - dy
            d = (cx - (tx * 32 + FOOT[0])) ** 2 + (cy - (ty * 32 + FOOT[1])) ** 2
            if best is None or d < best[0] - 1e-9:
                best = (d, dx, dy)
    return best[1], best[2]


def strip_of(dat, spr, eid):
    """(strip uint8 (h*32, w*32*phases, 4), frames, thing)"""
    import numpy as np
    from fxlib import render_frame
    t = dat.effects[eid - 1]
    if (t.layers, t.px, t.py, t.pz) != (1, 1, 1, 1):
        raise ValueError('effect %d has layers or patterns' % eid)
    frames = [np.array(render_frame(t, spr, p)) for p in range(t.phases)]
    for f in frames:
        f[f[..., 3] == 0] = 0
    return np.concatenate(frames, axis=1), frames, t


def build_rows(src):
    """[(row with the computed fields, treated strip)] from the footprint source's files under src"""
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    dat = Dat(os.path.join(src, 'Tibia.dat'))
    spr = Spr(os.path.join(src, 'Tibia.spr'))
    s12 = sha12(os.path.join(src, 'Tibia.dat'))
    out = []
    for r in pieces():
        raw, frames, t = strip_of(dat, spr, r['eid'])
        done = treat(frames, parse_treat(r['treat']))
        cx, cy = weight_centre(done)
        dx, dy = fit_offset(cx, cy, t.w, t.h)
        durs = durs_text(t.anim, t.phases)
        mean = [int(x.split(':')[0]) for x in durs.split(';')]
        r.update(src=s12, raw=digest(raw)[:12], w=t.w, h=t.h, phases=t.phases, ms=round(sum(mean) / len(mean)), dx=dx, dy=dy,
                 durs=durs)
        strip = np.ascontiguousarray(np.concatenate(done, axis=1))
        strip[strip[..., 3] == 0] = 0
        out.append((r, strip))
    return out


def spec_text(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=FIELDS, lineterminator='\n')
    w.writeheader()
    w.writerows(rows)
    return buf.getvalue()


def sums_text(pairs):
    return ''.join('%s  %s\n' % (digest(s), r['name']) for r, s in pairs)


def read_spec():
    with open(SPEC, newline='') as fh:
        return list(csv.DictReader(fh))


def read_sums():
    return dict(l.strip().split('  ', 1)[::-1] for l in open(SUMS))


def build(dat_path, spr_path, out, src, write):
    import numpy as np
    from PIL import Image
    sys.path.insert(0, HERE)
    from datspr import Dat
    d = Dat(dat_path)
    if len(d.effects) != NEED_EFFECTS:
        sys.exit('refused: the input pair has %d effects, this step needs exactly %d (pair 74: the last effect is %d)' % (
            len(d.effects), NEED_EFFECTS, NEED_EFFECTS))
    errs = table_errors(pieces())
    if errs:
        sys.exit('\n'.join(errs))
    for fn in ('Tibia.dat', 'Tibia.spr'):
        if not os.path.exists(os.path.join(src, fn)):
            sys.exit('--src %s has no %s' % (src, fn))
    pairs = build_rows(src)
    rows = [r for r, _ in pairs]
    texts = {SPEC: spec_text(rows), SUMS: sums_text(pairs)}
    if write:
        for p, t in texts.items():
            open(p, 'w', newline='').write(t)
            print('wrote', os.path.relpath(p, ROOT))
    else:
        bad = [p for p, t in texts.items() if not os.path.exists(p) or open(p, newline='').read() != t]
        if bad:
            sys.exit('the source files do not give the committed %s (run with --write after a wanted change)' % ', '.join(
                os.path.relpath(p, ROOT) for p in bad))
    strips = os.path.join(os.path.abspath(out), 'strips')
    os.makedirs(strips, exist_ok=True)
    spec = os.path.join(strips, 'import.csv')
    with open(spec, 'w', newline='') as fh:
        w = csv.writer(fh, lineterminator='\n')
        w.writerow(['replace', 'kind', 'name', 'file', 'w', 'h', 'phases', 'ms', 'dx', 'dy', 'note', 'alpha', 'durs'])
        for r, s in pairs:
            f = os.path.join(strips, r['name'] + '.png')
            Image.fromarray(np.ascontiguousarray(s)).save(f, optimize=False)
            w.writerow(['', 'effect', r['name'], f, r['w'], r['h'], r['phases'], r['ms'], r['dx'], r['dy'], r['note'], 'soft',
                        r['durs']])
    cmd = [sys.executable, '-I', os.path.join(HERE, 'import_fx_art.py'), '--ours-dat', dat_path, '--ours-spr', spr_path,
           '--out-dir', out, '--spec', spec, '--expect-first-effect', str(FIRST), '--keep-donor-names']
    if subprocess.run(cmd).returncode:
        sys.exit('import_fx_art.py failed')
    for f in ('chaos_vfx_art.lua', 'vfx_art_catalog.csv'):                # this step's ids come from the table
        p = os.path.join(out, f)
        if os.path.exists(p):
            os.remove(p)
    return live(os.path.join(out, 'Tibia.dat'), os.path.join(out, 'Tibia.spr'))


# ------------------------------------------------------------------------------------------------- server file
def total_ms(durs):
    return sum((int(a.split(':')[0]) + int(a.split(':')[-1])) // 2 for a in durs.split(';'))


def lua_text(rows):
    L = ['-- GENERATED by client/tools/sprites/gen_footprint_fx.py from art_import/footprint_fx.csv (O649). Do not edit by hand.',
         '-- The footprint effects of client pair %d: %d effects at the ids %d..%d, appended after the effects of pair 74 (the last' % (
             PAIR, len(rows), int(rows[0]['id']), int(rows[-1]['id'])),
         '-- is 5333). Each plays once on the tile a walker leaves (client game_cosmeticfx); the server never sends them.',
         '-- dx, dy: the send offset (the bottom-right tile of the art is the target tile + dx, dy); ms: the whole play.',
         '-- Gate: config.lua `chaosClientPair` >= %d, read from the file at load (M.on); a client on an older pair has no such' % PAIR,
         '-- effect, so below it the server offers none of the cosmetics that carry these ids (cosmetics_config.lua `pair`).',
         'local M = {}',
         '',
         'M.PAIR = %d' % PAIR,
         'M.FIRST = %d' % int(rows[0]['id']),
         'M.LAST = %d' % int(rows[-1]['id']),
         '',
         '-- by name: {id, dx, dy, ms, w, h}',
         'M.effects = {']
    for r in rows:
        L.append('\t%s = {id = %s, dx = %s, dy = %s, ms = %d, w = %s, h = %s},  -- %s' % (
            r['name'], r['id'], r['dx'], r['dy'], total_ms(r['durs']), r['w'], r['h'], r['note']))
    L += ['}',
          '',
          '-- the pair recorded in a config.lua text, or nil (the same reading as server/tools/client_pair.py parse)',
          'function M.parsePair(text)',
          '\tif type(text) ~= "string" then',
          '\t\treturn nil',
          '\tend',
          '\tlocal v = text:match("^%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\\n]*$") or text:match("\\n%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\\n]*")',
          '\treturn v and tonumber(v) or nil',
          'end',
          '',
          'function M.recordedPair(path)',
          '\tlocal f = io.open(path or "config.lua", "r")',
          '\tif not f then',
          '\t\treturn nil',
          '\tend',
          '\tlocal text = f:read("*a")',
          '\tf:close()',
          '\treturn M.parsePair(text)',
          'end',
          '',
          '-- the gate, read once at load; tests set it by hand',
          'M.on = (M.recordedPair() or 0) >= M.PAIR',
          '',
          '-- the names join ChaosVfx (chaos_vfx.lua), so the cosmetics window and the store play them like any effect; at load',
          '-- while the gate is on, by hand (a test) after it is set',
          'function M.merge()',
          '\tif not ChaosVfx then',
          '\t\tpcall(dofile, "data/lib/chaos_vfx.lua")',
          '\tend',
          '\tChaosVfx = ChaosVfx or {}',
          '\tfor name, e in pairs(M.effects) do',
          '\t\tChaosVfx[name] = {id = e.id, dx = e.dx, dy = e.dy, ms = e.ms}',
          '\tend',
          'end',
          '',
          'if M.on then',
          '\tM.merge()',
          'end',
          '',
          'ChaosFootprintFxIds = M',
          'return M']
    return '\n'.join(L) + '\n'


def ids(check):
    rows = read_spec()
    want = {LUA: lua_text(rows)}
    if check:
        bad = 0
        for p, text in want.items():
            have = open(p, encoding='utf-8', newline='').read() if os.path.exists(p) else None
            print(os.path.relpath(p, ROOT) + (': up to date' if have == text else ': OUT OF DATE (run gen_footprint_fx.py ids)'))
            bad += have != text
        return 1 if bad else 0
    for p, text in want.items():
        open(p, 'w', encoding='utf-8', newline='\n').write(text)
        print('wrote', os.path.relpath(p, ROOT))
    return 0


def check():
    errs = table_errors(pieces())
    rows = read_spec() if os.path.exists(SPEC) else []
    static = ['id', 'name', 'title', 'eid', 'treat', 'note']
    if [[str(r[k]) for k in static] for r in pieces()] != [[r[k] for k in static] for r in rows]:
        errs.append('art_import/footprint_fx.csv does not list the picks of the script in order')
    for r in rows:
        w, h, dx, dy, ph, ms = (int(r[k]) for k in ('w', 'h', 'dx', 'dy', 'phases', 'ms'))
        if not (0 <= dx < w and 0 <= dy < h and 1 <= w <= 3 and 1 <= h <= 3):
            errs.append('%s: size or offset' % r['name'])
        if len(r['durs'].split(';')) != ph or not 1 <= ph <= 32:
            errs.append('%s: phases or durations' % r['name'])
        if min(int(x.split(':')[0]) for x in r['durs'].split(';')) < 40:
            errs.append('%s: a phase under 40 ms' % r['name'])
        for k in ('src', 'raw'):
            if len(r[k]) != 12 or any(c not in '0123456789abcdef' for c in r[k]):
                errs.append('%s: %s is not 12 hex' % (r['name'], k))
    if len({r['src'] for r in rows}) > 1:
        errs.append('the rows name more than one source file')
    sums = [l.split('  ', 1)[1].strip() for l in open(SUMS)] if os.path.exists(SUMS) else []
    if sums != [r['name'] for r in rows]:
        errs.append('footprint_fx.sums does not list the table names in order')
    for e in errs:
        print(e)
    bad = ids(True) if rows else 1
    print('footprint fx: %d effects %d..%d, %s' % (len(rows), FIRST, FIRST + len(rows) - 1,
                                                   'OK' if not errs and not bad else 'PROBLEMS'))
    return 1 if errs or bad else 0


def live(dat_path, spr_path):
    """the pair holds each effect at its id: size, phases, durations and the pixels of the sums"""
    import numpy as np
    sys.path.insert(0, HERE)
    from datspr import Dat, Spr
    from fxlib import render_frame
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = read_spec()
    sums = read_sums()
    errs = []
    if len(dat.effects) != FIRST + len(rows) - 1:
        errs.append('the pair has %d effects, %d expected' % (len(dat.effects), FIRST + len(rows) - 1))
    for r in rows if not errs else []:
        t = dat.effects[int(r['id']) - 1]
        if (t.w, t.h, t.phases) != (int(r['w']), int(r['h']), int(r['phases'])):
            errs.append('%s: size or phases differ at %s' % (r['name'], r['id']))
            continue
        want = [v for x in r['durs'].split(';') for v in (int(x.split(':')[0]), int(x.split(':')[-1]))]
        if list(t.anim[3] if t.anim else ()) != want:
            errs.append('%s: durations differ' % r['name'])
        strip = np.concatenate([np.array(render_frame(t, spr, p)) for p in range(t.phases)], axis=1)
        strip[strip[..., 3] == 0] = 0
        if digest(strip) != sums.get(r['name']):
            errs.append('%s: pixels differ from the sum' % r['name'])
    for e in errs:
        print(e)
    print('footprint fx live: %d effects at %d..%d, %s' % (len(rows), FIRST, FIRST + len(rows) - 1,
                                                          'OK' if not errs else '%d problem(s)' % len(errs)))
    return 1 if errs else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['build', 'check', 'ids', 'live'])
    ap.add_argument('rest', nargs='*')
    ap.add_argument('--src')
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    if a.cmd == 'build':
        if not a.src or len(a.rest) != 3:
            sys.exit('build DAT SPR OUT_DIR --src DIR')
        return build(a.rest[0], a.rest[1], a.rest[2], a.src, a.write)
    if a.cmd == 'ids':
        return ids(a.check)
    if a.cmd == 'live':
        if len(a.rest) != 2:
            sys.exit('live DAT SPR')
        return live(*a.rest)
    return check()


if __name__ == '__main__':
    sys.exit(main())
