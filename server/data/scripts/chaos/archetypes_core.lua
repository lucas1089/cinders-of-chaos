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
-- itself: the prices of that archetype do not apply to it)}. Type-dependent prices: typeFactor.
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
-- state = {start, sum}: the leech of the last second. Returns the health to give for a hit of `amount` at `now`.
function A.leech(state, now, amount, maxHealth, unique)
	local s = cfg().arSanguine
	local share = s.share + (unique and s.uniqueShare or 0)
	local cap = math.floor((maxHealth or 0) * (s.capPerSecond + (unique and s.uniqueCap or 0)))
	if not state.start or now - state.start >= 1000 then
		state.start, state.sum = now, 0
	end
	local want = math.floor(math.abs(amount or 0) * share)
	local give = math.max(0, math.min(want, cap - state.sum))
	state.sum = state.sum + give
	return give
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

return A
