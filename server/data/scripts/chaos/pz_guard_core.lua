-- PZ guard (server/README.md "PZ guard"): scripted damage never lands on a player standing in a protection zone.
-- The engine checks the PZ for its own combat (a monster never targets a player in PZ, an area attack skips PZ
-- tiles), but doTargetCombat / doTargetCombatHealth from a script hit whoever they are given. Chaos systems call them
-- from monster mechanics (boss telegraphs, reflects, death explosions, pulses), so this guard wraps both globals once:
-- damage (a negative amount of any type but healing) to a player on a PZ tile is dropped, like the engine drops it.
-- Allowed through: healing and mana gain (positive amounts), a creature hurting itself (a self cost), a caster player
-- with PlayerFlag_IgnoreProtectionZone (staff).
-- chaos_constants.lua loads this file and calls ChaosPzGuard.install() before any system captures the globals.
-- tests/pz_guard_test.lua. Lua 5.1 / LuaJIT and Lua 5.3.

ChaosPzGuard = ChaosPzGuard or {}
local Z = ChaosPzGuard

local function try(fn, ...)
	local ok, res = pcall(fn, ...)
	if ok then
		return res
	end
	return nil
end

-- a creature from an id, a userdata or nil
local function creatureOf(v)
	if v == nil or v == 0 then
		return nil
	end
	if type(v) == "number" then
		return Creature and try(Creature, v) or nil
	end
	return v
end
Z.creatureOf = creatureOf

local function isPlayer(c)
	return c ~= nil and try(function() return c:isPlayer() end) == true
end

-- the tile under a position has the PZ flag
function Z.posInPz(pos)
	if not pos or not Tile or TILESTATE_PROTECTIONZONE == nil then
		return false
	end
	local tile = try(Tile, pos)
	return tile ~= nil and try(function() return tile:hasFlag(TILESTATE_PROTECTIONZONE) end) == true
end

-- the creature stands in a protection zone
function Z.inPz(creature)
	local c = creatureOf(creature)
	if not c then
		return false
	end
	return Z.posInPz(try(function() return c:getPosition() end))
end

local function sameCreature(a, b)
	if a == nil or b == nil then
		return false
	end
	if a == b then
		return true
	end
	local ia = try(function() return a:getId() end)
	return ia ~= nil and ia == try(function() return b:getId() end)
end

-- the hit is damage: a negative amount, not healing
function Z.isDamage(ctype, min, max)
	if COMBAT_HEALING ~= nil and ctype == COMBAT_HEALING then
		return false
	end
	return (tonumber(min) or 0) < 0 or (tonumber(max) or 0) < 0
end

-- true when a scripted hit of caster on target must be dropped
function Z.blocks(caster, target, ctype, min, max)
	if not Z.isDamage(ctype, min, max) then
		return false
	end
	local t = creatureOf(target)
	if not isPlayer(t) or not Z.inPz(t) then
		return false
	end
	local c = creatureOf(caster)
	if sameCreature(c, t) then
		return false
	end
	if isPlayer(c) and PlayerFlag_IgnoreProtectionZone ~= nil
		and try(function() return c:hasFlag(PlayerFlag_IgnoreProtectionZone) end) == true then
		return false
	end
	return true
end

-- a doTargetCombat-shaped function that drops PZ hits
function Z.wrap(raw)
	return function(caster, target, ctype, min, max, ...)
		if Z.blocks(caster, target, ctype, min, max) then
			Z.dropped = (Z.dropped or 0) + 1
			return false
		end
		return raw(caster, target, ctype, min, max, ...)
	end
end

-- wraps the globals; a second call leaves its own wrapper alone (a guard over another wrapper is harmless)
Z.raw = Z.raw or {}
Z.NAMES = {"doTargetCombat", "doTargetCombatHealth"}
function Z.install()
	for _, name in ipairs(Z.NAMES) do
		local current = rawget(_G, name)
		if current ~= nil and current ~= Z[name] then
			Z.raw[name] = current -- the engine's function (first load), another wrapper or a test's mock
			Z[name] = Z.wrap(current)
			rawset(_G, name, Z[name])
		end
	end
	return Z
end
