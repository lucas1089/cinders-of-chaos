-- tools/gold_faucets_model.lua (O754): every gold faucet at most `limit` x the one gold curve at the levels it is played.
-- Run from server/: luajit tests/gold_faucets_test.lua (also lua5.3).
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

ChaosGoldFaucetsLib = true
local M = dofile("tools/gold_faucets_model.lua")
ChaosGoldFaucetsLib = nil
local BC = dofile("data/scripts/chaos/gold_faucets_balance_config.lua")

-- the curve reader
ok(M.hunt(1000) == 1550000, "the curve at 1000")
ok(M.hunt(400) == (619000 + 1197000) / 2, "linear between the points")
ok(M.hunt(9000) == 1970000, "flat beyond the last point")
ok(M.fmt(1234567) == "1,234,567", "thousands")

local rows = M.build()
ok(#rows > 100, "the faucets: " .. #rows)
local groups, names = {}, {}
for _, r in ipairs(rows) do
	groups[r.group] = true
	names[r.name:match("^(%a+)")] = true
	ok(r.ratio <= BC.limit + 1e-9, string.format("%s at level %d: %.2f x the curve", r.name, r.level, r.ratio))
	ok(r.own >= 0 and r.kills >= 0 and r.hunt > 0, "a row's numbers: " .. r.name)
end
for _, g in ipairs({"rift", "map", "run", "event", "hunt"}) do
	ok(groups[g], "group " .. g)
end
for _, n in ipairs({"Rift", "Tier", "Greater", "Waystone", "Ember", "Infinity", "The", "World", "Invasion", "Bounty",
	"Vocation", "Guild", "Treasure"}) do
	ok(names[n], "faucet " .. n)
end

-- the tier 15 loop counts the Omen, Ascended and Cinderheart kills its drops open
local own, kills, k = M.loop(1025, 1)
ok(own > 0 and kills > 0 and kills < BC.rift.kills, "the loop: gold and kills")
ok(k.omens > 0 and k.asc > 0 and math.abs(k.cinder - k.asc / 3) < 1e-9, "the loop: Omen, Ascended, Cinderheart kills")

print(string.format("gold_faucets_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
