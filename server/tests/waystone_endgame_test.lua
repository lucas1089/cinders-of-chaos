-- Run from the server/ folder: luajit tests/waystone_endgame_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Waystone endgame (O666): the deep tiers' config and factors, the band bosses (config, files, the spawn rule, the table), the corrupted
-- waystone (the Void Orb: check, apply, break, no orb after, merge into the run's list, bonus), the endgame atlas (tiers paid in a bit mask,
-- ranks, spending, effects) and waystone_endgame.lua against a mocked engine (first clear, chest, band boss, density, onRunCleared,
-- the atlas actions).
local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

local unpack = table.unpack or unpack
local seed = 4242
local function rand(a, b)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return a + seed % (b - a + 1)
end

local tcfg = dofile("data/scripts/chaos/waystone_tiers_config.lua")
dofile("data/scripts/chaos/waystone_tiers_core.lua")
local TK = ChaosWaystoneTiersCore
local cfg = dofile("data/scripts/chaos/waystone_endgame_config.lua")
dofile("data/scripts/chaos/waystone_endgame_core.lua")
local E = ChaosWaystoneEndgameCore
local bal = dofile("data/scripts/chaos/waystone_endgame_balance_config.lua")

-- ================================================================== the deep tiers
eq(#tcfg.tiers, 25, "25 tiers")
eq(tcfg.tiers[16].level, 2600, "XVI at 2600")
eq(tcfg.tiers[25].level, 3500, "XXV at 3500")
eq(#tcfg.bands, 4, "four bands")
eq(tcfg.bands[4].name, "deep", "the fourth band")
local ids = {}
for t = 16, 25 do
	eq(tcfg.tiers[t].item, 41944 + t, "tier " .. t .. " item")
	check(not ids[tcfg.tiers[t].item], "tier " .. t .. " item once")
	ids[tcfg.tiers[t].item] = true
end
-- the deep factors: 1 below XVI, then base + perTier x steps, positive
for t = 1, 15 do
	local d = TK.deep(tcfg, t)
	check(d.health == 1 and d.damage == 1 and d.experience == 1, "no deep factor at tier " .. t)
end
for t = 16, 25 do
	local d = TK.deep(tcfg, t)
	check(d.health > 1 and d.damage > 0 and d.experience > 1, "deep factors at tier " .. t)
end
eq(TK.deep(tcfg, 16).health, tcfg.deep.health.base, "XVI is the base")
check(TK.deep(tcfg, 25).experience > TK.deep(tcfg, 16).experience, "the experience factor rises")
-- a monster of a deep run: the engine's level formula x the deep factors
local mon = {tier = 5, boss = false, map = 9, run = 25}
local f = TK.factors(tcfg, mon, 540)
local plain = TK.scale(tcfg, 540, 3500)
check(math.abs(f.health - plain.health * TK.deep(tcfg, 25).health) < 1e-9, "monster health x the deep factor")
check(math.abs(f.experience - plain.experience * TK.deep(tcfg, 25).experience) < 1e-9, "experience x the deep factor")
local mon15 = {tier = 5, boss = false, map = 9, run = 15}
check(math.abs(TK.factors(tcfg, mon15, 540).health - TK.scale(tcfg, 540, 2500).health) < 1e-9, "tier XV unchanged")
-- a band boss scales from its own level: its file's health at its own tier, a lower tier gets less
local band = {tier = 6, boss = true, band = true, map = 12, run = 25, native = 3500}
check(math.abs(TK.factors(tcfg, band, nil).health - 1) < 1e-9, "band boss at its tier: factor 1")
local low = {tier = 6, boss = true, band = true, map = 12, run = 20, native = 3500}
check(TK.factors(tcfg, low, nil).health < 1, "band boss of a lower run: less health")
check(math.abs(TK.damageMult(tcfg, band, nil) - 1) < 1e-9, "band boss: no base-tier boss damage factor")
check(TK.damageMult(tcfg, {tier = 6, boss = true, map = 12, run = 25}, nil) > 1.5, "a map boss keeps bossDamage")
-- drops stop at XXV
eq(TK.dropTier(tcfg, 25, 100), 25, "drops never above XXV")
eq(TK.bossDrop(tcfg, 24), 25, "the boss of XXIV adds XXV")
-- the deep band opens the maps of base tiers IV-VI
local o = TK.baseTiersOf(tcfg, 16)
eq(#o, 3, "the deep band: three base tiers")
eq(TK.defaultTier(tcfg, 7), 6, "a mid map counts at its first tier of the first band that lists it")
eq(TK.defaultTier(tcfg, 12), 11, "a high map counts at tier XI until its first run")

-- ================================================================== band bosses
eq(#cfg.bandBosses, 4, "four band bosses")
local seenTier = {}
for _, b in ipairs(cfg.bandBosses) do
	local lastOfBand = false
	for _, band in ipairs(tcfg.bands) do
		if band.last == b.tier then
			lastOfBand = true
		end
	end
	check(lastOfBand, b.monster .. ": the last tier of a band")
	check(not seenTier[b.tier], b.monster .. ": one boss a band")
	seenTier[b.tier] = true
	local f = io.open("data/monster/monsters/chaos/waystone_bosses/" .. b.file .. ".xml")
	check(f ~= nil, b.monster .. ": its file")
	if f then
		local text = f:read("*a")
		f:close()
		check(text:find('<monster name="' .. b.monster .. '"', 1, true) ~= nil, b.monster .. ": the name in its file")
		check(text:find('<flag isboss="1" />', 1, true) ~= nil, b.monster .. ": a boss flag")
		local look = tonumber(text:match('<look type="(%d+)"'))
		check(look == 2234 or look == 229 or look == 204 or look == 591, b.monster .. ": an existing boss outfit of the bounty pool (" .. tostring(look) .. ")")
		check(not (look >= 2127 and look <= 2131), b.monster .. ": not a raid boss outfit (raid_test: its alone)")
	end
	eq(E.bandBoss(cfg, tcfg, b.tier), b, b.monster .. ": by tier")
end
eq(E.bandBoss(cfg, tcfg, 6), nil, "no boss at tier VI")
local row, bnd = E.bandBossOfBand(cfg, tcfg, 22)
eq(row.tier, 25, "a deep run's band boss is the tier XXV one")
eq(bnd.name, "deep", "its band")
check(E.bandSpawns(cfg, tcfg, 25, 0, 100), "always at the last tier")
check(E.bandSpawns(cfg, tcfg, 5, 0, 100), "always at tier V")
check(not E.bandSpawns(cfg, tcfg, 3, 0, 1), "never without chance")
check(E.bandSpawns(cfg, tcfg, 3, 24, 24), "by the atlas chance")
check(not E.bandSpawns(cfg, tcfg, 3, 24, 25), "above the chance")
-- the table: pieces, unique rolls, Void Orbs, orbs
local plan = E.bandPlan(cfg, cfg.bandBosses[4], rand)
eq(plan.pieces, 6, "XXV: 6 pieces on top")
eq(plan.uniqueRolls, 6, "XXV: 6 unique rolls on top")
check(plan.void >= 0 and plan.void <= 3, "Void Orbs 0-3")
local voids = 0
for _ = 1, 200 do
	voids = voids + (E.bandPlan(cfg, cfg.bandBosses[4], rand).void > 0 and 1 or 0)
end
check(voids > 150, "XXV drops Void Orbs on most kills (" .. voids .. "/200)")
local chest = E.chestPlan(cfg, 25, rand)
check(#chest >= 2, "the chest holds orbs")
local c1 = E.chestPlan(cfg, 1, function() return 10001 end)
check(#c1 == 2 and c1[1].count == 1, "a tier I chest: whole orbs only")

-- ================================================================== corruption
local R, W
do
	dofile("data/scripts/chaos/waystone_mods_core.lua")
	W = ChaosWaystoneModsCore
	R = ChaosRiftCore
end
local mcfg = dofile("data/scripts/chaos/waystone_mods_config.lua")
local function defOf(k) return (R.modDef(mcfg, k)) end
for _, row in ipairs(cfg.corrupt.pool) do
	local def = defOf(row[1])
	check(def ~= nil, row[1] .. ": a waystone modifier")
	if def then
		local v = E.value(row, def)
		if def.range[2] > 1 then
			check(v > def.range[2], row[1] .. ": above the normal top (" .. v .. " > " .. def.range[2] .. ")")
		else
			eq(v, 1, row[1] .. ": a flag stays 1")
		end
	end
end
eq(select(2, E.corruptCheck(cfg, {}, {})), "wsNoMods", "a Normal waystone has nothing to corrupt")
eq(select(2, E.corruptCheck(cfg, {{key = "vitality", value = 30}}, {{key = "keen", value = 50}})), "corrupted", "corrupted is final")
eq(E.corruptCheck(cfg, {{key = "vitality", value = 30}}, {}), true, "a Magic waystone may be corrupted")
local broken, made, sizes = 0, 0, {}
for i = 1, 2000 do
	local held = {{key = "vitality", value = 30}}
	local r = E.corrupt(cfg, held, defOf, rand, R.modConflict)
	if r.broken then
		broken = broken + 1
	else
		made = made + 1
		sizes[#r.corrupt] = (sizes[#r.corrupt] or 0) + 1
		local keys = {}
		for _, m in ipairs(r.corrupt) do
			check(m.key ~= "vitality", "never a held key")
			check(not keys[m.key], "no key twice")
			keys[m.key] = true
		end
	end
end
check(broken > 200 and broken < 420, "about 15% break (" .. broken .. "/2000)")
check((sizes[2] or 0) > (sizes[3] or 0) and (sizes[3] or 0) > 0, "2 or 3 modifiers, 2 more often")
check(not sizes[1] and not sizes[4], "never 1 or 4")
-- the attribute text
local list = {{key = "keen", value = 70}, {key = "dread", value = 84}}
local text = E.encode(list)
eq(text, "keen:70,dread:84", "encode")
local back = E.decode(cfg, text, defOf)
eq(#back, 2, "decode: two")
eq(back[1].key, "keen", "decode: key")
eq(#E.decode(cfg, "nonsense:5,vitality:99999", defOf), 1, "decode: unknown keys dropped")
eq(E.decode(cfg, "vitality:99999", defOf)[1].value, E.value({"vitality", 1.4, 10}, defOf("vitality")), "decode: a value is clamped to the pool's top")
local merged = E.merge({{key = "vitality", value = 30}, {key = "keen", value = 20}}, {{key = "keen", value = 50}, {key = "dread", value = 80}})
eq(#merged, 3, "merge: a key once")
eq(merged[2].value, 20, "merge: the waystone's own value stays")
-- the orbs through waystone_mods_core.lua with the engine part present
_G.ChaosWaystoneEndgame = {voidApply = function(_, ws, d, conflict) return E.corrupt(cfg, ws.mods, d, rand, conflict) end}
local ws = {tier = 12, mods = {{key = "vitality", value = 30}}}
eq(W.orbCheck(mcfg, "void", ws), true, "void on a Magic waystone")
eq(select(2, W.orbCheck(mcfg, "void", {tier = 12, mods = {}})), "wsNoMods", "void on a Normal one")
local okA, res = W.orbApply(mcfg, "void", {tier = 12, mods = {{key = "vitality", value = 30}}}, rand)
check(okA and (res.broken or #res.corrupt >= 2), "void applies: broken or 2+ modifiers")
local corrupted = {tier = 12, mods = {{key = "vitality", value = 30}}, corrupt = {{key = "keen", value = 70}}}
for _, orb in ipairs({"transmutation", "alchemy", "exalted", "divine", "chaos", "annulment", "scouring", "void", "sockets"}) do
	eq(select(2, W.orbCheck(mcfg, orb, corrupted)), "corrupted", orb .. " refuses a corrupted waystone")
end
check(W.itemName(mcfg, corrupted):find("^Corrupted ") ~= nil, "the name says Corrupted")
check(W.describe(mcfg, corrupted, 3100):find("Corrupted: ", 1, true) ~= nil, "the description lists the corrupted modifiers")
_G.ChaosWaystoneEndgame = nil
eq(select(2, W.orbCheck(mcfg, "void", ws)), "wsOrb", "without the endgame file the Void Orb refuses")
-- the bonus sits inside the break-even bounds of the model
local cap = mcfg.bonusCap
check(cap.quantity + cfg.corrupt.bonus.quantity <= cap.quantity * bal.limits.corruptQuantityVsRare, "corrupted quantity within the model bound")
check(cfg.corrupt.breakChance <= bal.limits.corruptBreakMax, "break chance within the model bound")

-- ================================================================== the atlas
local mask = 0
eq(E.paidCount(mask), 0, "no tier paid")
mask = E.markPaid(mask, 1)
mask = E.markPaid(mask, 25)
mask = E.markPaid(mask, 25)
check(E.tierPaid(mask, 1) and E.tierPaid(mask, 25) and not E.tierPaid(mask, 2), "tiers paid by bit")
eq(E.paidCount(mask), 2, "two paid, a tier once")
eq(mask, 1 + 2 ^ 24, "the mask is plain arithmetic")
check(mask < 2147483647, "the 25 tiers fit a storage (int32)")
check(2 ^ 25 - 1 < 2147483647, "all 25 fit")
local ranks = E.ranks(cfg, 0)
eq(E.free(cfg, mask, ranks), 2, "two points to spend")
local ok1, _, r1 = E.spend(cfg, mask, ranks, "density")
check(ok1 and r1.density == 1, "a rank of density")
local ok2, why2 = E.spend(cfg, 0, ranks, "density")
check(not ok2 and why2 == "points", "no point, no rank")
check(select(2, E.spend(cfg, mask, ranks, "nothing")) == "unknown", "unknown stat")
local full = {}
for _, s in ipairs(cfg.atlas.stats) do full[s.key] = s.maxRank end
check(select(2, E.spend(cfg, 2 ^ 25 - 1, full, "density")) == "maxed", "a stat stops at its top rank")
local packed = E.packRanks(cfg, {density = 3, bossChance = 1, chestChance = 0, fragmentChance = 5})
eq(packed, 5013, "ranks as decimal places (first stat the lowest)")
local back2 = E.ranks(cfg, packed)
eq(back2.density, 3, "unpack density")
eq(back2.fragmentChance, 5, "unpack fragment chance")
eq(E.ranks(cfg, 9999).density, cfg.atlas.stats[1].maxRank, "a digit above the top is cut")
local fx = E.effects(cfg, back2)
eq(fx.density, 18, "density 3 x 6%")
eq(fx.fragmentChance, 20, "fragment chance 5 x 4%")
local fullPts = 0
for _, s in ipairs(cfg.atlas.stats) do fullPts = fullPts + s.maxRank * cfg.atlas.cost end
check(#tcfg.tiers <= fullPts * bal.limits.atlasFullShare, "the points do not fill every stat")
check(#tcfg.tiers >= fullPts * 0.5, "the points buy at least half")

-- ================================================================== waystone_endgame.lua against a mocked engine
do
	local storage, sent, scheduled, created = {}, {}, {}, {}
	local players = {}
	local MAP = 10 -- map index 10: base tier V, high band (tier 11-15 runs) and the deep band
	local mp = tcfg.maps[MAP]
	local POS = {x = mp.from.x + 5, y = mp.from.y + 5, z = mp.from.z}
	_G.Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
	_G.CONST_ME_TELEPORT, _G.CONST_ME_MAGIC_BLUE, _G.MESSAGE_EVENT_ADVANCE = 1, 2, 3
	_G.addEvent = function(fn, ms, ...) scheduled[#scheduled + 1] = {fn = fn, ms = ms, args = {...}} end
	local monsters = {}
	_G.Game = {createMonster = function(name, pos)
		local m = {id = 9000 + #created, name = name, pos = pos}
		function m:getId() return self.id end
		function m:getName() return self.name end
		function m:registerEvent() end
		function m:getPosition() return self.pos end
		created[#created + 1] = m
		monsters[m.id] = m
		return m
	end}
	_G.Creature = function(id) return monsters[id] end
	local function mkPlayer(guid, id)
		local p = {guid = guid, id = id, items = {}, msgs = {}, gold = 10000000}
		function p:getGuid() return self.guid end
		function p:getId() return self.id end
		function p:getStorageValue(k) return storage[guid .. ":" .. k] or -1 end
		function p:setStorageValue(k, v) storage[guid .. ":" .. k] = v end
		function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
		function p:addItem(id, n) self.items[id] = (self.items[id] or 0) + n return true end
		players[#players + 1] = p
		return p
	end
	_G.Player = function(id)
		for _, p in ipairs(players) do
			if p.id == id then return p end
		end
		return nil
	end
	_G.Chaos = {
		t = function(_, f, ...) return string.format(f, ...) end,
		tx = function(_, text) return text end,
		send = function(player, op, action, data) sent[#sent + 1] = {p = player, op = op, action = action, data = data} end,
		storage = {waystoneEndgame = 7103300},
		pay = function(player, n) if player.gold >= n then player.gold = player.gold - n return true end return false end
	}
	_G.ChaosOpcodes = {waystoneAtlas = 159}
	_G.ChaosWaystoneTiers = {config = tcfg, onRunCleared = nil}
	local a, b = mkPlayer(1, 101), mkPlayer(2, 102)
	_G.ChaosWaystoneAtlas = {runs = {[MAP] = {opener = 1}}, online = {[1] = 101, [2] = 102}, playersInMap = function(i)
		if i == MAP then return {a, b} end
		return {}
	end}
	dofile("data/scripts/chaos/waystone_endgame.lua")
	local EG = ChaosWaystoneEndgame
	eq(EG.state(a).points, 0, "a fresh character: no points")
	-- the first clear of tier 12: everyone in the map is paid once
	local cleared = {}
	_G.ChaosWaystoneTiers.onRunCleared = function(info) cleared[#cleared + 1] = info end
	local boss = {id = 5, name = "Morgrath the Umbral Archmage"}
	function boss:getId() return self.id end
	function boss:getName() return self.name end
	function boss:getPosition() return POS end
	local entry = {tier = 5, boss = true, map = MAP, run = 12}
	EG.onMapBossDeath(entry, boss)
	eq(EG.state(a).points, 1, "the first clear: a point")
	eq(EG.state(b).points, 1, "for everyone in the map")
	check(a.msgs[1] and a.msgs[1]:find("first clear of tier 12", 1, true), "the message names the tier")
	EG.onMapBossDeath(entry, boss)
	eq(EG.state(a).points, 1, "the same tier pays once")
	eq(#cleared, 2, "onRunCleared fires on every clear")
	eq(cleared[1].tier, 12, "the info: tier")
	eq(cleared[1].map, MAP, "the info: map")
	eq(cleared[1].opener, 1, "the info: the opener")
	eq(cleared[1].fragmentChance, 0, "the info: fragment chance (no rank)")
	eq(cleared[1].band, false, "the info: a map boss")
	check(#created == 0, "tier XII is not the band's last tier and no rank: no band boss")
	-- a deep run: the band boss always
	entry = {tier = 5, boss = true, map = MAP, run = 25}
	EG.onMapBossDeath(entry, boss)
	for _, s in ipairs(scheduled) do
		if s.ms == 1500 then s.fn(unpack(s.args)) end
	end
	eq(#created, 1, "tier XXV: the band boss appears")
	eq(created[1].name, "Vharkul the Embered Tyrant", "the tier XXV boss")
	local be = EG.bandEntry(created[1])
	check(be and be.boss and be.band and be.run == 25 and be.native == 3500, "the band boss is an entry of the run at its own level")
	eq(be.tier, tcfg.maps[MAP].tier, "its base tier is the map's")
	-- its death clears the run again, flagged band
	EG.onMapBossDeath(be, created[1])
	eq(cleared[#cleared].band, true, "the band boss's death: a band clear")
	eq(EG.bandEntry(created[1]), nil, "and it is forgotten")
	-- the atlas: spend, refuse, reset, actions
	local ok, why = EG.spend(a, "density")
	check(ok, "spend a point: " .. tostring(why))
	eq(EG.state(a).ranks.density, 1, "a rank of density")
	check(not EG.spend(b, "density") == false, "b has points too")
	for _ = 1, 4 do EG.spend(b, "density") end
	check(EG.spend(a, "density"), "the second point buys the second rank")
	local again, whyAgain = EG.spend(a, "density")
	check(not again and whyAgain:find("no atlas point", 1, true), "no point left: " .. tostring(whyAgain))
	eq(EG.fxOfPlayer(a).density, 12, "the effect: 2 ranks x 6%")
	check(EG.onAction(a, "eg_open", {}) and sent[#sent].action == "eg_state", "eg_open answers eg_state")
	eq(sent[#sent].data.points, 2, "the state: two tiers paid (12 and 25)")
	local pl = sent[#sent].data
	eq(#pl.levels, 25, "O670: the payload carries the level of every tier")
	eq(pl.levels[16], 2600, "O670: tier XVI is level 2600")
	eq(pl.deepFrom, 16, "O670: the deep band starts at tier XVI")
	eq(#pl.bosses, 4, "O670: four band bosses")
	eq(pl.bosses[4].name, "Vharkul the Embered Tyrant", "O670: the last band boss")
	check(EG.onAction(a, "eg_reset", {}), "eg_reset")
	eq(EG.state(a).spent, 0, "a reset gives the ranks back")
	eq(a.gold, 10000000 - cfg.atlas.respecGold, "and costs the respec gold")
	check(not EG.onAction(a, "other", {}), "an unknown action is not answered")
	-- the chest and the fragment chance come from the opener's ranks
	storage["1:" .. 7103301] = E.packRanks(cfg, {density = 0, bossChance = 0, chestChance = 5, fragmentChance = 5})
	eq(EG.fragmentChance(MAP), 20, "the opener's fragment chance")
	cleared = {}
	math.randomseed(3)
	local got = 0
	for _ = 1, 40 do
		a.items = {}
		EG.onMapBossDeath({tier = 5, boss = true, map = MAP, run = 20}, boss)
		if next(a.items) then got = got + 1 end
	end
	check(got > 5 and got < 40, "the chest comes on about 30% of the clears (" .. got .. "/40)")
	eq(cleared[1].fragmentChance, 20, "onRunCleared carries the fragment chance")
	-- density: at most maxAlive clones, a clone's death frees its place
	storage["1:" .. 7103301] = E.packRanks(cfg, {density = 5})
	_G.ChaosSpawnTile = {find = function(p) return {x = p.x + 1, y = p.y, z = p.z} end}
	local mon = {id = 77, name = "Hellmaw Brute"}
	function mon:getId() return self.id end
	function mon:getName() return self.name end
	function mon:getPosition() return POS end
	local n0 = #scheduled
	for _ = 1, 60 do
		EG.onMonsterDeath({tier = 5, boss = false, map = MAP, run = 12}, mon)
	end
	check(#scheduled > n0, "density schedules clones")
	for i = n0 + 1, #scheduled do
		scheduled[i].fn(unpack(scheduled[i].args))
	end
	check((EG.cloneCount[MAP] or 0) >= 1 and (EG.cloneCount[MAP] or 0) <= cfg.density.maxAlive, "clones alive: 1 to the cap")
	local before = EG.cloneCount[MAP]
	local firstId = next(EG.cloneIds)
	EG.onMonsterDeath({tier = 5, boss = false, map = MAP, run = 12}, {getId = function() return firstId end})
	eq(EG.cloneCount[MAP], before - 1, "a clone's death frees its place")
end

print(string.format("waystone_endgame_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
