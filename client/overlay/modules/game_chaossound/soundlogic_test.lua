-- luajit soundlogic_test.lua && lua5.3 soundlogic_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'soundlogic.lua')
dofile(dir .. '../game_visualfx/visualfx_logic.lua')
local S = ChaosSoundLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function near(a, b, what) eq(a ~= nil and math.abs(a - b) < 1e-9, true, what .. ' (' .. tostring(a) .. ' vs ' .. tostring(b) .. ')') end

-- ---------------------------------------------------------------- the files
-- every file a set names is on disk, and every file on disk is named by a set (or the quiet ones are not forgotten)
local function exists(path)
  local f = io.open(path, 'rb')
  if f then f:close() end
  return f ~= nil
end
local named = {}
for _, f in ipairs(S.allFiles()) do
  named[f] = true
  eq(exists(dir .. 'sounds/' .. f .. '.ogg'), true, 'file ' .. f .. '.ogg exists')
end
do
  local csv = io.open(dir .. '../../../tools/sfx_sources.csv', 'rb')
  local text = csv and csv:read('*a') or ''
  if csv then csv:close() end
  local rows = 0
  for name in text:gmatch('\n([%w_]+),') do
    rows = rows + 1
    eq(named[name], true, 'csv row ' .. name .. ' is used by a set')
  end
  eq(rows, #S.allFiles(), 'the csv has a row for each file of the sets')
end
for key, set in pairs(S.SETS) do
  eq(#set.files >= 1, true, key .. ' has files')
  eq(set.gain > 0 and set.gain <= 1, true, key .. ' gain in range')
  eq(set.gap > 0 and set.ms > 0, true, key .. ' gap and length')
  local ok = false
  for _, g in ipairs(S.GROUPS) do if g == set.group then ok = true end end
  eq(ok, true, key .. ' group is known')
end

-- ---------------------------------------------------------------- theme mapping
local themes = VisualFxLogic.EFFECT_THEME
local function ev(id) return (S.effectEvent(id, themes)) end
eq(ev(5), 'fire', 'explosion area (5) is fire')          -- THEME_IDS fire {5, 7}
eq(ev(37), 'fire', 'effect 37 is fire')
eq(ev(44), 'ice', 'frost effect (42-44) is ice')
eq(ev(12), 'energy', 'energy effect 12')
eq(ev(11), 'energy', 'arcane plays the energy set')
eq(ev(8), 'holy', 'holy effect 8')
eq(ev(18), 'death', 'death effect 18')
eq(ev(395), 'death', 'shadow plays the death set')
eq(ev(35), 'earth', 'earth effect 35')
eq(ev(9), 'earth', 'poison plays the earth set')
eq(ev(10), 'physical', 'physical effect 10')
eq(ev(15), 'heal', 'healing effect 15')
eq(ev(1), nil, 'blood is silent')
eq(ev(2), nil, 'water is silent')
eq(ev(99999), nil, 'unknown effect is silent')
eq(ev(nil), nil, 'nil effect is silent')
eq(ev('x'), nil, 'junk effect is silent')
do
  local k, own = S.effectEvent(3, themes)
  eq(k, 'block', 'stock block hit is a block'); eq(own, true, 'a block counts on the own tile only')
  k, own = S.effectEvent(416, themes)
  eq(k, 'dodge', 'dodge whoosh is a dodge'); eq(own, true, 'a dodge counts on the own tile only')
  k, own = S.effectEvent(5, themes)
  eq(own, false, 'a spell is not own-tile only')
  eq(S.effectEvent(5, nil), nil, 'no theme table: silent')
end
-- every theme of the visual effects table either plays a set or is on the silent list; every mapped set exists
do
  local silent = { blood = true, water = true }
  for theme in pairs(VisualFxLogic.THEME_IDS) do
    eq(S.THEME_SOUND[theme] ~= nil or silent[theme] == true, true, 'theme ' .. theme .. ' is mapped or silent')
  end
  for theme, key in pairs(S.THEME_SOUND) do
    eq(S.SETS[key] ~= nil, true, 'theme ' .. theme .. ' -> set ' .. key .. ' exists')
    eq(VisualFxLogic.THEME_IDS[theme] ~= nil, true, 'theme ' .. theme .. ' is a theme of game_visualfx')
  end
  -- the eight elements of the brief
  for _, k in ipairs({ 'fire', 'ice', 'energy', 'holy', 'death', 'earth', 'physical', 'heal' }) do
    eq(S.SETS[k] ~= nil and S.SETS[k].group == 'spells', true, 'element set ' .. k)
  end
end

-- ---------------------------------------------------------------- damage numbers and the mode/type numbers
eq(S.MODE.DAMAGE_DEALT, VisualFxLogic.MODE.DAMAGE_DEALT, 'mode dealt = visualfx')
eq(S.MODE.DAMAGE_RECEIVED, VisualFxLogic.MODE.DAMAGE_RECEIVED, 'mode received = visualfx')
eq(S.MODE.DAMAGE_OTHERS, VisualFxLogic.MODE.DAMAGE_OTHERS, 'mode others = visualfx')
eq(S.TYPE.CRITICAL, VisualFxLogic.TYPE.CRITICAL, 'type critical = visualfx')
eq(S.impactEvent(21, 0, 50), 'hit', 'your hit')
eq(S.impactEvent(21, 1, 50), 'crit', 'your critical hit')
eq(S.impactEvent(21, 2, 50), nil, 'a burn tick is silent')
eq(S.impactEvent(21, 4, 50), nil, 'mana gain is silent')
eq(S.impactEvent(21, 5, 50), nil, 'energy shield is silent')
eq(S.impactEvent(22, 0, 50), 'hurt', 'a hit you take')
eq(S.impactEvent(22, 1, 50), 'hurt', 'a critical you take')
eq(S.impactEvent(22, 2, 50), nil, 'a tick you take is silent')
eq(S.impactEvent(25, 0, 50), nil, 'other players numbers are silent')
eq(S.impactEvent(23, 0, 50), nil, 'healing numbers are silent')
eq(S.impactEvent(24, 0, 50), nil, 'experience is silent')
eq(S.impactEvent(21, 0, 0), nil, 'a zero hit is silent')
eq(S.impactEvent(21, nil, 5), 'hit', 'an older server (no type) still plays a hit')
eq(S.impactEvent(nil, 0, 5), nil, 'no mode is silent')

-- ---------------------------------------------------------------- kills
do
  local hits = S.newHits()
  S.noteHit(hits, 7, 1000)
  eq(S.isMyKill(hits, 8, 1100), false, 'a creature you did not hit')
  eq(S.isMyKill(hits, 7, 2000), true, 'a creature you hit a second ago')
  eq(S.isMyKill(hits, 7, 2100), false, 'one kill sounds once')
  S.noteHit(hits, 9, 1000)
  eq(S.isMyKill(hits, 9, 1000 + S.KILL_WINDOW + 1), false, 'too long after your last hit')
  S.noteHit(hits, 0, 1000); S.noteHit(hits, nil, 1000)
  eq(next(hits), nil, 'creature id 0 / nil is not kept')
  S.noteHit(hits, 5, 0); S.noteHit(hits, 6, 5000)
  S.prune(hits, 5000)
  eq(hits[5], nil, 'prune drops the old'); eq(hits[6], 5000, 'prune keeps the new')
end

-- ---------------------------------------------------------------- loot
eq(S.lootEvent({ { rank = 3 } }, false), nil, 'Magic is silent')
eq(S.lootEvent({ { rank = 4 } }, false), 'loot_rare', 'Rare')
eq(S.lootEvent({ { rank = 5 }, { rank = 4 } }, false), 'loot_great', 'the best drop decides: Legendary')
eq(S.lootEvent({ { rank = 10 } }, false), 'loot_great', 'Divine')
eq(S.lootEvent({ { rank = 100 }, { rank = 4 } }, false), 'loot_unique', 'unique')
eq(S.lootEvent({ { rank = 100 } }, true), nil, 'the loot filter already sounded an alert: silent')
eq(S.lootEvent({}, false), nil, 'no drops')
eq(S.lootEvent(nil, false), nil, 'no table')
eq(S.lootEvent({ 'junk', { text = 'x' } }, false), nil, 'junk rows')

-- ---------------------------------------------------------------- settings
do
  local d = S.normalize(nil)
  eq(d.enabled, true, 'on by default'); eq(d.volume, 'normal', 'normal volume'); eq(d.combat, true, 'combat on')
  eq(d.spells, true, 'spells on'); eq(d.events, true, 'events on'); eq(d.ui, false, 'interface sounds are off by default')
  local t = S.normalize({ enabled = false, volume = 'loud', ui = true, combat = 'yes', spells = false })
  eq(t.enabled, false, 'off is kept'); eq(t.volume, 'loud', 'volume kept'); eq(t.ui, true, 'ui on kept')
  eq(t.combat, true, 'junk -> default'); eq(t.spells, false, 'false kept')
  eq(S.normalize({ volume = 'deafening' }).volume, 'normal', 'junk volume -> normal')
  eq(S.normalize('x').enabled, true, 'not a table -> defaults')
end

-- ---------------------------------------------------------------- distance
near(S.distanceGain(0), 1, 'on the player: full')
near(S.distanceGain(1), 1, 'next to the player: full')
near(S.distanceGain(S.MAX_DIST), S.MIN_FADE, 'at the edge: the minimum')
eq(S.distanceGain(S.MAX_DIST + 0.5), nil, 'beyond: skipped')
eq(S.distanceGain(5) < 1 and S.distanceGain(5) > S.MIN_FADE, true, 'in between: faded')
eq(S.distanceGain(3) > S.distanceGain(6), true, 'farther is quieter')
eq(S.distance({ x = 10, y = 10, z = 7 }, { x = 13, y = 8, z = 7 }), 3, 'distance is the bigger axis')
eq(S.distance({ x = 10, y = 10, z = 7 }, { x = 10, y = 10, z = 8 }) > S.MAX_DIST, true, 'another floor is out of reach')
eq(S.distance(nil, { x = 1, y = 1, z = 1 }), 0, 'no position: 0')

-- ---------------------------------------------------------------- the mixer
local function seq(list)
  local i = 0
  return function(n) i = i % #list + 1; return math.min(list[i], n) end
end
do
  local m = S.newMixer()
  local path, gain = S.request(m, 'fire', 0, { rand = seq({ 1 }) })
  eq(path, S.DIR .. 'fire_1.ogg', 'first variant')
  near(gain, 0.60 * S.VOLUMES.normal, 'gain = set gain x volume')
  eq(select(2, S.request(m, 'fire', 100, {})), 'gap', 'the same event inside its gap')
  eq(S.request(m, 'fire', 200, { rand = seq({ 1 }) }) ~= nil, true, 'after the gap it plays')
  eq(select(2, S.request(m, 'nothing', 0, {})), 'unknown', 'unknown event')
end
-- variants: never the same file twice in a row, and every file comes up
do
  local m = S.newMixer()
  local last, seen, repeats = nil, {}, 0
  math.randomseed(7)
  for i = 1, 300 do
    local p = S.request(m, 'ice', i * 1000)
    if p == last then repeats = repeats + 1 end
    last = p; seen[p] = true
  end
  eq(repeats, 0, 'no variant twice in a row')
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  eq(n, 3, 'all three ice variants are used')
  -- a one-file set always plays its file
  eq(S.request(m, 'levelup', 1e6, {}), S.DIR .. 'levelup.ogg', 'one file')
end
-- off switches and volume
do
  local m = S.newMixer()
  eq(select(2, S.request(m, 'hit', 0, { settings = S.normalize({ enabled = false }) })), 'off', 'master switch off')
  eq(select(2, S.request(m, 'hit', 0, { settings = S.normalize({ combat = false }) })), 'off', 'combat group off')
  eq(S.request(m, 'fire', 0, { settings = S.normalize({ combat = false }) }) ~= nil, true, 'other groups unaffected')
  eq(select(2, S.request(m, 'ui_click', 0, {})), 'off', 'interface sounds are off by default')
  eq(S.request(m, 'ui_click', 0, { settings = S.normalize({ ui = true }) }) ~= nil, true, 'interface sounds when switched on')
  eq(select(2, S.request(m, 'goal', 0, { volume = 0 })), 'mute', 'the client channel gain 0 mutes')
  local _, g1 = S.request(S.newMixer(), 'goal', 0, { volume = 1 })
  local _, g2 = S.request(S.newMixer(), 'goal', 0, { volume = 0.5 })
  near(g2, g1 / 2, 'the channel gain scales the gain')
  local _, gl = S.request(S.newMixer(), 'goal', 0, { settings = S.normalize({ volume = 'loud' }) })
  local _, gq = S.request(S.newMixer(), 'goal', 0, { settings = S.normalize({ volume = 'quiet' }) })
  eq(gl > g1 and g1 > gq, true, 'loud > normal > quiet')
  eq(gl <= 1, true, 'the gain never goes over 1')
end
-- distance in the mixer
do
  local m = S.newMixer()
  eq(select(2, S.request(m, 'fire', 0, { dist = S.MAX_DIST + 2 })), 'far', 'an event off screen is skipped')
  local _, near1 = S.request(m, 'ice', 0, { dist = 0 })
  local _, far1 = S.request(m, 'earth', 0, { dist = 8 })
  eq(near1 > 0 and far1 > 0 and far1 < 0.6 * S.VOLUMES.normal, true, 'a far event is quieter')
  eq(select(2, S.request(m, 'fire', 10, { dist = S.MAX_DIST + 2 })), 'far', 'a skipped event does not start the gap')
  eq(S.request(m, 'fire', 10, { dist = 2 }) ~= nil, true, 'and the next near one plays')
end
-- an area spell on 20 monsters: 20 hit numbers and 20 effects in one frame play a few sounds
do
  local m = S.newMixer()
  local played = 0
  for i = 1, 20 do
    -- the effect of each tile, then the number of each monster, all at the same ms
    if S.request(m, 'fire', 1000, { dist = 3 }) then played = played + 1 end
    if S.request(m, 'hit', 1000, { dist = 0 }) then played = played + 1 end
  end
  eq(played <= S.BURST_MAX, true, 'an area spell plays at most BURST_MAX sounds (' .. played .. ')')
  eq(played >= 1, true, 'but not none')
  -- the burst passes; later it plays again
  eq(S.request(m, 'fire', 1000 + S.BURST_MS + 200, { dist = 3 }) ~= nil, true, 'plays again after the burst window')
end
-- a long fight: sounds per second are bounded for ordinary events
do
  local m = S.newMixer()
  local played = 0
  local t = 0
  while t < 3000 do -- 3 s, a hit and four spell sets every 25 ms
    for _, k in ipairs({ 'hit', 'fire', 'ice', 'earth', 'holy' }) do
      -- distinct times: a new ms each call so only the limits stop it
      if S.request(m, k, t, { dist = 2 }) then played = played + 1 end
    end
    t = t + 25
  end
  eq(played <= 3 * S.SECOND_MAX + 3, true, 'at most about ' .. S.SECOND_MAX .. ' ordinary sounds a second (' .. played .. ' in 3 s)')
  eq(played >= 6, true, 'and the fight is not silent (' .. played .. ')')
end
-- the cap on sounds sounding at once; an important event goes above it
do
  local m = S.newMixer()
  m.active = {}
  for i = 1, S.MAX_ACTIVE do m.active[i] = { at = 5000 } end
  eq(select(2, S.request(m, 'ice', 1000, {})), 'cap', 'the cap stops an ordinary sound')
  eq(S.request(m, 'levelup', 1000, {}) ~= nil, true, 'a level up goes above the cap')
  for i = 1, S.HARD_CAP do m.active[i] = { at = 5000 } end
  eq(select(2, S.request(m, 'loot_rare', 2000, {})), 'cap', 'but not above the hard cap')
  eq(S.request(m, 'ice', 6000, {}) ~= nil, true, 'sounds that ended free their place')
end
-- important events are not eaten by the burst rule the way fluff is
do
  local m = S.newMixer()
  for _, k in ipairs({ 'hit', 'fire', 'ice' }) do eq(S.request(m, k, 50, { dist = 1 }) ~= nil, true, 'burst fill ' .. k) end
  eq(select(2, S.request(m, 'earth', 50, { dist = 1 })), 'burst', 'the 4th ordinary sound in a burst is dropped')
  eq(S.request(m, 'kill', 50, { dist = 1 }) ~= nil, true, 'a kill still sounds')
  eq(S.request(m, 'crit', 50, { dist = 1 }) ~= nil, true, 'a crit still sounds')
  eq(select(2, S.request(m, 'goal', 50, { dist = 1 })), 'burst', 'but the burst bonus is limited too')
end
-- a clean state: a new mixer has no memory
do
  local m = S.newMixer()
  eq(next(m.last), nil, 'new mixer: no last')
  eq(#m.active, 0, 'new mixer: nothing active')
end

-- live sources: a stuck one is stopped after its length + slack, an ended one is let go, the list is bounded
do
  local list = {}
  local a, b, c = { n = 'a' }, { n = 'b' }, { n = 'c' }
  S.track(list, a, 1000, 500)
  S.track(list, b, 1000, 5000)
  S.track(list, nil, 1000, 5000)
  eq(#list, 2, 'a nil source is not tracked')
  eq(#S.reap(list, 2000, nil), 0, 'nothing is due inside length + slack')
  local due = S.reap(list, 1000 + 500 + S.REAP_SLACK, nil)
  eq(#due, 1, 'one is due after its length + slack')
  eq(due[1], a, 'the short one')
  eq(#list, 1, 'the other stays')
  S.track(list, c, 1000, 100)
  local ended = { [c] = true }
  eq(#S.reap(list, 1200, function(src) return not ended[src] end), 0, 'an ended source is let go, not stopped')
  eq(#list, 1, 'only the running one is left')
  eq(#S.reap(list, 0, function() error('boom') end), 0, 'a failing probe keeps the source')
  eq(#list, 1, 'still tracked after a failing probe')
  for i = 1, S.MAX_TRACKED + 10 do S.track(list, { i }, 1000, 100) end
  eq(#list, S.MAX_TRACKED, 'the list is bounded')
end

-- every sound decodes to the engine's cache size or less (mono 16 bit): the engine streams a longer one
do
  for key, set in pairs(S.SETS) do
    eq(set.ms / 1000 * 44100 * 2 <= 100000, true, key .. ' fits the engine cache (MAX_CACHE_SIZE 100000 bytes)')
  end
end

print(string.format('soundlogic_test: %d checks, %d failed', checks, fails))
os.exit(fails == 0 and 0 or 1)
