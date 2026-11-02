#!/usr/bin/env python3
"""versions.xml for map and sprite editors, read from the files it describes.

    python3 -I tools/windows/editor_versions.py DATA_DIR [OUT.xml] [--value 1098] [--name 10.98] [--otfi OUT.otfi]

DATA_DIR holds Tibia.dat, Tibia.spr and items.otb. The dat and spr signatures are their first 4 bytes (little
endian); the otb version is the client version id (the "minor" of the items.otb root version attribute). Written in
the editors' versions.xml layout:

    <versions>
      <version value="1098" string="10.98" dat="42A3" spr="57BBD603" otb="57"/>
    </versions>

The values always match the shipped files, so a new sprite pair or items.otb never leaves a stale versions.xml.

--otfi also writes the sprite info file that map editors read from the client folder (any *.otfi next to the dat):

    DatSpr
      extended: true
      transparency: true
      frame-durations: true
      frame-groups: true
      metadata-file: Tibia.dat
      sprites-file: Tibia.spr

Without it an editor guesses the flags from the dat signature and takes transparency as off, so it reads our spr
(4 bytes per pixel, RGBA) with 3 bytes per pixel: black boxes with stray pixels and boxes of vertical stripes (owner
2026-11-02, every item of the item palette). extended and transparency are read from the spr itself (u32 sprite
count; the pixel size that decodes the first records exactly); frame durations and frame groups come with the dat
format of 10.50 and 10.57 on.
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


def spr_layout(path, probe=60):
    """(extended, transparency) of a .spr: a u32 sprite count, and 4 bytes per pixel (RGBA) instead of 3 (RGB)"""
    with open(path, 'rb') as f:
        f.seek(0, 2)
        size = f.tell()

        def read(off, n):
            f.seek(off)
            data = f.read(n)
            if len(data) != n:
                raise ValueError('%s: short read at %d' % (path, off))
            return data

        layout = None
        for extended in (True, False):
            base = 8 if extended else 6
            count = struct.unpack('<I' if extended else '<H', read(4, base - 4))[0]
            if count == 0 or base + 4 * count > size:
                continue
            offsets = struct.unpack('<%dI' % count, read(base, 4 * count))
            first = [o for o in offsets if o][:probe]
            if first and min(first) >= base + 4 * count and max(first) < size:
                layout = (extended, first)
                break
        if layout is None:
            raise ValueError('%s: cannot read the sprite table' % path)
        extended, first = layout
        fits = {3: 0, 4: 0}
        for off in first:
            length = struct.unpack('<H', read(off + 3, 2))[0]
            rec = read(off + 5, length)
            for bpp in (3, 4):
                p = pixels = 0
                while p + 4 <= len(rec) and pixels <= 1024:
                    skip, run = struct.unpack_from('<HH', rec, p)
                    p += 4 + run * bpp
                    pixels += skip + run
                if p == len(rec) and pixels <= 1024:
                    fits[bpp] += 1
        if fits[4] == fits[3]:
            raise ValueError('%s: cannot tell the pixel size (%d records fit both)' % (path, fits[4]))
        return extended, fits[4] > fits[3]


def otfi_text(extended, transparency, frame_durations, frame_groups, dat='Tibia.dat', spr='Tibia.spr'):
    yes = lambda v: 'true' if v else 'false'  # noqa: E731
    return ('DatSpr\n  extended: %s\n  transparency: %s\n  frame-durations: %s\n  frame-groups: %s\n'
            '  metadata-file: %s\n  sprites-file: %s\n'
            % (yes(extended), yes(transparency), yes(frame_durations), yes(frame_groups), dat, spr))


def versions_xml(value, name, dat, spr, otb):
    return ('<?xml version="1.0" encoding="utf-8"?>\n<versions>\n'
            '  <version value="%d" string="%s" dat="%X" spr="%X" otb="%d"/>\n'
            '</versions>\n' % (value, name, dat, spr, otb))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('data_dir')
    ap.add_argument('out', nargs='?', help='versions.xml to write (needs items.otb in DATA_DIR)')
    ap.add_argument('--value', type=int, default=1098)
    ap.add_argument('--name', default='10.98')
    ap.add_argument('--otfi', help='also write the editors\' sprite info file (put it next to Tibia.dat)')
    args = ap.parse_args(argv)
    if not args.out and not args.otfi:
        ap.error('nothing to write: give OUT.xml, --otfi or both')
    d = Path(args.data_dir)
    if args.out:
        dat, spr = signature(d / 'Tibia.dat'), signature(d / 'Tibia.spr')
        _major, minor, _build = otb_version(d / 'items.otb')
        Path(args.out).write_text(versions_xml(args.value, args.name, dat, spr, minor), encoding='utf-8')
        print('versions.xml: %s dat %X spr %X otb %d' % (args.name, dat, spr, minor))
    if args.otfi:
        extended, alpha = spr_layout(d / 'Tibia.spr')
        text = otfi_text(extended, alpha, args.value >= 1050, args.value >= 1057)
        Path(args.otfi).write_text(text, encoding='utf-8')
        print('%s: extended %s transparency %s' % (Path(args.otfi).name, extended, alpha))
    return 0


if __name__ == '__main__':
    sys.exit(main())
