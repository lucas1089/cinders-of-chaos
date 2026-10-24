#!/usr/bin/env python3
"""Every spell of the client's spell data has a real icon in all three spell icon sheets (O157).

Owner report 2026-10-24: Gutting Slash, Razor Rain, Venom Spiral, Crescent Cut and Last Breath showed no icon in the
spell list. The icon of a Chaos spell is a cell of client/overlay/data/images/game/spells/spell-icons-{32x32,22x24,20x20}.png
(20 columns, cell n at col (n-1)%20, row (n-1)//20; game_chaosspells/spelldata.lua: iconKey and clientId). A spell
whose cell lies past the end of a sheet, is transparent, or is still the neutral filler plate that
client/tools/gen_all_spell_icons.py draws in every unused cell, has no icon in the game.

Checks:
 - every <instant> of server/data/spells/chaos/spells_chaos.xml is in spelldata.lua (by id, name and words), and the
   other way round;
 - every entry has an iconKey and a clientId, no two spells share a clientId or an iconKey;
 - in each of the three sheets the cell of every clientId exists, is not empty, and is not the filler plate
   (the last cell of the sheet, which no spell uses).
Pure standard library (the PNG decoder reads 8-bit RGB and RGBA), so it runs with -I and without Pillow.
usage: python3 -I tools/ci/check_spell_icons.py [--list]      (--list prints the spells and their cells)
"""
import os
import re
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SPELLDATA = os.path.join(REPO, 'client', 'overlay', 'modules', 'game_chaosspells', 'spelldata.lua')
XML = os.path.join(REPO, 'server', 'data', 'spells', 'chaos', 'spells_chaos.xml')
SHEETS_DIR = os.path.join(REPO, 'client', 'overlay', 'data', 'images', 'game', 'spells')
SHEETS = [('32x32', 32, 32), ('22x24', 22, 24), ('20x20', 20, 20)]
COLS = 20


def read_png(path):
    """(width, height, bytes per pixel, rows as a list of bytes) of an 8-bit RGB or RGBA PNG"""
    data = open(path, 'rb').read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('not a PNG')
    pos, idat, ihdr = 8, [], None
    while pos < len(data):
        n, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b'IHDR':
            ihdr = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            idat.append(body)
        pos += 12 + n
    w, h, depth, ctype, _, _, interlace = ihdr
    if depth != 8 or ctype not in (2, 6) or interlace:
        raise ValueError('%s: only 8-bit RGB / RGBA without interlace (type %d, depth %d)' % (path, ctype, depth))
    bpp = 4 if ctype == 6 else 3
    raw = zlib.decompress(b''.join(idat))
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        cur = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = cur[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                cur[i] = (cur[i] + a) & 255
            elif f == 2:
                cur[i] = (cur[i] + b) & 255
            elif f == 3:
                cur[i] = (cur[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 255
        rows.append(bytes(cur))
        prev = cur
    return w, h, bpp, rows


def cell(sheet, n, cw, ch):
    """the bytes of cell n (1-based), or None when it lies outside the sheet"""
    w, h, bpp, rows = sheet
    x, y = ((n - 1) % COLS) * cw, ((n - 1) // COLS) * ch
    if n < 1 or x + cw > w or y + ch > h:
        return None
    return b''.join(rows[y + j][x * bpp:(x + cw) * bpp] for j in range(ch))


def blank(px, bpp):
    """True for a cell that draws nothing: fully transparent (RGBA) or one flat colour"""
    if bpp == 4:
        return not any(px[3::4])
    return len(set(px[i:i + 3] for i in range(0, len(px), 3))) <= 1


def load_spelldata(path=SPELLDATA):
    out = []
    text = open(path, encoding='utf-8').read()
    for line in text.splitlines():
        m = re.match(r'\s*\{ id = (\d+), name = "([^"]+)", words = "([^"]+)"', line)
        if not m:
            continue
        key = re.search(r'iconKey = "([^"]*)"', line)
        cid = re.search(r'clientId = (\d+)', line)
        out.append({'id': int(m.group(1)), 'name': m.group(2), 'words': m.group(3),
                    'iconKey': key.group(1) if key else None, 'clientId': int(cid.group(1)) if cid else None})
    return out


def load_server(path=XML):
    text = open(path, encoding='utf-8').read()
    out = []
    for m in re.finditer(r'<instant ([^>]*)>', text):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        out.append({'id': int(a['spellid']), 'name': a['name'], 'words': a['words']})
    return out


def problems(spells, server, sheets):
    """the failures, as strings. spells: load_spelldata(); server: load_server(); sheets: {suffix: (png, cw, ch)}"""
    bad = []
    have = {(s['id'], s['name'], s['words']) for s in spells}
    for s in server:
        if (s['id'], s['name'], s['words']) not in have:
            bad.append('%s (%s, id %d) is on the server but not in spelldata.lua: run client/tools/gen_spell_data.py' % (
                s['name'], s['words'], s['id']))
    want = {(s['id'], s['name'], s['words']) for s in server}
    for s in spells:
        if (s['id'], s['name'], s['words']) not in want:
            bad.append('%s (%s, id %d) is in spelldata.lua but not in spells_chaos.xml' % (s['name'], s['words'], s['id']))
    seen_cell, seen_key = {}, {}
    for s in spells:
        if not s['iconKey'] or not s['clientId']:
            bad.append('%s has no iconKey / clientId' % s['name'])
            continue
        if s['clientId'] in seen_cell:
            bad.append('%s and %s share the icon cell %d' % (s['name'], seen_cell[s['clientId']], s['clientId']))
        seen_cell[s['clientId']] = s['name']
        if s['iconKey'] in seen_key:
            bad.append('%s and %s share the icon key %s' % (s['name'], seen_key[s['iconKey']], s['iconKey']))
        seen_key[s['iconKey']] = s['name']
    for suffix, (png, cw, ch) in sheets.items():
        w, h, bpp, _ = png
        total = (w // cw) * (h // ch)
        filler = cell(png, total, cw, ch)
        if total in seen_cell:
            bad.append('sheet %s: its last cell %d is a spell icon, so the filler plate cannot be told apart' % (suffix, total))
            filler = None
        for s in spells:
            n = s['clientId']
            if not n:
                continue
            px = cell(png, n, cw, ch)
            if px is None:
                bad.append('sheet %s: %s (cell %d) lies outside the sheet (%d cells): regenerate it with '
                           'client/tools/gen_all_spell_icons.py' % (suffix, s['name'], n, total))
            elif blank(px, bpp):
                bad.append('sheet %s: %s (cell %d) is empty' % (suffix, s['name'], n))
            elif filler is not None and px == filler:
                bad.append('sheet %s: %s (cell %d) is the filler plate, no icon is drawn for it' % (suffix, s['name'], n))
    return bad


def main(argv):
    spells, server = load_spelldata(), load_server()
    sheets = {}
    for suffix, cw, ch in SHEETS:
        sheets[suffix] = (read_png(os.path.join(SHEETS_DIR, 'spell-icons-%s.png' % suffix)), cw, ch)
    if '--list' in argv:
        for s in spells:
            print('%4d  cell %3d  %-24s %s' % (s['id'], s['clientId'] or 0, s['name'], s['words']))
    bad = problems(spells, server, sheets)
    for b in bad:
        print('FAIL ' + b)
    if bad:
        return 1
    print('spell icons: %d spells, every one has a drawn cell in %d sheets' % (len(spells), len(sheets)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
