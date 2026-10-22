-- Pure helpers of the level-up effect (game_levelwings): the effect and where it goes, the settings rule and the message
-- check. No client API here; tested by levelwingsmath_test.lua (luajit and lua5.3).
--
-- Since pair 36 (2026-10-22, owner: "Use as spells, level up e loot beams") a level-up is the pack's level-up effect
-- (w_fx_level_up of server/data/lib/chaos_pack36_fx_ids.lua, credited in docs/CREDITS.md), drawn by the client pair.
-- Our golden wing images (images/wings_*.png, client/tools/gen_levelwings_art.py) are retired.

LevelWingsMath = {}
local M = LevelWingsMath

-- the effect: its id in the pair and its send offset (the art's bottom-right tile is the creature's tile + dx, dy);
-- levelwingsmath_test.lua checks both against chaos_pack36_fx_ids.lua
M.EFFECT_NAME = 'w_fx_level_up'
M.EFFECT = { id = 4047, dx = 1, dy = 1 }

-- the tile the effect is added to for a creature standing on pos
function M.effectPos(pos)
  if type(pos) ~= 'table' or not pos.x or not pos.y or not pos.z then return nil end
  return { x = pos.x + M.EFFECT.dx, y = pos.y + M.EFFECT.dy, z = pos.z }
end

-- the settings (Options > Effects: "Level-up wings on my character" / "... on other characters"; nil = no settings
-- module or option: on)
function M.wanted(isLocal, ownOn, othersOn)
  if isLocal then
    return ownOn ~= false
  end
  return othersOn ~= false
end

-- the creature id of a server message {action = 'play', data = {id, lv, n}}, or nil
function M.playId(msg)
  if type(msg) ~= 'table' or msg.action ~= 'play' or type(msg.data) ~= 'table' then
    return nil
  end
  local id = tonumber(msg.data.id)
  if not id or id <= 0 or id ~= math.floor(id) then
    return nil
  end
  return id
end
