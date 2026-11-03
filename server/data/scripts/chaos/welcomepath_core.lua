-- welcomepath_core.lua: the pure rules of the welcome path (O370; welcomepath_config.lua; docs/CONTENT.md "Welcome
-- path"). No engine calls: welcomepath.lua gathers the facts of a character and acts on what these functions return.
-- Tests: server/tests/welcomepath_test.lua (luajit and lua5.3). Lua 5.1 / LuaJIT and 5.3.
--
-- Facts (what the engine side reads for the current step): {level, kills, flags, spell = bool, gear = bool,
--   stats = {[stat] = value}}. A step is done when M.progress says progress >= target.

ChaosWelcomePathCore = ChaosWelcomePathCore or {}
local M = ChaosWelcomePathCore

local floor, max, min = math.floor, math.max, math.min

local function num(v, d)
	v = tonumber(v)
	if not v or v ~= v then
		return d
	end
	return v
end

function M.cfg()
	if not M.config then
		local ok, t = pcall(dofile, "data/scripts/chaos/welcomepath_config.lua")
		M.config = ok and type(t) == "table" and t or nil
	end
	return M.config
end

function M.lang(code)
	code = tostring(code or "en"):lower()
	return code:sub(1, 2) == "pt" and "pt" or "en"
end

function M.text(t, lang)
	if type(t) ~= "table" then
		return tostring(t or "")
	end
	return t[M.lang(lang)] or t.en or ""
end

function M.hasBit(mask, bit)
	mask = floor(num(mask, 0))
	if mask < 0 then
		return false
	end
	return floor(mask / bit) % 2 == 1
end

function M.setBit(mask, bit)
	mask = max(0, floor(num(mask, 0)))
	if M.hasBit(mask, bit) then
		return mask
	end
	return mask + bit
end

M.FLAG_GOALS = 1

-- the problems of a config (empty list = fine)
function M.validate(cfg)
	local out = {}
	local checks = {spell = true, kills = true, gear = true, stat = true, goals = true}
	local seen = {}
	local s = cfg.storage or {}
	for _, k in ipairs({"state", "step", "kills", "flags"}) do
		local key = num(s.base, 0) + num(s[k], -1000)
		if key < 7101070 or key > 7101079 then
			out[#out + 1] = "storage " .. k .. " outside 7101070-7101079"
		end
	end
	if #(cfg.steps or {}) == 0 then
		out[#out + 1] = "no steps"
	end
	for i, st in ipairs(cfg.steps or {}) do
		local where = "step " .. i .. " (" .. tostring(st.key) .. ")"
		if type(st.key) ~= "string" or seen[st.key] then
			out[#out + 1] = where .. ": no key or a key twice"
		end
		seen[st.key or i] = true
		if not checks[st.check] then
			out[#out + 1] = where .. ": unknown check " .. tostring(st.check)
		end
		if st.check == "stat" and type(st.stat) ~= "string" then
			out[#out + 1] = where .. ": a stat check names no stat"
		end
		if st.check == "kills" and num(st.target, 0) < 1 then
			out[#out + 1] = where .. ": a kills check needs a target"
		end
		for _, f in ipairs({"title", "hint"}) do
			if type(st[f]) ~= "table" or type(st[f].en) ~= "string" or type(st[f].pt) ~= "string" then
				out[#out + 1] = where .. ": " .. f .. " needs en and pt"
			end
		end
		if type(st.reward) ~= "table" then
			out[#out + 1] = where .. ": no reward"
		end
	end
	return out
end

-- the target of a step (1 for the one-time checks)
function M.target(step)
	if step.check == "kills" or step.check == "stat" then
		return max(1, floor(num(step.target, 1)))
	end
	return 1
end

-- progress, target and whether the counter runs yet (false below the step's level: the row shows the level then)
function M.progress(step, facts)
	facts = facts or {}
	local level = num(facts.level, 0)
	if step.level and level < step.level then
		return floor(level), floor(step.level), false
	end
	local target = M.target(step)
	local p = 0
	if step.check == "spell" then
		p = facts.spell and 1 or 0
	elseif step.check == "kills" then
		p = num(facts.kills, 0)
	elseif step.check == "gear" then
		p = facts.gear and 1 or 0
	elseif step.check == "stat" then
		p = num(facts.stats and facts.stats[step.stat], 0)
	elseif step.check == "goals" then
		p = M.hasBit(facts.flags, M.FLAG_GOALS) and 1 or 0
	end
	return min(target, max(0, floor(p))), target, true
end

function M.isDone(step, facts)
	local p, t, running = M.progress(step, facts)
	return running and p >= t
end

-- the state of a character seen for the first time (storage state -1): "active" or "quiet" (it played before)
function M.firstState(cfg, level)
	if num(level, 0) > num(cfg.quietAbove, 20) then
		return cfg.states.quiet
	end
	return cfg.states.active
end

-- the steps a character that played before has surely done, though nothing counts them: a cast and kills
M.PLAYED = {spell = true, kills = true}

-- the first look: from step `from`, the steps the character has done already are passed silently (no reward).
-- factsOf(i) -> the facts for step i. played: the character played before (cfg.playedAfterSec, or above the start
-- level); then the spell and kills steps count as done too. A brand-new character never passes a spell step here (a
-- cast in its first seconds is the step's own reward). Returns the step to start on (#steps + 1 = every step done).
function M.skipDone(cfg, from, factsOf, played)
	local i = max(1, floor(num(from, 1)))
	while cfg.steps[i] do
		local step = cfg.steps[i]
		local done
		if M.PLAYED[step.check] then
			done = played and true or false
		else
			done = M.isDone(step, factsOf(i))
		end
		if not done then
			break
		end
		i = i + 1
	end
	return i
end

-- which facts the engine side needs for a step: spell / gear only for those checks (they cost a look at the
-- character), kills / flags / stats are cheap reads
function M.needs(step)
	return {spell = step.check == "spell", gear = step.check == "gear"}
end

-- the gear check: worn = list of item ids in the equipment slots (the backpack slot left out), kit = set of the kit's
-- ids. True when one worn item is not of the kit.
function M.gearNew(worn, kit)
	kit = kit or {}
	for _, id in ipairs(worn or {}) do
		id = num(id, 0)
		if id > 0 and not kit[id] then
			return true
		end
	end
	return false
end

-- the ids of a kit (newplayer_core.lua NP.kitFor result): equipment, fallbacks, backpack rows; the backpack itself
function M.kitSet(kit, extra)
	local set = {}
	for _, e in ipairs(kit and kit.equip or {}) do
		if e.id then set[e.id] = true end
		if e.fallback then set[e.fallback] = true end
	end
	for _, b in ipairs(kit and kit.backpack or {}) do
		if b.id then set[b.id] = true end
	end
	for _, id in ipairs(extra or {}) do
		set[id] = true
	end
	return set
end

-- the reward of a step as items: {gold, items = {{id, count}}} (potions of the role folded in)
function M.rewardOf(cfg, step, role)
	local r = step.reward or {}
	local out = {gold = max(0, floor(num(r.gold, 0))), items = {}}
	for _, it in ipairs(r.items or {}) do
		out.items[#out.items + 1] = {it[1], it[2] or 1}
	end
	if r.potions then
		local p = cfg.potions or {}
		for _, it in ipairs(p[role] or p.default or {}) do
			out.items[#out.items + 1] = {it[1], it[2] or 1, potion = true}
		end
	end
	return out
end

-- "1,500"
function M.int(n)
	local s = tostring(floor(num(n, 0)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- the reward line: nameOf(id) -> an item's name ("Orb of Awakening"); potions are named as one
function M.rewardText(cfg, rw, lang, nameOf)
	local T = cfg.texts
	local parts = {}
	if rw.gold > 0 then
		parts[#parts + 1] = string.format(M.text(T.gold, lang), M.int(rw.gold))
	end
	local potions = false
	for _, it in ipairs(rw.items) do
		if it.potion then
			potions = true
		else
			parts[#parts + 1] = string.format(M.text(T.items, lang), it[2], nameOf and nameOf(it[1]) or ("item " .. it[1]))
		end
	end
	if potions then
		parts[#parts + 1] = M.text(T.potions, lang)
	end
	return #parts > 0 and table.concat(parts, ", ") or M.text(T.none, lang)
end

-- the tracker message: {title, step, count, rows = [{key, title, progress, target, state, hint, where}]}; rows = {}
-- hides the section. state of the character: active only.
function M.view(cfg, state, stepIndex, facts, lang)
	local steps = cfg.steps
	local i = floor(num(stepIndex, 1))
	if state ~= cfg.states.active or not steps[i] then
		return {rows = {}}
	end
	local step = steps[i]
	local p, t, running = M.progress(step, facts)
	local title = M.text(step.title, lang)
	if not running then
		title = string.format(M.text(cfg.texts.reachLevel, lang), title, t)
	end
	return {title = M.text(cfg.texts.title, lang), step = i, count = #steps,
		rows = {{key = step.key, title = title, progress = p, target = t, state = (running and p >= t) and "done" or "open",
			hint = M.text(step.hint, lang), where = step.where}}}
end

-- what the client has of the view, as one string (nothing to send when it did not change)
function M.sig(v, lang)
	local r = v.rows and v.rows[1]
	if not r then
		return "hidden"
	end
	return string.format("%s|%d/%d|%s|%d/%d", tostring(lang), v.step, v.count, r.title, r.progress, r.target)
end

return M
