-- exercise_config.lua: the numbers and lists of the exercise (training) weapons (server/README.md "Training weapons").
-- Pure data, loaded with  ChaosExerciseConfig = dofile("data/scripts/chaos/exercise_config.lua").
-- Rules: exercise_core.lua (server/tests/exercise_test.lua). Engine glue: exercise_training.lua.
--
-- The base server has 21 exercise weapons (3 charge tiers x sword, axe, club, bow, rod, wand, shield), each open to
-- the stock Knights, Paladins, Sorcerers and Druids only; patch_base_classes.py gave the classes lists of those. Owner
-- request 2026-10-23: the Monk could use none that helps it, and axe, sword and club should be one melee weapon.
-- Now there are four kinds, and a kind lists the class lines that may use it:
--   melee   the sword weapon (the club ones work the same): Warrior, Thief, Templar lines. Trains the one melee skill (the
--           best of sword / club / axe, so the tries and the training rate follow the skill that counts)
--   fist    the fist weapon (owner 2026-10-28, "monk tambem nao tem training weapon"): Monk line only. Trains FIST FIGHTING,
--           the skill its hits and spells use (docs/CLASSES.md "Monk"). It lives on the item ids of the retired exercise
--           axe (their look is a pair of hand wraps now): see `tiers` for how the old items turn into the right one
--   ranged  bow: Ranger and Thief lines (distance skill)
--   magic   rod and wand: Mystic, Necromancer and Templar lines (magic level; the Templar's Rebuke, Thorns and Penitent's
--           Wrath scale with it. The Monk's spells scale with fist fighting, not the magic level)
--   shield  shield: every class (shielding is a skill of every class)

local WARRIOR = {4, 8, 14} -- Warrior, Juggernaut, Berserker
local RANGER = {3, 7, 15} -- Ranger, Deadeye, Beastmaster
local MYSTIC = {1, 5, 10} -- Mystic, Elementalist, Illusionist
local THIEF = {11, 12, 13} -- Thief, Ninja, Samurai
local MONK = {17, 18, 19} -- Monk, Shadowfist, Iron Sage
local NECRO = {20, 21, 22} -- Necromancer, Lich, Bone Lord
local TEMPLAR = {23, 24, 25} -- Templar, Inquisitor, Sentinel

return {
	-- the class lines (vocation ids); ChaosExercise.lineOf(vocationId) names the line
	lines = {warrior = WARRIOR, ranger = RANGER, mystic = MYSTIC, thief = THIEF, monk = MONK, necromancer = NECRO,
		templar = TEMPLAR},

	-- kind -> the lines that may use it, the skill it trains (a line in `skillBy` trains that one instead), and how the
	-- hit looks (ani = the name of the CONST_ANI_ the glue resolves; none = melee, the player stands next to the dummy)
	kinds = {
		melee = {lines = {"warrior", "thief", "templar"}, skill = "melee", range = 1},
		fist = {lines = {"monk"}, skill = "fist", range = 1},
		ranged = {lines = {"ranger", "thief"}, skill = "distance", ani = "CONST_ANI_SIMPLEARROW", range = 7},
		rod = {lines = {"mystic", "necromancer", "templar"}, skill = "magic", ani = "CONST_ANI_SMALLICE", range = 7},
		wand = {lines = {"mystic", "necromancer", "templar"}, skill = "magic", ani = "CONST_ANI_FIRE", range = 7},
		shield = {lines = {"warrior", "ranger", "mystic", "thief", "monk", "necromancer", "templar"}, skill = "shield",
			range = 1}
	},

	-- the weapons: item id -> kind. Charges are the item type's (500 / 1800 / 14400), set by the chest scripts.
	items = {
		[27732] = "melee", [27734] = "melee", -- exercise sword, club (500)
		[27738] = "melee", [27740] = "melee", -- durable (1800)
		[27744] = "melee", [27746] = "melee", -- lasting (14400)
		[27733] = "fist", [27739] = "fist", [27745] = "fist", -- exercise fist weapon (500 / 1800 / 14400; was the axe)
		[27735] = "ranged", [27741] = "ranged", [27747] = "ranged", -- bow
		[27736] = "rod", [27742] = "rod", [27748] = "rod",
		[27737] = "wand", [27743] = "wand", [27749] = "wand",
		[27758] = "shield", [27759] = "shield", [27760] = "shield"
	},

	-- the weapon of each charge tier, by kind: a weapon the user's class cannot train with turns into the one it can, with
	-- its charges (E.convertTo): the old club weapon into the sword one, an old exercise axe (now the fist weapon) held by a
	-- Warrior, Thief or Templar into the sword one, a sword weapon held by a Monk into the fist one. No purchase is lost.
	tiers = {
		{melee = 27732, fist = 27733, club = 27734}, -- 500
		{melee = 27738, fist = 27739, club = 27740}, -- 1800
		{melee = 27744, fist = 27745, club = 27746} -- 14400
	},

	-- the chest of each kind and tier (the store sells these; the base server's chest script gives the weapon of the same
	-- id order: chest 27761 -> 27732, 27762 -> 27733, ...). The old club chests are not sold any more (a club chest bought
	-- before gives a club weapon, which turns into the sword one, or the fist one for a Monk, on first use)
	chests = {
		{melee = 27761, fist = 27762}, {melee = 27768, fist = 27769}, {melee = 27775, fist = 27776}
	},
	retiredChests = {27763, 27770, 27777},

	-- the dummies (base server): house dummies give 10% more, free ones are plain
	dummies = {
		bonus = {27751, 27752, 27753, 27754, 27755, 27756, 29785, 29786, 29818, 29819, 29828, 29829},
		plain = {5787, 27750, 27757}
	},
	bonusFactor = 1.1,

	tickMs = 750, -- one charge, one training step
	activeMs = 2000, -- a chain whose last step is older than this has ended (a second click starts a new one)
	triesPerStep = 7, -- skill tries = this x the rate of the skill's stage
	manaPerStep = 500, -- mana spent for the magic level = this x the rate of the stage

	-- the base stages: below max level of the stage the rate multiplies the tries; above the last the server rate
	skillStages = {{min = 1, max = 50, rate = 5}, {min = 51, max = 100, rate = 3}, {min = 101, max = 200, rate = 2}},
	magicStages = {{min = 1, max = 50, rate = 5}, {min = 51, max = 100, rate = 3}, {min = 101, max = 200, rate = 2}}
}
