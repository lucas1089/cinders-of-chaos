-- Run from the server/ folder: luajit tests/wiki_unique_effort_test.lua (and lua5.3; CI runs both)
-- O467: the website wiki's "Expected effort" row of a unique (tools/gen_wiki_data.lua W.uniqueEffort). A leveling unique that
-- lists monsters also drops from any other monster near its level (loot_config.lua unique.openLevel, unique_window_core.lua):
-- the effort used to count the listed monsters only. It now says the window too, from the table the Codex's Level window row
-- reads (Gen.uniqueWindow). Entries the rule does not reach (boss-only, endgame, no monster list) keep the old text.
local checks = 0
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "assertion failed", 2)
	end
end

WIKI_GEN_NO_MAIN = true
local W = dofile("tools/gen_wiki_data.lua")
WIKI_GEN_NO_MAIN = nil
CODEX_GEN_NO_MAIN = true
local Gen = dofile("tools/gen_codex_data.lua")
CODEX_GEN_NO_MAIN = nil
local D = Gen.load()

local withWindow, plain = 0, 0
for _, u in ipairs(D.uniques) do
	local text = W.uniqueEffort(D, u)
	local win = Gen.uniqueWindow(D, u)
	if win then
		withWindow = withWindow + 1
		ok(text:find(string.format("Any other monster of level %d to %d drops it too: about 1 in %s %s kills at a level %d monster",
			win.lo, win.hi, Gen.num(win.n), win.tier, win.level), 1, true), "window text of " .. u.name .. ": " .. tostring(text))
		ok(text:find("of the listed monsters.", 1, true), "the listed monsters part stays: " .. u.name)
		ok(text:sub(-1) == ".", "ends with a full stop: " .. u.name)
	else
		plain = plain + 1
		ok(text == nil or not text:find("Any other monster of level", 1, true), "no window text for " .. u.name)
	end
end
ok(withWindow > 50 and plain > 20, "both kinds: " .. withWindow .. " with a window, " .. plain .. " without")

-- a worked example: a level 100 entry with a monster list, rare or stronger, chance 10 per 10000 (curve 2 at monster level 100)
do
	local u = {id = 1, name = "Example", level = 100, minTier = "rare", chance = 10, monsters = {"rat"}}
	local lu = D.loot.unique
	local saved = lu.openLevel.mult
	lu.openLevel.mult = {{1, 2}}
	local win = Gen.uniqueWindow(D, u)
	ok(win.lo == 90 and win.hi == 210 and win.level == 100 and win.tier == "rare", "the window of the example")
	-- 10 x tierMult.rare (2) x curve 2 = 40 per 10000: 1 in 250
	ok(win.n == 250, "1 in 250: " .. tostring(win.n))
	local text = W.uniqueEffort(D, u)
	ok(text:find("Any other monster of level 90 to 210 drops it too: about 1 in 250 rare kills at a level 100 monster", 1, true), text)
	lu.openLevel.mult = saved
end

print("wiki_unique_effort_test: " .. checks .. " checks ok")
