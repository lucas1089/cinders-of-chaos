-- luajit chaosdock_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
dofile(here .. 'chaosdocklogic.lua')
dofile(here .. 'chaosdockcolumn.lua')
dofile(here .. '../client_chaos_topbar/topbar_tree.lua')
local L = ChaosDockLogic
local COL = ChaosDockColumn
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- the five tabs of the owner's pick, in order, with the glyphs of the hub atlas
local ids = {}
for _, t in ipairs(L.TABS) do ids[#ids + 1] = t.id end
eq(table.concat(ids, ','), 'equip,quests,attributes,spells,shop', 'tabs')
local glyphFile = io.open(here .. '../client_chaos_topbar/topbar_glyph_index.lua')
local glyphs = glyphFile:read('*a')
glyphFile:close()
for _, t in ipairs(L.TABS) do
  eq(glyphs:find(t.glyph .. ' = {', 1, true) ~= nil, true, 'glyph in the atlas: ' .. t.glyph)
end

-- every window of a tab is a card of the hub menu (the dock takes the entry the card runs)
local cards = {}
for _, hub in ipairs(ChaosTopBarTree.HUBS) do
  for _, tab in ipairs(hub.tabs) do
    for _, c in ipairs(tab.cards) do cards[c] = true end
  end
end
for _, t in ipairs(L.TABS) do
  for _, w in ipairs(t.windows) do eq(cards[w.entry] or ChaosTopBarTree.PIN_ONLY[w.entry], true, 'card: ' .. w.entry) end
end

-- tab of an entry
local t, i = L.tabOf('Spell Supports')
eq(t.id, 'spells', 'tabOf tab'); eq(i, 2, 'tabOf index')
eq(L.tabOf('Bestiary'), nil, 'tabOf: not a dock window')
eq(select(2, L.tabOf('Store')), 2, 'store is the second window of Shop')

-- settings: on unless turned off, the last tab and windows come back, bad values are dropped
local function reader(values) return function(key) return values[key] end end
local st = L.newState(reader({}))
eq(st.enabled, true, 'on by default'); eq(st.tab, 'equip', 'first tab by default'); eq(st.open, false, 'closed at start')
eq(L.newState(reader({ [L.SETTING_ENABLED] = 'false' })).enabled, false, 'turned off (string)')
eq(L.newState(reader({ [L.SETTING_ENABLED] = false })).enabled, false, 'turned off (boolean)')
eq(L.newState(reader({ [L.SETTING_ENABLED] = 'true' })).enabled, true, 'turned on')
eq(L.newState(reader({ [L.SETTING_TAB] = 'nope' })).tab, 'equip', 'unknown tab')
local back = L.newState(reader({ [L.SETTING_TAB] = 'quests', [L.SETTING_SUBS] = 'quests=3,spells=9,bogus=1,shop=2' }))
eq(back.tab, 'quests', 'remembered tab'); eq(L.subOf(back, 'quests'), 3, 'remembered window')
eq(L.subOf(back, 'spells'), 1, 'index past the tab dropped'); eq(L.subOf(back, 'shop'), 2, 'shop window kept')
eq(L.formatSubs(back.subs), 'quests=3,shop=2', 'subs written in tab order')
eq(L.formatSubs({}), '', 'no subs')

-- hub routing: an entry of a tab opens the dock there, a second press closes it, another entry is not the dock's
st = L.newState(reader({}))
eq(L.route(st, 'Bestiary'), nil, 'not a dock entry')
local a = L.route(st, 'Market')
eq(a.open, 'shop', 'market opens Shop'); eq(a.sub, 1, 'market window')
local writes = L.apply(st, a)
eq(st.open, true, 'open'); eq(st.tab, 'shop', 'tab shown')
eq(writes[L.SETTING_TAB], 'shop', 'tab saved'); eq(writes[L.SETTING_SUBS], 'shop=1', 'window saved')
eq(writes[L.SETTING_OPEN], 'true', 'open saved')
eq(L.route(st, 'Market').close, true, 'same entry again closes')
a = L.route(st, 'Store')
eq(a.open, 'shop', 'other window of the tab'); eq(a.sub, 2, 'store window')
L.apply(st, a)
eq(L.route(st, 'Skills').open, 'attributes', 'another tab while open')
eq(L.apply(st, { close = true })[L.SETTING_OPEN], 'false', 'close saves the closed state')
eq(st.open, false, 'closed'); eq(st.tab, 'shop', 'tab kept after close'); eq(L.subOf(st, 'shop'), 2, 'window kept')
eq(L.route(st, 'Store').open, 'shop', 'closed: the entry opens again')
local off = L.newState(reader({ [L.SETTING_ENABLED] = 'false' }))
eq(L.route(off, 'Market'), nil, 'dock off: the window floats as before')
eq(L.toggle(off), nil, 'dock off: no toggle')
eq(L.pickTab(off, 'equip', true), nil, 'dock off: no tab key')

-- the dock's key opens the last tab and window, then closes
st = L.newState(reader({ [L.SETTING_TAB] = 'spells', [L.SETTING_SUBS] = 'spells=2' }))
a = L.toggle(st)
eq(a.open, 'spells', 'toggle: last tab'); eq(a.sub, 2, 'toggle: last window')
L.apply(st, a)
eq(L.toggle(st).close, true, 'toggle closes')

-- tab keys and clicks
a = L.pickTab(st, 'quests', true)
eq(a.open, 'quests', 'tab key opens its tab'); eq(a.sub, 1, 'first window by default')
L.apply(st, a)
eq(L.pickTab(st, 'quests', true).close, true, 'key of the tab shown closes')
eq(L.pickTab(st, 'quests', false).open, 'quests', 'a click on the tab shown keeps it')
eq(L.pickTab(st, 'nope', false), nil, 'unknown tab')
a = L.pickSub(st, 2)
eq(a.open, 'quests', 'sub keeps the tab'); eq(a.sub, 2, 'sub index')
eq(L.pickSub(st, 4), nil, 'sub past the tab'); eq(L.pickSub(st, 0), nil, 'sub 0')
L.apply(st, a)
eq(L.pickTab(st, 'quests', false).sub, 2, 'tab remembers its window')

-- per character (O755): the character's keys first, the plain ones of before as the fallback, the open state
eq(L.charKey(L.SETTING_TAB, 'Ash Walker'), 'chaosDockTab_Ash_Walker', 'key of a character')
eq(L.charKey(L.SETTING_TAB, nil), 'chaosDockTab', 'no character: the plain key')
local mine = L.newState(reader({ [L.SETTING_TAB] = 'shop', chaosDockTab_Ash = 'quests', chaosDockSubs_Ash = 'quests=2',
  chaosDockOpen_Ash = 'true' }), 'Ash')
eq(mine.tab, 'quests', 'the character\'s tab'); eq(L.subOf(mine, 'quests'), 2, 'the character\'s window')
eq(mine.wasOpen, true, 'was open at the logout'); eq(mine.open, false, 'not open before the dock opens it')
local other = L.newState(reader({ [L.SETTING_TAB] = 'shop', chaosDockOpen_Ash = 'true' }), 'Bryn')
eq(other.tab, 'shop', 'another character: the plain key'); eq(other.wasOpen, false, 'another character: closed')
eq(L.newState(reader({ chaosDockOpen_Ash = 'false' }), 'Ash').wasOpen, false, 'closed at the logout')

-- one column (O755): the dock is the right panel column wide whatever it holds, never wider
eq(L.width({ x = 1102, y = 0, width = 178, height = 720 }, 1280, false, 1280), 178, 'the column')
eq(L.width({ x = 1010, y = 0, width = 270, height = 720 }, 1280, false, 1280), 270, 'a wider column (a panel made wider)')
eq(L.width(nil, 1280, false, 1280), L.WIDTH, 'no column: the Inventory panel\'s width')
eq(L.width({ x = 1270, y = 0, width = 10, height = 720 }, 1280, false, 1280), L.WIDTH, 'a closed panel is no column')
eq(L.width({ x = 1102, width = 178 }, 1280, true, 1170), 1170, 'phone sheet')
eq(L.WIDTH, 178, 'the fallback is a side panel\'s width (the Inventory panel\'s before O755)')
eq(L.mapMargin({ x = 1102, y = 0, width = 178, height = 180 }, 0), 182, 'under the minimap')
eq(L.mapMargin(nil, 0), 0, 'no minimap: from the top')
eq(L.share(5, 170), 32, 'five tabs in a column'); eq(L.share(L.SUB_COLS, 170), 84, 'two sub tabs a row')
eq(L.share(1, 170), 170, 'one'); eq(L.share(5, 0), 0, 'no room')
eq(L.subRows(3), 2, 'three windows: two rows'); eq(L.subRows(2), 1, 'two: one row'); eq(L.subRows(1), 0, 'one: none')
eq(L.subsHeight(3), 2 * L.SUB_H + L.TAB_GAP, 'two rows high'); eq(L.subsHeight(1), 0, 'no row')
eq(L.hidesInColumn('minimapWindow'), false, 'the minimap stays'); eq(L.hidesInColumn('bagPanelWindow'), true, 'the bag panel hides')
eq(L.hidesInColumn('battleWindow'), true, 'any other window hides')
eq(L.hidesInColumn('skillWindow', { skillWindow = true }), false, 'a window the dock holds stays')
eq(L.fitOf(L.TABS[5].windows[1]), 'float', 'Market floats'); eq(L.fitOf(L.TABS[5].windows[2]), 'float', 'Store floats')
eq(L.fitOf(L.TABS[2].windows[1]), 'column', 'Quest Log in the column'); eq(L.fitOf(L.TABS[5].windows[1], true), 'sheet', 'phone')
eq(L.heightIn(COL.layout('Quest Log'), 537), 780, 'stacked Quest Log height'); eq(L.heightIn(nil, 487), 487, 'own height')
eq(L.TABS[1].windows[1].hidden, true, 'the Inventory panel is taken while hidden')

-- a bag click opens the Inventory tab: not while the login restores, not in its first seconds, not when shown already
st = L.newState(reader({}))
eq(L.bagOpensDock(st, false, false, 9000), true, 'a click opens it')
eq(L.bagOpensDock(st, true, false, 9000), false, 'login restore')
eq(L.bagOpensDock(st, false, true, 9000), false, 'pinned reopen')
eq(L.bagOpensDock(st, false, false, 1000), false, 'login grace')
L.apply(st, { open = 'equip', sub = 1 })
eq(L.bagOpensDock(st, false, false, 9000), false, 'already shown')
eq(L.bagOpensDock(off, false, false, 9000), false, 'dock off')

-- every window of the column: a sound layout, its ids in its .otui, no float window has one
local entries = {}
for _, t in ipairs(L.TABS) do for _, w in ipairs(t.windows) do entries[w.entry] = w end end
local layouts = 0
for entry, layout in pairs(COL.LAYOUTS) do
  layouts = layouts + 1
  eq(entries[entry] ~= nil, true, 'layout of a dock window: ' .. entry)
  eq(L.fitOf(entries[entry]), 'column', 'a float window has no column layout: ' .. entry)
  eq(table.concat(COL.faults(layout), '; '), '', 'layout sound: ' .. entry)
  if layout.otui then
    local f = io.open(here .. '../' .. layout.otui)
    eq(f ~= nil, true, 'otui of ' .. entry)
    local text = f:read('*a')
    f:close()
    for _, rule in ipairs(layout.rules) do
      eq(text:find('id: ' .. rule.id .. '\n', 1, true) ~= nil, true, entry .. ' has ' .. rule.id)
      for _, edge in ipairs(COL.EDGES) do
        for _, side in ipairs({ rule.col, rule.home or {} }) do
          local id = COL.target(side[edge])
          if id and id ~= 'parent' then eq(text:find('id: ' .. id .. '\n', 1, true) ~= nil, true, entry .. ' target ' .. id) end
        end
      end
    end
  end
end
eq(layouts, 5, 'five stacked windows')
eq(#COL.faults({ rules = { { id = 'a', col = { right = 'parent.right' } } } }), 1, 'an anchor not put back is a fault')
eq(#COL.faults({ rules = { { id = 'a', col = { wide = 1 } } } }), 1, 'an unknown key is a fault')
eq(#COL.faults({ rules = { { id = 'a', col = { top = 'b.middle' }, home = { top = false } } } }), 1, 'a bad edge is a fault')
eq(#COL.faults({ rules = { { id = 'a', col = { height = 4 }, home = { height = 2 } } } }), 1, 'home sets anchors only')
eq(#COL.faults({ rules = { { id = 'a', col = { wrap = 1 } } } }), 1, 'wrap is a boolean')
eq(#COL.faults({ rules = { { id = 'a', col = { width = 9 }, autoResize = true } } }), 1, 'autoResize needs wrap')
eq(#COL.faults({ rules = { { id = 'a', col = { wrap = true }, autoResize = true } } }), 0, 'a wrapped label')

-- no part of a column window is wider than the column (O760): a fixed width over 154 px needs both sides anchored in
-- the column (by its .otui or its layout), a narrower width or no show there
local function readFile(path)
  local f = io.open(path)
  eq(f ~= nil, true, 'file ' .. path)
  local text = f:read('*a')
  f:close()
  return text
end
local hosted = { Inventory = 'game_bagpanel/bagpanel.otui' }
for entry, layout in pairs(COL.LAYOUTS) do
  if layout.otui then hosted[entry] = layout.otui end
end
local seen = 0
for entry, file in pairs(hosted) do
  seen = seen + 1
  local wide = COL.wideParts(readFile(here .. '../' .. file), COL.layout(entry))
  eq(table.concat(wide, '; '), '', 'nothing wider than the column: ' .. entry)
end
eq(seen, 5, 'every column window with an .otui here (the Quest Log is a base module)')
local sample = table.concat({
  'Row < UIWidget', '  width: 300', '  $mobile:', '    width: 900',
  'ChaosMainWindow', '  size: 760 500', '  @onSetup: |', '    self:x()', '    width: 999',
  '  UILabel', '    id: wideOne', '    anchors.left: parent.left', '    width: 200',
  '  UILabel', '    id: both', '    anchors.left: parent.left', '    anchors.right: parent.right', '    width: 400',
  '  Panel', '    id: frame', '    anchors.left: parent.left', '    size: 230 40',
  '    UIWidget', '      id: inner', '      anchors.fill: parent', '      width: 500',
  '  UILabel', '    id: hid', '    width: 300',
  '  UILabel', '    id: narrow', '    width: 300',
  '  UILabel', '    id: small', '    width: 154',
}, '\n')
local probe = { rules = {
  { id = 'frame', col = { right = 'parent.right' }, home = { right = false } },
  { id = 'hid', col = { visible = false } },
  { id = 'narrow', col = { width = 130, wrap = true } },
} }
eq(table.concat(COL.wideParts(sample, probe), '; '), '? (line 1): width 300; wideOne (line 10): width 200',
  'a style and a widget wider than the column')
eq(#COL.wideParts(sample, { rules = {} }), 5, 'without the layout: frame, hid and narrow too')
eq(#COL.otuiWidgets(sample), 9, 'widgets of the sample')
eq(COL.COLUMN, 154, 'the column with the scroll bar')

eq(COL.target('parent.right'), 'parent', 'target id'); eq(select(2, COL.target('stats.bottom')), 'bottom', 'target edge')

-- the dock stops above the hotbar only when the two meet
eq(L.bottomMargin(950, nil, 720), 0, 'no hotbar')
eq(L.bottomMargin(950, { x = 450, y = 660, width = 380, height = 60 }, 720), 0, 'hotbar left of the dock')
eq(L.bottomMargin(950, { x = 540, y = 660, width = 380, height = 60 }, 720), 66, 'globes reach the dock')
eq(L.bottomMargin(1102, { x = 900, y = 660, width = 380, height = 60 }, 720), 66, 'a hotbar under the column')
eq(L.topMargin(950, nil, 0), 0, 'no menu bar')
eq(L.topMargin(950, { x = 458, y = 2, width = 364, height = 36 }, 0), 0, 'menu bar left of the dock')
eq(L.topMargin(800, { x = 458, y = 2, width = 364, height = 36 }, 0), 44, 'under the menu bar: starts below it')
eq(L.topMargin(822, { x = 458, y = 2, width = 364, height = 36 }, 0), 0, 'touching edges do not overlap')

-- slide: from hidden to in place, eased
local s = L.slide(330, 6)
eq(#s, 6, 'steps'); eq(s[6], 0, 'ends in place')
for k = 2, #s do eq(s[k] >= s[k - 1], true, 'slides one way ' .. k) end
eq(s[1] < 0, true, 'starts out of view')

-- the window an entry opened: the first one that was not there before
local x, y, z = { id = 'x' }, { id = 'y' }, { id = 'z' }
local byId = function(p, q) return p.id == q.id end
eq(L.pickNew({ x, y }, { { id = 'y' }, z, { id = 'x' } }, byId), z, 'new window')
eq(L.pickNew({ x }, { { id = 'x' } }, byId), nil, 'nothing new')
eq(L.pickNew({}, { x }), x, 'default compare')

-- keys: Alt+D and the three tab keys, minus keys in use
local keys = L.hotkeys()
local list = {}
for _, k in ipairs(keys) do list[#list + 1] = k.key .. '=' .. (k.tab or 'dock') end
eq(table.concat(list, ','), 'Alt+D=dock,Alt+I=equip,Alt+Q=quests,Alt+A=attributes', 'keys')
eq(#L.hotkeys({ ['Alt+D'] = true, ['Alt+Q'] = true }), 2, 'used keys skipped')
-- none of them is a key of the menu entries
local menu = io.open(here .. '../client_chaos_topbar/chaos_topbar.lua'):read('*a')
for _, k in ipairs(keys) do eq(menu:find("key = '" .. k.key .. "'", 1, true), nil, 'free key ' .. k.key) end

-- a shared window (Character Info is one page of the Info window) goes back when another page opens
local held = { { spec = L.TABS[3].windows[2] } }
eq(L.releaseForOther(held, 'Rifts'), true, 'shared window released for another page')
eq(L.releaseForOther(held, 'Skills'), false, 'a dock entry keeps it')
eq(L.releaseForOther({ { spec = L.TABS[1].windows[1] } }, 'Rifts'), false, 'not shared')

-- every text the dock shows through tr() has its pt-BR
local pt = io.open(here .. '../client_chaos_locale/pt_br.lua'):read('*a')
for _, text in ipairs(L.texts()) do eq(pt:find('["' .. text .. '"] =', 1, true) ~= nil, true, 'pt-BR: ' .. text) end

-- a docked hook names a global function of its module (the Inventory panel hides its title bar and tab row in the dock)
local hooks = 0
for _, t in ipairs(L.TABS) do
  for _, spec in ipairs(t.windows) do
    if spec.docked then
      hooks = hooks + 1
      local dir = here .. '../' .. spec.module .. '/'
      local found = false
      for _, f in ipairs({ dir .. spec.module:gsub('^game_', '') .. '.lua' }) do
        local h = io.open(f)
        if h then found = h:read('*a'):find('\nfunction ' .. spec.docked .. '%(') ~= nil h:close() end
      end
      eq(found, true, 'docked hook ' .. spec.module .. '.' .. spec.docked)
    end
  end
end
eq(hooks, 1, 'the Inventory panel has the docked hook')

print('chaosdock_test: ' .. n .. ' checks OK')
