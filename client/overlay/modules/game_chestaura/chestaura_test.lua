-- Run from the repo root: luajit client/overlay/modules/game_chestaura/chestaura_test.lua (and lua5.3)
-- Covers the pure rules (chestaura_logic.lua): the loop frame and its clip, the picture paths and the files the generator writes
-- (sizes of the strips), the floor and foot boxes, the range square (radius 4, 3, 5 and the passive tree's bonus: which tiles it covers,
-- the one widget that is sized and hosted for it), the visibility rules (party only, same floor, option), the server's message and the diffs.
local dir = arg[0]:match('^(.*)/[^/]*$') or '.'
dofile(dir .. '/chestaura_logic.lua')
local L = ChestAuraLogic

local fails, checks = 0, 0
local function eq(a, b, msg)
  checks = checks + 1
  if a ~= b then
    fails = fails + 1
    print('FAIL ' .. msg .. ': got ' .. tostring(a) .. ', want ' .. tostring(b))
  end
end

-- ---------------------------------------------------------------- the opcode and the option
eq(L.OPCODE, 118, 'opcode 118 (server ChaosOpcodes.templarAura)')
eq(L.optionOn(nil), true, 'option default on'); eq(L.optionOn(true), true, 'option true'); eq(L.optionOn(false), false, 'option false')
eq(L.optionOn('junk'), true, 'option junk is the default'); eq(L.optionOn(0), true, 'option number is the default')

-- ---------------------------------------------------------------- frames
eq(L.CHEST_FRAMES, 12, '12 frames a chest loop'); eq(L.FOOT_FRAMES, 24, '24 frames a foot turn'); eq(L.FOOT_FRAME_MS, 250, '250 ms a foot frame')
eq(L.frameIndex(0, 200, 12), 0, 'frame 0 at the start')
eq(L.frameIndex(199, 200, 12), 0, 'still frame 0 just before 200 ms'); eq(L.frameIndex(200, 200, 12), 1, 'frame 1 at 200 ms')
eq(L.frameIndex(2399, 200, 12), 11, 'the last frame'); eq(L.frameIndex(2400, 200, 12), 0, 'the loop wraps at 2.4 s')
eq(L.frameIndex(250 * 24 * 7 + 250 * 5, 250, 24), 5, 'foot frame after seven turns and five steps')
eq(L.frameIndex(123456789, 200, 12) >= 0 and L.frameIndex(123456789, 200, 12) < 12, true, 'always in range')
eq(L.frameIndex(nil, 200, 12), 0, 'nil time'); eq(L.frameIndex(100, 0, 12), 0, 'no frame length'); eq(L.frameIndex(100, 200, 0), 0, 'no frames')
eq(L.clip(0, 64), '0 0 64 64', 'clip of frame 0'); eq(L.clip(11, 64), '704 0 64 64', 'clip of frame 11 of a 64 px strip')
eq(L.clip(5, 128), '640 0 128 128', 'clip of a coffer frame'); eq(L.clip(23, 64), '1472 0 64 64', 'last foot frame')

-- ---------------------------------------------------------------- which chest, which picture
eq(L.chestOf(38758).art, 'reward_sigil', 'reward chest 38758'); eq(L.chestOf(38758).px, 64, 'one tile chest: 64 px')
eq(L.chestOf(38642).art, 'cursed_smoke', 'cursed chest 38642')
eq(L.chestOf(38657).art, 'coffer_smoke', 'the Sealed Coffer wears the big gold chest 38657')
eq(L.chestOf(38657).px, 128, 'the coffer aura is 128 px'); eq(L.chestOf(38657).big, true, 'the coffer is a 2 x 2 item')
eq(L.chestOf(38758).big, nil, 'the reward chest is one tile')
eq(L.chestOf(4073), nil, 'the old coffer look 4073 has no aura'); eq(L.chestOf(19250), nil, 'the stock reward chest has none'); eq(L.chestOf(nil), nil, 'nil id')
eq(L.chestPath('reward_sigil'), '/modules/game_chestaura/images/chest/reward_sigil.png', 'chest path')
eq(L.footPath(1), '/modules/game_chestaura/images/foot/templar_sigil.png', 'foot path templar')
eq(L.footPath(2), '/modules/game_chestaura/images/foot/inquisitor_sigil.png', 'foot path inquisitor')
eq(L.footPath(3), '/modules/game_chestaura/images/foot/sentinel_sigil.png', 'foot path sentinel'); eq(L.footPath(4), nil, 'no fourth line'); eq(L.footPath(0), nil, 'no line 0')
eq(L.framePath(3), '/modules/game_chestaura/images/frame/sentinel.png', 'frame path')

-- the pictures the generator wrote: every strip is the size the logic assumes (PNG header: width at bytes 17-20, height at 21-24)
local function pngSize(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local h = f:read(24)
  f:close()
  if not h or #h < 24 or h:sub(2, 4) ~= 'PNG' then return nil end
  local function u32(s) local a, b, c, d = s:byte(1, 4); return ((a * 256 + b) * 256 + c) * 256 + d end
  return u32(h:sub(17, 20)), u32(h:sub(21, 24))
end
local function check_strip(path, frames, px, what)
  local w, h = pngSize(dir .. path:gsub('^/modules/game_chestaura', ''))
  eq(w, frames * px, what .. ': strip width'); eq(h, px, what .. ': strip height')
end
for id, def in pairs(L.CHESTS) do check_strip(L.chestPath(def.art), L.CHEST_FRAMES, def.px, 'chest ' .. id) end
for line = 1, #L.LINES do
  check_strip(L.footPath(line), L.FOOT_FRAMES, L.FOOT_PX, 'foot ' .. L.LINES[line])
  check_strip(L.framePath(line), 1, L.FRAME_PX, 'frame ' .. L.LINES[line])
end

-- ---------------------------------------------------------------- sizes (sprite pixels)
local size, ml, mt = L.floorBox(32, 2, 0)
eq(size, 64, 'a 64 px picture is two tiles'); eq(ml, -16, 'centred on the tile: margin half a tile back'); eq(mt, -16, 'same vertically')
size, ml, mt = L.chestBox(L.chestOf(38758), 32)
eq(size, 64, 'reward chest widget 64'); eq(ml, -16, 'reward chest centred on its tile')
size, ml, mt = L.chestBox(L.chestOf(38657), 32)
eq(size, 128, 'coffer widget 128 (four tiles)'); eq(ml, -32, 'coffer centred on the corner of its tile: the middle of the 2 x 2 footprint'); eq(mt, -32, 'same vertically')
size, ml, mt = L.chestBox(L.chestOf(38657), 64)
eq(size, 256, 'a 64 px sprite size doubles it'); eq(ml, -64, 'and the margin')
eq(L.FRAME_PX, 3 * L.FRAME_BORDER, 'the frame picture is 3 tiles across with a one tile border')
local fsize, fdy = L.footBox(32)
eq(fsize, 64, 'foot picture 64 map px'); eq(fdy, 12, 'the ring goes 12 px down to the feet')
fsize, fdy = L.footBox(64)
eq(fsize, 128, 'foot picture at 64 px sprites'); eq(fdy, 24, 'and the offset')

-- the range frame is one widget of (2r + 1) tiles; on the Templar's own tile it is centred like any floor widget
size, ml, mt = L.frameBox(32, 4, 0, 0)
eq(size, 9 * 32, 'radius 4: nine tiles across'); eq(ml, -16, 'hosted on the Templar tile: centred'); eq(mt, -16, 'centred vertically')
size = L.frameBox(32, 3, 0, 0); eq(size, 7 * 32, 'radius 3 (Inquisitor): seven tiles')
size = L.frameBox(32, 5, 0, 0); eq(size, 11 * 32, 'radius 5 (Sentinel): eleven tiles')
size = L.frameBox(32, 6, 0, 0); eq(size, 13 * 32, 'radius 6 (Sentinel with Bastion): thirteen tiles')
-- hosted one tile west and two north of the Templar: the margins move the centre by (1, 2) tiles
size, ml, mt = L.frameBox(32, 4, 1, 2)
eq(ml, 16, 'the Templar is one tile east of the host'); eq(mt, 48, 'and two tiles south of it')
size, ml, mt = L.frameBox(32, 4, -1, 0)
eq(ml, -48, 'the Templar is one tile west of the host'); eq(mt, -16, 'same row')
size, ml, mt = L.frameBox(64, 4, 0, 0)
eq(size, 9 * 64, 'at 64 px sprites'); eq(ml, -32, 'and the margin')

-- ---------------------------------------------------------------- the range square
local origin = { x = 1000, y = 2000, z = 7 }
for _, r in ipairs({ 3, 4, 5, 6 }) do
  local b = L.squareBounds(origin, r)
  eq(b.x1 - b.x0 + 1, 2 * r + 1, 'radius ' .. r .. ': (2r + 1) tiles wide'); eq(b.y1 - b.y0 + 1, 2 * r + 1, 'and tall')
  eq(b.x0, 1000 - r, 'west edge'); eq(b.y1, 2000 + r, 'south edge'); eq(b.z, 7, 'floor')
  eq(L.squareSize(r), (2 * r + 1) * (2 * r + 1), 'tiles covered')
end
eq(L.squareSize(4), 81, 'the Templar covers 9 x 9 tiles'); eq(L.squareSize(3), 49, 'the Inquisitor 7 x 7'); eq(L.squareSize(5), 121, 'the Sentinel 11 x 11')
-- a tile is inside when its Chebyshev distance is at most r (the server's M.distance), on the same floor
eq(L.inSquare({ x = 1004, y = 2004, z = 7 }, origin, 4), true, 'the corner is covered'); eq(L.inSquare({ x = 1005, y = 2000, z = 7 }, origin, 4), false, 'one past the edge')
eq(L.inSquare({ x = 996, y = 1996, z = 7 }, origin, 4), true, 'the other corner'); eq(L.inSquare({ x = 1000, y = 2005, z = 7 }, origin, 4), false, 'one past south')
eq(L.inSquare({ x = 1000, y = 2000, z = 7 }, origin, 4), true, 'the Templar itself'); eq(L.inSquare({ x = 1002, y = 2000, z = 6 }, origin, 4), false, 'another floor')
eq(L.inSquare(nil, origin, 4), false, 'nil tile')
local covered = 0
for dy = -8, 8 do
  for dx = -8, 8 do
    if L.inSquare({ x = 1000 + dx, y = 2000 + dy, z = 7 }, origin, 4) then covered = covered + 1 end
  end
end
eq(covered, 81, 'counting the tiles gives 81')
eq(L.keyPos('997,1997,7').x, 997, 'keyPos x'); eq(L.keyPos('nonsense'), nil, 'keyPos junk'); eq(L.keyPos(L.tileKey({ x = -1, y = 5, z = 0 })).x, -1, 'keyPos negative')

-- the host of the frame: the Templar's own tile when it is free, else the nearest free tile (rings of growing distance)
local taken = {}
local function free(p) return not taken[p.x .. ',' .. p.y] end
local host = L.pickHost(origin, free)
eq(host.x, 1000, 'the Templar tile hosts when free'); eq(host.y, 2000, 'same row'); eq(host.z, 7, 'same floor')
taken['1000,2000'] = true
host = L.pickHost(origin, free)
eq(host.x, 999, 'the next candidate is the north west neighbour'); eq(host.y, 1999, 'ring 1 starts at the top left')
for dy = -1, 1 do for dx = -1, 1 do taken[(1000 + dx) .. ',' .. (2000 + dy)] = true end end
host = L.pickHost(origin, free)
eq(math.max(math.abs(host.x - 1000), math.abs(host.y - 2000)), 2, 'all of ring 1 taken: a tile of ring 2')
for dy = -2, 2 do for dx = -2, 2 do taken[(1000 + dx) .. ',' .. (2000 + dy)] = true end end
eq(L.pickHost(origin, free), nil, 'nothing free within reach: no frame')
eq(L.pickHost(origin, free, 3) ~= nil, true, 'a longer reach finds one')
eq(L.hostNear({ x = 1002, y = 1998, z = 7 }, origin), true, 'a host two tiles away still serves'); eq(L.hostNear({ x = 1003, y = 2000, z = 7 }, origin), false, 'three away: look for a new one')
eq(L.hostNear({ x = 1000, y = 2000, z = 6 }, origin), false, 'another floor')

-- ---------------------------------------------------------------- what is visible
local me = { x = 100, y = 100, z = 7 }
eq(L.onScreen({ x = 107, y = 105, z = 7 }, me, 15, 11), true, 'the edge of a 15 x 11 view')
eq(L.onScreen({ x = 108, y = 100, z = 7 }, me, 15, 11, 0), false, 'a host takes margin 0: a tile past the edge is not drawn')
eq(L.onScreen({ x = 108, y = 100, z = 7 }, me, 15, 11), true, 'one tile past it (the margin)')
eq(L.onScreen({ x = 109, y = 100, z = 7 }, me, 15, 11), false, 'two tiles past'); eq(L.onScreen({ x = 100, y = 107, z = 7 }, me, 15, 11), false, 'too far south')
eq(L.onScreen({ x = 100, y = 100, z = 6 }, me, 15, 11), false, 'another floor'); eq(L.onScreen(nil, me, 15, 11), false, 'nil position')
eq(L.onScreen({ x = 100, y = 100, z = 7 }, me, 0, 0), false, 'no visible dimension')

local entry = { id = 5, line = 1, radius = 4, party = true }
eq(L.showSigil(true, entry, true), true, 'a Templar in view has its sigil')
eq(L.showSigil(true, { id = 6, line = 1, radius = 4, party = false }, true), true, 'the sigil needs no party')
eq(L.showSigil(false, entry, true), false, 'option off: no sigil'); eq(L.showSigil(true, entry, false), false, 'creature not in view: no sigil')
eq(L.showSigil(true, nil, true), false, 'the server did not name it: no sigil'); eq(L.showSigil(true, { id = 7, line = 9, radius = 4, party = true }, true), false, 'unknown line')
eq(L.showFrame(true, entry, me, me), true, 'a Templar in a party: the frame (the Templar and its members get party = true)')
eq(L.showFrame(true, { id = 6, line = 1, radius = 4, party = false }, me, me), false, 'solo or not in its party: no frame')
eq(L.showFrame(false, entry, me, me), false, 'option off: no frame')
eq(L.showFrame(true, entry, { x = 100, y = 100, z = 6 }, me), false, 'the Templar is on another floor: no frame')
eq(L.showFrame(true, entry, nil, me), false, 'no Templar position'); eq(L.showFrame(true, nil, me, me), false, 'no entry')
eq(L.showFrame(true, { id = 6, line = 1, radius = 0, party = true }, me, me), false, 'no radius: no frame')

-- ---------------------------------------------------------------- the server's list
local ok = L.parseSync({ action = 'sync', data = { t = { { i = 11, l = 1, r = 4, p = 1 }, { i = 12, l = 3, r = 6, p = 0 } } } })
eq(ok[11].line, 1, 'line'); eq(ok[11].radius, 4, 'radius'); eq(ok[11].party, true, 'party flag 1'); eq(ok[12].party, false, 'party flag 0'); eq(ok[12].radius, 6, 'bonus radius')
eq(L.parseSync({ action = 'other' }), nil, 'not a sync'); eq(L.parseSync(nil), nil, 'nil'); eq(L.parseSync('x'), nil, 'a string')
local e = L.parseSync({ action = 'sync', data = { t = {} } })
eq(next(e), nil, 'an empty list clears'); e = L.parseSync({ action = 'sync' })
eq(next(e), nil, 'no data is an empty list')
e = L.parseSync({ action = 'sync', data = { t = { { i = 0, l = 1, r = 4, p = 1 }, { i = 5, l = 4, r = 4, p = 1 }, { i = 6, l = 1, r = 0, p = 1 },
  { i = 'x', l = 1, r = 4 }, 'junk', { i = 7, l = 2, r = 99, p = true } } } })
eq(e[0], nil, 'creature id 0 dropped'); eq(e[5], nil, 'line 4 dropped'); eq(e[6], nil, 'radius 0 dropped'); eq(e[7].radius, L.MAX_RADIUS, 'a huge radius is capped')
eq(e[7].party, true, 'a boolean flag is accepted')
local rows = {}
for i = 1, 100 do rows[i] = { i = i, l = 1, r = 4, p = 0 } end
local n = 0
for _ in pairs(L.parseSync({ action = 'sync', data = { t = rows } })) do n = n + 1 end
eq(n, L.MAX_ROWS, 'at most ' .. L.MAX_ROWS .. ' rows')

local a = L.parseSync({ action = 'sync', data = { t = { { i = 1, l = 1, r = 4, p = 0 }, { i = 2, l = 2, r = 3, p = 1 } } } })
local b = L.parseSync({ action = 'sync', data = { t = { { i = 2, l = 2, r = 3, p = 0 }, { i = 3, l = 3, r = 5, p = 1 } } } })
local sd = L.syncDiff(a, b)
eq(table.concat(sd.added, ','), '3', 'added'); eq(table.concat(sd.removed, ','), '1', 'removed'); eq(table.concat(sd.changed, ','), '2', 'the party flag changed')
sd = L.syncDiff(a, a)
eq(#sd.added + #sd.removed + #sd.changed, 0, 'no change'); eq(#L.syncDiff(nil, a).added, 2, 'from nothing')

if fails > 0 then
  print(string.format('chestaura_test: %d of %d checks failed', fails, checks))
  os.exit(1)
end
print(string.format('chestaura_test: all %d checks passed', checks))
