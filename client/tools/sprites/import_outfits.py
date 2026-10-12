#!/usr/bin/env python3
"""Import outfits from a donor dat/spr of ANOTHER format (e.g. an 8.60-flag dat) into COPIES of our 10.98 pair.

python3 -I import_outfits.py --src-dat DONOR.dat --src-spr DONOR.spr --ours-dat Tibia.dat --ours-spr Tibia.spr \
        --looks 1719,1718,1656 --expect-first 1502 --out-dir out/monsters  [--preview DIR]

merge_outfits.py copies dat entries byte for byte and is only valid when the donor dat uses our flag table.  This tool
converts each entry instead:
* flags are read by name (datspr, donor variant auto-detected) and re-encoded with our 10.98 table (TABLE_NEW), in
  ascending byte order.  Custom flag bytes (datspr DEFAULT_EXTRA) are stripped, as merge_outfits.py does; a flag our
  table has no byte for, or a market flag, stops the run.
* frame groups (idle / walking), sizes, exact size, layers, patterns, phases and the animator (async, loop count,
  start phase, per-phase min/max ms) are kept exactly.  A donor without frame groups gets one idle group (our outfits
  have them); a donor without animator data is refused when an entry is animated.
* sprites: the donor records are checked to decode exactly with our record layout (colour key, u16 size, runs of u16
  transparent / u16 coloured pixels, 4-byte RGBA when both files are alpha sprs) and are then copied byte for byte;
  otherwise they are decoded and re-encoded with gen_effects.encode_sprite.  Identical records are written once,
  empty donor sprites become id 0.  New records are appended to our spr (offset table grows, old records copied).
* new outfit ids = our outfit count + 1, +2, ... in the order of --looks.  --expect-first makes the run fail when the
  input pair is not the one the ids were planned for (the server monster XML files use these ids).  --first-outfit N
  instead pads the outfit list with blank outfits (no sprite, as import_art_things.py) so the first new id is N on any
  input pair with fewer outfits: stable ids when other looks were appended before (the run stops when the input already
  has N or more outfits).
Outputs in --out-dir: Tibia.dat, Tibia.spr, import_outfits.csv (donor lookType -> new lookType).  Inputs are never
modified.  Deterministic: the same inputs give byte-identical outputs.
Verification (always run): the output is re-parsed; every sprite slot of every group/frame/direction/addon/layer of
the new outfits decodes pixel-identical to the donor slot, and every composed frame (all groups, phases, directions,
addons, base layer) renders pixel-identical; flags and animator equal the donor's; all old dat entries are byte
identical; 3000 sampled old sprites (plus the first and last) are unchanged; then check_pair.py's append-only guard
(every old thing and sprite record byte-identical, the new outfits and sprites valid for the client).
"""
import sys, os, csv, struct, argparse, random, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image
from datspr import Dat, Spr, TABLE_NEW, _DATA, sprite_index
from set_multiuse import flag_spans

NEW_BYTE = {name: b for b, name in TABLE_NEW.items()}
BLANK_OUTFIT = b'\xff' + bytes([1, 0, 1, 1, 1, 1, 1, 1, 1]) + struct.pack('<I', 0)   # one idle group, 1x1, no sprite


class Group:
    """one frame group of an outfit entry (enough attributes for datspr.sprite_index)."""
    __slots__ = ('gtype', 'w', 'h', 'exact', 'layers', 'px', 'py', 'pz', 'phases', 'anim', 'sprites')


def parse_body(dat, t):
    """flags end offset + full list of frame groups of thing t (datspr keeps only the first group's sprites)."""
    _table, animator, u32, pz_present, fg = dat.variant
    d = dat.data
    _spans, pos = flag_spans(dat, t.raw[0])
    pos += 1                                         # 0xFF
    groups = []
    ngroups = 1
    if fg:
        ngroups = d[pos]; pos += 1
    for _ in range(ngroups):
        g = Group()
        g.gtype = 0
        if fg:
            g.gtype = d[pos]; pos += 1
        g.w, g.h = d[pos], d[pos + 1]; pos += 2
        g.exact = 32
        if g.w > 1 or g.h > 1:
            g.exact = d[pos]; pos += 1
        g.layers, g.px, g.py = d[pos], d[pos + 1], d[pos + 2]; pos += 3
        g.pz = 1
        if pz_present:
            g.pz = d[pos]; pos += 1
        g.phases = d[pos]; pos += 1
        g.anim = None
        if g.phases > 1:
            if not animator:
                raise SystemExit(f'{t}: animated entry in a dat without animator data (not supported)')
            asyn, loop, start = struct.unpack_from('<Bib', d, pos); pos += 6
            durs = struct.unpack_from('<' + 'II' * g.phases, d, pos); pos += 8 * g.phases
            g.anim = (asyn, loop, start, durs)
        ns = g.w * g.h * g.layers * g.px * g.py * g.pz * g.phases
        g.sprites = struct.unpack_from(f'<{ns}{"I" if u32 else "H"}', d, pos); pos += (4 if u32 else 2) * ns
        groups.append(g)
    assert pos == t.raw[1], (t, pos, t.raw)
    return groups


def encode_flags(t, ours_extra):
    """flags of donor thing t (by name) -> bytes in our 10.98 table; returns (bytes, stripped names)."""
    out, stripped = [], []
    for name, val in t.flags.items():
        if name.startswith('x') and name[1:].isdigit():
            stripped.append(name); continue
        if name == 'market' or name not in NEW_BYTE:
            raise SystemExit(f'{t}: flag {name!r} cannot be converted')
        kind = _DATA.get(name)
        b = bytes([NEW_BYTE[name]])
        if kind is None:
            pass
        elif kind == 'u16':
            b += struct.pack('<H', val)
        elif kind == 'u16x2':
            b += struct.pack('<HH', *val)
        else:
            raise SystemExit(f'{t}: flag {name!r} of kind {kind} not handled')
        out.append((NEW_BYTE[name], b))
    return b''.join(b for _, b in sorted(out)), stripped


def build_entry(flags, groups, sid_map):
    """our 10.98 outfit entry: flags, 0xFF, group count, per group: type, size, [exact], layers, px, py, pz, phases,
    [animator], u32 sprite ids."""
    e = bytearray(flags) + b'\xff' + bytes([len(groups)])
    for g in groups:
        e += bytes([g.gtype, g.w, g.h])
        if g.w > 1 or g.h > 1:
            e += bytes([g.exact])
        e += bytes([g.layers, g.px, g.py, g.pz, g.phases])
        if g.phases > 1:
            asyn, loop, start, durs = g.anim
            e += struct.pack('<Bib', asyn, loop, start) + struct.pack('<' + 'II' * g.phases, *durs)
        e += struct.pack(f'<{len(g.sprites)}I', *[sid_map[s] for s in g.sprites])
    return bytes(e)


def record_bytes(spr, sid):
    o = int(spr.offs[sid - 1]); ln = struct.unpack_from('<H', spr.m, o + 3)[0]
    return bytes(spr.m[o:o + 5 + ln])


def frame(g, spr, x, y, z, phase, layer=0):
    """compose one frame of a group (one layer) as a uint8 RGBA array (h*32, w*32)."""
    W, H = g.w * 32, g.h * 32
    cv = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for hh in range(g.h):
        for ww in range(g.w):
            a = spr.sprite(g.sprites[sprite_index(g, x, y, z, layer, phase, ww, hh)])
            if a is not None:
                cv.alpha_composite(Image.fromarray(a, 'RGBA'), ((g.w - 1 - ww) * 32, (g.h - 1 - hh) * 32))
    return np.asarray(cv)


def frames_of(g):
    return [(x, y, z, ph) for ph in range(g.phases) for z in range(g.pz) for y in range(g.py) for x in range(g.px)]


def preview_sheet(groups, spr, path):
    """one row per group/addon pattern: every direction x phase, base layer, on a grey background."""
    rows = [(gi, y) for gi, g in enumerate(groups) for y in range(g.py)]
    cw = max(g.w for g in groups) * 32 + 4; ch = max(g.h for g in groups) * 32 + 4
    ncols = max(g.px * g.phases for g in groups)
    sheet = Image.new('RGBA', (ncols * cw, len(rows) * ch), (96, 96, 96, 255))
    for r, (gi, y) in enumerate(rows):
        g = groups[gi]; c = 0
        for x in range(g.px):
            for ph in range(g.phases):
                im = Image.fromarray(frame(g, spr, x, y, 0, ph))
                sheet.alpha_composite(im, (c * cw + 2 + cw - 4 - im.width, r * ch + 2 + ch - 4 - im.height)); c += 1
    sheet.convert('RGB').resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--src-dat', required=True); ap.add_argument('--src-spr', required=True)
    ap.add_argument('--ours-dat', required=True); ap.add_argument('--ours-spr', required=True)
    ap.add_argument('--looks', required=True, help='donor lookTypes, in the order the new ids are given')
    ap.add_argument('--expect-first', type=int, default=None, help='fail unless the first new id is this')
    ap.add_argument('--first-outfit', type=int, default=None,
                    help='pad with blank outfits so the first new id is this (stable ids on any smaller input pair)')
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--preview', default=None, help='directory for PNG sheets of the imported outfits')
    a = ap.parse_args()
    t0 = time.time()
    os.makedirs(a.out_dir, exist_ok=True)
    for p in (a.ours_dat, a.ours_spr):
        assert os.path.abspath(os.path.dirname(p)) != os.path.abspath(a.out_dir), 'out-dir must differ from the input dir'
    looks = [int(x) for x in a.looks.split(',')]
    assert len(set(looks)) == len(looks), 'duplicate lookType'

    od = Dat(a.ours_dat); ospr = Spr(a.ours_spr)
    sd = Dat(a.src_dat); sspr = Spr(a.src_spr)
    assert od.variant[0] == 'new' and all(od.variant[1:]), f'expected our 10.98 dat (animator, u32, frame groups): {od.variant}'
    assert ospr.u32count and ospr.alpha, 'expected an alpha spr with u32 count'
    print(f'ours: dat {od.signature:#x} {od.variant} outfits {len(od.outfits)}; spr {ospr.signature:#x} {ospr.count} sprites')
    print(f'donor: dat {sd.signature:#x} {sd.variant} outfits {len(sd.outfits)}; spr {sspr.signature:#x} {sspr.count} '
          f'sprites alpha={sspr.alpha}')
    nours = len(od.outfits)
    pad = 0
    if a.first_outfit is not None:
        if a.first_outfit <= nours:
            sys.exit(f'--first-outfit {a.first_outfit} is not above the last outfit {nours} of the input (wrong pair, or already imported)')
        pad = a.first_outfit - nours - 1
    if a.expect_first is not None and nours + pad + 1 != a.expect_first:
        sys.exit(f'first new id would be {nours + pad + 1}, expected {a.expect_first}: wrong input pair (or already imported)')

    # --- 1. donor entries
    src = []
    for look in looks:
        t = sd.outfit(look)
        if t is None:
            sys.exit(f'donor has no outfit {look}')
        groups = parse_body(sd, t)
        assert groups[0].sprites == tuple(t.sprites), look
        if not any(s for g in groups for s in g.sprites):
            sys.exit(f'donor outfit {look} has no sprites')
        flags, stripped = encode_flags(t, od.extra)
        if not sd.variant[4]:
            assert len(groups) == 1
        src.append((look, t, groups, flags, stripped))

    # --- 2. sprite records
    same_layout = sspr.alpha == ospr.alpha
    sid_map, recs, newrecs = {0: 0}, {}, []
    copied = reenc = 0
    base = ospr.count
    if not same_layout:
        from gen_effects import encode_sprite
    for look, t, groups, flags, stripped in src:
        for g in groups:
            for sid in g.sprites:
                if sid in sid_map:
                    continue
                if sid > sspr.count or not sspr.offs[sid - 1] or sspr.sprite(sid) is None or not sspr.sprite(sid)[:, :, 3].any():
                    sid_map[sid] = 0; continue
                if same_layout and sspr._record_ok(sid, sspr.alpha):
                    rec = record_bytes(sspr, sid); copied += 1
                else:
                    rec = encode_sprite(sspr.sprite(sid)); reenc += 1
                if rec not in recs:
                    newrecs.append(rec); recs[rec] = base + len(newrecs)
                sid_map[sid] = recs[rec]

    # --- 3. dat
    entries = [BLANK_OUTFIT] * pad + [build_entry(flags, groups, sid_map) for look, t, groups, flags, stripped in src]
    d = od.data
    ins = od.effects[0].raw[0]
    assert od.outfits[-1].raw[1] == ins
    out = bytearray(d[:ins]) + b''.join(entries) + d[ins:]
    struct.pack_into('<H', out, 6, nours + len(entries))
    open(os.path.join(a.out_dir, 'Tibia.dat'), 'wb').write(out)

    # --- 4. spr (streamed: bigger table, old records shifted by 4*n, new records appended)
    m = ospr.m; cnt = ospr.count; nn = len(newrecs)
    old_table_end = 8 + 4 * cnt
    toffs = ospr.offs.astype('<u8').copy(); toffs[toffs > 0] += 4 * nn
    cur = len(m) + 4 * nn
    new_offs = []
    for rec in newrecs:
        new_offs.append(cur); cur += len(rec)
    assert cur < 1 << 32, 'spr would exceed 4 GB'
    table = np.concatenate([toffs, np.array(new_offs, dtype='<u8')]).astype('<u4')
    with open(os.path.join(a.out_dir, 'Tibia.spr'), 'wb') as f:
        f.write(struct.pack('<II', ospr.signature, cnt + nn)); f.write(table.tobytes())
        pos = old_table_end
        while pos < len(m):
            f.write(m[pos:pos + (1 << 24)]); pos += 1 << 24
        for rec in newrecs:
            f.write(rec)

    with open(os.path.join(a.out_dir, 'import_outfits.csv'), 'w', newline='') as fh:
        w = csv.writer(fh); w.writerow(['donor_lookType', 'new_lookType', 'groups', 'sprites', 'stripped_flags'])
        for i, (look, t, groups, flags, stripped) in enumerate(src):
            w.writerow([look, nours + pad + 1 + i, ' '.join(f'{g.w}x{g.h}L{g.layers}P{g.px}{g.py}{g.pz}F{g.phases}' for g in groups),
                        sum(len(g.sprites) for g in groups), ' '.join(stripped)])
            print(f'  donor {look} -> {nours + pad + 1 + i}: ' + ', '.join(
                f'group {g.gtype} {g.w}x{g.h} layers {g.layers} patterns {g.px}x{g.py}x{g.pz} phases {g.phases}' for g in groups)
                + (f'; flags {sorted(t.flags)}' if t.flags else '; no flags') + (f'; stripped {stripped}' if stripped else ''))
    print(f'dat: outfits {nours} -> {nours + len(entries)} ({pad} blank padding); spr: {copied} records copied, {reenc} re-encoded, '
          f'{nn} appended ({cnt} -> {cnt + nn})')

    # --- 5. verification
    md = Dat(os.path.join(a.out_dir, 'Tibia.dat')); ms = Spr(os.path.join(a.out_dir, 'Tibia.spr'))
    assert md.variant == od.variant, md.variant
    assert md.counts == (od.counts[0], nours + len(entries), od.counts[2], od.counts[3]), md.counts
    assert ms.count == cnt + nn and md.max_sprite <= ms.count and ms.alpha == ospr.alpha and ms.signature == ospr.signature
    assert md.data[:6] == d[:6] and md.data[8:ins] == d[8:ins], 'items/old outfits changed'
    assert md.data[ins + sum(map(len, entries)):] == d[ins:], 'effects/missiles changed'
    for to in od.outfits:
        tm = md.outfits[to.id - 1]
        assert md.data[tm.raw[0]:tm.raw[1]] == d[to.raw[0]:to.raw[1]], to.id
    nslots = nframes = 0
    for i, (look, t, groups, flags, stripped) in enumerate(src):
        nid = nours + pad + 1 + i
        tm = md.outfit(nid)
        mg = parse_body(md, tm)
        assert {k: v for k, v in tm.flags.items() if k not in stripped} == {k: v for k, v in t.flags.items() if k not in stripped}, nid
        assert len(mg) == len(groups), nid
        for g, h in zip(groups, mg):
            assert (g.gtype, g.w, g.h, g.exact, g.layers, g.px, g.py, g.pz, g.phases, g.anim) == \
                   (h.gtype, h.w, h.h, h.exact, h.layers, h.px, h.py, h.pz, h.phases, h.anim), (nid, 'group')
            for s0, s1 in zip(g.sprites, h.sprites):
                x, y = sspr.sprite(s0), ms.sprite(s1)
                if x is not None and not x[:, :, 3].any():
                    x = None
                assert (x is None) == (y is None) and (x is None or np.array_equal(x, y)), (nid, s0, s1)
                nslots += 1
            for (x, y, z, ph) in frames_of(g):
                for layer in range(g.layers):
                    if not np.array_equal(frame(g, sspr, x, y, z, ph, layer), frame(h, ms, x, y, z, ph, layer)):
                        sys.exit(f'MISMATCH new outfit {nid} (donor {look}) group {g.gtype} x{x} y{y} z{z} phase {ph} layer {layer}')
                nframes += 1
    for k in range(pad):
        tb = md.outfit(nours + 1 + k)
        assert md.data[tb.raw[0]:tb.raw[1]] == BLANK_OUTFIT, ('padding', nours + 1 + k)
    random.seed(1)
    for sid in random.sample(range(1, cnt + 1), min(3000, cnt)) + [1, cnt]:
        x, y = ospr.sprite(sid), ms.sprite(sid)
        assert (x is None) == (y is None) and (x is None or (x == y).all()), sid
    print(f'verified: output dat parses ({md.variant}), {len(md.outfits)} outfits, {ms.count} sprites; '
          f'{pad} blank padding outfits; {len(entries) - pad} imported outfits: {nslots} sprite slots and {nframes} frames (every group, phase, direction, '
          f'addon) pixel-identical to the donor, flags/animator equal; {nours} old outfits and all items/effects/missiles '
          f'byte-identical; 3000 sampled old sprites unchanged')

    from check_pair import check_append_only
    check_append_only(a.ours_dat, a.ours_spr, os.path.join(a.out_dir, 'Tibia.dat'), os.path.join(a.out_dir, 'Tibia.spr'))

    if a.preview:
        os.makedirs(a.preview, exist_ok=True)
        for i, (look, t, groups, flags, stripped) in enumerate(src):
            nid = nours + pad + 1 + i
            p = os.path.join(a.preview, f'outfit_{nid}.png')
            preview_sheet(parse_body(md, md.outfit(nid)), ms, p)
            print('preview', p)
    print(f'done in {time.time() - t0:.1f}s')


if __name__ == '__main__':
    main()
