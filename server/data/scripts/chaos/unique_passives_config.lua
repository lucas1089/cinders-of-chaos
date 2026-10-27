-- unique_passives_config.lua: the numbers of the unique item passives (O278; server/README.md "Unique passives",
-- rules in unique_passives_core.lua, texts in unique_passives_text.lua, engine glue in unique_passives.lua).
--
-- Every unique item has ONE passive that changes how a build plays: a conversion, a trigger, a rule with a price. The
-- passive is keyed by the unique's item id (`passives`), works only for the class lines it names (`lines`; the item can
-- be worn by every class its own equip rule allows, the passive just sleeps for the others) and only while the
-- item is worn as a real unique copy (custom attribute chaos_unique). Its numbers are the family's defaults
-- (`families`) with the entry's own on top, so an entry lists only what differs. The tooltip line is made from the same
-- numbers (tools/gen_unique_specs.py writes it into the unique's description), so a number changed here is changed on
-- the item too after one run of the generator; tests/unique_passives_test.lua fails when the two disagree.
--
-- Limits that hold for every passive (the "safety" of the design):
--   * maxActive passives are active at once and only one of each family: the strongest (highest item level) wins. A
--     character wearing ten uniques picks its five.
--   * the product of every damage multiplier is clamped to [dealtFloor, dealtCap]; the product of every damage taken
--     multiplier to [takenFloor, takenCeil]. The bonus part of a damage multiplier is scaled by pvpScale against
--     players; extra hits (extra, nova, riposte, spread) only ever hit wild monsters, never players or summons.
--   * every proc has an internal cooldown (icdMs) and the damage of a proc is a proc: it starts no other passive (the
--     glue's guard, and the core refuses a hit marked proc).
--   * a price paid in health (selfCost, costPct) never kills: it needs health above minHealth % and takes at most the
--     health above it.
--   * nothing here creates an item or gold; healing is capped per second (feast.capPerSec) or per tick (mend).
-- Prices every entry may carry on top of its family's own: healLess (healing you receive is that % lower), takenMore
-- (damage you take is that % higher), dealtLess (your direct hits deal that % less).

ChaosUniquePassivesConfig = {
	maxActive = 5,
	pvpScale = 1 / 3, -- the bonus part of a damage multiplier against players
	dealtCap = 1.8, dealtFloor = 0.5,
	takenCeil = 1.5, takenFloor = 0.4, -- the least damage taken: 40% (never more than 60% less from all passives)
	wardHitMax = 4, -- a ward gain from one hit: at most this % of the maximum health
	mendMaxPct = 3, -- a mend heals at most this % of a target's maximum health per tick
	healCapPct = 5, -- a heal from one hit (critrule): at most this % of the maximum health
	refreshMs = 3000, -- the equipment check (an item that left a slot without a move event)
	crowdCacheMs = 500, -- how long a count of the monsters near a character is kept
	afflictKeep = 120, -- afflicted monsters remembered per character (spread)
	markKeep = 8, -- marks per character, whatever the family says
	tickMs = 1000, -- the clock of the ward fade, mend and the equipment check
	labelMs = 1500, -- no text label of the same passive more often than this

	-- limits of tools/unique_passives_model.lua --check (the expected power gain of a passive: damage dealt x survivability)
	model = {
		minGain = 1.03, maxGain = 1.55, -- one passive, on the line it is made for
		bestFiveMin = 1.35, bestFiveMax = 3.2, -- the best five (one per family) of a class line in a level band
		bands = {{1, 100}, {101, 400}, {401, 900}, {901, 1600}, {1601, 99999}},
	},

	-- player line letters of `lines` (docs/CLASSES.md): the base class of each class
	lines = {W = "warrior", R = "ranger", M = "mystic", T = "thief", K = "monk", N = "necromancer", P = "templar"},
	lineOrder = {"warrior", "ranger", "mystic", "thief", "monk", "necromancer", "templar"},

	-- family defaults (an entry overrides any of them). Numbers are percent unless the name says Ms / PerLevel.
	families = {
		-- convert: share% of your physical damage is dealt as `elem` and deals bonus% more; other elements deal other% less
		convert = {elem = "fire", share = 50, bonus = 25, other = 15},
		-- lowlife: below `at`% health +bonus% damage; above malusAt% health -malus% damage
		lowlife = {at = 35, bonus = 40, malusAt = 70, malus = 15},
		-- overflow: at or above `at`% mana +bonus%; at or below malusAt% mana -malus%
		overflow = {at = 70, bonus = 35, malusAt = 30, malus = 15},
		-- opener: side "above": a target at `at`% health or more takes +bonus%, at malusAt% or less -malus%;
		-- side "below" (a finisher): at `at`% or less +bonus%, at malusAt% or more -malus%
		opener = {side = "above", at = 90, bonus = 60, malusAt = 25, malus = 10},
		-- focus: each consecutive hit on one target +perStack% (up to max stacks), reset after resetMs or a new target;
		-- the first hit on a new target deals first% less
		focus = {perStack = 7, max = 6, resetMs = 3000, first = 15},
		-- statscale: +bonusPer% damage for every `per` points of `stat` above `from`, at most cap%. stat: maxMana,
		-- maxHealth, magicLevel, shield (shielding skill), speed, level. origin: any, melee, ranged or spell
		statscale = {stat = "maxMana", from = 0, per = 100, bonusPer = 1, cap = 40, origin = "any"},
		-- critrule: critical hits +crit% damage, other hits -plain%; heal% of a critical hit heals you (healIcdMs apart)
		critrule = {crit = 45, plain = 10, heal = 0, healIcdMs = 1500},
		-- crowd: mode "pack": +per% per other monster within radius of you (up to max), -alone% when there is none;
		-- mode "duel": +bonus% with none but the target, -malus% with `many` or more
		crowd = {mode = "pack", radius = 3, per = 6, max = 5, alone = 15, bonus = 35, malus = 20, many = 3},
		-- extra: a hit of `origin` sends pct% of itself at up to `targets` other monsters within radius of the target
		-- (as `elem`, else the hit's type), icdMs apart; costs costPct% of the maximum `cost` (health: only above
		-- minHealth% health, mana: while it has it)
		extra = {origin = "ranged", pct = 55, targets = 1, radius = 3, cost = "health", costPct = 0.5, minHealth = 35,
			icdMs = 600},
		-- ward: onHit% of the damage you deal and onKill% of your maximum health per kill become a ward (at most cap% of
		-- the maximum health) that absorbs damage before the health and fades decayPct% of the cap a second once
		-- decayAfterMs have passed since the last gain; reflect% of what it absorbs from a monster is dealt back
		ward = {onHit = 8, onKill = 4, cap = 25, decayAfterMs = 6000, decayPct = 20, reflect = 0, healLess = 30},
		-- spread: a monster that dies with your `elem` damage over time on it (a tick of yours within recentMs) passes
		-- it to `targets` monsters within radius: share% of its last tick for `ticks` ticks tickMs apart, once
		spread = {elem = "poison", targets = 3, radius = 2, share = 70, ticks = 4, tickMs = 1000, recentMs = 4000,
			dealtLess = 12},
		-- stacks: each kill (trigger "kill") or critical hit (trigger "crit") adds a stack (up to max, windowMs after the
		-- last): +perStack% damage dealt and +takenPerStack% damage taken per stack
		stacks = {trigger = "kill", perStack = 6, max = 5, windowMs = 6000, takenPerStack = 4},
		-- feast: a kill heals (res "health") or restores (res "mana") onKill% of the maximum, at most capPerSec% a second
		feast = {res = "health", onKill = 3, capPerSec = 12, healLess = 40},
		-- hitcap: a single hit from a monster takes at most cap% of the maximum health
		hitcap = {cap = 30, healLess = 25},
		-- immunity: immune to the damage over time of `kind` (fire, poison, bleed, energy, ice, drown, death); the
		-- direct damage of that element (physical for bleed) is more% higher
		immunity = {kind = "fire", more = 15},
		-- riposte: a monster hit of minHit% of the maximum health or more is answered with pct% of it as `elem` (at most
		-- capBase + capPerLevel x level), icdMs apart
		riposte = {elem = "physical", pct = 60, minHit = 3, icdMs = 2500, capBase = 60, capPerLevel = 1.5},
		-- panic: a monster hit that would leave you under below% health makes you take reduce% less damage for ms and
		-- blocks your healing meanwhile; icdMs apart
		panic = {below = 30, reduce = 45, ms = 5000, icdMs = 60000},
		-- manashield: share% of the damage monsters deal is paid from mana instead, never below reserve% of the maximum
		manashield = {share = 30, reserve = 5, dealtLess = 10},
		-- mend: every tickMs, while you fought within fightMs, you and your party within radius heal heal% of their maximum
		mend = {heal = 1.5, radius = 3, tickMs = 2000, fightMs = 5000, healLess = 30},
		-- mark: your hits mark the target for ms (up to max at once); marked monsters take +bonus% from you, others -unmarked%
		mark = {max = 3, bonus = 30, ms = 6000, unmarked = 12},
		-- nova: on "kill", "crit" or "hurt" (a monster hit of minHit% of the maximum health or more) a nova of `elem`
		-- hits up to targets monsters within radius for base + perLevel x level, icdMs apart; costs selfCost% of the
		-- maximum health (only above minHealth% health)
		nova = {on = "kill", elem = "fire", base = 60, perLevel = 1.2, radius = 2, targets = 6, icdMs = 3000, minHit = 5,
			selfCost = 0.5, minHealth = 35},
		-- minionPact (Necromancer): minions deal hit% more and have health% more health; your own spells deal own% less
		minionPact = {hit = 30, health = 40, own = 25},
	},

	-- the unique items: [item id] = {lv = the item's level (checked against its description), name, family, lines, ...}
	passives = {
	[28693] = {lv = 6, name = "First Quarry", family = "opener", lines = "R", side = "above", at = 90, bonus = 30, malusAt = 25, malus = 0}, -- Fletcher's First Sheath
	[2403] = {lv = 10, name = "Light Fingers", family = "stacks", lines = "TK", trigger = "crit", perStack = 7, max = 4, windowMs = 5000, takenPerStack = 0}, -- Cutpurse's Sliver
	[23719] = {lv = 10, name = "Wick Surplus", family = "overflow", lines = "MN", at = 70, bonus = 20, malusAt = 25, malus = 5}, -- Cinder-Wick Wand
	[7438] = {lv = 12, name = "Fen Warden's Mark", family = "mark", lines = "R", max = 2, bonus = 20, ms = 6000, unmarked = 0}, -- Fenwatch Longbow
	[8900] = {lv = 12, name = "Small Fires", family = "nova", lines = "MN", on = "kill", elem = "fire", base = 1, perLevel = 2, targets = 4, icdMs = 3000, selfCost = 0}, -- Primer of Small Fires
	[10292] = {lv = 12, name = "Pilgrim's Resolve", family = "lowlife", lines = "WPK", at = 40, bonus = 69, malusAt = 85, malus = 0}, -- Ashen Pilgrim's Blade
	[27651] = {lv = 14, name = "Reed Whistle", family = "extra", lines = "R", origin = "ranged", pct = 40, targets = 1, costPct = 0.3, icdMs = 800}, -- Hollow-Reed Quiver
	[40009] = {lv = 14, name = "Vigil Knot", family = "ward", lines = "K", onHit = 5, onKill = 3, cap = 12, healLess = 0}, -- Vigil-Knot Wraps
	[8601] = {lv = 15, name = "Winter Bite", family = "convert", lines = "WP", elem = "ice", share = 40, bonus = 41, other = 8}, -- Hatchet of the First Winter
	[10302] = {lv = 15, name = "Bell Toll", family = "crowd", lines = "PK", mode = "pack", per = 5, max = 4, alone = 8}, -- Tallow-Bell Mace
	[2648] = {lv = 18, name = "Road Rations", family = "feast", lines = "WRT", res = "health", onKill = 4.3, capPerSec = 12, healLess = 15}, -- Wanderer's Leggings
	[10291] = {lv = 20, name = "Pilgrim's Pyre", family = "nova", lines = "MPN", on = "hurt", elem = "fire", base = 19, perLevel = 2, minHit = 4, targets = 4, icdMs = 5000, selfCost = 0}, -- Hood of the Roaming Pyre
	[25412] = {lv = 20, name = "Short Ways Home", family = "statscale", lines = "RTK", stat = "speed", from = 200, per = 10, bonusPer = 1.4, cap = 20, origin = "any"}, -- Pathfinder's Treads
	[10294] = {lv = 25, name = "Lantern Ward", family = "hitcap", lines = "WP", cap = 25, healLess = 10}, -- Lantern-Ward Buckler
	[10502] = {lv = 25, name = "Second Dawn", family = "panic", lines = "ALL", below = 30, reduce = 40, ms = 4000, icdMs = 90000}, -- Band of the Second Dawn
	[40010] = {lv = 26, name = "Door-Hinge Counter", family = "riposte", lines = "K", elem = "physical", pct = 89, minHit = 3, icdMs = 3000, capPerLevel = 2.2}, -- Chapel-Iron Knuckles
	[2402] = {lv = 28, name = "Silver Whisper", family = "opener", lines = "T", side = "above", at = 90, bonus = 40, malusAt = 25, malus = 5}, -- Moonlit Shiv
	[11393] = {lv = 30, name = "Moth to Flame", family = "mend", lines = "MPK", heal = 2.9, tickMs = 2500, radius = 3, healLess = 15}, -- Moth-Lantern Pendant
	[26185] = {lv = 30, name = "Knuckle Spark", family = "critrule", lines = "KT", crit = 76, plain = 8}, -- Cinder Knuckle Band
	[21692] = {lv = 35, name = "Gutter Mercy", family = "ward", lines = "WPK", onHit = 6, onKill = 3, cap = 15, healLess = 20}, -- Gutter-Saint's Mail
	[27694] = {lv = 38, name = "Wind-Borne", family = "crowd", lines = "R", mode = "duel", bonus = 50, malus = 12, radius = 3, many = 3}, -- Gravewind Quiver
	[13873] = {lv = 40, name = "Fen Frost", family = "convert", lines = "R", elem = "ice", share = 50, bonus = 20, other = 10}, -- Hoarfen Bow
	[22690] = {lv = 40, name = "Widow's Patience", family = "focus", lines = "TKW", perStack = 6, max = 5, first = 10}, -- Widowmaker
	[11374] = {lv = 50, name = "Scarab Swarm", family = "spread", lines = "T", elem = "poison", targets = 2, radius = 2, share = 97, ticks = 4, dealtLess = 8}, -- Carrion Scarab Amulet
	[19390] = {lv = 50, name = "Damned Flight", family = "convert", lines = "RT", elem = "fire", share = 60, bonus = 20, other = 10}, -- Hellspear of the Damned
	[2412] = {lv = 60, name = "Crypt Whisper", family = "critrule", lines = "T", crit = 67, plain = 10}, -- Nightfang Katana
	[3972] = {lv = 60, name = "Evil Eye", family = "mark", lines = "MNR", max = 3, bonus = 25, unmarked = 8}, -- Bonelord's Gaze
	[8849] = {lv = 60, name = "One Shot", family = "opener", lines = "R", side = "above", at = 95, bonus = 75, malusAt = 40, malus = 12}, -- Gallowsbolt Crossbow
	[10296] = {lv = 60, name = "Skull Pall", family = "immunity", lines = "TRK", kind = "poison", more = 12}, -- Pall of Skulls
	[21693] = {lv = 60, name = "Horn-Bind", family = "stacks", lines = "WP", trigger = "kill", perStack = 7, max = 4, takenPerStack = 3}, -- Hornbinder Ring
	[2496] = {lv = 70, name = "Hornsworn Oath", family = "hitcap", lines = "WP", cap = 18, healLess = 20}, -- Hornsworn Helm
	[3961] = {lv = 70, name = "Lich's Grasp", family = "spread", lines = "N", elem = "death", targets = 3, radius = 2, share = 94, ticks = 4, dealtLess = 10}, -- Lichfang Staff
	[8858] = {lv = 70, name = "Stormcall", family = "extra", lines = "R", origin = "ranged", elem = "energy", pct = 50, targets = 2, radius = 3, cost = "health", costPct = 0.5, icdMs = 700}, -- Stormcaller Recurve
	[11426] = {lv = 70, name = "Notched Edge", family = "spread", lines = "WT", elem = "bleed", targets = 3, radius = 2, share = 97, ticks = 4, dealtLess = 10}, -- Gorecleaver
	[27288] = {lv = 70, name = "Tiny Fangs", family = "riposte", lines = "WTK", elem = "physical", pct = 74, minHit = 3, icdMs = 2500, capPerLevel = 1.9}, -- Maw Treads
	[41640] = {lv = 70, name = "One Spark", family = "panic", lines = "ALL", below = 25, reduce = 50, ms = 5000, icdMs = 75000}, -- Ring of the Last Ember
	[2440] = {lv = 80, name = "Last Words", family = "opener", lines = "WK", side = "below", at = 30, bonus = 55, malusAt = 80, malus = 10}, -- Executioner's Reckoning
	[8892] = {lv = 80, name = "Cinder Coat", family = "immunity", lines = "WPKTR", kind = "fire", more = 15}, -- Cindermail Coat
	[10314] = {lv = 80, name = "Claw of Fire", family = "convert", lines = "WPT", elem = "fire", share = 50, bonus = 37, other = 12}, -- Cinderclaw Band
	[13760] = {lv = 80, name = "Seam of the World", family = "nova", lines = "MN", on = "crit", elem = "death", base = 50, perLevel = 1.2, targets = 5, icdMs = 3000, selfCost = 0.5}, -- Riftcaller
	[27647] = {lv = 80, name = "Road of Blood", family = "statscale", lines = "WTR", stat = "speed", from = 200, per = 10, bonusPer = 1, cap = 25, origin = "any"}, -- Bloodstep Boots
	[27692] = {lv = 80, name = "Warm Print", family = "mend", lines = "PKM", heal = 2.7, tickMs = 2000, radius = 3, healLess = 20}, -- Emberveil Greaves
	[41641] = {lv = 80, name = "Never-Cooling Coal", family = "statscale", lines = "WPK", stat = "maxHealth", per = 200, bonusPer = 2.9, cap = 35, origin = "melee", healLess = 15}, -- Heart of Cinders
	[3975] = {lv = 90, name = "Fire Asks Permission", family = "ward", lines = "WP", onHit = 6, onKill = 5, cap = 20, reflect = 40, healLess = 25}, -- Emberwarden
	[7379] = {lv = 90, name = "Grinding Wheel", family = "crowd", lines = "WK", mode = "pack", per = 7, max = 5, alone = 15}, -- Bonegrinder
	[10510] = {lv = 90, name = "Grave Vow", family = "lowlife", lines = "TKN", at = 30, bonus = 98, malusAt = 75, malus = 15}, -- Widow's Last Vow
	[11395] = {lv = 90, name = "Crimson Tide", family = "critrule", lines = "WT", crit = 74, plain = 12, heal = 3}, -- Bloodmoon Edge
	[27228] = {lv = 90, name = "Hollow Bark", family = "immunity", lines = "RMN", kind = "poison", more = 15}, -- Shroud of the Hollow Wood
	[27693] = {lv = 90, name = "Berry Juice", family = "spread", lines = "TR", elem = "poison", targets = 3, radius = 2, share = 94, ticks = 4, dealtLess = 6}, -- Nightshade Leggings
	[41642] = {lv = 90, name = "Borrowed Beat", family = "feast", lines = "WNP", res = "health", onKill = 6.4, capPerSec = 19, healLess = 40}, -- Heartbleed Pendant
	[7462] = {lv = 100, name = "Burning Crown", family = "nova", lines = "MPW", on = "kill", elem = "fire", base = 60, perLevel = 1.2, targets = 6, icdMs = 3000, selfCost = 0.5}, -- Crown of Cinders
	[10301] = {lv = 100, name = "Reaper's Reach", family = "extra", lines = "WP", origin = "melee", pct = 50, targets = 2, radius = 2, cost = "health", costPct = 0.6, icdMs = 700}, -- Harvester of Sorrows
	[16111] = {lv = 100, name = "Screaming Bolts", family = "critrule", lines = "R", crit = 74, plain = 12}, -- Hellspite Arbalest
	[22474] = {lv = 100, name = "Answering Voice", family = "overflow", lines = "MN", at = 75, bonus = 40, malusAt = 35, malus = 15}, -- Tome of Whispers
	[23590] = {lv = 100, name = "Argument Ender", family = "opener", lines = "PK", side = "below", at = 35, bonus = 60, malusAt = 85, malus = 12}, -- Gorehammer
	[24851] = {lv = 100, name = "Void Pool", family = "manashield", lines = "MNK", share = 35, reserve = 5, dealtLess = 10}, -- Tear of the Void
	[26133] = {lv = 100, name = "Soundless Step", family = "crowd", lines = "TRK", mode = "duel", bonus = 63, malus = 20, radius = 3, many = 3}, -- Voidwalker Boots
	[26756] = {lv = 100, name = "Rime Heart", family = "convert", lines = "W", elem = "ice", share = 60, bonus = 25, other = 15}, -- Shard of the Long Winter
	[27231] = {lv = 100, name = "Burial Linen", family = "minionPact", lines = "N", hit = 30, health = 40, own = 20}, -- Mortis Cowl
	[27295] = {lv = 100, name = "Remembering Hand", family = "riposte", lines = "WPK", elem = "death", pct = 73, minHit = 3, icdMs = 2500, capPerLevel = 1.8}, -- Wraithplate
	[10318] = {lv = 110, name = "Reflected Fear", family = "hitcap", lines = "WP", cap = 15, healLess = 25}, -- Obsidian Aegis
	[25418] = {lv = 110, name = "New Mouth", family = "extra", lines = "PK", origin = "melee", pct = 55, targets = 2, radius = 2, cost = "health", costPct = 0.6, icdMs = 700}, -- Mawmaker
	[27230] = {lv = 110, name = "Hum of the Dead", family = "mark", lines = "R", max = 3, bonus = 30, unmarked = 10}, -- Doomtide Longbow
	[27232] = {lv = 110, name = "Lich-Queen's Linen", family = "minionPact", lines = "N", hit = 35, health = 45, own = 25}, -- Mortis Shroud
	[2466] = {lv = 120, name = "Held Lightning", family = "convert", lines = "PK", elem = "energy", share = 55, bonus = 34, other = 12}, -- Aetherbound Plate
	[8209] = {lv = 120, name = "Hungry Blade", family = "feast", lines = "WTN", res = "health", onKill = 7.1, capPerSec = 21, healLess = 45}, -- Soulreaper
	[22423] = {lv = 120, name = "Carver's Patience", family = "ward", lines = "MN", onHit = 8, onKill = 4, cap = 25, healLess = 30}, -- Effigy Carver's Idol
	[24790] = {lv = 120, name = "Ninth-Circle Bite", family = "spread", lines = "MP", elem = "fire", targets = 3, radius = 2, share = 94, ticks = 4, dealtLess = 6}, -- Fangs of the Ninth Circle
	[27675] = {lv = 120, name = "Looks Back", family = "mark", lines = "MNT", max = 3, bonus = 35, unmarked = 10}, -- Visage of the Pale King
	[28115] = {lv = 120, name = "Footfall Debt", family = "stacks", lines = "RT", trigger = "crit", perStack = 10, max = 5, windowMs = 5000, takenPerStack = 3}, -- Snarewalker Greaves
	[29571] = {lv = 120, name = "Rattling Cage", family = "statscale", lines = "MN", stat = "maxMana", per = 150, bonusPer = 1.4, cap = 35, origin = "spell"}, -- Soulshackle Scepter
	[29868] = {lv = 120, name = "Unfound", family = "lowlife", lines = "TMN", at = 40, bonus = 92, malusAt = 80, malus = 12}, -- Veil of the Wraith
	[8925] = {lv = 130, name = "Dying Star", family = "convert", lines = "WP", elem = "fire", share = 60, bonus = 33, other = 15}, -- Cinderbrand Axe
	[15413] = {lv = 130, name = "Paid In Full", family = "riposte", lines = "WP", elem = "physical", pct = 70, minHit = 3, icdMs = 2000}, -- Spitethorn Bulwark
	[28020] = {lv = 130, name = "Between Stars", family = "immunity", lines = "MNK", kind = "energy", more = 15}, -- Voidscale Legguards
	[29866] = {lv = 140, name = "Last-Light Shroud", family = "mend", lines = "MPK", heal = 2.7, tickMs = 2000, radius = 3, healLess = 20}, -- Duskweaver Wand
	[2500] = {lv = 150, name = "Living Vine", family = "riposte", lines = "RTW", elem = "earth", pct = 73, minHit = 3, icdMs = 2500, capPerLevel = 1.8}, -- Thornwake Jerkin
	[7384] = {lv = 150, name = "Ninth Hall Quench", family = "lowlife", lines = "WP", at = 35, bonus = 94, malusAt = 70, malus = 15}, -- Emberfall Blade
	[7890] = {lv = 150, name = "Slow Burn", family = "spread", lines = "RT", elem = "fire", targets = 3, radius = 2, share = 94, ticks = 4, dealtLess = 6}, -- Fusewright's Charm
	[7891] = {lv = 150, name = "Down Never Back", family = "statscale", lines = "WTK", stat = "speed", from = 200, per = 10, bonusPer = 1, cap = 30, origin = "any"}, -- Ashwalker Treads
	[8881] = {lv = 150, name = "Giant's Pyre", family = "hitcap", lines = "WP", cap = 15, healLess = 25}, -- Pyreheart Mantle
	[18403] = {lv = 150, name = "Last Voice", family = "nova", lines = "MP", on = "kill", elem = "holy", base = 70, perLevel = 1.3, targets = 6, icdMs = 3000, selfCost = 0.6}, -- Brand of the Ashen Choir
	[18406] = {lv = 150, name = "Parting Undergrowth", family = "statscale", lines = "RT", stat = "speed", from = 200, per = 8, bonusPer = 1, cap = 30, origin = "ranged"}, -- Thornwake Striders
	[21691] = {lv = 150, name = "Never-Stopping Flower", family = "spread", lines = "TR", elem = "poison", targets = 4, radius = 2, share = 100, ticks = 4, dealtLess = 6}, -- Rotbloom Phial
	[27646] = {lv = 150, name = "Briar Shot", family = "extra", lines = "R", origin = "ranged", elem = "earth", pct = 55, targets = 2, radius = 3, cost = "health", costPct = 0.6, icdMs = 700}, -- Thornwake Longbow
	[28691] = {lv = 150, name = "Prick and Heal", family = "feast", lines = "RTW", res = "health", onKill = 6, capPerSec = 18, healLess = 35}, -- Thornwake Loop
	[15453] = {lv = 180, name = "Oath Under the Banner", family = "mend", lines = "PKMW", heal = 2.7, tickMs = 2000, radius = 4, healLess = 20}, -- Oathkeeper's Standard
	[27652] = {lv = 180, name = "Drinks First", family = "ward", lines = "ALL", onHit = 12, onKill = 4, cap = 28, healLess = 40}, -- Vein of the Unsated
	[2133] = {lv = 200, name = "Last Hall Ember", family = "stacks", lines = "WTK", trigger = "kill", perStack = 8.4, max = 6, takenPerStack = 4}, -- Heart of the Descent
	[27667] = {lv = 200, name = "Conductor's Rest", family = "nova", lines = "PMN", on = "hurt", elem = "holy", base = 60, perLevel = 1.2, minHit = 5, targets = 6, icdMs = 4000, selfCost = 0}, -- Choirmaster's Circlet
	[27251] = {lv = 220, name = "Kneeling Smoke", family = "mend", lines = "PMK", heal = 3, tickMs = 2500, radius = 4, healLess = 15}, -- Reliquary Censer
	[2129] = {lv = 250, name = "One Tooth per Pact", family = "minionPact", lines = "N", hit = 30, health = 40, own = 20}, -- Hollowpack Fang Chain
	[2357] = {lv = 250, name = "Nine Boons", family = "stacks", lines = "WTKR", trigger = "kill", perStack = 6, max = 9, takenPerStack = 2}, -- Sigil of the Ninth Room
	[24718] = {lv = 250, name = "Pack Smells Kin", family = "mark", lines = "RN", max = 3, bonus = 30, unmarked = 10}, -- Hollowpack Mask
	[24741] = {lv = 250, name = "Covenant Furs", family = "crowd", lines = "RWN", mode = "pack", per = 7, max = 5, alone = 12}, -- Hollowpack Hide
	[26808] = {lv = 250, name = "Fed Bond", family = "feast", lines = "NMR", res = "mana", onKill = 7.5, capPerSec = 22, dealtLess = 8, healLess = 10}, -- Hollowpack Bond
	[27668] = {lv = 250, name = "Cold Light", family = "manashield", lines = "MNKP", share = 40, reserve = 5, dealtLess = 10}, -- Hollowglass Diadem
	[7402] = {lv = 300, name = "Put the Tyrant Down", family = "opener", lines = "WP", side = "below", at = 30, bonus = 70, malusAt = 85, malus = 15}, -- Pyre Cleaver
	[7404] = {lv = 300, name = "First of a Pair", family = "focus", lines = "T", perStack = 8, max = 6, first = 12}, -- Duskstalker Fang
	[7418] = {lv = 300, name = "Where the Fang Was", family = "extra", lines = "T", origin = "melee", pct = 60, targets = 1, radius = 2, cost = "health", costPct = 0.5, icdMs = 500}, -- Duskstalker Sting
	[11301] = {lv = 300, name = "Blades Slide Off", family = "riposte", lines = "TK", elem = "physical", pct = 70, minHit = 3, icdMs = 2000}, -- Duskstalker Jerkin
	[11304] = {lv = 300, name = "Rooftop Run", family = "statscale", lines = "TKR", stat = "speed", from = 200, per = 8, bonusPer = 1, cap = 30, origin = "any"}, -- Duskstalker Breeches
	[25175] = {lv = 300, name = "Sworn on a Wound", family = "stacks", lines = "WP", trigger = "kill", perStack = 7.8, max = 5, takenPerStack = 4}, -- Bloodsworn Hauberk
	[25410] = {lv = 300, name = "Smiles When You Bleed", family = "critrule", lines = "WT", crit = 81, plain = 10, heal = 4}, -- Bloodsworn Visage
	[27249] = {lv = 300, name = "Dust Does Not Hear", family = "critrule", lines = "T", crit = 81, plain = 10}, -- Duskstalker Tabi
	[27390] = {lv = 300, name = "Bloodless Body", family = "hitcap", lines = "MNKP", cap = 15, healLess = 25}, -- Stillheart Robe
	[27658] = {lv = 300, name = "Altar Quench", family = "lowlife", lines = "W", at = 40, bonus = 98, malusAt = 75, malus = 15}, -- Bloodsworn Greataxe
	[28100] = {lv = 300, name = "Tightening Plates", family = "feast", lines = "WP", res = "health", onKill = 7.1, capPerSec = 21, healLess = 45}, -- Bloodsworn Legplates
	[28101] = {lv = 300, name = "Red Prints", family = "spread", lines = "WT", elem = "bleed", targets = 3, radius = 2, share = 96, ticks = 4, dealtLess = 10}, -- Bloodsworn Treads
	[28106] = {lv = 300, name = "Light That Is Not There", family = "overflow", lines = "MN", at = 70, bonus = 40, malusAt = 30, malus = 15}, -- Mirrorweave Circlet
	[28107] = {lv = 300, name = "Spun Twice", family = "ward", lines = "MNP", onHit = 8, onKill = 5, cap = 25, healLess = 30}, -- Mirrorweave Robe
	[28108] = {lv = 300, name = "Heartbeat Early", family = "focus", lines = "MR", perStack = 7, max = 6, first = 12}, -- Mirrorweave Skirt
	[28109] = {lv = 300, name = "Two Sets of Footprints", family = "nova", lines = "MNP", on = "hurt", elem = "energy", base = 70, perLevel = 1.2, minHit = 5, targets = 6, icdMs = 4000, selfCost = 0}, -- Mirrorweave Slippers
	[28111] = {lv = 300, name = "Every Page Shows the Reader", family = "extra", lines = "MN", origin = "spell", pct = 50, targets = 2, radius = 3, cost = "mana", costPct = 3, icdMs = 700}, -- Mirrorweave Codex
	[28112] = {lv = 300, name = "Swallowed Light", family = "crowd", lines = "TK", mode = "duel", bonus = 64, malus = 20, radius = 3, many = 3}, -- Duskstalker Cowl
	[28125] = {lv = 300, name = "No Front No Back", family = "critrule", lines = "MR", crit = 81, plain = 10}, -- Mirrorweave Band
	[7894] = {lv = 400, name = "Same Storm Twice", family = "manashield", lines = "MN", share = 35, reserve = 5, dealtLess = 10}, -- Cinderstorm Kilt
	[7899] = {lv = 400, name = "Never Burnt", family = "immunity", lines = "MNP", kind = "fire", more = 12}, -- Cinderstorm Mantle
	[8890] = {lv = 400, name = "Names of the Burned", family = "spread", lines = "N", elem = "death", targets = 3, radius = 3, share = 80, ticks = 5, dealtLess = 6}, -- Lichbound Robe
	[24637] = {lv = 400, name = "Court Mage's Pace", family = "statscale", lines = "WKP", stat = "magicLevel", per = 8, bonusPer = 1, cap = 40, origin = "any"}, -- Cinderstorm Sandals
	[27666] = {lv = 400, name = "Hisses When Drawn", family = "convert", lines = "W", elem = "fire", share = 50, bonus = 28, other = 12}, -- Cinderstorm Wand
	[28023] = {lv = 400, name = "Hand That Never Held", family = "focus", lines = "KTW", perStack = 8, max = 6, first = 10}, -- Knuckles of the Unbound
	[28041] = {lv = 400, name = "Court That Burned", family = "convert", lines = "P", elem = "ice", share = 50, bonus = 37, other = 12}, -- Cinderstorm Signet
	[28049] = {lv = 400, name = "Crack in Time", family = "nova", lines = "TKR", on = "crit", elem = "energy", base = 70, perLevel = 1.2, targets = 6, icdMs = 3000, selfCost = 0.5}, -- Splintered Instant
	[28126] = {lv = 400, name = "Alive and Hungry", family = "feast", lines = "N", res = "health", onKill = 6.4, capPerSec = 19, healLess = 40}, -- Lichbound Phylactery
	[29471] = {lv = 400, name = "Rain of Sparks", family = "nova", lines = "MN", on = "crit", elem = "energy", base = 80, perLevel = 1.1, targets = 6, icdMs = 3000, selfCost = 0.5}, -- Cinderstorm Crown
	[29573] = {lv = 400, name = "Eyes Go Dark", family = "mark", lines = "NM", max = 3, bonus = 35, unmarked = 10}, -- Lichbound Mask
	[29575] = {lv = 400, name = "Cord of Hair", family = "minionPact", lines = "N", hit = 35, health = 50, own = 25}, -- Lichbound Kilt
	[26198] = {lv = 450, name = "Walked In Walked Out", family = "panic", lines = "ALL", below = 25, reduce = 50, ms = 5000, icdMs = 60000}, -- Pilgrim's Reliquary
	[2404] = {lv = 600, name = "Quiet Work", family = "critrule", lines = "T", crit = 66, plain = 10, heal = 3}, -- Gravewhisper Stiletto
	[15407] = {lv = 600, name = "One Bolt per Pocket", family = "extra", lines = "R", origin = "ranged", pct = 55, targets = 2, radius = 3, cost = "health", costPct = 0.6, icdMs = 600}, -- Gallows Coat
	[27474] = {lv = 600, name = "Hangman's Rope", family = "opener", lines = "R", side = "above", at = 95, bonus = 90, malusAt = 50, malus = 15}, -- Gallows Arbalest
	[28114] = {lv = 600, name = "Standing Still", family = "focus", lines = "RM", perStack = 8, max = 6, resetMs = 4000, first = 15}, -- Gallows Leggings
	[28690] = {lv = 600, name = "Small Patient Fire", family = "mend", lines = "PMK", heal = 3, tickMs = 2500, radius = 3, healLess = 15}, -- Emberwake Locket
	[29470] = {lv = 600, name = "Face Unseen", family = "mark", lines = "RT", max = 4, bonus = 35, unmarked = 12}, -- Gallows Hood
	[36659] = {lv = 650, name = "Saint Walked On", family = "lowlife", lines = "K", at = 30, bonus = 98, malusAt = 70, malus = 15}, -- Grasp of the Pyre Saint
	[27696] = {lv = 750, name = "Shattered Volley", family = "extra", lines = "R", origin = "ranged", pct = 55, targets = 2, radius = 3, cost = "health", costPct = 0.6, icdMs = 600}, -- Quiver of Shattered Skies
	[2124] = {lv = 800, name = "Every Curse First", family = "spread", lines = "MN", elem = "death", targets = 4, radius = 3, share = 80, ticks = 5, dealtLess = 6}, -- Eye of the Hexmaw
	[2498] = {lv = 800, name = "Expected Throne", family = "hitcap", lines = "WP", cap = 15, healLess = 25}, -- Crown of the Last Sovereign
	[2504] = {lv = 800, name = "Creak and Hold", family = "hitcap", lines = "WPK", cap = 15, healLess = 25}, -- Marrowforged Greaves
	[7422] = {lv = 800, name = "Broken Shields", family = "opener", lines = "WP", side = "below", at = 30, bonus = 70, malusAt = 85, malus = 15}, -- Gravewarden's Verdict
	[8865] = {lv = 800, name = "Warm and Wrong", family = "mend", lines = "MPKN", heal = 2.9, tickMs = 2500, radius = 4, healLess = 15}, -- Shroud of the Ash-Sister
	[27403] = {lv = 800, name = "Oath in Stone", family = "riposte", lines = "WPK", elem = "holy", pct = 70, minHit = 3, icdMs = 2000}, -- Ashwarden Seal
	[29559] = {lv = 800, name = "Everything Behind Lived", family = "ward", lines = "WP", onHit = 8, onKill = 5, cap = 28, reflect = 50, healLess = 30}, -- Ashwarden Bulwark
	[29560] = {lv = 800, name = "Down They Stayed", family = "statscale", lines = "WPK", stat = "shield", per = 15, bonusPer = 1, cap = 40, origin = "melee"}, -- Ashwarden Visor
	[29561] = {lv = 800, name = "Ash in the Seams", family = "immunity", lines = "WPKTR", kind = "fire", more = 12}, -- Ashwarden Cuirass
	[26765] = {lv = 900, name = "Gallows Beam", family = "mark", lines = "R", max = 3, bonus = 40, unmarked = 12}, -- Moonlit Gallows Bow
	[27663] = {lv = 900, name = "Glow at the Knots", family = "convert", lines = "R", elem = "fire", share = 60, bonus = 30, other = 15}, -- Ember-Lashed Quiver
	[2123] = {lv = 1000, name = "Last Coal of a Sovereign", family = "nova", lines = "WPM", on = "kill", elem = "fire", base = 90, perLevel = 1.2, targets = 7, icdMs = 3000, selfCost = 0.6}, -- Cinderheart Signet
	[2171] = {lv = 1000, name = "Seer's Last Sight", family = "nova", lines = "MNT", on = "crit", elem = "energy", base = 90, perLevel = 1.2, targets = 7, icdMs = 3000, selfCost = 0.6}, -- Eye of the Unbroken Storm
	[2408] = {lv = 1000, name = "Drinks Before You", family = "ward", lines = "ALL", onHit = 14, onKill = 5, cap = 30, healLess = 45}, -- Sanguine Crescent
	[2493] = {lv = 1000, name = "Nothing Inside", family = "overflow", lines = "MN", at = 75, bonus = 55, malusAt = 40, malus = 20}, -- Hollow Crown of Morvane
	[2646] = {lv = 1200, name = "Endless Road", family = "statscale", lines = "WRTK", stat = "speed", from = 200, per = 6, bonusPer = 1, cap = 40, origin = "any"}, -- Greaves of the Endless Road
	[27686] = {lv = 1200, name = "Never Fewer Than You Need", family = "extra", lines = "R", origin = "ranged", pct = 54, targets = 3, radius = 3, cost = "health", costPct = 0.7, icdMs = 600}, -- Nightglass Quiver
	[2411] = {lv = 1250, name = "Opens Once After Dark", family = "spread", lines = "T", elem = "poison", targets = 4, radius = 3, share = 94, ticks = 5, dealtLess = 14}, -- Nightbloom Stiletto
	[8931] = {lv = 1300, name = "Judges of Ash", family = "opener", lines = "WTKP", side = "below", at = 30, bonus = 80, malusAt = 85, malus = 18}, -- Ashfall Verdict
	[24744] = {lv = 1400, name = "Eight Pyres Before", family = "nova", lines = "MN", on = "kill", elem = "fire", base = 100, perLevel = 1.2, targets = 8, icdMs = 3000, selfCost = 0.7}, -- Diadem of the Ninth Pyre
	[27695] = {lv = 1400, name = "Gale Sleeve", family = "stacks", lines = "R", trigger = "crit", perStack = 11, max = 6, windowMs = 5000, takenPerStack = 3}, -- Sleeve of Ashen Gales
	[40011] = {lv = 1400, name = "Wind Over an Empty Grave", family = "critrule", lines = "K", crit = 66, plain = 12, heal = 4}, -- Gravewind Talons
	[6391] = {lv = 1500, name = "Hundred Years of Tide", family = "hitcap", lines = "WP", cap = 15, healLess = 25}, -- Rampart of Grey Tides
	[25881] = {lv = 1500, name = "Wyrm Quench", family = "spread", lines = "WTKP", elem = "bleed", targets = 4, radius = 3, share = 80, ticks = 5, dealtLess = 6}, -- Wyrmgrave Cleaver
	[15408] = {lv = 1550, name = "Each Ember a Crown", family = "nova", lines = "WPMN", on = "hurt", elem = "fire", base = 100, perLevel = 1.2, minHit = 5, targets = 8, icdMs = 4000, selfCost = 0}, -- Crown of Ten Thousand Cinders
	[25880] = {lv = 1550, name = "Seat Kept Warm", family = "lowlife", lines = "WP", at = 35, bonus = 97, malusAt = 75, malus = 18}, -- Hollow Throne Claymore
	[22417] = {lv = 1600, name = "Strand of the Storm", family = "extra", lines = "R", origin = "ranged", elem = "energy", pct = 54, targets = 3, radius = 3, cost = "health", costPct = 0.7, icdMs = 600}, -- Stormherald's Recurve
	[25174] = {lv = 1600, name = "Oath Outlives the Pyre", family = "panic", lines = "ALL", below = 22, reduce = 55, ms = 5000, icdMs = 55000}, -- Pyre-Sworn Cuirass
	[27676] = {lv = 1600, name = "One More", family = "stacks", lines = "R", trigger = "kill", perStack = 6.7, max = 8, windowMs = 7000, takenPerStack = 3}, -- Quiver of the Last Volley
	[28708] = {lv = 1650, name = "Road Turns to Ash", family = "statscale", lines = "WTK", stat = "speed", from = 200, per = 6, bonusPer = 1, cap = 40, origin = "melee"}, -- Greaves of the Final Ash
	[29572] = {lv = 1650, name = "Unwritten Chapter", family = "overflow", lines = "MN", at = 75, bonus = 55, malusAt = 40, malus = 20}, -- Codex of the Unwritten End
	[2495] = {lv = 1700, name = "Spat Back", family = "immunity", lines = "WPKTRMN", kind = "death", more = 15}, -- Legguards of Unmaking
	[14334] = {lv = 1800, name = "One Note per Blow", family = "crowd", lines = "WTKP", mode = "pack", per = 9, max = 6, alone = 18}, -- Maul of the Sunken Choir
	[25886] = {lv = 1800, name = "Tide Brings Something", family = "mark", lines = "R", max = 4, bonus = 45, unmarked = 15}, -- Gravetide Arbalest
	[27196] = {lv = 1800, name = "Everyone Bows", family = "manashield", lines = "MNKP", share = 45, reserve = 5, dealtLess = 12}, -- Veil of the Quiet Throne
	[22516] = {lv = 1900, name = "Cut Loose", family = "critrule", lines = "WTKRMN", crit = 72, plain = 14, heal = 0}, -- Band of the Severed Star
	[27193] = {lv = 1900, name = "Carry Two", family = "focus", lines = "T", perStack = 10, max = 6, first = 15}, -- Misericorde of the Pale Vow
	[28379] = {lv = 1900, name = "Sun That Kept Its Shape", family = "convert", lines = "R", elem = "holy", share = 70, bonus = 35, other = 15}, -- Hollow Sun Quiver
	[25882] = {lv = 1950, name = "Embers Answer", family = "convert", lines = "WP", elem = "fire", share = 70, bonus = 35, other = 15}, -- Emberhowl Greataxe
	[2656] = {lv = 2000, name = "Choir Sang On", family = "minionPact", lines = "N", hit = 45, health = 60, own = 30}, -- Vestments of the Hollow Choir
	[40012] = {lv = 2000, name = "Morning That Never Came", family = "ward", lines = "K", onHit = 14, onKill = 6, cap = 32, reflect = 40, healLess = 40}, -- Dawnless Gauntlets
	[25885] = {lv = 2100, name = "Nothing It Watches Walks", family = "opener", lines = "R", side = "above", at = 95, bonus = 100, malusAt = 50, malus = 18}, -- Wake-Heron Longbow
	[28050] = {lv = 2100, name = "Not Allowed to Set", family = "extra", lines = "R", origin = "ranged", pct = 53, targets = 3, radius = 3, cost = "health", costPct = 0.7, icdMs = 550}, -- Quiver of Fallen Constellations
	[2472] = {lv = 2200, name = "Dawn Broke Here", family = "panic", lines = "WP", below = 22, reduce = 60, ms = 6000, icdMs = 60000}, -- Bastion of the Last Dawn
	[25884] = {lv = 2200, name = "Hour Without End", family = "mend", lines = "WPK", heal = 3, tickMs = 2500, radius = 4, healLess = 15}, -- Bellringer of the Last Vigil
	[22691] = {lv = 2400, name = "Silence Left Behind", family = "feast", lines = "ALL", res = "health", onKill = 7.8, capPerSec = 23, healLess = 50}, -- Choirless Pendant
	},
}

return ChaosUniquePassivesConfig
