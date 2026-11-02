-- survival_balance_config.lua (O367): the inputs and the limits of the hunt survival model, tools/survival_model.py --check
-- (CI). Plain table, loaded with dofile. Lua 5.1 / LuaJIT and Lua 5.3 compatible. No engine calls. server/README.md
-- "Hunt survival by class (O367)" has the method and the before / after tables.
--
-- The model (computed, not measured in game): a character `gap` levels above a hunt of the level-scaled late sets stands
-- in a pack of `pack` monsters of that hunt. Per class: its health (start_stats.lua, the tree's vitality), the damage the
-- pack deals to it per second after every layer (engine level bonus, pace damage curve, late-game physical boost, tier
-- mean, armour, block, the tree's absorbs, dodge, class toughness), the healing it has per second (one potion a second
-- and the line's self heal) and so: seconds to die with no healing (burst) and with it.
return {
	-- hunting levels of the report and of the check (the player is `gap` levels above). 750: owner report 2026-11-02 (a
	-- level 757 Ninja in a level 750 hunt)
	levels = {670, 750, 850, 1000},
	gap = 7,
	-- the hunt's monsters: the bounty pool's level-scaled ones within `band` levels of the hunting level, weighted by spawns
	band = 30,
	-- monsters hitting the player at once: a lured pack (tools/pack_model.py PACK, the 600-1000 band)
	pack = 7,
	-- the engine's damage bonus per monster level (config.lua monsterBonusDamage; README "Monster level: no skull, no spread")
	engineBonus = 0.0015,
	-- monster tiers on average (monster_tiers.lua: 6% magic x1.25, 1.5% rare x1.5, 0.25% legendary x2 of the spawns)
	tierMean = 1.025,

	-- armour: config.lua armorPercentConstant / armorPercentMax (README "Percent armour")
	armorK = 250, armorCap = 80,
	-- the gear: the equipment sets' curves at the level (tools/install_gear_sets.py CURVES, FIT_SHARE: heavy 1.0, medium
	-- 0.9, cloth 0.8 on helmet, body and legs), plus the rarity armour bonus of the engine on each armour piece (item.cpp:
	-- +3-7 at the middle rarities; armor_sim.py PROFILES has the same order)
	rarityPerPiece = 5, armourPieces = 6,
	weight = {
		heavy = {"warrior", "juggernaut", "berserker", "templar", "inquisitor", "sentinel"},
		medium = {"ranger", "deadeye", "beastmaster", "thief", "ninja", "samurai", "monk", "shadowfist", "ironsage"},
		cloth = {"mystic", "elementalist", "illusionist", "necromancer", "lich", "bonelord"}
	},
	-- block (defence, armor_sim.py: one block a second at most, uniform(d / 2, d), d = (skill / 4 + 2.23) x defence x 0.15):
	-- a shield (the set curve `shield`) or the weapon in hand (the set curve `defense`); casters and archers none
	blockSkill = 120,
	blockShield = {"warrior", "juggernaut", "templar", "inquisitor", "sentinel"},
	blockWeapon = {"berserker", "thief", "ninja", "samurai", "monk", "shadowfist", "ironsage"},

	-- damage taken factor of the class's own kit, from the toughness model of data/spells/README.md "Templar line" and
	-- "Classes with the passive trees" (Juggernaut: Iron Will and Bulwark; Sentinel: aura and Aegis of Faith; Samurai:
	-- Counter Stance). The Templar and the Inquisitor take their own aura (templar_aura_core.lua) on top of 1.
	toughness = {juggernaut = 0.765, sentinel = 0.81, samurai = 0.844},
	ownAura = {"templar", "inquisitor"},

	-- the lines with Ward of the Mind (docs/CLASSES.md "Spell cap"): the mana takes the hits first, so the mana pool adds to
	-- the health and a mana potion is worth its mana
	manaShield = {"mystic", "ranger", "necromancer"},

	-- self heal per second at level 300 and 1000 (data/spells/README.md "Healing", measured, and "Shadow Mend rebalance (C5)"),
	-- linear between, flat outside. By class key, else by line key. The Monk and the Shadowfist have no measured self heal:
	-- the Warrior line's stands in (stock heals only); the Templar and the Inquisitor take the Sentinel's (Vow of Mending).
	selfHeal = {
		warrior = {359, 733}, ranger = {798, 1180}, mystic = {1456, 2048}, illusionist = {1538, 2317},
		thief = {751, 1527}, necromancer = {1547, 2267}, monk = {359, 733}, ironsage = {1765, 2525}, templar = {150, 373}
	},
	-- potions: one Everfull potion a second (the 900 ms wait), the tier below (potions_config.lua everfull: its roll plus
	-- amount.everfullPct of the maximum health or mana)
	potionsPerSecond = 1, potionTier = 4,

	-- limits of --check, at every level of `levels`:
	-- every class lives at least burstShare x the median class's seconds with no healing in the pack. Before the Ninja guard
	-- (O367, chaos_constants.lua Chaos.classes.guard) the Ninja had 0.39 / 0.35 / 0.43 / 0.43 at 670 / 750 / 850 / 1000; with
	-- it 0.65 / 0.58 / 0.72 / 0.72. The next lowest are the Inquisitor (0.46-0.60) and the Iron Sage (0.49-0.64), the two
	-- support classes in heavy / medium armour with no absorb lane.
	burstShare = 0.45,
	-- the median class heals at least sustainMin x the pack's damage per second (the hunt itself is not too hard for
	-- everyone: 1.40 / 1.96 / 2.11 / 1.48 today)
	sustainMin = 1.2
}
