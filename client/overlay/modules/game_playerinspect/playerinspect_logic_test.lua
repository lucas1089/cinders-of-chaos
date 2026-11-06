-- luajit playerinspect_logic_test.lua && lua5.3 playerinspect_logic_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'playerinspect_logic.lua')
local L = PlayerInspectLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(L.cleanName('  Sir  Lancelot '), 'Sir Lancelot', 'spaces')
eq(L.cleanName("O'Neil-Smith"), "O'Neil-Smith", 'apostrophe, hyphen')
eq(L.cleanName('a'), nil, 'too short')
eq(L.cleanName(string.rep('a', 30)), nil, 'too long')
eq(L.cleanName('x;y'), nil, 'punctuation')
eq(L.cleanName(''), nil, 'empty')
eq(L.cleanName(nil), nil, 'nil')
eq(L.numberText(1234567), '1,234,567', 'thousands')
eq(L.numberText(120), '120', 'small')
eq(L.numberText(nil), '0', 'nil')

local n = 0
for slot = 1, 16 do if L.SLOTS[slot] then n = n + 1 end end
eq(n, 10, 'nine inventory slots and the badge slot have a place')
eq(L.SLOTS[10], nil, 'the ammunition slot is not shown (it takes nothing, server src-patch 0058)')
eq(L.SLOTS[13].name, 'Badge', 'slot 13 is the badge slot, where the ammunition slot was')
eq(L.SLOTS[13].col .. ',' .. L.SLOTS[13].row, '2,2', 'the badge slot sits where the second ring sat')
local seen = {}
for slot, p in pairs(L.SLOTS) do
  local k = p.col .. ',' .. p.row
  eq(seen[k], nil, 'slot ' .. slot .. ' has its own place')
  seen[k] = true
end

local full = { name = 'Anna', level = 120, voc = 'Berserker', ascended = true, guild = { name = 'Ravens', rank = 'Officer' },
  ach = 12500, rift = 7, trials = 3, title = 'Bossbane', paragon = 1234, collection = 410,
  bestiary = { points = 310, rank = 'Tracker' }, bosses = { got = 9, total = 12 },
  pvp = { name = 'Arena 1v1', tier = 'Gold', rating = 1650 }, passive = { spent = 80, total = 120 } }
local h = L.header(full)
eq(h.name.text, 'Anna', 'header name')
eq(h.class.text, 'Level 120 Berserker', 'level and class')
eq(h.badge.text, 'Ascended class', 'ascended badge')
eq(h.title.text, 'Bossbane', 'title')
eq(h.guild.text, 'Officer of Ravens', 'guild')
h = L.header({ name = 'Bob', level = 8, voc = '' })
eq(h.class.text, 'Level 8 No vocation', 'no vocation')
eq(h.badge, nil, 'no badge')
eq(h.title, nil, 'no title')
eq(h.guild.text, 'No guild', 'no guild')
eq(h.guild.color, L.COLORS.dim, 'no guild is dim')
eq(L.header({ name = 'C', level = 1, voc = 'X', guild = { name = 'G' } }).guild.text, 'Member of G', 'guild without rank')

local function flat(sections)
  local out = {}
  for _, sec in ipairs(sections) do
    for _, r in ipairs(sec.rows) do out[r.label] = r end
  end
  return out
end
local sections = L.stats(full)
eq(#sections, 2, 'two sections')
eq(sections[1].title, 'Progress', 'progress section')
eq(sections[2].title, 'Combat', 'combat section')
local rows = flat(sections)
eq(rows['Paragon points'].value, '1,234', 'paragon')
eq(rows['Passive points'].value, '80 / 120', 'passive points')
eq(rows['Achievement points'].value, '12,500', 'achievements')
eq(rows['Collection score'].value, '410', 'collection')
eq(rows['Bestiary'].value, '310 (Tracker)', 'bestiary')
eq(rows['Boss Points'].value, '9 / 12', 'boss points')
eq(rows['Best rift sealed'].value, 'Tier 7', 'rift')
eq(rows['Vocation Trials'].value, 'Tier 3 of 3', 'trials')
eq(rows['Vocation Trials'].color, L.COLORS.good, 'all trials cleared is green')
eq(rows['PvP: Arena 1v1'].value, '1,650 (Gold)', 'pvp')
eq(#sections[1].rows, 6, 'six progress rows')
eq(#sections[2].rows, 3, 'three combat rows')

-- an older server: only the first fields; no row for what was not sent, dim None for rift and trials
rows = flat(L.stats({ level = 8, voc = '', ach = 0, rift = 0, trials = 0 }))
eq(rows['Paragon points'], nil, 'no paragon row')
eq(rows['Passive points'], nil, 'no passive row')
eq(rows['Collection score'], nil, 'no collection row')
eq(rows['Bestiary'], nil, 'no bestiary row')
eq(rows['Boss Points'], nil, 'no boss row')
eq(rows['PvP: Arena'], nil, 'no pvp row')
eq(rows['Achievement points'].value, '0', 'zero achievements still show')
eq(rows['Achievement points'].color, L.COLORS.dim, 'and dim')
eq(rows['Best rift sealed'].value, 'None', 'no rift')
eq(rows['Best rift sealed'].color, L.COLORS.dim, 'dim')
eq(rows['Vocation Trials'].value, 'None', 'no trial')
sections = L.stats({})
eq(#sections[1].rows, 1, 'an empty packet: just the achievement row')
eq(#sections[2].rows, 2, 'and the two combat rows')
-- partial and odd values never raise
rows = flat(L.stats({ bestiary = { points = 5 }, bosses = { got = 0, total = 5 }, pvp = { rating = 900 }, passive = { spent = 3 },
  paragon = 'x' }))
eq(rows['Bestiary'].value, '5', 'bestiary without rank')
eq(rows['Boss Points'], nil, 'zero boss points: no row')
eq(rows['PvP: Arena'].value, '900', 'pvp without tier or name')
eq(rows['Passive points'].value, '3 / 3', 'passive without total')
eq(rows['Paragon points'], nil, 'bad paragon: no row')

-- the combat sheet page
eq(#L.combatStats({}), 0, 'no combat block (older server): no page')
local cs = L.combatStats({ combat = { attack = 40, hit = 1234, maxHit = 98765, attackSpeed = 9, critChance = 12.5, critAmount = 55,
  lifeLeech = { chance = 5, amount = 3 }, damage = { { k = 'fire', pct = 20 } }, defense = 30, armor = 22, mitigation = 34.6,
  resist = { { k = 'fire', pct = 40 }, { k = 'death', pct = -10 } }, maxHealth = 5000, maxMana = 2500, moveSpeed = 450 } })
eq(#cs, 3, 'offense, defense, resistances')
eq(cs[1].title, 'Offense', 'offense title')
local function crow(sec, label) for _, r in ipairs(cs[sec].rows) do if r.label == label then return r end end end
eq(crow(1, 'Weapon attack').value, '40', 'attack')
eq(crow(1, 'Highest hit').value, '98,765', 'highest hit')
eq(crow(1, 'Attack speed').value, '+9%', 'attack speed')
eq(crow(1, 'Critical chance').value, '12.5%', 'crit chance')
eq(crow(1, 'Life leech').value, '5% / 3%', 'leech')
eq(crow(1, 'Mana leech'), nil, 'no mana leech row')
eq(crow(1, 'Fire damage').value, '+20%', 'damage bonus')
eq(crow(2, 'Damage reduction').value, '34.6%', 'damage reduction')
eq(crow(2, 'Maximum health').value, '5,000', 'max health')
eq(crow(3, 'Fire').value, '40%', 'resistance')
eq(crow(3, 'Fire').color, L.COLORS.good, 'positive resistance is green')
eq(crow(3, 'Death').color, L.COLORS.red, 'negative resistance is red')
eq(crow(3, 'Ice'), nil, 'no row for a missing element')
cs = L.combatStats({ combat = { attack = 5 } })
eq(#cs[2].rows, 0, 'empty defense section')
eq(#cs[3].rows, 0, 'empty resistances section')

local st = L.newState()
eq(L.complete(st), false, 'nothing yet')
eq(L.onEquip(st, { name = 'Anna', rows = {} }), false, 'equipment before a result is ignored')
L.onResult(st, { name = 'Anna', parts = 2 })
eq(L.complete(st), false, 'waiting for the equipment')
eq(L.onEquip(st, { name = 'Bob', rows = { { slot = 1, tip = { name = 'x' } } } }), false, 'another character')
eq(L.onEquip(st, { name = 'Anna', rows = { { slot = 1, tip = { name = 'Helm' } }, { slot = 99, tip = {} } } }), true, 'first packet')
eq(st.tips[1].name, 'Helm', 'tip kept')
eq(st.tips[99], nil, 'unknown slot ignored')
eq(L.complete(st), false, 'one packet of two')
L.onEquip(st, { name = 'Anna', rows = { { slot = 6, tip = { name = 'Sword' } } } })
eq(L.complete(st), true, 'complete')
L.onResult(st, { name = 'Bob', parts = 0 })
eq(L.complete(st), true, 'no equipment is complete at once')
eq(st.tips[1], nil, 'a new result clears the slots')
eq(L.tipKey('Anna', 1, { key = '5:6' }), 'inspect:Anna:1:5:6', 'tooltip key')

-- the tree packet and the chunked parts
do
  local st = L.newState()
  eq(L.onTree(st, { name = 'Anna', nodes = { 1 } }), false, 'no tree before a result')
  L.onResult(st, { name = 'Anna', parts = 0 })
  eq(L.treeButtonText(st), nil, 'no tree yet')
  eq(L.onTree(st, { name = 'Bob', nodes = { 2 } }), false, "another character's tree")
  eq(L.onTree(st, { name = 'Anna', nodes = 'x' }), false, 'not a tree')
  eq(L.onTree(st, { name = 'Anna', nodes = { 626, 627, 628, 665 }, masteries = { { id = 665, choice = 2 } } }), true, 'the tree')
  eq(L.treeButtonText(st), 'Passive Tree (4)', 'button text')
  L.onResult(st, { name = 'Anna', parts = 0 })
  eq(st.tree, nil, 'a new result forgets the old tree')
  local parts = {}
  eq(L.joinPart(parts, '{"action":"tree"}'), '{"action":"tree"}', 'a whole message passes')
  eq(L.joinPart(parts, 'S{"a":'), nil, 'first part')
  eq(L.joinPart(parts, 'P"bc'), nil, 'middle part')
  eq(L.joinPart(parts, 'E"}'), '{"a":"bc"}', 'joined')
  eq(L.joinPart(parts, 'E"}'), nil, 'an end without a start')
  eq(L.joinPart(parts, ''), nil, 'empty')
end

-- a full answer as the server sends it (inspect.lua): result whole, the equipment packets each at most 8000 bytes or,
-- a single big row, in S/P/E parts (Chaos.sendChunked), then the tree. The window's handler joins every buffer with
-- L.joinPart before it decodes; here the decoded messages are looked up by their text.
do
  local msgs = {
    ['{"r":1}'] = { action = 'result', data = { name = 'Anna', parts = 3 } },
    ['{"e":1}'] = { action = 'equip', data = { name = 'Anna', part = 1, rows = { { slot = 1, tip = { name = 'Helm' } } } } },
    ['{"e":2,"big":"' .. string.rep('x', 9000) .. '"}'] = { action = 'equip', data = { name = 'Anna', part = 2,
      rows = { { slot = 4, tip = { name = 'Armour' } } } } },
    ['{"e":3}'] = { action = 'equip', data = { name = 'Anna', part = 3, rows = { { slot = 6, tip = { name = 'Sword' } } } } },
    ['{"t":1}'] = { action = 'tree', data = { name = 'Anna', nodes = { 1, 2 } } },
  }
  local big = '{"e":2,"big":"' .. string.rep('x', 9000) .. '"}'
  local wire = { '{"r":1}', '{"e":1}', 'S' .. big:sub(1, 4000), 'P' .. big:sub(4001, 8000), 'E' .. big:sub(8001), '{"e":3}',
    'S{"t"', 'E:1}' }
  local st, parts, decoded = L.newState(), {}, 0
  for _, buffer in ipairs(wire) do
    local whole = L.joinPart(parts, buffer)
    if whole then
      local m = msgs[whole]
      eq(m ~= nil, true, 'every joined message is one the server sent')
      decoded = decoded + 1
      if m.action == 'result' then L.onResult(st, m.data)
      elseif m.action == 'equip' then
        L.onEquip(st, m.data)
        if m.data.part < 3 then eq(L.complete(st), false, 'part ' .. m.data.part .. ' of 3') end
      elseif m.action == 'tree' then L.onTree(st, m.data) end
    end
  end
  eq(decoded, 5, 'five messages from eight buffers')
  eq(L.complete(st), true, 'every equipment packet, the chunked one too')
  eq(st.tips[1].name, 'Helm', 'packet 1')
  eq(st.tips[4].name, 'Armour', 'the chunked packet')
  eq(st.tips[6].name, 'Sword', 'the packet after it')
  eq(L.treeButtonText(st), 'Passive Tree (2)', 'the tree after the equipment')
  -- a part that is cut off (an S never ended) does not swallow the next answer
  local p2 = {}
  eq(L.joinPart(p2, 'S{"lost"'), nil, 'a start')
  eq(L.joinPart(p2, '{"r":1}'), '{"r":1}', 'a whole message still passes')
  eq(L.joinPart(p2, 'S{"e"'), nil, 'a new start')
  eq(L.joinPart(p2, 'E:1}'), '{"e":1}', 'replaces the lost one')
end

-- the personal records packet (O260)
do
  local st = L.newState()
  eq(L.onRecords(st, { name = 'Anna', rows = {} }), false, 'no records before a result')
  eq(L.recordsButtonText(st), nil, 'no button text before the packet')
  L.onResult(st, { name = 'Anna', parts = 0 })
  eq(L.recordsButtonText(st), nil, 'a result without the packet yet')
  eq(L.onRecords(st, { name = 'Bob', rows = {} }), false, 'another character')
  eq(L.onRecords(st, { name = 'Anna', rows = 'x' }), false, 'rows must be a list')
  eq(L.onRecords(st, 5), false, 'junk')
  local rows = { { name = 'Best drop: rarity', value = 'Legendary' }, { name = 'Highest Tower floor', value = 41 },
    { name = 5, value = 'x' }, { name = 'No value' }, 'junk' }
  eq(L.onRecords(st, { name = 'Anna', rows = rows }), true, 'the packet')
  eq(#st.records, 2, 'rows without a text name or a value are dropped')
  eq(st.records[2].value, '41', 'values are text')
  eq(L.recordsButtonText(st), 'Records (2)', 'the button counts the rows')
  eq(L.recordsEmptyText(st), 'No records yet.', 'empty text after the packet')
  L.onResult(st, { name = 'Bob', parts = 0 })
  eq(st.records, nil, 'a new result clears the records')
  eq(L.recordsEmptyText(st), 'Nothing to show.', 'empty text before the packet')
  L.onResult(st, { name = 'Cy', parts = 0 })
  L.onRecords(st, { name = 'Cy', rows = {} })
  eq(L.recordsButtonText(st), 'Records', 'no records: plain text')
  local many = {}
  for i = 1, 60 do many[i] = { name = 'r' .. i, value = i } end
  L.onRecords(st, { name = 'Cy', rows = many })
  eq(#st.records, L.MAX_RECORD_ROWS, 'at most MAX_RECORD_ROWS rows')
end

if fails > 0 then print(fails .. ' of ' .. checks .. ' checks FAILED'); os.exit(1) end
print('playerinspect_logic_test: ' .. checks .. ' checks ok')
