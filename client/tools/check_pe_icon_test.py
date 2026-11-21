#!/usr/bin/env python3
"""Unit test of check_pe_icon.py: a PE32+ with a .rsrc section built in memory, with the real launcher icon in it (O705).
Run: python3 -I client/tools/check_pe_icon_test.py"""
import contextlib
import io
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_pe_icon as c  # noqa: E402

ICO = os.path.join(HERE, "..", "..", "launcher", "assets", "app.ico")
RSRC_RVA, RSRC_OFF = 0x2000, 0x400


def ico_resources(ico):
    """({frame id: bytes}, group bytes) the way build.rs of the launcher turns an .ico file into resources."""
    n = struct.unpack_from("<H", ico, 4)[0]
    frames, group = {}, struct.pack("<HHH", 0, 1, n)
    for i in range(n):
        head = ico[6 + 16 * i : 6 + 16 * i + 8]
        size, off = struct.unpack_from("<II", ico, 6 + 16 * i + 8)
        frames[i + 1] = ico[off : off + size]
        group += head + struct.pack("<IH", size, i + 1)
    return frames, group


def build_rsrc(tree):
    """tree {type: {id: bytes}} -> the bytes of a resource section (one language level, 0x409)."""
    types = sorted(tree)
    # sizes first: root, one dir per type, one dir per id, one data entry per id, then the blobs
    root = 16 + 8 * len(types)
    off = root
    type_dir = {}
    for t in types:
        type_dir[t] = off
        off += 16 + 8 * len(tree[t])
    id_dir = {}
    for t in types:
        for rid in sorted(tree[t]):
            id_dir[(t, rid)] = off
            off += 16 + 8
    entry = {}
    for t in types:
        for rid in sorted(tree[t]):
            entry[(t, rid)] = off
            off += 16
    blob = {}
    for t in types:
        for rid in sorted(tree[t]):
            blob[(t, rid)] = off
            off += (len(tree[t][rid]) + 3) & ~3
    out = bytearray(off)

    def dirhead(at, n):
        struct.pack_into("<IIHHHH", out, at, 0, 0, 4, 0, 0, n)

    dirhead(0, len(types))
    for i, t in enumerate(types):
        struct.pack_into("<II", out, 16 + 8 * i, t, 0x80000000 | type_dir[t])
        ids = sorted(tree[t])
        dirhead(type_dir[t], len(ids))
        for j, rid in enumerate(ids):
            struct.pack_into("<II", out, type_dir[t] + 16 + 8 * j, rid, 0x80000000 | id_dir[(t, rid)])
            dirhead(id_dir[(t, rid)], 1)
            struct.pack_into("<II", out, id_dir[(t, rid)] + 16, 0x409, entry[(t, rid)])
            data = tree[t][rid]
            struct.pack_into("<IIII", out, entry[(t, rid)], RSRC_RVA + blob[(t, rid)], len(data), 0, 0)
            out[blob[(t, rid)] : blob[(t, rid)] + len(data)] = data
    return bytes(out)


def make_pe(rsrc=None, pe32=False, extra=b""):
    opt_size = 224 if pe32 else 240
    opt = bytearray(opt_size)
    struct.pack_into("<H", opt, 0, 0x10B if pe32 else 0x20B)
    ndd_off, dd_off = (92, 96) if pe32 else (108, 112)
    struct.pack_into("<I", opt, ndd_off, 16)
    if rsrc is not None:
        struct.pack_into("<II", opt, dd_off + 2 * 8, RSRC_RVA, len(rsrc))
    pe_off = 0x80
    head = bytearray(RSRC_OFF)
    head[0:2] = b"MZ"
    struct.pack_into("<I", head, 0x3C, pe_off)
    head[pe_off : pe_off + 4] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", head, pe_off + 4, 0x8664, 1, 0, 0, 0, opt_size, 0x22)
    head[pe_off + 24 : pe_off + 24 + opt_size] = opt
    sec = pe_off + 24 + opt_size
    head[sec : sec + 8] = b".rsrc\0\0\0"
    body = rsrc or b"\0" * 16
    struct.pack_into("<IIII", head, sec + 8, len(body), RSRC_RVA, len(body), RSRC_OFF)
    return bytes(head) + body + extra


def tree_of(ico):
    frames, group = ico_resources(ico)
    return {c.RT_ICON: frames, c.RT_GROUP_ICON: {1: group}}


def main():
    ico = open(ICO, "rb").read()
    good = make_pe(build_rsrc(tree_of(ico)))
    lines, failed = c.check(good)
    assert not failed, lines
    assert lines[0].startswith("icon             ok (group 1, frames 16, 20, 24, 32, 40, 48, 64, 128, 256)"), lines
    # the same with a 32-bit header
    assert not c.check(make_pe(build_rsrc(tree_of(ico)), pe32=True))[1]

    # no resources at all: what a link without the .res file gives
    lines, failed = c.check(make_pe(None))
    assert failed and "no resources at all" in lines[0], lines
    # resources but no icon
    lines, failed = c.check(make_pe(build_rsrc({24: {1: b"<manifest/>"}})))
    assert failed and "no RT_GROUP_ICON" in lines[0], lines
    # a group that names a frame the file does not have
    t = tree_of(ico)
    del t[c.RT_ICON][3]
    lines, failed = c.check(make_pe(build_rsrc(t)))
    assert failed and "frames that are not in the file: [3]" in lines[0], lines
    # only big frames: Explorer would scale a 256 px picture down for the small views
    frames, group = ico_resources(ico)
    only_big = struct.pack("<HHH", 0, 1, 1) + group[6 + 14 * 8 : 6 + 14 * 9]
    lines, failed = c.check(make_pe(build_rsrc({c.RT_ICON: {9: frames[9]}, c.RT_GROUP_ICON: {1: only_big}})))
    assert failed and "want one of 32 px or less" in lines[0], lines
    # garbage
    for bad in (b"", b"MZ" + b"\0" * 100, b"hello" * 100):
        lines, failed = c.check(bad)
        assert failed, bad

    # text: found as plain or wide text, missing is a failure
    url = "https://www.example.test/updates/live/manifest.json"
    lines, failed = c.check(make_pe(build_rsrc(tree_of(ico)), extra=url.encode()), [url])
    assert not failed, lines
    assert c.check(make_pe(build_rsrc(tree_of(ico)), extra=url.encode("utf-16-le")), [url])[1] is False
    lines, failed = c.check(good, [url])
    assert failed and "text             MISSING" in lines[1], lines

    # the command line
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "a.exe")
        open(p, "wb").write(good)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            assert c.main(["x", p]) == 0
            assert c.main(["x", p, "--text", url]) == 1
            assert c.main(["x"]) == 2
        assert "icon             ok" in out.getvalue()
    print("check_pe_icon_test: ok")


if __name__ == "__main__":
    main()
