-- Names over tall looks: the engine places a creature's name and bars from the dat alone (2 px over the top of its
-- cell, up by the displacement), so on a look drawn taller than the stock ones they fell across the face or the
-- chest. The lifts per look (info_lifts.lua, from the pair) go to the engine once at start; base patch 0111 adds
-- Creature.setInformationLift. A client without that patch has no such function and keeps the classic place.

function init()
  if not (Creature and Creature.setInformationLift) then return end
  if Creature.clearInformationLifts then Creature.clearInformationLifts() end
  InfoLiftCore.apply(ChaosInfoLifts, function(look, lift) Creature.setInformationLift(look, lift) end)
end

function terminate()
  if Creature and Creature.clearInformationLifts then Creature.clearInformationLifts() end
end
