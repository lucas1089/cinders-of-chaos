-- luajit client/overlay/modules/game_lookpreview/lookpreview_core_test.lua (and lua5.3), from the repo root
dofile('client/overlay/modules/game_lookpreview/lookpreview_core.lua')
dofile('client/overlay/modules/client_chaos_charselect/charselect_core.lua')
local P = LookPreviewCore
local C = CharSelectCore

local n = 0
local function eq(a, b, m)
  n = n + 1
  if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end

local own = { type = 2161, head = 10, body = 20, legs = 30, feet = 40, addons = 3, mount = 0, wings = 5, aura = 0,
  shader = 'chaos_ember_glow' }

-- bases
local b = P.base('own', own)
eq(b.type, 2161, 'own look') eq(b.wings, 5, 'own wings kept') eq(b.shader, 'chaos_ember_glow', 'own shader')
b.type = 1
eq(own.type, 2161, 'the base is a copy')
local s = P.base('simple', own)
eq(s.type, P.NEUTRAL.type, 'simple look') eq(s.addons, 0, 'no addons') eq(s.wings, nil, 'no wings') eq(s.shader, '', 'no shader')
eq(P.base('own', nil).type, P.NEUTRAL.type, 'no player: the plain figure')
eq(P.base('own', { type = 0 }).type, P.NEUTRAL.type, 'an empty outfit: the plain figure')

-- compose
local o, line, note = P.compose('own', own, { kind = 'wings', look = 7 })
eq(o.wings, 7, 'wings') eq(o.type, 2161, 'on the own look') eq(line, nil, 'no outline') eq(note, nil, 'no note')
o = P.compose('simple', own, { kind = 'aura', look = 9 })
eq(o.aura, 9, 'aura') eq(o.type, 128, 'on the plain figure') eq(o.wings, nil, 'own wings not on the plain figure')
o = P.compose('own', own, { kind = 'mount', look = 368 })
eq(o.mount, 368, 'mount')
o = P.compose('own', own, { kind = 'shader', shader = 'chaos_frost_rime' })
eq(o.shader, 'chaos_frost_rime', 'shader')
o = P.compose('own', own, { kind = 'shader' })
eq(o.shader, '', 'no shader')
o = P.compose('own', own, { kind = 'outfit', look = 2170, addons = 1 })
eq(o.type, 2170, 'outfit') eq(o.addons, 1, 'its addons') eq(o.head, 10, 'own colours kept')
o = P.compose('simple', own, { kind = 'addons', look = 2170 })
eq(o.type, 2170, 'addons look') eq(o.addons, 3, 'all addons') eq(o.head, P.NEUTRAL.head, 'grey on the plain figure')
o, line = P.compose('own', own, { kind = 'outline', art = 'ember', pulse = true })
eq(o.type, 2161, 'outline keeps the look') eq(line.art, 'ember', 'outline art') eq(line.pulse, true, 'pulse')
o, line = P.compose('own', own, { kind = 'outline', art = '' })
eq(line, nil, 'no art, no outline')
o = P.compose('simple', own, { kind = 'subject', look = 294 })
eq(o.type, 294, 'a pet alone') eq(o.wings, nil, 'nothing else')
local whole = { type = 2175, head = 1, mount = 400, wings = 3, aura = 4, shader = 'x' }
o = P.compose('own', own, { kind = 'look', outfit = whole })
eq(o.type, 2175, 'whole outfit') eq(o.mount, 400, 'its mount')
o = P.compose('simple', own, { kind = 'look', outfit = whole })
eq(o.type, 128, 'plain figure') eq(o.mount, 400, 'with its mount') eq(o.aura, 4, 'aura') eq(o.shader, 'x', 'shader')
o = P.compose('own', own, nil)
eq(o.type, 2161, 'nothing picked: as worn')
o, line, note = P.compose('own', own, { kind = 'footprint' })
eq(note, P.UNSHOWN.footprint, 'footprints get a note') eq(o.type, 2161, 'and the character')
o, line, note = P.compose('own', own, { kind = 'shader', shader = 'nope' }, function(name) return name ~= 'nope' end)
eq(o.shader, '', 'an unknown shader is left off') eq(note, P.UNKNOWN_SHADER, 'and said')
o, line, note = P.compose('own', own, { kind = 'wings', look = 2 }, function() return true end)
eq(o.shader, 'chaos_ember_glow', 'a known shader stays') eq(note, nil, 'no note')
eq(P.showable({ kind = 'footprint' }), false, 'footprints are not drawn on a creature')
eq(P.showable({ kind = 'wings' }), true, 'wings are') eq(P.showable(nil), true, 'nothing is')
eq(P.hasWearer({ kind = 'subject' }), false, 'a pet has no wearer') eq(P.hasWearer({ kind = 'aura' }), true, 'aura')

-- every note is a tr() key of pt_br.lua (run-time keys)
local f = assert(io.open('client/overlay/modules/client_chaos_locale/pt_br.lua', 'rb'))
local pt = f:read('*a') f:close()
local notes = { unknownShader = P.UNKNOWN_SHADER, noOutline = P.NO_OUTLINE }
for k, text in pairs(P.UNSHOWN) do notes[k] = text end
for k, text in pairs(notes) do
  local quoted = '["' .. text .. '"]'
  eq(pt:find(quoted, 1, true) ~= nil, true, 'pt-BR for the note of ' .. k)
end

-- store offers (server shop.lua clientOffer)
local opt = P.fromShopOffer({ type = 'outfit', kind = 'mount', outfit = { type = 1236 } })
eq(opt.kind, 'mount', 'mount by kind') eq(opt.look, 1236, 'mount id')
opt = P.fromShopOffer({ type = 'outfit', outfit = { type = 128, wings = 12, head = 1 } })
eq(opt.kind, 'wings', 'wings by field') eq(opt.look, 12, 'wings id')
opt = P.fromShopOffer({ type = 'outfit', outfit = { type = 128, aura = 33, head = 1 } })
eq(opt.kind, 'aura', 'aura by field')
opt = P.fromShopOffer({ type = 'outfit', outfit = { type = 128, shader = 'red_energizer', head = 1 } })
eq(opt.kind, 'shader', 'shader by field') eq(opt.shader, 'red_energizer', 'shader name')
opt = P.fromShopOffer({ type = 'outfit', outfit = { type = 909, head = 2, addons = 3 } })
eq(opt.kind, 'outfit', 'coloured look') eq(opt.addons, 3, 'addons')
opt = P.fromShopOffer({ type = 'outfit', outfit = { type = 294 } })
eq(opt.kind, 'subject', 'a bare look is drawn alone')
opt = P.fromShopOffer({ type = 'outfit', kind = 'addons', outfit = { type = 129, head = 1, addons = 3 } })
eq(opt.kind, 'addons', 'addons by kind')
eq(P.fromShopOffer({ type = 'item', item = 2160 }), nil, 'items have no look')

-- Cosmetics rows
opt = P.fromCosmeticRow({ kind = 'outline', id = 4, art = 'storm', pulse = true })
eq(opt.kind, 'outline', 'outline row') eq(opt.pulse, true, 'pulse')
eq(P.fromCosmeticRow({ kind = 'outline', id = 0 }), nil, 'the Default row: no outline')
eq(P.fromCosmeticRow({ kind = 'footprint', id = 2, art = 'ash' }).kind, 'footprint', 'footprint row')
eq(P.fromCosmeticRow({ kind = 'spellskin', id = 2 }), nil, 'spell skins are not on the character')
opt = P.fromCosmeticRow({ collection = true, kind = 'wings', look = 2140 })
eq(opt.kind, 'wings', 'collection wings') eq(opt.look, 2140, 'id')
opt = P.fromCosmeticRow({ collection = true, kind = 'addons', look = 2130 })
eq(opt.kind, 'outfit', 'collection addons') eq(opt.addons, 3, 'all addons')
opt = P.fromCosmeticRow({ collection = true, kind = 'shader', shader = 'ember_pixent' })
eq(opt.shader, 'ember_pixent', 'collection shader')
eq(P.fromCosmeticRow({ collection = true, kind = 'item', item = 3 }), nil, 'an item')

-- Outfit window buttons
eq(P.fromOutfitButton('outfitCheck', { type = 130, addons = 2 }).look, 130, 'outfit button')
eq(P.fromOutfitButton('mountCheck', { type = 368 }).kind, 'mount', 'mount button')
eq(P.fromOutfitButton('shaderCheck', { type = 1, shader = 'x' }).shader, 'x', 'shader button')
eq(P.fromOutfitButton('auraCheck', { type = 1, aura = 44 }).look, 44, 'aura button')
eq(P.fromOutfitButton('familiarCheck', { type = 1 }), nil, 'familiars: no option')

-- the Outfit window's state
local shown = { type = 130, addons = 1, mount = 0, aura = 7 }
local ownO, optO, last = P.outfitWindowState('outfitCheck', shown, nil, nil)
eq(ownO, shown, 'outfit row: the shown look') eq(optO.kind, 'outfit', 'as an outfit') eq(last, shown, 'remembered')
ownO, optO, last = P.outfitWindowState('mountCheck', { type = 368 }, { type = 400 }, shown)
eq(ownO, shown, 'mount row: the remembered look rides') eq(optO.look, 400, 'the focused mount') eq(last, shown, 'kept')
ownO, optO = P.outfitWindowState('mountCheck', { type = 368 }, nil, { type = 130, mount = 368 })
eq(optO.look, 368, 'no focused button: the worn mount')
ownO, optO = P.outfitWindowState('auraCheck', shown, nil, nil)
eq(optO.kind, 'look', 'aura row: the whole outfit') eq(optO.outfit.aura, 7, 'with its aura')
eq(P.outfitWindowState('outfitCheck', nil, nil, shown), shown, 'nothing shown: the remembered look')

-- keys
eq(P.key({ type = 1, shader = 'a' }) == P.key({ type = 1, shader = 'a' }), true, 'same key')
eq(P.key({ type = 1 }) == P.key({ type = 1, wings = 2 }), false, 'wings change the key')

-- turning
eq(P.turn(2, 1), 3, 'south -> west') eq(P.turn(3, 1), 0, 'west -> north') eq(P.turn(0, -1), 3, 'north <- west')
eq(P.turn(1, -5), 0, 'many steps')

-- the list cards' figure
dofile('client/overlay/modules/client_chaos_charselect/outfit_anchors.lua')
local small = C.figure(CharSelectAnchors or {}, { type = 128 })
local big = { fx = 0, fy = 20, top = -60, left = -32, right = 32 }
eq(P.fitFigure(P.FALLBACK, true).top, P.FALLBACK.top - P.RIDER, 'a rider above the mount')
eq(P.fitFigure(nil, false).fy, P.FALLBACK.fy, 'fallback figure')

-- ---------------------------------------------------------------- the box of a look, always 2x and centred
local function anchors(id) return P.anchorFrom(CharSelectAnchors[id]) end
-- the dat of pair 30 (things-1098, dat 8156792438dabee3aa768663d57a1619): size and displacement, no sprites
local DAT = { [128] = { w = 2, h = 2, dx = 8, dy = 8, pz = 2 }, [1221] = { w = 2, h = 2, dx = 8, dy = 8, pz = 2 },
  [1213] = { w = 2, h = 2, dx = 3, dy = 3, pz = 2 }, [1338] = { w = 3, h = 3, pz = 1 },
  [2163] = { w = 2, h = 2, dx = 8, dy = 8, pz = 1 }, [937] = { w = 2, h = 2, pz = 1 },
  [1561] = { w = 3, h = 4, dx = 65504, dy = 65504, pz = 2 } }
local function info(id) return DAT[id] end
eq(P.signed(65504), -32, 'a negative displacement as the engine reads it') eq(P.signed(8), 8, 'positive')
-- Prince of Lands (1221): the anchors' pixel bounds, bottom from its frame. The old layout put its feet (x 17), not
-- its picture (x -12..24, centre 6), under the middle and drew it at 4x: 11 sprite px (44 px) left and cut.
local pb = P.lookBox({ type = 1221, addons = 3 }, anchors, info, 6)
eq(pb.left .. ',' .. pb.top .. ',' .. pb.right .. ',' .. pb.bottom, '-12,-12,24,24', 'Prince of Lands box')
for _, look in ipairs({ { type = 1221, addons = 3 }, { type = 1213, addons = 3 }, { type = 128 }, { type = 128, mount = 1338 },
    { type = 9999 }, { type = 128, wings = 937 } }) do
  local bx = P.lookBox(look, anchors, info, 6)
  local Lb = P.layout(bx, 200, 300)
  eq(Lb.scale, 2, 'every look at 2x: ' .. look.type) eq(Lb.size, 128, 'creature rect 2T')
  local cx = Lb.x + ((bx.left + bx.right) / 2 + 32) * Lb.scale
  local cy = Lb.y + ((bx.top + bx.bottom) / 2 + 32) * Lb.scale
  eq(math.abs(cx - 100) <= 1 and math.abs(cy - 150) <= 1, true, 'the drawn box centred: ' .. look.type .. ' ' .. cx .. ',' .. cy)
end
-- Astral Fire (1213): its anchors (wide: a torch held out left)
local ab = P.lookBox({ type = 1213, addons = 3 }, anchors, info, 6)
eq(ab.left .. ',' .. ab.right, '-35,23', 'Astral Fire box')
-- a look the anchors do not know: from its sprite tiles. A 2x2 look with 8,8 whose art is in the bottom-right tile
-- only (yPattern 0) and its addon 1 (yPattern 1) also in the top-right tile: sprites in ThingType order
local tiles = { w = 2, h = 2, dx = 8, dy = 8, layers = 1, px = 1, py = 2, pz = 1, phases = 1,
  sprites = { 5, 0, 0, 0,   6, 0, 7, 0 } }
local tb = P.thingBox(tiles, 0, 0)
eq(tb.left .. ',' .. tb.top .. ',' .. tb.right .. ',' .. tb.bottom, '-8,-8,24,24', 'tiles: the bottom-right tile')
tb = P.thingBox(tiles, 0, 1)
eq(tb.top, -40, 'with addon 1 the tile above counts') eq(tb.left, -8, 'not the empty left column')
tb = P.thingBox({ w = 2, h = 2, dx = 8, dy = 8 }, 0, 0)
eq(tb.left .. ',' .. tb.top, '-40,-40', 'no sprites: the whole frame')
eq(P.thingBox(nil), nil, 'no info')
-- a two-layer aura (a pair 33 head accessory: layer 0 behind, layer 1 in front): the front layer's tiles count too
local head = { w = 2, h = 2, dx = 24, dy = 24, layers = 2, px = 4, py = 1, pz = 1, phases = 1, sprites = {} }
for i = 1, 32 do head.sprites[i] = 0 end
-- south (x 2): layer 0 only in the bottom-right tile, layer 1 in the top-left tile
head.sprites[17] = 11 -- ((x 2 * 2 layers + 0) * 2 + hh 0) * 2 + ww 0, 1-based
head.sprites[24] = 12 -- ((x 2 * 2 layers + 1) * 2 + hh 1) * 2 + ww 1, 1-based
tb = P.thingBox(head, 0, 0)
eq(tb.left .. ',' .. tb.top, '-24,-24', 'layer 0 only: the bottom-right tile')
tb = P.thingBox(head, 0, 0, true)
eq(tb.left .. ',' .. tb.top .. ',' .. tb.right .. ',' .. tb.bottom, '-56,-56,8,8', 'every layer: the front tile too')
local hb = P.lookBox({ type = 128, aura = 2477 }, function(id) return id == 2477 and { fx = 0, fy = 0, top = -20,
  left = -20, right = -10 } or anchors(id) end, function(id) return id == 2477 and head or info(id) end, 0)
eq(hb.left <= -56 + 16 and hb.top <= -56 + 16, true, 'a two-layer aura: its tiles (both layers), centred (w-1)*16')
local nb = P.lookBox({ type = 3000 }, function() return nil end, function() return tiles end, 0)
eq(nb.left .. ',' .. nb.right, '-8,24', 'no anchor: the tiles') eq(nb.fy, 19, 'feet a little above the bottom')
eq(P.lookBox({ type = 3000 }, nil, nil, 0).left, P.FALLBACK_BOX.left, 'nothing known: the stock look')
-- the anchors count every addon: without addons the worn tiles cut the box down (stock 128: -13,-22 -> -8,-8)
local cut = P.lookBox({ type = 3000, addons = 0 }, function() return anchors(128) end, function() return tiles end, 0)
eq(cut.left .. ',' .. cut.top .. ',' .. cut.right, '-8,-8,24', 'addons not worn: cut to the tiles')
cut = P.lookBox({ type = 3000, addons = 1 }, function() return anchors(128) end, function() return tiles end, 0)
eq(cut.top, anchors(128).top, 'addon 1 worn: the anchors\' top')
-- wings: the body 6 px up and left of the wings (GameWingOffset), both in the box
local wb = P.lookBox({ type = 128, wings = 937 }, anchors, info, 6)
local w937 = anchors(937)
eq(wb.left, math.min(w937.left, -8 - 6), 'wings reach left') eq(wb.fx, anchors(128).fx - 6, 'feet lifted with the body')
-- a mount: its own box and the rider seated on it
local mb = P.lookBox({ type = 128, mount = 1338 }, anchors, info, 0)
local m1338 = anchors(1338)
eq(mb.left .. ',' .. mb.top, m1338.left .. ',' .. m1338.top, 'the big mount holds the rider')
eq(mb.fy, m1338.fy, 'feet: the mount\'s')
-- a rider without the mounted pattern: the engine draws no mount, the box is the standing look
local rb = P.lookBox({ type = 2163, mount = 1338 }, anchors, info, 0)
eq(rb.top > m1338.top, true, 'no mount drawn under a look without the mounted pattern')
-- a mount with a negative displacement: drawn by its own displacement only (no extra shift)
local nm = P.lookBox({ type = 128, mount = 1561 }, function() return nil end, info, 0)
local t1561 = P.thingBox(DAT[1561], 0, 0)
eq(nm.left, math.min(t1561.left, -40), 'negative mount: no extra shift')
-- the shadow under the feet: centred on them, wider for a mount
local Ls = P.layout(pb, 200, 300)
local sx, sy, sw, sh = P.shadowRect(Ls, pb)
eq(sx + sw / 2 - Ls.feetX <= 1, true, 'shadow centred on the feet') eq(sw, P.SHADOW_MIN * 2 + 0, 'a person: the small shadow')
local _, _, mw = P.shadowRect(P.layout(mb, 200, 300), mb)
eq(mw > sw, true, 'a mount: a wider shadow')

-- a rider without the mounted pattern rides as the plain figure (the note says why)
o, line, note = P.compose('own', { type = 2163, head = 3, addons = 3 }, { kind = 'mount', look = 1338 }, nil,
  function(t) return t ~= 2163 end)
eq(o.type, P.NEUTRAL.type, 'plain figure rides') eq(o.mount, 1338, 'the mount kept') eq(o.head, 3, 'own colours')
eq(note, P.NO_RIDE, 'and the note')
o, line, note = P.compose('own', own, { kind = 'mount', look = 1338 }, nil, function() return true end)
eq(o.type, 2161, 'a look that can ride keeps its look') eq(note, nil, 'no note')
o = P.compose('own', { type = 2163 }, { kind = 'wings', look = 937 }, nil, function() return false end)
eq(o.type, 2163, 'no mount: the look is kept')

-- the fallback figure stands on the same feet as the character select's fallback for a 2x2 look
local fb = C.anchorOf(nil, 1, { w = 2, h = 2, dx = 8, dy = 8 })
eq(P.FALLBACK.fx, fb.fx, 'fallback feet x as charselect') eq(P.FALLBACK.fy, fb.fy, 'fallback feet y as charselect')
eq(C.NUDGE_X, 0, 'no nudge: the panel and the select both stand the feet on the point')

-- placement agrees with the character select
for _, fig in ipairs({ P.FALLBACK, big, small }) do
  local x1, y1, s1 = P.placeRect(fig, 128, 92, 200)
  local x2, y2, s2 = C.placeRect(fig, 128, 92, 200)
  eq(x1, x2, 'x as charselect') eq(y1, y2, 'y as charselect') eq(s1, s2, 'size as charselect')
end
local L = P.layout(P.FALLBACK_BOX, 184, 300)
local fx, fy = C.feetOf(P.FALLBACK_BOX, L.x, L.y, L.size)
eq(math.abs(fx - L.feetX) <= 1, true, 'feet x where the layout says') eq(math.abs(fy - L.feetY) <= 1, true, 'feet y')
eq(L.y + (P.FALLBACK_BOX.top + 32) * L.scale >= 0, true, 'the head inside the stage')

-- docking
local fixes = P.dockFixes({ a = { x = 10, width = 50 }, b = { x = 300, width = 60 }, c = { x = 0, width = 400 },
  closeButton = { x = 380, width = 14 } }, { a = { x = 10, width = 50 }, b = { x = 500, width = 60 },
  c = { x = 0, width = 600 }, closeButton = { x = 580, width = 14 } })
eq(fixes.a, nil, 'left anchored: untouched') eq(fixes.b, 200, 'right anchored: moved back')
eq(fixes.c, 200, 'stretched: shrunk back') eq(fixes.closeButton, nil, 'title bar button stays at the edge')
eq(next(P.dockFixes({ a = { x = 1, width = 2 } }, { a = { x = 1, width = 2 } })), nil, 'nothing moved')

-- list cards
local card = P.cardLayout(P.FALLBACK, 108, 78)
eq(card.scale, 1.5, 'a player look fills a 108 x 78 card at 1.5x')
eq((P.FALLBACK.fy - P.FALLBACK.top) * card.scale <= 78, true, 'the body fits the height')
eq(card.size, 96, 'creature rect 2T')
local feetX = card.x + (P.FALLBACK.fx + 32) * card.scale
local midX = card.x + ((P.FALLBACK.left + P.FALLBACK.right) / 2 + 32) * card.scale
eq(math.abs(midX - 54) <= 1, true, 'the body is centred across the card: ' .. midX)
eq(feetX > 0, true, 'feet inside')
local big = P.cardLayout({ fx = 40, fy = 50, top = -60, left = -20, right = 80, hover = 0 }, 108, 78)
eq(big.scale, 1, 'a large mount falls back to 1x')

-- ---------------------------------------------------------------- the effect stage
o, line, note = P.compose('own', own, { kind = 'footprint', art = 'ash' })
eq(note, nil, 'a footprint with art: the stage draws it, no note')
eq(P.fromCosmeticRow({ kind = 'footprint', id = 2, art = 'ash' }).art, 'ash', 'footprint art')
-- a 2 x 2 effect of 3 frames, one layer, no patterns: sprites in ThingType order (phase, ..., h, w)
local info = { w = 2, h = 2, layers = 1, px = 1, py = 1, pz = 1, phases = 3, dispX = 8, dispY = 8,
  sprites = { 0, 0, 0, 11,   -- frame 0: only (w 1, h 1) = the top-left tile
              21, 22, 23, 24, -- frame 1: full
              31, 0, 0, 0 } }  -- frame 2: the bottom-right tile
eq(P.spriteAt(info, 1, 1, 0, 0, 0, 0, 0), 11, 'sprite index of frame 0, tile (1, 1)')
eq(P.spriteAt(info, 0, 0, 0, 0, 0, 0, 2), 31, 'frame 2 bottom-right')
eq(P.spriteAt(info, 0, 0, 0, 0, 0, 0, 4), 21, 'the phase wraps')
eq(#P.frameTiles(info, 0), 1, 'empty tiles skipped')
eq(#P.frameTiles(info, 1), 4, 'full frame')
eq(P.bestPhase(info), 1, 'the fullest frame is the icon')
local x0, y0, x1, y1 = P.tileBox(info, 0)
eq(x0 .. y0 .. x1 .. y1, '0000', 'frame 0: the top-left tile only')
x0, y0, x1, y1 = P.tileBox(info, 2)
eq(x0 .. y0 .. x1 .. y1, '1111', 'frame 2: the bottom-right tile only')
eq(P.tileBox({ w = 1, h = 1, phases = 1, sprites = { 0 } }, 0), nil, 'an empty frame has no box')
local icon = P.iconLayout(info, 32)
eq(icon.tile, 16, 'two tiles in 32 px: 16 px each')
eq(#icon.tiles, 4, 'every tile drawn')
local single = P.iconLayout({ w = 3, h = 3, layers = 1, px = 1, py = 1, pz = 1, phases = 1,
  sprites = { 0, 0, 0, 0, 7, 0, 0, 0, 0 } }, 32)
eq(single.tile, 32, 'a 3 x 3 effect with one used tile: that tile fills the icon (cropped)')
eq(single.tiles[1].x .. ',' .. single.tiles[1].y, '0,0', 'at the corner')
-- main effect: the longest non-missile skin effect
local play = { { a = { id = 388 }, b = { id = 406, ms = 840 } }, { a = { id = 524, ms = 600, dx = 1, dy = 1 }, b = { id = 526, ms = 900, dx = 1, dy = 1 } },
  { a = { id = 122, m = 1 }, b = { id = 121, m = 1 } } }
eq(P.mainEffect(play).id, 526, 'main effect')
eq(P.mainEffect({ { b = { id = 121, m = 1 } } }).id, 121, 'a missile when nothing else')
eq(P.mainEffect({}), nil, 'nothing to show')
-- the loop
eq(P.fxDuration({ id = 1, ms = 600 }, 12), 600, 'the server length')
eq(P.fxDuration({ id = 1 }, 12), 12 * P.FRAME_MS, 'frames x frame length')
eq(P.fxDuration({ id = 1, m = 1 }, 2), P.MISSILE_MS, 'missile flight')
local tl = P.timeline(play, 'b', function() return 10 end)
eq(#tl.items, 3, 'three skin steps')
eq(tl.items[2].start, 840 + P.FX_GAP, 'one after the other')
eq(tl.total, 840 + 900 + P.MISSILE_MS + 2 * P.FX_GAP + P.FX_PAUSE, 'loop length with the pause')
local both = P.timeline(play, 'both', function() return 10 end)
eq(#both.items, 6, 'compare: stock then skin')
eq(both.items[1].side .. both.items[4].side, 'ab', 'stock first')
eq(P.timeline({ { b = { id = 468 } } }, 'a').total, 0, 'a kill effect has no stock side')
eq(#P.activeAt(tl, 10), 1, 'the first step plays')
eq(P.activeAt(tl, 10)[1].item.spec.id, 406, 'its effect')
eq(#P.activeAt(tl, 840 + 10), 0, 'the gap')
eq(#P.activeAt(tl, tl.total - 10), 0, 'the pause')
eq(P.activeAt(tl, tl.total + 10)[1].item.spec.id, 406, 'loops')
eq(#P.activeAt({ items = {}, total = 0 }, 5), 0, 'nothing to play')
eq(P.phaseAt(0, 600, 12), 0, 'first frame') eq(P.phaseAt(599, 600, 12), 11, 'last frame')
eq(P.phaseAt(5000, 600, 12), 11, 'held') eq(P.phaseAt(10, 0, 12), 0, 'no length')
-- missiles
local px, py = P.missilePattern(2, 1)
eq(px .. py, '22', 'down-right: south-east pattern')
px, py = P.missilePattern(0, -3)
eq(px .. py, '10', 'up: north')
px, py = P.missilePattern(-1, 0)
eq(px .. py, '01', 'left: west')
local ax, ay = P.itemPlace({ item = { spec = { id = 121, m = 1 } }, frac = 0 })
eq(ax .. ',' .. ay, P.MISSILE_FROM[1] .. ',' .. P.MISSILE_FROM[2], 'a missile starts away')
ax, ay = P.itemPlace({ item = { spec = { id = 121, m = 1 } }, frac = 1 })
eq(ax .. ',' .. ay, '0,0', 'and lands on the creature')
ax, ay = P.itemPlace({ item = { spec = { id = 526, dx = 1, dy = 1 } }, frac = 0.5 })
eq(ax .. ',' .. ay, '1,1', 'an effect on its offset tile')
-- extent and layout (one creature on the tile, the stock look's box: -0.25..0.75 tiles)
local sizes = { [406] = { 1, 1 }, [388] = { 2, 2 }, [524] = { 4, 4 }, [526] = { 4, 4 }, [121] = { 1, 1 }, [122] = { 1, 1 } }
local function sizeOf(sp) return sizes[sp.id][1], sizes[sp.id][2] end
local ex0, ey0, ex1, ey1 = P.fxExtent(play, sizeOf)
eq(string.format('%g,%g,%g,%g', ex0, ey0, ex1, ey1), '-2,-2,2,2', 'a 4 x 4 effect at (1, 1) covers -2..2')
local FL = P.fxLayout(200, 240, ex0, ey0, ex1, ey1)
eq(FL.scale, 1.5, '4 tiles in 200 px: 1.5x')
eq(FL.T, 48, 'tile 48 px')
eq(FL.tileX, math.floor((200 - 4 * 48) / 2 + 2 * 48 + 0.5), 'creature tile column')
eq(FL.size, 96, 'creature rect 2T')
eq(FL.x, FL.tileX - 48, 'creature rect left')
local FL2 = P.fxLayout(188, 240, -0.25, -0.25, 0.75, 0.75)
eq(FL2.scale, P.SCALE, 'never larger than the look\'s own zoom')
eq(FL2.tileX - 0.25 * FL2.T, (188 - FL2.T) / 2, 'one creature: centred')
local tx, ty = P.tilePixel(FL, 1, 1, 3, 3, 8, 8)
eq(tx, FL.tileX + (1 - 3) * 48 - 12, 'tile x with displacement')
eq(ty, FL.tileY + (1 - 3) * 48 - 12, 'tile y with displacement')
local rx, ry, rs = P.creatureRect(FL, { x = 2, y = 0 })
eq(rx .. ',' .. ry .. ',' .. rs, (FL.tileX + 48) .. ',' .. (FL.tileY - 48) .. ',96', 'a creature two tiles east')

-- ---------------------------------------------------------------- the scenes
-- spell skins: the player on (0, 0) facing east, the troll two tiles east
local sc = P.sceneOf({ kind = 'effects', play = play })
eq(sc.kill, false, 'a spell scene') eq(sc.caster.x .. sc.target.x, '0' .. P.TARGET_AT, 'caster and target')
eq(P.hasWearer({ kind = 'effects', play = play }), true, 'a spell skin has its player')
eq(P.hasWearer({ kind = 'effects', play = play, killfx = true }), false, 'a kill effect is on the troll')
eq(P.landsOn({ id = 1, m = 1 }, true, sc), 'missile', 'a missile flies')
eq(P.landsOn({ id = 1, n = 'vfx_aura_burst_violet' }, false, sc), 'caster', 'a war cry around the player')
eq(P.landsOn({ id = 1, n = 'fx_chain_lightning' }, false, sc), 'target', 'lightning on the troll')
eq(P.landsOn({ id = 1, n = 'fx_summon_vortex' }, true, sc), 'target', 'with a missile: the impact on the troll')
eq(P.landsOn({ id = 1, n = 'vfx_aura_burst_violet' }, false, P.sceneOf({ killfx = true })), 'target', 'kill: on the troll')
local stl = P.timeline(play, 'b', function() return 10 end, sc)
eq(stl.lead, 0, 'a spell starts at once') eq(stl.items[1].at, 'target', 'a row with a missile: its effects on the troll')
eq(stl.items[3].at, 'missile', 'its missile')
-- the missile flies from the player to the troll, pattern east
local mx, my, mpx, mpy = P.itemPlace({ item = stl.items[3], frac = 0 }, sc)
eq(mx .. ',' .. my, '0,0', 'from the player') eq(mpx .. mpy, '21', 'east pattern')
mx, my = P.itemPlace({ item = stl.items[3], frac = 1 }, sc)
eq(mx .. ',' .. my, P.TARGET_AT .. ',0', 'to the troll')
mx, my = P.itemPlace({ item = { spec = { id = 526, dx = 1, dy = 1 }, at = 'target' }, frac = 0.5 }, sc)
eq(mx .. ',' .. my, (P.TARGET_AT + 1) .. ',1', 'an impact on the troll, with its offset')
mx, my = P.itemPlace({ item = { spec = { id = 5 }, at = 'caster' }, frac = 0.5 }, sc)
eq(mx .. ',' .. my, '0,0', 'a war cry on the player')
-- the extent holds both creatures; the scene is centred
local boxes = { caster = P.FALLBACK_BOX, target = P.FALLBACK_BOX }
local sx0, sy0, sx1, sy1 = P.fxExtent({ { b = { id = 121, m = 1 } } }, sizeOf, sc, boxes)
eq(string.format('%g,%g', sx0, sx1), string.format('-0.25,%g', P.TARGET_AT + 1), 'from the player to the troll (the missile\'s tile on it)')
local SL = P.fxLayout(240, 240, sx0, sy0, sx1, sy1)
local left = SL.tileX + sx0 * SL.T
local right = SL.tileX + sx1 * SL.T
eq(math.abs(left - (240 - right)) <= 1, true, 'the scene centred across the stage')
-- kill effects: the troll alone, standing, then fading with the effect, standing again on the next loop
local ks = P.sceneOf({ kind = 'effects', play = { { b = { id = 468 } } }, killfx = true })
eq(ks.kill, true, 'a kill scene') eq(ks.caster, nil, 'no player')
local ktl = P.timeline({ { b = { id = 468, ms = 800 } } }, 'b', nil, ks)
eq(ktl.lead, P.KILL_LEAD, 'the troll stands first') eq(ktl.items[1].start, P.KILL_LEAD, 'the effect after the lead')
eq(ktl.items[1].at, 'target', 'on the troll') eq(ktl.total, P.KILL_LEAD + 800 + P.FX_PAUSE, 'loop length')
eq(P.targetAlpha(ktl, 10), 1, 'standing') eq(P.targetAlpha(ktl, P.KILL_LEAD + P.FADE_MS / 2), 0.5, 'fading')
eq(P.targetAlpha(ktl, P.KILL_LEAD + 700), 0, 'gone') eq(P.targetAlpha(ktl, ktl.total + 5), 1, 'back on the next loop')
eq(P.targetAlpha(stl, 500), 1, 'a spell scene: the troll stays')
eq(#P.activeAt(ktl, 10), 0, 'nothing plays during the lead')
mx, my = P.itemPlace({ item = ktl.items[1], frac = 0 }, ks)
eq(mx .. ',' .. my, '0,0', 'the kill effect on the troll\'s tile')
-- footprints and rows
local steps = P.footsteps(4)
eq(#steps, 4, 'four prints')
eq(steps[1].opacity > steps[4].opacity, true, 'older prints fade')
eq(steps[2].x < steps[1].x, true, 'behind the walker')
eq(P.fromPlayRow({ kind = 'killfx', play = { { b = { id = 468 } } } }).killfx, true, 'kill effect row')
eq(P.fromPlayRow({ kind = 'spellskin', play = {} }), nil, 'nothing to play')
eq(P.fromPlayRow({ kind = 'rarefx', play = { { b = { id = 468 } } } }).killfx, true, 'rare-loot effect row: on a dying troll')
eq(P.fromPlayRow({ kind = 'levelfx', play = { { b = { id = 468 } } } }).killfx, nil, 'level-up effect row: on the figure')
eq(P.fromPlayRow({ kind = 'emote', play = { { b = { id = 468 } } } }).killfx, nil, 'emote row: on the figure')
eq(P.showable({ kind = 'effects' }), true, 'effects are shown')

-- store offers carry their own look (server shop_core.lua K.lookOf): every kind becomes an option
local function L(l) return P.fromShopOffer({ type = 'item', item = 2160, look = l }) end
opt = L({ kind = 'outline', art = 'radiant', pulse = true })
eq(opt.kind, 'outline', 'outline offer') eq(opt.art, 'radiant', 'its art') eq(opt.pulse, true, 'its pulse')
o, line = P.compose('own', own, opt)
eq(line.art, 'radiant', 'the outline reaches the engine call') eq(o.type, 2161, 'on the own look')
opt = L({ kind = 'shader', shader = 'chaos_void_flicker' })
o = P.compose('own', own, opt, function(nm) return nm == 'chaos_void_flicker' end)
eq(o.shader, 'chaos_void_flicker', 'shader unlock offer')
o, line, note = P.compose('own', own, opt, function() return false end)
eq(o.shader, '', 'an unknown shader is left off') eq(note, P.UNKNOWN_SHADER, 'and the note says why')
opt = L({ kind = 'mount', look = 1561 })
eq(opt.kind, 'mount', 'mount offer') o = P.compose('own', own, opt) eq(o.mount, 1561, 'mount under the character')
eq(L({ kind = 'wings', look = 12 }).kind, 'wings', 'wings offer') eq(L({ kind = 'aura', look = 3 }).look, 3, 'aura offer')
opt = L({ kind = 'outfit', look = 1211, addons = 3 })
eq(opt.kind, 'outfit', 'outfit offer') eq(opt.addons, 3, 'addons')
eq(L({ kind = 'addons', look = 129 }).addons, 3, 'addons offer: both')
eq(L({ kind = 'subject', look = 294 }).kind, 'subject', 'a pet')
opt = L({ kind = 'effects', play = { { b = { id = 5 } } }, killfx = true })
eq(opt.kind, 'effects', 'effects offer') eq(opt.killfx, true, 'kill effect')
eq(P.effectsOf(opt), opt, 'effects found')
opt = L({ kind = 'footprint', art = 'ash' })
eq(P.footprintArt(opt), 'ash', 'footprint art')
opt = L({ kind = 'nameplate', frame = 'frost' })
o, line, note = P.compose('own', own, opt)
eq(note, P.UNSHOWN.nameplate, 'a plate frame: the note') eq(o.type, 2161, 'the character as worn')
eq(L({ kind = 'swatch', color = '#ffffff' }), nil, 'a colour sample is nothing to wear')
eq(L({ kind = 'outline', art = '../x' }), nil, 'a bad art name is dropped')
eq(L({ kind = 'mount', look = 0 }), nil, 'a mount without a look')
eq(L({ kind = 'weird' }), nil, 'an unknown kind')
eq(P.fromShopOffer({ type = 'item', item = 1 }), nil, 'no look: no option')

-- a bundle: every part on the character
opt = L({ kind = 'bundle', parts = { { kind = 'outfit', look = 1211, addons = 3 }, { kind = 'mount', look = 1234 },
  { kind = 'wings', look = 22 }, { kind = 'aura', look = 33 }, { kind = 'shader', shader = 'blue_energizer' },
  { kind = 'outline', art = 'frost' }, { kind = 'swatch' } } })
eq(opt.kind, 'bundle', 'bundle offer') eq(#opt.parts, 6, 'the parts that can be worn (the swatch dropped)')
o, line, note = P.compose('own', own, opt)
eq(o.type, 1211, 'bundle outfit') eq(o.addons, 3, 'bundle addons') eq(o.mount, 1234, 'bundle mount')
eq(o.wings, 22, 'bundle wings') eq(o.aura, 33, 'bundle aura') eq(o.shader, 'blue_energizer', 'bundle shader')
eq(line.art, 'frost', 'bundle outline') eq(note, nil, 'no note')
o = P.compose('simple', own, opt)
eq(o.type, 1211, 'simple figure: the bundle outfit') eq(o.mount, 1234, 'and its mount')
opt = L({ kind = 'bundle', parts = { { kind = 'wings', look = 22 }, { kind = 'effects', play = { { b = { id = 9 } } } } } })
eq(P.effectsOf(opt).play[1].b.id, 9, 'a bundle part with effects reaches the stage')
o = P.compose('own', own, opt)
eq(o.wings, 22, 'an effect part leaves the figure alone') eq(o.type, 2161, 'own look')
eq(L({ kind = 'bundle', parts = { { kind = 'swatch' } } }), nil, 'a bundle with nothing to wear')
eq(L({ kind = 'bundle', parts = { { kind = 'bundle', parts = { { kind = 'mount', look = 5 } } } } }), nil, 'nested bundles are not followed')
eq(P.showable({ kind = 'bundle' }), true, 'bundles are shown')

print('lookpreview_core_test: ' .. n .. ' checks OK')
