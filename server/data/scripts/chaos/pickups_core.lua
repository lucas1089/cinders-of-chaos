-- pickups_core.lua: the pure rules of the ground pickups (no engine calls; tests/pickups_test.lua). The engine glue is
-- pickups.lua, the numbers pickups_config.lua; overview server/README.md "Ground pickups and globes".
-- A pickup is an entry of a registry that lives in memory: where it lies, who it belongs to, how long it lasts and what
-- happens when it is taken. Taking removes the entry first, so a pickup is taken once; whatever is not in the registry
-- (left over from a crash, a reload) grants nothing.
--
--   K.new()                                   an empty registry
--   K.add(reg, spec, now)                     spec {kind, itemKey, x, y, z, ownerId, ttlMs, ownerWindowMs, onTake, data}
--                                             -> the entry {uid, ... bornMs, untilMs, pulseMs}
--   K.at(reg, x, y, z)                        the entries on a tile
--   K.canTake(entry, takerId, sameParty, now) -> true | false, why ("expired" | "owner" | "party")
--   K.take(reg, uid)                          removes and returns the entry (nil the second time)
--   K.restore(reg, entry)                     puts a refused entry back (its onTake said no)
--   K.expired(reg, now)                       removes and returns the entries whose time is up
--   K.pulses(reg, now, pulseMs)               the entries due for a glow (and notes the time)
--   K.countOf(reg, ownerId, kind)             how many live entries an owner has of a kind
-- The take rule: the owner at any time; the owner's party members once ownerWindowMs has passed (0: at once); nobody
-- else, ever. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosPickupsCore = ChaosPickupsCore or {}
local K = ChaosPickupsCore

function K.new()
	return {byUid = {}, nextUid = 1}
end

local function key(x, y, z)
	return x .. ":" .. y .. ":" .. z
end
K.tileKey = key

function K.add(reg, spec, now)
	local uid = reg.nextUid
	reg.nextUid = uid + 1
	local e = {
		uid = uid, kind = spec.kind, itemKey = spec.itemKey, x = spec.x, y = spec.y, z = spec.z,
		ownerId = spec.ownerId, bornMs = now, untilMs = now + math.max(1, spec.ttlMs or 15000),
		ownerWindowMs = math.max(0, spec.ownerWindowMs or 0), onTake = spec.onTake, data = spec.data,
		lastPulseMs = now
	}
	reg.byUid[uid] = e
	return e
end

function K.restore(reg, entry)
	reg.byUid[entry.uid] = entry
end

local function sorted(list)
	table.sort(list, function(a, b) return a.uid < b.uid end)
	return list
end

function K.at(reg, x, y, z)
	local out = {}
	for _, e in pairs(reg.byUid) do
		if e.x == x and e.y == y and e.z == z then
			out[#out + 1] = e
		end
	end
	return sorted(out)
end

function K.countOf(reg, ownerId, kind)
	local n = 0
	for _, e in pairs(reg.byUid) do
		if e.ownerId == ownerId and (kind == nil or e.kind == kind) then
			n = n + 1
		end
	end
	return n
end

function K.canTake(entry, takerId, sameParty, now)
	if now >= entry.untilMs then
		return false, "expired"
	end
	if takerId == entry.ownerId then
		return true
	end
	if not sameParty then
		return false, "owner"
	end
	if now - entry.bornMs < entry.ownerWindowMs then
		return false, "party"
	end
	return true
end

function K.take(reg, uid)
	local e = reg.byUid[uid]
	reg.byUid[uid] = nil
	return e
end

function K.expired(reg, now)
	local out = {}
	for uid, e in pairs(reg.byUid) do
		if now >= e.untilMs then
			out[#out + 1] = e
		end
	end
	for _, e in ipairs(out) do
		reg.byUid[e.uid] = nil
	end
	return sorted(out)
end

function K.pulses(reg, now, pulseMs)
	local out = {}
	for _, e in pairs(reg.byUid) do
		if now < e.untilMs and now - e.lastPulseMs >= pulseMs then
			e.lastPulseMs = now
			out[#out + 1] = e
		end
	end
	return sorted(out)
end

return K
