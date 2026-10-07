"""Append chosen magic effects + distance missiles (dat entry + sprites) from a source dat/spr pair (Black Talon 10.98)
to COPIES of our dat/spr.  Can chain after merge_outfits.py: pass its merged Tibia.dat/.spr as --ours-dat/--ours-spr and
the result holds both the new outfits (1501..) and the new effects (372..) / missiles (116..) in ONE pair.

python3 -I merge_effects.py --src-dat A_dat.dat --src-spr A.spr --ours-dat Tibia.dat --ours-spr Tibia.spr --out-dir out/fx \
        [--picks fx_picks.csv] [--lua-out chaos_fx.lua] [--catalog-out effects_catalog.csv]

* new effect ids = len(our effects)+1.. , new missile ids = len(our missiles)+1.. (appended at the end of each category,
  no existing id moves; outfit/item tables are copied untouched, so the order of the two merges does not matter).
* sprites are copied byte-for-byte (same RLE/alpha format) and appended to the end of the spr; the entry's sprite ids are
  rewritten.  Identical sprite records are shared (inside the new set and against ALL sprites already in our spr).
* custom flag bytes unknown to a stock client (39,41,42,43,46,62) are stripped; animator, frame durations and
  directional patterns (missiles 3x3) are copied verbatim.
Outputs: Tibia.dat, Tibia.spr, mapping.csv (name,category,source_id,new_id), effects_catalog.csv, chaos_fx.lua.
Verification (always run): re-parse, every added effect/missile is re-rendered for ALL frames and patterns and compared
byte-identical with the source; all original effects/missiles/outfits and sampled sprites are checked unchanged.
"""
import sys, os, csv, struct, argparse, hashlib, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from datspr import Dat, Spr, sprite_index
from PIL import Image


def record(spr, sid):
    if sid == 0 or sid > spr.count or not spr.offs[sid - 1]:
        return None
    off = int(spr.offs[sid - 1]); ln = struct.unpack_from('<H', spr.m, off + 3)[0]
    return bytes(spr.m[off:off + 5 + ln])


def all_frames(t, spr):
    """yield every (phase, x, y, z, layer) full-tile RGBA array of a thing (all frames, all patterns)."""
    for ph in range(t.phases):
        for z in range(t.pz):
            for y in range(t.py):
                for x in range(t.px):
                    for l in range(t.layers):
                        W, H = t.w * 32, t.h * 32
                        c = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                        for hh in range(t.h):
                            for ww in range(t.w):
                                a = spr.sprite(t.sprites[sprite_index(t, x, y, z, l, ph, ww, hh)])
                                if a is not None:
                                    c.alpha_composite(Image.fromarray(a, 'RGBA'), ((t.w - 1 - ww) * 32, (t.h - 1 - hh) * 32))
                        yield (ph, x, y, z, l), c.tobytes()


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument('--src-dat', required=True); ap.add_argument('--src-spr', required=True)
    ap.add_argument('--ours-dat', required=True); ap.add_argument('--ours-spr', required=True)
    ap.add_argument('--picks', default=os.path.join(here, 'fx_picks.csv'))
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--lua-out', default=None); ap.add_argument('--catalog-out', default=None)
    a = ap.parse_args()
    os.makedirs(a.out_dir, exist_ok=True)

    od = Dat(a.ours_dat); sd = Dat(a.src_dat); sspr = Spr(a.src_spr); ospr = Spr(a.ours_spr)
    assert od.variant[2] and sd.variant[2], 'u32 sprite ids required'
    assert ospr.u32count and ospr.alpha == sspr.alpha and ospr.signature == sspr.signature, 'spr formats differ'
    ne, nm = len(od.effects), len(od.missiles)
    assert od.counts[2] == ne and od.counts[3] == nm
    picks = list(csv.DictReader(open(a.picks)))
    names = [p['name'] for p in picks]
    assert len(set(names)) == len(names), 'duplicate names'

    # --- 1. collect distinct source sprite records; share against ours
    srcthings = []
    for p in picks:
        cat = p['category']; sid = int(p['source_id'])
        lst = sd.effects if cat == 'effect' else sd.missiles
        assert cat in ('effect', 'missile') and 1 <= sid <= len(lst), p
        srcthings.append(lst[sid - 1])
    recs = {}                                     # record bytes -> source sprite ids
    for t in srcthings:
        for s in set(t.sprites):
            r = record(sspr, s)
            if r is not None:
                recs.setdefault(r, set()).add(s)
    want = {}                                     # md5 -> record
    for r in recs:
        want[hashlib.md5(r).digest()] = r
    lens = {len(r) for r in recs}
    existing = {}                                 # record bytes -> lowest existing id in our spr
    for sid in range(1, ospr.count + 1):
        o = int(ospr.offs[sid - 1])
        if not o:
            continue
        ln = 5 + struct.unpack_from('<H', ospr.m, o + 3)[0]
        if ln in lens:
            r = bytes(ospr.m[o:o + ln])
            if hashlib.md5(r).digest() in want and r not in existing:
                existing[r] = sid
    newrecs, rec_id = [], {}                      # record -> final id
    base = ospr.count
    for r in sorted(recs, key=lambda r: min(recs[r])):
        if r in existing:
            rec_id[r] = existing[r]
        else:
            newrecs.append(r); rec_id[r] = base + len(newrecs)
    sprmap = {}
    for r, ss in recs.items():
        for s in ss:
            sprmap[s] = rec_id[r]

    # --- 2. rebuild entries
    def rebuild(t):
        d = sd.data; start, end = t.raw
        buf = bytearray(d[start:end])
        for pos, ns in t.spr_pos:
            for k in range(ns):
                o = pos - start + 4 * k
                s = struct.unpack_from('<I', buf, o)[0]
                if s:
                    struct.pack_into('<I', buf, o, sprmap.get(s, 0))
        for x, y in sorted(t.extras, reverse=True):
            del buf[x - start:y - start]
        return bytes(buf)
    ent_e, ent_m, mapping = [], [], []
    for p, t in zip(picks, srcthings):
        if p['category'] == 'effect':
            ent_e.append(rebuild(t)); nid = ne + len(ent_e)
        else:
            ent_m.append(rebuild(t)); nid = nm + len(ent_m)
        mapping.append(dict(p, new_id=nid, source_id=int(p['source_id'])))

    # --- 3. dat
    d = od.data
    ins = od.missiles[0].raw[0]
    assert od.missiles[-1].raw[1] == len(d), 'dat does not end with the missile table'
    out = bytearray(d[:ins] + b''.join(ent_e) + d[ins:] + b''.join(ent_m))
    struct.pack_into('<H', out, 8, ne + len(ent_e)); struct.pack_into('<H', out, 10, nm + len(ent_m))
    open(os.path.join(a.out_dir, 'Tibia.dat'), 'wb').write(out)

    # --- 4. spr: bigger table (old data shifted by 4*n), new records appended
    m = ospr.m; cnt = ospr.count; n = len(newrecs)
    old_table_end = 8 + 4 * cnt
    offs = ospr.offs.astype('<u8').copy(); offs[offs > 0] += 4 * n
    cur = old_table_end + 4 * n + (len(m) - old_table_end)
    new_offs = []
    for r in newrecs:
        new_offs.append(cur); cur += len(r)
    table = np.concatenate([offs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(a.out_dir, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', ospr.signature, cnt + n)); f.write(table.tobytes())
        pos = old_table_end
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)]); pos += 1 << 24
        for r in newrecs:
            f.write(r)

    # --- 5. mapping / catalog / lua
    with open(os.path.join(a.out_dir, 'mapping.csv'), 'w', newline='') as f:
        w = csv.writer(f); w.writerow(['name', 'category', 'source_id', 'new_id'])
        for r in mapping:
            w.writerow([r['name'], r['category'], r['source_id'], r['new_id']])
    cat_path = a.catalog_out or os.path.join(a.out_dir, 'effects_catalog.csv')
    with open(cat_path, 'w', newline='') as f:
        w = csv.writer(f); w.writerow(['name', 'theme', 'category', 'new id', 'source id', 'note'])
        for r in mapping:
            w.writerow([r['name'], r['theme'], r['category'], r['new_id'], r['source_id'], r['note']])
    lua = ['-- GENERATED by client/tools/sprites/merge_effects.py (ids = positions in the merged Tibia.dat).',
           '-- Magic effects > 255 need the client feature GameMagicEffectU16 (enabled in the 10.98 profile); the server',
           '-- already sends effects as uint16 (protocolgame.cpp sendMagicEffect).  Distance shots are uint8 (max 255).',
           'ChaosFx = {']
    for r in mapping:
        if r['category'] == 'effect':
            lua.append(f"\t{r['name']} = {r['new_id']},  -- {r['theme']}: {r['note']}")
    lua += ['}', '', 'ChaosFxMissile = {']
    for r in mapping:
        if r['category'] == 'missile':
            lua.append(f"\t{r['name']} = {r['new_id']},  -- {r['theme']}: {r['note']}")
    lua += ['}', '',
            'function Fx(name, fallback)', '\treturn ChaosFx[name] or fallback or CONST_ME_NONE', 'end', '',
            'function FxMissile(name, fallback)', '\treturn ChaosFxMissile[name] or fallback or CONST_ANI_NONE', 'end', '']
    open(a.lua_out or os.path.join(a.out_dir, 'chaos_fx.lua'), 'w').write('\n'.join(lua))
    print(f'appended {len(ent_e)} effects ({ne + 1}..{ne + len(ent_e)}), {len(ent_m)} missiles ({nm + 1}..{nm + len(ent_m)}); '
          f'{n} new sprites, {len(recs) - n} shared with existing sprites')

    # --- 6. verification
    md = Dat(os.path.join(a.out_dir, 'Tibia.dat')); ms = Spr(os.path.join(a.out_dir, 'Tibia.spr'))
    assert md.counts == (od.counts[0], od.counts[1], ne + len(ent_e), nm + len(ent_m)), md.counts
    assert len(md.effects) == ne + len(ent_e) and len(md.missiles) == nm + len(ent_m) and len(md.outfits) == len(od.outfits)
    assert ms.count == cnt + n and md.max_sprite <= ms.count
    bad = 0; nframes = 0
    for r, t in zip(mapping, srcthings):
        mt = (md.effects if r['category'] == 'effect' else md.missiles)[r['new_id'] - 1]
        assert (mt.w, mt.h, mt.layers, mt.px, mt.py, mt.pz, mt.phases) == (t.w, t.h, t.layers, t.px, t.py, t.pz, t.phases), r
        assert mt.anim == t.anim, ('animator differs', r)
        for (ka, ba), (kb, bb) in zip(all_frames(t, sspr), all_frames(mt, ms)):
            nframes += 1
            if ba != bb:
                bad += 1; print('MISMATCH', r['name'], ka)
    assert bad == 0
    # originals unchanged: dat prefix/suffix bytes, all original effects & missiles, sampled outfits and sprites
    for lst_o, lst_m in ((od.effects, md.effects), (od.missiles, md.missiles)):
        for to, tm in zip(lst_o, lst_m):
            assert od.data[to.raw[0]:to.raw[1]] == md.data[tm.raw[0]:tm.raw[1]], (to.cat, to.id)
    random.seed(1)
    for i in random.sample(range(1, len(od.outfits) + 1), min(60, len(od.outfits))):
        assert od.data[od.outfits[i - 1].raw[0]:od.outfits[i - 1].raw[1]] == md.data[md.outfits[i - 1].raw[0]:md.outfits[i - 1].raw[1]]
    for sid in random.sample(range(1, cnt + 1), 3000):
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    print(f'verified: merged dat parses ({md.variant}); {len(mapping)} added things x all frames/patterns = {nframes} frames '
          f'pixel-identical to source; all {ne} original effects, {nm} missiles, 60 outfits and 3000 sprites unchanged; '
          f'{ms.count} sprites')


if __name__ == '__main__':
    main()
