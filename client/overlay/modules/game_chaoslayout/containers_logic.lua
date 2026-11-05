-- Pure rules of the open containers of game_chaoslayout (O412; client/MANIFEST.md "Window layout per character";
-- tested by containers_test.lua). A container window is remembered by where its container item sits, not by the
-- window id (that is a server container id, new at every login):
--   a step  { i, id }: i = the inventory slot (first step) or the index in the parent container (0 = first), id = the
--           client id of the container item there (checked before anything is opened)
--   a key   the steps as text, "3_2854/1_1987/0_1991": the backpack slot's container, its 2nd item, that one's 1st
-- The saved layout keeps them as a list: containers = { { key, panel, side, index, height, minimized, scroll } }
-- (g_settings gives a list back with string keys: C.list reads both).
ChaosContainerLogic = {}
local C = ChaosContainerLogic

C.MAX = 16          -- containers remembered at most (the first in panel order)
C.MAX_DEPTH = 8     -- steps of a key at most
C.MAX_SLOT = 11     -- inventory slots 1..10 and the purse (11)
C.GAP_MS = 150      -- between one open and the next at the restore
C.WAIT_MS = 2000    -- the server's answer to an open, at most
C.PENDING_MS = 3000 -- an open the client asked for is matched with the window that opens within this time

local function int(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
  return math.floor(v)
end

function C.keyOf(steps)
  if type(steps) ~= 'table' or #steps == 0 or #steps > C.MAX_DEPTH then return nil end
  local parts = {}
  for k, s in ipairs(steps) do
    local i, id = int(s.i), int(s.id)
    if not i or not id or id <= 0 or i < 0 then return nil end
    if k == 1 and (i < 1 or i > C.MAX_SLOT) then return nil end
    parts[#parts + 1] = i .. '_' .. id
  end
  return table.concat(parts, '/')
end

function C.parse(key)
  if type(key) ~= 'string' or key == '' then return nil end
  local steps = {}
  for part in (key .. '/'):gmatch('([^/]*)/') do
    local i, id = part:match('^(%d+)_(%d+)$')
    if not i then return nil end
    steps[#steps + 1] = { i = tonumber(i), id = tonumber(id) }
  end
  if C.keyOf(steps) ~= key then return nil end
  return steps
end

function C.depth(key)
  local s = C.parse(key)
  return s and #s or 0
end

function C.parentKey(key)
  local s = C.parse(key)
  if not s or #s < 2 then return nil end
  s[#s] = nil
  return C.keyOf(s)
end

-- the key of a container item the player opens, from the item's position: an inventory slot (x = 65535, y = slot) or a
-- slot of an open container (x = 65535, y = 64 + container id, z = index) whose key is known. nil otherwise (the map,
-- a corpse, a container this module did not see open).
function C.fromPosition(pos, itemId, keyOfContainer)
  if type(pos) ~= 'table' or int(pos.x) ~= 65535 then return nil end
  local y, z = int(pos.y), int(pos.z)
  if not y then return nil end
  if y >= 64 then
    local parent = keyOfContainer and keyOfContainer[y - 64]
    if not parent or not z or z < 0 then return nil end
    local steps = C.parse(parent)
    if not steps then return nil end
    steps[#steps + 1] = { i = z, id = itemId }
    return C.keyOf(steps)
  end
  return C.keyOf({ { i = y, id = itemId } })
end

-- a list read from g_settings in index order (integer or numeric-string keys)
function C.list(t)
  if type(t) ~= 'table' then return {} end
  if ChaosSettings and ChaosSettings.list then return ChaosSettings.list(t) end
  local idx, out = {}, {}
  for k in pairs(t) do
    local i = int(k)
    if i and i >= 1 and tostring(i) == tostring(k) then idx[#idx + 1] = i end
  end
  table.sort(idx)
  for _, i in ipairs(idx) do out[#out + 1] = t[i] ~= nil and t[i] or t[tostring(i)] end
  return out
end

-- the saved entries, cleaned: a valid key each, one entry per key, at most C.MAX
function C.entries(list)
  local out, seen = {}, {}
  for _, e in ipairs(C.list(list)) do
    if type(e) == 'table' and C.parse(e.key) and not seen[e.key] and #out < C.MAX then
      seen[e.key] = true
      out[#out + 1] = e
    end
  end
  return out
end

local function sidePos(side) return side == 'left' and 1 or side == 'right' and 2 or 3 end

-- the open container windows now, in panel order. windows: { { key, panel, side, panelOrder, index, height, minimized,
-- scroll } } (key nil: a container this module cannot name, left out)
function C.snapshot(windows)
  local list = {}
  for _, w in ipairs(windows or {}) do
    if type(w) == 'table' and C.parse(w.key) then list[#list + 1] = w end
  end
  table.sort(list, function(a, b)
    if sidePos(a.side) ~= sidePos(b.side) then return sidePos(a.side) < sidePos(b.side) end
    if (a.panelOrder or 0) ~= (b.panelOrder or 0) then return (a.panelOrder or 0) < (b.panelOrder or 0) end
    return (a.index or 0) < (b.index or 0)
  end)
  local out = {}
  for _, w in ipairs(list) do
    out[#out + 1] = { key = w.key, panel = w.panel, side = w.side, index = int(w.index) or 1, height = int(w.height),
      minimized = w.minimized == true, scroll = int(w.scroll) and int(w.scroll) > 0 and int(w.scroll) or nil }
  end
  return C.entries(out)
end

-- what to open at the restore, in order: the saved containers not open now, each after its parent. A parent that is
-- neither open nor saved is opened too (the server needs it open to reach the child) and closed again at the end
-- (transient). open: { [key] = true }. Returns { { key, transient } }.
function C.plan(saved, open)
  open = open or {}
  local entries = C.entries(saved)
  local want, order = {}, {}
  for n, e in ipairs(entries) do
    want[e.key] = true
    order[e.key] = n
  end
  local items, added = {}, {}
  local function add(key, transient, rank)
    if added[key] or open[key] then return end
    local parent = C.parentKey(key)
    if parent then add(parent, not want[parent], rank) end
    added[key] = true
    items[#items + 1] = { key = key, transient = transient, rank = rank, depth = C.depth(key) }
  end
  for _, e in ipairs(entries) do add(e.key, false, order[e.key]) end
  -- parents first; among one depth the saved order
  table.sort(items, function(a, b)
    if a.depth ~= b.depth then return a.depth < b.depth end
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.key < b.key
  end)
  local out = {}
  for _, it in ipairs(items) do out[#out + 1] = { key = it.key, transient = it.transient or nil } end
  return out
end

-- which item of the parent to open for a step: the item at the saved index when it is still that container, else the
-- first container of that id not taken by another step. items: { { index, id, container } }; used: { [index] = true }
function C.resolve(items, step, used)
  if type(step) ~= 'table' then return nil end
  used = used or {}
  for _, it in ipairs(items or {}) do
    if it.index == step.i and it.id == step.id and it.container ~= false and not used[it.index] then return it.index end
  end
  for _, it in ipairs(items or {}) do
    if it.id == step.id and it.container ~= false and not used[it.index] then return it.index end
  end
  return nil
end

-- where the restored windows go: { { key, panel, index, ... } } sorted per panel by index (inserted in that order, each
-- lands at its index). existing: { [panelId] = side } of the panels now; first: { left = id, right = id }. A panel that
-- is gone gives the first panel of its side.
function C.placement(saved, existing, first)
  local out = {}
  for _, e in ipairs(C.entries(saved)) do
    local panel = e.panel
    if not (existing and existing[panel]) then panel = first and first[e.side] end
    if panel then
      local c = {}
      for k, v in pairs(e) do c[k] = v end
      c.panel = panel
      out[#out + 1] = c
    end
  end
  table.sort(out, function(a, b)
    if a.panel ~= b.panel then return tostring(a.panel) < tostring(b.panel) end
    return (int(a.index) or 0) < (int(b.index) or 0)
  end)
  return out
end

-- the option "Remember open backpacks" (client_settings rememberBackpacks, base patch 0187): on unless turned off
function C.enabled(value)
  return value ~= false
end

-- the pending opens: { { key, id, cid, at } } (cid: the container id g_game.open asked the server for, nil for a use);
-- the window that opened takes the oldest one of its item id and container id still in time
function C.takePending(pending, itemId, now, containerId)
  local keep, found = {}, nil
  for _, p in ipairs(pending or {}) do
    local alive = (now or 0) - (p.at or 0) <= C.PENDING_MS
    if alive and not found and (p.id == nil or p.id == itemId) and (p.cid == nil or p.cid == containerId) then
      found = p
    elseif alive then
      keep[#keep + 1] = p
    end
  end
  return found and found.key or nil, keep
end

return ChaosContainerLogic
