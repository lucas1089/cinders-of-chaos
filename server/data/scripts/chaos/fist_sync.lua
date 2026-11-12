-- fist_sync.lua: tells an engine with patch 0091 what to roll a player's bare-fist hit with (O505, owner 2026-11-11: "You can fix these 3
-- things of the auto attack"; server/README.md "Flat armour, weapon spells and the Monk's fist (O505)").
--
-- The engine's bare-fist hit is attack 7 (Weapon::useFist). The monster's own flat armour and defence take their part of it in the engine,
-- before any Lua runs, and a Monk's hit was rescaled to its fist attack (monk_combat.lua, Open Hand Creed in archetypes.lua) in an event
-- AFTER that: at attack 7 nearly all of it died in the flat armour (6% of a Monk's damage reached a level 100 monster). Engine patch 0091
-- adds Player:setFistAttack(attack, multiplier): the hit is rolled with that attack and its maximum multiplied by the number. This script
-- keeps the pushed pair right for every player whose rule says so, at every attack the player starts (EventCallback onTargetCombat, which
-- the engine runs when a target is set and before the swings), so the hit that leaves the engine is already the Monk's. The scripts that
-- rescaled the engine's hit (monk_combat.lua, archetypes.lua) then only correct the difference between what was pushed and what they want
-- now (a level up, a changed fist weapon), which is nearly always nothing.
-- Without the engine patch (no Player.setFistAttack: ChaosMonk.engineFist()) this script does nothing and everything is as before.
--
-- ChaosFistSync.pushed[player id] = {attack, multiplier} is what the engine was last told: the scripts read it to know what the hit they
-- are scaling was rolled with. It is dropped at logout (the engine's value is not saved: a new login starts at the stock hit and the first
-- target of the session pushes it again).
-- Who: the Monk line (the fist weapons' attack counts when it is higher: ChaosMonk.fistAttack) and, from archetypes.lua
-- (ChaosFistSync.openHandWanted), a non-Monk with Open Hand Creed or the Knuckles of the Unbound and an empty hand.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosMonk then
	dofile("data/scripts/chaos/monk_chi_core.lua")
end
local M = ChaosMonk

ChaosFistSync = ChaosFistSync or {}
local FS = ChaosFistSync
FS.pushed = FS.pushed or {}

-- an engine that rolls the fist with a script's attack (the method is the capability, never a version)
function FS.capable()
	return M.engineFist()
end

-- (attack, multiplier) the engine should roll this player's bare fists with now; nil when no rule applies (not a Monk line, a weapon in
-- the hands, no Open Hand)
function FS.wanted(player)
	local voc = player:getVocation()
	local vid = voc and voc:getId() or 0
	if M.isMonkLine(vid) then
		local fist = M.fistWeaponAttack and M.fistWeaponAttack(player)
		if not fist then
			return nil
		end
		return M.enginePush(vid, player:getLevel(), fist)
	end
	if FS.openHandWanted then
		return FS.openHandWanted(player)
	end
	return nil
end

-- pushes the pair wanted now when it is not the one the engine has; returns the pair the engine has after (nil: nothing pushed ever)
function FS.sync(player)
	if not FS.capable() then
		return nil
	end
	local pid = player:getId()
	local a, m = FS.wanted(player)
	local have = FS.pushed[pid]
	if a and (not have or math.abs(have[1] - a) > 1e-6 or math.abs(have[2] - m) > 1e-6) then
		player:setFistAttack(a, m)
		FS.pushed[pid] = {a, m}
		have = FS.pushed[pid]
	end
	return have
end

-- at every attack a player starts: the engine rolls the swings after this call
local cb = EventCallback
cb.onTargetCombat = function(creature, target)
	if creature and creature:isPlayer() and FS.capable() then
		local ok, err = pcall(FS.sync, creature)
		if not ok then
			print("[ChaosFistSync] " .. tostring(err))
		end
	end
	return RETURNVALUE_NOERROR
end
cb:register()

local login = CreatureEvent("ChaosFistSyncLogin")
function login.onLogin(player)
	player:registerEvent("ChaosFistSyncLogout")
	return true
end
login:register()

local logout = CreatureEvent("ChaosFistSyncLogout")
function logout.onLogout(player)
	FS.pushed[player:getId()] = nil
	return true
end
logout:register()
