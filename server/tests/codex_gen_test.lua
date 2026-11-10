-- Run from the server/ folder: luajit tests/codex_gen_test.lua (and lua5.3; CI runs both)
-- The Codex generator (tools/gen_codex_data.lua): its pure helpers (numbers, percent texts, the Lua writer, modifier
-- value texts), then the whole build on the real data files: every tab filled, ids unique, every link and shared
-- section resolvable, tier tables complete, only our own orb names in the texts, and the output byte-stable.

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	if not v then
		error(m or "expected true", 2)
	end
end

CODEX_GEN_NO_MAIN = true
local Gen = dofile("tools/gen_codex_data.lua")
local checks = 0
local function count()
	checks = checks + 1
end

-- ---------------------------------------------------------------- numbers and texts
eq(Gen.num(2), "2", "whole"); count()
eq(Gen.num(4 / 2), "2", "whole float (Lua 5.3 writes 2.0)"); count()
eq(Gen.num(0.25), "0.25", "decimal"); count()
eq(Gen.num(1 / 3), "0.3333", "four decimals"); count()
eq(Gen.num(-3), "-3", "negative"); count()
eq(Gen.per10k(25), "0.25%", "per 10000"); count()
eq(Gen.per10k(4000), "40%", "per 10000 whole"); count()
eq(Gen.per10k(4), "0.04%", "per 10000 small"); count()
eq(Gen.share(1, 3), "33.3%", "share"); count()
eq(Gen.share(5, 0), "0%", "share of nothing"); count()
eq(Gen.range(1, 1), "1", "range same"); count()
eq(Gen.range(1, 3), "1-3", "range"); count()
eq(Gen.seconds(1500), "1.5 s", "seconds"); count()
eq(Gen.signed(3), "+3", "signed plus"); count()
eq(Gen.signed(-3), "-3", "signed minus (a unique with a negative absorb)"); count()
eq(Gen.quote('a "b"\\c\nd'), '"a \\"b\\"\\\\c\\nd"', "quote"); count()

-- ---------------------------------------------------------------- modifier value texts
local pct = {label = "Attack Speed", fmt = "pct", cap = 15}
local flat = {label = "Thorns", fmt = "flat", cap = 250}
local less = {label = "Damage Taken from Monsters", fmt = "less", cap = 12}
local execute = {label = "Execute", text = "Executes Monsters below %d%% Health", cap = 10}
local regen = {label = "Health Regeneration", text = "Health Regeneration +%d per Second", cap = 120}
eq(Gen.chaosValue(pct, 1, 3), "+1-3%", "pct value"); count()
eq(Gen.chaosValue(flat, 4, 8), "+4-8", "flat value"); count()
eq(Gen.chaosValue(less, 1, 2), "-1-2%", "less value"); count()
eq(Gen.chaosValue(execute, 6, 8), "6-8%", "text percent value"); count()
eq(Gen.chaosValue(regen, 25, 40), "+25-40", "text flat value"); count()
eq(Gen.chaosLine(pct, 11, 14), "Attack Speed +11-14%", "pct line"); count()
eq(Gen.chaosLine(less, 4, 6), "Damage Taken from Monsters -4-6%", "less line"); count()
eq(Gen.chaosLine(execute, 6, 8), "Executes Monsters below 6-8% Health", "text line"); count()
eq(Gen.capValue(pct), "15%", "pct cap"); count()
eq(Gen.capValue(flat), "250", "flat cap"); count()
eq(Gen.capValue(less), "12%", "less cap"); count()
eq(Gen.capValue(execute), "10%", "text percent cap"); count()
eq(Gen.capValue(regen), "120", "text flat cap"); count()

-- ---------------------------------------------------------------- the Lua writer
local t = {name = "x", id = "a", zeta = 1, alpha = {1, 2, {3, "q"}}, [5] = true}
local src = Gen.serialize(t, "")
eq(src, Gen.serialize(t, ""), "stable"); count()
ok(src:find("^{id = \"a\", name = \"x\"") ~= nil, "id and name first: " .. src); count()
local back = (loadstring or load)("return " .. src)()
eq(back.alpha[3][2], "q", "round trip nested"); count()
eq(back[5], true, "round trip number key"); count()
eq(Gen.inline({1, {2, 3}}), "{1, {2, 3}}", "inline"); count()
local long = {}
for i = 1, 60 do
	long[i] = "entry " .. i
end
ok(Gen.serialize({list = long}, ""):find("\n") ~= nil, "long tables break into lines"); count()

-- ---------------------------------------------------------------- the build on the real data
local D = Gen.load()
local data = Gen.build(D)
local text = Gen.render(data)
eq(text, Gen.render(Gen.build(D)), "byte-stable output"); count()
local loaded = (loadstring or load)(text)()
eq(type(loaded), "table", "the output loads"); count()
eq(#loaded.tabs, 11, "eleven tabs (the last is Lore, docs/CONTENT.md)"); count()
eq(loaded.tabs[11].id, "lore", "the lore tab"); count()

local tabs, ids, entries = {}, {}, 0
for _, tab in ipairs(loaded.tabs) do
	tabs[tab.id] = tab
	ok(#tab.entries > 0, "tab " .. tab.id .. " has entries"); count()
	for _, e in ipairs(tab.entries) do
		ok(type(e.id) == "string" and e.id ~= "", "entry id"); count()
		ok(not ids[e.id], "unique id " .. e.id); count()
		ids[e.id] = e
		ok(type(e.name) == "string" and e.name ~= "", "name of " .. e.id); count()
		ok(type(e.sections) == "table" and #e.sections > 0, "sections of " .. e.id); count()
		entries = entries + 1
	end
	for _, f in ipairs(tab.filters) do
		ok(f.match == "eq" or f.match == "has" or f.match == "max" or f.match == "ilvl", "filter match " .. f.key); count()
		eq(f.options[1][1], "", "first option is 'any' (" .. f.key .. ")"); count()
	end
end

-- counts follow the data
local C, M = D.C, D.M
local nAffix, nPower = 0, 0
for _, a in ipairs(C.affixes()) do
	if a.noRoll then
		-- club and axe: shown as the one Melee modifier (sword), no entry of their own
	elseif a.def and M.isPower(a.def) then
		nPower = nPower + 1
	else
		nAffix = nAffix + 1
	end
end
eq(#tabs.modifiers.entries, nAffix, "every modifier"); count()
eq(#tabs.powers.entries, nPower, "every power"); count()
eq(#tabs.powers.entries, #D.P.defs, "powers = chaos_powers.lua"); count()
eq(#tabs.uniques.entries, #D.uniques, "every unique"); count()
eq(#tabs.sets.entries, #D.itemSets.sets, "every item set"); count()
eq(#tabs.supports.entries, #D.S.config.supports, "every support"); count()
eq(#tabs.gems.entries, #D.G.config.types + 1, "every gem type and the sockets page"); count()
eq(#tabs.rift.entries, #D.rift.mods + 3, "every rift modifier, keys, tiers, omens"); count()
eq(#tabs.materials.entries, #D.prof.materials + 1, "every profession material and the professions page"); count()
for _, orb in ipairs(C.config.orbs) do
	ok(ids["orb:" .. orb.key], "orb page " .. orb.key); count()
end
for _, r in ipairs(D.O.config.renames) do
	local found = false
	for _, e in ipairs(tabs.orbs.entries) do
		if e.name == r.name then
			found = true
		end
	end
	ok(found, "currency page " .. r.name); count()
end

-- tiers: eight per modifier and power, in order, with the value texts
for _, tab in ipairs({tabs.modifiers, tabs.powers}) do
	for _, e in ipairs(tab.entries) do
		eq(#e.tiers, M.config.maxTier, "tiers of " .. e.id); count()
		eq(#e.tv, M.config.maxTier, "tier texts of " .. e.id); count()
		ok(e.f.side == "prefix" or e.f.side == "suffix", "side of " .. e.id); count()
		ok(#e.f.kind > 0, "kinds of " .. e.id); count()
		local tierSection
		for _, s in ipairs(e.sections) do
			if s.tiers then
				tierSection = s
			end
		end
		ok(tierSection and #tierSection.rows == M.config.maxTier, "tier table of " .. e.id); count()
	end
end
local speed = ids["mod:chaos_mod_attackspeed"]
eq(speed.side, "suffix", "attack speed side"); count()
eq(speed.tv[8], "+26-27%", "attack speed T8"); count()
eq(speed.f.kind[1], "weapon", "attack speed on weapons"); count()
eq(#speed.f.kind, 1, "attack speed only on weapons"); count()
-- O461: the critical pair is two modifiers, each with its own page and numbers
local crit = ids["mod:rarity_criticalhitchance"]
eq(crit.name, "Critical Strike Chance", "critical chance name"); count()
eq(crit.tv[8], "+7-8%", "critical chance T8, in points"); count()
local critDmg = ids["mod:rarity_criticalhitamount"]
eq(critDmg.name, "Critical Strike Damage", "critical damage name"); count()
eq(critDmg.tv[8], "+35-38%", "critical damage T8"); count()
eq(critDmg.f.kind[1] ~= nil, true, "kinds of the critical damage"); count()
eq(ids["mod:chaos_mod_lifeleech"].tv[8], "+1-1.2%", "the Lua life leech in percent: T8 10-12 tenths"); count()
eq(ids["mod:chaos_mod_goldfind"], nil, "Gold Find left the roll pool: no page"); count()
eq(ids["mod:chaos_mod_manacost"], nil, "Mana Cost Reduction left the roll pool: no page"); count()
eq(ids["mod:rarity_miningskill"], nil, "the six crafting professions left the roll pool: no page"); count()
eq(loaded.tierWindow, M.config.maxTier, "every tier rolls: the window as wide as the table"); count()
eq(#ids["mod:rarity_physicalabsorb"].f.kind, 2, "O464: the physical reduction rolls on armour and shields only"); count()
eq(ids["mod:rarity_physicalabsorb"].f.kind[1] .. "," .. ids["mod:rarity_physicalabsorb"].f.kind[2], "shield,armor", "O464: shield and armour"); count()
eq(ids["mod:rarity_fireabsorb"], nil, "O464: the per-type absorbs left the roll pool: no page"); count()
eq(#ids["mod:chaos_mod_fireres"].f.kind, 7, "O464: a resistance rolls on seven kinds"); count()
eq(ids["mod:chaos_mod_fireres"].tv[8], "+46-48%", "O464: fire resistance T8"); count()
eq(ids["mod:chaos_mod_allres"].tv[1], "+3-4%", "O464: all resistances T1"); count()
eq(ids["mod:chaos_mod_armour"].tv[8], "+45-52", "O464: armour T8, flat"); count()
ok(ids["basics:defence"] ~= nil, "O464: the page How you defend"); count()

-- links and shared sections resolve
for id, e in pairs(ids) do
	for _, s in ipairs(e.sections) do
		if s.ref then
			ok(loaded.shared[s.ref], "shared section " .. s.ref .. " of " .. id); count()
			s = loaded.shared[s.ref]
		end
		for _, l in ipairs(s.links or {}) do
			ok(l == "" or ids[l], "link " .. tostring(l) .. " of " .. id); count()
		end
		if s.rows then
			ok(s.cols and #s.cols > 0, "columns of " .. id); count()
			ok(s.w and #s.w == #s.cols, "widths of " .. id); count()
			for _, row in ipairs(s.rows) do
				eq(#row, #s.cols, "cells of a row of " .. id .. " / " .. tostring(s.h)); count()
			end
			if s.links then
				eq(#s.links, #s.rows, "a link per row of " .. id); count()
			end
		end
	end
end

-- only our own names in what the player reads (ids and links may keep the old internal keys)
local OLD = {"transmutation", "augmentation", "regal", "vaal", "exalted", "chaos orb", "divine orb", "angel orb",
	"kalandra", "alchemy", "annulment", "scouring", "orb of chance"}
local function visible(v, path)
	if type(v) == "string" then
		local low = v:lower()
		for _, w in ipairs(OLD) do
			ok(not low:find(w, 1, true), "old name '" .. w .. "' in " .. path .. ": " .. v)
		end
		count()
	elseif type(v) == "table" then
		for k, x in pairs(v) do
			if k ~= "id" and k ~= "links" and k ~= "ref" then
				visible(x, path .. "." .. tostring(k))
			end
		end
	end
end
visible(loaded.tabs, "tabs")
visible(loaded.shared, "shared")

-- the orb pages name their sources from the configs
local upheaval = ids["orb:chaos"]
eq(upheaval.name, "Orb of Upheaval", "renamed orb"); count()
local sources
for _, s in ipairs(upheaval.sections) do
	if s.h == "Sources" then
		sources = s
	end
end
ok(sources and #sources.rows >= 5, "Upheaval sources"); count()
eq(sources.rows[1][1], "Monster drops", "drops first"); count()
ok(sources.rows[1][2]:find("Legendary 40%%") ~= nil, "loot_config chance: " .. sources.rows[1][2]); count()

-- a unique: stats from the specs, drop chances by tier
local soul = ids["unique:8209"]
ok(soul.sub:find("Attack 52") ~= nil, "unique stats " .. soul.sub); count()
eq(soul.f.level, 120, "unique level"); count()
eq(soul.f.kind[1], "weapon", "unique kind"); count()

-- ---------------------------------------------------------------- uniques explain themselves (O467)
do
	-- the steps of the Level filter come from the levels (10s to 100, 50s to 400, 100s to 1000, 200s above; the last is the top)
	local steps = Gen.levelSteps({10, 20, 30, 40, 55, 70, 90, 120, 180, 260, 410, 900, 1400, 2400}, 4)
	eq(table.concat(steps, ","), "40,90,500,2400", "level steps: quartiles (40, 90, 410) rounded up, the top as it is"); count()
	eq(table.concat(Gen.levelSteps({5, 5, 5}, 4), ","), "5", "level steps: one level, one step"); count()
	eq(#Gen.levelSteps({}, 4), 0, "level steps: no levels"); count()

	-- the Level filter of the Uniques tab reaches the highest unique level and every unique is under its top step
	local top, lowest = 0, math.huge
	for _, e in ipairs(tabs.uniques.entries) do
		top, lowest = math.max(top, e.f.level), math.min(lowest, e.f.level)
	end
	local levelFilter, classFilter
	for _, f in ipairs(tabs.uniques.filters) do
		if f.key == "level" then levelFilter = f end
		if f.key == "class" then classFilter = f end
	end
	ok(levelFilter ~= nil and classFilter ~= nil, "the Uniques tab has a Level and a Class filter"); count()
	eq(tonumber(levelFilter.options[#levelFilter.options][1]), top, "the last Level step is the highest unique level"); count()
	ok(top >= 2000, "the uniques really reach level 2000 and more: " .. top); count()
	local prev = 0
	for i = 2, #levelFilter.options do
		local v = tonumber(levelFilter.options[i][1])
		ok(v > prev, "Level steps rise: " .. v); count()
		prev = v
	end
	ok(#levelFilter.options >= 6, "several Level steps"); count()
	ok(tonumber(levelFilter.options[2][1]) >= lowest, "the first step is above the lowest level"); count()

	-- the Class filter: every unique has the class lines of its passive; the options are the seven lines
	eq(#classFilter.options, 8, "any class and the seven lines"); count()
	local P, PC = D.passives, ChaosUniquePassivesCore
	for _, e in ipairs(tabs.uniques.entries) do
		local id = tonumber(e.id:match("^unique:(%d+)$"))
		local want = {}
		for _, key in ipairs(P.lineOrder) do
			if PC.worksFor(P, PC.entry(P, id), key) then want[#want + 1] = key end
		end
		eq(table.concat(e.f.class, ","), table.concat(want, ","), "class lines of " .. e.id); count()
		ok(#want > 0, "a unique's power works for some class: " .. e.id); count()
	end
	eq(table.concat(ids["unique:8209"].f.class, ","), "warrior,thief,necromancer", "Soulreaper: Warrior, Thief, Necromancer"); count()
	-- the Item row says it: "Every class" when the power lists all seven lines
	local everyClass = 0
	for _, e in ipairs(tabs.uniques.entries) do
		for _, s in ipairs(e.sections) do
			if s.h == "Item" then
				local row
				for _, r in ipairs(s.rows) do
					if r[1] == "Power works for" then row = r end
				end
				ok(row ~= nil, "Power works for row of " .. e.id); count()
				if #e.f.class == 7 then
					eq(row[2], "Every class", "all seven lines: Every class"); count()
					everyClass = everyClass + 1
				end
			end
		end
	end
	ok(everyClass >= 5, "some uniques work for every class: " .. everyClass); count()

	-- the Level window row: exactly the leveling uniques with a monster list, with the levels of unique_window_core.lua
	local W, withRow, without = ChaosUniqueWindow, 0, 0
	for _, u in ipairs(D.uniques) do
		local sec
		for _, s in ipairs(ids["unique:" .. u.id].sections) do
			if s.h == "Sources" then sec = s end
		end
		local row
		for _, r in ipairs(sec.rows) do
			if r[1] == "Level window" then row = r end
		end
		local lo, hi = W.levels(D.loot.unique.openLevel, u)
		if lo and type(u.monsters) == "table" and #u.monsters > 0 then
			ok(row ~= nil, "Level window row of " .. u.name); count()
			ok(row[2]:find(string.format("monster of level %d to %d ", Chaos.huntingLevel(lo), Chaos.huntingLevel(hi)), 1, true) ~= nil,
				"its levels: " .. row[2]); count()
			withRow = withRow + 1
		else
			ok(row == nil, "no Level window row for " .. u.name); count()
			without = without + 1
		end
	end
	ok(withRow > 50 and without > 20, "both kinds exist: " .. withRow .. " with a window row, " .. without .. " without"); count()

	-- the Basics page: its numbers are the configs' (never typed in the generator)
	local page = ids["basics:uniques"]
	ok(page ~= nil, "the Basics page Uniques"); count()
	local words = {}
	for _, s in ipairs(page.sections) do
		for _, p in ipairs(s.p or {}) do words[#words + 1] = p end
	end
	local all = table.concat(words, "\n")
	local lu = D.loot.unique
	ok(all:find("At most " .. P.maxActive .. " unique powers work at once", 1, true) ~= nil, "the limit of active powers"); count()
	ok(all:find("level " .. lu.openLevel.maxItemLevel .. " or lower", 1, true) ~= nil, "the leveling unique's item level limit"); count()
	ok(all:find("from " .. math.floor((1 - lu.openLevel.below) * 100 + 0.5) .. "% of its level up to " .. Gen.num(lu.openLevel.above) ..
		" times its level plus " .. lu.openLevel.aboveFlat, 1, true) ~= nil, "the level window of the config"); count()
	ok(all:find(D.uniquePace.target.min .. " to " .. D.uniquePace.target.max .. " kills", 1, true) ~= nil, "the pace of the config"); count()
	ok(all:find("at " .. math.floor(lu.open.mult * 100 + 0.5) .. "% of its chance", 1, true) ~= nil, "the endgame rule"); count()
	ok(all:find("kill number " .. D.retention.firstUnique.kills, 1, true) ~= nil, "the first unique's kill"); count()
	ok(all:find("level " .. D.retention.firstUnique.maxLevel .. " or lower finds", 1, true) ~= nil, "the first unique's level"); count()
	ok(all:find("Ctrl", 1, true) and all:find("Alt", 1, true) and all:find("Open in Codex", 1, true), "Ctrl, Alt and the Codex entry"); count()

	-- every unique with a drop entry has a page the tooltip's right-click entry can open (T.codexId)
	for id in pairs(ChaosUniqueById) do
		ok(ids["unique:" .. id] ~= nil, "a Codex page for the unique " .. id); count()
	end
end

print(string.format("codex_gen_test: %d checks OK (%d entries)", checks, entries))
