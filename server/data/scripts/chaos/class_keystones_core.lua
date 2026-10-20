-- class_keystones_core.lua: the pure rules of the signature keystones of the Thief, Necromancer, Monk and Templar
-- lines (ChaosClassKeystones), the variants of the passive tree's nodes 621 / 624 next to Ricochet and Deadeye.
-- No engine calls: plain numbers and tables in, numbers and tables out (server/tests/class_keystones_test.lua).
-- Numbers: class_keystones_config.lua. Engine glue: passivetree_keystones.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosClassKeystonesConfig = ChaosClassKeystonesConfig or dofile("data/scripts/chaos/class_keystones_config.lua")

ChaosClassKeystones = ChaosClassKeystones or {}
local C = ChaosClassKeystones
C.cfg = ChaosClassKeystonesConfig
local function cfg()
	return C.cfg
end

-- the flags in a fixed order (tests, the client names)
C.FLAGS = {"ksShadowTwin", "ksViperVerdict", "ksCorpseBlast", "ksReapersToll", "ksSeventhPalm", "ksPiercingPalm",
	"ksRadiantRebuke", "ksDawnchain"}

-- ------------------------------------------------------------------------------------------------ helpers
-- chance in percent (0..100); random(1, 100) like math.random
function C.roll(chance, random)
	return chance > 0 and (random or math.random)(1, 100) <= chance
end

-- scale a damage value keeping its sign, rounding toward zero
function C.scale(v, m)
	local a = math.floor(math.abs((v or 0) * m) + 1e-6)
	return (v or 0) < 0 and -a or a
end

-- tiles between two positions (king moves); other floors are out of reach
function C.distance(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- does a bonus table hold any of these keystones?
function C.holds(b)
	if not b then
		return false
	end
	for _, key in ipairs(C.FLAGS) do
		if b[key] then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------------------------------------------ Shadow Twin
-- the shadow's strike for a hit of `amount` (0 when the roll fails)
function C.shadowTwin(amount, random)
	local s = cfg().ksShadowTwin
	if not C.roll(s.chance, random) then
		return 0
	end
	return math.floor(math.abs(amount or 0) * s.percent)
end

function C.shadowTwinTaken()
	return 1 + cfg().ksShadowTwin.taken
end

-- ------------------------------------------------------------------------------------------------ Viper's Verdict
-- the multiplier of a weapon hit on a target that is (or is not) poisoned, and whether it struck a vital
function C.viperStep(poisoned, random)
	local v = cfg().ksViperVerdict
	if not poisoned then
		return v.price, false
	end
	if C.roll(v.chance, random) then
		return v.multiplier, true
	end
	return 1, false
end

-- ------------------------------------------------------------------------------------------------ Corpse Detonation
-- the explosion of a monster of `maxHealth` killed by a holder of `level`
function C.corpseBlastAmount(maxHealth, level)
	local b = cfg().ksCorpseBlast
	return math.floor(math.min(math.max(0, maxHealth or 0) * b.percent, math.max(0, level or 0) * b.perLevel))
end

-- the victims: candidates {id, pos} within the radius of `center`, not the dead one, nearest first (ties: lowest id)
function C.corpseBlastPick(candidates, center, deadId)
	local b = cfg().ksCorpseBlast
	local list = {}
	for _, c in ipairs(candidates) do
		if c.id ~= deadId and C.distance(c.pos, center) <= b.radius then
			list[#list + 1] = c
		end
	end
	table.sort(list, function(x, y)
		local dx, dy = C.distance(x.pos, center), C.distance(y.pos, center)
		if dx ~= dy then
			return dx < dy
		end
		return x.id < y.id
	end)
	for i = #list, b.maxTargets + 1, -1 do
		list[i] = nil
	end
	return list
end

-- the price on the holder's (and its minions') hits
function C.corpseBlastPrice()
	return cfg().ksCorpseBlast.price
end

-- ------------------------------------------------------------------------------------------------ Reaper's Toll
-- the multiplier of a hit on a monster at `health` of `maxHealth`, and whether it is in the reaping range
function C.reaperFactor(health, maxHealth)
	local r = cfg().ksReapersToll
	if (maxHealth or 0) <= 0 then
		return 1, false
	end
	if (health or 0) <= maxHealth * r.below then
		return 1 + r.bonus, true
	end
	return r.price, false
end

-- ------------------------------------------------------------------------------------------------ Seventh Palm
-- state = {count, at}. One melee hit at `now`: the multiplier of the hit and whether it is the finisher.
function C.palmStep(state, now)
	local p = cfg().ksSeventhPalm
	if state.at and now - state.at > p.windowMs then
		state.count = 0
	end
	state.at = now
	state.count = (state.count or 0) + 1
	if state.count >= p.every then
		state.count = 0
		return p.finisher, true
	end
	return p.price, false
end

-- the shockwave's share of a finisher of `amount` (already x finisher)
function C.palmShock(amount)
	return math.floor(math.abs(amount or 0) * cfg().ksSeventhPalm.shockShare)
end

-- the shockwave's victims: other enemies within 1 sqm of the target, lowest ids first
function C.palmShockPick(candidates, center, mainId)
	local p = cfg().ksSeventhPalm
	local list = {}
	for _, c in ipairs(candidates) do
		if c.id ~= mainId and C.distance(c.pos, center) <= 1 then
			list[#list + 1] = c
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	for i = #list, p.maxTargets + 1, -1 do
		list[i] = nil
	end
	return list
end

-- ------------------------------------------------------------------------------------------------ Piercing Palm
-- the pierce from the attacker at `origin` through the target {id, pos} with a hit of `base`: up to two steps
-- {id, from, to, amount}. Each step is the nearest enemy next to the last one (1 sqm) that stands farther from the
-- attacker than it (ties: lowest id); never one twice. candidatesAt(pos) lists {id, pos} around pos.
function C.piercePlan(origin, target, base, candidatesAt)
	local p = cfg().ksPiercingPalm
	local steps, visited, last = {}, {[target.id] = true}, target
	for _, share in ipairs({p.first, p.second}) do
		local lastDist = C.distance(origin, last.pos)
		local best, bestDist
		for _, c in ipairs(candidatesAt(last.pos)) do
			local d = C.distance(last.pos, c.pos)
			if not visited[c.id] and d <= 1 and C.distance(origin, c.pos) > lastDist
					and (not best or d < bestDist or (d == bestDist and c.id < best.id)) then
				best, bestDist = c, d
			end
		end
		local amount = math.floor(math.abs(base or 0) * share)
		if not best or amount <= 0 then
			break
		end
		visited[best.id] = true
		steps[#steps + 1] = {id = best.id, from = last.pos, to = best.pos, amount = amount}
		last = best
	end
	return steps
end

function C.piercePrice()
	return cfg().ksPiercingPalm.price
end

-- ------------------------------------------------------------------------------------------------ Radiant Rebuke
-- a melee / ranged hit on a holder with a shield at `now`: blocked?, and does the block release the nova (state =
-- {novaAt} keeps its internal cooldown)
function C.rebukeBlock(state, now, random)
	local r = cfg().ksRadiantRebuke
	if not C.roll(r.blockChance, random) then
		return false, false
	end
	if state.novaAt and now - state.novaAt < r.icdMs then
		return true, false
	end
	state.novaAt = now
	return true, true
end

-- the nova's damage for a blocked hit of `blocked` and a magic level
function C.rebukeNova(blocked, magicLevel)
	local r = cfg().ksRadiantRebuke
	return math.floor(math.abs(blocked or 0) * r.share + math.max(0, magicLevel or 0) * r.perMagicLevel)
end

-- the nova's victims: enemies within the radius of `center`, nearest first (ties: lowest id), at most maxTargets
function C.rebukePick(candidates, center)
	local r = cfg().ksRadiantRebuke
	local list = {}
	for _, c in ipairs(candidates) do
		if C.distance(c.pos, center) <= r.radius then
			list[#list + 1] = c
		end
	end
	table.sort(list, function(x, y)
		local dx, dy = C.distance(x.pos, center), C.distance(y.pos, center)
		if dx ~= dy then
			return dx < dy
		end
		return x.id < y.id
	end)
	for i = #list, r.maxTargets + 1, -1 do
		list[i] = nil
	end
	return list
end

-- ------------------------------------------------------------------------------------------------ Dawnchain
-- the chain from the first target: {{id, from, to, amount}, ...}; candidatesAt(pos) lists {id, pos} around pos
function C.dawnchainPlan(startPos, startId, base, candidatesAt)
	local d = cfg().ksDawnchain
	local steps, visited, from, amount = {}, {[startId] = true}, startPos, math.abs(base or 0) * d.percent
	for _ = 1, d.bounces do
		local best, bestDist
		for _, c in ipairs(candidatesAt(from)) do
			local dist = C.distance(from, c.pos)
			if not visited[c.id] and dist <= d.range and (not best or dist < bestDist or (dist == bestDist and c.id < best.id)) then
				best, bestDist = c, dist
			end
		end
		if not best or math.floor(amount) <= 0 then
			break
		end
		visited[best.id] = true
		steps[#steps + 1] = {id = best.id, from = from, to = best.pos, amount = math.floor(amount)}
		from, amount = best.pos, amount * d.falloff
	end
	return steps
end

function C.dawnchainSpellPrice()
	return cfg().ksDawnchain.spellPrice
end

-- ------------------------------------------------------------------------------------------------ the balance model
-- Expected damage of a fight with the keystone against the same fight without it (computed, not measured), the way
-- server/data/spells/README.md "Keystones verified in game" reads Ricochet and Deadeye: `single` = one enemy, `pack` =
-- five enemies standing together (every bounce, cleave and explosion finds its targets). ref = ChaosKeystones.cfg for
-- the two references. poisonUptime: the share of a Thief's hits on a poisoned target (Blackblood Creed or Venom Craft
-- poisons on every hit; 0.9 leaves the first hit and a refresh out).
function C.model(ref, poisonUptime)
	local c = cfg()
	local u = poisonUptime or 0.9
	local out = {}
	local r = ref.ricochet
	out.Ricochet = {single = 1, pack = 1 + r.percent + r.percent * r.falloff}
	out.Deadeye = {single = 1 + ref.deadeye.chance / 100 * (ref.deadeye.multiplier - 1)}
	out.Deadeye.pack = out.Deadeye.single
	local s = c.ksShadowTwin
	out.ksShadowTwin = {single = 1 + s.chance / 100 * s.percent, taken = 1 + s.taken}
	out.ksShadowTwin.pack = out.ksShadowTwin.single
	local v = c.ksViperVerdict
	local poisoned = 1 + v.chance / 100 * (v.multiplier - 1)
	out.ksViperVerdict = {single = u * poisoned + (1 - u) * v.price}
	out.ksViperVerdict.pack = out.ksViperVerdict.single
	-- five monsters of one health: each death blasts the ones left (4 + 3 + 2 + 1 blasts of percent x health)
	local b = c.ksCorpseBlast
	local blasts = math.min(b.maxTargets, 4) + 3 + 2 + 1
	out.ksCorpseBlast = {single = b.price, pack = 5 / ((5 - b.percent * blasts) / b.price)}
	-- a monster's health from full to 0: the part above `below` at price, the rest at 1 + bonus
	local t = c.ksReapersToll
	out.ksReapersToll = {single = 1 / ((1 - t.below) / t.price + t.below / (1 + t.bonus))}
	out.ksReapersToll.pack = out.ksReapersToll.single
	local p = c.ksSeventhPalm
	local palm = ((p.every - 1) * p.price + p.finisher) / p.every
	out.ksSeventhPalm = {single = palm, pack = palm + p.finisher * p.shockShare * math.min(4, p.maxTargets) / p.every}
	-- the pack in a line behind the target (the best case; a ring of monsters gives about half)
	local pp = c.ksPiercingPalm
	out.ksPiercingPalm = {single = pp.price, pack = pp.price * (1 + pp.first + pp.second)}
	local d = c.ksDawnchain
	out.ksDawnchain = {single = 1, pack = 1 + d.percent + d.percent * d.falloff, spells = d.spellPrice}
	local rr = c.ksRadiantRebuke
	out.ksRadiantRebuke = {single = rr.price, pack = rr.price, takenWeapon = 1 - rr.blockChance / 100}
	return out
end

return C
