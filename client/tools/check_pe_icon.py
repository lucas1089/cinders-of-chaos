#!/usr/bin/env python3
"""Check that a Windows exe carries an icon (PE resource directory), stdlib only (O705).

Usage: python -I client/tools/check_pe_icon.py CindersLauncher.exe [--text TEXT]...

Fails (exit 1) unless the exe has an RT_GROUP_ICON resource whose every listed RT_ICON frame is in the file, with at least
one frame of 32 px or less and one of 48 px or more (Explorer, the taskbar, the Start menu and shortcuts all read this
resource: an exe without it shows the generic program icon, which is what "the launcher has no icon" looked like).
`--text TEXT` also requires that text to be somewhere in the file; the launcher build passes the manifest address of its
setup facts (`launcher/embedded.json`, compiled in), so a setup program without them (it would show the "launcher.json is
missing" box to every new player) fails here, before it is published. Prints one line per fact.
"""
import struct
import sys

sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import check_pe_hardening as pe  # noqa: E402

RT_ICON = 3
RT_GROUP_ICON = 14
IMAGE_DIRECTORY_ENTRY_RESOURCE = 2


class IconError(Exception):
    pass


def _resource_root(data):
    """-> (file offset of the resource directory, sections) or raises."""
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise IconError("not a PE file (no MZ header)")
    off = struct.unpack_from("<I", data, 0x3C)[0]
    if off + 24 > len(data) or data[off : off + 4] != b"PE\0\0":
        raise IconError("not a PE file (no PE signature)")
    _m, nsec, _t, _s, _n, optsize, _f = struct.unpack_from("<HHIIIHH", data, off + 4)
    opt = off + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    dd = opt + (112 if magic == 0x20B else 96 if magic == 0x10B else -1)
    if dd < opt:
        raise IconError("unknown optional header magic 0x%X" % magic)
    ndd = struct.unpack_from("<I", data, dd - 4)[0]
    if ndd <= IMAGE_DIRECTORY_ENTRY_RESOURCE:
        raise IconError("no resource directory")
    rva, size = struct.unpack_from("<II", data, dd + IMAGE_DIRECTORY_ENTRY_RESOURCE * 8)
    if not rva or not size:
        raise IconError("no resources at all (the exe was linked without its .res file)")
    try:
        sections = pe._sections(data, opt + optsize, nsec)
    except pe.PEError as e:
        raise IconError(str(e)) from e
    base = pe._rva_to_offset(sections, rva)
    if base is None:
        raise IconError("the resource directory is outside every section")
    return base, sections


def _entries(data, base, rel):
    """Entries of the directory at `rel` (from the resource root): [(id or None for a name, is_dir, target offset)]."""
    o = base + rel
    if o + 16 > len(data):
        raise IconError("resource directory is cut off")
    nnamed, nid = struct.unpack_from("<HH", data, o + 12)
    out = []
    for i in range(nnamed + nid):
        e = o + 16 + 8 * i
        if e + 8 > len(data):
            raise IconError("resource directory is cut off")
        name, to = struct.unpack_from("<II", data, e)
        out.append((None if i < nnamed else name, bool(to & 0x80000000), to & 0x7FFFFFFF))
    return out


def _leaf(data, base, sections, rel):
    """The first data entry below a directory: its bytes."""
    for _id, is_dir, to in _entries(data, base, rel):
        if is_dir:
            return _leaf(data, base, sections, to)
        d = base + to
        if d + 16 > len(data):
            raise IconError("resource data entry is cut off")
        rva, size = struct.unpack_from("<II", data, d)
        o = pe._rva_to_offset(sections, rva)
        if o is None or o + size > len(data):
            raise IconError("resource data is outside the file")
        return data[o : o + size]
    return None


def icons(data):
    """-> (group icon resources as {id: bytes}, ids of the RT_ICON frames present)"""
    base, sections = _resource_root(data)
    groups, frames = {}, set()
    for typ, is_dir, to in _entries(data, base, 0):
        if typ not in (RT_ICON, RT_GROUP_ICON) or not is_dir:
            continue
        for rid, sub, rel in _entries(data, base, to):
            if rid is None or not sub:
                continue
            if typ == RT_ICON:
                frames.add(rid)
            else:
                blob = _leaf(data, base, sections, rel)
                if blob is not None:
                    groups[rid] = blob
    return groups, frames


def frames_of(group):
    """-> [(width, height, frame id)] of a GRPICONDIR; 0 means 256."""
    if len(group) < 6 or struct.unpack_from("<HH", group, 0) != (0, 1):
        raise IconError("RT_GROUP_ICON is not an icon directory")
    n = struct.unpack_from("<H", group, 4)[0]
    if len(group) < 6 + 14 * n or n == 0:
        raise IconError("RT_GROUP_ICON is cut off or empty")
    out = []
    for i in range(n):
        w, h, _c, _r, _p, _b, _size, fid = struct.unpack_from("<BBBBHHIH", group, 6 + 14 * i)
        out.append((w or 256, h or 256, fid))
    return out


def check(data, texts=()):
    """-> (lines, failed)"""
    lines, failed = [], False
    try:
        groups, frames = icons(data)
        if not groups:
            raise IconError("no RT_GROUP_ICON resource: the exe shows the generic program icon")
        gid = min(groups)  # Explorer takes the lowest id
        sizes = frames_of(groups[gid])
        missing = [f for _w, _h, f in sizes if f not in frames]
        if missing:
            raise IconError("RT_GROUP_ICON %d names frames that are not in the file: %s" % (gid, missing))
        widths = sorted(w for w, _h, _f in sizes)
        if widths[0] > 32 or widths[-1] < 48:
            raise IconError("icon frames %s: want one of 32 px or less and one of 48 px or more" % widths)
        lines.append("icon             ok (group %d, frames %s)" % (gid, ", ".join(str(w) for w in widths)))
    except IconError as e:
        lines.append("icon             MISSING (%s)" % e)
        failed = True
    for t in texts:
        if t.encode() in data or t.encode("utf-16-le") in data:
            lines.append("text             ok (%s)" % t[:60])
        else:
            lines.append("text             MISSING (%s)" % t[:60])
            failed = True
    return lines, failed


def main(argv):
    args, path, texts, i = argv[1:], None, [], 0
    while i < len(args):
        if args[i] == "--text" and i + 1 < len(args):
            texts.append(args[i + 1])
            i += 2
        elif path is None and not args[i].startswith("--"):
            path = args[i]
            i += 1
        else:
            print(__doc__)
            return 2
    if path is None:
        print(__doc__)
        return 2
    with open(path, "rb") as f:
        data = f.read()
    lines, failed = check(data, texts)
    print("%s:" % path)
    print("\n".join(lines))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
