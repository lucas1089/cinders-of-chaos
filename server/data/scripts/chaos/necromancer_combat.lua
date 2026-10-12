-- necromancer_combat.lua: the combat glue of the Necromancer line (docs/CLASSES.md "Necromancer"; numbers in
-- necro_config.lua, rules in necro_core.lua). The minions live in necro_minions.lua.
--
--   * Withering Curse (spell): the spell puts a timer condition on the monster (sub id curse, or curseLich for the
--     Lich's stronger curse) and registers ChaosNecroCurse on it; while the condition lasts every damage the monster
--     takes is raised by the curse's amplify (necro_core.cursedDamage). Players are never amplified: on a player the
--     curse only rots.
--   * Bone Offering (spell): a timer condition on the Bone Lord (sub id boneShield); while it lasts the Bone Lord
--     takes less damage (ChaosNecroGuard, registered at login).
--   * The store unlock (class_unlocks.lua, another module): ChaosNecro.mayBecome(player, vocId) (necro_lib.lua) is
--     the gate the ascension and the vocation change ask before making a character a Necromancer, Lich or Bone Lord.

if not ChaosNecro then
	dofile("data/scripts/chaos/necro_lib.lua")
end
local L = ChaosNecro
local N = ChaosNecroCore
local function cfg()
	return ChaosNecroConfig
end

local function amplifyOf(creature)
	local s = cfg().subId
	return N.activeAmplify(cfg(), L.hasCond(creature, s.curse), L.hasCond(creature, s.curseLich))
end

local curse = CreatureEvent("ChaosNecroCurse")
function curse.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING or creature:isPlayer() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local ok, amp = pcall(amplifyOf, creature)
	if not ok then
		print("[ChaosNecroCurse] " .. tostring(amp))
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if amp > 0 then
		primaryDamage = N.cursedDamage(primaryDamage, amp, false)
		secondaryDamage = N.cursedDamage(secondaryDamage, amp, false)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
curse:register()

local guard = CreatureEvent("ChaosNecroGuard")
function guard.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING or not creature:isPlayer() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if L.hasCond(creature, cfg().subId.boneShield) then
		primaryDamage = N.shielded(cfg(), primaryDamage, true)
		secondaryDamage = N.shielded(cfg(), secondaryDamage, true)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
guard:register()

local login = CreatureEvent("ChaosNecroLogin")
function login.onLogin(player)
	-- every player (a vocation change can make a character a Bone Lord without a relog); cheap when no shield is up
	player:registerEvent("ChaosNecroGuard")
	return true
end
login:register()
