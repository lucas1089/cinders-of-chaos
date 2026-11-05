-- luajit stashfind_test.lua (CI runs every client *_test.lua)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
dofile(here .. 'stashview.lua')
dofile(here .. 'stashfind.lua')
local F = StashFind
local V = StashView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(s, part, m) eq(type(s) == 'string' and s:find(part, 1, true) ~= nil, true, (m or '') .. ' (' .. tostring(s) .. ')') end

-- the query
eq(F.query('  sword '), 'sword', 'trimmed')
eq(F.query('a'), nil, 'too short')
eq(F.query('a b'), 'a b', 'two letters in two words')
eq(F.query('   '), nil, 'spaces')
eq(F.query(string.rep('x', F.MAX_CHARS + 1)), nil, 'too long')
eq(F.query(nil), nil, 'nothing')
eq(F.HOTKEY ~= 'Ctrl+F', true, 'not the fullscreen key of the base client')

-- where an item is
local bag = { loc = 'bag', slot = 3, path = { 1, 0 }, at = 4, ids = { 1988, 1987, 1991 }, where = 'backpack > bag > green bag',
  name = 'fire sword', count = 1, cid = 3001, rarity = 5 }
has(F.whereText(bag), 'Carried: backpack > bag > green bag', 'a carried item')
has(F.whereText({ loc = 'equip', slot = 1 }), 'Head', 'an equipped item names its slot')
has(F.whereText({ loc = 'equip', slot = 99 }), 'Slot 99', 'an unknown slot')
has(F.whereText({ loc = 'purse' }), 'purse', 'the purse')
has(F.whereText({ loc = 'inbox' }), 'inbox', 'the inbox')
has(F.whereText({ loc = 'stash', tab = 1 }, V.tabLabel), 'Stash: Stash tab', 'the general tab')
has(F.whereText({ loc = 'stash', tab = 105, tabName = 'Weapons' }, V.tabLabel), 'Weapons tab', 'an affinity tab')
has(F.whereText({ loc = 'stash', tab = 200, old = true }, V.tabLabel), 'Old depot', 'the Old depot tab')
eq(F.whereText(nil), '', 'nothing')

-- what a click does
eq(F.action(bag), 'container', 'a carried item opens its bags')
eq(F.action({ loc = 'stash' }), 'stash', 'stash')
eq(F.action({ loc = 'inbox' }), 'inbox', 'inbox')
eq(F.action({ loc = 'purse' }), 'purse', 'purse')
eq(F.action({ loc = 'equip' }), 'equip', 'equip')
eq(F.action({ loc = 'moon' }), nil, 'unknown')
has(F.hint({ loc = 'inbox' }), 'Inbox button', 'the inbox points to the Inbox button')

-- the steps game_chaoslayout opens
local st = F.steps(bag)
eq(#st, 3, 'the backpack, the bag, the green bag')
eq(st[1].i, 3, 'the slot') eq(st[1].id, 1988, 'the backpack id')
eq(st[2].i, 1, 'the bag index') eq(st[2].id, 1987, 'the bag id')
eq(st[3].i, 0, 'the green bag index') eq(st[3].id, 1991, 'its id')
eq(F.steps({ loc = 'bag', slot = 3, path = {}, ids = { 1988 } })[1].i, 3, 'directly in the backpack')
eq(F.steps({ loc = 'bag', slot = 3, path = { 1 }, ids = { 1988 } }), nil, 'a path without its ids')
eq(F.steps({ loc = 'stash' }), nil, 'not carried')

-- the stash entry of a result
eq(F.isEntry({ loc = 'stash', row = 9 }, { row = 9, id = 2400 }), true, 'a stored item by its row')
eq(F.isEntry({ loc = 'stash', row = 9 }, { row = 8, id = 2400 }), false, 'another row')
eq(F.isEntry({ loc = 'stash', item = 2148 }, { id = 2148 }), true, 'a merged stack by its item')
eq(F.isEntry({ loc = 'stash', item = 2148 }, { id = 2148, row = 3 }), false, 'not a stored item of that id')
eq(F.isEntry({ loc = 'bag', item = 2148 }, { id = 2148 }), false, 'not a stash result')

-- status lines
has(F.statusText({ error = 'short' }), 'at least 2', 'short')
has(F.statusText({ error = 'long' }), 'at most 40', 'long')
has(F.statusText({ total = 0 }), 'No item', 'nothing')
has(F.statusText({ total = 3, shown = 3 }), '3 found', 'all')
has(F.statusText({ total = 300, shown = 200, capped = true }), 'the first 200', 'capped')
eq(F.pageText({ page = 1, pages = 1 }), '', 'one page: no line')
has(F.pageText({ page = 2, pages = 3 }), 'Page 2 of 3', 'pages')
eq(F.current({ q = 'sword' }, 'sword'), true, 'the answer to the query on screen')
eq(F.current({ q = 'swo' }, 'sword'), false, 'a late answer to an older query')

-- names and colours
eq(F.title(bag), 'Fire sword (Legendary)', 'name and rarity')
eq(F.title({ name = 'gold coin', count = 77 }), 'Gold coin x77', 'a stack')
eq(F.title({ name = 'ring', unique = true }), 'Ring (Unique)', 'a unique')
eq(F.color(bag), '#ffd040', 'Legendary')
eq(F.color({ unique = true }), F.UNIQUE_COLOR, 'Unique')
eq(F.color({}), F.NORMAL_COLOR, 'plain')

print('stashfind_test: ' .. n .. ' checks passed')
