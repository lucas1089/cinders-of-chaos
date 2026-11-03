-- Cinders of Chaos: a new area from our area generator, inside the map editor (docs/MAP_GUIDE.md "Generator in the
-- map editor"). Tools > Lua Scripts, mode "Custom Lua script", choose this file, change the values below, Generate:
-- the log shows the area; Apply writes it (one Undo removes it). Destination X / Y = the top-left corner; Destination
-- floor = the deepest floor of the area. Save the map afterwards. Spawns are listed in the log and in
-- generated_spawns.txt (the editor cannot place creatures).
local P = {
	biome = "cave",        -- cave, lava, waste, swamp, marsh, crypt, vault, catacomb, hall, abyss, sanctum, forest, ice
	                       -- (with the pack art: forest_pack, ice_pack; the harvest kit: harvest, harvest_crypt; townhall)
	width = 96,            -- 32-400; width x height x floors at most 100,000 tiles
	height = 76,
	floors = 1,            -- 1-4, going down
	seed = nil,            -- nil: the seed of the editor window; a number: always the same area
	level = {300, 400},    -- the monsters' level band (the spawn list)
	decoration = "normal", -- sparse, normal, dense
	light = nil,           -- dark, dim, normal, bright; nil: the biome's own
	boss = true,           -- a boss room (dungeons) or a boss spot
	dark = false,          -- the dark tile set
}
-- tests and other scripts may set CINDERS_PARAMS to change the values above
for k, v in pairs(CINDERS_PARAMS or {}) do
	P[k] = v
end
return dofile("tools/editor_scripts/cinders_editor.lua").generate(P)
