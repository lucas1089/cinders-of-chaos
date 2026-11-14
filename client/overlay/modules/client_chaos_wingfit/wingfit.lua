-- Wings centred on the body: the engine draws a look's wings at the creature's place and its body 6 px up and left;
-- the wings' art was placed against one body, so on a class look that stands further left or right in its tile they
-- sat off its back. The tables of wing_centres.lua (from the pair) go to the engine once at start; base patch 0193
-- adds setOutfitBodyCentre / setOutfitWingsCentre / clearOutfitWingCentres. A client without that patch has none of
-- them and draws as before. WingFit.shift is for the previews (the same shift, facing south).
WingFit = {}

local function headsSupported()
  return setOutfitHeadCentre ~= nil and setOutfitHeadRef ~= nil and setOutfitHeadPieces ~= nil and ChaosHeadCentres ~= nil
end

local function supported()
  return setOutfitBodyCentre ~= nil and setOutfitWingsCentre ~= nil
end

function init()
  -- head accessories (base patch 0200): a client without it has none of these functions
  if headsSupported() then
    if clearOutfitHeadCentres then clearOutfitHeadCentres() end
    WingFitCore.applyHeads(ChaosHeadCentres, function(dir, x, y) setOutfitHeadRef(dir, x, y) end,
      function(first, last) setOutfitHeadPieces(first, last) end,
      function(look, dir, x, y) setOutfitHeadCentre(look, dir, x, y) end)
  end
  if not supported() then return end
  if clearOutfitWingCentres then clearOutfitWingCentres() end
  WingFitCore.apply(ChaosWingCentres, function(look, dir, px) setOutfitBodyCentre(look, dir, px) end,
    function(look, dir, px) setOutfitWingsCentre(look, dir, px) end)
end

function terminate()
  if clearOutfitWingCentres then clearOutfitWingCentres() end
  if clearOutfitHeadCentres then clearOutfitHeadCentres() end
end

-- the {x, y} shift of a head piece of an outfit table {type, aura, ...} facing south, in sprite pixels at 1x; {0, 0}
-- without the engine patch, without an aura or on a mount (the engine does not shift a rider)
function WingFit.headShift(outfit)
  if not headsSupported() or type(outfit) ~= 'table' then return { 0, 0 } end
  if (tonumber(outfit.mount) or 0) > 0 then return { 0, 0 } end
  return WingFitCore.headShiftOf(ChaosHeadCentres, outfit.type, tonumber(outfit.aura) or 0, WingFitCore.SOUTH)
end

-- the shift of an outfit table {type, wings, ...} facing south, in sprite pixels at 1x; 0 without the engine patch or
-- without wings. lift: GameWingOffset's 6 (0 when the feature is off).
function WingFit.shift(outfit, lift)
  if not supported() or type(outfit) ~= 'table' then return 0 end
  local wings = tonumber(outfit.wings) or 0
  if wings <= 0 then return 0 end
  return WingFitCore.shiftOf(ChaosWingCentres, outfit.type, wings, WingFitCore.SOUTH, lift)
end
