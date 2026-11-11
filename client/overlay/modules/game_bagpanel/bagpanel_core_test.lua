-- luajit bagpanel_core_test.lua && lua5.3 bagpanel_core_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'bagpanel_core.lua')
local C = BagPanelCore
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(C.PURSE_SLOT, 11, 'the purse is inventory slot 11 (store delivery)')
eq(C.slotPos(C.PURSE_SLOT).y, 11, 'purse position')

-- equipment grid: the nine worn slots and the badge, once each
local seen, count = {}, 0
for _, row in ipairs(C.EQUIP_ROWS) do
  eq(#row, 3, 'row of 3')
  for _, s in ipairs(row) do
    if s ~= 0 then seen[s] = (seen[s] or 0) + 1; count = count + 1 end
  end
end
eq(count, #C.EQUIP_SLOTS, 'every slot in the grid')
eq(seen[10], nil, 'no ammunition slot')
for _, s in ipairs(C.EQUIP_SLOTS) do
  eq(seen[s], 1, 'slot ' .. s .. ' once')
  eq(type(C.SLOT_NAMES[s]), 'string', 'slot ' .. s .. ' has a name')
end

-- the places of the stock inventory window (O491): backpack top right, badge where the ammunition slot was
eq(C.EQUIP_ROWS[1][3], 3, 'backpack: row 1, column 3')
eq(C.EQUIP_ROWS[3][3], 13, 'badge: row 3, column 3 (where the ammunition slot was)')
eq(C.EQUIP_ROWS[3][1] .. ',' .. C.EQUIP_ROWS[3][2], '9,7', 'ring and legs stay')

-- tabs: a tab with no target is left out, the first target present wins
local has = { game_goals = true, game_shop = true, game_buffbar = true }
local tabs = C.tabs(function(m, f) return has[m] == true and f == 'toggle' end)
local ids = {}
for _, t in ipairs(tabs) do ids[#ids + 1] = t.id end
eq(table.concat(ids, ','), 'equip,quest,active,shop', 'no skills window: no Status tab')
eq(tabs[2].module, 'game_goals', 'quest falls back to the goals window')
has.game_questlog = true
eq(C.tabs(function(m) return has[m] == true end)[2].module, 'game_questlog', 'quest log first')
eq(#C.tabs(function() return false end), 1, 'nothing loaded: Equip only')

-- positions
local p = C.slotPos(4)
eq(p.x == 65535 and p.y == 4 and p.z == 0, true, 'inventory slot position')
p = C.containerPos(2, 7)
eq(p.x == 65535 and p.y == 66 and p.z == 7, true, 'container slot position')
eq(C.wholePos(0).z, 255, 'whole container index')
local pl = C.place({ x = 65535, y = 3, z = 0 })
eq(pl.kind == 'slot' and pl.slot == 3, true, 'place: slot')
pl = C.place({ x = 65535, y = 65, z = 9 })
eq(pl.kind == 'container' and pl.id == 1 and pl.index == 9, true, 'place: container')
eq(C.place({ x = 100, y = 100, z = 7 }), nil, 'place: map')
eq(C.place(nil), nil, 'place: nothing')

-- which container is which
local kind, idx = C.classify('3_2854')
eq(kind, 'main', 'main backpack')
kind, idx = C.classify('3_2854/4_1987')
eq(kind, 'bag', 'a bag in it')
eq(idx, 4, 'its index')
eq(C.classify('3_2854/4_1987/0_1991'), nil, 'a bag in a bag keeps its window')
eq(C.classify('5_2854'), nil, 'another slot')
eq(C.classify('1_2854/0_1'), nil, 'a bag of another container')
eq(C.classify(nil), nil, 'no key')
eq(C.inPanel('3_1'), true, 'main in panel')
eq(C.inPanel('10_1'), false, 'quiver not')

-- pages
local items = { { id = 2852, container = false }, { id = 1987, container = true }, false, { id = 1988, container = true } }
local bags = C.bagSlots(items)
eq(#bags, 2, 'two bags')
eq(bags[1].slot, 1, 'first bag slot')
eq(bags[2].slot, 3, 'second bag slot')
local pages = C.pages(bags)
eq(#pages, 3, 'main and two bags')
eq(pages[1].key, 'main', 'page 1 is the backpack')
eq(pages[3].key, 'bag3', 'page key by slot')
eq(C.validKey(pages, 'bag3'), 'bag3', 'valid key kept')
eq(C.validKey(pages, 'bag9'), 'main', 'gone bag: main')
eq(#C.pages(nil), 1, 'no bags')
-- items came in front: the same bag is one slot later
eq(C.rematch(1, 1987, { { slot = 2, id = 1987 }, { slot = 4, id = 1988 } }), 2, 'rematch nearest of the same id')
eq(C.rematch(1, 1987, { { slot = 0, id = 1987 }, { slot = 5, id = 1987 } }), 0, 'two of a kind: nearest')
eq(C.rematch(1, 1987, { { slot = 4, id = 1988 } }), nil, 'bag gone')

-- a remembered bag follows the list
eq(C.shiftAdd(2, 0), 3, 'item added in front: one later')
eq(C.shiftAdd(2, 2), 3, 'item added at its slot: one later')
eq(C.shiftAdd(2, 3), 2, 'item added behind: same')
eq(C.shiftRemove(2, 0), 1, 'item removed in front: one earlier')
eq(C.shiftRemove(2, 2), nil, 'the bag itself removed')
eq(C.shiftRemove(2, 5), 2, 'item removed behind: same')

-- grid
eq(C.columns(180, 34, 2), 5, '5 columns in 180 px')
eq(C.columns(0, 34, 2), 5, 'width unknown: 5')
eq(C.columns(72, 34, 2), 2, '2 columns')
eq(C.gridHeight(0, 5), 0, 'empty grid')
eq(C.gridHeight(5, 5), 34, 'one row')
eq(C.gridHeight(6, 5), 70, 'two rows')
eq(C.gridHeight(255, 5), 51 * 36 - 2, 'loot bag')
local col, row = C.cellOf(7, 5)
eq(col == 2 and row == 1, true, 'cell of slot 7')

-- money
eq(C.gold({ { id = 3031, count = 50 }, { id = 3035, count = 3 }, { id = 3043, count = 1 }, { id = 2852, count = 9 } }),
  50 + 300 + 10000, 'coins in gold')
eq(C.gold({}), 0, 'no coins')
eq(C.gold(nil), 0, 'no list')

-- sort: a fake container the way the server keeps it (a list, an item moved into the container goes to the front,
-- a stackable joins a stack of its own kind that has room)
local function fake(list)
  local self = { list = list, moves = 0 }
  function self.entries()
    local out = {}
    for i, e in ipairs(self.list) do out[i] = { id = e.id, count = e.count, slot = i - 1, stack = e.stack } end
    return out
  end
  function self.moveToFront(slot, merge)
    local item = table.remove(self.list, slot + 1)
    self.moves = self.moves + 1
    if merge and item.stack then
      for _, o in ipairs(self.list) do
        if o.id == item.id and o.count < 100 then
          local room = math.min(100 - o.count, item.count)
          o.count, item.count = o.count + room, item.count - room
          if item.count == 0 then return end
          break
        end
      end
    end
    table.insert(self.list, 1, item)
  end
  return self
end

local function sorted(list)
  local groups, partial = {}, {}
  for _, e in ipairs(list) do
    if e.stack then
      groups[e.id] = (groups[e.id] or 0) + 1
      if e.count < 100 then partial[e.id] = true end
    end
  end
  for i = 2, #list do
    local a, b = list[i - 1], list[i]
    if a.id > b.id then return false end
    local loose = (groups[a.id] or 0) > 1 and partial[a.id]
    if a.id == b.id and not loose and a.count < b.count then return false end
  end
  return true
end

local function run(box, merge)
  local s = C.newSort(#box.list)
  for _ = 1, 1000 do
    local action, slot = C.sortStep(s, box.entries())
    if action == 'done' then return 'done' end
    if action == 'stuck' then return 'stuck' end
    box.moveToFront(slot, merge)
  end
  return 'loop'
end

local box = fake({ { id = 3, count = 1 }, { id = 1, count = 1 }, { id = 2, count = 1 } })
eq(run(box, false), 'done', 'three items sorted')
eq(sorted(box.list), true, 'in order')
eq(box.moves, 2, 'two moves')

box = fake({ { id = 1, count = 1 }, { id = 2, count = 1 }, { id = 3, count = 1 } })
eq(run(box, false), 'done', 'sorted page')
eq(box.moves, 0, 'no move for a sorted page')

box = fake({ { id = 5, count = 1 }, { id = 1, count = 1 }, { id = 2, count = 1 }, { id = 3, count = 1 } })
eq(run(box, false), 'done', 'a new item in front of a sorted tail (a larger id goes behind the rest)')
eq(box.moves, 3, 'the three smaller ids go in front of it')
box = fake({ { id = 0, count = 1 }, { id = 1, count = 1 }, { id = 2, count = 1 }, { id = 3, count = 1 } })
eq(run(box, false), 'done', 'a new smallest item in front of a sorted page')
eq(box.moves, 0, 'no move')

box = fake({ { id = 7, count = 2 }, { id = 7, count = 9 }, { id = 7, count = 5 } })
eq(run(box, false), 'done', 'one id, counts')
eq(box.list[1].count == 9 and box.list[2].count == 5 and box.list[3].count == 2, true, 'bigger stack first')

eq(C.nextMove({}), nil, 'empty page')
eq(C.nextMove({ { id = 1, count = 1, slot = 0 } }), nil, 'one item')

-- fuzz: random pages end sorted within one move per item, with and without stacks merging
math.randomseed(420)
for round = 1, 300 do
  local n = math.random(0, 40)
  local list = {}
  for i = 1, n do
    local id = math.random(1, 8)
    list[i] = { id = id, count = math.random(1, 100), stack = id % 2 == 0 }
  end
  local merge = round % 2 == 0
  local b = fake(list)
  local res = run(b, merge)
  if res ~= 'done' then eq(res, 'done', 'fuzz ' .. round .. ' ended') end
  if not sorted(b.list) then eq(false, true, 'fuzz ' .. round .. ' sorted') end
  if not merge and b.moves > n then eq(b.moves, '<= ' .. n, 'fuzz ' .. round .. ' moves') end
end

-- the server does not answer: the sort gives up instead of looping
local s = C.newSort(3)
local still = { { id = 3, count = 1, slot = 0 }, { id = 1, count = 1, slot = 1 } }
local last
for _ = 1, 10 do
  last = C.sortStep(s, still)
  if last ~= 'move' then break end
end
eq(last, 'stuck', 'no answer: stuck')

-- fit: grows to the layout, never past the room the side panel has left (no window closed to make room)
eq(C.fitHeight(300, 400, nil), 400, 'fit: grows to need')
eq(C.fitHeight(300, 400, 500), 400, 'fit: room enough')
eq(C.fitHeight(300, 400, 350), 350, 'fit: capped by room')
eq(C.fitHeight(300, 400, 250), nil, 'fit: no room to grow, no change')
eq(C.fitHeight(400, 300, 500), nil, 'fit: tall enough')
eq(C.fitHeight(300, 400, -20), nil, 'fit: full panel')

if fails == 0 then print('bagpanel_core_test: ok') else os.exit(1) end
