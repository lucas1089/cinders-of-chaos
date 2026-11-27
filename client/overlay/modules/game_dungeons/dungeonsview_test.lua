-- luajit dungeonsview_test.lua && lua5.3 dungeonsview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'dungeonsview.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = DungeonsView

-- no `health` (a base dungeon or an older server): the texts of dungeons.otui
local f = io.open(dir .. 'dungeons.otui', 'r')
local otui = f:read('*a')
f:close()
local panels = {}
for t in otui:gmatch("DifficultyInfo%s+!text:%s*tr%('([^']*)'%)") do
  panels[#panels + 1] = (t:gsub('\\n', '\n'))
end
eq(#panels, 6, 'six panels in dungeons.otui')
for d = 1, 6 do
  eq(V.panelText(d, nil), panels[d], 'default text ' .. d)
  eq(V.DEFAULT[d], panels[d], 'default key ' .. d)
end
eq(V.panelText(6, nil):match('1300%%') ~= nil, true, 'old table at 6')

-- the Vault / generated dungeons: their own curves (server dungeons_difficulty.lua D.healthCurves)
local own = { monsters = { 100, 105, 110, 115, 120, 125 }, boss = { 100, 125, 150, 175, 200, 225 } }
eq(V.panelText(1, own), 'Monster Health 100%\nBoss Health 100%\nMonster Damage 100%', 'own curve 1')
eq(V.panelText(2, own), 'Monster Health 105%\nBoss Health 125%\nMonster Damage 130%\nBonus XP +75%\nGold Drop +75%',
  'own curve 2')
eq(V.panelText(6, own),
  'Monster Health 125%\nBoss Health 225%\nMonster Damage 600%\nBonus XP +400%\nGold Drop +400%\nLoot Chance +60%',
  'own curve 6')
eq(V.panelText(6, own):find('1300', 1, true), nil, 'no 1300% with own curves')
eq(V.panelText(9, own), V.panelText(6, own), 'difficulty clamped')
eq(V.panelText(0, own), V.panelText(1, own), 'difficulty clamped up')

-- bad payloads fall back to the table, never an error
eq(V.panelText(3, 'x'), panels[3], 'string health')
eq(V.panelText(3, {}), panels[3], 'empty health')
eq(V.panelText(3, { monsters = {}, boss = {} }), panels[3], 'empty curves')
eq(V.panelText(3, { monsters = { 1, 2, 'a' }, boss = own.boss }), panels[3], 'not a number')
eq(V.panelText(3, { monsters = { 1, 2, 0 / 0 }, boss = own.boss }), panels[3], 'NaN')
eq(V.panelText(3, { monsters = { 1, 2, 1e300 }, boss = own.boss }), panels[3], 'huge')
eq(V.panelText(3, { monsters = own.monsters, boss = 5 }), panels[3], 'boss not a table')
eq(V.panelText(2.7, own), V.panelText(2, own), 'fractional difficulty')
eq(V.panelText('x', own), V.panelText(1, own), 'difficulty not a number')
local m, b = V.healthOf(own, 4)
eq(m, 115, 'healthOf monsters')
eq(b, 175, 'healthOf boss')

-- banners: own art for the Vault and 6-9, the old names, the fallback
local present = {}
for _, n in pairs(V.BANNERS) do present['/images/dungeons/' .. n .. '.png'] = true end
local function exists(p) return present[p] == true end
eq(V.bannerFor('The Pyre Throne', exists), '/images/dungeons/PyreThrone', 'pyre throne')
eq(V.bannerFor('The Hollow Vault', exists), '/images/dungeons/HollowVault', 'vault')
eq(V.bannerFor('The Marrow Crypts', exists), '/images/dungeons/MarrowCrypts', 'marrow')
eq(V.bannerFor('The Iron Crucible', exists), '/images/dungeons/IronCrucible', 'crucible')
eq(V.bannerFor('The Fallen Sanctum', exists), '/images/dungeons/FallenSanctum', 'sanctum')
eq(V.bannerFor('Rootmaw', exists), '/images/dungeons/Rootkraken', 'rootmaw')
eq(V.bannerFor('Something New', exists), '/images/dungeons/Underworld', 'fallback')
eq(V.bannerFor(nil, exists), '/images/dungeons/Underworld', 'nil title')
-- every banner the table names is in the overlay
local images = dir .. '../../data/images/dungeons/'
for title, n in pairs(V.BANNERS) do
  local h = io.open(images .. n .. '.png', 'rb')
  eq(h ~= nil, true, 'banner file for ' .. title)
  if h then h:close() end
end

-- the Weekly Challenge (server weekly_challenge.lua `weekly`)
eq(V.weeklyTitle(nil), nil, 'no weekly: no line')
eq(V.weeklyTitle({ theme = 'X' }), nil, 'weekly without a label')
local wk = { label = '2026-W45', theme = 'Marrow Crypts', current = true, resetIn = 2 * 86400 + 5 * 3600 }
eq(V.weeklyTitle(wk), 'Weekly Challenge 2026-W45: Marrow Crypts', 'weekly title')
eq(V.weeklyText(wk):match('New layout in 2d 5h%.$') ~= nil, true, 'weekly: time to the new layout')
eq(V.weeklyText({ label = '2026-W45', current = false, resetIn = 60 }):match("last week's") ~= nil, true,
  'weekly: a stale layout says so')
eq(V.weeklyText(wk):match('seed') == nil, true, 'weekly: no seed line without a seed')
local seeded = { label = '2026-W48', theme = 'Marrow Crypts', seed = 1773680016, current = true, resetIn = 60 }
eq(V.weeklyText(seeded):match('^Layout seed 1773680016, the same for every player%.\n') ~= nil, true,
  'weekly: the seed on the first line (V35)')
eq(V.span(3725), '1h 02m', 'span hours')
eq(V.span(59), '0m', 'span minutes')
eq(V.bannerTitle({ title = 'Weekly Challenge', weekly = wk }), 'The Marrow Crypts', 'weekly banner: the theme')
eq(V.bannerTitle({ title = 'The Pyre Throne' }), 'The Pyre Throne', 'banner title')
eq(V.bannerFor(V.bannerTitle({ title = 'Weekly Challenge', weekly = wk }), exists), '/images/dungeons/MarrowCrypts',
  'weekly banner file')

-- the card rail (O555): groups by level band, the Weekly Challenge on its own
eq(V.groupOf(1, nil), 'low', 'level 1')
eq(V.groupOf(499, nil), 'low', 'level 499')
eq(V.groupOf(500, nil), 'mid', 'level 500')
eq(V.groupOf(999, nil), 'mid', 'level 999')
eq(V.groupOf(1000, nil), 'high', 'level 1000')
eq(V.groupOf(2000, nil), 'high', 'level 2000')
eq(V.groupOf(nil, nil), 'low', 'no level')
eq(V.groupOf('700', nil), 'mid', 'a level as a string')
eq(V.groupOf(150, { label = 'W1' }), 'weekly', 'a weekly payload wins over the level')
eq(V.groupOf(150, 'x'), 'low', 'weekly must be a table')
eq(V.groupTitle('low'), 'Levels 1-499', 'low title')
eq(V.groupTitle('mid'), 'Levels 500-999', 'mid title')
eq(V.groupTitle('high'), 'Levels 1000+', 'high title')
eq(V.groupTitle('weekly'), 'Weekly', 'weekly title')
eq(V.groupTag('low') .. V.groupTag('mid') .. V.groupTag('high') .. V.groupTag('weekly'), 'EarlyMidLateWeekly', 'tags')

local list = {
  { id = 9, title = 'Pyre', level = 2000 }, { id = 3, title = 'Chev', level = 500 }, { id = 1, title = 'Bones', level = 150 },
  { id = 10, title = 'Weekly', level = 800 }, { id = 5, title = 'Vault', level = 800 }, { id = 2, title = 'Master', level = 200 },
  { id = 4, title = 'Rootmaw', level = 600 }, { id = 6, title = 'Marrow', level = 1000 }, { id = 11, title = 'Twin', level = 150 },
}
local info = { [10] = { weekly = { label = 'W' } } }
local function infoOf(id) return info[id] end
local function ids(groups)
  local out = {}
  for _, g in ipairs(groups) do
    local one = {}
    for _, e in ipairs(g.items) do one[#one + 1] = e.id end
    out[#out + 1] = g.key .. '=' .. table.concat(one, ',')
  end
  return table.concat(out, ' ')
end
eq(ids(V.arrange(list, infoOf, nil)), 'low=1,11,2 mid=3,4,5 high=6,9 weekly=10', 'all groups, by level then id, the weekly last')
eq(ids(V.arrange(list, infoOf, 'all')), ids(V.arrange(list, infoOf, nil)), "'all' is no filter")
eq(ids(V.arrange(list, infoOf, 'mid')), 'mid=3,4,5', 'one group')
eq(ids(V.arrange(list, infoOf, 'weekly')), 'weekly=10', 'the weekly group')
eq(ids(V.arrange(list, infoOf, 'nonsense')), ids(V.arrange(list, infoOf, nil)), 'a key nobody has shows everything')
eq(ids(V.arrange(list, nil, nil)), 'low=1,11,2 mid=3,4,5,10 high=6,9', 'without payloads the weekly card sits in its band')
eq(ids(V.arrange({}, infoOf, nil)), '', 'no dungeons, no groups')
eq(ids(V.arrange(nil, infoOf, nil)), '', 'nil list')
eq(V.arrange(list, infoOf, nil)[1].title, 'Levels 1-499', 'a group carries its heading')
local fl = V.filters(list, infoOf)
local names = {}
for _, f in ipairs(fl) do names[#names + 1] = f.key .. ':' .. f.count end
eq(table.concat(names, ' '), 'all:9 low:3 mid:3 high:2 weekly:1', 'the filter chips with their counts')
eq(#V.filters({ list[3] }, infoOf), 2, 'one group: All and that group')
eq(V.filters({}, infoOf)[1].count, 0, 'an empty list still has All')
local groups = V.arrange(list, infoOf, nil)
eq(V.pick(groups, 4), 4, 'the chosen dungeon stays chosen')
eq(V.pick(groups, 77), 1, 'a dungeon that is gone: the first card')
eq(V.pick(groups, nil), 1, 'nothing chosen: the first card')
eq(V.pick(V.arrange(list, infoOf, 'high'), 4), 6, 'a dungeon the filter hides: the first card of the filter')
eq(V.pick({}, 4), nil, 'no cards, nothing to pick')
eq(table.concat(V.railIds(groups), ','), '1,11,2,3,4,5,6,9,10', 'rail order')
eq(V.groupWidth(3, 156, 8), 3 * 164, 'a group is as wide as its cards and their margins')
eq(V.groupWidth(0, 156, 8), 0, 'an empty group')
eq(V.groupWidth('x', 156, 8), 0, 'a bad count')
-- the list the arrange sorted is not required to be sorted already, and the input is not reordered by id twice
eq(list[1].id, 9, 'the caller list keeps its order')

-- the texts of a card
eq(V.queuePlayers(3), 3, 'queue number')
eq(V.queuePlayers({ players = 4, estimated = 1 }), 4, 'queue table')
eq(V.queuePlayers(nil), 0, 'no queue')
eq(V.queuePlayers('x'), 0, 'bad queue')
eq(V.queueShort(0), 'Open', 'open queue')
eq(V.queueShort(2), '2 Players', 'two players')
eq(V.queueText(0), 'Queue: Open', 'queue line')
eq(V.queueText({ players = 5 }), 'Queue: 5 Players', 'queue line of a payload')
eq(V.queueTone(0), 'green', 'tone 0')
eq(V.queueTone(2), 'green', 'tone 2')
eq(V.queueTone(3), 'orange', 'tone 3')
eq(V.queueTone(5), 'orange', 'tone 5')
eq(V.queueTone(6), 'red', 'tone 6')
eq(V.queueTone({ players = 9 }), 'red', 'tone of a payload')
eq(V.levelText(150), '150+ Level', 'level text')
eq(V.levelText(nil), '1+ Level', 'level text without a level')
eq(V.lockText(800, 600), 'Needs level 800', 'a level below the requirement')
eq(V.lockText(800, 800), nil, 'exactly the level')
eq(V.lockText(800, 1200), nil, 'above the level')
eq(V.lockText(800, nil), nil, 'unknown character level: no veil')
eq(V.lockText(nil, 5), nil, 'unknown requirement: no veil')
eq(V.lockText('800', '600'), 'Needs level 800', 'numbers as strings')
eq(V.difficultyName(1), 'Normal', 'difficulty 1')
eq(V.difficultyName(6), 'Hell', 'difficulty 6')
eq(V.difficultyName(9), 'Hell', 'difficulty clamped')
eq(V.bestText(1), nil, 'nothing to say about Normal')
eq(V.bestText(nil), nil, 'no difficulty')
eq(V.bestText(2), 'Best: Hard', 'best Hard')
eq(V.bestText(6), 'Best: Hell', 'best Hell')
eq(V.bestText(2, true), nil, 'the Weekly Challenge runs at Normal only: no best (V35)')
eq(V.headerChips({ id = 10, level = 800 }, { req = { level = 800 }, difficulty = 2, weekly = true }, 1500).best, nil,
  'no best chip on the Weekly Challenge (V35)')
local chips = V.headerChips({ id = 1, level = 150, queue = 2 }, { req = { level = 150, party = '1-2' }, queue = { players = 4 }, difficulty = 3 }, 600)
eq(chips.level, '150+ Level', 'header level')
eq(chips.levelTone, 'plain', 'header level tone')
eq(chips.queue, 'Queue: 4 Players', 'the payload queue beats the list queue')
eq(chips.queueTone, 'orange', 'header queue tone')
eq(chips.best, 'Best: Expert', 'header best')
local chips2 = V.headerChips({ id = 5, level = 800, queue = 0 }, nil, 100)
eq(chips2.level, '800+ Level', 'header level without a payload')
eq(chips2.levelTone, 'red', 'a character below the level sees it red')
eq(chips2.queue, 'Queue: Open', 'header queue without a payload')
eq(chips2.best, nil, 'no best without a payload')
eq(V.headerChips(nil, nil, nil).level, '1+ Level', 'header of nothing')
eq(V.statusText(800, 600, 3), 'Needs level 800', 'the status names the missing level first')
eq(V.statusText(800, 900, 3), '3 Players', 'else the queue')
eq(V.statusText(800, 900, 0), 'Open', 'an open queue')

-- a card name that does not fit ends in '..' (seen in a client 2026-11-25: "Master of the Element" cut at the edge)
local w6 = function(t) return #t * 6 end
eq(V.fit('Rootmaw', 142, w6), 'Rootmaw', 'a short name stays whole')
eq(V.fit('Master of the Elements', 120, w6), 'Master of the Elem..', 'a long name ends in ..')
eq(V.fit('Master of the Elements', 120, w6):len() * 6 <= 120, true, 'the cut name fits')
eq(V.fit('Master of', 40, w6), 'Mast..', 'cut inside a word')

-- the difficulty tile: the engine moves only the top-left corner of the text by text-offset, so a centred text with
-- offset -56 moved 28 px and sat on the icon (seen in a client 2026-11-25); the name is drawn from the top
local tile = otui:match('DifficultyButton < Panel\n(.-)\n%S')
eq(tile and tile:find('text%-align: top') ~= nil, true, 'the tile name is aligned to the top')
eq(tile and tile:find('text%-offset: 0 %-') == nil, true, 'no negative text offset on the tile')

-- every pt-BR line of a tile fits its 108 px (Verdana 9 px, about 5.5 px a character: at most 19 characters)
ChaosLocaleStrings = nil
local okL = pcall(dofile, dir .. '../client_chaos_locale/pt_br.lua')
local pt = okL and ChaosLocaleStrings and ChaosLocaleStrings['pt-BR'] or nil
eq(pt ~= nil, true, 'pt_br.lua loads')
if pt then
  -- the template lines with the biggest number each can show (V.LEVELS: damage 600, XP and gold +400, loot +60)
  local keys = {}
  for _, k in ipairs(panels) do keys[#keys + 1] = { k, '' } end
  for _, k in ipairs({ { 'Monster Health %d%%', '1300' }, { 'Boss Health %d%%', '1300' }, { 'Monster Damage %d%%', '600' },
    { 'Bonus XP +%d%%', '400' }, { 'Gold Drop +%d%%', '400' }, { 'Loot Chance +%d%%', '60' } }) do keys[#keys + 1] = k end
  for _, kv in ipairs(keys) do
    local k = kv[1]
    local v = pt[k]
    eq(v ~= nil, true, 'pt-BR for ' .. k)
    for line in tostring(v):gsub('%%d', kv[2]):gsub('%%%%', '%%'):gmatch('[^\n]+') do
      local n = select(2, line:gsub('[^\128-\191]', ''))
      eq(n <= 19, true, 'pt-BR tile line fits: ' .. line)
    end
  end
end

-- the kill counter's spot (V11, 2026-11-25): the floating chat and the hotbar globes covered it at bottom left
do
  local area = { x = 0, y = 0, width = 1100, height = 720 }
  local chat = { x = 10, y = 455, width = 375, height = 142 }
  local bar = { x = 180, y = 610, width = 740, height = 110 }
  local s = V.counterSpot(area, 305, 170, {})
  eq(s.left, 0, 'nothing in the way: left')
  eq(s.bottom, 0, 'nothing in the way: bottom left')
  s = V.counterSpot(area, 305, 170, { chat, bar })
  eq(s.bottom, 720 - (455 - V.COUNTER_GAP), 'above the chat')
  local top = 720 - s.bottom - 170
  eq(top + 170 <= chat.y, true, 'clear of the chat')
  eq(top >= 0, true, 'inside the map')
  s = V.counterSpot(area, 305, 170, { bar })
  eq(s.bottom, 720 - (610 - V.COUNTER_GAP), 'above the hotbar alone')
  s = V.counterSpot(area, 305, 170, { { x = 400, y = 500, width = 100, height = 100 } })
  eq(s.bottom, 0, 'a rect to the right leaves bottom left')
  -- no room above: bottom left as before
  s = V.counterSpot({ x = 0, y = 0, width = 800, height = 300 }, 305, 200, { { x = 0, y = 100, width = 300, height = 200 } })
  eq(s.bottom, 0, 'no room: the old spot')
  s = V.counterSpot(area, 305, 170, { chat, false })
  eq(s.bottom, 720 - (455 - V.COUNTER_GAP), 'a missing rect is skipped')
end

if fails > 0 then print(fails .. ' failure(s)'); os.exit(1) end
print('dungeonsview tests passed')
