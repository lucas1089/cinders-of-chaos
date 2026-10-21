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
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
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

-- Chaos.registerOnce / eventKnown (chaos_constants.lua): register on a monster once, not at every hit
local function registerOnce(creature, name)
	local f = Chaos and Chaos.registerOnce
	if f then
		return f(creature, name)
	end
	creature:registerEvent(name)
	return true
end
local function eventKnown(creature, name)
	local f = Chaos and Chaos.eventKnown
	return f ~= nil and f(creature, name)
end
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and creature ~= target and not eventKnown(target, "ChaosGemsDealt") then
		local p = playerOf(creature)
		local t = p and cache[p:getId()]
		if t and hasDamage(t) then
			registerOnce(target, "ChaosGemsDealt")
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

-- count of id into the backpack; what does not fit goes to the depot inbox, and without one to the player's feet (never
-- lost). Returns false (all in the backpack), "inbox" or "ground"
local function give(player, id, count)
	local rest = count - (tonumber(Chaos.giveItem(player, id, count)) or 0)
	if rest <= 0 then
		return false
	end
	local inbox = player:getInbox()
	if inbox then
		inbox:addItem(id, rest, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		return "inbox"
	end
	Game.createItem(id, rest, player:getPosition())
	return "ground"
end
G.give = give

local function whereText(where)
	if where == "inbox" then
		return " It is in your inbox (no room)."
	elseif where == "ground" then
		return " It is at your feet (no room)."
	end
	return ""
end

-- Where a gem stack is for this player: "carried" (equipment, backpack and the bags in it: what the engine's
-- player:getItemCount / removeItem see), "box" (the player's own, but outside that walk: the purse = store inbox, the
-- depot inbox and the depot chest; only their owner can open them) or nil (the ground, someone else's).
local BOX = {[26052] = "purse", [14404] = "inbox", [2589] = "locker"} -- ITEM_STORE_INBOX, ITEM_INBOX, ITEM_LOCKER1
local function idOf(thing)
	if not thing or not thing.isItem then
		return nil
	end
	local ok, id = pcall(function() return thing:isItem() and thing:getId() end)
	return ok and id or nil
end
local function placeOf(player, item)
	local inBox = false
	local p = item
	for _ = 1, 32 do
		local ok, parent = pcall(function() return p:getParent() end)
		if not ok or not parent then
			break
		end
		local kind = BOX[idOf(parent)]
		if kind == "inbox" or kind == "locker" then
			return "box"
		elseif kind == "purse" then
			inBox = true
		end
		p = parent
	end
	if owns(player, item) then
		return inBox and "box" or "carried"
	end
	return nil
end

local function isLocked(item)
	return ChaosCrafting.customNumber(item, "chaos_locked") ~= 0
end

local function same(a, b)
	local ok, r = pcall(function() return a == b end)
	return ok and r or rawequal(a, b)
end

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

-- three gems of this id -> one of the next tier. used / target: the stacks of the use with (the same stack when the
-- player used a stack on itself), optional. The engine's player:getItemCount / removeItem only see what the player
-- carries (equipment, backpack, bags), so the stacks clicked in the purse or the depot are counted and taken here
-- first, the rest from what is carried. Everything is counted before anything is taken; a removal that fails gives
-- back what was taken. Returns ok, text
function G.combine(player, id, used, target)
	local newId, why = G.combineResult(id)
	if not newId then
		return false, G.reasons[why] or why
	end
	local boxed, extra = {}, 0
	local picked = {}
	for _, s in ipairs({used, target}) do
		if s and s.getId and s:getId() == id and not (picked[1] and same(picked[1], s)) then
			picked[#picked + 1] = s
			local place = placeOf(player, s)
			if not place then
				return false, G.reasons.notYours
			end
			if isLocked(s) then
				return false, G.reasons.locked
			end
			if place == "box" then
				local n = tonumber(s:getCount()) or 0
				boxed[#boxed + 1] = {item = s, count = n}
				extra = extra + n
			end
		end
	end
	local carried = tonumber(player:getItemCount(id)) or 0
	if carried + extra < 3 then
		return false, G.reasons.needThree
	end
	local need, taken = 3, 0
	for _, b in ipairs(boxed) do
		local n = math.min(need, b.count)
		if n > 0 then
			if b.item:remove(n) == false then
				if taken > 0 then
					give(player, id, taken)
				end
				return false, G.reasons.needThree
			end
			need, taken = need - n, taken + n
		end
	end
	if need > 0 and not player:removeItem(id, need) then
		if taken > 0 then
			give(player, id, taken)
		end
		return false, G.reasons.needThree
	end
	local where = give(player, newId, 1)
	local text = string.format("Three %s became a %s.%s", (G.listText({{id = id, count = 3}}):gsub("^3 ", "")),
		G.gemName(newId), whereText(where))
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
		if not Chaos.pay(player, cost) then
			return false, string.format("Taking the %s out unharmed costs %d gold (bank or backpack).", G.gemName(id), cost)
		end
	end
	G.take(item, index)
	changed(player, item)
	local name = ChaosCrafting.itemName(item)
	local text
	if keep then
		text = string.format("%s taken out of %s for %d gold.%s", G.gemName(id), name, cost,
			whereText(give(player, id, 1)))
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
	player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player,
		"%s%s - %s. Use it with a piece of gear that has a free socket to socket it, or with %s of the same kind to combine three into one of the next quality.", prefix and Chaos.t(player, prefix) or "", G.gemName(id), G.gemSummary(id),
		Chaos.t(player, G.gemOf(id).tier < G.TIERS and "a gem" or "nothing (Perfect is the best quality)")))
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
		ok, text = G.combine(player, id, item, target)
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
		player:sendCancelMessage(Chaos.t(player, text))
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
