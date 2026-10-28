-- quest_buffs_config.lua: the seven level 800 buffs of the line spell quests (server/README.md "Line spell quests", server/data/spells/
-- README.md "Line spell quests, level 800 buffs"). Every number of the seven spells is here; the rules that read them are
-- quest_buffs_core.lua, the casts are data/spells/chaos/<folder>/*.lua through data/spells/chaos/_questbuffs.lua.
--   subId     the condition sub id of each buff (CONDITION_ATTRIBUTES, CONDITIONID_COMBAT): the spells and the combat scripts run in
--             different Lua states, the condition is what both see (buff bar rows in data/lib/chaos_buffs.lua). Veil of Whispers adds
--             a regeneration condition of sub id + regenOffset. 71075-71081 are free in the sub id table (README "Condition sub ids").
--   durationMs, then per buff the effect. skill percents are the engine's (120 = +20%); evade is added to the line's evasion
--   (a chance, classes.lua / monk_chi_core.lua); minion and death are factors on the damage of the Necromancer's minions and of its
--   death spells; taken / holy on the Templar's damage taken and the holy strike after a melee hit (Radiant Strikes).
-- Plain table, Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosQuestBuffsConfig = {
	cooldownMs = 90000,
	regenOffset = 1000,
	subId = {
		oath = 71075, gaze = 71076, veil = 71077, knives = 71078, dirge = 71079, lotus = 71080, mantle = 71081
	},
	-- Ironbound Oath (Warrior line): +20% melee skill, +25% shielding
	oath = {durationMs = 20000, melee = 120, shield = 125},
	-- Unblinking Gaze (Ranger line): +25% distance skill, +10 points of critical chance
	gaze = {durationMs = 20000, distance = 125, crit = 10},
	-- Veil of Whispers (Mystic line): +15% magic level, mana regeneration of `manaPct` of the maximum mana every second
	veil = {durationMs = 20000, magic = 115, manaPct = 0.01, minMana = 5},
	-- Shroud of Knives (Thief line): +20% melee and distance skill (the blade and the shuriken), +10 points of evasion
	knives = {durationMs = 15000, melee = 120, distance = 120, evade = 0.10},
	-- Dirge of the Legion (Necromancer line): the minions' hits +25%, death spell damage +10%
	dirge = {durationMs = 20000, minion = 0.25, death = 0.10},
	-- Lotus Stance (Monk line): +1 chi on a weapon or fist hit, +10 points of evasion
	lotus = {durationMs = 15000, chi = 1, evade = 0.10},
	-- Mantle of Dawn (Templar line): 15% less damage taken, the holy strike after a melee hit +20%
	mantle = {durationMs = 20000, taken = 0.15, holy = 0.20}
}

return ChaosQuestBuffsConfig
