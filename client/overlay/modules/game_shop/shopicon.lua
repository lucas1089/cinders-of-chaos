-- Pure part of the store's icons (server shop.lua / shop_core.lua K.lookOf; client/MANIFEST.md "game_shop"). An offer or
-- a category carries its own appearance as `look`; the icon is that cosmetic itself, not a stand-in item:
--   a creature  outfits, mounts, wings, auras, shaders, pets, bundles (the server sends them as type "outfit"); an
--               outline is the plain figure with the outline on it
--   a picture   a footprint's print, a plate frame's plate (the client's own art)
--   an effect   a spell skin's or kill effect's main effect, from the generated picture or the sprites themselves
--   a sample    a chat colour, a loot label accent
-- ShopIcon.plan(data, mainEffect) says which; no client API, so shopicon_test.lua runs it under LuaJIT and Lua 5.3.
ShopIcon = {}
local S = ShopIcon

S.PRINTS = '/modules/game_cosmeticfx/images/prints/'
S.GLOWS = '/modules/game_cosmeticfx/images/glows/'
S.PLATES = '/modules/game_nameplate/images/plate_'
S.FX = '/modules/game_cosmetics/images/fx'

local function artName(v)
  return type(v) == 'string' and v:match('^[%w_]+$') and #v <= 40 and v or nil
end

local function color(v)
  if type(v) ~= 'string' then return nil end
  return (v:match('^#%x%x%x%x%x%x$') or v:match('^#%x%x%x%x%x%x%x%x$')) and v or nil
end

-- the outline inside a look (its own, or a bundle's part)
function S.outlineOf(look)
  if type(look) ~= 'table' then return nil end
  if look.kind == 'outline' and artName(look.art) then return { art = look.art, pulse = look.pulse == true } end
  if look.kind == 'bundle' then
    for _, p in ipairs(type(look.parts) == 'table' and look.parts or {}) do
      local o = type(p) == 'table' and p.kind == 'outline' and S.outlineOf(p)
      if o then return o end
    end
  end
  return nil
end

-- data: an offer or category entry as the server sends it ({type, item | outfit, look}). mainEffect(play) -> the spec
-- of the effect to draw (LookPreviewCore.mainEffect). Returns {mode = ...}:
--   'native'   the widget the type asks for (item or creature) as before
--   'creature' the creature, plus outline = {art, pulse} and glow = the picture to use when the engine cannot outline
--   'image'    image = path (without .png), fixed = keep the ratio, rotation
--   'effect'   spec = {id, dx, dy, ms, m, n}
--   'swatch'   color, accent = true for a loot label (a bar), else the chat colour as text
function S.plan(data, mainEffect)
  local look = type(data) == 'table' and data.look or nil
  if type(look) ~= 'table' then return { mode = 'native' } end
  local k = look.kind
  if k == 'footprint' and artName(look.art) then
    return { mode = 'image', image = S.PRINTS .. look.art, rotation = 90 }
  elseif k == 'nameplate' and artName(look.frame) then
    return { mode = 'image', image = S.PLATES .. look.frame, fixed = true }
  elseif k == 'effects' and type(look.play) == 'table' then
    local spec = mainEffect and mainEffect(look.play)
    if type(spec) == 'table' and tonumber(spec.id) then return { mode = 'effect', spec = spec } end
    return { mode = 'native' }
  elseif k == 'swatch' and color(look.color) then
    return { mode = 'swatch', color = look.color, accent = look.accent == true }
  end
  local outline = S.outlineOf(look)
  if outline and data.type == 'outfit' then
    return { mode = 'creature', outline = outline, glow = S.GLOWS .. outline.art }
  end
  return { mode = 'native' }
end

-- the text of a sample ("Aa" in the colour, or a bar for a loot label accent)
function S.sampleText(plan)
  return plan and plan.accent and '' or 'Aa'
end
