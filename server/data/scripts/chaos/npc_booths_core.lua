-- The NPC booths of the hub: the pure part (no engine calls), shared by npc_booths.lua, npc_place.lua, trials.lua,
-- tile_labels.lua and server/tests/npc_booths_test.lua. server/README.md "Hub NPC booths". Lua 5.1 / LuaJIT and 5.3.
--   K.cfg()                          the config (npc_booths_config.lua)
--   K.booths(cfg)                    {{name, x, y, z}, ...}: every stall with a Chaos NPC, in the config's order
--   K.spot(cfg, name, townId)        the tile of that NPC's stall when townId is the hub's town, else nil
--   K.spotForTemple(cfg, name, t)    the same, by the temple position the caller places next to
--   K.retiredHallAt(cfg, pos)        the retired Hall of Services whose rectangle holds pos ({town, at, size}), or nil
ChaosNpcBoothsCore = ChaosNpcBoothsCore or {}
local K = ChaosNpcBoothsCore

function K.cfg()
	if not K.config then
		K.config = dofile("data/scripts/chaos/npc_booths_config.lua")
	end
	return K.config
end

function K.booths(cfg)
	local out = {}
	if not (cfg and cfg.enabled) then
		return out
	end
	for _, b in ipairs(cfg.booths or {}) do
		if type(b.npc) == "string" and b.npc ~= "" then
			out[#out + 1] = {name = b.npc, x = b.x, y = b.y, z = b.z}
		end
	end
	return out
end

function K.spot(cfg, name, townId)
	if not (cfg and cfg.enabled and type(name) == "string") or townId ~= cfg.town then
		return nil
	end
	local want = name:lower()
	for _, b in ipairs(K.booths(cfg)) do
		if b.name:lower() == want then
			return {x = b.x, y = b.y, z = b.z}
		end
	end
	return nil
end

function K.spotForTemple(cfg, name, temple)
	local t = cfg and cfg.temple
	if not (t and temple and t.x == temple.x and t.y == temple.y and t.z == temple.z) then
		return nil
	end
	return K.spot(cfg, name, cfg.town)
end

function K.retiredHallAt(cfg, pos)
	if not (cfg and pos and pos.x and pos.y and pos.z) then
		return nil
	end
	for _, h in ipairs(cfg.retiredHalls or {}) do
		local a, s = h.at, h.size or {0, 0}
		if pos.z == a.z and pos.x >= a.x and pos.y >= a.y and pos.x < a.x + s[1] and pos.y < a.y + s[2] then
			return h
		end
	end
	return nil
end

return K
