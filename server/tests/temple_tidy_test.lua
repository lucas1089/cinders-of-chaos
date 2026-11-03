-- Run from the server/ folder: luajit tests/temple_tidy_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers what O386 (owner 2026-11-03: "organize o templo, deixe ele mais clean, retire um dos portais roxos") put in
-- the configs of Cinderhold's temple (the base map was read on 2026-11-03; tools/patch_temple_tidy_test.py checks the
-- map tool): the tidy list of temple_portals_config.lua takes the east purple teleport and keeps the west one, the
-- Chronicle's town decoration (chronicle_config.lua town.sets) stands in mirrored spots off the walkways (not the
-- side doors, not the walk from the temple to the north door, not the vestibule or the portal gallery south of the
-- wall), and the Great Brazier first takes the freed teleport tile, not the walk to the east side room.
local gallery = dofile("data/scripts/chaos/temple_portals_config.lua")
local chron = dofile("data/scripts/chaos/chronicle_config.lua")
local comm = dofile("data/scripts/chaos/community_config.lua")

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local town
for _, t in ipairs(gallery.towns) do
	if t.town == 2 then
		town = t
	end
end
ok(town ~= nil, "Cinderhold's gallery")
local T = town.temple

-- ------------------------------------------------------------------ the tidy list
eq(#gallery.tidy, 1, "one town tidied")
local tidy = gallery.tidy[1]
eq(tidy.town, 2, "Cinderhold")
eq(tidy.z, T.z, "the temple's floor")
local pieces = {}
for _, r in ipairs(tidy.remove) do
	if r.item >= 28013 and r.item <= 28017 then
		pieces[r.item] = r
		ok(r.x > T.x, "only the east teleport: " .. r.item .. " at " .. r.x)
	end
	ok(math.abs(r.x - T.x) <= 12 and math.abs(r.y - T.y) <= 8, "in the temple: " .. r.x .. "," .. r.y)
	ok(r.y < town.portalRow, "north of the gallery: " .. r.x .. "," .. r.y)
end
for id = 28013, 28017 do
	ok(pieces[id] ~= nil, "teleport piece " .. id .. " listed")
end
local texts = {}
for _, s in ipairs(tidy.texts) do
	texts[s.text] = s
end
ok(texts["Teleports"] and texts["Teleports"].x == pieces[28014].x and texts["Teleports"].y == pieces[28014].y,
	"the east teleport's floating text goes with it")
ok(texts["Collect First Items!"] ~= nil, "the starter chest's floating text goes")

-- ------------------------------------------------------------------ the Chronicle's town decoration
ok(chron.town.anchor == nil, "anchored on the capital's temple")
local function blocked(dx, dy)
	if dy >= town.portalRow - T.y then
		return "the temple's south wall, the vestibule or the gallery"
	end
	if (dx == -6 or dx == 6) and dy == 0 then
		return "a side door"
	end
	if dx >= -2 and dx <= 2 and dy < 0 then
		return "the walk to the north door"
	end
	if dx >= -2 and dx <= 2 and dy == 0 then
		return "the temple spot"
	end
	if (dx == -8 or dx == 7) and dy == 2 then
		return "the stairs of a side room"
	end
	return nil
end
for key, set in pairs(chron.town.sets) do
	local mirror = {}
	for _, p in ipairs(set.pieces) do
		for _, o in ipairs(p.at) do
			local why = blocked(o[1], o[2])
			ok(not why, key .. " piece " .. p.id .. " at " .. o[1] .. "," .. o[2] .. ": " .. tostring(why))
			mirror[o[1] .. "," .. o[2]] = true
		end
	end
	for k in pairs(mirror) do
		local dx, dy = k:match("^(%-?%d+),(%-?%d+)$")
		ok(mirror[(-tonumber(dx)) .. "," .. dy], key .. ": " .. k .. " has its mirror on the temple's axis")
	end
end

-- ------------------------------------------------------------------ the Great Brazier
eq(comm.brazier.townId, 2, "the Brazier in Cinderhold")
local first = comm.brazier.offsets[1]
eq(T.x + first[1], pieces[28014].x, "the Brazier's first spot: the freed teleport tile (x)")
eq(T.y + first[2], pieces[28014].y, "the Brazier's first spot: the freed teleport tile (y)")
ok(comm.brazier.pos == nil, "no fixed spot: a map without the tidy goes on down the offsets")

print(string.format("temple_tidy_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
