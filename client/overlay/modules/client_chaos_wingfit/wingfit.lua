-- Wings centred on the body: the engine draws a look's wings at the creature's place and its body 6 px up and left;
-- the wings' art was placed against one body, so on a class look that stands further left or right in its tile they
-- sat off its back. The tables of wing_centres.lua (from the pair) go to the engine once at start; base patch 0193
-- adds setOutfitBodyCentre / setOutfitWingsCentre / clearOutfitWingCentres. A client without that patch has none of
-- them and draws as before. WingFit.shift is for the previews (the same shift, facing south).
WingFit = {}

local function headsSupported()
  return setOutfitHeadCentre ~= nil and setOutfitHeadRef ~= nil and setOutfitHeadPieces ~= nil and ChaosHeadCentres ~= nil
end

local function anchorsSupported()
  return setOutfitWingsAnchor ~= nil and setOutfitBodyAnchor ~= nil and ChaosWingAnchors ~= nil
end

local function supported()
  return setOutfitBodyCentre ~= nil and setOutfitWingsCentre ~= nil
end

-- the rows belong to pair 83: an older pair has the drawn art on the replaced wings looks and no look from `first` on
local function piecesSupported()
  if setOutfitPackPiece == nil or setOutfitWingsLift == nil or type(ChaosWearPieces) ~= 'table' then return false end
  if not g_things or not g_things.isValidDatId or not ThingCategoryCreature then return false end
  local ok, valid = pcall(function() return g_things.isValidDatId(ChaosWearPieces.first, ThingCategoryCreature) end)
  return ok and valid == true
end

-- anchor tile and lift; a client without the patch has none, and on an older pair the torso anchors of
-- wing_anchors.lua keep the drawn art of the replaced looks in place
function applyPieces()
  if clearOutfitPackPieces then clearOutfitPackPieces() end
  if clearOutfitPackShifts then clearOutfitPackShifts() end
  if not piecesSupported() then return end
  WingFitCore.applyPieces(ChaosWearPieces, function(look, ax, ay) setOutfitPackPiece(look, ax, ay) end,
    function(look, text) setOutfitWingsLift(look, text) end, isLevitation())
  -- O779 (base patch 0217): the north view of a pack wing moved up to the south one's height; a client without the
  -- patch has no setOutfitPackShift and draws the pack's place
  if setOutfitPackShift then
    WingFitCore.applyShifts(ChaosWearPieces, function(look, dir, dx, dy) setOutfitPackShift(look, dir, dx, dy) end)
  end
end

-- O762 (owner 2026-11-24: "o efeito de flutuar funciona. coloque uma opção pra desativar"): the pack wings lift their wearer
-- unless this client switched it off (the Float box of the Customise Character window). Saved per client, on by default.
-- Off: the pieces go in without their lifts, so every winged body on this screen stands on the ground, the wings still drawn.
function isLevitation()
  local ok, v = pcall(g_settings.getBoolean, WingFitCore.LEVITATION_KEY, true)
  if not ok then return true end
  return WingFitCore.levitationOn(v)
end

function setLevitation(on)
  on = on ~= false
  pcall(g_settings.set, WingFitCore.LEVITATION_KEY, on)
  applyPieces()
end

function init()
  -- purchased pieces of pair 83 (base patch 0209): the dat is loaded at login, so they go in at each game start
  connect(g_game, { onGameStart = applyPieces })
  if g_game.isOnline() then applyPieces() end
  -- head accessories (base patch 0200): a client without it has none of these functions
  if headsSupported() then
    if clearOutfitHeadCentres then clearOutfitHeadCentres() end
    WingFitCore.applyHeads(ChaosHeadCentres, function(dir, x, y) setOutfitHeadRef(dir, x, y) end,
      function(first, last) setOutfitHeadPieces(first, last) end,
      function(look, dir, x, y) setOutfitHeadCentre(look, dir, x, y) end)
  end
  -- code-drawn wings (base patch 0204): the engine measures the body and puts the wings' anchor on its torso; a
  -- client without the patch has none of these functions and keeps the table below
  if anchorsSupported() then
    if clearOutfitWingAnchors then clearOutfitWingAnchors() end
    WingFitCore.applyAnchors(ChaosWingAnchors, function(look, x, y) setOutfitWingsAnchor(look, x, y) end,
      function(look, dir, x, y) setOutfitBodyAnchor(look, dir, x, y) end)
  end
  if not supported() then return end
  if clearOutfitWingCentres then clearOutfitWingCentres() end
  WingFitCore.apply(ChaosWingCentres, function(look, dir, px) setOutfitBodyCentre(look, dir, px) end,
    function(look, dir, px) setOutfitWingsCentre(look, dir, px) end)
end

function terminate()
  disconnect(g_game, { onGameStart = applyPieces })
  if clearOutfitWingCentres then clearOutfitWingCentres() end
  if clearOutfitHeadCentres then clearOutfitHeadCentres() end
  if clearOutfitWingAnchors then clearOutfitWingAnchors() end
  if clearOutfitPackPieces then clearOutfitPackPieces() end
  if clearOutfitPackShifts then clearOutfitPackShifts() end
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
