#!/usr/bin/env python3
"""Split a 10.98 Tibia.spr into shard files the client loads in parallel (base patch 0048), and check them.

  split  SPR OUT_DIR [--name Tibia] [--per-shard 16384]
         Writes OUT_DIR/<name>.000.spr, <name>.001.spr, ... and the index OUT_DIR/<name>.sprshards. Shard k holds the
         sprites k*per_shard+1 .. (k+1)*per_shard (the last one the rest). Deterministic: the same .spr and settings
         give the same bytes (no dates, no paths). Shard files of an older split with a higher number are removed.
  verify SPR SHARD_DIR [--name Tibia]
         Checks the index (format, signature, ranges, sizes, SHA-256 of every shard) and that every sprite record
         (colour key, size, pixel runs) of every shard is byte-identical to the same id in SPR, empty ids included.
         Also joins the shards in memory and compares the MD5 with SPR (equal when SPR is in canonical layout:
         records in id order with no gaps, which is how our tools write it).
  check  SHARD_DIR [--name Tibia]
         The index part of verify without the source .spr (what make_update_manifest.py runs before publishing).
  join   SHARD_DIR OUT_SPR [--name Tibia]
         Writes one .spr again from the shards (canonical layout).

Shard file: a normal .spr with a u32 count: u32 signature, u32 count, count x u32 address (absolute in the shard,
0 = no sprite), then the records exactly as in the source. Two ids of one shard that share a record in the source
share it in the shard too. Index (<name>.sprshards, text, one item per line):
  chaos-spr-shards 1
  signature <u32>
  sprites <total>
  per-shard <n>
  shard <first id> <count> <file name> <size in bytes> <sha256>     (one line per shard, in id order)
The client (spritemanager.cpp) checks the format line, that the shards cover 1..sprites with no gap, every shard's
size and its header (signature, count); it does not hash the shards at start (the updater checked them).
Pure Python, no numpy / Pillow. Tests: spr_shards_test.py.
"""
import argparse
import array
import hashlib
import mmap
import os
import re
import struct
import sys

FORMAT_LINE = 'chaos-spr-shards 1'
DEFAULT_PER_SHARD = 16384
SHARD_NAME = re.compile(r'^(?P<name>.+)\.(?P<num>\d{3})\.spr$')


class ShardError(Exception):
    pass


# ---------------------------------------------------------------- reading a .spr

class Spr:
    """a .spr with a u32 sprite count (10.98 with GameSpritesU32): signature, count, address table, records"""

    def __init__(self, path):
        self.path = path
        self._f = open(path, 'rb')
        size = os.fstat(self._f.fileno()).st_size
        if size < 8:
            raise ShardError(f'{path}: too small for a .spr')
        self.data = mmap.mmap(self._f.fileno(), 0, access=mmap.ACCESS_READ)
        self.signature, self.count = struct.unpack_from('<II', self.data, 0)
        if 8 + 4 * self.count > size:
            raise ShardError(f'{path}: address table ({self.count} sprites) runs past the end of the file')
        self.addresses = array.array('I')
        self.addresses.frombytes(self.data[8:8 + 4 * self.count])
        if sys.byteorder != 'little':
            self.addresses.byteswap()

    def record(self, sid):
        """the raw record of sprite id `sid` (colour key, u16 size, data) or b'' when it has none"""
        addr = self.addresses[sid - 1]
        if addr == 0:
            return b''
        if addr + 5 > len(self.data):
            raise ShardError(f'{self.path}: sprite {sid} address {addr} is past the end of the file')
        n = struct.unpack_from('<H', self.data, addr + 3)[0]
        if addr + 5 + n > len(self.data):
            raise ShardError(f'{self.path}: sprite {sid} record runs past the end of the file')
        return self.data[addr:addr + 5 + n]

    def close(self):
        self.data.close()
        self._f.close()


# ---------------------------------------------------------------- pure parts (tests)

def shard_ranges(total, per_shard):
    """[(first id, count)] covering 1..total in blocks of per_shard; an empty .spr still gets one empty shard"""
    if per_shard < 1:
        raise ShardError('per-shard must be 1 or more')
    if total == 0:
        return [(1, 0)]
    return [(first, min(per_shard, total - first + 1)) for first in range(1, total + 1, per_shard)]


def shard_file_name(name, k):
    return '%s.%03d.spr' % (name, k)


def build_shard(signature, records):
    """bytes of one shard file. records: [(key, record bytes)] in id order, b'' for no sprite; key is the record's
    source address, so ids that shared one record in the source share it in the shard too"""
    count = len(records)
    head = bytearray(struct.pack('<II', signature, count))
    table = array.array('I', [0] * count)
    body = bytearray()
    base = 8 + 4 * count
    placed = {}
    for i, (key, rec) in enumerate(records):
        if not rec:
            continue
        if key in placed:
            table[i] = placed[key]
            continue
        addr = base + len(body)
        if addr > 0xFFFFFFFF:
            raise ShardError('shard larger than 4 GiB')
        placed[key] = addr
        table[i] = addr
        body += rec
    if sys.byteorder != 'little':
        table.byteswap()
    return bytes(head) + table.tobytes() + bytes(body)


def index_text(signature, total, per_shard, shards):
    """shards: [(first, count, file name, size, sha256)]"""
    lines = [FORMAT_LINE, 'signature %d' % signature, 'sprites %d' % total, 'per-shard %d' % per_shard]
    for first, count, fname, size, sha in shards:
        lines.append('shard %d %d %s %d %s' % (first, count, fname, size, sha))
    return '\n'.join(lines) + '\n'


def parse_index(text):
    """the index as a dict {signature, sprites, per_shard, shards: [(first, count, file, size, sha256)]}; raises
    ShardError on anything the client would refuse"""
    lines = [ln.strip() for ln in text.replace('\r\n', '\n').split('\n')]
    lines = [ln for ln in lines if ln and not ln.startswith('#')]
    if not lines or lines[0] != FORMAT_LINE:
        raise ShardError('not a sprite shard index (first line must be "%s")' % FORMAT_LINE)
    out = {'signature': None, 'sprites': None, 'per_shard': None, 'shards': []}
    for ln in lines[1:]:
        parts = ln.split()
        key = parts[0]
        if key in ('signature', 'sprites', 'per-shard') and len(parts) == 2 and parts[1].isdigit():
            out[key.replace('-', '_')] = int(parts[1])
        elif key == 'shard' and len(parts) == 6 and parts[1].isdigit() and parts[2].isdigit() and parts[4].isdigit():
            fname = parts[3]
            if '/' in fname or '\\' in fname or fname.startswith('.') or not fname.lower().endswith('.spr'):
                raise ShardError('bad shard file name: ' + fname)
            if not re.fullmatch(r'[0-9a-f]{64}', parts[5]):
                raise ShardError('bad sha256 for ' + fname)
            out['shards'].append((int(parts[1]), int(parts[2]), fname, int(parts[4]), parts[5]))
        else:
            raise ShardError('bad index line: ' + ln)
    for key in ('signature', 'sprites', 'per_shard'):
        if out[key] is None:
            raise ShardError('index has no "%s" line' % key.replace('_', '-'))
    if not out['shards']:
        raise ShardError('index lists no shard')
    expect = 1
    for first, count, fname, size, _ in out['shards']:
        if first != expect:
            raise ShardError('%s starts at sprite %d, expected %d (gap or overlap)' % (fname, first, expect))
        if size < 8 + 4 * count:
            raise ShardError('%s: size %d is too small for %d sprites' % (fname, size, count))
        expect = first + count
    if expect - 1 != out['sprites']:
        raise ShardError('shards hold %d sprites, the index says %d' % (expect - 1, out['sprites']))
    if len({s[2].lower() for s in out['shards']}) != len(out['shards']):
        raise ShardError('a shard file is listed twice')
    return out


def index_path(shard_dir, name):
    return os.path.join(shard_dir, name + '.sprshards')


# ---------------------------------------------------------------- commands

def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def split(spr_path, out_dir, name='Tibia', per_shard=DEFAULT_PER_SHARD, quiet=False):
    spr = Spr(spr_path)
    try:
        os.makedirs(out_dir, exist_ok=True)
        shards = []
        for k, (first, count) in enumerate(shard_ranges(spr.count, per_shard)):
            records = []
            for sid in range(first, first + count):
                records.append((spr.addresses[sid - 1], spr.record(sid)))
            data = build_shard(spr.signature, records)
            fname = shard_file_name(name, k)
            tmp = os.path.join(out_dir, fname + '.tmp')
            with open(tmp, 'wb') as f:
                f.write(data)
            os.replace(tmp, os.path.join(out_dir, fname))
            shards.append((first, count, fname, len(data), sha256_bytes(data)))
        # stale shards of an older split (more shards, or another per-shard) would only confuse a reader
        listed = {s[2] for s in shards}
        for entry in sorted(os.listdir(out_dir)):
            m = SHARD_NAME.match(entry)
            if m and m.group('name') == name and entry not in listed:
                os.remove(os.path.join(out_dir, entry))
        text = index_text(spr.signature, spr.count, per_shard, shards)
        tmp = index_path(out_dir, name) + '.tmp'
        with open(tmp, 'w', encoding='ascii', newline='\n') as f:
            f.write(text)
        os.replace(tmp, index_path(out_dir, name))
        if not quiet:
            total = sum(s[3] for s in shards)
            print('%s: %d sprites -> %d shards of %d (%.1f MB, largest %.1f MB), index %s' % (
                spr_path, spr.count, len(shards), per_shard, total / 1048576.0,
                max(s[3] for s in shards) / 1048576.0, index_path(out_dir, name)))
        return shards
    finally:
        spr.close()


def check(shard_dir, name='Tibia', quiet=False, hashes=True):
    """index + every shard's size, header and (hashes=True) SHA-256. Returns the parsed index."""
    path = index_path(shard_dir, name)
    if not os.path.isfile(path):
        raise ShardError('no shard index ' + path)
    idx = parse_index(open(path, encoding='ascii').read())
    for first, count, fname, size, sha in idx['shards']:
        full = os.path.join(shard_dir, fname)
        if not os.path.isfile(full):
            raise ShardError('missing shard ' + fname)
        if os.path.getsize(full) != size:
            raise ShardError('%s: %d bytes, the index says %d' % (fname, os.path.getsize(full), size))
        with open(full, 'rb') as f:
            sig, n = struct.unpack('<II', f.read(8))
        if sig != idx['signature'] or n != count:
            raise ShardError('%s: header says signature %d, %d sprites; the index %d, %d' % (
                fname, sig, n, idx['signature'], count))
        if hashes and sha256_file(full) != sha:
            raise ShardError('%s: SHA-256 differs from the index' % fname)
    if not quiet:
        print('%s: %d shards, %d sprites, signature 0x%08X: index, sizes, headers%s OK' % (
            path, len(idx['shards']), idx['sprites'], idx['signature'], ' and SHA-256' if hashes else ''))
    return idx


def joined_chunks(shard_dir, idx):
    """the bytes of the joined .spr (canonical layout) as chunks, without writing it"""
    total = idx['sprites']
    yield struct.pack('<II', idx['signature'], total)
    shard_objs = []
    for first, count, fname, _, _ in idx['shards']:
        s = Spr(os.path.join(shard_dir, fname))
        shard_objs.append((first, count, s))
    try:
        # pass 1: the address table
        table = array.array('I', [0] * total)
        pos = 8 + 4 * total
        placed = {}
        for first, count, s in shard_objs:
            for i in range(count):
                addr = s.addresses[i]
                if addr == 0:
                    continue
                key = (first, addr)
                if key in placed:
                    table[first - 1 + i] = placed[key]
                    continue
                n = struct.unpack_from('<H', s.data, addr + 3)[0] + 5
                placed[key] = pos
                table[first - 1 + i] = pos
                pos += n
        if sys.byteorder != 'little':
            table.byteswap()
        yield table.tobytes()
        # pass 2: the records in the same order
        for first, count, s in shard_objs:
            seen = set()
            for i in range(count):
                addr = s.addresses[i]
                if addr == 0 or addr in seen:
                    continue
                seen.add(addr)
                yield s.record(i + 1)
    finally:
        for _, _, s in shard_objs:
            s.close()


def join(shard_dir, out_path, name='Tibia', quiet=False):
    idx = check(shard_dir, name, quiet=True)
    tmp = out_path + '.tmp'
    h = hashlib.md5()
    with open(tmp, 'wb') as f:
        for chunk in joined_chunks(shard_dir, idx):
            f.write(chunk)
            h.update(chunk)
    os.replace(tmp, out_path)
    if not quiet:
        print('%s: %d sprites from %d shards, md5 %s' % (out_path, idx['sprites'], len(idx['shards']), h.hexdigest()))
    return h.hexdigest()


def md5_file(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def verify(spr_path, shard_dir, name='Tibia', quiet=False):
    """every record identical; returns (sprites compared, joined md5 == source md5)"""
    idx = check(shard_dir, name, quiet=True)
    src = Spr(spr_path)
    try:
        if src.signature != idx['signature']:
            raise ShardError('signature 0x%08X in %s, 0x%08X in the shards' % (src.signature, spr_path, idx['signature']))
        if src.count != idx['sprites']:
            raise ShardError('%d sprites in %s, %d in the shards' % (src.count, spr_path, idx['sprites']))
        for first, count, fname, _, _ in idx['shards']:
            s = Spr(os.path.join(shard_dir, fname))
            try:
                for i in range(count):
                    a, b = src.record(first + i), s.record(i + 1)
                    if a != b:
                        raise ShardError('sprite %d differs (%s record %d)' % (first + i, fname, i + 1))
            finally:
                s.close()
    finally:
        src.close()
    h = hashlib.md5()
    for chunk in joined_chunks(shard_dir, idx):
        h.update(chunk)
    same = h.hexdigest() == md5_file(spr_path)
    if not quiet:
        print('%s vs %s: %d sprites in %d shards byte-identical; joined md5 %s %s' % (
            spr_path, index_path(shard_dir, name), idx['sprites'], len(idx['shards']), h.hexdigest(),
            '== source' if same else '!= source (the source is not in canonical layout; the sprites still match)'))
    return idx['sprites'], same


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('split')
    p.add_argument('spr')
    p.add_argument('out_dir')
    p.add_argument('--name', default='Tibia')
    p.add_argument('--per-shard', type=int, default=DEFAULT_PER_SHARD)
    p = sub.add_parser('verify')
    p.add_argument('spr')
    p.add_argument('shard_dir')
    p.add_argument('--name', default='Tibia')
    p = sub.add_parser('check')
    p.add_argument('shard_dir')
    p.add_argument('--name', default='Tibia')
    p = sub.add_parser('join')
    p.add_argument('shard_dir')
    p.add_argument('out_spr')
    p.add_argument('--name', default='Tibia')
    a = ap.parse_args(argv)
    try:
        if a.cmd == 'split':
            split(a.spr, a.out_dir, a.name, a.per_shard)
        elif a.cmd == 'verify':
            verify(a.spr, a.shard_dir, a.name)
        elif a.cmd == 'check':
            check(a.shard_dir, a.name)
        else:
            join(a.shard_dir, a.out_spr, a.name)
    except (ShardError, OSError, struct.error) as e:
        print('error: %s' % e, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
