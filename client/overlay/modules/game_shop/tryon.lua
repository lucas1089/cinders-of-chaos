-- Pure part of the store's TRY ON button (client/MANIFEST.md "game_shop"; no client API, tryon_test.lua runs it under
-- LuaJIT and Lua 5.3). The button shows an offer on the player's own character for TryOn.MS milliseconds and buys
-- nothing: the look preview (game_lookpreview) pins the offer's option on the character, and, for the cosmetics whose
-- effect the server can play, the server plays it round the real character for the asker only (the "preview" action,
-- cosmetics.lua). Nobody else sees either, nothing is granted.
--   in the panel     outfits, addons, mounts, wings, auras, shaders (the outfit fields), outlines (the engine's outline
--                    pass), footprints (prints behind the walking figure), spell skins, kill / level-up / rare-loot
--                    effects and emotes (the effect on the stage), and a bundle of those
--   on the map       the server's preview of a cosmetic with an effect (preview.effect): spell skins, kill, level-up,
--                    rare-loot effects, emotes (an effect round you), footprints and outlines (game_cosmeticfx draws them
--                    on you for a few seconds)
--   not tried        name plate frames (the map draws plates; the panel prints a note), chat colours and loot label
--                    accents (the row's title shows the colour), pets (drawn alone, not on you), items, services,
--                    coins, pacts, hideout decorations: the offer keeps its icon or preview and has no button
TryOn = {}
local T = TryOn

T.MS = 10000 -- how long the look stays on the character

-- the option kinds of LookPreviewCore that put something on the player's own character
T.WORN = { outfit = true, addons = true, mount = true, wings = true, aura = true, shader = true, outline = true,
  effects = true, footprint = true }
-- the kinds that keep their icon (the list above, for the report and the manifest; nothing reads it)
T.NOT_TRIED = { 'nameplate', 'subject', 'swatch', 'item', 'service', 'premium', 'pact' }

local function worn(opt)
  if type(opt) ~= 'table' then return false end
  if opt.kind == 'bundle' then
    for _, p in ipairs(type(opt.parts) == 'table' and opt.parts or {}) do
      if type(p) == 'table' and T.WORN[p.kind] then return true end
    end
    return false
  end
  return T.WORN[opt.kind] == true
end
T.worn = worn

-- data = the offer as the server sent it (preview.effect), option = LookPreviewCore.fromShopOffer(data), hasPanel = the
-- look preview exists (not on the small mobile layout). Returns {panel, server, show}.
function T.plan(data, option, hasPanel)
  local plan = { panel = hasPanel == true and worn(option), server = false }
  local pv = type(data) == 'table' and data.preview
  plan.server = type(pv) == 'table' and pv.effect == true
  plan.show = plan.panel or plan.server
  return plan
end

-- seconds left (rounded up) at `now` of a try that ends at `untilMs`; 0 when over
function T.secondsLeft(untilMs, now)
  local left = (tonumber(untilMs) or 0) - (tonumber(now) or 0)
  if left <= 0 then return 0 end
  return math.ceil(left / 1000)
end

-- the button's text while a try runs: "8s"; nil = the normal text
function T.countdown(left)
  left = tonumber(left) or 0
  return left > 0 and (left .. 's') or nil
end

-- the right margin of the button and the description's, by what else sits on the row's right (the gift button)
function T.margins(giftShown)
  if giftShown then return { button = 48, description = 164 } end
  return { button = 4, description = 120 }
end

return T
