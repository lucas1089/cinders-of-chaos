-- luajit pouchesview_test.lua (CI runs every client *_test.lua)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'pouchesview.lua')
local V = PouchesView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

local r = V.normalize({ list = true, gold = 1, gear = true, minRarity = 40 })
eq(r.list, true, 'list on') eq(r.gold, false, 'only true counts') eq(r.minRarity, 15, 'rarity clamped')
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
eq(#opts, 15, '15 options') eq(opts[2], 'Uncommon', 'names used') eq(opts[3], 'Rarity 3', 'fallback name')
-- the window fits its content (live test winpkg-35: the note was cut off, the saved line ran under the buttons)
eq(V.fitHeight({ top = 100, contentBottom = 480, savedHeight = 14, buttonHeight = 24, paddingBottom = 16, minHeight = 452 }),
  452, 'short content: the minimum height')
-- pt-BR: a three-line note and Open Store under it reach lower; the saved line wraps to two lines
eq(V.fitHeight({ top = 100, contentBottom = 560, savedHeight = 28, buttonHeight = 24, paddingBottom = 16, minHeight = 452 }),
  460 + V.SAVED_GAP + 28 + V.BUTTON_GAP + 24 + 16, 'long content: the window grows')
local noteEn = V.statusText({ loot = false }, 'Loot Bag')
eq(noteEn:find('when you do.', 1, true) ~= nil, true, 'the note ends with its full sentence (no placeholder cut)')
print('pouchesview_test: ' .. n .. ' checks OK')
