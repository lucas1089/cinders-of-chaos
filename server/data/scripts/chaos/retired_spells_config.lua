-- retired_spells_config.lua: the numbers and the list of the retired-spell clean-up at login (retired_spells_core.lua,
-- retired_spells.lua; tests/retired_spells_test.lua; server/README.md "Retired spells (O145)").
--
-- names: the Chaos names of the stock spells tools/patch_spell_cap.py retires (CAP entries with no class) and of the three
-- cure-retirement spells (retire_cure_spells.py). A character that learned one keeps the row in player_spells (the engine
-- never checks it); the login forgets it so the row is not dead data. The test checks the list against patch_spell_cap.py.
-- notices: a class lost a spell that it did not learn by a row (every Chaos class spell is needlearn="0"), so the player
-- cannot tell from the spellbook what went. Each notice is told once per character (storage `storage`, the notice
-- version): the text is the English key of i18n_strings.lua (pt-BR there).
return {
	storage = 7100205, -- the highest notice version told (next to the classes' 7100200-7100204)
	version = 1,
	delayMs = 4000, -- the notice goes out this long after the login (the login messages are done by then)
	names = {
		"Deep Mending", "Call Thrall", "Cinder Fan", "Stormlance", "Thunder Lance", "Infernal Heart", "Lance of the Grave",
		"Skinchanger's Guise", "Galeborne Stride", "Shatterfrost", "Quakeburst", "Greater Glacier Fan", "Shroud of Shadows",
		"Fading Step", "Crossfire Hex", "Wildwood Ruin", "Greater Phantom Javelin", "Dread", "Ruinous Cleave", "Reaver's Spin",
		"Circle of Mending", "Kindred Mend", "Gravetouch", "Arc Bolt", "Ember Lash", "Unveil", "Heartwood Embrace", "Earthrend",
		"Cyclone Hurl", "Frostbite", "Thornlash", "Endless Rime", "Storm Crown's Wrath", "Bramble Fan", "Glacier Fan",
		"Dawnbolt", "Martial Communion", "Shielding Communion", "Mending Communion", "Arcane Communion", "Warhorse Rush",
		"Smoulder Brand", "Hex of Withering", "Galvanic Mark", "Rending Mark", "Blackroot Venom", "Glare of Dawn",
		"Hammerfall Palm", "Skyfang", "Greater Ember Lash", "Greater Arc Bolt", "Greater Frostbite", "Greater Thornlash",
		"Supreme Ember Lash", "Supreme Arc Bolt", "Supreme Frostbite", "Supreme Thornlash", "Warlord's Resolve", "Second Wind",
		"Greater Second Wind", "Gravity Snare", "Riftbolt", "Sunder Guard", "Bog Splatter", "Rime Breath", "Arcane Stitch",
		"Static Sting", "Searing Gust", "Duelist's Oath",
		-- retire_cure_spells.py (their ids went to Tautstring, Ironhold and Wildstride)
		"Hawkeye", "Bulwark", "Windrunner"
	},
	notices = {
		{
			name = "Galeborne Stride", level = 20, since = "2026-10-23",
			-- Mystic, Elementalist, Thief, Ninja, Samurai, Monk, Shadowfist, Iron Sage, Necromancer, Lich, Bone Lord
			vocations = {1, 5, 11, 12, 13, 17, 18, 19, 20, 21, 22},
			text = "Galeborne Stride was retired. Fleetfoot and Vigil of Haste give the same haste and every class has them. "
				.. "Take it off your hotbar and helper."
		}
	}
}
