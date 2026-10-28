-- spellquest_core.lua: the rules of the line spell quests that need no engine (ChaosSpellQuestCore). Used by
-- spellquest.lua (kills, storage, the trial, the reward), spellquest_tracker_core.lua and the NPC script of Archivist
-- Odrenna (data/npc/scripts/archivist_odrenna.lua, its own Lua state). Tests: server/tests/spellquest_test.lua
-- (luajit and lua5.3). Settings: spellquest_config.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Steps of a quest (storage +0): 0 none -> 1 hunt (counted kills and fragments) -> 2 the trial is open -> 3 done.
-- Progress is per character. The "done" flag is per line: a bit of the mask in storage +7, so a Vocation Change to
-- another line shows the quest as not done there (it needs that line's own quest), and the way back finds it done and
-- teaches the spell again for free. Quest n needs quest n - 1 done on the same line.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.spellQuest then
	Chaos.spellQuest = dofile("data/scripts/chaos/spellquest_config.lua")
end

ChaosSpellQuestCore = ChaosSpellQuestCore or {}
local M = ChaosSpellQuestCore
local floor, max, min = math.floor, math.max, math.min

-- a text in `lang` through ChaosI18n (i18n_core.lua) when it is loaded, else English
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

M.STEP = {NONE = 0, HUNT = 1, TRIAL = 2, DONE = 3}

function M.cfg()
	return Chaos.spellQuest
end

function M.count()
	return #M.cfg().quests
end

function M.quest(n)
	return M.cfg().quests[n]
end

-- ------------------------------------------------------------------------------------------------ storage
-- storage keys of quest n (1..count)
function M.keys(n)
	local base = Chaos.storage.spellQuest + Chaos.storage.spellQuestSlots * (n - 1)
	return {step = base, kills = base + 1, fragments = base + 2, pity = base + 3, attempts = base + 4,
		cooldown = base + 5, doneAt = base + 6, lines = base + 7}
end

-- a stored value (-1 = never set) as a count >= 0
local function count(raw)
	return max(0, floor(tonumber(raw) or 0))
end
M.count0 = count

function M.step(raw)
	return min(count(raw), M.STEP.DONE)
end

-- ------------------------------------------------------------------------------------------------ lines
-- the line of a vocation: index, line (config entry), or nil. The base class comes from Chaos.classes at call time.
function M.lineOf(vocId)
	local base = Chaos.classes.baseOf[vocId]
	if not base then
		return nil
	end
	for i, line in ipairs(M.cfg().lines) do
		if Chaos.classes.ids[line.class] == base then
			return i, line
		end
	end
	return nil
end

function M.lineBit(idx)
	return 2 ^ (idx - 1)
end

function M.lineDone(mask, idx)
	return floor(count(mask) / M.lineBit(idx)) % 2 == 1
end

function M.markLine(mask, idx)
	mask = count(mask)
	if M.lineDone(mask, idx) then
		return mask
	end
	return mask + M.lineBit(idx)
end

-- the step of quest n for a line: done on this line = 3; a stored 3 from another line = 0; else the stored one
function M.effectiveStep(rawStep, mask, lineIdx)
	if lineIdx and M.lineDone(mask, lineIdx) then
		return M.STEP.DONE
	end
	local s = M.step(rawStep)
	if s >= M.STEP.DONE then
		return M.STEP.NONE
	end
	return s
end

-- the spell of a line and quest, or nil
function M.spellName(lineIdx, n)
	local line = M.cfg().lines[lineIdx]
	return line and line.spells[n] or nil
end

-- {line = index, quest = n} of a quest spell name (case-insensitive), or nil
function M.spellInfo(name)
	local key = tostring(name or ""):lower()
	for i, line in ipairs(M.cfg().lines) do
		for n, spell in ipairs(line.spells) do
			if spell:lower() == key then
				return {line = i, quest = n}
			end
		end
	end
	return nil
end

-- ------------------------------------------------------------------------------------------------ which quest
-- q[n] = {step = raw, mask = raw} for every quest. Returns n, step (effective), code:
--   "ok"      quest n may be worked on now
--   "level"   quest n is next but the level is below its gate
--   "done"    all quests of the line are done (n = count, step 3)
--   "noline"  the vocation has no line (n = nil)
--   "off"     the quests are switched off
function M.current(vocId, level, q)
	if M.cfg().enabled == false then
		return nil, 0, "off"
	end
	local idx = M.lineOf(vocId)
	if not idx then
		return nil, 0, "noline"
	end
	for n = 1, M.count() do
		local e = q[n] or {}
		local step = M.effectiveStep(e.step, e.mask, idx)
		if step < M.STEP.DONE then
			if (tonumber(level) or 0) < M.quest(n).level then
				return n, step, "level"
			end
			return n, step, "ok"
		end
	end
	return M.count(), M.STEP.DONE, "done"
end

-- ------------------------------------------------------------------------------------------------ kills
-- What a kill is worth for one character. k = {playerLevel, monsterLevel, boss, summon, excluded, nearProtection,
-- hunt (a hunt monster: known to the pace layer; bosses need none)}, questN. Returns weight (0 = does not count), why.
function M.killWeight(questN, k)
	local qc = M.quest(questN)
	local hc = M.cfg().hunt
	if not qc then
		return 0, "quest"
	end
	if k.summon then
		return 0, "summon"
	end
	if k.excluded then
		return 0, "instance"
	end
	if k.nearProtection then
		return 0, "protection"
	end
	if not k.boss and not k.hunt then
		return 0, "event"
	end
	if (tonumber(k.playerLevel) or 0) < qc.level then
		return 0, "playerLevel"
	end
	if (tonumber(k.monsterLevel) or 0) < qc.level then
		return 0, "level"
	end
	return k.boss and hc.bossKills or 1
end

-- players a kill counts for. killers: the players that made it (last hit, most damage, summons resolved); damagers: every
-- player that dealt damage (damage map); partyOf(p) -> the party members of p or nil; posOf, idOf as ChaosBounty.credit;
-- near(a, b) -> true when b is within the party range of a. A killer always counts; any other damager only as a party member of
-- a killer, within range. Order: killers first, then the others by id.
function M.credited(killers, damagers, partyOf, posOf, idOf, near)
	local out, seen = {}, {}
	local function add(p)
		local id = idOf(p)
		if not seen[id] then
			seen[id] = true
			out[#out + 1] = p
		end
	end
	for _, k in ipairs(killers or {}) do
		add(k)
	end
	local dealt = {}
	for _, d in ipairs(damagers or {}) do
		dealt[idOf(d)] = d
	end
	local ids = {}
	for id in pairs(dealt) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local d = dealt[id]
		if not seen[id] then
			for _, k in ipairs(killers or {}) do
				local members = partyOf(k)
				local inParty = false
				for _, m in ipairs(members or {}) do
					if idOf(m) == id then
						inParty = true
						break
					end
				end
				if inParty and near(posOf(k), posOf(d)) then
					add(d)
					break
				end
			end
		end
	end
	return out
end

-- one fragment roll. state.pity = counted kills since the last fragment. tier: "normal" | "magic" | "rare" | "legendary";
-- rand() -> 0 <= x < 1. Returns dropped, newPity, why ("boss" | "pity" | "roll" | nil)
function M.fragmentRoll(pity, tier, boss, rand)
	local fc = M.cfg().fragments
	if boss then
		return true, 0, "boss"
	end
	pity = count(pity)
	if pity + 1 > fc.pity then
		return true, 0, "pity"
	end
	local chance = min(1, fc.chance * (fc.tierMultiplier[tier] or 1))
	if rand() < chance then
		return true, 0, "roll"
	end
	return false, pity + 1
end

-- A counted kill. s = {step, kills, fragments, pity} (raw storage values), questN, weight, tier, boss, rand.
-- Returns the new state {step, kills, fragments, pity} and info {fragment = bool, why, huntDone = bool, killsGained}.
-- Only step 1 counts. Fragments stop at the needed number and kills at theirs; the hunt is done with both.
function M.applyKill(s, questN, weight, tier, boss, rand)
	local qc = M.quest(questN)
	local out = {step = M.step(s.step), kills = count(s.kills), fragments = count(s.fragments), pity = count(s.pity)}
	local info = {fragment = false, huntDone = false, killsGained = 0}
	if out.step ~= M.STEP.HUNT or not qc or (weight or 0) <= 0 then
		return out, info
	end
	local before = out.kills
	out.kills = min(qc.kills, before + weight)
	info.killsGained = out.kills - before
	if out.fragments < qc.fragments then
		local dropped, pity, why = M.fragmentRoll(out.pity, tier, boss, rand)
		out.pity = pity
		if dropped then
			out.fragments = out.fragments + 1
			info.fragment, info.why = true, why
		end
	end
	if out.kills >= qc.kills and out.fragments >= qc.fragments then
		out.step = M.STEP.TRIAL
		info.huntDone = true
	end
	return out, info
end

-- a quest started: the counters are new
function M.startState()
	return {step = M.STEP.HUNT, kills = 0, fragments = 0, pity = 0}
end

-- ------------------------------------------------------------------------------------------------ the trial
-- may the character enter the trial of quest n: ok, text
function M.canEnterTrial(questN, step, level, now, cooldownUntil, busy, lang)
	local qc = M.quest(questN)
	if not qc then
		return false, T(lang, "That quest does not exist.")
	end
	if step ~= M.STEP.TRIAL then
		if step >= M.STEP.DONE then
			return false, T(lang, "You have passed this trial already.")
		end
		return false, T(lang, "The trial is closed to you until the hunt is done.")
	end
	if (tonumber(level) or 0) < qc.level then
		return false, T(lang, "You are not ready. Return when you have reached level %d.", qc.level)
	end
	if busy then
		return false, T(lang, "You are in a trial already.")
	end
	local wait = (tonumber(cooldownUntil) or 0) - (tonumber(now) or 0)
	if wait > 0 then
		return false, T(lang, "The door stays shut for now. Return in %s.", M.formatWait(wait, lang))
	end
	return true
end

function M.formatWait(seconds, lang)
	seconds = max(0, floor(seconds))
	if seconds >= 60 then
		local m = math.ceil(seconds / 60)
		return m == 1 and T(lang, "1 minute") or T(lang, "%d minutes", m)
	end
	return seconds == 1 and T(lang, "1 second") or T(lang, "%d seconds", seconds)
end

-- what finishing quest n pays: {gold, spell}. doneAt = storage +6 before this completion (0 = never done on any line)
function M.reward(questN, lineIdx, level, doneAt)
	local gold = 0
	if count(doneAt) == 0 then
		gold = max(0, floor(tonumber(level) or 0)) * M.cfg().reward.goldPerLevel
	end
	return {gold = gold, spell = M.spellName(lineIdx, questN)}
end

-- ------------------------------------------------------------------------------------------------ vocation change
-- Which quest spells a character of this vocation should know: the spells of its line whose quest is done on that line.
-- q[n] = {step, mask} raw. Returns a list of names.
function M.unlockedSpells(vocId, q)
	local idx = M.lineOf(vocId)
	local out = {}
	if not idx then
		return out
	end
	for n = 1, M.count() do
		local e = q[n] or {}
		if M.lineDone(e.mask, idx) then
			out[#out + 1] = M.spellName(idx, n)
		end
	end
	return out
end

-- every quest spell name of every line
function M.allSpells()
	local out = {}
	for _, line in ipairs(M.cfg().lines) do
		for _, name in ipairs(line.spells) do
			out[#out + 1] = name
		end
	end
	return out
end

-- {forget = {names}, learn = {names}} for a vocation: knows(name) -> bool. Quest spells of another line are forgotten, the
-- done spells of this line are taught again (free); sorted.
function M.spellPlan(vocId, q, knows)
	local want = {}
	for _, name in ipairs(M.unlockedSpells(vocId, q)) do
		want[name] = true
	end
	local forget, learn = {}, {}
	for _, name in ipairs(M.allSpells()) do
		local known = knows(name) and true or false
		if want[name] and not known then
			learn[#learn + 1] = name
		elseif known and not want[name] then
			forget[#forget + 1] = name
		end
	end
	table.sort(forget)
	table.sort(learn)
	return {forget = forget, learn = learn}
end

-- ------------------------------------------------------------------------------------------------ staff and testers
-- "/spellquest set <player>, <quest>, <step>[, kills[, fragments]]" | "show <player>" | "reset <player>": action, name, args or
-- nil and the reason
function M.parseCommand(param)
	local text = tostring(param or "")
	local action, rest = text:match("^%s*(%a+)%s*(.-)%s*$")
	if not action then
		return nil, "Usage: /spellquest set <player>, <quest 1-3>, <step 0-3>[, kills[, fragments]] | show <player> | reset <player>"
	end
	action = action:lower()
	local parts = {}
	for piece in (rest .. ","):gmatch("%s*([^,]-)%s*,") do
		parts[#parts + 1] = piece
	end
	local name = parts[1]
	if not name or name == "" then
		return nil, "Usage: /spellquest " .. action .. " <player>" .. (action == "set" and ", <quest>, <step>[, kills[, fragments]]" or "")
	end
	if action == "show" or action == "reset" then
		return action, name, {}
	end
	if action ~= "set" then
		return nil, "Unknown action: " .. action .. "."
	end
	local n, step = tonumber(parts[2]), tonumber(parts[3])
	if not n or not step or n < 1 or n > M.count() or n ~= floor(n) or step < 0 or step > M.STEP.DONE or step ~= floor(step) then
		return nil, "Usage: /spellquest set <player>, <quest 1-" .. M.count() .. ">, <step 0-3>[, kills[, fragments]]"
	end
	return "set", name, {quest = n, step = step, kills = tonumber(parts[4]), fragments = tonumber(parts[5])}
end

-- the storage values a staff "set" leaves for quest n on a line: {step, kills, fragments, pity, mask} (raw), given the
-- current ones. Step 3 marks the line done (no gold: doneAt stays as it is), a lower step takes the mark away; the counters
-- follow the step (step 2 and 3 = everything needed) unless given.
function M.applySet(cur, lineIdx, n, step, kills, fragments)
	local qc = M.quest(n)
	local out = {step = step, mask = count(cur.mask), pity = 0}
	if step >= M.STEP.TRIAL then
		out.kills, out.fragments = qc.kills, qc.fragments
	elseif step == M.STEP.HUNT then
		out.kills, out.fragments = min(qc.kills, count(kills)), min(qc.fragments, count(fragments))
		out.pity = count(cur.pity)
	else
		out.kills, out.fragments = 0, 0
	end
	if kills and step >= M.STEP.TRIAL then
		out.kills = min(qc.kills, count(kills))
	end
	if fragments and step >= M.STEP.TRIAL then
		out.fragments = min(qc.fragments, count(fragments))
	end
	if step == M.STEP.DONE then
		out.mask = M.markLine(out.mask, lineIdx)
	elseif M.lineDone(out.mask, lineIdx) then
		out.mask = out.mask - M.lineBit(lineIdx)
	end
	return out
end

-- ------------------------------------------------------------------------------------------------ texts
-- the lowest monster level that counts for quest n (the quest's level)
function M.huntText(questN, state, lang)
	local qc = M.quest(questN)
	return T(lang, "Hunt monsters of level %d or higher: %d of %d kills, %d of %d fragments.", qc.level,
		min(qc.kills, count(state.kills)), qc.kills, min(qc.fragments, count(state.fragments)), qc.fragments)
end

function M.trialText(questN, lang)
	local qc = M.quest(questN)
	if not Chaos.trials then
		pcall(function() Chaos.trials = dofile("data/scripts/chaos/trials_config.lua") end)
	end
	local tc = Chaos.trials and Chaos.trials.spellTiers
	local tier
	for _, t in ipairs(tc or {}) do
		if t.key == qc.trial then
			tier = t
		end
	end
	if not tier then
		return T(lang, "Your trial awaits.")
	end
	return T(lang, "Your trial: %d minutes, %d lives, alone. If you fall, nothing is lost; the door stays shut for %s.",
		floor(tier.time / 60), tier.lives, M.formatWait(M.cfg().trial.failCooldownSeconds, lang))
end

-- Engine helpers shared with the NPC script: the trial question
function M.sendModal(player, id, title, text, buttons)
	if not ModalWindow then
		return false
	end
	local w = ModalWindow(id, title, text)
	for _, b in ipairs(buttons) do
		w:addButton(b[1], b[2])
	end
	w:setDefaultEnterButton(buttons[1][1])
	w:setDefaultEscapeButton(buttons[#buttons][1])
	w:sendToPlayer(player)
	return true
end

function M.sendTrialModal(player, questN, spellName, lang)
	local text = T(lang, "%s waits at the end of the trial.\n\n%s\n\nYou go alone. Enter?", spellName or "", M.trialText(questN, lang))
	return M.sendModal(player, M.cfg().modal.trial, T(lang, "The Archivist's Trial"), text,
		{{1, T(lang, "Enter")}, {2, T(lang, "Not yet")}})
end

return M
