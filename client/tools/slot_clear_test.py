#!/usr/bin/env python3
"""Model test of base patch 0115 (a slot that loses its item keeps the marks of that item).

The engine is not built in CI, so this runs the Lua that decides what a container slot shows, under LuaJIT and Lua 5.3:
  * chaosSetSlotItem, taken from the patch (the added lines of modules/game_containers/containers.lua);
  * the real overlay game_itemrarity (updateRarityFrame on onItemChange: the irFrame child, widget.irColor) and the
    greyscale decision of game_shaderfx (shaderfxlogic.lua: a locked item is drawn grey, the grey is taken back);
  * a mock UIItem whose setItem is the stock engine (onItemChange only when the slot gets an item) or the engine of
    0115 (also when it loses one, and UIItem.notifiesItemRemoval);
  * an Auto Seller sale on a 40-slot Loot Bag (items removed one by one: each removal redraws the window, as
    game_containers does) and on the last page of a paged window.
Checks: with the stock setItem every emptied slot keeps its frame (the bug); with chaosSetSlotItem no slot without an
item has a frame, a grey or a rarity colour, on both engines, and each emptied slot hears of it exactly once.
Run: python3 -I client/tools/slot_clear_test.py
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATCH = os.path.join(ROOT, 'client', 'base-patches', '0115-empty-slot-clears-decorations.patch')
MODULES = os.path.join(ROOT, 'client', 'overlay', 'modules')


def file_hunks(patch_text, path):
    """the hunk lines of one file of a unified diff"""
    out, inside = [], False
    for line in patch_text.splitlines():
        if line.startswith('--- '):
            inside = False
        elif line.startswith('+++ '):
            inside = line[4:].strip() == 'b/' + path
        elif inside:
            out.append(line)
    return out


def added_function(lines, name):
    """the text of a function the patch adds (its '+' lines from 'function name(' to the first 'end' at column 0)"""
    body, on = [], False
    for line in lines:
        if not line.startswith('+'):
            if on:
                break
            continue
        text = line[1:]
        if text.startswith('function ' + name + '('):
            on = True
        if on:
            body.append(text)
            if text == 'end':
                return '\n'.join(body) + '\n'
    raise AssertionError('patch 0115 adds no function ' + name)


HARNESS = r'''
local subjectFile, modulesDir = ...
local fails, checks = 0, 0
local function ok(cond, what)
  checks = checks + 1
  if not cond then print('FAIL ' .. what); fails = fails + 1 end
end

-- corelib: connect / signalcall (a handler returning true stops the chain, as in the client)
function signalcall(param, ...)
  if type(param) == 'function' then return param(...) end
  if type(param) == 'table' then
    for _, f in ipairs(param) do if f(...) then return true end end
  end
end
function connect(object, signals)
  for signal, slot in pairs(signals) do
    local cur = rawget(object, signal)
    if cur == nil then object[signal] = { slot }
    elseif type(cur) == 'function' then object[signal] = { cur, slot }
    else table.insert(cur, slot) end
  end
end
function disconnect() end

-- the engine of the test: plain widgets; UIItem.setItem is the stock one or the one of 0115
local engineNotifies = false
local Widget = {}
Widget.__index = Widget
local function newWidget(id, parent)
  local w = setmetatable({ id = id, children = {}, visible = true }, Widget)
  if parent then parent.children[#parent.children + 1] = w; w.parent = parent end
  return w
end
function Widget:getChildById(id) for _, c in ipairs(self.children) do if c.id == id then return c end end end
function Widget:getChildren() return self.children end
function Widget:setId(id) self.id = id end
function Widget:getId() return self.id end
function Widget:getParent() return self.parent end
function Widget:isDestroyed() return false end
function Widget:setPhantom() end
function Widget:setFocusable() end
function Widget:fill() end
function Widget:setImageSource(s) self.image = s end
function Widget:setImageColor(c) self.imageColor = c end
function Widget:show() self.visible = true end
function Widget:hide() self.visible = false end
function Widget:isVisible() return self.visible end

UIItem = {}
UIItem.__index = function(t, k)
  local v = rawget(UIItem, k)
  if v ~= nil then return v end
  return Widget[k]
end
local function fire(w)
  signalcall(w.onItemChange, w)
end
function UIItem.getItem(w) return w.item end
function UIItem.setItem(w, item)
  local removed = w.item ~= nil and item == nil
  w.item = item
  if item then fire(w) elseif removed and engineNotifies then fire(w) end
end
function UIItem.setItemShader(w, s)
  w.shader = s
  if w.item then fire(w) end
end
local function newItemWidget(id, parent)
  local w = setmetatable({ id = id, children = {}, visible = true }, UIItem)
  parent.children[#parent.children + 1] = w; w.parent = parent
  return w
end

g_ui = { createWidget = function(_, parent) return newWidget(nil, parent) end }
local containers = {}
g_game = { getFeature = function(f) return f == 126 end, getContainers = function() return containers end,
  isOnline = function() return false end }
LocalPlayer = {}
dofile(modulesDir .. '/game_shaderfx/shaderfxlogic.lua')
local SL = ShaderFxLogic
modules = { game_shaderfx = {
  onSlotItem = function(widget, item) SL.applyItemGrey(widget, SL.isLocked(item)) end,
  onRarityFrame = function() end,
} }
dofile(modulesDir .. '/game_itemrarity/itemrarity.lua')
init()
-- what every module hooked to onItemChange hears, whoever signals it (the engine or chaosSetSlotItem)
local changes = {}
connect(UIItem, { onItemChange = function(w) changes[w] = (changes[w] or 0) + 1 end })
dofile(subjectFile)

local function item(rarity, locked)
  local attrs = { [1] = rarity, [3] = locked and 1 or 0 }
  return { getCustomAttribute = function(_, k) return attrs[k] or 0 end, getTooltip = function() return '' end }
end

-- a window: `capacity` slots showing items[first + 1 ..]; put(w, item) is how the window fills a slot
local function window(capacity)
  local panel = newWidget('contentsPanel')
  for slot = 0, capacity - 1 do newItemWidget('item' .. slot, panel) end
  return panel
end
local function refresh(panel, capacity, items, first, put)
  for slot = 0, capacity - 1 do
    put(panel:getChildById('item' .. slot), items[first + slot + 1])
  end
end
local function marks(w)
  local frame = w:getChildById('irFrame')
  return (frame and frame:isVisible()) or w.irColor ~= nil or w.sfxGrey == true
end

local stockPut = function(w, it) w:setItem(it) end
local patchedPut = function(w, it) chaosSetSlotItem(w, it) end

-- an Auto Seller sale: 40 items (every third locked), 35 sold one by one; each removal redraws the window
local function sale(put, notifies, capacity, first, total, keep)
  engineNotifies = notifies
  UIItem.notifiesItemRemoval = notifies and function() return true end or nil
  local panel = window(capacity)
  local items = {}
  for i = 1, total do items[i] = item((i % 5) + 1, i % 3 == 0) end
  refresh(panel, capacity, items, first, put)
  while #items > keep do
    table.remove(items, 1)
    refresh(panel, capacity, items, first, put)
  end
  local stale, framed, heard = 0, 0, true
  for slot = 0, capacity - 1 do
    local w = panel:getChildById('item' .. slot)
    local it = items[first + slot + 1]
    if not it and marks(w) then stale = stale + 1 end
    if it and not (w.irColor == getItemFrameColor(it) and (w.sfxGrey == true) == SL.isLocked(it)) then framed = framed + 1 end
  end
  return stale, framed, panel
end

-- the bug: the stock engine and a plain setItem leave the frames of the sold items on the empty slots
local stale = sale(stockPut, false, 40, 0, 40, 5)
ok(stale == 35, 'stock engine, plain setItem: the 35 emptied slots keep their marks (' .. stale .. ')')

for _, notifies in ipairs({ false, true }) do
  local name = notifies and 'engine 0115' or 'stock engine'
  local s, wrong = sale(patchedPut, notifies, 40, 0, 40, 5)
  ok(s == 0, name .. ': no empty slot keeps a mark (' .. s .. ')')
  ok(wrong == 0, name .. ': every slot with an item shows that item (' .. wrong .. ')')
  -- the last page of a paged window (capacity 8, page 2 of a 16-item bag) loses 14 items
  s, wrong = sale(patchedPut, notifies, 8, 8, 16, 10)
  ok(s == 0, name .. ', paged window: no empty slot keeps a mark (' .. s .. ')')
  ok(wrong == 0, name .. ', paged window: the slots with items are right (' .. wrong .. ')')
  -- one signal per slot change: a slot emptied once hears of it once (no second call on top of the engine's)
  engineNotifies = notifies
  UIItem.notifiesItemRemoval = notifies and function() return true end or nil
  changes = {}
  local panel = window(1)
  local w = panel:getChildById('item0')
  chaosSetSlotItem(w, item(4, false))
  chaosSetSlotItem(w, nil)
  chaosSetSlotItem(w, nil)
  ok(changes[w] == 2, name .. ': one change for the item, one for its removal, none for an empty slot set empty ('
    .. tostring(changes[w]) .. ')')
  ok(not marks(w), name .. ': the emptied slot is plain')
end
chaosSetSlotItem(nil, nil) -- a missing widget is ignored

if fails > 0 then print(fails .. ' failure(s)') os.exit(1) end
print('slot_clear_test (' .. _VERSION .. (jit and (' ' .. jit.version) or '') .. '): ' .. checks .. ' checks OK')
'''


def main():
    with open(PATCH, encoding='utf-8') as f:
        patch = f.read()
    lua = file_hunks(patch, 'modules/game_containers/containers.lua')
    # every slot of the container window is filled through the helper: no plain setItem is left in what 0115 touches
    left = [l for l in lua if not l.startswith('-') and 'itemWidget:setItem(' in l and 'function' not in l]
    assert left == ['+  itemWidget:setItem(item)'], left
    subject = added_function(lua, 'chaosSetSlotItem')
    cpp = '\n'.join(l[1:] for l in file_hunks(patch, 'src/client/uiitem.cpp') if not l.startswith('-'))
    assert re.search(r'const bool removed = m_item && !item;', cpp), 'setItem remembers that the slot had an item'
    assert re.search(r'else if \(removed\) \{\s*m_lastDecayUpdate = 0;\s*callLuaField\("onItemChange"\);', cpp), \
        'setItem(nil) on a slot with an item calls onItemChange'
    binding = '\n'.join(file_hunks(patch, 'src/client/luafunctions_client.cpp'))
    assert '"notifiesItemRemoval"' in binding, 'the engine tells Lua that it signals removals'

    interpreters = [i for i in ('luajit', 'lua5.3') if shutil.which(i)]
    if not interpreters:
        print('slot_clear_test: no luajit or lua5.3 found')
        return 1
    tmp = tempfile.mkdtemp(prefix='slot_clear_')
    try:
        subject_path = os.path.join(tmp, 'subject.lua')
        harness_path = os.path.join(tmp, 'harness.lua')
        with open(subject_path, 'w', encoding='utf-8') as f:
            f.write(subject)
        with open(harness_path, 'w', encoding='utf-8') as f:
            f.write(HARNESS)
        status = 0
        for interp in interpreters:
            r = subprocess.run([interp, harness_path, subject_path, MODULES], capture_output=True, text=True)
            sys.stdout.write(r.stdout)
            sys.stderr.write(r.stderr)
            if r.returncode != 0:
                status = 1
        return status
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
