-- Global experience cap (xpcap.lua, xpcap_core.lua): every number. Plain table, loaded with
--     ChaosXpCapConfig = dofile("data/scripts/chaos/xpcap_config.lua")
-- server/README.md "Experience cap". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,

	-- the experience of a monster kill after every bonus is at most cap x the kill's base experience: the monster's
	-- experience x its level factor x the stage of the player's level x the monster tier. Everything in between
	-- multiplies into it and counts: the store potion (doubled in base player.lua; halved back for season characters
	-- by shop_services.lua), stamina, Blood Moon, Victory, World Experience, blessings, professions, community, the
	-- Marches and the shrine, the passive tree, item mods, waystones, bestiary, guild, siege, mentor, the Chaos Pact
	-- (pact_perks.lua, index 7), the Weekend Ritual (weekend.lua, index 55), season modifier and the admin double_exp event (admin/actions_events.lua, index 50).
	cap = 4.0,

	-- EventCallback onGainExperience index of the cap: after every bonus (0-50), before the dungeon difficulty (90:
	-- the difficulty's experience goes with its 1.3-13x monster health, like the tier), the rift cap (100) and the hunt
	-- tracker (1000, it records what was really given)
	index = 85,
	-- index of the recorder that keeps the experience as it enters the chain, used only when the engine passes no rawExp
	recordIndex = -1000
}
