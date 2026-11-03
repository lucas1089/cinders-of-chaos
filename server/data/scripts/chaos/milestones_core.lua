-- Level milestones (O378): the pure rules. No engine calls (tests/milestones_test.lua, goals_config.lua read it with
-- plain Lua). Numbers: milestones_config.lua. Engine glue: milestones.lua. server/README.md "Level milestones (O378)".
--
--   K.validate(cfg, ach)            -> problems (list of texts); ach = achievements_data.lua (its level_<L> entries)
--   K.byLevel(cfg, level)           -> the milestone of exactly that level, or nil
--   K.next(cfg, level)              -> the first milestone above level, or nil
--   K.baseline(cfg, level)          -> the highest milestone level at or below level (0 when none)
--   K.titleOf(ach, level)           -> the title of achievement "level_<level>", or nil
--   K.cacheItems(cfg, m)            -> {{id, count}} of the Milestone Cache (orbs with a count above 0)
--   K.cacheText(cfg, m)             -> "5 Orb of Upheaval, 2 Orb of Fate"
--   K.plan(cfg, s)                  -> what to do now. s = {paid, level, oldLevel?, staff?, login?}; returns
--                                      {paid = new storage value, pay = {milestones to give a cache for},
--                                       top = the highest milestone reached now (toast, broadcast) or nil}
--   K.toast(cfg, m, title, cacheText, nextLevel, tr) -> header, text. tr(key, ...) formats in the player's language
--   K.goals(cfg, ach)               -> {why = {[level] = {en, pt}}, challenges = {goal tables for goals_config.lua}}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosMilestonesCore = ChaosMilestonesCore or {}
local K = ChaosMilestonesCore

local function int(n)
	n = tonumber(n)
	return n and math.floor(n) or nil
end

local function fmt(t, ...)
	return string.format(t, ...)
end

function K.achievementOf(ach, level)
	local id = "level_" .. tostring(level)
	for _, a in ipairs(ach and ach.list or {}) do
		if a.id == id then
			return a
		end
	end
	return nil
end

function K.titleOf(ach, level)
	local a = K.achievementOf(ach, level)
	return a and a.title or nil
end

function K.validate(cfg, ach)
	local problems = {}
	local function bad(f, ...)
		problems[#problems + 1] = fmt(f, ...)
	end
	if type(cfg) ~= "table" or type(cfg.list) ~= "table" or #cfg.list == 0 then
		return {"config: list needed"}
	end
	local step = int(cfg.step) or 0
	if step <= 0 then
		bad("step must be above 0")
	end
	if type(cfg.orbs) ~= "table" or #cfg.orbs == 0 then
		bad("orbs needed")
	end
	local want = int(cfg.first)
	local prev
	for i, m in ipairs(cfg.list) do
		local where = "milestone " .. tostring(m.level or i)
		if int(m.level) ~= want then
			bad("%s: level %s expected", where, tostring(want))
		end
		want = (int(m.level) or 0) + step
		if type(m.cache) ~= "table" then
			bad("%s: cache needed", where)
		else
			for j = 1, #(cfg.orbs or {}) do
				local c = m.cache[j]
				if not (int(c) and int(c) == c and c >= 0) then
					bad("%s: cache %d must be a whole number >= 0", where, j)
				elseif prev and prev.cache and (tonumber(prev.cache[1]) or 0) > (tonumber(m.cache[1]) or 0) and j == 1 then
					bad("%s: the cache must not shrink", where)
				end
			end
		end
		local ch = m.challenge
		if type(ch) ~= "table" or (ch.stat ~= "tower_floor" and ch.stat ~= "pocket_kills") or not (int(ch.target) and ch.target >= 1) then
			bad("%s: challenge {stat = tower_floor | pocket_kills, target >= 1} needed", where)
		elseif prev and prev.challenge and prev.challenge.stat == ch.stat and ch.target <= prev.challenge.target then
			bad("%s: the challenge must rise", where)
		end
		if ach then
			local a = K.achievementOf(ach, m.level)
			if not a then
				bad("%s: no achievement level_%s", where, tostring(m.level))
			elseif a.stat ~= "level" or a.target ~= m.level or type(a.title) ~= "string" or a.cat ~= "milestones" then
				bad("%s: level_%s needs stat level, target %s, a title and category milestones", where, tostring(m.level),
					tostring(m.level))
			end
		end
		prev = m
	end
	if int(cfg.list[#cfg.list].level) ~= int(cfg.last) then
		bad("the last milestone must be level %s", tostring(cfg.last))
	end
	return problems
end

function K.byLevel(cfg, level)
	for _, m in ipairs(cfg.list) do
		if m.level == level then
			return m
		end
	end
	return nil
end

function K.next(cfg, level)
	level = tonumber(level) or 0
	for _, m in ipairs(cfg.list) do
		if m.level > level then
			return m
		end
	end
	return nil
end

function K.baseline(cfg, level)
	level = tonumber(level) or 0
	local out = 0
	for _, m in ipairs(cfg.list) do
		if m.level <= level then
			out = m.level
		end
	end
	return out
end

function K.cacheItems(cfg, m)
	local out = {}
	for i, o in ipairs(cfg.orbs or {}) do
		local n = int(m and m.cache and m.cache[i]) or 0
		if n > 0 then
			out[#out + 1] = {id = o.id, count = n, name = o.name}
		end
	end
	return out
end

function K.cacheText(cfg, m)
	local parts = {}
	for _, it in ipairs(K.cacheItems(cfg, m)) do
		parts[#parts + 1] = it.count .. " " .. it.name
	end
	return table.concat(parts, ", ")
end

-- s.paid: the storage (-1 / nil = never seen). s.login: the first sight sets the baseline without a cache. A staff
-- character moves the mark too (no cache, no toast), so a later change of group never pays a backlog. A lower level
-- (a death) pays nothing: the mark stays where it is.
function K.plan(cfg, s)
	local level = int(s.level) or 0
	local paid = int(s.paid)
	local out = {pay = {}}
	if paid == nil or paid < 0 then
		-- not seen yet: the baseline is what the character had before this advance (the whole level at a login)
		paid = K.baseline(cfg, s.login and level or (int(s.oldLevel) or level))
		out.baselined = true
	end
	out.paid = paid
	if s.login or cfg.enabled == false then
		out.paid = math.max(paid, s.login and K.baseline(cfg, level) or paid)
		return out
	end
	for _, m in ipairs(cfg.list) do
		if m.level > paid and m.level <= level then
			if not s.staff then
				out.pay[#out.pay + 1] = m
			end
			out.top = (not s.staff) and m or nil
			out.paid = m.level
		end
	end
	return out
end

function K.toast(cfg, m, title, cacheText, nextLevel, tr)
	local T = cfg.texts
	local header = tr(T.toastTitle, m.level)
	local text = tr(T.toast, title or "-", cacheText ~= "" and cacheText or "-")
	if nextLevel then
		text = text .. " " .. tr(T.toastNext, nextLevel)
	end
	return header, text
end

-- the Next Goals lines (goals_config.lua): the "why" of each "Reach level <L>" goal, and one challenge goal per milestone
function K.goals(cfg, ach)
	local G = cfg.texts.goals
	local why, challenges = {}, {}
	for _, m in ipairs(cfg.list) do
		local title = K.titleOf(ach, m.level) or "-"
		local cache = K.cacheText(cfg, m)
		why[m.level] = {en = fmt(G.why.en, title, cache), pt = fmt(G.why.pt, title, cache)}
		local ch = m.challenge
		local tower = ch.stat == "tower_floor"
		local t = tower and G.tower or G.pocket
		challenges[#challenges + 1] = {
			key = "ms" .. m.level, level = m.level, stat = ch.stat, target = ch.target,
			title = {en = fmt(t.en, m.level, ch.target), pt = fmt(t.pt, m.level, ch.target)},
			why = {en = G.challengeWhy.en, pt = G.challengeWhy.pt},
			where = {k = "window", m = tower and "game_infinitytower" or "game_bossspawns", f = "toggle"},
			effort = tower and {en = G.towerEffort.en, pt = G.towerEffort.pt} or {en = G.pocketEffort.en, pt = G.pocketEffort.pt},
			requires = (not tower) and "ChaosPocketBoss" or nil
		}
	end
	return {why = why, challenges = challenges}
end

return K
