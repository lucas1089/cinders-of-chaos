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
  ['Bonebreaker'] = entry(61, 'Bonebreaker', 'kah brak'),
}
local icons = {}
for _, e in pairs(info) do
  icons[e.icon] = { 7, e.id }
end
local runes = { [3180] = { id = 86, group = 3, name = 'Bastion Rune' }, [3189] = { id = 15, group = 1 } }
local server = F.serverWords(ChaosSpellData, ChaosSpellNames)
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
eq(runes[3180].group, 1, 'Bastion Rune in the attack group')
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

if fails > 0 then os.exit(1) end
print('spell fix tests OK')
