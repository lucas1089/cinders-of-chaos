#!/usr/bin/env python3
"""Tests of tools/ci/check_window_close.py: window blocks, close controls, the allow list, and the real repository."""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('check_window_close', os.path.join(HERE, 'check_window_close.py'))
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)

THEME = """ChaosWindow < UIWindow
  size: 100 100
ChaosMainWindow < ChaosWindow
  anchors.centerIn: parent
ChaosCloseX < UIButton
  size: 20 20
ChaosButton < UIButton
  size: 10 10
ChaosName
  id: ignored
"""
GOOD_X = """ChaosMainWindow
  id: withX
  ChaosCloseX
    id: closeX
    @onClick: modules.m.hide()
"""
GOOD_BTN = """ChaosMainWindow
  id: withButton
  ChaosButton
    id: closeButton
    !text: tr('Close')
"""
GOOD_CANCEL = """MyDialog < ChaosMainWindow
  ChaosButton
    id: buttonCancel
    !text: tr('Cancel')
"""
BAD = """ChaosMainWindow
  id: noClose
  ChaosButton
    id: okButton
    !text: tr('Ok')
"""
BAD_STYLE = """ForgeLike < ChaosMainWindow
  size: 900 536
  ChaosButton
    id: goButton
"""
NOT_WINDOW = """ChaosPanel < UIWidget
  size: 4 4
VirtualWin < ChaosMainWindow
  virtual: true
"""
TOPBAR = """local CATEGORIES = {
  entry('X', 'a', { modules = { 'game_one', 'game_two' }, fns = { 'toggle' } }),
}
local CATEGORY_ALIAS = {}
"""


def windows(files):
    return C.windows_of(files)


def main():
    fails = 0

    def eq(a, b, what):
        nonlocal fails
        if a != b:
            print('FAIL %s: %r != %r' % (what, a, b))
            fails += 1

    def closes(text):
        ws = windows({'t': {'theme.otui': THEME}, 'm': {'m.otui': text}})
        return [(w[2], w[4]) for w in ws if w[0] == 'm']

    eq(closes(GOOD_X), [('withX', True)], 'the ChaosCloseX style counts')
    eq(closes(GOOD_BTN), [('withButton', True)], 'a Close button counts')
    eq(closes(GOOD_CANCEL), [('MyDialog', True)], 'a Cancel button closes a dialog')
    eq(closes(BAD), [('noClose', False)], 'a window with only an Ok button has no close control')
    eq(closes(BAD_STYLE), [('ForgeLike', False)], 'a window style with no close control')
    eq(closes(NOT_WINDOW), [], 'a panel and a virtual style are no windows')
    eq([w for w in windows({'t': {'theme.otui': THEME}}) if w[0] == 't'] != [], True, 'the theme styles are windows too, outside the hub')

    ws = [w for w in windows({'t': {'theme.otui': THEME}, 'm': {'m.otui': BAD + BAD_STYLE + GOOD_X}}) if w[0] == 'm']
    found = C.problems(ws, allowed={})
    eq(len(found), 2, 'two windows without a close control fail')
    eq(all('noClose' in p or 'ForgeLike' in p for p in found), True, 'the problems name the windows')
    eq(C.problems(ws, allowed={'noClose': 'a reason', 'ForgeLike': 'a reason'}), [], 'the allow list passes them')
    eq(len(C.problems(ws, allowed={'noClose': 'x', 'ForgeLike': 'x', 'gone': 'x'})), 1, 'an allow entry that is no window fails')

    mods = C.hub_modules(TOPBAR, {'game_three': 'ChaosTopBar.addEntry(api.addEntry, "x")', 'game_four': 'nothing'})
    eq(sorted(mods), ['game_one', 'game_three', 'game_two'], 'modules of CATEGORIES and of api.addEntry callers')

    # the real repository: the forge has its X, every hub window closes
    topbar, sources, files = C.load()
    mods = C.hub_modules(topbar, sources)
    real = [w for w in C.windows_of(dict(files)) if w[0] in mods]
    forge = [w for w in real if w[2] == 'forgeWindow']
    eq(len(forge), 1, 'the forge window is a hub window')
    eq(forge[0][4] if forge else None, True, 'the forge window has a close control')
    eq(len(real) >= 80, True, 'the hub opens many windows (%d)' % len(real))
    eq(C.problems(real), [], 'every hub window has a close control')

    print('check_window_close_test: %s' % ('OK' if not fails else '%d failure(s)' % fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
