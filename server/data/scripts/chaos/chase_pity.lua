-- chase_pity.lua: the engine side of the chase pity (O753; rules chase_pity_core.lua, numbers chase_pity_config.lua,
-- server/README.md "Chase pity (O753)"). The counters are player storages (config `storage`). The sources call:
--   ChaosChasePity.mult(player, key)          -> the item find multiplier of this event (content_rewards.lua, itemsets.lua)
--   ChaosChasePity.forced(player, key)        -> true when this event must drop (the n-th)
--   ChaosChasePity.topUp(player, key, p)      -> true when a second roll after a missed own roll of p hits (pocketboss.lua,
--                                                pinnacle.lua): the total chance is the core's K.chance
--   ChaosChasePity.record(player, key, hit, forced) -> the count after the event (0 after a drop); a forced drop says so
--   ChaosChasePity.misses(player, key), .view(player) (the Collection log's pity panel, collection_log.lua)
-- Every entry is safe to call when the system is off or a key is unknown (it then changes nothing).
-- Staff: /chasepity Name (the counts), /chasepity Name, reset.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosChasePityCore then
	dofile("data/scripts/chaos/chase_pity_core.lua")
end

ChaosChasePity = ChaosChasePity or {}
local CP = ChaosChasePity
local K = ChaosChasePityCore

CP.config = CP.config or dofile("data/scripts/chaos/chase_pity_config.lua")

local function cfg()
	return CP.config
end

function CP.enabled()
	return cfg().enabled == true
end

local function srcOf(key)
	return CP.enabled() and K.source(cfg(), key) or nil
end

local function keyOf(src)
	return cfg().storage.base + (src.slot or 0)
end

function CP.misses(player, key)
	local src = K.source(cfg(), key)
	if not (player and src) then
		return 0
	end
	local v = tonumber(player:getStorageValue(keyOf(src))) or 0
	return v > 0 and v or 0
end

function CP.mult(player, key)
	local src = srcOf(key)
	if not (player and src) then
		return 1
	end
	return K.mult(src, CP.misses(player, key))
end

function CP.forced(player, key)
	local src = srcOf(key)
	if not (player and src) then
		return false
	end
	return K.forced(src, CP.misses(player, key))
end

function CP.topUp(player, key, p, rand)
	local src = srcOf(key)
	if not (player and src) then
		return false
	end
	local q = K.topUp(p, src, CP.misses(player, key))
	if q <= 0 then
		return false
	end
	rand = rand or math.random
	return q >= 1 or rand(1, 1000000) <= math.floor(q * 1000000)
end

function CP.record(player, key, hit, forced)
	local src = srcOf(key)
	if not (player and src) then
		return 0
	end
	local nextK = K.nextMisses(src, CP.misses(player, key), hit)
	player:setStorageValue(keyOf(src), nextK)
	if hit and forced and cfg().message then
		pcall(function()
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, cfg().message, Chaos.t(player, src.label)))
		end)
	end
	return nextK
end

-- the pity panel: the sources of the config, then the pinnacle bosses' own count (pinnacle_config.lua unique.pity)
function CP.view(player)
	local rows = K.view(cfg(), function(src)
		return CP.misses(player, src.key)
	end)
	local P = Chaos.pinnacleConfig
	if not P then
		local ok, loaded = pcall(dofile, "data/scripts/chaos/pinnacle_config.lua")
		P = ok and loaded or nil
	end
	if P and P.enabled and P.unique and P.storage then
		for i, b in ipairs(P.bosses or {}) do
			local v = tonumber(player:getStorageValue(P.storage.base + P.storage.pity + i - 1)) or 0
			rows[#rows + 1] = {k = "pinnacle_" .. tostring(b.key), l = "Pinnacle: %s unique", a = b.short or b.name,
				d = math.max(0, v), n = P.unique.pity or 8}
		end
	end
	return rows
end

-- ---------------------------------------------------------------- staff
local talk = TalkAction("/chasepity")
function talk.onSay(player, words, param)
	if player:getGroup():getId() < (cfg().staffGroup or 4) then
		return true
	end
	local name, what = tostring(param or ""):match("^%s*([^,]+)%s*,?%s*(.-)%s*$")
	local target = name and Player(name)
	if not target then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/chasepity Name [, reset]")
		return false
	end
	if what == "reset" then
		for _, s in ipairs(cfg().sources) do
			target:setStorageValue(keyOf(s), 0)
		end
	end
	local parts = {}
	for _, r in ipairs(CP.view(target)) do
		parts[#parts + 1] = string.format("%s %d/%d", r.k, r.d, r.n)
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, target:getName() .. ": " .. table.concat(parts, ", "))
	return false
end
talk:separator(" ")
talk:register()
