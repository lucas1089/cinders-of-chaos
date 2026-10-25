#!/usr/bin/env python3
"""Check the hardening flags of a Windows exe (PE header), stdlib only.

Usage: python -I client/tools/check_pe_hardening.py Chaos.exe [--require guard_cf] [--require cet_compat]

Always required (exit 1 when missing): DYNAMICBASE (ASLR, with a relocation table), HIGH_ENTROPY_VA (64-bit ASLR),
NX_COMPAT (DEP). GUARD_CF (control flow guard) and CET_COMPAT (shadow stack) are reported; they only fail the check
when named with --require, since the build sets them only where the toolchain takes the flag (client/BASE.md
"Release build flags"). Prints one line per flag, `ok`, `MISSING` or `not set`.
"""
import struct
import sys

# IMAGE_OPTIONAL_HEADER.DllCharacteristics
FLAGS = {
    "high_entropy_va": 0x0020,
    "dynamic_base": 0x0040,
    "nx_compat": 0x0100,
    "guard_cf": 0x4000,
}
ALWAYS = ("dynamic_base", "high_entropy_va", "nx_compat")
IMAGE_FILE_RELOCS_STRIPPED = 0x0001
IMAGE_DEBUG_TYPE_EX_DLLCHARACTERISTICS = 20
EX_DLL_CET_COMPAT = 0x0001


class PEError(Exception):
    pass


def _sections(data, first, count):
    out = []
    for i in range(count):
        o = first + 40 * i
        if o + 40 > len(data):
            raise PEError("section table is cut off")
        vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, o + 8)
        out.append((va, max(vsize, rawsize), rawptr))
    return out


def _rva_to_offset(sections, rva):
    for va, size, rawptr in sections:
        if va <= rva < va + size:
            return rawptr + (rva - va)
    return None


def parse(data):
    """-> dict: machine, file_characteristics, dll_characteristics, cet_compat (bool)."""
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise PEError("not a PE file (no MZ header)")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if pe + 24 > len(data) or data[pe:pe + 4] != b"PE\0\0":
        raise PEError("not a PE file (no PE signature)")
    machine, nsec, _ts, _sym, _nsym, optsize, fchar = struct.unpack_from("<HHIIIHH", data, pe + 4)
    opt = pe + 24
    if opt + optsize > len(data) or optsize < 70:
        raise PEError("optional header is cut off")
    magic = struct.unpack_from("<H", data, opt)[0]
    if magic == 0x20B:      # PE32+
        dd_off, ndd_off = opt + 112, opt + 108
    elif magic == 0x10B:    # PE32
        dd_off, ndd_off = opt + 96, opt + 92
    else:
        raise PEError("unknown optional header magic 0x%X" % magic)
    dllchar = struct.unpack_from("<H", data, opt + 70)[0]
    cet = False
    ndd = struct.unpack_from("<I", data, ndd_off)[0] if ndd_off + 4 <= len(data) else 0
    if ndd > 6 and dd_off + 7 * 8 <= opt + optsize:
        dbg_rva, dbg_size = struct.unpack_from("<II", data, dd_off + 6 * 8)
        sections = _sections(data, opt + optsize, nsec)
        base = _rva_to_offset(sections, dbg_rva) if dbg_rva else None
        if base is not None:
            for i in range(dbg_size // 28):
                e = base + 28 * i
                if e + 28 > len(data):
                    break
                dtype, dsize, _rva, rawptr = struct.unpack_from("<IIII", data, e + 12)
                if dtype == IMAGE_DEBUG_TYPE_EX_DLLCHARACTERISTICS and dsize >= 4 and rawptr + 4 <= len(data):
                    cet = bool(struct.unpack_from("<I", data, rawptr)[0] & EX_DLL_CET_COMPAT)
    return {"machine": machine, "file_characteristics": fchar, "dll_characteristics": dllchar, "cet_compat": cet}


def check(info, require=()):
    """-> (lines, failed). `require` adds guard_cf / cet_compat to the always required flags."""
    lines, failed = [], False
    need = set(ALWAYS) | set(require)
    state = {k: bool(info["dll_characteristics"] & v) for k, v in FLAGS.items()}
    state["cet_compat"] = info["cet_compat"]
    for name in ("dynamic_base", "high_entropy_va", "nx_compat", "guard_cf", "cet_compat"):
        if state[name]:
            lines.append("%-16s ok" % name)
        elif name in need:
            lines.append("%-16s MISSING" % name)
            failed = True
        else:
            lines.append("%-16s not set" % name)
    if state["dynamic_base"] and info["file_characteristics"] & IMAGE_FILE_RELOCS_STRIPPED:
        lines.append("%-16s MISSING (DYNAMICBASE set but the relocation table is stripped: no ASLR)" % "relocations")
        failed = True
    return lines, failed


def main(argv):
    args = argv[1:]
    require, path, i = [], None, 0
    while i < len(args):
        if args[i] == "--require" and i + 1 < len(args):
            require.append(args[i + 1].lower())
            i += 2
        elif path is None and not args[i].startswith("--"):
            path = args[i]
            i += 1
        else:
            print(__doc__)
            return 2
    bad = [r for r in require if r not in ("guard_cf", "cet_compat")]
    if path is None or bad:
        print(__doc__)
        return 2
    with open(path, "rb") as f:
        data = f.read()
    try:
        info = parse(data)
    except PEError as e:
        print("%s: %s" % (path, e))
        return 1
    lines, failed = check(info, require)
    print("%s: machine 0x%04X, DllCharacteristics 0x%04X" % (path, info["machine"], info["dll_characteristics"]))
    print("\n".join(lines))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
