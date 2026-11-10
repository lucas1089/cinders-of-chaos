-- Run from the server/ folder: luajit tests/crit_cap_test.lua (and lua5.3; CI runs both)
-- O471 (2026-11-10): the character caps on critical hits (chance 45, extra damage 150, every source together) and on
-- penetration (20 points of each kind, worn pieces plus Sunder). The pure maths in data/lib/chaos_item_mods.lua
-- (config.crit, config.penetration, M.critTotals, M.critKeep, M.critFactor, M.critHit, M.critRoom, M.penLeft, the cap of
-- physpen / elepen in M.totals), the hit script data/scripts/chaos/crit_cap.lua against a mocked engine, the slots the two
-- critical modifiers roll on (ChaosCrafting.singles) and an old badge or quiver that keeps its modifier.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "expected true", 2)
	end
end
local function near(a, b, tol, m)
	checks = checks + 1
	if math.abs(a - b) > tol then
		error((m or "") .. ": " .. tostring(a) .. " is not within " .. tol .. " of " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_ATTACK_SPEED = 1, 2, 3
COMBAT_PHYSICALDAMAGE, COMBAT_HEALING = 1, 128
SPECIALSKILL_CRITICALHITCHANCE, SPECIALSKILL_CRITICALHITAMOUNT = 0, 1
RETURNVALUE_NOERROR = 0
Chaos = {}
local events, callbacks = {}, {}
CreatureEvent = function(name)
	local e = {name = name}
	function e:register() events[name] = self end
	return e
end
EventCallback = setmetatable({}, {
	__newindex = function(self, k, v) rawset(self, "_pending", {k, v}) end,
	__index = function(self, k)
		if k == "register" then
			return function(this)
				local p = rawget(this, "_pending")
				callbacks[p[1]] = p[2]
				rawset(this, "_pending", nil)
			end
		end
	end
})
local registered = {}
function Chaos.eventKnown(creature, name) return registered[creature.id .. name] == true end
function Chaos.registerOnce(creature, name)
	registered[creature.id .. name] = true
	creature.events = (creature.events or 0) + 1
end

local Creature = {}
Creature.__index = Creature
local nextId = 0
local function newCreature(kind, chance, amount)
	nextId = nextId + 1
	return setmetatable({id = nextId, kind = kind, skills = {[SPECIALSKILL_CRITICALHITCHANCE] = chance or 0,
		[SPECIALSKILL_CRITICALHITAMOUNT] = amount or 0}}, Creature)
end
function Creature:getId() return self.id end
function Creature:isPlayer() return self.kind == "player" end
function Creature:isMonster() return self.kind == "monster" end
function Creature:getSpecialSkill(i) return self.skills[i] end

dofile("data/lib/chaos_item_mods.lua")
local M = ChaosItemMods
dofile("data/scripts/chaos/crit_cap.lua")
local K = ChaosCritCap

-- a small linear congruential generator, the same on every interpreter
local function lcg(seed)
	local s = seed
	return function()
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

-- ---------------------------------------------------------------- the numbers
eq(M.config.crit.chanceCap, 45, "chance cap 45"); eq(M.config.crit.amountCap, 150, "extra damage cap 150")
eq(M.config.penetration.cap, 20, "penetration cap 20")
eq(M.byKey.physpen.cap, 20, "physpen: the cap of the totals"); eq(M.byKey.elepen.cap, 20, "elepen: the cap of the totals")
eq(M.byKey.physpen.cap, M.config.penetration.cap, "the row and the config agree")
ok(M.config.engine.critchance.tiers[8][2] <= M.config.crit.chanceCap, "no single piece beats the chance cap")
ok(M.config.engine.critdamage.tiers[8][2] <= M.config.crit.amountCap, "nor the damage cap")

-- ---------------------------------------------------------------- the totals against the caps
local t = M.critTotals(30, 100)
eq(t.chance, 30, "under both caps: as it is"); eq(t.amount, 100); eq(t.chanceCapped, false); eq(t.amountCapped, false)
t = M.critTotals(71, 300)
eq(t.chance, 45, "a dedicated build of 71 counts 45"); eq(t.amount, 150, "an amount of 300 counts 150")
eq(t.rawChance, 71); eq(t.rawAmount, 300); eq(t.chanceCapped, true); eq(t.amountCapped, true)
eq(t.chanceCap, 45); eq(t.amountCap, 150)
t = M.critTotals(45, 150); eq(t.chanceCapped, false, "exactly the cap is not over it"); eq(t.amountCapped, false)
t = M.critTotals(nil, nil); eq(t.chance, 0, "nothing"); eq(t.amount, 0)
t = M.critTotals(-5, -5); eq(t.chance, 0, "never negative")

-- ---------------------------------------------------------------- the maths of a hit
eq(M.critKeep(30), 1, "under the cap every crit stays"); eq(M.critKeep(45), 1)
near(M.critKeep(90), 0.5, 1e-9, "twice the cap keeps half"); near(M.critKeep(60), 0.75, 1e-9)
eq(M.critKeep(0), 1)
eq(M.critFactor(100), 1, "under the damage cap"); eq(M.critFactor(150), 1)
near(M.critFactor(300), 250 / 400, 1e-9, "amount 300: the extra of 150 only")
near(M.critFactor(300, true), 100 / 400, 1e-9, "a crit taken off loses its whole extra")
near(M.critFactor(0, true), 1, 1e-9, "no extra, nothing to take off")
-- a hit of 1000 the engine made at chance 60 / amount 300 (base 250)
local p, s, state = M.critHit(1000, 400, 60, 300, function() return 0 end)
eq(p, 625, "the crit stays, the extra cut to 150: 250 x 2.5"); eq(s, 250, "the secondary part follows"); eq(state, "cut")
p, s, state = M.critHit(1000, 400, 60, 300, function() return 0.99 end)
eq(p, 250, "the crit is taken off: the base hit"); eq(s, 100); eq(state, "thinned")
p, s, state = M.critHit(1000, 0, 30, 100, function() return 0.99 end)
eq(p, 1000, "under both caps nothing changes, whatever the roll"); eq(state, "kept")
p, s = M.critHit(-1000, -400, 60, 300, function() return 0 end)
eq(p, -625, "a negative value keeps its sign"); eq(s, -250)
-- over the damage cap only: no thinning
p, s, state = M.critHit(1000, 0, 40, 300, function() return 0.99 end)
eq(state, "cut", "chance under its cap: the crit is never taken off"); eq(p, 625)
-- over the chance cap only
p, s, state = M.critHit(1000, 0, 90, 100, function() return 0.9 end)
eq(state, "thinned", "chance 90, cap 45: half the crits go (roll 0.9 is above the kept half)"); eq(p, 500)
p, s, state = M.critHit(1000, 0, 90, 100, function() return 0.2 end)
eq(state, "kept", "the kept half: amount 100 under its cap"); eq(p, 1000)

-- statistics, a seeded generator: the crits that stay follow the cap. The engine rolled 60% crits; 45% must remain
do
	local r, rolled, kept, total, base = lcg(471), 40000, 0, 0, 100
	for _ = 1, rolled do
		local engineCrit = r() * 100 < 60
		local dmg = base
		if engineCrit then
			dmg = base * (100 + 300) / 100 -- the engine's crit at amount 300
			local pp = M.critHit(dmg, 0, 60, 300, r)
			dmg = pp
		end
		if dmg > base then kept = kept + 1 end
		total = total + dmg
	end
	near(kept / rolled, 0.45, 0.012, "the share of critical hits that remain is the cap")
	-- the mean damage per hit: 1 + chance x amount = 1 + 0.45 x 1.5
	near(total / rolled / base, 1 + 0.45 * 1.5, 0.035, "the mean damage is that of chance 45, extra damage 150")
end

-- ---------------------------------------------------------------- scripted crits get the room the cap leaves
near(M.critRoom(0), 45, 1e-9, "no engine chance: 45 points of room")
near(M.critRoom(30), (45 - 30) / 0.7, 1e-9, "30 from the engine: the independent roll that makes 45 in all")
eq(M.critRoom(45), 0, "at the cap: no room"); eq(M.critRoom(80), 0, "over it: none")
do
	local room = M.critRoom(30)
	near(100 * (1 - (1 - 0.30) * (1 - room / 100)), 45, 1e-9, "engine and scripted rolls together make exactly the cap")
	local r2 = M.critRoom(20, 10)
	near(100 * (1 - 0.8 * 0.9 * (1 - r2 / 100)), 45, 1e-9, "two scripted sources before it count too")
end

-- ---------------------------------------------------------------- penetration
eq(M.penLeft(0), 20, "no item penetration: Sunder may give all 20"); eq(M.penLeft(12), 8); eq(M.penLeft(20), 0); eq(M.penLeft(25), 0)
local function pieces(...)
	local items = {}
	for _, v in ipairs({...}) do
		local it = {attrs = {}}
		function it:getCustomAttribute(k) return self.attrs[k] end
		function it:setCustomAttribute(k, val) self.attrs[k] = val end
		function it:removeCustomAttribute(k) self.attrs[k] = nil end
		it:setCustomAttribute("chaos_mod_physpen", v[1])
		it:setCustomAttribute("chaos_mod_elepen", v[2])
		it:setCustomAttribute("chaos_modv", M.config.modVersion)
		items[#items + 1] = it
	end
	return items
end
local tot = M.totals(pieces({12, 12}, {12, 8}, {9, 9}))
eq(tot.physpen, 20, "33 points of physical penetration count 20"); eq(tot.elepen, 20, "29 of elemental count 20")
tot = M.totals(pieces({12, 3}, {5, 4}))
eq(tot.physpen, 17, "under the cap: as it is"); eq(tot.elepen, 7)
tot = M.totals({}, {physpen = 30, elepen = 5})
eq(tot.physpen, 20, "sets, uniques and the veiled slot come in through `extra`: capped too"); eq(tot.elepen, 5)
tot = M.totals(pieces({20, 20}))
eq(tot.physpen, 20, "exactly the cap")

-- ---------------------------------------------------------------- the hit script
local hitEv = events.ChaosCritCap
ok(hitEv ~= nil, "the hit event is registered")
local mon = newCreature("monster")
local function hit(attacker, pd, sd, critical)
	return hitEv.onHealthChange(mon, attacker, pd, COMBAT_PHYSICALDAMAGE, sd, COMBAT_PHYSICALDAMAGE, 3, critical)
end
local over = newCreature("player", 71, 300)
math.random = lcg(99) -- the event rolls with math.random() (a float)
local sawCut, sawKept = false, false
for _ = 1, 200 do
	local pd = hit(over, 1000, 0, true)
	ok(pd == 625 or pd == 250, "an engine crit of a character over both caps: cut (625) or taken off (250), got " .. tostring(pd))
	if pd == 625 then sawCut = true else sawKept = true end
end
ok(sawCut and sawKept, "both outcomes happen at chance 71")
-- the share that stays is 45 / 71
do
	local stay = 0
	for _ = 1, 20000 do
		if hit(over, 1000, 0, true) == 625 then stay = stay + 1 end
	end
	near(stay / 20000, 45 / 71, 0.015, "45 of 71 crits stay")
end
local pd, pt, sd, st = hit(over, 1000, 400, false)
eq(pd, 1000, "a hit that is not critical is never touched"); eq(sd, 400); eq(pt, COMBAT_PHYSICALDAMAGE); eq(st, COMBAT_PHYSICALDAMAGE)
local under = newCreature("player", 30, 100)
eq((hit(under, 1000, 0, true)), 1000, "a character under both caps: the crit stays whole")
local amountOnly = newCreature("player", 40, 300)
eq((hit(amountOnly, 1000, 0, true)), 625, "damage over its cap only: always cut, never taken off")
local summon = newCreature("monster", 90, 400)
eq((hit(summon, 1000, 0, true)), 1000, "a creature that is not a player has no critical totals of its own")
eq((hit(nil, 1000, 0, true)), 1000, "no attacker")
local noApi = setmetatable({id = 99, kind = "player"}, {__index = Creature})
noApi.getSpecialSkill = nil
eq((hit(noApi, 1000, 0, true)), 1000, "without the binding: nothing changes")
-- healing is never cut
local a, at = hitEv.onHealthChange(mon, over, 500, COMBAT_HEALING, 0, COMBAT_PHYSICALDAMAGE, 3, true)
eq(a, 500, "a heal"); eq(at, COMBAT_HEALING)
-- the event goes on a target only while the attacker is over a cap
eq(K.over(over), true); eq(K.over(under), false); eq(K.over(amountOnly), true); eq(K.over(newCreature("player", 45, 150)), false)
local target = newCreature("monster")
callbacks.onTargetCombat(under, target)
eq(target.events, nil, "under the caps: no event on the target")
callbacks.onTargetCombat(over, target)
eq(target.events, 1, "over a cap: the event goes on the target")
callbacks.onTargetCombat(over, target)
eq(target.events, 1, "once")
local pvpTarget = newCreature("player")
callbacks.onTargetCombat(over, pvpTarget)
eq(pvpTarget.events, 1, "a player target (PvP) gets it too")
eq(callbacks.onTargetCombat(nil, target), RETURNVALUE_NOERROR, "the callback always allows the attack")

-- ---------------------------------------------------------------- the slots of the two critical modifiers
dofile("data/lib/chaos_crafting.lua")
local C = ChaosCrafting
for _, s in ipairs(C.singles) do
	eq(s.kinds.weapon, true, s.key .. " rolls on weapons"); eq(s.kinds.jewel, true, s.key .. " on the necklace and the ring")
	eq(s.kinds.other, nil, s.key .. " no longer on the badge"); eq(s.kinds.quiver, nil, s.key .. " no longer on the quiver")
end
for _, a in ipairs(C.affixes()) do
	if a.group == "single" then
		ok(M.allowed(a, "weapon") and M.allowed(a, "jewel"), a.key .. " allowed on weapon and jewel")
		ok(not M.allowed(a, "other"), a.key .. " not on the badge (kind other)")
		ok(not M.allowed(a, "quiver"), a.key .. " not on a quiver")
		ok(not M.allowed(a, "armor") and not M.allowed(a, "helmet"), a.key .. " not on armour")
	end
end

-- an old badge and an old quiver: the modifier stays on the item and is read as it is
local function bare(attrs)
	local it = {attrs = attrs or {}}
	function it:getCustomAttribute(k) return self.attrs[k] end
	function it:setCustomAttribute(k, v) self.attrs[k] = v end
	function it:removeCustomAttribute(k) self.attrs[k] = nil end
	function it:getId() return 1 end
	function it:getAttribute() return "" end
	return it
end
for _, name in ipairs({"badge", "quiver"}) do
	local old = bare({rarity_criticalHitChance = 8, rarity_criticalHitAmount = 35, rarity = 4, chaos_modv = M.config.modVersion})
	local found = {}
	for _, m in ipairs(C.readMods(old)) do found[m.key] = m.value end
	eq(found.rarity_criticalHitChance, 8, "an old " .. name .. " keeps its Critical Strike Chance")
	eq(found.rarity_criticalHitAmount, 35, "and its Critical Strike Damage")
end
-- what such an item adds still clamps with the rest: a character wearing badge + quiver + weapon + two jewels at T8 reaches
-- 5 x 8 = 40 gear points, plus a tree and gems: over 45 is cut
local worn = M.critTotals(5 * 8 + 30 * 0.7 + 7 + 5, 5 * 38 + 35 + 75)
eq(worn.chance, 45, "five T8 pieces, tree, trial and gems: 45 counts"); eq(worn.amount, 150)
ok(worn.chanceCapped and worn.amountCapped, "both are over")

print("crit_cap_test: " .. checks .. " checks OK")
