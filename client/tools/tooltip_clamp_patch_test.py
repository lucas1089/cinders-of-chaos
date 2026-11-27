#!/usr/bin/env python3
"""Guard for client base patch 0216: a tooltip flipped left or up stays on the screen (client/BASE.md "0216"; V39,
seen in a client 2026-11-27: a passive tree mastery tooltip of about 640 px, hovered at the middle of a 1280 px screen,
flipped left of the mouse and lost its left part off the screen).

Checks on the patch text:
  * it is the only patch numbered 0216 and touches exactly modules/corelib/ui/tooltip.lua,
  * it only adds lines, in one hunk with three context lines on each side and consistent line counts,
  * x and y are clamped from 0 to the window size less the label size, before toolTipLabel:setPosition,
then runs the added clamp lines in LuaJIT (or Lua 5.3) after the base flip rule: a wide tooltip flipped left stays at
x >= 0, a tall one flipped up at y >= 0, a small tooltip keeps the base place, one wider than the screen starts at 0.
Run: python3 -I client/tools/tooltip_clamp_patch_test.py (standard library; skips the Lua part when no Lua is found)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PATCHES = os.path.join(HERE, '..', 'base-patches')
NAME = '0216-tooltip-on-screen.patch'
fails = 0


def check(cond, what):
    global fails
    if not cond:
        fails += 1
        print('FAIL ' + what)


files = sorted(f for f in os.listdir(PATCHES) if f.endswith('.patch'))
check([f for f in files if f.startswith('0216-')] == [NAME], 'one patch numbered 0216')
text = open(os.path.join(PATCHES, NAME), encoding='utf-8').read()
touched = re.findall(r'^\+\+\+ b/(\S+)', text, re.M)
check(touched == ['modules/corelib/ui/tooltip.lua'], 'files: %r' % touched)

removed = [l[1:] for l in text.splitlines() if l.startswith('-') and not l.startswith('---')]
added = [l[1:] for l in text.splitlines() if l.startswith('+') and not l.startswith('+++')]
check(removed == [], 'only additions')
clamp = [l for l in added if l.strip().startswith('pos.x =') or l.strip().startswith('pos.y =')]
check(len(clamp) == 2, 'two clamp lines: %r' % clamp)
check(any('math.max(0, math.min(pos.x, windowSize.width - labelSize.width))' in l for l in clamp), 'x clamp')
check(any('math.max(0, math.min(pos.y, windowSize.height - labelSize.height))' in l for l in clamp), 'y clamp')

hunks = re.split(r'^@@ .*@@.*$', text, flags=re.M)[1:]
check(len(hunks) == 1, 'one hunk')
for head, hunk in zip(re.findall(r'^@@ -\d+,(\d+) \+\d+,(\d+) @@', text, re.M), hunks):
    lines = [l for l in hunk.split('\n') if l[:1] in (' ', '+', '-') and not l.startswith('---') and not l.startswith('+++')]
    lead = 0
    while lead < len(lines) and lines[lead].startswith(' '):
        lead += 1
    trail = 0
    while trail < len(lines) and lines[-1 - trail].startswith(' '):
        trail += 1
    check(lead == trail == 3, 'symmetric hunk context (%d / %d)' % (lead, trail))
    check(any('toolTipLabel:setPosition(pos)' in l for l in lines[-trail:]), 'the clamp comes before setPosition')
    old = sum(1 for l in lines if l[:1] in (' ', '-'))
    new = sum(1 for l in lines if l[:1] in (' ', '+'))
    check((old, new) == (int(head[0]), int(head[1])), 'hunk line counts %r against %r' % ((old, new), head))

LUA = r'''
local fails = 0
local function eq(a, b, what) if a ~= b then fails = fails + 1; print('FAIL ' .. what .. ': ' .. tostring(a)) end end
-- the base flip rule of moveToolTip, then the patched clamp lines
local function place(mx, my, lw, lh, ww, wh)
  local pos = { x = mx + 1, y = my + 1 }
  local windowSize = { width = ww, height = wh }
  local labelSize = { width = lw, height = lh }
  if windowSize.width - (pos.x + labelSize.width) < 10 then pos.x = pos.x - labelSize.width - 3 else pos.x = pos.x + 10 end
  if windowSize.height - (pos.y + labelSize.height) < 10 then pos.y = pos.y - labelSize.height - 3 else pos.y = pos.y + 10 end
%s
  return pos.x, pos.y
end
local x, y = place(640, 172, 640, 200, 1280, 720)
eq(x, 0, 'the 640 px tree tooltip at the middle flips left and stays on the screen')
eq(y, 183, 'its y keeps the base place')
x, y = place(100, 100, 200, 50, 1280, 720)
eq(x, 111, 'a small tooltip keeps the base place (x)')
eq(y, 111, 'a small tooltip keeps the base place (y)')
x, y = place(1200, 700, 300, 710, 1280, 720)
eq(x, 898, 'near the right edge it flips left as before')
eq(y, 0, 'a tall tooltip flipped up stays on the screen')
x = place(10, 10, 1400, 50, 1280, 720)
eq(x, 0, 'wider than the screen: starts at 0')
os.exit(fails == 0 and 0 or 1)
'''

lua = shutil.which('luajit') or shutil.which('lua5.3')
if lua:
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 't.lua')
        with open(path, 'w') as fh:
            fh.write(LUA % '\n'.join(clamp))
        r = subprocess.run([lua, path], capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout + r.stderr)
        check(r.returncode == 0, 'the clamp in ' + os.path.basename(lua))
else:
    print('tooltip_clamp_patch_test: no luajit or lua5.3, the Lua part skipped')

if fails:
    print('tooltip_clamp_patch_test: %d failed' % fails)
    sys.exit(1)
print('tooltip_clamp_patch_test: OK')
