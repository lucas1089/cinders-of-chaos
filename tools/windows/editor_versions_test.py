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


def spr(records, extended=True, bpp=4):
    """a .spr with one record per entry: None = empty id, else a list of (skip, run) pixel runs"""
    head = struct.pack('<II', 0x57BBD603, len(records)) if extended else struct.pack('<IH', 0x57BBD603, len(records))
    table, body = [], b''
    start = len(head) + 4 * len(records)
    for runs in records:
        if runs is None:
            table.append(0)
            continue
        data = b''.join(struct.pack('<HH', skip, run) + bytes([200, 100, 50, 255][:bpp]) * run for skip, run in runs)
        table.append(start + len(body))
        body += b'\xff\x00\xff' + struct.pack('<H', len(data)) + data
    return head + struct.pack('<%dI' % len(records), *table) + body


with tempfile.TemporaryDirectory() as tmp:
    d = Path(tmp)
    # sprite layout: u32 count and RGBA (the Chaos pair), u16 count and RGB (a stock older spr)
    runs = [[(0, 12), (20, 4)], None, [(5, 3), (100, 9), (1, 1)], [(0, 32)]]
    (d / 'a.spr').write_bytes(spr(runs, extended=True, bpp=4))
    check(ev.spr_layout(d / 'a.spr') == (True, True), 'extended RGBA spr')
    (d / 'b.spr').write_bytes(spr(runs, extended=False, bpp=3))
    check(ev.spr_layout(d / 'b.spr') == (False, False), 'u16 RGB spr')
    (d / 'c.spr').write_bytes(spr([[(0, 12)], [(4, 8)]], extended=True, bpp=3))
    check(ev.spr_layout(d / 'c.spr') == (True, False), 'extended RGB spr')
    (d / 'e.spr').write_bytes(spr([None, None]))
    try:
        ev.spr_layout(d / 'e.spr')
        check(False, 'spr without records raises')
    except ValueError:
        pass
    text = ev.otfi_text(True, True, True, True)
    for line in ('DatSpr', '  extended: true', '  transparency: true', '  frame-durations: true', '  frame-groups: true',
                 '  metadata-file: Tibia.dat', '  sprites-file: Tibia.spr'):
        check(line in text.split('\n'), 'otfi line ' + line)
    check('false' in ev.otfi_text(True, False, True, True), 'otfi false flag')

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
    # --otfi reads the spr: the Chaos pair is extended and RGBA, so every flag is on
    (d / 'Tibia.spr').write_bytes(spr(runs, extended=True, bpp=4))
    check(ev.main([str(d), str(out), '--otfi', str(d / 'Tibia.otfi')]) == 0, 'main with --otfi returns 0')
    check((d / 'Tibia.otfi').read_text(encoding='utf-8') == ev.otfi_text(True, True, True, True), 'otfi file')
    # the map editor's client folder has no items.otb: --otfi alone
    (d / 'Tibia.otfi').unlink()
    (d / 'items.otb').rename(d / 'items.otb.off')
    check(ev.main([str(d), '--otfi', str(d / 'Tibia.otfi')]) == 0, 'main with --otfi alone returns 0')
    check((d / 'Tibia.otfi').is_file(), 'otfi alone written')
    (d / 'items.otb.off').rename(d / 'items.otb')

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
