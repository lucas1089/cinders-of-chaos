#!/usr/bin/env python3
"""Cut the chosen donor-library outfits into ONE small 10.98 pair, in pick order, recoloured where the pick says so.

python3 -I donor_pick.py --picks monster_looks/picks.csv --lib-dir <donor library folder> --out-dir OUT \
        [--base-dat <live pair Tibia.dat> --base-spr <live pair Tibia.spr>] [--sheets DIR]

picks.csv (one row per new look, in the order the looks get their ids): key, look (the planned client lookType), lib
(B, C, D, ...: the library folder donor<lib>), lib_id (its outfit id), recolour (empty, or a rule below), and the
last column edit (empty, or an edit below).
Output: OUT/Tibia.dat + OUT/Tibia.spr with only these outfits, numbered 1..N in pick order (no items, effects or
missiles; the signature of the first library), and OUT/picks_resolved.csv. The import into the live pair is then one
run of import_outfits.py (--looks 1,2,..,N --first-outfit <first planned look>), which converts nothing (the libraries
are already our 10.98 layout) and verifies the copy.

Recolour rules (applied to every sprite of the outfit, every group, frame, direction and layer):
  green>ember   pixels of a green hue (75..170 degrees, saturation >= 0.18) turn ember orange (hue 24): same
                lightness, saturation kept (at least 0.55 where it was a glow); used where a donor's green glow does not
                fit the family (the Ashen Crypt's ember eyes, the Obsidian Hall's ember eye)
Fully transparent pixels stay transparent; alpha is never changed.

Edits (optional column `edit`; no pixel is changed):
  aura-feet     an aura outfit from a library whose client placed auras its own way: its displacement is set so the
                centre of the art (the bounding box of every frame, layer and direction of its first group) lands on
                the feet point (14, 20) of the creature's tile, the point import_vfx.py puts our own auras on, after
                the shift our client applies to a w x h aura ((w-1)*16, (h-1)*16; GameBigAurasCenter, base patch 0006)
"""
import argparse, colorsys, csv, os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from datspr import Dat, Spr
from import_outfits import parse_body, encode_flags, build_entry, frame, frames_of
from import_art_things import encode_sprite


def recolour_green_ember(a):
    """uint8 RGBA 32x32 -> recoloured copy (rule green>ember)."""
    out = a.copy()
    rgb = a[..., :3].astype(np.float64) / 255.0
    mx, mn = rgb.max(-1), rgb.min(-1)
    l = (mx + mn) / 2
    d = mx - mn
    s = np.where(d == 0, 0, d / np.maximum(1 - np.abs(2 * l - 1), 1e-9))
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.zeros_like(mx)
    m = d > 0
    hr = m & (mx == r)
    hg = m & (mx == g) & ~hr
    hb = m & ~hr & ~hg
    h[hr] = ((g - b)[hr] / d[hr]) % 6
    h[hg] = (b - r)[hg] / d[hg] + 2
    h[hb] = (r - g)[hb] / d[hb] + 4
    h = h * 60
    sel = (a[..., 3] > 0) & (h >= 75) & (h <= 170) & (s >= 0.18)
    for y, x in zip(*np.nonzero(sel)):
        ss = s[y, x]
        if l[y, x] > 0.45:
            ss = max(ss, 0.55)
        rr, gg, bb = colorsys.hls_to_rgb(24 / 360.0, l[y, x], min(ss, 1.0))
        out[y, x, :3] = (round(rr * 255), round(gg * 255), round(bb * 255))
    return out


RULES = {'': None, 'green>ember': recolour_green_ember}


class Edited:
    """a donor thing with edited flags (the `edit` column); everything else read from the donor thing"""
    def __init__(self, t, flags):
        self.t, self.flags = t, flags

    def __getattr__(self, k):
        return getattr(self.t, k)


FEET = (14, 20)  # import_vfx.py PLACE['feet']: where our creatures stand on their tile


def edit_flags(t, groups, edit, spr=None):
    """the flags dict of donor thing t after the `edit` rule (a copy; t is not changed); spr: the donor spr"""
    f = dict(t.flags)
    if edit == '':
        return f
    if edit == 'aura-feet':
        g = groups[0]
        box = None
        for ph in range(g.phases):
            for x in range(g.px):
                for layer in range(g.layers):
                    a = frame(g, spr, x, 0, 0, ph, layer=layer)[:, :, 3] > 0
                    ys, xs = np.nonzero(a)
                    if len(ys):
                        b = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
                        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
        if box is None:
            sys.exit(f'{t}: aura-feet on an empty outfit')
        cx, cy = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
        nx, ny = cx - (g.w - 1) * 16 - FEET[0], cy - (g.h - 1) * 16 - FEET[1]
        f['displacement'] = (nx % 65536, ny % 65536)
        return f
    sys.exit(f'{t}: unknown edit {edit!r}')


def masks(d, s, t):
    """the cropped alpha mask of the first idle frame of each direction."""
    g = parse_body(d, t)[0]
    out = []
    for x in range(min(4, g.px)):
        m = frame(g, s, x, 0, 0, 0)[:, :, 3] > 0
        ys, xs = np.nonzero(m)
        out.append(m[ys.min():ys.max() + 1, xs.min():xs.max() + 1] if len(ys) else None)
    return out


def mask_iou(a, b):
    """overlap of two cropped masks aligned at each corner (the best of the four)."""
    if a is None or b is None or abs(a.shape[0] - b.shape[0]) > 3 or abs(a.shape[1] - b.shape[1]) > 3:
        return 0.0
    H, W = max(a.shape[0], b.shape[0]), max(a.shape[1], b.shape[1])
    best = 0.0
    for ay, ax, by, bx in ((0, 0, 0, 0), (H - a.shape[0], W - a.shape[1], H - b.shape[0], W - b.shape[1]),
                           (0, W - a.shape[1], 0, W - b.shape[1]), (H - a.shape[0], 0, H - b.shape[0], 0)):
        A = np.zeros((H, W), bool); A[ay:ay + a.shape[0], ax:ax + a.shape[1]] = a
        B = np.zeros((H, W), bool); B[by:by + b.shape[0], bx:bx + b.shape[1]] = b
        best = max(best, (A & B).sum() / max((A | B).sum(), 1))
    return best


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--picks', required=True)
    ap.add_argument('--lib-dir', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--base-dat'); ap.add_argument('--base-spr')
    ap.add_argument('--stock-last', type=int, default=1465,
                    help='the last outfit id of the stock (commercial) art in the base pair: silhouette check against them')
    ap.add_argument('--sheets', default=None, help='directory for one PNG sheet per pick (first frame of each group)')
    a = ap.parse_args()
    os.makedirs(a.out_dir, exist_ok=True)
    picks = list(csv.DictReader(open(a.picks, newline='')))
    libs = {}

    def lib(name):
        if name not in libs:
            p = os.path.join(a.lib_dir, 'donor' + name)
            libs[name] = (Dat(os.path.join(p, 'Tibia.dat')), Spr(os.path.join(p, 'Tibia.spr')))
        return libs[name]

    # rows the library catalogue tags "named character (do not use live)" or "library only" never go live
    tags = {}
    for pk in picks:
        cat = os.path.join(a.lib_dir, 'donor' + pk['lib'], 'catalogue.csv')
        if pk['lib'] not in tags:
            tags[pk['lib']] = {r[1]: r[7] for r in csv.reader(open(cat, newline='')) if r and r[0] == 'outfit'} \
                if os.path.isfile(cat) else {}
        desc = tags[pk['lib']].get(pk['lib_id'], '')
        if 'named character' in desc or 'library only' in desc:
            sys.exit(f"{pk['key']}: donor{pk['lib']} {pk['lib_id']} is tagged in the catalogue: {desc}")

    # --- sprites and entries
    records, rec_ids, entries, src = [], {}, [], []
    for pk in picks:
        if pk['recolour'] not in RULES:
            sys.exit(f"{pk['key']}: unknown recolour rule {pk['recolour']!r}")
        rule = RULES[pk['recolour']]
        d, s = lib(pk['lib'])
        t = d.outfit(int(pk['lib_id']))
        if t is None:
            sys.exit(f"{pk['key']}: donor{pk['lib']} has no outfit {pk['lib_id']}")
        groups = parse_body(d, t)
        edit = pk.get('edit') or ''
        flags, stripped = encode_flags(Edited(t, edit_flags(t, groups, edit, s)) if edit else t, d.extra)
        sid_map = {0: 0}
        for g in groups:
            for sid in g.sprites:
                if sid in sid_map:
                    continue
                px = s.sprite(sid)
                if px is None or not px[:, :, 3].any():
                    sid_map[sid] = 0
                    continue
                if rule:
                    px = rule(px)
                rec = encode_sprite(px)
                if rec not in rec_ids:
                    records.append(rec)
                    rec_ids[rec] = len(records)
                sid_map[sid] = rec_ids[rec]
        entries.append(build_entry(flags, groups, sid_map))
        src.append((pk, d, s, t, groups, rule, stripped))
        print(f"  {len(entries):2d} {pk['key']:<18} donor{pk['lib']} {pk['lib_id']:>4}: "
              + ', '.join(f'{g.w}x{g.h} L{g.layers} P{g.px}{g.py}{g.pz} F{g.phases}' for g in groups)
              + (f" recolour {pk['recolour']}" if rule else '') + (f" edit {pk['edit']}" if pk.get('edit') else '')
              + (f' stripped {stripped}' if stripped else ''))

    # --- dat: header (signature of the first library, items 99 = none), outfits, no effects / missiles
    sig = lib(picks[0]['lib'])[0].signature
    dat = struct.pack('<IHHHH', sig, 99, len(entries), 0, 0) + b''.join(entries)
    open(os.path.join(a.out_dir, 'Tibia.dat'), 'wb').write(dat)
    # --- spr: alpha, u32 count
    n = len(records)
    offs, cur = [], 8 + 4 * n
    for r in records:
        offs.append(cur); cur += len(r)
    with open(os.path.join(a.out_dir, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', lib(picks[0]['lib'])[1].signature, n))
        f.write(struct.pack(f'<{n}I', *offs))
        for r in records:
            f.write(r)

    # --- verification
    md, ms = Dat(os.path.join(a.out_dir, 'Tibia.dat')), Spr(os.path.join(a.out_dir, 'Tibia.spr'))
    assert md.variant == ('new', True, True, True, True), md.variant
    assert len(md.outfits) == len(entries) and ms.count == n and ms.alpha
    slots = frames = 0
    for i, (pk, d, s, t, groups, rule, stripped) in enumerate(src):
        tm = md.outfit(i + 1)
        mg = parse_body(md, tm)
        assert {k: v for k, v in tm.flags.items() if k not in stripped} == \
               {k: v for k, v in edit_flags(t, groups, pk.get('edit') or '', s).items() if k not in stripped}, pk['key']
        assert len(mg) == len(groups), pk['key']
        for g, h in zip(groups, mg):
            assert (g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases, g.anim) == \
                   (h.gtype, h.w, h.h, h.exact, h.layers, h.px, h.py, h.pz, h.phases, h.anim), pk['key']
            for s0, s1 in zip(g.sprites, h.sprites):
                x, y = s.sprite(s0), ms.sprite(s1)
                if x is not None and not x[:, :, 3].any():
                    x = None
                if x is not None and rule:
                    x = rule(x)
                assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), (pk['key'], s0, s1)
                slots += 1
            frames += len(frames_of(g)) * g.layers
    print(f'verified: {len(entries)} outfits, {slots} sprite slots equal the donor (recolour rule recomputed), '
          f'{frames} frames; {n} sprites')

    # --- new to the game: no pick equals an outfit of the live pair or another pick
    def key_of(dd, ss, t):
        g = parse_body(dd, t)[0]
        im = Image.fromarray(frame(g, ss, min(2, g.px - 1), 0, 0, 0))
        bb = im.getchannel('A').getbbox()
        if not bb:
            return None
        return im.crop(bb).tobytes() + bytes(str(im.crop(bb).size), 'ascii')
    seen = {}
    for i in range(len(entries)):
        k = key_of(md, ms, md.outfit(i + 1))
        if k in seen:
            sys.exit(f"pick {picks[i]['key']} is the same art as {seen[k]}")
        seen[k] = picks[i]['key']
    if a.base_dat:
        bd, bs = Dat(a.base_dat), Spr(a.base_spr)
        hits = 0
        for t in bd.outfits:
            try:
                k = key_of(bd, bs, t)
            except Exception:  # noqa: BLE001 -- blank padding entries
                continue
            if k in seen:
                own = next(p for p in picks if p['key'] == seen[k])
                if int(own['look']) == t.id:
                    continue  # an earlier pick already imported at its planned id (base = the live pair)
                print(f'  ALREADY IN THE PAIR: {seen[k]} = outfit {t.id}')
                hits += 1
        if hits:
            sys.exit(f'{hits} pick(s) already in the live pair')
        print(f'checked: no pick is already in the live pair ({len(bd.outfits)} outfits) and no two picks are the same')
        # stock art recoloured or retouched: the silhouette of every idle direction against the stock outfits
        stock = []
        for t in bd.outfits[:a.stock_last]:
            try:
                stock.append((t.id, masks(bd, bs, t)))
            except Exception:  # noqa: BLE001
                continue
        bad = 0
        for i in range(len(entries)):
            m = masks(md, ms, md.outfit(i + 1))
            best = (0.0, 0)
            for sid, sm in stock:
                if len(sm) == len(m) and m[0] is not None and sm[0] is not None and \
                        abs(m[0].shape[0] - sm[0].shape[0]) <= 3 and abs(m[0].shape[1] - sm[0].shape[1]) <= 3:
                    v = float(np.mean([mask_iou(x, y) for x, y in zip(m, sm)]))
                    best = max(best, (v, sid))
            flag = 'STOCK SILHOUETTE' if best[0] >= 0.9 else ('check by eye' if best[0] >= 0.7 else '')
            if flag:
                print(f"  {picks[i]['key']}: silhouette {best[0]:.2f} of stock outfit {best[1]} {flag}")
            bad += best[0] >= 0.9
        if bad:
            sys.exit(f'{bad} pick(s) have the silhouette of a stock outfit (recoloured stock art)')
        print(f'checked: no pick has the silhouette of a stock outfit 1..{a.stock_last} (all idle directions, IoU < 0.9)')

    with open(os.path.join(a.out_dir, 'picks_resolved.csv'), 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['mini_id', 'key', 'look', 'lib', 'lib_id', 'recolour', 'edit', 'groups'])
        for i, (pk, d, s, t, groups, rule, stripped) in enumerate(src):
            w.writerow([i + 1, pk['key'], pk['look'], pk['lib'], pk['lib_id'], pk['recolour'], pk.get('edit') or '',
                        ' '.join(f'{g.w}x{g.h}L{g.layers}P{g.px}{g.py}{g.pz}F{g.phases}' for g in groups)])
    if a.sheets:
        os.makedirs(a.sheets, exist_ok=True)
        from import_outfits import preview_sheet
        for i, (pk, *_r) in enumerate(src):
            preview_sheet(parse_body(md, md.outfit(i + 1)), ms, os.path.join(a.sheets, pk['key'] + '.png'))


if __name__ == '__main__':
    main()
