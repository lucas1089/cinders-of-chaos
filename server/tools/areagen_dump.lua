-- Prints the tile model of the generated areas (areagen_core.lua, areagen_config.lua) as plain lines for
-- server/tools/areagen_export.py. Run from the server/ folder:
--     luajit tools/areagen_dump.lua [area id | all] [dark]
-- Lines (space separated, the monster name last):
--   A id kind originX originY originZ width height floors name...
--   F z walkable hunt monsters
--   T x y z walkable(1/0) ground [item ...]
--   S x y z level count spawntime monster...
--   B x y z level healthMult spawntime monster|shown name
--   L holeX holeY holeZ ladderX ladderY ladderZ upX upY upZ
--   R arrivalX arrivalY arrivalZ exitX exitY exitZ
--   E entranceX entranceY entranceZ backX backY backZ   (when the area has an entrance on the map)
--   Q x1 y1 x2 y2 z                                    (a room of a dungeon layout)
--   X problem...                                        (A.validate)
--   C checksum
dofile("data/scripts/chaos/areagen_core.lua")
dofile("data/lib/chaos_dark_tiles.lua")
local A = ChaosAreaGenCore
local cfg = dofile("data/scripts/chaos/areagen_config.lua")
local want = arg[1] or "all"
local dark = arg[2] == "dark"
local opts = {dark = dark, darkIds = ChaosDarkTiles.ids}

local out = {}
local function put(s)
	out[#out + 1] = s
	if #out >= 2000 then
		io.write(table.concat(out, "\n"), "\n")
		out = {}
	end
end

for _, def in ipairs(cfg.areas) do
	if want == "all" or want == def.id then
		local m = A.generate(cfg, def, opts)
		put(string.format("A %s %s %d %d %d %d %d %d %s", def.id, def.kind, def.origin.x, def.origin.y, def.origin.z,
			m.w, m.h, def.floors or 1, def.name))
		for _, f in ipairs(m.floors) do
			put(string.format("F %d %d %d %d", f.z, f.walkable, f.hunt, f.monsters))
		end
		for _, t in ipairs(m.tiles) do
			local wk = m.walk[t.z] and m.walk[t.z][t.y * 65536 + t.x] and 1 or 0
			put(string.format("T %d %d %d %d %d", t.x, t.y, t.z, wk, t.ground) .. (#t.items > 0 and (" " .. table.concat(t.items, " ")) or ""))
		end
		for _, s in ipairs(m.spawns) do
			put(string.format("S %d %d %d %d %d %d %s", s.x, s.y, s.z, s.level, s.count, s.spawntime or 0, s.monster))
		end
		if m.boss then
			local b = m.boss
			put(string.format("B %d %d %d %d %d %d %s|%s", b.x, b.y, b.z, b.level or 0, b.healthMult or 1, b.spawntime or 0,
				b.monster, b.name or b.monster))
		end
		for _, l in ipairs(m.links) do
			put(string.format("L %d %d %d %d %d %d %d %d %d", l.hole.x, l.hole.y, l.hole.z, l.ladder.x, l.ladder.y, l.ladder.z,
				l.up.x, l.up.y, l.up.z))
		end
		put(string.format("R %d %d %d %d %d %d", m.arrival.x, m.arrival.y, m.arrival.z, m.exit.x, m.exit.y, m.exit.z))
		if def.entrance then
			local e, b = def.entrance, def.back or def.entrance
			put(string.format("E %d %d %d %d %d %d", e.x, e.y, e.z, b.x, b.y, b.z))
		end
		for _, q in ipairs(m.rooms or {}) do
			put(string.format("Q %d %d %d %d %d", q.x1, q.y1, q.x2, q.y2, q.z))
		end
		for _, p in ipairs(A.validate(cfg, m, opts)) do
			put("X " .. p)
		end
		put("C " .. A.checksum(m))
	end
end
io.write(table.concat(out, "\n"), "\n")
