-- The Halls of Services: the pure part (no engine calls), shared by npc_booths.lua and server/tests/npc_booths_test.lua.
-- server/README.md "Halls of Services". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--   K.cfg()                          the config (npc_booths_config.lua)
--   K.npcName(booth, townId)         the NPC of a booth in that town, or nil (a free slot)
--   K.hallOf(cfg, townId)            the hall of a town, or nil
--   K.offset(hall, dx, dy, dz)       a world {x, y, z} from offsets of the hall's origin
--   K.rowTiles(row, townId)          {{dx, dy, kind, id?}, ...}: kind npc | partition | light | counter; {} when the
--                                    row has no NPC in that town (nothing is built)
--   K.fixtures(cfg, hall)            the world tiles of every fixture of a hall: {{x, y, z, id, kind}, ...}
--   K.booths(cfg, hall)              {{name, x, y, z, row}, ...}: every NPC booth of a hall with its NPC
--   K.spot(cfg, name, townId)        the world tile of that NPC's booth in that town, or nil
--   K.portal(cfg, hall, key)         the world tile of a system portal (descent, raid) in that hall, or nil
ChaosNpcBoothsCore = ChaosNpcBoothsCore or {}
local K = ChaosNpcBoothsCore

function K.cfg()
	if not K.config then
		K.config = dofile("data/scripts/chaos/npc_booths_config.lua")
	end
	return K.config
end

function K.npcName(booth, townId)
	local n = booth.npc
	if type(n) == "table" then
		n = n[townId]
	end
	if type(n) == "string" and n ~= "" then
		return n
	end
	return nil
end

function K.hallOf(cfg, townId)
	for _, h in ipairs(cfg.halls or {}) do
		if h.town == townId then
			return h
		end
	end
	return nil
end

function K.offset(hall, dx, dy, dz)
	return {x = hall.at.x + dx, y = hall.at.y + dy, z = hall.at.z + (dz or 0)}
end

local function rowHasNpc(row, townId)
	for _, b in ipairs(row.booths or {}) do
		if K.npcName(b, townId) then
			return true
		end
	end
	return false
end

function K.rowTiles(row, townId, items)
	local out = {}
	if not rowHasNpc(row, townId) then
		return out
	end
	items = items or K.cfg().items
	local kind = {}
	for _, b in ipairs(row.booths) do
		kind[b.x] = "npc"
		kind[b.x - 1] = kind[b.x - 1] or "partition"
		kind[b.x + 1] = kind[b.x + 1] or "partition"
	end
	for x = row.from, row.to do
		local k = kind[x] or "light"
		local id = (k == "partition" and items.partition) or (k == "light" and items.light) or nil
		out[#out + 1] = {x, row.npcRow, k, id}
	end
	for x = row.from, row.to do
		out[#out + 1] = {x, row.counterRow, "counter", items.counter[(x - row.from) % #items.counter + 1]}
	end
	return out
end

function K.fixtures(cfg, hall)
	local out = {}
	for _, row in ipairs(cfg.rows or {}) do
		for _, t in ipairs(K.rowTiles(row, hall.town, cfg.items)) do
			if t[3] ~= "npc" then
				local p = K.offset(hall, t[1], t[2])
				out[#out + 1] = {x = p.x, y = p.y, z = p.z, id = t[4], kind = t[3]}
			end
		end
	end
	return out
end

function K.booths(cfg, hall)
	local out = {}
	for _, row in ipairs(cfg.rows or {}) do
		for _, b in ipairs(row.booths or {}) do
			local name = K.npcName(b, hall.town)
			if name then
				local p = K.offset(hall, b.x, row.npcRow)
				out[#out + 1] = {name = name, x = p.x, y = p.y, z = p.z, row = row.key}
			end
		end
	end
	return out
end

function K.spot(cfg, name, townId)
	if not cfg.enabled or not name then
		return nil
	end
	local hall = K.hallOf(cfg, townId)
	if not hall then
		return nil
	end
	local want = name:lower()
	for _, b in ipairs(K.booths(cfg, hall)) do
		if b.name:lower() == want then
			return {x = b.x, y = b.y, z = b.z}
		end
	end
	return nil
end

function K.portal(cfg, hall, key)
	local o = cfg.portals and cfg.portals[key]
	return o and K.offset(hall, o[1], o[2], o[3]) or nil
end

return K
