#!/usr/bin/env python3
"""Tests for tools/map_master.py (server/README.md "Map master") on tiny synthetic maps: an OTBM header with escaped
bytes, a description, spawn and house file names and a few kilobytes of noise as tiles.

pack (parts, SHA256SUMS, MAP_MASTER.json, version bump, same map refused, stale parts removed), verify and sha256sum -c,
unpack byte for byte, a damaged part refused with nothing written, not a map refused, install into a server folder
(backup with a timestamp, marker, header names set to the server's map name, a second install skipped, --force,
old backups pruned), installed.

usage: python3 -I server/tools/map_master_test.py
"""
import json
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'map_master.py')
sys.path.insert(0, HERE)
import map_master as M  # noqa: E402

FAILS = []
CHECKS = [0]


def check(cond, what, out=''):
    CHECKS[0] += 1
    if not cond:
        FAILS.append(what)
        print('FAIL: ' + what)
        if out:
            print(out[-2000:])


def esc(data):
    out = bytearray()
    for b in data:
        if b in (0xFD, 0xFE, 0xFF):
            out.append(0xFD)
        out.append(b)
    return bytes(out)


def attr(a, text):
    b = text.encode('latin-1')
    return bytes([a]) + struct.pack('<H', len(b)) + b


def fake_map(name, seed, size=6000, desc='Saved with the map editor \xff'):
    """an OTBM: root header (width 0xFEFD: escaped bytes), map data with description / spawn / house names, then a
    tile area node of noise (escaped) and the closing bytes"""
    rnd = random.Random(seed)
    root = struct.pack('<IHHII', 2, 0xFEFD, 2048, 3, 57)
    data = attr(1, desc) + attr(11, name + '-spawn.xml') + attr(13, name + '-house.xml')
    noise = bytes(rnd.randrange(256) for _ in range(size))
    return (b'\0\0\0\0' + bytes([0xFE, 0]) + esc(root) + bytes([0xFE, 2]) + esc(data)
            + bytes([0xFE, 4]) + esc(noise) + bytes([0xFF, 0xFF, 0xFF]))


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb' if isinstance(data, bytes) else 'w') as f:
        f.write(data)


def read(path):
    with open(path, 'rb') as f:
        return f.read()


def run(*args):
    r = subprocess.run([sys.executable, '-I', TOOL] + list(args), capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def main():
    root = tempfile.mkdtemp(prefix='map_master_test_')
    try:
        src = os.path.join(root, 'sent', 'edited.otbm')
        m1 = fake_map('edited', 1)
        write(src, m1)
        h = M.read_header(m1)
        check(h['width'] == 0xFEFD and h['items_minor'] == 57, 'header: escaped root header read')
        check(M.file_names(h) == {'spawn': 'edited-spawn.xml', 'house': 'edited-house.xml'}, 'header: file names')

        world = os.path.join(root, 'assets', 'world')
        rc, out = run('pack', src, world, '--part-size', '2000', '--date', '2026-10-22', '--note', 'first')
        meta = json.load(open(os.path.join(world, M.META)))
        check(rc == 0 and meta['version'] == 1 and meta['date'] == '2026-10-22', 'pack: version 1', out)
        check(len(meta['parts']) >= 3 and all(os.path.getsize(os.path.join(world, p)) <= 2000 for p in meta['parts']),
              'pack: parts of at most the part size %r' % meta['parts'])
        check(meta['otbm_size'] == len(m1) and meta['otbm_sha256'] == M.hashlib.sha256(m1).hexdigest(),
              'pack: the source SHA-256 and size')
        check(meta['header']['width'] == 0xFEFD and meta['previous'] == 0 and meta['note'] == 'first', 'pack: header, note')
        check('world/MAP_MASTER.json' in out and 'world/' + meta['parts'][0] in out, 'pack: says what to commit', out)
        check(not [n for n in os.listdir(world) if n.startswith('.')], 'pack: no temporary files')
        if shutil.which('sha256sum'):
            r = subprocess.run(['sha256sum', '-c', M.SUMS], cwd=world, capture_output=True, text=True)
            check(r.returncode == 0, 'SHA256SUMS: sha256sum -c accepts it', r.stdout + r.stderr)

        rc, out = run('verify', world, '--deep')
        check(rc == 0 and 'version=1' in out and 'otbm_sha256=' + meta['otbm_sha256'] in out, 'verify --deep', out)
        dst = os.path.join(root, 'out', 'map.otbm')
        os.makedirs(os.path.dirname(dst))
        rc, out = run('unpack', world, dst)
        check(rc == 0 and read(dst) == m1, 'unpack: byte for byte', out)

        rc, out = run('pack', src, world, '--part-size', '2000')
        check(rc == 1 and 'version 1 already' in out, 'pack: the same map again refused', out)
        rc, out = run('pack', src, world, '--version', '1')
        check(rc == 1, 'pack: a version not newer refused', out)
        m2 = fake_map('other', 2, size=1500)
        write(src, m2)
        rc, out = run('pack', src, world, '--part-size', '2000')
        meta2 = json.load(open(os.path.join(world, M.META)))
        check(rc == 0 and meta2['version'] == 2 and meta2['previous'] == 1, 'pack: version 2', out)
        parts = sorted(n for n in os.listdir(world) if n.startswith(M.PART_PREFIX))
        check(parts == meta2['parts'] and len(parts) < len(meta['parts']), 'pack: parts of version 1 removed %r' % parts)
        rc, out = run('verify', world)
        check(rc == 0 and 'version=2' in out, 'verify version 2', out)

        bad = os.path.join(root, 'bad.otbm')
        write(bad, b'PK\x03\x04 a zip, not a map')
        rc, out = run('pack', bad, os.path.join(root, 'w2'))
        check(rc == 1 and 'not an OTBM' in out, 'pack: not a map refused', out)

        # a damaged part: refused, the old file stays, nothing temporary left
        dmg = os.path.join(root, 'damaged')
        shutil.copytree(world, dmg)
        p0 = os.path.join(dmg, meta2['parts'][0])
        b = bytearray(read(p0))
        b[100] ^= 0x55
        write(p0, bytes(b))
        write(dst, b'old map')
        rc, out = run('unpack', dmg, dst)
        check(rc == 1 and 'SHA-256' in out and read(dst) == b'old map', 'unpack: a damaged part refused', out)
        check(not os.path.exists(dst + '.tmp'), 'unpack: no temporary file left')
        # a damaged stream whose sums were made to match: the decompression check catches it
        write(os.path.join(dmg, M.SUMS), ''.join('%s  %s\n' % (M.sha256_file(os.path.join(dmg, n)), n)
                                                  for n in meta2['parts']))
        rc, out = run('unpack', dmg, dst)
        check(rc == 1 and read(dst) == b'old map', 'unpack: damaged data with matching sums refused', out)
        os.remove(os.path.join(dmg, meta2['parts'][-1]))
        rc, out = run('verify', dmg)
        check(rc == 1 and 'missing' in out, 'verify: a missing part', out)

        # install into a server folder (mapName "world1"; the master was saved as "other")
        srv = os.path.join(root, 'server')
        write(os.path.join(srv, 'config.lua'), 'serverName = "x"\nmapName = "world1"\n')
        old_map = fake_map('world1', 9, size=300)
        target = os.path.join(srv, 'data', 'world', 'world1.otbm')
        write(target, old_map)
        write(target + '.bak', b'the base map')
        rc, out = run('installed', srv)
        check(rc == 0 and 'version=0' in out, 'installed: none yet', out)
        rc, out = run('install', world, srv, '--dry-run')
        check(rc == 0 and read(target) == old_map, 'install --dry-run writes nothing', out)
        rc, out = run('install', world, srv, '--stamp', '20261022-101500')
        backup = os.path.join(srv, 'map-backups', 'world1.otbm.20261022-101500')
        check(rc == 0 and 'backup=' + backup in out and read(backup) == old_map, 'install: the old map backed up', out)
        new = read(target)
        hn = M.read_header(new)
        check(M.file_names(hn) == {'spawn': 'world1-spawn.xml', 'house': 'world1-house.xml'},
              'install: the header names the server\'s spawn and house files', out)
        check('header: spawn other-spawn.xml -> world1-spawn.xml' in out, 'install: says the names changed', out)
        check(new.endswith(m2[-500:]) and hn['width'] == 0xFEFD, 'install: the rest of the map as packed')
        check(read(target + '.bak') == b'the base map', 'install: the base map backup of the install steps stays')
        mark = json.load(open(target + M.MARK_SUFFIX))
        check(mark['version'] == 2 and mark['otbm_sha256'] == meta2['otbm_sha256'], 'install: marker written')
        rc, out = run('installed', srv)
        check('version=2' in out, 'installed: version 2', out)
        rc, out = run('install', world, srv)
        check(rc == 0 and 'installed=skip' in out and not os.path.exists(os.path.join(srv, 'map-backups',
                                                                                       'world1.otbm.x')),
              'install: the same version again is skipped', out)
        check(len(os.listdir(os.path.join(srv, 'map-backups'))) == 1, 'install skipped: no new backup')
        for i, stamp in enumerate(('20261022-101600', '20261022-101700')):
            rc, out = run('install', world, srv, '--force', '--keep', '2', '--stamp', stamp)
            check(rc == 0 and 'installed=2' in out, 'install --force %d' % i, out)
            os.utime(os.path.join(srv, 'map-backups', 'world1.otbm.' + stamp), (2e9 + i, 2e9 + i))
        left = sorted(n for n in os.listdir(os.path.join(srv, 'map-backups')) if not n.endswith(M.MARK_SUFFIX))
        check(left == ['world1.otbm.20261022-101600', 'world1.otbm.20261022-101700'], 'install: --keep 2 prunes %r' % left)
        check(os.path.isfile(os.path.join(srv, 'map-backups', 'world1.otbm.20261022-101700' + M.MARK_SUFFIX)),
              'install: the backup keeps the marker of the map it holds')
        write(os.path.join(srv, 'config.lua'), 'mapName = "../x"\n')
        rc, out = run('install', world, srv, '--force')
        check(rc == 1 and 'mapName' in out, 'install: an odd mapName refused', out)
        rc, out = run('bogus')
        check(rc == 2, 'unknown command: usage')
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print('map_master_test: %d checks, %d failures' % (CHECKS[0], len(FAILS)))
    return 1 if FAILS else 0


if __name__ == '__main__':
    sys.exit(main())
