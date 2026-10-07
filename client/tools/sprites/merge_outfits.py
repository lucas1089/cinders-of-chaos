"""Append selected outfits (dat entry + its sprites) from a source dat/spr pair to COPIES of our dat/spr.

python3 -I merge_outfits.py --src-dat A_dat.dat --src-spr A.spr --ours-dat Tibia.dat --ours-spr Tibia.spr \
        --report report.csv --out-dir out/merged  [--looks 2201,2200,...]  [--classes b_collision,c_missing]

* new outfit ids = len(our outfits)+1, +2, ...  (appended at the end of the outfit table, so no existing id moves)
* source sprites are copied byte-for-byte (same RLE/alpha spr format; both files are 0x57bbd603 u32-count sprs) and
  appended to the end of our spr; the entry's sprite ids are rewritten to the new ids; duplicate sprites are shared.
* custom dat flag bytes unknown to a stock 10.98 OTClient (39,41,42,43,46,62 in the source) are stripped from the
  copied entry; everything else (frame groups, animator, patterns) is copied verbatim (both files use the same
  10.98 + frame-group + animator layout, auto-detected by datspr).
* rows whose picture already exists in our dat under another id (dup_in_ours) are NOT appended; they are mapped to the
  existing id.  Rows already identical at the same id map to themselves.  Rows with an empty source are skipped.
Outputs: Tibia.dat, Tibia.spr, mapping.csv (old_lookType,new_lookType,action,monsters), mapping.json (old->new)
"""
import sys, os, csv, json, struct, argparse, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from datspr import Dat, Spr, render_outfit, pixdiff


def rebuild_entry(sdat, t, sspr, sprmap, newrecs, nbase):
    d = sdat.data
    start, end = t.raw
    buf = bytearray(d[start:end])
    for pos, ns in t.spr_pos:
        for k in range(ns):
            o = pos - start + 4 * k
            sid = struct.unpack_from('<I', buf, o)[0]
            if sid:
                if sid not in sprmap:
                    if sid > sspr.count or not sspr.offs[sid - 1]:
                        sprmap[sid] = 0          # source sprite missing / empty -> transparent
                    else:
                        off = int(sspr.offs[sid - 1]); ln = struct.unpack_from('<H', sspr.m, off + 3)[0]
                        newrecs.append(bytes(sspr.m[off:off + 5 + ln]))
                        sprmap[sid] = nbase + len(newrecs)
                struct.pack_into('<I', buf, o, sprmap[sid])
    for a, b in sorted(t.extras, reverse=True):          # strip custom flags (absolute -> relative)
        del buf[a - start:b - start]
    return bytes(buf)


def main():
    ap = argparse.ArgumentParser()
    S = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
    ap.add_argument('--src-dat', required=True); ap.add_argument('--src-spr', required=True)
    ap.add_argument('--ours-dat', default=S + 'things/Tibia.dat'); ap.add_argument('--ours-spr', default=S + 'things/Tibia.spr')
    ap.add_argument('--report', default=None); ap.add_argument('--looks', default=None)
    ap.add_argument('--classes', default='b_collision,c_missing')
    ap.add_argument('--out-dir', required=True)
    a = ap.parse_args()
    os.makedirs(a.out_dir, exist_ok=True)

    od = Dat(a.ours_dat); sd = Dat(a.src_dat); sspr = Spr(a.src_spr); ospr = Spr(a.ours_spr)
    assert od.variant[2] and sd.variant[2], 'u32 sprite ids required'
    assert ospr.u32count and ospr.alpha == sspr.alpha and ospr.signature == sspr.signature, 'spr formats differ'
    nours = len(od.outfits)

    # --- selection
    wanted = {}      # old look -> dict(action, dup, monsters)
    if a.looks:
        for l in a.looks.split(','):
            wanted[int(l)] = dict(dup='', mons=[])
        classes = None
    else:
        classes = set(a.classes.split(','))
        for r in csv.DictReader(open(a.report)):
            if r['lookType'] == '' or r['cls'] not in classes:
                continue
            w = wanted.setdefault(int(r['lookType']), dict(dup=r['dup_in_ours'].split()[0] if r['dup_in_ours'] else '', mons=[]))
            w['mons'].append(r['name'])
    sprmap, newrecs, newentries, mapping = {}, [], [], []
    nbase = ospr.count
    next_id = nours
    for look in sorted(wanted):
        w = wanted[look]
        t = sd.outfit(look)
        if t is None or not any(t.sprites):
            mapping.append((look, '', 'skipped_source_empty', w['mons'])); continue
        if w['dup']:
            mapping.append((look, int(w['dup']), 'reuse_existing_ours_id', w['mons'])); continue
        newentries.append(rebuild_entry(sd, t, sspr, sprmap, newrecs, nbase))
        next_id += 1
        mapping.append((look, next_id, 'appended', w['mons']))
    nnew_out, nnew_spr = len(newentries), len(newrecs)

    # --- dat: insert entries at end of outfit table
    ins = od.effects[0].raw[0]
    dd = bytearray(od.data)
    assert struct.unpack_from('<H', dd, 6)[0] == nours
    out = bytes(dd[:ins]) + b''.join(newentries) + bytes(dd[ins:])
    out = bytearray(out)
    struct.pack_into('<H', out, 6, nours + nnew_out)
    open(os.path.join(a.out_dir, 'Tibia.dat'), 'wb').write(out)

    # --- spr: new header/table, old data shifted by 4*n, new records appended
    m = ospr.m; cnt = ospr.count; n = nnew_spr
    old_table_end = 8 + 4 * cnt
    offs = ospr.offs.astype('<u8').copy()
    nz = offs > 0
    offs[nz] += 4 * n
    data_len = len(m) - old_table_end
    cur = old_table_end + 4 * n + data_len          # == new file position where appended records start
    import numpy as np
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur); cur += len(rec)
    table = np.concatenate([offs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(a.out_dir, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<I', ospr.signature)); f.write(struct.pack('<I', cnt + n)); f.write(table.tobytes())
        pos = old_table_end
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)]); pos += 1 << 24
        for rec in newrecs:
            f.write(rec)

    with open(os.path.join(a.out_dir, 'mapping.csv'), 'w', newline='') as f:
        w = csv.writer(f); w.writerow(['old_lookType', 'new_lookType', 'action', 'monsters'])
        for o, nw, act, mons in mapping:
            w.writerow([o, nw, act, '; '.join(mons)])
    json.dump({str(o): nw for o, nw, act, mons in mapping if nw != ''}, open(os.path.join(a.out_dir, 'mapping.json'), 'w'), indent=1)
    print(f'appended {nnew_out} outfits, {nnew_spr} sprites; reuse {sum(1 for x in mapping if x[2].startswith("reuse"))}; '
          f'skipped {sum(1 for x in mapping if x[2].startswith("skipped"))}')

    # --- verification: re-parse and re-render
    md = Dat(os.path.join(a.out_dir, 'Tibia.dat')); ms = Spr(os.path.join(a.out_dir, 'Tibia.spr'))
    assert md.counts[1] == nours + nnew_out and len(md.outfits) == nours + nnew_out, 'outfit count'
    assert md.counts[0] == od.counts[0] and len(md.effects) == len(od.effects) and len(md.missiles) == len(od.missiles)
    assert ms.count == cnt + n
    bad = 0
    for o, nw, act, mons in mapping:
        if act != 'appended':
            continue
        diff = pixdiff(render_outfit(sd, sspr, o), render_outfit(md, ms, nw))
        if diff > 1e-9:
            bad += 1; print('MISMATCH', o, nw, diff)
    # untouched originals
    import random
    random.seed(0)
    for i in random.sample(range(1, nours + 1), 60):
        assert pixdiff(render_outfit(od, ospr, i), render_outfit(md, ms, i)) < 1e-9, i
    assert md.max_sprite <= ms.count, 'sprite ids out of range'
    print(f'verified: merged dat parses ({md.variant}), {nours + nnew_out} outfits, {ms.count} sprites; '
          f'{nnew_out - bad}/{nnew_out} appended outfits render pixel-identical to source; 60 random originals unchanged')


if __name__ == '__main__':
    main()
