-- Display scale, the pure part (no client API; scalelogic_test.lua runs it with plain luajit and lua5.3).
--
-- The server shows every combat number x the factor of the viewer's own level (server/README.md "Display scale";
-- server display_scale_core.lua): damage and heal numbers, the own health (stats packet), the DPS meter, the combat
-- log, the death recap, party frames, boards, tooltips. Those arrive scaled. Mana is never scaled (owner 2026-10-21,
-- server src-patch 0052): the own mana arrives as it is and a spell's mana cost in SpellInfo is its one fixed number at
-- every level, so nothing here touches SpellInfo. This module keeps the factor for the numbers other modules work out
-- by themselves: the globals ChaosScale, chaosDisplayFactor() and chaosDisplayValue(n) (chaosscale.lua puts them in
-- _G: the module is sandboxed).
-- Messages (JSON on opcode 157): server -> client {action = 'scale', data = {level, f}}; client -> server
-- {action = 'hello'} at a game start (the server answers with the factor).

ChaosScale = ChaosScale or {}
local S = ChaosScale
S.factor = S.factor or 1
S.level = S.level or 0
S.MAX_FACTOR = 1000000000 -- a sanity bound on what the server may say

function S.hello()
  return { action = 'hello' }
end

-- whether the own level (from the stats packet) is not the level of the last factor: ask again. A level of 0 or
-- before any factor (the login) waits for the login's own message.
function S.levelChanged(level)
  level = tonumber(level)
  return level ~= nil and level > 0 and S.level > 0 and level ~= S.level
end

-- the factor in a message, or nil when it is not a scale message
function S.parse(msg)
  if type(msg) ~= 'table' or msg.action ~= 'scale' or type(msg.data) ~= 'table' then
    return nil
  end
  local f = tonumber(msg.data.f)
  if not f or f ~= f or f < 1 or f > S.MAX_FACTOR then
    return nil
  end
  return math.floor(f), math.floor(tonumber(msg.data.level) or 0)
end

-- n x factor (whole numbers stay exact; a fraction is rounded); anything else as it is
function S.value(n, f)
  f = f or S.factor
  if type(n) ~= 'number' or n ~= n or f == 1 then
    return n
  end
  local r = n * f
  if r ~= math.floor(r) then
    r = math.floor(r + 0.5)
  end
  return r
end

function chaosDisplayFactor()
  return S.factor
end

function chaosDisplayValue(n)
  return S.value(n, S.factor)
end
