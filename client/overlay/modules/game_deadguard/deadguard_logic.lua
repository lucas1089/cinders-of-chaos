-- Pure decisions of game_deadguard (client/MANIFEST.md). The server removes a dead monster within milliseconds of its
-- 0 percent health update. A creature that is still on the map GRACE_MS after that lost its removal packet and is taken
-- off locally. Players are never touched.
DeadGuardLogic = {}
local L = DeadGuardLogic

L.GRACE_MS = 3000

-- info: { isPlayer, isLocalPlayer, healthPercent, removed, onMap }
-- 'skip'  : not ours to remove (player, health above 0, already gone): forget it
-- 'wait'  : a dead monster that is on the map, still inside the grace time
-- 'remove': on the map at 0 percent after the grace time
function L.decide(info, ageMs)
  if type(info) ~= 'table' then return 'skip' end
  if info.isPlayer or info.isLocalPlayer then return 'skip' end
  if info.removed or not info.onMap then return 'skip' end
  if info.healthPercent == nil or info.healthPercent > 0 then return 'skip' end
  if (ageMs or 0) < L.GRACE_MS then return 'wait' end
  return 'remove'
end

-- should a health change start a watch? Only a non-player that reached 0 and is not watched already
function L.wantsWatch(state, id, isPlayer, isLocalPlayer, percent)
  if isPlayer or isLocalPlayer or not id or percent == nil or percent > 0 then return false end
  return not state.pending[id]
end

function L.newState() return { pending = {}, warned = {}, zeroSince = {}, offSince = nil } end

-- one warning per removal: true the first time an id is reported, false while it stays warned
function L.shouldLog(state, id)
  if state.warned[id] then return false end
  state.warned[id] = true
  return true
end

-- keep the tables small: forget the ids of a long session
function L.forget(state, id)
  state.pending[id] = nil
end

function L.reset(state)
  state.pending = {}
  state.warned = {}
  state.zeroSince = {}
  state.offSince = nil
end

-- The sweep (every SWEEP_MS), for the two ways a dead monster stays that the health event cannot see:
--  * 'zero': a monster at 0 percent whose health event never reached the watch (it was on the map before the module
--    started, the event came while the module was off): seen at 0 for GRACE_MS in a row.
--  * 'duplicate': two objects of one creature id on the map (a refresh that made a second object, server src-patch 0083
--    fixes the server side). The map's own entry for the id (canon) is the live one; the other is a leftover that no later
--    packet reaches, so it keeps its old health and never moves. Only when exactly one of the objects IS the canon one:
--    if the engine hands out a different wrapper for every call, nothing is touched.
-- list: { { id, obj, isPlayer, isLocalPlayer, healthPercent, removed, onMap } ... }; canon(id) -> the map's object or nil.
-- Returns the entries to remove, { entry, why }.
L.SWEEP_MS = 1000

function L.sweep(state, list, canon, now)
  local out = {}
  local byId = {}
  for _, e in ipairs(list or {}) do
    if type(e) == 'table' and e.id and not e.isPlayer and not e.isLocalPlayer and not e.removed and e.onMap then
      byId[e.id] = byId[e.id] or {}
      table.insert(byId[e.id], e)
    end
  end
  local seenZero = {}
  for id, group in pairs(byId) do
    local live = canon and canon(id) or nil
    if #group > 1 and live ~= nil then
      local canonCount = 0
      for _, e in ipairs(group) do if e.obj == live then canonCount = canonCount + 1 end end
      if canonCount == 1 then
        for _, e in ipairs(group) do
          if e.obj ~= live then out[#out + 1] = { entry = e, why = 'duplicate' } end
        end
      end
    end
    for _, e in ipairs(group) do
      if e.healthPercent ~= nil and e.healthPercent <= 0 then
        seenZero[id] = true
        state.zeroSince[id] = state.zeroSince[id] or now
        if now - state.zeroSince[id] >= L.GRACE_MS then
          local already = false
          for _, o in ipairs(out) do if o.entry == e then already = true end end
          if not already then out[#out + 1] = { entry = e, why = 'zero' } end
        end
      end
    end
  end
  for id in pairs(state.zeroSince) do
    if not seenZero[id] then state.zeroSince[id] = nil end
  end
  return out
end

-- The own character off its tile (owner report 2026-10-30: "invisible while standing still, visible while walking", always
-- together with a ghost dead monster). The engine draws a creature that stands from its tile's list of things, and one
-- that walks from the tile's list of walking creatures (tile.cpp drawCreatures). A stack position that missed (a packet
-- that removed or replaced the thing at an index where the client holds the character) takes the character out of the
-- first list while the object lives on and keeps walking: not drawn standing, drawn walking. If the character stands
-- (not walking) on a tile that does not list it for OFF_TILE_MS in a row, it is put back on that tile.
-- info: { onMap, walking, listed } (listed: the tile's list of things holds the object). Returns 'readd' or nil.
L.OFF_TILE_MS = 1500

function L.selfOffTile(state, info, now)
  if type(info) ~= 'table' or not info.onMap or info.walking or info.listed ~= false then
    state.offSince = nil
    return nil
  end
  state.offSince = state.offSince or now
  if now - state.offSince >= L.OFF_TILE_MS then
    state.offSince = nil
    return 'readd'
  end
  return nil
end
