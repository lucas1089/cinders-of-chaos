-- ascension_quest_core.lua: the rules of the ascension quest that need no engine (ChaosAscensionQuestCore).
-- Used by ascension_quest.lua (the scripts' Lua state) and by the Oracle's NPC script (data/npc/scripts/
-- ascendant_oracle.lua, its own Lua state). Tests: server/tests/ascension_quest_test.lua (luajit and lua5.3).
--
-- Stages (storage Chaos.ascensionQuest.storage.stage):
--   0 not started -> the Calling (talk to the Oracle) -> 1 Proof of Strength (rare / legendary kills at your level)
--   -> 2 the Trial (a runtime-built room, a class-themed guardian) -> 3 the Choice (one of the two ascended classes)
--   -> 4 ascended
-- The level rule and the choices come from Chaos.classes.ascension at call time, so a new class line works without
-- changes here.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.ascensionQuest then
	Chaos.ascensionQuest = dofile("data/scripts/chaos/ascension_quest_config.lua")
end

ChaosAscensionQuestCore = ChaosAscensionQuestCore or {}
local M = ChaosAscensionQuestCore

-- Texts take an optional `lang` ("pt-BR" | "en"): through ChaosI18n (i18n_core.lua) when it is loaded, else English.
-- ascension_quest.lua passes Chaos.lang(player), the Oracle ChaosI18n.langOf(player).
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

M.STAGE = {NONE = 0, PROOF = 1, TRIAL = 2, CHOICE = 3, DONE = 4}

function M.cfg()
	return Chaos.ascensionQuest
end

local function classes()
	return Chaos.classes
end

-- a stored stage value (-1 = never set) as 0..4
function M.stage(raw)
	local n = math.floor(tonumber(raw) or 0)
	if n < 0 then
		return 0
	end
	return math.min(n, M.STAGE.DONE)
end

-- ------------------------------------------------------------------------------------------------ classes
function M.baseOf(vocId)
	return classes().baseOf[vocId]
end

-- the two ascended classes of a base class as a list sorted by word: {{word = "berserker", id = 14}, ...}; nil when the
-- base class has none
function M.choicesOf(baseId)
	local map = classes().ascension.choices[baseId]
	if not map then
		return nil
	end
	local list = {}
	for word, id in pairs(map) do
		list[#list + 1] = {word = word, id = id}
	end
	table.sort(list, function(a, b) return a.word < b.word end)
	return list
end

function M.isAscendedId(vocId)
	local base = classes().baseOf[vocId]
	return base ~= nil and base ~= vocId and classes().ascension.choices[base] ~= nil
end

-- who may walk the quest: ok, code, text. code: "noline" (no ascension for this vocation), "ascended" (already),
-- "level" (below Chaos.classes.ascension.minLevel)
function M.eligibility(vocId, level, lang)
	local base = classes().baseOf[vocId]
	if not base or not classes().ascension.choices[base] then
		return false, "noline", T(lang, "Your path holds no ascension, wanderer.")
	end
	if base ~= vocId then
		return false, "ascended", T(lang, "You have ascended already. Your path is chosen; only the store's Vocation Change can alter it.")
	end
	local minLevel = classes().ascension.minLevel
	if (tonumber(level) or 0) < minLevel then
		return false, "level", T(lang, "You are not ready. Return when you have reached level %d.", minLevel)
	end
	return true, "ok"
end

-- the ascended class a word names for this character, or nil and the reason (the Choice, stage 3)
function M.validateChoice(vocId, word, stage, lang)
	local ok, code, text = M.eligibility(vocId, math.huge, lang)
	if not ok then
		return nil, text, code
	end
	-- DONE too: a character the store's Vocation Change took back to the base class may choose again
	if M.stage(stage) < M.STAGE.CHOICE then
		return nil, T(lang, "You have not passed the Trial yet."), "stage"
	end
	local w = (tostring(word or "")):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local id = classes().ascension.choices[vocId][w]
	if not id then
		local words = {}
		for _, c in ipairs(M.choicesOf(vocId)) do
			words[#words + 1] = c.word
		end
		return nil, T(lang, "Choose: %s.", table.concat(words, T(lang, " or "))), "word"
	end
	return id
end

-- the first ascended class word of the character's line found in a chat line ("I choose the berserker path")
function M.choiceInText(vocId, text)
	local base = classes().baseOf[vocId]
	local list = base and M.choicesOf(base)
	if not list then
		return nil
	end
	local t = (tostring(text or "")):lower()
	for _, c in ipairs(list) do
		if t:find(c.word, 1, true) then
			return c.word, c.id
		end
	end
	return nil
end

-- ------------------------------------------------------------------------------------------------ texts
-- the Calling: the two paths of the base class. nameOf(id) -> vocation name; describe(word, id) -> text or nil
function M.pathText(word, id, nameOf, lang)
	local p = M.cfg().paths[word]
	if p then
		return T(lang, p)
	end
	local name = nameOf and nameOf(id) or word
	return T(lang, "the %s", tostring(name))
end

function M.callingText(baseName, baseId, nameOf, lang)
	local list = M.choicesOf(baseId) or {}
	local parts = {}
	for i, c in ipairs(list) do
		parts[#parts + 1] = T(lang, i == 1 and "%s ({%s})." or "The other is %s ({%s}).", M.pathText(c.word, c.id, nameOf, lang), c.word)
	end
	return T(lang, "Two roads rise from the %s. One is %s", tostring(baseName), table.concat(parts, " "))
end

function M.proofText(points, lang)
	local p = M.cfg().proof
	return T(lang, "Prove your strength: slay rare and legendary beasts that are worthy of your level. A rare one counts %d, a legendary one %d. You have %d of %d.",
		p.points.rare or 0, p.points.legendary or 0, math.max(0, points or 0), p.needed)
end

-- ------------------------------------------------------------------------------------------------ Proof of Strength
-- the hunting level of a monster, as tools/gen_bounty_pool.py estimates it for monsters without a level range
function M.estimateLevel(experience, health)
	local byExp = 1.6 * math.sqrt(math.max(tonumber(experience) or 0, 1))
	local byHp = (tonumber(health) or 0) / 60
	local lvl = math.max(byExp, math.min(byHp, byExp * 1.5))
	return math.max(1, math.floor(lvl + 0.5))
end

-- the lowest hunting level (the level the player sees) of a monster that counts for a player of this level
function M.minHuntingLevel(playerLevel)
	local p = M.cfg().proof
	return math.max(p.minMonsterLevel or 0, math.floor((p.levelShare or 0) * (tonumber(playerLevel) or 0)))
end

-- the same bar in bounty-pool levels, the scale monsterLevel and proofPoints compare: hunting level = pool level x
-- Chaos.huntingMult(). Before 2026-10-28 the hunting bar was compared with pool levels, so a level 202 player was
-- asked for monsters of hunting level 242 (1.2 x) instead of 121.
function M.minMonsterLevel(playerLevel)
	local mult = Chaos.huntingMult and Chaos.huntingMult() or 1
	return math.ceil(M.minHuntingLevel(playerLevel) / mult)
end

-- points a kill is worth: tier = "normal" | "magic" | "rare" | "legendary" | "boss"
function M.proofPoints(tier, monsterLevel, playerLevel)
	local pts = M.cfg().proof.points[tier]
	if not pts or pts <= 0 then
		return 0, "tier"
	end
	if (tonumber(monsterLevel) or 0) < M.minMonsterLevel(playerLevel) then
		return 0, "level"
	end
	return pts
end

-- new points (capped at needed) and whether the Proof is complete
function M.addProof(current, add)
	local need = M.cfg().proof.needed
	local n = math.min(need, math.max(0, tonumber(current) or 0) + math.max(0, tonumber(add) or 0))
	return n, n >= need
end

-- ------------------------------------------------------------------------------------------------ the Trial
-- may the character enter: ok, reason
function M.canEnterTrial(stage, now, cooldownUntil, busy, lang)
	if M.stage(stage) ~= M.STAGE.TRIAL then
		if M.stage(stage) < M.STAGE.TRIAL then
			return false, T(lang, "The Trial is closed to you until your strength is proven.")
		end
		return false, T(lang, "You have passed the Trial already.")
	end
	if busy then
		return false, T(lang, "You are in a trial already.")
	end
	local wait = (tonumber(cooldownUntil) or 0) - (tonumber(now) or 0)
	if wait > 0 then
		return false, T(lang, "The Trial rejects you for now. Return in %s.", M.formatWait(wait, lang))
	end
	return true
end

function M.formatWait(seconds, lang)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 60 then
		local m = math.ceil(seconds / 60)
		return m == 1 and T(lang, "1 minute") or T(lang, "%d minutes", m)
	end
	return seconds == 1 and T(lang, "1 second") or T(lang, "%d seconds", seconds)
end

-- the guardian's numbers for a player of this level (the level is clamped to scaleMin..scaleMax)
function M.trialScale(level)
	local t = M.cfg().trial
	local lvl = math.max(t.scaleMin, math.min(t.scaleMax, math.floor(tonumber(level) or 0)))
	local factor = lvl / t.scaleMin
	return {
		level = lvl,
		factor = factor,
		health = math.floor(t.guardianHealth * factor + 0.5),
		addHealth = math.floor(t.addHealth * factor + 0.5),
		damage = t.guardianDamage * factor
	}
end

-- the guardian entry of a base class (the default for lines without one)
function M.guardianFor(baseId)
	local g = M.cfg().guardians
	return g[baseId] or g.default
end

function M.hasMechanic(guardian, name)
	for _, m in ipairs(guardian and guardian.mechanics or {}) do
		if m == name then
			return true
		end
	end
	return false
end

-- damage multiplier of the guardian's own hits: the scale, x enrageMultiplier below enrageBelow of its health
function M.guardianMultiplier(guardian, scale, health, maxHealth)
	local t = M.cfg().trial
	local mult = scale.damage
	if M.hasMechanic(guardian, "enrage") and maxHealth and maxHealth > 0 and health / maxHealth < t.enrageBelow then
		mult = mult * t.enrageMultiplier
	end
	return mult
end

-- "stillness": state = {key, since, warned}; returns "move" (moved), "wait", "warn" or "slam" (and resets the timer)
function M.stillness(state, posKey, now)
	local t = M.cfg().trial
	if state.key ~= posKey then
		state.key, state.since, state.warned = posKey, now, false
		return "move"
	end
	local still = now - (state.since or now)
	if still >= t.stillMs then
		state.since, state.warned = now, false
		return "slam"
	end
	if still >= t.stillWarnMs and not state.warned then
		state.warned = true
		return "warn"
	end
	return "wait"
end

-- "zones": `count` distinct tiles within `radius` of the centre, the centre first; rand(n) -> 1..n
function M.zoneTiles(center, count, radius, rand)
	local list, seen = {{x = center.x, y = center.y, z = center.z}}, {[center.x .. ":" .. center.y] = true}
	local candidates = {}
	for dx = -radius, radius do
		for dy = -radius, radius do
			if dx ~= 0 or dy ~= 0 then
				candidates[#candidates + 1] = {x = center.x + dx, y = center.y + dy, z = center.z}
			end
		end
	end
	while #list < count and #candidates > 0 do
		local i = rand(#candidates)
		local c = table.remove(candidates, i)
		local key = c.x .. ":" .. c.y
		if not seen[key] then
			seen[key] = true
			list[#list + 1] = c
		end
	end
	return list
end

-- a hit that would kill is cut to leave 1 health (as arena_core.lua): primary, secondary, caught
function M.catchDamage(health, primary, secondary)
	primary, secondary = math.max(0, primary or 0), math.max(0, secondary or 0)
	if primary + secondary < health then
		return primary, secondary, false
	end
	local keep = math.max(0, health - 1)
	local p = math.min(primary, keep)
	local s = math.min(secondary, keep - p)
	return p, s, true
end

-- geometry of trial slot `slot` (1..slots): walls around an inner square, basins in the inner corners
function M.layout(slot)
	local t = M.cfg().trial
	local g = t.grid
	local col = (slot - 1) % g.cols
	local row = math.floor((slot - 1) / g.cols)
	local ox, oy, z = g.origin.x + col * g.spacing, g.origin.y + row * g.spacing, g.origin.z
	local n = t.inner
	local L = {slot = slot, x1 = ox + 1, y1 = oy + 1, x2 = ox + n, y2 = oy + n, z = z, floor = {}, walls = {}, basins = {}}
	for x = ox, ox + n + 1 do
		for y = oy, oy + n + 1 do
			local p = {x = x, y = y, z = z}
			if x == ox or y == oy or x == ox + n + 1 or y == oy + n + 1 then
				L.walls[#L.walls + 1] = p
			else
				L.floor[#L.floor + 1] = p
			end
		end
	end
	L.basins = {{x = L.x1, y = L.y1, z = z}, {x = L.x2, y = L.y1, z = z}, {x = L.x1, y = L.y2, z = z}, {x = L.x2, y = L.y2, z = z}}
	local cx, cy = ox + math.floor((n + 1) / 2), oy + math.floor((n + 1) / 2)
	L.center = {x = cx, y = cy, z = z}
	-- six tiles apart: both on the player's screen from the start
	L.playerStart = {x = cx, y = cy + 3, z = z}
	L.guardianStart = {x = cx, y = cy - 3, z = z}
	return L
end

-- the slot a position is in (walls included), or nil
function M.slotAt(pos)
	local t = M.cfg().trial
	local g = t.grid
	if not pos or pos.z ~= g.origin.z then
		return nil
	end
	local dx, dy = pos.x - g.origin.x, pos.y - g.origin.y
	if dx < 0 or dy < 0 then
		return nil
	end
	local col, row = math.floor(dx / g.spacing), math.floor(dy / g.spacing)
	if col >= g.cols or dx % g.spacing > t.inner + 1 or dy % g.spacing > t.inner + 1 then
		return nil
	end
	local slot = row * g.cols + col + 1
	if slot > g.slots then
		return nil
	end
	return slot
end

-- inside the room (not on a wall) of `slot`
function M.inRoom(L, pos)
	return pos ~= nil and pos.z == L.z and pos.x >= L.x1 and pos.x <= L.x2 and pos.y >= L.y1 and pos.y <= L.y2
end

-- ------------------------------------------------------------------------------------------------ !ascend and staff
-- what !ascend does: true = the old command runs; false, text = the player is sent to the Oracle.
-- mode "open" keeps the command for everyone; staff keeps it always; a migrated character's free switch keeps working.
function M.commandGate(mode, isStaff, freeSwitchPending, lang)
	if mode == "open" or isStaff or freeSwitchPending then
		return true
	end
	return false, T(lang, "Ascension is earned, not claimed. Speak with the %s in the teleport room's market.", M.cfg().npc.name)
end

-- "/ascendset <player>, <class>": name, ascended vocation id (any line) or nil and the reason
function M.parseAscendSet(param)
	local name, word = (tostring(param or "")):match("^%s*(.-)%s*,%s*(%S+)%s*$")
	if not name or name == "" then
		return nil, nil, "Usage: /ascendset <player>, <ascended class>"
	end
	word = word:lower()
	for base, map in pairs(classes().ascension.choices) do
		if map[word] then
			return name, map[word], nil, base
		end
	end
	return name, nil, "Unknown ascended class: " .. word .. "."
end

-- ------------------------------------------------------------------------------------------------ rewards
-- the name plate title of an ascended character (titles.lua): nil for anything else
function M.titleFor(vocId, vocName, at)
	local tc = M.cfg().title
	if not tc or not tc.enabled or not M.isAscendedId(vocId) or not vocName then
		return nil
	end
	local text = (tc.prefix or "") .. vocName
	if #text > 24 then
		text = vocName
	end
	return {text = text, key = "ascension:" .. vocName:lower(), color = tc.color, at = (at and at > 0) and at or nil, priority = 1}
end

-- ------------------------------------------------------------------------------------------------ modal windows
-- Engine helpers, shared by the Oracle (its NPC Lua state) and ascension_quest.lua: the answers always arrive in the
-- scripts' state (CreatureEvent "ChaosAscensionModal"), which checks everything again.
function M.sendModal(player, id, title, text, buttons, choices)
	if not ModalWindow then
		return false
	end
	local w = ModalWindow(id, title, text)
	for i, c in ipairs(choices or {}) do
		w:addChoice(i, c)
	end
	for _, b in ipairs(buttons) do
		w:addButton(b[1], b[2])
	end
	w:setDefaultEnterButton(buttons[1][1])
	w:setDefaultEscapeButton(buttons[#buttons][1])
	w:sendToPlayer(player)
	return true
end

function M.sendTrialModal(player, baseId, lang)
	local g = M.guardianFor(baseId)
	local t = M.cfg().trial
	local text = T(lang, "The %s waits beyond the veil. You go alone; you have %d seconds to break it.\n\n%s\n\nIf you fall, the Oracle pulls you back unharmed: no experience, no items lost. You may try again after %s.",
		g.name, t.timeLimitSeconds, g.hint and T(lang, g.hint) or "", M.formatWait(t.cooldownSeconds, lang))
	return M.sendModal(player, M.cfg().modal.trial, T(lang, "The Trial of Ascension"), text,
		{{1, T(lang, "Enter")}, {2, T(lang, "Not yet")}})
end

-- nameOf(id) -> vocation name
function M.sendChoiceModal(player, baseId, nameOf, lang)
	local list = M.choicesOf(baseId) or {}
	local names, lines = {}, {}
	for _, c in ipairs(list) do
		local name = nameOf and nameOf(c.id) or c.word
		names[#names + 1] = name
		lines[#lines + 1] = "- " .. M.pathText(c.word, c.id, nameOf, lang)
	end
	local text = T(lang, "Choose the path you will walk. The choice is final; only the store's Vocation Change can alter it.\n\n%s",
		table.concat(lines, "\n"))
	return M.sendModal(player, M.cfg().modal.choice, T(lang, "The Choice"), text,
		{{1, T(lang, "Choose")}, {2, T(lang, "Not yet")}}, names)
end

function M.sendConfirmModal(player, id, word, name, lang)
	local text = T(lang, "You will walk the path of %s.\n\nThis is final. Ascend?",
		M.pathText(word, id, function() return name end, lang))
	return M.sendModal(player, M.cfg().modal.confirmBase + id, T(lang, "Ascend as %s?", tostring(name)), text,
		{{1, T(lang, "Ascend")}, {2, T(lang, "Cancel")}})
end

return M
