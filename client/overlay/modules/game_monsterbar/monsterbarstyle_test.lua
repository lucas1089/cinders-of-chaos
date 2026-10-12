-- luajit monsterbarstyle_test.lua && lua5.3 monsterbarstyle_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'monsterbarstyle.lua')
local S = MonsterBarStyle
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- tier and role -> style
eq(S.key('normal'), 'normal', 'normal')
eq(S.key('magic'), 'magic', 'magic')
eq(S.key('rare'), 'rare', 'rare')
eq(S.key('legendary'), 'legendary', 'legendary')
eq(S.key('boss'), 'boss', 'boss')
eq(S.key('legendary', 'guardian'), 'guardian', 'a rift guardian (legendary tier) gets the guardian look')
eq(S.key('boss', 'omen'), 'omen', 'an omen guardian')
eq(S.key(nil, 'omen'), 'omen', 'an omen guardian without a tier')
eq(S.key('rare', 'nonsense'), 'rare', 'an unknown role keeps the tier')
eq(S.key('mythic'), 'normal', 'an unknown tier looks normal')
eq(S.key(nil, nil), 'normal', 'nothing known yet')
eq(S.images('boss').frame, '/images/chaos/monsterbar/frame_boss', 'frame image')
eq(S.images('bogus').fill, '/images/chaos/monsterbar/fill_normal', 'unknown style: normal images')

-- every style has its images in the overlay (run from the repo root or from the module folder)
local function exists(p)
  local f = io.open(p, 'rb')
  if f then f:close() return true end
  return false
end
local root
for _, r in ipairs({ dir .. '../../data', 'client/overlay/data' }) do
  if exists(r .. '/images/chaos/monsterbar/trail.png') then root = r end
end
if root then
  for key in pairs(S.STYLES) do
    for _, img in pairs(S.images(key)) do
      eq(exists(root .. img .. '.png'), true, 'image ' .. img)
    end
  end
  for key in pairs(S.MODS) do
    eq(exists(root .. S.mod(key) .. '.png'), true, 'chip ' .. key)
  end
  eq(exists(root .. S.IMAGES .. 'mods/unknown.png'), true, 'chip unknown')
end

-- text
eq(S.title('legendary', 'Legendary', 'Dragon'), 'Legendary Dragon', 'server label')
eq(S.title('magic', nil, 'Dragon'), 'Magic Dragon', 'style label')
eq(S.title('boss', nil, 'Ferocious Thing'), 'Ferocious Thing', 'a boss has no tag')
eq(S.title('guardian', 'Legendary', 'Rot King'), 'Rift Guardian Rot King', 'the role tag wins over the tier label')
eq(S.title('omen', nil, 'Morvane'), 'Omen Guardian Morvane', 'omen tag')
eq(S.title('guardian', nil, 'Rot King'), 'Rift Guardian Rot King', 'guardian tag')
eq(S.title('normal', '', 'Rat'), 'Rat', 'normal')
eq(S.levelText(245), 'Lv 245', 'level')
eq(S.levelText(245.7), 'Lv 245', 'level floored')
eq(S.levelText(0), nil, 'no level')
eq(S.levelText(nil), nil, 'no level sent')
eq(S.percentText(73), '73%', 'percent')
eq(S.percentText(140), '100%', 'percent capped')
eq(S.percentText(-3), '0%', 'percent floored')
eq(S.fillWidth(50, 344), 172, 'half')
eq(S.fillWidth(100, 344), 344, 'full')
eq(S.fillWidth(0, 344), 0, 'empty')
eq(S.fillWidth(0.1, 344), 1, 'a sliver stays')

-- modifiers
local img, tip = S.mod('Blazing')
eq(img, '/images/chaos/monsterbar/mods/blazing', 'chip image')
eq(tip:find('^Blazing') ~= nil, true, 'chip tooltip')
img, tip = S.mod('Cursed Thing')
eq(img, '/images/chaos/monsterbar/mods/unknown', 'unknown modifier')
eq(tip, 'Cursed Thing', 'unknown modifier: its name')

-- damage trail
local t = S.trailHit(nil, 100, 100)
eq(t.value, 100, 'trail starts at the health')
t = S.trailHit(t, 100, 70)
eq(t.value, 100, 'hit: the lost part stays lit')
eq(t.hold, S.TRAIL_HOLD, 'hit: held')
local moving
t, moving = S.trailStep(t, 70, 200)
eq(t.value, 100, 'held: no shrink yet')
eq(moving, true, 'held: still moving')
t = S.trailStep(t, 70, 200) -- the rest of the hold
eq(t.hold, 0, 'hold over')
t = S.trailHit(t, 70, 60) -- a second hit while lit keeps the top and holds again
eq(t.value, 100, 'second hit: top kept')
eq(t.hold, S.TRAIL_HOLD, 'second hit: held again')
local steps = 0
repeat
  t, moving = S.trailStep(t, 60, 30)
  steps = steps + 1
until not moving or steps > 1000
eq(t.value, 60, 'trail reaches the health')
eq(steps * 30 < 2000, true, 'within two seconds')
-- a shrink never overshoots
t = { value = 61, hold = 0 }
t = S.trailStep(t, 60, 1000)
eq(t.value, 60, 'no overshoot')
-- healed above the trail: nothing lit
t = S.trailHit({ value = 50, hold = 100 }, 40, 80)
eq(t.value, 80, 'healed: trail follows')
eq(t.hold, 0, 'healed: no hold')
t, moving = S.trailStep(t, 80, 30)
eq(moving, false, 'healed: still')
-- monotone: each step shrinks or holds
t = S.trailHit(nil, 100, 100); t = S.trailHit(t, 100, 10)
local last, ok = t.value, true
for _ = 1, 100 do
  t = S.trailStep(t, 10, 16)
  if t.value > last or t.value < 10 then ok = false end
  last = t.value
end
eq(ok, true, 'monotone shrink, never below the health')

print(string.format('monsterbar style: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
