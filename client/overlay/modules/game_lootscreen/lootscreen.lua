-- Loot lines stay off the game screen (owner request 2026-10-27: the line drew over the character on top of other
-- status text). terminate puts the stock entry back.
local previous

function init()
  previous = LootScreen.apply(MessageTypes, MessageModes.Loot)
end

function terminate()
  LootScreen.restore(MessageTypes, MessageModes.Loot, previous)
  previous = nil
end
