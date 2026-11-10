-- section_keystones_core.lua: the pure rules of the six class section keystones of the Warrior, Ranger and Mystic lines
-- (ChaosSectionKeystones, O449): Unbroken Line, Open Veins, Lone Mark, Wolfbond, Convergence, Phantom Double.
-- No engine calls: plain numbers and tables in, numbers and tables out (server/tests/section_keystones_test.lua).
-- Numbers: section_keystones_config.lua (Wolfbond: class_tree.lua fx). Engine glue: passivetree_keystones.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosSectionKeystonesConfig = ChaosSectionKeystonesConfig or dofile("data/scripts/chaos/section_keystones_config.lua")

ChaosSectionKeystones = ChaosSectionKeystones or {}
local C = ChaosSectionKeystones
C.cfg = ChaosSectionKeystonesConfig
local function cfg()
	return C.cfg
end

-- the flags in a fixed order (tests, the client names)
C.FLAGS = {"ksUnbrokenLine", "ksOpenVeins", "ksLoneMark", "ksWolfbond", "ksConvergence", "ksPhantomDouble"}

-- does a bonus table hold any of these keystones? (Wolfbond's gain is the wolf factor of classes.lua; the glue only
-- applies its price)
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

-- tiles between two positions (king moves); other floors are out of reach
function C.distance(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- how many of the candidates {id, pos} stand within radius of center, not counting the one with id skipId
function C.crowd(candidates, center, skipId, radius)
	local n = 0
	for _, c in ipairs(candidates or {}) do
		if c.id ~= skipId and C.distance(c.pos, center) <= radius then
			n = n + 1
		end
	end
	return n
end

-- scale a damage value keeping its sign, rounding toward zero
function C.scale(v, m)
	local a = math.floor(math.abs((v or 0) * m) + 1e-6)
	return (v or 0) < 0 and -a or a
end

-- ------------------------------------------------------------------------------------------------ Unbroken Line
-- the factor of a melee or ranged hit taken with a shield when `enemies` stand next to the player
function C.unbrokenFactor(enemies)
	local u = cfg().ksUnbrokenLine
	return 1 - math.min(u.maxEnemies, math.max(0, enemies or 0)) * u.perEnemy
end

function C.unbrokenPrice()
	return cfg().ksUnbrokenLine.price
end

-- ------------------------------------------------------------------------------------------------ Open Veins
-- the bleed of a hit of `amount`: tick, ticks, tickMs (nil when the hit is too small to bleed)
function C.bleedOf(amount)
	local o = cfg().ksOpenVeins
	local tick = math.floor(math.abs(amount or 0) * o.share / o.ticks)
	if tick <= 0 then
		return nil
	end
	return tick, o.ticks, o.tickMs
end

function C.openVeinsPrice()
	return cfg().ksOpenVeins.price
end

-- ------------------------------------------------------------------------------------------------ Lone Mark
-- the factor of a bow or crossbow hit on a target with `others` other enemies near it
function C.loneMarkFactor(others)
	local l = cfg().ksLoneMark
	return (others or 0) == 0 and l.alone or l.crowd
end

-- ------------------------------------------------------------------------------------------------ Wolfbond
-- the price of the owner's own distance weapon hits; the gain is the wolf factor (classes.lua wolfFactor)
function C.wolfbondPrice()
	if not ChaosClassTree then
		dofile("data/scripts/chaos/class_tree.lua")
	end
	return ChaosClassTree.fx.ksWolfbond.price
end

-- ------------------------------------------------------------------------------------------------ Convergence
-- the factor of an elemental spell hit on a target with `others` other enemies near it (1 between the two)
function C.convergenceFactor(others)
	local v = cfg().ksConvergence
	others = others or 0
	if others >= v.others then
		return v.bonus
	end
	if others == 0 then
		return v.alone
	end
	return 1
end

-- ------------------------------------------------------------------------------------------------ Phantom Double
-- the double's strike for a spell hit of `amount` at `now` (ms); state = {phantomUntil}. 0 when the roll fails or the
-- cooldown runs; `random` gives 1..100 like math.random
function C.phantomStrike(state, amount, now, random)
	local p = cfg().ksPhantomDouble
	if (state.phantomUntil or 0) > now then
		return 0
	end
	if not ((random or math.random)(1, 100) <= p.chance) then
		return 0
	end
	state.phantomUntil = now + p.icdMs
	return math.floor(math.abs(amount or 0) * p.percent)
end

function C.phantomPrice()
	return cfg().ksPhantomDouble.price
end

return C
