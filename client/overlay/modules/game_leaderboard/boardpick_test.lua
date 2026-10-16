-- luajit boardpick_test.lua && lua5.3 boardpick_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'boardpick.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the server's boards in its order (leaderboard_config.lua), the ladder last
local boards = {
  { key = 'worldboss', name = 'World Boss' }, { key = 'bosshealer', name = 'Boss Healer' },
  { key = 'bosstank', name = 'Boss Tank' }, { key = 'bounty', name = 'Bounty Hunter' }, { key = 'rift', name = 'Rifts' },
  { key = 'goblin', name = 'Goblin Slayer' }, { key = 'siege', name = 'Guild Siege' },
  { key = 'arena1v1', name = 'Arena 1v1' }, { key = 'arena2v2', name = 'Arena 2v2' }, { key = 'arena3v3', name = 'Arena 3v3' },
  { key = 'battleground', name = 'Battleground' }, { key = 'defender', name = 'Defender' },
  { key = 'factions', name = 'Reputation' }, { key = 'cinder_solo', name = 'Cinderheart Solo' },
  { key = 'cinder_small', name = 'Cinderheart 2-3' }, { key = 'cinder_party', name = 'Cinderheart 4-5' },
  { key = 'descent', name = 'Ember Descent' }, { key = 'raid_clear', name = 'Sepulchre Clear' },
  { key = 'marches', name = 'Scorched Marches' }, { key = 'professions', name = 'Gatherers' },
  { key = 'ladder', name = 'Class Ladder' },
}

local function texts(options)
  local t = {}
  for i, o in ipairs(options) do t[i] = o.text end
  return table.concat(t, ' | ')
end

-- English: alphabetical, case-insensitive, every board kept
local en = BoardPick.options(boards)
eq(#en, #boards, 'every board')
eq(texts(en), 'Arena 1v1 | Arena 2v2 | Arena 3v3 | Battleground | Boss Healer | Boss Tank | Bounty Hunter | '
  .. 'Cinderheart 2-3 | Cinderheart 4-5 | Cinderheart Solo | Class Ladder | Defender | Ember Descent | Gatherers | '
  .. 'Goblin Slayer | Guild Siege | Reputation | Rifts | Scorched Marches | Sepulchre Clear | World Boss', 'English order')
eq(en[1].board, boards[8], 'option keeps its board')

-- pt-BR: sorted by the translated name, accents with their base letter (UTF-8 and cp1252 alike)
local pt = {
  ['Reputation'] = 'Reputa\195\167\195\163o', ['Class Ladder'] = 'Ranking de Classes',
  ['Bounty Hunter'] = 'Ca\195\167ador de Bounty', ['Gatherers'] = 'Coletores', ['Defender'] = 'Defensor',
  ['Boss Healer'] = '\195\137lite Cura', -- an accented first letter sorts with E
}
local function trUtf8(s) return pt[s] or s end
local order = BoardPick.options(boards, trUtf8)
local pos = {}
for i, o in ipairs(order) do pos[o.key] = i end
eq(pos.bounty < pos.cinder_small, true, 'Caçador before Cinderheart')
eq(pos.professions > pos.cinder_solo and pos.professions < pos.defender, true, 'Coletores between Cinderheart and Defensor')
eq(pos.bosshealer > pos.defender and pos.bosshealer < pos.descent, true, 'Élite between Defensor and Ember')
eq(pos.ladder > pos.siege and pos.ladder < pos.factions, true, 'Ranking before Reputação')
eq(pos.factions < pos.rift, true, 'Reputação before Rifts')
local function trCp1252(s)
  local v = pt[s]
  if not v then return s end
  return (v:gsub('\195([\128-\191])', function(c) return string.char(c:byte() + 64) end))
end
eq((texts(BoardPick.options(boards, trCp1252)):gsub('[\128-\255]', '?')), (texts(order):gsub('\195[\128-\191]', '?')),
  'cp1252 same order')

eq(BoardPick.fold('\195\137LITE \195\167\195\163'), 'elite ca', 'fold UTF-8')
eq(BoardPick.fold('\201lite \231\227'), 'elite ca', 'fold cp1252')
eq(BoardPick.less('apple', 'Banana'), true, 'case-insensitive')
eq(BoardPick.less('Banana', 'apple'), false, 'case-insensitive reverse')

-- bad entries are left out
eq(#BoardPick.options({ 'x', { name = 'no key' }, { key = 'k' }, false }), 1, 'bad entries')
eq(BoardPick.options({ { key = 'k' } })[1].text, 'k', 'no name: the key')
eq(#BoardPick.options(nil), 0, 'no boards')

-- resolve: the saved board, else World Boss, else the first
eq(BoardPick.resolve(en, 'rift'), 'rift', 'saved board')
eq(BoardPick.resolve(en, 'gone'), 'worldboss', 'unknown: default')
eq(BoardPick.resolve(en, nil), 'worldboss', 'nothing saved: World Boss')
eq(BoardPick.resolve(BoardPick.options({ { key = 'b', name = 'B' }, { key = 'a', name = 'A' } }), nil), 'a', 'no World Boss: first')
eq(BoardPick.resolve({}, 'rift'), nil, 'no options')
eq(BoardPick.resolve(BoardPick.options({ { key = 7, name = 'N' } }), '7'), 7, 'numeric key from the settings')

-- per character settings
local node = BoardPick.remember(nil, 'Ash Knight', 'rift')
eq(node['ash knight'], 'rift', 'remember lower case')
eq(BoardPick.saved(node, ' ASH KNIGHT '), 'rift', 'saved by any case')
eq(BoardPick.saved(node, 'Other'), nil, 'another character')
local node2 = BoardPick.remember(node, 'Other', 'ladder')
eq(node['other'], nil, 'remember copies')
eq(node2['ash knight'], 'rift', 'keeps the others')
eq(node2['other'], 'ladder', 'second character')
eq(BoardPick.saved(node2, nil), nil, 'no character')
eq(BoardPick.saved('bad', 'Ash Knight'), nil, 'bad node')
eq(BoardPick.saved({ ['ash knight'] = 5 }, 'Ash Knight'), nil, 'bad value')
eq(next(BoardPick.remember(nil, '', 'rift')), nil, 'empty name')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('boardpick: all tests passed')
