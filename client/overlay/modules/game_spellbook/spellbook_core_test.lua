-- luajit spellbook_core_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local C = dofile(here .. 'spellbook_core.lua')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function ok(v, m) eq(not not v, true, m) end

eq(ChaosSpellCore, C, 'shared as a global')

-- the spells of a level 8 Mystic (server vocation 1) and others
local S = {
  { name = 'Minor Mending', words = 'a', level = 8, vocations = { 1, 10 } },
  { name = 'Faint Hexdart Rune', words = 'b', level = 1, vocations = { 1, 5 }, rune = 3174, runeClientId = 4174 },
  { name = 'Pebblestorm Rune', words = '', level = 25, vocations = { 4 }, rune = 3175 },
  { name = 'Conjure Hexdart', words = 'adori hex', level = 4, vocations = { 1 }, type = 'conjure' },
  { name = 'Deep Mending', words = 'c', level = 20, vocations = { 1 } },
  { name = 'Grand Mending', words = 'd', level = 30, vocations = { 10 } },
  { name = 'Bog Splatter', words = 'e', level = 14, vocations = { 1 } },
  { name = 'Ember Lash', words = 'f', level = 1, maglevel = 5, vocations = { 1 } },
  { name = 'Old Secret', words = 'g', level = 5, vocations = { 1 }, needLearn = true },
  { name = 'Light', words = 'h', level = 8, vocations = {} },
  { name = 'Reaping Gyre', words = 'kah spir', level = 30, vocations = { 4 } }
}
local by = {}
for _, s in ipairs(S) do by[s.name] = s end
local ctx = { vocation = 1, level = 8, magicLevel = 2, learned = {} }

-- status: vocation, learned, level, magic level
eq(C.status(by['Minor Mending'], ctx), 'ready', 'own vocation, level reached')
eq(C.status(by['Light'], ctx), 'ready', 'no vocation list: everyone')
eq(C.status(by['Grand Mending'], ctx), 'vocation', 'ascension-only spell is not the base class')
eq(C.status(by['Deep Mending'], ctx), 'level', 'level too low')
eq(C.status(by['Ember Lash'], ctx), 'level', 'magic level too low')
eq(C.status(by['Old Secret'], ctx), 'learn', 'needlearn, not learned')
eq(C.status(by['Old Secret'], { vocation = 1, level = 8, learned = { ['old secret'] = true } }), 'ready', 'learned')
C.setLearned({ 'Old Secret' })
eq(C.status(by['Old Secret'], { vocation = 1, level = 8 }), 'ready', 'the shared learned list (server reply)')
C.setLearned({})
eq(C.status(by['Grand Mending'], { level = 100 }), 'ready', 'no vocation in the context: not checked (pickers)')

-- filters
local function names(filter, text, c)
  local out = {}
  local list = {}
  for i, s in ipairs(S) do list[i] = s end
  C.sort(list)
  for _, i in ipairs(C.visibleIndexes(list, c or ctx, filter, text)) do out[#out + 1] = list[i].name end
  return table.concat(out, ',')
end
eq(names('learned'), 'Conjure Hexdart,Light,Minor Mending', 'learned: castable now, by level then name; no runes')
eq(names('soon'), 'Ember Lash,Old Secret,Bog Splatter', 'soon: own vocation, not castable, within 10 levels')
eq(names('vocation'), 'Ember Lash,Conjure Hexdart,Old Secret,Light,Minor Mending,Bog Splatter,Deep Mending',
  'vocation: every spell of the class')
eq(#C.visibleIndexes(S, ctx, 'all', ''), #S - 2, 'all: every spell, no runes')
-- runes have their own filter; a conjure spell (it makes runes) stays a spell
eq(names('runes'), 'Faint Hexdart Rune,Pebblestorm Rune', 'runes: every rune entry, by level')
eq(names('runes', 'pebble'), 'Pebblestorm Rune', 'runes: search')
ok(C.isRune(by['Faint Hexdart Rune']) and not C.isRune(by['Conjure Hexdart']), 'conjure is a spell')
ok(C.isRune({ name = 'X', type = 'Rune' }), 'a client entry of type Rune')
eq(C.normalizeFilter('runes'), 'runes', 'runes is a filter')
for _, f in ipairs({ 'learned', 'soon', 'vocation', 'all' }) do
  for _, s in ipairs(S) do
    if C.isRune(s) then ok(not C.filterMatches(s, ctx, f), f .. ': no rune (' .. s.name .. ')') end
  end
end
eq(names('all', 'mend'), 'Minor Mending,Deep Mending,Grand Mending', 'search by name')
eq(names('all', ' KAH '), 'Reaping Gyre', 'search by words, trimmed, any case')
eq(names('learned', 'zzz'), '', 'no match')
eq(C.normalizeFilter('bogus'), 'learned', 'unknown filter: the default (Learned)')
eq(C.DEFAULT_FILTER, 'learned', 'default filter')

-- order: level, then name (the healing picker used to be alphabetical)
local heals = { { name = 'Rebirth of Flesh', level = 300 }, { name = 'Purifying Wellspring', level = 40 },
  { name = 'Minor Mending', level = 8 }, { name = 'Grand Mending', level = 30 }, { name = 'Deep Mending', level = 20 } }
C.sort(heals)
local order = {}
for i, s in ipairs(heals) do order[i] = s.name end
eq(table.concat(order, ','), 'Minor Mending,Deep Mending,Grand Mending,Purifying Wellspring,Rebirth of Flesh', 'by level')
ok(C.compare({ name = 'a', level = 5 }, { name = 'b', level = 5 }), 'same level: by name')

-- the filter saved per character
local node = C.saveFilter(nil, 'Alice', 'soon')
node = C.saveFilter(node, 'Bob', 'all')
eq(C.loadFilter(node, 'Alice'), 'soon', 'per character')
eq(C.loadFilter(node, 'Bob'), 'all', 'other character')
eq(C.loadFilter(node, 'Carol'), 'learned', 'new character: default')
eq(C.loadFilter(nil, 'Alice'), 'learned', 'no settings yet')
eq(C.saveFilter({}, 'X', 'nope').X, 'learned', 'an unknown key is not saved')

-- cooldown seconds
eq(C.cooldownLeft(5000, 3500), 2, 'rounded up')
eq(C.cooldownLeft(3000, 3500), nil, 'over')
eq(C.cooldownLeft(nil, 1), nil, 'none')

-- ------------------------------------------------------------- spell pickers (mocked widgets)
local function widget(props)
  local w = props or {}
  w.visible, w.opacity = true, 1
  function w:setVisible(v) self.visible = v end
  function w:isVisible() return self.visible end
  function w:setOpacity(v) self.opacity = v end
  function w:getText() return self.text or '' end
  function w:setText(t) self.text = t end
  function w:setEnabled(v) self.enabled = v end
  function w:setChecked(v)
    local was = self.checked
    self.checked = v
    if was ~= v and self.onCheckChange then self:onCheckChange(v) end
  end
  function w:isChecked() return self.checked == true end
  return w
end

local INFO = {
  ['Minor Mending'] = { level = 8 }, ['Deep Mending'] = { level = 20 }, ['Grand Mending'] = { level = 30 },
  ['Purifying Wellspring'] = { level = 40 }, ['Rebirth of Flesh'] = { level = 300 },
  ['Old Secret'] = { level = 1, needLearn = true }
}

-- one picker window as the helper / action bar / custom hotkeys build it: rows in pairs() order (here alphabetical)
local function pickerWindow(spellNames)
  local list = widget({ children = {} })
  for _, name in ipairs(spellNames) do
    local row = widget({ text = name .. '\nwords ' .. name:lower(), image = { gray = widget() } })
    row.image.gray.visible = false
    list.children[#list.children + 1] = row
  end
  function list:getChildren()
    local out = {}
    for i, c in ipairs(self.children) do out[i] = c end
    return out
  end
  function list:moveChildToIndex(c, index)
    for i, x in ipairs(self.children) do
      if x == c then table.remove(self.children, i) break end
    end
    table.insert(self.children, index, c)
  end
  local win = { ids = { spellList = list, tick = widget({ checked = true, enabled = false }), searchText = widget(),
    preview = widget() } }
  function win:recursiveGetChildById(id) return self.ids[id] end
  return win, list
end

local function shown(list)
  local out = {}
  for _, c in ipairs(list.children) do
    if c.visible then out[#out + 1] = c.text:match('^(.-)\n') end
  end
  return table.concat(out, ',')
end

local player = { getLevel = function() return 25 end, getMagicLevel = function() return 10 end }
local store = {}
local env = {
  tr = function(s) return s end,
  getSetting = function(k) return store[k] end,
  setSetting = function(k, v) store[k] = v end
}
local alphabetical = { 'Deep Mending', 'Grand Mending', 'Minor Mending', 'Old Secret', 'Purifying Wellspring',
  'Rebirth of Flesh' }

-- every picker the base patch hooks (Assign Healing / Attack Spell, Select Attack Spell, Training / Haste / Cure
-- Paralyze, the action bar, the custom hotkeys) gets the same behaviour from setupPicker
local PICKERS = { 'helper assignSpell (healing)', 'helper assignSpell (attack)', 'helper assignSpellForMagicShooter',
  'helper assignTrainingSpell', 'actionbar assignSpell', 'custom hotkeys assignSpell' }
for _, picker in ipairs(PICKERS) do
  store = {}
  local win, list = pickerWindow(alphabetical)
  local refilter = C.setupPicker(win, player, INFO, env)
  ok(refilter, picker .. ': set up')
  eq(shown(list), 'Old Secret,Minor Mending,Deep Mending,Grand Mending,Purifying Wellspring,Rebirth of Flesh',
    picker .. ': level order, all shown (the box starts unchecked)')
  eq(list.children[4].opacity, 0.5, picker .. ': above the level dimmed (Grand Mending, 30 > 25)')
  ok(list.children[4].image.gray.visible, picker .. ': icon dithered')
  eq(list.children[2].opacity, 1, picker .. ': castable not dimmed')
  eq(list.children[1].opacity, 0.5, picker .. ': not learned dimmed')
  local tick = win.ids.tick
  eq(tick.enabled, true, picker .. ': the box is usable (it was forced on and disabled)')
  eq(tick.text, 'Only show learned spells', picker .. ': box text')
  -- toggling the box changes the list
  tick:setChecked(true)
  eq(shown(list), 'Minor Mending,Deep Mending', picker .. ': learned only')
  eq(store[C.PICKER_SETTING], true, picker .. ': remembered')
  tick:setChecked(false)
  eq(shown(list), 'Old Secret,Minor Mending,Deep Mending,Grand Mending,Purifying Wellspring,Rebirth of Flesh',
    picker .. ': all again')
  -- search and the box together
  tick:setChecked(true)
  win.ids.searchText.text = 'deep'
  win.ids.searchText.onTextChange()
  eq(shown(list), 'Deep Mending', picker .. ': search inside the learned ones')
  win.ids.searchText.text = 'grand'
  win.ids.searchText.onTextChange()
  eq(shown(list), '', picker .. ': search does not bring back an unlearned spell')
  eq(win.ids.preview.text, 'Select a spell from the list.', picker .. ': the empty preview says what to do')
end
-- a rune entry in a spell picker stays out (rune slots use the item picker); env.runes keeps it
INFO['Faint Dart Rune'] = { level = 1, type = 'Rune' }
local rwin, rlist = pickerWindow({ 'Deep Mending', 'Faint Dart Rune', 'Minor Mending' })
C.setupPicker(rwin, player, INFO, env)
eq(shown(rlist), 'Minor Mending,Deep Mending', 'picker: no rune row')
rwin, rlist = pickerWindow({ 'Deep Mending', 'Faint Dart Rune', 'Minor Mending' })
C.setupPicker(rwin, player, INFO, { tr = env.tr, getSetting = env.getSetting, setSetting = env.setSetting, runes = true })
eq(shown(rlist), 'Faint Dart Rune,Minor Mending,Deep Mending', 'picker for runes keeps them')
INFO['Faint Dart Rune'] = nil

-- the saved choice comes back on the next picker; a learned needlearn spell counts as learned
store = { [C.PICKER_SETTING] = true }
C.setLearned({ 'Old Secret' })
local win, list = pickerWindow(alphabetical)
C.setupPicker(win, player, INFO, env)
eq(shown(list), 'Old Secret,Minor Mending,Deep Mending', 'saved box state and the learned list')
C.setLearned({})

-- the base patch calls setupPicker in every picker (and no picker keeps its alphabetical sort)
local root = here .. '../../../../'
local f = io.open(root .. 'client/base-patches/0057-spell-pickers-order-learned.patch', 'r')
ok(f, 'base patch 0057 is there')
local patch = f:read('*a')
f:close()
local function count(s, pattern)
  local c = 0
  for _ in s:gmatch(pattern) do c = c + 1 end
  return c
end
eq(count(patch, '\n%+[^\n]*ChaosSpellCore%.setupPicker%('), 5, 'five picker functions call setupPicker')
for _, fn in ipairs({ 'function assignTrainingSpell', 'function assignSpell%(button, groupName',
  'function assignSpellForMagicShooter', 'function assignSpell%(button, multiSlotIn', 'function CustomHotkeys%.assignSpell' }) do
  ok(patch:find(fn), 'patch reaches ' .. fn)
end
for _, file in ipairs({ 'mods/game_helper/helper.lua', 'modules/game_actionbar/actionbar.lua',
  'mods/client_settings/classes/custom%-hotkeys.lua' }) do
  ok(patch:find('%+%+%+ b/' .. file), 'patch edits ' .. file)
end

-- attack / support kind and the AoE mark
local function sp(t) return t end
eq(C.kindOf(sp({ type = 'damage' })), 'attack', 'damage is attack')
eq(C.kindOf(sp({ type = 'heal' })), 'support', 'heal is support')
eq(C.kindOf(sp({ type = 'buff' })), 'support', 'buff is support')
eq(C.kindOf(sp({ type = 'summon', group = 'attack' })), 'support', 'type beats group')
eq(C.kindOf(sp({ group = 'attack' })), 'attack', 'no type: attack group')
eq(C.kindOf(sp({ group = 1 })), 'attack', 'no type: numeric attack group')
eq(C.kindOf(sp({ group = 'healing' })), 'support', 'no type: healing group is support')
eq(C.kindOf(sp({ group = 3 })), 'support', 'no type: support group')
local ring = { { 0, 1, 0 }, { 1, 2, 1 }, { 0, 1, 0 } }
eq(C.hitCells(ring), 4, 'centre only (2) is not a hit')
eq(C.hitCells({ { 3 } }), 1, 'centre and hit counts')
eq(C.hitCells(nil), 0, 'no area')
ok(C.isAoE({ type = 'damage', target = 'area', area = ring }), 'area spell')
ok(C.isAoE({ type = 'damage', target = 'front', area = { { 1, 1, 1 } } }), 'wave')
ok(C.isAoE({ type = 'damage', target = 'area' }), 'area target without a matrix')
ok(not C.isAoE({ type = 'damage', target = 'single', range = 5 }), 'single target')
ok(not C.isAoE({ type = 'damage', target = 'area', area = { { 3 } } }), 'one tile only')
ok(not C.isAoE({ type = 'buff', target = 'area', area = ring }), 'support area is not AoE')
ok(not C.isAoE({ type = 'damage', target = 'self' }), 'self')
eq(C.normalizeKind('attack'), 'attack', 'kind kept')
eq(C.normalizeKind('bogus'), 'all', 'bad kind -> all')
local mix = {
  { name = 'Bolt', level = 1, vocations = { 1 }, type = 'damage', target = 'single' },
  { name = 'Nova', level = 1, vocations = { 1 }, type = 'damage', target = 'area', area = ring },
  { name = 'Mend', level = 1, vocations = { 1 }, type = 'heal', target = 'self' },
  { name = 'Ward', level = 1, vocations = { 1 }, type = 'buff', target = 'self' }
}
local kctx = { vocation = 1, level = 10, magicLevel = 0, learned = {} }
eq(#C.visibleIndexes(mix, kctx, 'learned', '', 'all'), 4, 'all types')
eq(#C.visibleIndexes(mix, kctx, 'learned', '', nil), 4, 'no kind = all')
eq(table.concat(C.visibleIndexes(mix, kctx, 'learned', '', 'attack'), ','), '1,2', 'attack only')
eq(table.concat(C.visibleIndexes(mix, kctx, 'learned', '', 'support'), ','), '3,4', 'support only')
eq(table.concat(C.visibleIndexes(mix, kctx, 'learned', 'nov', 'attack'), ','), '2', 'kind and text together')
eq(#C.visibleIndexes(mix, kctx, 'learned', 'mend', 'attack'), 0, 'kind excludes text match')

-- the pickers (helper shooter, healing, action bar) list what the Spellbook's "Learned" filter lists: the same vocation rule
do
  local vinfo = {
    ['Own Bolt'] = { level = 1, vocations = { 1 } }, ['Other Bolt'] = { level = 1, vocations = { 4 } },
    ['Asc Bolt'] = { level = 1, vocations = { 10 } }, ['Any Light'] = { level = 1, vocations = {} }
  }
  local names = { 'Any Light', 'Asc Bolt', 'Other Bolt', 'Own Bolt' }
  local vplayer = { getLevel = function() return 25 end, getMagicLevel = function() return 10 end,
    getVocation = function() return 1 end }
  local vwin, vlist = pickerWindow(names)
  C.setupPicker(vwin, vplayer, vinfo, env)
  vwin.ids.tick:setChecked(true)
  local spellbook = {}
  local sctx = { vocation = 1, level = 25, magicLevel = 10, learned = {} }
  for _, name in ipairs(names) do
    local sp = { name = name, words = '', level = 1, vocations = vinfo[name].vocations }
    if C.filterMatches(sp, sctx, 'learned') then spellbook[#spellbook + 1] = name end
  end
  table.sort(spellbook)
  local picked = {}
  for _, c in ipairs(vlist.children) do
    if c.visible then picked[#picked + 1] = c.text:match('^(.-)\n') end
  end
  table.sort(picked)
  eq(table.concat(picked, ','), table.concat(spellbook, ','), 'picker learned-only list equals the Spellbook learned list')
  eq(table.concat(picked, ','), 'Any Light,Own Bolt', 'other vocations stay out of the picker')
  -- a client that folds ascension ids into the base class (translateVocation) still keeps the ascension spell
  local fwin, flist = pickerWindow(names)
  C.setupPicker(fwin, vplayer, vinfo, { tr = env.tr, getSetting = env.getSetting, setSetting = env.setSetting,
    translate = function(v) return v == 10 and 1 or v end })
  fwin.ids.tick:setChecked(true)
  eq(shown(flist), 'Any Light,Own Bolt', 'folding never widens the list on its own')
end

-- the line spell quest spells: not learned = locked ('quest'), with the quest number and the level Archivist Odrenna opens it at
do
  C.setLearned({})
  C.questByName = nil
  local qs = {
    { name = 'Keepfall', words = 'q1', level = 500, vocations = { 4, 8, 14 }, needLearn = true },
    { name = 'Ironbound Oath', words = 'q2', level = 800, vocations = { 4, 8, 14 }, needLearn = true },
    { name = 'Judgment of Iron', words = 'q3', level = 1200, vocations = { 4, 8, 14 }, needLearn = true },
    { name = 'Old Secret', words = 'g', level = 5, vocations = { 4 }, needLearn = true },
    { name = 'Row Quest', words = 'r', level = 800, vocations = { 4 }, needLearn = true, quest = 2 }
  }
  local data = { { name = 'Keepfall', quest = 1 }, { name = 'Ironbound Oath', quest = 2 }, { name = 'Judgment of Iron', quest = 3 },
    { name = 'Old Secret' } }
  eq(C.questOf(qs[1]), nil, 'no spell data loaded yet: not a quest spell, asked again later')
  eq(C.questByName, nil, 'and nothing cached')
  C.setQuestSpells(data)
  eq(C.QUEST_NPC, 'Archivist Odrenna', 'the NPC')
  eq(C.questOf(qs[1]), 1, 'Keepfall is quest 1'); eq(C.questOf(qs[2]), 2, 'Ironbound Oath is quest 2')
  eq(C.questOf(qs[3]), 3, 'Judgment of Iron is quest 3'); eq(C.questOf(qs[4]), nil, 'a plain needlearn spell is no quest spell')
  eq(C.questOf(qs[5]), 2, 'a row may carry its quest itself')
  eq(C.questLevel(qs[1]), 500, 'quest 1 opens at 500'); eq(C.questLevel(qs[2]), 800, 'quest 2 at 800')
  eq(C.questLevel(qs[3]), 1200, 'quest 3 at 1200'); eq(C.questLevel(qs[4]), nil, 'no level for a plain spell')
  eq(C.questOf(nil), nil, 'nil spell')
  local qctx = { vocation = 4, level = 900, magicLevel = 0, learned = {} }
  eq(C.status(qs[1], qctx), 'quest', 'not learned: locked')
  eq(C.status(qs[3], qctx), 'quest', 'locked even below the level (the hint names the level)')
  eq(C.status(qs[4], qctx), 'learn', 'a plain needlearn spell is still just "learn"')
  eq(C.status(qs[1], { vocation = 11, level = 900, learned = {} }), 'vocation', 'another line: not its spell')
  eq(C.status(qs[1], { vocation = 4, level = 900, learned = { keepfall = true } }), 'ready', 'learned: castable')
  eq(C.status(qs[2], { vocation = 4, level = 300, learned = { ['ironbound oath'] = true } }), 'level', 'learned but the level was lowered')
  eq(C.filterMatches(qs[1], qctx, 'learned'), false, 'locked is not in Learned')
  eq(C.filterMatches(qs[3], { vocation = 4, level = 10, learned = {} }, 'soon'), true, 'locked quest spells are always in Available soon')
  eq(C.filterMatches({ name = 'Far Secret', level = 50, vocations = { 4 }, needLearn = true }, { vocation = 4, level = 10, learned = {} }, 'soon'), false, 'a far plain spell is not')
  eq(C.filterMatches(qs[1], { vocation = 11, level = 10, learned = {} }, 'soon'), false, 'another line stays out of soon')
  eq(C.filterMatches(qs[3], qctx, 'vocation'), true, 'locked is in My vocation'); eq(C.filterMatches(qs[3], qctx, 'all'), true, 'and in All')
  eq(C.kindOf({ name = 'Ironbound Oath', group = 3 }), 'support', 'the buff is a support spell')
  -- a server that is slow to learn: the learned reply unlocks it
  C.setLearned({ 'Keepfall' })
  eq(C.status(qs[1], { vocation = 4, level = 900 }), 'ready', 'the shared learned list unlocks it')
  C.setLearned({})
  -- the real data: every quest spell of the client has a number 1..3 and a level of the quest
  C.questByName = nil
  dofile(here .. '../game_chaosspells/spelldata.lua')
  local count = { 0, 0, 0 }
  for _, s in ipairs(ChaosSpellData) do
    local q = C.questOf(s)
    if q then
      count[q] = count[q] + 1
      eq(s.level, C.QUEST_LEVELS[q], s.name .. ': the spell level is the quest level')
    end
  end
  eq(count[1] .. '/' .. count[2] .. '/' .. count[3], '7/7/7', 'seven quest spells per quest in the spell data')
  C.questByName = nil
end

print('spellbook_core_test: ' .. n .. ' checks ok')
