#!/usr/bin/env python3
"""Make monsters from other servers loadable on ours.

usage: python3 -I adapt_monsters.py ITEMS_OTB DAT_OUTFIT_COUNT FALLBACK_CORPSE SRC_DIR OUT_DIR

Copies *.xml / *.lua monster files from SRC_DIR to OUT_DIR, and
  * replaces a corpse id missing from items.otb with FALLBACK_CORPSE,
  * removes loot entries whose item id is missing from items.otb (one-line entries only),
  * leaves lookType alone but lists monsters above the dat outfit count in OUT_DIR/needs_sprites.txt.
Every change is written to OUT_DIR/adapt_report.txt. Original files are not modified.
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_monsters import otb_ids, parse

def main():
    otb, outfits, fb, src, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
    valid = otb_ids(otb)
    os.makedirs(out, exist_ok=True)
    report, sprites = [], []
    for f in sorted(os.listdir(src)):
        if not f.endswith(('.xml', '.lua')): continue
        t = open(os.path.join(src, f), errors='ignore').read()
        info = parse(os.path.join(src, f))
        if not info: continue
        name, look, corpse, loot, _ = info
        xml = f.endswith('.xml')
        if corpse and corpse not in valid:
            pat = r'(corpse=")%d(")' % corpse if xml else r'(monster\.corpse\s*=\s*)%d' % corpse
            t = re.sub(pat, (r'\g<1>%d\g<2>' if xml else r'\g<1>%d') % fb, t)
            report.append(f'{name}: corpse {corpse} -> {fb}')
        drop = sorted({i for i in loot if i not in valid})
        if drop:
            lines = t.split('\n'); keep = []; n = 0
            for ln in lines:
                m = re.search(r'<item\s+id="(\d+)"' if xml else r'\{\s*id\s*=\s*(\d+)', ln)
                one_line = ('/>' in ln or '</item>' in ln) if xml else ln.rstrip().endswith(('},', '}'))
                if m and int(m.group(1)) in drop and one_line: n += 1; continue
                keep.append(ln)
            t = '\n'.join(keep)
            report.append(f'{name}: dropped {n} loot lines for ids {drop[:8]}')
        if look and look > outfits: sprites.append(f'{name}\t{look}')
        open(os.path.join(out, f), 'w').write(t)
    open(os.path.join(out, 'adapt_report.txt'), 'w').write('\n'.join(report) + '\n')
    open(os.path.join(out, 'needs_sprites.txt'), 'w').write('\n'.join(sprites) + '\n')
    print(f'{len(report)} changes, {len(sprites)} monsters need sprites above lookType {outfits}')

if __name__ == '__main__':
    main()
