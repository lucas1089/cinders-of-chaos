-- Smart loot (server/README.md "Smart loot"): a gear drop that nobody near the corpse can wear may become a gear item of
-- the same monster's loot table that someone near can wear, and the Chaos extra rolls favour gear made for the corpse
-- owner's class (SL.reweight; the sum of the gear chances stays). Rules: smartloot_core.lua (pure, tests/smartloot_test.lua);
-- numbers: smartloot_config.lua.
--
-- Called by loot.lua (the Chaos loot layer, step 1b) after the extra rolls and before the gear quality step, so a
-- swapped item still gets its rarity floor, item level, modifiers and sockets like any other drop. The swap is
-- Item:transform: the item keeps the rarity the stock roll gave it.
-- Who can wear what: the equip rules of movements.xml and weapons.xml (class and level), read once by the Gambler's
-- parser (ChaosGamble.rules, gamble.lua). Without that parser nothing is swapped. An item without a rule is wearable by
-- every class and is never swapped.
-- Assumed engine API (TFS 1.4): ItemType:getWeaponType/getSlotPosition, Item:transform, Container:getItem/getSize,
-- Player:getParty/getVocation/getLevel/getPosition, Party:getMembers/getLeader. Lua 5.1 / LuaJIT and Lua 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/smartloot_core.lua")
ChaosSmartLootConfig = dofile("data/scripts/chaos/smartloot_config.lua")

ChaosSmartLoot = ChaosSmartLoot or {}
local SL = ChaosSmartLoot
local K = ChaosSmartLootCore

SL.kinds = SL.kinds or {} -- item id -> kind (cached)

local function cfg()
	return ChaosSmartLootConfig
end

local function log(text)
	print("[Chaos smart loot] " .. text)
end

-- the kind of an item: weapon, shield, quiver or its slot (head, armor, legs, feet, ring, necklace); "other" else
function SL.kindOf(id)
	local k = SL.kinds[id]
	if k then
		return k
	end
	local ok, res = pcall(function()
		local it = ItemType(id)
		if ChaosItemMods and ChaosItemMods.kindOfType and ChaosItemMods.kindOfType(it) == "quiver" then
			return "quiver"
		end
		local wt = it:getWeaponType()
		if WEAPON_SHIELD and wt == WEAPON_SHIELD then
			return "shield"
		end
		if wt and wt ~= (WEAPON_NONE or 0) then
			return "weapon"
		end
		local slot = it:getSlotPosition() or 0
		local map = {{SLOTP_HEAD, "head"}, {SLOTP_ARMOR, "armor"}, {SLOTP_LEGS, "legs"}, {SLOTP_FEET, "feet"},
			{SLOTP_RING, "ring"}, {SLOTP_NECKLACE, "necklace"}}
		for _, m in ipairs(map) do
			if m[1] and m[1] > 0 and math.floor(slot / m[1]) % 2 == 1 then
				return m[2]
			end
		end
		return "other"
	end)
	k = ok and res or "other"
	SL.kinds[id] = k
	return k
end

local function wearerOf(player)
	local ok, voc, level = pcall(function()
		return player:getVocation():getName(), player:getLevel()
	end)
	if not ok then
		return nil
	end
	return {voc = tostring(voc or ""):lower(), level = tonumber(level) or 1}
end

-- the corpse owner and the owner's party members on the same floor within cfg.partyRange of the corpse
function SL.wearers(owner, pos)
	local out = {}
	local first = wearerOf(owner)
	if first then
		out[1] = first
	end
	local party = owner.getParty and owner:getParty()
	if not party or not pos then
		return out
	end
	local members = party:getMembers() or {}
	members[#members + 1] = party:getLeader()
	local range = cfg().partyRange or 30
	for _, m in ipairs(members) do
		if m and m:getId() ~= owner:getId() then
			local p = m:getPosition()
			if p.z == pos.z and math.abs(p.x - pos.x) <= range and math.abs(p.y - pos.y) <= range then
				local w = wearerOf(m)
				if w then
					out[#out + 1] = w
				end
			end
		end
	end
	return out
end

local function isRolled(item)
	return ChaosLoot and ChaosLoot.isRolled and ChaosLoot.isRolled(item)
end

-- loot.lua step 1: the loot table for the Chaos extra rolls, the gear chances favouring the corpse owner's class
-- (smartloot_config.lua weights). The table itself when off or without the equip rules.
function SL.reweight(lootTable, owner)
	local c = cfg()
	if not c or not c.enabled or not c.weights or not owner or not lootTable then
		return lootTable
	end
	local G = ChaosGamble
	local rules = G and G.rules and G.rules()
	local w = wearerOf(owner)
	if not rules or not w or not (ChaosLoot and ChaosLoot.isGearId) then
		return lootTable
	end
	return K.reweight(lootTable, {cfg = c, wearers = {w}, isGear = ChaosLoot.isGearId,
		ruleOf = function(id) return rules[id] end})
end

-- loot.lua step 1b. Returns the number of swaps.
function SL.apply(corpse, owner, lootTable, rnd)
	local c = cfg()
	if not c or not c.enabled or not owner or not corpse or not lootTable then
		return 0
	end
	local G = ChaosGamble
	local rules = G and G.rules and G.rules()
	if not rules or not (ChaosLoot and ChaosLoot.isGearId) then
		return 0
	end
	local list, items = {}, {}
	for slot = 0, corpse:getSize() - 1 do
		local item = corpse:getItem(slot)
		if item and not item:isContainer() and not isRolled(item) then
			list[#list + 1] = item:getId()
			items[#list] = item
		end
	end
	if #list == 0 then
		return 0
	end
	local swaps = K.plan(list, {
		cfg = c,
		lootTable = lootTable,
		wearers = SL.wearers(owner, corpse:getPosition()),
		isGear = ChaosLoot.isGearId,
		ruleOf = function(id) return rules[id] end,
		kindOf = SL.kindOf,
		rnd = rnd or math.random
	})
	local done = 0
	for _, s in ipairs(swaps) do
		local item = items[s.index]
		local ok, res = pcall(function() return item:transform(s.to) end)
		if ok and res ~= false then
			done = done + 1
		elseif not ok then
			log("transform " .. s.from .. " -> " .. s.to .. ": " .. tostring(res))
		end
	end
	return done
end
