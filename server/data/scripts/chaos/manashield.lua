-- manashield.lua: the engine glue of the mana shield parity (server/README.md "Magic Shield"). Rules:
-- manashield_core.lua (pure, tested by server/tests/manashield_test.lua), numbers: manashield_config.lua.
--
-- The mana shield itself is the engine's (stock CONDITION_MANASHIELD: Ward of the Mind and Soulward): the mana takes a
-- hit first, the health only the rest. This file adds one onManaChange event on every player. On a hit the mana shield
-- takes it runs the providers (the Chaos systems that scale a monster's hit on a player; each registers itself with
-- ChaosManaShield.provide), so the mana pays the scaled hit. When the mana cannot take it all, it marks the hit and each
-- system's health event leaves the rest as it is (ChaosManaShield.scaled). When the mana takes it all, it runs the
-- providers' side effects (stacks, on-hit effects) that their health events would have run.
-- Order: the login event's name sorts after "Chaos0MonsterDamageLogin" (the late-game boost scales the hit first) and
-- before every other Chaos login event, so the combat log, the arena and the other mana events see the scaled hit.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosManaShield or not ChaosManaShield.decide then
	dofile("data/scripts/chaos/manashield_core.lua")
end

local S = ChaosManaShield

local mana = CreatureEvent("ChaosManaShieldMana")
function mana.onManaChange(creature, attacker, pd, pt, sd, st, origin)
	if not S.cfg.parity or not creature:isPlayer() then
		return pd, pt, sd, st
	end
	local id = creature:getId()
	S.clear(id)
	if not attacker or pt == COMBAT_HEALING or pt == COMBAT_MANADRAIN or attacker:getId() == id
		or not creature:hasCondition(CONDITION_MANASHIELD) then
		return pd, pt, sd, st
	end
	local healSecondary = st == COMBAT_HEALING
	local s = healSecondary and 0 or (sd or 0)
	local total = math.abs(pd or 0) + math.abs(s)
	if total <= 0 then
		return pd, pt, sd, st
	end
	local ctx = {primaryType = pt, secondaryType = st, origin = origin, at = S.now()}
	local new, keys, overflow = S.decide(creature, attacker, total, creature:getMana(), ctx)
	if #keys == 0 then
		return pd, pt, sd, st
	end
	local p2, s2 = S.rescale(pd, s, total, new)
	if overflow then
		S.mark(id, attacker:getId(), ctx.at, keys)
	else
		S.absorbed(creature, attacker, new, ctx, keys)
	end
	return p2, pt, healSecondary and sd or s2, st
end
mana:register()

-- "Chaos1..." sorts after "Chaos0MonsterDamageLogin" and before "ChaosA..." (the engine runs login events by name)
local login = CreatureEvent("Chaos1ManaShieldLogin")
function login.onLogin(player)
	player:registerEvent("ChaosManaShieldMana")
	player:registerEvent("ChaosManaShieldLogout")
	return true
end
login:register()

local logout = CreatureEvent("ChaosManaShieldLogout")
function logout.onLogout(player)
	S.clear(player:getId())
	return true
end
logout:register()

