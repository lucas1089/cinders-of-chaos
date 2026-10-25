#!/usr/bin/env python3
"""Unit test of check_pe_hardening.py: a tiny PE32+ header built in memory. Run: python3 -I client/tools/check_pe_hardening_test.py"""
import contextlib
import io
import os
import struct
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_pe_hardening as c  # noqa: E402


def make_pe(dllchar, fchar=0x0022, cet=None, pe32=False):
    """One section (.rdata at RVA 0x1000, file offset 0x400) holding the debug directory when `cet` is not None."""
    opt_size = 224 if pe32 else 240
    opt = bytearray(opt_size)
    struct.pack_into("<H", opt, 0, 0x10B if pe32 else 0x20B)
    struct.pack_into("<H", opt, 70, dllchar)
    ndd_off, dd_off = (92, 96) if pe32 else (108, 112)
    struct.pack_into("<I", opt, ndd_off, 16)
    if cet is not None:
        struct.pack_into("<II", opt, dd_off + 6 * 8, 0x1000, 28)
    pe_off = 0x80
    head = bytearray(0x400)
    head[0:2] = b"MZ"
    struct.pack_into("<I", head, 0x3C, pe_off)
    head[pe_off:pe_off + 4] = b"PE\0\0"
    struct.pack_into("<HHIIIHH", head, pe_off + 4, 0x8664, 1, 0, 0, 0, opt_size, fchar)
    head[pe_off + 24:pe_off + 24 + opt_size] = opt
    sec = pe_off + 24 + opt_size
    head[sec:sec + 8] = b".rdata\0\0"
    struct.pack_into("<IIII", head, sec + 8, 0x200, 0x1000, 0x200, 0x400)
    body = bytearray(0x200)
    if cet is not None:
        # IMAGE_DEBUG_DIRECTORY at the start, its data (the EX_DLLCHARACTERISTICS dword) at file offset 0x400 + 0x40
        struct.pack_into("<IIHHIIII", body, 0, 0, 0, 0, 0, c.IMAGE_DEBUG_TYPE_EX_DLLCHARACTERISTICS, 4, 0x1040, 0x440)
        struct.pack_into("<I", body, 0x40, 1 if cet else 0)
    return bytes(head + body)


def run(data, require=()):
    return c.check(c.parse(data), require)


def main():
    good = 0x0020 | 0x0040 | 0x0100
    lines, failed = run(make_pe(good))
    assert not failed, lines
    assert "guard_cf         not set" in lines and "cet_compat       not set" in lines, lines

    for missing, name in ((0x0020, "high_entropy_va"), (0x0040, "dynamic_base"), (0x0100, "nx_compat")):
        lines, failed = run(make_pe(good & ~missing))
        assert failed and any(l.startswith(name) and "MISSING" in l for l in lines), (name, lines)

    # guard_cf only fails when required
    assert not run(make_pe(good))[1]
    assert run(make_pe(good), ("guard_cf",))[1]
    lines, failed = run(make_pe(good | 0x4000), ("guard_cf",))
    assert not failed and "guard_cf         ok" in lines, lines

    # CET compat from the debug directory
    assert c.parse(make_pe(good, cet=True))["cet_compat"] is True
    assert c.parse(make_pe(good, cet=False))["cet_compat"] is False
    assert not run(make_pe(good, cet=True), ("cet_compat",))[1]
    assert run(make_pe(good, cet=False), ("cet_compat",))[1]

    # ASLR flag with a stripped relocation table is no ASLR
    lines, failed = run(make_pe(good, fchar=0x0023))
    assert failed and any("relocations" in l for l in lines), lines

    # PE32 layout parses too
    assert c.parse(make_pe(good, pe32=True))["dll_characteristics"] == good
    assert c.parse(make_pe(good, cet=True, pe32=True))["cet_compat"] is True

    # garbage and truncation
    for bad in (b"", b"MZ", b"\0" * 0x100, make_pe(good)[:0x90]):
        try:
            c.parse(bad)
        except c.PEError:
            continue
        raise AssertionError("accepted a broken file")

    # command line
    with tempfile.TemporaryDirectory() as d, contextlib.redirect_stdout(io.StringIO()):
        p = os.path.join(d, "a.exe")
        with open(p, "wb") as f:
            f.write(make_pe(good))
        assert c.main(["x", p]) == 0
        assert c.main(["x", p, "--require", "guard_cf"]) == 1
        assert c.main(["x", p, "--require", "nonsense"]) == 2
        with open(p, "wb") as f:
            f.write(make_pe(0x0040))
        assert c.main(["x", p]) == 1
    print("check_pe_hardening_test: ok")


if __name__ == "__main__":
    main()
