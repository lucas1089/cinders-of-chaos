-- luajit pouchesview_test.lua (CI runs every client *_test.lua)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'pouchesview.lua')
local V = PouchesView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

local r = V.normalize({ list = true, gold = 1, gear = true, minRarity = 40 })
eq(r.list, true, 'list on') eq(r.gold, false, 'only true counts') eq(r.minRarity, 10, 'rarity clamped to Divine')
eq(V.normalize({ minRarity = 7 }).minRarity, 5, 'an old Mythic is Legendary') eq(V.normalize({ minRarity = 3 }).minRarity, 3, 'Magic')
eq(#V.rarityOptions(nil), 6, 'six rarities') eq(V.rarityOptions(nil)[3], 'Magic', 'names') eq(V.rarityOptions({ 'a', 'b' })[2], 'b', 'names from the server')
eq(V.rarityIndex(10), 6, 'Divine is the sixth') eq(V.rarityIndex(5), 5) eq(V.rarityIndex(12), 6, 'an old Celestial') eq(V.rarityIndex(0), 1)
eq(V.normalize(nil).minRarity, 5, 'default rarity')
eq(V.normalize(nil).overflow, true, 'overflow on when not sent') eq(V.normalize({ overflow = false }).overflow, false, 'overflow off kept')
eq(r.overflow, true, 'overflow default with other rules') eq(V.normalize({ minRarity = 0 }).minRarity, 1, 'at least 1')
eq(V.statusText({ loot = true }):find('You have a Loot Bag') ~= nil, true, 'owned text')
eq(V.statusText({}):find('Store') ~= nil, true, 'not owned: points to the store')
eq(V.statusText(nil), '', 'no data yet')
local ids = { loot = 3925, orbs = 3926 }
eq(V.isLootPouch(3925, 1, ids), true, 'pouch: look and lock flag')
eq(V.isLootPouch(3925, 0, ids), false, 'a stock bag of the same look')
eq(V.isLootPouch(3926, 1, ids), false, 'another pouch')
eq(V.isLootPouch(3925, 1, {}), false, 'ids not known yet')
local opts = V.rarityOptions({ 'Common', 'Uncommon' })
eq(#opts, 6, 'six options') eq(opts[2], 'Uncommon', 'names used') eq(opts[3], 'Magic', 'fallback name')
-- the window fits its content (live test winpkg-35: the note was cut off, the saved line ran under the buttons)
eq(V.fitHeight({ top = 100, contentBottom = 480, savedHeight = 14, buttonHeight = 24, paddingBottom = 16, minHeight = 452 }),
  452, 'short content: the minimum height')
-- pt-BR: a three-line note and Open Store under it reach lower; the saved line wraps to two lines
eq(V.fitHeight({ top = 100, contentBottom = 560, savedHeight = 28, buttonHeight = 24, paddingBottom = 16, minHeight = 452 }),
  460 + V.SAVED_GAP + 28 + V.BUTTON_GAP + 24 + 16, 'long content: the window grows')
local noteEn = V.statusText({ loot = false }, 'Loot Bag')
eq(noteEn:find('when you do.', 1, true) ~= nil, true, 'the note ends with its full sentence (no placeholder cut)')
print('pouchesview_test: ' .. n .. ' checks OK')
