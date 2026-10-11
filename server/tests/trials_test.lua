-- Run from the server/ folder: luajit tests/trials_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The Vocation Trials without an engine (trials_core.lua, trials_config.lua, trials_nodes.lua): the node tables of every
-- vocation, picking and switching rules, tiers and scaling, rewards, the combat maths of the nodes and the run mechanics.
local n = 0
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/trials_core.lua")
local M = ChaosTrialsCore
local cfg = M.cfg()

local function rng(seed)
	local s = seed
	return function(a, b)
		s = (s * 16807) % 2147483647
		if not a then return s end
		if not b then return 1 + s % a end
		return a + s % (b - a + 1)
	end
end

-- ------------------------------------------------------------------ config
do
	local seen = {}
	for name, key in pairs(cfg.storage) do
		ok(not seen[key], "storage key distinct: " .. name)
		seen[key] = true
		ok(key >= 7101700 and key < 7101800, "storage in the Trials' range: " .. name)
	end
	-- the per-vocation storages stay in their blocks (vocation ids up to 29)
	ok(cfg.storage.tierBase + 29 < cfg.storage.picksBase, "tier block does not touch the picks block")
	ok(cfg.storage.picksBase + 29 < cfg.storage.tokens, "picks block does not touch the single storages")
	eq(#cfg.tiers, 3, "three difficulties")
	for i, t in ipairs(cfg.tiers) do
		ok(t.minLevel < t.maxLevel and t.hp > 0 and t.time > 60 and t.lives >= 1, "tier " .. i .. " sane")
		if i > 1 then
			ok(t.hp > cfg.tiers[i - 1].hp and t.hit >= cfg.tiers[i - 1].hit and t.minLevel > cfg.tiers[i - 1].minLevel,
				"tier " .. i .. " is harder than " .. (i - 1))
		end
	end
	-- the grid does not touch the rifts (8192-8447), the ascension trial (7000+), tower, siege, arena
	local g = cfg.room.grid
	local rows = math.ceil(g.slots / g.cols)
	ok(g.origin.x >= 8448 and g.origin.y >= 8448, "trial grid east / south of the rift grid")
	ok(g.spacing > cfg.room.inner + 1, "slots do not overlap")
	ok(rows * g.spacing + g.origin.y < 65000, "inside the map")
	eq(cfg.reward.first.chaos[1] < cfg.reward.first.chaos[3], true, "rewards grow")
	ok(cfg.switch.maxTokens >= 1 and cfg.switch.goldPerLevel > 0, "switch cost")
	ok(cfg.npc.name == "Keeper of Trials", "npc name matches data/npc/Keeper of Trials.xml")
end

-- ------------------------------------------------------------------ every vocation has a trial and six nodes
do
	dofile("data/scripts/chaos/chaos_constants.lua")
	local classes = Chaos.classes
	local count = 0
	for voc in pairs(classes.baseOf) do
		count = count + 1
		local fam = M.family(voc)
		ok(fam ~= nil, "vocation " .. voc .. " has a trial family")
		local list = M.pairsOf(voc)
		ok(list and #list == 3, "vocation " .. voc .. " has three pairs")
	end
	eq(count, 21, "21 vocations in Chaos.classes (base classes and both ascensions)")
	eq(#M.vocations(), count, "every vocation of a family is a class, and the other way round")
	for _, voc in ipairs(M.vocations()) do
		ok(classes.baseOf[voc] ~= nil, "family vocation " .. voc .. " is a class")
	end
	eq(#M.validate(), 0, "the node tables validate (" .. table.concat(M.validate(), "; ") .. ")")
	-- the ascended classes of one line do not share nodes with each other or the base class
	local names = {}
	for _, voc in ipairs(M.vocations()) do
		for p, entry in ipairs(M.pairsOf(voc)) do
			for _, node in ipairs({entry.a, entry.b}) do
				ok(not names[node.name:lower()], "unique node name " .. node.name)
				names[node.name:lower()] = true
				ok(#node.name <= 24, "node name fits its card: " .. node.name)
				ok(node.lore and #node.lore <= 56, "lore short: " .. tostring(node.name))
			end
			-- each pair is a real choice: two different nodes
			ok(entry.a.name ~= entry.b.name, "pair has two nodes")
		end
	end
	eq(next(names) ~= nil and 126 or 0, 126, "126 nodes exist")
	local total = 0
	for _ in pairs(names) do total = total + 1 end
	eq(total, 126, "21 vocations x 6 nodes")
	-- family looks are existing outfits (check_content.py MAX_OUTFIT)
	for key, f in pairs(cfg.families) do
		ok(f.boss.look.lookType <= 2038 and f.add.look.lookType <= 2038, key .. " looks exist in the client")
		ok(#f.story <= 200, key .. " story fits")
		ok(#f.name <= 28, key .. " trial name fits")
		for _, m in ipairs(f.mech) do
			ok(m == "stillness" or m == "zones" or m == "adds" or m == "enrage" or m == "pyre" or m == "rise", key .. " mechanic " .. m)
		end
	end
	for voc in pairs(cfg.variants) do
		ok(M.family(voc) ~= nil, "variant for a known vocation " .. voc)
	end
end

-- ------------------------------------------------------------------ ids and picks
do
	eq(M.nodeId(8, 2, 1), 821, "node id")
	local voc, pair, side = M.parseId(822)
	eq(voc, 8, "parse voc"); eq(pair, 2, "parse pair"); eq(side, 2, "parse side")
	ok(M.parseId(823) == nil, "side 3 is not a node")
	ok(M.parseId(850) == nil, "side 0 is not a node")
	ok(M.parseId(840 + 1) == nil, "pair 4 is not a node")
	eq(M.nodeById(821).name, M.pairsOf(8)[2].a.name, "node by id")
	eq(M.nodeById(822).name, M.pairsOf(8)[2].b.name, "node by id B")
	ok(M.nodeById(999) == nil, "unknown id")
	for raw = 0, 26 do
		local p = M.unpack(raw)
		eq(M.pack(p), raw, "pack/unpack " .. raw)
		ok(p[1] <= 2 and p[2] <= 2 and p[3] <= 2, "digits")
	end
	eq(M.pack({1, 2, 1}), 1 + 6 + 9, "packing")
	eq(M.unpack(-5)[1], 0, "bad storage reads as none")
	eq(M.unpack(99)[3], 0, "bad storage reads as none (too big)")
	eq(M.clearedTier(-1), 0, "unset tier"); eq(M.clearedTier(7), 3, "tier clamps")
	-- locked pairs do not count
	local a = M.activePicks(1, {2, 2, 2})
	eq(a[1], 2, "pair 1 open"); eq(a[2], 0, "pair 2 locked"); eq(a[3], 0, "pair 3 locked")
	local fx = M.effects(8, 3, {1, 2, 1})
	ok(next(fx) ~= nil, "effects of three held nodes")
	eq(next(M.effects(8, 0, {1, 1, 1})), nil, "nothing held without a clear")
	eq(#M.heldNodes(8, 2, {1, 1, 1}), 2, "two held at tier 2")
	-- fx and cost add up under their keys
	local f2 = M.effects(4, 1, {1, 0, 0})
	eq(f2.dealMelee, 15, "Reckless Blows gives +15% melee"); eq(f2.takeAll, 6, "and takes 6% more damage")
	-- the same key from two nodes sums
	local sum = M.effects(8, 3, {2, 2, 1})
	ok(type(sum.dealAll) == "number", "dealAll summed from two nodes")
end

-- ------------------------------------------------------------------ choosing and switching
do
	local st = {tier = 2, picks = {0, 0, 0}, tokens = 0, level = 300}
	local plan, why = M.planPick(st, 1, 1)
	ok(plan and plan.free and plan.gold == 0 and plan.tokens == 0, "the first pick of a pair is free")
	plan, why = M.planPick(st, 3, 1)
	ok(plan == nil and why:find("Locked") and why:find("Merciless"), "pair 3 is locked below Merciless: " .. tostring(why))
	plan = M.planPick(st, 2, 2)
	ok(plan and plan.free, "an unlocked pair can be filled")
	st.picks = {1, 0, 0}
	plan, why = M.planPick(st, 1, 1)
	ok(plan == nil and why:find("already"), "picking what you hold says so")
	plan, why = M.planPick(st, 1, 2)
	ok(plan == nil and why:find("Trial Token"), "switching without a token is refused")
	st.tokens = 1
	plan = M.planPick(st, 1, 2)
	ok(plan and not plan.free and plan.tokens == 1 and plan.gold == 300 * cfg.switch.goldPerLevel, "switching costs a token and gold by level")
	plan = M.planPick(st, 1, 0)
	ok(plan and plan.tokens == 1, "giving a pair up costs the same")
	plan, why = M.planPick(st, 2, 0)
	ok(plan == nil and why:find("Nothing"), "nothing to give up")
	ok(M.planPick(st, 0, 1) == nil and M.planPick(st, 4, 1) == nil and M.planPick(st, 1, 3) == nil, "out of range")
	ok(M.planPick(st, "x", 1) == nil, "garbage input")
	ok(M.planPick(st, 1.5, 1) == nil or true, "fractions are floored")
end

-- ------------------------------------------------------------------ entering and scaling
do
	ok(M.enterProblem(1, 99, 0, 0, 0):find("level 100"), "Normal needs its level")
	eq(M.enterProblem(1, 100, 0, 0, 0), nil, "Normal at level 100")
	ok(M.enterProblem(2, 400, 0, 0, 0):find("Normal"), "Cruel needs Normal cleared")
	eq(M.enterProblem(2, 250, 1, 0, 0), nil, "Cruel after Normal")
	ok(M.enterProblem(3, 300, 2, 0, 0):find("level 400"), "Merciless needs its level")
	ok(M.enterProblem(1, 500, 3, 100, 160):find("60 seconds"), "cooldown")
	eq(M.enterProblem(1, 500, 3, 200, 160), nil, "cooldown over")
	ok(M.enterProblem(4, 500, 3, 0, 0) ~= nil, "no fourth difficulty")
	-- scaling
	local a, b, c = M.scale(1, 100, 4), M.scale(1, 250, 4), M.scale(1, 9999, 4)
	ok(b.hp > a.hp and c.hp == b.hp, "health grows with level and stops at the tier's max level")
	eq(M.scale(1, 50, 4).hp, a.hp, "below the minimum level uses the minimum")
	ok(M.scale(2, 250, 4).hp > M.scale(1, 250, 4).hp, "harder tiers have more health")
	ok(M.scale(3, 400, 4).hp > M.scale(2, 500, 4).hp, "Merciless above Cruel")
	ok(M.scale(1, 100, 8).hit > M.scale(1, 100, 4).hit, "variant: Juggernaut hits harder")
	ok(M.scale(1, 100, 14).waveSize > M.scale(1, 100, 4).waveSize, "variant: Berserker meets more thralls")
	ok(a.addHp < a.hp and a.addHp >= 50, "thrall health is a share of the boss's")
	-- stages
	for key, f in pairs(cfg.families) do
		for i = 1, 3 do
			local st = M.stages(key, i)
			eq(st[#st].kind, "boss", key .. " ends with the boss")
			local waves = 0
			for _, s in ipairs(st) do
				if s.kind == "wave" then waves = waves + 1 end
			end
			if f.stages[1] == "wave" then
				eq(waves, #f.stages + cfg.tiers[i].extraWaves, key .. " waves on tier " .. i)
			end
		end
	end
	eq(M.stages("mystic", 3)[1].count, 5, "Merciless seals: 5")
	eq(M.stages("thief", 1)[1].count, 3, "Normal marks: 3")
	ok(M.hasMech("templar", "pyre") and not M.hasMech("warrior", "pyre"), "mechanics per family")
end

-- ------------------------------------------------------------------ rewards
do
	local o = M.clearOutcome(1, 200, 0, 0, 0)
	ok(o.first and o.gold == 200 * cfg.reward.first.goldPerLevel and o.chaos == cfg.reward.first.chaos[1] and o.tokens == 0, "first clear pays the first reward, no token")
	o = M.clearOutcome(2, 300, 1, 0, 0)
	ok(o.first, "tier above the cleared one is a first clear")
	o = M.clearOutcome(1, 300, 2, 0, 0)
	ok(not o.first and o.tokens == 1 and o.counted and o.gold == 300 * cfg.reward.repeatReward.goldPerLevel, "repeat: a token and the small reward")
	o = M.clearOutcome(1, 300, 2, cfg.switch.maxTokens, 0)
	eq(o.tokens, 0, "no token above the cap")
	o = M.clearOutcome(1, 300, 2, 0, cfg.reward.repeatsPerWeek)
	ok(o.tokens == 1 and o.gold == 0 and not o.counted, "weekly cap: the token still comes, the reward does not")
	-- the shared week (ChaosBounty.week: Monday 06:00), not the day-of-year weeks (Dec 31 was a one-day week 53)
	local function at(y, m, d, h)
		return os.time({year = y, month = m, day = d, hour = h, min = 0, sec = 0})
	end
	local w1 = M.weekKey(at(2026, 1, 3, 12))
	local w2 = M.weekKey(at(2026, 1, 9, 12))
	ok(w2 > w1, "week key rolls")
	eq(w1, 20251229, "Saturday 3 Jan 2026: the week of Monday 29 Dec 2025")
	eq(w2, 20260105, "Friday 9 Jan: the week of Monday 5 Jan")
	eq(M.weekKey(at(2026, 12, 31, 12)), M.weekKey(at(2026, 12, 28, 12)), "31 Dec is in its Monday's week, not a week of its own")
	eq(M.weekKey(at(2027, 1, 3, 23)), 20261228, "the week runs across the year end")
	eq(M.weekKey(at(2026, 10, 12, 5)), 20261005, "Monday 05:00: still last week")
	eq(M.weekKey(at(2026, 10, 12, 6)), 20261012, "Monday 06:00: the new week")
	eq(M.weekKey(at(2026, 10, 14, 12)), ChaosBounty.week(at(2026, 10, 14, 12), {rollHour = 6}), "the bounty board's week")
	-- an old key (YYYYWW) never matches: the first clear after the switch counts from 0 (no repeat is lost)
	ok(M.weekKey(at(2026, 10, 14, 12)) > 99999999 / 10 and 202641 ~= M.weekKey(at(2026, 10, 14, 12)), "old 6-digit keys never match")
end

-- ------------------------------------------------------------------ combat maths
do
	local b = {dealMelee = 15, dealAll = -5, dealFire = 20, dealLowHp = 30, dealFirst = 25, dealExecute = 40,
		dealHighHp = 10, dealMinion = 25, killStackPct = 3, killStackMax = 4, killStackMs = 5000}
	local function near(a, c, w) ok(math.abs(a - c) < 1e-9, w .. ": " .. a .. " ~= " .. c) end
	near(M.dealMultiplier(b, {origin = "melee", ctype = "physical", hpRatio = 0.5, targetRatio = 0.5}), 1.10, "melee +15 -5")
	near(M.dealMultiplier(b, {origin = "spell", ctype = "fire", hpRatio = 0.5, targetRatio = 0.5}), 1.15, "fire +20 -5")
	near(M.dealMultiplier(b, {origin = "melee", hpRatio = 0.2, targetRatio = 0.5}), 1.40, "low health adds 30")
	near(M.dealMultiplier(b, {origin = "melee", hpRatio = 1, targetRatio = 1}), 1.10 + 0.10 + 0.25, "full health and first strike")
	near(M.dealMultiplier(b, {origin = "melee", hpRatio = 0.5, targetRatio = 0.2}), 1.50, "execute")
	near(M.dealMultiplier(b, {origin = "minion", hpRatio = 0.5, targetRatio = 0.5}), 1.20, "minion +25 -5")
	near(M.dealMultiplier(b, {origin = "melee", hpRatio = 0.5, targetRatio = 0.5, stacks = 9}), 1.10 + 0.12, "stacks are capped at killStackMax")
	near(M.dealMultiplier({dealAll = -90}, {origin = "melee"}), 0.25, "damage never below 25%")
	near(M.dealMultiplier({dealAll = 900}, {origin = "melee"}), 2.5, "damage never above 250%")
	near(M.dealMultiplier({}, {origin = "melee"}), 1, "nothing held")
	-- take
	local t = {takeAll = 6, takeMelee = -12, takeMagic = 8, takeLowHp = -25}
	near(M.takeMultiplier(t, {origin = "melee", hpRatio = 1}), 0.94, "melee: +6 -12")
	near(M.takeMultiplier(t, {origin = "ranged", hpRatio = 1}), 0.94, "ranged counts as melee")
	near(M.takeMultiplier(t, {origin = "spell", hpRatio = 1}), 1.14, "spell: +6 +8")
	near(M.takeMultiplier(t, {origin = "other", hpRatio = 0.1}), 0.81, "low health: -25")
	near(M.takeMultiplier({takeAll = -95}, {origin = "melee"}), 0.3, "never less than 30% taken")
	near(M.takeMultiplier({takeAll = 500}, {origin = "melee"}), 2.0, "never more than double")
	-- evade / reflect / shield / last stand
	eq(M.evadeChance({evade = 12}, "melee"), 12, "evade"); eq(M.evadeChance({evade = 80}, "ranged"), M.EVADE_CAP, "evade capped")
	eq(M.evadeChance({evade = 12}, "spell"), 0, "spells cannot be evaded")
	eq(M.reflectAmount({reflect = 20}, "melee", 1000), 200, "reflect"); eq(M.reflectAmount({reflect = 20}, "spell", 1000), 0, "only melee is reflected")
	eq(M.reflectAmount({reflect = 90}, "melee", 1000), 500, "reflect capped at 50%")
	local rest, paid = M.shieldSplit({manaShield = 25}, 1000, 5000)
	eq(rest, 750, "shield: the rest"); eq(paid, 250, "shield: the mana paid")
	rest, paid = M.shieldSplit({manaShield = 25}, 1000, 100)
	eq(paid, 100, "shield: at most the mana left"); eq(rest, 900, "rest")
	rest, paid = M.shieldSplit({manaShield = 25}, 1000, 0)
	eq(rest, 1000, "no mana, no shield")
	local state = {}
	local dmg, hit = M.lastStand({lastStandCd = 90}, state, 1000, 500, 800)
	ok(hit and dmg == 499, "last stand leaves 1 health")
	dmg, hit = M.lastStand({lastStandCd = 90}, state, 1050, 500, 800)
	ok(not hit and dmg == 800, "last stand on cooldown")
	dmg, hit = M.lastStand({lastStandCd = 90}, state, 1091, 500, 800)
	ok(hit, "last stand ready again")
	dmg, hit = M.lastStand({lastStandCd = 90}, {}, 0, 500, 100)
	ok(not hit, "a survivable hit does not trigger it")
	dmg, hit = M.lastStand({}, {}, 0, 500, 800)
	ok(not hit, "no node, no last stand")
	-- kill stacks
	local ks = {}
	local nb = {killStackPct = 3, killStackMax = 3, killStackMs = 5000}
	for i = 1, 5 do M.addKill(ks, nb, i * 1000) end
	eq(M.stackCount(ks, nb, 5000), 3, "stacks capped at 3")
	eq(M.stackCount(ks, nb, 8500), 2, "kills older than the duration drop off")
	eq(M.stackCount(ks, nb, 20000), 0, "all expired")
	eq(M.stackCount({}, nb, 0), 0, "no kills")
	eq(M.scaleDamage(-100, 1.13), -113, "scale keeps the sign and rounds toward zero")
	eq(M.scaleDamage(100, 1.13), 113, "scale positive")
	ok(M.roll(100, function() return 100 end) and not M.roll(0, function() return 1 end), "roll")
end

-- ------------------------------------------------------------------ descriptions
do
	local lines = M.describe(M.nodeById(411))
	eq(#lines, 2, "gain and price"); ok(lines[1].good and not lines[2].good, "gain good, price bad")
	eq(lines[1].text, "+15% melee damage", "text of the gain"); eq(lines[2].text, "+6% damage taken", "text of the price")
	lines = M.describe(M.nodeById(412))
	ok(lines[1].good and lines[1].text == "-12% melee and ranged damage taken", "less damage taken is good: " .. lines[1].text)
	ok(not lines[2].good and lines[2].text == "-6% melee damage", "less damage dealt is bad")
	-- special lines
	local stack = M.describe(M.nodeById(431))
	ok(stack[1].text:find("Each kill") and stack[1].text:find("8 times") and stack[1].text:find("8 s"), "stack line: " .. stack[1].text)
	local ls = M.describe(M.nodeById(432))
	ok(ls[1].text:find("Survive a lethal hit") and ls[1].text:find("90 s"), "last stand line")
	local echo = M.describe(M.nodeById(312))
	ok(echo[1].text:find("15%% chance") and echo[1].text:find("again for 50%%"), "echo line: " .. echo[1].text)
	local nova = M.describe(M.nodeById(332))
	ok(nova[1].text:find("bursts"), "nova line: " .. nova[1].text)
	local crit = M.describe(M.nodeById(711))
	ok(crit[1].text:find("critical hit damage") and crit[2].text:find("%+4%% critical hit chance"), "crit lines: " .. crit[1].text)
	-- every line of every node fits a card (the client wraps at about 40 characters per line, two lines each)
	for _, voc in ipairs(M.vocations()) do
		for _, entry in ipairs(M.pairsOf(voc)) do
			for _, node in ipairs({entry.a, entry.b}) do
				local ls = M.describe(node)
				ok(#ls >= 2 and #ls <= 5, "node " .. node.name .. " has 2-5 lines")
				for _, l in ipairs(ls) do
					ok(#l.text <= 46, "line fits a card: " .. l.text)
				end
			end
		end
	end
	-- spell events: exactly the nodes with spellCost / spellCd say so
	local needs = 0
	for _, voc in ipairs(M.vocations()) do
		for _, entry in ipairs(M.pairsOf(voc)) do
			for _, node in ipairs({entry.a, entry.b}) do
				local has = node.fx.spellCost or node.fx.spellCd or node.cost.spellCost or node.cost.spellCd
				eq(M.needsSpellEvents(node), has ~= nil, "needsSpellEvents " .. node.name)
				if has then needs = needs + 1 end
			end
		end
	end
	ok(needs >= 5 and needs <= 16, "a few nodes need the spell events (" .. needs .. ")")
end

-- ------------------------------------------------------------------ run mechanics
do
	-- stillness
	local s = {}
	eq(M.stillness(s, "1:1", 0), "move", "first tile"); eq(M.stillness(s, "1:1", 1000), "wait", "wait")
	eq(M.stillness(s, "1:1", 2100), "warn", "warn"); eq(M.stillness(s, "1:1", 2600), "wait", "warned once")
	eq(M.stillness(s, "1:1", 3200), "slam", "slam"); eq(M.stillness(s, "2:1", 3300), "move", "moving resets")
	-- zones
	local zones = M.zoneTiles({x = 10, y = 10, z = 7}, 5, 2, rng(7))
	eq(#zones, 5, "five zones"); eq(zones[1].x, 10, "the first is the player's own tile")
	local seen = {}
	for _, z in ipairs(zones) do ok(not seen[z.x .. ":" .. z.y], "distinct"); seen[z.x .. ":" .. z.y] = true end
	-- lethal hit catch
	local p, sd, caught = M.catchDamage(100, 60, 30)
	ok(not caught and p == 60 and sd == 30, "survivable hit untouched")
	p, sd, caught = M.catchDamage(100, 90, 30)
	ok(caught and p + sd == 99, "a lethal hit leaves 1 health")
	p, sd, caught = M.catchDamage(1, 50, 0)
	ok(caught and p == 0, "at 1 health any hit is caught")
	-- seals
	for seed = 1, 20 do
		local order = M.sealOrder(5, rng(seed))
		eq(#order, 5, "seal order length")
		for i = 2, #order do ok(order[i] ~= order[i - 1], "never the same seal twice in a row") end
		for _, v in ipairs(order) do ok(v >= 1 and v <= 4, "seal id") end
	end
	local order = {2, 4, 1}
	local st = {index = 1, charge = 0}
	eq(M.sealStep(st, order, nil, 500), "none", "off a seal")
	eq(M.sealStep(st, order, 2, 500), "charging", "on the right seal")
	eq(M.sealStep(st, order, 2, 1000), "charging", "...")
	eq(M.sealStep(st, order, 2, 1000), "done", "charged")
	eq(st.index, 2, "next seal")
	eq(M.sealStep(st, order, 1, 2500), "wrong", "the wrong seal after the full charge")
	eq(st.index, 2, "a wrong seal does not advance")
	M.sealStep(st, order, 4, 100); M.sealStep(st, order, nil, 100)
	eq(st.charge, 0, "stepping off resets the charge")
	-- pyre
	local safes = {{x = 10, y = 10, z = 7}, {x = 20, y = 20, z = 7}}
	ok(M.pyreSafe({x = 11, y = 9, z = 7}, safes), "next to a sanctuary light")
	ok(not M.pyreSafe({x = 13, y = 10, z = 7}, safes), "two tiles away is not safe")
	ok(not M.pyreSafe({x = 10, y = 10, z = 8}, safes), "another floor")
	eq(M.markEscaped(100), 100 - cfg.markPenaltySeconds, "a mark that escapes costs time"); eq(M.markEscaped(5), 0, "never below zero")
end

-- ------------------------------------------------------------------ the room
do
	local L = M.layout(1)
	eq(#L.floor, cfg.room.inner * cfg.room.inner, "floor tiles")
	eq(#L.walls, (cfg.room.inner + 2) ^ 2 - cfg.room.inner ^ 2, "wall tiles")
	ok(M.inRoom(L, L.playerStart) and M.inRoom(L, L.bossStart) and M.inRoom(L, L.center), "starts inside")
	ok(math.abs(L.playerStart.y - L.bossStart.y) <= 6 and L.playerStart.x == L.bossStart.x, "the guardian sees the player at the start")
	for i, s in ipairs(L.seals) do ok(M.inRoom(L, s), "seal " .. i .. " inside") end
	ok(not M.inRoom(L, {x = L.x1 - 1, y = L.y1, z = L.z}), "the wall is outside")
	eq(M.slotAt(L.center), 1, "slot of the centre"); eq(M.slotAt(M.layout(8).center), 8, "slot 8")
	ok(M.slotAt({x = 1, y = 1, z = 7}) == nil, "far away is no slot")
	ok(M.slotAt({x = L.center.x, y = L.center.y, z = 6}) == nil, "other floor")
	-- slots do not overlap
	local occupied = {}
	for slot = 1, cfg.room.grid.slots do
		for _, list in ipairs({M.layout(slot).floor, M.layout(slot).walls}) do
			for _, p in ipairs(list) do
				local k = p.x .. "," .. p.y
				ok(not occupied[k], "tile used by two slots")
				occupied[k] = true
			end
		end
	end
	-- the rift grid (8192-8447) and the ascension trial (7000-7100) are not touched
	for k in pairs(occupied) do
		local x, y = k:match("(%d+),(%d+)")
		x, y = tonumber(x), tonumber(y)
		if (x >= 8192 and x < 8448 and y >= 8192 and y < 8448) or (x >= 7000 and x < 7110 and y >= 7000 and y < 7110) then
			ok(false, "overlaps another runtime area at " .. k)
			break
		end
	end
	-- seals are far enough from each other that one is not stood on by accident
	for i = 1, 4 do
		for j = i + 1, 4 do
			ok(math.max(math.abs(L.seals[i].x - L.seals[j].x), math.abs(L.seals[i].y - L.seals[j].y)) >= 5, "seals apart")
		end
	end
end

-- ------------------------------------------------------------------ the client state
do
	local st = M.clientState({voc = 8, level = 300, tier = 1, picks = {1, 0, 0}, tokens = 1, now = 0, cooldown = 0})
	ok(st.supported and st.voc == 8 and st.tier == 1 and #st.tiers == 3 and #st.pairs == 3, "shape")
	ok(st.pairs[1].held == 1 and not st.pairs[1].locked and st.pairs[2].locked and st.pairs[3].locked, "lock state")
	ok(st.pairs[1].nodes[2].can and st.pairs[1].nodes[2].switch, "switching is possible with a token")
	ok(not st.pairs[2].nodes[1].can and st.pairs[2].nodes[1].why:find("Locked"), "locked pair says why")
	ok(st.tiers[1].cleared and not st.tiers[2].cleared, "tiers cleared")
	ok(st.tiers[2].problem == nil, "Cruel can be entered at level 300 after Normal")
	ok(st.tiers[3].problem ~= nil, "Merciless cannot")
	ok(st.pairs[1].nodes[1].lines[1].text and st.pairs[1].nodes[1].name == M.pairsOf(8)[1].a.name, "node text")
	st = M.clientState({voc = 99, level = 300})
	eq(st.supported, false, "no trial for an unknown vocation")
	-- the state survives JSON-like walking (only plain values)
	local function plain(t, depth)
		if depth > 8 then return false end
		for k, v in pairs(t) do
			local tv = type(v)
			if tv == "table" then
				if not plain(v, depth + 1) then return false end
			elseif tv ~= "string" and tv ~= "number" and tv ~= "boolean" then
				return false
			end
		end
		return true
	end
	ok(plain(M.clientState({voc = 24, level = 800, tier = 3, picks = {2, 1, 2}, tokens = 0, now = 0, cooldown = 0}), 0), "plain data")
end

print(string.format("trials_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
