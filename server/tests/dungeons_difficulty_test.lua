-- Run from the server/ folder: luajit tests/dungeons_difficulty_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Dungeon difficulty (dungeons_difficulty.lua): the scaling functions, and that the numbers are exactly the ones the
-- client's difficulty panel shows (client/overlay/modules/game_dungeons/dungeons.otui).
local D = dofile("data/scripts/chaos/dungeons_difficulty.lua")

local fails, checks = 0, 0
local function eq(a, b, what)
	checks = checks + 1
	if a ~= b then
		fails = fails + 1
		print("FAIL " .. what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end

-- the client's panel: the six DifficultyInfo texts in order
local f = io.open("../client/overlay/modules/game_dungeons/dungeons.otui", "r")
if f then
	local text = f:read("*a")
	f:close()
	local panels = {}
	for t in text:gmatch("DifficultyInfo%s+!text:%s*tr%('([^']*)'%)") do -- the panel texts go through tr() (pt-BR)
		panels[#panels + 1] = t:gsub("\\n", "\n")
	end
	eq(#panels, #D.levels, "six panels in the client")
	for i, t in ipairs(panels) do
		eq(D.panelText(i), t, "difficulty " .. i .. " matches the client panel")
	end
else
	print("(client overlay not found: the panel comparison is skipped)")
end

-- scaling
eq(D.health(1000, 1), 1000, "normal health")
eq(D.health(1000, 2), 2000, "hard health x2")
eq(D.health(1000, 6), 13000, "difficulty 6 health x13")
eq(D.health(0, 3), 1, "health at least 1")
eq(D.damage(-100, 1), -100, "normal damage")
eq(D.damage(-100, 2), -130, "hard damage x1.3")
eq(D.damage(-333, 3), -633, "difficulty 3 damage x1.9")
eq(D.damage(250, 6), 1500, "positive damage keeps the sign")
eq(D.experience(1000, 1), 1000, "normal experience")
eq(D.experience(1000, 2), 1750, "hard experience +75%")
eq(D.experience(1000, 6), 5000, "difficulty 6 experience +400%")
eq(D.extraLootChance(10000, 1), 0, "no extra loot at normal")
eq(D.extraLootChance(10000, 2), 0, "no extra loot at hard")
eq(D.extraLootChance(10000, 3), 1500, "difficulty 3 +15% of the chance")
eq(D.extraLootChance(100000, 6), 60000, "difficulty 6 +60%")
eq(D.of(0), D.levels[1], "difficulty clamped up")
eq(D.of(99), D.levels[6], "difficulty clamped down")
eq(select(2, D.of("3")), 3, "difficulty from a string")

-- gold: +75% of 10 coins = 7.5 -> 7 or 8, about half each
local seed = 5
local function rand(a, b)
	seed = (seed * 16807) % 2147483647
	return a + seed % (b - a + 1)
end
local eights, n = 0, 4000
for _ = 1, n do
	local x = D.extraGold(10, 2, rand)
	eq(x == 7 or x == 8, true, "extra gold 7 or 8")
	if x == 8 then
		eights = eights + 1
	end
end
eq(math.abs(eights / n - 0.5) < 0.04, true, "the fraction is a chance (" .. eights / n .. ")")
eq(D.extraGold(10, 1, rand), 0, "no extra gold at normal")
eq(D.extraGold(100, 6, rand), 400, "difficulty 6 +400% gold")

-- a boss with its own curve (the Hollow Vault): its percents, not the table's; without a curve the table's
local vault = {100, 125, 150, 175, 200, 225}
eq(D.bossHealth(1000000, 1, vault), 1000000, "boss curve difficulty 1")
eq(D.bossHealth(1000000, 3, vault), 1500000, "boss curve difficulty 3")
eq(D.bossHealth(1000000, 6, vault), 2250000, "boss curve difficulty 6")
eq(D.bossHealth(1000000, 9, vault), 2250000, "boss curve clamped")
eq(D.bossHealth(1000000, 6, nil), 13000000, "no curve: the table's 1300%")

print(string.format("dungeons difficulty tests: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
