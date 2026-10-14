-- Hunt teleports, pure logic (server/README.md "Hunt teleports"; tests/hunt_teleports_test.lua). No engine calls.
-- The config is hunt_teleports_config.lua; the places (slot, arrival, exit and level band of every placed plan) come
-- from data/lib/chaos_hunt_places.lua, which server/tools/install_content_areas.py writes into the installed server.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosHuntTeleportsCore = ChaosHuntTeleportsCore or {}
local H = ChaosHuntTeleportsCore

local function key(p)
	return p.x .. "," .. p.y .. "," .. p.z
end
H.key = key

local function isPos(p)
	return type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
end

-- "pt-BR" for a Portuguese language code, else "en"
function H.lang(code)
	if type(code) == "string" and code:lower():sub(1, 2) == "pt" then
		return "pt-BR"
	end
	return "en"
end

-- the text of `k` in `lang` (the English key when the language has none), formatted
function H.text(cfg, lang, k, ...)
	local t = cfg.texts and cfg.texts[H.lang(lang)]
	local pattern = t and t[k] or k
	local ok, s = pcall(string.format, pattern, ...)
	if ok then
		return s
	end
	return (string.format(k, ...))
end

-- problems of the config and the places (strings); an empty list when both are usable
function H.validate(cfg, places)
	local out = {}
	if type(cfg) ~= "table" then
		return {"no config"}
	end
	if type(cfg.aid) ~= "number" or cfg.aid < 47930 or cfg.aid > 47939 then
		out[#out + 1] = "aid must be in the block 47930-47939"
	end
	local ids = {}
	for i, p in ipairs(cfg.plans or {}) do
		if type(p.id) ~= "string" then
			out[#out + 1] = "plans[" .. i .. "] has no id"
		elseif ids[p.id] then
			out[#out + 1] = "plan " .. p.id .. " is listed twice"
		end
		ids[p.id or ""] = true
		if type(p.monster) ~= "string" or p.monster == "" then
			out[#out + 1] = "plan " .. tostring(p.id) .. " has no display monster"
		end
	end
	if places == nil then
		return out
	end
	if type(places) ~= "table" or type(places.places) ~= "table" then
		out[#out + 1] = "places: not a table"
		return out
	end
	if not isPos(places.back) then
		out[#out + 1] = "places: no back tile"
	end
	local seen = {}
	for i, e in ipairs(places.places) do
		local name = tostring(e.id or i)
		for _, f in ipairs({"teleport", "arrival"}) do
			if not isPos(e[f]) then
				out[#out + 1] = name .. ": no " .. f .. " tile"
			end
		end
		if type(e.level) ~= "table" or type(e.level[1]) ~= "number" or type(e.level[2]) ~= "number" then
			out[#out + 1] = name .. ": no level band"
		end
		if isPos(e.teleport) then
			if seen[key(e.teleport)] then
				out[#out + 1] = name .. ": shares its teleport tile with " .. seen[key(e.teleport)]
			end
			seen[key(e.teleport)] = name
		end
	end
	return out
end

-- the plan entries of the config by id
local function cfgPlans(cfg)
	local by = {}
	for _, p in ipairs(cfg.plans or {}) do
		if p.id then
			by[p.id] = p
		end
	end
	return by
end

-- the lookup tables: byTeleport[tile key] and byExit[tile key] -> entry {id, name, level, minLevel, teleport, sign,
-- arrival, exit, monster}; the config's entry of a plan (when it has one) gives minLevel and the display monster
function H.index(cfg, places)
	local idx = {byTeleport = {}, byExit = {}, list = {}, back = places and places.back}
	if type(places) ~= "table" or type(places.places) ~= "table" then
		return idx
	end
	local by = cfgPlans(cfg)
	for _, e in ipairs(places.places) do
		local c = by[e.id] or {}
		if isPos(e.teleport) and isPos(e.arrival) and type(e.level) == "table" then
			local entry = {
				id = e.id, name = e.name or e.id, level = {e.level[1], e.level[2]},
				minLevel = c.minLevel or e.level[1], teleport = e.teleport, sign = e.sign, arrival = e.arrival,
				exit = e.exit, monster = c.monster or e.monster
			}
			idx.byTeleport[key(e.teleport)] = entry
			if isPos(e.exit) then
				idx.byExit[key(e.exit)] = entry
			end
			idx.list[#idx.list + 1] = entry
		end
	end
	return idx
end

-- the label of a teleport in one language: "Widowmere, levels 480-640"
function H.label(cfg, entry, lang)
	return H.text(cfg, lang, "%s, levels %d-%d", entry.name, entry.level[1], entry.level[2])
end

-- the sign's text (signs have one text for everybody): the name, then the band in both languages
function H.signText(cfg, entry)
	return H.label(cfg, entry, "en") .. "\n" .. H.label(cfg, entry, "pt-BR")
end

-- a player of `level` steps on the teleport of `entry`: true, arrival message; or false, refusal message
function H.enter(cfg, entry, level, lang)
	if type(level) ~= "number" or level < entry.minLevel then
		return false, H.text(cfg, lang, "%s is for level %d and above.", entry.name, entry.minLevel)
	end
	return true, H.text(cfg, lang, "%s: monsters of level %d-%d. The portal at the camp leads back to the teleport room.",
		entry.name, entry.level[1], entry.level[2])
end

-- where the exit portal at `pos` sends players: the room's back tile for a placed plan's exit, else nil
function H.backFor(idx, pos)
	if not isPos(pos) or not idx or not idx.byExit[key(pos)] then
		return nil
	end
	return idx.back
end

return H
