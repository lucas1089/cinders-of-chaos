-- Vigils, the spells' side (ChaosVigilSpell): the four toggle spells (Vigil of Wrath, Iron, Haste, Clarity;
-- spells_chaos.xml 179, 255, 161, 162). A cast switches the vigil on or off in the player storage
-- (vigils_config.lua storage, a bit per vigil); data/scripts/chaos/vigils.lua reserves the mana (or health) and
-- spreads the effects on its next think (at most a second later; at once when it shares this Lua state).
-- Rules and numbers: data/scripts/chaos/vigils_core.lua, vigils_config.lua; design: docs/BUILDS.md "Vigils".

if ChaosVigilSpell then
	return
end
ChaosVigilSpell = {}
local W = ChaosVigilSpell

if not ChaosVigilsCore then
	dofile("data/scripts/chaos/vigils_core.lua")
end
if not ChaosArchetypesCore then
	pcall(dofile, "data/scripts/chaos/archetypes_core.lua")
end
local V = ChaosVigilsCore

-- the player's mods: keystones from the archetype flag storage, the worn uniques
function W.mods(player)
	local A, AC = ChaosArchetypesCore, ChaosArchetypesConfig
	if not A or not AC then
		return V.modsOf({}, {})
	end
	return V.modsOf(A.flagsOfMask(player:getStorageValue(AC.storage)), A.wornUniques(player))
end

function W.toggle(creature, key)
	local player = creature and creature:getPlayer()
	if not player then
		return false
	end
	local storage = ChaosVigilsConfig.storage
	local mask = math.max(0, tonumber(player:getStorageValue(storage)) or 0)
	local mods = W.mods(player)
	local was = V.has(mask, key)
	local new, total, err = V.toggle(mask, key, mods)
	if err then
		return ChaosSpell.cancel(player, string.format("%s would reserve more than all of your %s (%d%% reserved now).",
			V.byKey[key].def.name, mods.tithe and "health" or "mana", math.floor(total * 100 + 0.5)))
	end
	player:setStorageValue(storage, new)
	player:sendTextMessage(MESSAGE_INFO_DESCR or MESSAGE_STATUS_SMALL or 1, V.toggleText(key, not was, total, mods))
	player:getPosition():sendMagicEffect(was and (CONST_ME_POFF or 3) or (CONST_ME_MAGIC_GREEN or CONST_ME_POFF or 3))
	if ChaosVigils and ChaosVigils.refresh then -- the scripts' side in the same Lua state: at once
		pcall(ChaosVigils.refresh, player)
	end
	return true
end

return W
