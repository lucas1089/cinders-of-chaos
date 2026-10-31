-- necro_balance_config.lua (O160): the inputs and the limits of the minion balance model, tools/minion_model.py --check (CI).
-- Plain table, loaded with dofile. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls. The minion numbers
-- themselves are in necro_config.lua; server/data/spells/README.md "Necromancer minions (O160)" has the method.
--
-- The model (computed, not measured in game): the Necromancer line's damage is the owner's spells (rotation_sim.py, class
-- spell factor included), its wand (a share of the Mystic's rotation) and its minions (necro_config.lua formulas, the
-- action cycle with the two minion spells), all x the class's tree, gear and class damage factor. It is anchored to the
-- C4 measurement (README "Classes with the passive trees": 4 skeletons, no minion spells, 1 target / 5 targets at level
-- 300 and 1000), where the minions were `share` of the damage. Against that anchor the model takes the cap, the minion
-- spells, the tree, and the time the minions are alive in a hunt: a pack cycle (pack_model.py's pack, its clear time and
-- walking time) in which the monsters hit the minions (monsterDps, focus), the minions die and are raised again, and
-- heal between packs.
return {
	-- the levels of the report (the first summon is at 8)
	levels = {8, 50, 200, 500, 1000},
	-- the levels the limits below are checked at
	checkLevels = {50, 200, 500, 1000},

	-- what the Necromancer raises first: the kinds in order; a kind not yet learned (spell levels in necro_config.lua
	-- summonSpells; Raise Dead 20) is replaced by the next one. "trio": two sturdy warriors in front and a mage
	-- behind them (3 minions; the Raise Bone Archer, the third of the old trio, became an attack spell in O254); "dead": Raise Dead's skeletons (the Raise Dead caps); "mages": the
	-- glass cannon.
	builds = {
		trio = {"warrior", "warrior", "mage"},
		dead = {"skeleton", "skeleton", "skeleton", "skeleton"},
		mages = {"mage", "mage", "mage"},
	},
	-- the build the limits are checked on
	defaultBuild = "trio",
	-- the Lich and the Bone Lord raise their own minions (necro_config.lua classes)
	classBuilds = {
		lich = {"shade"},
		bonelord = {"skeleton", "skeleton", "skeleton", "skeleton", "skeleton", "skeleton", "golem"},
	},

	-- the C4 measurement (2026-10-11, one 60 s run per class, tree build of every point, test gear): Raise Dead's skeleton
	-- caps then (the total cap came on 2026-10-18), the minions' share of the damage on 1 / 5 targets at level 300 and 1000
	-- (README "Covenant of the Grave": solved from the with / without runs), and the class damage factors then (the
	-- factors of necro_config / class_tree.lua are today's)
	c4 = {
		caps = {necromancer = {{0, 1}, {40, 2}, {80, 3}, {200, 4}}, lich = {{0, 1}}, bonelord = {{0, 5}, {400, 6}}},
		golem = {bonelord = true},
		share = {
			necromancer = {{300, 0.49}, {1000, 0.50}},
			bonelord = {{300, 0.58}, {1000, 0.61}},
			lich = {{300, 0.17}, {1000, 0.17}},
		},
		classDamage = {necromancer = {{300, 1.0}, {1000, 0.64}}, bonelord = {{300, 0.75}, {1000, 0.61}}, lich = {{300, 0.50}, {1000, 0.57}}},
	},
	-- the wand: a caster's auto attack is this share of the Mystic's single target rotation (README "Auto attack power")
	wandShare = 0.15,

	-- damage per second one monster deals to a minion {hunting level, damage}: armor_sim.py's "stock" column of the caster
	-- profile (README "Percent armour"): the monsters keep the stock armour formula and a minion has 20 armour, so a
	-- minion takes about what a caster with no percent armour takes. Interpolated by a power law between the points, and
	-- below the first by the exponent of the first two. The pace damage curve and the late-game boost do not reach a minion.
	-- O345 (2026-10-31): x5.5 after a live run (four Plagueroots, level 350, on the trio: about 1400 a second each after the
	-- pace curve, against 260 here); the armour estimate missed the monsters' area attacks hitting every minion at once.
	monsterDps = {{100, 640}, {300, 1250}, {1000, 5400}},

	-- the pack fight: the share of the monsters' attacks that land on the minions (the rest on the owner; monsters pick the
	-- nearest 7 times in 10: engine default target strategy), the share of the clear time an average monster is alive,
	-- and how the hits spread over the minions by kind (the front melee minion draws more; the warrior's taunt most)
	focus = 0.7,
	alive = 0.55,
	aggro = {warrior = 2.0, skeleton = 1.5, golem = 2.0, shade = 0.8, mage = 0.6},
	-- a minion that died is raised again at the start of the next pack (a cast and its mana), at full health; the others
	-- start the next pack with what is left plus the regeneration of the walk
	packs = 40,

	-- the tree, gear and class factors on the minions' hits, relative to the owner's spells (solved from the C4 share at
	-- 300 and 1000: 1.19 and 1.02)
	minionTree = 1.1,

	limits = {
		-- the trio's steady state in a base hunt pack cycle: the share of the minions' damage time they are alive
		uptimeMin = 0.90,
		-- a full set survives at least this many packs of the level (health pool / the damage a pack deals to the minions)
		-- (1.5: the minions heal between packs, idle regeneration; the level 1000 pack of 15600 damage is half a full set)
		packsPerSet = 1.5,
		-- the minions' share of the Necromancer's damage (the C4 measurement: 49 / 50%)
		shareMin = 0.35, shareMax = 0.60,
		-- the Necromancer's damage against the median class (pack_model.py damage(), 1 target and 5 targets) and its
		-- experience per hour in packs (kills per hour), with the minions alive as the fight model has them
		-- 1 target: parity. 5 targets: the minions' area spells make a summoner stronger on a pack (up to 1.25, as the Bone
		-- Lord's 5 target rows in README "Classes with the passive trees"); level 50 sits lower (0.85), a known gap of the
		-- first levels where the median class has its area spells and the Necromancer its three minions. Experience per hour
		-- at level 50 is 0.78 for the same reason (0.75 floor).
		ratio1 = {0.95, 1.15}, ratio5 = {0.84, 1.25}, ratioExp = {0.75, 1.15},
		-- the minions' own damage per second against one Bone Spear a second (the player's cheapest spell): every level
		-- of the first 100 the trio at least this many
		firstSummon = {minShare = 0.10},
	},
}
