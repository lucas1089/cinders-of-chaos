-- tales_core.lua: the pure rules of the tales (tales_config.lua; docs/CONTENT.md "Tales"). No engine calls: the engine
-- file is tales.lua, the NPC script data/npc/scripts/archivist_maelis.lua; both read their texts and rules here.
-- tests/tales_test.lua covers it. Lua 5.1 / LuaJIT and 5.3.
--
-- A tale's state (player storage, tales_config.lua `storage`): 0 not taken, 1..n the step in progress, 100 done; a
-- second storage counts the kills of the current kill step. Steps: kill (credit by monster type or shown name),
-- deliver (items handed over at the Archivist), report (talk to her).

ChaosTalesCore = ChaosTalesCore or {}
local M = ChaosTalesCore

local floor, max, min = math.floor, math.max, math.min

local function load(path)
	local ok, t = pcall(dofile, path)
	if ok and type(t) == "table" then
		return t
	end
	return nil
end

function M.cfg()
	if not M.config then
		M.config = load("data/scripts/chaos/tales_config.lua")
	end
	return M.config
end

function M.lore()
	if not M.loreData then
		M.loreData = load("data/scripts/chaos/lore_data.lua") or {kinds = {}, entries = {}}
		M.loreById = {}
		for _, e in ipairs(M.loreData.entries) do
			M.loreById[e.id] = e
		end
	end
	return M.loreData
end

function M.loreEntry(id)
	M.lore()
	return M.loreById[id]
end

-- ------------------------------------------------------------------------------------------------ language
-- "en" or "pt": the hook (the localization work's Chaos.lang, when it exists) wins, else the stored choice (2 = pt)
function M.lang(stored, hooked)
	if hooked == "pt" or hooked == "pt-BR" or hooked == "pt_BR" or hooked == "ptbr" then
		return "pt"
	elseif hooked == "en" then
		return "en"
	end
	return tonumber(stored) == 2 and "pt" or "en"
end

function M.langCode(lang)
	return lang == "pt" and 2 or 1
end

-- a text table {en, pt} (or a plain string) in a language, English when the language is missing
function M.t(text, lang)
	if type(text) ~= "table" then
		return tostring(text or "")
	end
	return text[lang] or text.en or ""
end

local function plain(msg)
	local s = " " .. tostring(msg or ""):lower() .. " "
	-- the accented letters of Portuguese, as the NPC channel may send them, folded to plain ASCII
	local fold = {["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["é"] = "e", ["ê"] = "e", ["í"] = "i", ["ó"] = "o",
		["ô"] = "o", ["õ"] = "o", ["ú"] = "u", ["ç"] = "c", ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o",
		["Ú"] = "u", ["Ç"] = "c", ["Ã"] = "a", ["Õ"] = "o", ["Â"] = "a", ["Ê"] = "e", ["Ô"] = "o"}
	for k, v in pairs(fold) do
		s = s:gsub(k, v)
	end
	return (s:gsub("[%p]", " "))
end
M.plain = plain

local function hasWord(text, word)
	word = plain(word):gsub("^%s+", ""):gsub("%s+$", "")
	return text:find(" " .. word .. " ", 1, true) ~= nil
end

-- a language switch said to the NPC: "pt", "en" or nil
function M.langWord(msg)
	local s = plain(msg)
	for _, w in ipairs({"portugues", "pt br", "ptbr", "brasileiro"}) do
		if hasWord(s, w) then
			return "pt"
		end
	end
	for _, w in ipairs({"english", "ingles"}) do
		if hasWord(s, w) then
			return "en"
		end
	end
	return nil
end

-- does the message ask for the tales
function M.asksTales(msg)
	local s = plain(msg)
	for _, w in ipairs({"tale", "tales", "quest", "quests", "mission", "missions", "task", "historia", "historias",
		"missao", "missoes", "tarefa", "tarefas"}) do
		if hasWord(s, w) then
			return true
		end
	end
	return false
end

-- the lore entry a message names (first match by entry order), or nil
function M.loreFor(msg)
	local s = plain(msg)
	for _, e in ipairs(M.lore().entries) do
		for _, k in ipairs(e.keywords or {}) do
			if hasWord(s, k) then
				return e
			end
		end
	end
	return nil
end

function M.loreText(e, lang)
	local p = e and (e[lang] or e.en) or {}
	return table.concat(p, " ")
end

-- the lore topics, one line ("names: a, b, c")
function M.loreTopics(lang)
	local out = {}
	for _, e in ipairs(M.lore().entries) do
		out[#out + 1] = e.keywords and e.keywords[1] or e.id
	end
	return table.concat(out, ", ")
end

-- the book of a lore entry: title, text (a stock book holds 1023 characters)
function M.book(id, lang)
	local e = M.loreEntry(id)
	if not e then
		return nil
	end
	local text = e.name .. "\n\n" .. table.concat(e[lang] or e.en, "\n\n")
	if #text > 1023 then
		text = text:sub(1, 1020) .. "..."
	end
	return e.name, text
end

-- ------------------------------------------------------------------------------------------------ tales and states
function M.tales()
	return M.cfg().tales
end

function M.tale(key)
	for _, t in ipairs(M.tales()) do
		if t.key == key then
			return t
		end
	end
	return nil
end

function M.stateKey(t)
	local s = M.cfg().storage
	return s.base + s.state + t.slot
end

function M.countKey(t)
	local s = M.cfg().storage
	return s.base + s.count + t.slot
end

function M.langKey()
	local s = M.cfg().storage
	return s.base + s.lang
end

-- 0 (not taken), 1..#steps, or done (100)
function M.state(t, v)
	v = floor(tonumber(v) or 0)
	if v >= M.cfg().done then
		return M.cfg().done
	end
	if v < 1 then
		return 0
	end
	return min(v, #t.steps)
end

function M.count(v)
	return max(0, floor(tonumber(v) or 0))
end

-- "new", "on", "ready" (the current step is done at the Archivist) or "done"
function M.status(t, state)
	state = M.state(t, state)
	if state == M.cfg().done then
		return "done"
	elseif state == 0 then
		return "new"
	end
	local step = t.steps[state]
	if step.kind == "report" or step.kind == "deliver" then
		return "ready"
	end
	return "on"
end

function M.canTake(t, level)
	return (tonumber(level) or 0) >= t.minLevel
end

-- accept: ok, new state | false, reason ("level", "taken")
function M.accept(t, state, level)
	if M.state(t, state) ~= 0 then
		return false, "taken"
	end
	if not M.canTake(t, level) then
		return false, "level"
	end
	return true, 1
end

local function eqName(a, b)
	return a and b and tostring(a):lower() == tostring(b):lower()
end

function M.matches(step, typeName, shownName)
	if not step or step.kind ~= "kill" then
		return false
	end
	for _, m in ipairs(step.monsters or {}) do
		if eqName(m, typeName) or eqName(m, shownName) then
			return true
		end
	end
	return false
end

-- a kill: new state, new count, event ("progress", "step" when the step is done) or nil when it does not count
function M.addKill(t, state, count, typeName, shownName)
	state, count = M.state(t, state), M.count(count)
	if state < 1 or state > #t.steps then
		return state, count, nil
	end
	local step = t.steps[state]
	if not M.matches(step, typeName, shownName) then
		return state, count, nil
	end
	count = count + 1
	if count >= step.count then
		return state + 1 <= #t.steps and state + 1 or M.cfg().done, 0, "step"
	end
	return state, count, "progress"
end

-- turn in at the Archivist. has(id) -> the count the character holds.
-- -> ok, new state, take ({{id, count}} to remove), finished | false, reason ("kill" step not done, "missing" items)
function M.turnIn(t, state, count, has)
	state = M.state(t, state)
	if state < 1 or state > #t.steps then
		return false, "state"
	end
	local step = t.steps[state]
	local take = {}
	if step.kind == "kill" then
		return false, "kill"
	elseif step.kind == "deliver" then
		for _, it in ipairs(step.items) do
			local n = tonumber(has and has(it.id)) or 0
			if n < it.count then
				return false, "missing", it, it.count - n
			end
			take[#take + 1] = {it.id, it.count}
		end
	end
	local nextState = state + 1
	-- a report step right after a deliver step is answered by the same turn-in
	while nextState <= #t.steps and t.steps[nextState].kind == "report" and step.kind ~= "report" do
		nextState = nextState + 1
	end
	if nextState > #t.steps then
		return true, M.cfg().done, take, true
	end
	return true, nextState, take, false
end

-- ------------------------------------------------------------------------------------------------ rewards
-- the engine's experience for a level (Player::getExpForLevel)
function M.expForLevel(level)
	local l = max(0, (tonumber(level) or 1) - 1)
	return floor((50 * l * l * l - 150 * l * l + 400 * l) / 3)
end

function M.xpFor(level, share)
	level = max(1, floor(tonumber(level) or 1))
	return floor((M.expForLevel(level + 1) - M.expForLevel(level)) * (tonumber(share) or 0))
end

local function money(n)
	local s = tostring(floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
M.money = money

function M.rewardLines(t, lang, level)
	local ui, r = M.cfg().ui, t.rewards
	local out = {}
	if r.xpLevels and r.xpLevels > 0 then
		out[#out + 1] = string.format(M.t(ui.xp, lang), money(M.xpFor(level, r.xpLevels)))
	end
	if r.gold and r.gold > 0 then
		out[#out + 1] = string.format(M.t(ui.gold, lang), money(r.gold))
	end
	for _, it in ipairs(r.items or {}) do
		out[#out + 1] = string.format("%d x %s", it.count, it.name)
	end
	if r.rep and r.rep > 0 and t.faction then
		out[#out + 1] = string.format(M.t(ui.rep, lang), r.rep, M.cfg().factions[t.faction] or t.faction)
	end
	if r.book then
		local e = M.loreEntry(r.book)
		if e then
			out[#out + 1] = string.format(M.t(ui.book, lang), e.name)
		end
	end
	return out
end

-- ------------------------------------------------------------------------------------------------ views
local function statusWord(st, lang)
	local ui = M.cfg().ui
	return M.t(({new = ui.stateNew, on = ui.stateOn, ready = ui.stateReady, done = ui.stateDone})[st], lang)
end

-- the list window: {title, text, choices = {{key, label}}}; stateOf(t) -> stored state
function M.listView(level, stateOf, lang)
	local ui = M.cfg().ui
	local choices, nextLevel = {}, nil
	for _, t in ipairs(M.tales()) do
		local st = M.status(t, stateOf(t))
		if M.canTake(t, level) or st ~= "new" then
			choices[#choices + 1] = {key = t.key, label = string.format("%s (%s)", M.t(t.name, lang), statusWord(st, lang))}
		elseif not nextLevel or t.minLevel < nextLevel then
			nextLevel = t.minLevel
		end
	end
	local text = M.t(ui.listText, lang)
	if #choices == 0 then
		text = string.format(M.t(ui.none, lang), nextLevel or 0)
	end
	return {title = M.t(ui.listTitle, lang), text = text, choices = choices}
end

-- one tale: {title, text, buttons = {"accept" | "turnin" ...}}
function M.taleView(t, state, count, lang, level)
	local ui = M.cfg().ui
	state, count = M.state(t, state), M.count(count)
	local st = M.status(t, state)
	local lines = {M.t(t.story, lang), "", M.t(ui.steps, lang) .. ":"}
	for i, step in ipairs(t.steps) do
		local mark = (st == "done" or i < state) and "[x]" or (i == state and "[>]" or "[ ]")
		local extra = ""
		if i == state and step.kind == "kill" then
			extra = string.format(" (%d / %d)", count, step.count)
		end
		lines[#lines + 1] = string.format("%s %s%s", mark, M.t(step.text, lang), extra)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = M.t(ui.rewards, lang) .. ": " .. table.concat(M.rewardLines(t, lang, level), ", ")
	if st == "done" and t.outro then
		lines[#lines + 1] = ""
		lines[#lines + 1] = M.t(t.outro, lang)
	end
	local buttons = {}
	if st == "new" and M.canTake(t, level) then
		buttons[#buttons + 1] = "accept"
	elseif st == "ready" then
		buttons[#buttons + 1] = "turnin"
	end
	return {title = M.t(t.name, lang) .. " - " .. string.format(M.t(ui.level, lang), t.minLevel),
		text = table.concat(lines, "\n"), buttons = buttons, status = st}
end

-- one line for !tales: "The Bone Choir (in progress, 12 / 40); ..."
function M.statusLine(level, stateOf, countOf, lang)
	local parts = {}
	for _, t in ipairs(M.tales()) do
		local state = M.state(t, stateOf(t))
		local st = M.status(t, state)
		if st ~= "new" then
			local extra = ""
			local step = t.steps[state]
			if st == "on" and step and step.kind == "kill" then
				extra = string.format(", %d / %d", M.count(countOf(t)), step.count)
			end
			parts[#parts + 1] = string.format("%s (%s%s)", M.t(t.name, lang), statusWord(st, lang), extra)
		end
	end
	if #parts == 0 then
		return nil
	end
	return string.format(M.t(M.cfg().ui.status, lang), table.concat(parts, "; "))
end

return M
