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
--   H.xpAnomaly(level, gained)         an experience gain that is negative or absurd for the level
--   H.itemAnomaly(item)                an item with an impossible count or stat
-- Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosTesterHelperCore = ChaosTesterHelperCore or {}
local H = ChaosTesterHelperCore

H.STORAGE = 7102900 -- Chaos.storage.tester (chaos_constants.lua; the test checks they agree)
H.MARK = "[tester-helper]"
H.ANOMALY = "[tester-anomaly]"
H.COMMANDS = {town = true, depot = true, shop = true, hunt = true, info = true, enter = true, places = true}

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

return H
