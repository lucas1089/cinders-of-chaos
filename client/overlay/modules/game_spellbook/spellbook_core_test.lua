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
  { name = 'Faint Hexdart Rune', words = 'b', level = 1, vocations = { 1, 5 } },
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
eq(names('learned'), 'Faint Hexdart Rune,Light,Minor Mending', 'learned: castable now, by level then name')
eq(names('soon'), 'Ember Lash,Old Secret,Bog Splatter', 'soon: own vocation, not castable, within 10 levels')
eq(names('vocation'), 'Ember Lash,Faint Hexdart Rune,Old Secret,Light,Minor Mending,Bog Splatter,Deep Mending',
  'vocation: every spell of the class')
eq(#C.visibleIndexes(S, ctx, 'all', ''), #S, 'all')
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

print('spellbook_core_test: ' .. n .. ' checks ok')
