-- luajit spellfix_test.lua && lua5.3 spellfix_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'spelldata.lua')
dofile(dir .. 'spellfix.lua')
local F = ChaosSpellFix
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the fix table against the generated spell data: every corrected entry is a renamed stock spell, no new id is a
-- Chaos spell's, no two corrections share an id, every excluded id is a Chaos spell
local chaosIds, chaosWords, renamed = {}, {}, {}
for _, s in ipairs(ChaosSpellData) do
  chaosIds[s.id] = s.name
  chaosWords[s.words] = true
end
for _, e in pairs(ChaosSpellNames) do
  renamed[e.words] = true
end
local seen = {}
for words, fix in pairs(F.STOCK) do
  eq(renamed[words] or false, true, words .. ' is a renamed stock spell')
  if fix.id then
    eq(chaosIds[fix.id], nil, words .. ': id ' .. fix.id .. ' not a Chaos spell id')
    eq(seen[fix.id], nil, words .. ': id ' .. fix.id .. ' used once')
    eq(fix.id < 256, true, words .. ': id fits in the cooldown packet byte')
    seen[fix.id] = words
  end
end
for id in pairs(F.HELPER_EXCLUDE) do
  eq(chaosIds[id] ~= nil, true, 'excluded id ' .. id .. ' is a Chaos spell')
end

-- apply on a small table shaped like the client's (after the rename)
local function entry(id, name, words, extra)
  local e = { id = id, name = name, words = words, icon = name:lower():gsub('%W', ''), group = { [1] = 2000 },
    mana = 100, level = 10 }
  for k, v in pairs(extra or {}) do
    e[k] = v
  end
  return e
end
local info = {
  ['Pyre Torrent'] = entry(240, 'Pyre Torrent', 'drai gal pyr ul'),
  ['Shadow Step'] = entry(240, 'Shadow Step', 'ash umh'),
  ['Divine Dazzle'] = entry(238, 'Divine Dazzle', 'exana amp res', { group = { [3] = 2000 } }),
  ['Shadow Veil'] = entry(238, 'Shadow Veil', 'fen umh', { group = { [3] = 2000 } }),
  ['Bog Splatter'] = entry(174, 'Bog Splatter', 'kah tin gor'),
  ['Arcane Stitch'] = entry(172, 'Arcane Stitch', 'saen tin', { group = { [2] = 1000 } }),
  ['Sunder Guard'] = entry(243, 'Sunder Guard', 'kah gro', { group = { [3] = 2000, [6] = 12000 } }),
  ['Radiant Shard'] = entry(258, 'Radiant Shard', 'drai ira vas sol', { level = 0, range = 5, area = {} }),
  ['Kindred Mend'] = entry(84, 'Kindred Mend', 'saen kin', { mana = 120 }),
  ['Bonebreaker'] = entry(61, 'Bonebreaker', 'kah brak', { premium = true }),
}
local icons = {}
for _, e in pairs(info) do
  icons[e.icon] = { 7, e.id }
end
local runes = { [3180] = { id = 86, group = 3, name = 'Bastion Rune' }, [3189] = { id = 15, group = 1, premium = true } }
local server = F.serverWords(ChaosSpellData, ChaosSpellNames)
-- the swap of two stock ids (Bog Splatter 174 -> 172, Arcane Stitch 172 -> 174) is a fixture of this test: the shipped table has
-- no entry for them any more (the ids went to the line spell quests), but the mechanism stays tested
F.STOCK['kah tin gor'] = { id = 172 }
F.STOCK['saen tin'] = { id = 174 }
local undo, idMap = F.apply(info, icons, runes, server)
eq(info['Pyre Torrent'].id, 163, 'Pyre Torrent gets the server id')
eq(info['Shadow Step'].id, 240, 'Shadow Step keeps its id')
eq(icons.pyretorrent[2], 163, 'icon table server id follows')
eq(info['Divine Dazzle'].notOnServer, true, 'Divine Dazzle is not on the server')
eq(info['Divine Dazzle'].id, 1238, 'and moves out of the byte range')
eq(info['Shadow Veil'].id, 238, 'Shadow Veil keeps 238')
eq(info['Bog Splatter'].id, 172, 'swap 174 -> 172')
eq(info['Arcane Stitch'].id, 174, 'swap 172 -> 174')
eq(info['Sunder Guard'].id, 171, 'Sunder Guard 171')
eq(info['Sunder Guard'].group[1], 2000, 'Sunder Guard in the attack group, 2 s (rotation pass)')
eq(info['Sunder Guard'].group[3], nil, 'not in the support group')
eq(info['Radiant Shard'].id, 34, 'Radiant Shard 34 (server patch_spell_ids.py)')
eq(info['Radiant Shard'].level, 300, 'Radiant Shard level 300')
eq(info['Radiant Shard'].needTarget, true, 'Radiant Shard needs a target')
eq(info['Kindred Mend'].mana, 140, 'Kindred Mend mana')
eq(info['Bonebreaker'].id, 61, 'Bonebreaker keeps its id')
eq(info['Bonebreaker'].exhaustion, 2000, 'Bonebreaker 2 s (second rotation pass)')
eq(info['Bonebreaker'].level, 8, 'Bonebreaker level 8 (the Warrior line has a spell at the start level)')
eq(info['Bonebreaker'].mana, 10, 'Bonebreaker 10 mana (mana runway, patch_spell_timings.py)')
eq(runes[3180].group, 1, 'Bastion Rune in the attack group')
eq(info['Bonebreaker'].premium, false, 'stock spell free (no premium)')
eq(runes[3189].premium, false, 'rune free (no premium)')
eq(idMap[240], 163, 'id map 240'); eq(idMap[238], false, 'id map 238 dropped'); eq(idMap[61], nil, 'id map 61')
eq(idMap[174], 172, 'id map 174'); eq(idMap[172], 174, 'id map 172'); eq(idMap[243], 171, 'id map 243')
local ids = {}
for name, e in pairs(info) do
  if not e.notOnServer then
    eq(ids[e.id], nil, 'id ' .. e.id .. ' once (' .. name .. ')')
    ids[e.id] = name
  end
end
-- a second apply changes nothing
local undo2, idMap2 = F.apply(info, icons, runes, server)
eq(next(idMap2), nil, 'idempotent: no id changes')
eq(info['Divine Dazzle'].id, 1238, 'idempotent: not moved twice')
F.restore(undo2)
F.restore(undo)
eq(info['Pyre Torrent'].id, 240, 'restore id')
eq(info['Divine Dazzle'].id, 238, 'restore moved id')
eq(info['Divine Dazzle'].notOnServer, nil, 'restore flag')
eq(info['Sunder Guard'].group[3], 2000, 'restore group')
eq(info['Bonebreaker'].exhaustion, nil, 'restore exhaustion')
eq(info['Bonebreaker'].premium, true, 'restore premium')
eq(runes[3189].premium, true, 'restore rune premium')
eq(icons.pyretorrent[2], 240, 'restore icon')
eq(runes[3180].group, 3, 'restore rune')

-- the helper's lists (keyed by the stock ids)
local function helperData()
  local byVoc = { [1] = { 61, 240, 243 }, [3] = { 240, 238, 172 } }
  local healing = { [172] = { 4 }, [174] = { 1 } }
  local support = { [3] = { 238, 243 } }
  local supportSet = { [3] = { [238] = true, [243] = true } }
  local ignored = { [174] = true }
  local ranged = { 237, 238 }
  local expose = { [243] = true }
  local buff = { [243] = 10000 }
  local d = {}
  function d.getSpellFilterByVocation() return byVoc end
  function d.getHealingSpellFilter() return healing end
  function d.getSupportSpellsWhitelist() return support end
  function d.getSupportSpellsWhitelistSet() return supportSet end
  function d.getIgnoredSpellsIds() return ignored end
  function d.getRangedMonsterSpells() return ranged end
  function d.isRangedMonsterSpell(id) return id == 237 or id == 238 end
  function d.isExposeWeaknessSpell(id) return expose[id] == true end
  function d.isSapStrengthSpell(id) return id == 244 end
  function d.getBuffDuration(id) return buff[id] or 0 end
  return d
end
local d = helperData()
eq(F.remapHelper(d, idMap), true, 'remapped')
eq(F.remapHelper(d, idMap), false, 'only once')
eq(table.concat(d.getSpellFilterByVocation()[1], ','), '61,163,171', 'warrior list')
eq(table.concat(d.getSpellFilterByVocation()[3], ','), '163,174', 'mystic list: Divine Dazzle dropped, Arcane Stitch 174')
eq(d.getHealingSpellFilter()[174][1], 4, 'healing key 172 -> 174')
eq(d.getHealingSpellFilter()[172][1], 1, 'healing key 174 -> 172')
eq(table.concat(d.getSupportSpellsWhitelist()[3], ','), '171', 'support list')
eq(d.getSupportSpellsWhitelistSet()[3][238], nil, 'support set: 238 (now Shadow Veil) out')
eq(d.getSupportSpellsWhitelistSet()[3][171], true, 'support set: 171')
eq(d.getIgnoredSpellsIds()[172], true, 'ignored follows the spell')
eq(d.getIgnoredSpellsIds()[174], nil, 'ignored follows the spell (174)')
eq(table.concat(d.getRangedMonsterSpells(), ','), '237', 'ranged list: 238 dropped')
eq(d.isRangedMonsterSpell(238), false, 'Shadow Veil is no ranged monster spell')
eq(d.isRangedMonsterSpell(237), true, "Duelist's Oath still is")
eq(d.isExposeWeaknessSpell(171), true, 'Sunder Guard expose weakness at 171')
eq(d.isExposeWeaknessSpell(243), false, 'Counter Stance (243) is not')
eq(d.getBuffDuration(171), 10000, 'buff by the new id')
eq(d.getBuffDuration(243), 0, 'no buff on the Chaos 243')

-- the spells the server removed (ChaosRemovedSpells, the conjure spells): kept with their id, never cast, out of the
-- helper's lists
local rinfo = {
  ['Hexdart Rune'] = entry(7, 'Hexdart Rune', 'rhun ti zhul', { group = { [3] = 2000 } }),
  ['Bonebreaker'] = entry(61, 'Bonebreaker', 'kah brak'),
}
local removed = F.removedWords(ChaosRemovedSpells)
eq(removed['rhun ti zhul'], true, 'Hexdart Rune is a removed spell (spelldata.lua)')
local rundo, rmap, rids = F.apply(rinfo, {}, {}, server, removed)
eq(rinfo['Hexdart Rune'].id, 7, 'removed spell keeps its id')
eq(rinfo['Hexdart Rune'].notOnServer, true, 'removed spell is never cast')
eq(rids[7], true, 'removed id reported')
eq(rids[61], nil, 'live spell not removed')
local rd = helperData()
rd.getSpellFilterByVocation()[1] = { 7, 61 }
F.remapHelper(rd, rmap, rids)
eq(table.concat(rd.getSpellFilterByVocation()[1], ','), '61', 'removed spell out of the helper list')
F.restore(rundo)
eq(rinfo['Hexdart Rune'].notOnServer, nil, 'restore removed flag')

-- a removed spell whose id a Chaos spell took (Conjure Rations 42 -> Grave Nova, 2026-10-22): it moves off the server's
-- ids instead, so the Chaos spell keeps the id's cooldown and helper entries
local gn
for _, s in ipairs(ChaosSpellData) do if s.name == 'Grave Nova' then gn = s end end
eq(gn and gn.id, 42, 'Grave Nova has the id of Conjure Rations')
eq(removed['drai bren'], true, 'Conjure Rations is a removed spell')
local cinfo = { ['Conjure Rations'] = entry(42, 'Conjure Rations', 'drai bren', { group = { [3] = 2000 } }) }
local cundo, cmap, cids = F.apply(cinfo, {}, {}, server, removed, F.chaosIds(ChaosSpellData))
eq(cinfo['Conjure Rations'].id, 42 + F.OFF_SERVER, 'Conjure Rations moved off id 42')
eq(cinfo['Conjure Rations'].notOnServer, true, 'Conjure Rations is never cast')
eq(cids[42], nil, 'id 42 is not a removed id (Grave Nova keeps it)')
eq(cmap[42], false, 'the stock 42 leaves the helper lists')
F.restore(cundo)
eq(cinfo['Conjure Rations'].id, 42, 'restore the id')

-- the attack kit (2026-10-23) took the ids of 37 stock spells that the cap retired (Deep Mending 2, Summon Creature 9 ...):
-- each of those entries moves off its id, so the Chaos spell keeps the id's cooldown and its helper entries
do
  local capRemoved = F.removedWords(ChaosRemovedSpells, ChaosCappedSpells)
  local ids = F.chaosIds(ChaosSpellData)
  local f = io.open(dir .. 'spelldata.lua', 'r')
  local text = f:read('*a')
  f:close()
  local capped = text:sub((text:find('ChaosCappedSpells = {', 1, true)))
  local moved, kit = 0, {}
  for _, s in ipairs(ChaosSpellData) do
    if s.name == 'Gorehook' or s.name == 'Bulwark Slam' or s.name == 'Rampart Quake' then kit[s.id] = s.name end
  end
  for words, keep, name, id in capped:gmatch('%["([^"]+)"%] = (%b{}), %-%- ([^\n]-) %((%d+)%)') do
    id = tonumber(id)
    if #keep == 2 and ids[id] then
      local info = { [name] = entry(id, name, words) }
      local _, map, rids = F.apply(info, {}, {}, server, capRemoved, ids)
      eq(info[name].id, id + F.OFF_SERVER, name .. ' moved off id ' .. id .. ' (a Chaos spell has it)')
      eq(info[name].notOnServer, true, name .. ' is never cast')
      eq(rids[id], nil, 'id ' .. id .. ' is not a removed id')
      moved = moved + 1
    end
  end
  eq(moved >= 37, true, 'at least the 37 kit ids were stock ids: ' .. moved)
  eq(next(kit) ~= nil, true, 'the kit spells are in the Chaos spell data')
end

-- a stock spell the server retired (ChaosRetiredSpells: Sharpshooter, 2026-10-20): no rename, so its stock words are not
-- the server's; it leaves id 135 to the Chaos Tautstring and is never cast, and the helper's lists drop the stock 135
eq(ChaosRetiredSpells and ChaosRetiredSpells['utito tempo san'], true, 'Sharpshooter is a retired stock spell')
local taut
for _, s in ipairs(ChaosSpellData) do if s.name == 'Tautstring' then taut = s end end
eq(taut and taut.id, 135, 'Tautstring has the retired id 135')
eq(taut and taut.group, 3, 'Tautstring is a support spell')
for _, e in pairs(ChaosSpellNames) do
  eq(e.words == 'vyr ira sol', false, 'no rename to the retired Hawkeye words')
end
eq(F.STOCK['vyr ira sol'], nil, 'no fix entry for the retired Hawkeye')
local tinfo = { ['Sharpshooter'] = entry(135, 'Sharpshooter', 'utito tempo san', { group = { [3] = 2000, [2] = 10000 } }) }
local tserver = F.serverWords(ChaosSpellData, ChaosSpellNames)
local tundo, tmap = F.apply(tinfo, {}, {}, tserver, F.removedWords(ChaosRemovedSpells))
eq(tinfo['Sharpshooter'].notOnServer, true, 'Sharpshooter is never cast')
eq(tinfo['Sharpshooter'].id, 135 + F.OFF_SERVER, 'Sharpshooter moved off the server ids')
eq(tmap[135], false, 'the stock 135 leaves the helper lists')
F.restore(tundo)

-- the same for Protector (Bulwark, 132 -> Ironhold) and Swift Foot (Windrunner, 134 -> Wildstride), 2026-10-20: both
-- pacified the caster for 10 s (O254: id 134 is the attack spell Gale Volley now)
for _, r in ipairs({ { 'utamo tempo', 'Protector', 132, 'Ironhold', 'tor ira' },
    { 'utamo tempo san', 'Swift Foot', 134, 'Gale Volley', 'tor ira sol', 1 } }) do
  local old, stock, id, chaos, oldWords, grp = r[1], r[2], r[3], r[4], r[5], r[6] or 3
  eq(ChaosRetiredSpells[old], true, stock .. ' is a retired stock spell')
  local new
  for _, s in ipairs(ChaosSpellData) do if s.name == chaos then new = s end end
  eq(new and new.id, id, chaos .. ' has the retired id ' .. id)
  eq(new and new.group, grp, chaos .. ' has its group')
  eq(ChaosSpellNames[old], nil, 'no Chaos name for the retired ' .. stock)
  eq(F.STOCK[oldWords], nil, 'no fix entry for the retired ' .. stock)
  local info = { [stock] = entry(id, stock, old, { group = { [3] = 2000 } }) }
  local undo, map = F.apply(info, {}, {}, tserver, F.removedWords(ChaosRemovedSpells))
  eq(info[stock].notOnServer, true, stock .. ' is never cast')
  eq(info[stock].id, id + F.OFF_SERVER, stock .. ' moved off the server ids')
  eq(map[id], false, 'the stock ' .. id .. ' leaves the helper lists')
  F.restore(undo)
end

-- the 15-spell cap (ChaosCappedSpells, server/tools/patch_spell_cap.py, 2026-10-20)
do
  eq(type(ChaosCappedSpells), 'table', 'ChaosCappedSpells generated')
  eq(#ChaosCappedSpells['drai zar nyx'], 0, 'Lance of the Grave retired')
  local removedSet = F.removedWords(ChaosRemovedSpells, ChaosCappedSpells)
  eq(removedSet['drai zar nyx'], true, 'a retired spell is a removed word')
  eq(removedSet['saen'], nil, 'Minor Mending stays')
  eq(table.concat(F.capVocations('saen', { 1, 2, 4, 8, 14, 3, 10 }, ChaosCappedSpells), ','), '1,3,10',
    'Minor Mending: the Warrior line (4, 8, 14) and the old druid 2 cut')
  eq(F.capVocations('kah brak', { 4, 8, 14 }, ChaosCappedSpells), nil, 'Bonebreaker: not capped')
  eq(F.capVocations('saen', { 1, 3 }, ChaosCappedSpells), nil, 'nothing to cut: nil')
  -- a fix entry never gives a class back that the cap took away
  for words, fix in pairs(F.STOCK) do
    local keep = ChaosCappedSpells[words]
    if fix.vocations and keep and #keep > 0 then
      eq(F.capVocations(words, fix.vocations, ChaosCappedSpells), nil, words .. ': fix vocations within the cap')
    end
  end
  for _, e in ipairs(F.EXTRA) do
    eq(ChaosCappedSpells[e.words] == nil or #ChaosCappedSpells[e.words] > 0, true, e.name .. ' is not retired')
  end
  local cinfo = { ['Lance of the Grave'] = entry(260, 'Lance of the Grave', 'drai zar nyx') }
  local cundo = F.apply(cinfo, {}, {}, server, removedSet)
  eq(cinfo['Lance of the Grave'].notOnServer, true, 'a retired spell is never cast')
  F.restore(cundo)
end

-- the base spells the client had no entry for (F.EXTRA) carry the installed server's numbers
-- (server/data/spells/stock_spells.csv, written from an installed server by server/tools/rotation_sim.py)
local VOC = { Mystic = 1, Elementalist = 5, Illusionist = 10 }
local csvPath = dir .. '../../../../server/data/spells/stock_spells.csv'
local fh = io.open(csvPath, 'r')
eq(fh ~= nil, true, 'stock_spells.csv found')
if fh then
  local rows = {}
  for line in fh:lines() do
    local f = {}
    for v in (line .. ','):gmatch('([^,]*),') do f[#f + 1] = v end
    rows[tonumber(f[1]) or -1] = f
  end
  fh:close()
  -- a cooldown a fix entry gives is the server's (the cooldown ladder, 2026-10-20)
  for id, r in pairs(rows) do
    local fix = r[3] and F.STOCK[r[3]]
    if id > 0 and fix and fix.exhaustion then
      eq(fix.exhaustion, tonumber(r[7]), r[2] .. ': fix cooldown = the server cooldown')
    end
  end
  for _, e in ipairs(F.EXTRA) do
    local r = rows[e.id]
    eq(r ~= nil, true, e.name .. ' is a server spell')
    if r then
      eq(r[2], e.name, e.name .. ' name'); eq(r[3], e.words, e.name .. ' words')
      eq(tonumber(r[5]), e.level, e.name .. ' level'); eq(tonumber(r[6]), e.mana, e.name .. ' mana')
      eq(tonumber(r[7]), e.cooldown, e.name .. ' cooldown'); eq(tonumber(r[8]), e.groupCooldown, e.name .. ' group cooldown')
      local v = {}
      for name in r[12]:gmatch('[^;]+') do v[#v + 1] = VOC[name] or -1 end
      eq(table.concat(v, ','), table.concat(e.vocations, ','), e.name .. ' vocations')
    end
    eq(chaosIds[e.id], nil, e.name .. ': not a Chaos spell id')
    eq(seen[e.id], nil, e.name .. ': id not used by a fixed stock entry')
  end
end

-- the helper's lists get every castable spell (owner 2026-10-17: "some spells appear in the spellbook but not in the helper")
do
  local lists = { byVoc = { [3] = { 5 }, [13] = { 5 } }, healing = {}, support = {}, supportSet = {}, ignored = { [90] = true } }
  local data = {
    getSpellFilterByVocation = function() return lists.byVoc end,
    getHealingSpellFilter = function() return lists.healing end,
    getSupportSpellsWhitelist = function() return lists.support end,
    getSupportSpellsWhitelistSet = function() return lists.supportSet end,
    getIgnoredSpellsIds = function() return lists.ignored end,
  }
  local HV = { [1] = 3, [4] = 1, [10] = 4 }
  local function has(list, id) for _, v in ipairs(list or {}) do if v == id then return true end end return false end
  local spells = {
    { id = 5, name = 'Already There', groups = { 1 }, vocations = { 1 } },
    { id = 168, name = 'Riftbolt', groups = { 1 }, vocations = { 1, 5, 10 } },       -- F.EXTRA style: attack
    { id = 130, name = 'Mend', groups = { 2 }, vocations = { 1 } },                  -- healing
    { id = 131, name = 'Ward', groups = { 3 }, vocations = { 4 } },                  -- support
    { id = 90, name = 'Ignored', groups = { 1 }, vocations = { 1 } },                -- the helper ignores it
    { id = 179, name = 'Excluded', groups = { 1 }, vocations = { 1 } },
    { id = 140, name = 'Nobody', groups = { 1 }, vocations = { 99 } },               -- no helper class
  }
  local added = F.extendHelperLists(data, spells, HV, { [179] = true }, true)
  eq(has(lists.byVoc[3], 168) and has(lists.byVoc[13], 168), true, 'Riftbolt: Mystic helper class and its promoted +10')
  eq(has(lists.byVoc[4], 168), true, 'Riftbolt: Illusionist helper class (4)')
  eq(#lists.byVoc[3], 3, 'Mystic list: Already There once, Riftbolt, Mend')
  eq(has(lists.healing[130], 3) and has(lists.healing[130], 13), true, 'healing filter for the healing spell')
  eq(has(lists.byVoc[3], 130), true, 'a healing spell is also in the vocation list')
  eq(has(lists.support[1], 131) and lists.supportSet[1][131], true, 'support whitelist for the support spell')
  eq(has(lists.byVoc[3], 90), false, 'the helper ignores 90: left out')
  eq(has(lists.byVoc[3], 179), false, 'excluded id: left out')
  eq(has(lists.byVoc[3], 140), false, 'no helper class: left out')
  eq(#added > 0, true, 'additions are reported')
  eq(#F.extendHelperLists(data, spells, HV, { [179] = true }, true), 0, 'a second pass changes nothing (idempotent)')
  -- the Chaos pass does not skip ignored ids
  local c = F.extendHelperLists(data, { { id = 90, name = 'Ignored', groups = { 1 }, vocations = { 1 } } }, HV, {}, false)
  eq(#c > 0 and has(lists.byVoc[3], 90), true, 'skipIgnored = false offers it')
  eq(#F.extendHelperLists(nil, spells, HV, {}, true), 0, 'no helper data: nothing')
  -- castableFromInfo: instants the server has
  local info = {
    A = { id = 10, type = 'Instant', vocations = { 1 }, group = { [1] = 2000 } },
    B = { id = 11, type = 'Rune', vocations = { 1 }, group = { [1] = 2000 } },
    C = { id = 12, type = 'Instant', vocations = { 1 }, group = { [2] = 1000 }, notOnServer = true },
    D = { id = 1012, type = 'Instant', vocations = { 1 }, group = { [1] = 1 } },
    E = { id = 13, type = 'Instant', vocations = {}, group = { [1] = 1 } },
    F = { id = 14, type = 'Instant', vocations = { 4 }, group = { [3] = 1000, [1] = 2000 } },
    G = { id = 15, type = 'Instant', vocations = { 4 }, group = { [1] = 1 } },
  }
  local list = F.castableFromInfo(info, { [15] = true })
  eq(#list, 2, 'castable: instants on the server with a vocation, not removed')
  eq(list[1].id .. ',' .. list[2].id, '10,14', 'sorted by id')
  eq(table.concat(list[2].groups, ','), '1,3', 'its groups')
end

-- allowsVocation (base patch 0079): the picker rule of the action bar and the custom hotkeys
do
  local function fold(id)
    if id == 15 or id == 7 or id == 3 then return 7 end
    if id == 10 then return 6 end
    if id == 1 or id == 5 then return 5 end
    return 0
  end
  local wild = { vocations = { 15 } }
  local moon = { vocations = { 10 } }
  local stock = { vocations = { 3, 7, 15 } }
  eq(F.allowsVocation(wild, 15, fold), true, 'Wild Bond is offered to the Beastmaster (server id, not the folded 7)')
  eq(F.allowsVocation(wild, 7, fold), false, 'Wild Bond not offered to the Deadeye')
  eq(F.allowsVocation({ vocations = { 7 } }, 15, fold), false, 'a spell listed under the folded id 7 only is not the Beastmaster\'s (O329: no fold)')
  eq(F.allowsVocation(wild, 4, fold), false, 'Wild Bond not offered to the Warrior')
  eq(F.allowsVocation(moon, 10, fold), true, 'Moonfang Pack is offered to the Illusionist (folded 6 is not in its list)')
  eq(F.allowsVocation(moon, 1, fold), false, 'Moonfang Pack not offered to the Mystic')
  eq(F.allowsVocation(stock, 15, fold), true, 'a stock spell listed for the Beastmaster')
  eq(F.allowsVocation({ vocations = { 7 }, notOnServer = true }, 7, fold), false, 'a spell the server lacks is never offered')
  eq(F.allowsVocation({ vocations = { 8 } }, 15, fold), false, 'Summon Knight Familiar: not for the Beastmaster')
  eq(F.allowsVocation({}, 15, fold), true, 'no vocation list: not restricted')
  eq(F.allowsVocation(nil, 15, fold), false, 'no entry')
  eq(F.allowsVocation({ vocations = { 15 } }, 15, nil), true, 'no translate function: the server id still matches')
  -- every real summon spell is offered to its own classes (generated data)
  local function offered(name, vocation)
    for _, s in ipairs(ChaosSpellData) do
      if s.name == name then return F.allowsVocation(s, vocation, fold) end
    end
    return nil
  end
  eq(offered('Wild Bond', 15), true, 'generated data: Wild Bond for the Beastmaster')
  eq(offered('Moonfang Pack', 10), true, 'generated data: Moonfang Pack for the Illusionist')
  for _, s in ipairs(ChaosSpellData) do
    for _, v in ipairs(s.vocations) do
      eq(F.allowsVocation(s, v, fold), true, s.name .. ' is offered to vocation ' .. v)
    end
  end
end

-- O307: a Chaos spell is offered to exactly the classes on its list, with the real fold of base patch 0016 (the Beastmaster
-- folds to 7, the Deadeye: Final Verdict, Twin Verdict, Hail of Dawn and Skewering Line were listed for it)
do
  local function realFold(id)
    if id == 4 or id == 8 or id == 14 then return 8 end
    if id == 3 or id == 7 or id == 15 then return 7 end
    if id == 1 or id == 5 then return 5 end
    if id == 10 then return 6 end
    if id == 11 or id == 12 or id == 13 or (id >= 17 and id <= 25) then return id end
    return 0
  end
  for _, s in ipairs(ChaosSpellData) do
    local on = {}
    for _, v in ipairs(s.vocations) do on[v] = true end
    for v = 1, 25 do
      eq(F.allowsVocation(s, v, realFold), on[v] == true, s.name .. ' for vocation ' .. v .. ' follows its list')
    end
  end
  local fv
  for _, s in ipairs(ChaosSpellData) do if s.name == 'Final Verdict' then fv = s end end
  eq(F.allowsVocation(fv, 15, realFold), false, 'Final Verdict: not for the Beastmaster')
  eq(F.allowsVocation(fv, 7, realFold), true, 'Final Verdict: the Deadeye')
  -- the helper's Auto setup passes the id with the list
  eq(F.allowsVocation({ id = fv.id, vocations = fv.vocations }, 15, realFold), false, 'by id: not for the Beastmaster')
end

-- slots and hotkeys of retired spells are cleared (O145, base patch 0123)
do
  local set = F.retiredWordSet(ChaosRemovedSpells, ChaosCappedSpells, ChaosRetiredSpells, ChaosSpellNames, ChaosSpellData)
  eq(set['ruan gal ul'], true, 'Galeborne Stride (new words) is retired')
  eq(set['utani gran hur'], true, 'and its stock words')
  eq(set['utito tempo san'], true, 'Swift Foot, retired by the cure step')
  for _, c in ipairs(ChaosSpellData) do
    eq(set[c.words:lower()], nil, c.name .. ' is not retired')
  end
  local live = { notOnServer = false }
  local function lookup(text) if text == 'odd words' then return { notOnServer = true } end return live end
  eq(F.slotIsRetired('ruan gal ul', set, lookup), true, 'retired words')
  eq(F.slotIsRetired('Ruan Gal Ul', set, lookup), true, 'any case')
  eq(F.slotIsRetired('odd words', set, lookup), true, 'a stock entry the server does not have')
  eq(F.slotIsRetired(ChaosSpellData[1].words, set, lookup), false, 'a live Chaos spell stays')
  eq(F.slotIsRetired('hello world', set, lookup), false, 'plain text stays')
  eq(F.slotIsRetired('', set, lookup), false, 'empty')
  local maps = {
    { actionBar = 1, actionButton = 1, actionsetting = { chatText = 'ruan gal ul' } },
    { actionBar = 1, actionButton = 2, actionsetting = { chatText = ChaosSpellData[1].words } },
    { keysequence = 'F2', actionsetting = { chatText = 'utani gran hur' } },
    { actionBar = 1, actionButton = 3, actionsetting = { useObject = 3031 } },
    { actionBar = 1, actionButton = 4, actionsetting = { chatText = 'odd words' } },
  }
  eq(F.pruneRetiredSlots(maps, lookup, set), 3, 'three mappings cleared')
  eq(#maps, 2, 'two stay')
  eq(maps[1].actionButton .. ':' .. maps[2].actionButton, '2:3', 'in order')
  eq(F.pruneRetiredSlots(maps, lookup, set), 0, 'a second pass changes nothing')
  eq(F.pruneRetiredSlots(nil, lookup, set), 0, 'no mappings')
end

if fails > 0 then os.exit(1) end
print('spell fix tests OK')
