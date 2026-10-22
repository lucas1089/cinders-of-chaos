-- tales_core.lua: the pure rules of the tales (tales_config.lua; docs/CONTENT.md "Tales"). No engine calls: the engine
-- file is tales.lua, the NPC script data/npc/scripts/archivist_maelis.lua; both read their texts and rules here.
-- tests/tales_test.lua covers it. Lua 5.1 / LuaJIT and 5.3.
--
-- A tale's state (player storage, tales_config.lua `storage`): 0 not taken, 1..n the step in progress, 100 done; a
-- second storage counts the kills of the current kill step. Steps: kill (credit by monster type or shown name),
-- deliver (items handed over at the Archivist), report (talk to her), visit (stand near a place: tales.lua checks
-- the characters with such a step every few seconds) and talk (speak with another NPC of ours: the NPC's script
-- calls M.talkTo). kill, visit and talk are done in the field; deliver and report at the Archivist. A tale may need
-- another one done first (`requires`): the chains.

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

-- slots 1..storage.slots live in the first block (+1 + slot state, +21 + slot count); the later slots in the second
-- block (storage.ext: +0 + n state, +count + n count, n = slot - storage.slots - 1)
local function extOf(t)
	local s = M.cfg().storage
	local first = s.slots or 19
	if s.ext and t.slot > first then
		return s.ext, t.slot - first - 1
	end
	return nil
end

function M.stateKey(t)
	local s = M.cfg().storage
	local e, n = extOf(t)
	if e then
		return e.base + n
	end
	return s.base + s.state + t.slot
end

function M.countKey(t)
	local s = M.cfg().storage
	local e, n = extOf(t)
	if e then
		return e.base + e.count + n
	end
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

-- the step kinds: done in the field (kill, visit, talk) or at the Archivist (deliver, report)
M.FIELD = {kill = true, visit = true, talk = true}
M.KINDS = {kill = true, visit = true, talk = true, deliver = true, report = true}

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

-- is the tale a chain needs done first (t.requires) done? stateOf(t) -> stored state; without stateOf only the tales
-- without a requirement pass
function M.unlocked(t, stateOf)
	if not t.requires then
		return true
	end
	local r = M.tale(t.requires)
	if not r or not stateOf then
		return false
	end
	return M.state(r, stateOf(r)) == M.cfg().done
end

function M.canTake(t, level, stateOf)
	return (tonumber(level) or 0) >= t.minLevel and M.unlocked(t, stateOf)
end

-- accept: ok, new state | false, reason ("level", "taken", "requires"). stateOf: the other tales' states (chains)
function M.accept(t, state, level, stateOf)
	if M.state(t, state) ~= 0 then
		return false, "taken"
	end
	if (tonumber(level) or 0) < t.minLevel then
		return false, "level"
	end
	if not M.unlocked(t, stateOf) then
		return false, "requires"
	end
	return true, 1
end

-- the state after a field step (kill, visit, talk) is done. A tale ends at the Archivist (deliver or report; checked
-- by M.problems), so this is never past the last step. Before, a kill as the last step marked the tale done (100)
-- with no reward; the guard keeps a bad config from doing that: the tale stays on its last step.
function M.advance(t, state)
	state = M.state(t, state)
	if state < 1 or state >= #t.steps then
		return state
	end
	return state + 1
end

-- the current step when it is of `kind`, or nil
function M.current(t, state, kind)
	state = M.state(t, state)
	local step = state >= 1 and state <= #t.steps and t.steps[state] or nil
	if step and step.kind == kind then
		return step
	end
	return nil
end

-- a visit step: is the position {x, y, z} at the step's place (same floor, within `radius` tiles; default 5)
function M.atPlace(step, pos)
	if not step or step.kind ~= "visit" or type(pos) ~= "table" then
		return false
	end
	local p, r = step.pos, step.radius or 5
	return pos.z == p.z and math.abs(pos.x - p.x) <= r and math.abs(pos.y - p.y) <= r
end

-- a visit: new state, event ("step") or nil
function M.visit(t, state, pos)
	local step = M.current(t, state, "visit")
	if step and M.atPlace(step, pos) then
		return M.advance(t, state), "step"
	end
	return M.state(t, state), nil
end

-- the talk steps that name this NPC: every such tale advances. stateOf(t) -> stored state; setState(t, v) writes it
-- (the NPC's script, in its own Lua state). -> {{tale = t, step = step, state = new state}}
function M.talkTo(npcName, stateOf, setState)
	local out = {}
	local name = tostring(npcName or ""):lower()
	for _, t in ipairs(M.tales()) do
		local state = stateOf(t)
		local step = M.current(t, state, "talk")
		if step and tostring(step.npc):lower() == name then
			local ns = M.advance(t, state)
			if setState then
				setState(t, ns)
			end
			out[#out + 1] = {tale = t, step = step, state = ns}
		end
	end
	return out
end

-- does any tale of the character wait for a visit (tales.lua keeps those characters on its watch list)
function M.visiting(stateOf)
	for _, t in ipairs(M.tales()) do
		if M.current(t, stateOf(t), "visit") then
			return true
		end
	end
	return false
end

-- the config's mistakes (the test, and tales.lua at startup): a list of lines, empty when sound
function M.problems(cfg)
	cfg = cfg or M.cfg()
	local out, slots, keys, byKey = {}, {}, {}, {}
	local s = cfg.storage
	local function bad(t, why)
		out[#out + 1] = tostring(t.key) .. ": " .. why
	end
	for _, t in ipairs(cfg.tales) do
		if byKey[t.key] then
			bad(t, "key used twice")
		end
		byKey[t.key] = t
	end
	for _, t in ipairs(cfg.tales) do
		if slots[t.slot] then
			bad(t, "slot used twice")
		end
		slots[t.slot] = true
		for _, k in ipairs({M.stateKey(t), M.countKey(t)}) do
			local inBase = k > s.base + s.lang and k <= s.last
			local inExt = s.ext and k >= s.ext.base and k <= s.ext.last
			if not inBase and not inExt then
				bad(t, "storage " .. k .. " outside the blocks")
			end
			if keys[k] then
				bad(t, "storage " .. k .. " shared")
			end
			keys[k] = true
		end
		if #t.steps < 1 then
			bad(t, "no steps")
		end
		for i, step in ipairs(t.steps) do
			if not M.KINDS[step.kind] then
				bad(t, "step " .. i .. " kind " .. tostring(step.kind))
			elseif step.kind == "kill" and (not step.count or step.count < 1 or #(step.monsters or {}) < 1) then
				bad(t, "step " .. i .. ": a kill needs a count and monsters")
			elseif step.kind == "visit" and not (step.pos and step.pos.x and step.pos.y and step.pos.z) then
				bad(t, "step " .. i .. ": a visit needs pos")
			elseif step.kind == "talk" and (type(step.npc) ~= "string" or type(step.reply) ~= "table") then
				bad(t, "step " .. i .. ": a talk needs npc and reply")
			elseif step.kind == "deliver" and #(step.items or {}) < 1 then
				bad(t, "step " .. i .. ": a delivery needs items")
			end
		end
		local last = t.steps[#t.steps]
		if last and M.FIELD[last.kind] then
			bad(t, "the last step must be done at the Archivist (deliver or report)")
		end
		if t.requires then
			local r = byKey[t.requires]
			if not r then
				bad(t, "requires an unknown tale " .. tostring(t.requires))
			elseif r.minLevel > t.minLevel or r == t then
				bad(t, "requires a tale of a higher level")
			end
		end
	end
	return out
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
		return M.advance(t, state), 0, "step"
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
	if M.FIELD[step.kind] then
		return false, step.kind
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

-- the level a tale's experience is measured at: the character's, at most the top of the tale's band. Without the cap a
-- level 2000 character took a share of ITS next level from a level 200 tale (and would from every low tale).
function M.xpLevel(t, level)
	level = max(1, floor(tonumber(level) or 1))
	local top = t.band and tonumber(t.band[2])
	if top and level > top then
		return top
	end
	return level
end

function M.taleXp(t, level)
	return M.xpFor(M.xpLevel(t, level), t.rewards and t.rewards.xpLevels or 0)
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
		out[#out + 1] = string.format(M.t(ui.xp, lang), money(M.taleXp(t, level)))
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

-- the list window: {title, text, choices = {{key, label}}}; stateOf(t) -> stored state. The tales in progress first,
-- then the new ones, then the done ones; by level within each. The NPC's list and the answer in tales.lua both call
-- this, so a choice index names the same tale. A chain's next tale shows once the one before is done.
local GROUP = {on = 1, ready = 1, new = 2, done = 3}
function M.listView(level, stateOf, lang)
	local ui = M.cfg().ui
	local rows, nextLevel = {}, nil
	for i, t in ipairs(M.tales()) do
		local st = M.status(t, stateOf(t))
		if M.canTake(t, level, stateOf) or st ~= "new" then
			rows[#rows + 1] = {t = t, st = st, i = i}
		elseif M.unlocked(t, stateOf) and (not nextLevel or t.minLevel < nextLevel) then
			nextLevel = t.minLevel
		end
	end
	table.sort(rows, function(a, b)
		if GROUP[a.st] ~= GROUP[b.st] then
			return GROUP[a.st] < GROUP[b.st]
		end
		if a.t.minLevel ~= b.t.minLevel then
			return a.t.minLevel < b.t.minLevel
		end
		return a.i < b.i
	end)
	local choices = {}
	for _, r in ipairs(rows) do
		choices[#choices + 1] = {key = r.t.key, label = string.format("%s (%s)", M.t(r.t.name, lang), statusWord(r.st, lang))}
	end
	local text = M.t(ui.listText, lang)
	if #choices == 0 then
		text = string.format(M.t(ui.none, lang), nextLevel or 0)
	end
	return {title = M.t(ui.listTitle, lang), text = text, choices = choices}
end

-- one tale: {title, text, buttons = {"accept" | "turnin" ...}}; stateOf: the other tales' states (chains)
function M.taleView(t, state, count, lang, level, stateOf)
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
	if st == "new" and M.canTake(t, level, stateOf) then
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
