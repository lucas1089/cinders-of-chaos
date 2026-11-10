-- round4_keystones_core.lua: the pure rules of the round 4 keystones (ChaosRound4, O450): Momentum, Attunement, Open
-- Wounds. No engine calls: plain numbers and tables in, numbers and tables out (server/tests/round4_keystones_test.lua).
-- Numbers: round4_keystones_config.lua. Engine glue: archetypes.lua (the hit event, the hit taken, the bleed).
-- Each rule reuses an existing hook: Momentum the statscale family of the unique items, Attunement the price rule of
-- Winter's Lattice (a factor on one damage type), Open Wounds the bleed of Barbed Quiver.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosRound4Config = ChaosRound4Config or dofile("data/scripts/chaos/round4_keystones_config.lua")

ChaosRound4 = ChaosRound4 or {}
local R = ChaosRound4
R.cfg = ChaosRound4Config
local function cfg()
	return R.cfg
end

R.FLAGS = {"arMomentum", "arAttunement", "arOpenWounds"}

-- does a flag table hold any of the round 4 keystones
function R.holds(flags)
	if not flags then
		return false
	end
	for _, f in ipairs(R.FLAGS) do
		if flags[f] then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------------------------------------------ Momentum
-- the movement speed above the base speed, in percent of the base: 0 at or below the base (a slow gives nothing)
function R.speedAbovePct(stepSpeed, baseSpeed)
	stepSpeed, baseSpeed = tonumber(stepSpeed) or 0, tonumber(baseSpeed) or 0
	if baseSpeed <= 0 or stepSpeed <= baseSpeed then
		return 0
	end
	return (stepSpeed - baseSpeed) * 100 / baseSpeed
end

-- the unique items' statscale rule (unique_passives_core.lua C.dealt, family statscale), fed with Momentum's numbers and
-- the speed above the base in percent: the damage factor of a direct hit (1 + gain). `pvp`: the target is a player.
function R.momentumFactor(abovePct, pvp)
	if not ChaosUniquePassivesConfig then
		dofile("data/scripts/chaos/unique_passives_config.lua")
	end
	if not ChaosUniquePassivesCore then
		dofile("data/scripts/chaos/unique_passives_core.lua")
	end
	local m = cfg().arMomentum
	local entry = {family = "statscale", stat = "momentum", from = 0, per = m.per, bonusPer = m.bonusPer, cap = m.cap,
		origin = "any"}
	local f = ChaosUniquePassivesCore.dealt(ChaosUniquePassivesConfig, {}, {entry},
		{now = 0, origin = "any", elem = "physical", stats = {momentum = abovePct or 0}})
	if pvp and f > 1 then
		f = 1 + (f - 1) * m.pvpScale
	end
	return f
end

-- the gain in percent a speed above the base gives (the whole steps, at most the cap)
function R.momentumGainPct(abovePct)
	return math.floor((R.momentumFactor(abovePct, false) - 1) * 100 + 0.5)
end

-- the factor of a hit with a worn speed-scaling unique of factor `unique` (1 without one): the larger of the two counts,
-- so the keystone adds nothing to it. Never below 1.
function R.momentumAgainstUnique(factor, unique)
	unique = tonumber(unique) or 1
	if unique <= 1 then
		return factor
	end
	return math.max(1, factor / unique)
end

-- the price: the damage you take
function R.momentumTaken()
	return cfg().arMomentum.taken
end

-- ------------------------------------------------------------------------------------------------ Attunement
local ELEMENT_KEYS = {fire = "incrementFire", ice = "incrementIce", energy = "incrementEnergy", earth = "incrementEarth",
	death = "incrementDeath", holy = "incrementHoly"}
R.ELEMENTS = ELEMENT_KEYS

-- the element a tree favours most (the largest incrementX; the first of fire, ice, energy, earth, death, holy on a tie), or
-- nil when no element has an increment
local ORDER = {"fire", "ice", "energy", "earth", "death", "holy"}
function R.lockedElement(bonuses)
	local best, value = nil, 0
	for _, name in ipairs(ORDER) do
		local v = bonuses and bonuses[ELEMENT_KEYS[name]] or 0
		if v > value then
			best, value = name, v
		end
	end
	return best
end

-- the multiplier of one damage half of type `ctype` ("fire" ...) with `locked` the favoured element (nil: no lock)
function R.attunementFactor(ctype, locked)
	if not locked or not ELEMENT_KEYS[ctype] then
		return 1
	end
	local a = cfg().arAttunement
	return ctype == locked and a.locked or a.others
end

-- ------------------------------------------------------------------------------------------------ Open Wounds
-- the bleed of a hit of `amount`: tick, ticks, tickMs (nil when the hit is too small to bleed)
function R.bleedOf(amount)
	local o = cfg().arOpenWounds
	local tick = math.floor(math.abs(amount or 0) * o.share / o.ticks)
	if tick <= 0 then
		return nil
	end
	return tick, o.ticks, o.tickMs
end

-- does a melee hit bleed: bare fists or a one-handed weapon (`twoHanded` says the weapon in the hands takes both)
function R.bleeds(origin, hasWeapon, twoHanded)
	return origin == "melee" and not (hasWeapon and twoHanded)
end

function R.openWoundsPrice()
	return cfg().arOpenWounds.price
end

-- ------------------------------------------------------------------------------------------------ the +40% rule
-- The net gain of each keystone in its specialty, the number the test stacks (the owner: a specialised build is at most
-- +40% over its class default). All three are factors of the damage you deal, prices included.
-- Momentum: the factor at a speed above the base (its price is on the damage taken, not on the damage dealt)
function R.momentumNet(abovePct)
	return R.momentumFactor(abovePct, false)
end

-- Attunement in a build that casts one element only (the specialty): the locked element's factor. A kit of several elements
-- gets less: R.attunementMix
function R.attunementNet()
	return cfg().arAttunement.locked
end

-- Attunement for a kit whose damage is split over elements: shares = {element = share of the damage}, locked = the
-- favoured element; the damage-weighted factor
function R.attunementMix(shares, locked)
	local total, sum = 0, 0
	for ctype, share in pairs(shares or {}) do
		total = total + share
		sum = sum + share * R.attunementFactor(ctype, locked)
	end
	return total > 0 and sum / total or 1
end

-- Open Wounds on one target over a long fight: the price on every hit, and a bleed that the next hit replaces, so each hit's
-- bleed pays share x hit x the part of its duration before the next hit
function R.openWoundsNet(intervalMs)
	local o = cfg().arOpenWounds
	local cover = math.min(1, (intervalMs or 2000) / (o.ticks * o.tickMs))
	return o.price * (1 + o.share * cover)
end

return R
