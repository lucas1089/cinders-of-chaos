-- Look preview: the pure part (no client API; lookpreview_core_test.lua runs it under LuaJIT and Lua 5.3).
-- One shared preview panel for every window where a look or a visual effect is picked (client/MANIFEST.md
-- "Look preview"): the outfit drawn, what the picked option changes on it, the zoom and where the feet go, turning and
-- the docking of the panel into a window that was not built with one (the base Outfit window).
-- The engine applies every effect itself: the option only becomes outfit fields (type, addons, mount, wings, aura,
-- shader) or the outline call of game_cosmeticfx, the same paths the map uses.

LookPreviewCore = LookPreviewCore or {}
local P = LookPreviewCore

-- ---------------------------------------------------------------- the two bases
-- 'own': the player's own outfit as worn; 'simple': the plain figure ("boneco simples"), a citizen look in greys with
-- no addons, mount, wings, aura or shader, so the effect reads on its own. Colours are outfit colour indexes: the
-- first column of the 7 x 19 table is the grey ramp (0 white ... 114 near black).
P.NEUTRAL = { type = 128, head = 76, body = 57, legs = 76, feet = 95, addons = 0, mount = 0 }
P.EXTRAS = { 'mount', 'wings', 'aura' }

local function copy(t)
  local o = {}
  for k, v in pairs(t or {}) do o[k] = v end
  return o
end
P.copy = copy

local function num(v) return tonumber(v) or 0 end

-- the outfit the panel starts from for a mode
function P.base(mode, own)
  if mode == 'simple' or type(own) ~= 'table' or num(own.type) <= 0 then
    local o = copy(P.NEUTRAL)
    o.shader = ''
    return o
  end
  local o = copy(own)
  o.shader = type(o.shader) == 'string' and o.shader or ''
  return o
end

-- ---------------------------------------------------------------- options
-- An option is what the window's row picks, as a table:
--   { kind = 'outfit', look = id, addons = 0-3 }   a look (and its addons); 'addons' is the same with addons 3
--   { kind = 'mount' | 'wings' | 'aura', look = id }
--   { kind = 'shader', shader = name }               '' or nil: no shader
--   { kind = 'outline', art = key, pulse = bool }    drawn by game_cosmeticfx.applyOutline (engine patch 0038)
--   { kind = 'look', outfit = {...} }                a whole outfit as a window holds it (the Outfit window's choice)
--   { kind = 'subject', look = id }                  something that is not worn: a pet, drawn alone
--   { kind = 'bundle', parts = {option, ...} }       a store bundle: every part on the character, in order (outfit,
--                                                    mount, wings, aura, shader, an outline, an effect)
--   { kind = 'effects', play, killfx }               a spell skin / kill effect, played on the stage (fromPlayRow)
--   { kind = 'footprint', art }                      prints behind the walking figure
--   { kind = 'nameplate', frame }                    a plate frame: a note (the map draws it)
--   nil or { kind = 'none' }                         the base unchanged
-- Kinds a UICreature cannot show (footprints are tile widgets, name plates are drawn by the map only, transmog and
-- rarity outlines are item looks): P.UNSHOWN gives the note the panel prints instead of a picture.
P.KINDS = { outfit = true, addons = true, mount = true, wings = true, aura = true, shader = true, outline = true, effects = true,
  look = true, subject = true, bundle = true, none = true }
P.UNSHOWN = {
  footprint = 'Footprints are left on the ground as you walk.',
  nameplate = 'Name plates show over characters in the game world.',
  transmog = 'Item looks show on the item, not on the character.',
}

function P.showable(opt)
  if opt == nil then return true end
  return type(opt) == 'table' and P.KINDS[opt.kind or 'none'] == true
end

function P.note(opt)
  return type(opt) == 'table' and P.UNSHOWN[opt.kind] or nil
end

-- does the 'simple' toggle mean anything for this option (a pet has no wearer; a kill effect is shown on a troll)
function P.hasWearer(opt)
  if type(opt) ~= 'table' then return true end
  return not (opt.kind == 'subject' or (opt.kind == 'effects' and opt.killfx == true))
end

P.UNKNOWN_SHADER = 'This shader is not in your client yet.'
P.NO_OUTLINE = 'Your client cannot draw outlines yet.' -- an engine without base patch 0038
P.NO_RIDE = 'Your look cannot ride: the mount is shown with the plain figure.'

-- What to draw: outfit, outline ({art, pulse} or nil) and a note (an unshown kind). The 'simple' figure keeps only
-- the option itself: for a whole outfit that is its extras (mount, wings, aura, shader) on the plain figure.
-- known(name): is the outfit shader registered in the client (the engine draws nothing for an unknown name, so it is
-- left off and the note says why).
-- canRide(type), optional: has that look the mounted pattern (pattern z 2). Before base patch 0088 Outfit::draw drew
-- the mount only for such a rider, so a look without it stood on foot with no mount; given, such a rider is replaced by
-- the plain figure in its colours and the note says why. The window passes none: with 0088 every look rides.
function P.compose(mode, own, opt, known, canRide)
  local o, outline, note = P.composeRaw(mode, own, opt)
  if o.shader and o.shader ~= '' and known and not known(o.shader) then
    o.shader = ''
    note = note or P.UNKNOWN_SHADER
  end
  if num(o.mount) > 0 and canRide and canRide(num(o.type)) == false then
    o.type, o.addons = P.NEUTRAL.type, 0
    note = note or P.NO_RIDE
  end
  return o, outline, note
end

function P.composeRaw(mode, own, opt)
  local kind = type(opt) == 'table' and opt.kind or 'none'
  if kind == 'subject' then
    return { type = num(opt.look) }, nil, nil
  end
  local o = P.base(mode, own)
  local outline
  if kind == 'bundle' then
    -- the parts one after the other on the same figure: a later part of the same field wins
    local note
    for _, part in ipairs(type(opt.parts) == 'table' and opt.parts or {}) do
      local pk = type(part) == 'table' and part.kind
      if pk and pk ~= 'bundle' and pk ~= 'subject' and pk ~= 'effects' and pk ~= 'footprint' then
        local po, pl, pn = P.composeRaw('own', o, part)
        o, outline, note = po, pl or outline, note or pn
      end
    end
    return o, outline, note
  end
  if kind == 'look' and type(opt.outfit) == 'table' then
    if mode == 'simple' then
      for _, k in ipairs(P.EXTRAS) do o[k] = num(opt.outfit[k]) end
      o.shader = type(opt.outfit.shader) == 'string' and opt.outfit.shader or ''
    else
      o = P.base('own', opt.outfit)
    end
  elseif kind == 'outfit' or kind == 'addons' then
    if num(opt.look) > 0 then o.type = num(opt.look) end
    o.addons = kind == 'addons' and 3 or num(opt.addons)
  elseif kind == 'mount' or kind == 'wings' or kind == 'aura' then
    o[kind] = num(opt.look)
  elseif kind == 'shader' then
    o.shader = type(opt.shader) == 'string' and opt.shader or ''
  elseif kind == 'outline' and type(opt.art) == 'string' and opt.art ~= '' then
    outline = { art = opt.art, pulse = opt.pulse == true }
  elseif kind == 'footprint' and type(opt.art) == 'string' and opt.art ~= '' then
    return o, nil, nil -- the stage draws the prints (P.footsteps)
  end
  return o, outline, P.note(opt)
end

-- ---------------------------------------------------------------- options from window data
-- The `look` of a store offer or category (server shop_core.lua K.lookOf) as an option; nil for what is not worn (a
-- colour sample) or not understood. Everything is checked: the server's table is data.
local function name(v) return type(v) == 'string' and v:match('^[%w_ ]+$') and #v <= 64 and v or nil end
function P.fromStoreLook(l, depth)
  if type(l) ~= 'table' or (depth or 0) > 1 then return nil end
  local k = l.kind
  if k == 'outfit' or k == 'addons' then
    return num(l.look) > 0 and { kind = 'outfit', look = num(l.look), addons = k == 'addons' and 3 or (tonumber(l.addons) or 3) } or nil
  elseif k == 'mount' or k == 'wings' or k == 'aura' or k == 'subject' then
    return num(l.look) > 0 and { kind = k, look = num(l.look) } or nil
  elseif k == 'shader' then
    return type(l.shader) == 'string' and l.shader ~= '' and { kind = 'shader', shader = l.shader } or nil
  elseif k == 'outline' then
    return name(l.art) and { kind = 'outline', art = l.art, pulse = l.pulse == true } or nil
  elseif k == 'footprint' then
    return name(l.art) and { kind = 'footprint', art = l.art } or nil
  elseif k == 'effects' then
    return type(l.play) == 'table' and #l.play > 0 and { kind = 'effects', play = l.play, killfx = l.killfx == true or nil } or nil
  elseif k == 'nameplate' then
    return name(l.frame) and { kind = 'nameplate', frame = l.frame } or nil
  elseif k == 'bundle' then
    local parts = {}
    for _, p in ipairs(type(l.parts) == 'table' and l.parts or {}) do
      local o = P.fromStoreLook(p, (depth or 0) + 1)
      if o then parts[#parts + 1] = o end
    end
    return #parts > 0 and { kind = 'bundle', parts = parts } or nil
  end
  return nil
end

-- the effects option inside an option (a spell skin itself, or a bundle's part), for the stage; nil when none
function P.effectsOf(opt)
  if type(opt) ~= 'table' then return nil end
  if opt.kind == 'effects' and type(opt.play) == 'table' then return opt end
  if opt.kind == 'bundle' then
    for _, p in ipairs(opt.parts or {}) do
      local e = P.effectsOf(p)
      if e then return e end
    end
  end
  return nil
end

-- the footprint art of an option (itself or a bundle's part), for the prints behind the figure; nil when none
function P.footprintArt(opt)
  if type(opt) ~= 'table' then return nil end
  if opt.kind == 'footprint' and type(opt.art) == 'string' and opt.art ~= '' then return opt.art end
  if opt.kind == 'bundle' then
    for _, p in ipairs(opt.parts or {}) do
      local a = P.footprintArt(p)
      if a then return a end
    end
  end
  return nil
end

-- a store offer (server shop.lua clientOffer: look; older servers: kind, outfit). Without a kind: wings / aura / shader by their field, a
-- coloured look is an outfit, a bare look a subject (a pet, or a mount of an older server)
function P.fromShopOffer(data)
  if type(data) == 'table' and type(data.look) == 'table' then
    -- the server sends the offer's own appearance (shop_core.lua K.lookOf): outlines, shaders, mounts, bundles ...
    return P.fromStoreLook(data.look)
  end
  if type(data) ~= 'table' or data.type ~= 'outfit' or type(data.outfit) ~= 'table' then return nil end
  local o, kind = data.outfit, data.kind
  if kind == 'mount' then return { kind = 'mount', look = num(o.type) } end
  if kind == 'outfit' or kind == 'addons' then return { kind = kind, look = num(o.type), addons = num(o.addons) } end
  if num(o.wings) > 0 then return { kind = 'wings', look = num(o.wings) } end
  if num(o.aura) > 0 then return { kind = 'aura', look = num(o.aura) } end
  if type(o.shader) == 'string' and o.shader ~= '' then return { kind = 'shader', shader = o.shader } end
  if o.head ~= nil then return { kind = 'outfit', look = num(o.type), addons = num(o.addons) } end
  if num(o.type) > 0 then return { kind = 'subject', look = num(o.type) } end
  return nil
end

-- a Cosmetics row (server cosmetics.lua / exclusives.lua): outlines, footprints and the Collection's looks
function P.fromCosmeticRow(r)
  if type(r) ~= 'table' then return nil end
  if r.kind == 'outline' then
    if num(r.id) ~= 0 and type(r.art) == 'string' then return { kind = 'outline', art = r.art, pulse = r.pulse == true } end
    return nil
  end
  if r.kind == 'footprint' then
    return num(r.id) ~= 0 and { kind = 'footprint', art = type(r.art) == 'string' and r.art or nil } or nil
  end
  if not r.collection then return nil end
  if r.kind == 'outfit' or r.kind == 'addons' then
    return num(r.look) > 0 and { kind = 'outfit', look = num(r.look), addons = r.addons or 3 } or nil
  elseif r.kind == 'mount' or r.kind == 'wings' or r.kind == 'aura' then
    return num(r.look) > 0 and { kind = r.kind, look = num(r.look) } or nil
  elseif r.kind == 'shader' then
    return type(r.shader) == 'string' and r.shader ~= '' and { kind = 'shader', shader = r.shader } or nil
  end
  return nil
end

-- a button of the base Outfit window's list (under the mouse, or focused): the row checked says what the button
-- shows. Outfits, auras and shaders carry a whole outfit (aura: its client id; shaders: base patch 0045), mounts the
-- mount alone as the look. Other rows (familiars): no option.
function P.fromOutfitButton(row, outfit)
  if type(outfit) ~= 'table' then return nil end
  if row == 'outfitCheck' then
    return { kind = 'outfit', look = num(outfit.type), addons = num(outfit.addons) }
  elseif row == 'mountCheck' then
    return { kind = 'mount', look = num(outfit.type) }
  elseif row == 'auraCheck' then
    return { kind = 'aura', look = num(outfit.aura) }
  elseif row == 'shaderCheck' then
    return { kind = 'shader', shader = type(outfit.shader) == 'string' and outfit.shader or '' }
  end
  return nil
end

-- What the panel of the Outfit window draws: the window's own preview (shown) is the choice so far, except on the
-- Mount row, where the window shows the mount alone: there the last look seen on another row rides the focused mount.
-- Returns own outfit, option, the look to remember.
function P.outfitWindowState(row, shown, focused, lastLook)
  if type(shown) ~= 'table' then return lastLook, nil, lastLook end
  if row == 'mountCheck' then
    local own = lastLook or shown
    local opt = P.fromOutfitButton('mountCheck', focused)
    if not opt or opt.look <= 0 then opt = { kind = 'mount', look = num(own.mount) } end
    return own, opt, lastLook
  end
  if row == 'outfitCheck' then
    return shown, { kind = 'outfit', look = num(shown.type), addons = num(shown.addons) }, shown
  end
  return shown, { kind = 'look', outfit = shown }, shown
end

-- the same outfit (no redraw while a window's outfit has not changed)
local FIELDS = { 'type', 'head', 'body', 'legs', 'feet', 'addons', 'mount', 'wings', 'aura', 'shader' }
function P.key(o)
  if type(o) ~= 'table' then return '' end
  local t = {}
  for i, k in ipairs(FIELDS) do t[i] = tostring(o[k] or '') end
  return table.concat(t, ',')
end

-- ---------------------------------------------------------------- turning
-- directions as the client numbers them: 0 north, 1 east, 2 south, 3 west; one step clockwise is +1
P.SOUTH = 2
function P.turn(dir, step)
  return ((num(dir) + num(step)) % 4 + 4) % 4
end
P.AUTO_MS = 1600   -- one direction per 1.6 s while the slow turn is on

-- ---------------------------------------------------------------- zoom and placement
-- A UICreature of size 2T draws the creature at T / 32 px per sprite pixel, its own tile the rect's lower right
-- quarter (client_chaos_charselect/charselect_core.lua, "UICreature draws a creature ..."). The list cards place a
-- figure (fx, fy: the feet; top, left, right: the reach), CharSelectCore.figure's, from the sprite anchors of the
-- pair: the centre of the feet goes where the feet should stand (client/MANIFEST.md "Where a character stands"); the
-- panel itself centres the drawn picture's box (below). P.FALLBACK, when that
-- module is absent: a 2x2 player look with displacement 8, its feet where CharSelectCore.FEET_FALLBACK puts them
-- (the test checks both agree), the bounds of stock look 128.
P.FALLBACK = { fx = 12, fy = 19, top = -22, left = -13, right = 24, hover = 0 }
P.RIDER = 22       -- sprite pixels a rider reaches above its mount's top (the list cards' figure)

-- the figure of a list card: a mounted look by its mount's reach plus the rider
function P.fitFigure(fig, mounted)
  local f = copy(type(fig) == 'table' and fig or P.FALLBACK)
  if mounted then f.top = f.top - P.RIDER end
  return f
end

-- the UICreature rect (x, y, size) that puts the feet of fig at (cx, feetY) at tile size T (same maths as
-- CharSelectCore.placeRect; the test checks both agree)
function P.placeRect(fig, T, cx, feetY)
  local s = T / 32
  return math.floor(cx - (fig.fx + 32) * s + 0.5), math.floor(feetY - (fig.fy + 32) * s + 0.5), 2 * T
end

-- ---------------------------------------------------------------- the drawn picture's box
-- The panel draws every look at one zoom, P.SCALE (owner, 2026-10-20: "make them all the size of this one", a 2x
-- look), and centres the box of everything the engine draws (body with its addons, mount, wings, aura) in the stage.
-- The box is in sprite pixels from the top left of the creature's own tile, as Outfit::draw (1098 profile) places
-- each part, facing south:
--   * a part's own box: the pixel bounds of the pair (CharSelectAnchors: top, left, right; first south frame, every
--     addon, displacement applied) when the table has the thing; else the tiles of its south frame that hold a sprite
--     (ThingType sprites), moved by its displacement (a frame's bottom-right tile is the creature's tile, the others
--     up and left of it); else its whole frame. The bottom is always the tiles' (the table has no bottom row).
--   * GameWingOffset with wings: the body, mount and aura 6 px (`lift`) up and left of the wings.
--   * a mount (only for a rider with the mounted pattern): a mount with a positive displacement is drawn that much
--     further up and left (the positive path of Outfit::draw), the rider with it; a rider sits P.RIDER_SEAT px higher
--     than it stands. A mount with a negative displacement is drawn by its own displacement only.
--   * wings of a mounted rider facing south 6 px up; a big aura (w - 1) * 16, (h - 1) * 16 right and down
--     (GameBigAurasCenter).
--   * an aura with two layers (GameAuraFrontAndBack: layer 0 behind the body, layer 1 over it; the head accessories
--     and capes of pair 33) counts the tiles of both layers, not the anchors (they measure layer 0 only).
-- anchorOf(id) -> {fx, fy, top, left, right} or nil; infoOf(id) -> {w, h, dx, dy, layers, px, py, pz, phases,
-- sprites} or nil (any field may be missing). Returns {left, top, right, bottom, fx, fy} (fx, fy: the feet).
P.SCALE = 2
P.RIDER_SEAT = 10
P.BELOW_GROUND = 5 -- sprite px a part's art reaches below the anchors' ground row (pair 30: 128, 1221, 1213, 1338)
P.FALLBACK_BOX = { left = -8, top = -8, right = 24, bottom = 24, fx = 12, fy = 19 } -- stock look 128 (2x2, 8,8)

-- a displacement as the engine reads it (a dat u16 above 32767 is negative: GameNegativeOffset)
local function signed(v)
  v = num(v)
  if v > 32767 then v = v - 65536 end
  return v
end
P.signed = signed

local function max1(v) return math.max(1, num(v)) end

-- the box of the tiles of a thing's south frame (phase 0, layer 0 or with allLayers every layer, the given addons and
-- pattern z) that hold a sprite, displacement applied; the whole frame without sprites; nil without info
function P.thingBox(info, z, addons, allLayers)
  if type(info) ~= 'table' then return nil end
  local w, h = max1(info.w), max1(info.h)
  local dx, dy = signed(info.dx or info.dispX), signed(info.dy or info.dispY)
  local c0, r0, c1, r1
  if type(info.sprites) == 'table' and #info.sprites > 0 then
    local px = max1(info.px) >= 4 and 2 or 0
    local pz = math.min(num(z), max1(info.pz) - 1)
    for yp = 0, max1(info.py) - 1 do
      if yp == 0 or (math.floor(num(addons) / 2 ^ (yp - 1)) % 2 == 1) then
        for layer = 0, allLayers and max1(info.layers) - 1 or 0 do
          for hh = 0, h - 1 do
            for ww = 0, w - 1 do
              if P.spriteAt(info, ww, hh, layer, px, yp, pz, 0) > 0 then
                local c, r = w - 1 - ww, h - 1 - hh
                c0 = c0 and math.min(c0, c) or c
                r0 = r0 and math.min(r0, r) or r
                c1 = c1 and math.max(c1, c) or c
                r1 = r1 and math.max(r1, r) or r
              end
            end
          end
        end
      end
    end
  end
  if not c0 then c0, r0, c1, r1 = 0, 0, w - 1, h - 1 end
  local ox, oy = -dx - (w - 1) * 32, -dy - (h - 1) * 32
  return { left = ox + c0 * 32, top = oy + r0 * 32, right = ox + (c1 + 1) * 32, bottom = oy + (r1 + 1) * 32 }
end

-- a CharSelectAnchors row {fx, fy, top, left, right, ...} as a table
function P.anchorFrom(row)
  if type(row) ~= 'table' or type(row[1]) ~= 'number' then return nil end
  return { fx = row[1], fy = row[2], top = row[3], left = row[4], right = row[5] }
end

-- one part's box (and feet) drawn at (ox, oy)
local function partBox(anchor, info, z, addons, ox, oy, allLayers)
  local tb = P.thingBox(info, z, addons, allLayers)
  local b
  if type(anchor) == 'table' then
    -- the table has no bottom row: its ground row (the lowest band of the solid mass) plus P.BELOW_GROUND, within
    -- the frame's tiles
    local bottom = num(anchor.fy) + P.BELOW_GROUND
    if tb then bottom = math.min(bottom, tb.bottom) end
    b = { left = anchor.left, top = anchor.top, right = anchor.right, bottom = math.max(bottom, num(anchor.fy)),
      fx = anchor.fx, fy = anchor.fy }
    -- the table counts every addon: the tiles of the addons worn (they hold every drawn pixel) cut it down
    if tb and tb.right > tb.left then
      b.left, b.top, b.right = math.max(b.left, tb.left), math.max(b.top, tb.top), math.min(b.right, tb.right)
      if b.right <= b.left then b.left, b.right = tb.left, tb.right end
    end
  elseif tb then
    b = tb
    b.fx, b.fy = (tb.left + tb.right) / 2, tb.bottom - 5
  else
    return nil
  end
  return { left = b.left + ox, top = b.top + oy, right = b.right + ox, bottom = b.bottom + oy, fx = b.fx + ox,
    fy = b.fy + oy }
end

function P.lookBox(outfit, anchorOf, infoOf, lift)
  if type(outfit) ~= 'table' then return copy(P.FALLBACK_BOX) end
  local function A(id) return anchorOf and num(id) > 0 and anchorOf(num(id)) or nil end
  local function I(id) return infoOf and num(id) > 0 and infoOf(num(id)) or nil end
  local box
  local function add(b)
    if not b then return end
    if not box then
      box = { left = b.left, top = b.top, right = b.right, bottom = b.bottom }
    else
      box.left, box.top = math.min(box.left, b.left), math.min(box.top, b.top)
      box.right, box.bottom = math.max(box.right, b.right), math.max(box.bottom, b.bottom)
    end
  end
  local l = num(outfit.wings) > 0 and num(lift) or 0
  local bodyInfo = I(outfit.type)
  local mounted = num(outfit.mount) > 0 and (bodyInfo == nil or bodyInfo.pz == nil or num(bodyInfo.pz) >= 2)
  local ox, oy, seat = -l, -l, 0
  local feet
  if mounted then
    local mi = I(outfit.mount)
    local mdx, mdy = signed(mi and (mi.dx or mi.dispX)), signed(mi and (mi.dy or mi.dispY))
    if mdx >= 0 and mdy >= 0 then ox, oy = ox - mdx, oy - mdy end
    local mb = partBox(A(outfit.mount), mi, 0, 0, ox, oy)
    add(mb)
    feet = mb
    seat = P.RIDER_SEAT
  end
  local rb = partBox(A(outfit.type), bodyInfo, 0, outfit.addons, ox, oy - seat)
  add(rb)
  feet = feet or rb
  if num(outfit.wings) > 0 then
    add(partBox(A(outfit.wings), I(outfit.wings), mounted and 1 or 0, 0, 0, mounted and -6 or 0))
  end
  if num(outfit.aura) > 0 then
    local ai = I(outfit.aura)
    local aw, ah = max1(ai and ai.w), max1(ai and ai.h)
    local front = ai ~= nil and num(ai.layers) >= 2
    add(partBox(not front and A(outfit.aura) or nil, ai, mounted and 1 or 0, 0, -l + (aw - 1) * 16,
      -l + (ah - 1) * 16, front))
  end
  if not box then return copy(P.FALLBACK_BOX) end
  box.fx = feet and feet.fx or (box.left + box.right) / 2
  box.fy = feet and feet.fy or box.bottom
  return box
end

-- the whole layout for a stage of w x h: always P.SCALE, the box's centre on the stage's centre. Returns scale, T, the
-- UICreature rect (x, y, size) and where the feet are drawn (feetX, feetY)
function P.layout(box, w, h)
  box = box or P.FALLBACK_BOX
  local s = P.SCALE
  local T = 32 * s
  local cx, cy = (box.left + box.right) / 2, (box.top + box.bottom) / 2
  local x = math.floor(w / 2 - (cx + 32) * s + 0.5)
  local y = math.floor(h / 2 - (cy + 32) * s + 0.5)
  local fx, fy = box.fx or cx, box.fy or box.bottom
  return { scale = s, T = T, x = x, y = y, size = 2 * T, feetX = math.floor(x + (fx + 32) * s + 0.5),
    feetY = math.floor(y + (fy + 32) * s + 0.5) }
end

-- the soft shadow under the feet (the character select's hover_shadow art): as wide as 60% of the body, 22 to 60
-- sprite px, 22 x 8 in shape. Returns x, y, w, h in stage px
P.SHADOW_MIN, P.SHADOW_MAX = 22, 60
function P.shadowRect(L, box)
  box = box or P.FALLBACK_BOX
  local sw = math.max(P.SHADOW_MIN, math.min(P.SHADOW_MAX, (box.right - box.left) * 0.6))
  local w = math.floor(sw * L.scale + 0.5)
  local h = math.floor(sw * 8 / 22 * L.scale + 0.5)
  return math.floor(L.feetX - w / 2 + 0.5), math.floor(L.feetY - h / 2 + 0.5), w, h
end

-- ---------------------------------------------------------------- docking into a finished window
-- The base Outfit window is widened by the panel's width and its children put back where they were: after the
-- widening, a child that moved right or grew (anchored to the right edge, centred, or stretched) gets the difference
-- added to its right margin. A child anchored to a moved sibling moves back with it in the next round, so the rounds
-- repeat until nothing moved (P.DOCK_ROUNDS at most). before / after: {id = {x, width}} of the same children.
P.DOCK_ROUNDS = 6
P.DOCK_KEEP = { closeButton = true, minimizeButton = true, lockButton = true } -- title bar buttons stay at the edge
function P.dockFixes(before, after)
  local fixes = {}
  for id, b in pairs(before or {}) do
    local a = after and after[id]
    if a and not P.DOCK_KEEP[id] then
      local dw = num(a.width) - num(b.width)
      local d = dw ~= 0 and dw or (num(a.x) - num(b.x))
      if d ~= 0 then fixes[id] = d end
    end
  end
  return fixes
end

-- ---------------------------------------------------------------- list cards (the Outfit window's buttons)
-- A card of w x h px (the picture's part, above its name) shows the look facing south, as large as fits: the body
-- (feet to top) inside P.CARD_FILL of the height and the width, at one of P.CARD_SCALES, feet centred.
P.CARD_SCALES = { 3, 2, 1.5, 1 }
P.CARD_FILL = 0.96
function P.cardLayout(fig, w, h)
  fig = fig or P.FALLBACK
  local tall = math.max(1, fig.fy - fig.top)
  local wide = math.max(1, fig.right - fig.left)
  local s = P.CARD_SCALES[#P.CARD_SCALES]
  for _, sc in ipairs(P.CARD_SCALES) do
    if tall * sc <= h * P.CARD_FILL and wide * sc <= w * P.CARD_FILL then s = sc break end
  end
  local T = math.floor(32 * s + 0.5)
  local feetY = math.floor((h + tall * s) / 2 + 0.5)
  local cx = math.floor(w / 2 + ((fig.left + fig.right) / 2 - fig.fx) * -s + 0.5)
  local x, y, size = P.placeRect(fig, T, cx, feetY)
  return { scale = s, x = x, y = y, size = size, feetY = feetY }
end

-- ---------------------------------------------------------------- the effect stage
-- A Cosmetics row that changes effects (spell skins, kill effects) carries `play` from the server
-- (cosmetics_core.lua C.playRows): one step per swap, {a = the stock effect, b = the skin's}, each
-- {id, dx, dy, ms, m = 1 for a missile, n = icon name}. The panel plays them in a loop around the preview creature
-- with the client's own sprites: an effect is its thing type's frames, tile by tile (UISprite widgets, no map), placed
-- the way the map places it: its bottom-right tile on the target tile + (dx, dy), each tile (w, h) of the thing
-- w * T left and h * T up of that, minus the thing's displacement. Ground effects (base patch 0055, game_groundfx)
-- go under the creature, the others over it. Missiles fly from P.MISSILE_FROM to the creature's tile.
-- info = a thing type read once: {w, h, layers, px, py, pz, phases, dispX, dispY, sprites = {ids, 1-based}}.
P.FRAME_MS = 100        -- one frame of an effect whose length the server did not send (enhanced animations: 50-100)
P.MISSILE_MS = 420      -- a missile's flight over the preview's short path
P.FX_GAP = 250          -- between two steps
P.FX_PAUSE = 900        -- after the last step, before the loop starts again
P.MISSILE_FROM = { -2, -1 } -- tiles from the target when there is no caster on the stage
P.FX_SCALES = { 2, 1.5, 1 } -- never larger than the look's own zoom (P.SCALE)

-- ---------------------------------------------------------------- the scene
-- Spell skins (owner, 2026-10-20: "show the player using the spell on a monster"): the player on the stage's tile
-- (0, 0) facing east, a troll P.TARGET_AT tiles east of it facing west; a missile flies from the player to the troll,
-- an effect plays on the troll or around the player (P.landsOn). Kill effects ("show a monster dying, it can be a
-- troll"): the troll alone on (0, 0), facing south; it stands P.KILL_LEAD ms, then the kill effect plays on its tile
-- and it fades out over P.FADE_MS (P.targetAlpha), and the loop starts again with it standing.
P.TROLL = 15        -- the stock troll's look type (server bounty_pool.lua: Troll look 15)
P.TARGET_AT = 2
P.KILL_LEAD = 600
P.FADE_MS = 350
P.EAST, P.WEST = 1, 3

-- the scene of an effects option: {kill, caster = {x, y} or nil, target = {x, y}}
function P.sceneOf(opt)
  if type(opt) == 'table' and opt.killfx == true then
    return { kill = true, target = { x = 0, y = 0 } }
  end
  return { kill = false, caster = { x = 0, y = 0 }, target = { x = P.TARGET_AT, y = 0 } }
end

-- Where a step's effect plays: 'missile' (it flies from the caster to the target), 'target' or 'caster'. The server
-- sends no spell geometry with a skin's effects, so: a kill effect is on the target; in a spell with a missile the
-- other effects are its impact (the target); else an effect whose name says it hits something (P.TARGET_WORDS) is on
-- the target, the others (war cries, novas, auras, portals, vanishing) around the caster.
P.TARGET_WORDS = { 'explosion', 'lightning', 'strike', 'impact', 'hit', 'punch', 'slash', 'bite', 'spear', 'bolt',
  'chain', 'meteor', 'pyre', 'fall', 'pierce', 'arrow', 'shot', 'inferno' }
function P.landsOn(spec, hasMissile, scene)
  if type(spec) ~= 'table' then return 'target' end
  if spec.m then return 'missile' end
  if type(scene) == 'table' and (scene.kill or not scene.caster) then return 'target' end
  if hasMissile then return 'target' end
  local n = type(spec.n) == 'string' and spec.n:lower() or ''
  for _, w in ipairs(P.TARGET_WORDS) do
    if n:find(w, 1, true) then return 'target' end
  end
  return 'caster'
end

local function hasMissile(play)
  for _, step in ipairs(type(play) == 'table' and play or {}) do
    if type(step) == 'table' and ((type(step.a) == 'table' and step.a.m) or (type(step.b) == 'table' and step.b.m)) then
      return true
    end
  end
  return false
end
P.hasMissile = hasMissile

-- the target's opacity `ms` into the loop: 1 standing (always outside a kill scene), fading after the lead, then 0
function P.targetAlpha(tl, ms)
  if type(tl) ~= 'table' or num(tl.total) <= 0 or num(tl.lead) <= 0 then return 1 end
  local d = num(ms) % tl.total - tl.lead
  if d < 0 then return 1 end
  if d < P.FADE_MS then return 1 - d / P.FADE_MS end
  return 0
end

-- the sprite of tile (w, h) of a frame (ThingType::getSpriteIndex), 0 when out of range
function P.spriteAt(info, w, h, layer, x, y, z, phase)
  if type(info) ~= 'table' or type(info.sprites) ~= 'table' then return 0 end
  local phases = math.max(1, num(info.phases))
  local idx = ((((((phase % phases) * math.max(1, num(info.pz)) + z) * math.max(1, num(info.py)) + y)
    * math.max(1, num(info.px)) + x) * math.max(1, num(info.layers)) + layer) * math.max(1, num(info.h)) + h)
    * math.max(1, num(info.w)) + w
  return num(info.sprites[idx + 1])
end

-- the non-empty tiles of one frame: {{w, h, sprite}} (w, h counted from the bottom-right tile)
function P.frameTiles(info, phase, x, y)
  local out = {}
  if type(info) ~= 'table' then return out end
  for h = 0, math.max(1, num(info.h)) - 1 do
    for w = 0, math.max(1, num(info.w)) - 1 do
      local id = P.spriteAt(info, w, h, 0, x or 0, y or 0, 0, phase or 0)
      if id > 0 then out[#out + 1] = { w = w, h = h, sprite = id } end
    end
  end
  return out
end

-- the fullest frame (most non-empty tiles; the earliest of equals after the first quarter): the list icon's frame
function P.bestPhase(info)
  local phases = math.max(1, num(info and info.phases))
  local best, bestN = 0, -1
  local from = math.floor(phases / 4)
  for i = 0, phases - 1 do
    local a = (from + i) % phases
    local c = #P.frameTiles(info, a)
    if c > bestN then best, bestN = a, c end
  end
  return best
end

-- the box of a frame's non-empty tiles in tiles from the thing's top-left: x0, y0, x1, y1 (inclusive); nil if empty
function P.tileBox(info, phase)
  local W, H = math.max(1, num(info.w)), math.max(1, num(info.h))
  local x0, y0, x1, y1
  for _, t in ipairs(P.frameTiles(info, phase)) do
    local cx, cy = W - 1 - t.w, H - 1 - t.h
    x0 = x0 and math.min(x0, cx) or cx
    y0 = y0 and math.min(y0, cy) or cy
    x1 = x1 and math.max(x1, cx) or cx
    y1 = y1 and math.max(y1, cy) or cy
  end
  if not x0 then return nil end
  return x0, y0, x1, y1
end

-- the list icon of an effect drawn from its tiles (no generated picture): the best frame's tile box fitted into
-- size x size px. Returns {scale, tiles = {{x, y, sprite}}} with x, y the tile's pixel place, or nil
function P.iconLayout(info, size)
  if type(info) ~= 'table' then return nil end
  local phase = P.bestPhase(info)
  local x0, y0, x1, y1 = P.tileBox(info, phase)
  if not x0 then return nil end
  local cols, rows = x1 - x0 + 1, y1 - y0 + 1
  local t = size / math.max(cols, rows)
  local ox = math.floor((size - cols * t) / 2 + 0.5)
  local oy = math.floor((size - rows * t) / 2 + 0.5)
  local W, H = math.max(1, num(info.w)), math.max(1, num(info.h))
  local out = { tile = t, phase = phase, tiles = {} }
  for _, tl in ipairs(P.frameTiles(info, phase)) do
    local cx, cy = W - 1 - tl.w, H - 1 - tl.h
    out.tiles[#out.tiles + 1] = { x = ox + math.floor((cx - x0) * t + 0.5), y = oy + math.floor((cy - y0) * t + 0.5),
      sprite = tl.sprite }
  end
  return out
end

-- the row's main effect (its list icon): the longest non-missile skin effect, else the first one
function P.mainEffect(play)
  local best
  for _, step in ipairs(type(play) == 'table' and play or {}) do
    local b = type(step) == 'table' and step.b
    if type(b) == 'table' and not b.m and (not best or num(b.ms) > num(best.ms)) then best = b end
  end
  if best then return best end
  local first = type(play) == 'table' and play[1]
  return type(first) == 'table' and first.b or nil
end

-- ---------------------------------------------------------------- the loop
function P.fxDuration(spec, phases)
  if type(spec) ~= 'table' then return 0 end
  if spec.m then return P.MISSILE_MS end
  if num(spec.ms) > 0 then return num(spec.ms) end
  return math.max(1, num(phases)) * P.FRAME_MS
end

-- the timeline of a row's steps: side 'b' (the skin) or 'a' (the stock effects); 'both': every stock effect, then
-- every skin effect (the "compare" toggle). phasesOf(spec) -> frames. scene (P.sceneOf, optional): each item gets
-- `at` (P.landsOn); a kill scene starts the effects after P.KILL_LEAD (`lead`, the troll standing). Returns
-- {items = {{spec, start, dur, side, step, at}}, total, lead}; empty play: no items, total 0
function P.timeline(play, side, phasesOf, scene)
  local lead = (type(scene) == 'table' and scene.kill) and P.KILL_LEAD or 0
  local items, t = {}, lead
  local missile = hasMissile(play)
  local sides = side == 'both' and { 'a', 'b' } or { side or 'b' }
  for _, sd in ipairs(sides) do
    for i, step in ipairs(type(play) == 'table' and play or {}) do
      local spec = type(step) == 'table' and step[sd]
      if type(spec) == 'table' and num(spec.id) > 0 then
        local dur = P.fxDuration(spec, phasesOf and phasesOf(spec) or 1)
        items[#items + 1] = { spec = spec, start = t, dur = dur, side = sd, step = i,
          at = P.landsOn(spec, missile, scene) }
        t = t + dur + P.FX_GAP
      end
    end
  end
  if #items == 0 then return { items = items, total = 0, lead = 0 } end
  return { items = items, total = t - P.FX_GAP + P.FX_PAUSE, lead = lead }
end

-- what plays at `ms` into the loop: {{item, local = ms into it, frac = 0..1}}
function P.activeAt(tl, ms)
  local out = {}
  if type(tl) ~= 'table' or num(tl.total) <= 0 then return out end
  local t = num(ms) % tl.total
  for _, it in ipairs(tl.items) do
    if t >= it.start and t < it.start + it.dur then
      local l = t - it.start
      out[#out + 1] = { item = it, ms = l, frac = it.dur > 0 and l / it.dur or 1 }
    end
  end
  return out
end

-- the frame of an effect `ms` into it (Effect::draw without enhanced timings: one frame per dur / phases, the last
-- held)
function P.phaseAt(ms, dur, phases)
  phases = math.max(1, num(phases))
  if num(dur) <= 0 then return 0 end
  return math.max(0, math.min(phases - 1, math.floor(num(ms) * phases / dur)))
end

-- the direction pattern of a missile flying (dx, dy) tiles (Missile::setPath with the 8 sectors of
-- Position::getDirectionFromPositions, the patterns of Effect::setDirection): x, y in 0..2
function P.missilePattern(dx, dy)
  if dx == 0 and dy == 0 then return 1, 1 end
  local angle = math.atan2 and math.atan2(-dy, dx) or math.atan(-dy, dx)
  local deg = angle * 180 / math.pi
  if deg < 0 then deg = deg + 360 end
  local sector = math.floor((deg + 22.5) / 45) % 8 -- 0 E, 1 NE, 2 N, 3 NW, 4 W, 5 SW, 6 S, 7 SE
  local pat = { [0] = { 2, 1 }, { 2, 0 }, { 1, 0 }, { 0, 0 }, { 0, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } }
  return pat[sector][1], pat[sector][2]
end

-- where a playing item's thing goes, in tiles from the stage's tile (0, 0) (the top-left of the caster's tile, or the
-- target's in a kill scene): ox, oy (fractions for a missile in flight) and the pattern x, y. scene (P.sceneOf;
-- nil: one creature on (0, 0)): a missile flies from the caster to the target (with no caster, from P.MISSILE_FROM
-- tiles away), an effect plays on the tile its item's `at` names, moved by the spec's own offset (dx, dy).
function P.itemPlace(active, scene)
  local spec, at = active.item.spec, active.item.at
  local t = type(scene) == 'table' and scene.target or { x = 0, y = 0 }
  local c = type(scene) == 'table' and scene.caster or nil
  if spec.m then
    local fx, fy
    if c and (c.x ~= t.x or c.y ~= t.y) then fx, fy = c.x, c.y
    else fx, fy = t.x + P.MISSILE_FROM[1], t.y + P.MISSILE_FROM[2] end
    local px, py = P.missilePattern(t.x - fx, t.y - fy)
    local f = math.min(1, math.max(0, active.frac))
    return num(spec.dx) + fx + (t.x - fx) * f, num(spec.dy) + fy + (t.y - fy) * f, px, py
  end
  local a = (at == 'caster' and c) or t
  return num(spec.dx) + a.x, num(spec.dy) + a.y, 0, 0
end

-- The part of the stage the scene covers, in tiles from the stage's tile (fractions; x1, y1 exclusive): each creature
-- by its drawn box (boxes.caster / boxes.target: P.lookBox's, sprite px; default the stock look's) and every step's
-- thing (its tiles from the tile it plays on, displacement applied; a missile at both ends of its flight).
-- sizeOf(spec) -> w, h [, dispX, dispY] of its thing. scene nil: one creature on (0, 0), missiles from P.MISSILE_FROM.
function P.fxExtent(play, sizeOf, scene, boxes)
  scene = type(scene) == 'table' and scene or { target = { x = 0, y = 0 } }
  boxes = type(boxes) == 'table' and boxes or {}
  local x0, y0, x1, y1
  local function add(l, t, r, b)
    x0 = x0 and math.min(x0, l) or l
    y0 = y0 and math.min(y0, t) or t
    x1 = x1 and math.max(x1, r) or r
    y1 = y1 and math.max(y1, b) or b
  end
  for _, who in ipairs({ 'caster', 'target' }) do
    local pos = scene[who]
    if pos then
      local b = boxes[who] or P.FALLBACK_BOX
      add(pos.x + b.left / 32, pos.y + b.top / 32, pos.x + b.right / 32, pos.y + b.bottom / 32)
    end
  end
  local missile = hasMissile(play)
  for _, step in ipairs(type(play) == 'table' and play or {}) do
    for _, sd in ipairs({ 'a', 'b' }) do
      local spec = type(step) == 'table' and step[sd]
      if type(spec) == 'table' then
        local w, h, ddx, ddy = 1, 1, 0, 0
        if sizeOf then w, h, ddx, ddy = sizeOf(spec) end
        w, h, ddx, ddy = math.max(1, num(w)), math.max(1, num(h)), signed(ddx) / 32, signed(ddy) / 32
        local item = { item = { spec = spec, at = P.landsOn(spec, missile, scene) }, frac = 0 }
        local ends = spec.m and { 0, 1 } or { 0 }
        for _, f in ipairs(ends) do
          item.frac = f
          local ax, ay = P.itemPlace(item, scene)
          add(ax - (w - 1) - ddx, ay - (h - 1) - ddy, ax + 1 - ddx, ay + 1 - ddy)
        end
      end
    end
  end
  return x0, y0, x1, y1
end

-- the stage layout with effects: the largest of P.FX_SCALES at which the scene's extent fits the stage, the extent
-- centred. Returns scale, T, tileX, tileY (the stage tile's top-left px) and the UICreature rect of a creature on
-- that tile (x, y, size: its own tile is the lower right quarter of a 2T square; P.creatureRect for another tile).
-- Every creature keeps its feet on its tile, as the map draws it.
function P.fxLayout(w, h, x0, y0, x1, y1)
  local cols, rows = math.max(0.5, x1 - x0), math.max(0.5, y1 - y0)
  local s = P.FX_SCALES[#P.FX_SCALES]
  for _, sc in ipairs(P.FX_SCALES) do
    if cols * 32 * sc <= w and rows * 32 * sc <= h then s = sc break end
  end
  local T = math.floor(32 * s + 0.5)
  local tileX = math.floor((w - cols * T) / 2 - x0 * T + 0.5)
  local tileY = math.floor((h - rows * T) / 2 - y0 * T + 0.5)
  return { scale = s, T = T, tileX = tileX, tileY = tileY, x = tileX - T, y = tileY - T, size = 2 * T,
    feetY = tileY + T }
end

-- the UICreature rect (x, y, size) of a creature standing on tile pos of the stage
function P.creatureRect(L, pos)
  pos = pos or { x = 0, y = 0 }
  return L.tileX + (pos.x - 1) * L.T, L.tileY + (pos.y - 1) * L.T, 2 * L.T
end

-- the pixel place of tile (w, h) of a thing drawn on the tile at (ox, oy) tiles from the creature tile
function P.tilePixel(L, ox, oy, w, h, dispX, dispY)
  local s = L.T / 32
  return math.floor(L.tileX + (ox - w) * L.T - num(dispX) * s + 0.5), math.floor(L.tileY + (oy - h) * L.T - num(dispY) * s + 0.5)
end

-- ---------------------------------------------------------------- footprints on the stage
-- a few prints behind a character walking east: {x, y (tile fractions from the creature tile), rotation, opacity},
-- the newest first, alternating feet
P.STEPS = 4
function P.footsteps(n)
  local out = {}
  for i = 1, n or P.STEPS do
    out[#out + 1] = { x = -0.5 * i, y = (i % 2 == 0) and 0.1 or -0.1, rotation = 90, opacity = math.max(0.15, 1 - 0.22 * (i - 1)) }
  end
  return out
end

-- the option of a Cosmetics row for the stage: {kind = 'effects', play} for a row with effects
function P.fromPlayRow(r)
  if type(r) ~= 'table' or type(r.play) ~= 'table' or #r.play == 0 then return nil end
  return { kind = 'effects', play = r.play, killfx = r.kind == 'killfx' or nil }
end

return P
