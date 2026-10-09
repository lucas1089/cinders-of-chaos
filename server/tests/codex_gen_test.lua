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
eq(#loaded.tabs, 8, "eight tabs"); count()

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
	if a.def and M.isPower(a.def) then
		nPower = nPower + 1
	else
		nAffix = nAffix + 1
	end
end
eq(#tabs.modifiers.entries, nAffix, "every modifier"); count()
eq(#tabs.powers.entries, nPower, "every power"); count()
eq(#tabs.powers.entries, #D.P.defs, "powers = chaos_powers.lua"); count()
eq(#tabs.uniques.entries, #D.uniques, "every unique"); count()
eq(#tabs.supports.entries, #D.S.config.supports, "every support"); count()
eq(#tabs.gems.entries, #D.G.config.types + 1, "every gem type and the sockets page"); count()
eq(#tabs.rift.entries, #D.rift.mods + 3, "every rift modifier, keys, tiers, omens"); count()
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
eq(speed.tv[8], "+11-14%", "attack speed T8"); count()
eq(speed.f.kind[1], "weapon", "attack speed on weapons"); count()
eq(#speed.f.kind, 1, "attack speed only on weapons"); count()
local crit = ids["mod:rarity_criticalhitchance"]
eq(crit.name, "Critical Hit", "critical pair name"); count()
eq(crit.tv[8], "3-5% chance, +5-7%", "critical T8 (chance two thirds)"); count()
eq(ids["mod:rarity_physicalabsorb"].f.kind[8], "other", "absorbs on any gear"); count()

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

print(string.format("codex_gen_test: %d checks OK (%d entries)", checks, entries))
