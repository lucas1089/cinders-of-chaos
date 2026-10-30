#!/usr/bin/env python3
"""Tests of check_mobile_layout.py on synthetic .otui text.

Usage: python3 -I client/tools/check_mobile_layout_test.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_mobile_layout as M  # noqa: E402

n = 0


def eq(a, b, msg):
    global n
    n += 1
    if a != b:
        raise AssertionError('%s: %r ~= %r' % (msg, a, b))


def scan(text):
    return M.scan_text(text)


eq(scan('ChaosMainWindow\n  id: aWindow\n  size: 400 300\n'), [('ChaosMainWindow#aWindow', 400, 300, False)], 'fixed size')
eq(scan('ChaosMainWindow\n  id: aWindow\n  width: 700\n  height: 600\n'), [('ChaosMainWindow#aWindow', 700, 600, False)],
   'width and height')
eq(scan('ChaosMainWindow\n  anchors.fill: parent\n  size: 2000 2000\n'), [], 'fill is skipped')
eq(scan('ChaosMainWindow\n  id: x\n'), [], 'no size is skipped')
eq(scan('Panel\n  size: 2000 2000\n'), [], 'not a window')
eq(scan('ChaosMainWindow\n  id: a\n  size: 400 700\n  $mobile:\n    size: 400 500\n')[0][3], True, '$mobile rule')
eq(scan('ChaosMainWindow\n  id: a\n  size: 400 700\n  Panel\n    $!mobile:\n      size: 1 1\n')[0][3], True, 'nested $!mobile')
eq(scan('ChaosMainWindow\n  id: a\n  size: 400 300\n  Panel\n    size: 2000 2000\n'), [('ChaosMainWindow#a', 400, 300, False)],
   'child size is not the window size')
eq(scan('ChaosMainWindow\n  // size: 1 1\n  size: 5 5\n'), [('ChaosMainWindow', 5, 5, False)], 'comment line')
# a definition and an instance of the same name: one entry, the instance inherits the size
eq(scan('FooWindow < ChaosMainWindow\n  size: 800 600\n\nFooWindow\n  id: foo\n'),
   [('FooWindow', 800, 600, False)], 'definition then bare instance')
eq(scan('FooWindow < ChaosMainWindow\n  size: 800 600\n  $mobile:\n    size: 800 500\n\nFooWindow\n  id: foo\n')[0][3], True,
   'inherited mobile rule')
eq(scan('Big < ChaosMainWindow\n  size: 800 600\n'), [('Big', 800, 600, False)], 'base ends in Window')

found = {'a:W1': (900, 540, False), 'a:W2': (960, 541, False), 'a:W3': (961, 100, False), 'a:W4': (2000, 2000, True)}
bad = M.offenders(found)
eq(sorted(bad), ['a:W2', 'a:W3'], 'limits: 960 and 540 fit, over fails, $mobile passes')

base = {'a:W2': (960, 600), 'a:Old': (990, 700)}
new, grown, removable = M.compare(bad, base)
eq(new, ['a:W3'], 'new offender')
eq(grown, [], 'not grown')
eq(removable, ['a:Old'], 'removable entry')
bad2 = {'a:W2': (960, 700)}
eq(M.compare(bad2, base)[1], ['a:W2'], 'grown window')

txt = M.format_baseline({'b:X': (1, 2), 'a:Y': (3, 4)})
eq([ln for ln in txt.split('\n') if ln and not ln.startswith('#')], ['a:Y 3x4', 'b:X 1x2'], 'baseline format sorted')

# the committed baseline matches the real tree
real = M.offenders(M.scan_tree(M.MODULES))
eq(M.compare(real, M.read_baseline(M.BASELINE)), ([], [], []), 'real tree against the committed baseline')

print('ok %d checks' % n)
