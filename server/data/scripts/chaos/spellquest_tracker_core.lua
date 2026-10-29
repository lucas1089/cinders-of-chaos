-- spellquest_tracker_core.lua: the rows of the line spell quest tracker (ChaosSpellQuestTrackerCore, no engine). The
-- tracker is the twin of the Ascension tracker and of the Next Goals tracker (client game_goals): the steps of the quest
-- the character is on, each with a count and a bar. Engine side: spellquest_tracker.lua. Tests:
-- server/tests/spellquest_tracker_test.lua (luajit and lua5.3).
--
-- Rule: the rows show for a character whose line has a spell quest it can work on now (the next one not done on this line, its
-- level reached). Characters without a line, below the level, with every quest of the line done, or with the quests off get
-- no rows (the client hides the section).
-- Rows (same shape as the Ascension tracker): {key, title, progress, target, state = open | done}.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosSpellQuestCore then
	dofile("data/scripts/chaos/spellquest_core.lua")
end

ChaosSpellQuestTrackerCore = ChaosSpellQuestTrackerCore or {}
local M = ChaosSpellQuestTrackerCore
local Q = ChaosSpellQuestCore

local function T(lang, key, ...)
	local text = key
	if ChaosI18n and ChaosI18n.text then
		text = ChaosI18n.text(lang, key)
	end
	if select("#", ...) == 0 then
		return text
	end
	return string.format(text, ...)
end

-- ctx = {vocId, level, q = {[n] = {step = raw, kills = raw, fragments = raw, mask = raw}}}; lang optional.
-- Returns the rows ({} = hidden).
function M.rows(ctx, lang)
	local n, step, code = Q.current(ctx.vocId, ctx.level, ctx.q or {})
	if code ~= "ok" then
		return {}
	end
	local qc = Q.quest(n)
	local e = ctx.q[n] or {}
	local S = Q.STEP
	local kills, frags = 0, 0
	if step >= S.TRIAL then
		kills, frags = qc.kills, qc.fragments
	elseif step >= S.HUNT then
		kills = math.min(qc.kills, Q.count0(e.kills))
		frags = math.min(qc.fragments, Q.count0(e.fragments))
	end
	local idx = Q.lineOf(ctx.vocId)
	local spell = Q.spellName(idx, n)
	local function row(key, title, progress, target)
		return {key = key, title = title, progress = progress, target = target,
			state = progress >= target and "done" or "open"}
	end
	return {
		row("talk", T(lang, "Learn %s: speak with %s", spell, Q.cfg().npc.name), step >= S.HUNT and 1 or 0, 1),
		row("kills", T(lang, "Slay monsters of level %d or higher", qc.level), kills, qc.kills),
		row("fragments", T(lang, "Gather quest fragments from your kills"), frags, qc.fragments),
		-- the quest is done (and the rows hidden) as soon as the trial is won
		row("trial", T(lang, "Win the Archivist's trial"), 0, 1)
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
