-- pinnacle_balance_config.lua (O667): the inputs and the limits of the pinnacle boss model, tools/pinnacle_model.py --check (CI).
-- Plain table, loaded with dofile. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls. server/README.md "Pinnacle bosses
-- (O667)" has the method and the tables.
--
-- The model (computed, not measured in game): four bosses, each planned for a character level (pinnacle_config.lua `refLevel`).
--   length    the median class (class_dps_model.py, through boss_length_model.py: the armour and resistance a boss keeps) kills the boss
--             alone in `seconds.solo` and five of them in `seconds.party`: the fight's health (pinnacle_config.lua `health`, the XML's)
--             is seconds x (players x damage x uptime - the boss's heal a second), and `perExtra` the party curve to five.
--   damage    the boss's hits (its XML attacks x the engine's level bonus 1 + 0.0015 x its level x the level pace, as the hunt model does)
--             and its marked attacks (boss_mechanics_config.lua: the share of max health of a telegraph x the share a player still
--             takes, the timed ones too) against the median class of the planned level (survival_model.py through guardian_model.py):
--             seconds to die with no healing, and the pressure (damage against healing).
--   fragments a whole set is four kinds, three from one content each and the keystone from any: the hours of top content for a set
--             and, with the unique's roll and its bad-luck count, for a unique.
return {
	-- O672 (owner 2026-11-19): the player's level cap is 2500, so no boss is shown, planned or opened at a level above it. The first
	-- version (O667) had 2000 / 2500 / 3000 / 3500 with planned levels 2000-2500; the ladder is now 1900 / 2100 / 2300 / 2500: even steps
	-- of 200 under the cap, so a capped character meets the last boss at its own level and the first is one the 1800-1900 characters of
	-- the waystone tier XII+ fragments can reach. Each fight is planned for the level it is shown at (`refLevel` = `level`) and opens
	-- 100 levels below it (`minLevel`, `openBelow`), as the first version did.
	levelCap = 2500,
	-- the planned fight
	seconds = {solo = 420, party = 300},
	players = 5,
	-- the damage lands this share of the time (the mechanics' own downtime is held by boss_mechanics_core.lua G.balance: the profile's
	-- `ref` is this fight, the health of the run is x its hpMult)
	uptime = 0.85,
	limitSeconds = 1200, -- pinnacle_config.lua minutes x 60
	-- the weakest class deals this share of the median (class_dps_model.py keeps every class within 25%): it finishes alone within
	-- `weakestShare` of the limit
	weakest = 0.75,
	weakestShare = 0.6,

	-- how the boss's hits split over the player's layers: melee (armour, block) / physical spell / elemental (absorbs)
	split = {melee = 0.5, physical = 0.1, element = 0.4},
	-- the share of the marked attacks a player still takes after moving (the telegraphs are dodgeable)
	marksTaken = 0.35,
	-- a Hex Effigy (the immobile ward of the adds) and the boss's heal a second: from the XML (healing defense)

	-- O698: the mechanics' health factor (boss_mechanics_core.lua G.balance, for the fight's size) keeps the planned kill time of every size
	-- inside `tolerance` (the model's own plan is the base of the factor, so the gap is the floor of the factor and the downtime's rounding);
	-- `partyDiffers`: a party's factor within this of the solo one is only accepted when the solo one still hits the plan
	factor = {tolerance = 0.01, partyDiffers = 0.002},

	-- tolerance of the committed numbers (health, party curve) against the derivation
	tolerance = {health = 0.015, perExtra = 0.02},

	-- limits of --check (the boss at its planned level, the median class)
	limits = {
		ladder = {1900, 2100, 2300, 2500},
		openBelow = 100,
		-- seconds to die with no healing, solo (the Omen guardian: 3-10, the rift guardians 1.2-16)
		burst = {min = 4.0, max = 13.0},
		-- the boss's damage against the median class's healing, solo: above it the healer loses without dodging, far below it the boss is
		-- only a wall of health (guardian_balance_config.lua pressure 0.55-1.15, Omen 0.7-1.35; a pinnacle is the harder fight)
		pressure = {min = 0.80, max = 1.40},
		-- a party of 5: the boss's damage x the damage curve on its target, against that player's healing (the party heals each other too)
		partyPressure = 1.75,
		-- the rise of the pressure from the first boss to the last: each one at least this much above the one before it (a higher
		-- level is a harder fight), at most `riseMax` x the first
		rise = 0.0, riseMax = 1.5
	},

	-- O690 (owner 2026-11-20, "pode por um teto sim"): the cap of one hit of a pinnacle boss on a player (pinnacle_config.lua hitCap; the rule is the
	-- rift guardian's, O478). The O685 live runs showed hits of 70 to 98% of a character's maximum health (casters of 15 to 17k health), the
	-- model's rolls reach 60 to 109% of the pool of the weakest classes (tools/pinnacle_model.py --hits). The numbers, and why:
	--   share      0.40 of the pool (the maximum health, plus the maximum mana under a mana shield) for every plain hit: the boss's spell and melee
	--              attacks, its adds, after every multiplier. It is the highest share that lets a character of full health take `survives` = 2 hits
	--              in a row with `left` = 20% of the pool still standing (2 x 0.40 + 0.20 = 1); no hit is a one-shot, a healer has a window.
	--              The lower end is the retention below: at 0.30 the weakest class keeps 0.42-0.66 of the boss's damage and the average 0.88-0.95
	--              (the cap starts to feel like a wall of health: the hits that remain are the small ones), at 0.40 0.56-0.84 and 0.93-0.99. The
	--              median class's biggest roll is 17-48% of its pool (21 to 48 with five), so the cap leaves its ordinary hits alone and cuts the tail.
	--   telegraph  0.60 for the marked attacks (ring, marks, lines, cone, half, eye, soak, channel: the scripted hit of a share of the victim's health,
	--              boss_mechanics.lua). Dodging is the point of a telegraph, so standing in it hurts more than a plain hit: 0.60 is the biggest
	--              share the profiles design (the Vhoss channel, 0.6; the Malgrath soak miss 0.55), so a solo fight is never cut by it and only
	--              what the party curve (x1.24 with five) adds on top is trimmed. It is still a cap: one marked hit never takes the whole pool.
	--              Not an exemption: the O685 live Tidal Collapse (101 hits, up to 72% of the health) was one of the one-shots.
	--              A marked hit and a plain hit in the same moment can still add up (0.6 + 0.4); both are avoidable or healed in between, and
	--              the lethal catch of the fight (pinnacle_config.lua catchLethal) stays under it.
	-- The model reads the cap as the damage it leaves (E[min(roll, cap)] / E[roll] of each attack, per class, rolls even between the XML's min and
	-- max) and the pressure and seconds to die of the median class are computed with it. The limits of --check:
	hitCap = {
		share = 0.40, telegraph = 0.60,
		survives = 2, left = 0.20, -- share x survives <= 1 - left
		telegraphMax = 0.65, -- the marked cap is above the plain one, at most this, and not under the biggest designed marked share
		-- the damage the cap leaves, per boss, solo and with five: the mean over the 21 classes at least `mean`, the hardest hit class at least `worst`
		retention = {mean = 0.90, worst = 0.50},
		-- with five, the number of classes whose biggest roll is over the plain cap: at least `atLeast` (a cap that touches nobody is no cap) and at most
		-- `atMost` of the 21 (it is the fight that is hard, not the hit)
		cuts = {atLeast = 5, atMost = 0.80}
	},

	-- O698: what the one boss video measured (O689 run 6, the five tester bots of O685 / O693 against the Ascended Malgrath; fight report and
	-- server console of the run, `damage_final` is the count behind every damage event, O697). tools/pinnacle_model.py --options reads it:
	-- the kill time of the bots against the median five, per boss, for three health choices. Measured, not modelled: one run, one boss
	measured = {
		boss = "ascended malgrath", players = 5, level = 1893,
		seconds = 79,           -- the boss came, the boss fell (the bar read 100% at 7 s)
		startHealth = 10134615, -- the boss's maximum at the start (12,704,600 x the solo factor 0.7977, O697)
		lost = 10139361,        -- the fall of its own health (the ledger)
		-- damage a second of each bot on the boss over 78 s, every event behind it (damage_final); dots are part of it
		perBot = {Deadeye = 56968, Elementalist = 33664, Juggernaut = 14656, Samurai = 13596, Illusionist = 10822},
		-- the same before the events a first hit registers (the damage pool, gems, supports, charms): the early tally
		early = {Deadeye = 19654, Elementalist = 12152, Juggernaut = 9442, Samurai = 8847, Illusionist = 6410},
		dots = {Deadeye = 623606, Juggernaut = 345841}, -- total damage of the fight that came as dots
		botSeconds = 78
	},

	-- the fragments: what the top content takes (minutes a clear, solo or a party) and the limits of --check. A waystone map of the
	-- top tiers and a rift of tier 15 are the size band of the biggest rift (12-15 minutes, rift_config.lua layout.sizes); the Omen
	-- guardian is its rift (the run, the climb to the guardian and its 5:18 kill, boss_length_model.py OMEN_SECONDS).
	minutes = {waystone = 15, rift = 13, omen = 12},
	hours = {
		-- hours of top content for a whole set (the three specific kinds in turn, the keystone along the way): a set is an evening or
		-- two of the top content, not a week; and not less than the 2.5 hours of a hunt of the band
		set = {min = 2.5, max = 7.0},
		-- the keystone's own rate: one an hour of mixed top content at most (it is a roll on every clear)
		keystonePerHour = 1.5,
		-- hours of top content for the exclusive unique of one boss (sets x kills to the unique), with the bad-luck count
		unique = {min = 8, max = 45}
	}
}
