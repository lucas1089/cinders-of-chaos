-- Dynamic respawn, pure logic (no engine calls; tests/respawn_test.lua). respawn.lua feeds it the hunters online
-- and hands the result to the engine (Game.setSpawnIntervalPercent, engine patch 0022). Numbers: respawn_config.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosRespawn = ChaosRespawn or {}
local R = ChaosRespawn

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

-- the respawn interval in percent of the spawntime for n hunters close together
function R.percentFor(n, cfg)
	local global = cfg.globalPercent or 100
	local p = 100
	if n >= (cfg.minHunters or 2) then
		p = math.max(cfg.minPercent or 50, 100 - (cfg.perExtraHunter or 15) * (n - 1))
	end
	return clamp(math.floor(p * global / 100 + 0.5), 10, 1000)
end

-- hunters: list of {x, y, z, ip}. Returns a list (same order) of how many hunters (distinct IPs with onePerIp)
-- are on the same floor within nearRadius of each one, itself included.
function R.counts(hunters, cfg)
	local r = cfg.nearRadius or 10
	local cell = math.max(1, r)
	local grid = {}
	for i, h in ipairs(hunters) do
		local key = math.floor(h.x / cell) .. ":" .. math.floor(h.y / cell) .. ":" .. h.z
		local list = grid[key]
		if not list then
			list = {}
			grid[key] = list
		end
		list[#list + 1] = i
	end
	local out = {}
	for i, h in ipairs(hunters) do
		local seen, n = {}, 0
		local gx, gy = math.floor(h.x / cell), math.floor(h.y / cell)
		for dx = -1, 1 do
			for dy = -1, 1 do
				for _, j in ipairs(grid[(gx + dx) .. ":" .. (gy + dy) .. ":" .. h.z] or {}) do
					local o = hunters[j]
					if math.abs(o.x - h.x) <= r and math.abs(o.y - h.y) <= r then
						local id = (cfg.onePerIp ~= false and o.ip and o.ip ~= 0) and ("ip" .. o.ip) or ("i" .. j)
						if not seen[id] then
							seen[id] = true
							n = n + 1
						end
					end
				end
			end
		end
		out[i] = n
	end
	return out
end

-- busy zones: one per grid cell holding a hunter with at least minHunters around. Each zone:
-- {key, x0, y0, x1, y1, z, n, percent}, sorted so that applying them in order lets the busiest win.
function R.zones(hunters, cfg)
	local counts = R.counts(hunters, cfg)
	local size, margin = cfg.cellSize or 16, cfg.margin or 8
	local byKey = {}
	for i, h in ipairs(hunters) do
		local n = counts[i]
		if n >= (cfg.minHunters or 2) then
			local cx, cy = math.floor(h.x / size), math.floor(h.y / size)
			local key = cx .. ":" .. cy .. ":" .. h.z
			local z = byKey[key]
			if not z then
				z = {key = key, x0 = cx * size - margin, y0 = cy * size - margin, x1 = (cx + 1) * size - 1 + margin,
					y1 = (cy + 1) * size - 1 + margin, z = h.z, n = 0}
				byKey[key] = z
			end
			if n > z.n then
				z.n = n
			end
		end
	end
	local list = {}
	for _, z in pairs(byKey) do
		z.percent = R.percentFor(z.n, cfg)
		if z.percent ~= R.percentFor(0, cfg) then
			list[#list + 1] = z
		end
	end
	table.sort(list, function(a, b)
		if a.percent ~= b.percent then
			return a.percent > b.percent
		end
		return a.key < b.key
	end)
	return list
end

-- a text that is the same when the zones (and the global percent) are the same
function R.signature(zones, cfg)
	local parts = {tostring(R.percentFor(0, cfg))}
	for _, z in ipairs(zones) do
		parts[#parts + 1] = z.key .. "=" .. z.percent
	end
	return table.concat(parts, ";")
end

-- the engine calls for this tick: nothing when nothing changed, else one call that sets every spawn to the global
-- percent, then one per zone. state is kept between ticks ({} at the start; the engine starts with 100 everywhere).
-- Each call: {percent = p} (all spawns) or {percent = p, from = {x, y, z}, to = {x, y, z}}.
function R.plan(state, zones, cfg)
	local sig = R.signature(zones, cfg)
	local last = state.signature or tostring(100)
	if sig == last then
		return {}
	end
	state.signature = sig
	local calls = {{percent = R.percentFor(0, cfg)}}
	for _, z in ipairs(zones) do
		calls[#calls + 1] = {percent = z.percent, from = {x = z.x0, y = z.y0, z = z.z}, to = {x = z.x1, y = z.y1, z = z.z}}
	end
	return calls
end

return R
