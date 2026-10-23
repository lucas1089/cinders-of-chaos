#!/usr/bin/env python3
"""Model test of base patch 0122 (a full container packet for an open window keeps its slot widgets).

The engine is not built in CI, so this runs the Lua the patch adds to onContainerOpen (its '+' lines of
modules/game_containers/containers.lua, taken from the patch file) against mock widgets, under LuaJIT and Lua 5.3:
a Loot Bag of 255 slots gets 6 full packets in a row (an area kill with auto loot). The stock code builds 6 x 255
widgets; the patch builds 255 once and then only sets the slot contents. A changed capacity or lock state rebuilds.
Run: python3 -I client/tools/slot_reuse_test.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATCH = os.path.join(ROOT, 'client', 'base-patches', '0122-container-reopen-keeps-slots.patch')


def added_block(text):
    """the new text of the hunk from 'local locked' to the 'chaosSetSlotItem(itemWidget, itemSlot)' line ('+' and context lines)"""
    out, on = [], False
    for line in text.splitlines():
        if line[:1] not in ('+', ' ') or line.startswith('+++'):
            continue
        body = line[1:]
        if body.strip().startswith('local locked ='):
            on = True
        if on:
            out.append(body)
            if 'chaosSetSlotItem(itemWidget, itemSlot)' in body:
                return '\n'.join(out)
    raise AssertionError('patch 0122 has no slot block')


STOCK = '''
  containerPanel:destroyChildren()
  for slot = 0, container:getCapacity() - 1 do
    local itemWidget = g_ui.createWidget('Item', containerPanel)
    itemWidget:setId('item' .. slot)
    local itemSlot = container:getItem(slot)
    itemWidget:setItem(itemSlot)
'''

HARNESS = r'''
local mode = ...
local created, sets, destroyed = 0, 0, 0
local function newWidget(panel)
  local w = {children = nil, item = nil}
  function w:setId(id) self.id = id; panel.byId[id] = self end
  function w:setItem(i) sets = sets + 1; self.item = i end
  function w:getItem() return self.item end
  return w
end
local function newPanel()
  local p = {list = {}, byId = {}}
  function p:destroyChildren() destroyed = destroyed + #self.list; self.list = {}; self.byId = {} end
  function p:getChildCount() return #self.list end
  function p:getChildById(id) return self.byId[id] end
  return p
end
g_ui = {createWidget = function(_, panel) created = created + 1; local w = newWidget(panel); panel.list[#panel.list + 1] = w; return w end}
function chaosSetSlotItem(w, i) w:setItem(i) end
local function newContainer(cap, unlocked)
  local c = {}
  function c:getCapacity() return cap end
  function c:isUnlocked() return unlocked end
  function c:getItem(s) return s < 40 and {slot = s} or nil end
  return c
end
local function packet(panel, previous, container)
  local containerPanel, previousContainer = panel, previous
  local f, err = load([[
    local containerPanel, previousContainer, container = ...
    ]] .. CODE .. [[
    end
  ]])
  assert(f, err)
  f(containerPanel, previousContainer, container)
end
local panel, prev = newPanel(), nil
for i = 1, 6 do
  local c = newContainer(255, true)
  packet(panel, prev, c)
  prev = c
end
local base = created
print('after6', created, destroyed, #panel.list)
-- another capacity: rebuilt
local c2 = newContainer(100, true)
packet(panel, prev, c2)
print('cap', created - base, #panel.list)
local before = created
packet(panel, c2, newContainer(100, false))
print('lock', created - before, #panel.list)
'''


def run(interp, code):
    lua = HARNESS.replace('CODE', '[==[' + code + ']==]', 1)
    # CODE is the block body; the loop it opens is closed by the harness ('end')
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'h.lua')
        with open(path, 'w') as f:
            f.write(lua)
        r = subprocess.run([interp, path], capture_output=True, text=True)
    if r.returncode != 0:
        raise AssertionError(interp + ': ' + r.stderr)
    return {l.split()[0]: l.split()[1:] for l in r.stdout.splitlines()}


def main():
    with open(PATCH) as f:
        block = added_block(f.read())
    fails = 0
    for interp in ('luajit', 'lua5.3'):
        if not shutil.which(interp):
            print('skip ' + interp)
            continue
        stock = run(interp, STOCK)
        new = run(interp, block)
        checks = [
            (stock['after6'][0] == str(6 * 255), 'stock builds 6 x 255 widgets: ' + str(stock['after6'])),
            (new['after6'][0] == '255' and new['after6'][1] == '0', 'patched builds 255 once, destroys none: ' + str(new['after6'])),
            (new['cap'][0] == '100', 'a new capacity rebuilds: ' + str(new['cap'])),
            (new['lock'][0] == '100', 'a changed lock state rebuilds: ' + str(new['lock'])),
        ]
        for ok, what in checks:
            if not ok:
                print('FAIL ' + interp + ' ' + what)
                fails += 1
        print(interp + ': stock ' + stock['after6'][0] + ' widgets, patched ' + new['after6'][0])
    if fails:
        sys.exit(1)
    print('slot_reuse_test ok')


main()
