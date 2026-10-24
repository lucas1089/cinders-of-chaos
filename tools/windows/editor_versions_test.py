#!/usr/bin/env python3
"""Tests of editor_versions.py on synthetic files: python3 -I tools/windows/editor_versions_test.py"""
import struct
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import editor_versions as ev  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print('FAIL', what)


def otb(major, minor, build, escape_in_flags=False):
    flags = struct.pack('<I', 0xFD if escape_in_flags else 0)
    value = struct.pack('<III', major, minor, build) + b'OTB 3.57.0-10.98'.ljust(128, b'\0')
    body = bytes([0]) + flags + bytes([ev.ROOT_ATTR_VERSION]) + struct.pack('<H', len(value)) + value
    esc = bytearray()
    for b in body:
        if b in (ev.NODE_START, ev.NODE_END, ev.ESCAPE):
            esc.append(ev.ESCAPE)
        esc.append(b)
    return b'\0\0\0\0' + bytes([ev.NODE_START]) + bytes(esc) + bytes([ev.NODE_START, 0, ev.NODE_END, ev.NODE_END])


with tempfile.TemporaryDirectory() as tmp:
    d = Path(tmp)
    (d / 'Tibia.dat').write_bytes(struct.pack('<I', 0x42A3) + b'\0' * 8)
    (d / 'Tibia.spr').write_bytes(struct.pack('<I', 0x57BBD603) + b'\0' * 8)
    (d / 'items.otb').write_bytes(otb(3, 57, 62))
    check(ev.signature(d / 'Tibia.dat') == 0x42A3, 'dat signature')
    check(ev.signature(d / 'Tibia.spr') == 0x57BBD603, 'spr signature')
    check(ev.otb_version(d / 'items.otb') == (3, 57, 62), 'otb version')
    out = d / 'versions.xml'
    check(ev.main([str(d), str(out)]) == 0, 'main returns 0')
    text = out.read_text(encoding='utf-8')
    check('<version value="1098" string="10.98" dat="42A3" spr="57BBD603" otb="57"/>' in text, 'xml line: ' + text)

    # escaped bytes in the root node (flags 0xFD) and a version byte that needs escaping (0xFE)
    (d / 'items.otb').write_bytes(otb(3, 0xFE, 1, escape_in_flags=True))
    check(ev.otb_version(d / 'items.otb') == (3, 0xFE, 1), 'escaped otb version')

    (d / 'items.otb').write_bytes(b'\0\0\0\0\x00')
    try:
        ev.otb_version(d / 'items.otb')
        check(False, 'bad otb raises')
    except ValueError:
        pass
    (d / 'Tibia.dat').write_bytes(b'\1')
    try:
        ev.signature(d / 'Tibia.dat')
        check(False, 'short dat raises')
    except ValueError:
        pass

print('editor_versions_test: %s' % ('ok' if not failures else '%d failures' % failures))
sys.exit(1 if failures else 0)
