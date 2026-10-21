#!/usr/bin/env python3
"""The map master: the owner's hand-edited world map, kept so the builds and the live server use it (server/README.md
"Map master", docs/MAP_GUIDE.md "Editing the live map").

usage: python3 -I server/tools/map_master.py pack OTBM OUT_DIR [--version N] [--date YYYY-MM-DD] [--note TEXT] [--force]
       python3 -I server/tools/map_master.py unpack DIR OUT_OTBM
       python3 -I server/tools/map_master.py verify DIR [--deep]
       python3 -I server/tools/map_master.py install DIR SERVER_DIR [--force] [--dry-run] [--backup-dir DIR] [--keep N]
       python3 -I server/tools/map_master.py installed SERVER_DIR

The master lives on the private branch windows-assets under world/ (never on main: it is large and it is the live map):
  map-master.otbm.xz.partNN  the .otbm compressed with xz and cut into parts of 95 MiB (GitHub refuses files over
                             100 MB; one part for a map that compresses well)
  SHA256SUMS                 the SHA-256 of every part (sha256sum -c works on it)
  MAP_MASTER.json            format, version (1, 2, ...), date, the SHA-256 and size of the .otbm (the source) and of
                             the .xz, the parts in order, the map's header (OTBM version, size, items version), a note

pack       OTBM (the file the owner sent) -> OUT_DIR (a checkout of windows-assets' world/ folder, or an empty
           folder). The version is the one of OUT_DIR/MAP_MASTER.json plus one (1 when there is none), or --version.
           The same map as the current version is refused (--force packs it again). Parts of an earlier version that
           the new one does not have are deleted. The .otbm is checked first: an OTBM header, a map data node.
unpack     DIR -> OUT_OTBM: every part checked against SHA256SUMS, joined, decompressed, the result checked against
           the SHA-256 and size in MAP_MASTER.json; written through OUT_OTBM.tmp, so a failure leaves OUT_OTBM as it was.
verify     DIR: the parts against SHA256SUMS and MAP_MASTER.json; --deep also decompresses (nothing written). Prints
           version=, date=, otbm_sha256= lines.
install    DIR into a server folder (config.lua and data/): the map of config.lua's mapName (data/world/<mapName>.otbm)
           is replaced. Skipped when that map already is this version (the marker <mapName>.otbm.master.json next to
           the map says so; --force installs anyway). The old map is moved to BACKUP_DIR/<mapName>.otbm.<timestamp>
           (default SERVER_DIR/map-backups; the newest --keep, default 3, stay) and the line backup=PATH says where.
           The map names its spawn and house files in its header (the engine loads those); when the owner saved the
           map under another name they are set back to <mapName>-spawn.xml / <mapName>-house.xml. Then the marker is
           written. The install steps (install_all.py) run on top afterwards as on any installed map: each one sees
           its work in place and changes nothing, a newer step adds its own.
installed  SERVER_DIR: version=N of the installed master (0: the map is no master).

Only the .otbm is the master. The spawn file (monsters, NPCs) and the house file stay the install steps' (the map
editor rewrites a spawn file without the install steps' markers, so a second install would add every spawn twice).
Exit status: 0 done (or nothing to do), 1 refused or failed, 2 usage. Test: tools/map_master_test.py.
"""
import datetime
import hashlib
import json
import lzma
import os
import re
import struct
import sys

PART_PREFIX = 'map-master.otbm.xz.part'
META = 'MAP_MASTER.json'
SUMS = 'SHA256SUMS'
PART_SIZE = 95 * 1024 * 1024  # as the other large files of windows-assets (base-client.tar.xz.partNN)
CHUNK = 1 << 20
FORMAT = 1
MARK_SUFFIX = '.master.json'

ESC, START, END = 0xFD, 0xFE, 0xFF
ATTR_DESCRIPTION, ATTR_SPAWN, ATTR_HOUSE = 1, 11, 13
NODE_ROOT, NODE_MAP_DATA = 0, 2


class MasterError(Exception):
    pass


def say(text):
    print(text, flush=True)


# ------------------------------------------------------------------------------------------------ OTBM header
def _unescape(raw, pos, stop):
    """bytes of node data from raw[pos] to the next unescaped START/END (or stop); returns (data, raw end, [raw offset
    of each data byte])"""
    out, where = bytearray(), []
    i = pos
    while i < stop:
        b = raw[i]
        if b == ESC:
            if i + 1 >= stop:
                break
            out.append(raw[i + 1])
            where.append(i)
            i += 2
            continue
        if b in (START, END):
            return bytes(out), i, where
        out.append(b)
        where.append(i)
        i += 1
    raise MasterError('the OTBM header is longer than %d bytes or cut short' % stop)


def _escape(data):
    out = bytearray()
    for b in data:
        if b in (ESC, START, END):
            out.append(ESC)
        out.append(b)
    return bytes(out)


def read_header(raw):
    """the header of an .otbm from its first bytes: {otbm_version, width, height, items_major, items_minor,
    attrs: [(attr, value bytes, raw start, raw end)], data_end}"""
    limit = len(raw)
    if limit < 6 or raw[:4] not in (b'\0\0\0\0', b'OTBM'):
        raise MasterError('not an OTBM map (no OTBM identifier)')
    if raw[4] != START or raw[5] != NODE_ROOT:
        raise MasterError('not an OTBM map (no root node)')
    head, at, _ = _unescape(raw, 6, limit)
    if len(head) < 16:
        raise MasterError('not an OTBM map (root header of %d bytes)' % len(head))
    version, width, height, major, minor = struct.unpack('<IHHII', head[:16])
    if raw[at] != START or at + 1 >= limit or raw[at + 1] != NODE_MAP_DATA:
        raise MasterError('not an OTBM map (no map data node after the root header)')
    data, end, where = _unescape(raw, at + 2, limit)
    attrs, i = [], 0
    while i < len(data):
        a = data[i]
        if i + 3 > len(data):
            raise MasterError('OTBM map data: attribute %d cut short' % a)
        n = struct.unpack('<H', data[i + 1:i + 3])[0]
        if i + 3 + n > len(data):
            raise MasterError('OTBM map data: attribute %d longer than the node' % a)
        raw_start = where[i]
        raw_end = where[i + 3 + n] if i + 3 + n < len(where) else end
        attrs.append((a, data[i + 3:i + 3 + n], raw_start, raw_end))
        i += 3 + n
    return {'otbm_version': version, 'width': width, 'height': height, 'items_major': major, 'items_minor': minor,
            'attrs': attrs, 'data_end': end}


def header_of(path, size=1 << 16):
    with open(path, 'rb') as f:
        return read_header(f.read(size))


def file_names(header):
    """{'spawn': name, 'house': name} the map's header names (missing ones left out)"""
    out = {}
    for a, value, _s, _e in header['attrs']:
        if a == ATTR_SPAWN:
            out['spawn'] = value.decode('latin-1')
        elif a == ATTR_HOUSE:
            out['house'] = value.decode('latin-1')
    return out


def set_file_names(path, spawn, house):
    """the header's spawn / house file names set to these (the file rewritten through PATH.names); returns the list of
    changes ('spawn a -> b')"""
    with open(path, 'rb') as f:
        raw = f.read(1 << 16)
    h = read_header(raw)
    want = {ATTR_SPAWN: spawn, ATTR_HOUSE: house}
    cut, changes, found = [], [], set()
    for a, value, s, e in h['attrs']:
        if a in want:
            found.add(a)
            old = value.decode('latin-1')
            if old != want[a]:
                new = want[a].encode('latin-1')
                cut.append((s, e, _escape(bytes([a]) + struct.pack('<H', len(new)) + new)))
                changes.append('%s %s -> %s' % ('spawn' if a == ATTR_SPAWN else 'house', old, want[a]))
    for a in (ATTR_SPAWN, ATTR_HOUSE):
        if a not in found:  # the engine then loads no spawns / houses: add the attribute at the end of the map data
            new = want[a].encode('latin-1')
            cut.append((h['data_end'], h['data_end'], _escape(bytes([a]) + struct.pack('<H', len(new)) + new)))
            changes.append('%s file named: %s' % ('spawn' if a == ATTR_SPAWN else 'house', want[a]))
    if not cut:
        return []
    head = bytearray(raw[:max(e for _s, e, _b in cut)])
    for s, e, b in sorted(cut, reverse=True):
        head[s:e] = b
    tail_from = max(e for _s, e, _b in cut)
    tmp = path + '.names'
    with open(path, 'rb') as src, open(tmp, 'wb') as out:
        out.write(head)
        src.seek(tail_from)
        while True:
            b = src.read(CHUNK)
            if not b:
                break
            out.write(b)
    read_header(open(tmp, 'rb').read(1 << 16))  # still a map
    os.replace(tmp, path)
    return changes


# ------------------------------------------------------------------------------------------------ the master folder
def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while True:
            b = f.read(CHUNK)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def load_meta(folder):
    p = os.path.join(folder, META)
    if not os.path.isfile(p):
        return None
    try:
        meta = json.load(open(p, encoding='utf-8'))
    except ValueError as e:
        raise MasterError('%s: not JSON (%s)' % (p, e))
    if not isinstance(meta, dict) or meta.get('format') != FORMAT:
        raise MasterError('%s: format %r, this tool reads format %d' % (p, meta.get('format') if isinstance(meta, dict)
                                                                          else None, FORMAT))
    for k in ('version', 'otbm_sha256', 'otbm_size', 'xz_sha256', 'parts'):
        if k not in meta:
            raise MasterError('%s: no %s' % (p, k))
    if not isinstance(meta['version'], int) or meta['version'] < 1:
        raise MasterError('%s: bad version %r' % (p, meta['version']))
    for name in meta['parts']:
        if not re.fullmatch(re.escape(PART_PREFIX) + r'\d{2,4}', str(name)):
            raise MasterError('%s: bad part name %r' % (p, name))
    return meta


def read_sums(folder):
    p = os.path.join(folder, SUMS)
    if not os.path.isfile(p):
        raise MasterError('no %s in %s' % (SUMS, folder))
    out = {}
    for line in open(p, encoding='utf-8'):
        line = line.strip()
        if not line:
            continue
        m = re.fullmatch(r'([0-9a-f]{64}) [ *]?(\S+)', line)
        if not m:
            raise MasterError('%s: bad line %r' % (SUMS, line))
        out[m.group(2)] = m.group(1)
    return out


def verify(folder, deep=False):
    """the master's metadata, every part checked; deep: decompressed and checked too (nothing written)"""
    meta = load_meta(folder)
    if meta is None:
        raise MasterError('no %s in %s' % (META, folder))
    sums = read_sums(folder)
    if sorted(sums) != sorted(meta['parts']):
        raise MasterError('%s lists %s, %s lists %s' % (SUMS, sorted(sums), META, meta['parts']))
    for name in meta['parts']:
        p = os.path.join(folder, name)
        if not os.path.isfile(p):
            raise MasterError('part %s is missing' % name)
        got = sha256_file(p)
        if got != sums[name]:
            raise MasterError('part %s: SHA-256 %s, %s says %s' % (name, got, SUMS, sums[name]))
    if deep:
        _decompress(folder, meta, None)
    return meta


def _decompress(folder, meta, out_path):
    """the parts joined and decompressed into out_path (None: only checked); the sizes and SHA-256 checked"""
    dec = lzma.LZMADecompressor(format=lzma.FORMAT_XZ)
    hx, ho, size = hashlib.sha256(), hashlib.sha256(), 0
    out = open(out_path, 'wb') if out_path else None
    try:
        for name in meta['parts']:
            with open(os.path.join(folder, name), 'rb') as f:
                while True:
                    b = f.read(CHUNK)
                    if not b:
                        break
                    hx.update(b)
                    if dec.eof:
                        raise MasterError('data after the end of the xz stream')
                    d = dec.decompress(b)
                    ho.update(d)
                    size += len(d)
                    if size > meta['otbm_size']:
                        raise MasterError('the map is larger than the %d bytes %s says' % (meta['otbm_size'], META))
                    if out:
                        out.write(d)
        if not dec.eof:
            raise MasterError('the xz stream is cut short')
    except lzma.LZMAError as e:
        raise MasterError('xz: %s' % e)
    finally:
        if out:
            out.close()
    if hx.hexdigest() != meta['xz_sha256']:
        raise MasterError('the joined parts: SHA-256 %s, %s says %s' % (hx.hexdigest(), META, meta['xz_sha256']))
    if size != meta['otbm_size'] or ho.hexdigest() != meta['otbm_sha256']:
        raise MasterError('the map: %d bytes, SHA-256 %s; %s says %d bytes, %s' % (
            size, ho.hexdigest(), META, meta['otbm_size'], meta['otbm_sha256']))


def unpack(folder, out_path):
    meta = verify(folder)
    tmp = out_path + '.tmp'
    try:
        _decompress(folder, meta, tmp)
        read_header(open(tmp, 'rb').read(1 << 16))
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise
    os.replace(tmp, out_path)
    return meta


def pack(otbm, folder, version=None, date=None, note='', force=False, part_size=PART_SIZE):
    header = header_of(otbm)
    os.makedirs(folder, exist_ok=True)
    old = load_meta(folder)
    src_sha = sha256_file(otbm)
    if old and old['otbm_sha256'] == src_sha and not force:
        raise MasterError('this map is version %d already (same SHA-256); nothing written (--force packs it again)'
                          % old['version'])
    if version is None:
        version = old['version'] + 1 if old else 1
    elif old and version <= old['version'] and not force:
        raise MasterError('version %d is not newer than version %d (--force)' % (version, old['version']))
    date = date or datetime.date.today().isoformat()
    if not re.fullmatch(r'\d{4}-\d\d-\d\d', date):
        raise MasterError('bad date %r (YYYY-MM-DD)' % date)
    # compress into parts (temporary names first)
    comp = lzma.LZMACompressor(format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC64, preset=9)
    parts, hx, size, xz_size = [], hashlib.sha256(), 0, 0
    state = {'f': None, 'n': 0, 'h': None}

    def emit(b):
        while b:
            if state['f'] is None or state['n'] >= part_size:
                close()
                name = '%s%02d' % (PART_PREFIX, len(parts))
                parts.append([name, None])
                state['f'] = open(os.path.join(folder, '.' + name + '.new'), 'wb')
                state['n'], state['h'] = 0, hashlib.sha256()
            take = b[:part_size - state['n']]
            state['f'].write(take)
            state['h'].update(take)
            state['n'] += len(take)
            b = b[len(take):]

    def close():
        if state['f'] is not None:
            state['f'].close()
            parts[-1][1] = state['h'].hexdigest()
            state['f'] = None
    hs = hashlib.sha256()
    try:
        with open(otbm, 'rb') as f:
            while True:
                b = f.read(CHUNK)
                if not b:
                    break
                hs.update(b)
                size += len(b)
                c = comp.compress(b)
                hx.update(c)
                xz_size += len(c)
                emit(c)
        c = comp.flush()
        hx.update(c)
        xz_size += len(c)
        emit(c)
        close()
        if hs.hexdigest() != src_sha:
            raise MasterError('%s changed while it was packed' % otbm)
    except BaseException:
        close()
        for name, _h in parts:
            p = os.path.join(folder, '.' + name + '.new')
            if os.path.exists(p):
                os.remove(p)
        raise
    keep = {name for name, _h in parts}
    for n in os.listdir(folder):
        if n.startswith(PART_PREFIX) and n not in keep:
            os.remove(os.path.join(folder, n))
    for name, _h in parts:
        os.replace(os.path.join(folder, '.' + name + '.new'), os.path.join(folder, name))
    with open(os.path.join(folder, SUMS), 'w', encoding='utf-8', newline='\n') as f:
        for name, h in parts:
            f.write('%s  %s\n' % (h, name))
    meta = {'format': FORMAT, 'version': version, 'date': date, 'otbm_sha256': src_sha, 'otbm_size': size,
            'xz_sha256': hx.hexdigest(), 'xz_size': xz_size, 'parts': [name for name, _h in parts],
            'header': {k: header[k] for k in ('otbm_version', 'width', 'height', 'items_major', 'items_minor')},
            'previous': old['version'] if old else 0, 'note': note}
    with open(os.path.join(folder, META), 'w', encoding='utf-8', newline='\n') as f:
        json.dump(meta, f, indent=1)
        f.write('\n')
    verify(folder, deep=True)
    return meta


# ------------------------------------------------------------------------------------------------ a server folder
def map_name(server):
    cfg = os.path.join(server, 'config.lua')
    if not os.path.isfile(cfg):
        raise MasterError('no config.lua in %s' % server)
    m = re.search(r'^\s*mapName\s*=\s*"([^"]+)"', open(cfg, encoding='latin-1').read(), re.M)
    if not m or not re.fullmatch(r'[A-Za-z0-9_.-]+', m.group(1)) or m.group(1).startswith('.'):
        raise MasterError('config.lua: no plain mapName = "..." line')
    return m.group(1)


def installed(server):
    """{version, ...} of the master installed in SERVER (version 0: none)"""
    name = map_name(server)
    p = os.path.join(server, 'data', 'world', name + '.otbm' + MARK_SUFFIX)
    try:
        d = json.load(open(p, encoding='utf-8'))
        if isinstance(d, dict) and isinstance(d.get('version'), int):
            return d
    except (OSError, ValueError):
        pass
    return {'version': 0}


def install(folder, server, force=False, dry=False, backup_dir=None, keep=3, stamp=None):
    meta = verify(folder)
    name = map_name(server)
    world = os.path.join(server, 'data', 'world')
    target = os.path.join(world, name + '.otbm')
    have = installed(server)
    say('master: version %d (%s), installed: %s' % (meta['version'], meta.get('date', '?'),
                                                    'version %d' % have['version'] if have['version'] else 'none'))
    if have['version'] == meta['version'] and have.get('otbm_sha256') == meta['otbm_sha256'] and not force \
            and os.path.isfile(target):
        say('installed=skip (the map already is version %d)' % meta['version'])
        return None
    if dry:
        say('dry run: would replace %s with version %d' % (target, meta['version']))
        return None
    os.makedirs(world, exist_ok=True)
    tmp = target + '.master-new'
    try:
        _decompress(folder, meta, tmp)
        changes = set_file_names(tmp, name + '-spawn.xml', name + '-house.xml')
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise
    for c in changes:
        say('header: ' + c)
    backup = None
    if os.path.isfile(target):
        backup_dir = backup_dir or os.path.join(server, 'map-backups')
        os.makedirs(backup_dir, exist_ok=True)
        stamp = stamp or datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
        backup = os.path.join(backup_dir, '%s.otbm.%s' % (name, stamp))
        n = 1
        while os.path.exists(backup):
            backup = os.path.join(backup_dir, '%s.otbm.%s-%d' % (name, stamp, n))
            n += 1
        if same_fs(target, backup_dir):
            os.replace(target, backup)
        else:
            copy_then_remove(target, backup)
        mark = target + MARK_SUFFIX
        if os.path.isfile(mark):
            with open(mark, 'rb') as a, open(backup + MARK_SUFFIX, 'wb') as b:
                b.write(a.read())
        say('backup=%s' % backup)
    os.replace(tmp, target)
    mark = {'version': meta['version'], 'date': meta.get('date', ''), 'otbm_sha256': meta['otbm_sha256'],
            'installed': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
    with open(target + MARK_SUFFIX, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(mark, f, indent=1)
        f.write('\n')
    say('installed=%d (%s)' % (meta['version'], target))
    if backup:
        prune(os.path.dirname(backup), name, keep)
    return backup


def same_fs(path, folder):
    return os.stat(path).st_dev == os.stat(folder).st_dev


def copy_then_remove(src, dst):
    with open(src, 'rb') as a, open(dst + '.tmp', 'wb') as b:
        while True:
            chunk = a.read(CHUNK)
            if not chunk:
                break
            b.write(chunk)
    os.replace(dst + '.tmp', dst)
    os.remove(src)


def prune(folder, name, keep):
    """the newest KEEP backups of NAME stay (each one is as large as the map)"""
    pat = re.compile(re.escape(name) + r'\.otbm\.\d{8}-\d{6}(-\d+)?$')
    found = sorted((n for n in os.listdir(folder) if pat.match(n)),
                   key=lambda n: os.path.getmtime(os.path.join(folder, n)), reverse=True)
    for n in found[max(keep, 1):]:
        for p in (os.path.join(folder, n), os.path.join(folder, n + MARK_SUFFIX)):
            if os.path.exists(p):
                os.remove(p)
        say('old backup removed: %s' % n)


# ------------------------------------------------------------------------------------------------ command line
def main(argv):
    opts, args, i = {}, [], 0
    valued = ('--version', '--date', '--note', '--backup-dir', '--keep', '--part-size', '--stamp')
    while i < len(argv):
        a = argv[i]
        if a in valued:
            if i + 1 >= len(argv):
                say('%s needs a value' % a)
                return 2
            opts[a] = argv[i + 1]
            i += 2
            continue
        if a in ('--force', '--dry-run', '--deep'):
            opts[a] = True
        elif a in ('-h', '--help'):
            say(__doc__)
            return 0
        elif a.startswith('--'):
            say('unknown option %s' % a)
            return 2
        else:
            args.append(a)
        i += 1
    want = {'pack': 3, 'unpack': 3, 'verify': 2, 'install': 3, 'installed': 2}
    if not args or args[0] not in want or len(args) != want[args[0]]:
        say(__doc__)
        return 2
    try:
        cmd = args[0]
        if cmd == 'pack':
            v = opts.get('--version')
            if v is not None and not re.fullmatch(r'[1-9]\d{0,5}', v):
                raise MasterError('--version must be a number from 1')
            meta = pack(args[1], args[2], int(v) if v else None, opts.get('--date'), opts.get('--note', ''),
                        bool(opts.get('--force')), int(opts.get('--part-size', PART_SIZE)))
            say('map master version %d: %d bytes -> %d bytes of xz in %d part(s)' % (
                meta['version'], meta['otbm_size'], meta['xz_size'], len(meta['parts'])))
            say('commit on windows-assets: world/%s, world/%s, %s' % (
                META, SUMS, ', '.join('world/' + p for p in meta['parts'])))
        elif cmd == 'unpack':
            meta = unpack(args[1], args[2])
            say('version %d written to %s (%d bytes, SHA-256 checked)' % (meta['version'], args[2], meta['otbm_size']))
        elif cmd == 'verify':
            meta = verify(args[1], bool(opts.get('--deep')))
            say('version=%d' % meta['version'])
            say('date=%s' % meta.get('date', ''))
            say('otbm_sha256=%s' % meta['otbm_sha256'])
            say('ok: %d part(s) checked%s' % (len(meta['parts']), ', decompressed' if opts.get('--deep') else ''))
        elif cmd == 'install':
            keep = opts.get('--keep', '3')
            if not re.fullmatch(r'\d{1,3}', keep):
                raise MasterError('--keep must be a number')
            install(args[1], args[2], bool(opts.get('--force')), bool(opts.get('--dry-run')), opts.get('--backup-dir'),
                    int(keep), opts.get('--stamp'))
        else:
            say('version=%d' % installed(args[1])['version'])
    except MasterError as e:
        say('map_master: %s' % e)
        return 1
    except OSError as e:
        say('map_master: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
