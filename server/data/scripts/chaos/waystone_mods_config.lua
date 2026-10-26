-- Waystone modifiers (waystone_mods.lua, waystone_mods_core.lua; server/README.md "Waystone modifiers"): every number.
-- Plain table: ChaosWaystoneMods.config = dofile("data/scripts/chaos/waystone_mods_config.lua"). Lua 5.1 / LuaJIT and 5.3.
--
-- Owner 2026-10-23: "treat the waystones as the maps of an ARPG: they take modifiers, each one a debuff for the
-- player or a buff for the monsters, with an experience and loot bonus". So a waystone has a rarity by its modifiers:
-- Normal (none), Magic (at most one prefix and one suffix), Rare (at most three of each). Prefixes make the map's monsters
-- (or its boss) stronger, suffixes make it worse for the players. Every modifier adds item quantity, item rarity,
-- experience (its own `reward`, as on the rift keys) and waystone drop chance (`perMod.waystone`). The modifiers, their
-- ranges, tiers I-V and groups are the rift keys' (rift_config.lua mods, copied by key below), so a modifier does in a
-- waystone map what it does in a rift; the effects run through rift_core.lua (R.effects, R.monsterHit, R.monsterTaken).
-- The rift-only ones (packs, goblin, coffer, twin guardians, double loot, time, lives, one brood, the guardian's nova)
-- are left out: a waystone map is a fixed map of the base server, not a generated rift.
local rift = dofile("data/scripts/chaos/rift_config.lua")

local PREFIX = {"vitality", "brutality", "haste", "elites", "reflection", "warding", "keen", "ironhide", "festering",
	"spiteglass", "emberbrand", "frostbrand", "stormbrand", "cinder", "breach", "dread"}
local SUFFIX = {"withering", "parched", "blight", "searing", "flaying", "sapping", "scorched", "rimefloor", "veilstorm"}
-- texts that name the rift
local TEXT = {dread = "The map's boss has +%d%% health and damage"}

local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = type(v) == "table" and copy(v) or v
	end
	return out
end

local mods = {}
for _, list in ipairs({{PREFIX, "prefix"}, {SUFFIX, "suffix"}}) do
	for _, key in ipairs(list[1]) do
		for _, m in ipairs(rift.mods) do
			if m.key == key then
				local d = copy(m)
				d.side = list[2]
				d.text = TEXT[key] or d.text
				mods[#mods + 1] = d
			end
		end
	end
end

return {
	enabled = true,

	-- custom attribute of a waystone with modifiers ("key:value,...", rift_core.lua R.encodeMods); a waystone without it is
	-- Normal. The tier stays the item's (waystone_tiers_config.lua tiers).
	attribute = "ws_mods",
	key = {maxMods = 6}, -- read by R.decodeMods

	mods = mods,

	-- rarity by modifiers: {name, most prefixes, most suffixes}. A waystone with more than magic allows is Rare.
	rarities = {
		{name = "Normal", prefix = 0, suffix = 0},
		{name = "Magic", prefix = 1, suffix = 1},
		{name = "Rare", prefix = 3, suffix = 3}
	},

	-- how many modifiers a roll gives: {count, weight}. magic: an Orb of Awakening gives one, Upheaval on a Magic one
	-- rerolls 1-2; rare: a drop or an Orb of Upheaval on a Rare one; gilding: an Orb of Gilding (alchemy-like: 4+)
	count = {
		magic = {{1, 60}, {2, 40}},
		rare = {{3, 30}, {4, 35}, {5, 25}, {6, 10}},
		gilding = {{4, 50}, {5, 35}, {6, 15}}
	},

	-- a waystone that drops (waystone_tiers.lua retierDrops): its rarity {name, weight}. Inside a run, by its tier; a
	-- Tier I outside the maps is always Normal.
	dropRarity = {{"Normal", 55}, {"Magic", 30}, {"Rare", 15}},

	-- every modifier adds this much on top of its own reward (percent). waystone: more waystones drop in the map (each
	-- dropped waystone has this chance of a second one; the boss's next-tier waystone too)
	perMod = {waystone = 12},

	-- caps of the summed bonuses (percent; up to six modifiers, the rift keys' caps are for three); modifier tiers IV / V
	-- raise them as on the keys (modTiers.capRaise)
	bonusCap = {quantity = 120, rarity = 110, experience = 80, waystone = 72},
	modTiers = rift.modTiers, -- I-V and the window per tier: 1-5 I-III, 6-10 I-IV, 11-15 II-V
	maxTier = 15,

	-- the effects' own numbers (rift_config.lua blocks, the same in both)
	brands = rift.brands,
	keen = rift.keen,
	festering = rift.festering,
	cinder = rift.cinder,
	breach = {count = 2, delayMs = 800, spread = 2, maxAlive = 40}, -- maxAlive: breach monsters alive per map at once
	ground = rift.ground,
	veilstorm = rift.veilstorm,
	-- Elites: the chance a map monster comes as magic (else rare) is elite x (value / 100) on top of the natural roll
	elites = {base = 8, rareShare = 30, runBase = 12}, -- runBase: the chance (percent) every map monster of a run comes as magic or rare, with no modifier

	-- a run's modifiers stay while players are in its map; it ends this many seconds after the base's own timer (30
	-- minutes) or when the next waystone opens the map
	runSeconds = 31 * 60,
	-- a waystone used on the device is the one the window's teleport takes for this long (seconds)
	chosenSeconds = 300,
	tickMs = 1000
}
