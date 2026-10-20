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

-- does the 'simple' toggle mean anything for this option (a pet has no wearer)
function P.hasWearer(opt)
  return not (type(opt) == 'table' and opt.kind == 'subject')
end

P.UNKNOWN_SHADER = 'This shader is not in your client yet.'
P.NO_OUTLINE = 'Your client cannot draw outlines yet.' -- an engine without base patch 0038

-- What to draw: outfit, outline ({art, pulse} or nil) and a note (an unshown kind). The 'simple' figure keeps only
-- the option itself: for a whole outfit that is its extras (mount, wings, aura, shader) on the plain figure.
-- known(name): is the outfit shader registered in the client (the engine draws nothing for an unknown name, so it is
-- left off and the note says why)
function P.compose(mode, own, opt, known)
  local o, outline, note = P.composeRaw(mode, own, opt)
  if o.shader and o.shader ~= '' and known and not known(o.shader) then
    o.shader = ''
    note = note or P.UNKNOWN_SHADER
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
-- quarter (client_chaos_charselect/charselect_core.lua, "UICreature draws a creature ..."). The figure (fx, fy: the
-- feet; top, left, right: the reach) is CharSelectCore.figure's, from the sprite anchors of the pair: the centre of
-- the feet goes where the feet should stand (client/MANIFEST.md "Where a character stands"). P.FALLBACK, when that
-- module is absent: a 2x2 player look with displacement 8, its feet where CharSelectCore.FEET_FALLBACK puts them
-- (the test checks both agree), the bounds of stock look 128.
P.FALLBACK = { fx = 12, fy = 19, top = -22, left = -13, right = 24, hover = 0 }
P.SCALES = { 4, 3, 2 }
P.FILL = 0.78      -- the body takes at most this share of the stage's height
P.RIDER = 22       -- sprite pixels a rider reaches above its mount's top

-- the figure to fit: a mounted look by its mount's reach plus the rider
function P.fitFigure(fig, mounted)
  local f = copy(type(fig) == 'table' and fig or P.FALLBACK)
  if mounted then f.top = f.top - P.RIDER end
  return f
end

-- the zoom (2x to 4x) that puts the body (feet to its top, its width) inside the stage: the largest that fits, else 2x
function P.zoom(fig, w, h)
  fig = fig or P.FALLBACK
  local tall = math.max(1, fig.fy - fig.top)
  local wide = math.max(1, fig.right - fig.left)
  for _, s in ipairs(P.SCALES) do
    if tall * s <= h * P.FILL and wide * s <= w * 0.92 then return s end
  end
  return P.SCALES[#P.SCALES]
end

-- the UICreature rect (x, y, size) that puts the feet of fig at (cx, feetY) at tile size T (same maths as
-- CharSelectCore.placeRect; the test checks both agree)
function P.placeRect(fig, T, cx, feetY)
  local s = T / 32
  return math.floor(cx - (fig.fx + 32) * s + 0.5), math.floor(feetY - (fig.fy + 32) * s + 0.5), 2 * T
end

-- the whole layout for a stage of w x h: scale, rect. The body is centred: the feet under the middle, the space
-- between its top and the feet in the middle of the height.
function P.layout(fig, w, h)
  fig = fig or P.FALLBACK
  local s = P.zoom(fig, w, h)
  local T = 32 * s
  local tall = (fig.fy - fig.top) * s
  local feetY = math.floor((h + tall) / 2 + 0.5)
  local x, y, size = P.placeRect(fig, T, math.floor(w / 2), feetY)
  return { scale = s, x = x, y = y, size = size, feetY = feetY }
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
P.MISSILE_FROM = { -2, -1 } -- tiles from the target (the server's own preview sends from -3, -2; the stage is smaller)
P.FX_SCALES = { 4, 3, 2, 1.5, 1 }

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
-- every skin effect (the "compare" toggle). phasesOf(spec) -> frames. Returns {items = {{spec, start, dur, side,
-- step}}, total}; empty play: no items, total 0
function P.timeline(play, side, phasesOf)
  local items, t = {}, 0
  local sides = side == 'both' and { 'a', 'b' } or { side or 'b' }
  for _, sd in ipairs(sides) do
    for i, step in ipairs(type(play) == 'table' and play or {}) do
      local spec = type(step) == 'table' and step[sd]
      if type(spec) == 'table' and num(spec.id) > 0 then
        local dur = P.fxDuration(spec, phasesOf and phasesOf(spec) or 1)
        items[#items + 1] = { spec = spec, start = t, dur = dur, side = sd, step = i }
        t = t + dur + P.FX_GAP
      end
    end
  end
  if #items == 0 then return { items = items, total = 0 } end
  return { items = items, total = t - P.FX_GAP + P.FX_PAUSE }
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

-- where a playing item's thing goes, in tiles from the creature's tile (its bottom-right tile's top-left): ox, oy
-- (fractions for a missile in flight) and the pattern x, y
function P.itemPlace(active)
  local spec = active.item.spec
  if spec.m then
    local fx, fy = P.MISSILE_FROM[1], P.MISSILE_FROM[2]
    local px, py = P.missilePattern(-fx, -fy)
    local f = math.min(1, math.max(0, active.frac))
    return num(spec.dx) + fx * (1 - f), num(spec.dy) + fy * (1 - f), px, py
  end
  return num(spec.dx), num(spec.dy), 0, 0
end

-- the tiles every step of a row covers, from the creature's tile: minX, minY, maxX, maxY (the body's 2 x 2 included).
-- sizeOf(spec) -> w, h of its thing
function P.fxExtent(play, sizeOf)
  local x0, y0, x1, y1 = -1, -1, 0, 0
  local function add(ax, ay, w, h)
    x0, y0 = math.min(x0, ax - w + 1), math.min(y0, ay - h + 1)
    x1, y1 = math.max(x1, ax), math.max(y1, ay)
  end
  for _, step in ipairs(type(play) == 'table' and play or {}) do
    for _, sd in ipairs({ 'a', 'b' }) do
      local spec = type(step) == 'table' and step[sd]
      if type(spec) == 'table' then
        local w, h = 1, 1
        if sizeOf then w, h = sizeOf(spec) end
        w, h = math.max(1, num(w)), math.max(1, num(h))
        add(num(spec.dx), num(spec.dy), w, h)
        if spec.m then add(num(spec.dx) + P.MISSILE_FROM[1], num(spec.dy) + P.MISSILE_FROM[2], w, h) end
      end
    end
  end
  return x0, y0, x1, y1
end

-- the stage layout with effects: the largest of P.FX_SCALES at which the effects' tiles fit the stage (the body's
-- zoom at most), the box centred. Returns the same table as P.layout plus tileX, tileY (the creature tile's
-- top-left px) and T. The body keeps its feet on that tile, as the map draws it.
function P.fxLayout(fig, w, h, x0, y0, x1, y1)
  fig = fig or P.FALLBACK
  local cols, rows = x1 - x0 + 1, y1 - y0 + 1
  local bodyMax = P.zoom(fig, w, h)
  local s = P.FX_SCALES[#P.FX_SCALES]
  for _, sc in ipairs(P.FX_SCALES) do
    if sc <= bodyMax and cols * 32 * sc <= w and rows * 32 * sc <= h then s = sc break end
  end
  local T = math.floor(32 * s + 0.5)
  local left = math.floor((w - cols * T) / 2 + 0.5)
  local top = math.floor((h - rows * T) / 2 + 0.5)
  local tileX, tileY = left - x0 * T, top - y0 * T
  -- the UICreature rect: its own tile is the lower right quarter of a 2T square
  return { scale = s, T = T, tileX = tileX, tileY = tileY, x = tileX - T, y = tileY - T, size = 2 * T,
    feetY = tileY + T }
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
