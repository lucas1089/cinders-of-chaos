-- Shared cast of the seven level 800 buffs of the line spell quests (server/README.md "Line spell quests"; numbers in
-- data/scripts/chaos/quest_buffs_config.lua, rules in quest_buffs_core.lua). Loaded by each buff with:
--   dofile('data/spells/scripts/chaos/_questbuffs.lua')
-- A buff is one CONDITION_ATTRIBUTES on the caster with its own sub id (the buff bar row, chaos_buffs.lua), which also carries the
-- skill parameters where the buff has some; the rest of the effect is read from that condition by the combat scripts. No pacify
-- and no lock on other spells: a buff never stops the fight.
dofile('data/spells/scripts/chaos/_common.lua')
if not ChaosQuestBuffs then
	dofile('data/scripts/chaos/quest_buffs_core.lua')
end
if QuestBuffSpell then
	return
end

QuestBuffSpell = {}

-- cast buff `key` on the caster. params = {[CONDITION_PARAM_*] = value} added to the condition; effects = {vfx name, fx name,
-- fallback} for ChaosSpell.vfxOr at the caster's feet; extra(player, cfg) may add more (Veil of Whispers' regeneration)
function QuestBuffSpell.cast(creature, key, params, effects, extra)
	local player = creature and creature:getPlayer()
	if not player then
		return false
	end
	local cfg = ChaosQuestBuffsConfig
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
	c:setParameter(CONDITION_PARAM_SUBID, cfg.subId[key])
	c:setParameter(CONDITION_PARAM_TICKS, cfg[key].durationMs)
	for param, value in pairs(params or {}) do
		c:setParameter(param, value)
	end
	if params and next(params) then
		c:setParameter(CONDITION_PARAM_BUFF_SPELL, true)
	end
	player:addCondition(c)
	if extra then
		extra(player, cfg[key])
	end
	local pos = player:getPosition()
	ChaosSpell.vfxOr(pos, effects[1], effects[2], effects[3])
	return true
end
