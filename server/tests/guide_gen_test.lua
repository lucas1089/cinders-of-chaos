-- cd server && luajit tests/guide_gen_test.lua && lua5.3 tests/guide_gen_test.lua
-- tools/gen_guide_data.lua (O373): the level of a "who" sentence, the top menu parser and the entries modules add
-- themselves, the order of the guide (first steps, then by level, then any level) on synthetic data, and on the real
-- data: every card in one place only, the steps from guide_config.lua, levels rising, the rift card's menu path.
GUIDE_GEN_NO_MAIN = true
local Guide = dofile("tools/gen_guide_data.lua")

local fails, count = 0, 0
local function eq(a, b, what)
	count = count + 1
	if a ~= b then
		print("FAIL " .. what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
		fails = fails + 1
	end
end

-- the level of a sentence
eq(Guide.levelOfText("Level 100+. Go alone."), 100, "Level N+")
eq(Guide.levelOfText("World boss: level 300+, up to 40 players."), 300, "level N+ inside")
eq(Guide.levelOfText("Every player from level 8. You need the tool."), 8, "from level N")
eq(Guide.levelOfText("Every player."), nil, "no level")

-- the menu
local src = table.concat({
	"local CATEGORIES = {",
	"  { id = 'character', text = 'Character', icon = 'skills', entries = {",
	"    entry('Spellbook',       'spells',      { modules = { 'game_spellbook' }, fns = { 'toggle' }, key = 'Alt+S' }),",
	"    entry('More',            'inventory',   { sub = {",
	"      entry('Inventory',          'inventory',   { modules = { 'game_inventory' }, fns = { 'toggle' } }),",
	"    } }),",
	"  } },",
	"  { id = 'adventure', text = 'Adventure', icon = 'x', entries = {",
	"    entry('Rifts',           'dungeons',    info('rift')),",
	"  } },",
	"}",
	"entry('Stray', 'x', { modules = { 'game_stray' } })"
}, "\n")
local menu = Guide.parseMenu(src)
eq(#menu, 3, "three entries, the sub-menu head and the stray line left out")
eq(menu[1].path, "Character > Spellbook", "path")
eq(menu[1].module, "game_spellbook", "module")
eq(menu[2].path, "Character > More > Inventory", "sub-menu path")
eq(menu[3].module, nil, "an info() entry has no module")
eq(menu.categories.adventure, "Adventure", "category ids")
local added = Guide.addedEntry("pcall(api.addEntry, 'social',\n  { text = 'Mentors', icon = 'vip', modules = { 'game_mentor' }, fns = { 'toggle' } })",
	"game_mentor", menu.categories)
eq(added, nil, "an unknown category id gives nothing")
menu.categories.social = "Social"
added = Guide.addedEntry("pcall(api.addEntry, 'social',\n  { text = 'Mentors', icon = 'vip', modules = { 'game_mentor' }, fns = { 'toggle' } })",
	"game_mentor", menu.categories)
eq(added and added.path, "Social > Mentors", "an entry a module adds")

-- the order on synthetic data
local cards = {
	{key = "a", title = {en = "A", pt = "A"}, window = "game_spellbook", rows = {{id = "who", en = "Every player.", pt = "x"}}},
	{key = "b", title = {en = "B", pt = "B"}, unlocks = {"ub"}, rows = {{id = "who", en = "Level 5+.", pt = "x"}}},
	{key = "c", title = {en = "C", pt = "C"}, rows = {{id = "who", en = "Level 50+.", pt = "x"}}},
	{key = "d", title = {en = "D", pt = "D"}, rows = {{id = "who", en = "Level 20+.", pt = "x"}}},
	{key = "e", title = {en = "E", pt = "E"}, rows = {{id = "what", en = "Something.", pt = "x"}}}
}
local unlocks = {{key = "ub", level = 30, menu = "Rifts", title = {"B", "B"}, why = {{"one", "um"}, {"two", "dois"}}}}
local G = {intro = {en = "i", pt = "i"}, headings = {}, steps = {{card = "a", tip = {"t", "t"}}}, words = {c = {"w", "p"}}}
local d = Guide.build(cards, unlocks, menu, G)
eq(#d.steps, 1, "one step")
eq(d.steps[1].card, "a", "the step")
eq(d.cards[1].menu, "Character > Spellbook", "menu by window")
eq(d.cards[2].level, 30, "the unlock level wins over the sentence")
eq(d.cards[2].menu, "Adventure > Rifts", "menu by the unlock entry's text")
eq(d.levels[1].level, 20, "levels rise: 20")
eq(d.levels[2].level, 30, "then 30")
eq(d.levels[3].level, 50, "then 50")
eq(d.anytime[1], "e", "no level: any level")
eq(d.cards[3].words.en, "w", "search words")
eq(d.unlocks[1].card, "b", "the unlock entry's card")
eq(d.unlocks[1].why.pt, "um dois", "the two lines joined")
eq(pcall(Guide.build, cards, unlocks, menu, {steps = {{card = "zz", tip = {"t", "t"}}}}), false, "an unknown step stops the run")

-- the real data (run from server/)
local real = Guide.make()
local placed = {}
local function place(k, where)
	eq(placed[k], nil, "card " .. k .. " placed once (" .. where .. ")")
	placed[k] = where
end
for _, s in ipairs(real.steps) do place(s.card, "steps") end
local last = 0
for _, l in ipairs(real.levels) do
	eq(l.level > last, true, "levels rise at " .. l.level)
	last = l.level
	for _, k in ipairs(l.cards) do place(k, "level " .. l.level) end
end
for _, k in ipairs(real.anytime) do place(k, "any level") end
for _, c in ipairs(real.cards) do
	eq(placed[c.key] ~= nil, true, "card " .. c.key .. " is in the guide")
	if c.key == "rift" then
		eq(c.menu, "Adventure > Rifts", "the rift card's menu")
		eq(c.level, 100, "the rift card's level")
	end
end
local G2 = dofile("tools/guide_config.lua")
eq(#real.steps, #G2.steps, "every step of guide_config.lua")
local web = Guide.renderWeb(real)
eq(web:find("\226\128\148", 1, true), nil, "no em dash in the website data")
eq(Guide.renderClient(real):find("^%-%- GENERATED") ~= nil, true, "the client file says it is generated")

print(("guide_gen_test: %d of %d checks failed"):format(fails, count))
if fails > 0 then
	os.exit(1)
end
