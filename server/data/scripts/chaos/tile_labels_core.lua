-- Orange tile labels: the pure part (no engine calls), shared by tile_labels.lua and server/tests/tile_labels_test.lua.
--   K.collect(cfg, boothsCfg, boothsCore, stands) -> {{text, x, y, z}, ...}: the booth names, the row titles at both
--                                           ends of each row built in that hall's town, the names over the temple
--                                           arcade's stands (stands = {{name, x, y, z}}, npc_place_core.lua
--                                           templeStands; cfg.stands) and the fixed labels, each tile and text once,
--                                           in a stable order
-- Lua 5.1 / LuaJIT and 5.3 compatible.
ChaosTileLabelsCore = ChaosTileLabelsCore or {}
local K = ChaosTileLabelsCore

function K.collect(cfg, boothsCfg, B, stands)
	local out, seen = {}, {}
	local function add(text, p)
		if type(text) ~= "string" or text == "" or type(p) ~= "table" or not (p.x and p.y and p.z) then
			return
		end
		local key = p.x .. ":" .. p.y .. ":" .. p.z .. ":" .. text
		if not seen[key] then
			seen[key] = true
			out[#out + 1] = {text = text, x = p.x, y = p.y, z = p.z}
		end
	end
	if boothsCfg and B then
		for _, hall in ipairs(boothsCfg.halls or {}) do
			if cfg.booths then
				for _, b in ipairs(B.booths(boothsCfg, hall)) do
					add(b.name, b)
				end
			end
			for _, row in ipairs(boothsCfg.rows or {}) do
				local title = cfg.rowTitles and cfg.rowTitles[row.key]
				local built = not B.rowTiles or #B.rowTiles(row, hall.town, boothsCfg.items) > 0
				if title and row.from and row.to and built then
					add(title, B.offset(hall, row.from, row.npcRow))
					add(title, B.offset(hall, row.to, row.npcRow))
				end
			end
		end
	end
	if cfg.stands then
		for _, st in ipairs(stands or {}) do
			add(st.name, st)
		end
	end
	for _, l in ipairs(cfg.labels or {}) do
		add(l.text, l.pos)
	end
	return out
end

return K
