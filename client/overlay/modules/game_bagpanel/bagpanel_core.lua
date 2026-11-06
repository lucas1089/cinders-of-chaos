-- Pure rules of game_bagpanel (O420; client/MANIFEST.md): no client API here, bagpanel_core_test.lua tests them.
-- The panel shows the equipment and one page of the main backpack at a time: page 1 is the backpack, every bag in it
-- is another page. A container is told apart by the key game_chaoslayout learns for it ("3_2854" = the container in
-- inventory slot 3, "3_2854/1_1987" = the bag at index 1 of that one). Positions are the protocol's: an inventory slot
-- is (65535, slot, 0), a slot of an open container is (65535, 64 + container id, index).
BagPanelCore = {}
local C = BagPanelCore

C.BACK_SLOT = 3
C.CELL = 34
C.SPACING = 2
C.MAX_STEPS_PER_ITEM = 2   -- the sort stops after this many moves per item (a safety net, a sort needs at most one)
C.STUCK = 3                -- moves that changed nothing in a row: the sort gives up
C.STEP_MS = 220            -- between two sort moves (the answer of the server comes in between)
C.WHOLE = 255              -- the "whole container" index: the server adds the item to the front of the container
C.OPTION = 'chaosBagPanel'

-- the equipment grid, rows of 3 (inventory slot ids, 0 = no slot): the client's slot numbers
C.EQUIP_ROWS = { { 2, 1, 10 }, { 6, 4, 5 }, { 9, 7, 3 }, { 0, 8, 0 } }
-- English names (tr() keys at run time)
C.SLOT_NAMES = { [1] = 'Head', [2] = 'Necklace', [3] = 'Backpack', [4] = 'Armor', [5] = 'Right hand',
  [6] = 'Left hand', [7] = 'Legs', [8] = 'Feet', [9] = 'Ring', [10] = 'Ammunition' }

-- coins by client id, in gold
C.COINS = { [3031] = 1, [3035] = 100, [3043] = 10000 }

-- tabs: Equip is this panel; the others open a window that already exists. The first target whose module is loaded
-- wins; a tab with no target is not shown.
C.TABS = {
  { id = 'equip', text = 'Equip' },
  { id = 'quest', text = 'Quest', targets = { { 'game_questlog', 'toggle' }, { 'game_goals', 'toggle' } } },
  { id = 'status', text = 'Status', targets = { { 'game_skills', 'toggle' } } },
  { id = 'active', text = 'Active', targets = { { 'game_buffbar', 'toggle' } } },
  { id = 'shop', text = 'Shop', targets = { { 'game_shop', 'toggle' } } },
}

local function int(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
  return math.floor(v)
end

-- ---------------------------------------------------------------- the option
-- on unless it was turned off (a new player has none saved)
function C.isOn(v)
  if v == nil then return true end
  if v == false or v == 0 or v == 'false' or v == '0' then return false end
  return true
end

-- ---------------------------------------------------------------- tabs
-- has(module, fn) -> boolean. The tabs to show, each with the target found: { id, text, module, fn }
function C.tabs(has)
  local out = {}
  for _, t in ipairs(C.TABS) do
    if not t.targets then
      out[#out + 1] = { id = t.id, text = t.text }
    else
      for _, target in ipairs(t.targets) do
        if has(target[1], target[2]) then
          out[#out + 1] = { id = t.id, text = t.text, module = target[1], fn = target[2] }
          break
        end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- positions
function C.slotPos(slot)
  return { x = 65535, y = int(slot) or 0, z = 0 }
end

function C.containerPos(cid, index)
  return { x = 65535, y = 64 + (int(cid) or 0), z = int(index) or 0 }
end

-- drop target "the container itself": the server adds the item to the front
function C.wholePos(cid)
  return C.containerPos(cid, C.WHOLE)
end

-- an item position as a place: { kind = 'slot', slot } | { kind = 'container', id, index } | nil (the map)
function C.place(pos)
  if type(pos) ~= 'table' or int(pos.x) ~= 65535 then return nil end
  local y = int(pos.y)
  if not y then return nil end
  if y >= 64 then return { kind = 'container', id = y - 64, index = int(pos.z) or 0 } end
  return { kind = 'slot', slot = y }
end

-- ---------------------------------------------------------------- which container is which
-- key -> 'main' (the backpack slot's container), 'bag', index (a container item of the main backpack, index 0 = first)
-- or nil (any other container: a corpse, the depot, a bag in a bag, a quiver: it keeps its classic window)
function C.classify(key)
  if type(key) ~= 'string' then return nil end
  if key:match('^' .. C.BACK_SLOT .. '_%d+$') then return 'main' end
  local idx = key:match('^' .. C.BACK_SLOT .. '_%d+/(%d+)_%d+$')
  if idx then return 'bag', tonumber(idx) end
  return nil
end

-- true when a container with this key is shown by the panel (so its own window stays hidden)
function C.inPanel(key)
  return C.classify(key) ~= nil
end

-- ---------------------------------------------------------------- pages
-- items: the main backpack's slots in order, { { id, container } or false for a gap }. The bag slots:
-- { { slot = index, id = item id } }
function C.bagSlots(items)
  local out = {}
  for i = 1, #items do
    local it = items[i]
    if it and it.container then out[#out + 1] = { slot = i - 1, id = it.id } end
  end
  return out
end

-- the pages: the main backpack first, then one per bag
function C.pages(bags)
  local out = { { key = 'main', id = nil } }
  for _, b in ipairs(bags or {}) do
    out[#out + 1] = { key = 'bag' .. b.slot, slot = b.slot, id = b.id }
  end
  return out
end

-- the page key still valid after the bags changed, else 'main'
function C.validKey(pages, key)
  for _, p in ipairs(pages) do
    if p.key == key then return key end
  end
  return 'main'
end

-- a bag opened at index `old` moved when items came in front of it: the slot of the same kind of bag nearest to
-- where it was, or nil when no bag of that id is left
function C.rematch(old, id, bags)
  local best, bestDist
  for _, b in ipairs(bags or {}) do
    if b.id == id then
      local d = math.abs(b.slot - (int(old) or 0))
      if not bestDist or d < bestDist then best, bestDist = b.slot, d end
    end
  end
  return best
end

-- a bag remembered by its index follows the list: an item added at `at` pushes it one later, an item removed from
-- `at` pulls it one earlier (nil when the bag itself is the one removed)
function C.shiftAdd(slot, at)
  slot, at = int(slot), int(at)
  if not slot or not at then return slot end
  if at <= slot then return slot + 1 end
  return slot
end

function C.shiftRemove(slot, at)
  slot, at = int(slot), int(at)
  if not slot or not at then return slot end
  if at == slot then return nil end
  if at < slot then return slot - 1 end
  return slot
end

-- ---------------------------------------------------------------- grid
function C.columns(width, cell, spacing)
  cell, spacing = cell or C.CELL, spacing or C.SPACING
  width = tonumber(width) or 0
  local n = math.floor((width + spacing) / (cell + spacing))
  if n < 1 then return 5 end -- the width is not known yet
  return n
end

function C.gridHeight(count, cols, cell, spacing)
  cell, spacing = cell or C.CELL, spacing or C.SPACING
  count = math.max(int(count) or 0, 0)
  cols = math.max(int(cols) or 1, 1)
  local rows = math.ceil(count / cols)
  if rows == 0 then return 0 end
  return rows * (cell + spacing) - spacing
end

-- the cell of a slot in a grid of `cols` columns: column, row (0-based)
function C.cellOf(index, cols)
  cols = math.max(int(cols) or 1, 1)
  return index % cols, math.floor(index / cols)
end

-- ---------------------------------------------------------------- money
-- items: { { id, count } } of the open containers
function C.gold(items)
  local sum = 0
  for _, it in ipairs(items or {}) do
    local v = C.COINS[it.id]
    if v then sum = sum + v * (int(it.count) or 1) end
  end
  return sum
end

-- ---------------------------------------------------------------- sort
-- entries: the page's items in slot order, { { id, count, slot, stack } } with no gaps (a container is a list: the
-- server adds an item at the front). The order wanted: item id up, then the bigger stack first, equal items keep their
-- order. Stacks of one id that can still join (a stack under 100 and another of the same id) are not ordered by count:
-- the server joins them as they move, which would undo it; they keep their order.
C.STACK_MAX = 100

local function before(a, b)
  if a.id ~= b.id then return a.id < b.id end
  if not a.loose and a.count ~= b.count then return a.count > b.count end
  return a.pos < b.pos
end

-- the slot of the next item to move to the front, nil when the page is in order. The items that stay are the longest
-- tail of the wanted order that already sits in that order; the rest go to the front one by one, last of them first,
-- so the page is sorted after at most (items - tail) moves, and the tail is never touched.
function C.nextMove(entries)
  local n = #entries
  if n < 2 then return nil end
  local list, groups, partial = {}, {}, {}
  for i, e in ipairs(entries) do
    local id, count = int(e.id) or 0, int(e.count) or 1
    list[i] = { id = id, count = count, pos = i, slot = e.slot }
    if e.stack then
      groups[id] = (groups[id] or 0) + 1
      if count < C.STACK_MAX then partial[id] = true end
    end
  end
  for _, e in ipairs(list) do
    e.loose = (groups[e.id] or 0) > 1 and partial[e.id] == true
  end
  local want = {}
  for i = 1, n do want[i] = list[i] end
  table.sort(want, before)
  local keep = 1
  for j = n - 1, 1, -1 do
    if want[j].pos < want[j + 1].pos then keep = keep + 1 else break end
  end
  if keep >= n then return nil end
  return want[n - keep].slot
end

local function signature(entries)
  local parts = {}
  for i, e in ipairs(entries) do parts[i] = tostring(e.id) .. 'x' .. tostring(e.count) end
  return table.concat(parts, ',')
end

function C.newSort(count)
  return { steps = 0, max = (int(count) or 0) * C.MAX_STEPS_PER_ITEM + 4, last = nil, stuck = 0 }
end

-- one step: ('move', slot) | ('done') | ('stuck', reason). Called again with the page as it is after the answer.
function C.sortStep(s, entries)
  local sig = signature(entries)
  if s.last ~= nil then
    if sig == s.last then s.stuck = s.stuck + 1 else s.stuck = 0 end
  end
  s.last = sig
  local slot = C.nextMove(entries)
  if slot == nil then return 'done' end
  if s.stuck >= C.STUCK then return 'stuck', 'nothing moved' end
  if s.steps >= s.max then return 'stuck', 'too many moves' end
  s.steps = s.steps + 1
  return 'move', slot
end
