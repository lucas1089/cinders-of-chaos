#!/usr/bin/env python3
"""Mobile layout guard (O313): a window must fit the phone interface or have a $mobile rule.

The phone zoom leaves an interface of about 1170 x 540 logical pixels on a 1080-high phone
(game_chaosuiscale PHONE_W 960, PHONE_H 540). This tool reads the top-level windows of every
client/overlay/modules/**/*.otui and fails when a window with a fixed size is taller than 540 or
wider than 960 and has no $mobile (or $!mobile) rule anywhere in its body. Windows that are over
the limit today are listed in client/tools/mobile_layout_baseline.txt, one "module/file:window WxH"
per line, so the list can only shrink.

OTUI is indentation based. A top-level window is a line at column 0 that is either an instance whose
name ends in "Window" or a definition "Name < Base" where the name or the base ends in "Window".
Size comes from direct properties (two spaces): "size: W H", "width: W", "height: H". A window with
"anchors.fill" has no fixed size and is skipped. A window without its own size uses the size of its
base when that base is defined in the same file. Non-numeric values (expressions) count as unknown.

Usage:
  python3 -I client/tools/check_mobile_layout.py                  check
  python3 -I client/tools/check_mobile_layout.py --write-baseline regenerate the baseline
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MODULES = os.path.join(ROOT, 'client', 'overlay', 'modules')
BASELINE = os.path.join(HERE, 'mobile_layout_baseline.txt')
MAX_W, MAX_H = 960, 540

_HEAD = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)(?:\s*<\s*([A-Za-z_][A-Za-z0-9_]*))?\s*$')
_INT = re.compile(r'^-?\d+$')


def _split_blocks(text):
    """Top-level blocks as (header, [body lines]); comments and blank lines dropped."""
    blocks = []
    cur = None
    for raw in text.split('\n'):
        line = raw.rstrip('\r')
        s = line.strip()
        if not s or s.startswith('//'):
            continue
        if line[0] not in ' \t':
            cur = (s, [])
            blocks.append(cur)
        elif cur is not None:
            cur[1].append(line)
    return blocks


def _is_window(name, base):
    return name.endswith('Window') or (base is not None and base.endswith('Window'))


def _parse_body(body):
    """-> (width, height, fill, id, mobile): width and height are ints or None."""
    w = h = None
    fill = False
    wid = None
    mobile = False
    for line in body:
        s = line.strip()
        if s.startswith('$mobile') or s.startswith('$!mobile'):
            mobile = True
        indent = len(line) - len(line.lstrip(' '))
        if indent != 2 or ':' not in s:
            continue
        key, _, val = s.partition(':')
        key, val = key.strip(), val.strip()
        if key == 'size':
            parts = val.split()
            if len(parts) == 2 and all(_INT.match(p) for p in parts):
                w, h = int(parts[0]), int(parts[1])
        elif key == 'width' and _INT.match(val):
            w = int(val)
        elif key == 'height' and _INT.match(val):
            h = int(val)
        elif key == 'anchors.fill':
            fill = True
        elif key == 'id':
            wid = val
    return w, h, fill, wid, mobile


def scan_text(text):
    """-> list of (window key, width, height, has_mobile) for the windows of one file that have a fixed size."""
    infos = {}
    order = []
    for header, body in _split_blocks(text):
        m = _HEAD.match(header)
        if not m:
            continue
        name, base = m.group(1), m.group(2)
        w, h, fill, wid, mobile = _parse_body(body)
        order.append((name, base, w, h, fill, wid, mobile))
        if base is not None:
            infos[name] = (base, w, h, fill, mobile)
    out = []
    seen = {}
    for name, base, w, h, fill, wid, mobile in order:
        if not _is_window(name, base):
            continue
        cur = base
        hops = 0
        while (w is None or h is None) and cur in infos and hops < 8:       # inherit from a base of this file
            b2, bw, bh, bfill, bmob = infos[cur]
            if w is None:
                w = bw
            if h is None:
                h = bh
            fill = fill or bfill
            mobile = mobile or bmob
            cur = b2
            hops += 1
        if fill or (w is None and h is None):
            continue
        key = name + ('#' + wid if wid and base is None else '')
        w, h = w or 0, h or 0
        if key in seen:                                                      # definition and instance: keep the larger
            o = seen[key]
            o[1], o[2], o[3] = max(o[1], w), max(o[2], h), o[3] or mobile
        else:
            seen[key] = [key, w, h, mobile]
            out.append(seen[key])
    return [tuple(o) for o in out]


def scan_tree(modules_dir):
    """-> {'module/file:window': (w, h, has_mobile)}"""
    res = {}
    for dp, dn, fn in os.walk(modules_dir):
        dn.sort()
        for f in sorted(fn):
            if not f.endswith('.otui'):
                continue
            path = os.path.join(dp, f)
            rel = os.path.relpath(path, modules_dir).replace(os.sep, '/')
            with open(path, encoding='utf-8', errors='replace') as fh:
                text = fh.read()
            for key, w, h, mob in scan_text(text):
                res['%s:%s' % (rel, key)] = (w, h, mob)
    return res


def over(w, h):
    return h > MAX_H or w > MAX_W


def offenders(found):
    """Windows over the limit with no $mobile rule: {key: (w, h)}"""
    return {k: (w, h) for k, (w, h, mob) in found.items() if over(w, h) and not mob}


def read_baseline(path):
    base = {}
    if not os.path.exists(path):
        return base
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            m = re.match(r'^(.+) (\d+)x(\d+)$', line)
            if m:
                base[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return base


def format_baseline(bad):
    lines = ['# O313: windows over %dx%d logical pixels with no $mobile rule. The list may only shrink.' % (MAX_W, MAX_H),
             '# Regenerate with: python3 -I client/tools/check_mobile_layout.py --write-baseline']
    lines += ['%s %dx%d' % (k, w, h) for k, (w, h) in sorted(bad.items())]
    return '\n'.join(lines) + '\n'


def compare(bad, base):
    """-> (new offenders, grown, removable entries)"""
    new = sorted(k for k in bad if k not in base)
    grown = sorted(k for k in bad if k in base and (bad[k][0] > base[k][0] or bad[k][1] > base[k][1]))
    removable = sorted(k for k in base if k not in bad)
    return new, grown, removable


def main(argv):
    found = scan_tree(MODULES)
    bad = offenders(found)
    if '--write-baseline' in argv:
        with open(BASELINE, 'w', encoding='utf-8', newline='\n') as fh:
            fh.write(format_baseline(bad))
        print('baseline written: %d windows' % len(bad))
        return 0
    base = read_baseline(BASELINE)
    new, grown, removable = compare(bad, base)
    for k in new:
        print('FAIL %s %dx%d is over %dx%d and has no $mobile rule' % (k, bad[k][0], bad[k][1], MAX_W, MAX_H))
    for k in grown:
        print('FAIL %s grew to %dx%d (baseline %dx%d)' % (k, bad[k][0], bad[k][1], base[k][0], base[k][1]))
    for k in removable:
        print('FAIL %s now fits or has a $mobile rule: remove it from the baseline (--write-baseline)' % k)
    if new or grown or removable:
        return 1
    print('mobile layout ok: %d windows scanned, %d in the baseline' % (len(found), len(base)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
