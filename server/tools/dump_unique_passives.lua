-- Prints the tooltip line of every unique passive, one per line: id <TAB> English <TAB> pt-BR (O278).
-- tools/gen_unique_specs.py reads it to put the line into the unique's description and the pt-BR Codex texts.
-- usage (from server/): luajit tools/dump_unique_passives.lua
dofile("data/scripts/chaos/unique_passives_config.lua")
dofile("data/scripts/chaos/unique_passives_text.lua")
dofile("data/scripts/chaos/unique_passives_core.lua")
local C = ChaosUniquePassivesCore
local cfg = ChaosUniquePassivesConfig
local ids = {}
for id in pairs(cfg.passives) do
	ids[#ids + 1] = id
end
table.sort(ids)
for _, id in ipairs(ids) do
	local e = C.entry(cfg, id)
	print(id .. "\t" .. C.text(cfg, e, "en") .. "\t" .. C.text(cfg, e, "pt-BR"))
end
