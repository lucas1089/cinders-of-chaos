-- Display scale, the pure part (ChaosDisplayScale): the factor curve, the rounding and the clamp, and the scaling of
-- every Chaos payload that carries a combat number. No engine calls; display_scale.lua does the engine part (the
-- factor table for engine src-patch 0037, the opcode to the client) and every hook site calls the functions below
-- right before its json.encode. Tested by server/tests/display_scale_test.lua. Lua 5.1 / LuaJIT and Lua 5.3.
--
-- What it is: a VISUAL scale. A shown combat number is the internal number x factor(level), the factor a whole number
-- (1 up to level 100, then rising to 1000 at level 1000, capped at 10000; display_scale_config.lua). Internal numbers,
-- the balance and the database never change; only what goes to the client does.
-- Whose level: the viewer's own level for everything that viewer sees (own and other creatures' health, damage dealt
-- and taken, heals, meters, recaps, boards), except
--   * an item tooltip: the factor of the item's level requirement (the same text for every viewer: trade, chat links,
--     the market, Inspect), tip.ds = that factor so the client's compare view can convert;
--   * a death recap: the level the character had at that death (the numbers it saw while dying).
-- Never scaled: gold, experience, levels, skills, counts, prices, timers, percentages, durations, ids, anything stored,
-- and mana (owner 2026-10-21, "Fixed spell costs" in server/README.md): the own mana and max mana, a spell's mana cost,
-- a party member's mana, the mana rows of item tooltips (engine patch 0052 for the stats packet and the mana messages),
-- so a spell costs the same shown number at every level.
--
-- Every site function returns a scaled COPY (payloads may be shared between viewers or cached) and, at factor 1, the
-- payload itself untouched.

ChaosDisplayScale = ChaosDisplayScale or {}
local DS = ChaosDisplayScale
local floor, exp, log = math.floor, math.exp, math.log

local DEFAULTS = {
	curve = {{1, 1}}, -- off (owner 2026-10-23): x1 at every level
	jsonMax = 9007199254740992,
	opcode = 157,
	tableLevels = 1500,
	leaderboardBoards = {worldboss = true, bosshealer = true, bosstank = true},
	itemFlatKeys = {maxhealth = true, thorns = true, lifeonkill = true, lifeonhit = true, regen = true, smolderaura = true,
		gem_maxhealth = true}
}
DS.U32_MAX = 4294967295
DS.MOD_PREFIX = "chaos_mod_" -- ChaosItemMods.PREFIX: a modifier row's key is its attribute name

function DS.configure(cfg)
	DS.cfg = {}
	for k, v in pairs(DEFAULTS) do
		DS.cfg[k] = v
	end
	for k, v in pairs(cfg or {}) do
		DS.cfg[k] = v
	end
	DS.memo = {}
	return DS.cfg
end
if not DS.cfg then
	DS.configure()
end

-- ---------------------------------------------------------------- the curve
-- the factor before rounding: 1 up to the first point, log-linear between points, the last factor past the last one
function DS.rawFactor(level)
	local curve = DS.cfg.curve
	level = tonumber(level) or 1
	local first, last = curve[1], curve[#curve]
	if level <= first[1] then
		return first[2]
	end
	if level >= last[1] then
		return last[2]
	end
	for i = 2, #curve do
		local a, b = curve[i - 1], curve[i]
		if level <= b[1] then
			local t = (level - a[1]) / (b[1] - a[1])
			return exp(log(a[2]) + (log(b[2]) - log(a[2])) * t)
		end
	end
	return last[2]
end

-- the factor of a level: a whole number >= 1 (rounded to nearest), so scaling is exact and additive
function DS.factor(level)
	level = floor(tonumber(level) or 1)
	if level < 1 then
		level = 1
	end
	local memo = DS.memo
	local f = memo[level]
	if not f then
		f = floor(DS.rawFactor(level) + 0.5)
		if f < 1 then
			f = 1
		end
		memo[level] = f
	end
	return f
end

-- the engine's table (Game.setDisplayScale of src-patch 0037): factor of levels 1..n, n = cfg.tableLevels
function DS.table(n)
	n = n or DS.cfg.tableLevels
	local t = {}
	for level = 1, n do
		t[level] = DS.factor(level)
	end
	return t
end

-- the viewer's factor: the factor of player:getLevel() (nil or no level: 1)
function DS.forPlayer(player)
	if not player then
		return 1
	end
	local ok, level = pcall(function() return player:getLevel() end)
	return DS.factor(ok and level or 1)
end

-- a hook site in one call: DS[site](payload, viewer's factor); an unknown site returns the payload as it is
function DS.apply(site, player, payload)
	local fn = DS[site]
	if type(fn) ~= "function" then
		return payload
	end
	return fn(payload, DS.forPlayer(player))
end

-- ---------------------------------------------------------------- numbers
local function isNum(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- one number x factor: whole numbers stay exact (an integer factor), a fraction (a rate such as DPS) is rounded to the
-- nearest whole number, the result clamped to +-limit (default cfg.jsonMax, 2^53: exact in JSON and a double).
-- Anything that is not a finite number comes back as it is.
function DS.scale(v, f, limit)
	if not isNum(v) or not f or f == 1 then
		return v
	end
	limit = limit or DS.cfg.jsonMax
	local r = v * f
	if r ~= floor(r) then
		r = floor(r + 0.5)
	end
	if r > limit then
		r = limit
	elseif r < -limit then
		r = -limit
	end
	return r
end

-- the same rule for a uint32 packet field (the engine's TextMessage values and the stats packet): 0..2^32-1
function DS.u32(v, f)
	if not isNum(v) then
		return 0
	end
	local r = DS.scale(v, f or 1, DS.U32_MAX)
	if r < 0 then
		r = 0
	end
	return r
end

-- every whole number in a text x factor ("Health on Hit +20" -> "Health on Hit +20000"); only for texts whose numbers
-- are all the scaled kind (a modifier line, a heal line). Digits glued to a '.' (a decimal) are left alone.
function DS.scaleNumbersIn(text, f)
	if type(text) ~= "string" or not f or f == 1 then
		return text
	end
	return (text:gsub("()(%d+)()", function(s, digits, e)
		local before, after = text:sub(s - 1, s - 1), text:sub(e, e + 1)
		if before == "." or after:match("^%.%d") then
			return digits
		end
		return string.format("%.0f", DS.scale(tonumber(digits), f))
	end))
end

-- a deep copy of plain data (the payloads: tables of numbers, strings and booleans)
function DS.clone(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = DS.clone(v)
	end
	return c
end

-- named fields of a table x factor (in place)
function DS.fields(t, keys, f)
	if type(t) ~= "table" then
		return t
	end
	for _, k in ipairs(keys) do
		if t[k] ~= nil then
			t[k] = DS.scale(t[k], f)
		end
	end
	return t
end

-- the same for each table in a list
function DS.each(list, keys, f)
	if type(list) ~= "table" then
		return list
	end
	for _, t in ipairs(list) do
		DS.fields(t, keys, f)
	end
	return list
end

-- ---------------------------------------------------------------- the sites
-- DPS meter and combat log (combatlog.lua, combatlog_core.lua CL.state): segs [[id, label, dur, damage, healing,
-- taken, live, boss, received]]; v.t = [{tot, ov, el = {[element] = amount}, r = [[key, kind, name, icon, total, hits,
-- crits, max, over]]}]; party = [{fd, fh, ft, sd, sh, st, ...}] (CL.brief). Durations, hits and crits stay.
local SEG_COLS, ROW_COLS = {4, 5, 6, 9}, {5, 8, 9}
local BRIEF = {"fd", "fh", "ft", "sd", "sh", "st"}
function DS.combatLogState(st, f)
	if f == 1 or type(st) ~= "table" then
		return st
	end
	st = DS.clone(st)
	for _, seg in ipairs(st.segs or {}) do
		DS.fields(seg, SEG_COLS, f)
	end
	local v = st.v
	if type(v) == "table" then
		for _, tab in ipairs(v.t or {}) do
			tab.tot, tab.ov = DS.scale(tab.tot, f), DS.scale(tab.ov, f)
			for el, amount in pairs(tab.el or {}) do
				tab.el[el] = DS.scale(amount, f)
			end
			for _, row in ipairs(tab.r or {}) do
				DS.fields(row, ROW_COLS, f)
			end
		end
	end
	DS.each(st.party, BRIEF, f)
	return st
end

-- a party member's totals alone (CL.brief)
function DS.combatLogBrief(b, f)
	if f == 1 or type(b) ~= "table" then
		return b
	end
	return DS.fields(DS.clone(b), BRIEF, f)
end

-- death recap (deathrecap_core.lua): {kb = {a}, tot, hp, mp, el = {[element] = amount}, att = [{tot, hp, mp, x, el}],
-- last = [{a}]}; the experience and levels lost, hits, crits and times stay
function DS.deathRecap(recap, f)
	if f == 1 or type(recap) ~= "table" then
		return recap
	end
	recap = DS.clone(recap)
	DS.fields(recap, {"tot", "hp", "mp"}, f)
	if type(recap.kb) == "table" then
		recap.kb.a = DS.scale(recap.kb.a, f)
	end
	for el, amount in pairs(type(recap.el) == "table" and recap.el or {}) do
		recap.el[el] = DS.scale(amount, f)
	end
	for _, a in ipairs(recap.att or {}) do
		DS.fields(a, {"tot", "hp", "mp", "x"}, f)
		for el, amount in pairs(type(a.el) == "table" and a.el or {}) do
			a.el[el] = DS.scale(amount, f)
		end
	end
	DS.each(recap.last, {"a"}, f)
	return recap
end

-- a death recap message (deathrecap.lua send: {recap} | {list = [summary], recap}): every recap and summary at the
-- factor of the level the character had at that death (recap.lvl / summary.lvl), else the viewer's factor
function DS.deathRecapData(data, viewerFactor)
	if type(data) ~= "table" then
		return data
	end
	local function factorOf(t)
		local lvl = type(t) == "table" and tonumber(t.lvl) or nil
		return lvl and DS.factor(lvl) or viewerFactor or 1
	end
	local out = {}
	for k, v in pairs(data) do
		out[k] = v
	end
	if type(data.recap) == "table" then
		out.recap = DS.deathRecap(data.recap, factorOf(data.recap))
	end
	if type(data.list) == "table" then
		out.list = {}
		for i, s in ipairs(data.list) do
			local f = factorOf(s)
			out.list[i] = f == 1 and s or DS.fields(DS.clone(s), {"tot"}, f)
		end
	end
	return out
end

-- party frames (partyframes_core.lua P.state): members = [{h, H, m, M}] (health and mana of the members in range):
-- the health; the mana (m, M) and p, the percent, stay
function DS.partyState(state, f)
	if f == 1 or type(state) ~= "table" then
		return state
	end
	state = DS.clone(state)
	DS.each(state.members, {"h", "H"}, f)
	return state
end

-- hunt tracker (hunt_core.lua H.state): dmg, dps, heal, hps
function DS.huntState(st, f)
	if f == 1 or type(st) ~= "table" then
		return st
	end
	return DS.fields(DS.clone(st), {"dmg", "dps", "heal", "hps"}, f)
end

-- a leaderboard (leaderboard.lua LB.sendBoard "board"): rows / champions / own value, only on the damage and healing
-- boards (cfg.leaderboardBoards); ranks, counts and every other board stay
function DS.leaderboard(data, f)
	if f == 1 or type(data) ~= "table" or not DS.cfg.leaderboardBoards[data.key] then
		return data
	end
	data = DS.clone(data)
	DS.each(data.rows, {"value"}, f)
	DS.each(data.champions, {"value"}, f)
	DS.fields(data.own, {"value"}, f)
	return data
end

-- battleground scoreboard (battleground.lua scoreboardOf: rows = [{damage, healing}]) in any message that has rows
function DS.battleground(data, f)
	if f == 1 or type(data) ~= "table" or type(data.rows) ~= "table" then
		return data
	end
	data = DS.clone(data)
	DS.each(data.rows, {"damage", "healing"}, f)
	return data
end

-- guild window state (guildwar.lua W.state): boss = guild boss view {damage, board = [{damage}]}
function DS.guildState(data, f)
	if f == 1 or type(data) ~= "table" or type(data.boss) ~= "table" then
		return data
	end
	data = DS.clone(data)
	DS.fields(data.boss, {"damage"}, f)
	DS.each(data.boss.board, {"damage"}, f)
	return data
end

-- a bestiary entry (bestiary.lua "entry"): the monster's health; experience stays
function DS.bestiaryEntry(data, f)
	if f == 1 or type(data) ~= "table" then
		return data
	end
	return DS.fields(DS.clone(data), {"health"}, f)
end

-- ---------------------------------------------------------------- item tooltips
local function flatKey(k)
	if type(k) ~= "string" then
		return false
	end
	local keys = DS.cfg.itemFlatKeys
	if keys[k] then
		return true
	end
	local p = DS.MOD_PREFIX
	return k:sub(1, #p) == p and keys[k:sub(#p + 1)] == true
end
DS.isItemFlatKey = flatKey

-- the factor of an item tooltip: its level requirement's (req.level; none: 1)
function DS.itemFactor(tip)
	local req = type(tip) == "table" and type(tip.req) == "table" and tonumber(tip.req.level) or nil
	return req and DS.factor(req) or 1
end

-- an item tooltip (item_tooltip_core.lua T.build): the flat health / damage / heal rows (cfg.itemFlatKeys; mana stays) of
-- base, mods (value, range, text, and the second value when it has its own flat key), stats and the socket lines of
-- flat gems, at the factor of the item's level requirement. tip.ds = that factor (always set, 1 included), so the
-- client's compare view brings a worn item of another level to this one's scale.
function DS.itemTip(tip)
	if type(tip) ~= "table" then
		return tip
	end
	local f = DS.itemFactor(tip)
	tip = DS.clone(tip)
	tip.ds = f
	for _, s in ipairs(tip.stats or {}) do
		if flatKey(s.k) and s.fmt == nil then
			s.sc = 1 -- a scaled row: the client's compare view converts the other item's value to this item's scale
		end
	end
	if f == 1 then
		return tip
	end
	for _, b in ipairs(tip.base or {}) do
		if flatKey(b.k) and b.fmt == nil then
			b.v = DS.scale(b.v, f)
		end
	end
	for _, m in ipairs(tip.mods or {}) do
		if flatKey(m.k) then
			m.v, m.lo, m.hi = DS.scale(m.v, f), DS.scale(m.lo, f), DS.scale(m.hi, f)
			m.t = DS.scaleNumbersIn(m.t, f)
		end
	end
	for _, s in ipairs(tip.stats or {}) do
		if s.sc then
			s.v = DS.scale(s.v, f)
		end
	end
	local sockets = type(tip.sockets) == "table" and tip.sockets.list or nil
	for _, g in ipairs(sockets or {}) do
		if type(g.text) == "string" and g.text:find("Max Health", 1, true) then
			g.text = DS.scaleNumbersIn(g.text, f)
		end
	end
	return tip
end

return DS
