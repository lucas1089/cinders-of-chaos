-- Skill stage speed-up (O154): the factor tools/patch_skill_stages.py multiplies the base server's skill and magic level
-- stage multipliers (data/scripts/customs/skills/skills_stages.lua) by, from `fromLevel` up. Owner decision 2026-10-24, "pode
-- acelerar 5x o treino de skill": x5 from skill / magic level 101, the stages up to 100 stay as they are. Plain table, loaded
-- with dofile by tools/skill_model.lua; the patch tool reads the two numbers with a pattern, so keep them as `name = number`.
-- Hunting, exercise weapons and offline training all pass the stage, so all three train `factor` times faster from `fromLevel`.
-- Numbers and reasons: docs/PRICES.md "Skill training (O150)" and "Skill stages x5 (O154)". Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	fromLevel = 101,
	factor = 5
}
