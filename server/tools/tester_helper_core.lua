-- TEST ONLY: never ship this file. It is not under server/data, so install_all.py never copies it.
-- Pure rules of the tester bots' helper (tester_helper.lua; server/README.md "Tester bots"; tests/tester_helper_test.lua).
-- chaos-ctl.sh testers start copies both files into data/scripts as zz_tester_helper.lua and zz_tester_helper_core.lua
-- and removes them at stop. The engine loads this one as a script too: it only sets a table.
--
--   H.eligible(name, storageValue)     the helper acts ONLY on a character that has BOTH the tester storage (= 1) and a
--                                       "Tester Xxx" name. Anything else (every real player) is never touched.
--   H.nearest(origin, list, range)     the nearest live, unowned monster on the same floor within range
--   H.directionTo(from, to)            the direction to face a target (0 north, 1 east, 2 south, 3 west)
--   H.parseCommand(param)              "!tester <command> [arg]" -> command, arg (unknown -> nil)
--   H.encode(kind, data)               one helper line: "[tester-helper] <kind> <json>" (the bot reads it)
--   H.hitAnomaly(hit)                  a hit taken or dealt far out of range for the level, or a one-shot from full
--   H.pushHit(list, now, hit)          remember a hit a tester took (the last 10 seconds)
--   H.deathRecord(list, now, d)        the death event: hits, damage and the biggest hit of the last 5 seconds, as % of max health
--   H.xpAnomaly(level, gained)         an experience gain that is negative or absurd for the level
--   H.itemAnomaly(item)                an item with an impossible count or stat
--   H.parsePlace(arg)                  "enter <kind> [N]" / "enter npc <name>" / "enter rift [tier]" -> a place, or nil
--   H.pickMark(marks, kind, n)         the n-th map mark of a kind (data/chaos_poi.lua marks; wraps), and the count
--   H.placeCounts(marks)               {kind = count} of the marks the helper can bring a tester to
--   H.bagPlan(items, want, held)       the backpack clean-up: which top-level items to remove (every id not in `want`) and which
--                                       supplies to add (an id of `want` held under half of its number, up to the number)
--   H.onlineLine(count, last, minute)  the console line "[tester-helper] testers online: N" when the count changed
--                                       since the last line, or every 5 minutes; nil otherwise
-- Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosTesterHelperCore = ChaosTesterHelperCore or {}
local H = ChaosTesterHelperCore

H.STORAGE = 7102900 -- Chaos.storage.tester (chaos_constants.lua; the test checks they agree)
H.MARK = "[tester-helper]"
H.ANOMALY = "[tester-anomaly]"
H.COMMANDS = {town = true, depot = true, shop = true, hunt = true, info = true, enter = true, places = true, bag = true}

-- numbers of the anomaly rules (a hit is "absurd" far above anything the game should do; tune with the report)
H.limits = {
	takenOverMaxHealth = 3, -- a single hit taken larger than 3x the tester's max health
	dealtBase = 5000, -- a single hit dealt larger than dealtBase + dealtPerLevel * level
	dealtPerLevel = 400,
	xpPerLevel = 2000000, -- one experience gain larger than xpPerLevel * level (the cap rules allow far less)
	maxStack = 100,
	maxAttr = 10000000, -- a numeric item attribute beyond this is impossible
}

function H.eligible(name, storageValue)
	return type(name) == "string" and name:match("^Tester [A-Z][a-z][a-z]$") ~= nil and storageValue == 1
end

local function cheb(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- list: {pos = {x, y, z}, health, owned (has a master), id}
function H.nearest(origin, list, range)
	local best, bestD
	for _, c in ipairs(list or {}) do
		if c.pos and c.pos.z == origin.z and not c.owned and (c.health or 0) > 0 then
			local d = cheb(origin, c.pos)
			if d <= range and (not bestD or d < bestD or (d == bestD and (c.id or 0) < (best.id or 0))) then
				best, bestD = c, d
			end
		end
	end
	return best, bestD
end

function H.directionTo(from, to)
	local dx, dy = to.x - from.x, to.y - from.y
	if math.abs(dx) > math.abs(dy) then
		return dx > 0 and 1 or 3
	end
	return dy > 0 and 2 or 0
end

function H.parseCommand(param)
	if type(param) ~= "string" then
		return nil
	end
	local cmd, arg = param:match("^%s*(%a+)%s*(.-)%s*$")
	cmd = cmd and cmd:lower()
	if not cmd or not H.COMMANDS[cmd] then
		return nil
	end
	return cmd, arg ~= "" and arg or nil
end

-- the places `!tester enter` brings a tester to: map mark kinds (poi_core.lua P.KINDS, guild halls left out: guilds
-- are out of scope), an NPC by name, and a rift (a key of the tier into the backpack, then the temple)
H.PLACE_KINDS = {temple = true, depot = true, craft = true, bank = true, bless = true, travel = true, shop = true,
	boss = true, hunt = true, npc = true, portal = true, dungeon = true}
H.RIFT_MAX = 15

-- items = {{id, count}, ...} (the backpack's own slots); want = {[itemId] = number} (the supplies a tester keeps);
-- held = {[itemId] = number} (carried in all, nested bags too). Returns the indexes of `items` to remove and the
-- {id, count} to add, by id. A tester loots and never sells, so the bag fills; the potions are used up.
function H.bagPlan(items, want, held)
	local remove, add = {}, {}
	for i, it in ipairs(items or {}) do
		if not want[it.id] then
			remove[#remove + 1] = i
		end
	end
	for id, n in pairs(want or {}) do
		local have = (held or {})[id] or 0
		if have < n / 2 then
			add[#add + 1] = {id = id, count = n - have}
		end
	end
	table.sort(add, function(a, b) return a.id < b.id end)
	return remove, add
end

function H.parsePlace(arg)
	if type(arg) ~= "string" then
		return nil
	end
	local kind, rest = arg:match("^%s*(%a+)%s*(.-)%s*$")
	kind = kind and kind:lower()
	if kind == "rift" then
		local t = tonumber(rest) or 1
		t = math.floor(t)
		if t < 1 then t = 1 end
		if t > H.RIFT_MAX then t = H.RIFT_MAX end
		return {kind = "rift", tier = t}
	end
	if kind == "npc" then
		-- an NPC name: letters, spaces, apostrophes; never a player (the engine file checks isNpc)
		if rest == "" or #rest > 40 or not rest:match("^[%a][%a '%-]*$") then
			return nil
		end
		return {kind = "npc", name = rest}
	end
	if not kind or not H.PLACE_KINDS[kind] then
		return nil
	end
	local n = tonumber(rest)
	if rest ~= "" and (not n or n < 1 or n ~= math.floor(n)) then
		return nil
	end
	return {kind = kind, n = n}
end

function H.pickMark(marks, kind, n)
	local list = {}
	for _, m in ipairs(marks or {}) do
		if m.k == kind and m.x and m.y and m.z then
			list[#list + 1] = m
		end
	end
	if #list == 0 then
		return nil, 0
	end
	return list[((n or 1) - 1) % #list + 1], #list
end

function H.placeCounts(marks)
	local out = {}
	for _, m in ipairs(marks or {}) do
		if H.PLACE_KINDS[m.k] and m.k ~= "npc" then
			out[m.k] = (out[m.k] or 0) + 1
		end
	end
	return out
end

-- a small JSON writer (the engine's json may be missing in the tests; no functions, no cycles)
local function enc(v)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		return (math.floor(v) == v and math.abs(v) < 1e15) and string.format("%d", v) or string.format("%.4f", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			local map = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
			return map[c] or string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local out = {}
			for i = 1, #v do
				out[i] = enc(v[i])
			end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys, vals = {}, {}
		for k, val in pairs(v) do
			keys[#keys + 1] = tostring(k)
			vals[tostring(k)] = val
		end
		table.sort(keys)
		local out = {}
		for _, k in ipairs(keys) do
			out[#out + 1] = enc(k) .. ":" .. enc(vals[k])
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end
H.json = enc

function H.encode(kind, data)
	return H.MARK .. " " .. kind .. " " .. enc(data or {})
end

-- hit: {kind = "taken" | "dealt", damage, health (before), maxHealth, level}
-- returns the rule name or nil
function H.hitAnomaly(hit)
	local L = H.limits
	local dmg = tonumber(hit.damage) or 0
	if dmg < 0 or dmg ~= dmg then
		return "negative damage"
	end
	if hit.kind == "taken" then
		local maxH = math.max(1, tonumber(hit.maxHealth) or 1)
		if dmg > L.takenOverMaxHealth * maxH then
			return "hit taken over " .. L.takenOverMaxHealth .. "x max health"
		end
		if (tonumber(hit.health) or 0) >= maxH and dmg >= maxH and maxH > 1 then
			return "one hit from full health"
		end
	elseif hit.kind == "dealt" then
		local level = math.max(1, tonumber(hit.level) or 1)
		if dmg > L.dealtBase + L.dealtPerLevel * level then
			return "hit dealt far above the level"
		end
	end
	return nil
end

-- the last hits a tester took, for its death record (the first live run, 2026-10-27: 2998 deaths and nobody could say whether one
-- hit or a pack did it). list: {{t, damage, by}}, newest last; the helper keeps one per tester.
H.HIT_WINDOW = 5 -- seconds a death record looks back
H.HIT_KEEP = 40

function H.pushHit(list, now, hit)
	list[#list + 1] = {t = now, damage = math.max(0, tonumber(hit.damage) or 0), by = hit.by}
	while #list > H.HIT_KEEP or (list[1] and now - list[1].t > 2 * H.HIT_WINDOW) do
		table.remove(list, 1)
	end
end

-- d: {who, level, killer, maxHealth, online (seconds since the login)}; the record the console line carries: how many hits
-- in the last HIT_WINDOW seconds, their sum, the biggest one and the monster that dealt it, both as a percent of the maximum
function H.deathRecord(list, now, d)
	local hits, sum, big, bigBy = 0, 0, 0, nil
	for _, h in ipairs(list or {}) do
		if now - h.t <= H.HIT_WINDOW then
			hits = hits + 1
			sum = sum + h.damage
			if h.damage > big then
				big, bigBy = h.damage, h.by
			end
		end
	end
	local maxH = math.max(1, tonumber(d.maxHealth) or 1)
	return {kind = "death", who = d.who, level = d.level, killer = d.killer or "?", t = now, maxHealth = maxH,
		hits = hits, damage = sum, damagePct = math.floor(100 * sum / maxH), biggest = big,
		biggestPct = math.floor(100 * big / maxH), biggestBy = bigBy or "?", online = d.online}
end

function H.xpAnomaly(level, gained)
	gained = tonumber(gained)
	if not gained or gained ~= gained then
		return "experience not a number"
	end
	if gained < 0 then
		return "negative experience gain"
	end
	if gained > H.limits.xpPerLevel * math.max(1, tonumber(level) or 1) then
		return "absurd experience gain"
	end
	return nil
end

-- item: {count, stackable, attrs = {name = number}}
function H.itemAnomaly(item)
	local count = tonumber(item.count) or 1
	if count < 1 or (item.stackable and count > H.limits.maxStack) then
		return "impossible count " .. count
	end
	for k, v in pairs(item.attrs or {}) do
		if type(v) == "number" and (v ~= v or v < -H.limits.maxAttr or v > H.limits.maxAttr) then
			return "impossible attribute " .. tostring(k) .. " = " .. enc(v)
		end
	end
	return nil
end

-- once a minute the helper counts the testers in game; the server console gets a line when it changed (or every
-- ONLINE_EVERY minutes, so the log shows they are still there)
H.ONLINE_EVERY = 5
function H.onlineLine(count, last, minute)
	if count == last and (minute or 0) % H.ONLINE_EVERY ~= 0 then
		return nil
	end
	return string.format("%s testers online: %d", H.MARK, count)
end

return H
