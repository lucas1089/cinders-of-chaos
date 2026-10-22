-- City portals, the pure part (no engine calls): where a labelled portal next to a temple goes, whether a tile may take
-- one, its look text. Shared by cityportals.lua (the engine side), cityportals_fx.lua, hideout.lua, guild_hall.lua and
-- server/tests/cityportals_test.lua. server/README.md "City portals". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--   C.cfg()                                  the config (cityportals_config.lua)
--   C.candidates(cfg, spot, town, temple, offsets)
--                                            the tiles to try, in order: {{x, y, z, why}, ...}; why = town | offset;
--                                            spot: the key of `towns` (the kind, or e.g. one Chronicle gate)
--   C.spotOk(f)                              may a new portal stand on a tile; f = {ground, solid, path, house, teleport,
--                                            floorchange, loose (movable items and doors on it)}
--   C.pick(list, probe)                      the first tile of `list` that already holds our portal ("ours"), else the
--                                            first "free" one; probe(pos) -> "ours" | "free" | anything else. pos, had
--   C.lookText(cfg, kind, t, title)          "Name (title): text" through the translator t(text) (default: as is); title
--                                            (optional, a proper name such as a Chronicle area) is not translated
--   C.labelOf(cfg, kind, t, title)          the orange label over a portal: its title (a proper name, as is), else the
--                                            kind's label through t; nil for a kind without a label
--   C.key(pos)                               "x,y,z"
--   C.bandTitle(name, band)                  "Sulphur Gallery, levels 215-299" (band {low, high}; one level: "level N")
ChaosCityPortalsCore = ChaosCityPortalsCore or {}
local C = ChaosCityPortalsCore

function C.cfg()
	if not C.config then
		C.config = dofile("data/scripts/chaos/cityportals_config.lua")
	end
	return C.config
end

function C.key(p)
	return p.x .. "," .. p.y .. "," .. p.z
end

local function sameTemple(a, t)
	return type(a) == "table" and t ~= nil and a[1] == t.x and a[2] == t.y and a[3] == t.z
end

function C.candidates(cfg, kind, town, temple, offsets)
	local out, seen = {}, {}
	local function add(x, y, z, why)
		local p = {x = x, y = y, z = z, why = why}
		local k = C.key(p)
		if not seen[k] then
			seen[k] = true
			out[#out + 1] = p
		end
	end
	if not temple or (temple.x or 0) <= 0 then
		return out
	end
	local t = cfg.towns and cfg.towns[town]
	if t and t[kind] and sameTemple(t.temple, temple) then
		add(temple.x + t[kind][1], temple.y + t[kind][2], temple.z, "town")
	end
	for _, list in ipairs({offsets or {}, cfg.offsets or {}}) do
		for _, o in ipairs(list) do
			add(temple.x + o[1], temple.y + o[2], temple.z, "offset")
		end
	end
	return out
end

function C.spotOk(f)
	return f ~= nil and f.ground == true and not f.solid and not f.path and not f.house and not f.teleport
		and not f.floorchange and (f.loose or 0) == 0
end

function C.pick(list, probe)
	for _, p in ipairs(list) do
		if probe(p) == "ours" then
			return p, true
		end
	end
	for _, p in ipairs(list) do
		if probe(p) == "free" then
			return p, false
		end
	end
	return nil, false
end

function C.bandTitle(name, band)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local lo, hi = type(band) == "table" and tonumber(band[1]), type(band) == "table" and tonumber(band[2])
	if lo and hi and hi ~= lo then
		return string.format("%s, levels %d-%d", name, lo, hi)
	elseif lo then
		return string.format("%s, level %d", name, lo)
	end
	return name
end

function C.lookText(cfg, kind, t, title)
	local k = cfg.kinds[kind]
	if not k then
		return nil
	end
	t = t or function(s) return s end
	return t(k.name) .. (title and (" (" .. title .. ")") or "") .. ": " .. t(k.text)
end

function C.labelOf(cfg, kind, t, title)
	local k = cfg.kinds[kind]
	if not (k and k.label) then
		return nil
	end
	if type(title) == "string" and title ~= "" then
		return title
	end
	t = t or function(s) return s end
	return t(k.label)
end

return C
