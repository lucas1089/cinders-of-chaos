-- archetypes_core.lua: the pure rules of the build archetype keystones (ChaosArchetypesCore). No engine calls: plain
-- numbers and tables in, numbers and tables out, so server/tests/archetypes_test.lua covers every rule.
-- Numbers: archetypes_config.lua. Engine glue: archetypes.lua. Design and builds: docs/BUILDS.md.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosArchetypesConfig = ChaosArchetypesConfig or dofile("data/scripts/chaos/archetypes_config.lua")

ChaosArchetypesCore = ChaosArchetypesCore or {}
local A = ChaosArchetypesCore
A.cfg = ChaosArchetypesConfig
local function cfg()
	return A.cfg
end

-- the flags in the order of the nodes (also the order of the client's names)
A.FLAGS = {}
for _, n in ipairs(ChaosArchetypesConfig.nodes) do
	A.FLAGS[#A.FLAGS + 1] = n.flag
end

-- ------------------------------------------------------------------------------------------------ small helpers
-- scale a damage value keeping its sign, rounding toward zero
function A.scale(v, m)
	local a = math.floor(math.abs((v or 0) * m) + 1e-6)
	return (v or 0) < 0 and -a or a
end

-- tiles between two positions (king moves); other floors are out of reach
function A.distance(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- the archetype flags a bonus table holds: {flag = true}
function A.flagsOf(bonuses)
	local out, any = {}, false
	for _, flag in ipairs(A.FLAGS) do
		if bonuses and (bonuses[flag] or 0) > 0 then
			out[flag] = true
			any = true
		end
	end
	return out, any
end

-- may class `classKey` take the keystone `flag` (nil list = every class)
function A.classMay(flag, classKey)
	local list = cfg().classes[flag]
	if not list then
		return true
	end
	for _, k in ipairs(list) do
		if k == classKey then
			return true
		end
	end
	return false
end

-- candidates {id, pos} within radius of center, not in `exclude`, nearest first (ties: lowest id), at most max
function A.pickNear(candidates, center, radius, exclude, max)
	local list = {}
	for _, c in ipairs(candidates or {}) do
		local d = A.distance(c.pos, center)
		if d <= radius and not (exclude and exclude[c.id]) then
			list[#list + 1] = {id = c.id, pos = c.pos, d = d}
		end
	end
	table.sort(list, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.id < b.id
	end)
	for i = #list, (max or #list) + 1, -1 do
		list[i] = nil
	end
	return list
end

-- ------------------------------------------------------------------------------------------------ prices (own damage)
-- The multiplier of an own hit. ctx = {origin = "melee" | "ranged" | "spell" | "condition" | "other", bow = bool
-- (a bow / crossbow hit), critical = bool, source = nil | "pyre" | "relic" | "effigy" | ... (a hit of an archetype
-- itself: the prices of that archetype do not apply to it), snare = bool (a snare's hit, snares_config.lua storage.hit)}.
-- Type-dependent prices: typeFactor.

-- the configs of the second round's keystones (their numbers live with their systems)
function A.snaresConfig()
	ChaosSnaresConfig = ChaosSnaresConfig or dofile("data/scripts/chaos/snares_config.lua")
	return ChaosSnaresConfig
end

function A.vigilsConfig()
	ChaosVigilsConfig = ChaosVigilsConfig or dofile("data/scripts/chaos/vigils_config.lua")
	return ChaosVigilsConfig
end
function A.hitFactor(flags, ctx)
	local m = 1
	local c = cfg()
	if flags.arPyreOath and ctx.source ~= "pyre" then
		m = m * c.arPyreOath.ownDamage
	end
	if flags.arThornbound and ctx.source ~= "reflect" then
		m = m * c.arThornbound.ownDamage
	end
	if flags.arReliquary and ctx.source ~= "relic" then
		m = m * c.arReliquary.ownDamage
	end
	-- Covenant of Vigils: every hit of yours (vigils_config.lua keystone.ownDamage)
	if flags.arVigils then
		m = m * A.vigilsConfig().keystone.ownDamage
	end
	-- Snarewright's Creed: every hit that is not a snare's (and not damage over time) (snares_config.lua keystone)
	if flags.arSnarewright and not ctx.snare and ctx.origin ~= "condition" then
		m = m * A.snaresConfig().keystone.otherDamage
	end
	if not ctx.source then
		local weapon = ctx.origin == "melee" or ctx.origin == "ranged"
		if flags.arContagion and weapon then
			m = m * c.arContagion.weaponDamage
		end
		if flags.arCascade and not ctx.critical and ctx.origin ~= "condition" then
			m = m * c.arCascade.nonCrit
		end
		if flags.arStormstring and ctx.origin == "ranged" and ctx.bow then
			m = m * c.arStormstring.mainDamage
		end
		if flags.arEffigy and ctx.origin == "spell" then
			m = m * c.arEffigy.ownSpell
		end
	end
	return m
end

-- the multiplier of one damage half of type `ctype` ("fire", "ice", "energy", "holy", "physical", ...)
function A.typeFactor(flags, ctype, ctx)
	local m = 1
	local c = cfg()
	if flags.arWinterLattice and (ctype == "fire" or ctype == "energy") then
		m = m * c.arWinterLattice.otherElements
	end
	if flags.arCinderSigil and ctype ~= "fire" and ctype ~= "holy" and not (ctx and ctx.source == "sigil") then
		m = m * c.arCinderSigil.otherDamage
	end
	return m
end

-- ------------------------------------------------------------------------------------------------ Pyre Oath
-- the aura's fire damage per enemy and tick (before tree bonuses: it is dealt like a spell)
function A.pyreAura(maxHealth, unique)
	local p = cfg().arPyreOath
	return math.floor((maxHealth or 0) * p.auraShare * (1 + (unique and p.uniqueAura or 0)))
end

-- the self burn of a tick: never lethal (health + shield - 1 at most)
function A.pyreBurn(maxHealth, health, shield)
	local p = cfg().arPyreOath
	local burn = math.floor((maxHealth or 0) * p.selfBurn)
	return math.max(0, math.min(burn, (health or 0) + (shield or 0) - 1))
end

function A.pyreRegen(maxHealth)
	return math.floor((maxHealth or 0) * cfg().arPyreOath.regen)
end

-- the aura burns while out of a protection zone and in a fight or with an enemy in reach
function A.pyreActive(inPz, inFight, enemyNear)
	return not inPz and (inFight == true or enemyNear == true)
end

-- ------------------------------------------------------------------------------------------------ Sanguine Covenant
-- state = {start, sum, frac}: the leech of the last second and the fraction of a health point carried to the next hit.
-- Returns the health to give for a hit that did `amount` damage at `now`.
-- Fix (2026-10, owner item C2: the Sanguine Covenant leech "does not work"): the share was floored per hit, so every hit
-- under 20 damage (5%) gave 0 and an early character never saw a heal; the fraction is carried now. A hit that did no
-- damage (0, nil, not a number) gives nothing and touches no state.
function A.leech(state, now, amount, maxHealth, unique)
	amount = tonumber(amount) or 0
	if amount == 0 or amount ~= amount then
		return 0
	end
	local s = cfg().arSanguine
	local share = s.share + (unique and s.uniqueShare or 0)
	local cap = math.floor((maxHealth or 0) * (s.capPerSecond + (unique and s.uniqueCap or 0)))
	if not state.start or now - state.start >= 1000 then
		state.start, state.sum = now, 0
	end
	local want = math.abs(amount) * share + (state.frac or 0)
	local whole = math.floor(want + 1e-9)
	local give = math.max(0, math.min(whole, cap - state.sum))
	state.sum = state.sum + give
	state.frac = (give == whole) and math.max(0, want - whole) or 0 -- the cap eats the rest
	return give
end

-- The damage that really landed: the health the target lost, at most the hit. The hit event sees the damage before the
-- later events (a boss ward that is immune, a shield, an absorb) change it, and a hit can be larger than what was left
-- (overkill), so the leech reads the target's health after the hit. Nothing lost (immune target, zero damage, a target
-- that was healed meanwhile) is 0: no heal and no division.
function A.landed(amount, healthBefore, healthAfter)
	amount, healthBefore, healthAfter = tonumber(amount) or 0, tonumber(healthBefore) or 0, tonumber(healthAfter) or 0
	local lost = healthBefore - healthAfter
	if lost <= 0 or amount <= 0 then
		return 0
	end
	return math.min(math.abs(amount), lost)
end

function A.healingTaken(value)
	return A.scale(value, cfg().arSanguine.healingTaken)
end

-- ------------------------------------------------------------------------------------------------ Thornbound Oath
-- the reflected damage of a hit. t = {landed, itemReflect (percent of the items), ownMaxHealth, ownLevel, unique,
-- pvp = bool, targetMaxHealth (players), boss = bool, bossState = {start, sum} (per boss), now}
function A.reflect(t)
	local r = cfg().arThornbound
	local share = r.share + (t.unique and r.uniqueShare or 0) + (t.itemReflect or 0) / 100
	local amount = math.floor(math.abs(t.landed or 0) * share)
	amount = math.min(amount, math.floor((t.ownMaxHealth or 0) * r.ownCap))
	if t.pvp then
		amount = math.floor(amount * r.pvpScale)
		amount = math.min(amount, math.floor((t.targetMaxHealth or 0) * r.pvpCap))
	end
	if t.boss then
		amount = math.floor(amount * r.bossScale)
		local s = t.bossState
		if s then
			if not s.start or t.now - s.start >= 1000 then
				s.start, s.sum = t.now, 0
			end
			local cap = math.floor((t.ownLevel or 0) * r.bossPerLevel)
			amount = math.max(0, math.min(amount, cap - s.sum))
			s.sum = s.sum + amount
		end
	end
	return math.max(0, amount)
end

-- ------------------------------------------------------------------------------------------------ Open Hand Creed
-- the engine's maximum weapon damage (Weapons::getMaxWeaponDamage), as monk_chi_core.lua
function A.maxWeaponDamage(level, skill, attack, attackFactor)
	attackFactor = attackFactor or 1
	return math.floor((level or 0) / 5) + ((((skill or 0) / 4) + 1) * ((attack or 0) / 3) * 1.03) / attackFactor
end

function A.fistAttack(level)
	local o = cfg().arOpenHand
	return math.min(o.attackMax, o.attackBase + (level or 0) * o.attackPerLevel)
end

-- the factor an engine fist hit is scaled by. keystone / unique: what the player has; nil when neither
function A.openHandFactor(level, fistSkill, bestSkill, attackFactor, keystone, unique)
	local o = cfg().arOpenHand
	local m
	if keystone then
		m = o.damage * (unique and (1 + o.uniqueBonus) or 1)
	elseif unique then
		m = o.damage * o.uniqueEnable
	else
		return nil
	end
	local engine = A.maxWeaponDamage(level, fistSkill, o.engineAttack, attackFactor)
	if engine <= 0 then
		return 1
	end
	return A.maxWeaponDamage(level, math.max(fistSkill or 0, bestSkill or 0), A.fistAttack(level), attackFactor) * m / engine
end

-- the attack an empty hand gives the spells that read the weapon's attack (ChaosSpell.meleeAttack: the Thief line's
-- strikes, the Templar line's), nil when neither the keystone nor the unique applies
function A.openHandAttack(level, keystone, unique)
	local o = cfg().arOpenHand
	if keystone then
		return A.fistAttack(level) * o.damage * (unique and (1 + o.uniqueBonus) or 1)
	elseif unique then
		return A.fistAttack(level) * o.damage * o.uniqueEnable
	end
	return nil
end

-- ------------------------------------------------------------------------------------------------ the flag storage
-- the storage value of a flag set (a bit per flag, in the order of A.FLAGS)
function A.mask(flags)
	local v = 0
	for i, f in ipairs(A.FLAGS) do
		if flags and flags[f] then
			v = v + 2 ^ (i - 1)
		end
	end
	return math.floor(v)
end

function A.maskHas(mask, flag)
	for i, f in ipairs(A.FLAGS) do
		if f == flag then
			return (mask or 0) > 0 and math.floor(mask / 2 ^ (i - 1)) % 2 == 1
		end
	end
	return false
end

-- for the spells' Lua state (no ChaosPassiveCache there): Open Hand's attack of an empty hand, or nil. Reads the flag
-- storage and the worn Knuckles of the Unbound (a copy that carries chaos_unique).
function A.spellOpenHandAttack(player)
	if not player or not player.getStorageValue then
		return nil
	end
	local keystone = A.maskHas(player:getStorageValue(cfg().storage), "arOpenHand")
	local unique = false
	for id, key in pairs(cfg().uniques) do
		if key == "openHand" then
			for _, slot in ipairs({CONST_SLOT_RING, CONST_SLOT_AMMO}) do
				local item = slot and player:getSlotItem(slot)
				if item and item:getId() == id then
					local ok, mark = pcall(item.getCustomAttribute, item, "chaos_unique")
					unique = unique or (ok and mark ~= nil and mark ~= 0)
				end
			end
		end
	end
	return A.openHandAttack(player:getLevel(), keystone, unique)
end

-- the archetype flags of a storage mask (the spells' Lua state reads the keystones this way)
function A.flagsOfMask(mask)
	local out = {}
	for _, f in ipairs(A.FLAGS) do
		if A.maskHas(mask, f) then
			out[f] = true
		end
	end
	return out
end

-- the archetype uniques a player wears: {key = true} (copies that carry chaos_unique; for the spells' Lua state, which
-- has no archetypes.lua)
local WORN_SLOTS = {"CONST_SLOT_HEAD", "CONST_SLOT_NECKLACE", "CONST_SLOT_ARMOR", "CONST_SLOT_RIGHT", "CONST_SLOT_LEFT",
	"CONST_SLOT_LEGS", "CONST_SLOT_FEET", "CONST_SLOT_RING", "CONST_SLOT_AMMO"}
function A.wornUniques(player)
	local out = {}
	if not player or not player.getSlotItem then
		return out
	end
	for _, name in ipairs(WORN_SLOTS) do
		local slot = _G[name]
		local item = slot and player:getSlotItem(slot)
		local key = item and cfg().uniques[item:getId()]
		if key then
			local ok, mark = pcall(item.getCustomAttribute, item, "chaos_unique")
			if ok and mark ~= nil and mark ~= 0 then
				out[key] = true
			end
		end
	end
	return out
end

-- ------------------------------------------------------------------------------------------------ chain reactions
-- One queue for every spread (poison, burn, shatter): at most chain.perTick a tick, chain.perChain per chain id,
-- chain.queueMax waiting. queue = {items = {}, perChain = {}}.
function A.newQueue()
	return {items = {}, perChain = {}}
end

-- returns true when the item was queued (false: the queue is full or the chain spent its budget)
function A.enqueue(queue, item)
	local c = cfg().chain
	if #queue.items >= c.queueMax then
		return false
	end
	local key = item.chain or 0
	local used = queue.perChain[key] or 0
	if used >= c.perChain then
		return false
	end
	queue.perChain[key] = used + 1
	queue.items[#queue.items + 1] = item
	return true
end

-- the items to run this tick (oldest first), removed from the queue
function A.drain(queue, n)
	n = n or cfg().chain.perTick
	local out = {}
	while #out < n and #queue.items > 0 do
		out[#out + 1] = table.remove(queue.items, 1)
	end
	return out
end

-- forget the chain budgets of chains with nothing queued (called now and then)
function A.forgetChains(queue)
	local live = {}
	for _, item in ipairs(queue.items) do
		live[item.chain or 0] = true
	end
	for key in pairs(queue.perChain) do
		if not live[key] then
			queue.perChain[key] = nil
		end
	end
end

-- ------------------------------------------------------------------------------------------------ Contagion Rite
-- record = {owner, tick, at, gen, chain}: the last poison tick of an owner on a monster. Returns the spread
-- {owner, tick, ticks, gen, chain, targets, radius} for a death at `now`, or nil.
function A.contagionSpread(record, now, unique)
	local c = cfg().arContagion
	if not record or now - (record.at or 0) > c.recentMs then
		return nil
	end
	local maxGen = c.maxGenerations + (unique and c.uniqueGenerations or 0)
	local gen = (record.gen or 0) + 1
	if gen > maxGen then
		return nil
	end
	local tick = math.max(1, math.floor(math.abs(record.tick or 0) * c.share))
	return {owner = record.owner, tick = tick, ticks = c.ticks, tickMs = c.tickMs, gen = gen, chain = record.chain,
		targets = c.targets + (unique and c.uniqueTargets or 0), radius = c.radius}
end

-- ------------------------------------------------------------------------------------------------ Cascade Edge
function A.cascadeAmount(critHit, unique)
	local c = cfg().arCascade
	return math.floor(math.abs(critHit or 0) * (c.share + (unique and c.uniqueShare or 0)))
end

function A.cascadeIcd(unique)
	local c = cfg().arCascade
	return c.icdMs - (unique and c.uniqueIcdMs or 0)
end

-- the strongest element of the tree bonuses (incrementFire ...), "energy" when none
local ELEMENT_KEYS = {{"fire", "incrementFire"}, {"ice", "incrementIce"}, {"energy", "incrementEnergy"},
	{"earth", "incrementEarth"}, {"death", "incrementDeath"}, {"holy", "incrementHoly"}}
function A.cascadeElement(bonuses)
	local best, value = "energy", 0
	for _, e in ipairs(ELEMENT_KEYS) do
		local v = bonuses and bonuses[e[2]] or 0
		if v > value then
			best, value = e[1], v
		end
	end
	return best
end

-- ------------------------------------------------------------------------------------------------ Stormstring
-- {arcs, share} of a bow hit, or nil
function A.stormArcs(keystone, unique)
	local s = cfg().arStormstring
	if keystone then
		return s.arcs + (unique and s.uniqueArcs or 0), s.share
	elseif unique then
		return s.enableArcs, s.enableShare
	end
	return nil
end

-- ------------------------------------------------------------------------------------------------ Winter's Lattice
function A.shatterAmount(maxHealth, level, unique)
	local w = cfg().arWinterLattice
	local share = w.share + (unique and w.uniqueShare or 0)
	return math.min(math.floor((maxHealth or 0) * share), math.floor((level or 0) * w.perLevel))
end

function A.shatterRadius(unique)
	local w = cfg().arWinterLattice
	return w.radius + (unique and w.uniqueRadius or 0)
end

-- ------------------------------------------------------------------------------------------------ Effigy Covenant
-- a cast: hits = {{id, amount, type}, ...} of one spell in one tick. Returns {count, average, type} when it raises an
-- effigy, else nil (fewer than minTargets)
function A.effigyCast(hits)
	local e = cfg().arEffigy
	if #hits < e.minTargets then
		return nil
	end
	local sum, byType = 0, {}
	for _, h in ipairs(hits) do
		sum = sum + math.abs(h.amount)
		byType[h.type] = (byType[h.type] or 0) + math.abs(h.amount)
	end
	local best, bestV
	for t, v in pairs(byType) do
		if not bestV or v > bestV or (v == bestV and tostring(t) < tostring(best)) then
			best, bestV = t, v
		end
	end
	return {count = #hits, average = math.floor(sum / #hits), type = best}
end

-- the effigies of a player: list (oldest first) of {id, pos, untilTime, nextPulse, cast}. Adds one and returns the
-- ones that must go (over the maximum: the oldest first).
function A.effigyAdd(list, effigy, unique)
	local e = cfg().arEffigy
	list[#list + 1] = effigy
	local gone = {}
	local max = e.max + (unique and e.uniqueMax or 0)
	while #list > max do
		gone[#gone + 1] = table.remove(list, 1)
	end
	return gone
end

-- The keystone's net effect on the spell damage of a pack (2+ targets), as a fraction of the damage without it: the pulses
-- of every standing effigy (max, plus the Idol's) give back share x ownSpell of a cast each (the pulse is a share of the
-- already priced hit) per cast interval, the price takes 1 - ownSpell. castMs: the time between the caster's area casts
-- (default the pulse time: a cast every 2 s); spellShare: the part of the damage that comes from spells (0.96 for the
-- Elementalist's area rotation, 0.88 on one target). One target raises no effigy: A.effigyNetSingle.
function A.effigyNetGain(unique, spellShare, castMs)
	local e = cfg().arEffigy
	local effigies = e.max + (unique and e.uniqueMax or 0)
	local pulses = (castMs or e.pulseMs) / e.pulseMs
	return (spellShare or 1) * (effigies * e.share * e.ownSpell * pulses - (1 - e.ownSpell))
end

-- one target: no effigy (minTargets), only the price
function A.effigyNetSingle(spellShare)
	return -(spellShare or 1) * (1 - cfg().arEffigy.ownSpell)
end

-- the damage of one pulse per enemy
function A.effigyPulse(cast)
	return math.floor((cast and cast.average or 0) * cfg().arEffigy.share)
end

-- ------------------------------------------------------------------------------------------------ Sigil of Cinders
-- the ignite of a fire or holy spell hit: damage per tick, ticks, tick ms
function A.igniteTick(hit)
	local s = cfg().arCinderSigil
	return math.max(1, math.floor(math.abs(hit or 0) * s.igniteShare / s.igniteTicks)), s.igniteTicks, s.igniteTickMs
end

function A.sigilPulse(hit, unique)
	local s = cfg().arCinderSigil
	return math.floor(math.abs(hit or 0) * s.pulseShare * (1 + (unique and s.uniquePulse or 0)))
end

-- a burn spread on death: the record {owner, tick, at, gen, chain} of the last ignite tick, or nil
function A.burnSpread(record, now)
	local s = cfg().arCinderSigil
	if not record or now - (record.at or 0) > s.igniteTickMs * 2 then
		return nil
	end
	local gen = (record.gen or 0) + 1
	if gen > s.spreadGenerations then
		return nil
	end
	return {owner = record.owner, tick = math.max(1, math.floor(math.abs(record.tick or 0))), ticks = s.igniteTicks,
		tickMs = s.igniteTickMs, gen = gen, chain = record.chain, targets = s.spreadTargets, radius = s.spreadRadius}
end

-- ------------------------------------------------------------------------------------------------ Aether Edge
function A.aetherAmount(shield, unique)
	local a = cfg().arAetherEdge
	return math.floor(math.max(0, shield or 0) * (a.share + (unique and a.uniqueShare or 0)))
end

function A.aetherHealthPercent()
	return math.floor(cfg().arAetherEdge.maxHealth * 100 + 0.5)
end

-- ------------------------------------------------------------------------------------------------ Reliquary Vow
function A.relicHeal(maxHealth, magicLevel, unique)
	local r = cfg().arReliquary
	return math.floor(((maxHealth or 0) * r.healShare + (magicLevel or 0) * r.healPerMagicLevel)
		* (1 + (unique and r.uniqueBonus or 0)))
end

function A.relicDamage(level, magicLevel, unique)
	local r = cfg().arReliquary
	return math.floor(((level or 0) * r.damagePerLevel + (magicLevel or 0) * r.damagePerMagicLevel)
		* (1 + (unique and r.uniqueBonus or 0)))
end

-- the party damage buff: buffs = {[memberId] = untilTime}; multiplier of a hit by attackerId at now
function A.relicBuff(buffs, attackerId, now)
	local untilTime = buffs and buffs[attackerId]
	if untilTime and untilTime >= now then
		return 1 + cfg().arReliquary.partyDamage
	end
	return 1
end

-- ------------------------------------------------------------------------------------------------ Hollow Vessel
-- the health cut that brings the maximum to arHollowVessel.health: maxHealth = the maximum now (the cut already applied
-- is part of it), applied = that cut. Returns the cut, which is also the health given up.
function A.hollowCut(maxHealth, applied)
	local base = (maxHealth or 0) + (applied or 0)
	return math.max(0, base - cfg().arHollowVessel.health)
end

-- the maximum energy shield: the items' maximum (ChaosEnergyShield.maximum), the health given up, the unique worn
function A.hollowShield(itemMax, givenUp, keystone, stillheart)
	local h = cfg().arHollowVessel
	if not keystone then
		return itemMax or 0
	end
	local more = h.more + (stillheart and h.uniqueMore or 0)
	return math.floor((itemMax or 0) * (1 + more) + (givenUp or 0) * h.fromHealth + 1e-9)
end

-- the recharge per mille added (keystone, Hollowglass Diadem)
function A.hollowRecharge(keystone, diadem)
	local h = cfg().arHollowVessel
	return (keystone and h.recharge or 0) + (diadem and h.diademRecharge or 0)
end

-- a hit the keystone ignores: earth damage over time (poison) and life drain
function A.hollowImmune(ctype, origin)
	return ctype == "lifedrain" or (ctype == "earth" and origin == "condition")
end

-- what the one second think adds to the shield: the part of the last `ms` that lies between earlyMs and the engine's
-- delay after the last hit (the engine recharges from its delay on). sinceHit = ms since the last hit at the think.
function A.earlyRecharge(current, maximum, perMille, sinceHit, ms, engineDelay)
	local h = cfg().arHollowVessel
	current, maximum, ms, engineDelay = current or 0, maximum or 0, ms or 1000, engineDelay or 2000
	if maximum <= 0 or current >= maximum or not sinceHit then
		return 0
	end
	local from = math.max(sinceHit - ms, h.earlyMs)
	local to = math.min(sinceHit, engineDelay)
	if to <= from then
		return 0
	end
	local gain = math.max(1, math.floor(maximum * (perMille or 0) * (to - from) / 1000000))
	return math.min(gain, maximum - current)
end

-- the base of a "percent of maximum health" hit (the rifts): health + maximum shield for a holder
function A.percentBase(maxHealth, maxShield, keystone)
	if keystone then
		return (maxHealth or 0) + (maxShield or 0)
	end
	return maxHealth or 0
end

return A
