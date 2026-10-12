-- Crafting bonus of the base crafting tables (data/scripts/customs/crafting/1crafting_mod.lua, extended opcode 91):
-- crafted equipment rolls a rarity and an item level the way a drop does, crafted potions and runes may come with extra
-- pieces. Both grow with the crafter's skill in the recipe's category above the recipe's level. The base script calls
-- this only through the block server/tools/patch_base_crafting_bonus.py writes into it (`CraftingBonus`), inside the
-- guarded craft (patch_base_crafting.py): after the gold and the materials were taken, before the item is added.
-- Numbers: craft_bonus_config.lua; pure logic: craft_bonus_core.lua (tests: server/tests/craft_bonus_test.lua and
-- server/tests/base_crafting_bonus_test.lua); server/README.md "Crafting bonus".
--
--   ChaosCraftBonus.kind(craft)                        "gear" | "stack" | nil (any other product, tools included:
--                                                        the stock way)
--   ChaosCraftBonus.odds(player, category, craft)      what the window shows for a recipe (sent with the recipe page):
--                                                        gear:  {kind = "gear", level, odds = [{rarity, name, pct}]}
--                                                        stack: {kind = "stack", odds = [{extra, pct}]}
--   ChaosCraftBonus.make(player, category, craft, skill)  gear: {kind, item, rarity, level} (item nil when it could not
--                                                        be made); stack: {kind, extra} (the base script makes the
--                                                        recipe's own count); nil for any other product
--   ChaosCraftBonus.finish(player, craft, made)        after the item was added: gives a stack's extra pieces
--                                                        (backpack, the rest to the store inbox) and returns the text
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua")
end
dofile("data/scripts/chaos/craft_bonus_core.lua")

ChaosCraftBonusConfig = dofile("data/scripts/chaos/craft_bonus_config.lua")
ChaosCraftBonus = ChaosCraftBonus or {}
local B = ChaosCraftBonus
local K = ChaosCraftBonusCore
local cfg = ChaosCraftBonusConfig

B.random = function(a, b) return math.random(a, b) end
local kinds = {} -- item id -> "gear" | "stack" | false

local function typeNumber(it, method)
	local ok, v = pcall(function() return it[method](it) end)
	return ok and tonumber(v) or 0
end

function B.kind(craft)
	if type(craft) ~= "table" or not tonumber(craft.id) then
		return nil
	end
	local id = tonumber(craft.id)
	local k = kinds[id]
	if k == nil then
		k = false
		local it = ItemType(id)
		local okRune, rune = pcall(function() return it:isRune() end)
		if K.isYieldId(cfg, id) or (cfg.yield.runes and okRune and rune) then
			k = "stack"
		elseif ChaosCrafting and ChaosCrafting.isGear then
			-- ChaosCrafting.isGear reads only the item's id and type: a stand-in does
			local ok, gear = pcall(ChaosCrafting.isGear, {getId = function() return id end})
			local okKind, kind = pcall(function() return ChaosItemMods.kindOfType(it) end)
			if ok and gear and not K.isTool(cfg, okKind and kind or nil, typeNumber(it, "getSlotPosition")) then
				k = "gear"
			end
		end
		kinds[id] = k
	end
	-- equipment: one piece a craft (every stock recipe); more is left to the stock script
	if k == "gear" and (tonumber(craft.count) or 1) ~= 1 then
		return nil
	end
	return k or nil
end

function B.skill(player, category)
	local skill = cfg.skills[category]
	if not skill then
		return 0
	end
	local ok, v = pcall(function() return player:getEffectiveSkillLevel(skill) end)
	return ok and tonumber(v) or 0
end

-- the item level a plain piece of this type gets from its required level (as ChaosCrafting.orbLevel)
function B.typeLevel(id)
	local ok, lv = pcall(function()
		return ChaosItemMods.sourceLevel({monsterLevel = math.max(1, typeNumber(ItemType(id), "getMinReqLevel"))})
	end)
	return ok and tonumber(lv) or 1
end

local function rarityName(r)
	return ChaosCrafting and ChaosCrafting.rarityName and ChaosCrafting.rarityName(r) or ("Rarity " .. r)
end

function B.odds(player, category, craft)
	local kind = B.kind(craft)
	local skill = B.skill(player, category)
	if kind == "gear" then
		local odds = {}
		for _, r in ipairs(K.gearOdds(cfg, craft.level, skill)) do
			odds[#odds + 1] = {rarity = r.rarity, name = rarityName(r.rarity), pct = r.pct}
		end
		return {kind = "gear", level = K.itemLevel(cfg, craft.level, skill, B.typeLevel(craft.id)), odds = odds}
	elseif kind == "stack" then
		return {kind = "stack", odds = K.yieldOdds(cfg, craft.level, skill, craft.count)}
	end
	return nil
end

function B.make(player, category, craft, skill)
	local kind = B.kind(craft)
	skill = tonumber(skill) or B.skill(player, category)
	if kind == "gear" then
		local rarity = K.rollGear(cfg, craft.level, skill, B.random)
		local level = K.itemLevel(cfg, craft.level, skill, B.typeLevel(craft.id))
		local item = ChaosCrafting.createItem(craft.id, rarity, level, B.random)
		if item and rarity > 0 and ChaosGems and ChaosGems.rollDropSockets then
			pcall(ChaosGems.rollDropSockets, item)
		end
		return {kind = "gear", item = item, rarity = item and rarity or 0, level = level}
	elseif kind == "stack" then
		return {kind = "stack", extra = K.rollYield(cfg, craft.level, skill, craft.count, B.random)}
	end
	return nil
end

-- extra pieces: into the backpack, what does not fit to the store inbox (as bestiary.lua's rewards); returns how many
-- went to the inbox
function B.giveExtra(player, id, n)
	if n <= 0 then
		return 0
	end
	local rest = n - Chaos.giveItem(player, id, n)
	if rest <= 0 then
		return 0
	end
	local inbox = player.getInbox and player:getInbox()
	local sent = 0
	while inbox and rest > 0 do
		local k = math.min(rest, cfg.yield.inboxStack)
		inbox:addItem(id, k, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest, sent = rest - k, sent + k
	end
	if rest > 0 then
		player:addItem(id, rest, true) -- no inbox: at the player's feet
	end
	return sent
end

function B.finish(player, craft, made)
	local name = tostring(craft.name or ItemType(craft.id):getName())
	if made.kind == "gear" then
		return K.gearText(name, made.rarity > 0 and rarityName(made.rarity) or nil, made.level)
	end
	local extra = math.max(0, math.floor(tonumber(made.extra) or 0))
	local inbox = B.giveExtra(player, craft.id, extra)
	return K.yieldText(name, (tonumber(craft.count) or 1) + extra, extra, inbox)
end
