-- game_bossanimate: boss looks that animate while standing (bossanimatelogic.lua; base patch 0189).
-- A client without patch 0189 has no ThingType:setAnimateAlways: nothing changes.
local L = BossAnimateLogic

local function apply()
  if not g_things or not g_things.getThingType then return end
  L.apply(function(id)
    local ok, t = pcall(g_things.getThingType, id, ThingCategoryCreature)
    return ok and t or nil
  end)
end

function init()
  connect(g_game, { onGameStart = apply })
  if g_game.isOnline() then apply() end
end

function terminate()
  disconnect(g_game, { onGameStart = apply })
end
