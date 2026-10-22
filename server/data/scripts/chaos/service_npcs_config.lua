-- The service NPCs of the hub (service_npcs.lua, service_npcs_core.lua, service_npcs_run.lua, the NPC
-- scripts data/npc/scripts/chaos_service_npc.lua; server/README.md "Service NPCs"): every number. Plain data, no engine
-- calls (tests/service_npcs_test.lua and tools/install_service_npcs.py read it). Lua 5.1 / LuaJIT and Lua 5.3.
--
-- Owner decision 2026-10-20: five NPCs that stand in for menu entries, in this order: the stash keeper, the pocket
-- boss NPC, the banker, the house broker and the services clerk (each in a stall of the hub, npc_booths_config.lua). The menu entries stay (the owner confirms in the game before any is removed). They
-- add no opcode, no storage key and no table: every window opens through the opcode of its own module.
local C = {}

C.enabled = true

-- the main city only: each stands in its stall of the hub (npc_booths_config.lua; owner 2026-10-22, the Halls of
-- Services are gone)
C.towns = {2}
C.delayMs = 4000 -- after the other startup NPCs, like Osric the Chandler (3500)
-- next to the temple, only when an NPC has no stall in the hub (npc_place.lua)
C.offsets = {{-5, -3}, {5, -3}, {-5, 3}, {5, 3}, {-4, -5}, {4, 5}, {-7, -2}, {7, -2}, {-7, 2}, {7, 2}}

-- key -> NPC. `name` is also the file data/npc/<name>.xml; `script` the file it names. `window`: what the NPC opens
-- ({opcode = key of ChaosOpcodes, json = the message the module's client handles, "npc" action}); nil: no window.
C.npcs = {
	stash = {name = "Tavish Coldhand", script = "tavish_coldhand.lua", slot = "stash keeper",
		window = {opcode = "stash", json = '{"action":"Stash","data":{"make":"Toggle","remote":false,"open":true}}'}},
	pocketboss = {name = "Vessa Hollowmark", script = "vessa_hollowmark.lua", slot = "pocket boss NPC",
		window = {opcode = "bossSpawns", json = '{"action":"npc","data":{}}'}},
	banker = {name = "Cassian Auric", script = "cassian_auric.lua",
		window = {opcode = "bank", json = '{"action":"npc","data":{}}'}},
	broker = {name = "Halvard Deedkeeper", script = "halvard_deedkeeper.lua",
		window = {opcode = "info", json = '{"action":"npc","data":{"page":"house"}}'}},
	services = {name = "Pell Ashmere", script = "pell_ashmere.lua",
		window = {opcode = "info", json = '{"action":"npc","data":{"page":"services"}}'}}
}
C.order = {"stash", "pocketboss", "banker", "broker", "services"}

-- The house broker. perSqm: the price of a tile when the base config has none (config.lua housePriceEachSQM, read
-- first); listMax: houses named in one answer; townMax: towns named in one answer.
C.broker = {perSqm = 1000, listMax = 6, townMax = 8, nameMax = 40}

return C
