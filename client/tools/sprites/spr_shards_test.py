#!/usr/bin/env python3
"""Tests of spr_shards.py on small synthetic .spr files (no real pair needed, no numpy / Pillow).

python3 -I client/tools/sprites/spr_shards_test.py
"""
import hashlib
import os
import shutil
import struct
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spr_shards as ss  # noqa: E402

SIG = 0x57BBD603
FAILS = []


def eq(got, want, what):
    if got != want:
        FAILS.append('%s: got %r, want %r' % (what, got, want))


def raises(fn, what, needle=''):
    try:
        fn()
    except ss.ShardError as e:
        if needle and needle not in str(e):
            FAILS.append('%s: error %r does not mention %r' % (what, str(e), needle))
        return
    FAILS.append(what + ': no error')


def rec(seed, n):
    """a record: colour key, u16 size, `n` bytes of made-up pixel runs"""
    body = bytes((seed * 7 + i) & 0xFF for i in range(n))
    return b'\xff\x00\xff' + struct.pack('<H', len(body)) + body


def write_spr(path, records, canonical=True, share=None):
    """records: list (id order) of bytes or None. share: {id: other id} reuses the other id's record.
    canonical=False writes the records in reverse id order (a valid .spr whose layout is not canonical)."""
    share = share or {}
    count = len(records)
    table = [0] * count
    body = bytearray()
    base = 8 + 4 * count
    order = list(range(count)) if canonical else list(reversed(range(count)))
    for i in order:
        if records[i] is None or (i + 1) in share:
            continue
        table[i] = base + len(body)
        body += records[i]
    for sid, other in share.items():
        table[sid - 1] = table[other - 1]
    with open(path, 'wb') as f:
        f.write(struct.pack('<II', SIG, count))
        f.write(struct.pack('<%dI' % count, *table))
        f.write(body)


def md5(path):
    return hashlib.md5(open(path, 'rb').read()).hexdigest()


def main():
    eq(ss.shard_ranges(10, 4), [(1, 4), (5, 4), (9, 2)], 'ranges')
    eq(ss.shard_ranges(8, 4), [(1, 4), (5, 4)], 'ranges exact')
    eq(ss.shard_ranges(0, 4), [(1, 0)], 'ranges empty')
    raises(lambda: ss.shard_ranges(5, 0), 'per-shard 0')
    eq(ss.shard_file_name('Tibia', 7), 'Tibia.007.spr', 'name')

    tmp = tempfile.mkdtemp()
    try:
        src = os.path.join(tmp, 'Tibia.spr')
        records = [rec(i, 3 + i % 9) if i % 5 != 3 else None for i in range(23)]  # ids 4, 9, 14, 19 empty
        write_spr(src, records, share={7: 6, 12: 11})  # 6/7 and 11/12 share a record, inside one shard
        out = os.path.join(tmp, 'out')
        shards = ss.split(src, out, per_shard=4, quiet=True)
        eq(len(shards), 6, 'shard count')
        eq([s[:3] for s in shards][:2], [(1, 4, 'Tibia.000.spr'), (5, 4, 'Tibia.001.spr')], 'shard ranges')
        n, same = ss.verify(src, out, quiet=True)
        eq((n, same), (23, True), 'verify canonical: every sprite, md5 equal')
        joined = os.path.join(tmp, 'joined.spr')
        eq(ss.join(out, joined, quiet=True), md5(src), 'join md5')
        eq(md5(joined), md5(src), 'join file')
        # a shared record stays shared inside a shard: the shard is as big as the source part
        sh = ss.Spr(os.path.join(out, 'Tibia.002.spr'))  # ids 9..12, 11 and 12 share
        eq(sh.addresses[2], sh.addresses[3], 'shared record kept shared')
        eq(sh.record(4), records[10], 'record 12 = record 11')
        eq((sh.record(1), sh.record(2)), (b'', records[9]), 'record 9 empty, record 10')
        sh.close()

        # deterministic: a second split gives the same bytes
        idx1 = open(ss.index_path(out, 'Tibia'), 'rb').read()
        blobs1 = {f: open(os.path.join(out, f), 'rb').read() for f in sorted(os.listdir(out))}
        ss.split(src, out, per_shard=4, quiet=True)
        eq(open(ss.index_path(out, 'Tibia'), 'rb').read(), idx1, 'index deterministic')
        eq({f: open(os.path.join(out, f), 'rb').read() for f in sorted(os.listdir(out))}, blobs1, 'shards deterministic')

        # a coarser split removes the shard files it no longer lists
        ss.split(src, out, per_shard=10, quiet=True)
        eq(sorted(f for f in os.listdir(out) if f.endswith('.spr')), ['Tibia.000.spr', 'Tibia.001.spr', 'Tibia.002.spr'],
           'stale shards removed')
        eq(ss.verify(src, out, quiet=True), (23, True), 'verify after resplit')

        # check: corruption is found
        bad = os.path.join(tmp, 'bad')
        shutil.copytree(out, bad)
        with open(os.path.join(bad, 'Tibia.001.spr'), 'r+b') as f:
            f.seek(-1, 2)
            last = f.read(1)
            f.seek(-1, 2)
            f.write(bytes([last[0] ^ 1]))
        raises(lambda: ss.check(bad, quiet=True), 'flipped byte', 'SHA-256')
        eq(ss.check(bad, quiet=True, hashes=False)['sprites'], 23, 'flipped byte passes the size-only check')
        with open(os.path.join(bad, 'Tibia.001.spr'), 'ab') as f:
            f.write(b'x')
        raises(lambda: ss.check(bad, quiet=True, hashes=False), 'longer shard', 'bytes')
        os.remove(os.path.join(bad, 'Tibia.001.spr'))
        raises(lambda: ss.check(bad, quiet=True, hashes=False), 'missing shard', 'missing')
        raises(lambda: ss.check(os.path.join(tmp, 'nothing'), quiet=True), 'no index', 'no shard index')

        # verify: a sprite that differs from the source is named
        other = os.path.join(tmp, 'other.spr')
        changed = list(records)
        changed[16] = rec(200, 5)
        write_spr(other, changed, share={7: 6, 12: 11})
        raises(lambda: ss.verify(other, out, quiet=True), 'changed sprite', 'sprite 17')

        # a non-canonical source: every sprite still matches, the joined md5 is the canonical one
        nc = os.path.join(tmp, 'nc.spr')
        write_spr(nc, records, canonical=False, share={7: 6, 12: 11})
        out2 = os.path.join(tmp, 'out2')
        ss.split(nc, out2, per_shard=4, quiet=True)
        eq(ss.verify(nc, out2, quiet=True), (23, False), 'non-canonical source')
        eq(ss.join(out2, os.path.join(tmp, 'j2.spr'), quiet=True), md5(src), 'non-canonical joins to canonical')

        # a record shared across a shard boundary is copied into both shards: the sprites match, the joined file
        # (no sharing across shards) is longer than the source
        cross = os.path.join(tmp, 'cross.spr')
        write_spr(cross, records, share={7: 6, 12: 11, 5: 2})
        out3 = os.path.join(tmp, 'out3')
        ss.split(cross, out3, per_shard=4, quiet=True)
        eq(ss.verify(cross, out3, quiet=True), (23, False), 'cross-shard share')
        eq(os.path.getsize(os.path.join(tmp, 'cross.spr')) < sum(s[3] for s in ss.check(out3, quiet=True)['shards']),
           True, 'cross-shard share copied')

        # an empty .spr
        empty = os.path.join(tmp, 'empty.spr')
        write_spr(empty, [])
        ss.split(empty, os.path.join(tmp, 'e'), quiet=True)
        eq(ss.verify(empty, os.path.join(tmp, 'e'), quiet=True), (0, True), 'empty spr')

        # the split server/deploy/publish_client_update.sh makes: by the command line, into the folder of the single
        # Tibia.spr itself (the source is kept until the caller removes it, an older split's extra shard is removed)
        same = os.path.join(tmp, 'same')
        os.makedirs(same)
        single = os.path.join(same, 'Tibia.spr')
        shutil.copy(src, single)
        open(os.path.join(same, 'Tibia.009.spr'), 'wb').write(b'stale')
        eq(ss.main(['split', single, same, '--name', 'Tibia']), 0, 'main split into the spr folder')
        eq(ss.main(['verify', single, same, '--name', 'Tibia']), 0, 'main verify in the spr folder')
        eq(md5(single), md5(src), 'the single spr is untouched by a split next to it')
        eq(os.path.exists(os.path.join(same, 'Tibia.009.spr')), False, 'stale shard removed')
        eq(ss.main(['split', os.path.join(tmp, 'missing.spr'), same]), 1, 'main split of a missing spr')

        # main() exit codes
        eq(ss.main(['check', out]), 0, 'main check exit')
        eq(ss.main(['check', os.path.join(tmp, 'nothing')]), 1, 'main error exit')
    finally:
        shutil.rmtree(tmp)

    # parse_index: what the client refuses
    good = ss.index_text(SIG, 6, 4, [(1, 4, 'T.000.spr', 100, 'a' * 64), (5, 2, 'T.001.spr', 30, 'b' * 64)])
    eq(ss.parse_index(good)['sprites'], 6, 'parse good')
    eq(ss.parse_index('# comment\n' + good.replace('\n', '\r\n'))['per_shard'], 4, 'parse comments and CRLF')
    raises(lambda: ss.parse_index(good.replace('chaos-spr-shards 1', 'chaos-spr-shards 2')), 'format', 'first line')
    raises(lambda: ss.parse_index(good.replace('shard 5 2', 'shard 6 2')), 'gap', 'expected 5')
    raises(lambda: ss.parse_index(good.replace('sprites 6', 'sprites 7')), 'total', 'index says 7')
    raises(lambda: ss.parse_index(good.replace('T.001.spr', '../x.spr')), 'path', 'bad shard file name')
    raises(lambda: ss.parse_index(good.replace('T.001.spr', 'T.001.exe')), 'extension', 'bad shard file name')
    raises(lambda: ss.parse_index(good.replace(' 30 ', ' 10 ')), 'too small', 'too small')
    raises(lambda: ss.parse_index(good.replace('b' * 64, 'B' * 64)), 'sha', 'sha256')
    raises(lambda: ss.parse_index(good.replace('signature', 'sig')), 'unknown line', 'bad index line')
    raises(lambda: ss.parse_index('chaos-spr-shards 1\nsignature 1\nsprites 0\nper-shard 4\n'), 'no shard', 'no shard')

    if FAILS:
        print('\n'.join(FAILS))
        print('%d failure(s)' % len(FAILS))
        return 1
    print('spr_shards: all tests passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
