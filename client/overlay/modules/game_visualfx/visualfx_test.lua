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
local wantDefault = { hitFlash = true, screenShake = true, creatureShadow = true, screenGrade = false, spellLight = true, liquidShimmer = true, weather = true, bloom = false, numberMotion = true }
for _, name in ipairs(L.OPTIONS) do
  local d = wantDefault[name]
  eq(L.optionOn(name, nil), d, name .. ' default')
  eq(L.optionOn(name, false), false, name .. ' off is kept')
  eq(L.optionOn(name, true), true, name .. ' on is kept')
  eq(L.optionOn(name, 'no'), d, name .. ' junk -> default')
  eq(L.optionOn(name, 0), d, name .. ' number -> default')
end
eq(#L.OPTIONS, 9, 'nine options')
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

if fails > 0 then
  print(fails .. ' of ' .. checks .. ' checks failed')
  os.exit(1)
end
print('visualfx_test: ' .. checks .. ' checks ok')
