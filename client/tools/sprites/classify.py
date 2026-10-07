"""Classify the lookTypes of monsters we spawn but do not define against OUR dat/spr.

python3 -I classify.py --src-dat A_dat.dat --src-spr A.spr [--ours-dat ..] [--ours-spr ..] \
        --mon2 mon2.json --mon mon.json --evo-dir ms/evo/x --out report.csv

Classes
  a_same            our dat has the same picture (pixel diff < 0.02) at that lookType
  b_collision       lookType exists in our dat but shows a different picture (or an empty slot)
  c_missing         lookType > number of outfits in our dat
  x_source_empty    the source pair has no sprite at that lookType (cannot judge / cannot merge)
  item_look         monster uses lookTypeEx (an item sprite), not an outfit
  e_undefined       name not found in Evolisca xml/registry nor in v6 lua (no lookType known)
For b/c rows the column `dup_in_ours` lists lookTypes in our dat whose picture equals the source picture
(so the creature already exists under another id and only the monster's lookType needs remapping).
"""
import sys, os, re, json, csv, argparse, hashlib, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from datspr import Dat, Spr, render_outfit, phash, hamming, pixdiff

DUP = 0.03   # stricter for 'same picture elsewhere in our dat' (hue changes score low on dark art)
SAME = 0.12   # 0.0 = identical; recompressed/re-encoded copies of the same art land at 0.00-0.05



def empty(im):
    return im is None or im.getchannel('A').getbbox() is None


def evo_looks(evo_dir):
    """lowercased registry name (monsters.xml) and xml name -> (file, look, lookex)"""
    out = {}
    mdirs = glob.glob(os.path.join(evo_dir, '**', 'monster'), recursive=True)
    for md in mdirs:
        reg = os.path.join(md, 'monsters.xml')
        if not os.path.exists(reg):
            continue
        for m in re.finditer(r'<monster\s+name="([^"]+)"\s+file="([^"]+)"', open(reg, errors='replace').read()):
            n, f = m.group(1).lower(), os.path.join(md, m.group(2))
            if os.path.exists(f):
                t = open(f, errors='replace').read()
                l = re.search(r'<look\s[^>]*?\btype="(\d+)"', t)
                le = re.search(r'<look\s[^>]*?\btypeex="(\d+)"', t)
                out.setdefault(n, (f, int(l.group(1)) if l else None, int(le.group(1)) if le else None))
        for f in glob.glob(os.path.join(md, '**', '*.xml'), recursive=True):
            if f.endswith('monsters.xml'):
                continue
            t = open(f, errors='replace').read()
            n = re.search(r'<monster[^>]*\bname="([^"]+)"', t)
            l = re.search(r'<look\s[^>]*?\btype="(\d+)"', t)
            le = re.search(r'<look\s[^>]*?\btypeex="(\d+)"', t)
            if n:
                out.setdefault(n.group(1).lower(), (f, int(l.group(1)) if l else None, int(le.group(1)) if le else None))
    return out


def main():
    ap = argparse.ArgumentParser()
    S = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
    ap.add_argument('--src-dat', required=True); ap.add_argument('--src-spr', required=True)
    ap.add_argument('--ours-dat', default=S + 'things/Tibia.dat'); ap.add_argument('--ours-spr', default=S + 'things/Tibia.spr')
    ap.add_argument('--mon2', default=S + 'mon2.json'); ap.add_argument('--mon', default=S + 'mon.json')
    ap.add_argument('--evo-dir', default=S + 'ms/evo/x'); ap.add_argument('--out', default='report.csv')
    ap.add_argument('--sheet-dir', default=None, help='write side-by-side PNG sheets (ours | source) here')
    a = ap.parse_args()

    od, os_ = Dat(a.ours_dat), Spr(a.ours_spr)
    sd, ss = Dat(a.src_dat), Spr(a.src_spr)
    nours = len(od.outfits)
    m2 = json.load(open(a.mon2)); mon = json.load(open(a.mon))
    evo = evo_looks(a.evo_dir)
    v6 = mon['v6']
    cnt = m2['cnt']

    # index of our outfits by hash for duplicate lookup
    oh = {}
    for i in range(1, nours + 1):
        im = render_outfit(od, os_, i)
        if empty(im):
            continue
        oh[i] = (phash(im), im)

    def dups(src_im):
        h = phash(src_im)
        res = []
        for i, (hh, im) in oh.items():
            if hamming(h, hh) <= 24 and pixdiff(src_im, im) < DUP:
                res.append(i)
        return res

    rows = []
    sheet_items = []
    for name in m2['miss']:
        defs = {}
        if name in evo:
            defs['evolisca'] = evo[name][1:]
        if name in v6:
            defs['v6'] = (v6[name]['look'], v6[name]['ex'])
        if not defs:
            rows.append(dict(name=name, source='none', lookType='', cls='e_undefined', spawns=cnt.get(name, 0),
                             pixdiff='', dup_in_ours='', note='not in Evolisca registry/xml nor v6 lua'))
            continue
        # merge identical looks
        bylook = {}
        for srv, (l, le) in defs.items():
            bylook.setdefault((l, le), []).append(srv)
        for (l, le), srvs in bylook.items():
            r = dict(name=name, source='+'.join(srvs), lookType=l if l is not None else '', spawns=cnt.get(name, 0),
                     pixdiff='', dup_in_ours='', note='')
            if l is None:
                r['cls'] = 'item_look'; r['note'] = f'lookTypeEx={le}' if le else 'no look in definition'
                rows.append(r); continue
            sim = render_outfit(sd, ss, l)
            if empty(sim):
                r['cls'] = 'x_source_empty'; r['note'] = 'source pair has no outfit/empty sprite at this id'
                rows.append(r); continue
            if l > nours:
                r['cls'] = 'c_missing'
            else:
                oim = render_outfit(od, os_, l)
                if empty(oim):
                    r['cls'] = 'b_collision'; r['note'] = 'our slot is empty'
                else:
                    d = pixdiff(sim, oim)
                    # animated sprites may be re-phased between dats: also try every source / our phase
                    ts, to = sd.outfit(l), od.outfit(l)
                    if d >= SAME and (ts.phases > 1 or to.phases > 1):
                        for ps in range(ts.phases):
                            for po in range(to.phases):
                                if ps == 0 and po == 0:
                                    continue
                                d2 = pixdiff(render_outfit(sd, ss, l, phase=ps), render_outfit(od, os_, l, phase=po))
                                if d2 < d:
                                    d = d2
                        if d < SAME:
                            r['note'] = 'same art, different animation phasing'
                    r['pixdiff'] = round(d, 4)
                    r['cls'] = 'a_same' if d < SAME else 'b_collision'
                    if r['cls'] == 'a_same' and d > 0.005 and not r['note']:
                        r['note'] = 'near-identical (re-encoded)'
            if r['cls'] in ('b_collision', 'c_missing'):
                dd = dups(sim)
                r['dup_in_ours'] = ' '.join(map(str, dd[:6]))
            sheet_items.append((l, name))
            rows.append(r)
    fields = ['name', 'source', 'lookType', 'cls', 'spawns', 'pixdiff', 'dup_in_ours', 'note']
    with open(a.out, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction='ignore'); w.writeheader()
        for r in sorted(rows, key=lambda r: (r['cls'], -int(r['spawns']))):
            w.writerow(r)
    from collections import Counter, defaultdict
    c = Counter(r['cls'] for r in rows); sp = defaultdict(int)
    for r in rows:
        sp[r['cls']] += int(r['spawns'])
    print('rows', len(rows), 'names', len(m2['miss']))
    for k in sorted(c):
        print(f'{k:16s} {c[k]:4d} rows  {sp[k]:6d} spawns')
    if a.sheet_dir:
        from PIL import Image, ImageDraw
        os.makedirs(a.sheet_dir, exist_ok=True)
        rr = [r for r in rows if r['lookType'] != '' and r['cls'] not in ('x_source_empty',)]
        rr.sort(key=lambda r: (r['cls'], int(r['lookType'])))
        cell = 96; per = 12
        for k in range(0, len(rr), per):
            chunk = rr[k:k + per]
            S_ = Image.new('RGBA', (2 * cell * 3, ((len(chunk) + 2) // 3) * (cell + 14)), (60, 60, 70, 255))
            dr = ImageDraw.Draw(S_)
            for i, r in enumerate(chunk):
                x, y = (i % 3) * 2 * cell, (i // 3) * (cell + 14)
                dr.text((x + 2, y + 1), f"{r['lookType']} {r['name']} [{r['cls'][:2]}]"[:34], fill=(255, 255, 0, 255))
                for j, (dd, ss_) in enumerate(((od, os_), (sd, ss))):
                    im = render_outfit(dd, ss_, int(r['lookType']))
                    if im is None or empty(im):
                        continue
                    if im.width > cell or im.height > cell:
                        im.thumbnail((cell, cell))
                    S_.alpha_composite(im, (x + j * cell + (cell - im.width) // 2, y + 14 + (cell - im.height) // 2))
            S_.convert('RGB').save(os.path.join(a.sheet_dir, f'cmp_{k // per:02d}.png'))


if __name__ == '__main__':
    main()
