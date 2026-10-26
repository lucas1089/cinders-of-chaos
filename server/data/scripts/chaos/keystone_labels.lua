-- Keystone labels of the combat log (config: keystone_labels_config.lua; tests/keystone_labels_test.lua; server/README.md
-- "DPS meter and combat log").
--
-- The DPS meter names what a hit is attributed to. Without this file every keystone proc is "Keystones" and a keystone
-- that only changes a hit (a factor, a block) shows nowhere. The scripts that apply a keystone call two functions, by
-- the keystone's flag (the key of passivetree_data.lua customStats, "ksDeadeye", "arCascade" ...):
--   ChaosKeystoneLabels.run(flag, fn, ...)      runs fn(...) with the damage and healing dealt inside it (doTargetCombat /
--                                               doAreaCombat) labelled "Keystone: <name>"; returns fn's results
--   ChaosKeystoneLabels.note(player, flag, amount)   the keystone changed a hit by `amount` (kind k), or healed `amount`
--                                               itself (kind p, healing tab: Chaos.heal runs no health event)
-- Both do nothing special without the combat log (the combat log registers itself here), for a flag that has no label
-- and for a character that is not a player, so the keystone scripts never depend on the meter. Never errors.
-- Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosKeystoneLabels = ChaosKeystoneLabels or {}
local L = ChaosKeystoneLabels

L.cfg = dofile("data/scripts/chaos/keystone_labels_config.lua")
L.defs = {} -- flag -> {flag, name (with the prefix), kind, tab, observe, why}
for flag, d in pairs(L.cfg.flags) do
	L.defs[flag] = {flag = flag, name = (L.cfg.prefix or "") .. d.name, kind = d.kind, tab = d.tab,
		observe = d.observe ~= false, why = d.why}
end

function L.def(flag)
	return L.defs[flag]
end

-- the sink: the combat log sets L.sink = {run = function(def, fn, ...), note = function(player, def, amount)}
L.sink = L.sink or nil

function L.run(flag, fn, ...)
	local def = L.defs[flag]
	local sink = L.sink
	if not def or not sink then
		return fn(...)
	end
	return sink.run(def, fn, ...)
end

-- true when something was recorded
function L.note(player, flag, amount)
	local def = L.defs[flag]
	local sink = L.sink
	if not def or not sink or not player then
		return false
	end
	local ok, res = pcall(sink.note, player, def, tonumber(amount) or 0)
	return ok and res == true
end
