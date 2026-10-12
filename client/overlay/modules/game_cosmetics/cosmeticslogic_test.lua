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
eq(table.concat(keys, ','), 'spellskin,killfx,lootbeam,chatcolor,footprint,outline,collection', 'tabs')

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

print('cosmeticslogic_test: ' .. n .. ' checks OK')
