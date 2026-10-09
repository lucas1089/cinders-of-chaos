-- townportal_config.lua: the Town Portal ability and the portal styles (townportal.lua, townportal_core.lua).
-- Plain table, loaded with  ChaosTownPortalConfig = dofile("data/scripts/chaos/townportal_config.lua")
-- No engine calls here (server/tests/townportal_test.lua reads it with plain Lua).
--
-- Effects (open / close / loop / travel / cast) are a list tried in order: a name of data/lib/chaos_vfx.lua (Vfx), a
-- name of data/lib/chaos_fx.lua (ChaosFx), or a stock CONST_ME number. The first one that exists is sent, so the
-- stock number at the end is what a client without the Chaos effect art shows.
-- Portal items are stock items of the base server (type teleport in items.xml, walkable); they are placed without a
-- destination and carry the action id below, the move event decides where a step leads.

-- stock CONST_ME numbers (TFS const.h): POFF 3, FIREAREA 7, TELEPORT 11, ENERGYHIT 12, MAGIC_BLUE 13, MAGIC_RED 14,
-- MAGIC_GREEN 15, MORTAREA 18, ICEAREA 42, STONES 45, HOLYAREA 50
local ME_POFF, ME_FIRE, ME_TELEPORT, ME_ENERGY, ME_MAGIC_BLUE, ME_RED, ME_GREEN = 3, 7, 11, 12, 13, 14, 15
local ME_DEATH, ME_ICE, ME_STONES, ME_HOLY = 18, 42, 45, 50

return {
	spellId = 254, -- spells_chaos.xml "Town Portal" (words "ash domh"); the cooldown shown on the action bar
	castMs = 3000, -- channel time; moving or taking damage interrupts it
	pollMs = 250, -- how often the channel checks for a step
	cooldownSeconds = 60, -- from the moment the portal opens (an interrupted or refused cast costs nothing)
	portalMinutes = 5, -- a pair closes after this, or when its owner walks back through the return portal
	loopMs = 2000, -- the style's loop effect on both portals while they are open
	partyCanUse = true, -- members of the owner's party (at the moment of the step) may use both portals
	aid = {field = 47810, back = 47811}, -- field portal (-> temple) and return portal (-> the spot of the cast)

	-- storages (Chaos.storage reserves 7101600 - 7101639)
	storage = {
		style = 7101600, -- selected style id (0 / -1 = the default)
		cooldown = 7101601, -- os.time() when the next portal may open
		storeOwnedBase = 7101610 -- + style id: 1 = the store style is owned (store styles have ids 1..29)
	},

	-- where the portal beside the caster goes (first free tile), then the return portal around the temple
	fieldOffsets = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1},
		{2, 0}, {-2, 0}, {0, 2}, {0, -2}},
	templeRadius = 4, -- rings 1..4 around the temple; many players' return portals share the temple

	castEffect = {"arcane_circle", ME_MAGIC_BLUE}, -- once per second on the caster while channelling
	interruptEffect = {ME_POFF},

	-- styles: id (stable, stored), key (stable, for the store / achievements), route:
	--   "default"     everyone has it
	--   "store"       bought once with Chaos Coins: shop_config.lua category "Portal Styles", unlock = "portal_<key>",
	--                 price there; owned per character (storeOwnedBase + id)
	--   "achievement" owned while the character has the achievement whose reward is {portal = {key = <key>}} in
	--                 achievements_data.lua (one achievement per style; checked by server/tests/townportal_test.lua)
	-- Each style has exactly one route: a store style is never an achievement reward and the other way round.
	styles = {
		{id = 0, key = "waygate", name = "Waygate", route = "default", item = 5023,
			desc = "A ring of blue force: the portal every character starts with.",
			open = {"teleport_in", ME_TELEPORT}, close = {"teleport_out", ME_POFF}, travel = {ME_TELEPORT}},

		-- store (Chaos Coins)
		{id = 1, key = "emberforge", name = "Emberforge Gate", route = "store", item = 29640,
			desc = "A gate of molten rock that spills embers.",
			open = {"infernal_seal", "fire_ring", ME_FIRE}, close = {"fire_explosion", ME_FIRE},
			loop = {"inferno_burst", ME_FIRE}, travel = {"fire_burst", ME_FIRE}},
		{id = 2, key = "rimeglass", name = "Rimeglass Gate", route = "store", item = 29641,
			desc = "A frame of blue ice that hums with cold.",
			open = {"frost_glyph", "frost_ripple", ME_ICE}, close = {"ice_shatter", "frost_burst", ME_ICE},
			loop = {"frost_ripple", ME_ICE}, travel = {"frost_nova", ME_ICE}},
		{id = 3, key = "gilded", name = "Gilded Gate", route = "store", item = 29630,
			desc = "A golden arch full of sunlight.",
			open = {"holy_seal", "holy_spiral", ME_HOLY}, close = {"solar_flash", "holy_cross", ME_HOLY},
			loop = {"holy_spiral", ME_HOLY}, travel = {"holy_hit", ME_HOLY}},
		{id = 4, key = "bloodmoon", name = "Bloodmoon Gate", route = "store", item = 29631,
			desc = "A red gate under a blood moon.",
			open = {"blood_rune", "blood_pact", ME_RED}, close = {"blood_nova", ME_RED},
			loop = {"blood_ring", ME_RED}, travel = {"blood_splash", ME_RED}},
		{id = 5, key = "verdant", name = "Verdant Gate", route = "store", item = 29632,
			desc = "A gate overgrown with living green.",
			open = {"grove_glyph", "poison_pentagram", ME_GREEN}, close = {"healing_bloom", "heal_sparkle", ME_GREEN},
			loop = {"heal_sparkle", ME_GREEN}, travel = {"px286_green", ME_GREEN}},
		{id = 6, key = "sanctum", name = "Sanctum Gate", route = "store", item = 29636,
			desc = "A white palace door with a red veil.",
			open = {"px586_white", "holy_cross", ME_HOLY}, close = {"px652_white", ME_HOLY},
			loop = {"arcane_aura", ME_MAGIC_BLUE}, travel = {"holy_hit", ME_HOLY}},

		-- achievements (achievements_data.lua reward = {portal = {key = ...}})
		{id = 31, key = "abyssal", name = "Abyssal Maw", route = "achievement", item = 29633,
			desc = "A violet maw held open by chained demons.",
			open = {"void_maw", "void_eye", ME_DEATH}, close = {"void_rift", "shadow_ring", ME_POFF},
			loop = {"void_eye", ME_DEATH}, travel = {"shade_appear", "shadow_smoke", ME_DEATH}},
		{id = 32, key = "riftwalker", name = "Riftwalker's Gate", route = "achievement", item = 27407,
			desc = "A torn doorway of rift light.",
			open = {"px03_arcane", "summon_portal", ME_ENERGY}, close = {"teleport_out", ME_POFF},
			loop = {"summon_portal", ME_ENERGY}, travel = {"blink_appear", ME_TELEPORT}},
		{id = 33, key = "hellmouth", name = "Hellmouth Gate", route = "achievement", item = 29635,
			desc = "A demon's jaw that burns at the edges.",
			open = {"infernal_seal", "fire_tornado", ME_FIRE}, close = {"dome_blast_fire", "fire_explosion", ME_FIRE},
			loop = {"shadow_flame", ME_FIRE}, travel = {"px197_crimson", ME_RED}},
		{id = 34, key = "hoarder", name = "Hoarder's Gate", route = "achievement", item = 29634,
			desc = "A royal gate of stolen gold.",
			open = {"aura_burst_gold", "holy_spiral", ME_HOLY}, close = {"loot_ray_legendary", ME_HOLY},
			loop = {"arcane_burst", ME_MAGIC_BLUE}, travel = {"ki_hit_gold", ME_HOLY}},
		{id = 35, key = "warbanner", name = "Warbanner Gate", route = "achievement", item = 29629,
			desc = "A siege gate of old stone.",
			open = {"stone_rise", "ground_slam", ME_STONES}, close = {"earth_spikes", "ground_slam", ME_STONES},
			loop = {"stone_ward", ME_STONES}, travel = {"blunt_smash", ME_STONES}},
		{id = 36, key = "gravecall", name = "Gravecall Gate", route = "achievement", item = 28013,
			desc = "A crypt door for those who have died often enough to know the way.",
			open = {"necro_seal", "necro_skull", ME_DEATH}, close = {"px633_indigo", "necro_skull", ME_DEATH},
			loop = {"shadow_cloud", ME_DEATH}, travel = {"px633_green", ME_DEATH}}
	}
}
