-- luajit helpertimers_test.lua && lua5.3 helpertimers_test.lua (CI runs every *_test.lua from the repo root)
-- The helper's cooldown channels (ChaosHelperTimers) and base patch 0062, which makes mods/game_helper use them.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helpertimers.lua')
local T = ChaosHelperTimers
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(not not c, true, what) end

-- channels from the spell groups
eq(T.castChannel({ [2] = 1000 }), 'heal', 'healing group')
eq(T.castChannel({ [1] = 2000 }), 'attack', 'attack group')
eq(T.castChannel({ [1] = 2000, [4] = 8000 }), 'attack', 'attack with the special group')
eq(T.castChannel({ [3] = 2000 }), 'support', 'support group')
eq(T.castChannel({ [3] = 10000, [2] = 10000 }), 'heal', 'a support spell that also holds healing counts as heal')
eq(T.castChannel(nil), 'support', 'no group')
eq(T.runeChannel(2), 'healRune', 'healing rune (group number)')
eq(T.runeChannel(1), 'attackRune', 'attack rune')
eq(T.runeChannel({ [1] = 2000 }), 'attackRune', 'attack rune (group table)')
eq(T.runeChannel(3), 'supportRune', 'support rune')

-- heal and attack casts never share a rate guard
local st = T.new()
for i = 1, 4 do
  ok(T.castAllowed(st, 'attack', 'atk' .. i, 100 * i), 'attack cast ' .. i)
end
eq(T.castAllowed(st, 'attack', 'atk5', 450), false, 'the attack channel is full for this second')
ok(T.castAllowed(st, 'heal', 'saen', 450), 'a heal goes out while the attack channel is full')
ok(T.castAllowed(st, 'support', 'tor', 460), 'a support cast too')
eq(T.castAllowed(st, 'heal', 'saen', 700), false, 'the same heal words wait their gap')
ok(T.castAllowed(st, 'heal', 'saen', 950), 'then go again')
ok(T.castAllowed(st, 'attack', 'atk5', 1101), 'the attack channel frees after its second')
-- each channel stays limited on its own (no flood)
local n = 0
for i = 0, 99 do
  if T.castAllowed(st, 'heal', 'h' .. i, 2000 + i) then n = n + 1 end
end
eq(n, 4, 'at most 4 heals in a second')
n = 0
for i = 0, 99 do
  if T.castAllowed(st, 'nonsense', 's' .. i, 5000 + i) then n = n + 1 end
end
eq(n, 3, 'an unknown channel uses the support guard')

-- object uses: a potion and the runes never wait for each other
st = T.new()
ok(T.useReady(st, 'potion', 0), 'potion ready')
T.used(st, 'attackRune', 0)
ok(T.useReady(st, 'potion', 10), 'an attack rune does not hold the potion')
ok(T.useReady(st, 'healRune', 10), 'nor the healing rune')
eq(T.useReady(st, 'attackRune', 999), false, 'the attack rune waits its own second')
ok(T.useReady(st, 'attackRune', 1000), 'then is ready')
T.used(st, 'potion', 20)
eq(T.useReady(st, 'potion', 500), false, 'potion exhaust')
ok(T.useReady(st, 'attackRune', 1000) and T.useReady(st, 'healRune', 500), 'a potion holds no rune')
T.used(st, 'food', 30, 1500)
eq(T.useReady(st, 'food', 1529), false, 'food: its own duration')
ok(T.useReady(st, 'potion', 1020), 'food holds no potion')
T.reset(st)
ok(T.useReady(st, 'food', 31), 'reset (logout)')

-- configuration merges over the defaults
st = T.new({ cast = { heal = { maxPerSecond = 6 } }, use = { potion = 900 } })
eq(st.cfg.cast.heal.maxPerSecond, 6, 'heal rate set')
eq(st.cfg.cast.heal.sameWordsGap, 500, 'heal gap kept')
eq(st.cfg.cast.attack.maxPerSecond, 4, 'attack untouched')
eq(st.cfg.use.potion, 900, 'potion ms set')
eq(T.defaults.use.potion, 1000, 'defaults untouched')

-- base patch 0062 routes the helper through these channels
local function read(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local t = f:read('*a')
  f:close()
  return t
end
local patchDir = dir .. '../../../base-patches/'
local patch = read(patchDir .. '0062-helper-cooldown-channels.patch')
ok(patch ~= nil, 'base patch 0062 found')
if patch then
  local plus, minus = {}, {}
  for line in patch:gmatch('[^\n]*') do
    if line:sub(1, 1) == '+' and line:sub(1, 3) ~= '+++' then plus[#plus + 1] = line:sub(2) end
    if line:sub(1, 1) == '-' and line:sub(1, 3) ~= '---' then minus[#minus + 1] = line:sub(2) end
  end
  plus, minus = table.concat(plus, '\n'), table.concat(minus, '\n')
  ok(plus:find('ChaosHelperTimers.castAllowed(t, channel or "support", words, now)', 1, true), 'cast guard per channel')
  ok(plus:find('helperCastAllowed(spell.words, "heal")', 1, true), 'heals use the heal guard')
  ok(plus:find('helperCastAllowed(spell.words, castChannel)', 1, true), 'the shooter its spell channel')
  ok(minus:find('local charging = (rotation and ChaosHelperRotation.channeling(rotation, castAt)) or', 1, true),
    'a heal no longer waits for a charging attack cast')
  ok(plus:find('objectUseReady("potion", now)', 1, true), 'potions wait only for the potion timer')
  ok(minus:find('if potionTurnCooldown > now then', 1, true), 'no potion turn after a rune')
  ok(plus:find('objectUseReady("healRune"', 1, true), 'the healing rune its own timer')
  ok(plus:find('_Helper.isObjectUseOnCooldown(runeChannel)', 1, true), 'shooter runes their channel')
  ok(plus:find('objectUseReady("food"', 1, true), 'special foods their own timer')
  ok(not plus:find('multiUseExDelay > now', 1, true), 'no shared object-use check added')
end

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('helpertimers_test: OK')
