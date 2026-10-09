-- Chaos item modifiers on the character: the totals of the equipped items' Chaos modifiers (data/lib/chaos_item_mods.lua,
-- custom attributes "chaos_mod_<key>") applied to the player. Overview: server/README.md "Item modifiers".
--
-- Like customs/rarity/base_rarity.lua, the totals are worked out again when an item is put on or taken off
-- (EventCallback onItemMoved) and at login; a check every few seconds catches items that left a slot another way
-- (decay, a script). The totals are kept in memory per player (ChaosItemModsCache) and capped per modifier; nothing
-- is written to storages, so nothing can stack across logins.
--   movement speed     Creature:changeSpeed by the difference to what was applied before (% of the base speed)
--   attack speed       none here: it is the weapon's own attack interval (chaos_item_mods.lua M.syncAttackSpeed)
--   elites and bosses  damage dealt to magic / rare / legendary monsters and bosses (onHealthChange on the target,
--                      registered by onTargetCombat, like passivetree_effects.lua)
--   life / mana on kill  CreatureEvent onKill, monsters only
--   dodge, reflect, thorns, damage taken from monsters  onHealthChange on the player (hits from creatures)
--   healing done       onHealthChange on the healed player (the healer's bonus)
--   experience         EventCallback onGainExperience
--   gold find          EventCallback onDropLoot (priority 2, as Paragon's gold find)
--   item / rarity find read by loot.lua (ChaosItemMods.playerBonus)
-- The gems in the sockets of the same items (data/lib/chaos_gems.lua) are summed on the same path: their totals
-- (ChaosGems.totals) are worked out here with the modifiers' and handed to gems.lua (ChaosGems.applyTotals); gem
-- Movement Speed is added to the modifier's under the modifier's cap.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua") -- loads chaos_item_mods.lua
end

local M = ChaosItemMods
ChaosItemModsCache = ChaosItemModsCache or {} -- player id -> totals {key -> value}
local cache = ChaosItemModsCache
local applied = {} -- player id -> {speed = n, sig = "..."}
local CHECK_INTERVAL = 3000 -- ms between two checks of the equipment of everyone online
local guard = false -- reflect / thorns hits must not trigger more reflect / thorns

-- ---------------------------------------------------------------- equipped items
local SLOT_BITS = {
	[CONST_SLOT_HEAD] = SLOTP_HEAD, [CONST_SLOT_NECKLACE] = SLOTP_NECKLACE, [CONST_SLOT_ARMOR] = SLOTP_ARMOR,
	[CONST_SLOT_LEGS] = SLOTP_LEGS, [CONST_SLOT_FEET] = SLOTP_FEET, [CONST_SLOT_RING] = SLOTP_RING,
	[CONST_SLOT_RIGHT] = SLOTP_RIGHT, [CONST_SLOT_LEFT] = SLOTP_LEFT
}
if CONST_SLOT_BADGE and SLOTP_BADGE then
	SLOT_BITS[CONST_SLOT_BADGE] = SLOTP_BADGE
end
if CONST_SLOT_GLOVES and SLOTP_GLOVES then
	SLOT_BITS[CONST_SLOT_GLOVES] = SLOTP_GLOVES
end
if CONST_SLOT_BELT and SLOTP_BELT then
	SLOT_BITS[CONST_SLOT_BELT] = SLOTP_BELT
end

local function fits(item, slot)
	local bitValue = SLOT_BITS[slot]
	if not bitValue then
		return false
	end
	local it = item:getType()
	local slots = it:getSlotPosition()
	if math.floor(slots / bitValue) % 2 == 1 then
		return true
	end
	-- hands: weapons and shields (two-handed weapons carry SLOTP_TWO_HAND, a dual-wield off-hand sword the other hand)
	if slot == CONST_SLOT_LEFT or slot == CONST_SLOT_RIGHT then
		return it:getWeaponType() ~= WEAPON_NONE and it:getWeaponType() ~= WEAPON_AMMO
	end
	return false
end

local function equipped(player)
	local items, sig = {}, {}
	for slot in pairs(SLOT_BITS) do
		local item = player:getSlotItem(slot)
		if item and fits(item, slot) then
			local mods = M.read(item)
			local gems = ChaosGems and ChaosGems.read(item)
			if #mods > 0 or (gems and gems.filled > 0) then
				items[#items + 1] = item
				for _, m in ipairs(mods) do
					sig[#sig + 1] = slot .. m.key .. m.value
				end
				for i = 1, gems and gems.count or 0 do
					if gems.gems[i] > 0 then
						sig[#sig + 1] = slot .. "g" .. i .. ":" .. gems.gems[i]
					end
				end
			end
		end
	end
	table.sort(sig)
	return items, table.concat(sig, ",")
end

-- ---------------------------------------------------------------- totals and speed
local function applySpeed(player, state, totals)
	local want = M.speedBonus(player:getBaseSpeed(), totals.movespeed or 0)
	if want ~= state.speed then
		player:changeSpeed(want - state.speed)
		state.speed = want
	end
end

function M.refresh(player, force)
	local id = player:getId()
	local state = applied[id] or {speed = 0, sig = nil}
	applied[id] = state
	local items, sig = equipped(player)
	if not force and sig == state.sig then
		return cache[id]
	end
	state.sig = sig
	local totals = M.totals(items)
	if ChaosGems and ChaosGems.totals then
		local gemTotals = ChaosGems.totals(items)
		local def = M.byKey.movespeed
		totals.movespeed = math.min(def and def.cap or 12, (totals.movespeed or 0) + (gemTotals.movespeed or 0))
		if ChaosGems.applyTotals then
			ChaosGems.applyTotals(player, gemTotals)
		end
	end
	cache[id] = totals
	applySpeed(player, state, totals)
	return totals
end

-- a player's capped total of one modifier (0 when none or offline)
function M.playerBonus(player, key)
	if not player then
		return 0
	end
	local ok, id = pcall(function() return player:getId() end)
	local totals = ok and cache[id]
	return totals and totals[key] or 0
end

-- ---------------------------------------------------------------- equip / unequip
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	local inv = CONTAINER_POSITION or 0xFFFF
	local fromSlot = fromPosition.x == inv and math.floor(fromPosition.y / 64) % 2 == 0
	local toSlot = toPosition.x == inv and math.floor(toPosition.y / 64) % 2 == 0
	if fromSlot or toSlot then
		M.refresh(player)
	end
end
moved:register(11) -- after base_rarity.lua (10)

local function checkAll()
	for _, player in ipairs(Game.getPlayers()) do
		if applied[player:getId()] then
			M.refresh(player)
		end
	end
	addEvent(checkAll, CHECK_INTERVAL)
end

local startup = GlobalEvent("ChaosItemModsStartup")
function startup.onStartup()
	addEvent(checkAll, CHECK_INTERVAL)
	return true
end
startup:register()

-- ---------------------------------------------------------------- damage
local function isElite(creature)
	if not creature or not creature:isMonster() then
		return false
	end
	local tier = type(ChaosTierOf) == "function" and ChaosTierOf(creature) or "normal"
	if tier ~= "normal" then
		return true
	end
	local mt = creature:getType()
	local ok, boss = pcall(function() return mt and mt:isBoss() end)
	return ok and boss or false
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	return master and master:isPlayer() and master or nil
end

-- damage dealt to elites and bosses
local dealt = CreatureEvent("ChaosItemModsDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if guard or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local p = playerOf(attacker)
	local pct = p and M.playerBonus(p, "bossdamage") or 0
	if pct > 0 and isElite(creature) then
		primaryDamage = M.scale(primaryDamage, pct)
		secondaryDamage = M.scale(secondaryDamage, pct)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:register()

local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and target:isMonster() then
		local p = playerOf(creature)
		if p and M.playerBonus(p, "bossdamage") > 0 then
			target:registerEvent("ChaosItemModsDealt")
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

-- hits taken (dodge, damage from monsters, reflect, thorns) and heals received (the healer's Healing Done)
local taken = CreatureEvent("ChaosItemModsTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if guard then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if primaryType == COMBAT_HEALING then
		local healer = playerOf(attacker)
		local pct = healer and M.playerBonus(healer, "healing") or 0
		if pct > 0 then
			primaryDamage = M.scale(primaryDamage, pct)
		end
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if not attacker or attacker == creature then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local totals = cache[creature:getId()]
	if not totals then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if (totals.dodge or 0) > 0 and math.random(1, 100) <= totals.dodge then
		creature:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
		return 0, primaryType, 0, secondaryType
	end
	if (totals.monsterreduction or 0) > 0 and attacker:isMonster() then
		primaryDamage = M.scale(primaryDamage, -totals.monsterreduction)
		secondaryDamage = M.scale(secondaryDamage, -totals.monsterreduction)
	end
	local attackerId = attacker:getId()
	local back = 0
	if (totals.reflect or 0) > 0 then
		local landed = math.min(math.abs(primaryDamage) + math.abs(secondaryDamage), creature:getHealth())
		back = back + M.reflected(landed, totals.reflect)
	end
	if (totals.thorns or 0) > 0 and origin == ORIGIN_MELEE then
		back = back + totals.thorns
	end
	if back > 0 then
		guard = true
		doTargetCombatHealth(creature:getId(), attackerId, COMBAT_PHYSICALDAMAGE, -back, -back, CONST_ME_NONE)
		guard = false
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

-- ---------------------------------------------------------------- kills
-- this engine's Creature:addHealth takes (damage type, amount); a one-argument call heals nothing (Chaos.heal)
local function heal(creature, amount)
	if Chaos.heal then
		return Chaos.heal(creature, amount)
	end
	local before = creature:getHealth()
	amount = math.min(math.floor(amount), creature:getMaxHealth() - before)
	if amount > 0 then
		creature:addHealth("healing", amount)
		if creature:getHealth() == before then
			creature:addHealth(amount)
		end
	end
end

local killed = {} -- monster id -> true (onKill may run for more than one killer)
local kill = CreatureEvent("ChaosItemModsKill")
function kill.onKill(player, target)
	if not target or not target:isMonster() or target:getMaster() then
		return true
	end
	local totals = cache[player:getId()]
	if not totals then
		return true
	end
	local key = player:getId() .. ":" .. target:getId()
	if killed[key] then
		return true
	end
	killed[key] = true
	addEvent(function() killed[key] = nil end, 2000)
	if (totals.lifeonkill or 0) > 0 then
		heal(player, totals.lifeonkill)
	end
	if (totals.manaonkill or 0) > 0 then
		player:addMana(totals.manaonkill)
	end
	return true
end
kill:register()

-- ---------------------------------------------------------------- experience and gold
local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	local pct = M.playerBonus(self, "experience")
	if pct > 0 and source then
		return M.experience(exp, pct)
	end
	return exp
end
xpCb:register(1)

local COINS = {{2160, 10000}, {2152, 100}, {2148, 1}} -- crystal, platinum, gold coin
local goldCb = EventCallback
goldCb.onDropLoot = function(self, corpse)
	local owner = corpse and Player(corpse:getCorpseOwner())
	local pct = owner and M.playerBonus(owner, "goldfind") or 0
	if pct <= 0 then
		return
	end
	local value = 0
	for slot = 0, corpse:getSize() - 1 do
		local item = corpse:getItem(slot)
		if item then
			for _, coin in ipairs(COINS) do
				if item:getId() == coin[1] then
					value = value + item:getCount() * coin[2]
				end
			end
		end
	end
	local exact = value * pct / 100
	local extra = math.floor(exact)
	if math.random() < exact - extra then
		extra = extra + 1
	end
	for _, coin in ipairs(COINS) do
		local n = math.floor(extra / coin[2])
		extra = extra - n * coin[2]
		while n > 0 do
			local stack = math.min(n, 100)
			corpse:addItem(coin[1], stack)
			n = n - stack
		end
	end
end
-- after the stock loot (0) and the Chaos loot layer (1), before autoloot (3), so autoloot picks the extra coins up
goldCb:register(2)

-- ---------------------------------------------------------------- drops
-- The engine rolls the rarity of a corpse's items in Monster::dropLoot AFTER every Lua onDropLoot callback, and appends
-- its text to the description. loot.lua calls this for a corpse whose items got Chaos modifiers: the corpse is marked
-- and, right after the engine is done, the description of those items is written again from their attributes.
local PENDING = "chaos_mods_pending"
function M.afterDrop(corpse)
	local ok = pcall(function() corpse:setCustomAttribute(PENDING, 1) end)
	if ok then
		local pos = corpse:getPosition()
		addEvent(M.fixCorpses, 0, {x = pos.x, y = pos.y, z = pos.z})
	end
end

function M.fixCorpses(pos)
	local tile = Tile(Position(pos.x, pos.y, pos.z))
	for _, corpse in ipairs(tile and tile:getItems() or {}) do
		if corpse:isContainer() and corpse:getCustomAttribute(PENDING) then
			corpse:removeCustomAttribute(PENDING)
			for _, item in ipairs(corpse:getItems(true)) do
				if #M.read(item) > 0 or (ChaosGems and ChaosGems.count(item) > 0) then
					ChaosCrafting.rewriteDescription(item)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- login / level / logout
local login = CreatureEvent("ChaosItemModsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosItemModsTaken")
	player:registerEvent("ChaosItemModsKill")
	player:registerEvent("ChaosItemModsAdvance")
	player:registerEvent("ChaosItemModsLogout")
	M.refresh(player, true)
	return true
end
login:register()

-- the movement speed share follows the base speed, which grows with every level
local advance = CreatureEvent("ChaosItemModsAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and applied[player:getId()] then
		applySpeed(player, applied[player:getId()], cache[player:getId()] or {})
	end
	return true
end
advance:register()

local logout = CreatureEvent("ChaosItemModsLogout")
function logout.onLogout(player)
	applied[player:getId()] = nil
	cache[player:getId()] = nil
	if ChaosGems and ChaosGems.forget then
		ChaosGems.forget(player)
	end
	return true
end
logout:register()
