-- Main quest balance (O551; computed, not measured): the gold of the steps against the gold an ideal hunter earns, the pace of the
-- kill and drop steps against the minutes they pay for, the items, the boss reward against the Cruel Trial.
--     cd server && luajit tools/mainquest_model.lua [--check|--table]      (also lua5.3)
-- Inputs: mainquest_config.lua (steps, minutes, items, drop numbers), embercache_config.lua income (one source of the gold per hour),
-- progression_model.lua (minutes per level, level 8 to 500: the hunting an ideal player does), trials_config.lua (the Cruel Trial's
-- first clear: 4,000 x level x tier gold, README "Vocation Trials"), store_balance_config.lua (no coin item).
-- Limits are in mainquest_config.lua (`reward.maxShareOfHunting`) and below.
ChaosProgressionLib = true
local PM = dofile("tools/progression_model.lua")
ChaosProgressionLib = nil
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/mainquest_core.lua")
local K = ChaosMainQuestCore
local cfg = K.cfg()
local income = dofile(cfg.reward.incomeFrom).income

local env = PM.load({})
local curve = PM.curve(env, 500)

local LIMITS = {
	paceMin = 0.5, paceMax = 2.2, -- the minutes a kill / drop step takes at killsPerMinute, over the minutes it pays for
	itemMax = 4, -- orbs in one step
	allowed = {[29856] = true, [29851] = true, [29857] = true, [24692] = true, [32256] = true}, -- Upheaval, Awakening, Fate, Sockets, Whetstone
	bossAtMostCruelFirstClear = 4000 * 500 * 2
}

local problems = {}
local function bad(text) problems[#problems + 1] = text end

local total, byChapter = 0, {}
for i, s in ipairs(cfg.steps) do
	local g = K.gold(cfg, income, s)
	total = total + g
	byChapter[s.ch] = (byChapter[s.ch] or 0) + g
	for _, c in ipairs(s.conds) do
		if c.c == "count" then
			local minutes = c.target / cfg.drop.killsPerMinute
			if c.item then
				minutes = math.max(minutes, 1 / K.dropChance(cfg, s.mins, c.target) * c.target / cfg.drop.killsPerMinute)
			end
			local ratio = minutes / math.max(1, s.mins)
			if ratio < LIMITS.paceMin or ratio > LIMITS.paceMax then
				bad(string.format("step %d %s: %.1f minutes of %s against %d paid (ratio %.2f)", i, s.key, minutes, c.label, s.mins, ratio))
			end
		end
	end
	for _, it in ipairs(s.items) do
		if not LIMITS.allowed[it[1]] then bad("step " .. s.key .. ": item " .. it[1] .. " is not a cheap orb") end
		if it[2] > LIMITS.itemMax then bad("step " .. s.key .. ": more than " .. LIMITS.itemMax .. " of an item") end
	end
end

local ideal = 0
for L = 8, 499 do
	ideal = ideal + (curve[L].min / 60) * K.income(income, L)
end
total = total + cfg.boss.reward.gold -- the boss reward counts: the whole quest is held to the share
local share = total / ideal
if share > cfg.reward.maxShareOfHunting then
	bad(string.format("the quest (steps and boss) pays %.1f%% of the ideal hunting gold (limit %.0f%%)", share * 100, cfg.reward.maxShareOfHunting * 100))
end
if cfg.boss.reward.gold > LIMITS.bossAtMostCruelFirstClear then
	bad("the boss pays more than the Cruel Trial's first clear")
end
for _, it in ipairs(cfg.boss.reward.items) do
	if not LIMITS.allowed[it[1]] then bad("the boss reward holds a store or coin item") end
end
-- no coin: nothing in the config names Chaos Coins
local f = assert(io.open("data/scripts/chaos/mainquest_config.lua"))
local src = f:read("*a")
f:close()
if src:lower():find("chaos coin", 1, true) or src:find("coins", 1, true) then bad("the quest config names coins") end

local mode = arg and arg[1]
if mode == "--table" or mode ~= "--check" then
	print("| Chapter | Steps | Gold |")
	print("|---|---:|---:|")
	for _, ch in ipairs(cfg.chapters) do
		local n = 0
		for _, s in ipairs(cfg.steps) do if s.ch == ch.n then n = n + 1 end end
		print(string.format("| %d %s | %d | %s |", ch.n, ch.name.en, n, K.int(byChapter[ch.n] or 0)))
	end
	print(string.format("total with the boss reward %s gold = %.1f%% of the %s gold of an ideal hunt from level 8 to 500 (%.1f hours)", K.int(total), share * 100,
		K.int(ideal), PM.hours(curve, 8, 500)))
end
if #problems > 0 then
	for _, p in ipairs(problems) do io.stderr:write("mainquest_model: " .. p .. "\n") end
	os.exit(1)
end
if mode == "--check" then print("mainquest_model: ok") end
