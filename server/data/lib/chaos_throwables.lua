-- Stackable throwing weapons are out of the game (owner 2026-10-20; server/README.md "Throwing weapons"): the small
-- stone, spear, throwing star and knife, hunting spear, viper star, enchanted spear, assassin star and royal spear. They
-- leave monster loot, NPC shops and NPC rewards (server/tools/patch_base_throwables.py reads the list below, so does
-- the hunt supply generator), no class kit gives one, and the loot layer takes a stray one out of a corpse. Characters
-- keep what they already hold. The shuriken spells need no star: they use Chaos.classes.shuriken.defaultAttack.
-- Also the one place of the rarity rule for stackables: a stackable item never carries a rarity (mayCarryRarity).
-- Pure (no engine calls). Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosThrowables = ChaosThrowables or {}
local T = ChaosThrowables

-- [server item id] = name; the patch tool and the tests read this block, keep one entry per line
T.items = {
	[1294] = "small stone",
	[2389] = "spear",
	[2399] = "throwing star",
	[2410] = "throwing knife",
	[3965] = "hunting spear",
	[7366] = "viper star",
	[7367] = "enchanted spear",
	[7368] = "assassin star",
	[7378] = "royal spear",
}

function T.isThrowable(id)
	return T.items[tonumber(id) or 0] ~= nil
end

-- the ids, sorted
function T.list()
	local out = {}
	for id in pairs(T.items) do
		out[#out + 1] = id
	end
	table.sort(out)
	return out
end

-- false for a stackable item type (a stack has no rarity: the rarity belongs to one piece of gear); nil or an
-- unreadable type answers true, so the gear gate of the caller decides
function T.mayCarryRarity(itemType)
	if not itemType or not itemType.isStackable then
		return true
	end
	local ok, stack = pcall(itemType.isStackable, itemType)
	return not (ok and stack)
end

return T
