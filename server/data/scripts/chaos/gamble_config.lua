-- The Gambler (Mordecai Ashwager): sealed equipment for gold, the rarity hidden until it is bought. Every number of the
-- system is here. Engine part: gamble.lua; pure logic: gamble_core.lua (tests: server/tests/gamble_test.lua); NPC:
-- data/npc/Mordecai Ashwager.xml (installed by server/tools/install_gamble.py); client game_gamble; overview:
-- server/README.md "The Gambler".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then /reload scripts (or restart).

local C = {}

C.enabled = true
C.opcode = 199 -- ChaosOpcodes.gamble (chaos_constants.lua); client game_gamble
C.requestMs = 300 -- one window request per player per 300 ms (Chaos.limited)
C.staffGroup = 4 -- /gamble needs this group or higher

-- player storages 7101900 - 7101909 (server/README.md "Storage keys"):
--   +0 the window the stock below belongs to, +1 the level and +2 the vocation id it was made for (frozen for the
--   window), +3 the sold slots (bit i-1 = slot i), +4 the early refreshes bought in this window
C.storage = 7101900

-- ------------------------------------------------------------------ the refresh schedule
-- The stock is new every `hours` hours at fixed times: 00:00, 04:00, 08:00, 12:00, 16:00 and 20:00. utcOffsetHours = nil
-- uses the server's own time zone (the clock of the machine, as every other daily and weekly reset); a number pins it
-- (-3 = UTC-3, the owner's clock, whatever the machine is set to). With the machine on UTC and nil here the refreshes
-- come at 21:00, 01:00, 05:00, ... UTC-3. `hours` must divide 24.
C.refresh = {hours = 4, utcOffsetHours = nil}

-- ------------------------------------------------------------------ the stock
-- size: pieces per stock (one stock per character and window, from a seed of the character and the window: the same
-- after a relog or a restart, nothing stored per piece). The slot of each piece is drawn with these weights; a slot
-- with no base the character can use is drawn again.
C.stock = {
	size = 14, seed = 7717,
	slots = {weapon = 3, armor = 2, helmet = 2, legs = 2, boots = 2, shield = 1, amulet = 1, ring = 1},
	order = {"weapon", "shield", "helmet", "armor", "legs", "boots", "amulet", "ring"} -- also the display order
}

-- the item level of a piece: the gate is the item level a kill of a monster of the character's level gives
-- (ChaosItemMods.sourceLevel, tier `tier`: the drops' own curve, never higher), the piece rolls between gate - spread
-- and the gate
C.itemLevel = {tier = "normal", spread = 6}

-- the base type: among the pool entries of the slot the character can use (the installed movements.xml and weapons.xml:
-- vocation and level; no charges, no duration, no unique, gear only) with lv <= the character's level, the `choices`
-- with the highest lv. lv is the level the base belongs to: its required level, or the level band of an unrestricted
-- stock piece.
C.base = {choices = 4, dedupe = true}

-- the pool: {id, lv} per slot (ids of the base server's items; names in the comments). Never a transmog set look
-- (transmog_config.lua sets: those looks come only from their own source; tests/transmog_test.lua checks it).
C.pool = {
	weapon = {
		{2398, 1}, {2386, 1}, {2456, 1}, -- mace, axe, bow
		{2190, 7}, {2182, 7}, {2191, 13}, {2186, 13}, -- wand of vortex, snakebite rod, wand of dragonbreath, moonlight rod
		{7385, 20}, {2423, 20}, {2430, 25}, {2189, 26}, {2181, 26}, -- crimson sword, clerical mace, knight axe, wand of cosmic energy, terra rod
		{2392, 30}, {2445, 35}, {8920, 37}, {8912, 37}, {8857, 40}, -- fire sword, crystal mace, wand of starstorm, springsprout rod, silkweaver bow
		{7412, 45}, {2446, 45}, {7427, 45}, {8855, 50}, {7383, 50}, -- butcher's axe, pharaoh sword, chaos mace, composite hornbow, relic sword
		{7389, 60}, {7415, 60}, {7384, 60}, {18409, 65}, {18412, 65}, -- heroic axe, cranial basher, mystic blade, wand of everblazing, glacial rod
		{8858, 70}, {7418, 70}, {7434, 75}, {7429, 75}, {2400, 80}, {8854, 80}, -- elemental bow, nightmare blade, royal axe, blessed sceptre, magic sword, warsinger bow
		{8930, 100}, {8928, 100}, {8852, 100}, {26756, 100}, {26757, 100}, -- emerald sword, obsidian truncheon, the devileye, frozen wand, venom rod
		{8924, 110}, {8931, 120}, {8927, 120}, {8851, 130}, {27650, 150}, {27649, 150}, -- hellforged axe, the epiphany, dark trinity mace, royal crossbow, jungle wand, jungle rod
		{22400, 250}, {22406, 250}, {22412, 250}, {22418, 250}, {27665, 250}, {27671, 250}, -- umbral master blade / axe / mace / bow, eldritch wand / rod
		{27204, 300}, {27205, 300}, {27206, 300}, {27199, 300}, {27198, 300}, {27197, 300}, -- falcon longsword / battleaxe / mace / bow / wand / rod
		{27377, 400}, {27380, 400}, {27381, 400}, {27383, 400}, {27385, 400}, {27386, 400}, -- soulcutter, souleater, soulcrusher, soulbleeder, soultainter, soulhexer
		{27458, 600}, {27462, 600}, {27460, 600}, {27471, 600}, {27476, 600}, {27479, 600}, -- sanguine blade / hatchet / cudgel / bow / coil / rod
		{29883, 1000}, {29885, 1000}, {29887, 1000}, {29874, 1000}, {29866, 1000} -- Dawnforged Blade / Chopper / Mace, Seraphic Bleeder, Myst Regalia Wand
	},
	shield = {
		{2509, 1}, {2175, 1}, {2516, 20}, {8900, 30}, {2519, 35}, {8901, 40}, -- steel shield, spellbook, dragon shield, enlightenment, crown shield, warding
		{2536, 50}, {8902, 50}, {8903, 60}, {2520, 70}, {2514, 80}, {8918, 80}, -- medusa shield, mind control, lost souls, demon shield, mastermind shield, dark mysteries
		{8905, 100}, {22423, 120}, {15413, 130}, {18410, 150}, {16112, 150}, -- rainbow shield, umbral spellbook, ornate shield, prismatic shield, ancient arcana
		{27653, 250}, {22424, 250}, {27202, 300}, {28111, 300}, -- eldritch shield, umbral master spellbook, falcon shield, vigils spellbook
		{29559, 400}, {29572, 400}, {29882, 1000}, {29865, 1000} -- Deathlord Shield, Soulbinder Tome, Dawnforged Shield, Myst Regalia Spellbook
	},
	helmet = {
		{2457, 1}, {8820, 1}, {2491, 20}, {7903, 25}, {2475, 30}, {2498, 50}, {9778, 80}, -- steel helmet, mage hat, crown helmet, terra hood, warrior helmet, royal helmet, yalahari mask
		{12645, 100}, {26766, 100}, {26761, 100}, {18403, 150}, {18398, 150}, -- elite draken helmet, varruth helmet, netherwave helmet, prismatic helmet, gill gugel
		{29470, 220}, {27227, 230}, {27667, 230}, {27668, 230}, {27196, 300}, {29471, 300}, -- hellstalker visor, terra helmet, eldritch cowl / hood, falcon coif, dreadfire headpiece
		{29560, 400}, {29567, 400}, {29573, 400}, {29878, 1000}, {29869, 1000}, {29861, 1000} -- Deathlord, Haloed, Soulbinder, Dawnforged, Seraphic, Myst Regalia
	},
	armor = {
		{2463, 1}, {8819, 1}, {2476, 25}, {8870, 25}, {8891, 35}, {2487, 35}, -- plate armor, magician's robe, knight armor, spirit cloak, paladin armor, crown armor
		{7884, 50}, {2466, 50}, {2492, 60}, {8877, 60}, {8867, 75}, {8869, 75}, {9776, 80}, -- terra mantle, golden armor, dragon scale mail, lavos armor, dragon robe, greenwood coat, yalahari armor
		{8888, 100}, {8881, 100}, {8890, 100}, {12643, 100}, {18404, 120}, {18399, 150}, {15407, 150}, -- master archer's, fireborn giant, robe of the underworld, royal scale robe, prismatic, gill coat, depth lorica
		{15406, 200}, {25186, 200}, {25190, 200}, {27295, 230}, {27660, 270}, {27690, 270}, {27691, 270}, -- ornate chestplate, firesoul tabard, firemind raiment, ghost chestplate, eldritch cuirass, dawnfire sherwani, midnight tunic
		{28099, 300}, {28107, 300}, {28113, 300}, {29561, 400}, {29568, 400}, {29574, 400}, -- embersage, vigils, shadewalker, Deathlord, Haloed, Soulbinder
		{29879, 1000}, {29870, 1000}, {29862, 1000} -- Dawnforged Plate, Seraphic Tabard, Myst Regalia Mantle
	},
	legs = {
		{2647, 1}, {2477, 25}, {8923, 30}, {2488, 35}, {7885, 40}, {2470, 60}, {9777, 80}, -- plate legs, knight legs, ranger legs, crown legs, terra legs, golden legs, yalahari leg piece
		{26768, 100}, {26763, 100}, {26776, 100}, {15409, 130}, {18405, 150}, {27287, 180}, {15412, 185}, -- varruth, netherwave, felsinger, depth ocrea, prismatic, soulful, ornate
		{27664, 250}, {27692, 250}, {27693, 250}, {28100, 300}, {28108, 300}, -- eldritch breeches, dawnfire pantaloons, midnight sarong, embersage legs, vigils legs
		{29562, 350}, {29569, 350}, {29575, 400}, {27470, 500}, {27475, 500}, -- Deathlord, Haloed, Soulbinder, sanguine legs / greaves
		{29880, 1000}, {29871, 1000}, {29863, 1000} -- Dawnforged, Seraphic, Myst Regalia
	},
	boots = {
		{2643, 1}, {7886, 35}, {2195, 40}, {11117, 70}, {11118, 70}, {12646, 80}, {24637, 80}, -- leather boots, terra boots, boots of haste, crystal, dragon scale, draken boots, oriental shoes
		{26769, 100}, {26777, 100}, {26764, 100}, {15410, 150}, {18406, 150}, {27647, 150}, {27648, 150}, -- varruth, felsinger, netherwave, depth calcei, prismatic, makeshift, make-do
		{27211, 220}, {27249, 220}, {28101, 300}, {28115, 300}, {28109, 300}, -- cobra boots, winged boots, embersage, shadewalker, vigils
		{29563, 400}, {29570, 400}, {29576, 400}, {27478, 500}, {27481, 500}, -- Deathlord, Haloed, Soulbinder, sanguine boots / galoshes
		{29881, 1000}, {29872, 1000}, {29864, 1000} -- Dawnforged, Seraphic, Myst Regalia
	},
	amulet = {
		{26807, 30}, {11374, 50}, {21691, 150}, {27652, 180}, {27251, 220}, {27403, 230}, {27215, 250}, -- foxtail, beetle, shrunken head, exotic, rainbow, lion, cobra
		{28126, 300}, {28022, 400}, {28040, 400}, {28048, 400}, {29889, 1000}, {29876, 1000}, {29867, 1000} -- forbidden, Astro, Arodis, Mercurial, Dawnforged, Seraphic, Myst Regalia
	},
	ring = {
		{28691, 100}, {28125, 300}, {28023, 400}, {28041, 400}, {28049, 400}, -- ring of temptation, forbidden ring, Astro Ring (x2), Mercurial Ring
		{29890, 1000}, {29877, 1000}, {29868, 1000} -- Dawnforged, Seraphic, Myst Regalia
	}
}

-- ------------------------------------------------------------------ prices
-- gold for a piece of item level L: straight lines between these {item level, gold} points, x the slot's multiplier,
-- rounded down to `round`. An armour piece costs about 18% of an hour of hunting at the character level whose kills
-- give that item level (the hunting model of professions_config.lua balance; tests/gamble_test.lua checks every level
-- 8-1500 stays between `balance.minShare` and `balance.maxShare`). A gold sink: a whole stock of 14 costs about two and
-- a half hours of hunting, so nobody buys every crate of every window.
C.price = {
	curve = {{1, 1500}, {4, 3000}, {5, 3600}, {12, 8300}, {18, 13000}, {22, 20000}, {36, 56000}, {54, 97000},
		{67, 150000}, {74, 300000}, {90, 850000}, {106, 1100000}, {118, 1350000}, {123, 1500000}, {136, 1650000},
		{150, 1800000}},
	slot = {weapon = 1.3, armor = 1.15, shield = 1.0, helmet = 1.0, legs = 1.0, boots = 0.9, amulet = 1.1, ring = 1.1},
	round = 100
}
C.balance = {
	minShare = 0.08, maxShare = 0.35,
	-- hunting gold per hour by character level (professions_config.lua C.balance.hunting; server/README.md "Respec")
	hunting = {{8, 19000}, {40, 83000}, {100, 358839}, {300, 881866}, {500, 5548330}, {1000, 9519711}}
}

-- early refresh (a new stock before the 4-hour mark): the price is `mult` x the price of an armour piece at the gate,
-- doubled for every earlier one in the same window, at most `max` per window; 0 turns it off. A new stock also clears
-- the sold marks (each piece is still paid in full).
C.reroll = {max = 3, mult = 0.5, growth = 2}

-- ------------------------------------------------------------------ the rarity roll (at the purchase, after the gold)
-- The loot layer's own roll (loot.lua, the same API monster drops and the rift / raid / goblin rewards use):
-- best of `draws` ChaosLoot.stockRarity(), raised to at least `floor`, then ChaosLoot.upgradeRarity(tier, r, find),
-- capped at maxRarity. With these numbers the roll is a magic monster's gear drop that is never plain: every piece has a
-- rarity (a normal monster's gear drop has none 58% of the time, a magic one's 52%), Common 61.9%, Uncommon 11.6%,
-- Rare 8.1%, Epic 5.4%, Legendary or better 13.0% (12.2% of a normal monster's gear drops, 13.0% of a magic one's: no
-- more often than from monsters), the top at Divine (2.2%; Phantasmal and above only from monsters). The exact table
-- is ChaosGambleCore.odds (in the window and in server/README.md). No item find applies.
C.odds = {draws = 1, floor = 1, tier = "magic", find = 1, maxRarity = 10}
-- players within 8 tiles see "<name> opened a [Divine] ..." from this rarity on (0 = never)
C.announceFrom = 10

-- ------------------------------------------------------------------ the NPC
-- placed next to the temple of every town in `towns` (ids; the main town is 1) on the first free tile of `offsets`
-- (none of the other temple NPCs, portals and the Great Brazier use these), at startup after them. Buying and the
-- early refresh need the Gambler within `range` tiles; the window opens anywhere (Economy > The Gambler) to look.
C.npc = {
	name = "Mordecai Ashwager", range = 4, towns = {1}, delayMs = 3000,
	offsets = {{-5, -2}, {5, -2}, {-5, 2}, {5, 2}, {-1, -5}, {1, 5}, {-6, -3}, {6, -3}, {-6, 3}, {6, 3}}
}

return C
