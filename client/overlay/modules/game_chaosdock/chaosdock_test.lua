-- luajit chaosdock_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
dofile(here .. 'chaosdocklogic.lua')
dofile(here .. '../client_chaos_topbar/topbar_tree.lua')
local L = ChaosDockLogic
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
eq(L.route(st, 'Market').close, true, 'same entry again closes')
a = L.route(st, 'Store')
eq(a.open, 'shop', 'other window of the tab'); eq(a.sub, 2, 'store window')
L.apply(st, a)
eq(L.route(st, 'Skills').open, 'attributes', 'another tab while open')
eq(L.apply(st, { close = true }), nil, 'close writes nothing')
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

-- width: 330 for a narrow window, wider for a wide one, beside the dock past the screen less 320 px, phone sheet
local w, float = L.width(nil, 1280, false)
eq(w, 330, 'no window'); eq(float, false, 'no window float')
eq((L.width(230, 1280, false)), 330, 'narrow window')
eq((L.width(306, 1280, false)), 330, 'exactly fits')
w, float = L.width(640, 1280, false)
eq(w, 664, 'spellbook widens the dock'); eq(float, false, 'spellbook docked')
w, float = L.width(900, 1280, false)
eq(w, 924, 'market'); eq(float, false, 'market docked at 1280')
w, float = L.width(960, 1280, false)
eq(w, 330, 'too wide: dock keeps its width'); eq(float, true, 'too wide floats')
w, float = L.width(960, 1920, false)
eq(w, 984, 'wide screen'); eq(float, false, 'wide screen docked')
w, float = L.width(900, 1170, true)
eq(w, 1170, 'phone sheet'); eq(float, false, 'phone never floats')

-- the dock stops above the hotbar only when the two meet
eq(L.bottomMargin(950, nil, 720), 0, 'no hotbar')
eq(L.bottomMargin(950, { x = 450, y = 660, width = 380, height = 60 }, 720), 0, 'hotbar left of the dock')
eq(L.bottomMargin(950, { x = 540, y = 660, width = 380, height = 60 }, 720), 66, 'globes reach the dock')
eq(L.bottomMargin(356, { x = 450, y = 660, width = 380, height = 60 }, 720), 66, 'wide dock over the hotbar')

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

print('chaosdock_test: ' .. n .. ' checks OK')
