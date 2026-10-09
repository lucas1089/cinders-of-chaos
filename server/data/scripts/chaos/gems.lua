-- Gems and sockets on the server: use-with of the gems (socket into gear, combine three into one), taking gems out
-- (the crafting bench calls ChaosGems.unsocket), and the gem effects on the character. Rules and numbers live in
-- data/lib/chaos_gems.lua and chaos_gems_config.lua; overview: server/README.md "Gems and sockets".
--
-- Effects. item_mods.lua works out the totals of the equipped items (ChaosGems.totals, same path and same moments as
-- the Chaos item modifiers: equip / unequip, login, a check every 3 s) and hands them to ChaosGems.applyTotals:
--   max health, max mana, critical chance + extra damage, life leech chance + amount
--                          one CONDITION_ATTRIBUTES (sub id SUBID) with those parameters, replaced when they change
--   element damage         onHealthChange on the target (registered by onTargetCombat): the player's hits (and their
--                          summons') of that combat type, primary and secondary part, +N%
--   resistances            onHealthChange on the player: hits of that combat type -N%
--   movement speed         added to the item modifier in item_mods.lua (shared cap)
--   attack speed           the weapon's own attack interval (chaos_item_mods.lua M.syncAttackSpeed)
-- Totals live in memory (ChaosGemsCache), nothing is written to storages.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua") -- loads chaos_item_mods.lua and chaos_gems.lua
end

local G = ChaosGems
local cfg = G.config
ChaosGemsCache = ChaosGemsCache or {} -- player id -> totals
local cache = ChaosGemsCache
local appliedSig = {} -- player id -> signature of the condition values
local SUBID = 7240 -- next to the passive tree's conditions (7200-7221)

-- ---------------------------------------------------------------- the condition
local PARAMS = {
	{"maxhealth", CONDITION_PARAM_STAT_MAXHITPOINTS},
	{"maxmana", CONDITION_PARAM_STAT_MAXMANAPOINTS},
	{"crit", CONDITION_PARAM_SPECIALSKILL_CRITICALHITCHANCE},
	{"crit2", CONDITION_PARAM_SPECIALSKILL_CRITICALHITAMOUNT},
	{"leech", CONDITION_PARAM_SPECIALSKILL_LIFELEECHCHANCE},
	{"leech2", CONDITION_PARAM_SPECIALSKILL_LIFELEECHAMOUNT}
}

function G.applyTotals(player, totals)
	local id = player:getId()
	cache[id] = totals
	local parts = {}
	for _, p in ipairs(PARAMS) do
		parts[#parts + 1] = tostring(totals[p[1]] or 0)
	end
	local sig = table.concat(parts, ",")
	if appliedSig[id] == sig then
		return
	end
	appliedSig[id] = sig
	player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, SUBID, true)
	local any = false
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT)
	c:setTicks(-1)
	c:setParameter(CONDITION_PARAM_SUBID, SUBID)
	for _, p in ipairs(PARAMS) do
		local v = totals[p[1]] or 0
		if v > 0 and p[2] then
			c:setParameter(p[2], v)
			any = true
		end
	end
	if any then
		player:addCondition(c)
	end
end

function G.forget(player)
	local id = player:getId()
	cache[id] = nil
	appliedSig[id] = nil
end

-- a player's capped gem total of one effect (0 when none or offline)
function G.playerBonus(player, key)
	local ok, id = pcall(function() return player:getId() end)
	local t = ok and cache[id]
	return t and t[key] or 0
end

-- ---------------------------------------------------------------- damage dealt and taken
local DAMAGE = {
	[COMBAT_PHYSICALDAMAGE] = "physical", [COMBAT_FIREDAMAGE] = "fire", [COMBAT_ICEDAMAGE] = "ice",
	[COMBAT_EARTHDAMAGE] = "earth", [COMBAT_ENERGYDAMAGE] = "energy", [COMBAT_DEATHDAMAGE] = "death",
	[COMBAT_HOLYDAMAGE] = "holy"
}

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

local function hasDamage(t)
	for _, name in pairs(DAMAGE) do
		if (t["dmg_" .. name] or 0) > 0 then
			return true
		end
	end
	return false
end

local dealt = CreatureEvent("ChaosGemsDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local p = playerOf(attacker)
	local t = p and p ~= creature and cache[p:getId()]
	if t then
		local a = DAMAGE[primaryType] and t["dmg_" .. DAMAGE[primaryType]] or 0
		if a > 0 and primaryDamage ~= 0 then
			primaryDamage = G.scale(primaryDamage, a)
		end
		local b = DAMAGE[secondaryType] and t["dmg_" .. DAMAGE[secondaryType]] or 0
		if b > 0 and secondaryDamage ~= 0 then
			secondaryDamage = G.scale(secondaryDamage, b)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:register()

local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and creature ~= target then
		local p = playerOf(creature)
		local t = p and cache[p:getId()]
		if t and hasDamage(t) then
			target:registerEvent("ChaosGemsDealt")
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

local taken = CreatureEvent("ChaosGemsTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local t = cache[creature:getId()]
	if t then
		local a = DAMAGE[primaryType] and t["res_" .. DAMAGE[primaryType]] or 0
		if a > 0 and primaryDamage ~= 0 then
			primaryDamage = G.scale(primaryDamage, -a)
		end
		local b = DAMAGE[secondaryType] and t["res_" .. DAMAGE[secondaryType]] or 0
		if b > 0 and secondaryDamage ~= 0 then
			secondaryDamage = G.scale(secondaryDamage, -b)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

-- ---------------------------------------------------------------- owning an item
local function holderOf(item)
	local ok, top = pcall(function() return item:getTopParent() end)
	if ok and top and top.isPlayer and top:isPlayer() then
		return top
	end
	return nil
end

local function owns(player, item)
	local h = holderOf(item)
	return h ~= nil and h:getId() == player:getId()
end

local function isEquipped(player, item)
	local ok, parent = pcall(function() return item:getParent() end)
	return ok and parent and parent.isPlayer and parent:isPlayer() or false
end

-- after the sockets of an item changed: its text, the weapon's own interval, the character's totals
local function changed(player, item)
	G.writeDescription(item)
	if ChaosItemMods and ChaosItemMods.syncAttackSpeed then
		ChaosItemMods.syncAttackSpeed(item)
	end
	if isEquipped(player, item) and ChaosItemMods and ChaosItemMods.refresh then
		ChaosItemMods.refresh(player, true)
	end
end

local function give(player, id, count)
	local rest = count - Chaos.giveItem(player, id, count)
	if rest > 0 then
		local inbox = player:getInbox()
		if inbox then
			inbox:addItem(id, rest, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			return true
		end
	end
	return false
end
G.give = give

local function log(player, what, itemName, text)
	if ChaosCraftingLog then
		pcall(ChaosCraftingLog, player, what, itemName, text)
	end
end

-- ---------------------------------------------------------------- socketing, combining, taking out
-- put the used gem (one of the stack gemItem) into target. Returns ok, text
function G.socket(player, gemItem, target)
	local id = gemItem:getId()
	if not owns(player, target) then
		return false, "Socket gems into gear you carry (backpack or equipment)."
	end
	if G.count(target) == 0 then
		return false, G.maxSockets(target) > 0
			and "This item has no sockets. An Orb of Sockets gives it some." or G.reasons.notGear
	end
	local okCount, count = pcall(function() return target:getCount() end)
	if okCount and tonumber(count) and count > 1 then
		return false, G.reasons.stack
	end
	local i = G.insert(target, id)
	if not i then
		return false, G.reasons.full
	end
	gemItem:remove(1)
	changed(player, target)
	local name = ChaosCrafting.itemName(target)
	local e = G.effectOf(id, G.groupOf(target))
	local text = string.format("%s socketed into %s (socket %d): %s.", G.gemName(id), name, i,
		e and G.effectText(e.key, e.value, e.value2) or "no effect")
	log(player, "Gem", name, text)
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	return true, text
end

-- three gems of this id -> one of the next tier. Returns ok, text
function G.combine(player, id)
	local newId, why = G.combineResult(id)
	if not newId then
		return false, G.reasons[why] or why
	end
	if player:getItemCount(id) < 3 then
		return false, G.reasons.needThree
	end
	if not player:removeItem(id, 3) then
		return false, G.reasons.needThree
	end
	local inbox = give(player, newId, 1)
	local text = string.format("Three %s became a %s.%s", (G.listText({{id = id, count = 3}}):gsub("^3 ", "")),
		G.gemName(newId), inbox and " It is in your inbox (no room)." or "")
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	log(player, "Gem", G.gemName(id), text)
	return true, text
end

-- take the gem out of socket index. keep = true: it comes back for the tier's gold cost (bank first, then the
-- backpack); false: it is destroyed (free). Returns ok, text
function G.unsocket(player, item, index, keep)
	index = tonumber(index) or 0
	local id = G.gemAt(item, index)
	if index < 1 or index > G.count(item) or id == 0 then
		return false, G.reasons.noGem
	end
	local cost = keep and G.removeCost(id) or 0
	if cost > 0 then
		local bank = player:getBankBalance()
		if bank >= cost then
			player:setBankBalance(bank - cost)
		elseif not player:removeMoney(cost) then
			return false, string.format("Taking the %s out unharmed costs %d gold (bank or backpack).", G.gemName(id), cost)
		end
	end
	G.take(item, index)
	changed(player, item)
	local name = ChaosCrafting.itemName(item)
	local text
	if keep then
		local inbox = give(player, id, 1)
		text = string.format("%s taken out of %s for %d gold.%s", G.gemName(id), name, cost,
			inbox and " It is in your inbox (no room)." or "")
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	else
		text = string.format("%s shattered (taken out of %s).", G.gemName(id), name)
		player:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
	end
	log(player, keep and "Gem removed" or "Gem shattered", name, text)
	return true, text
end

-- ---------------------------------------------------------------- use-with on every gem
local function hint(player, id, prefix)
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format(
		"%s%s - %s. Use it with a piece of gear that has a free socket to socket it, or with %s of the same kind "
		.. "to combine three into one of the next quality.", prefix or "", G.gemName(id), G.gemSummary(id),
		G.gemOf(id).tier < G.TIERS and "a gem" or "nothing (Perfect is the best quality)"))
end

local function onUseGem(player, item, fromPosition, target, toPosition, isHotkey)
	local id = item:getId()
	local kind = type(target)
	if (kind ~= "userdata" and kind ~= "table") or not target.isItem or not target:isItem() then
		hint(player, id)
		return true
	end
	local ok, text
	if target:getId() == id then
		ok, text = G.combine(player, id)
	elseif G.isGem(target:getId()) then
		ok, text = false, "Only gems of the same kind and quality combine."
	elseif G.maxSockets(target) > 0 then
		ok, text = G.socket(player, item, target)
	else
		hint(player, id, "That cannot hold gems. ")
		return true
	end
	if ok then
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	else
		player:sendCancelMessage(text)
	end
	return true
end

for typeIndex = 1, G.TYPES do
	for tier = 1, G.TIERS do
		local action = Action()
		action.onUse = onUseGem
		action:id(G.gemId(typeIndex, tier))
		action:allowFarUse(false)
		action:register()
	end
end

-- ---------------------------------------------------------------- uniques: the fixed socket in the look text
if ChaosMakeUnique and not G.uniqueWrapped then
	G.uniqueWrapped = true
	local make = ChaosMakeUnique
	ChaosMakeUnique = function(item, ...)
		local res = make(item, ...)
		if item and G.count(item) > 0 then
			pcall(G.writeDescription, item)
		end
		return res
	end
end

-- ---------------------------------------------------------------- login
local login = CreatureEvent("ChaosGemsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosGemsTaken")
	return true
end
login:register()
