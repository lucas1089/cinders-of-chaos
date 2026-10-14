#!/usr/bin/env python3
"""python3 -I tools/ci/check_layouts_test.py : check_layouts.py on synthetic .otui text (an anchor cycle across axes
like the Auto Seller window's item row of 2026-10-14, the fixed row, a chain, fit-children) and on the committed
game_pouches/autoseller.otui as it was before the fix (from git, when git is there)."""
import os
import pathlib
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import check_layouts as C  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    if not ok:
        failed += 1
        print('FAIL:', what)


def errors_of(text):
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / 'x.otui'
        p.write_text(text, encoding='utf-8')
        errs = []
        C.walk(p, C.parse(p), errs)
        return errs


CYCLE = """Win < MainWindow
  TextEdit
    id: itemEdit
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: addButton.left

  Button
    id: addButton
    anchors.verticalCenter: itemEdit.verticalCenter
    anchors.right: parent.right
"""
FIXED = CYCLE.replace('anchors.verticalCenter: itemEdit.verticalCenter', 'anchors.top: parent.top')
CHAIN = """Win < MainWindow
  Label
    id: a
    anchors.top: parent.top
  Label
    id: b
    anchors.top: a.bottom
  Label
    id: c
    anchors.top: b.bottom
    anchors.left: a.left
"""
NESTED = """Win < MainWindow
  Panel
    id: p
    anchors.fill: parent
    Label
      id: x
      anchors.left: y.right
    Label
      id: y
      anchors.fill: x
"""

e = errors_of(CYCLE)
check(len(e) == 1 and 'anchor cycle' in e[0] and 'itemEdit' in e[0] and 'addButton' in e[0], 'cycle across axes: %r' % e)
check(errors_of(FIXED) == [], 'the fixed row passes')
check(errors_of(CHAIN) == [], 'a chain is no cycle')
e = errors_of(NESTED)
check(len(e) == 1 and ('x -> y -> x' in e[0] or 'y -> x -> y' in e[0]), 'a cycle inside a child panel: %r' % e)
check(errors_of("""W < UIWidget
  layout:
    type: verticalBox
    fit-children: true
  anchors.fill: parent
""") != [], 'fit-children with anchors.fill is still reported')

root = HERE.parents[1]
try:
    old = subprocess.run(['git', '-C', str(root), 'show', 'd99fc12f:client/overlay/modules/game_pouches/autoseller.otui'],
                         capture_output=True, text=True, timeout=30)
except (OSError, subprocess.SubprocessError):
    old = None
if old is not None and old.returncode == 0 and old.stdout:
    e = errors_of(old.stdout)
    check(any('itemEdit' in x and 'addButton' in x for x in e), 'the 2026-10-14 Auto Seller window is caught: %r' % e)
check(errors_of((root / 'client/overlay/modules/game_pouches/autoseller.otui').read_text(encoding='utf-8')) == [],
      'the Auto Seller window now passes')

print('check_layouts_test: %s' % ('OK' if not failed else '%d failures' % failed))
sys.exit(1 if failed else 0)
