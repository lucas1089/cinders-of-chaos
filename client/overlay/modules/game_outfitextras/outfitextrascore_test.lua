-- luajit outfitextrascore_test.lua && lua5.3 outfitextrascore_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'outfitextrascore.lua')
local E = OutfitExtrasCore
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local cosmetics = { line = 'ember', lineName = 'Ember', rows = {
  { id = 11, kind = 'outline', name = 'Gold Outline', owned = true, selected = true },
  { id = 12, kind = 'outline', name = 'Void Outline', owned = true },
  { id = 13, kind = 'outline', name = 'Storm Outline', owned = false },
  { id = 21, kind = 'footprint', name = 'Ember Prints', owned = false },
  { id = 31, kind = 'spellskin', name = 'Blue Flame', owned = true, line = 'ember' },
  { id = 32, kind = 'spellskin', name = 'Green Frost', owned = true, line = 'frost' },
  { id = 33, kind = 'spellskin', name = 'Red Flame', owned = true, selected = true, line = 'ember' },
  { id = 41, kind = 'chatcolor', name = 'Ash', owned = true },
} }
local o = E.cosmeticRow(cosmetics, 'outline')
eq(#o.options, 3, 'default + two owned outlines'); eq(o.options[1].value, 0, 'default first'); eq(o.current, 11, 'selected outline')
eq(o.locked, 1, 'one locked outline'); eq(o.line, nil, 'no line for an outline')
local f = E.cosmeticRow(cosmetics, 'footprint')
eq(#f.options, 1, 'only the default when nothing is owned'); eq(f.current, 0, 'default selected'); eq(f.locked, 1, 'locked footprint counted')
local s = E.cosmeticRow(cosmetics, 'spellskin')
eq(#s.options, 3, 'spell skins of the own line only'); eq(s.current, 33, 'selected skin'); eq(s.line, 'ember', 'line sent with a skin')
eq(E.cosmeticRow(nil, 'outline'), nil, 'no state, no row'); eq(E.cosmeticRow({}, 'outline'), nil, 'no rows, no row')

local w = E.wingsRow({ stock = { { 5, 'Gold Wings' }, { 6, 'Ash Wings' } }, wardrobe = { { l = 5, n = 'Gold Wings', o = true },
  { l = 7, n = 'Storm Wings', o = false } }, current = 6 })
eq(#w.options, 3, 'none + two wings'); eq(w.current, 6, 'worn wings'); eq(w.locked, 1, 'one locked wings')
eq(E.wingsRow({ stock = {}, current = 9 }).current, 0, 'worn wings not in the list: none')
eq(E.wingsRow(nil), nil, 'no wings source')

local fr = E.frameRow({ frames = { 'frost', 'ember' }, activeFrame = 'ember' })
eq(#fr.options, 3, 'title frame + two'); eq(fr.current, 'ember', 'shown frame'); eq(fr.options[2].text, 'Frost', 'capital')
eq(E.frameRow({ frames = {}, activeFrame = 'gone' }).current, '', 'unknown frame: the title frame')
eq(E.frameRow(nil), nil, 'no services')

local p = E.petRow({ pets = { { species = 'ashwolf', name = 'Fang', level = 4 }, { species = 'cinderbat', speciesName = 'Cinder Bat' } },
  active = 'cinderbat', catalog = { { key = 'ashwolf', owned = true }, { key = 'emberfox', owned = false } } })
eq(#p.options, 3, 'none + two pets'); eq(p.current, 'cinderbat', 'active pet'); eq(p.locked, 1, 'one pet not owned')
eq(p.options[2].text, 'Fang (level 4)', 'name and level'); eq(p.options[3].text, 'Cinder Bat', 'species name, no level')
eq(E.petRow({ pets = {}, active = 'x' }).current, '', 'active pet unknown: none')

local rows = E.rows({ cosmetics = cosmetics, wings = { stock = { { 5, 'Gold Wings' } }, current = 0 },
  services = { frames = { 'frost' } }, pets = { pets = {} } })
eq(#rows, 9, 'every dropdown has its data: wings, six cosmetic kinds, frame, pet')
eq(rows[1].key, 'wings', 'wings first'); eq(rows[1].label, 'Wings', 'label')
eq(E.lineCount(rows), 5, 'two columns'); eq(E.lineCount({}), 0, 'no rows no lines')
eq(#E.rows({}), 0, 'no sources, no rows')

-- Ok
local acts = E.plan(rows, { outline = 12, footprint = 0, spellskin = 31, frame = 'frost', pet = '', wings = 5, chatcolor = 41 })
eq(#acts, 4, 'outline, spell skin, frame and chat colour changed; unchanged ones and wings skipped')
eq(acts[1].act, 'cosmetic', 'cosmetic'); eq(acts[1].kind, 'outline', 'outline'); eq(acts[1].id, 12, 'id')
eq(acts[2].kind, 'chatcolor', 'order is the window order'); eq(acts[3].kind, 'spellskin', 'spell skin'); eq(acts[3].line, 'ember', 'line')
eq(acts[4].act, 'frame', 'frame'); eq(acts[4].value, 'frost', 'frame value')
eq(#E.plan(rows, { outline = 999 }), 0, 'a value not in the list is refused')
eq(#E.plan(rows, nil), 0, 'nothing chosen')
eq(#E.plan(nil, { outline = 1 }), 0, 'no rows')
eq(E.plan({ { key = 'pet', options = { { text = 'None', value = '' }, { text = 'A', value = 'a' } }, current = 'a' } }, { pet = '' })[1].act, 'pet', 'dismiss the pet')
eq(E.indexOf(rows[2], 11), 2, 'indexOf')

print('outfitextras tests OK (' .. checks .. ' checks)')
if fails > 0 then os.exit(1) end
