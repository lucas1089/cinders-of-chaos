-- game_bossanimate, the logic without client API (tested by bossanimatelogic_test.lua).
-- Some boss looks have walk frames but no idle group: standing still they drew as one picture (owner 2026-11-06,
-- Skaldra the Rime Queen). Base patch 0189 binds ThingType:setAnimateAlways; a look on this list then plays its
-- phases on a clock while it stands (outfit.cpp, the isAnimateAlways path).
BossAnimateLogic = {}
local L = BossAnimateLogic

-- creature look ids (the server's <look type>): Skaldra the Rime Queen (wing beat)
L.LOOKS = { 1534 }

-- Boss looks whose art sits up and left of their tile (owner 2026-11-06, Gravewarden Ulthar: "o hitbox do boss esta
-- fora do lugar"). A 4x4 look is drawn with its bottom right cell on the creature's tile; look 2127's art stands in
-- the middle of its 128 px canvas (south frame: x 33-99, y 44-98), so it floated about 1.5 tiles up and left of where
-- the boss is. A negative displacement (GameNegativeOffset, on in game_features) moves it down and right by that gap:
-- the art's lowest row and right edge reach the bottom right cell, as our other 4x4 bosses (big_bosses.py).
-- look id -> {dx, dy} (ThingType:setDisplacement, bound in the base engine; no new client build needed).
L.SHIFTS = {
  [2127] = { -28, -28 }, -- Gravewarden Ulthar (raid boss; measured on pair 58 with tools/sprites/datspr.py)
}

-- sets each listed shift on its look; returns how many were set. getType(id) -> thing type or nil
function L.shift(getType, shifts)
  local n = 0
  for id, d in pairs(shifts or L.SHIFTS) do
    local t = getType(id)
    if (type(t) == "table" or type(t) == "userdata") and t.setDisplacement then
      local ok, res = pcall(t.setDisplacement, t, { x = d[1], y = d[2] })
      if ok and res ~= false then n = n + 1 end
    end
  end
  return n
end

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
