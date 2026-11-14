-- Pure rules of game_bagpanel (O420; client/MANIFEST.md): no client API here, bagpanel_core_test.lua tests them.
-- The panel shows the equipment and one page at a time: page 1 is the backpack, every bag in it is another page, then
-- the purse (O492) and, once it is open, every bag in it (Loot Bag, the pouches) as pages of their own. A container is told apart by the key game_chaoslayout learns for it ("3_2854" = the container in
-- inventory slot 3, "3_2854/1_1987" = the bag at index 1 of that one). Positions are the protocol's: an inventory slot
-- is (65535, slot, 0), a slot of an open container is (65535, 64 + container id, index).
-- The Loot Bag (O516) is the one bag that is no page: it is a section under the grid of the page shown, 20 slots at a time
-- (C.lootView), so opening it never takes the backpack away.
BagPanelCore = {}
local C = BagPanelCore

C.BACK_SLOT = 3
C.PURSE_SLOT = 11          -- the purse: the engine's store inbox, where store purchases are delivered (server/README.md "Store")
C.CELL = 34
C.SPACING = 2
C.MAX_STEPS_PER_ITEM = 2   -- the sort stops after this many moves per item (a safety net, a sort needs at most one)
C.STUCK = 3                -- moves that changed nothing in a row: the sort gives up
C.STEP_MS = 220            -- between two sort moves (the answer of the server comes in between)
C.WHOLE = 255              -- the "whole container" index: the server adds the item to the front of the container

-- the equipment grid, rows of 3 (inventory slot ids, 0 = no slot): the client's slot numbers
-- 13 is the badge slot (base patch 0113): the Chaos server takes nothing in the ammunition slot (10), so it is not shown.
-- The places are the stock inventory window's (BASE.md, owner 2026-11-11, O491): the backpack top right, the badge where
-- the ammunition slot was (row 3, column 3). The panel had swapped them.
C.EQUIP_SLOTS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 13 }
C.EQUIP_ROWS = { { 2, 1, 3 }, { 6, 4, 5 }, { 9, 7, 13 }, { 0, 8, 0 } }
-- English names (tr() keys at run time)
C.SLOT_NAMES = { [1] = 'Head', [2] = 'Necklace', [3] = 'Backpack', [4] = 'Armor', [5] = 'Right hand',
  [6] = 'Left hand', [7] = 'Legs', [8] = 'Feet', [9] = 'Ring', [13] = 'Badge' }

-- coins by client id, in gold
C.COINS = { [3031] = 1, [3035] = 100, [3043] = 10000 }

-- tabs: Equip is this panel; the others open a window that already exists. The first target whose module is loaded
-- wins; a tab with no target is not shown.
C.TABS = {
  { id = 'equip', text = 'Equip' },
  { id = 'quest', text = 'Quest', targets = { { 'game_questlog', 'toggle' }, { 'game_goals', 'toggle' } } },
  { id = 'status', text = 'Stats', targets = { { 'game_skills', 'toggle' } } },
  { id = 'active', text = 'Buffs', targets = { { 'game_buffbar', 'toggle' } } },
  { id = 'shop', text = 'Shop', targets = { { 'game_shop', 'toggle' } } },
}

local function int(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
  return math.floor(v)
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
-- key -> 'main' (the backpack slot's container), 'bag', index (a container item of the main backpack, index 0 = first),
-- 'purse' (the container in inventory slot 11, the store inbox), 'pbag', index (a container item of the purse) or nil
-- (any other container: a corpse, the depot, a bag in a bag, a quiver: it keeps its classic window)
function C.classify(key)
  if type(key) ~= 'string' then return nil end
  if key:match('^' .. C.BACK_SLOT .. '_%d+$') then return 'main' end
  local idx = key:match('^' .. C.BACK_SLOT .. '_%d+/(%d+)_%d+$')
  if idx then return 'bag', tonumber(idx) end
  if key:match('^' .. C.PURSE_SLOT .. '_%d+$') then return 'purse' end
  idx = key:match('^' .. C.PURSE_SLOT .. '_%d+/(%d+)_%d+$')
  if idx then return 'pbag', tonumber(idx) end
  return nil
end

-- true when a container with this key is shown by the panel (so its own window stays hidden)
function C.inPanel(key)
  return C.classify(key) ~= nil
end

-- the container a kind belongs to: the backpack's family ('main', 'bag') or the purse's ('purse', 'pbag')
function C.family(kind)
  if kind == 'purse' or kind == 'pbag' then return 'purse' end
  if kind == 'main' or kind == 'bag' then return 'main' end
  return nil
end

-- page keys: 'main', 'purse', 'bag<slot>' (a bag of the backpack), 'pbag<slot>' (a bag of the purse)
function C.bagKey(fam, slot)
  return (fam == 'purse' and 'pbag' or 'bag') .. tostring(int(slot) or 0)
end

-- a page key -> 'main' | 'purse' | 'bag' | 'pbag', slot (nil for a key that is none of them)
function C.parseKey(key)
  if key == 'main' or key == 'purse' then return key end
  local kind, n = tostring(key):match('^(p?bag)(%d+)$')
  if kind then return kind, tonumber(n) end
  return nil
end

-- ---------------------------------------------------------------- pages
-- items: the slots of a container in order, { { id, container } or false for a gap }. The bag slots:
-- { { slot = index, id = item id } }
function C.bagSlots(items)
  local out = {}
  for i = 1, #items do
    local it = items[i]
    if it and it.container then out[#out + 1] = { slot = i - 1, id = it.id } end
  end
  return out
end

-- the pages: the main backpack first, then one per bag of it, then (purse = nil: the character has no purse) the purse
-- and one per bag in it (ids: the client ids the server named, C.isLootBag; the Loot Bag's entry carries loot = true:
-- its button shows or hides the Loot Bag section instead of switching the page). purse.bags is empty until the purse has been opened: the client does not know its contents
-- before.
function C.pages(bags, purse, ids)
  local out = { { key = 'main', id = nil } }
  for _, b in ipairs(bags or {}) do
    out[#out + 1] = { key = C.bagKey('main', b.slot), slot = b.slot, id = b.id, fam = 'main' }
  end
  if purse then
    out[#out + 1] = { key = 'purse', id = nil, fam = 'purse' }
    for _, b in ipairs(purse.bags or {}) do
      out[#out + 1] = { key = C.bagKey('purse', b.slot), slot = b.slot, id = b.id, fam = 'purse',
        loot = C.isLootBag(b.id, ids) or nil }
    end
  end
  return out
end

-- the page key still valid after the pages changed: a gone bag of the purse falls back to the purse, anything else to
-- the main backpack
function C.validKey(pages, key)
  for _, p in ipairs(pages) do
    if p.key == key then return key end
  end
  if C.parseKey(key) == 'pbag' then
    for _, p in ipairs(pages) do
      if p.key == 'purse' then return 'purse' end
    end
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

-- the page shown follows the list of the container of family `fam` when an item came in (add) or left at `at`: a bag
-- page moves with its bag, and falls back to the family's first page when its bag is the one removed ('main' for the
-- backpack, 'purse' for the purse)
function C.shiftSelected(selected, fam, at, add)
  local kind, n = C.parseKey(selected)
  if not n or C.family(kind) ~= fam then return selected end
  local s
  if add then s = C.shiftAdd(n, at) else s = C.shiftRemove(n, at) end
  if s then return C.bagKey(fam, s) end
  return fam == 'purse' and 'purse' or 'main'
end

-- ---------------------------------------------------------------- selection
-- the page shown after a container opened. A bag or the purse the player opened (a double click, a page button, the
-- Purse button, Find my item) is the page shown; the login restore opens containers too, and those leave the page alone
-- (the panel starts on the backpack). The main backpack opening changes nothing, nor does the Loot Bag (`loot`: a section
-- of its own, C.lootShownOnOpen).
function C.selectOnOpen(selected, kind, slot, restoring, loot)
  if restoring or loot then return selected end
  if kind == 'bag' or kind == 'pbag' then return C.bagKey(C.family(kind), slot) end
  if kind == 'purse' then return 'purse' end
  return selected
end

-- the page shown after a container closed (kind and slot as C.classify gave them when it opened): the page of a bag goes
-- back to its family's first page, the purse back to the backpack
function C.selectOnClose(selected, kind, slot)
  if kind == 'bag' and selected == C.bagKey('main', slot) then return 'main' end
  if kind == 'pbag' and selected == C.bagKey('purse', slot) then return 'purse' end
  if kind == 'purse' and (selected == 'purse' or C.parseKey(selected) == 'pbag') then return 'main' end
  return selected
end

-- ---------------------------------------------------------------- container ids
-- The server holds at most 16 open containers for a player, and the id of an open is chosen by the client. The panel
-- keeps at most one bag open per family, so it holds at most 4 containers: the main backpack, one bag of it, the purse
-- and one bag of the purse, and the Loot Bag (O516: its own, a bag with `loot` in the memo is neither reused nor closed by
-- the other bags of the family) makes 5. memo: container id -> { fam, slot, id, loot } of the bags opened for the panel.
C.MAX_OPEN = 5

-- the container whose id a bag page of family `fam` reuses (g_game.open(item, previous)): the bag of that family open
-- now, nil when there is none (the client then takes a free id)
function C.previousFor(memo, fam)
  local best
  for cid, m in pairs(memo or {}) do
    if m.fam == fam and not m.loot and not m.pinned and (best == nil or cid < best) then best = cid end
  end
  return best
end

-- the bags of family `fam` still open when the bag in container `cid` opened with an id of its own (a double click uses
-- a free id): they are closed, so one bag stays open per family
function C.superseded(memo, cid, fam)
  local out = {}
  for other, m in pairs(memo or {}) do
    if m.fam == fam and other ~= cid and not m.loot and not m.pinned then out[#out + 1] = other end
  end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------- the Loot Bag section (O516)
-- The Loot Bag (500 slots, weightless, in the purse: server pouches_config.lua kinds.loot) opened as a page and took the
-- backpack's place with a grid of 250 slots (owner 2026-11-12: "open only 20 slots by default and leave the main backpack
-- open"). It is now a section under the grid of the page shown, LOOT_SLOTS slots at a time with arrows. The engine sends
-- it in pages of 250 (server src-patch 0081: the container's capacity at the client is 250, the first index and the
-- number of items come with it); a client page of 20 never crosses an engine page, so the last client page of an engine
-- page is the 10 slots that are left and the next one asks the server for the next engine page (g_game.seekInContainer).
C.LOOT_SLOTS = 20
-- the client ids of the Loot Bag: pouches_config.lua kinds.loot clientId and oldClientId (a pair before 62 draws the old
-- one); the server names the one in use (game_pouches getState().ids.loot), which wins when it is known
C.LOOT_CLIENT_IDS = { 38608, 33653 }

-- true when a bag of the purse with this client item id is the Loot Bag
function C.isLootBag(id, ids)
  id = int(id)
  if not id then return false end
  local named = type(ids) == 'table' and int(ids.loot) or nil
  if named and named ~= 0 then return id == named end
  for _, v in ipairs(C.LOOT_CLIENT_IDS) do
    if id == v then return true end
  end
  return false
end

-- the section after the Loot Bag opened: shown when the player opened it (a double click in the purse, its page button),
-- not when the login restore opened it (the panel starts without it, as it starts on the backpack)
function C.lootShownOnOpen(shown, restoring)
  if restoring then return shown end
  return true
end

-- client pages of an engine page of `ep` slots: ceil(ep / 20) (13 for 250)
local function lootPer(ep)
  return math.ceil(math.max(int(ep) or 1, 1) / C.LOOT_SLOTS)
end

-- the client page that holds item index `index` (0-based over the whole container)
function C.lootPageOf(index, ep)
  ep = math.max(int(ep) or 1, 1)
  index = math.max(int(index) or 0, 0)
  return math.floor(index / ep) * lootPer(ep) + math.floor((index % ep) / C.LOOT_SLOTS)
end

-- how many client pages the arrows walk: up to the page of the last item, one when the bag is empty. size: the items in
-- the whole container, ep: the container's capacity as the client has it
function C.lootPageCount(size, ep)
  size = int(size) or 0
  if size <= 0 then return 1 end
  return C.lootPageOf(size - 1, ep) + 1
end

-- what client page `page` (0-based, clamped) shows: { page, pages, seek = the first index of the engine page it lives in
-- (0 for a bag that is not paged), first = the first slot of that engine page it shows, count = slots shown }
function C.lootView(page, size, ep)
  ep = math.max(int(ep) or 1, 1)
  local pages = C.lootPageCount(size, ep)
  page = math.min(math.max(int(page) or 0, 0), pages - 1)
  local per = lootPer(ep)
  local first = (page % per) * C.LOOT_SLOTS
  return { page = page, pages = pages, seek = math.floor(page / per) * ep, first = first,
    count = math.min(C.LOOT_SLOTS, ep - first) }
end

-- the client page the container shows now, from its first index (c:getFirstIndex()); the page the player asked for while
-- the engine page it needs has not come yet stays the asked one (the server answers a seek with a new open)
function C.lootPageFor(want, firstIndex, size, ep)
  local v = C.lootView(want, size, ep)
  if (int(firstIndex) or 0) == v.seek then return v.page end
  return C.lootPageOf(int(firstIndex) or 0, ep)
end

-- ---------------------------------------------------------------- drops on a page button
-- Where an item dropped on a page button goes (a position for g_game.move), nil when there is none. ids: the container
-- ids of the open { main = , purse = }. A bag page: the position of the bag's item in its container, which the server
-- takes as "into that bag" (as a drop on a bag in a window), so the bag need not be open. The backpack page: the front
-- of the backpack. The purse page: the inventory slot of the purse, the engine's store inbox, which refuses what it does
-- not take with its own message (server/README.md "Delivery to the purse").
function C.dropTarget(key, ids)
  local kind, slot = C.parseKey(key)
  ids = ids or {}
  if kind == 'main' then return ids.main and C.wholePos(ids.main) or nil end
  if kind == 'purse' then return C.slotPos(C.PURSE_SLOT) end
  if kind == 'bag' then return ids.main and C.containerPos(ids.main, slot) or nil end
  if kind == 'pbag' then return ids.purse and C.containerPos(ids.purse, slot) or nil end
  return nil
end

-- true when an item at `from` already is at `to` (the drop changes nothing)
function C.samePlace(from, to)
  if type(from) ~= 'table' or type(to) ~= 'table' then return false end
  return int(from.x) == int(to.x) and int(from.y) == int(to.y) and int(from.z) == int(to.z)
end

-- Sort moves an item to the front of its page. The purse is the engine's store inbox: it takes an item only when the item
-- is a store item (storeinbox.cpp, queryAdd), and nothing the Chaos server delivers is flagged one, so a move inside it
-- is refused. The bags in the purse are not store items (container.cpp refuses moves into a store item bag in the inbox
-- only), so Sort works there. Returns the reason code the page cannot be sorted, nil when it can.
function C.sortBlock(key)
  if C.parseKey(key) == 'purse' then return 'purse' end
  return nil
end

-- ---------------------------------------------------------------- empty slots (O557)
-- A container the engine sizes to its capacity (a rift bag, a pouch: 36 slots and more) drew every slot, a wall of empty
-- cells under the nine items it held. The grid now draws the slots in use and one more row to drop into, at least `minRows`
-- rows, never more than the capacity. Items sit at the front (the server adds at the front), so the slots shown are the
-- first ones. total: the capacity (or the slots of the page), used: the highest occupied slot + 1.
C.MIN_ROWS = 2
function C.visibleSlots(total, used, cols, minRows)
  total, used = math.max(int(total) or 0, 0), math.max(int(used) or 0, 0)
  cols, minRows = math.max(int(cols) or 1, 1), math.max(int(minRows) or C.MIN_ROWS, 1)
  local rows = math.max(math.ceil((used + 1) / cols), minRows)
  return math.min(total, rows * cols)
end

-- the highest occupied slot + 1 of a container read by `get(i)` (a truthy value: a slot in use), i = 0 .. cap - 1
function C.usedSlots(cap, get)
  local used = 0
  for i = 0, (int(cap) or 0) - 1 do
    if get(i) then used = i + 1 end
  end
  return used
end

-- ---------------------------------------------------------------- bag names (O557)
-- The tooltip of a page button names the bag: the first usable name among `names`, else "Bag N" (the caller's tr). The
-- engine's own placeholder names are no names.
function C.bagName(names)
  for _, n in ipairs(names or {}) do
    if type(n) == 'string' then
      n = n:gsub('^%s+', ''):gsub('%s+$', '')
      local low = n:lower()
      if n ~= '' and low ~= 'item' and low ~= 'unknown' and not low:match('^item of type') then return n end
    end
  end
  return nil
end

-- ---------------------------------------------------------------- loot header (O557)
-- "Page 1 of 13" did not fit between the arrows: the page reads "1/13" (the tooltip has the words), and the text a label
-- has not the room for is cut with "..." by `measure(text)` (the pixel width in the label's font).
function C.pageText(page, pages)
  return string.format('%d/%d', math.max(int(page) or 1, 1), math.max(int(pages) or 1, 1))
end

function C.elide(text, room, measure)
  text = tostring(text or '')
  room = int(room) or 0
  if measure(text) <= room then return text end
  local dots = '...'
  if measure(dots) > room then return '' end
  local n = #text
  while n > 0 do
    local cut = text:sub(1, n):gsub('%s+$', '')
    if measure(cut .. dots) <= room then return cut .. dots end
    n = n - 1
  end
  return dots
end

-- ---------------------------------------------------------------- pinned bags (O557)
-- A pinned bag stays open: no other bag replaces it (C.previousFor, C.superseded skip it) and it opens again after a login.
-- It is remembered per character as a key that does not move when items are added in front of the bag (the bag's index
-- does): the kind, the bag's item id and its number among the bags of that id in its container ("bag:1987#2": the second bag
-- 1987 of the backpack; "pbag:38608#1": a bag of the purse; "purse"). Limit: two bags of one id that swap places swap pins;
-- a bag replaced by another of the same id keeps the pin.
C.MAX_PINS = 3

-- items: the slots of the parent container as C.bagSlots reads them, { { id, container } or false }
function C.pinKey(fam, slot, items)
  slot = int(slot)
  local it = slot and items and items[slot + 1]
  if not it or not it.container then return nil end
  local n = 0
  for i = 1, slot + 1 do
    local o = items[i]
    if o and o.container and o.id == it.id then n = n + 1 end
  end
  return (fam == 'purse' and 'pbag:' or 'bag:') .. tostring(it.id) .. '#' .. n
end

-- 'purse' | 'bag' | 'pbag', id, number (nil for a key that is none of them)
function C.parsePin(key)
  if key == 'purse' then return 'purse' end
  local kind, id, n = tostring(key):match('^(p?bag):(%d+)#(%d+)$')
  if kind then return kind, tonumber(id), tonumber(n) end
  return nil
end

-- the slot the pin is at now in the parent's items, nil when that bag is gone
function C.pinSlot(key, items)
  local kind, id, num = C.parsePin(key)
  if not id then return nil end
  local n = 0
  for i = 1, #items do
    local o = items[i]
    if o and o.container and o.id == id then
      n = n + 1
      if n == num then return i - 1 end
    end
  end
  return nil
end

function C.encodePins(list)
  return table.concat(list or {}, ';')
end

-- the saved text -> the pins: valid keys only, no duplicates, at most MAX_PINS
function C.decodePins(text)
  local out, seen = {}, {}
  for key in tostring(text or ''):gmatch('[^;]+') do
    if C.parsePin(key) and not seen[key] and #out < C.MAX_PINS then
      seen[key] = true
      out[#out + 1] = key
    end
  end
  return out
end

function C.pinned(list, key)
  for _, k in ipairs(list or {}) do
    if k == key then return true end
  end
  return false
end

-- toggles `key`: the new list, whether it is pinned now, and 'full' when a fourth pin was refused
function C.togglePin(list, key)
  local out, found = {}, false
  for _, k in ipairs(list or {}) do
    if k == key then found = true else out[#out + 1] = k end
  end
  if found then return out, false end
  if not C.parsePin(key) then return out, false, 'invalid' end
  if #out >= C.MAX_PINS then return out, false, 'full' end
  out[#out + 1] = key
  return out, true
end

-- the next thing to open for the pins after a login, nil when nothing is left. state: { mainItems, purseItems (nil while
-- the purse is closed), purseOpen, open = { [pin key] = true } for the pinned bags open now }. The purse first, then the
-- bags of the backpack, then the bags of the purse (they need it open); a pin whose bag is gone is skipped.
function C.nextPinOpen(list, state)
  state = state or {}
  local open = state.open or {}
  local want = {}
  for _, k in ipairs(list or {}) do want[#want + 1] = k end
  local function order(k) local kind = C.parsePin(k) return kind == 'purse' and 1 or kind == 'bag' and 2 or 3 end
  table.sort(want, function(a, b) return order(a) < order(b) end)
  for _, k in ipairs(want) do
    local kind = C.parsePin(k)
    if kind == 'purse' then
      if not state.purseOpen then return { kind = 'purse', key = k } end
    elseif not open[k] then
      if kind == 'bag' and state.mainItems then
        local slot = C.pinSlot(k, state.mainItems)
        if slot then return { kind = 'bag', slot = slot, key = k } end
      elseif kind == 'pbag' and state.purseOpen and state.purseItems then
        local slot = C.pinSlot(k, state.purseItems)
        if slot then return { kind = 'pbag', slot = slot, key = k } end
      end
    end
  end
  return nil
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

-- the height the panel grows to so its whole layout shows: `need`, but never more than `room`, the height its side panel
-- has left besides the other shown windows. Taller, the side panel's fitAll (onHeightChange) closes other windows to
-- make room; the layout restore opens them again and the panel grows again: windows opening and closing on a phone,
-- whose side panel is short (owner 2026-11-06). nil: no change (already tall enough, or no room to grow).
function C.fitHeight(current, need, room)
  current, need = int(current) or 0, int(need) or 0
  local target = need
  if room ~= nil then target = math.min(need, int(room) or 0) end
  if target > current then return target end
  return nil
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
