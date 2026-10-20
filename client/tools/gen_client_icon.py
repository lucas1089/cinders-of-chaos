#!/usr/bin/env python3
"""The client's own window and executable icon, made from the existing brand icon (docs/brand/cinders_logo_icon.png).

  python3 -I client/tools/gen_client_icon.py [--check]

Writes (no new art, only a copy and a resize of the brand icon):
  client/overlay/data/images/clienticon.png   the window icon (g_window.setIcon('/images/clienticon')); replaces the
                                              stock picture when tools/assemble_client.sh copies the overlay
  client/overlay/src/otcicon.ico              the Windows executable icon (src/otcicon.rc, IDI_ICON1); assemble_client.sh
                                              copies overlay/src/ over the base client's src/ before the build
--check: fail when the PNG differs from the brand icon or the ico lacks a size (no byte compare of the ico: the
encoder differs between Pillow versions).
"""
import io
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs" / "brand" / "cinders_logo_icon.png"
PNG = ROOT / "client" / "overlay" / "data" / "images" / "clienticon.png"
ICO = ROOT / "client" / "overlay" / "src" / "otcicon.ico"
SIZES = (16, 24, 32, 48, 64, 128, 256)


def ico_sizes(data):
    if data[:4] != b"\x00\x00\x01\x00":
        return None
    n = struct.unpack("<H", data[4:6])[0]
    out = []
    for i in range(n):
        w = data[6 + 16 * i]
        out.append(256 if w == 0 else w)
    return sorted(out)


def build_ico():
    from PIL import Image
    img = Image.open(SRC).convert("RGBA")
    buf = io.BytesIO()
    img.save(buf, format="ICO", sizes=[(s, s) for s in SIZES])
    return buf.getvalue()


def main():
    check = "--check" in sys.argv[1:]
    src = SRC.read_bytes()
    if check:
        bad = []
        if not PNG.is_file() or PNG.read_bytes() != src:
            bad.append("%s differs from %s" % (PNG.relative_to(ROOT), SRC.relative_to(ROOT)))
        got = ico_sizes(ICO.read_bytes()) if ICO.is_file() else None
        if got != sorted(SIZES):
            bad.append("%s sizes %s, want %s" % (ICO.relative_to(ROOT), got, list(SIZES)))
        for b in bad:
            print("FAIL " + b)
        print("client icon: %s" % ("stale" if bad else "ok"))
        return 1 if bad else 0
    PNG.parent.mkdir(parents=True, exist_ok=True)
    ICO.parent.mkdir(parents=True, exist_ok=True)
    PNG.write_bytes(src)
    ICO.write_bytes(build_ico())
    print("wrote %s, %s" % (PNG.relative_to(ROOT), ICO.relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
