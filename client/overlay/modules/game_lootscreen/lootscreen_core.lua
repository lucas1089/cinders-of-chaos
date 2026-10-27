-- Pure helpers of the loot line filter (no engine calls, unit tested by lootscreen_test.lua).
-- The stock message module draws a message on the game screen when its MessageTypes entry has a screenTarget, and adds
-- it to the console when it has a consoleTab. The loot line ("Loot of a Bone Warrior: 84 gold coins.") is drawn over
-- the character on top of other status text, so the Loot mode gets a copy of its settings without the screen target.
-- The text still reaches the console, the Server Log and the Loot channel, and every module that reads the line.
LootScreen = {}

-- Gives types[mode] a copy without screenTarget; returns the previous entry to put back (false when nothing to do).
-- Calling it twice keeps the first previous entry: a marked copy is not copied again.
function LootScreen.apply(types, mode)
  if type(types) ~= 'table' or mode == nil then return false end
  local cur = types[mode]
  if type(cur) ~= 'table' or cur.chaosNoScreen then return false end
  local copy = {}
  for k, v in pairs(cur) do copy[k] = v end
  copy.screenTarget = nil
  copy.chaosNoScreen = true
  types[mode] = copy
  return cur
end

function LootScreen.restore(types, mode, previous)
  if type(types) == 'table' and mode ~= nil and previous then types[mode] = previous end
end

return LootScreen
