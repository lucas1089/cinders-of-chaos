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

-- ---------------------------------------------------------------- the purse as a page (O492)
-- which container is which: the purse is the container in inventory slot 11, its bags are pages
kind, idx = C.classify('11_26052')
eq(kind, 'purse', 'the purse')
eq(idx, nil, 'the purse has no index')
kind, idx = C.classify('11_26052/2_26100')
eq(kind, 'pbag', 'a bag in the purse')
eq(idx, 2, 'its index')
eq(C.classify('11_26052/2_26100/0_5'), nil, 'a bag in a bag of the purse keeps its window')
eq(C.classify('11_26052/x_1'), nil, 'a broken key')
eq(C.classify('111_26052'), nil, 'not slot 11')
eq(C.classify('13_26052'), nil, 'not slot 11 either')
eq(C.inPanel('11_26052'), true, 'purse in panel')
eq(C.inPanel('11_26052/0_1'), true, 'purse bag in panel')
eq(C.family('purse'), 'purse', 'family of purse')
eq(C.family('pbag'), 'purse', 'family of a purse bag')
eq(C.family('bag'), 'main', 'family of a bag')
eq(C.family('main'), 'main', 'family of main')
eq(C.family('x'), nil, 'no family')

-- page keys
eq(C.bagKey('main', 3), 'bag3', 'bag key')
eq(C.bagKey('purse', 3), 'pbag3', 'purse bag key')
local k, n = C.parseKey('pbag12')
eq(k == 'pbag' and n == 12, true, 'parse a purse bag key')
k, n = C.parseKey('bag0')
eq(k == 'bag' and n == 0, true, 'parse a bag key')
eq(C.parseKey('purse'), 'purse', 'parse purse')
eq(C.parseKey('main'), 'main', 'parse main')
eq(C.parseKey('nope'), nil, 'parse nothing')
eq(C.parseKey(nil), nil, 'parse nil')

-- the page list: backpack, its bags, then the purse and its bags (only once the purse is open: bags = {})
local ppages = C.pages({ { slot = 1, id = 1987 } }, { bags = {} })
eq(#ppages, 3, 'main, one bag, the purse')
eq(ppages[3].key, 'purse', 'the purse page comes after the bags')
eq(ppages[2].fam, 'main', 'bag page family')
ppages = C.pages({ { slot = 1, id = 1987 } }, { bags = { { slot = 0, id = 26100 }, { slot = 2, id = 26101 } } })
eq(#ppages, 5, 'main, bag, purse, two purse bags')
eq(ppages[4].key, 'pbag0', 'first purse bag')
eq(ppages[5].key, 'pbag2', 'second purse bag')
eq(ppages[4].fam, 'purse', 'purse bag family')
eq(#C.pages({}, nil), 1, 'no purse: no purse page')
eq(#C.pages(nil, { bags = nil }), 2, 'a purse with unknown contents: just its page')
eq(#C.pages({ { slot = 1, id = 1987 } }), 2, 'one argument as before')
eq(C.validKey(ppages, 'pbag2'), 'pbag2', 'purse bag page kept')
eq(C.validKey(ppages, 'purse'), 'purse', 'purse page kept')
eq(C.validKey(ppages, 'pbag9'), 'purse', 'a gone purse bag falls back to the purse')
eq(C.validKey(ppages, 'bag9'), 'main', 'a gone bag falls back to the backpack')
eq(C.validKey(C.pages({}, nil), 'purse'), 'main', 'no purse page: the backpack')
eq(C.validKey(C.pages({}, nil), 'pbag1'), 'main', 'no purse page and a purse bag: the backpack')

-- the page follows the list of its own container only
eq(C.shiftSelected('bag2', 'main', 0, true), 'bag3', 'bag page follows an add in the backpack')
eq(C.shiftSelected('bag2', 'purse', 0, true), 'bag2', 'a purse change leaves a bag page')
eq(C.shiftSelected('pbag2', 'purse', 1, false), 'pbag1', 'purse bag page follows a remove in the purse')
eq(C.shiftSelected('pbag2', 'main', 1, false), 'pbag2', 'a backpack change leaves a purse bag page')
eq(C.shiftSelected('pbag2', 'purse', 2, false), 'purse', 'its purse bag removed: the purse page')
eq(C.shiftSelected('bag2', 'main', 2, false), 'main', 'its bag removed: the backpack')
eq(C.shiftSelected('purse', 'purse', 0, true), 'purse', 'the purse page stays')
eq(C.shiftSelected('main', 'main', 0, true), 'main', 'the backpack page stays')

-- selection on open: what the player opens is shown, the login restore leaves the page alone
eq(C.selectOnOpen('main', 'purse', nil, false), 'purse', 'the purse opened: its page')
eq(C.selectOnOpen('bag1', 'purse', nil, false), 'purse', 'the purse opened from a bag page')
eq(C.selectOnOpen('purse', 'pbag', 3, false), 'pbag3', 'a purse bag opened: its page')
eq(C.selectOnOpen('main', 'bag', 3, false), 'bag3', 'a bag opened: its page')
eq(C.selectOnOpen('purse', 'main', nil, false), 'purse', 'the backpack opening changes nothing')
eq(C.selectOnOpen('main', 'purse', nil, true), 'main', 'restore: the purse opens, the page stays')
eq(C.selectOnOpen('main', 'pbag', 3, true), 'main', 'restore: a purse bag opens, the page stays')
eq(C.selectOnOpen('main', 'bag', 3, true), 'main', 'restore: a bag opens, the page stays')
-- selection on close
eq(C.selectOnClose('pbag3', 'pbag', 3), 'purse', 'its purse bag closed: the purse')
eq(C.selectOnClose('pbag4', 'pbag', 3), 'pbag4', 'another purse bag closed: no change')
eq(C.selectOnClose('purse', 'purse', nil), 'main', 'the purse closed: the backpack')
eq(C.selectOnClose('pbag3', 'purse', nil), 'main', 'the purse closed on a purse bag page: the backpack')
eq(C.selectOnClose('bag3', 'purse', nil), 'bag3', 'the purse closed on a bag page: no change')
eq(C.selectOnClose('bag3', 'bag', 3), 'main', 'its bag closed: the backpack')
eq(C.selectOnClose('purse', 'bag', 3), 'purse', 'a bag closed on the purse page: no change')

-- container ids: one bag per family, so the panel holds at most four containers
eq(C.MAX_OPEN, 4, 'main, one bag, the purse, one purse bag')
local memo = { [5] = { fam = 'main', slot = 1 }, [7] = { fam = 'purse', slot = 0 }, [9] = { fam = 'purse', slot = 2 } }
eq(C.previousFor(memo, 'main'), 5, 'a backpack bag reuses the id of the backpack bag open')
eq(C.previousFor(memo, 'purse'), 7, 'a purse bag reuses the id of a purse bag open')
eq(C.previousFor({}, 'purse'), nil, 'none open: a free id')
eq(C.previousFor(nil, 'main'), nil, 'no memo')
local sup = C.superseded(memo, 11, 'purse')
eq(table.concat(sup, ','), '7,9', 'a purse bag opened with a new id closes the purse bags open')
eq(#C.superseded(memo, 11, 'main'), 1, 'and one backpack bag')
eq(#C.superseded(memo, 7, 'purse'), 1, 'the id it reused is not closed')
eq(#C.superseded({}, 7, 'purse'), 0, 'nothing open')

-- drops on a page button
local ids = { main = 1, purse = 2 }
local t = C.dropTarget('main', ids)
eq(t.y == 65 and t.z == 255, true, 'the backpack page: the front of the backpack')
t = C.dropTarget('bag4', ids)
eq(t.x == 65535 and t.y == 65 and t.z == 4, true, 'a bag page: the bag item in the backpack')
t = C.dropTarget('purse', ids)
eq(t.x == 65535 and t.y == 11 and t.z == 0, true, 'the purse page: the purse slot')
t = C.dropTarget('purse', {})
eq(t.y, 11, 'the purse page needs no open container')
t = C.dropTarget('pbag3', ids)
eq(t.x == 65535 and t.y == 66 and t.z == 3, true, 'a purse bag page: the bag item in the purse')
eq(C.dropTarget('pbag3', { main = 1 }), nil, 'a purse bag page with the purse closed: no target')
eq(C.dropTarget('main', {}), nil, 'the backpack closed: no target')
eq(C.dropTarget('nope', ids), nil, 'unknown page')
eq(C.dropTarget('bag1', nil), nil, 'no ids')
eq(C.samePlace({ x = 65535, y = 65, z = 3 }, { x = 65535, y = 65, z = 3 }), true, 'same place')
eq(C.samePlace({ x = 65535, y = 65, z = 3 }, { x = 65535, y = 65, z = 4 }), false, 'another slot')
eq(C.samePlace(nil, { x = 1, y = 1, z = 1 }), false, 'no position')

-- sort: not in the purse (the store inbox takes no plain item), as in any bag of it
eq(C.sortBlock('purse'), 'purse', 'no sort on the purse page')
eq(C.sortBlock('pbag1'), nil, 'sort in a bag of the purse')
eq(C.sortBlock('main'), nil, 'sort in the backpack')
eq(C.sortBlock('bag1'), nil, 'sort in a bag')
eq(C.sortBlock(nil), nil, 'no page')

if fails == 0 then print('bagpanel_core_test: ok') else os.exit(1) end
