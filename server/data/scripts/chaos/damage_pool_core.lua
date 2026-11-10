-- damage_pool_core.lua: the one additive "increased damage" pool (O473; numbers: damage_pool_config.lua; the engine side:
-- passivetree_effects.lua ChaosPassiveDealt; tests: server/tests/damage_pool_test.lua). Pure: no engine call besides what a
-- provider does. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- One registry. Each source of damage that is "increased damage" registers a provider with ChaosDamagePool.register(name, fn):
--   fn(hit, combatType, which) -> raw percent (a number, 0 or more)
-- `hit` is the table the event builds once per hit {attacker, creature, origin, critical, primaryType, secondaryType, cache = {}}
-- (a provider may keep a once-per-hit result in hit.cache), `which` is "primary" or "secondary" (the part of the hit the type
-- belongs to). The pool clamps every entry to its own cap (damage_pool_config.lua sources), then the entries of one group to the
-- group cap, adds the passive tree's own raw sum, and takes the tree's soft cap once: factor = 1 + soft(sum) / 100.
-- A character with no entry has the factor exactly 1.

ChaosDamagePool = ChaosDamagePool or {}
local P = ChaosDamagePool
P.providers = P.providers or {}
P.names = P.names or {}

if not ChaosDamagePoolConfig then
	ChaosDamagePoolConfig = dofile("data/scripts/chaos/damage_pool_config.lua")
end
P.config = ChaosDamagePoolConfig

local function cfg()
	return P.config
end

-- Soft cap: full value up to `cap`, then cap + H ln(1 + (raw - cap) / H). The same curve as passivetree_effects.lua ChaosSoftCap
-- (the tests compare the two); the cap and H are the tree's (ChaosPassiveEffectsConfig) when it is loaded.
function P.softCap()
	local e = rawget(_G, "ChaosPassiveEffectsConfig")
	if e and e.maxDamagePercent and e.softCap and e.softCap.damagePercentH then
		return e.maxDamagePercent, e.softCap.damagePercentH
	end
	local c = cfg().softCap
	return c.cap, c.H
end

function P.soft(raw)
	raw = tonumber(raw) or 0
	local cap, H = P.softCap()
	if raw <= cap then
		return raw
	end
	return cap + H * math.log(1 + (raw - cap) / H)
end

-- the multiplier of a sum of raw percent
function P.factor(sum)
	return 1 + P.soft(math.max(0, tonumber(sum) or 0)) / 100
end

-- register (or replace) the provider of a source. `static` (optional) is the same source without a hit: fn(player, combatType)
-- -> raw percent that holds whatever the target is (Paragon, gems, the card set of that element). The character sheet and
-- the passive tree totals use it; a source that depends on a hit (a unique passive's condition, a charm's family, the
-- sword's stacks, a mastery's spell) has none and shows only in the help text.
function P.register(name, fn, static)
	if not P.providers[name] then
		P.names[#P.names + 1] = name
	end
	P.providers[name] = fn
	P.statics = P.statics or {}
	P.statics[name] = static
end

-- the cap of one source for a damage type (nil: none). Physical gems have their own, lower cap.
function P.cap(name, combatType)
	local s = cfg().sources[name]
	if not s then
		return nil
	end
	if name == "gems" and combatType ~= nil and combatType == rawget(_G, "COMBAT_PHYSICALDAMAGE") and s.capPhysical then
		return s.capPhysical
	end
	return s.cap
end

local function skipsType(combatType)
	return combatType == rawget(_G, "COMBAT_HEALING") or combatType == rawget(_G, "COMBAT_NONE") or combatType == nil
end

-- Clamp the raw numbers of the sources. raws = {name = raw}; returns the list of {name, raw, cap, label} in the config's order
-- (a source with nothing is left out) and the sum of what counts, group caps included. `treeRaw` is the passive tree's sum.
function P.combine(raws, treeRaw, combatType)
	local c = cfg()
	local list, sum = {}, 0
	local used = {}
	local function add(name, raw)
		raw = math.max(0, tonumber(raw) or 0)
		local s = c.sources[name] or {}
		local cap = P.cap(name, combatType)
		local capped = false
		if cap and raw > cap then
			raw, capped = cap, true
		end
		if s.group then
			local g = c.groups[s.group]
			local room = math.max(0, g.cap - (used[s.group] or 0))
			if raw > room then
				raw, capped = room, true
			end
			used[s.group] = (used[s.group] or 0) + raw
			cap = g.cap
		end
		if raw > 0 or name == "tree" then
			list[#list + 1] = {name = name, raw = raw, cap = cap, capped = capped, label = s.label or name}
			sum = sum + raw
		end
	end
	for _, name in ipairs(c.order) do
		if name == "tree" then
			add(name, treeRaw)
		elseif raws and raws[name] then
			add(name, raws[name])
		end
	end
	return list, sum
end

-- Ask every registered provider for one part of a hit. Returns the raw table. A provider that fails counts 0 (one line in the log).
function P.raws(hit, combatType, which)
	local out = {}
	if skipsType(combatType) then
		return out
	end
	for _, name in ipairs(P.names) do
		local ok, v = pcall(P.providers[name], hit, combatType, which)
		if ok then
			if type(v) == "number" and v > 0 then
				out[name] = v
			end
		elseif not P.warned then
			P.warned = true
			print("[ChaosDamagePool] " .. tostring(name) .. ": " .. tostring(v))
		end
	end
	return out
end

-- the raws the sources give a player in general (no target): {name = raw}
function P.staticRaws(player, combatType)
	local out = {}
	if skipsType(combatType) then
		return out
	end
	for _, name in ipairs(P.names) do
		local fn = P.statics and P.statics[name]
		if fn then
			local ok, v = pcall(fn, player, combatType)
			if ok and type(v) == "number" and v > 0 then
				out[name] = v
			end
		end
	end
	return out
end

-- the pool of a player for a damage type without a target (the character sheet, the tree totals): list, sum, soft, factor
function P.sheet(player, combatType, treeRaw)
	return P.lines(P.staticRaws(player, combatType), treeRaw, combatType)
end

-- the whole pool of one part of a hit: returns factor, sum, list
function P.part(hit, combatType, which, treeRaw)
	local list, sum = P.combine(P.raws(hit, combatType, which), treeRaw, combatType)
	return P.factor(sum), sum, list
end

-- the lines of the character sheet / help line for a set of raws: {{label, raw, cap}, ...}, then the sum and the soft cap result
function P.lines(raws, treeRaw, combatType)
	local list, sum = P.combine(raws, treeRaw, combatType)
	return list, sum, P.soft(sum), P.factor(sum)
end

return P
