-- npc_travel_core.lua: the pure logic of "Travel to an NPC" (npc_travel_config.lua; engine side: npc_travel.lua; client
-- game_npctravel). No engine calls. Lua 5.1 / LuaJIT and 5.3.
--   K.entry(cfg, key)                       the NPC entry of a key, or nil
--   K.keys(cfg)                             the keys, sorted
--   K.hubSpot(cfg, booths, name)            {x, y, z} of the NPC's stall in the hub, and the carpet tile in front of it, or nil
--   K.resolve(cfg, booths, key, probe)      where the NPC is: {npc = pos, hint = pos | nil, front = true | nil, via = "live" |
--                                           "hub" | "pos" | "temple"} | nil, "unknown" | "unset"
--   K.candidates(npc, hint, maxRing, front) the tiles around the NPC to try, best first (a list of {x, y, z})
--   K.near(a, b, range)                     same floor and within range tiles
--   K.cooldownLeft(cfg, now, last)          seconds left of the cooldown
--   K.blockReason(f, T, labels)             why the player may not travel (nil = allowed); f = the facts, T = text function
--   K.validate(cfg, booths, factions, towns) a list of problems of the config
ChaosNpcTravelCore = ChaosNpcTravelCore or {}
local K = ChaosNpcTravelCore

function K.entry(cfg, key)
	local e = cfg and cfg.npcs and type(key) == "string" and cfg.npcs[key] or nil
	return type(e) == "table" and e or nil
end

function K.keys(cfg)
	local out = {}
	for key in pairs(cfg and cfg.npcs or {}) do
		out[#out + 1] = key
	end
	table.sort(out)
	return out
end

-- booths: a list of {name, x, y, z} (ChaosNpcBoothsCore.booths)
function K.hubSpot(cfg, booths, name)
	local want = tostring(name or ""):lower()
	for _, b in ipairs(booths or {}) do
		if tostring(b.name):lower() == want then
			local walk = cfg and cfg.hub and cfg.hub.walkY
			local spot = {x = b.x, y = b.y, z = b.z}
			local front = walk and {x = b.x, y = walk, z = b.z} or nil
			return spot, front
		end
	end
	return nil
end

-- probe: {live = function(name) -> {x, y, z} | nil, temple = function(townId) -> {x, y, z} | nil}
function K.resolve(cfg, booths, key, probe)
	local e = K.entry(cfg, key)
	if not e then
		return nil, "unknown"
	end
	probe = probe or {}
	local stall, front = K.hubSpot(cfg, booths, e.name)
	local live = probe.live and probe.live(e.name) or nil
	if live then
		if stall and live.z == stall.z and math.abs(live.x - stall.x) <= 1 and math.abs(live.y - stall.y) <= 1 then
			return {npc = live, hint = front, front = true, via = "live"}
		end
		local temple = e.townId and probe.temple and probe.temple(e.townId) or nil
		return {npc = live, hint = temple, via = "live"}
	end
	if stall then
		return {npc = stall, hint = front, front = true, via = "hub"}
	end
	if type(e.pos) == "table" and e.pos.x then
		return {npc = {x = e.pos.x, y = e.pos.y, z = e.pos.z}, via = "pos"}
	end
	local temple = e.townId and probe.temple and probe.temple(e.townId) or nil
	if temple then
		return {npc = temple, via = "temple"}
	end
	return nil, "unset"
end

local function cheb(dx, dy)
	return math.max(math.abs(dx), math.abs(dy))
end

-- the tiles within maxRing of the NPC (not its own), best first. front (a stall behind a counter): by the distance to the
-- hint (the carpet), so the tiles in front come before the ones behind the counter; else the nearest ring first, then
-- the closer to the hint (the temple), so a player lands next to the NPC on the side the town is.
function K.candidates(npc, hint, maxRing, front)
	maxRing = math.max(1, math.floor(tonumber(maxRing) or 2))
	local list = {}
	for dy = -maxRing, maxRing do
		for dx = -maxRing, maxRing do
			if dx ~= 0 or dy ~= 0 then
				local p = {x = npc.x + dx, y = npc.y + dy, z = npc.z}
				local d = 0
				if hint then
					local hx, hy = p.x - hint.x, p.y - hint.y
					d = hx * hx + hy * hy
				end
				list[#list + 1] = {pos = p, ring = cheb(dx, dy), d = d}
			end
		end
	end
	table.sort(list, function(a, b)
		if front then
			if a.d ~= b.d then return a.d < b.d end
			if a.ring ~= b.ring then return a.ring < b.ring end
		else
			if a.ring ~= b.ring then return a.ring < b.ring end
			if a.d ~= b.d then return a.d < b.d end
		end
		if a.pos.y ~= b.pos.y then return a.pos.y < b.pos.y end
		return a.pos.x < b.pos.x
	end)
	local out = {}
	for i, c in ipairs(list) do
		out[i] = c.pos
	end
	return out
end

function K.near(a, b, range)
	return a ~= nil and b ~= nil and a.z == b.z and cheb(a.x - b.x, a.y - b.y) <= (range or 2)
end

function K.cooldownLeft(cfg, now, last)
	local cd = (cfg and cfg.cooldownSeconds) or 0
	if not last or last <= 0 then
		return 0
	end
	return math.max(0, math.ceil(last + cd - now))
end

-- f: {disabled, casting, cooldownLeft, tutorial, arena, worldBoss, siege, rift, dungeon, tower, hideout, marches,
-- instance (a label), inFight, skull}. T(key, ...) is the text in the player's language (English without it).
function K.blockReason(f, T, labels)
	local function tx(key, ...)
		if T then
			return T(key, ...)
		end
		if select("#", ...) > 0 then
			return string.format(key, ...)
		end
		return key
	end
	labels = labels or {}
	if f.disabled then
		return tx("Travel to an NPC is switched off.")
	end
	if f.casting then
		return tx("Finish opening your portal first.")
	end
	if (f.cooldownLeft or 0) > 0 then
		return f.cooldownLeft == 1 and tx("You can travel to an NPC again in 1 second.")
			or tx("You can travel to an NPC again in %d seconds.", f.cooldownLeft)
	end
	if f.tutorial then
		return tx("Finish or skip the tutorial first: the NPCs of the city wait for you after the island.")
	end
	for _, k in ipairs({"arena", "worldBoss", "siege", "rift", "dungeon", "tower", "hideout", "marches"}) do
		if f[k] then
			return tx("You cannot travel to an NPC from %s: leave through its own exit.", tx(labels[k] or k))
		end
	end
	if f.instance then
		return tx("You cannot travel to an NPC from %s: leave through its own exit.",
			type(f.instance) == "string" and f.instance or tx("this place"))
	end
	if f.inFight then
		return tx("You cannot travel to an NPC while you are in combat.")
	end
	if f.skull then
		return tx("You cannot travel to an NPC while you carry a skull.")
	end
	return nil
end

-- booths: ChaosNpcBoothsCore.booths(cfg) rows; factions: factions_config.lua `factions`; towns: {[id] = true} the towns with a
-- temple on the map (data/chaos_poi.lua). Any argument may be nil (its checks are skipped).
function K.validate(cfg, booths, factions, towns)
	local problems = {}
	if type(cfg) ~= "table" or type(cfg.npcs) ~= "table" then
		return {"no npcs"}
	end
	local used = {}
	for _, key in ipairs(K.keys(cfg)) do
		local e = cfg.npcs[key]
		if type(e.name) ~= "string" or e.name == "" then
			problems[#problems + 1] = key .. ": no name"
		elseif used[e.name] then
			problems[#problems + 1] = key .. ": NPC " .. e.name .. " used twice (" .. used[e.name] .. ")"
		else
			used[e.name] = key
		end
		if type(e.where) ~= "string" or e.where == "" then
			problems[#problems + 1] = key .. ": no where text"
		end
		local inHub = booths and K.hubSpot(cfg, booths, e.name) ~= nil
		if booths and not inHub and not e.townId and not e.pos then
			problems[#problems + 1] = key .. ": not in a hub stall, and no townId or pos"
		end
		if e.townId and towns and not towns[e.townId] then
			problems[#problems + 1] = key .. ": town " .. tostring(e.townId) .. " has no temple on the map"
		end
	end
	for _, f in ipairs(factions or {}) do
		local e = cfg.npcs["faction_" .. f.key]
		if not e then
			problems[#problems + 1] = "faction_" .. f.key .. ": missing"
		else
			if e.name ~= f.npc.name then
				problems[#problems + 1] = "faction_" .. f.key .. ": NPC " .. tostring(e.name) .. " is " .. f.npc.name .. " in factions_config.lua"
			end
			local inHub = booths and K.hubSpot(cfg, booths, e.name) ~= nil
			if not inHub and e.townId ~= f.npc.townId then
				problems[#problems + 1] = "faction_" .. f.key .. ": townId " .. tostring(e.townId) .. " is " .. tostring(f.npc.townId) .. " in factions_config.lua"
			end
		end
	end
	return problems
end

return K
