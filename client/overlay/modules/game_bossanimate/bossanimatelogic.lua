-- game_bossanimate, the logic without client API (tested by bossanimatelogic_test.lua).
-- Some boss looks have walk frames but no idle group: standing still they drew as one picture (owner 2026-11-06,
-- Skaldra the Rime Queen). Base patch 0189 binds ThingType:setAnimateAlways; a look on this list then plays its
-- phases on a clock while it stands (outfit.cpp, the isAnimateAlways path).
BossAnimateLogic = {}
local L = BossAnimateLogic

-- creature look ids (the server's <look type>): Skaldra the Rime Queen (wing beat)
L.LOOKS = { 1534 }

-- applies fn(thingType) to each listed look that exists and can be set; returns how many were set.
-- getType(id) -> thing type or nil
function L.apply(getType, looks)
  local n = 0
  for _, id in ipairs(looks or L.LOOKS) do
    local t = getType(id)
    if (type(t) == "table" or type(t) == "userdata") and t.setAnimateAlways then
      local ok = pcall(t.setAnimateAlways, t, true)
      if ok then n = n + 1 end
    end
  end
  return n
end
