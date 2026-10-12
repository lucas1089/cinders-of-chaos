-- Death recap, pure logic (no engine calls): the rolling log of damage a character takes (a ring of the last hits,
-- bounded by count and age), the recap built from it at a death (attackers with health / mana damage and the element
-- split, the killing blow, the time window, the last hits), the payload bound, the experience and levels lost
-- (filled in at the next login), the history of the last deaths and the SQL of the table. Used by deathrecap.lua;
-- tested by server/tests/deathrecap_test.lua. Lua 5.1 / LuaJIT and 5.3 compatible.
--
-- A hit: {t (ms), k (attacker key "<kind>:<name>[>master]"), n (name as the victim saw it), kind, m (master's name of
-- a summon), el (element name), a (amount), c (critical), mp (true: mana, a mana shield or mana drain), pv (true: a
-- player's summon, so the hit counts as PvP)}
-- Kinds: c monster, u player, s the character itself, e environment (no attacker), h hidden (ghost staff), o others
-- (the rows beyond maxAttackers summed)
--
-- A recap (JSON on the wire and in the table; short keys):
--   {v = 1, at (unix time), real (1 a death, 0 a mode's defeat), mode (label of the instance, or nil), mk (its key),
--    lvl, exp (level and experience before the death), xl, ll (experience and levels lost; set at the next login),
--    kb = {n, kind, m, el, a, c, mp} (the killing blow), dur (ms from the first hit shown to the death), win (window ms),
--    tot, hp, mp (damage shown: all, health, mana), el = {[element] = amount}, pvp (1 when a player took part),
--    nh (hits shown), att = [{n, kind, m, look, tot, hp, mp, h (hits), c (crits), x (max), el = {[element] = amount}}],
--    last = [{dt (ms before the death), n, el, a, c, mp}]}

ChaosDeathRecap = ChaosDeathRecap or {}
local R = ChaosDeathRecap
local floor, max, min = math.floor, math.max, math.min

local DEFAULTS = {windowMs = 20000, maxHits = 60, maxAttackers = 8, lastHits = 6, nameMax = 40, maxRecapBytes = 5000,
	keep = 5, hiddenName = "Unseen attacker", killerGapMs = 1500}
R.cfg = R.cfg or {}
for k, v in pairs(DEFAULTS) do
	if R.cfg[k] == nil then
		R.cfg[k] = v
	end
end

function R.configure(cfg)
	R.cfg = {}
	for k, v in pairs(DEFAULTS) do
		R.cfg[k] = v
	end
	for k, v in pairs(cfg or {}) do
		R.cfg[k] = v
	end
	return R.cfg
end

-- ---------------------------------------------------------------- names, keys, looks
function R.cut(name)
	name = tostring(name or "")
	local n = R.cfg.nameMax or 40
	if #name > n then
		name = name:sub(1, n)
	end
	return name
end

function R.key(kind, name, master)
	local k = tostring(kind) .. ":" .. tostring(name or "")
	if master then
		k = k .. ">" .. tostring(master)
	end
	return k
end

-- an engine outfit ({lookType, lookHead, ..., lookTypeEx}) -> the names the client's UICreature takes, or nil
function R.look(o)
	if type(o) ~= "table" then
		return nil
	end
	local function n(v, top)
		v = floor(tonumber(v) or 0)
		if v ~= v or v < 0 or v > top then
			return 0
		end
		return v
	end
	local t = {type = n(o.lookType, 65535), head = n(o.lookHead, 255), body = n(o.lookBody, 255), legs = n(o.lookLegs, 255),
		feet = n(o.lookFeet, 255), addons = n(o.lookAddons, 3)}
	local aux = n(o.lookTypeEx, 65535)
	if aux > 0 then
		t.type, t.auxType = 0, aux
	end
	if t.type == 0 and not t.auxType then
		return nil
	end
	return t
end

-- ---------------------------------------------------------------- the rolling log
function R.newLog()
	return {buf = {}, head = 0, n = 0, looks = {}, nLooks = 0}
end

-- adds a hit (the table is kept; the caller makes a new one per hit). The oldest hit goes beyond maxHits.
function R.record(log, now, hit)
	local cap = R.cfg.maxHits
	hit.t = now
	log.head = log.head % cap + 1
	log.buf[log.head] = hit
	if log.n < cap then
		log.n = log.n + 1
	end
	-- a cap lowered by a /reload: the ring starts over with this hit
	if log.head > cap or log.n > cap then
		log.buf, log.head, log.n = {hit}, 1, 1
	end
	return hit
end

-- the hits, oldest first
function R.hits(log)
	local out = {}
	local cap = R.cfg.maxHits
	local start = log.n < cap and 1 or (log.head % cap + 1)
	for i = 0, log.n - 1 do
		local h = log.buf[(start - 1 + i) % cap + 1]
		if h then
			out[#out + 1] = h
		end
	end
	return out
end

-- drops the hits older than the window (a log with nothing left can be forgotten: returns true)
function R.prune(log, now)
	if log.n == 0 then
		return true
	end
	local cut = now - R.cfg.windowMs
	local keep = {}
	for _, h in ipairs(R.hits(log)) do
		if h.t >= cut then
			keep[#keep + 1] = h
		end
	end
	if #keep == log.n then
		return false
	end
	log.buf, log.n, log.head = keep, #keep, #keep
	if log.n == 0 then
		log.looks, log.nLooks = {}, 0
		return true
	end
	return false
end

-- whether the look of an attacker is still to be taken (bounded: twice maxAttackers per log)
function R.wantLook(log, key)
	return log.looks[key] == nil and log.nLooks < 2 * R.cfg.maxAttackers + 4
end

function R.setLook(log, key, look)
	if log.looks[key] == nil then
		log.looks[key] = look or false
		log.nLooks = log.nLooks + 1
	end
end

-- ---------------------------------------------------------------- the recap
local function addEl(t, el, a)
	el = el or "other"
	t[el] = (t[el] or 0) + a
end

local function newRow(h)
	return {k = h.k, n = h.n, kind = h.kind, m = h.m, tot = 0, hp = 0, mp = 0, h = 0, c = 0, x = 0, el = {}}
end

local function addHit(row, h)
	local a = h.a
	row.tot = row.tot + a
	if h.mp then
		row.mp = row.mp + a
	else
		row.hp = row.hp + a
	end
	row.h = row.h + 1
	if h.c then
		row.c = row.c + 1
	end
	if a > row.x then
		row.x = a
	end
	addEl(row.el, h.el, a)
end

local function mergeInto(dst, src)
	dst.tot, dst.hp, dst.mp = dst.tot + src.tot, dst.hp + src.hp, dst.mp + src.mp
	dst.h, dst.c, dst.x = dst.h + src.h, dst.c + src.c, max(dst.x, src.x)
	for el, a in pairs(src.el) do
		addEl(dst.el, el, a)
	end
end

local function sortRows(rows)
	table.sort(rows, function(a, b)
		if a.tot ~= b.tot then
			return a.tot > b.tot
		end
		return tostring(a.n) < tostring(b.n)
	end)
end

local function others()
	return {k = "o:", n = "Others", kind = "o", tot = 0, hp = 0, mp = 0, h = 0, c = 0, x = 0, el = {}}
end

local function strip(row, looks)
	local out = {n = row.n, kind = row.kind, m = row.m, tot = row.tot, hp = row.hp, mp = row.mp, h = row.h, c = row.c,
		x = row.x, el = row.el}
	local look = looks and looks[row.k]
	if look then
		out.look = look
	end
	return out
end

-- the recap of a death at deathAt (ms, the log's clock). info = {at (unix), real (bool), mode, mk, level, exp,
-- killer = {n, kind, m} (the engine's last hit creature: the killing blow when the log has no hit, or when its last
-- health hit is another attacker's or older than killerGapMs; then without an amount)}
function R.build(log, deathAt, info)
	info = info or {}
	local cfg = R.cfg
	local from = deathAt - cfg.windowMs
	local shown = {}
	for _, h in ipairs(R.hits(log)) do
		if h.t >= from and h.t <= deathAt then
			shown[#shown + 1] = h
		end
	end
	local byKey, rows = {}, {}
	local recap = {v = 1, at = info.at, real = info.real == false and 0 or 1, mode = info.mode, mk = info.mk,
		lvl = info.level, exp = info.exp, win = cfg.windowMs, tot = 0, hp = 0, mp = 0, el = {}, nh = #shown, dur = 0}
	local pvp = false
	for _, h in ipairs(shown) do
		local row = byKey[h.k]
		if not row then
			row = newRow(h)
			byKey[h.k] = row
			rows[#rows + 1] = row
		end
		addHit(row, h)
		recap.tot = recap.tot + h.a
		if h.mp then
			recap.mp = recap.mp + h.a
		else
			recap.hp = recap.hp + h.a
		end
		addEl(recap.el, h.el, h.a)
		if h.kind == "u" or h.pv then
			pvp = true
		end
	end
	if #shown > 0 then
		recap.dur = deathAt - shown[1].t
	end
	-- the killing blow: the last health hit (a mana shield hit cannot kill), else the last hit, else the engine's killer
	local kb
	for i = #shown, 1, -1 do
		if not shown[i].mp then
			kb = shown[i]
			break
		end
	end
	kb = kb or shown[#shown]
	-- the engine's killer when the log missed the lethal hit (a script's damage without health events, ORIGIN_NONE):
	-- another attacker, or the last logged hit is too long before the death
	local killer = info.killer
	if kb and killer and killer.n and (kb.n ~= killer.n or deathAt - kb.t > (cfg.killerGapMs or 1500)) then
		kb = nil
	end
	if kb then
		recap.kb = {n = kb.n, kind = kb.kind, m = kb.m, el = kb.el, a = kb.a, c = kb.c and 1 or nil, mp = kb.mp and 1 or nil}
	elseif info.killer and info.killer.n then
		recap.kb = {n = R.cut(info.killer.n), kind = info.killer.kind or "c", m = info.killer.m}
		if info.killer.kind == "u" then
			pvp = true
		end
	else
		recap.kb = {n = "Unknown", kind = "e"}
	end
	recap.pvp = pvp and 1 or nil
	sortRows(rows)
	local att = {}
	local rest
	for i, row in ipairs(rows) do
		if i < cfg.maxAttackers or (i == cfg.maxAttackers and #rows == cfg.maxAttackers) then
			att[#att + 1] = strip(row, log.looks)
		else
			rest = rest or others()
			mergeInto(rest, row)
		end
	end
	if rest then
		att[#att + 1] = strip(rest)
	end
	recap.att = att
	local last = {}
	for i = max(1, #shown - cfg.lastHits + 1), #shown do
		local h = shown[i]
		last[#last + 1] = {dt = deathAt - h.t, n = h.n, el = h.el, a = h.a, c = h.c and 1 or nil, mp = h.mp and 1 or nil}
	end
	recap.last = last
	return R.fit(recap, cfg.maxRecapBytes)
end

-- ---------------------------------------------------------------- payload size
-- about the length of json.encode(v) (keys quoted, strings escaped as they are: names have no quotes or backslashes
-- worth counting twice; a little over is fine, never under for plain data)
function R.size(v)
	local tv = type(v)
	if tv == "table" then
		local n = 2
		local isArray = #v > 0
		for k, x in pairs(v) do
			n = n + R.size(x) + 1
			if not isArray then
				n = n + #tostring(k) + 3
			end
		end
		return n
	elseif tv == "string" then
		local extra = 0
		for _ in v:gmatch('[%c"\\]') do
			extra = extra + 5
		end
		return #v + 2 + extra
	elseif tv == "number" then
		return #string.format("%.14g", v)
	elseif tv == "boolean" then
		return 5
	end
	return 4
end

-- cuts a recap to maxBytes: the attackers from the bottom into "Others" (one row stays), then the timeline
function R.fit(recap, maxBytes)
	maxBytes = maxBytes or R.cfg.maxRecapBytes
	local att = recap.att or {}
	while R.size(recap) > maxBytes and #att > 2 do
		local last = att[#att]
		local rest
		if last.kind == "o" then
			table.remove(att)
			rest = last
			last = table.remove(att)
		else
			table.remove(att)
			rest = {n = "Others", kind = "o", tot = 0, hp = 0, mp = 0, h = 0, c = 0, x = 0, el = {}}
		end
		mergeInto(rest, last)
		att[#att + 1] = rest
	end
	local last = recap.last or {}
	while R.size(recap) > maxBytes and #last > 1 do
		table.remove(last, 1)
	end
	-- still too big (absurd names): the element splits of the rows go
	if R.size(recap) > maxBytes then
		for _, row in ipairs(att) do
			row.el = {}
			row.look = nil
		end
	end
	return recap
end

-- ---------------------------------------------------------------- after the death
-- the experience and levels lost, from the character as it logs in again (a mode's defeat loses nothing)
function R.finalize(recap, levelNow, expNow)
	if type(recap) ~= "table" or recap.xl ~= nil then
		return recap
	end
	if recap.real == 1 and tonumber(recap.exp) and tonumber(levelNow) and tonumber(expNow) then
		recap.xl = max(0, floor(recap.exp - expNow))
		recap.ll = max(0, floor((tonumber(recap.lvl) or levelNow) - levelNow))
	else
		recap.xl, recap.ll = 0, 0
	end
	return recap
end

-- the line of a recap in the history list
function R.summary(id, recap)
	recap = type(recap) == "table" and recap or {}
	local kb = type(recap.kb) == "table" and recap.kb or {}
	return {id = id, at = recap.at, k = kb.n, kind = kb.kind, lvl = recap.lvl, xl = recap.xl, ll = recap.ll,
		mode = recap.mode, pvp = recap.pvp, tot = recap.tot, real = recap.real}
end

-- a history list (newest first) with a new entry in front, cut to `keep`
function R.pushHistory(list, entry, keep)
	keep = keep or R.cfg.keep
	table.insert(list, 1, entry)
	while #list > keep do
		table.remove(list)
	end
	return list
end

-- whether a mode (an instance key) hides its recaps on purpose
function R.hidden(modeKey, hideModes)
	if not modeKey then
		return false
	end
	for _, k in ipairs(hideModes or {}) do
		if k == modeKey then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- SQL
function R.createSql(T)
	return "CREATE TABLE IF NOT EXISTS `" .. T .. "` (`id` int(10) unsigned NOT NULL AUTO_INCREMENT, " ..
		"`player_id` int(11) NOT NULL, `at` int(10) unsigned NOT NULL DEFAULT 0, `seen` tinyint(1) unsigned NOT NULL DEFAULT 0, " ..
		"`data` text NOT NULL, PRIMARY KEY (`id`), KEY `player_id` (`player_id`, `id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
end

function R.insertSql(T, guid, at, data, seen, esc)
	return string.format("INSERT INTO `%s` (`player_id`, `at`, `seen`, `data`) VALUES (%d, %d, %d, %s)", T, floor(guid),
		floor(at or 0), seen and 1 or 0, esc(data))
end

-- deletes the rows of a character beyond the newest `keep`
function R.trimSql(T, guid, keep)
	return string.format("DELETE FROM `%s` WHERE `player_id` = %d AND `id` NOT IN (SELECT `id` FROM (SELECT `id` FROM `%s` " ..
		"WHERE `player_id` = %d ORDER BY `id` DESC LIMIT %d) AS `k`)", T, floor(guid), T, floor(guid), floor(keep))
end

function R.listSql(T, guid, keep)
	return string.format("SELECT `id`, `at`, `seen`, `data` FROM `%s` WHERE `player_id` = %d ORDER BY `id` DESC LIMIT %d", T,
		floor(guid), floor(keep))
end

function R.seenSql(T, id, guid, data, esc)
	return string.format("UPDATE `%s` SET `seen` = 1, `data` = %s WHERE `id` = %d AND `player_id` = %d", T, esc(data), floor(id),
		floor(guid))
end

return R
