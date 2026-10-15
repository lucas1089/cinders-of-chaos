-- Competitive records: pure logic (no engine calls), shared by records.lua and server/tests/records_test.lua.
--   ChaosRecordsCore.catalogue(cfg, src)        the boards (templates of records_config.lua x the content lists)
--   ChaosRecordsCore.periodKeys(t, hour, season) {week = "w<YYYYMMDD>", season = "s<id>" | "q<YYYY><1-4>", all = "all"}
--   ChaosRecordsCore.slot(board, variant, size)  storage key of one filter combination
--   ChaosRecordsCore.sizeOf(board, n, cfg)       the party size bracket of a run (nil: no bracket of the board fits)
--   ChaosRecordsCore.validate(run, board, cfg)   true | false, reason (the anti-abuse rules, server/README.md)
--   ChaosRecordsCore.merge(e, value, mode, at)   one result into a stored best (min / max / add)
--   ChaosRecordsCore.rank(entries, mode)         ranked list: best value first, a tie goes to the earlier time
--   ChaosRecordsCore.awards / held / titlesOf    the weekly top 3: category titles and the badge
--   ChaosRecordsCore.isRecord, firstTitle, valueText, recordText, firstText
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosLeaderboard or not ChaosLeaderboard.week then
	dofile("data/scripts/chaos/leaderboard_core.lua")
end

ChaosRecordsCore = ChaosRecordsCore or {}
local K = ChaosRecordsCore

-- is this dungeon title the Hollow Vault (its own board)? The dungeon's title is "The Hollow Vault", the config
-- name "Hollow Vault": compare without a leading "The " and without case
local function plainTitle(s)
	return (tostring(s or ""):lower():gsub("^%s*the%s+", ""):gsub("%s+$", ""))
end
function K.isHollowVault(cfg, title)
	return title ~= nil and cfg.hollowVaultName ~= nil and plainTitle(title) == plainTitle(cfg.hollowVaultName)
end
local floor = math.floor

-- ---------------------------------------------------------------- periods
function K.week(t, hour)
	return ChaosLeaderboard.week(t, hour)
end

function K.prevWeek(week, hour)
	return ChaosLeaderboard.prevWeek(week, hour)
end

function K.nextReset(t, hour)
	return ChaosLeaderboard.nextReset(t, hour)
end

-- the season of the records: the running server season (season.lua), else the calendar quarter of t
function K.seasonKey(season, t)
	if type(season) == "table" and season.id then
		return "s" .. tostring(season.id)
	end
	local d = os.date("*t", t)
	return string.format("q%d%d", d.year, floor((d.month - 1) / 3) + 1)
end

function K.seasonName(key, season)
	if type(season) == "table" and season.name and key == K.seasonKey(season) then
		return season.name
	end
	local y, q = tostring(key):match("^q(%d%d%d%d)(%d)$")
	if y then
		return string.format("Q%s %s", q, y)
	end
	return tostring(key)
end

function K.periodKeys(t, hour, season)
	return {week = "w" .. K.week(t, hour), season = K.seasonKey(season, t), all = "all"}
end

-- ---------------------------------------------------------------- catalogue
local function slug(s)
	return (tostring(s):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end
K.slug = slug

-- the short name of a boss for titles: "Kaelgor the Infernal Warlord" -> "Kaelgor", "The Rotmother" -> "Rotmother"
function K.shortName(name)
	name = tostring(name or ""):gsub("^[Tt]he%s+", "")
	return name:match("^(.-)%s+the%s") or name
end

-- src: {worldBosses = {"name", ...}, omens = {{key, name, boss}}, ascended = {{key, name, boss, final}},
--       guildBoss = "name", trials = {{key, name}}, dungeons = {{id, name}}}
local function variantsOf(cfg, tpl, src)
	local v = tpl.variants
	local out = {}
	if v == "worldboss" then
		for i, name in ipairs(src.worldBosses or {}) do
			out[#out + 1] = {key = slug(K.shortName(name)), name = name, short = K.shortName(name), index = i}
		end
	elseif v == "omens" then
		for _, o in ipairs(src.omens or {}) do
			out[#out + 1] = {key = o.key, name = o.boss or o.name, short = K.shortName(o.boss or o.name)}
		end
	elseif v == "ascended" then
		for _, a in ipairs(src.ascended or {}) do
			out[#out + 1] = {key = a.key, name = a.boss or a.name, short = a.final and (a.name or "Cinderheart")
				or K.shortName(a.boss or a.name)}
		end
	elseif v == "bands" then
		for _, b in ipairs(cfg.bands or {}) do
			out[#out + 1] = {key = b.key, name = b.name, min = b.min, max = b.max}
		end
	elseif v == "difficulties" then
		for d = 1, cfg.difficulties or 6 do
			out[#out + 1] = {key = "d" .. d, name = string.format(cfg.difficultyName or "Difficulty %d", d), difficulty = d}
		end
	elseif v == "trialTiers" then
		for i, t in ipairs(src.trials or {}) do
			out[#out + 1] = {key = t.key, name = t.name, tier = i}
		end
	elseif v == "towerFloors" then
		for _, f in ipairs(cfg.towerFloors or {}) do
			out[#out + 1] = {key = "f" .. f, name = "Floor " .. f, floor = f}
		end
	elseif v == "arena" then
		for _, a in ipairs(cfg.arena or {}) do
			out[#out + 1] = {key = a.key, name = a.name}
		end
	end
	return out
end

local function makeBoard(cfg, tpl, src, key, name, extra)
	local b = {key = key, cat = tpl.cat, name = name, mode = tpl.mode or "min", format = tpl.format, value = tpl.value,
		byClass = tpl.byClass and true or false, first = tpl.first and true or false, maxGroup = tpl.maxGroup,
		hook = tpl.hook, template = tpl.key, sizes = {}, variants = variantsOf(cfg, tpl, src)}
	for _, s in ipairs(tpl.sizes or {}) do
		local def = cfg.sizes[s]
		if def then
			b.sizes[#b.sizes + 1] = {key = s, name = def.name, min = def.min, max = def.max}
		end
	end
	for k, v in pairs(extra or {}) do
		b[k] = v
	end
	b.variantByKey = {}
	for _, v in ipairs(b.variants) do
		b.variantByKey[v.key] = v
	end
	return b
end

-- -> boards (ordered: category order, then template order), byKey
function K.catalogue(cfg, src)
	src = src or {}
	local list = {}
	for _, cat in ipairs(cfg.categories) do
		for _, tpl in ipairs(cfg.boards) do
			if tpl.cat == cat.key then
				if tpl.perDungeon then
					for _, d in ipairs(src.dungeons or {}) do
						if not K.isHollowVault(cfg, d.name) then
							list[#list + 1] = makeBoard(cfg, tpl, src, tpl.key .. "_" .. tostring(d.id), d.name, {dungeon = d.id})
						end
					end
				elseif not (tpl.variants and #variantsOf(cfg, tpl, src) == 0) then
					local name = tpl.name
					if tpl.key == "guildboss" and src.guildBoss then
						name = src.guildBoss
					end
					list[#list + 1] = makeBoard(cfg, tpl, src, tpl.key, name)
				end
			end
		end
	end
	local byKey = {}
	for _, b in ipairs(list) do
		byKey[b.key] = b
	end
	return list, byKey
end

-- ---------------------------------------------------------------- slots and sizes
function K.slot(board, variant, size)
	return string.format("%s|%s|%s", board, variant or "-", size or "-")
end

function K.parseSlot(slot)
	local b, v, s = tostring(slot):match("^([^|]+)|([^|]+)|([^|]+)$")
	if not b then
		return nil
	end
	return b, v ~= "-" and v or nil, s ~= "-" and s or nil
end

-- party size n -> the bracket key of the board, "-" when the board has no brackets, nil when the size does not fit
function K.sizeOf(board, n, cfg)
	n = floor(tonumber(n) or 0)
	if n < 1 then
		return nil
	end
	if #board.sizes == 0 then
		return n <= (board.maxGroup or cfg.valid.maxGroup or 40) and "-" or nil
	end
	for _, s in ipairs(board.sizes) do
		if n >= s.min and n <= s.max then
			return s.key
		end
	end
	return nil
end

-- the rift band of a tier (variant key), or nil
function K.bandOf(cfg, tier)
	for _, b in ipairs(cfg.bands or {}) do
		if tier >= b.min and tier <= b.max then
			return b.key
		end
	end
	return nil
end

-- the tower floors of `floors` this floor clear reaches (exactly that floor)
function K.towerVariant(cfg, floorNo)
	for _, f in ipairs(cfg.towerFloors or {}) do
		if f == floorNo then
			return "f" .. f
		end
	end
	return nil
end

-- ---------------------------------------------------------------- validation
-- run = {board, variant, value, members = {{guid, name, group, voc, mc}}, debug, difficulty, difficultyStart, size}
-- Returns true, sizeKey or false, reason.
function K.validate(run, board, cfg)
	if not board then
		return false, "unknown board"
	end
	if type(run) ~= "table" then
		return false, "no run"
	end
	if run.debug then
		return false, "debug run"
	end
	local members = run.members or {}
	if #members == 0 then
		return false, "nobody"
	end
	for _, m in ipairs(members) do
		if not tonumber(m.guid) then
			return false, "member without a guid"
		end
		if cfg.valid.staffTaints ~= false and (tonumber(m.group) or 1) >= cfg.staffGroup then
			return false, "staff in the group"
		end
		if m.mc then
			return false, "multi-client character"
		end
	end
	if #board.variants > 0 then
		if not run.variant or not board.variantByKey[run.variant] then
			return false, "unknown variant"
		end
	elseif run.variant then
		return false, "variant on a board without variants"
	end
	if run.difficultyStart ~= nil and run.difficulty ~= run.difficultyStart then
		return false, "difficulty changed during the run"
	end
	local size = K.sizeOf(board, run.size or #members, cfg)
	if not size then
		return false, "party size outside the board's limits"
	end
	local value = tonumber(run.value)
	if not value or value ~= value or value <= 0 or value == math.huge then
		return false, "no value"
	end
	if board.mode == "min" and value < (cfg.valid.minSeconds or 1) then
		return false, "time below the minimum"
	end
	return true, size
end

-- ---------------------------------------------------------------- merge and rank
function K.better(mode, a, b)
	a, b = tonumber(a) or 0, tonumber(b) or 0
	if mode == "min" then
		return a > 0 and (b <= 0 or a < b)
	end
	return a > b
end

-- e = {value, at, count} or nil. Returns the entry and whether the value changed. at = when the value was reached:
-- a tie keeps the older at (the first to reach it stays ahead).
function K.merge(e, value, mode, at)
	value = floor(tonumber(value) or 0)
	e = e or {value = 0, count = 0, at = at}
	e.count = (e.count or 0) + 1
	local changed = false
	if mode == "add" then
		if value > 0 then
			e.value = (e.value or 0) + value
			changed = true
		end
	elseif K.better(mode, value, e.value) then
		e.value = value
		changed = true
	end
	if changed then
		e.at = at
	end
	return e, changed
end

local function cmp(mode)
	return function(a, b)
		if a.value ~= b.value then
			if mode == "min" then
				return a.value < b.value
			end
			return a.value > b.value
		end
		if (a.at or 0) ~= (b.at or 0) then
			return (a.at or 0) < (b.at or 0) -- tie: the earlier time first
		end
		return (tonumber(a.guid) or 0) < (tonumber(b.guid) or 0)
	end
end

-- entries = list or {[guid] = entry}; entries with value <= 0 are left out; ranks 1..n, never shared
function K.rank(entries, mode)
	local list = {}
	for k, e in pairs(entries or {}) do
		if (tonumber(e.value) or 0) > 0 then
			if e.guid == nil and type(k) == "number" and not entries[1] then
				e.guid = k
			end
			list[#list + 1] = e
		end
	end
	table.sort(list, cmp(mode))
	for i, e in ipairs(list) do
		e.rank = i
	end
	return list
end

function K.filterClass(ranked, ids)
	if not ids then
		return ranked
	end
	local set, out = {}, {}
	for _, id in ipairs(ids) do
		set[id] = true
	end
	for _, e in ipairs(ranked) do
		if set[e.voc or -1] then
			local c = {}
			for k, v in pairs(e) do
				c[k] = v
			end
			c.rank = #out + 1
			out[#out + 1] = c
		end
	end
	return out
end

function K.find(ranked, guid)
	for _, e in ipairs(ranked) do
		if e.guid == guid then
			return e
		end
	end
	return nil
end

-- the all-time record is beaten: there was one and the value is better
function K.isRecord(prevBest, value, mode)
	return prevBest ~= nil and (tonumber(prevBest) or 0) > 0 and K.better(mode, value, prevBest)
end

-- ---------------------------------------------------------------- weekly awards
-- ranked = {[slot] = ranked list of the ended week}; catOf(slot) -> category key. -> {slot, cat, rank, guid, name, value}
function K.awards(ranked, top, catOf)
	local slots = {}
	for slot in pairs(ranked) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	local out = {}
	for _, slot in ipairs(slots) do
		local list = ranked[slot]
		for i = 1, math.min(top or 3, #list) do
			local e = list[i]
			out[#out + 1] = {slot = slot, cat = catOf and catOf(slot) or nil, rank = i, guid = e.guid, name = e.name,
				value = e.value}
		end
	end
	return out
end

-- awards -> {[guid] = {cats = {[cat] = best rank}, count = n}}
function K.held(awards)
	local map = {}
	for _, a in ipairs(awards or {}) do
		local h = map[a.guid] or {cats = {}, count = 0}
		map[a.guid] = h
		h.count = h.count + 1
		if a.cat and (not h.cats[a.cat] or a.rank < h.cats[a.cat]) then
			h.cats[a.cat] = a.rank
		end
	end
	return map
end

function K.firstTitle(cfg, short)
	local text = string.format(cfg.firstTitle or "First: %s", tostring(short or "?"))
	if #text > 24 then
		local cut = text:sub(1, 25)
		text = cut:match("^(.*%S)%s+%S*$") or text:sub(1, 24) -- at a word boundary
		if #text > 24 then
			text = text:sub(1, 24)
		end
	end
	return text
end

-- held (K.held entry or nil), firsts = {{target, short, at}} of the player this season -> ChaosTitles titles
function K.titlesOf(cfg, held, firsts, weekAt)
	local out = {}
	if held then
		for _, cat in ipairs(cfg.categories) do
			if held.cats[cat.key] then
				out[#out + 1] = {key = "records:" .. cat.key, text = cat.title, color = cfg.titleColor, at = weekAt or 0}
			end
		end
	end
	for _, f in ipairs(firsts or {}) do
		out[#out + 1] = {key = "records:first:" .. f.target, text = K.firstTitle(cfg, f.short), color = cfg.firstColor,
			at = f.at or 0}
	end
	return out
end

-- ---------------------------------------------------------------- texts
function K.valueText(value, format)
	value = tonumber(value) or 0
	if format == "time" then
		local s = math.max(0, floor(value))
		if s >= 3600 then
			return string.format("%d:%02d:%02d", floor(s / 3600), floor(s % 3600 / 60), s % 60)
		end
		return string.format("%d:%02d", floor(s / 60), s % 60)
	elseif format == "pct" then
		return string.format("%.2f%%", value / 100)
	end
	return tostring(floor(value))
end

local function label(board, variant, size)
	local parts = {board.name}
	local v = variant and board.variantByKey[variant]
	if v then
		parts[#parts + 1] = v.name
	end
	for _, s in ipairs(board.sizes) do
		if s.key == size then
			parts[#parts + 1] = s.name
		end
	end
	return table.concat(parts, ", ")
end
K.label = label

local function names(list)
	local n = {}
	for _, m in ipairs(list or {}) do
		n[#n + 1] = m.name or "?"
	end
	table.sort(n)
	if #n > 5 then
		local more = #n - 5
		n = {n[1], n[2], n[3], n[4], n[5]}
		n[#n + 1] = string.format("%d more", more)
	end
	return table.concat(n, ", ")
end
K.names = names

-- a text in `lang` (server/README.md "Server texts in pt-BR (Chaos.t)"); English without ChaosI18n
local function T(lang, key, ...)
	if ChaosI18n then
		return ChaosI18n.text(lang, key, ...)
	end
	return string.format(key, ...)
end

function K.recordText(board, variant, size, value, members, prev, lang)
	return T(lang, "New record! %s: %s by %s%s.", label(board, variant, size), K.valueText(value, board.format),
		names(members), prev and T(lang, " (was %s)", K.valueText(prev, board.format)) or "")
end

-- display = the third value of K.firstTarget (the boss's full name, or the board's)
function K.firstText(display, members, seasonName, lang)
	return T(lang, #members == 1 and "Realm first of %s! %s is the first to defeat %s." or
		"Realm first of %s! %s are the first to defeat %s.", seasonName or T(lang, "the season"), names(members),
		tostring(display))
end

-- the realm first target of a run: key, short name, display name (nil: the board has no realm firsts). run.first = {key, short}
-- overrides (the trials: one first per class family boss and difficulty).
function K.firstTarget(board, variant, run)
	if not board.first then
		return nil
	end
	if run and type(run.first) == "table" and run.first.key then
		local v = variant and board.variantByKey[variant]
		local name = run.first.short or board.name
		return board.key .. ":" .. tostring(run.first.key), name, v and (name .. " (" .. v.name .. ")") or name
	end
	local v = variant and board.variantByKey[variant]
	if v and board.template ~= "hollowvault" and not board.dungeon then
		return board.key .. ":" .. tostring(variant), v.short or v.name, v.name
	end
	return board.key, K.shortName(board.name), board.name
end

-- the name a realm first is listed by (the client's Realm Firsts, records.lua rfirsts), from its stored target: the
-- third value of K.firstTarget. A first keeps only its target and the short title name ("Skaldra"); the list showed
-- that short name (live test 2026-10-14) instead of "Skaldra the Rime Queen". byKey = the catalogue's boards by key;
-- short = the stored name (used when the target names no board or variant any more).
function K.firstDisplay(byKey, target, short)
	target = tostring(target or "")
	local bkey, rest = target:match("^([^:]+):(.+)$")
	local board = byKey and byKey[bkey or target]
	if not board then
		return short
	end
	if not rest then
		return board.name
	end
	local vk = board.variantByKey or {}
	if vk[rest] then
		return vk[rest].name
	end
	-- run.first override ("<family>.<variant>": the trials): the stored name and the variant, as K.firstTarget
	local v = vk[rest:match("%.([^.]+)$") or ""]
	if v and short then
		return short .. " (" .. v.name .. ")"
	end
	return short or board.name
end
