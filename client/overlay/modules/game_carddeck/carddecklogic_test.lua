-- luajit carddecklogic_test.lua && lua5.3 carddecklogic_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'carddecklogic.lua')
local L = CardDeckLogic
local fails, n = 0, 0
local function eq(a, b, what)
  n = n + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- a server list in the shape of cards_core.lua K.cardsPayload (a few cards)
local payload = { max = 5, cards = {
  { i = 27482, c = 28000, n = 'Common Gyre Card', t = 1, r = 'Common', l = 'Reaping Gyre', e = 'Earth', k = 'convert', s = 'Earth',
    x = 'While on, Reaping Gyre deals Earth damage instead.', cl = { 'Warrior', 'Berserker' } },
  { i = 27483, c = 28001, n = 'Rare Gyre Card', t = 2, r = 'Rare', l = 'Reaping Gyre', e = 'Ice', k = 'convert', s = '',
    x = 'While on, Reaping Gyre deals Ice damage instead.', cl = { 'Warrior', 'Berserker' } },
  { i = 27485, c = 28003, n = 'Mythic Gyre Card', t = 4, r = 'Mythic', l = 'Reaping Gyre', e = 'Energy', k = 'convert', s = 'Energy',
    x = 'Energy.', cl = { 'Warrior' } },
  { i = 27526, c = 28044, n = 'Common Mending Card', t = 1, r = 'Common', l = 'Grand Mending', e = '', k = 'heal', s = '',
    x = 'Heals 10% more.' },
  { i = 27547, c = 28065, n = 'Legendary Wand Card', t = 5, r = 'Legendary', l = 'Sorcerer', e = '', k = 'legendary', s = '',
    x = 'Summons.', cl = { 'Mystic', 'Necromancer' } },
  'junk', { n = 'no id' },
} }
local cards = L.cleanCards(payload)
eq(#cards, 5, 'junk rows are dropped')
eq(cards[1].id, 27482, 'id') eq(cards[1].cid, 28000, 'client id') eq(cards[1].name, 'Common Gyre Card', 'name')
eq(cards[4].classes, nil, 'no class list: any class') eq(#cards[1].classes, 2, 'classes')
eq(#L.cleanCards(nil), 0, 'no payload') eq(#L.cleanCards({ cards = 5 }), 0, 'bad payload')

local state = { unlocked = true, own = { { 27482, 3 }, { 27485, 1 }, { 27547, 2 } }, new = { 27485, 27547, 99 }, on = { 27482 }, max = 5,
  quest = 'See the main quest.' }
local rows = L.rows(cards, state)
eq(#rows, 5, 'one row per card, owned or not')
eq(rows[1].count, 3, 'copies') eq(rows[1].owned, true, 'owned') eq(rows[1].on, true, 'on') eq(rows[1].new, false, 'seen')
eq(rows[2].owned, false, 'not owned') eq(rows[2].count, 0, 'no copies')
eq(rows[3].new, true, 'new') eq(rows[5].new, true, 'new legendary') eq(rows[5].order, 5, 'order')
eq(L.rows(cards, nil)[1].count, 0, 'no state: nothing owned')
eq(L.rows(cards, { own = { 'x', { 'y' } }, on = 'bad' })[1].count, 0, 'a bad state is ignored')

-- filters
local function ids(list) local t = {} for _, r in ipairs(list) do t[#t + 1] = r.id end return table.concat(t, ',') end
eq(ids(L.filter(rows, { owned = 'owned' })), '27482,27485,27547', 'owned')
eq(ids(L.filter(rows, { owned = 'missing' })), '27483,27526', 'missing')
eq(ids(L.filter(rows, { set = 'Earth' })), '27482', 'set Earth') eq(ids(L.filter(rows, { set = 'none' })), '27483,27526,27547', 'no set')
eq(ids(L.filter(rows, { rarity = 'Mythic' })), '27485', 'rarity') eq(ids(L.filter(rows, { rarity = 'Legendary' })), '27547', 'legendary')
eq(ids(L.filter(rows, { element = 'Ice' })), '27483', 'element') eq(ids(L.filter(rows, { element = 'none' })), '27526,27547', 'no element')
eq(ids(L.filter(rows, { mine = true }, 'Warrior')), '27482,27483,27485,27526', 'my class: Warrior (no class list = everyone)')
eq(ids(L.filter(rows, { mine = true }, 'Mystic')), '27526,27547', 'my class: Mystic')
eq(ids(L.filter(rows, { mine = true }, nil)), '27482,27483,27485,27526,27547', 'no class known: no filter')
eq(ids(L.filter(rows, { search = 'gyre' })), '27482,27483,27485', 'search by name') eq(ids(L.filter(rows, { search = 'HEALS' })), '27526', 'search the text')
eq(ids(L.filter(rows, { search = '  summons ' })), '27547', 'search is trimmed') eq(ids(L.filter(rows, { search = 'zzz' })), '', 'no match')
eq(ids(L.filter(rows, { owned = 'owned', rarity = 'Common', set = 'Earth' })), '27482', 'filters add up')
eq(ids(L.filter(rows, nil)), '27482,27483,27485,27526,27547', 'no filter')

-- sort
eq(ids(L.sort(rows, 'number')), '27482,27483,27485,27526,27547', 'number')
eq(ids(L.sort(rows, 'name')), '27482,27526,27547,27485,27483', 'name') eq(ids(L.sort(rows, 'rarity')), '27547,27485,27483,27482,27526', 'rarity best first')
eq(ids(L.sort(rows, 'copies')), '27482,27547,27485,27483,27526', 'copies') eq(ids(L.sort(rows, 'new')), '27485,27547,27482,27483,27526', 'new first')
eq(ids(L.sort(rows, 'element')), '27526,27547,27482,27485,27483', 'element') eq(ids(L.sort(rows, 'bogus')), '27482,27483,27485,27526,27547', 'unknown sort: number')
eq(ids(rows), '27482,27483,27485,27526,27547', 'the sort copies, the rows stay')

-- numbers and the panel
local c = L.counts(rows)
eq(c.owned, 3, 'owned') eq(c.total, 5, 'total') eq(c.copies, 6, 'copies') eq(c.on, 1, 'on') eq(c.new, 2, 'new')
eq(L.summary(rows, 5), 'Cards: 3 of 5  -  copies: 6  -  on: 1 of 5', 'summary')
eq(L.newCount(state), 3, 'the badge counts the server list') eq(L.newCount(nil), 0, 'no state') eq(L.newCount({ new = 'x' }), 0, 'bad list')
eq(ids(L.activeRows(rows)), '27482', 'the active cards')
local d = L.detail(rows[1])
eq(d:find('Common Gyre Card', 1, true) ~= nil and d:find('Card set: Earth', 1, true) ~= nil and d:find('Copies: 3', 1, true) ~= nil, true, 'detail text')
eq(L.detail(rows[2]):find('Not owned yet', 1, true) ~= nil, true, 'detail: not owned')

-- the button
eq(L.toggleButton(rows[1], state).label, 'Turn off', 'on: turn off') eq(L.toggleButton(rows[1], state).enabled, true, 'enabled')
eq(L.toggleButton(rows[3], state).label, 'Turn on', 'owned: turn on') eq(L.toggleButton(rows[3], state).enabled, true, 'enabled')
eq(L.toggleButton(rows[2], state).enabled, false, 'no copy: disabled') eq(L.toggleButton(rows[2], state).why, 'You have no copy of this card.', 'why')
local five = { unlocked = true, on = { 1, 2, 3, 4, 5 }, max = 5 }
eq(L.toggleButton(rows[3], five).enabled, false, 'five on: disabled') eq(L.toggleButton(rows[1], five).enabled, true, 'off still works at five')
local locked = { unlocked = false, quest = 'Locked: see the main quest.' }
eq(L.toggleButton(rows[3], locked).label, 'Locked', 'locked label') eq(L.toggleButton(rows[3], locked).enabled, false, 'locked disabled')
eq(L.toggleButton(rows[3], locked).why, 'Locked: see the main quest.', 'the server text')
eq(L.toggleButton(nil, state).enabled, false, 'no card selected')

-- options
eq(#L.options('set'), 7, 'five sets, all, none') eq(L.options('set')[1][1], nil, 'all') eq(L.options('set')[7][1], 'none', 'no set')
eq(#L.options('rarity'), 6, 'rarities') eq(#L.options('element'), 9, 'elements') eq(#L.options('owned'), 3, 'owned') eq(#L.options('sort'), 6, 'sorts')
eq(L.valueOf(L.options('set'), 'Fire'), 'Fire', 'a label is a value') eq(L.valueOf(L.options('set'), 'All sets'), nil, 'all: no filter')
eq(L.valueOf(L.options('class'), 'My class'), true, 'class box')
-- every sort and option of the logic is a sort the logic knows
for _, s in ipairs(L.SORTS) do eq(#L.sort(rows, s), 5, 'sort ' .. s) end
eq(L.borderColor(rows[1]), L.ON_COLOR, 'on: green') eq(L.borderColor(rows[2]), '#3a3228', 'not owned: dim')
eq(L.borderColor(rows[3]), L.RARITY_COLOR.Mythic, 'owned: rarity colour')

print('carddecklogic_test: ' .. n .. ' checks ok' .. (fails > 0 and (', ' .. fails .. ' FAILED') or ''))
os.exit(fails == 0 and 0 or 1)
