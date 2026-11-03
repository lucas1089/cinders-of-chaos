-- Run from the server/ folder: luajit tests/deathadvice_test.lua (or lua5.3; CI runs both)
-- Death advice (O371): the rules of deathadvice_core.lua (level gap, element against resistance, no potions, low healing,
-- a big pack, the order and the cap of 3), the facts from a rolling log, the resistance sum, the gem of each element
-- against data/lib/chaos_gems_config.lua, and deathrecap.lua against a mocked engine (healing and potion hooks, the
-- monster level, the tips stored with the recap).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/deathrecap_config.lua")
dofile("data/scripts/chaos/deathrecap_core.lua")
dofile("data/scripts/chaos/deathadvice_core.lua")
local R = ChaosDeathRecap
local A = ChaosDeathAdvice
R.configure(cfg)
local adv = cfg.advice

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function kinds(tips)
	local out = {}
	for _, t in ipairs(tips) do out[#out + 1] = t.k end
	return table.concat(out, ",")
end

-- ---------------------------------------------------------------- config
check(type(adv) == "table" and adv.enabled == true, "advice on")
eq(adv.max, 3, "at most 3 tips")
-- each element's gem gives that resistance in the named group (the client's sentence names the same gem)
local gems = dofile("data/lib/chaos_gems_config.lua")
for el, g in pairs(adv.resElements) do
	local found
	for _, t in ipairs(gems.types) do
		if t.key == g.gem then found = t end
	end
	check(found ~= nil, "gem exists: " .. g.gem)
	local eff = found and found[g.group] and found[g.group].effect
	eq(eff, "res_" .. el, "the " .. g.gem .. " in " .. g.group .. " resists " .. el)
end

-- ---------------------------------------------------------------- resistance
eq(A.combine(0, 0), 0, "nothing")
eq(A.combine(20, 0), 20, "absorb only")
eq(A.combine(0, 8), 8, "gem only")
eq(A.combine(50, 10), 55, "one after the other")
eq(A.combine(150, -5), 100, "clamped")
eq(math.floor(A.absorb({10, 20}, 0) + 0.5), 28, "items one after the other")
eq(A.absorb({50}, 60), 75, "held at the ceiling")
eq(A.absorb({}, 0), 0, "no absorb")

-- ---------------------------------------------------------------- rules
local base = {pl = 50, dur = 10000, tot = 1000, hp = 1000, heal = 0, pot = 0, pack = 1, high = {share = 0, gap = 0}}
local function with(t)
	local f = {}
	for k, v in pairs(base) do f[k] = v end
	for k, v in pairs(t) do f[k] = v end
	return f
end
eq(kinds(A.tips(with({heal = 900}), adv)), "", "a plain death with healing: no tip")
eq(kinds(A.tips(with({}), adv)), "pot", "no potions, no healing")
eq(kinds(A.tips(with({dur = 2000}), adv)), "", "a one-shot: no potion tip")
eq(kinds(A.tips(with({heal = 400}), adv)), "", "healing 40% without potions: no potion tip")
local t = A.tips(with({pot = 3, heal = 100}), adv)
eq(kinds(t), "heal", "potions but little healing")
eq(t[1].s, 10, "healing share")
eq(kinds(A.tips(with({pot = 3, heal = 100, dur = 6000}), adv)), "", "short fight: no heal tip")
t = A.tips(with({heal = 900, high = {share = 80, gap = 40}}), adv)
eq(kinds(t), "lvl", "monsters far above")
eq(t[1].d, 40, "the gap")
eq(kinds(A.tips(with({heal = 900, high = {share = 80, gap = 20}}), adv)), "", "20 levels is fine")
eq(kinds(A.tips(with({heal = 900, high = {share = 10, gap = 90}}), adv)), "", "one strong add is not the cause")
t = A.tips(with({heal = 900, top = {el = "fire", share = 62, r = 0}}), adv)
eq(kinds(t), "res", "fire and no fire resistance")
check(t[1].el == "fire" and t[1].r == 0 and t[1].s == 62, "res tip fields")
eq(kinds(A.tips(with({heal = 900, top = {el = "fire", share = 62, r = 15}}), adv)), "", "fire resisted")
eq(kinds(A.tips(with({heal = 900, top = {el = "fire", share = 30, r = 0}}), adv)), "", "fire a small share")
eq(kinds(A.tips(with({heal = 900, top = {el = "lifedrain", share = 90, r = 0}}), adv)), "", "no tip for life drain")
eq(kinds(A.tips(with({heal = 900, top = {el = "fire", share = 90}}), adv)), "", "unknown resistance: no tip")
t = A.tips(with({heal = 900, pack = 7}), adv)
eq(kinds(t), "pack", "a big pack")
eq(t[1].n, 7, "pack size")
t = A.tips(with({pack = 7, high = {share = 90, gap = 45}, top = {el = "death", share = 70, r = 2}}), adv)
eq(kinds(t), "lvl,res,pot", "rule order, cut at 3")
eq(#A.tips(with({}), {enabled = false}), 0, "advice off")
eq(#A.tips(with({tot = 0}), adv), 0, "no damage: no tip")

-- ---------------------------------------------------------------- facts from a log
do
	local log = R.newLog()
	local now = 1000000
	local function hit(dt, key, name, kind, a, el, cid, m)
		R.record(log, now + dt, {k = key, n = name, kind = kind, a = a, el = el, cid = cid, m = m})
	end
	A.setLevel(log, "c:Drake", 95)
	A.setLevel(log, "c:Rat", 2)
	A.setLevel(log, "c:Golem", 0) -- a type without a level
	hit(0, "c:Drake", "Drake", "c", 400, "fire", 11)
	hit(500, "c:Drake", "Drake", "c", 300, "fire", 12)
	hit(800, "c:Rat", "Rat", "c", 50, "physical", 13)
	hit(900, "c:Golem", "Golem", "c", 100, "earth", 14)
	hit(1000, "c:Wolf>Ash", "Wolf", "c", 150, "physical", 15, "Ash") -- a player's summon is no monster here
	A.addHeal(log, now + 200, 120)
	A.addHeal(log, now - 60000, 999) -- before the window
	A.addPotion(log, now + 300)
	local deathAt = now + 1000
	local recap = R.build(log, deathAt, {level = 50})
	local f = A.facts(log, deathAt, recap, 50, cfg.windowMs, function(el) return el == "fire" and 4 or nil end)
	eq(f.pl, 50, "level")
	eq(f.pack, 4, "distinct monsters (summon not counted)")
	eq(f.heal, 120, "healing in the window")
	eq(f.pot, 1, "one potion")
	eq(f.high.gap, 45, "gap of the hardest hitter above")
	eq(f.high.share, 70, "share of the monsters above")
	eq(f.top.el, "fire", "top element")
	eq(f.top.share, 70, "fire share")
	eq(f.top.r, 4, "fire resistance")
	eq(log.lv["c:Golem"], false, "level 0 kept as none")
	check(not A.wantLevel(log, "c:Drake"), "a level is taken once")
	local tips = A.tips(f, adv)
	eq(kinds(tips), "lvl,res", "drake death: level and fire")
	-- the bounds
	for i = 1, 100 do A.addHeal(log, now, 1, 60) end
	eq(#log.hl, 60, "healing log bounded")
	for i = 1, 100 do A.addPotion(log, now, 30) end
	eq(#log.po, 30, "potion log bounded")
end

-- ---------------------------------------------------------------- deathrecap.lua against a mocked engine
do
	local registry = {}
	function CreatureEvent(name)
		local o = {name = name}
		function o:type(t) self.t = t end
		function o:register() registry[name] = self end
		return o
	end
	function GlobalEvent(name)
		local o = {}
		function o:type() end
		function o:register() registry[name] = self end
		return o
	end
	function addEvent() end
	local clock = 9000000
	os.mtime = function() return clock end
	local stored = {}
	json = {encode = function(t) stored[#stored + 1] = t return "#" .. #stored end, decode = function() return nil end}
	db = {query = function() return true end, asyncQuery = function() return true end, escapeString = function(s) return s end,
		storeQuery = function() return false end}
	COMBAT_FIREDAMAGE, COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE = 8, 1, 2
	COMBAT_EARTHDAMAGE, COMBAT_ICEDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_DEATHDAMAGE = 4, 512, 1024, 2048
	local absorbs = {[3001] = {absorbPercent = {0, 0, 0, 5}}} -- an amulet with 5% fire (index 4 = fire, 1 << 3)
	function ItemType(id)
		return {getAbilities = function() return absorbs[id] end}
	end
	ChaosGems = {playerBonus = function(_, key) return key == "res_fire" and 3 or 0 end}
	local function mk(def)
		local c = def
		function c:getId() return self.id end
		function c:getGuid() return self.guid end
		function c:getName() return self.name end
		function c:isPlayer() return self.player == true end
		function c:isMonster() return not self.player end
		function c:getMaster() return nil end
		function c:getLevel() return self.level end
		function c:getMonsterLevel() return self.mlevel or 0 end
		function c:getExperience() return 1000 end
		function c:getHealth() return 0 end
		function c:isInGhostMode() return false end
		function c:getOutfit() return {lookType = 34} end
		function c:registerEvent() end
		function c:getSlotItem(slot) return self.slots and self.slots[slot] or nil end
		function c:getStorageValue(k) return self.storage and self.storage[k] or -1 end
		return c
	end
	dofile("data/scripts/chaos/deathrecap.lua")
	eq(ChaosCombatLog.healHook, R.onHealed, "the heal hook is set")
	check(type(R.onPotion) == "function", "the potion hook")
	local hero = mk({id = 0x10000001, guid = 7, name = "Aldric", player = true, level = 20,
		slots = {[2] = {getId = function() return 3001 end}}, storage = {[977544] = 0}})
	local fiend = mk({id = 0x40000001, name = "Fire Fiend", mlevel = 70})
	eq(R.resistOf(hero, "fire"), 7, "fire: 5% amulet, then a 3% gem")
	eq(R.resistOf(hero, "ice"), 0, "ice: nothing")
	eq(R.resistOf(hero, "lifedrain"), nil, "no tip element")
	local hook = ChaosCombatLog.takenHook
	for i = 1, 6 do
		clock = clock + 1000
		hook(hero, fiend, {n = "Fire Fiend", t = "c"}, 100, "fire", false, clock)
	end
	eq(R.logs[hero.id].lv["c:Fire Fiend"], 70, "monster level taken")
	R.onHealed(hero, 20, clock)
	R.onHealed(fiend, 20, clock) -- a monster: nothing
	registry.ChaosDeathRecapDeath.onDeath(hero, nil, fiend, fiend)
	local recap = stored[#stored]
	check(type(recap) == "table" and type(recap.tips) == "table", "tips stored with the recap")
	eq(kinds(recap.tips or {}), "lvl,res,pot", "level 50 above, fire 7% resisted, no potion")
	eq(recap.tips and recap.tips[1].d, 50, "the gap")
	eq(recap.tips and recap.tips[2].r, 7, "the resistance shown")
	-- with potions: the heal tip instead
	for i = 1, 10 do
		clock = clock + 1000
		hook(hero, fiend, {n = "Fire Fiend", t = "c"}, 100, "fire", false, clock)
	end
	R.onPotion(hero, clock)
	R.onHealed(hero, 50, clock)
	registry.ChaosDeathRecapDeath.onDeath(hero, nil, fiend, fiend)
	eq(kinds(stored[#stored].tips or {}), "lvl,res,heal", "potions drunk, healing 5%")
	-- advice off: no tips
	Chaos.deathRecapConfig.advice.enabled = false
	hook(hero, fiend, {n = "Fire Fiend", t = "c"}, 100, "fire", false, clock)
	registry.ChaosDeathRecapDeath.onDeath(hero, nil, fiend, fiend)
	eq(stored[#stored].tips, nil, "advice off")
	Chaos.deathRecapConfig.advice.enabled = true
end

print(string.format("deathadvice_test: %d checks, %d failed", count, failures))
if failures > 0 then
	os.exit(1)
end
