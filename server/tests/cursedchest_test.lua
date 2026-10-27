-- Run from the server/ folder: luajit tests/cursedchest_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Cursed Chest (O244): the pure rules (cursedchest_core.lua + cursedchest_config.lua): the chance by tier and level
-- gap, every exclusion, the cooldown and the caps, the pool, the five hordes and their escalation, the level scale, the
-- event's state machine (timers, failures, win), one claim per player, the loot amounts and their value against the
-- hunting gold model; then the engine file (cursedchest.lua) against a mocked engine: a kill leaves a chest, the use
-- starts the event, five hordes come one at a time, the loot is delivered once per player, every failure removes the
-- monsters and the chest, an unknown chest crumbles, and event monsters never leave a second chest.
local cfg = dofile("data/scripts/chaos/cursedchest_config.lua")
dofile("data/scripts/chaos/cursedchest_core.lua")
local K = ChaosCursedChestCore

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, tol, what)
	ok(math.abs(a - b) <= tol, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function low(a, b) return a end
local function high(a, b) return b end
local function rng(seed)
	local s = seed
	return function(a, b)
		s = (s * 16807) % 2147483647
		return a + s % (b - a + 1)
	end
end

-- ------------------------------------------------------------------ the config
eq(#cfg.event.hordes, 5, "five hordes")
ok(cfg.enabled == true, "enabled")
eq(cfg.spawn.chance.normal, 0.3, "normal odds 0.3%")
eq(cfg.spawn.chance.magic, 0.8, "magic odds 0.8%")
eq(cfg.spawn.chance.rare, 1.5, "rare odds 1.5%")
eq(cfg.spawn.chance.boss, 3, "boss odds 3%")
ok(cfg.spawn.expireSec >= 120 and cfg.spawn.expireSec <= 180, "an unopened chest lasts 2-3 minutes")
ok(cfg.event.totalSec >= 240 and cfg.event.totalSec <= 300, "total time 4-5 minutes")
for i = 2, 5 do
	local a, b = cfg.event.hordes[i - 1], cfg.event.hordes[i]
	ok(b.count >= a.count, "horde " .. i .. " is not smaller")
	ok(b.health >= a.health and b.damage >= a.damage, "horde " .. i .. " is not softer")
end
ok(cfg.event.hordes[5].leader and cfg.event.hordes[5].leader.rare, "the fifth horde has a leader")
for i = 1, 4 do
	ok(cfg.event.hordes[i].leader == nil, "horde " .. i .. " has no leader")
end
-- the chest and its action id collide with nothing
ok(cfg.chest.actionId == 47730, "action id")
do
	local fh = io.open("data/scripts/chaos/harvest_event_config.lua", "r")
	if fh then
		local src = fh:read("*a")
		fh:close()
		ok(not src:find("47730", 1, true), "47730 is not the harvest event's")
	end
end
-- the hunting gold table is the same as the gamble model's (one source of truth in two files)
do
	local g = dofile("data/scripts/chaos/gamble_config.lua")
	local pts = g.balance and g.balance.hunting
	ok(pts ~= nil, "gamble_config.lua balance.hunting")
	if pts then
		eq(#pts, #cfg.loot.hunting, "hunting points")
		for i, p in ipairs(pts) do
			eq(cfg.loot.hunting[i][1], p[1], "hunting level " .. i)
			eq(cfg.loot.hunting[i][2], p[2], "hunting gold " .. i)
		end
	end
end

-- ------------------------------------------------------------------ the chance
eq(K.levelFactor(cfg, 100, 95), 1, "within the grace")
eq(K.levelFactor(cfg, 100, 90), 1, "at the grace")
eq(K.levelFactor(cfg, 100, 80), 1.0, "share 0.8 keeps the full chance")
eq(K.levelFactor(cfg, 100, 65), 0.5, "share 0.65")
eq(K.levelFactor(cfg, 100, 50), 0.2, "share 0.5")
eq(K.levelFactor(cfg, 100, 40), 0, "far below: nothing")
eq(K.chance(cfg, "normal", 100, 100), 0.3, "normal")
near(K.chance(cfg, "magic", 100, 65), 0.4, 1e-9, "magic at half")
eq(K.chance(cfg, "boss", 100, 100), 3, "boss")
eq(K.chance(cfg, "weird", 100, 100), 0, "unknown tier")
eq(K.chance(cfg, "boss", 100, 100, 100), cfg.spawn.maxChance, "capped")
ok(K.roll(cfg, {tier = "normal", playerLevel = 100, monsterLevel = 100}, low), "a low roll hits")
ok(not K.roll(cfg, {tier = "normal", playerLevel = 100, monsterLevel = 100}, high), "a high roll misses")
ok(not K.roll(cfg, {tier = "normal", playerLevel = 100, monsterLevel = 10}, low), "far below: no hit")
do -- the rate over many kills sits at the odds
	local r, hits, n = rng(7), 0, 400000
	for _ = 1, n do
		if K.roll(cfg, {tier = "magic", playerLevel = 100, monsterLevel = 100}, r) then
			hits = hits + 1
		end
	end
	near(hits / n * 100, 0.8, 0.06, "simulated magic rate")
end

-- ------------------------------------------------------------------ exclusions
local function info(extra)
	local i = {ownerId = 1, tier = "normal", name = "Troll", maxHealth = 200, playerLevel = 100, monsterLevel = 100,
		pos = {x = 100, y = 100, z = 7}, stamina = true}
	for k, v in pairs(extra or {}) do
		i[k] = v
	end
	return i
end
local st = K.newState()
eq(select(1, K.eligible(cfg, info(), st, 1000)), true, "a plain kill is eligible")
for field, reason in pairs({summon = "summon", tagged = "event monster", husk = "event monster", place = "pvp place",
	instance = "instance", protectionZone = "zone", house = "zone"}) do
	local ok1, why = K.eligible(cfg, info({[field] = (field == "place" or field == "instance") and "x" or true}), st, 1000)
	ok(not ok1 and why == reason, field .. " blocks: " .. tostring(why))
end
local ok1, why = K.eligible(cfg, info({stamina = false}), st, 1000)
ok(not ok1 and why == "stamina", "no stamina")
ok1, why = K.eligible(cfg, info({maxHealth = 10}), st, 1000)
ok(not ok1 and why == "weak", "a critter")
ok1, why = K.eligible(cfg, info({monsterLevel = 20}), st, 1000)
ok(not ok1 and why == "level", "far below the player")
local noOwner = info()
noOwner.ownerId = nil
ok1, why = K.eligible(cfg, noOwner, st, 1000)
ok(not ok1 and why == "no owner", "no owner")
local c2 = {}
for k, v in pairs(cfg) do c2[k] = v end
c2.spawn = {}
for k, v in pairs(cfg.spawn) do c2.spawn[k] = v end
c2.spawn.excludeNames = {troll = true}
c2.spawn.excludedAreas = {{90, 90, 110, 110, 7}}
ok1, why = K.eligible(c2, info(), st, 1000)
ok(not ok1 and why == "skipped", "excluded name")
c2.spawn.excludeNames = {}
ok1, why = K.eligible(c2, info(), st, 1000)
ok(not ok1 and why == "area", "excluded rectangle")
ok1 = K.eligible(c2, info({pos = {x = 100, y = 100, z = 8}}), st, 1000)
ok(ok1, "the rectangle is for floor 7 only")
c2.enabled = false
ok1, why = K.eligible(c2, info(), st, 1000)
ok(not ok1 and why == "disabled", "disabled")

-- cooldown, one chest per player, the server cap
st = K.newState()
K.markSpawn(cfg, st, 1, 1000)
ok1, why = K.eligible(cfg, info(), st, 1100)
ok(not ok1 and why == "own chest", "one chest at a time")
K.markGone(st, 1)
ok1, why = K.eligible(cfg, info(), st, 1100)
ok(not ok1 and why == "cooldown", "the cooldown after a chest")
ok1 = K.eligible(cfg, info(), st, 1000 + cfg.spawn.cooldownSec)
ok(ok1, "eligible again after the cooldown")
ok1 = K.eligible(cfg, info({ownerId = 2}), st, 1100)
ok(ok1, "another player is not on the cooldown")
st = K.newState()
for i = 1, cfg.spawn.maxAlive do
	K.markSpawn(cfg, st, 100 + i, 0)
end
ok1, why = K.eligible(cfg, info(), st, 99999)
ok(not ok1 and why == "max alive", "the server cap")
K.markGone(st, 101)
eq(st.alive, cfg.spawn.maxAlive - 1, "markGone")
K.markGone(st, 999)
K.prune(st, 99999)
eq(next(st.cooldown), nil, "prune drops passed cooldowns")

-- ------------------------------------------------------------------ the level and the scale
eq(K.areaLevel(cfg, 120, 130), 120, "area level: the monster's")
eq(K.areaLevel(cfg, 20, 130), 65, "lifted to half the opener's")
eq(K.areaLevel(cfg, 400, 130), 130, "at most the opener's")
eq(K.areaLevel(cfg, 0, 1), 1, "at least 1")
eq(K.targetLevel(cfg, 200), 180, "the hordes' level")
local sc = K.levelScale(cfg, 180, 180)
eq(sc.health, 1, "no scale at the same level")
sc = K.levelScale(cfg, 100, 180)
near(sc.health, (1 + 0.0074 * 180) / (1 + 0.0074 * 100), 1e-9, "health scale")
near(sc.damage, (1 + 0.0015 * 180) / (1 + 0.0015 * 100), 1e-9, "damage scale")
sc = K.levelScale(cfg, 1, 1000)
eq(sc.health, cfg.event.scale.maxHealth, "health capped")
eq(sc.damage, cfg.event.scale.maxDamage, "damage capped")
eq(K.levelScale(cfg, 500, 100).health, 1, "never lowered")
-- the same formula as the generated areas' scale
dofile("data/scripts/chaos/areagen_core.lua")
local ag = ChaosAreaGenCore.levelScale(100, 180)
near(K.levelScale(cfg, 100, 180).health, ag.health, 1e-9, "health scale = areagen levelScale")
near(K.levelScale(cfg, 100, 180).damage, ag.damage, 1e-9, "damage scale = areagen levelScale")

-- ------------------------------------------------------------------ the pool
local pl = K.buildPool(cfg, "Troll", {"Troll", "Goblin", "Goblin", "Goblin", "Orc", "Rat", "Bat"}, 20)
eq(#pl, cfg.event.pool.maxKinds, "at most maxKinds kinds")
eq(pl[1].name, "Troll", "the killed monster leads (weight 3 + 1)")
eq(pl[2].name, "Goblin", "the next by count")
pl = K.buildPool(cfg, "Troll", {}, 20)
eq(#pl, cfg.event.pool.minKinds, "padded to minKinds from the themed list")
eq(pl[1].name, "Troll", "killed first")
ok(pl[2].name ~= "Troll", "a themed kind")
pl = K.buildPool(cfg, "Troll", {"Boss One"}, 20, {["boss one"] = true})
ok(#pl >= 2 and pl[1].name == "Troll" and pl[2].name ~= "Boss One", "a skipped name stays out")
pl = K.buildPool(cfg, "Demon", {}, 300)
ok(pl[2] ~= nil, "themed pool of a high band")
eq(K.pickKind({{name = "A", weight = 1}, {name = "B", weight = 3}}, low), "A", "pick low")
eq(K.pickKind({{name = "A", weight = 1}, {name = "B", weight = 3}}, high), "B", "pick high")
eq(K.pickKind({}, low), nil, "empty pool")

-- ------------------------------------------------------------------ the hordes
local prevCount = 0
for n = 1, 5 do
	local plan = K.hordePlan(cfg, n, 1, rng(n))
	eq(plan.count, cfg.event.hordes[n].count, "horde " .. n .. " solo size")
	eq(#plan.tiers, plan.count, "horde " .. n .. " tiers")
	ok(plan.count >= prevCount, "escalating size")
	prevCount = plan.count
	if n < 5 then
		eq(plan.leader, nil, "no leader in horde " .. n)
	else
		ok(plan.leader == "rare" or plan.leader == "legendary", "the fifth leads with a rare or elite")
		eq(plan.tiers[1], plan.leader, "the leader is listed first")
	end
	eq(K.hordePlan(cfg, 6, 1, low), nil, "no sixth horde")
end
do -- the share of magic+ grows with the horde
	local function eliteShare(n)
		local r, elite, total = rng(11 * n), 0, 0
		for _ = 1, 400 do
			local plan = K.hordePlan(cfg, n, 1, r)
			for i = (plan.leader and 2 or 1), plan.count do
				total = total + 1
				if plan.tiers[i] ~= "normal" then
					elite = elite + 1
				end
			end
		end
		return elite / total
	end
	ok(eliteShare(1) == 0, "horde 1 is all normal")
	ok(eliteShare(3) > eliteShare(2), "horde 3 tougher than 2")
	ok(eliteShare(5) > eliteShare(3), "horde 5 tougher than 3")
end
eq(K.partyScale(cfg, 1), 1, "party scale solo")
eq(K.partyScale(cfg, 3), 1.7, "party scale of three")
eq(K.partyScale(cfg, 20), cfg.event.maxPartyScale, "party scale capped")
eq(K.hordePlan(cfg, 1, 5, low).count, math.floor(4 * 2.0 + 0.5), "five players: double hordes")

-- ------------------------------------------------------------------ the state machine
local e = cfg.event
local function newEv(t0)
	return K.newEvent(cfg, {ownerId = 1, openerId = 10, level = 100, openerLevel = 100, pool = {}, participants = {[10] = true}}, t0 or 0)
end
local ev = newEv(0)
eq(ev.players, 1, "one participant")
local acts = K.step(cfg, ev, {alive = 0, inside = 1}, 1000)
eq(#acts, 0, "nothing before the first delay")
acts = K.step(cfg, ev, {alive = 0, inside = 1}, e.firstDelayMs)
eq(acts[1][1], "spawn", "the first horde comes after the delay")
eq(acts[1][2], 1, "horde 1")
K.spawned(ev, 1, e.firstDelayMs)
acts = K.step(cfg, ev, {alive = 4, inside = 1}, e.firstDelayMs + 5000)
eq(#acts, 0, "the next horde waits while the current one lives")
acts = K.step(cfg, ev, {alive = 0, inside = 1}, e.firstDelayMs + 6000)
eq(#acts, 0, "and the pause after a clear")
acts = K.step(cfg, ev, {alive = 0, inside = 1}, e.firstDelayMs + 6000 + e.betweenMs)
eq(acts[1][2], 2, "horde 2 after the pause")
K.spawned(ev, 2, e.firstDelayMs + 9000)
acts = K.step(cfg, ev, {alive = 3, inside = 1}, e.firstDelayMs + 9000 + e.hordeTimerSec * 1000)
eq(acts[1] and acts[1][2], 3, "the horde timer brings horde 3 with monsters alive")
K.spawned(ev, 3, 100000)
acts = K.step(cfg, ev, {alive = e.aliveCap, inside = 1}, 100000 + e.hordeTimerSec * 1000)
eq(#acts, 0, "no horde past the alive cap")
K.spawned(ev, 4, 150000)
K.spawned(ev, 5, 160000)
acts = K.step(cfg, ev, {alive = 2, inside = 1}, 170000)
eq(#acts, 0, "no win with the fifth alive")
acts = K.step(cfg, ev, {alive = 0, inside = 1}, 171000)
eq(acts[1][1], "win", "the win after the fifth is dead")
K.win(cfg, ev, 171000)
eq(ev.state, "won", "won")
eq(#K.step(cfg, ev, {alive = 0, inside = 1}, 172000), 0, "a won event does no more steps")

-- failures
ev = newEv(0)
acts = K.step(cfg, ev, {alive = 3, inside = 1}, e.totalSec * 1000)
eq(acts[1][1], "fail", "time")
eq(acts[1][2], "time", "the reason: time")
ev = newEv(0)
acts = K.step(cfg, ev, {alive = 3, inside = 0}, 1000)
eq(#acts, 0, "nobody inside: grace first")
acts = K.step(cfg, ev, {alive = 3, inside = 0}, 1000 + e.warnSec * 1000)
eq(acts[1][1], "warn", "a warning")
acts = K.step(cfg, ev, {alive = 3, inside = 0}, 1000 + e.warnSec * 1000 + 500)
local warns = 0
for _, a in ipairs(acts) do
	if a[1] == "warn" then warns = warns + 1 end
end
eq(warns, 0, "one warning only")
acts = K.step(cfg, ev, {alive = 3, inside = 1}, 8000)
eq(acts[1][1], "unwarn", "back inside: the warning clears")
acts = K.step(cfg, ev, {alive = 3, inside = 0}, 9000)
acts = K.step(cfg, ev, {alive = 3, inside = 0}, 9000 + e.emptyGraceSec * 1000)
eq(acts[1] and acts[1][1], "fail", "everyone left or died: fail")
eq(acts[1] and acts[1][2], "abandoned", "the reason: abandoned")
K.fail(ev, "abandoned")
eq(#K.step(cfg, ev, {alive = 0, inside = 1}, 99999), 0, "a failed event does nothing more")

-- claims: once per participant, only participants, only in time
ev = newEv(0)
ev.participants = {[10] = true, [11] = true}
ok(not K.canClaim(ev, 10, 0), "no claim while running")
K.win(cfg, ev, 1000)
ok(K.canClaim(ev, 10, 2000), "a participant may claim")
ok(not K.canClaim(ev, 12, 2000), "a stranger may not")
ok(K.claim(ev, 10), "first claim")
ok(not K.claim(ev, 10), "second claim refused")
local can, why2 = K.canClaim(ev, 10, 2000)
ok(not can and why2 == "claimed", "claimed")
ok(not K.claimDone(ev, 2000), "not done while 11 waits")
ok(K.canClaim(ev, 11, 2000), "the other may still claim")
K.claim(ev, 11)
ok(K.claimDone(ev, 2000), "done when all claimed")
ev = newEv(0)
K.win(cfg, ev, 1000)
ok(not K.canClaim(ev, 10, 1000 + e.claimSec * 1000), "no claim after the time")
ok(K.claimDone(ev, 1000 + e.claimSec * 1000), "done by time")
ok(K.mayUse({userId = 1, ownerId = 1}), "the owner may use")
ok(K.mayUse({userId = 2, ownerId = 1, sameParty = true}), "the owner's party may use")
ok(not K.mayUse({userId = 2, ownerId = 1}), "a stranger may not use")

-- the looks: one own id (the one-tile look of pair 53), two older looks that still count, the Sealed Coffer's chest as the fallback
eq(#cfg.chest.itemIds, 1, "one look")
eq(cfg.chest.itemIds[1], 32281, "the look is server item 32281 (client 38642, redrawn one tile)")
eq(table.concat(cfg.chest.legacyItemIds, ","), "32282,32283", "the older looks of pair 43")
eq(cfg.chest.itemId, 12664, "the fallback is the Sealed Coffer chest")
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
local allOf = function() return true end
eq(#K.chestIds(cfg, allOf), 1, "the installed look may be drawn")
eq(#K.chestIds(cfg, nil), 1, "no existence check: the one look")
eq(table.concat(K.chestIds(cfg, function() return false end), ","), "12664", "none installed: the fallback")
ok(not has(K.chestIds(cfg, allOf), 32282) and not has(K.chestIds(cfg, allOf), 32283), "the older looks are never drawn")
eq(K.pickChestId(cfg, allOf, low), cfg.chest.itemIds[1], "the draw: the look")
eq(K.pickChestId(cfg, allOf, high), cfg.chest.itemIds[1], "the draw: the look, whatever the roll")
eq(K.pickChestId(cfg, function() return false end, high), 12664, "the draw with none installed: the fallback")
local seenLook = {}
local r1 = rng(11)
for _ = 1, 300 do seenLook[K.pickChestId(cfg, allOf, r1)] = true end
ok(seenLook[32281] and next(seenLook, 32281) == nil, "a random draw always gives the look")
for _, id in ipairs({32281, 32282, 32283}) do
	ok(K.isChestId(cfg, id), "look " .. id .. " is a cursed chest")
end
ok(K.isChestId(cfg, 12664), "the fallback id is a cursed chest")
ok(not K.isChestId(cfg, 12665) and not K.isChestId(cfg, nil), "other items are not")
eq(#K.allChestIds(cfg), 4, "four ids count as a cursed chest")

-- ------------------------------------------------------------------ the loot
eq(K.hourlyGold(cfg, 1), 19000, "gold per hour below the table")
eq(K.hourlyGold(cfg, 100), 358839, "gold per hour at 100")
eq(K.hourlyGold(cfg, 5000), 9519711, "flat beyond the table")
near(K.hourlyGold(cfg, 70), (83000 + 358839) / 2, 1, "linear between points")
local gv = K.goldValue(cfg, 100, 1, function() return 100 end)
eq(gv, math.floor(358839 * 3 / 60), "gold: three minutes of the level's hunting gold")
for _, level in ipairs({8, 40, 100, 300, 500, 1000}) do
	local v = K.goldValue(cfg, level, 1, high)
	local hourly = K.hourlyGold(cfg, level)
	ok(v <= hourly * (cfg.loot.goldMinutes + 0.5) / 60 * cfg.loot.goldMax / 100 + 1, "gold stays inside the budget at " .. level)
end
-- a party's total grows slower than its size
for n = 2, 5 do
	ok(K.shareOf(cfg, n) * n < n, "party of " .. n .. " shares")
	ok(K.shareOf(cfg, n) * n > K.shareOf(cfg, n - 1) * (n - 1), "but still more in total")
end
eq(K.shareOf(cfg, 9), cfg.loot.partyShare[#cfg.loot.partyShare], "party share beyond the table")
local coins = K.coins(123456)
local sum = 0
for _, cn in ipairs(coins) do
	sum = sum + cn.count * ({[2160] = 10000, [2152] = 100, [2148] = 1})[cn.id]
	ok(cn.count <= 100, "stack of at most 100")
end
eq(sum, 123456, "coins add up")
eq(K.chaosOrbs(cfg, 100, 1, low), 1, "one Orb of Upheaval")
eq(K.chaosOrbs(cfg, 5000, 1, low), cfg.loot.chaosOrb.cap, "orbs capped")
ok(K.divineOrb(cfg, 1, 1, low), "a low roll gives an Orb of Fate")
ok(not K.divineOrb(cfg, 1, 1, high), "a high roll does not")
eq(K.shardCount(cfg, 100, 1, low), 8, "shards at level 100")
eq(K.shardCount(cfg, 100000, 1, low), cfg.loot.shards.cap, "shards capped")
local keys = K.orbKeys(cfg, low)
eq(#keys, 1, "one crafting orb")
eq(keys[1], "transmutation", "the first weight")
eq(K.itemCount(cfg, 1, low), 1, "1-2 pieces")
eq(K.itemCount(cfg, 1, high), 2, "1-2 pieces (high)")
eq(K.pickItemTier(cfg, low).tier, "magic", "tier low")
eq(K.pickItemTier(cfg, high).tier, "legendary", "tier high")
eq(#K.poolFor(cfg, 10), 9, "pool band 0")
eq(#K.poolFor(cfg, 300), 9, "pool band 250")
eq(K.pickGear(cfg, 10, {111}, 3, low)[3], 111, "gear from the monster's table")
ok(K.pickGear(cfg, 10, {}, 2, low)[1] ~= nil, "gear from the pool")
do -- expected orbs and gold an hour against the model: 4-5 chests an hour at the odds, at most the cooldown's 10
	local perHour = 3600 / cfg.spawn.cooldownSec
	ok(perHour <= 10, "at most 10 chests an hour by the cooldown")
	local killsPerHour = 1000
	local mix = {normal = 0.8, magic = 0.15, rare = 0.05}
	local expected = 0
	for tier, share in pairs(mix) do
		expected = expected + killsPerHour * share * cfg.spawn.chance[tier] / 100
	end
	ok(expected >= 3 and expected <= 6, "about 3-6 chests an hour of hunting: " .. expected)
	local goldShare = expected * cfg.loot.goldMinutes / 60
	-- the fight (about 3 minutes, husks: no corpse loot) takes the hunting minutes that gold pays back: neutral, not a faucet
	local fightShare = expected * cfg.event.hordeTimerSec * 4 / 3600
	ok(goldShare <= 0.25, "chest gold is at most 25% of an hour's hunting gold: " .. goldShare)
	ok(goldShare <= fightShare * 1.5, "and about what the fights cost in lost corpse loot: " .. goldShare .. " vs " .. fightShare)
	local orbs = expected * (cfg.loot.chaosOrb.max + cfg.loot.divineOrb.chance / 100)
	ok(orbs <= 8, "at most 8 orbs an hour from chests: " .. orbs)
end

-- ================================================================== the engine file against a mocked engine
local T = 10000000
os.mtime = function() return T end
local clock = 5000
os.time = function() return clock end
do
	local n = 0
	for _, name in ipairs({"MESSAGE_EVENT_ADVANCE", "MESSAGE_INFO_DESCR", "MESSAGE_LOOT", "TILESTATE_PROTECTIONZONE",
		"TILESTATE_BLOCKSOLID", "TILESTATE_FLOORCHANGE", "TILESTATE_TELEPORT", "TILESTATE_PVPZONE", "CONST_ME_MORTAREA",
		"CONST_ME_PURPLEENERGY", "CONST_ME_FIREWORK_YELLOW", "CONST_ME_POFF", "CONST_ME_TELEPORT", "ITEM_ATTRIBUTE_NAME",
		"ITEM_ATTRIBUTE_DESCRIPTION", "ACCOUNT_TYPE_GOD", "INDEX_WHEREEVER", "FLAG_NOLIMIT"}) do
		n = n + 1
		_G[name] = n
	end
end
RETURNVALUE_NOERROR = 0

local events, callbacks, globals, talks, actions = {}, {}, {}, {}, {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_pending", {k, v}) end})
rawset(EventCallback, "register", function(self, index)
	local p = rawget(self, "_pending")
	callbacks[p[1]] = callbacks[p[1]] or {}
	table.insert(callbacks[p[1]], {fn = p[2], index = index or 0})
	rawset(self, "_pending", nil)
end)
function CreatureEvent(name)
	local ce = {}
	function ce.register() events[name] = ce end
	function ce.type() end
	return ce
end
function GlobalEvent(name)
	local ge = {}
	function ge.interval() end
	function ge.register() globals[name] = ge end
	return ge
end
function TalkAction(words)
	local te = {}
	function te.separator() end
	function te.register() talks[words] = te end
	return te
end
function Action()
	local ae = {}
	function ae:aid(id) self._aid = id end
	function ae:register() actions[self._aid] = self end
	return ae
end

-- queued addEvent calls, run by hand
local queue = {}
function addEvent(fn, delay, ...)
	queue[#queue + 1] = {fn = fn, args = {...}}
end
local function runQueue()
	local q = queue
	queue = {}
	for _, item in ipairs(q) do
		item.fn((unpack or table.unpack)(item.args))
	end
end

local effects, labels = {}, {}
function Position(x, y, z)
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
	return {x = x, y = y, z = z, sendMagicEffect = function(self, id) effects[#effects + 1] = id end}
end
local tiles, blocked = {}, {}
function Tile(pos)
	local key = pos.x .. ":" .. pos.y .. ":" .. pos.z
	if blocked[key] == "none" then
		return nil
	end
	local tl = tiles[key]
	if not tl then
		tl = {items = {}, flags = {}}
		tl.getGround = function() return {} end
		tl.hasFlag = function(self, f)
			return self.flags[f] == true or (blocked[key] == "solid" and f == TILESTATE_BLOCKSOLID)
		end
		tl.getHouse = function() return nil end
		tl.getItemById = function(self, id)
			for _, it in ipairs(self.items) do
				if it._id == id and not it._removed then
					return it
				end
			end
			return nil
		end
		tiles[key] = tl
	end
	return tl
end

Game = Game or {}
local monsters, players, monsterSeq = {}, {}, 1000
local spectators = {}
function Game.createItem(id, count, pos)
	local it = {_id = id, _attrs = {}, _count = count}
	function it:getId() return id end
	function it:setActionId(a) self._aid = a end
	function it:setAttribute(k, v) self._attrs[k] = v end
	function it:getPosition() return self._pos end
	function it:remove() self._removed = true end
	if pos then
		it._pos = Position(pos.x, pos.y, pos.z)
		table.insert(Tile(pos).items, it)
	end
	return it
end
local createFail = {}
function Game.createMonster(name, pos, extended, force)
	if createFail[name] then
		return nil
	end
	monsterSeq = monsterSeq + 1
	local m = {_id = monsterSeq, _name = name, _hp = 1000, _max = 1000, _events = {}, _pos = Position(pos.x, pos.y, pos.z),
		_level = 100, _tier = "normal", _created = true}
	function m:getId() return self._id end
	function m:getName() return self._name end
	function m:isMonster() return true end
	function m:isPlayer() return false end
	function m:getMaster() return nil end
	function m:getHealth() return self._hp end
	function m:getMaxHealth() return self._max end
	function m:setMaxHealth(v) self._max = v end
	function m:setHealth(v) self._hp = v end
	function m:getPosition() return self._pos end
	function m:getMonsterLevel() return self._level end
	function m:registerEvent(e) self._events[e] = true end
	function m:unregisterEvent(e) self._events[e] = nil end
	function m:setDropLoot(v) self._dropLoot = v end
	function m:remove() self._removed = true; monsters[self._id] = nil end
	function m:getType() return {isBoss = function() return false end, getLoot = function() return {} end} end
	monsters[m._id] = m
	return m
end
function Monster(id)
	return monsters[id]
end
function Game.getSpectators(pos, multi, onlyPlayers, ...)
	return spectators
end
function Game.getPlayers()
	local out = {}
	for _, p in pairs(players) do
		out[#out + 1] = p
	end
	return out
end
local installedIds = {} -- item ids the mocked server has besides the base ones (the Cursed Chest's own looks)
ItemType = function(id)
	return {getName = function() return "item" .. id end, getId = function() return (installedIds[id] or id < 30000) and id or 0 end}
end

local given = {}
local function mkPlayer(id, guid, name)
	local p = {_id = id, _guid = guid, _name = name, _msgs = {}, _cancels = {}, _pos = Position(100, 100, 7), _level = 100,
		_hp = 500, _stamina = 2520, _given = {}, _items = {}}
	function p:getId() return self._id end
	function p:getGuid() return self._guid end
	function p:getName() return self._name end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getPosition() return self._pos end
	function p:getLevel() return self._level end
	function p:getHealth() return self._hp end
	function p:getStamina() return self._stamina end
	function p:getParty() return self._party end
	function p:getInbox() return nil end
	function p:getGroup() return {getAccess = function() return true end} end
	function p:getAccountType() return ACCOUNT_TYPE_GOD end
	function p:sendTextMessage(t, text) self._msgs[#self._msgs + 1] = text end
	function p:sendCancelMessage(text) self._cancels[#self._cancels + 1] = text end
	function p:getItemCount(id2) return self._given[id2] or 0 end
	function p:addItem(id2, count) self._given[id2] = (self._given[id2] or 0) + count; return {} end
	function p:addItemEx(item) self._items[#self._items + 1] = item; return 0 end
	players[id] = p
	return p
end
function Player(id)
	if type(id) == "table" then
		return id
	end
	return players[id]
end
local function mkParty(list)
	local party = {}
	function party:getLeader() return list[1] end
	function party:getMembers() return {table.unpack and table.unpack(list, 2) or unpack(list, 2)} end
	for _, p in ipairs(list) do
		p._party = party
	end
	return party
end

ChaosCombatFx = {label = function(pos, text, color) labels[#labels + 1] = {text = text, color = color} end}
ChaosTierOf = function(m) return m._tier end
local toasts = {}
ChaosNotify = {gmBroadcast = function(p, text) toasts[#toasts + 1] = text end}
local appliedTiers = {}
ChaosApplyTier = function(m, tier) appliedTiers[#appliedTiers + 1] = tier; m._tier = tier; m._max = m._max * 2; return true end
local paced = {}
ChaosPace = {apply = function(m, include) paced[m._id] = include; return true end}
ChaosLoot = {
	monsterLevel = function(m) return m._level end,
	itemFindMult = function() return 1 end,
	stockRarity = function() return 0 end,
	upgradeRarity = function(tier, cur, find, lvl) return 3 end,
	isGearId = function(id) return id < 1000 end,
	rollUniques = function() return {} end
}
local crafted = {}
ChaosCrafting = {
	orbByKey = {transmutation = {id = 5001}, chaos = {id = 29856}},
	createItem = function(id, rarity, level)
		local it = Game.createItem(id, 1)
		it._rarity, it._ilvl = rarity, level
		crafted[#crafted + 1] = it
		return it
	end
}
ChaosItemMods = {sourceLevel = function(src) return src.monsterLevel end}
local rifts = {}
ChaosRift = {runOf = rifts, monsterRun = {}}
ChaosAreaGen = {scaled = {}, pointOf = {}}

dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.giveItem = function(player, id, count)
	player._given[id] = (player._given[id] or 0) + count
	return count
end
dofile("data/scripts/chaos/cursedchest.lua")
local CC = ChaosCursedChest
ok(CC ~= nil, "engine file loaded")
eq(callbacks.onDropLoot[1].index, 5, "drop callback after the loot layer and autoloot")
ok(actions[47730] ~= nil, "the chest's action is registered")
ok(events.ChaosCursedChestDeath ~= nil, "the death event is registered")
ok(globals.ChaosCursedChestThink ~= nil, "the loop is registered")

local drop = callbacks.onDropLoot[1].fn
local use = actions[47730].onUse
local think = globals.ChaosCursedChestThink.onThink
math.randomseed(1)
local realRandom = math.random
local function allHit() math.random = function(a, b) return a end end
local function noHit() math.random = function(a, b) return b end end

local function mkCorpse(ownerId, pos)
	return {getCorpseOwner = function() return ownerId end, getPosition = function() return pos end}
end
local function mkDying(name, tier, level, hp)
	local m = {_id = 7000 + math.random(1, 1), _name = name, _tier = tier or "normal", _level = level or 100, _max = hp or 500}
	function m:getId() return self._id end
	function m:getName() return self._name end
	function m:getMaster() return self._master end
	function m:getMaxHealth() return self._max end
	function m:getMonsterLevel() return self._level end
	function m:getType() return {isBoss = function() return false end, getLoot = function() return {} end} end
	return m
end

local hero = mkPlayer(1, 501, "Hero")
local friend = mkPlayer(2, 502, "Friend")
local stranger = mkPlayer(3, 503, "Stranger")
local deathPos = Position(100, 100, 7)

-- ---- a kill: only the corpse owner rolls
noHit()
drop(mkDying("Troll"), mkCorpse(1, deathPos))
eq(next(CC.chests), nil, "a missed roll leaves nothing")
allHit()
drop(mkDying("Troll"), mkCorpse(999, deathPos))
eq(next(CC.chests), nil, "no player owner: nothing")
local summoned = mkDying("Troll")
summoned._master = hero
drop(summoned, mkCorpse(1, deathPos))
eq(next(CC.chests), nil, "a summon's death: nothing")
hero._stamina = 0
drop(mkDying("Troll"), mkCorpse(1, deathPos))
eq(next(CC.chests), nil, "no stamina: nothing")
hero._stamina = 2520
rifts[1] = {}
drop(mkDying("Troll"), mkCorpse(1, deathPos))
eq(next(CC.chests), nil, "inside a rift run: nothing")
rifts[1] = nil
tiles["100:100:7"] = nil
Tile(deathPos).flags[TILESTATE_PROTECTIONZONE] = true
drop(mkDying("Troll"), mkCorpse(1, deathPos))
eq(next(CC.chests), nil, "a protection zone: nothing")
tiles["100:100:7"] = nil
-- another system's monster
local goblin = mkDying("Treasure Goblin")
ChaosTreasureGoblin = {alive = {[goblin._id] = {}}}
drop(goblin, mkCorpse(1, deathPos))
eq(next(CC.chests), nil, "a treasure goblin: nothing")
ChaosTreasureGoblin = nil
-- a trivial monster far below the player
drop(mkDying("Rat", "normal", 10, 500), mkCorpse(1, deathPos))
eq(next(CC.chests), nil, "a monster far below: nothing")

-- ---- the roll that hits
spectators = {}
drop(mkDying("Troll", "magic"), mkCorpse(1, deathPos))
local ch
for _, c in pairs(CC.chests) do ch = c end
ok(ch ~= nil, "a hit leaves a chest")
eq(ch.state, "idle", "idle chest")
eq(ch.ownerId, 501, "owned by the corpse owner")
local chestItemAt = Tile(ch.pos):getItemById(12664)
ok(chestItemAt ~= nil, "the chest item is on the map")
eq(chestItemAt._aid, 47730, "with the action id")
eq(chestItemAt._attrs[ITEM_ATTRIBUTE_NAME], "cursed chest", "named")
ok(hero._msgs[#hero._msgs]:find("cursed chest rises"), "the owner is told")
ok(#toasts >= 1, "and a toast")
eq(#labels, 1, "a floating label")
eq(CC.state.alive, 1, "counted")
-- the cooldown and the one chest per player
drop(mkDying("Troll", "magic"), mkCorpse(1, deathPos))
local count = 0
for _ in pairs(CC.chests) do count = count + 1 end
eq(count, 1, "a second chest for the same player: none")
-- the loop: a dark effect and no expiry yet
effects = {}
think(1500)
ok(#effects >= 1, "the dark loop plays")
ok(Tile(ch.pos):getItemById(12664) ~= nil, "the chest stays while it is fresh")

-- ---- the use
local item = chestItemAt
stranger._pos = Position(101, 100, 7)
use(stranger, item, nil, nil, nil, false)
ok(stranger._cancels[#stranger._cancels]:find("not yours"), "a stranger may not open it")
eq(ch.state, "idle", "still idle")
-- the owner opens it
hero._pos = Position(101, 101, 7)
friend._pos = Position(103, 100, 7)
mkParty({hero, friend})
use(hero, item)
eq(ch.state, "running", "the use starts the event")
eq(ch.ev.players, 2, "the opener and the party member in range take part")
ok(ch.ev.participants[1] and ch.ev.participants[2], "both recorded")
ok(not ch.ev.participants[3], "the stranger is not")
use(hero, item)
ok(hero._cancels[#hero._cancels]:find("awake"), "a second use while it runs is refused")
use(friend, item)
ok(friend._cancels[#friend._cancels]:find("awake"), "the party member too")
ok(#queue >= 1, "a tick is scheduled")
-- the first horde
T = T + 3000
runQueue()
eq(ch.ev.horde, 1, "horde 1 after the delay")
local alive = 0
for _, m in pairs(monsters) do
	alive = alive + 1
	ok(m._dropLoot == false, "a husk: no corpse loot")
	ok(m._events.ChaosCursedChestDeath, "tagged with the death event")
	ok(CC.tagged[m._id] == ch, "tagged in the table")
	ok(paced[m._id] == true, "paced like a hunt")
	ok(ChaosAreaGen.scaled[m._id] ~= nil, "damage scale registered")
	eq(ChaosAreaGen.scaled[m._id].experience, 1, "experience stays normal")
	ok(not m._events.ChaosTierRollMagic, "the natural tier roll is off")
end
eq(alive, math.floor(4 * 1.35 + 0.5), "horde 1 size for two players")
ok(labels[#labels].text(hero):find("HORDE 1/5"), "label: horde 1/5")
ok(hero._msgs[#hero._msgs]:find("Horde 1/5"), "message: Horde 1/5")
-- a tagged monster never leaves a chest, nor does it count for another system
local anyMonster
for _, m in pairs(monsters) do anyMonster = m end
local before = 0
for _ in pairs(CC.chests) do before = before + 1 end
CC.state.cooldown = {}
CC.state.perOwner = {}
allHit()
drop(anyMonster, mkCorpse(1, deathPos))
local after = 0
for _ in pairs(CC.chests) do after = after + 1 end
eq(after, before, "an event monster never leaves a chest")
-- run the whole event: kill each horde, the next comes after the pause
local function killAll()
	for id, m in pairs(monsters) do
		events.ChaosCursedChestDeath.onDeath(m, nil, hero)
		monsters[id] = nil
	end
end
for horde = 1, 5 do
	eq(ch.ev.horde, horde, "horde " .. horde .. " is on")
	killAll()
	T = T + 1000
	runQueue()
	if horde < 5 then
		eq(ch.ev.horde, horde, "the next horde waits for its pause")
		T = T + cfg.event.betweenMs
		runQueue()
	end
end
eq(ch.state, "won", "after the fifth horde the chest is won")
eq(ch.ev.state, "won", "event won")
eq(chestItemAt._attrs[ITEM_ATTRIBUTE_NAME], "unsealed cursed chest", "the chest is renamed")
eq(next(CC.tagged), nil, "no tagged monsters left")
eq(next(ChaosAreaGen.scaled), nil, "no damage scale entries left")
eq(#appliedTiers > 0, true, "tiers were applied to some monsters")
local sawLeader = false
for _, t in ipairs(appliedTiers) do
	if t == "rare" or t == "legendary" then sawLeader = true end
end
ok(sawLeader, "a rare or elite appeared in the last hordes")

-- ---- the loot: once per participant, strangers refused
use(stranger, item)
ok(stranger._cancels[#stranger._cancels]:find("not yours"), "a stranger still may not use it")
local other = mkPlayer(4, 504, "Late")
other._pos = Position(101, 100, 7)
local function totalGiven(p)
	local s = 0
	for _, v in pairs(p._given) do s = s + v end
	return s + #p._items
end
use(hero, item)
ok(hero._msgs[#hero._msgs]:find("Cursed Chest loot"), "the opener gets a loot message")
local heroItems = totalGiven(hero)
ok(heroItems > 0, "and loot")
ok(hero._given[2148] or hero._given[2152] or hero._given[2160], "gold among it")
eq(hero._given[29856] ~= nil, true, "an Orb of Upheaval")
ok(#crafted >= 1, "a rolled gear piece")
ok(crafted[1]._rarity >= 3, "of a good rarity")
use(hero, item)
eq(totalGiven(hero), heroItems, "no loot twice")
ok(hero._cancels[#hero._cancels]:find("already took"), "told so")
friend._pos = Position(102, 100, 7)
use(friend, item)
ok(totalGiven(friend) > 0, "the party member takes a share")
eq(ch.state, "won", "still there until the loop sees everyone served")
think(1500)
eq(Tile(ch.pos):getItemById(12664), nil, "everyone served: the chest crumbles")
eq(next(CC.chests), nil, "and the table is empty")
eq(CC.state.alive, 0, "server count back to zero")

-- ---- failures remove the monsters and the chest
local function freshChest(owner)
	CC.state.cooldown, CC.state.perOwner = {}, {}
	allHit()
	drop(mkDying("Troll", "magic"), mkCorpse(owner:getId(), deathPos))
	local c2
	for _, c in pairs(CC.chests) do c2 = c end
	return c2
end
local function openIt(c2, who)
	who._pos = Position(c2.pos.x + 1, c2.pos.y, 7)
	use(who, Tile(c2.pos):getItemById(12664))
	T = T + 3000
	runQueue()
end
hero._party, friend._party = nil, nil
hero._pos = Position(101, 100, 7)
-- time
ch = freshChest(hero)
openIt(ch, hero)
eq(ch.ev.horde, 1, "a fresh event runs")
local spawned = 0
for _ in pairs(monsters) do spawned = spawned + 1 end
ok(spawned > 0, "with monsters")
T = T + cfg.event.totalSec * 1000
runQueue()
eq(next(monsters), nil, "time up: the monsters despawn")
eq(Tile(ch.pos):getItemById(12664), nil, "and the chest crumbles")
eq(ch.ev.state, "failed", "failed")
eq(ch.ev.reason, "time", "by time")
ok(hero._msgs[#hero._msgs]:find("time is up"), "the players are told")
eq(next(CC.tagged), nil, "tags cleaned")
eq(next(ChaosAreaGen.scaled), nil, "scale entries cleaned")
-- everyone leaves
ch = freshChest(hero)
openIt(ch, hero)
hero._pos = Position(300, 300, 7)
for _ = 1, cfg.event.emptyGraceSec + 2 do
	T = T + 1000
	runQueue()
end
eq(ch.ev.state, "failed", "everyone left: failed")
eq(ch.ev.reason, "abandoned", "abandoned")
eq(next(monsters), nil, "monsters gone")
-- everyone dies (health 0 and sent away)
hero._pos = Position(101, 100, 7)
ch = freshChest(hero)
openIt(ch, hero)
hero._hp = 0
for _ = 1, cfg.event.emptyGraceSec + 2 do
	T = T + 1000
	runQueue()
end
eq(ch.ev.state, "failed", "all participants dead: failed")
eq(next(monsters), nil, "monsters gone after a death wipe")
hero._hp = 500
-- a failed horde build (no monster can be created) does not hang the event
createFail.Troll = true
for _, name in ipairs(cfg.event.pool.themed[1][2]) do createFail[name] = true end
ch = freshChest(hero)
openIt(ch, hero)
eq(ch.ev.horde, 1, "an empty horde still counts as spawned")
for _ = 1, 40 do
	T = T + 4000
	runQueue()
end
eq(ch.state, "won", "empty hordes pass and the chest is won")
createFail = {}
use(hero, Tile(ch.pos):getItemById(12664))
-- the loop removes an unclaimed open chest
think(1500)
T = T + (cfg.event.claimSec + 5) * 1000
think(1500)
eq(next(CC.chests), nil, "an unclaimed chest crumbles after the claim time")

-- ---- an unopened chest expires
ch = freshChest(hero)
T = T + (cfg.spawn.expireSec + 1) * 1000
think(1500)
eq(Tile(ch.pos):getItemById(12664), nil, "an unopened chest crumbles")
eq(next(CC.chests), nil, "and is forgotten")

-- ---- a chest the table does not know (a restart, a reload) crumbles at the use
local ghost = Game.createItem(12664, 1, Position(120, 120, 7))
ghost:setActionId(47730)
use(hero, ghost)
ok(ghost._removed == true, "an unknown chest is removed")
ok(hero._cancels[#hero._cancels]:find("crumbles"), "with a message")
eq(next(monsters), nil, "no stuck monsters")

-- ---- a PvP place or an instance blocks the opening
clock = clock + 100000
ch = freshChest(hero)
Chaos.instanceOrder = {"fake"}
Chaos.instances.fake = {label = "a fake instance", at = function(pos) return true end}
use(hero, Tile(ch.pos):getItemById(12664))
ok(hero._cancels[#hero._cancels]:find("cannot open"), "no opening inside an instance")
eq(ch.state, "idle", "the chest stays closed")
Chaos.instanceOrder, Chaos.instances.fake = {}, nil

-- ---- the look on the map: the one-tile id, and the older ids still work like the fallback
Chaos.instanceOrder, Chaos.instances.fake = {}, nil
do
	local ids = cfg.chest.itemIds
	eq(ch.itemId, 12664, "the look is not installed on the mocked server: the chests above wore the fallback")
	installedIds[ids[1]] = true
	local info = {name = "Troll", pool = "x", gear = {}, monsterLevel = 100, tier = "magic"}
	math.random = realRandom
	local made = {}
	for k = 1, 3 do
		CC.state.cooldown, CC.state.perOwner = {}, {}
		local c3 = CC.spawnChest(hero, Position(140 + 3 * k, 140, 7), info)
		ok(c3 ~= nil, "chest " .. k .. ": made")
		eq(c3.itemId, 32281, "chest " .. k .. ": the one-tile look")
		local it = Tile(c3.pos):getItemById(32281)
		ok(it ~= nil, "chest " .. k .. ": on the map")
		eq(it._aid, 47730, "chest " .. k .. ": with the chest's action id")
		eq(it._attrs[ITEM_ATTRIBUTE_NAME], "cursed chest", "chest " .. k .. ": named")
		eq(Tile(c3.pos):getItemById(12664), nil, "chest " .. k .. ": not the fallback")
		made[k] = c3
	end
	-- the use works on the look (a stranger is refused, as on the fallback)
	for k = 1, 3 do
		stranger._pos = Position(made[k].pos.x + 1, made[k].pos.y, 7)
		use(stranger, Tile(made[k].pos):getItemById(32281))
		ok(stranger._cancels[#stranger._cancels]:find("not yours"), "chest " .. k .. ": a stranger may not use it")
		eq(made[k].state, "idle", "chest " .. k .. ": still idle")
	end
	-- an unopened chest crumbles
	T = T + (cfg.spawn.expireSec + 1) * 1000
	think(1500)
	for k = 1, 3 do
		eq(Tile(made[k].pos):getItemById(32281), nil, "chest " .. k .. ": crumbles unopened")
	end
	eq(next(CC.chests), nil, "and is forgotten")
	-- a chest of an older look that the table does not know (placed before the change) crumbles at the use, like the fallback
	for _, old in ipairs(cfg.chest.legacyItemIds) do
		local ghost2 = Game.createItem(old, 1, Position(150, 150, 7))
		ghost2:setActionId(47730)
		use(hero, ghost2)
		ok(ghost2._removed == true, "an unknown chest of the older look " .. old .. " is removed")
	end
	installedIds[ids[1]] = nil
	-- and a server that does not have the look: the fallback again
	CC.state.cooldown, CC.state.perOwner = {}, {}
	local c5 = CC.spawnChest(hero, Position(200, 200, 7), info)
	eq(c5.itemId, 12664, "none installed: the fallback chest")
	ok(Tile(c5.pos):getItemById(12664) ~= nil, "on the map")
	T = T + (cfg.spawn.expireSec + 1) * 1000
	think(1500)
	eq(Tile(c5.pos):getItemById(12664), nil, "and it crumbles")
end

print(string.format("cursedchest_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
