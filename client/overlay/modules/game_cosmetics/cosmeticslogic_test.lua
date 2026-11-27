-- luajit client/overlay/modules/game_cosmetics/cosmeticslogic_test.lua (and lua5.3), from the repo root
dofile('client/overlay/modules/game_cosmetics/cosmeticslogic.lua')
local CL = CosmeticsLogic

local n = 0
local function eq(a, b, m)
  n = n + 1
  if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end

local function joined(parts)
  local t = {}
  for i = 1, #parts - 1, 2 do t[#t + 1] = parts[i] end
  return table.concat(t)
end

-- colours
eq(CL.validColor('#7fc8ff'), true, 'rgb') eq(CL.validColor('#0a1632f0'), true, 'rgba')
eq(CL.validColor('red'), false, 'a name is no colour') eq(CL.validColor('#12345'), false, 'short')

-- name ranges in console lines
local first, last = CL.nameRange('12:30 Bob [120]: hi Bob', 'Bob')
eq(first, 7, 'name start') eq(last, 9, 'name end')
first = CL.nameRange(' Bob: hello', 'Bob')
eq(first, 2, 'no timestamp, no level')
eq(CL.nameRange('12:30 Bobby [5]: hi', 'Bob'), nil, 'a longer name is not the name')
eq(CL.nameRange('12:30 Ann [5]: Bob: hi', 'Bob'), nil, 'the name inside the text is not the speaker')
eq(CL.nameRange('12:30 Ann Bob [5]: hi', 'Ann Bob'), 7, 'names with a space')

-- recolouring keeps the text and the other colours
local parts = { '12:30 Bob [120]: look ', '#f0f000', '[Magic Sword]', '#a35cf0', ' now', '#f0f000' }
local text = joined(parts)
local out = CL.recolor(parts, 7, 9, '#7fc8ff')
eq(joined(out), text, 'same text')
eq(out[3], 'Bob', 'the name alone') eq(out[4], '#7fc8ff', 'in its colour')
eq(out[1], '12:30 ', 'before the name') eq(out[2], '#f0f000', 'message colour before')
eq(out[5], ' [120]: look ', 'after the name') eq(out[6], '#f0f000', 'message colour after')
eq(out[7], '[Magic Sword]', 'the item link stays') eq(out[8], '#a35cf0', 'in its rarity colour')
local whole = CL.recolor({ 'Bob', 'white' }, 1, 3, '#ff9a4a')
eq(#whole, 2, 'a part that is only the name') eq(whole[2], '#ff9a4a', 'recoloured')

-- whole lines: players only, known colours only
local names = { Bob = '#7fc8ff' }
local line = { '12:30 Bob [120]: hi', '#f0f000' }
local res = CL.colorLine(line, joined(line), { name = 'Bob', level = 120 }, names)
eq(res[3], 'Bob', 'coloured') eq(res[4], '#7fc8ff', 'Bob in frost blue')
eq(CL.colorLine(line, joined(line), { name = 'Bob', level = 0 }, names), nil, 'no level: an NPC or a system line')
eq(CL.colorLine(line, joined(line), { name = 'Bob', level = 5, npc = true }, names), nil, 'NPC chat')
eq(CL.colorLine(line, joined(line), { name = 'Ann', level = 5 }, names), nil, 'no colour for Ann')

-- the colour list from the server
local m = CL.mergeColors({}, { names = { Bob = '#7fc8ff', Ann = 'bad' }, full = true })
eq(m.Bob, '#7fc8ff', 'kept') eq(m.Ann, nil, 'a bad colour is dropped')
m = CL.mergeColors(m, { names = { Carl = '#ff9a4a' } })
eq(m.Bob, '#7fc8ff', 'an update keeps the others') eq(m.Carl, '#ff9a4a', 'and adds')
m = CL.mergeColors(m, { names = { Bob = false } })
eq(m.Bob, nil, 'false removes')
m = CL.mergeColors(m, { names = {}, full = true })
eq(next(m), nil, 'a full list replaces')

-- window rows
local rows = {
  { id = 1, kind = 'spellskin', line = 'warrior', lineName = 'Warrior line', name = 'Voidborn', owned = true, selected = true },
  { id = 8, kind = 'spellskin', line = 'monk', lineName = 'Monk line', name = 'Crimson Palms', owned = true },
  { id = 2, kind = 'spellskin', line = 'warrior', name = 'Stormborn', owned = false, how = 'Store: 250 Chaos Coins' },
  { id = 101, kind = 'killfx', name = 'Soul Spark', owned = true },
}
local tab = CL.tabRows(rows, 'spellskin', 'warrior', 'Warrior line')
eq(#tab, 4, 'default + two warrior skins + the monk one')
eq(tab[1].id, 0, 'default first') eq(tab[1].selected, false, 'a skin is in use')
eq(tab[2].id, 1, 'own line next') eq(tab[4].otherLine, true, 'other line last')
eq(rows[2].otherLine, nil, 'the server rows are not changed')
eq(CL.subText(tab[2]), 'In use', 'in use') eq(CL.subText(tab[3]), 'Store: 250 Chaos Coins', 'how to get it')
eq(CL.subText(tab[4]), 'Monk line - not your class', 'another class')
eq(CL.canUse(tab[1]), true, 'back to the default') eq(CL.canUse(tab[2]), false, 'already in use')
eq(CL.canUse(tab[3]), false, 'not owned') eq(CL.canUse(tab[4]), false, 'not your class')
tab = CL.tabRows(rows, 'killfx')
eq(#tab, 2, 'default + soul spark') eq(tab[1].selected, true, 'nothing chosen: the default')
tab = CL.tabRows(rows, 'spellskin', nil)
eq(tab[1].otherLine, true, 'a class without skins: no default row, all other lines')


-- footprints and outlines: a Default row to take them off
local fx = { { id = 401, kind = 'footprint', name = 'Ember Steps', owned = true, selected = true, art = 'ember' },
  { id = 501, kind = 'outline', name = 'Gilded Glow', owned = false, how = 'Store: 250 Chaos Coins', art = 'gold' } }
tab = CL.tabRows(fx, 'footprint')
eq(#tab, 2, 'default + the footprint') eq(tab[1].selected, false, 'the footprint is in use')
eq(tab[1].desc, 'You leave no footprints.', 'default text') eq(CL.canUse(tab[1]), true, 'take it off')
tab = CL.tabRows(fx, 'outline')
eq(tab[1].selected, true, 'no outline chosen') eq(CL.subText(tab[2]), 'Store: 250 Chaos Coins', 'how to get one')
eq(CL.DRAWN.footprint and CL.DRAWN.outline, true, 'drawn kinds')
local keys = {}
for _, k in ipairs(CL.KINDS) do keys[#keys + 1] = k.key end
eq(table.concat(keys, ','), 'spellskin,killfx,lootbeam,chatcolor,footprint,outline,levelfx,rarefx,head,cape,collection', 'tabs')

-- the Collection tab (server exclusives_core.lua rows): owned first, never usable here
local col = { { key = 'mount_tuskhide', kind = 'mount', kindName = 'Mount', name = 'Tuskhide Boar',
    how = 'Achievement: Nothing Surprises Me (Kill 250 ambushing monsters.)' },
  { key = 'wings_cinderplumes', kind = 'wings', kindName = 'Wings', name = 'Cinder Plumes', owned = true,
    how = 'Boss: Ysgrath the Cinderheart, rare drop' },
  { key = 'frame_laurel', kind = 'frame', kindName = 'Name Plate Frame', name = 'Laurel' }, 'junk' }
local cr = CL.collectionRows(col)
eq(#cr, 3, 'three rows, junk skipped') eq(cr[1].key, 'wings_cinderplumes', 'owned first')
eq(cr[2].key, 'mount_tuskhide', 'then the server order') eq(cr[1].id, 'x:wings_cinderplumes', 'row id')
eq(CL.subText(cr[1]), 'Wings - Unlocked', 'owned line')
eq(CL.subText(cr[2]), 'Mount - Achievement: Nothing Surprises Me (Kill 250 ambushing monsters.)', 'how to earn it')
eq(CL.canUse(cr[1]), false, 'chosen in its own window')
eq(#CL.collectionRows(col, 'owned'), 1, 'owned filter') eq(#CL.collectionRows(col, 'missing'), 2, 'missing filter')
local have, all = CL.collectionCount(col)
eq(have, 1, 'one earned') eq(all, 3, 'of the rows sent (junk skipped)')
eq(col[1].id, nil, 'the server rows are not changed')

-- the combat cosmetics tabs (O318): a default row and the rows of their kind
local combat = { { id = 601, kind = 'levelfx', name = 'Dawn Ascent', owned = true, preview = true },
  { id = 701, kind = 'rarefx', name = 'Gilded Glint', owned = false, how = 'Store: 200 Chaos Coins', preview = true },
  { id = 702, kind = 'rarefx', name = 'Crimson Gleam', owned = true, selected = true, preview = true } }
tab = CL.tabRows(combat, 'levelfx')
eq(#tab, 2, 'default + the level-up effect') eq(tab[1].desc, 'No effect when you gain a level.', 'level-up default text')
eq(tab[1].selected, true, 'none chosen')
tab = CL.tabRows(combat, 'rarefx')
eq(tab[1].selected, false, 'a rare loot effect is in use') eq(CL.canUse(tab[1]), true, 'switch it off') eq(CL.canUse(tab[3]), false, 'already in use')
eq(CL.tabRows(combat, 'rarefx')[2].how, 'Store: 200 Chaos Coins', 'how to get it')

-- the collection score (server collection_core.lua K.view)
local view = { score = 142, groups = { { g = 'outfit', n = 3, p = 18 }, { g = 'mount', n = 2, p = 18 }, { g = 'bogus', n = 1, p = 1 } },
  next = { points = 220, left = 78 },
  milestones = { { key = 'collector', points = 20, done = true, rewards = { { k = 'title', n = 'Collector' } } },
    { key = 'trail', points = 60, done = true, rewards = { { k = 'footprint', n = 'Laurel Steps' } } },
    { key = 'curator', points = 120, done = true, rewards = { { k = 'title', n = 'Curator' } } },
    { key = 'gold', points = 220, rewards = { { k = 'chatcolor', n = "Collector's Gold" } } },
    { key = 'connoisseur', points = 400, rewards = { { k = 'title', n = 'Connoisseur', f = 'gallery' } } } } }
eq(CL.scoreLine(view), 'Collection score: 142 - next reward at 220 (78 to go)', 'the strip')
eq(CL.scoreLine({ score = 5000 }), 'Collection score: 5000 - every reward earned', 'nothing left')
eq(CL.scoreLine(nil), '', 'no score yet')
local lines = CL.milestoneLines(view)
eq(#lines, 5, 'a line per milestone') eq(lines[1], '[x] 20 points: Title Collector', 'a reached milestone')
eq(lines[4], "[ ] 220 points: Chat colour Collector's Gold", 'one ahead') eq(lines[5], '[ ] 400 points: Title Connoisseur and a plate frame', 'with a frame')
eq(lines[2], '[x] 60 points: Footprints Laurel Steps', 'footprints')
eq(CL.groupLine(view), 'Outfits 3 (18), Mounts 2 (18)', 'groups in the server order, unknown ones skipped')
-- V42: whole entries per line, never a break inside "Loot labels 1 (4)"
local function chars(t) return #t * 7 end
local entries = { 'Outfits 11 (47)', 'Kill effects 1 (4)', 'Level-up effects 3 (11)', 'Loot labels 1 (4)', 'Chat colours 2 (8)' }
local wrapped = CL.wrapEntries('Unlocked - ', entries, 70 * 7, chars)
eq(wrapped, 'Unlocked - Outfits 11 (47), Kill effects 1 (4),\nLevel-up effects 3 (11), Loot labels 1 (4), Chat colours 2 (8)',
  'lines of whole entries')
for l in wrapped:gmatch('[^\n]+') do eq(chars(l) <= 70 * 7, true, 'each line fits: ' .. l) end
eq(CL.wrapEntries('Unlocked - ', entries, 9999, chars), 'Unlocked - ' .. table.concat(entries, ', '), 'one line when it fits')
eq(CL.wrapEntries('Unlocked - ', {}, 100, chars), 'Unlocked - ', 'no entries')
eq(CL.wrapEntries('U - ', { 'a very long entry indeed' }, 5, chars), 'U - a very long entry indeed', 'the first entry stays on the head line')
eq(#CL.groupEntries(view), 2, 'an entry per known group')
local row = CL.scoreRow(view)
eq(#row.howEntries, 2, 'the score row carries its entries')
eq(row.id, 'x:score', 'row id') eq(row.collection, true, 'never usable') eq(row.name, 'Collection score: 142', 'name')
eq(CL.canUse(row), false, 'not usable') eq(CL.subText(row), 'Rewards for owning cosmetics', 'sub text')
eq(CL.scoreRow(nil), nil, 'no row without a score') eq(CL.scoreRow({}), nil, 'no row for junk')
local rows2 = CL.collectionRows(col, nil, view)
eq(#rows2, 4, 'the score row and the three exclusives') eq(rows2[1].id, 'x:score', 'the score comes first')
eq(rows2[2].key, 'wings_cinderplumes', 'then the owned ones')
eq(CL.collectionRows(col, 'owned', view)[1].id, 'x:score', 'also with a filter')
eq(#CL.collectionRows(col, nil, nil), 3, 'no score: only the exclusives')


-- head pieces and capes of client pair 83 (O747)
eq(CL.tabShown({}, 'head'), false, 'no head tab without head rows (below pair 83)')
eq(CL.tabShown({ { kind = 'cape', id = 1101 } }, 'cape'), true, 'a cape row shows the cape tab')
eq(CL.tabShown({}, 'killfx'), true, 'the other tabs always show')
local hrows = CL.tabRows({ { kind = 'head', id = 1001, look = 3590, name = 'Antelope Horns' } }, 'head')
eq(#hrows, 2, 'the Default and the piece') eq(hrows[1].desc, 'You wear no head piece.', 'the Default text')
local ch = CL.wearChanges({ names = { Bob = { h = 3590 }, Al = { c = 3656, f = 'ash' }, Cy = false, Dee = { o = 'gold' } } })
eq(ch.clear, false, 'one change') eq(#ch.list, 4, 'every name')
eq(ch.list[1][1] .. ch.list[1][2] .. ch.list[1][3], 'Al03656', 'a cape, in name order')
eq(ch.list[2][2], 3590, 'a head') eq(ch.list[3][2] + ch.list[3][3], 0, 'false: nothing worn')
eq(ch.list[4][2] + ch.list[4][3], 0, 'an outline only: nothing worn')
ch = CL.wearChanges({ full = true, names = { Bob = { h = 3590 }, Cy = { o = 'gold' }, Ed = { h = -4, c = 1.5 } } })
eq(ch.clear, true, 'a full list clears first') eq(#ch.list, 1, 'then only the characters that wear something')
eq(#CL.wearChanges(nil).list, 0, 'junk') eq(#CL.wearChanges({ names = { [''] = { h = 1 } } }).list, 0, 'no name')

-- tab widths from their text (V31): the English row of 11 tabs fits with a padding of 16
local en = { 84, 72, 77, 84, 70, 54, 66, 66, 33, 39, 65 }
local w = CL.tabWidths(en, 961, 4)
eq(w[1], 100, 'Spell Effects: text and 16') eq(w[9], 49, 'Head')
local function total(t) local s = 0 for _, v in ipairs(t) do s = s + v end return s + 4 * (#t - 1) end
eq(total(w) <= 961, true, 'the row fits')
-- pt-BR is longer: the padding shrinks, no text is cut
local pt = { 100, 98, 92, 80, 50, 60, 85, 55, 42, 36, 48 }
w = CL.tabWidths(pt, 961, 4)
eq(total(w) <= 961, true, 'pt-BR fits')
eq(w[1] >= 100 + CL.TAB_PAD_MIN, true, 'pt-BR text whole')
-- far too narrow: shares of the text, still inside
w = CL.tabWidths(en, 500, 4)
eq(total(w) <= 500, true, 'cut row fits') eq(w[1] > w[9], true, 'longer text, wider tab')
eq(#CL.tabWidths({}, 900, 4), 0, 'no tabs')

print('cosmeticslogic_test: ' .. n .. ' checks OK')
