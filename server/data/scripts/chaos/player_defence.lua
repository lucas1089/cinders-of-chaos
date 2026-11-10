-- Player defence: how a player takes a hit, O464. server/README.md "Player defence (O464)". Rules: player_defence_core.lua
-- (pure, tested by server/tests/player_defence_test.lua), numbers: defence_config.lua (shared with the monster side) and
-- player_defence_config.lua.
--
-- * What: ONE healthchange event, "ChaosPlayerDefence", on every player, the first one after the three damage multipliers of
--   the monster stage (Chaos0MonsterDamageLogin, Chaos0RiftHitLogin, Chaos0TierLogin). It runs before every other Lua event of
--   the player, so every later event sees a hit that avoidance and mitigation have treated:
--   1 avoidance (attack hits: dodge, block; spell hits: spell suppression; never a tick or a field)
--   2 mitigation by type (physical: armour by hit size plus the physical reduction, at most 90; fire, cold, lightning and
--     chaos: one resistance each, level penalty included)
--   Then the older multipliers (damage taken from monsters, blessings, gems, charms ...), the mana shield, the energy shield
--   and the health run as before. Last Breath runs last of all (item_powers.lua, login event ChaosZLastBreathLogin).
-- * What still runs in the engine: immunity, the shield's block (the player's defence value), and the item absorb of the
--   worn pieces (Player::blockHit and patch 0049: no switch from Lua). The engine's armour is off (config.lua
--   armorPercentMax = 0, tools/patch_base_armor_percent.py) and the base script's absorb event returns a player's hit
--   unchanged (tools/patch_base_absorb_player.py). The layer divides the engine's item absorb out of the hit and counts the
--   same absorb as one of its sources, so nothing is taken twice.
-- * Sources of the groups (ONE reader, PD.sums): the worn pieces' absorbPercent (engine abilities of the item types), the two
--   absorb storages of every damage type (gear rarity attributes, passive tree and Paragon), the resistances of item sets
--   (ChaosItemSets.resistances), charms (ChaosCharms.resistOf), gems (ChaosGems.resistOf) and the item modifiers fireres,
--   coldres, lightningres, chaosres and allres. Their own events no longer reduce a player's hit (they ask
--   ChaosPlayerDefence.active()).
-- * Armour: the sum of the armour of the worn pieces (the engine's number, without the vocation multiplier that Lua cannot
--   read) plus the Armour modifier.
-- * Penetration of a player (PvP): ChaosItemMods totals physpen (points off the armour share) and elepen (points off the
--   resistance), after the cap. Monsters have none yet.
--
-- Exports: ChaosPlayerDefence.active(), .sums(player, pvp), .state(player, pvp), .resistances(player, pvp), .invalidate(player),
-- .penaltyOf(player), .hooks (capDelta, area: replaced by the rift modifier).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
Chaos.defence = Chaos.defence or dofile("data/scripts/chaos/defence_config.lua")
Chaos.playerDefence = dofile("data/scripts/chaos/player_defence_config.lua")
dofile("data/scripts/chaos/player_defence_core.lua")
if not ChaosManaShield or not ChaosManaShield.provide then
	dofile("data/scripts/chaos/manashield_core.lua")
end

ChaosPlayerDefence = ChaosPlayerDefence or {}
local PD = ChaosPlayerDefence
-- more sources registered by other scripts (the class evasion of thief_combat.lua and monk_combat.lua): `dodge` functions
-- (player) -> percent, `onDodge` functions (player, attacker) called when the player dodged. A global created by whoever
-- loads first, so the load order does not matter.
ChaosPlayerDefenceSources = ChaosPlayerDefenceSources or {dodge = {}, onDodge = {}}
local SRC = ChaosPlayerDefenceSources
local C = ChaosPlayerDefenceCore
local K = C.engineConstants()
PD.K = K
local GROUP_OF = C.groupTable(Chaos.playerDefence, K)
PD.groupOf = GROUP_OF

local function cfg()
	return Chaos.playerDefence
end

local function def()
	return Chaos.defence
end

function PD.active()
	return cfg().enabled ~= false
end

-- hooks that the rift modifier (and any later area rule) replaces: points off the sums, a change of the cap (negative lowers)
PD.hooks = PD.hooks or {
	area = function(player) return 0 end,
	-- the rift modifier Frayed Wards (rift_core.lua R.effects: fx.maxResistLower): the points off the cap while a run is on
	capDelta = function(player)
		local run = ChaosRift and ChaosRift.runOf and ChaosRift.runOf[player:getId()]
		local lower = run and run.state == "running" and run.fx and tonumber(run.fx.maxResistLower) or 0
		return lower > 0 and -lower or 0
	end
}

local function try(fn, ...)
	local ok, res = pcall(fn, ...)
	if ok then
		return res
	end
	return nil
end

-- the damage types a player meets, with the two absorb storages of each (gear rarity roll, passive tree and Paragon) and the
-- element name the item sets use
local TYPES = {
	{"physical", 977545, 977563}, {"fire", 977544, 977562}, {"ice", 977549, 977567}, {"energy", 977546, 977564},
	{"earth", 977547, 977565}, {"death", 977551, 977569}, {"holy", 977550, 977568}, {"drown", 977548, 977566},
	{"water", 977552, 977570}, {"arcane", 977553, 977571}, {"lifedrain", 977572, 977573}, {"manadrain", 977574, 977575}}
PD.TYPES = TYPES

-- engine: combatTypeToIndex + 1 (the Lua table index of ItemType abilities absorbPercent)
local function absorbIndex(ctype)
	local i = 1
	while ctype > 1 do
		ctype = math.floor(ctype / 2)
		i = i + 1
	end
	return i
end

local ARMOUR_SLOTS = {"CONST_SLOT_HEAD", "CONST_SLOT_NECKLACE", "CONST_SLOT_ARMOR", "CONST_SLOT_LEGS", "CONST_SLOT_FEET",
	"CONST_SLOT_RING", "CONST_SLOT_AMMO", "CONST_SLOT_DECK", "CONST_SLOT_BADGE", "CONST_SLOT_SHIP", "CONST_SLOT_BELT",
	"CONST_SLOT_GLOVES"}

-- Player::getArmor without the vocation multiplier: the armour of the worn pieces (the item's own attribute, else the type's)
local function wornArmour(player)
	local total = 0
	for _, name in ipairs(ARMOUR_SLOTS) do
		local slot = rawget(_G, name)
		local item = slot and try(player.getSlotItem, player, slot)
		if item then
			local v
			if ITEM_ATTRIBUTE_ARMOR and try(item.hasAttribute, item, ITEM_ATTRIBUTE_ARMOR) then
				v = tonumber(try(item.getAttribute, item, ITEM_ATTRIBUTE_ARMOR))
			end
			if not v then
				v = tonumber(try(function() return ItemType(item:getId()):getArmor() end))
			end
			total = total + math.max(0, math.floor(v or 0))
		end
	end
	return total
end

local function bonus(player, key)
	local IM = ChaosItemMods
	return IM and IM.playerBonus and tonumber(IM.playerBonus(player, key)) or 0
end

-- the sums and values of one player. pvp: the attacker is a player (item sets give their PvP share). Returns
-- {sums, A, dodge, block, suppress, worn (ctype -> list of percents), storage (ctype -> percent)}
local function read(player, pvp)
	local c = cfg()
	local sums = C.newSums(c)
	local worn, storage = {}, {}
	for _, t in ipairs(TYPES) do
		local ctype = K[t[1]]
		if ctype then
			local s = 0
			for i = 2, 3 do
				local v = tonumber(try(player.getStorageValue, player, t[i])) or 0
				if v > 0 then
					s = s + v
				end
			end
			storage[ctype] = s
			C.addType(sums, GROUP_OF, K, ctype, s)
		end
	end
	for _, slot in ipairs(c.wornSlots) do
		local item = try(player.getSlotItem, player, slot)
		local ab = item and try(function() return ItemType(item:getId()):getAbilities() end)
		local list = type(ab) == "table" and type(ab.absorbPercent) == "table" and ab.absorbPercent
		if list then
			for _, t in ipairs(TYPES) do
				local ctype = K[t[1]]
				local p = ctype and tonumber(list[absorbIndex(ctype)]) or 0
				if p ~= 0 then
					worn[ctype] = worn[ctype] or {}
					worn[ctype][#worn[ctype] + 1] = p
					if c.undoEngineAbsorb then
						C.addType(sums, GROUP_OF, K, ctype, p)
					end
				end
			end
		end
	end
	local sets = rawget(_G, "ChaosItemSets")
	if sets and sets.resistances then
		for el, v in pairs(try(sets.resistances, player, pvp) or {}) do
			C.addType(sums, GROUP_OF, K, K[el], v)
		end
	end
	local charms = rawget(_G, "ChaosCharms")
	if charms and charms.resistOf then
		for _, t in ipairs(TYPES) do
			if K[t[1]] then
				C.addType(sums, GROUP_OF, K, K[t[1]], try(charms.resistOf, player, K[t[1]]))
			end
		end
	end
	local gems = rawget(_G, "ChaosGems")
	if gems and gems.resistOf then
		for _, t in ipairs(TYPES) do
			if K[t[1]] then
				C.addType(sums, GROUP_OF, K, K[t[1]], try(gems.resistOf, player, K[t[1]]))
			end
		end
	end
	C.addGroup(sums, "fire", bonus(player, "fireres"))
	C.addGroup(sums, "cold", bonus(player, "coldres"))
	C.addGroup(sums, "lightning", bonus(player, "lightningres"))
	C.addGroup(sums, "chaos", bonus(player, "chaosres"))
	C.addAll(sums, c, bonus(player, "allres"))
	local dodge = bonus(player, "dodge")
	for _, fn in pairs(SRC.dodge) do
		dodge = dodge + (tonumber(try(fn, player)) or 0)
	end
	return {sums = sums, A = wornArmour(player) + bonus(player, "armour"), dodge = dodge,
		block = bonus(player, "block"), suppress = bonus(player, "spellsuppress"), worn = worn, storage = storage}
end

local cache = {} -- player id -> {at, [false] = state, [true] = state}
local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

function PD.invalidate(player)
	local id = type(player) == "number" and player or (player and player:getId())
	if id then
		cache[id] = nil
	end
end

-- the state of a player for a hit (cached for cfg().cacheMs)
function PD.state(player, pvp)
	local id = player:getId()
	local t = now()
	local e = cache[id]
	if not e or t - e.at > cfg().cacheMs then
		e = {at = t}
		cache[id] = e
	end
	local key = pvp and true or false
	local s = e[key]
	if not s then
		s = read(player, key)
		s.level = player:getLevel()
		s.area = tonumber(try(PD.hooks.area, player)) or 0
		s.capDelta = tonumber(try(PD.hooks.capDelta, player)) or 0
		e[key] = s
	end
	return s
end

function PD.sums(player, pvp)
	return PD.state(player, pvp).sums
end

function PD.penaltyOf(player)
	return C.penalty(cfg(), player:getLevel())
end

-- the four resistances of a player (percent, penalty and the cap included, no penetration): {fire = r, ...}
function PD.resistances(player, pvp)
	local s = PD.state(player, pvp)
	return C.resistances(def(), cfg(), s.sums, {level = s.level, area = s.area, capDelta = s.capDelta, pen = 0})
end

-- everything the character sheet shows (charsheet.lua, Inspect Player, the Skills window): the four resistances with
-- their sum, the penalty and the result, the armour, the armour share against a typical hit, the physical reduction, the
-- physical total against a typical hit (armour and reduction, at most 90), dodge, block and spell suppression (capped)
function PD.sheet(player)
	local s = PD.state(player, false)
	local c, d = cfg(), def()
	local penalty = C.penalty(c, s.level)
	local res = {}
	for _, g in ipairs(c.groupOrder) do
		res[#res + 1] = {k = g, sum = s.sums.group[g], penalty = penalty + s.area,
			pct = C.resistance(d, c, s.sums.group[g], {level = s.level, area = s.area, capDelta = s.capDelta, pen = 0})}
	end
	local hit = C.typicalHit(c, s.level)
	local share = C.armourShare(d, s.A, hit)
	return {armor = s.A, armourShare = share * 100, reduction = s.sums.phys, hit = hit,
		physical = C.physicalTotal(d, share, s.sums.phys) * 100, dodge = math.min(c.dodgeCap, s.dodge),
		block = math.min(d.blockCap, s.block), suppress = math.min(c.suppressCap, s.suppress), penalty = penalty,
		cap = d.resistCap + s.capDelta, resist = res}
end

-- one number per damage type name (fire, ice, energy ... physical) for the death advice: the result of the group, the
-- physical total against a typical hit for physical; nil for a type without a group
function PD.resistOfElement(player, el)
	local ctype = K[el]
	if not ctype then
		return nil
	end
	if ctype == K.physical then
		return PD.sheet(player).physical
	end
	local g = GROUP_OF[ctype]
	return g and PD.resistances(player)[g] or nil
end

local function playerOf(attacker)
	if not attacker then
		return nil
	end
	if attacker:isPlayer() then
		return attacker
	end
	local master = attacker:getMaster()
	return master and master:isPlayer() and master or nil
end

local function ceiling()
	return ChaosItemMods and ChaosItemMods.config and ChaosItemMods.config.absorbCeiling or 75
end

local ctxBox = {k = K}
local function rand(n)
	return math.random(n)
end

-- the context of one hit on `player` by `attacker` (nil: no creature: a field, the environment)
local function contextFor(player, attacker)
	local foe = playerOf(attacker)
	local s = PD.state(player, foe ~= nil)
	local ctx = ctxBox
	ctx.def, ctx.cfg, ctx.groupOf = def(), cfg(), GROUP_OF
	ctx.sums, ctx.A = s.sums, s.A
	ctx.dodge, ctx.block, ctx.suppress = s.dodge, s.block, s.suppress
	ctx.level, ctx.area, ctx.capDelta = s.level, s.area, s.capDelta
	ctx.pen, ctx.physPen = 0, 0
	if foe then -- penetration of a player attacker (PvP): the monsters have none
		ctx.pen = bonus(foe, "elepen")
		ctx.physPen = bonus(foe, "physpen")
	end
	ctx.engineKeep = cfg().undoEngineAbsorb and function(ctype)
		local list = ctype and s.worn[ctype]
		if not list then
			return nil
		end
		return C.engineKeep(list, s.storage[ctype], ceiling())
	end or nil
	ctx.rand = rand
	return ctx
end

local SHIELD_KEY = "zdefence"

local ev = CreatureEvent("ChaosPlayerDefence")
function ev.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING or not PD.active() or attacker == creature or not creature:isPlayer()
			or (primaryDamage == 0 and secondaryDamage == 0) then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	-- the mana shield took part of this hit and its mana event ran this layer on the whole hit already
	if attacker and ChaosManaShield and ChaosManaShield.scaled(creature, attacker, SHIELD_KEY) then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local ctx = contextFor(creature, attacker)
	local pd, sd, info = C.defend(ctx, {primary = primaryDamage, ptype = primaryType, secondary = secondaryDamage,
		stype = secondaryType, origin = origin})
	if (info.dodged or info.blocked) and CONST_ME_BLOCKHIT then
		creature:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
		if info.dodged then
			for _, fn in pairs(SRC.onDodge) do
				try(fn, creature, attacker)
			end
		end
		local IM = ChaosItemMods
		if IM and IM.onAvoid and attacker then
			IM.onAvoid(creature, attacker, info.dodged and "dodge" or "block",
				math.abs(primaryDamage) + math.abs(secondaryDamage)) -- Glacial Ward (item_powers.lua), sets
		end
	end
	return pd, primaryType, sd, secondaryType
end
ev:register()

-- the mana shield: the engine hands the whole hit to the mana event first. The same layer scales the amount the mana pays
-- ("zdefence" sorts after every other provider, so it sees the rank and rift damage); when the mana cannot take it all the
-- health event leaves the rest as it is.
ChaosManaShield.provide(SHIELD_KEY, {
	hit = function(player, attacker, amount, ctx)
		if not PD.active() or not player:isPlayer() then
			return nil
		end
		local c = contextFor(player, attacker)
		local pt = ctx and ctx.primaryType or K.physical
		local pd = C.defend(c, {primary = -amount, ptype = pt, secondary = 0, stype = nil, origin = ctx and ctx.origin})
		return math.abs(pd)
	end
})

-- "Chaos0Z..." sorts after "Chaos0TierLogin" and before "Chaos1ManaShieldLogin": the third damage multiplier of the monster
-- stage is the last thing before this layer
local login = CreatureEvent("Chaos0ZPlayerDefenceLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPlayerDefence")
	player:registerEvent("ChaosPlayerDefenceAdvance")
	player:registerEvent("ChaosPlayerDefenceLogout")
	PD.invalidate(player)
	PD.notify(player, nil)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosPlayerDefenceLogout")
function logout.onLogout(player)
	PD.invalidate(player)
	return true
end
logout:type("logout")
logout:register()

-- ------------------------------------------------------------------------------------------------- level penalty notices
local function say(player, text, ...)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, text, ...))
end

-- tell the player about the penalty: the mark just crossed (oldLevel -> newLevel), else the warning of levels below a mark
-- (once per level, the last level told is a storage)
function PD.notify(player, oldLevel)
	local c = cfg()
	local level = player:getLevel()
	local key = c.storage.lastWarned
	if oldLevel then
		local m = C.crossed(c, oldLevel, level)
		if m then
			player:setStorageValue(key, level)
			say(player, "Your resistances now carry a penalty of %d points (level %d). Raise them with gear and the passive tree.",
				m.points, m.level)
			return "crossed"
		end
	end
	local w = C.warning(c, level)
	if w and (tonumber(player:getStorageValue(key)) or -1) ~= level then
		player:setStorageValue(key, level)
		say(player, "Warning: at level %d all your resistances drop by %d points. Raise them before you get there.", w.level,
			w.points)
		return "warning"
	end
	return nil
end

local advance = CreatureEvent("ChaosPlayerDefenceAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL or skill == nil then
		PD.invalidate(player)
		PD.notify(player, oldLevel)
	end
	return true
end
advance:type("advance")
advance:register()

-- the equipment and storages changed: read the sums again at the next hit
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if player then
		PD.invalidate(player)
	end
end
moved:register(12)
