#!/usr/bin/env python3
"""Test of tools/ci/check_topbar_widgets.py on synthetic files: the good case, then one case per failure, then the real files."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_topbar_widgets as C  # noqa: E402

n = 0


def check(cond, msg):
    global n
    n += 1
    if not cond:
        print('FAIL: ' + msg)
        sys.exit(1)


OTUI = """ChaosHubCard < UIWidget
  size: 182 68

  $mobile:
    height: 76

  UIWidget
    id: badge
    anchors.left: parent.left

  UILabel
    id: name
    anchors.top: badge.bottom

ChaosHubWindow < ChaosWindow
  size: 780 262

  $mobile:
    size: 780 290

  UIWidget
    id: footer

ChaosHubBadge < UIButton
  size: 28 28

  $mobile:
    size: 40 40
"""
LUA = """local w = g_ui.createWidget('ChaosHubCard', parent)
get(w, 'badge'):setText('x')
local n = get(w, 'name')
"""
THEME = "ChaosWindow < UIWindow\n  size: 1 1\n"


def run(lua=LUA, otui=OTUI, theme=THEME):
    return C.problems({'topbar_hub.lua': lua}, {'topbar_hub.otui': otui}, theme)


def has(found, word):
    return any(word in p for p in found)


check(run() == [], 'the synthetic files are clean: %s' % run())
check(has(run(lua=LUA + "get(w, 'nope')\n"), "'nope'"), 'an id the .otui lacks fails')
check(has(run(lua=LUA + "x:getChildById('ghost')\n"), "'ghost'"), 'getChildById is read too')
check(has(run(lua=LUA + "x:recursiveGetChildById('ghost2')\n"), "'ghost2'"), 'recursiveGetChildById is read too')
check(has(run(lua=LUA + "g_ui.createWidget('NoSuchStyle', p)\n"), "'NoSuchStyle'"), 'a style nobody declares fails')
check(run(lua=LUA + "g_ui.createWidget('ChaosWindow', p)\n") == [], 'a theme style is fine')
check(has(run(otui=OTUI.replace('badge.bottom', 'gone.bottom')), "'gone'"), 'an anchor to a missing id fails')
check(run(otui=OTUI.replace('badge.bottom', 'parent.bottom')) == [], 'parent anchors are fine')
check(has(run(otui=OTUI.replace("  $mobile:\n    height: 76\n", "")), 'ChaosHubCard has no $mobile'), 'a card without $mobile fails')
check(has(run(otui=OTUI.replace("  $mobile:\n    size: 780 290\n", "")), 'ChaosHubWindow has no $mobile'), 'a window without $mobile fails')
check(has(run(otui=OTUI.replace("  $mobile:\n    size: 40 40\n", "")), 'ChaosHubBadge has no $mobile'), 'a badge without $mobile fails')
check(C.declared_ids(OTUI) == {'badge', 'name', 'footer'}, 'ids read')
check(set(C.style_blocks(OTUI)) == {'ChaosHubCard', 'ChaosHubWindow', 'ChaosHubBadge'}, 'styles read')

check(C.main() == 0, 'the real files pass')
print('check_topbar_widgets_test: %d checks ok' % n)
