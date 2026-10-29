-- luajit visualfx_test.lua && lua5.3 visualfx_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'visualfx_logic.lua')
local L = VisualFxLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- options: the grade is off by default (it shifts the biome colours), the rest on; a boolean wins, junk is the default
local wantDefault = { hitFlash = true, screenShake = true, creatureShadow = true, screenGrade = false, spellLight = true, liquidShimmer = true, weather = true, bloom = false, numberMotion = true, targetOutline = true, hoverOutline = false, sceneFade = true, deathFade = true, ambientParticles = true, smoothBars = true, missileTrails = true, lightFlicker = true, cooldownPulse = true }

for _, name in ipairs(L.OPTIONS) do
  local d = wantDefault[name]
  eq(L.optionOn(name, nil), d, name .. ' default')
  eq(L.optionOn(name, false), false, name .. ' off is kept')
  eq(L.optionOn(name, true), true, name .. ' on is kept')
  eq(L.optionOn(name, 'no'), d, name .. ' junk -> default')
  eq(L.optionOn(name, 0), d, name .. ' number -> default')
end
eq(#L.OPTIONS, 18, 'eighteen options')
do
  local f = io.open(dir .. 'visualfx.lua'); local src = f:read('*a'); f:close()
  eq(src:find("name == 'cooldownPulse'", 1, true) ~= nil, true, 'onOption handles cooldownPulse')
  eq(src:find("optionValue('cooldownPulse')", 1, true) ~= nil, true, 'the pulse option value is read')
  eq(src:find('ChaosCooldownPulse.terminate()', 1, true) ~= nil, true, 'terminate removes the pulse hook')
  eq(L.DEFAULTS.cooldownPulse, true, 'the cooldown pulse is on by default')
end
eq(L.optionOn('nothing', nil), false, 'an unknown option is off')
eq(L.DEFAULTS.numberMotion, true, 'soft damage numbers are on by default (purely visual, a few float operations per text)')
do
  -- the option is wired: the engine switch is called from visualfx.lua on a change, at game start and off at terminate
  local f = io.open(dir .. 'visualfx.lua', 'r')
  local src = f and f:read('*a') or ''
  if f then f:close() end
  local _, calls = src:gsub('AnimatedText%.setSoftMotion', '')
  eq(calls >= 3, true, 'setSoftMotion is checked, called with the option and switched off at terminate')
  eq(src:find("name == 'numberMotion'", 1, true) ~= nil, true, 'onOption handles numberMotion')
  eq(src:find("optionValue('numberMotion')", 1, true) ~= nil, true, 'the option value is read')
end

do
  -- the death fade (O221, base patch 0139): on by default, the engine switch is called on a change, at game start and off at terminate
  eq(L.DEFAULTS.deathFade, true, 'the death fade is on by default (a copy of one frame, bounded, no server state)')
  local f = io.open(dir .. 'visualfx.lua', 'r')
  local src = f and f:read('*a') or ''
  if f then f:close() end
  local _, calls = src:gsub('Creature%.setDeathFade', '')
  eq(calls >= 3, true, 'setDeathFade is checked, called with the option and switched off at terminate')
  eq(src:find("name == 'deathFade'", 1, true) ~= nil, true, 'onOption handles deathFade')
  eq(src:find("optionValue('deathFade')", 1, true) ~= nil, true, 'the option value is read')
  eq(src:find('applyDeathFade()', 1, true) ~= nil, true, 'reapply sets it at game start')
end

do
  -- the smooth bars (O229, base patch 0146): on by default, the engine switch is called on a change, at game start and off at terminate
  eq(L.DEFAULTS.smoothBars, true, 'smooth bars are on by default')
  local f = io.open(dir .. 'visualfx.lua', 'r')
  local src = f and f:read('*a') or ''
  if f then f:close() end
  local _, calls = src:gsub('Creature%.setSmoothBars', '')
  eq(calls >= 3, true, 'setSmoothBars is checked, called with the option and switched off at terminate')
  eq(src:find("name == 'smoothBars'", 1, true) ~= nil, true, 'onOption handles smoothBars')
  eq(src:find("optionValue('smoothBars')", 1, true) ~= nil, true, 'the option value is read')
  eq(src:find('applySmoothBars()', 1, true) ~= nil, true, 'reapply sets it at game start')
end

do
  -- the light flicker (O228, base patch 0145): on by default, the engine switch g_map.setLightFlicker is called on a change,
  -- at game start (reapply) and off at terminate
  eq(L.DEFAULTS.lightFlicker, true, 'the light flicker is on by default')
  eq(L.optionOn('lightFlicker', nil), true, 'default when unset')
  eq(L.optionOn('lightFlicker', false), false, 'off is kept')
  local f = io.open(dir .. 'visualfx.lua', 'r')
  local src = f and f:read('*a') or ''
  if f then f:close() end
  eq(src:find("name == 'lightFlicker'", 1, true) ~= nil, true, 'onOption handles lightFlicker')
  eq(src:find("optionValue('lightFlicker')", 1, true) ~= nil, true, 'the option value is read')
  eq(src:find('applyLightFlicker()', 1, true) ~= nil, true, 'reapply sets it at game start')
  eq(src:find('g_map.setLightFlicker, false', 1, true) ~= nil, true, 'terminate switches it off')
end

do
  -- the hit flash tint (O224, base patch 0142): the existing option hitFlash drives the engine switch too
  eq(L.DEFAULTS.hitFlash, true, 'the hit flash is on by default')
  local f = io.open(dir .. 'visualfx.lua', 'r')
  local src = f and f:read('*a') or ''
  if f then f:close() end
  local _, calls = src:gsub('Creature%.setHitTint', '')
  eq(calls >= 3, true, 'setHitTint is checked, called with the option and switched off at terminate')
  eq(src:find("name == 'hitFlash'", 1, true) ~= nil, true, 'onOption handles hitFlash')
  eq(src:find("optionValue('hitFlash')", 1, true) ~= nil, true, 'the option value is read')
  eq(src:find('applyHitTint()', 1, true) ~= nil, true, 'reapply sets it at game start')
end

-- hit flash
local M = L.MODE
local f = L.newFlasher()
local shader, ms = L.flashPlan(f, 1000, 7, M.DAMAGE_DEALT, 0, 120, false)
eq(shader, 'chaos_hit_white', 'a hit on a monster flashes white')
eq(ms, 80, 'a plain hit: 80 ms')
shader, ms = L.flashPlan(f, 1000, 8, M.DAMAGE_RECEIVED, 0, 50, true)
eq(shader, 'chaos_hit_red', 'a hit on the player flashes red')
shader, ms = L.flashPlan(f, 1000, 9, M.DAMAGE_OTHERS, 1, 300, false)
eq(shader, 'chaos_hit_white', 'a critical hit of someone else')
eq(ms, 110, 'a critical hit: 110 ms')
eq(L.flashPlan(f, 1050, 7, M.DAMAGE_DEALT, 0, 120, false), nil, 'the same creature inside the gap does not flash again')
eq(L.flashPlan(f, 1139, 7, M.DAMAGE_DEALT, 0, 120, false), nil, 'one ms before the gap ends')
eq(L.flashPlan(f, 1140, 7, M.DAMAGE_DEALT, 0, 120, false), 'chaos_hit_white', 'at the gap it flashes again')
eq(L.flashPlan(f, 2000, 20, M.HEAL or 23, 0, 100, false), nil, 'a heal does not flash')
eq(L.flashPlan(f, 2000, 20, 24, 0, 100, false), nil, 'experience does not flash')
eq(L.flashPlan(f, 2000, 20, M.DAMAGE_DEALT, 2, 100, false), nil, 'a damage-over-time tick does not flash')
eq(L.flashPlan(f, 2000, 20, M.DAMAGE_DEALT, 3, 100, false), nil, 'a mana drain does not flash')
eq(L.flashPlan(f, 2000, 20, M.DAMAGE_DEALT, 0, 0, false), nil, 'a zero hit does not flash')
eq(L.flashPlan(f, 2000, 0, M.DAMAGE_DEALT, 0, 10, false), nil, 'no creature id, no flash')
eq(L.flashPlan(f, 2000, nil, M.DAMAGE_DEALT, 0, 10, false), nil, 'nil creature id, no flash')
eq(L.flashPlan(f, 2000, 21, M.DAMAGE_DEALT, nil, 10, false), 'chaos_hit_white', 'a missing type is a plain hit')

-- the cap on flashes alive at once, and it opens as they end
local c = L.newFlasher()
local fired = 0
for id = 1, 20 do
  if L.flashPlan(c, 5000, id, M.DAMAGE_DEALT, 0, 10, false) then fired = fired + 1 end
end
eq(fired, L.FLASH.maxActive, 'at most maxActive flashes at once')
eq(L.flashPlan(c, 5079, 30, M.DAMAGE_DEALT, 0, 10, false), nil, 'still full 79 ms in')
eq(L.flashPlan(c, 5080, 30, M.DAMAGE_DEALT, 0, 10, false), 'chaos_hit_white', 'room again when they end')

-- the memory of old creatures is pruned
local p = L.newFlasher()
for id = 1, 200 do L.flashPlan(p, id * 3000, id, M.DAMAGE_DEALT, 0, 10, false) end
local n = 0
for _ in pairs(p.last) do n = n + 1 end
eq(n < 100, true, 'old creatures are forgotten')

-- shake strength
eq(L.shakeAmp(0, 0), 0, 'no percent, no shake')
eq(L.shakeAmp(0, 1499), 0, 'a plain 14.99% hit does not shake')
eq(L.shakeAmp(0, 1500), 2, 'a plain 15% hit shakes by 2')
eq(L.shakeAmp(0, 3000), 3, '30% shakes by 3')
eq(L.shakeAmp(0, 5000), 4, '50% shakes by 4')
eq(L.shakeAmp(0, 10000), 4, 'never above the cap')
eq(L.shakeAmp(1, 299), 0, 'a small critical hit does not shake')
eq(L.shakeAmp(1, 300), 2, 'a critical hit of 3% shakes by 2')
eq(L.shakeAmp(2, 5000), 4, 'a big tick still counts as a big hit')
eq(L.shakeAmp(nil, 'x'), 0, 'junk -> none')
eq(L.shakeAmp(0, -5), 0, 'negative -> none')
eq(L.shakeAmp(0, 65535) <= L.SHAKE.maxPx, true, 'u16 maximum stays under the cap')

-- shake run: starts, falls off, ends, gap, a stronger hit restarts
local function const(v) return function() return v end end
local s = L.newShake()
eq(L.shakeStart(s, 1000, 0), false, 'no strength, no shake')
eq(L.shakeStart(s, 1000, 3), true, 'starts')
eq(L.shakeNow(s, 1000), 3, 'full strength at the start')
eq(L.shakeNow(s, 1090) <= 2, true, 'falls off halfway')
eq(L.shakeNow(s, 1179) >= 1, true, 'still 1 px at the very end')
eq(L.shakeNow(s, 1180), 0, 'over after 180 ms')
local x, y, done = L.shakeOffset(s, 1000, const(0.99))
eq(x, 3, 'offset x at the top of the roll')
eq(y, 3, 'offset y at the top of the roll')
eq(done, false, 'running')
x, y, done = L.shakeOffset(s, 1000, const(0))
eq(x, -3, 'offset x at the bottom of the roll')
x, y, done = L.shakeOffset(s, 1000, const(0.5))
eq(x ~= 0 or y ~= 0, true, 'a running frame is never a no-op')
x, y, done = L.shakeOffset(s, 1200, const(0.5))
eq(x, 0, 'no offset when over')
eq(done, true, 'reports done')
eq(L.shakeStart(s, 1100, 2), false, 'a weaker hit while running does not restart')
eq(L.shakeStart(s, 1100, 4), true, 'a stronger hit while running restarts')
eq(L.shakeNow(s, 1100), 4, 'at the new strength')
eq(L.shakeStart(s, 1100 + 180 + 50, 3), false, 'inside the gap after the last start')
eq(L.shakeStart(s, 1100 + 300, 3), true, 'after the gap')
eq(L.shakeStart(L.newShake(), 5, 99), true, 'a huge strength starts')
local capped = L.newShake()
L.shakeStart(capped, 0, 99)
eq(L.shakeNow(capped, 0), L.SHAKE.maxPx, 'a huge strength is capped')

-- the cap holds for every frame of a long run with random rolls
local r = L.newShake()
L.shakeStart(r, 0, 4)
local worst, seed = 0, 12345
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
for t = 0, 400, 16 do
  local ox, oy = L.shakeOffset(r, t, rnd)
  worst = math.max(worst, math.abs(ox), math.abs(oy))
end
eq(worst <= L.SHAKE.maxPx, true, 'no frame goes over the cap')
eq(worst >= 1, true, 'the run moved the picture')

-- ---------------------------------------------------------------- spell colour light (O205)
eq(L.DEFAULTS.spellLight, true, 'spell light is on by default')
eq(L.optionOn('spellLight', nil), true, 'spell light option default')
eq(L.optionOn('spellLight', false), false, 'spell light option off')
-- every theme of the id lists has a colour, every colour is a valid 8-bit palette index, none is black
for theme in pairs(L.THEME_IDS) do
  local c = L.THEME_COLOR[theme]
  eq(c ~= nil and c > 0 and c < 216, true, 'colour of ' .. theme)
end
-- an id is in one theme only
local seen = {}
local dup = 0
for theme, list in pairs(L.THEME_IDS) do
  for _, e in ipairs(list) do
    local a, b = type(e) == 'table' and e[1] or e, type(e) == 'table' and e[2] or e
    for id = a, b do
      if seen[id] then dup = dup + 1 end
      seen[id] = true
    end
  end
end
eq(dup, 0, 'no effect id in two themes')
local fireC, fireR = L.lightFor(7)
eq(fireC, 5 * 36 + 2 * 6, 'fire is orange')
eq(fireR, L.LIGHT.radius, 'default radius')
eq(L.lightFor(762) ~= L.lightFor(7), true, 'ice and fire differ')
eq(L.lightFor(415), nil, 'combat feedback gives no light')
eq(L.lightFor(99999), nil, 'unknown effect gives no light')
eq(L.lightFor(nil), nil, 'no id gives no light')
eq(L.LIGHT.radius >= 1 and L.LIGHT.radius <= 3, true, 'radius 1-3 tiles')
eq(L.LIGHT.ms >= 250 and L.LIGHT.ms <= 400, true, 'life 250-400 ms')
-- fade: rises, peaks, falls to nothing
eq(L.fade(0), 0, 'fade starts at 0')
eq(L.fade(L.LIGHT.ms * L.LIGHT.attack), 1, 'fade peaks after the attack')
eq(L.fade(L.LIGHT.ms * 0.6) < 1 and L.fade(L.LIGHT.ms * 0.6) > L.fade(L.LIGHT.ms * 0.9), true, 'fade falls')
eq(L.fade(L.LIGHT.ms), 0, 'fade over at the end of the life')
eq(L.fade(-5), 0, 'no fade before the start')
eq(L.dim(L.THEME_COLOR.fire, 1), L.THEME_COLOR.fire, 'dim 1 keeps the colour')
eq(L.dim(L.THEME_COLOR.fire, 0), 0, 'dim 0 is black')
eq(L.dim(5 * 36 + 5 * 6 + 5, 0.5), 3 * 36 + 3 * 6 + 3, 'dim halves the levels')
eq(L.radiusAt(2, 0.01), 1, 'radius never under 1 while it shows')
eq(L.radiusAt(9, 1), L.LIGHT.maxRadius, 'radius capped')

local lights = L.newLights()
local p = { x = 100, y = 100, z = 7 }
local a = L.lightAdd(lights, 1000, p, 7, true)
eq(a ~= nil and a.color == fireC, true, 'a known effect lights')
eq(L.lightAdd(lights, 1000, p, 7, false), nil, 'option off -> no light')
eq(L.lightAdd(lights, 1000, p, 99999, true), nil, 'unknown effect -> no light')
eq(L.lightAdd(lights, 1030, p, 7, true), nil, 'same effect on the same tile is one light')
eq(L.lightAdd(lights, 1030, { x = 101, y = 100, z = 7 }, 7, true) ~= nil, true, 'another tile lights')
eq(L.lightAdd(lights, 1000, nil, 7, true), nil, 'no position -> no light')
-- the cap
local capped = L.newLights()
local made = 0
for i = 1, 40 do
  if L.lightAdd(capped, 5000, { x = 200 + i, y = 100, z = 7 }, 7, true) then made = made + 1 end
end
eq(made, L.LIGHT.max, 'at most the cap alive at once')
eq(#L.lightsNow(capped, 5000 + 50) <= L.LIGHT.max, true, 'never more than the cap drawn')
eq(L.lightAdd(capped, 5000 + L.LIGHT.ms, { x = 300, y = 100, z = 7 }, 7, true) ~= nil, true, 'room again after the life')
-- drawn lights fade and end
local live = L.newLights()
L.lightAdd(live, 0, p, 7, true)
local early = L.lightsNow(live, math.floor(L.LIGHT.ms * L.LIGHT.attack))
eq(#early, 1, 'drawn at the peak')
eq(early[1].color, fireC, 'full colour at the peak')
local late = L.lightsNow(live, math.floor(L.LIGHT.ms * 0.85))
eq(#late == 0 or late[1].color < fireC, true, 'dimmer late in the life')
eq(#L.lightsNow(live, L.LIGHT.ms), 0, 'gone after the life')
eq(#L.lightsNow(L.newLights(), 0), 0, 'nothing when nothing played')

-- living water and lava: the id sets and the option
eq(L.DEFAULTS.liquidShimmer, true, 'liquid shimmer is on by default')
eq(L.optionOn('liquidShimmer', nil), true, 'liquid shimmer option default')
eq(L.optionOn('liquidShimmer', false), false, 'liquid shimmer option off')
eq(L.liquidKind(629), 'water', 'stock swimmable shallows')
eq(L.liquidKind(4597), 'water', 'stock water first id')
eq(L.liquidKind(4614), 'water', 'stock water last id')
eq(L.liquidKind(4603), nil, 'between the stock water ranges')
eq(L.liquidKind(4615), nil, 'one past the stock water')
eq(L.liquidKind(729), 'lava', 'stock lava ground')
eq(L.liquidKind(4800), nil, 'a stock lava border is not a liquid')
eq(L.liquidKind(33456), 'water', 'deep lake water')
eq(L.liquidKind(33463), 'water', 'mountain shallows')
eq(L.liquidKind(33464), nil, 'not a liquid')
eq(L.liquidKind(35101), 'water', 'sewer water')
eq(L.liquidKind(35059), 'lava', 'lava')
eq(L.liquidKind(35073), 'lava', 'lava pool last piece')
eq(L.liquidKind(35060), nil, 'lava bubbles (a border) do not shimmer')
eq(L.liquidKind(35064), nil, 'the island floor does not shimmer')
eq(L.liquidKind(27485), nil, 'magma-veined obsidian floor is a plain ground')
eq(L.liquidKind(nil), nil, 'nil id')
eq(L.liquidKind('x'), nil, 'junk id')
eq(L.liquidKind('35059'), 'lava', 'an id as a string')
local list = L.liquidList()
local sawWater, sawLava, sorted, kindsOk = false, false, true, true
for i, e in ipairs(list) do
  if i > 1 and list[i - 1].id >= e.id then sorted = false end
  if e.kind == 1 then sawWater = true; kindsOk = kindsOk and L.liquidKind(e.id) == 'water' end
  if e.kind == 2 then sawLava = true; kindsOk = kindsOk and L.liquidKind(e.id) == 'lava' end
end
eq(#list, 6 + 6 + 6 + 8 + 1 + 3 + 1 + 4, 'liquid id count')
eq(sorted and sawWater and sawLava, true, 'the list is sorted and has both kinds')
eq(kindsOk, true, 'list kinds agree with liquidKind')
eq(L.LIQUID.kind.water, 1, 'water kind number of the engine table')
eq(L.LIQUID.kind.lava, 2, 'lava kind number of the engine table')

-- soft glow (O210): off by default, strength low and capped, the shader holds the owner's high threshold
eq(L.DEFAULTS.bloom, false, 'soft glow is off by default')
eq(L.bloomStrength(false), 0, 'off asks for no strength')
eq(L.bloomStrength(true), L.BLOOM.strength, 'on asks for the configured strength')
eq(L.BLOOM.strength <= 0.5, true, 'the strength is low')
eq(L.BLOOM.threshold >= 0.8, true, 'the threshold is high (luma 0.8 or more)')
eq(L.BLOOM.full > L.BLOOM.threshold and L.BLOOM.full <= 1, true, 'the ramp goes up to full')
do
  local saved = L.BLOOM.strength
  L.BLOOM.strength = 3
  eq(L.bloomStrength(true), L.BLOOM.maxStrength, 'a too high strength is capped')
  L.BLOOM.strength = -1
  eq(L.bloomStrength(true), 0, 'a negative strength is 0')
  L.BLOOM.strength = saved
end
do
  local f = io.open(dir .. '../../data/shaders/chaos_bloom_extract.frag', 'r')
  if f then
    local src = f:read('*a'); f:close()
    local lo, hi = src:match('smoothstep%(([%d%.]+),%s*([%d%.]+),%s*l%)')
    eq(tonumber(lo), L.BLOOM.threshold, 'the shader threshold is L.BLOOM.threshold')
    eq(tonumber(hi), L.BLOOM.full, 'the shader ramp end is L.BLOOM.full')
  end
end

-- target / follow / hover outline (O216)
eq(L.DEFAULTS.targetOutline, true, 'target outline is on by default')
eq(L.DEFAULTS.hoverOutline, false, 'hover outline is off by default')
do
  local both = { target = true, hover = true }
  local w = L.outlineWanted({ targetId = 5, followId = 6, hoverId = 7, meId = 1 }, both)
  eq(w[5], 'target', 'target kind'); eq(w[6], 'follow', 'follow kind'); eq(w[7], 'hover', 'hover kind')
  w = L.outlineWanted({ targetId = 5, followId = 5, hoverId = 5, meId = 1 }, both)
  eq(w[5], 'target', 'one creature has the strongest kind only')
  w = L.outlineWanted({ targetId = 5, followId = 6, hoverId = 6, meId = 1 }, both)
  eq(w[6], 'follow', 'follow beats hover')
  w = L.outlineWanted({ targetId = 5, followId = 6, hoverId = 7, meId = 1 }, { target = false, hover = true })
  eq(w[5], nil, 'target option off: no target outline'); eq(w[6], nil, 'and no follow outline'); eq(w[7], 'hover', 'hover still on')
  w = L.outlineWanted({ targetId = 5, hoverId = 7, meId = 1 }, { target = true, hover = false })
  eq(w[7], nil, 'hover option off'); eq(w[5], 'target', 'target on')
  w = L.outlineWanted({ hoverId = 1, targetId = 0, meId = 1 }, both)
  eq(next(w), nil, 'the local player and id 0 get nothing')
  eq(next(L.outlineWanted({}, both)), nil, 'empty state')
  -- diff
  eq(#L.outlineDiff({}, {}), 0, 'nothing to do')
  eq(#L.outlineDiff({ [5] = 'target' }, { [5] = 'target' }), 0, 'same hover creature again: no engine call')
  local ops = L.outlineDiff({ [5] = 'target', [7] = 'hover' }, { [5] = 'follow', [8] = 'hover' })
  eq(#ops, 3, 'clear 7, set 5 and 8')
  eq(ops[1].op == 'clear' and ops[1].id == 7, true, 'clears come first')
  eq(ops[2].op == 'set' and ops[2].id == 5 and ops[2].kind == 'follow', true, 'a kind change is a set')
  eq(ops[3].id, 8, 'new creature')
  -- args
  for _, k in ipairs({ 'target', 'follow', 'hover' }) do
    local a = L.outlineArgs(k)
    eq(type(a), 'table', k .. ' has args')
    for i = 1, 4 do eq(a[i] >= 0 and a[i] <= 255, true, k .. ' colour channel ' .. i) end
    eq(a[5] >= 1 and a[5] <= 3, true, k .. ' width 1-3')
  end
  eq(L.outlineArgs('order'), nil, 'order is not a kind'); eq(L.outlineArgs('x'), nil, 'unknown kind')
  eq(L.OUTLINE.target[6] > 0, true, 'the target outline pulses'); eq(L.OUTLINE.hover[4] < L.OUTLINE.target[4], true, 'hover is fainter')
  -- mouse gate
  local g = {}
  eq(L.mouseGate(g, 1000), true, 'first move looked at')
  eq(L.mouseGate(g, 1010), false, 'next one too soon')
  eq(L.mouseGate(g, 1033), true, 'after the gap')
  -- wiring
  local f = io.open(dir .. 'visualfx.lua', 'r')
  local src = f and f:read('*a') or ''
  if f then f:close() end
  eq(src:find("name == 'targetOutline'", 1, true) ~= nil, true, 'onOption handles targetOutline')
  eq(src:find("name == 'hoverOutline'", 1, true) ~= nil, true, 'onOption handles hoverOutline')
  eq(src:find('onAttackingCreatureChange', 1, true) ~= nil, true, 'target change is listened to')
  eq(src:find('onFollowingCreatureChange', 1, true) ~= nil, true, 'follow change is listened to')
  eq(src:find('setHighlight', 1, true) ~= nil, true, 'cosmetic outlines are coordinated')
end

do
  -- missile trails and arcs (O230, base patch 0147): on by default, the arc list is sane, the engine switch is wired
  eq(L.DEFAULTS.missileTrails, true, 'missile trails are on by default')
  local seen, sorted = {}, true
  local prev = 0
  for _, id in ipairs(L.ARC_MISSILES) do
    eq(type(id) == 'number' and id == math.floor(id) and id > 0 and id < 65536, true, 'arc id ' .. tostring(id) .. ' is a missile id')
    eq(seen[id], nil, 'arc id ' .. tostring(id) .. ' is listed once')
    seen[id] = true
    if id <= prev then sorted = false end
    prev = id
  end
  eq(sorted, true, 'the arc ids are ascending')
  eq(seen[2] and seen[3] and seen[1], true, 'bolt, arrow and spear arc')
  for _, spell in ipairs({ 4, 5, 11, 29, 30, 31 }) do eq(seen[spell], nil, 'spell missile ' .. spell .. ' stays straight') end
  local f = io.open(dir .. 'visualfx.lua', 'r')
  local src = f and f:read('*a') or ''
  if f then f:close() end
  local _, calls = src:gsub('Missile%.setTrails', '')
  eq(calls >= 3, true, 'setTrails is checked, called with the option and switched off at terminate')
  eq(src:find("name == 'missileTrails'", 1, true) ~= nil, true, 'onOption handles missileTrails')
  eq(src:find("optionValue('missileTrails')", 1, true) ~= nil, true, 'the option value is read')
  eq(src:find('applyMissileTrails()', 1, true) ~= nil, true, 'reapply sets it at game start')
  eq(src:find('L.ARC_MISSILES', 1, true) ~= nil, true, 'the arc list is sent')
end

do -- O235: option values are read once and refreshed by the options' apply
  local reads, store, up = 0, { hitFlash = false, bloom = true }, true
  local C = L.newOptionCache(function(name)
    reads = reads + 1
    if not up then return false end
    return true, store[name]
  end)
  eq(C.get('hitFlash'), false, 'cache: stored false')
  eq(C.get('hitFlash'), false, 'cache: second read')
  eq(C.get('bloom'), true, 'cache: stored true')
  eq(reads, 2, 'cache: one settings read per option')
  for _ = 1, 50 do C.get('hitFlash'); C.get('bloom') end
  eq(reads, 2, 'cache: hits do not read the settings')
  C.set('hitFlash', true)
  eq(C.get('hitFlash'), true, 'cache: set by the option change')
  C.set('bloom', 'junk')
  eq(C.get('bloom'), false, 'cache: junk is the default (bloom off)')
  eq(reads, 2, 'cache: set does not read')
  store.screenGrade = nil
  eq(C.get('screenGrade'), false, 'cache: nil screenGrade is the default, off')
  eq(C.get('sceneFade'), true, 'cache: nil sceneFade is the default, on')
  C.clear()
  store.hitFlash = false
  eq(C.get('hitFlash'), false, 'cache: clear reads again')
  up = false
  local C2 = L.newOptionCache(function() return false end)
  eq(C2.get('hoverOutline'), false, 'cache: no settings, default off')
  eq(C2.get('deathFade'), true, 'cache: no settings, default on')
  up = true
  local seen = 0
  local C3 = L.newOptionCache(function() seen = seen + 1; return seen > 1, true end)
  eq(C3.get('bloom'), false, 'cache: settings not ready, default')
  eq(C3.get('bloom'), true, 'cache: a failed read is not kept')
  local f = io.open(dir .. 'visualfx.lua', 'r')
  local src = f and f:read('*a') or ''
  if f then f:close() end
  eq(src:find('optionCache.set(name, value)', 1, true) ~= nil, true, 'onOption refreshes the cache')
  eq(src:find('optionCache.clear()', 1, true) ~= nil, true, 'game start clears the cache')
  local _, direct = src:gsub('pcall%(cs%.getOption', '')
  eq(direct, 1, 'getOption is called in one place only')
end

do -- O235: DEFAULTS match the value of each option in the base patches' dataset.lua entries (so a checkbox that shows a missing value matches)
  local root = dir .. '../../../base-patches/'
  local want = {}
  for _, n in ipairs(L.OPTIONS) do want[n] = true end
  local found = 0
  local ok = io.open(root .. '0126-visual-effects.patch', 'r')
  if ok then
    ok:close()
    for _, pf in ipairs({ '0126-visual-effects', '0127-spell-light', '0128-living-liquids', '0130-weather-option', '0132-map-bloom',
      '0134-soft-damage-numbers', '0136-target-outline-options', '0138-scene-fade-option', '0139-death-fade',
      '0144-ambient-particles-option', '0146-smooth-bars', '0147-missile-trails', '0149-light-flicker', '0161-cooldown-pulse' }) do
      local h = io.open(root .. pf .. '.patch', 'r')
      local text = h and h:read('*a') or ''
      if h then h:close() end
      for name, val in text:gmatch('\n%+  (%w+) = {\n%+    value = (%a+),') do
        if want[name] then
          found = found + 1
          eq(L.DEFAULTS[name], val == 'true', 'DEFAULTS.' .. name .. ' matches the dataset value')
        end
      end
    end
    eq(found, #L.OPTIONS, 'every visualfx option has a dataset default in the base patches')
  end
end

do
  -- glowing spell effects (O233, base patch 0152): bright themes glow, dark and soft ones do not, the list is sane and sent
  local ids = L.glowIds()
  eq(#ids > 40, true, 'a good number of effects glow: ' .. #ids)
  local prev, seen = 0, {}
  for _, id in ipairs(ids) do
    eq(type(id) == 'number' and id > 0 and id < 65536, true, 'glow id ' .. tostring(id) .. ' is an effect id')
    eq(id > prev, true, 'glow ids ascend and are unique at ' .. id)
    prev = id
    seen[id] = true
    eq(L.glows(id), true, 'listed id glows ' .. id)
    local theme = L.EFFECT_THEME[id]
    eq(L.GLOW_THEMES[theme] == true, true, 'glow id ' .. id .. ' has a glowing theme, not ' .. tostring(theme))
  end
  for theme in pairs(L.GLOW_THEMES) do eq(L.THEME_COLOR[theme] ~= nil, true, 'glow theme ' .. theme .. ' exists') end
  -- the dark, soft and solid themes keep the normal blend, whatever their ids
  for _, theme in ipairs({ 'blood', 'water', 'poison', 'frost', 'physical', 'death', 'shadow', 'earth', 'healing' }) do
    eq(L.GLOW_THEMES[theme], nil, theme .. ' is not a glow theme')
  end
  for id, theme in pairs(L.EFFECT_THEME) do
    if not L.GLOW_THEMES[theme] then eq(seen[id], nil, 'effect ' .. id .. ' (' .. theme .. ') stays normal') end
  end
  -- named cases: fire hit 16, energy hit 12, holy rings 8, the energy range 384-387 glow; blood 1, water 2, poof 3,
  -- block 4, death 18, poison 17, the explosion pair 5 and 6 (smoke) and the combat feedback range 415-423 do not
  for _, id in ipairs({ 7, 8, 12, 16, 38, 384, 387, 403, 405, 372, 378 }) do eq(L.glows(id), true, 'effect ' .. id .. ' glows') end
  for _, id in ipairs({ 1, 2, 3, 4, 5, 6, 9, 17, 18, 415, 416, 423, 628 }) do eq(L.glows(id), false, 'effect ' .. id .. ' stays normal') end
  eq(L.glows(nil), false, 'nil does not glow')
  eq(L.glows('x'), false, 'junk does not glow')
  eq(L.glows(0), false, '0 does not glow')
  eq(L.glows(-12), false, 'negative does not glow')
  eq(L.glows(12.5), false, 'a fraction does not glow')
  eq(L.glows(70000), false, 'over the engine bound does not glow')
  eq(L.glows('12'), true, 'a numeric string is an id')
  -- a skipped id of a glowing theme is the only way in and out of the list
  for id in pairs(L.GLOW_SKIP) do
    eq(L.EFFECT_THEME[id] ~= nil and L.GLOW_THEMES[L.EFFECT_THEME[id]] == true, true, 'skipped id ' .. id .. ' is of a glowing theme (else the skip is dead)')
    eq(seen[id], nil, 'skipped id ' .. id .. ' is not listed')
  end
  -- wired: tied to the spell light option, sent once, switched off at terminate, no new option
  eq(#L.OPTIONS, 18, 'still eighteen options (the glow work adds no checkbox)')
  local f = io.open(dir .. 'visualfx.lua', 'r')
  local src = f and f:read('*a') or ''
  if f then f:close() end
  eq(src:find('g_map.setGlowEffects', 1, true) ~= nil, true, 'the engine switch is called')
  eq(src:find('g_map.addGlowEffect', 1, true) ~= nil, true, 'the ids are sent')
  eq(src:find('L.glowIds()', 1, true) ~= nil, true, 'the id list comes from the logic file')
  local _, calls = src:gsub('setGlowEffects', '')
  eq(calls >= 3, true, 'checked, called with the option and switched off at terminate')
  eq(src:find("optionValue('glow", 1, true), nil, 'no option of its own')
end

if fails > 0 then
  print(fails .. ' of ' .. checks .. ' checks failed')
  os.exit(1)
end
print('visualfx_test: ' .. checks .. ' checks ok')
