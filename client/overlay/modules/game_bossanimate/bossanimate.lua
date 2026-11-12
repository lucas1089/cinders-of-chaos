-- game_bossanimate: boss looks that animate while standing (bossanimatelogic.lua; base patch 0189) and boss looks
-- moved onto their tile (L.SHIFTS).
-- Hunt monster looks with one idle phase walk in place (L.WALK, idle_walk_looks.lua, O534).
-- A client without patch 0189 has no ThingType:setAnimateAlways: nothing changes.
local L = BossAnimateLogic

local function apply()
  if not g_things or not g_things.getThingType then return end
  local function getType(id)
    local ok, t = pcall(g_things.getThingType, id, ThingCategoryCreature)
    return ok and t or nil
  end
  L.apply(getType)
  L.applyWalk(getType)
  L.shift(getType)
end

function init()
  connect(g_game, { onGameStart = apply })
  if g_game.isOnline() then apply() end
end

function terminate()
  disconnect(g_game, { onGameStart = apply })
end
