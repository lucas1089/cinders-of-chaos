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
eq(L.formatValue(1, 'sec', nil, true), '1s', 'one second: no rate')
eq(L.formatValue(0.5, 'sec'), '0.5s', 'a difference shows no rate')
eq(L.formatValue(0.33, 'sec', nil, true), '0.33s (3/s)', 'the floor: 3 attacks per second')
eq(L.formatValue(0.5, 'sec', nil, true), '0.5s (2/s)', 'two per second')
eq(L.formatValue(0.37, 'sec', nil, true), '0.37s (2.7/s)', 'a rate with a decimal')
eq(L.formatValue(0.83, 'sec', nil, true), '0.83s (1.2/s)', 'under a second')
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
-- a Void Orb's corruption: the Corrupted line, the implicit under its own heading, before the prefixes
local cor = L.lines({ rarity = 4, rarityName = 'Rare', level = 100, corrupted = true,
  sides = { p = 1, s = 0, max = 2 },
  mods = { { t = 'Block Chance +12%', g = 'chaos', tr = 8, sd = 'i' }, { t = 'Sword +2', g = 'skill', tr = 3, sd = 'p' } } })
local corAll, implicitLine = {}, nil
for i, l in ipairs(cor) do
  corAll[i] = l.text
  if l.text:find('Block Chance', 1, true) then implicitLine = l end
end
corAll = table.concat(corAll, '|')
eq(corAll:find('Corrupted: no orb can change this item', 1, true) ~= nil, true, 'corrupted line')
eq(corAll:find('Corrupted implicit|T8 Block Chance +12%|Prefixes 1/2|T3 Sword +2', 1, true) ~= nil, true,
  'the implicit first, under its heading, the prefixes after')
eq(implicitLine.color, L.COLORS.corrupted, 'the implicit in the corrupted colour')
eq(v2all:find('Corrupted', 1, true), nil, 'no corrupted line on an item that is not')
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

-- a unique's passive (server T.splitPassive): the flavour dim, the name in the passive colour on a new section, the rule bright
local reaper = { name = 'Soulreaper', unique = { name = 'Soulreaper' }, slot = 'Weapon', rarity = 0,
  desc = 'Every soul it cuts feeds the blade. Hungry Blade: Each kill restores 7.1% of your maximum health. (Requires level 120.)',
  passive = { name = 'Hungry Blade', text = 'Each kill restores 7.1% of your maximum health.',
    flavor = 'Every soul it cuts feeds the blade. (Requires level 120.)' } }
lines = L.lines(reaper)
found = {}
for _, l in ipairs(lines) do found[l.text] = l end
eq(found['Hungry Blade'] ~= nil and found['Hungry Blade'].color, L.COLORS.passive, 'passive name in its colour')
eq(found['Hungry Blade'].sep, true, 'passive name opens a section')
eq(found['Each kill restores 7.1% of your maximum'] ~= nil and found['Each kill restores 7.1% of your maximum'].color,
  L.COLORS.passiveText, 'passive rule in bright text')
local all = {}
for _, l in ipairs(lines) do all[#all + 1] = l.text end
eq(table.concat(all, ' '):find('Hungry Blade: Each', 1, true), nil, 'the passive is not repeated in the flavour')
eq(table.concat(all, ' '):find('Every soul it cuts', 1, true) ~= nil, true, 'flavour kept')
-- does the power work for the viewer (O467): the line under the rule, normal text or the warning colour
reaper.passive.fit = 'Works for your class. Active.'
lines = L.lines(reaper)
found = {}
for _, l in ipairs(lines) do found[l.text] = l end
eq(found['Works for your class. Active.'] ~= nil and found['Works for your class. Active.'].color, L.COLORS.text, 'fit line in normal text')
local fitAt, ruleAt
for i, l in ipairs(lines) do
  if l.text == 'Works for your class. Active.' then fitAt = i end
  if l.text:find('Each kill restores', 1, true) then ruleAt = i end
end
eq(fitAt ~= nil and ruleAt ~= nil and fitAt > ruleAt, true, 'the fit line comes under the rule')
reaper.passive.fit, reaper.passive.warn = 'Asleep: your class is not in its list.', true
lines = L.lines(reaper)
found = {}
for _, l in ipairs(lines) do found[l.text] = l end
eq(found['Asleep: your class is not in its list.'] ~= nil and found['Asleep: your class is not in its list.'].color, L.COLORS.red,
  'an asleep power in the warning colour')
local fitCard = L.card({ name = 'x', unique = { name = 'x' }, passive = { name = 'P', text = 'Rule.', flavor = 'F.', fit = 'Asleep: Y is stronger.', warn = true } }, {})
local rows
for _, g in ipairs(fitCard.extras) do if g.caption == 'P' then rows = g.rows end end
eq(rows ~= nil and rows[#rows].text, 'Asleep: Y is stronger.', 'card: the fit line ends the passive group')
eq(rows ~= nil and rows[#rows].color, L.COLORS.red, 'card: in the warning colour')
-- the cache: a tip with a power line is forgotten when the equipment changes (it names the worn uniques)
do
  local cache = L.newCache()
  L.cachePut(cache, 'u', { name = 'U', passive = { name = 'P', text = 'R', fit = 'Active.' } }, false, 0)
  L.cachePut(cache, 'v', { name = 'V', passive = { name = 'P', text = 'R' } }, false, 0)
  eq(L.dropSetTips(cache), 1, 'only the tip with a power line is dropped')
  eq(L.cacheGet(cache, 'v', 0) ~= nil, true, 'a tip without one stays')
end
-- the Codex page of a tip (the server's tip.codex): a unique page or a set page, nothing else
eq(L.codexId({ codex = 'unique:8209' }), 'unique:8209', 'a unique page id')
eq(L.codexId({ codex = 'set:cinderstorm' }), 'set:cinderstorm', 'a set page id')
eq(L.codexId({ codex = 'orb:ruin' }), nil, 'another page: refused')
eq(L.codexId({ codex = 12 }), nil, 'not a string')
eq(L.codexId({}), nil, 'no id')
eq(L.codexId(nil), nil, 'no tip')
-- the class row goes through the translation: the prefix and the words 'all classes' (the class names stay)
do
  local saved = rawget(_G, 'tr')
  rawset(_G, 'tr', function(s, ...)
    local pt = { ['For %s'] = 'Para %s', ['all classes'] = 'todas as classes', ['Set'] = 'Conjunto', ['Unique'] = 'Única' }
    s = pt[s] or s
    if select('#', ...) > 0 then return string.format(s, ...) end
    return s
  end)
  eq(L.classText('all classes'), 'todas as classes', 'all classes translated')
  eq(L.classText('Mystic, Necromancer'), 'Mystic, Necromancer', 'class names untouched')
  local classLines = L.lines({ name = 'Ring', slot = 'Ring', req = { voc = 'all classes' } })
  local cl
  for _, l in ipairs(classLines) do if l.text:find('^Para') then cl = l.text end end
  eq(cl, 'Para todas as classes', 'the class row in pt-BR')
  eq(L.kindText({ unique = { set = {} }, slot = 'Ring' }):find('Conjunto', 1, true) ~= nil, true, 'the Set kind in pt-BR')
  local chips = L.reqChips({ voc = 'all classes' }, {})
  eq(chips[1].text, 'todas as classes', 'the chip of all classes in pt-BR')
  rawset(_G, 'tr', saved)
end
-- an older server (no passive block): the description as before
reaper.passive = nil
all = {}
for _, l in ipairs(L.lines(reaper)) do all[#all + 1] = l.text end
eq(table.concat(all, ' '):find('Hungry Blade: Each', 1, true) ~= nil, true, 'without the block the description is whole')

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
local srcTip = { name = 'x', weight = 10, src = { s = { { k = 'monster', n = 'Rat', v = '5%' } }, e = { p = 0.05, w = 'kill', m = 'Rat' },
  u = { n = { 'Myst Emblem' } } } }
local withSrc = L.lines(srcTip, { alt = true })
eq(withSrc[#withSrc - 3].text, 'Drops from: Rat (5%)', 'with Alt the sources sit above the effort, used in and the weight')
-- owner 2026-11-11: the "Drops from" row shows only while Alt is held; the effort line, "Used in" and the weight stay
do
  local plain = L.lines(srcTip)
  local texts = {}
  for _, l in ipairs(plain) do texts[#texts + 1] = l.text end
  local joined = table.concat(texts, '\n')
  eq(joined:find('Drops from', 1, true), nil, 'no Alt: no Drops from row')
  eq(joined:find('~1 in 20 kills of Rat', 1, true) ~= nil, true, 'no Alt: the effort line stays')
  eq(joined:find('Used in: Myst Emblem', 1, true) ~= nil, true, 'no Alt: Used in stays')
  eq(plain[#plain].text, 'Weight 10 oz', 'no Alt: the weight stays')
  eq(#L.sourceLines(srcTip.src, true), 2, 'hideRow: effort and used in')
  eq(#L.sourceLines(srcTip.src), 3, 'default: the row too')
  eq(#L.sourceLines({ s = { { k = 'shop', n = 'Agnes', v = '4 gold' } } }, true), 0, 'the Sources row hides the same way')
  eq(L.hasSourceRow(srcTip.src), true, 'a row to open')
  eq(L.hasSourceRow({ s = {}, t = 1200 }), false, 'a vendor price alone: nothing hidden')
  eq(L.hasSourceRow(nil), false, 'no sources')
  local foot = L.card(srcTip, {}).foot
  eq(foot[1].text, '~1 in 20 kills of Rat', 'card without Alt: the foot starts at the effort line')
  eq(L.card(srcTip, { alt = true }).foot[1].text, 'Drops from: Rat (5%)', 'card with Alt: the row is back')
  eq(L.altHintText(srcTip, true), 'Hold Alt for where it comes from and what each line does.', 'the hint names the hidden row')
  eq(L.altHintText(srcTip, false), 'Hold Alt for where it comes from.', 'an item without help lines still gets a hint')
  eq(L.altHintText({ name = 'x' }, true), nil, 'nothing hidden: the shared hint stays')
end

-- what a material is for (server K.brief u; owner 2026-10-22: "Coloque pra que servem")
local stone = L.sourceLines({ s = { { k = 'monster', n = 'Fractalis the Shardmaw', v = '60%' } },
  u = { n = { 'Seraphic Tabard', 'Seraphic Greaves' }, m = 7 } })
local stoneText = {}
for _, l in ipairs(stone) do stoneText[#stoneText + 1] = l.text end
eq(table.concat(stoneText, ' '):find('Used in: Seraphic Tabard, Seraphic Greaves +7 more', 1, true) ~= nil, true,
  'used-in line after the sources: ' .. table.concat(stoneText, ' | '))
eq(stone[#stone].color, L.COLORS.dim, 'the used-in line is dim')
eq(L.usedInText({ n = { 'Seraphic Emblem' } }), 'Used in: Seraphic Emblem', 'one product, no count')
eq(L.usedInText({ n = { 'A', 'B' }, m = 0 }), 'Used in: A, B', 'no "+0 more"')
eq(L.usedInText(nil), nil, 'an older server: no used-in line')
eq(L.usedInText({ n = {} }), nil, 'no products: no line')
eq(L.usedInText({ n = 'x', m = 3 }), nil, 'a bad payload: no line')
local onlyUsed = L.sourceLines({ s = {}, u = { n = { 'Myst Emblem' } } })
eq(#onlyUsed, 1, 'used in something, from nowhere: the used-in line alone')
eq(onlyUsed[1].text, 'Used in: Myst Emblem', 'used-in alone')
local oldSrc = L.sourceLines({ s = { { k = 'monster', n = 'Rat', v = '5%' } } })
eq(#oldSrc, 1, 'a brief without u: as before')
local usedTip = L.lines({ name = 'x', weight = 10, src = { s = {}, u = { n = { 'Myst Emblem' }, m = 2 } } })
eq(usedTip[#usedTip - 1].text, 'Used in: Myst Emblem +2 more', 'the used-in line sits above the weight')

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

-- O353: a wand's or rod's Attack row shows its range
eq(L.baseValue({ k = 'attack', l = 'Attack', v = 135, lo = 126, hi = 144, fmt = 'range' }), '126-144', 'rod attack range')
eq(L.baseValue({ k = 'attack', l = 'Attack', v = 1500, lo = 1500, hi = 1500, fmt = 'range' }), '1,500', 'one value')
eq(L.baseValue({ k = 'attack', l = 'Attack', v = 48 }), '48', 'a plain row as before')
eq(L.baseValue({ k = 'attack', v = 7, fmt = 'range' }), '7', 'a range row without its ends shows the value')

-- ---------------------------------------------------------------- the card layout (O422)
local wand = {
  key = '9:9', id = 3074, name = 'venomous vigils wand of mercy', kind = 'weapon', slot = 'Wand', rarity = 5,
  rarityName = 'Legendary', level = 84, maxTier = 5, sides = { p = 2, s = 3, max = 3 },
  base = {
    { k = 'attack', l = 'Attack', v = 112, lo = 92, hi = 133, fmt = 'range' },
    { k = 'range', l = 'Range', v = 5 },
    { k = 'attackspeed', l = 'Attack Interval', v = 1.8, fmt = 'sec', low = true },
    { k = 'maglevel', l = 'Magic Level', v = 3 },
    { k = 'protect4', l = 'Fire Protection', v = 3, fmt = 'pct' },
    { k = 'yourinterval', l = 'Your Attack Interval', v = 1.08, fmt = 'sec', low = true },
    { k = 'dps', l = 'Estimated DPS', v = 104, fmt = 'est' },
  },
  mods = {
    { k = 'a', t = 'Chance to Poison +12%', g = 'chaos', lo = 9, hi = 13, tr = 4, sd = 'p' },
    { k = 'b', t = 'Arc Lightning: 2% on hit, arcs to 3 monsters', pw = true, lo = 2, hi = 3, tr = 5, sd = 'p' },
    { k = 'c', t = 'Fire +2%', g = 'element', lo = 2, hi = 2, tr = 1, sd = 's', bd = true },
    { k = 'd', t = 'Life Chance +1%', lo = 1, hi = 2, tr = 2, sd = 's' },
  },
  req = { level = 300, voc = 'Mystic, Necromancer' }, weight = 24.9,
  src = { s = { { k = 'monster', n = 'Axebringer Fiend' } } },
}
local card = L.card(wand, { level = 100 })
eq(card.title, 'Venomous vigils wand of mercy', 'card title')
eq(card.kind, 'LEGENDARY WAND', 'card kind in capitals')
eq(card.kindColor, L.RARITY_COLORS[5], 'kind in the rarity colour')
eq(card.level, 'Item Level 84 - up to T5', 'card level line')
eq(#card.stats.tiles, 4, 'four tiles')
eq(card.stats.tiles[1].key, 'dps', 'DPS first')
eq(card.stats.tiles[1].hero, true, 'DPS is the hero tile')
eq(card.stats.tiles[1].value, '~104', 'DPS value')
eq(card.stats.tiles[2].value, '92-133', 'wand attack range')
eq(card.stats.tiles[3].key, 'speed', 'speed tile')
eq(card.stats.tiles[3].value, '1.08s', 'the speed tile is the player interval')
eq(card.stats.tiles[4].value, '5', 'range tile')
eq(#card.stats.extra, 2, 'the extra items wrap at the line limit')
local extraText = {}
for i = 1, #card.stats.extra[1], 2 do extraText[#extraText + 1] = card.stats.extra[1][i] end
eq(table.concat(extraText), 'Attack Interval 1.8s - Magic Level +3', 'the raw interval and the bonuses')
eq(card.stats.extra[2][3], '+3%', 'second line value')
eq(card.stats.extra[1][#card.stats.extra[1]], L.COLORS.better, 'values are green')
eq(#card.mods, 2, 'prefix and suffix groups')
eq(card.mods[1].caption, 'PREFIXES 2/3', 'prefix caption')
eq(card.mods[2].caption, 'SUFFIXES 3/3', 'suffix caption')
eq(card.mods[1].rows[1].tag, 'T4', 'tier tag')
eq(card.mods[1].rows[1].top, false, 'T4 is not the best tier')
eq(card.mods[1].rows[2].top, true, 'the best tier of the item level')
eq(card.mods[1].rows[1].range, '9-13', 'roll range')
eq(card.mods[2].rows[1].range, '2', 'a single value range')
eq(card.mods[1].rows[1].color, L.COLORS.chaos, 'modifier colour kept')
eq(card.mods[1].rows[2].color, L.COLORS.power, 'power colour kept')
eq(card.mods[2].rows[1].parts[3], ' [bound]', 'bound marker')
eq(card.extras, nil, 'no extra groups')
eq(#card.chips, 3, 'level and two classes')
eq(card.chips[1].text, 'Level 300', 'level chip')
eq(card.chips[1].low, true, 'level chip low')
eq(card.chips[3].text, 'Necromancer', 'class chip')
eq(L.card(wand, { level = 300 }).chips[1].low, false, 'level reached')
eq(#card.foot, 1, 'the weight alone without Alt')
eq(card.foot[1].text, 'Weight 24.9 oz', 'foot line without Alt')
do
  local altCard = L.card(wand, { level = 100, alt = true })
  eq(#altCard.foot, 1, 'Alt: source and weight on one line')
  eq(altCard.foot[1].text, 'Drops from: Axebringer Fiend - Weight 24.9 oz', 'foot line with Alt')
end

-- armour: Armour and Defense tiles, the rest in the extra line; no DPS hero
local armor = { name = 'plate armor', kind = 'armor', slot = 'Armour', rarity = 3, rarityName = 'Magic', level = 20,
  base = { { k = 'armor', l = 'Armour', v = 15 }, { k = 'defense', l = 'Defense', v = 4 },
    { k = 'maxhealth', l = 'Max Health', v = 80 }, { k = 'protect1', l = 'Physical Protection', v = 5, fmt = 'pct' } } }
local ac = L.card(armor, {})
eq(#ac.stats.tiles, 2, 'armour tiles')
eq(ac.stats.tiles[1].key, 'armor', 'armour first')
eq(ac.stats.tiles[1].hero, false, 'no hero without DPS')
eq(#ac.stats.extra, 1, 'armour extra line')
eq(ac.stats.extra[1][1], 'Max Health ', 'extra label')
eq(ac.stats.extra[1][3], '+80', 'bonus signed')
eq(ac.kind, 'MAGIC ARMOUR', 'armour kind')
eq(ac.level, 'Item Level 20', 'no tier text without a max tier')
eq(ac.mods, nil, 'no mods')

-- a melee weapon: attack, speed (no range), defense as the 4th tile when there is room; the item interval alone is the speed
local mace = { name = 'mace', kind = 'weapon', base = { { k = 'attack', l = 'Attack', v = 30 },
  { k = 'defense', l = 'Defense', v = 12 }, { k = 'attackspeed', l = 'Attack Interval', v = 2, fmt = 'sec' } } }
local mc = L.card(mace, {})
eq(mc.stats.tiles[1].key, 'attack', 'no DPS tile without the row')
eq(mc.stats.tiles[2].key, 'speed', 'speed tile from the item interval')
eq(mc.stats.tiles[3].key, 'defense', 'defense tile')
eq(#mc.stats.extra, 0, 'nothing left over')
-- more candidates than tiles: the rest goes to the extra line
local many = L.card({ name = 'x', base = { { k = 'dps', l = 'Estimated DPS', v = 5, fmt = 'est' },
  { k = 'attack', l = 'Attack', v = 5 }, { k = 'yourinterval', l = 'Your Attack Interval', v = 1, fmt = 'sec' },
  { k = 'range', l = 'Range', v = 4 }, { k = 'defense', l = 'Defense', v = 9 } } }, {})
eq(#many.stats.tiles, 4, 'at most four tiles')
eq(#many.stats.extra, 1, 'the fifth goes to the extra line')
eq(many.stats.extra[1][1], 'Defense ', 'the leftover')

-- a plain item: no stats, mods, chips; only a name
local plain = L.card({ name = 'rope', id = 3003, weight = 18 }, {})
eq(plain.stats, nil, 'plain: no stats')
eq(plain.kind, nil, 'plain: no kind')
eq(plain.level, nil, 'plain: no level')
eq(#plain.chips, 0, 'plain: no chips')
eq(plain.foot[1].text, 'Weight 18 oz', 'plain: weight alone')

-- extras: sockets, set, passive, charges, veil, implicit
local rich = L.card({ name = 'ring', rarity = 4, rarityName = 'Rare', slot = 'Ring', maxTier = 3, level = 50,
  mods = { { t = 'Implicit +1', tr = 1, sd = 'i' }, { t = 'Fire +1%', tr = 3, sd = 'p' } },
  veil = { s = 'open', n = 'Wraithstride', tr = 4, tn = 'V4', lo = 8, hi = 10, t = 'Faster steps.' },
  sockets = { count = 2, list = { { name = 'Ruby', text = 'Fire +9%', color = '#ff5a4a' }, {} } },
  unique = { name = 'ring', set = { name = 'Embers', have = 1, total = 3, pieces = { { n = 'Ring', eq = true } } } },
  passive = { name = 'Last Voice', text = 'Hits hard.', flavor = 'A choir sang.' },
  locked = true, charges = { n = 5, max = 10 } }, {})
eq(rich.mods[1].caption, 'CORRUPTED IMPLICIT', 'implicit group first')
eq(rich.mods[2].caption, 'PREFIXES', 'prefix caption without side counts')
eq(rich.mods[2].rows[1].top, true, 'T3 of max T3')
eq(rich.mods[3].caption, 'VEILED', 'veil group')
eq(rich.mods[3].rows[1].tag, 'V4', 'veil tag')
eq(rich.mods[3].rows[1].range, '8-10', 'veil range')
eq(rich.mods[3].rows[2].text, 'Faster steps.', 'veil text')
eq(rich.extras[1].caption, 'SOCKETS 1/2', 'sockets caption')
eq(rich.extras[1].rows[1].parts[1], 'Ruby', 'gem name part')
eq(rich.extras[1].rows[2].text, 'empty socket', 'empty socket row without the indent')
eq(rich.extras[2].caption, 'Set: Embers (1/3)', 'set caption')
eq(rich.extras[2].rows[1].text, 'Ring', 'set piece row')
eq(rich.extras[3].rows[1].text, 'A choir sang.', 'flavour')
eq(rich.extras[4].caption, 'Last Voice', 'passive caption')
eq(rich.extras[5].rows[1].text, 'Locked', 'locked')
eq(rich.extras[5].rows[2].text, 'Charges: 5 of 10', 'charges')
eq(rich.kind, 'SET RING', 'a set piece is a set kind')
local veiled = L.card({ name = 'x', veil = { s = 'veiled' } }, {})
eq(veiled.mods[1].caption, 'VEILED MODIFIER', 'veiled slot caption')
eq(veiled.mods[1].rows[1].text, 'Reveal it with an Orb of Unveiling', 'veiled slot text')
local flags = L.card({ name = 'x', quality = { q = 5, cap = 20 }, ruined = true, corrupted = true }, {})
eq(#flags.flags, 3, 'quality, ruined and corrupted flags')
local quiver = L.card({ name = 'quiver', slot = 'Off-hand: Quiver', note = 'Works only with a bow.',
  base = { { k = 'x', l = 'Arrow Damage', v = 4, fmt = 'pct', imp = true } } }, {})
eq(quiver.kind, 'QUIVER', 'quiver kind names what')
eq(quiver.slotLine, 'Off-hand: Quiver', 'quiver slot line')
eq(quiver.stats.extra[1][3], '+4%', 'implicit signed')
eq(quiver.extras[1].rows[1].color, L.COLORS.gold, 'note in gold')
-- the foot keeps the effort and used-in lines; the weight stays a line of its own after a gold line
local foot = L.card({ name = 'x', weight = 3, src = { e = { p = 0.002 } } }, {})
eq(foot.foot[#foot.foot].text, 'Weight 3 oz', 'weight after the effort line')
eq(L.caps('Armadura n\195\163o'), 'ARMADURA N\195\163O', 'capitals leave the UTF-8 bytes alone')

-- measured wrap and chip rows
local function measure(t) return #t * 6 end
local wr = L.wrapPx('Venomous Vigils Wand of Mercy', 100, measure)
eq(#wr, 2, 'two lines')
eq(wr[1], 'Venomous Vigils', 'first line')
eq(wr[2], 'Wand of Mercy', 'second line')
eq(#L.wrapPx('Supercalifragilistic', 30, measure), 1, 'a word longer than the width stays whole')
eq(#L.wrapPx('', 30, measure), 0, 'empty')
local cr = L.chipRows({ 60, 50, 90, 40 }, 6, 150)
eq(#cr, 2, 'chips in two rows')
eq(#cr[1], 2, 'two on the first row')
eq(cr[2][1], 3, 'the third starts the second')
eq(#L.chipRows({}, 6, 100), 0, 'no chips')


-- spell support runes and other items that are no gear (owner 2026-11-06)
local runeDesc = 'A support rune for a spell socket: mana cost -9%, refunded after the cast. Fits single target, area, healing, buff / utility spells. Three of them combine into one of the next level: use the stack, then left-click the same stack. Use it to open the spell supports (!supports).'
local rune = L.card({ name = 'rare thrift rune', id = 5000, rarity = 3, rarityName = 'Rare', desc = runeDesc, weight = 1.5,
  cmp = { 5 }, kind = 'other' }, {})
eq(rune.kind, 'RARE SUPPORT RUNE', 'rune kind line')
eq(rune.stats.effect.text, 'Mana cost -9%, refunded after the cast', 'rune effect as the highlighted row')
eq(#rune.stats.tiles, 0, 'rune: no tiles')
eq(#rune.fitChips, 4, 'four spell kinds')
eq(rune.fitChips[4].text, 'buff / utility', 'last kind')
eq(rune.fitCaption, 'FITS SPELLS', 'fits caption')
eq(rune.extras, nil, 'the description is not repeated')
eq(#rune.foot, 3, 'combine line, command line, weight')
eq(rune.foot[1].text, 'Three combine into one of the next level.', 'combine rule')
eq(rune.foot[2].text, 'Open the spell supports with !supports.', 'command hint')
eq(rune.foot[3].text, 'Weight 1.5 oz', 'weight')
eq(rune.comparable, false, 'a rune is not compared')
eq(L.comparable({ cmp = { 5 }, kind = 'other' }), false, 'no stats, no compare')
eq(L.comparable({ cmp = { 5 }, kind = 'weapon', stats = { { k = 'attack', v = 1 } } }), true, 'a weapon is compared')
eq(L.comparable({ kind = 'weapon', stats = { { k = 'attack', v = 1 } } }), false, 'no slots, no compare')
eq(L.supportInfo('A healing potion.'), nil, 'other text is no rune')
eq(L.supportInfo(nil), nil, 'no text')
local top = L.supportInfo('A support rune for a spell socket: cast speed +5%. Fits area spells.')
eq(top.fits[1], 'area', 'one kind')
eq(top.combine, false, 'no combine rule on the top level')
eq(top.command, false, 'no command')
-- other non-gear items keep a plain card
local potion = L.card({ name = 'strong health potion', id = 7588, desc = 'Restores health.', weight = 2 }, {})
eq(potion.stats, nil, 'potion: no stats')
eq(potion.extras[1].rows[1].text, 'Restores health.', 'potion: the description')
eq(potion.comparable, false, 'potion: no compare')
local gem = L.card({ name = 'flawless ruby', rarity = 3, rarityName = 'Rare', desc = 'A gem for a socket.' }, {})
eq(gem.kind, 'RARE', 'gem: the rarity as kind')
eq(gem.extras[1].rows[1].text, 'A gem for a socket.', 'gem: description')

-- ---------------------------------------------------------------- O471: the character cap on a modifier line
eq(L.capText({}), '', 'no cap, no text')
eq(L.capText({ cap = 45 }), ' (character cap 45)', 'the cap of the critical chance')
eq(L.capText({ cap = 150, over = true }), ' (over the character cap of 150)', 'over it')
local capTip = {
  key = '9:9', id = 2160, name = 'old badge', kind = 'other', rarity = 4, rarityName = 'Rare', level = 100, maxTier = 4,
  sides = { p = 2, s = 0, max = 2 },
  mods = {
    { k = 'rarity_criticalHitChance', l = 'Critical Strike Chance', t = 'Critical Strike Chance +7%', v = 7, g = 'single',
      lo = 7, hi = 8, tr = 8, sd = 'p', cap = 45, over = true },
    { k = 'chaos_mod_physpen', l = 'Physical Penetration', t = 'Physical Penetration +9%', v = 9, g = 'chaos', lo = 9, hi = 9,
      tr = 6, sd = 'p', cap = 20, bd = true }
  }
}
local capLines = L.lines(capTip, { level = 60 })
local capAll = {}
for i, l in ipairs(capLines) do capAll[i] = l.text end
capAll = table.concat(capAll, '|')
eq(capAll:find('T8 Critical Strike Chance +7% [7-8] (over the character cap of 45)', 1, true) ~= nil, true, 'the line says it is over the cap')
eq(capAll:find('T6 Physical Penetration +9% [9] (character cap 20) [bound]', 1, true) ~= nil, true, 'the cap before [bound]')
local critLine
for _, l in ipairs(capLines) do
  if l.text:find('Critical Strike Chance', 1, true) then critLine = l end
end
eq(critLine.parts[7], ' (over the character cap of 45)', 'the cap text is a part of its own')
eq(critLine.parts[8], L.COLORS.red, 'red when over')
local groups = L.modGroups(capTip)
eq(groups[1].rows[1].parts[3], ' (over the character cap of 45)', 'the group row carries the cap too')
eq(groups[1].rows[2].parts[3], ' (character cap 20)', 'a row with a bound modifier and a cap')
eq(groups[1].rows[2].parts[5], ' [bound]', 'then the bound mark')
eq(groups[1].rows[2].parts[4], L.COLORS.dim, 'the cap in the dim colour')

-- ---------------------------------------------------------------- the gem block (O479, owner 2026-11-11: colour option 3)
do
  local C = L.COLORS
  local pt = dofile(dir .. '../client_chaos_locale/pt_br.lua')
  local function withLang(table_, fn)
    local saved = rawget(_G, 'tr')
    rawset(_G, 'tr', function(s, ...)
      s = (table_ and table_[s]) or s
      if select('#', ...) > 0 then return string.format(s, ...) end
      return s
    end)
    fn()
    rawset(_G, 'tr', saved)
  end
  local chipped = { name = 'chipped diamond', id = 3028, count = 3, weight = 0.1,
    desc = 'A gem for a socket. Weapon: Holy Damage +2%. Armour: Elemental Resistances +1%. Jewellery: Holy Resistance +2%. '
      .. 'Use it on gear with a free socket. Three of the same make one of the next quality: use the stack, then left-click it.',
    gem = { combine = true, rows = {
      { place = 'weapon', label = 'Holy Damage', value = '+2%', text = 'Holy Damage +2%' },
      { place = 'armour', label = 'Elemental Resistances', value = '+1%', text = 'Elemental Resistances +1%' },
      { place = 'jewel', label = 'Holy Resistance', value = '+2%', text = 'Holy Resistance +2%' } } },
    src = { s = { { k = 'drop', n = 'Any monster', v = 'global drop' } }, e = { p = 1 / 3350, w = 'kill' } } }
  local perfect = { name = 'perfect amethyst', gem = { combine = false, rows = {
    { place = 'weapon', label = 'Critical Chance', value = '+3%', label2 = 'Critical Hit', value2 = '+25%',
      text = 'Critical Chance +3%, Critical Hit +25%' },
    { place = 'armour', label = 'Death Resistance', value = '+8%' }, { place = 'jewel', label = 'Death Damage', value = '+12%' } } } }

  -- the named colours
  eq(C.gemWeapon, '#ff9a5c', 'weapon label colour') eq(C.gemArmour, '#6fb0ff', 'armour label colour')
  eq(C.gemJewel, '#c890ff', 'jewellery label colour') eq(C.gemValue, C.quality, 'the number is the quality green')
  eq(C.gemEffect, C.text, 'the effect name is the text colour') eq(C.gemHint, C.dim, 'hints are dim') eq(C.gemHead, C.dim, 'header is dim')

  withLang(nil, function()
    local b = L.gemBlock(chipped)
    eq(b.head, 'SOCKETED IN', 'English header')
    eq(#b.rows, 3, 'one row per place')
    eq(b.rows[1].label, 'Weapon:', 'weapon label') eq(b.rows[2].label, 'Armour:', 'armour label') eq(b.rows[3].label, 'Jewellery:', 'jewellery label')
    eq(b.rows[1].labelColor, C.gemWeapon, 'weapon colour') eq(b.rows[2].labelColor, C.gemArmour, 'armour colour')
    eq(b.rows[3].labelColor, C.gemJewel, 'jewellery colour')
    eq(b.rows[1].text, 'Holy Damage +2%', 'effect text') eq(b.rows[2].text, 'Elemental Resistances +1%', 'effect text 2')
    -- the parts of a row: the name (text colour), the number (value colour)
    eq(b.rows[1].parts[1], 'Holy Damage ', 'name part') eq(b.rows[1].parts[2], C.gemEffect, 'name colour')
    eq(b.rows[1].parts[3], '+2%', 'number part') eq(b.rows[1].parts[4], C.gemValue, 'number colour')
    eq(#b.hints, 2, 'two hints')
    eq(b.hints[1], 'Use it on gear with a free socket.', 'first hint')
    eq(b.hints[2], 'Three of the same make one of the next quality: use the stack, then left-click it.', 'combine hint')
    local p = L.gemBlock(perfect)
    eq(#p.hints, 1, 'a Perfect gem has no combine hint')
    eq(#p.rows, 4, 'a pair effect takes a second row')
    eq(p.rows[2].label, '', 'the second row has no label') eq(p.rows[2].cont, true, 'and is marked as the continuation')
    eq(p.rows[1].text, 'Critical Chance +3%', 'first of the pair') eq(p.rows[2].text, 'Critical Hit +25%', 'second of the pair')
    eq(p.rows[2].parts[3], '+25%', 'both numbers have their own part') eq(p.rows[2].parts[4], C.gemValue, 'and the value colour')
    eq(L.gemBlock({ name = 'x' }), nil, 'an item without tip.gem: no block (an older server)')
    eq(L.gemBlock({ gem = { rows = {} } }), nil, 'no rows: no block')
    eq(L.gemBlock({ gem = { rows = { { place = 'head', label = 'a', value = '+1' } } } }), nil, 'an unknown place is dropped')

    -- the card: the box, then the two hints outside it; the long description is gone; sources and weight stay
    local card = L.card(chipped, { level = 10, alt = true })
    eq(card.extras[1].kind, 'gembox', 'the gem box first') eq(card.extras[1].head, 'SOCKETED IN', 'its header')
    eq(card.extras[1].headColor, C.gemHead, 'dim header') eq(#card.extras[1].rows, 3, 'three rows in the box')
    eq(card.extras[2].rows[1].text, 'Use it on gear with a free socket.', 'the hint after the box') eq(card.extras[2].rows[1].color, C.gemHint, 'dim hint')
    local all = {}
    for _, g in ipairs(card.extras) do for _, r in ipairs(g.rows) do all[#all + 1] = r.text end end
    local joined = table.concat(all, '\n')
    eq(joined:find('A gem for a socket', 1, true), nil, 'no old sentence in the card (no double information)')
    eq(joined:find('Three of the same make', 1, true) ~= nil, true, 'the combine hint is in the card once')
    eq(card.foot[1].text, 'Drops from: Any monster (global drop)', 'the drop row without the chance')
    eq(card.foot[2].text, '~1 in 3,350 kills', 'the chance once, in the effort row')
    eq(card.foot[#card.foot].text, 'Weight 0.1 oz', 'the weight stays')
    -- an older server (no tip.gem): the description as before
    local old = {}
    for k, v in pairs(chipped) do old[k] = v end
    old.gem = nil
    local oldCard = L.card(old, { level = 10 })
    local oldAll = {}
    for _, g in ipairs(oldCard.extras) do for _, r in ipairs(g.rows) do oldAll[#oldAll + 1] = r.text end end
    eq(table.concat(oldAll, ' '):find('A gem for a socket.', 1, true) ~= nil, true, 'no tip.gem: the description is shown')
    -- the same in the line list
    local lines = L.lines(chipped)
    local txt = {}
    for _, l in ipairs(lines) do txt[#txt + 1] = l.text end
    local lj = table.concat(txt, '\n')
    eq(lj:find('SOCKETED IN', 1, true) ~= nil and lj:find('Weapon: Holy Damage +2%', 1, true) ~= nil, true, 'L.lines: the rows')
    eq(lj:find('A gem for a socket', 1, true), nil, 'L.lines: no old sentence')
  end)

  withLang(pt, function()
    local b = L.gemBlock(chipped)
    eq(b.head, 'ENCAIXADA EM', 'pt-BR header')
    eq(b.rows[1].label, 'Arma:', 'Arma') eq(b.rows[2].label, 'Armadura:', 'Armadura') eq(b.rows[3].label, 'Joia:', 'Joia')
    eq(b.rows[1].text, 'Dano Sagrado +2%', 'effect in pt-BR') eq(b.rows[2].text, 'Resist\195\170ncias Elementais +1%', 'effect 2 in pt-BR')
    eq(b.rows[3].text, 'Resist\195\170ncia Sagrada +2%', 'effect 3 in pt-BR')
    eq(b.hints[1], 'Use em um equipamento com um encaixe livre.', 'pt-BR hint')
    eq(b.hints[2], 'Tr\195\170s iguais formam uma da qualidade seguinte: use a pilha e depois clique nela com o bot\195\163o esquerdo.', 'pt-BR combine hint')
    local p = L.gemBlock(perfect)
    eq(p.rows[2].text, 'Dano Cr\195\173tico +25%', 'pair second effect in pt-BR')
    -- every effect name the server can send has a pt-BR text (the gem config's labels)
    local cfg = dofile(dir .. '../../../../server/data/lib/chaos_gems_config.lua')
    for key, def in pairs(cfg.effects) do
      eq(pt[def.label] ~= nil, true, 'pt-BR text of ' .. def.label)
      if def.label2 then eq(pt[def.label2] ~= nil, true, 'pt-BR text of ' .. def.label2) end
    end
    -- a socketed gem: the name goes through tr, the number stays; an older server's text as it is
    eq(L.socketText({ name = 'Chipped Diamond', text = 'Holy Damage +2%', l = 'Holy Damage', v = '+2%' }), 'Dano Sagrado +2%', 'socket text in pt-BR')
    eq(L.socketText({ text = 'Critical Chance +1%, Critical Hit +5%', l = 'Critical Chance', v = '+1%', l2 = 'Critical Hit', v2 = '+5%' }),
      'Chance de Cr\195\173tico +1%, Dano Cr\195\173tico +5%', 'socket pair in pt-BR')
    eq(L.socketText({ name = 'x', text = 'Fire Damage +9%' }), 'Fire Damage +9%', 'an older server: the text as sent')
    local sock = L.extraGroups({ sockets = { count = 1, max = 1, list = { { name = 'Flawless Ruby', text = 'Fire Damage +9%', color = '#ff5a4a',
      l = 'Fire Damage', v = '+9%' } } } })
    eq(sock[1].rows[1].text, 'Flawless Ruby: Dano de Fogo +9%', 'the socket row in the card')
    eq(sock[1].rows[1].color, '#ff5a4a', 'the gem colour stays')
    -- the sources and weight rows are the client's own words
    eq(L.card(chipped, { alt = true }).foot[1].text, 'Cai de: Any monster (global drop)', 'drops from in pt-BR (the server sends its own words translated)')
  end)

  -- the module reads tr from ChaosLocale when the global one is hidden in _G's metatable (rawget(_G, 'tr') is nil then)
  do
    local saved = rawget(_G, 'tr')
    rawset(_G, 'tr', nil)
    ChaosLocale = { tr = function(s, ...) return 'X:' .. s end }
    eq(L.gemBlock(perfect).head, L.caps('X:Socketed in'), 'tr from ChaosLocale.tr')
    ChaosLocale = nil
    eq(L.gemBlock(perfect).head, 'SOCKETED IN', 'no tr at all: English')
    rawset(_G, 'tr', saved)
  end
end

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('tooltiplogic_test: ' .. checks .. ' checks OK')
