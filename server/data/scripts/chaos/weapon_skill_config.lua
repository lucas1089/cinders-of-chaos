-- weapon_skill_config.lua: the numbers of weapon_skill_core.lua (auto attack damage scales with the skill; owner
-- 2026-10-20: "faça o dano das armas/auto attack escalar com as skills dos players"; server/README.md "Weapon damage
-- scales with skills", server/data/spells/README.md "Weapon damage and skills"). Data only. Lua 5.1 / LuaJIT and 5.3.
--
-- typical: the skill and the magic level a character usually has at a level, {level, value} anchors, linear between
-- them, flat outside. They are the stats of the C4 measurement (server/tools/rotation_sim.py ANCHORS "skill" and
-- "ml_caster"), except that the magic level starts at 0 on level 8, where a new character starts: a fresh Mystic hits
-- with its wand exactly as before. tools/weapon_sim.py --skills reads this file for its report.
--
-- wand: a wand or rod hit (flat min .. max of weapons.xml in the engine) is multiplied by
--   (magic level + offset) / (typical magic level of the level + offset), clamped to minFactor .. maxFactor
-- so the typical magic level of a level deals what the wand dealt before, a higher one more, a lower one less. offset
-- 20 gives the wand the slope the engine gives a weapon's skill: +10% magic level is about +8% damage at level 300
-- (the skill: about +9%). The magic level is the effective one (equipment included), like the skill of a weapon hit.
return {
	typical = {
		skill = {{1, 10}, {100, 80}, {300, 110}, {600, 125}, {1000, 140}},
		magic = {{8, 0}, {100, 60}, {300, 100}, {600, 120}, {1000, 140}},
	},
	wand = {
		offset = 20,
		minFactor = 0.5,
		maxFactor = 2.0,
	},
}
