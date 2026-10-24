#!/usr/bin/env python3
"""versions.xml for map and sprite editors, read from the files it describes.

    python3 -I tools/windows/editor_versions.py DATA_DIR OUT.xml [--value 1098] [--name 10.98]

DATA_DIR holds Tibia.dat, Tibia.spr and items.otb. The dat and spr signatures are their first 4 bytes (little
endian); the otb version is the client version id (the "minor" of the items.otb root version attribute). Written in
the editors' versions.xml layout:

    <versions>
      <version value="1098" string="10.98" dat="42A3" spr="57BBD603" otb="57"/>
    </versions>

The values always match the shipped files, so a new sprite pair or items.otb never leaves a stale versions.xml.
"""
import argparse
import struct
import sys
from pathlib import Path

NODE_START, NODE_END, ESCAPE = 0xFE, 0xFF, 0xFD
ROOT_ATTR_VERSION = 0x01


def signature(path):
    data = Path(path).read_bytes()[:4]
    if len(data) < 4:
        raise ValueError('%s: shorter than 4 bytes' % path)
    return struct.unpack('<I', data)[0]


def otb_version(path):
    """(major, minor, build) of an items.otb root node"""
    raw = Path(path).read_bytes()
    if len(raw) < 6 or raw[4] != NODE_START:
        raise ValueError('%s: not an OTB file' % path)
    # the root node's own data, unescaped, up to its first child or its end
    data = bytearray()
    i = 5
    while i < len(raw):
        b = raw[i]
        if b == ESCAPE:
            i += 1
            data.append(raw[i])
        elif b in (NODE_START, NODE_END):
            break
        else:
            data.append(b)
        i += 1
    # type (1), flags (4), then attributes: id (1), length (2), value
    j = 5
    while j + 3 <= len(data):
        attr = data[j]
        length = struct.unpack_from('<H', data, j + 1)[0]
        if attr == ROOT_ATTR_VERSION and length >= 12:
            return struct.unpack_from('<III', data, j + 3)
        j += 3 + length
    raise ValueError('%s: no version attribute in the root node' % path)


def versions_xml(value, name, dat, spr, otb):
    return ('<?xml version="1.0" encoding="utf-8"?>\n<versions>\n'
            '  <version value="%d" string="%s" dat="%X" spr="%X" otb="%d"/>\n'
            '</versions>\n' % (value, name, dat, spr, otb))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('data_dir')
    ap.add_argument('out')
    ap.add_argument('--value', type=int, default=1098)
    ap.add_argument('--name', default='10.98')
    args = ap.parse_args(argv)
    d = Path(args.data_dir)
    dat, spr = signature(d / 'Tibia.dat'), signature(d / 'Tibia.spr')
    _major, minor, _build = otb_version(d / 'items.otb')
    Path(args.out).write_text(versions_xml(args.value, args.name, dat, spr, minor), encoding='utf-8')
    print('versions.xml: %s dat %X spr %X otb %d' % (args.name, dat, spr, minor))
    return 0


if __name__ == '__main__':
    sys.exit(main())
