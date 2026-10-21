-- luajit tooltiplogic_test.lua && lua5.3 tooltiplogic_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'tooltiplogic.lua')
local L = ItemTooltipLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- keys
local key, plain = L.cacheKey({ id = 1873000000123, ver = 3054 }, 3400, 1, { x = 65535, y = 6, z = 0 })
eq(key, '1873000000123:3054', 'key from the per-item id and version')
eq(plain, false, 'not plain')
key, plain = L.cacheKey({ id = 0, ver = 0 }, 3031, 37, { x = 65535, y = 64, z = 3 })
eq(key, 'p:65535:64:3:3031:37', 'plain key: position, id and count')
eq(plain, true, 'plain')
eq(L.askable({ x = 65535, y = 1, z = 0 }), true, 'inventory')
eq(L.askable({ x = 65535, y = 65, z = 4 }), true, 'container')
eq(L.askable({ x = 1000, y = 1000, z = 7 }), false, 'map items are not asked')
eq(L.askable(nil), false, 'no position')
eq(L.posKey({ x = 65535, y = 6, z = 0 }, 12), '65535,6,0,0,12', 'pos key')
eq(L.inventoryPos(9).y, 9, 'inventory position')
eq(L.iidText(1878573878083590), '1878573878083590', 'big id written in full')
eq(L.posKey({ x = 65535, y = 64, z = 4 }, '1878573878083590'), L.posKey({ x = 65535, y = 64, z = 4 }, 1878573878083590),
  'the echoed string id matches the number')

-- ---------------------------------------------------------------- cache
local c = L.newCache()
L.cachePut(c, 'a', { name = 'A' }, false, 100)
L.cachePut(c, 'p', { name = 'P' }, true, 100)
eq(L.cacheGet(c, 'a', 100000).name, 'A', 'keyed entries do not expire')
eq(L.cacheGet(c, 'p', 100 + L.PLAIN_TTL).name, 'P', 'plain entry within its time')
eq(L.cacheGet(c, 'p', 101 + L.PLAIN_TTL), nil, 'plain entry expired')
local max = L.MAX_CACHE
L.MAX_CACHE = 3
for i = 1, 5 do L.cachePut(c, 'k' .. i, { i = i }, false, 0) end
eq(L.cacheGet(c, 'a', 0), nil, 'oldest dropped')
eq(L.cacheGet(c, 'k5', 0).i, 5, 'newest kept')
eq(#c.order, 3, 'size limit')
L.MAX_CACHE = max

-- ---------------------------------------------------------------- formatting
eq(L.formatValue(3, 'pct', true), '+3%', 'signed percent')
eq(L.formatValue(2.2, 'sec'), '2.2s', 'seconds')
eq(L.formatValue(1.25, nil), '1.25', 'decimals')
eq(L.formatValue(15, nil, true), '+15', 'signed flat')
eq(L.formatValue(-4, 'pct', true), '-4%', 'negative')
eq(L.formatValue(1234, 'est'), '~1,234', 'an estimate is marked with ~')
eq(L.diffText({ d = -120, fmt = 'est', l = 'Estimated DPS' }), '-~120 Estimated DPS', 'estimate difference')
local w = L.wrap('Every soul it cuts only feeds the hunger of its blade. (Requires level 120.)', 30)
eq(#w, 3, 'wrapped in three lines')
eq(w[1], 'Every soul it cuts only feeds', 'first line')
for _, line in ipairs(w) do eq(#line <= 30, true, 'line length') end
eq(#L.wrap('', 10), 0, 'empty text')
eq(L.title('magic sword'), 'Magic sword', 'capital first letter')
eq(L.title('Soulreaper'), 'Soulreaper', 'already capital')

-- ---------------------------------------------------------------- lines
local sword = {
  key = '1:2', id = 3400, name = 'magic sword', kind = 'weapon', slot = 'Weapon', rarity = 4, rarityName = 'Rare',
  level = 37, maxTier = 3, sides = { p = 1, s = 2, max = 2 },
  base = { { k = 'attack', l = 'Attack', v = 50 }, { k = 'defense', l = 'Defense', v = 35 } },
  mods = {
    { k = 'rarity_swordSkill', l = 'Sword', t = 'Sword +1', v = 1, g = 'skill', lo = 1, hi = 1, tr = 1, sd = 'p' },
    { k = 'rarity_physicalAbsorb', l = 'Physical', t = 'Physical +2%', v = 2, g = 'absorb', lo = 1, hi = 2, tr = 2, sd = 's' },
    { k = 'chaos_mod_lifeonkill', l = 'Life on Kill', t = 'Life on Kill +15', v = 15, g = 'chaos', lo = 10, hi = 20,
      tr = 3, sd = 's' }
  },
  sockets = { count = 2, max = 2, list = { { name = 'Flawless Ruby', text = 'Fire Damage +9%', color = '#ff5a4a' }, {} } },
  req = { level = 80, voc = 'knights' }, weight = 45,
  stats = { { k = 'attack', l = 'Attack', v = 50 }, { k = 'defense', l = 'Defense', v = 35 },
    { k = 'rarity_physicalAbsorb', l = 'Physical Protection', v = 2, fmt = 'pct' },
    { k = 'chaos_mod_lifeonkill', l = 'Life on Kill', v = 15 },
    { k = 'attackspeed', l = 'Attack Interval', v = 2.0, fmt = 'sec', low = true } },
  cmp = { 6, 5 }
}
local lines = L.lines(sword, { level = 60 })
local texts = {}
for i, l in ipairs(lines) do texts[i] = l.text end
local all = table.concat(texts, '|')
eq(lines[1].text, 'Rare Weapon', 'rarity and slot')
eq(lines[1].color, L.rarityColor(4), 'in the rarity colour')
eq(lines[2].text, 'Item Level 37  (up to T3)', 'item level and the best tier it allows')
eq(lines[3].text, 'Attack: 50', 'base stat')
eq(lines[3].sep, true, 'a rule before the base stats')
eq(all:find('T2 Physical +2% [1-2]', 1, true) ~= nil, true, 'modifier with its tier and the range of the tier')
eq(all:find('T1 Sword +1 [1]', 1, true) ~= nil, true, 'a range of one value')
eq(all:find('Prefixes 1/2|T1 Sword', 1, true) ~= nil, true, 'prefix heading with the count')
eq(all:find('Suffixes 2/2|T2 Physical', 1, true) ~= nil, true, 'then the suffixes')
local chaosLine, prefixHead
for _, l in ipairs(lines) do
  if l.text:find('Life on Kill', 1, true) then chaosLine = l end
  if l.text == 'Prefixes 1/2' then prefixHead = l end
end
eq(prefixHead.sep, true, 'a rule before the modifiers')
eq(chaosLine.color, L.COLORS.chaos, 'Chaos modifier colour')
eq(chaosLine.parts[1], 'T3 ', 'tier first')
eq(chaosLine.parts[2], L.TIER_COLORS[3], 'in the tier colour')
eq(chaosLine.parts[5], ' [10-20]', 'range in its own colour')
eq(L.tierColor(8), '#ff8a40', 'T8 colour')
eq(L.tierColor(nil), L.COLORS.dim, 'no tier')
-- orbs v2: quality, a bound modifier, a legendary power, the extra slot, a ruined item
local v2 = L.lines({ rarity = 5, rarityName = 'Legendary', level = 100, quality = { q = 7, cap = 20 }, ruined = true,
  sides = { p = 3, s = 1, max = 2, mp = 3, ms = 2 },
  mods = { { t = 'Death Blast: 5% chance on kill to explode', g = 'chaos', tr = 4, sd = 'p', pw = true },
    { t = 'Sword +2', g = 'skill', tr = 3, sd = 'p', bd = true } } })
local v2all, powerLine, boundLine = {}, nil, nil
for i, l in ipairs(v2) do
  v2all[i] = l.text
  if l.text:find('Death Blast', 1, true) then powerLine = l end
  if l.text:find('Sword +2', 1, true) then boundLine = l end
end
v2all = table.concat(v2all, '|')
eq(v2all:find('Quality +7%  (up to 20%)', 1, true) ~= nil, true, 'quality line')
eq(v2all:find('Ruined: no orb can change this item', 1, true) ~= nil, true, 'ruined line')
eq(v2all:find('Prefixes 3/3', 1, true) ~= nil, true, 'the extra slot raises the limit of that side')
eq(v2all:find('Suffixes', 1, true), nil, 'no suffix rows, no suffix heading')
eq(powerLine.color, L.COLORS.power, 'a legendary power in its own colour')
eq(boundLine.text:find(' [bound]', 1, true) ~= nil, true, 'a bound modifier says so')
eq(boundLine.parts[#boundLine.parts], L.COLORS.bound, 'in the bound colour')
local legacy = L.lines({ rarity = 2, level = 12, mods = { { t = 'Fire +5% dmg', g = 'element', lo = 3, hi = 6 } } })
local legacyAll = {}
for i, l in ipairs(legacy) do legacyAll[i] = l.text end
eq(table.concat(legacyAll, '|'):find('Fire +5% dmg [3-6]', 1, true) ~= nil, true, 'a row without a tier still shows')
eq(all:find('Sockets 1/2', 1, true) ~= nil, true, 'socket count')
eq(all:find('  Flawless Ruby: Fire Damage +9%', 1, true) ~= nil, true, 'gem line')
eq(all:find('  empty socket', 1, true) ~= nil, true, 'empty socket')
local reqLine
for _, l in ipairs(lines) do if l.text == 'Requires level 80' then reqLine = l end end
eq(reqLine.color, L.COLORS.red, 'level too low in red')
eq(L.lines(sword, { level = 90 })[#L.lines(sword, { level = 90 }) - 2].color, L.COLORS.dim, 'level met: dim')
eq(texts[#texts], 'Weight 45 oz', 'weight last')

local unique = { name = 'Hornsworn Helm', unique = { name = 'Hornsworn Helm', set = { name = 'Embers of Aranoth', have = 2, total = 6 } },
  slot = 'Helmet', rarity = 0, desc = 'Forged in the embers of a dead god. (Requires level 70.)', locked = true }
lines = L.lines(unique)
eq(lines[1].text, 'Set Helmet', 'a set piece: set title')
eq(L.titleColor(unique), L.COLORS.set, 'set colour')
eq(L.titleColor({ unique = { name = 'Soulreaper' } }), L.COLORS.unique, 'unique colour')
eq(L.lines({ name = 'Soulreaper', unique = { name = 'Soulreaper' }, slot = 'Weapon' })[1].text, 'Unique Weapon', 'unique title')
local found = {}
for _, l in ipairs(lines) do found[l.text] = l end
eq(found['Set: Embers of Aranoth (2/6)'] ~= nil, true, 'set line')
eq(found['Locked'] ~= nil, true, 'locked line')
eq(L.titleColor({ rarity = 0 }), L.COLORS.normal, 'normal item colour')

-- a store pouch (server pouches.lua): the store line in gold and what it collects, no lock line
local pouch = { name = 'orbs pouch', rarity = 0, store = 'Store item: cannot be traded',
  collects = 'Auto-collects orbs, whetstones, rune shards and gems while you carry it.', weight = 1 }
lines = L.lines(pouch)
found = {}
for _, l in ipairs(lines) do found[l.text] = l end
eq(found['Store item: cannot be traded'] ~= nil and found['Store item: cannot be traded'].color, L.COLORS.gold, 'store line in gold')
eq(found['Locked'], nil, 'no lock line on a pouch')
local joined = {}
for _, l in ipairs(lines) do joined[#joined + 1] = l.text end
eq(table.concat(joined, ' '):find('Auto-collects orbs', 1, true) ~= nil, true, 'collects line')

-- a transmog look (server transmog.lua): one "Appearance:" line, the stats stay the item's own
local tm = { name = 'plate armor', rarity = 0, slot = 'Armor', look = { cid = 3400, name = 'talon plate' }, weight = 120 }
found = {}
for _, l in ipairs(L.lines(tm)) do found[l.text] = l end
eq(found['Appearance: talon plate'] ~= nil and found['Appearance: talon plate'].color, L.COLORS.mod, 'appearance line')
found = {}
for _, l in ipairs(L.lines({ name = 'plate armor', rarity = 0 })) do found[l.text] = l end
eq(found['Appearance: talon plate'], nil, 'no appearance line without a look')

-- ---------------------------------------------------------------- compare
local equipped = {
  key = '9:9', name = 'fire sword', kind = 'weapon',
  stats = { { k = 'attack', l = 'Attack', v = 54 }, { k = 'defense', l = 'Defense', v = 35 },
    { k = 'rarity_elementfire', l = 'Fire Damage', v = 7, fmt = 'pct' },
    { k = 'attackspeed', l = 'Attack Interval', v = 2.5, fmt = 'sec', low = true } }
}
local shield = { key = '8:8', name = 'mastermind shield', kind = 'shield', stats = {} }
local others = L.compareWith(sword, { [6] = equipped, [5] = shield }, sword.key)
eq(#others, 1, 'the shield in the other hand is not compared with a weapon')
eq(others[1].name, 'fire sword', 'compared with the weapon')
eq(#L.compareWith(sword, { [6] = sword }, sword.key), 0, 'never with itself')
eq(#L.compareWith({ name = 'coin' }, { [6] = equipped }), 0, 'nothing to compare')

local d = L.diff(sword, equipped)
local byK = {}
for _, r in ipairs(d) do byK[r.k] = r end
eq(byK.attack.d, -4, 'attack lower') eq(byK.attack.better, false, 'worse')
eq(byK.defense, nil, 'equal numbers are left out')
eq(byK.rarity_physicalAbsorb.d, 2, 'only the hovered has it') eq(byK.rarity_physicalAbsorb.better, true, 'better')
eq(byK.rarity_elementfire.d, -7, 'only the equipped has it') eq(byK.rarity_elementfire.better, false, 'loses it')
eq(math.abs(byK.attackspeed.d + 0.5) < 1e-9, true, 'interval 0.5 s shorter')
eq(byK.attackspeed.better, true, 'shorter interval is better')
eq(L.diffText(byK.attack), '-4 Attack', 'diff text')
eq(L.diffText(byK.rarity_physicalAbsorb), '+2% Physical Protection', 'diff text percent')
eq(L.diffText(byK.attackspeed), '-0.5s Attack Interval', 'diff text seconds')
eq(d[1].k, 'attack', 'hovered order first')
eq(d[#d].k, 'rarity_elementfire', 'then what only the equipped has')
eq(#L.diff(sword, nil), 5, 'against nothing: every number')

-- ---------------------------------------------------------------- a quiver: implicit rows and the bow note
local quiver = { name = 'Seraphic Quiver', kind = 'quiver', slot = 'Off-hand: Quiver', rarity = 3, rarityName = 'Rare', level = 120,
  base = { { k = 'chaos_mod_bowdistance', l = 'Distance Fighting', v = 4, imp = true },
    { k = 'chaos_mod_multishot', l = 'Extra Projectile Chance', v = 8, fmt = 'pct', imp = true } },
  mods = { { k = 'chaos_mod_bowcrit', t = 'Critical Strike Chance with Bows +6%', g = 'chaos', tr = 6, sd = 'p', lo = 6, hi = 7 } },
  note = 'Works only while you hold a bow or crossbow.', weight = 24.7 }
local ql = L.lines(quiver)
local qtext = {}
for _, row in ipairs(ql) do qtext[#qtext + 1] = row.text end
qtext = table.concat(qtext, '|')
eq(ql[1].text, 'Rare Quiver', 'quiver title')
eq(ql[2].text, 'Off-hand: Quiver', 'worn in the off-hand, a line of its own (server src-patch 0023)')
eq(ql[2].color, L.COLORS.dim, 'in the dim colour')
eq(qtext:find('Distance Fighting: +4', 1, true) ~= nil, true, 'implicit flat, signed')
eq(qtext:find('Extra Projectile Chance: +8%', 1, true) ~= nil, true, 'implicit percent, signed')
eq(qtext:find('Works only while you hold a bow or crossbow.', 1, true) ~= nil, true, 'the note')
for _, row in ipairs(ql) do
  if row.text:find('^Distance Fighting') then eq(row.color, L.COLORS.chaos, 'implicit colour') end
  if row.text:find('^Works only') then eq(row.color, L.COLORS.gold, 'note colour') end
end

-- ---------------------------------------------------------------- display scale (server display_scale_core.lua DS.itemTip)
-- a level-1000 helmet (ds 1000) against a worn level-500 one (ds 22): the flat rows (sc) are compared in the hovered
-- item's scale; percent rows as they are
local hiHelm = { kind = 'helmet', ds = 1000, stats = { { k = 'maxhealth', l = 'Max Health', v = 200000, sc = 1 },
  { k = 'chaos_mod_lifeonkill', l = 'Life on Kill', v = 50000, sc = 1 }, { k = 'chaos_mod_itemfind', l = 'Item Find', v = 5, fmt = 'pct' } } }
local loHelm = { kind = 'helmet', ds = 22, stats = { { k = 'maxhealth', l = 'Max Health', v = 4400, sc = 1 },
  { k = 'chaos_mod_lifeonhit', l = 'Health on Hit', v = 220, sc = 1 }, { k = 'chaos_mod_itemfind', l = 'Item Find', v = 3, fmt = 'pct' } } }
local dd = {}
for _, r in ipairs(L.diff(hiHelm, loHelm)) do dd[r.k] = r.d end
eq(dd.maxhealth, nil, 'the same raw max health (200) is no difference across scales')
eq(dd.chaos_mod_lifeonkill, 50000, 'only on the hovered one')
eq(dd.chaos_mod_lifeonhit, -10000, 'only on the worn one: brought to x1000 (10 raw)')
eq(dd.chaos_mod_itemfind, 2, 'a percent row is not converted')
eq(L.toScale(4400, 22, 1000), 200000, 'toScale')
eq(L.toScale(7, nil, nil), 7, 'tooltips without ds')
local plainA, plainB = { stats = { { k = 'maxhealth', v = 300, sc = 1 } } }, { stats = { { k = 'maxhealth', v = 100, sc = 1 } } }
eq(L.diff(plainA, plainB)[1].d, 200, 'no ds: as before')

-- ---------------------------------------------------------------- sources and expected effort (server itemfinder.lua F.brief)
eq(#L.sourceLines(nil), 0, 'no sources')
local src = L.sourceLines({ s = { { k = 'drop', n = 'Unique drop', v = '0.9%' }, { k = 'reward', n = 'Rift chest' } },
  e = { p = 1 / 400, w = 'legendary' }, t = 690 })
eq(src[1].text, 'Drops from: Unique drop (0.9%), Rift chest', 'drops from line')
eq(src[#src - 1].text, '~1 in 400 legendary kills, or 690 Conquest', 'effort and tokens (wrapped)')
local joined = {}
for _, l in ipairs(src) do joined[#joined + 1] = l.text end
eq(table.concat(joined, ' '):find('or 690 Conquest Tokens', 1, true) ~= nil, true, 'token price')
eq(L.sourceLines({ s = { { k = 'shop', n = 'Agnes', v = '4 gold' } } })[1].text, 'Sources: Agnes (4 gold)', 'sources line')
eq(L.sourceLines({ s = { { k = 'monster', n = 'Dragon', v = '0.1%' } }, e = { p = 0.001, w = 'kill', m = 'Dragon' } })[2].text,
  '~1 in 1,000 kills of Dragon', 'kills of a monster')
eq(L.sourceLines({ s = {}, t = 1200 })[1].text, 'Conquest vendor: 1,200 tokens', 'vendor only')
eq(L.oneIn(1 / 267), 270, 'rounded')
eq(L.oneIn(0), nil, 'no chance')
local withSrc = L.lines({ name = 'x', weight = 10, src = { s = { { k = 'monster', n = 'Rat', v = '5%' } } } })
eq(withSrc[#withSrc - 1].text, 'Drops from: Rat (5%)', 'the sources sit above the weight')

-- ---------------------------------------------------------------- the answer is for the item asked about
-- live test winpkg-35: a Rope in the backpack showed "Cheese 62", a Training Wand "Gold coin 100", "Drops from: Abyssal
-- Crab (100%), Abyssal Crab (100%)". Model: the backpack (container 0) and the loot bag (container 1) are open with
-- different items at the same index; loot goes in at the front of the backpack and shifts its items one slot.
do
  local ROPE, CHEESE, WAND, GOLD = 3003, 3607, 3075, 3031
  local server = { [0] = { { CHEESE, 62 }, { ROPE, 1 }, { WAND, 1 } }, [1] = { { GOLD, 100 }, { ROPE, 1 } } }
  local function tipAt(cid, index) -- the server's tooltip of what it finds there (no identity check)
    local e = server[cid][index + 1]
    return e and { id = e[1], count = e[2] } or nil
  end
  -- the client still sees the backpack before the cheese went in: Rope at index 0, Wand at index 1
  local rope = L.identity(ROPE, 1, false)
  local wand = L.identity(WAND, 1, false)
  eq(L.tipMatches(rope, tipAt(0, 0)), false, 'shifted slot: the cheese is not kept as the rope tooltip')
  eq(L.tipMatches(wand, tipAt(0, 1)), false, 'shifted slot: the rope is not kept as the wand tooltip')
  eq(L.tipMatches(rope, tipAt(0, 1)), true, 'the rope where it is now')
  -- the same index in another open container is another item
  eq(L.tipMatches(rope, tipAt(1, 0)), false, 'same index, other container: the gold is not the rope')
  eq(L.tipMatches(rope, tipAt(1, 1)), true, 'a rope is a rope in either container')
  -- a stackable also by its count
  local cheese = L.identity(CHEESE, 62, true)
  eq(cheese.n, 62, 'a stackable names its count')
  eq(L.identity(WAND, 5, false).n, nil, 'a non-stackable does not (charges are no count)')
  eq(L.tipMatches(cheese, { id = CHEESE, count = 62 }), true, 'the same stack')
  eq(L.tipMatches(cheese, { id = CHEESE, count = 10 }), false, 'another stack of cheese')
  eq(L.tipMatches(nil, { id = CHEESE }), false, 'nothing asked')
  eq(L.tipMatches({ cid = 0 }, { id = CHEESE }), true, 'no client id: an older request is not refused')
  -- the plain cache keys of the two containers' index 0 never meet
  local k0 = L.cacheKey({}, ROPE, 1, { x = 65535, y = 64, z = 0 })
  local k1 = L.cacheKey({}, ROPE, 1, { x = 65535, y = 65, z = 0 })
  eq(k0 ~= k1, true, 'cache keys of the same index in two containers differ')
  eq(L.posKey({ x = 65535, y = 64, z = 0 }, 0) ~= L.posKey({ x = 65535, y = 65, z = 0 }, 0), true, 'and the request keys')
  -- the sources line names a monster once
  eq(L.sourceLines({ s = { { k = 'monster', n = 'Abyssal Crab', v = '100%' }, { k = 'monster', n = 'Abyssal Crab', v = '100%' } } })[1].text,
    'Drops from: Abyssal Crab (100%)', 'a monster once in the sources line')
end

-- ---------------------------------------------------------------- charges (live test winpkg-35: a Lasting Exercise Wand
-- showed only its name and weight)
eq(L.chargesText({ n = 14400 }), 'Charges: 14,400', 'full charges')
eq(L.chargesText({ n = 1200, max = 14400 }), 'Charges: 1,200 of 14,400', 'used charges')
eq(L.chargesText({ unlimited = true }), 'Charges: unlimited', 'unlimited')
eq(L.chargesText(nil), nil, 'no charges')
do
  local rows = L.lines({ name = 'lasting exercise wand', weight = 10, charges = { n = 14400 } })
  local found = false
  for _, r in ipairs(rows) do if r.text == 'Charges: 14,400' then found = true end end
  eq(found, true, 'the charges line is in the tooltip')
  eq(rows[#rows].text, 'Weight 10 oz', 'the weight stays last')
end

-- ---------------------------------------------------------------- live charges (owner 2026-10-20: an Exercise wand
-- in training kept "Charges: 500" in its tooltip)
eq(L.liveTip({ charges = { n = 499, max = 500 } }), true, 'counted charges are live')
eq(L.liveTip({ charges = { n = 500 } }), true, 'full charges are live too')
eq(L.liveTip({ charges = { unlimited = true } }), false, 'unlimited charges never change')
eq(L.liveTip({ name = 'sword' }), false, 'no charges')
eq(L.liveTip(nil), false, 'no tip')
do
  local lc = L.newCache()
  L.cachePut(lc, 'p:65535:64:0:3000:1', { charges = { n = 500 } }, true, 10)
  L.cachePut(lc, 'q', { name = 'Q' }, false, 10)
  eq(L.cacheDrop(lc, 'p:65535:64:0:3000:1'), true, 'the live entry is dropped')
  eq(L.cacheGet(lc, 'p:65535:64:0:3000:1', 10), nil, 'and gone')
  eq(#lc.order, 1, 'and out of the order list')
  eq(lc.order[1], 'q', 'the other entry stays')
  eq(L.cacheDrop(lc, 'nothing'), false, 'dropping a missing key')
  -- a new answer for the same key after the drop is cached again with the new number
  L.cachePut(lc, 'p:65535:64:0:3000:1', { charges = { n = 499, max = 500 } }, true, 11)
  eq(L.chargesText(L.cacheGet(lc, 'p:65535:64:0:3000:1', 11).charges), 'Charges: 499 of 500', 'the new charges show')
  eq(#lc.order, 2, 'no duplicate in the order list')
end

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('tooltiplogic_test: ' .. checks .. ' checks OK')
