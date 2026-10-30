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

function L.newState() return { pending = {}, warned = {} } end

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
end
