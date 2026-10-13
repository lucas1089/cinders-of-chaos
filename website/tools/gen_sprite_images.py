#!/usr/bin/env python3
"""Item and outfit images for the website, drawn from our client pair (website/README.md "Sprite images").

    python3 -I website/tools/gen_sprite_images.py --dat P/Tibia.dat --spr P/Tibia.spr --out-dir OUT \
        [--otb SERVER/data/items/items.otb] [--publish own] [--preview DIR]

The pair is not in git: take it from the windows-assets branch (things/things-1098.tar.xz) or the client folder.
Only the art of the tiers named by --publish is drawn (website/tools/sprite_owners.csv says which client ids are
ours: own, donor or stock). Every other item and look gets a neutral placeholder of our own; stock art is never
read for an image.

Output (OUT, the site's chaos-sprites/ folder; install_site.sh builds it when CHAOS_SPRITE_PAIR is set):
  items/<server id>.png         the item as the client draws it alone (count 1, empty fluid), every layer, phase 0
  items/<server id>-c<n>.png    stackable items: the stack pattern of n = 2, 3, 4, 5, 10, 25, 50 pieces
  items/<server id>-f<k>.png    fluid containers and splashes: client fluid colour k = 1..8 (blue, red, brown,
                                green, yellow, white, purple, black)
  items/<server id>.png of a stock item: a hard link to placeholder-item.png
  outfits/<look>.png            the look's layer sheet: idle group, phase 0, facing south; one column per
                                (addon pattern y, mount pattern z), column = z * patterns_y + y; row 0 the art,
                                row 1 the colour template (yellow head, red body, green legs, blue feet)
  outfits/<look>-d.png          the look drawn with the default colours 78/69/58/76, no addons (no-GD fallback)
  placeholder-item.png, placeholder-outfit.png
  index.json                    {version, stamp, publish, pair, items: {sid: "" | "c" | "f"}, outfits: {look: meta}}
                                meta = [w, h, dx, dy, patterns_y, patterns_z, layers, negative, bones, bx, by]
The PHP side (plugins/chaos/sprite_lib.php, chaos_outfit.php) tints the sheet per request with the same maths as
tint() and compose() below; gen_sprite_images_test.py checks them on hand-made masks.

The colouring follows the client's own drawing (Creature / Outfit draw of the 10.98 client): the template layer is
split by its four exact colours, and the art under each is multiplied by that part's outfit colour; addon patterns
are drawn over pattern 0 for each addon worn. The idea of drawing outfit images from the pair this way comes from
open-tibia-library (Gesior, MIT): this tool follows its documented method (4-layer template mask, the 133-colour
table, addon layers); none of its code is used or copied.
"""
import argparse
import csv
import hashlib
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(REPO, 'client', 'tools', 'sprites'))
sys.path.insert(0, os.path.join(REPO, 'server', 'tools'))
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

VERSION = 1
OWNERS = os.path.join(HERE, 'sprite_owners.csv')
ITEM_MANIFESTS = ('art_items.csv', 'dark_tiles.csv', 'donor_items.csv', 'fist_items.csv', 'theme_items.csv')
TIERS = ('own', 'donor', 'stock')
DEFAULT_PUBLISH = ('own',)
DEFAULT_COLOURS = (78, 69, 58, 76)
STACKS = (1, 2, 3, 4, 5, 10, 25, 50)
FLUIDS = range(1, 9)
# the template's exact colours, in the order head, body, legs, feet
MASK = ((255, 255, 0), (255, 0, 0), (0, 255, 0), (0, 0, 255))


# ------------------------------------------------------------------------------------------------ colours
def outfit_colour(c):
    """the client's outfit colour (id 0..132) as (r, g, b): 19 hues x 7 shades, column 0 greys; id >= 133 is 0."""
    if not 0 <= c < 133:
        c = 0
    if c % 19 == 0:
        g = int((1 - c / 19 / 7) * 255)
        return (g, g, g)
    h = (c % 19) / 18.0
    s, v = ((0.25, 1.0), (0.25, 0.75), (0.5, 0.75), (0.667, 0.75), (1.0, 1.0), (1.0, 0.75), (1.0, 0.5))[c // 19]
    seg = h * 6
    if h < 1 / 6:
        r, b = v, v * (1 - s); g = b + (v - b) * seg
    elif h < 2 / 6:
        g, b = v, v * (1 - s); r = g - (v - b) * (seg - 1)
    elif h < 3 / 6:
        g, r = v, v * (1 - s); b = r + (v - r) * (seg - 2)
    elif h < 4 / 6:
        b, r = v, v * (1 - s); g = b - (v - r) * (seg - 3)
    elif h < 5 / 6:
        b, g = v, v * (1 - s); r = g + (v - g) * (seg - 4)
    else:
        r, g = v, v * (1 - s); b = r - (v - g) * (seg - 5)
    return (int(r * 255), int(g * 255), int(b * 255))


def tint(canvas, mask, colours, at=(0, 0)):
    """multiply the canvas (H x W x 4 uint8, in place) under each exact template colour of mask (h x w x 4) by that
    part's outfit colour, as the client's multiply pass does: rgb = (rgb * c + 127) // 255, alpha kept.
    `at` is the mask's top-left in the canvas."""
    x0, y0 = at
    h, w = mask.shape[:2]
    view = canvas[y0:y0 + h, x0:x0 + w]
    opaque = mask[..., 3] > 0
    for col, cid in zip(MASK, colours):
        sel = opaque & np.all(mask[..., :3] == col, axis=2)
        if sel.any():
            c = np.array(outfit_colour(cid), np.uint32)
            view[sel, :3] = ((view[sel, :3].astype(np.uint32) * c + 127) // 255).astype(np.uint8)
    return canvas


def over(canvas, img, at):
    """alpha-composite img (h x w x 4 uint8) onto canvas at (x, y), in place (the client's normal blending)."""
    x0, y0 = at
    h, w = img.shape[:2]
    dst = canvas[y0:y0 + h, x0:x0 + w].astype(np.float64)
    src = img.astype(np.float64)
    sa = src[..., 3:4] / 255
    da = dst[..., 3:4] / 255
    oa = sa + da * (1 - sa)
    rgb = np.where(oa > 0, (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-9), 0)
    canvas[y0:y0 + h, x0:x0 + w, :3] = np.rint(rgb).astype(np.uint8)
    canvas[y0:y0 + h, x0:x0 + w, 3:4] = np.rint(oa * 255).astype(np.uint8)
    return canvas


# ------------------------------------------------------------------------------------------------ placement
def u16(v):
    return v & 0xFFFF


def s16(v):
    v &= 0xFFFF
    return v - 65536 if v >= 32768 else v


def place(rider, mount=None):
    """top-left of the rider's (and the mount's) frame relative to the tile's top-left, as the client draws a creature
    facing south (Outfit::draw with client base patch 0034): returns (rider_xy, mount_xy or None, z pattern).
    rider / mount: meta lists [w, h, dx, dy, py, pz, layers, negative, bones, bx, by] (index.json)."""
    w, h, dx, dy, _py, pz, _layers, neg, bones, bx, by = rider
    z = 1 if (mount is not None and pz > 1) else 0
    if not z:
        return (-dx - (w - 1) * 32, -dy - (h - 1) * 32), None, 0
    mw, mh, mdx, mdy, _mpy, _mpz, _ml, mneg, mbones, mbx, mby = mount
    destx = desty = 0
    if not mneg:
        destx -= mdx; desty -= mdy
    mx, my = destx, desty
    if bones and mbones:   # both have a seat: the stock bone alignment (unsigned pairs, as the client reads them)
        bonus = abs(mw - w) * 32
        mx += u16(bx) - u16(mbx) + bonus
        my += u16(by) - u16(mby) + bonus
    mount_xy = (mx - mdx - (mw - 1) * 32, my - mdy - (mh - 1) * 32)
    if neg or mneg:
        if not mneg:
            destx += mdx; desty += mdy
        if mneg and mbones and not bones:   # base patch 0034: the rider sits at the mount's seat
            destx += s16(mbx); desty += s16(mby)
    else:
        destx += dx; desty += dy
    return (destx - dx - (w - 1) * 32, desty - dy - (h - 1) * 32), mount_xy, 1


def compose(rider, sheet, colours=DEFAULT_COLOURS, addons=0, mount=None, mount_sheet=None):
    """the outfit image: rider meta and sheet (H x W x 4 array, the layer sheet of index.json's layout), optional
    mount meta and sheet. The canvas is the union of the frames drawn; returns an H x W x 4 uint8 array."""
    w, h, _dx, _dy, py, pz, layers = rider[:7]
    rxy, mxy, z = place(rider, mount)
    rects = [(rxy[0], rxy[1], w * 32, h * 32)]
    if mxy is not None:
        rects.append((mxy[0], mxy[1], mount[0] * 32, mount[1] * 32))
    left = min(r[0] for r in rects); top = min(r[1] for r in rects)
    right = max(r[0] + r[2] for r in rects); bottom = max(r[1] + r[3] for r in rects)
    canvas = np.zeros((bottom - top, right - left, 4), np.uint8)
    if mxy is not None:
        cw, ch = mount[0] * 32, mount[1] * 32
        over(canvas, mount_sheet[0:ch, 0:cw], (mxy[0] - left, mxy[1] - top))
    cw, ch = w * 32, h * 32
    for y in range(py):
        if y > 0 and not (addons & (1 << (y - 1))):
            continue
        col = z * py + y
        at = (rxy[0] - left, rxy[1] - top)
        over(canvas, sheet[0:ch, col * cw:(col + 1) * cw], at)
        if layers > 1:
            tint(canvas, sheet[ch:2 * ch, col * cw:(col + 1) * cw], colours, at)
    return canvas


# ------------------------------------------------------------------------------------------------ items
def stack_pattern(count, px, py):
    """(x, y) pattern of a stackable item with count pieces (the client's rule for 4 x 2 patterns)."""
    if px != 4 or py != 2 or count <= 0:
        return 0, 0
    if count < 5:
        return count - 1, 0
    for i, n in enumerate((10, 25, 50)):
        if count < n:
            return i, 1
    return 3, 1


def fluid_pattern(colour, px, py):
    return (colour % 4) % px, (colour // 4) % py


def draw_thing(t, spr, x=0, y=0, z=0, layers=None, phase=0):
    """an item or one cell of a look: H x W x 4 array, the listed layers composited (default: all)."""
    from datspr import sprite_index
    W, H = t.w * 32, t.h * 32
    out = np.zeros((H, W, 4), np.uint8)
    for layer in (range(t.layers) if layers is None else layers):
        if layer >= t.layers:
            continue
        for hh in range(t.h):
            for ww in range(t.w):
                a = spr.sprite(t.sprites[sprite_index(t, x, y, z, layer, phase, ww, hh)])
                if a is not None:
                    over(out, a, ((t.w - 1 - ww) * 32, (t.h - 1 - hh) * 32))
    return out


def blank(t, spr):
    return all(not s or s > spr.count or not spr.offs[s - 1] for s in t.sprites)


# ------------------------------------------------------------------------------------------------ outfits
def outfit_meta(t):
    disp = t.flags.get('displacement') or (0, 0)
    dx, dy = s16(disp[0]), s16(disp[1])
    b = t.flags.get('x39')
    bx = by = 0
    if b:
        bx, by = struct.unpack_from('<2h', bytes(b), 4)   # the south pair (north, south, east, west)
    return [t.w, t.h, dx, dy, t.py, min(t.pz, 2), min(t.layers, 2), int(dx < 0 or dy < 0), int(bool(b)), bx, by]


def outfit_sheet(t, spr):
    """the layer sheet: columns (z * py + y) for z < min(pz, 2), rows art and template (when the look has one)."""
    cw, ch = t.w * 32, t.h * 32
    pz, layers = min(t.pz, 2), min(t.layers, 2)
    x = 2 if t.px >= 4 else 0
    sheet = np.zeros((ch * layers, cw * pz * t.py, 4), np.uint8)
    for z in range(pz):
        for y in range(t.py):
            col = z * t.py + y
            for layer in range(layers):
                sheet[layer * ch:(layer + 1) * ch, col * cw:(col + 1) * cw] = draw_thing(t, spr, x, y, z, [layer])
    return sheet


# ------------------------------------------------------------------------------------------------ ownership
def read_owners(path=OWNERS):
    """rows (kind, first, last, tier) in file order; a later row wins (exceptions after ranges)."""
    rows = []
    with open(path, newline='', encoding='utf-8') as f:
        for r in csv.DictReader(f):
            if r['kind'] not in ('item', 'outfit') or r['tier'] not in TIERS:
                raise SystemExit(f'{path}: bad row {r}')
            rows.append((r['kind'], int(r['first']), int(r['last']), r['tier']))
    return rows


def tier_of(rows, kind, cid):
    tier = 'stock'   # unlisted ids are not ours
    for k, a, b, t in rows:
        if k == kind and a <= cid <= b:
            tier = t
    return tier


def parse_publish(text):
    text = (text or '').strip().lower()
    if text in ('', 'default'):
        return DEFAULT_PUBLISH
    if text == 'all':
        return TIERS
    tiers = tuple(t for t in TIERS if t in {p.strip() for p in text.split(',')})
    bad = {p.strip() for p in text.split(',')} - set(TIERS)
    if bad or not tiers:
        raise SystemExit(f'--publish: own, donor, stock (comma separated) or all; got {text!r}')
    return tiers


def server_ids(otb=None, items_dir=os.path.join(REPO, 'server', 'data', 'items')):
    """server id -> client id: the server's items.otb (every item), else only our manifests (our items)."""
    out = {}
    if otb:
        from install_dark_tiles import scan
        kids, _ = scan(open(otb, 'rb').read())
        for k in kids:
            if k[2] is not None and k[3]:
                out[k[2]] = k[3]
        return out
    for name in ITEM_MANIFESTS:
        p = os.path.join(items_dir, name)
        if os.path.isfile(p):
            with open(p, newline='', encoding='utf-8') as f:
                for r in csv.DictReader(f):
                    out[int(r['server_id'])] = int(r['client_id'])
    return out


# ------------------------------------------------------------------------------------------------ placeholders
def placeholder_item():
    """a neutral slot: a dim rounded square with a faint inner rim (32 x 32, our own drawing)."""
    im = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((5, 5, 26, 26), radius=4, fill=(44, 40, 42, 150), outline=(96, 88, 84, 190))
    d.rounded_rectangle((9, 9, 22, 22), radius=2, outline=(70, 64, 62, 150))
    return im


def placeholder_outfit():
    """a neutral standing figure: grey hood and cloak shapes (64 x 64, the tile at the bottom right like a look)."""
    im = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    body = (58, 54, 56, 200)
    d.polygon([(30, 30), (50, 30), (56, 60), (24, 60)], fill=body)
    d.ellipse((32, 14, 48, 32), fill=(70, 66, 68, 215))
    d.ellipse((36, 19, 44, 28), fill=(28, 26, 28, 220))
    d.line([(30, 30), (24, 60)], fill=(96, 90, 88, 200))
    d.line([(50, 30), (56, 60)], fill=(96, 90, 88, 200))
    d.ellipse((24, 56, 58, 63), fill=(0, 0, 0, 70))
    return im


def save_png(arr_or_img, path):
    im = arr_or_img if isinstance(arr_or_img, Image.Image) else Image.fromarray(arr_or_img, 'RGBA')
    im.save(path, optimize=True)


def link_or_copy(src, dst):
    try:
        os.link(src, dst)
    except OSError:
        import shutil
        shutil.copyfile(src, dst)


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


# ------------------------------------------------------------------------------------------------ build
def build(dat_path, spr_path, out_dir, otb=None, publish=DEFAULT_PUBLISH, owners=OWNERS, log=print, ids=None):
    """write OUT (see the module docstring); ids: a server id -> client id map in place of --otb (tests)."""
    from datspr import Dat, Spr
    dat, spr = Dat(dat_path), Spr(spr_path)
    rows = read_owners(owners)
    os.makedirs(os.path.join(out_dir, 'items'), exist_ok=True)
    os.makedirs(os.path.join(out_dir, 'outfits'), exist_ok=True)
    ph_item = os.path.join(out_dir, 'placeholder-item.png')
    save_png(placeholder_item(), ph_item)
    save_png(placeholder_outfit(), os.path.join(out_dir, 'placeholder-outfit.png'))
    n_items = dat.counts[0]
    items, drawn, placeholders = {}, {}, 0
    for sid, cid in sorted((ids if ids is not None else server_ids(otb)).items()):
        dst = os.path.join(out_dir, 'items', f'{sid}.png')
        t = dat.items[cid - 100] if 100 <= cid <= n_items else None
        if t is None or tier_of(rows, 'item', cid) not in publish or blank(t, spr):
            link_or_copy(ph_item, dst)
            placeholders += 1
            continue
        kind = ''
        if cid not in drawn:
            img = {'': draw_thing(t, spr)}
            if t.flags.get('stackable') and t.px == 4 and t.py == 2:
                kind = 'c'
                for n in STACKS[1:]:
                    x, y = stack_pattern(n, t.px, t.py)
                    img[f'-c{n}'] = draw_thing(t, spr, x, y)
            elif (t.flags.get('fluid') or t.flags.get('splash')) and t.px * t.py > 1:
                kind = 'f'
                for k in FLUIDS:
                    x, y = fluid_pattern(k, t.px, t.py)
                    img[f'-f{k}'] = draw_thing(t, spr, x, y)
            drawn[cid] = (sid, kind)
            for suffix, a in img.items():
                save_png(a, os.path.join(out_dir, 'items', f'{sid}{suffix}.png'))
        else:   # two server ids of one client id share the files
            first, kind = drawn[cid]
            for name in os.listdir(os.path.join(out_dir, 'items')):
                if name == f'{first}.png' or name.startswith(f'{first}-'):
                    link_or_copy(os.path.join(out_dir, 'items', name),
                                 os.path.join(out_dir, 'items', name.replace(str(first), str(sid), 1)))
        items[str(sid)] = kind
    outfits = {}
    for t in dat.outfits:
        if tier_of(rows, 'outfit', t.id) not in publish or blank(t, spr):
            continue
        meta = outfit_meta(t)
        sheet = outfit_sheet(t, spr)
        save_png(sheet, os.path.join(out_dir, 'outfits', f'{t.id}.png'))
        save_png(compose(meta, sheet), os.path.join(out_dir, 'outfits', f'{t.id}-d.png'))
        outfits[str(t.id)] = meta
    pair = {'dat': md5(dat_path), 'spr': md5(spr_path), 'otb': md5(otb) if otb else ''}
    stamp = hashlib.sha256(json.dumps([VERSION, pair, list(publish), md5(owners)]).encode()).hexdigest()[:16]
    index = {'version': VERSION, 'stamp': stamp, 'publish': list(publish), 'pair': pair, 'items': items,
             'outfits': outfits}
    with open(os.path.join(out_dir, 'index.json'), 'w', encoding='utf-8') as f:
        json.dump(index, f, separators=(',', ':'), sort_keys=True)
    log(f'sprite images: {len(items)} items drawn ({len(drawn)} client ids), {placeholders} placeholders, '
        f'{len(outfits)} looks; publish {",".join(publish)}; stamp {stamp}')
    return index


def preview(out_dir, dest, cols=24):
    """contact sheets of what was written: items.png (drawn items), outfits.png (looks with colours and addons)."""
    from PIL import ImageFont  # noqa: F401  (default bitmap font)
    os.makedirs(dest, exist_ok=True)
    index = json.load(open(os.path.join(out_dir, 'index.json')))
    bg = (40, 36, 38, 255)
    sids = sorted(int(s) for s in index['items'])
    cell = 72
    sheet = Image.new('RGBA', (cols * cell, max(1, -(-len(sids) // cols)) * cell), bg)
    d = ImageDraw.Draw(sheet)
    for i, sid in enumerate(sids):
        im = Image.open(os.path.join(out_dir, 'items', f'{sid}.png')).convert('RGBA')
        x, y = (i % cols) * cell, (i // cols) * cell
        im = im.resize((im.width * 64 // max(im.width, im.height), im.height * 64 // max(im.width, im.height)), Image.NEAREST)
        sheet.alpha_composite(im, (x + (cell - im.width) // 2, y + 2))
        d.text((x + 2, y + cell - 10), str(sid), fill=(200, 190, 170, 255))
    sheet.save(os.path.join(dest, 'items.png'))
    looks = sorted(int(k) for k in index['outfits'])
    sets = [((78, 69, 58, 76), 0), ((94, 132, 79, 114), 3), ((19, 57, 38, 0), 1)]
    cell_w, cell_h = 3 * 100, 110
    oc = 6
    sheet = Image.new('RGBA', (oc * cell_w, max(1, -(-len(looks) // oc)) * cell_h), bg)
    d = ImageDraw.Draw(sheet)
    for i, look in enumerate(looks):
        meta = index['outfits'][str(look)]
        src = np.asarray(Image.open(os.path.join(out_dir, 'outfits', f'{look}.png')).convert('RGBA')).copy()
        x0, y0 = (i % oc) * cell_w, (i // oc) * cell_h
        for j, (colours, addons) in enumerate(sets):
            im = Image.fromarray(compose(meta, src, colours, addons), 'RGBA')
            if max(im.size) > 96:
                f = 96 / max(im.size)
                im = im.resize((max(1, int(im.width * f)), max(1, int(im.height * f))), Image.NEAREST)
            sheet.alpha_composite(im, (x0 + j * 100 + (100 - im.width) // 2, y0 + 96 - im.height))
        d.text((x0 + 4, y0 + 98), str(look), fill=(200, 190, 170, 255))
    sheet.save(os.path.join(dest, 'outfits.png'))
    return dest


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--dat', required=True)
    ap.add_argument('--spr', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--otb', help="the game server's data/items/items.otb (server id -> client id of every item)")
    ap.add_argument('--publish', default=os.environ.get('CHAOS_SPRITE_PUBLISH', ''),
                    help='tiers to draw: own, donor, stock (comma separated) or all; default own')
    ap.add_argument('--owners', default=OWNERS)
    ap.add_argument('--preview', help='also write contact sheets (items.png, outfits.png) into this folder')
    a = ap.parse_args(argv)
    if a.otb and not os.path.isfile(a.otb):
        raise SystemExit(f'--otb: no such file {a.otb}')
    build(a.dat, a.spr, a.out_dir, a.otb, parse_publish(a.publish), a.owners)
    if a.preview:
        print('previews:', preview(a.out_dir, a.preview))


if __name__ == '__main__':
    main()
