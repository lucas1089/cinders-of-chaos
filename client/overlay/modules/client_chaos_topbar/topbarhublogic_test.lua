-- luajit topbarhublogic_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
dofile(here .. 'topbar_tree.lua')
dofile(here .. 'topbar_cards.lua')
dofile(here .. 'topbarhublogic.lua')
local T, C, H = ChaosTopBarTree, ChaosTopBarCards, ChaosTopBarHubLogic
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

local function item(text, extra)
  local it = { text = text, category = 'hunt', icon = 'help', status = 'open' }
  for k, v in pairs(extra or {}) do it[k] = v end
  return it
end
local function cardTexts(tab)
  local out = {}
  for _, c in ipairs(tab.cards) do out[#out + 1] = c.text end
  return table.concat(out, '|')
end

-- ---------------------------------------------------------------- the tree itself
eq(#T.HUBS, 6, 'six hubs')
local names = {}
for _, hub in ipairs(T.HUBS) do names[#names + 1] = hub.id end
eq(table.concat(names, ','), 'hero,hunt,adventure,trade,social,system', 'the hubs in bar order')
local tabs, cards, seen = 0, 0, {}
for _, hub in ipairs(T.HUBS) do
  for ti, tab in ipairs(hub.tabs) do
    tabs = tabs + 1
    eq(#tab.cards >= 1 and #tab.cards <= 6, true, hub.id .. '/' .. tab.id .. ' holds 1 to 6 cards (two rows of four fit)')
    local glyphs = {}
    for _, text in ipairs(tab.cards) do
      cards = cards + 1
      eq(seen[text], nil, 'no card twice: ' .. text)
      seen[text] = true
      local def = C.CARDS[text]
      eq(def ~= nil, true, 'a glyph and line for ' .. text)
      eq(#def[2] <= 34 and #def[2] > 0, true, 'line of ' .. text .. ' fits the card')
      eq(glyphs[def[1]], nil, 'glyph used twice on ' .. hub.id .. '/' .. tab.id .. ': ' .. def[1])
      glyphs[def[1]] = true
    end
  end
end
eq(tabs, 26, '26 tabs')
eq(cards, 104, '104 cards (the Store is a pin, on no tab)')
for text in pairs(C.CARDS) do eq(seen[text] or T.PIN_ONLY[text], true, 'a card line for a text the tree does not hold: ' .. text) end
-- the hotkey windows are on the first tab of their hub (two clicks)
local first = {}
for _, hub in ipairs(T.HUBS) do for _, text in ipairs(hub.tabs[1].cards) do first[text] = true end end
for _, text in ipairs({ 'Spellbook', 'Passive Tree', 'Hunt Tracker', 'Bestiary', 'Party Finder', 'Dungeons', 'Crafting Bench', 'Market',
  'Guild', 'Codex', 'Help Search' }) do
  eq(first[text], true, 'hotkey window on a first tab: ' .. text)
end
eq(seen['The Gambler'], nil, 'NPC windows stay out')
eq(seen['Unjustified Points'], nil, 'dropped stays out')

-- ---------------------------------------------------------------- text helpers
local b, c = H.baseText('Party Finder (3)')
eq(b, 'Party Finder', 'base text'); eq(c, 3, 'count')
b, c = H.baseText('Bank')
eq(b, 'Bank', 'plain text'); eq(c, nil, 'no count')
eq(H.baseText('Raid: Ashen Sepulchre'), 'Raid: Ashen Sepulchre', 'a colon is no count')
eq(H.hubOfCategory(T, 'economy'), 'trade', 'economy is trade'); eq(H.hubOfCategory(T, 'admin'), 'system', 'admin is system')
eq(H.hubOfCategory(T, 'chaos'), 'adventure', 'the old chaos id'); eq(H.hubOfCategory(T, 'nope'), nil, 'unknown id')
eq(H.shown(function(k) return 'Saque' end, 'tab.hunt.loot', 'Loot'), 'Saque', 'translated name')
eq(H.shown(function(k) return k end, 'tab.hunt.loot', 'Loot'), 'Loot', 'no translation: the English name')
eq(H.shown(function() error('x') end, 'tab.hunt.loot', 'Loot'), 'Loot', 'a failing tr gives the English name')

-- ---------------------------------------------------------------- the model
local m = H.build(T, C, {
  item('Hunt Tracker', { key = 'Alt+H' }), item('Battle List'), item('Auto Loot', { isNew = true }),
  item('Party Finder (3)', { key = 'Alt+L' }), item('Unjustified Points'), item('Menu Style'),
}, {})
eq(#m.hubs, 1, 'only the Hunt hub has anything')
local hunt = m.hubs[1]
eq(hunt.id, 'hunt', 'hunt'); eq(#hunt.tabs, 2, 'Hunting and Loot; the empty tabs are hidden')
eq(cardTexts(hunt.tabs[1]), 'Hunt Tracker|Battle List|Party Finder', 'tree order, not the order of the items')
eq(hunt.tabs[1].cards[3].count, 3, 'count of Party Finder'); eq(hunt.tabs[1].cards[3].shown, 'Party Finder (3)', 'shown text kept')
eq(hunt.tabs[1].cards[1].key, 'Alt+H', 'hotkey'); eq(hunt.tabs[1].cards[1].glyph, 'stopwatch', 'glyph')
eq(hunt.tabs[1].cards[1].desc, 'Exp, loot and profit per hour', 'line')
eq(hunt.count, 3, 'hub count'); eq(hunt.tabs[1].count, 3, 'tab count')
eq(hunt.new, true, 'new passes up to the hub'); eq(hunt.tabs[2].new, true, 'new on the tab'); eq(hunt.tabs[1].new, false, 'not on the other tab')

-- locked: the next system shows grey with its level; its new flag is off
m = H.build(T, C, { item('Passive Tree', { category = 'character', status = 'locked', level = 12 }), item('Skills', { category = 'character' }) }, {})
local hero = m.hubs[1]
eq(cardTexts(hero.tabs[1]), 'Skills|Passive Tree', 'locked card kept in its slot')
eq(hero.tabs[1].cards[2].locked, 12, 'level of the locked card'); eq(hero.tabs[1].cards[2].new, false, 'a locked card is not new')

-- hidden or unknown status never shows
m = H.build(T, C, { item('Skills', { status = 'hidden' }) }, {})
eq(#m.hubs, 0, 'a hidden entry shows nothing')

-- admin entries only for staff, in the System hub, tab Staff
local adminItem = item('Admin Panel', { category = 'admin' })
eq(#H.build(T, C, { adminItem }, {}).hubs, 0, 'no admin without access')
m = H.build(T, C, { adminItem }, { admin = true })
eq(m.hubs[1].id, 'system', 'system hub'); eq(m.hubs[1].tabs[1].id, 'staff', 'staff tab')

-- shared slots: Spell List takes the Spellbook card, with its own name
m = H.build(T, C, { item('Spell List', { category = 'character' }) }, {})
eq(m.hubs[1].tabs[1].cards[1].text, 'Spell List', 'shared slot keeps the entry text')
eq(m.hubs[1].tabs[1].cards[1].glyph, 'tome', 'glyph of the slot')

-- unknown entries fall into the last tab of the hub of their category
m = H.build(T, C, { item('Future Window', { category = 'economy', icon = 'bank' }), item('Bank', { category = 'economy' }) }, {})
local trade = m.hubs[1]
eq(trade.id, 'trade', 'trade hub'); eq(#trade.tabs, 2, 'Shop and the last tab for the extra')
eq(trade.tabs[2].id, 'finder', 'last tab of trade'); eq(trade.tabs[2].cards[1].text, 'Future Window', 'extra card')
eq(trade.tabs[2].cards[1].extra, true, 'flagged'); eq(trade.tabs[2].cards[1].glyph, 'columns', 'glyph of the old icon name')
m = H.build(T, C, { item('Future Window', { category = 'weird', icon = 'zzz' }) }, {})
eq(m.hubs[1].id, 'system', 'unknown category goes to system'); eq(m.hubs[1].tabs[1].id, 'staff', 'last tab'); eq(m.hubs[1].tabs[1].cards[1].glyph, 'star', 'fallback glyph')

-- login screen: the caller passes only the offline entries, so only System shows
m = H.build(T, C, { item('Options', { category = 'system' }), item('Credits', { category = 'system' }), item('Exit', { category = 'system' }) }, {})
eq(#m.hubs, 1, 'one hub'); eq(m.hubs[1].id, 'system', 'System'); eq(#m.hubs[1].tabs, 2, 'Basics and Support')

-- find
local card, hub, tab = H.findCard(m, 'Credits')
eq(card.text, 'Credits', 'findCard'); eq(hub.id, 'system', 'its hub'); eq(tab.id, 'support', 'its tab')
eq(H.findCard(m, 'Nope'), nil, 'missing card')
eq(select(2, H.findHub(m, 'system')), 1, 'findHub index')

-- ---------------------------------------------------------------- remembered tab and pins
eq(H.tabSettingKey('hunt', 'Ash'), 'chaosHubTab_hunt_Ash', 'tab key per character'); eq(H.tabSettingKey('hunt', nil), 'chaosHubTab_hunt', 'login key')
eq(H.pinsSettingKey('Ash'), 'chaosHubPins_Ash', 'pins key')
local h2 = { tabs = { { id = 'a' }, { id = 'b' }, { id = 'c' } } }
eq(H.pickTab(h2, 'c'), 3, 'saved tab'); eq(H.pickTab(h2, 'gone'), 1, 'a tab that is gone'); eq(H.pickTab(h2, nil), 1, 'first open')

eq(H.parsePins(''), nil, 'never set'); eq(H.parsePins(nil), nil, 'nil')
eq(#H.parsePins('v1:'), 0, 'cleared'); eq(table.concat(H.parsePins('v1:Store|Market'), ','), 'Store,Market', 'two pins')
eq(#H.parsePins('v1:a|b|c|d|e'), 3, 'at most three')
eq(table.concat(H.pinsOrDefault(''), ','), 'Store', 'the Store is the default pin (its own button, on no tab)'); eq(#H.pinsOrDefault('v1:'), 0, 'cleared stays cleared')
eq(H.serializePins({ 'Store', 'Bank' }), 'v1:Store|Bank', 'serialize')
local pins, changed, why = H.togglePin({ 'Store' }, 'Market')
eq(changed, true, 'pinned'); eq(table.concat(pins, ','), 'Store,Market', 'added last')
pins = H.togglePin(pins, 'Store')
eq(table.concat(pins, ','), 'Market', 'a second toggle unpins')
pins, changed, why = H.togglePin({ 'a', 'b', 'c' }, 'd')
eq(changed, false, 'no room'); eq(why, 'full', 'full'); eq(#pins, 3, 'list kept')
m = H.build(T, C, { item('Store', { category = 'economy' }), item('Bank', { category = 'economy' }) }, {})
local pc = H.pinnedCards(m, { 'Bank', 'Market', 'Store' })
eq(#pc, 2, 'a pin with no usable card is skipped'); eq(pc[1].text, 'Bank', 'pin order kept')

-- ---------------------------------------------------------------- style
eq(H.normalizeStyle('text'), 'text', 'text'); eq(H.normalizeStyle(nil), 'hubs', 'default hubs'); eq(H.normalizeStyle('x'), 'hubs', 'junk')
eq(H.resolveStyle('hubs', true, false), 'hubs', 'hubs'); eq(H.resolveStyle('hubs', false, false), 'text', 'art missing')
eq(H.resolveStyle('hubs', true, true), 'text', 'after an error'); eq(H.resolveStyle('text', true, false), 'text', 'chosen')
eq(H.rowsOf({ cards = { 1, 2, 3, 4, 5 } }), 2, 'rows')

-- ---------------------------------------------------------------- the grid, fit, bar width
local x, y = H.cardPos(1); eq(x + y, 0, 'first card at the corner')
x, y = H.cardPos(4); eq(x, 3 * 188, 'fourth card, last column'); eq(y, 0, 'fourth card, first row')
x, y = H.cardPos(5); eq(x, 0, 'fifth card wraps'); eq(y, 74, 'second row'); x, y = H.cardPos(6, 76); eq(x, 188, 'sixth card column'); eq(y, 82, 'phone row pitch')
local function m8(s) return #s * 8 end
eq(H.fit('Short', 100, m8), 'Short', 'fits as it is')
eq(H.fit('Map Overlay Settings', 100, m8), 'Map Overla..', 'cut with dots')
eq(H.fit('Ab', 1, m8), 'A', 'nothing fits: one letter')
eq(m8(H.fit('Points of interest and party marks', 118, m8)) <= 118, true, 'cut width within the limit')
local bm = { hubs = { { id = 'hero' }, { id = 'hunt' }, { id = 'system' } } }
local function kinds(items) local o = {} for _, it in ipairs(items) do o[#o + 1] = it.kind == 'hub' and it.hub.id or (it.kind == 'pin' and ('pin:' .. it.card.text) or '|') end return table.concat(o, ',') end
eq(kinds(H.barItems(bm, {})), 'hero,hunt,|,system', 'System alone at the right end, behind a divider')
eq(kinds(H.barItems(bm, { { text = 'Bank' } })), 'hero,hunt,|,pin:Bank,|,system', 'pins between the hubs and System')
eq(kinds(H.barItems({ hubs = { { id = 'system' } } }, {})), 'system', 'the login screen: System only, no divider')
eq(H.barWidth(H.barItems(bm, {}), 32), 16 + 3 * 32 + 5 + 3 * 4, 'width: three badges and a divider')
eq(H.barWidth(H.barItems({ hubs = { { id = 'system' } } }, {}), 32), 16 + 32, 'width of the login bar')
eq(H.barWidth({}, 32), 16, 'empty bar')
local full = { hubs = { { id = 'hero' }, { id = 'hunt' }, { id = 'adventure' }, { id = 'trade' }, { id = 'social' }, { id = 'system' } } }
eq(H.barWidth(H.barItems(full, { {}, {}, {} }), 32) <= 420, true, 'six hubs and three pins stay in 420 px')
local pm = H.build(T, C, { item('Passive Tree', { category = 'character', points = 3 }), item('Skills', { category = 'character', points = 0 }) }, {})
eq(H.findCard(pm, 'Passive Tree').points, 3, 'a card takes the points its module counts'); eq(H.findCard(pm, 'Skills').points, nil, 'zero points: no badge')
local pt = H.build(T, C, { item('Passive Tree', { category = 'character', points = '!' }) }, {})
eq(H.findCard(pt, 'Passive Tree').points, '!', 'an open trial with no point waiting: the card keeps "!" (O559)')

print('topbarhublogic_test: ' .. n .. ' checks ok')
