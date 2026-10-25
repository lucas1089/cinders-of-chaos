-- game_visualfx logic (client/MANIFEST.md "Visual effects"): the hit flash, the screen shake and the option values, with no
-- engine calls so visualfx_test.lua can run it. Every function takes the time (ms) and, where it needs luck, a random
-- function, so the tests are exact.
VisualFxLogic = {}
local L = VisualFxLogic

-- the options (client_settings dataset.lua, Options > Graphics "Visual effects"); on by default except the grade,
-- which changes the biome colours and waits for the owner's look at the first build, and the soft glow (bloom, O210), which
-- costs fill rate and waits for the same look
L.OPTIONS = { 'hitFlash', 'screenShake', 'creatureShadow', 'screenGrade', 'spellLight', 'liquidShimmer', 'weather', 'bloom', 'numberMotion', 'targetOutline', 'hoverOutline', 'sceneFade', 'deathFade' }
L.DEFAULTS = { hitFlash = true, screenShake = true, creatureShadow = true, screenGrade = false, spellLight = true, liquidShimmer = true, weather = true, bloom = false, numberMotion = true, targetOutline = true, hoverOutline = false, sceneFade = true, deathFade = true }

-- an option value from the settings: a boolean is kept, anything else (nil, junk, an older settings file) is the default
function L.optionOn(name, value)
  if type(value) == 'boolean' then return value end
  return L.DEFAULTS[name] == true
end

-- ---------------------------------------------------------------- hit flash
-- Otc::MessageMode of this client as g_map.onImpactText gets it (same as game_damagescatter's L.MODE)
L.MODE = { DAMAGE_DEALT = 21, DAMAGE_RECEIVED = 22, DAMAGE_OTHERS = 25 }
-- number types of the server (ChaosImpactType): only plain and critical hits flash, a damage-over-time tick does not
-- (it would flicker the creature for the whole burn)
L.TYPE = { NORMAL = 0, CRITICAL = 1 }
L.FLASH = {
  ms = 80,          -- a plain hit
  critMs = 110,     -- a critical hit
  gap = 140,        -- the same creature does not flash again inside this many ms (a spray of hits is one flash)
  maxActive = 8,    -- flashes alive at once on the map: the shader draw is a little dearer than the plain one
  white = 'chaos_hit_white',  -- creatures the player hits, and the others' fights
  red = 'chaos_hit_red',      -- the player is hit
}

function L.newFlasher()
  return { last = {}, ends = {}, n = 0 }
end

local function isDamageMode(mode)
  return mode == L.MODE.DAMAGE_DEALT or mode == L.MODE.DAMAGE_RECEIVED or mode == L.MODE.DAMAGE_OTHERS
end

-- Whether a damage number makes its creature flash. Returns the outfit shader and the milliseconds, or nil.
-- `state` is L.newFlasher(); `mine` tells that the creature is the local player.
function L.flashPlan(state, now, creatureId, mode, typeId, value, mine)
  if not isDamageMode(mode) then return nil end
  typeId = tonumber(typeId) or 0
  if typeId ~= L.TYPE.NORMAL and typeId ~= L.TYPE.CRITICAL then return nil end
  if not creatureId or creatureId == 0 then return nil end
  if (tonumber(value) or 0) <= 0 then return nil end
  local F = L.FLASH
  local last = state.last[creatureId]
  if last and now - last < F.gap then return nil end
  -- drop the flashes that are over, then the cap
  local alive = 0
  for id, at in pairs(state.ends) do
    if at <= now then state.ends[id] = nil else alive = alive + 1 end
  end
  if alive >= F.maxActive then return nil end
  local ms = typeId == L.TYPE.CRITICAL and F.critMs or F.ms
  state.last[creatureId] = now
  state.ends[creatureId] = now + ms
  -- the memory of old creatures does not grow for ever
  state.n = state.n + 1
  if state.n >= 64 then
    state.n = 0
    for id, at in pairs(state.last) do
      if now - at > 2000 then state.last[id] = nil end
    end
  end
  return mine and F.red or F.white, ms
end

-- ---------------------------------------------------------------- screen shake
-- Only the local player's hits shake the view, and only the big ones: a critical hit of at least 3% of the maximum
-- health, or any hit of at least 15% (percent is x100 as the server sends it: 10000 = 100%). A few pixels, short.
L.SHAKE = {
  maxPx = 4,         -- the cap, in 1x sprite pixels (the engine scales it to the sprite size)
  ms = 180,          -- how long it lasts; the strength falls off to nothing
  gap = 300,         -- after a shake, the next one may start this many ms after the last start (a shake that runs is only
                     -- restarted by a stronger hit)
  bigPercent = 1500,
  critPercent = 300,
}

-- the strength (pixels) a received hit asks for, 0 for none
function L.shakeAmp(typeId, percent)
  local S = L.SHAKE
  percent = tonumber(percent) or 0
  typeId = tonumber(typeId) or 0
  if percent <= 0 then return 0 end
  local big = percent >= S.bigPercent
  local crit = typeId == L.TYPE.CRITICAL and percent >= S.critPercent
  if not big and not crit then return 0 end
  local amp = percent >= 5000 and 4 or percent >= 3000 and 3 or 2
  if amp > S.maxPx then amp = S.maxPx end
  return amp
end

function L.newShake()
  return { startAt = 0, endAt = 0, amp = 0, lastAt = -1e9 }
end

-- starts (or strengthens) a shake; true when it started
function L.shakeStart(state, now, amp)
  if not amp or amp <= 0 then return false end
  local S = L.SHAKE
  if amp > S.maxPx then amp = S.maxPx end
  local running = now < state.endAt
  if running and amp <= L.shakeNow(state, now) then return false end
  if not running and now - state.lastAt < S.gap then return false end
  state.startAt, state.endAt, state.amp, state.lastAt = now, now + S.ms, amp, now
  return true
end

-- the strength at this moment (a whole number of pixels, falling off), 0 when over
function L.shakeNow(state, now)
  if now >= state.endAt then return 0 end
  local S = L.SHAKE
  local left = (state.endAt - now) / S.ms
  local mag = math.ceil(state.amp * left)
  if mag > S.maxPx then mag = S.maxPx end
  return mag
end

-- the pixel shift of this frame and whether the shake is over; `rnd()` is a number in [0, 1)
function L.shakeOffset(state, now, rnd)
  local mag = L.shakeNow(state, now)
  if mag <= 0 then return 0, 0, true end
  local function pick()
    local v = math.floor(rnd() * (2 * mag + 1)) - mag
    if v > mag then v = mag elseif v < -mag then v = -mag end
    return v
  end
  local x = pick()
  -- at least one pixel on one axis, so a frame is never a no-op while the shake runs
  local y = pick()
  if x == 0 and y == 0 then x = (rnd() < 0.5) and -mag or mag end
  return x, y, false
end

-- ---------------------------------------------------------------- spell colour light (O205)
-- A magic effect that plays on the map lights the tiles around it for a moment, in a colour that matches it, so spells
-- glow in caves and at night. The engine (base patch 0127, Map::spellLightEffect, called from Tile::addThing for an
-- effect) keeps the live lights and adds them to the map light view; this file holds the numbers and the rules the
-- engine mirrors (the tests run the model below). The light view only adds light: on the full-light surface the
-- ambient is already at its maximum, so the glow does not show there.
L.LIGHT = {
  max = 12,         -- lights alive at once; a new effect finds the table full -> no light
  ms = 320,         -- life of one light
  attack = 0.15,    -- share of the life spent rising to full
  radius = 2,       -- tiles, 1..3
  minRadius = 1,
  maxRadius = 3,
  minGap = 90,      -- the same effect on the same tile again inside this many ms is one light
  minFade = 0.12,   -- under this share of full the light is dropped
}

-- the light colours, 8-bit (the engine palette: 36 * red + 6 * green + blue, each 0..5)
local function rgb(r, g, b) return r * 36 + g * 6 + b end
L.THEME_COLOR = {
  fire = rgb(5, 2, 0), blood = rgb(5, 0, 0), energy = rgb(3, 4, 5), frost = rgb(1, 3, 5), water = rgb(0, 3, 5),
  holy = rgb(5, 5, 2), poison = rgb(1, 5, 1), physical = rgb(4, 4, 4), arcane = rgb(4, 1, 5), healing = rgb(2, 5, 2),
  death = rgb(3, 0, 3), shadow = rgb(2, 0, 4), earth = rgb(3, 2, 0),
}

-- effect ids by theme (single ids and {first, last} ranges): the stock spell effects and the effects of
-- server/data/spells/effects_catalog.csv (ids 372-423 are ours), and by name the class, status and pack catalogs
-- (class_fx, status_fx, pack, pack27, pack29, pack30). Left out on purpose: combat feedback (415-423), damage-over-time
-- ticks, warning circles, loot beams, buffs, portals, smoke, sound and block effects.
L.THEME_IDS = {
  blood = { 1, 14, 167, 223, {388, 392}, {597, 598}, 716, {719, 726}, 730, 760, 831 },
  water = { 2, 26, 54, 660, 840 },
  fire = { {5, 7}, 16, 37, 200, 213, 216, 221, 226, 248, {372, 378}, 709, 739, 761, 834, {851, 852} },
  holy = { 8, 40, 50, 201, {224, 225}, 262, 264, {403, 405}, {619, 621}, 624, 656, 672, 686, {711, 714}, 748, 753, 755, 835 },
  poison = { 9, 17, 21, 47, {399, 402}, 729, 767, 839, {853, 854} },
  physical = { 10, 32, 173 },
  arcane = { 11, 13, 48, 187, 244, 288, 291, 309, 312, {406, 408}, 607, {768, 769}, 771, 775, {777, 778}, 830 },
  energy = { 12, 38, 41, 49, 204, 217, 219, 246, {384, 387}, 671, 685, 710, 759, 833, 837 },
  healing = { 15, 185, {411, 412}, 605, {665, 667}, 741, 776 },
  death = { 18, 39, 158, 203, 218, 220, 222 },
  earth = { 35, {45, 46}, 51, {182, 183}, 367, 593, 601, {668, 669}, 674, {717, 718}, {765, 766} },
  frost = { {42, 44}, 53, 202, 205, 215, 359, {379, 383}, 662, 708, 762, 836 },
  shadow = { {393, 398}, {614, 615}, 617, 657, 659, 727, {731, 738}, {742, 743}, 757, 770, {772, 774}, 779, 832 },
}

-- effect id -> theme, built once from THEME_IDS
L.EFFECT_THEME = {}
for theme, list in pairs(L.THEME_IDS) do
  for _, e in ipairs(list) do
    if type(e) == 'table' then
      for id = e[1], e[2] do L.EFFECT_THEME[id] = theme end
    else
      L.EFFECT_THEME[e] = theme
    end
  end
end

-- the light of an effect: 8-bit colour and radius in tiles, or nil (unknown effect -> no light)
function L.lightFor(effectId)
  local theme = L.EFFECT_THEME[tonumber(effectId) or -1]
  if not theme then return nil end
  return L.THEME_COLOR[theme], L.LIGHT.radius
end

-- strength 0..1 at an age in ms: a short rise, then a smooth fall to nothing; 0 outside the life
function L.fade(age)
  local A = L.LIGHT
  age = tonumber(age) or 0
  if age < 0 or age >= A.ms then return 0 end
  local t = age / A.ms
  if t < A.attack then return t / A.attack end
  local u = (t - A.attack) / (1 - A.attack)
  return (1 - u) * (1 - u)
end

-- an 8-bit colour with each of its three levels scaled by f (0..1, rounded)
function L.dim(color, f)
  local r, g, b = math.floor(color / 36) % 6, math.floor(color / 6) % 6, color % 6
  local function s(v) return math.floor(v * f + 0.5) end
  return rgb(s(r), s(g), s(b))
end

-- the radius (tiles) at strength f: shrinks with the light, never under minRadius while it shows
function L.radiusAt(radius, f)
  local A = L.LIGHT
  local r = math.floor(radius * f + 0.5)
  if r < A.minRadius then r = A.minRadius end
  if r > A.maxRadius then r = A.maxRadius end
  return r
end

function L.newLights()
  return { list = {}, last = {} }
end

local function prune(state, now)
  local keep = {}
  for _, l in ipairs(state.list) do
    if now - l.at < L.LIGHT.ms then keep[#keep + 1] = l end
  end
  state.list = keep
end

-- An effect id plays at a position {x, y, z}. Returns the new light {x, y, z, color, radius, at} or nil: option off,
-- unknown effect, the same effect on the same tile just now, or the table full.
function L.lightAdd(state, now, pos, effectId, enabled)
  if not enabled or not pos then return nil end
  local color, radius = L.lightFor(effectId)
  if not color then return nil end
  local key = pos.x .. ':' .. pos.y .. ':' .. pos.z .. ':' .. effectId
  local last = state.last[key]
  if last and now - last < L.LIGHT.minGap then return nil end
  prune(state, now)
  if #state.list >= L.LIGHT.max then return nil end
  state.last[key] = now
  -- the memory of old keys does not grow for ever
  local n = 0
  for _ in pairs(state.last) do n = n + 1 end
  if n > 256 then
    for k, at in pairs(state.last) do
      if now - at > L.LIGHT.ms then state.last[k] = nil end
    end
  end
  local light = { x = pos.x, y = pos.y, z = pos.z, color = color, radius = radius, at = now }
  state.list[#state.list + 1] = light
  return light
end

-- the lights to draw at this moment: { color, radius, x, y, z } with the fade applied
function L.lightsNow(state, now)
  prune(state, now)
  local out = {}
  for _, l in ipairs(state.list) do
    local f = L.fade(now - l.at)
    if f >= L.LIGHT.minFade then
      local color = L.dim(l.color, f)
      if color > 0 then
        out[#out + 1] = { x = l.x, y = l.y, z = l.z, color = color, radius = L.radiusAt(l.radius, f) }
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- living water and lava
-- Ground sprites that shimmer (base patch 0128, Item.addLiquidId): client ids of the water and lava grounds. The pack
-- grounds are the rows of kind `water` in server/data/items/*.csv (client_id column: deep lake and shallows 33456-33463,
-- the lava of the lava islands 35059 and 35070-35073, sewer water 35101). The stock 10.98 grounds are the client ids items.otb gives the
-- items.xml "shallow water" grounds 4608-4625 (629-634, 4597-4602, 4609-4614) and "lava" grounds 599-601 (728-730). Lava
-- borders, bubbles and the magma-veined floor are not liquids and stay as they are. A new liquid ground is one line here.
L.LIQUID = {
  water = { { 629, 634 }, { 4597, 4602 }, { 4609, 4614 }, { 33456, 33463 }, { 35101, 35101 } },
  lava = { { 728, 730 }, { 35059, 35059 }, { 35070, 35073 } },
  kind = { water = 1, lava = 2 },      -- the kind numbers Item.addLiquidId takes
  waterShader = 'chaos_liquid_water',  -- data/shaders, vertex stage chaos_liquid_vertex
  lavaShader = 'chaos_liquid_lava',
}

-- 'water', 'lava' or nil for a client id
function L.liquidKind(id)
  id = tonumber(id)
  if not id then return nil end
  for _, name in ipairs({ 'water', 'lava' }) do
    for _, r in ipairs(L.LIQUID[name]) do
      if id >= r[1] and id <= r[2] then return name end
    end
  end
  return nil
end

-- every (id, kind number) pair, in id order, for the one-time table sent to the engine
function L.liquidList()
  local out = {}
  for _, name in ipairs({ 'water', 'lava' }) do
    for _, r in ipairs(L.LIQUID[name]) do
      for id = r[1], r[2] do out[#out + 1] = { id = id, kind = L.LIQUID.kind[name] } end
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- ---------------------------------------------------------------- soft glow (O210)
-- A halo around very bright light only (base patch 0132, g_app.setMapBloom; shaders chaos_bloom_extract / chaos_bloom_blur in
-- data/shaders). The engine keeps a pixel only when its luma is above `threshold` (smooth up to `full`) and screen-blends the blurred
-- result over the map, so ordinary ground and biome colours are never changed. The two luma numbers are written in
-- chaos_bloom_extract.frag; they are here so the test can hold them to the owner's rule (high threshold, low strength).
L.BLOOM = {
  strength = 0.35,   -- weight of the halo, 0..1 (the engine clamps it); low on purpose
  maxStrength = 0.5, -- the most this file may ask for
  threshold = 0.80,  -- luma under which nothing glows
  full = 0.96,       -- luma from which a pixel glows at full weight
  extractShader = 'chaos_bloom_extract',
  blurShader = 'chaos_bloom_blur',
  vertex = '/shaders/chaos_bloom_vertex',
}

-- the strength to hand to the engine: 0 when the option is off, else the configured one inside 0..maxStrength
function L.bloomStrength(enabled)
  if not enabled then return 0 end
  local B = L.BLOOM
  local s = tonumber(B.strength) or 0
  if s < 0 then s = 0 elseif s > B.maxStrength then s = B.maxStrength end
  return s
end

-- ---------------------------------------------------------------- target, follow and hover outline (O216)
-- Creature:setOutline (base patch 0038) draws a silhouette line under the outfit. Kinds, strongest first: the creature the
-- player attacks (red, a gentle pulse), the one followed (green), the one under the mouse (faint white). One creature has one
-- kind: the strongest that applies. Option targetOutline covers target and follow, hoverOutline the mouse.
L.OUTLINE = {
  target = { 235, 45, 40, 235, 2, 1600 },   -- r, g, b, a, width px, pulse ms (0: steady)
  follow = { 70, 220, 95, 225, 2, 0 },
  hover = { 255, 255, 255, 110, 1, 0 },
  order = { 'target', 'follow', 'hover' },
  mouseGapMs = 33,                          -- mouse moves closer than this are not looked at (a lookup is not free)
  sweepMs = 500,                            -- the lost-outline check; the timer runs only while an outline is up
}

-- which creature id has which kind. `st` = {targetId, followId, hoverId, meId}; `opts` = {target = bool, hover = bool}.
-- Returns a table id -> kind. The local player never gets one.
function L.outlineWanted(st, opts)
  local out = {}
  local function put(id, kind)
    id = tonumber(id)
    if not id or id == 0 or id == tonumber(st.meId) or out[id] then return end
    out[id] = kind
  end
  if opts.target then
    put(st.targetId, 'target')
    put(st.followId, 'follow')
  end
  if opts.hover then put(st.hoverId, 'hover') end
  return out
end

-- what to do to go from `applied` (id -> kind) to `wanted`: clears first, then sets, only for what changed. Nothing is
-- listed when nothing changed, so a mouse move over the same creature costs no engine call.
function L.outlineDiff(applied, wanted)
  local ops = {}
  for id, kind in pairs(applied) do
    if wanted[id] == nil then ops[#ops + 1] = { op = 'clear', id = id } end
  end
  for id, kind in pairs(wanted) do
    if applied[id] ~= kind then ops[#ops + 1] = { op = 'set', id = id, kind = kind } end
  end
  table.sort(ops, function(a, b)
    if a.op ~= b.op then return a.op == 'clear' end
    return a.id < b.id
  end)
  return ops
end

-- the engine arguments of a kind, or nil
function L.outlineArgs(kind)
  local o = L.OUTLINE[kind]
  if kind == 'order' or type(o) ~= 'table' then return nil end
  return o
end

-- whether a mouse move is looked at: true when at least mouseGapMs passed since the last one looked at
function L.mouseGate(state, now)
  if now - (state.last or -1e9) < L.OUTLINE.mouseGapMs then return false end
  state.last = now
  return true
end
