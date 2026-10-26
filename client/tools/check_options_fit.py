#!/usr/bin/env python3
"""Options window height: a tab whose stacked groups are taller than the window must scroll.

The Options window (base client mods/client_settings/settings.otui) gives a tab 442 px minus 6 px of padding. The
tabs of options/*.otui are plain Panels with FlatPanel groups of a fixed height stacked below one another, so a tab
that grows past that height draws its dark group backgrounds below the window, over the game (owner report
2026-10-26, Graphics tab; base patch 0156 puts the Graphics and Interface tabs in a ScrollablePanel).

The check adds up the height and margin-top of the direct FlatPanel children of each tab (the tab's own size
lines are ignored) and fails when the sum is over the room and the tab has no ScrollablePanel with a vertical scrollbar.

Usage: python3 -I client/tools/check_options_fit.py <assembled-client-dir>   (client/tools/assemble_client.sh output)
       python3 -I client/tools/check_options_fit.py --self-test
"""
import glob
import os
import re
import sys

ROOM = 442 - 6


def tab_height(text):
    """(stacked height of the direct FlatPanel children, True when a ScrollablePanel is used)"""
    lines = text.split('\n')
    total = 0
    for i, line in enumerate(lines):
        if line == '  FlatPanel':
            h, m = None, 0
            j = i + 1
            while j < len(lines) and (lines[j].startswith('    ') or not lines[j].strip()):
                s = re.match(r'    size: \d+ (\d+)\s*$', lines[j])
                if s and h is None:
                    h = int(s.group(1))
                s = re.match(r'    margin-top: (-?\d+)\s*$', lines[j])
                if s:
                    m = int(s.group(1))
                j += 1
            if h:
                total += h + m
    return total, bool(re.search(r'^  ScrollablePanel\s*$', text, re.M))


def check_text(name, text):
    """an error string, or None"""
    # a tab file may hold helper styles first; only the top-level `XWindow < Panel` block is a tab
    if not re.search(r'^\w+ < Panel\s*$', text, re.M) or 'anchors.fill: parent' not in text:
        return None
    total, scrolls = tab_height(text)
    if total > ROOM and not scrolls:
        return f'{name}: groups add up to {total} px, the window has {ROOM} px, and the tab does not scroll'
    return None


def check(root):
    errors = []
    files = sorted(glob.glob(os.path.join(root, 'mods', 'client_settings', 'options', '*.otui')))
    if not files:
        return ['no mods/client_settings/options/*.otui in ' + root]
    for f in files:
        err = check_text(os.path.basename(f), open(f, encoding='utf-8').read())
        if err:
            errors.append(err)
    return errors


def self_test():
    tall = 'XWindow < Panel\n  id: x\n  anchors.fill: parent\n' + ''.join(
        '  FlatPanel\n    size: 505 100\n    margin-top: 5\n\n' for _ in range(5))
    assert check_text('tall.otui', tall) is not None
    assert check_text('ok.otui', tall.replace('100', '50')) is None
    scrolled = tall.replace('  FlatPanel\n', '  ScrollablePanel\n    id: s\n    FlatPanel\n', 1)
    assert check_text('scrolled.otui', scrolled) is None
    print('self-test ok')


if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']:
        self_test()
        sys.exit(0)
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    errs = check(sys.argv[1])
    for e in errs:
        print('FAIL', e)
    print('options fit:', 'FAIL' if errs else 'ok')
    sys.exit(1 if errs else 0)
