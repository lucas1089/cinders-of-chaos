-- Cinders of Chaos: paint one of our compiled area plans (server/tools/areaplan/plans) in the map editor
-- (docs/MAP_GUIDE.md "Generator in the map editor"). Tools > Lua Scripts, mode "Custom Lua script", choose this file,
-- set plan below, Generate, then Apply (one Undo removes it). The log says which Destination puts the area where the
-- server has it. plans\index.txt lists the plans; plans\<id>-notes.txt has what the editor cannot write (spawns,
-- NPCs, chest and portal action ids, teleport targets, protection zones).
local P = {
	plan = "sunken_mirewood", -- the plan id (file name without .json)
	floor = nil,              -- nil: every floor; a z (for example 9): that floor only (plans over 100,000 tiles)
	frame = true,             -- the view frame: bare rock around the area, as on the server
}
for k, v in pairs(CINDERS_PARAMS or {}) do
	P[k] = v
end
return dofile("tools/editor_scripts/cinders_editor.lua").paint(P)
