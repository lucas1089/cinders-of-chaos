-- weapon_families_config.lua: the numbers of the three melee weapon families (O454; rules: weapon_families_core.lua, engine
-- glue: weapon_families.lua, called by weapon_styles.lua; server/README.md "Weapon families (O454)", docs/BUILDS.md).
-- Plain table, numbers only. Lua 5.1 / LuaJIT and 5.3 compatible. tools/weapon_family_model.py reads the numbers below with
-- regular expressions: keep `name = number` on one line.
--
-- One melee skill, one attack per item level: a sword, an axe and a club of one tier hit the same. The families give each
-- one a trait on the BASIC melee attack (a spell's weapon strike, a keystone's extra hit and the fist stay as they are):
--   sword  tempo   hits on the same target speed up the swing; each hit is lighter by the same share (the interval it was
--                  swung at over the interval without tempo), so the damage per second does not move, plus a small edge at
--                  full stacks. Best on one target. A new target, or a pause, starts over.
--   axe    cleave  a share of every hit is split among the monsters next to the target. The total split share is `pool`,
--                  whatever the number of neighbours, so the gain on a pack has a ceiling. Pays with `single`.
--   club   impact  a chance on a hit to daze a monster: it cannot attack for stunMs. A rest of immuneMs after, shared with
--                  the Monk's Iron Palm, so there is no stun lock; a boss is only slowed, once in a while. Pays with `single`.
-- single = the multiplier of one hit of the family (the price). The measured class damage (data/spells/class_dps_measured.csv)
-- holds for every family: each is within 3% of 1.00 and no family is more than 5% above another on one target.
-- tools/weapon_family_model.py --check holds the limits (CI).
return {
	-- false: the traits are off (the hit is the hit of before O454)
	enabled = true,

	-- the vocations that get the traits: the Warrior line (4 Warrior, 8 Juggernaut, 14 Berserker), the Thief line (11 Thief,
	-- 12 Ninja, 13 Samurai) and the Templar line (23, 24, 25). The Monk line (17, 18, 19) keeps its fists and its chi: not here.
	vocations = {[4] = true, [8] = true, [14] = true, [11] = true, [12] = true, [13] = true, [23] = true, [24] = true, [25] = true},

	families = {
		sword = {
			name = "Sword", trait = "tempo",
			single = 1.00,
			tempo = {
				-- each hit on the same target within windowMs adds one stack, up to maxStacks (hits closer than minGapMs are one
				-- swing: the off-hand hit of a dual wielder). A stack is stackPct percent attack speed, set through the player
				-- attack speed bonus (engine patch 0078, source "tempo"); the cap of patch 0011 and the 3 attacks per second floor
				-- still hold, and when they hold the hit stays as heavy as it was.
				maxStacks = 5, stackPct = 4, windowMs = 3000, minGapMs = 150,
				-- at full stacks the hit is this much heavier, on top of the interval ratio (stacks / maxStacks of it)
				edge = 0.02,
				-- against a player: this share of the stacks (and the edge it brings), rounded down, at least one
				pvpStackShare = 0.5
			}
		},
		axe = {
			name = "Axe", trait = "cleave",
			single = 0.975,
			cleave = {
				-- the share of the hit split among the monsters next to the target (3x3 around it); each takes pool / number
				pool = 0.14,
				-- at most this many neighbours take a share
				maxTargets = 8,
				-- against a player nothing is split (the neighbours are never players either)
				pvp = false
			}
		},
		club = {
			name = "Club", trait = "impact",
			single = 0.975,
			daze = {
				-- a hit dazes a monster with this chance: it cannot attack for stunMs (monk_combat.lua cancels its attacks while
				-- the stun condition lasts) and stands still. Then it cannot be dazed or Iron Palmed for immuneMs more
				chance = 0.25, stunMs = 700, immuneMs = 3000,
				-- a boss (MonsterType:isBoss, or more than bossHealth maximum health, the Monk's rule) is only slowed by bossSlow
				-- for bossSlowMs, with bossChance, and then not again for bossImmuneMs
				bossHealth = 50000, bossChance = 0.15, bossSlow = 0.25, bossSlowMs = 1000, bossImmuneMs = 8000,
				-- the condition sub ids (CONDITIONID_COMBAT): Iron Palm's stun and its immunity timer (monk_chi_core.lua), shared; the
				-- boss slow and the boss rest are new
				stunSubId = 71034, immuneSubId = 71035, bossSlowSubId = 71095, bossRestSubId = 71096,
				-- against a player nothing happens
				pvp = false
			}
		}
	}
}
