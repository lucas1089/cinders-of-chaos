-- ascension_tracker_core.lua: the rows of the Ascension tracker (ChaosAscensionTrackerCore, no engine). The tracker is
-- the twin of the Next Goals tracker (client game_goals): the steps of the ascension quest, each with a count and a bar.
-- Engine side: ascension_tracker.lua. Tests: server/tests/ascension_tracker_test.lua (luajit and lua5.3).
--
-- Rule (the quest's own): the tracker shows for a base class whose line has an ascension, from the quest's level
-- (Chaos.classes.ascension.minLevel) on, until the character has ascended. Ascended classes, lines without an
-- ascension and characters below the level get no rows (the client hides the section). A character the store's
-- Vocation Change took back to a base class sees the finished steps and the Choice again.
-- Rows (same shape as the Next Goals tracker, plus state): {key, title, progress, target, state = open | done}.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosAscensionQuestCore then
	dofile("data/scripts/chaos/ascension_quest_core.lua")
end

ChaosAscensionTrackerCore = ChaosAscensionTrackerCore or {}
local M = ChaosAscensionTrackerCore
local Q = ChaosAscensionQuestCore

local function T(lang, key)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key)
	end
	return key
end

-- ctx = {vocId, level, stage (raw storage), proof (raw storage points)}; lang optional. Returns the rows ({} = hidden).
function M.rows(ctx, lang)
	local cfg = Q.cfg()
	if not cfg or cfg.enabled == false then
		return {}
	end
	if not Q.eligibility(ctx.vocId, ctx.level) then
		return {}
	end
	local stage = Q.stage(ctx.stage)
	local S = Q.STAGE
	local need = cfg.proof.needed
	local proof = 0
	if stage >= S.TRIAL then
		proof = need
	elseif stage >= S.PROOF then
		proof = math.min(need, math.max(0, math.floor(tonumber(ctx.proof) or 0)))
	end
	local function row(key, title, progress, target)
		return {key = key, title = T(lang, title), progress = progress, target = target,
			state = progress >= target and "done" or "open"}
	end
	return {
		row("calling", "Hear the Calling of the Ascendant Oracle", stage >= S.PROOF and 1 or 0, 1),
		-- the lowest monster level that counts, in the title (owner 2026-10-24): it moves with the player's level
		row("proof", string.format(T(lang, "Slay rare and legendary beasts of level %d or higher"),
			Q.minMonsterLevel(ctx.level)), proof, need),
		row("trial", "Win the Ascension Trial", stage >= S.CHOICE and 1 or 0, 1),
		-- the Choice is never done while the rows show: ascending hides them
		row("choice", "Choose your ascended class", 0, 1)
	}
end

-- what the player sees of the rows as one string: the same string, nothing to send again
function M.sig(rows, lang)
	local parts = {tostring(lang or "")}
	for _, r in ipairs(rows or {}) do
		parts[#parts + 1] = string.format("%s:%d/%d:%s", r.key, r.progress, r.target, tostring(r.title))
	end
	return table.concat(parts, ";")
end

return M
