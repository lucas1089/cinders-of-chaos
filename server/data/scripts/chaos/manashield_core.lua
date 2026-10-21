-- manashield_core.lua: the pure rules of the mana shield (ChaosManaShield; server/README.md "Magic Shield"). No engine
-- calls; manashield.lua is the glue. Numbers: manashield_config.lua. Test: server/tests/manashield_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- * The split (the engine's, written out for the tests and the docs): a hit goes to the mana first, at most the mana
--   there is; only the rest goes to the health (then the energy shield, engine patch 0015, before the health).
-- * Parity: the engine hands the whole hit to the onManaChange events first and only what the mana could not take to the
--   onHealthChange events. The Chaos systems that scale a monster's hit on a player do it in onHealthChange, so the
--   mana part skipped them. Each such system registers a provider here: provider.hit(player, attacker, amount, ctx)
--   returns the amount after its scaling (nil: it does not apply to this hit), provider.absorbed(player, attacker,
--   amount, ctx) (optional) runs its side effects (debuff stacks, on-hit effects) when the mana took the whole hit and
--   no health event follows. When the mana cannot take the scaled hit, the hit is marked: the system's health event
--   of the same hit asks S.scaled(...) and leaves the rest as it is (it was scaled here already).

ChaosManaShieldConfig = ChaosManaShieldConfig or dofile("data/scripts/chaos/manashield_config.lua")

ChaosManaShield = ChaosManaShield or {}
local S = ChaosManaShield
S.cfg = ChaosManaShieldConfig
S.providers = S.providers or {} -- key -> {hit = fn, absorbed = fn or nil}; a /reload replaces a key's entry
S.marks = S.marks or {}         -- player id -> {attacker = id, at = ms, keys = {key = true}}
local floor, abs, min, max = math.floor, math.abs, math.min, math.max

function S.now()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- the classic split of a hit: (mana part, health part)
function S.split(hit, mana)
	hit = max(0, floor(tonumber(hit) or 0))
	mana = max(0, floor(tonumber(mana) or 0))
	local m = min(hit, mana)
	return m, hit - m
end

-- may this vocation id learn and cast Ward of the Mind
function S.allowed(vocationId, cfg)
	for _, v in ipairs((cfg or S.cfg).vocations) do
		if v == vocationId then
			return true
		end
	end
	return false
end

function S.provide(key, provider)
	if type(key) == "string" and type(provider) == "table" and type(provider.hit) == "function" then
		S.providers[key] = provider
	end
end

local function sortedKeys()
	local keys = {}
	for k in pairs(S.providers) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return keys
end

-- run the providers (in key order) on a hit of `amount` (positive): the new amount and the keys that applied.
-- A provider that errors is skipped (S.lastError keeps the message).
function S.apply(player, attacker, amount, ctx)
	local applied = {}
	for _, key in ipairs(sortedKeys()) do
		local ok, v = pcall(S.providers[key].hit, player, attacker, amount, ctx)
		if not ok then
			S.lastError = key .. ": " .. tostring(v)
		elseif tonumber(v) then
			amount = max(0, floor(tonumber(v)))
			applied[#applied + 1] = key
		end
	end
	return amount, applied
end

-- the side effects of the providers that applied, when the mana took the whole hit
function S.absorbed(player, attacker, amount, ctx, keys)
	for _, key in ipairs(keys) do
		local p = S.providers[key]
		if p and p.absorbed then
			local ok, err = pcall(p.absorbed, player, attacker, amount, ctx)
			if not ok then
				S.lastError = key .. ": " .. tostring(err)
			end
		end
	end
end

-- a signed (primary, secondary) pair of a hit of `total` scaled to `new` (the secondary keeps its share; a healing
-- secondary is passed as 0 and stays out)
function S.rescale(pd, sd, total, new)
	if total <= 0 or new == total then
		return pd, sd
	end
	local sp = (pd or 0) < 0 and -1 or 1
	local ss = (sd or 0) < 0 and -1 or ((sd or 0) == 0 and sp or 1)
	if new <= 0 then
		return 0, 0
	end
	local s = abs(sd or 0)
	if s == 0 then
		return sp * new, sd
	end
	local p = floor(abs(pd or 0) * new / total + 0.5)
	return sp * p, ss * (new - p)
end

-- the decision of one mana shield hit: (new amount, keys that applied, overflow). overflow: the mana cannot take the
-- whole hit, the health events follow with the rest.
function S.decide(player, attacker, amount, mana, ctx)
	local new, keys = S.apply(player, attacker, amount, ctx)
	return new, keys, new > max(0, mana or 0)
end

function S.mark(playerId, attackerId, at, keys)
	local set = {}
	for _, k in ipairs(keys) do
		set[k] = true
	end
	S.marks[playerId] = {attacker = attackerId, at = at, keys = set}
end

function S.clear(playerId)
	S.marks[playerId] = nil
end

-- did the mana event of this hit already scale it for `key`? Consumes the key (each system asks once per hit).
function S.consume(playerId, key, attackerId, at)
	local m = S.marks[playerId]
	if not m then
		return false
	end
	if m.attacker ~= attackerId or abs((at or 0) - (m.at or 0)) > (S.cfg.markMs or 10) then
		S.marks[playerId] = nil -- stale: an older hit whose health events never came
		return false
	end
	if not m.keys[key] then
		return false
	end
	m.keys[key] = nil
	if next(m.keys) == nil then
		S.marks[playerId] = nil
	end
	return true
end

-- the engine form for the health events: creature and attacker objects
function S.scaled(creature, attacker, key)
	if next(S.marks) == nil or not creature or not attacker or not S.marks[creature:getId()] then
		return false -- no mark at all: the usual case, no engine call
	end
	return S.consume(creature:getId(), key, attacker:getId(), S.now())
end

return S
