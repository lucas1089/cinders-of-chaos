-- chaos_unique_equip.lua: who may wear a unique copy whose base item has other equip rules (server/README.md "Unique
-- equip rules"). A unique is a copy of a stock base item (chaos_unique_items.lua ChaosMakeUnique), and the engine's equip
-- check (movements.xml: level and vocations) belongs to the base item id. A unique with an `equip` rule in its spec
-- (data/items/chaos_items.xml equipLevel / equipLines, generated into chaos_unique_specs.lua) is worn by its own rule;
-- a stock copy of the same id keeps the base server's rule.
--
-- tools/install_unique_equip.py rewrites the movements.xml Equip entry of each such base id: the engine checks the
-- looser of the two rules (the lower level, both vocation lists), and the entry's script (movements/scripts/
-- chaos_unique_equip.lua, written by the same tool with the stock rules it took out) calls ChaosUniqueEquip.onEquip,
-- which then holds each copy to its own rule. Pure apart from onEquip; tested by tests/unique_equip_test.lua.

ChaosUniqueEquip = ChaosUniqueEquip or {}
local E = ChaosUniqueEquip

-- does a rule ({level = n, vocations = {names} or nil for everyone}; nil = no rule) let this character wear it?
function E.allows(rule, level, vocationName)
	if not rule then
		return true
	end
	if (level or 0) < (rule.level or 0) then
		return false
	end
	if rule.vocations then
		for _, name in ipairs(rule.vocations) do
			if name == vocationName then
				return true
			end
		end
		return false
	end
	return true
end

-- the rule a copy is held to: the unique's own one (its spec has `equip` and the copy carries chaos_unique), else the
-- stock rule the install tool recorded for the base id (stock[id]; nil = none)
function E.ruleOf(id, isUnique, specs, stock)
	local spec = isUnique and specs and specs[id]
	if spec and spec.equip then
		return spec.equip
	end
	return stock and stock[id]
end

local function isUniqueCopy(item)
	if not item.getCustomAttribute then
		return false
	end
	local ok, v = pcall(item.getCustomAttribute, item, "chaos_unique")
	return ok and v ~= nil and v ~= false and v ~= 0
end

-- the movement script's onEquip (movements/scripts/chaos_unique_equip.lua): the engine has already checked the looser
-- rule. Only the check pass decides (the engine asks with isCheck before it moves an item into a slot); the real
-- equip, a login and an unequip pass always.
function E.onEquip(player, item, slot, isCheck, stock)
	if not isCheck or not player or not item then
		return true
	end
	if PlayerFlag_IgnoreWeaponCheck and player.hasFlag and player:hasFlag(PlayerFlag_IgnoreWeaponCheck) then
		return true
	end
	if not ChaosUniqueSpecs then
		pcall(dofile, "data/lib/chaos_unique_specs.lua")
	end
	local rule = E.ruleOf(item:getId(), isUniqueCopy(item), ChaosUniqueSpecs, stock)
	local vocation = player:getVocation()
	return E.allows(rule, player:getLevel(), vocation and vocation:getName())
end

return E
