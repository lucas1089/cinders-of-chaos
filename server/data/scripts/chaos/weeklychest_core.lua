-- weeklychest_core.lua: the pure rules of the Weekly Chest (weeklychest_config.lua; server/README.md "The Weekly Chest
-- (O261)"). No engine calls; weeklychest.lua is the engine side. Tests: server/tests/weeklychest_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- A state (one per character, kept in player storages):
--   {week = YYYYMMDD of the week's Monday, done = bit mask of the activities done this week, chest = 0 | 1,
--    bonus = 0 | 1, chests = chests given in all}

if not ChaosEmberCacheCore then
	dofile("data/scripts/chaos/embercache_core.lua")
end

ChaosWeeklyChestCore = ChaosWeeklyChestCore or {}
local K = ChaosWeeklyChestCore
local E = ChaosEmberCacheCore -- the week rule, the income table and the gold of "hours" are the Ember Cache's

local floor, max, min = math.floor, math.max, math.min

local function num(v, d)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return d or 0
	end
	return v
end

-- the week of t: YYYYMMDD of its Monday (the bounty board's rule, ChaosBounty.week)
function K.week(t, hour)
	return E.week(t, hour)
end

-- seconds to the end of the week
function K.weekEndsIn(t, hour)
	return E.weekEndsIn(t, hour)
end

-- ---------------------------------------------------------------- config
function K.validate(cfg)
	local problems = {}
	local function bad(text)
		problems[#problems + 1] = text
	end
	local st = cfg.storage or {}
	if not (st.base and st.last and st.last >= st.base) then
		bad("storage block missing")
	else
		for k, off in pairs(st) do
			if k ~= "base" and k ~= "last" and (type(off) ~= "number" or st.base + off > st.last) then
				bad("storage offset out of the block: " .. tostring(k))
			end
		end
	end
	local acts, seen = cfg.activities or {}, {}
	if #acts < 2 or #acts > 20 then
		bad("activities: 2 to 20 needed")
	end
	for _, a in ipairs(acts) do
		if type(a.key) ~= "string" or seen[a.key] then
			bad("activity key missing or twice: " .. tostring(a.key))
		end
		seen[tostring(a.key)] = true
		if num(a.level, -1) < 1 then
			bad("activity level: " .. tostring(a.key))
		end
	end
	for _, map in ipairs({cfg.stats or {}, cfg.emits or {}}) do
		for counter, key in pairs(map) do
			if not seen[key] then
				bad("counter " .. tostring(counter) .. " names an unknown activity: " .. tostring(key))
			end
		end
	end
	if num(cfg.minNeed) < 1 or num(cfg.need) < num(cfg.minNeed) or num(cfg.need) > #acts then
		bad("need / minNeed")
	end
	local prev = 0
	for i, b in ipairs(cfg.bands or {}) do
		if num(b.min, -1) <= prev and not (i == 1 and num(b.min) >= 1) then
			bad("bands must rise")
		end
		prev = num(b.min)
		if num(b.orbs) < 1 then
			bad("band orbs factor")
		end
	end
	if not cfg.bands or #cfg.bands == 0 or cfg.bands[1].min > 1 then
		bad("the first band must start at level 1")
	end
	local function checkReward(def, label)
		if num(def.hours, -1) < 0 then
			bad(label .. ": hours")
		end
		for _, it in ipairs(def.items or {}) do
			if not cfg.orbHours[it.id] then
				bad(label .. ": item without an orb value: " .. tostring(it.id))
			end
			if num(it.count) < 1 then
				bad(label .. ": item count")
			end
		end
	end
	checkReward(cfg.chest or {}, "chest")
	if not cfg.bonus or #cfg.bonus == 0 then
		bad("bonus options missing")
	end
	for i, def in ipairs(cfg.bonus or {}) do
		checkReward(def, "bonus " .. i)
	end
	return problems
end

-- ---------------------------------------------------------------- state
function K.new()
	return {week = 0, done = 0, chest = 0, bonus = 0, chests = 0}
end

-- storages <-> state. get(offset) -> value (-1 when unset); set(offset, value)
function K.load(cfg, get)
	local s = cfg.storage
	local function v(off)
		return max(0, floor(num(get(off), 0)))
	end
	return {week = v(s.week), done = v(s.done), chest = min(1, v(s.chest)), bonus = min(1, v(s.bonus)), chests = v(s.chests)}
end

function K.save(cfg, st, set)
	local s = cfg.storage
	set(s.week, st.week)
	set(s.done, st.done)
	set(s.chest, st.chest)
	set(s.bonus, st.bonus)
	set(s.chests, st.chests)
end

-- a new week empties the week's values; returns true when it did
function K.roll(st, t, cfg)
	local week = K.week(t, cfg.resetHour)
	if st.week ~= week then
		st.week, st.done, st.chest, st.bonus = week, 0, 0, 0
		return true
	end
	return false
end

-- ---------------------------------------------------------------- activities
function K.indexOf(cfg, key)
	for i, a in ipairs(cfg.activities) do
		if a.key == key then
			return i
		end
	end
	return nil
end

function K.isDone(st, cfg, key)
	local i = K.indexOf(cfg, key)
	return i ~= nil and floor(st.done / 2 ^ (i - 1)) % 2 == 1
end

-- marks an activity done; true when it was not done before this week
function K.mark(st, cfg, key)
	local i = K.indexOf(cfg, key)
	if not i or K.isDone(st, cfg, key) then
		return false
	end
	st.done = st.done + 2 ^ (i - 1)
	return true
end

function K.doneCount(st, cfg)
	local n = 0
	for _, a in ipairs(cfg.activities) do
		if K.isDone(st, cfg, a.key) then
			n = n + 1
		end
	end
	return n
end

function K.isUnlocked(cfg, level, key)
	local i = K.indexOf(cfg, key)
	return i ~= nil and num(level, 1) >= cfg.activities[i].level
end

-- what the chest asks at a level: {total = activities in all, open = activities of the character (unlocked, or done
-- anyway), need = how many open the chest, bonusNeed = how many give the bonus roll (nil: none at this level)}
function K.targets(st, cfg, level)
	local total, open = #cfg.activities, 0
	for _, a in ipairs(cfg.activities) do
		if num(level, 1) >= a.level or K.isDone(st, cfg, a.key) then
			open = open + 1
		end
	end
	local need = max(cfg.minNeed, cfg.need - (total - open))
	need = min(need, open)
	local bonusNeed = open > need and open or nil
	return {total = total, open = open, need = need, bonusNeed = bonusNeed}
end

-- {chest = true when the chest is due now, bonus = true when the bonus roll is due now}; nothing is changed
function K.due(st, cfg, level)
	local t = K.targets(st, cfg, level)
	local n = K.doneCount(st, cfg)
	return {chest = st.chest ~= 1 and n >= t.need, bonus = st.bonus ~= 1 and t.bonusNeed ~= nil and n >= t.bonusNeed}
end

-- ---------------------------------------------------------------- rewards
function K.bandOf(cfg, level)
	level = num(level, 1)
	local idx = 1
	for i, b in ipairs(cfg.bands) do
		if level >= b.min then
			idx = i
		end
	end
	return idx, cfg.bands[idx]
end

-- {gold, items = {{id, count}}} of a reward definition at a level
function K.reward(cfg, level, def)
	local _, band = K.bandOf(cfg, level)
	local items = {}
	for _, it in ipairs(def.items or {}) do
		items[#items + 1] = {id = it.id, count = max(1, floor(it.count * band.orbs))}
	end
	return {gold = E.gold({hours = def.hours}, level, cfg.income), items = items}
end

-- the value of a reward in hours of hunting at a level (the gold's hours plus the orbs'), for the limits
function K.hours(cfg, level, def)
	local r = K.reward(cfg, level, def)
	local h = num(def.hours)
	for _, it in ipairs(r.items) do
		h = h + num(cfg.orbHours[it.id]) * it.count
	end
	return h
end

-- the bonus roll option for a die in [0, 1) (equal chances)
function K.bonusOption(cfg, die)
	local n = #cfg.bonus
	local i = min(n, floor(num(die) * n) + 1)
	return i, cfg.bonus[i]
end

-- ---------------------------------------------------------------- the window
-- the state payload: {week = {endsIn}, acts = [{k, done 0/1, open 0/1, lv}], got, need, bonusNeed, chest = {given, gold,
-- it = [{cid, n, name}]}, bonus = {given, lo, hi (the gold of its options)}, chests}
-- itemInfo(id) -> client id, name
function K.view(st, cfg, t, level, itemInfo)
	local tg = K.targets(st, cfg, level)
	local acts = {}
	for _, a in ipairs(cfg.activities) do
		acts[#acts + 1] = {k = a.key, done = K.isDone(st, cfg, a.key) and 1 or 0,
			open = (num(level, 1) >= a.level or K.isDone(st, cfg, a.key)) and 1 or 0, lv = a.level}
	end
	local function items(list)
		local out = {}
		for _, it in ipairs(list) do
			local cid, name = it.id, "item " .. it.id
			if itemInfo then
				cid, name = itemInfo(it.id)
			end
			out[#out + 1] = {cid = cid, n = it.count, name = name}
		end
		return out
	end
	local chest = K.reward(cfg, level, cfg.chest)
	local lo, hi
	for _, def in ipairs(cfg.bonus) do
		local r = K.reward(cfg, level, def)
		lo = lo and min(lo, r.gold) or r.gold
		hi = hi and max(hi, r.gold) or r.gold
	end
	return {endsIn = K.weekEndsIn(t, cfg.resetHour), acts = acts, got = K.doneCount(st, cfg), need = tg.need,
		bonusNeed = tg.bonusNeed or 0, open = tg.open, chest = {given = st.chest, gold = chest.gold, it = items(chest.items)},
		bonus = {given = st.bonus, lo = lo or 0, hi = hi or 0}, chests = st.chests}
end

return K
