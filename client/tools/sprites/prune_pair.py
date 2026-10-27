#!/usr/bin/env python3
"""Prune a 10.98 Tibia.dat / Tibia.spr pair: blank the things the game does not use, drop the sprites nothing
refers to, renumber the sprites, and keep an archive of what was taken out (pair 51, built from pair 50).

python3 -I prune_pair.py prune --dat IN.dat --spr IN.spr --removed pair51_removed.csv --out-dir OUT
                              [--archive-dir ARCH] [--strip-flags] [--expect-dat-md5 MD5]
python3 -I prune_pair.py check-map --dat IN.dat --removed pair51_removed.csv --map MAP.otbm --otb items.otb
python3 -I prune_pair.py keep-names --removed pair51_removed.csv [--repo REPO]
    drops every effect / missile that scripts, tables or xml use BY NAME (quoted catalog name, its base without a
    direction / number suffix, or a prefix used in a concatenation) from the list; `prune` refuses a list that names one.
python3 -I prune_pair.py stats --dat IN.dat --spr IN.spr --removed pair51_removed.csv

The removed list is a CSV with the columns `kind,id,reason` (kind: item, outfit, effect or missile; id: the client id
of the item, the look type, the effect or the missile id; reason: one short line, free text). Only those things are
blanked. Everything else stays: byte for byte the same entry, with its sprite ids renumbered. To keep a thing the
list names, delete its row and run again.

What `prune` writes (OUT/Tibia.dat, OUT/Tibia.spr):
  * Every id stays. A blanked thing keeps its flag bytes (so the client's walk prediction, light and stack rules
    for the id stay as they were; `--strip-flags` drops them too) and gets one 1x1 frame with sprite 0 (the client
    draws nothing there; check_pair reports it as `thing-empty`, a warning). An outfit keeps one idle frame group.
    The header (counts, signature) is unchanged: no id moves, so the server's items.otb, the Lua tables and the
    client's id tables still match.
  * The spr holds only the records that a kept thing refers to, in the order of their old ids, and the dat is
    rewritten with the new sprite ids. Sprite ids that were empty slots become 0 (the same: nothing is drawn).
    Records several sprite ids shared (one offset) are still shared. Records are copied byte for byte.
  * Sprites no thing referred to before are dropped too.

What `--archive-dir ARCH` adds (ARCH/Tibia.dat, ARCH/Tibia.spr, also a valid pair): the original ids and the
original sprite ids; only the blanked things are there (entry as before, flags and sprites), every other thing is a
blank padding entry and the spr holds only the records those things use. To put a thing back, import it from the
archive into the live pair like any other art (its sprites go to new ids), or run `restore` (below).

python3 -I prune_pair.py restore --dat PRUNED.dat --spr PRUNED.spr --archive-dat A.dat --archive-spr A.spr
                                 --ids item:123,effect:4000-4010 --out-dir OUT
  appends the archive's sprites the things need at the end of the pair (new ids), puts the archive entries back
  at their ids and writes OUT/Tibia.dat, OUT/Tibia.spr.

`check-map` lists, per blanked item, how many times it stands on a map (needs numpy; reads the map with
tools/map/otbm.py and the item ids with tools/map/itemdb.py): run it on the live map before shipping a pruned pair.

Pure Python for prune / restore / stats (no numpy, no Pillow). The spr is mapped, never loaded whole.
"""
import argparse
import array
import csv
import hashlib
import mmap
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
sys.path.insert(0, HERE)
import check_pair as cp  # noqa: E402

CATS = cp.CATS                      # item, outfit, effect, missile
FIRST = cp.FIRST
BLANK_PART = bytes([1, 1, 1, 1, 1, 1, 1]) + struct.pack('<I', 0)             # w h layers px py pz phases, sprite 0
BLANK_OUTFIT_PART = bytes([1, 0]) + bytes([1, 1, 1, 1, 1, 1, 1]) + struct.pack('<I', 0)   # one idle group + the same
SPR_HEAD = 8


class PruneError(Exception):
    pass


# ------------------------------------------------------------------ dat

def group_size(g, outfit):
    n = 2 + (1 if g.w > 1 or g.h > 1 else 0) + 5 + (6 + 8 * g.phases if g.phases > 1 else 0) + 4 * len(g.sprites)
    return n + (1 if outfit else 0)


def entry_layout(data, t):
    """-> (offset just after the 0xFF end byte of the flags, [(offset of the sprite array, count) per group])"""
    outfit = t.cat == 'outfit'
    total = (1 if outfit else 0) + sum(group_size(g, outfit) for g in t.groups)
    flags_end = t.end - total
    pos = flags_end + (1 if outfit else 0)
    slots = []
    for g in t.groups:
        pos += 1 if outfit else 0
        pos += 2 + (1 if g.w > 1 or g.h > 1 else 0) + 5 + (6 + 8 * g.phases if g.phases > 1 else 0)
        slots.append((pos, len(g.sprites)))
        pos += 4 * len(g.sprites)
    if pos != t.end or data[flags_end - 1] != 0xFF:
        raise PruneError(f'{t.ref}: cannot lay out the entry (offset {t.start})')
    return flags_end, slots


def blank_entry(data, t, strip_flags=False):
    if strip_flags:
        head = b'\xff'
    else:
        flags_end, _ = entry_layout(data, t)
        head = bytes(data[t.start:flags_end])
    return head + (BLANK_OUTFIT_PART if t.cat == 'outfit' else BLANK_PART)


def read_removed(path):
    """-> {(cat, id): reason}"""
    out = {}
    with open(path, newline='', encoding='utf-8') as f:
        for r in csv.DictReader(f):
            kind = (r.get('kind') or '').strip()
            if kind not in CATS:
                raise PruneError(f'{path}: unknown kind {kind!r} (item, outfit, effect or missile)')
            out[(kind, int(r['id']))] = (r.get('reason') or '').strip()
    return out


def check_removed(removed, things):
    for cat, i in removed:
        lo = FIRST[cat]
        if not (lo <= i < lo + len(things[cat])):
            raise PruneError(f'the removed list names {cat} {i}, which the dat does not hold')


# ------------------------------------------------------------------ spr

class Spr:
    """read-only view of a spr: offsets as an array('I'), records through mmap"""

    def __init__(self, path):
        self.f = open(path, 'rb')
        self.m = mmap.mmap(self.f.fileno(), 0, access=mmap.ACCESS_READ)
        self.signature, self.count = struct.unpack_from('<II', self.m, 0)
        if SPR_HEAD + 4 * self.count > len(self.m):
            raise PruneError(f'{path}: the offset table does not fit the file')
        self.offs = array.array('I')
        self.offs.frombytes(self.m[SPR_HEAD:SPR_HEAD + 4 * self.count])
        if sys.byteorder == 'big':
            self.offs.byteswap()

    def record(self, sid):
        """the record's bytes (header + pixel data) or None for an empty slot"""
        o = self.offs[sid - 1]
        if not o:
            return None
        size = struct.unpack_from('<H', self.m, o + 3)[0]
        return self.m[o:o + 5 + size]

    def close(self):
        self.m.close()
        self.f.close()


def write_spr(path, signature, count, sids_in_order, spr, newid_of_sid=None):
    """Write a spr of `count` slots to `path`.
    sids_in_order: old sprite ids whose records are copied, in the order they are written.
    newid_of_sid: {old id: new id} (default: the id stays). A record shared by several old ids (the same offset)
    is written once. Returns {old offset: new offset}."""
    offs_new = array.array('I', bytes(4 * count))
    written = {}
    pos = SPR_HEAD + 4 * count
    with open(path, 'wb') as out:
        out.write(struct.pack('<II', signature, count))
        out.write(bytes(4 * count))
        for sid in sids_in_order:
            o = spr.offs[sid - 1]
            if not o:
                continue
            nid = sid if newid_of_sid is None else newid_of_sid[sid]
            if o in written:
                offs_new[nid - 1] = written[o]
                continue
            size = struct.unpack_from('<H', spr.m, o + 3)[0]
            out.write(spr.m[o:o + 5 + size])
            written[o] = pos
            offs_new[nid - 1] = pos
            pos += 5 + size
        out.seek(SPR_HEAD)
        if sys.byteorder == 'big':
            offs_new.byteswap()
        out.write(offs_new.tobytes())
    return written


def md5_of(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 22), b''):
            h.update(chunk)
    return h.hexdigest()


# ------------------------------------------------------------------ prune

def used_sprites(things, removed):
    """{sprite id} referenced by the things that stay"""
    used = set()
    for cat in CATS:
        for t in things[cat]:
            if (cat, t.id) in removed:
                continue
            for g in t.groups:
                used.update(g.sprites)
    used.discard(0)
    return used


def prune(dat_path, spr_path, removed_path, out_dir, archive_dir=None, strip_flags=False, log=print, repo=None):
    removed = read_removed(removed_path)
    if repo:
        bad = name_conflicts(removed, repo)
        if bad:
            raise PruneError('the removed list names effects / missiles that scripts use by name: ' +
                             ', '.join(f'{k[0]} {k[1]} ({n})' for k, n in bad[:10]) +
                             (f' ... ({len(bad)} in all)' if len(bad) > 10 else '') + '; run keep-names')
    data = open(dat_path, 'rb').read()
    sig, counts, things, end = cp.parse_dat(data)
    if end != len(data):
        raise PruneError(f'{dat_path}: {len(data) - end} bytes after the last missile')
    check_removed(removed, things)
    spr = Spr(spr_path)
    used = used_sprites(things, removed)

    # new sprite ids: the kept records in the order of their old ids; an id with no record becomes 0
    order = sorted(s for s in used if 0 < s <= spr.count and spr.offs[s - 1])
    newid = {}
    for n, s in enumerate(order, 1):
        newid[s] = n
    remap = array.array('I', bytes(4 * (spr.count + 1)))
    for s, n in newid.items():
        remap[s] = n
    # sprites that share a record keep sharing it: their ids are still two ids, the record is written once

    os.makedirs(out_dir, exist_ok=True)
    out_dat = os.path.join(out_dir, 'Tibia.dat')
    out_spr = os.path.join(out_dir, 'Tibia.spr')
    parts = [data[:12]]
    n_blank = 0
    for cat in CATS:
        for t in things[cat]:
            if (cat, t.id) in removed:
                parts.append(blank_entry(data, t, strip_flags))
                n_blank += 1
                continue
            e = bytearray(data[t.start:t.end])
            _, slots = entry_layout(data, t)
            for pos, ns in slots:
                pos -= t.start
                ids = struct.unpack_from(f'<{ns}I', e, pos)
                struct.pack_into(f'<{ns}I', e, pos, *[remap[s] if 0 < s <= spr.count else 0 for s in ids])
            parts.append(bytes(e))
    with open(out_dat, 'wb') as f:
        f.write(b''.join(parts))
    write_spr(out_spr, spr.signature, len(order), order, spr, newid)
    log(f'prune: {n_blank} things blanked; sprites {spr.count} -> {len(order)}; '
        f'dat {len(data)} -> {os.path.getsize(out_dat)} bytes, spr {os.path.getsize(spr_path)} -> {os.path.getsize(out_spr)} bytes')

    if archive_dir:
        make_archive(data, things, removed, spr, archive_dir, log)
    verify(data, things, removed, spr, out_dat, out_spr, newid, log)
    old_count = spr.count
    spr.close()
    return {'blanked': n_blank, 'sprites_old': old_count, 'sprites_new': len(order), 'dat': out_dat, 'spr': out_spr}


def make_archive(data, things, removed, spr, archive_dir, log=print):
    os.makedirs(archive_dir, exist_ok=True)
    parts = [data[:12]]
    sids = set()
    for cat in CATS:
        for t in things[cat]:
            if (cat, t.id) in removed:
                parts.append(bytes(data[t.start:t.end]))
                for g in t.groups:
                    sids.update(g.sprites)
            else:
                parts.append(blank_entry(data, t, strip_flags=True))
    sids.discard(0)
    adat = os.path.join(archive_dir, 'Tibia.dat')
    aspr = os.path.join(archive_dir, 'Tibia.spr')
    with open(adat, 'wb') as f:
        f.write(b''.join(parts))
    write_spr(aspr, spr.signature, spr.count, sorted(s for s in sids if 0 < s <= spr.count), spr)
    log(f'archive: {len(removed)} things, {len(sids)} sprites; dat {os.path.getsize(adat)} bytes, spr {os.path.getsize(aspr)} bytes')


def verify(data, things, removed, spr, out_dat, out_spr, newid, log=print):
    """re-parse the output: same counts, same ids, kept entries equal except sprite ids, every mapped sprite record
    byte for byte the old one, blanked things blank"""
    ndata = open(out_dat, 'rb').read()
    nsig, ncounts, nthings, nend = cp.parse_dat(ndata)
    if (nsig,) + tuple(ncounts) != struct.unpack_from('<IHHHH', data, 0):
        raise PruneError('verify: the header changed')
    if nend != len(ndata):
        raise PruneError('verify: bytes after the last missile')
    nspr = Spr(out_spr)
    for cat in CATS:
        if len(nthings[cat]) != len(things[cat]):
            raise PruneError(f'verify: {cat} count changed')
        for t, n in zip(things[cat], nthings[cat]):
            if (cat, t.id) in removed:
                if len(n.groups) != 1 or len(n.groups[0].sprites) != 1 or n.groups[0].sprites[0] != 0:
                    raise PruneError(f'verify: {t.ref} is not blank')
                continue
            if [b for b, _, _ in n.flags] != [b for b, _, _ in t.flags]:
                raise PruneError(f'verify: {t.ref} flags changed')
            for g, ng in zip(t.groups, n.groups):
                if (g.w, g.h, g.layers, g.px, g.py, g.pz, g.phases, g.anim, g.gtype) != \
                        (ng.w, ng.h, ng.layers, ng.px, ng.py, ng.pz, ng.phases, ng.anim, ng.gtype):
                    raise PruneError(f'verify: {t.ref} dims changed')
                for s, ns in zip(g.sprites, ng.sprites):
                    if s == 0 or s > spr.count or not spr.offs[s - 1]:
                        if ns != 0:
                            raise PruneError(f'verify: {t.ref} empty slot {s} -> {ns}')
                    elif spr.record(s) != nspr.record(ns):
                        raise PruneError(f'verify: {t.ref} sprite {s} -> {ns} differs')
    nspr.close()
    log('verify: ok (header, ids, flags, dims, every kept sprite record byte for byte)')


# ------------------------------------------------------------------ names

import re  # noqa: E402

CATALOG_RE = re.compile(r'\b(ChaosVfxMissile|ChaosFxMissile|ChaosVfx|ChaosFx)\.([A-Za-z0-9_]+)\s*=\s*\{\s*id\s*=\s*(\d+)')
SUFFIX_RE = re.compile(r'_(?:n|s|e|w|ne|nw|se|sw|N|\d+)$')
QUOTED_RE = re.compile(r"""["']([A-Za-z0-9_]+)["']""")
PREFIX_RE = re.compile(r"""["']([A-Za-z0-9_]+_)["']\s*\.\.""")
# a keyed table value: fx = "name", [CONST_ANI_FIRE] = "name", CONST_ME_X = "name" (also caught by QUOTED_RE; kept explicit)
KEYED_RE = re.compile(r"""(?:\bfx|\bCONST_ANI_[A-Z0-9_]+|\bCONST_ME_[A-Z0-9_]+)\]?\s*=\s*["']([A-Za-z0-9_]+)["']""")
SCAN_EXT = ('.lua', '.xml', '.json', '.otui')
SCAN_DIRS = ('server', 'client/overlay', 'website')
MAX_SCAN = 8 << 20


def is_catalog(rel):
    b = os.path.basename(rel)
    return (b == 'chaos_vfx.lua' or (b.startswith('chaos_') and 'fx' in b and b.endswith('_ids.lua'))
            or b in ('chaos_vfx_art.lua',))


def is_test(rel):
    b = os.path.basename(rel)
    parts = rel.replace(os.sep, '/').split('/')
    return b.endswith('_test.lua') or 'tests' in parts or 'tools' in parts


def catalog_names(repo):
    """{name: (kind, id)} from the effect / missile catalogs (kind: effect or missile)"""
    out = {}
    lib = os.path.join(repo, 'server', 'data', 'lib')
    if not os.path.isdir(lib):
        return out
    for fn in sorted(os.listdir(lib)):
        rel = os.path.join('server', 'data', 'lib', fn)
        if not (fn.endswith('.lua') and is_catalog(rel)):
            continue
        with open(os.path.join(lib, fn), encoding='utf-8', errors='replace') as f:
            for tbl, name, i in CATALOG_RE.findall(f.read()):
                out[name] = ('missile' if 'Missile' in tbl else 'effect', int(i))
    return out


def name_refs(repo):
    """-> (set of quoted strings, set of concatenation prefixes) found in the consumers: every .lua / .xml / .json / .otui
    of server, client/overlay and website that is neither a catalog nor a test or tool file"""
    words, prefixes = set(), set()
    for top in SCAN_DIRS:
        for dp, dn, fns in os.walk(os.path.join(repo, top)):
            for fn in fns:
                if not fn.endswith(SCAN_EXT):
                    continue
                path = os.path.join(dp, fn)
                rel = os.path.relpath(path, repo)
                if is_catalog(rel) or is_test(rel) or os.path.getsize(path) > MAX_SCAN:
                    continue
                with open(path, encoding='utf-8', errors='replace') as f:
                    txt = f.read()
                words.update(QUOTED_RE.findall(txt))
                words.update(KEYED_RE.findall(txt))
                prefixes.update(PREFIX_RE.findall(txt))
    return words, prefixes


def name_used(name, words, prefixes):
    if name in words:
        return True
    base = SUFFIX_RE.sub('', name)
    if base != name and base in words:
        return True
    return any(name.startswith(p) for p in prefixes)


# Things kept on review although no name in a script refers to them: pair51_keep.csv (kind,id,name,reason). These are
# pack 36 names reserved for spells that are not written yet, and one effect with no catalog name.
KEEP_FILE = os.path.join(HERE, 'pair51_keep.csv')


def keep_list():
    """{(kind, id): reason} from KEEP_FILE"""
    if not os.path.isfile(KEEP_FILE):
        return {}
    with open(KEEP_FILE, newline='', encoding='utf-8') as f:
        return {(r['kind'], int(r['id'])): r['reason'] for r in csv.DictReader(f)}


def used_by_name(repo):
    """{(kind, id): name or reason} of every catalog effect / missile a consumer refers to by name, every id of KEEP_FILE"""
    words, prefixes = name_refs(repo)
    out = {v: n for n, v in catalog_names(repo).items() if name_used(n, words, prefixes)}
    out.update(keep_list())
    return out


def name_conflicts(removed, repo):
    used = used_by_name(repo)
    return sorted((k, used[k]) for k in removed if k in used and k[0] in ('effect', 'missile'))


def keep_names(removed_path, repo, out_path=None, log=print):
    """drop from the removed list every effect / missile a consumer uses by name; rewrite the CSV (same order)"""
    used = used_by_name(repo)
    rows = []
    with open(removed_path, newline='', encoding='utf-8') as f:
        rdr = csv.DictReader(f)
        for r in rdr:
            rows.append(r)
    kept, dropped = [], []
    for r in rows:
        k = (r['kind'], int(r['id']))
        (dropped if k in used else kept).append(r)
    with open(out_path or removed_path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['kind', 'id', 'reason'])
        for r in kept:
            w.writerow([r['kind'], r['id'], r['reason']])
    n = {c: sum(1 for r in dropped if r['kind'] == c) for c in ('effect', 'missile')}
    log(f'keep-names: {len(dropped)} rows dropped ({n["effect"]} effects, {n["missile"]} missiles), {len(kept)} stay')
    return dropped


# ------------------------------------------------------------------ restore

def parse_ids(text):
    out = set()
    for part in text.split(','):
        part = part.strip()
        if not part:
            continue
        kind, _, rng = part.partition(':')
        if kind not in CATS:
            raise PruneError(f'unknown kind in {part!r}')
        lo, _, hi = rng.partition('-')
        for i in range(int(lo), int(hi or lo) + 1):
            out.add((kind, i))
    return out


def restore(dat_path, spr_path, adat_path, aspr_path, ids, out_dir, log=print):
    """put archive things back: their sprites are appended (new ids), the entries replace the blanks"""
    data = open(dat_path, 'rb').read()
    adata = open(adat_path, 'rb').read()
    _, counts, things, end = cp.parse_dat(data)
    _, acounts, athings, aend = cp.parse_dat(adata)
    if counts != acounts:
        raise PruneError('the archive and the pair have different header counts')
    check_removed(dict.fromkeys(ids), things)
    spr = Spr(spr_path)
    aspr = Spr(aspr_path)
    newid = {}
    nxt = spr.count
    append = []
    for cat, i in sorted(ids):
        t = athings[cat][i - FIRST[cat]]
        for g in t.groups:
            for s in g.sprites:
                if s and s not in newid and 0 < s <= aspr.count and aspr.offs[s - 1]:
                    nxt += 1
                    newid[s] = nxt
                    append.append(s)
    os.makedirs(out_dir, exist_ok=True)
    out_spr = os.path.join(out_dir, 'Tibia.spr')
    # one pass, no temporary copy (the spr is over 1 GiB): the new records are collected first, then the file is
    # written as head, grown offset table, the old records and the new records
    grown = len(append)
    add = 4 * grown
    old_size = os.path.getsize(spr_path)
    new_recs = []
    table_add = array.array('I')
    shared = {}
    pos = old_size + add
    for s in append:
        o = aspr.offs[s - 1]
        if o in shared:
            table_add.append(shared[o])
            continue
        rec = aspr.record(s)
        new_recs.append(rec)
        shared[o] = pos
        table_add.append(pos)
        pos += len(rec)
    with open(spr_path, 'rb') as src, open(out_spr, 'wb') as out:
        head = src.read(SPR_HEAD + 4 * spr.count)
        sig, cnt = struct.unpack_from('<II', head, 0)
        offs = array.array('I')
        offs.frombytes(head[SPR_HEAD:])
        offs = array.array('I', [o + add if o else 0 for o in offs])
        out.write(struct.pack('<II', sig, cnt + grown))
        out.write(offs.tobytes())
        out.write(table_add.tobytes())
        while True:
            chunk = src.read(1 << 22)
            if not chunk:
                break
            out.write(chunk)
        for rec in new_recs:
            out.write(rec)
    parts = [data[:12]]
    for cat in CATS:
        for t in things[cat]:
            if (cat, t.id) in ids:
                a = athings[cat][t.id - FIRST[cat]]
                e = bytearray(adata[a.start:a.end])
                _, slots = entry_layout(adata, a)
                for pos, ns in slots:
                    pos -= a.start
                    sids = struct.unpack_from(f'<{ns}I', e, pos)
                    struct.pack_into(f'<{ns}I', e, pos, *[newid.get(s, 0) for s in sids])
                parts.append(bytes(e))
            else:
                parts.append(bytes(data[t.start:t.end]))
    out_dat = os.path.join(out_dir, 'Tibia.dat')
    with open(out_dat, 'wb') as f:
        f.write(b''.join(parts))
    log(f'restore: {len(ids)} things, {grown} sprites appended (ids {spr.count + 1}-{spr.count + grown})')
    spr.close()
    aspr.close()


# ------------------------------------------------------------------ stats / check-map

def stats(dat_path, spr_path, removed_path, log=print):
    removed = read_removed(removed_path)
    data = open(dat_path, 'rb').read()
    _, counts, things, _ = cp.parse_dat(data)
    check_removed(removed, things)
    spr = Spr(spr_path)
    used = used_sprites(things, removed)
    keep_bytes = 0
    total = 0
    for s in range(1, spr.count + 1):
        r = spr.offs[s - 1]
        if r:
            size = 5 + struct.unpack_from('<H', spr.m, r + 3)[0]
            total += size
    seen = set()
    for s in used:
        r = spr.offs[s - 1] if 0 < s <= spr.count else 0
        if r and r not in seen:
            seen.add(r)
            keep_bytes += 5 + struct.unpack_from('<H', spr.m, r + 3)[0]
    log(f'record bytes {total} -> {keep_bytes} ({100 * (total - keep_bytes) / max(total, 1):.1f}% freed), '
        f'sprites in use {len(used)} of {spr.count}')
    spr.close()
    return total, keep_bytes


def check_map(dat_path, removed_path, map_path, otb_path, log=print):
    sys.path.insert(0, os.path.join(REPO, 'tools', 'map'))
    import numpy as np
    from otbm import load_map
    from itemdb import ItemDB
    removed = read_removed(removed_path)
    gone = {i for (c, i) in removed if c == 'item'}
    db = ItemDB(otb_path, os.devnull)
    m = load_map(map_path)
    ids, counts = np.unique(m.items, return_counts=True)
    bad = []
    for sid, n in zip(ids.tolist(), counts.tolist()):
        cid = int(db.cid[sid]) if sid < len(db.cid) else 0
        if cid in gone:
            bad.append((cid, sid, n))
    for cid, sid, n in sorted(bad):
        log(f'item client id {cid} (server id {sid}) is blanked and stands {n} times on {os.path.basename(map_path)}')
    log(f'check-map: {len(bad)} blanked item ids on the map')
    return bad


# ------------------------------------------------------------------ CLI

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('prune')
    p.add_argument('--dat', required=True)
    p.add_argument('--spr', required=True)
    p.add_argument('--removed', required=True)
    p.add_argument('--out-dir', required=True)
    p.add_argument('--archive-dir')
    p.add_argument('--strip-flags', action='store_true')
    p.add_argument('--expect-dat-md5')
    p.add_argument('--repo', default=REPO, help='repo root for the name check (default: this repo; "" skips it)')
    p = sub.add_parser('keep-names')
    p.add_argument('--removed', required=True)
    p.add_argument('--repo', default=REPO)
    p.add_argument('--out')
    p = sub.add_parser('stats')
    p.add_argument('--dat', required=True)
    p.add_argument('--spr', required=True)
    p.add_argument('--removed', required=True)
    p = sub.add_parser('check-map')
    p.add_argument('--dat', required=True)
    p.add_argument('--removed', required=True)
    p.add_argument('--map', required=True)
    p.add_argument('--otb', required=True)
    p = sub.add_parser('restore')
    p.add_argument('--dat', required=True)
    p.add_argument('--spr', required=True)
    p.add_argument('--archive-dat', required=True)
    p.add_argument('--archive-spr', required=True)
    p.add_argument('--ids', required=True)
    p.add_argument('--out-dir', required=True)
    a = ap.parse_args(argv)
    try:
        if a.cmd == 'prune':
            if a.expect_dat_md5 and md5_of(a.dat) != a.expect_dat_md5:
                raise PruneError(f'{a.dat} md5 {md5_of(a.dat)} is not {a.expect_dat_md5}')
            prune(a.dat, a.spr, a.removed, a.out_dir, a.archive_dir, a.strip_flags, repo=a.repo or None)
        elif a.cmd == 'keep-names':
            keep_names(a.removed, a.repo, a.out)
        elif a.cmd == 'stats':
            stats(a.dat, a.spr, a.removed)
        elif a.cmd == 'check-map':
            return 1 if check_map(a.dat, a.removed, a.map, a.otb) else 0
        else:
            restore(a.dat, a.spr, a.archive_dat, a.archive_spr, parse_ids(a.ids), a.out_dir)
    except (PruneError, cp.DatError) as e:
        print(f'prune_pair: {e}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
