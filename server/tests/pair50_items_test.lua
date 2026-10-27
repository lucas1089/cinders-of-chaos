-- Run from the server/ folder: luajit tests/pair50_items_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Pair 50 items: the generated ids file (data/lib/chaos_pair50_items.lua) lists exactly the ladders of the manifest
-- (data/items/pair50_items.csv), in range; the ladder script registers one Action for the ids the server knows, moves the
-- player up with the base's Position:moveUpstairs(), and refuses a protection zone for a player with a pz lock; the generated
-- effects table (data/lib/chaos_pair50_fx_ids.lua) has one ChaosVfx entry per effect, consecutive ids after 4101.
local failures = 0
local function ok(c, msg)
	if not c then
		failures = failures + 1
		print("FAIL " .. msg)
	end
end
local function eq(a, b, msg)
	ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function readFile(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- the manifest: client id, server id, key, ..., floorchange, use (columns by header name; no field holds a comma but names)
local manifest = readFile("data/items/pair50_items.csv")
ok(manifest ~= nil, "manifest")
local function split(line)
	local out, i, n = {}, 1, #line
	while i <= n + 1 do
		local c = line:sub(i, i)
		if c == '"' then
			local j = line:find('"', i + 1, true)
			out[#out + 1] = line:sub(i + 1, j - 1)
			i = j + 2
		else
			local j = line:find(",", i, true) or (n + 1)
			out[#out + 1] = line:sub(i, j - 1)
			i = j + 1
		end
	end
	return out
end
local header, col = nil, {}
local rows = {}
for line in (manifest or ""):gmatch("[^\r\n]+") do
	if not header then
		header = split(line)
		for i, name in ipairs(header) do
			col[name] = i
		end
	else
		rows[#rows + 1] = split(line)
	end
end
eq(#rows, 5198, "manifest rows")
local ladders, stairsDown, stairsUp = {}, 0, 0
for i, r in ipairs(rows) do
	local cid, sid = tonumber(r[col.client_id]), tonumber(r[col.server_id])
	eq(sid, cid + 4000, "server id of row " .. i)
	eq(cid, 39197 + i, "client ids are consecutive from 39198 (row " .. i .. ")")
	if r[col.use] == "ladder" then
		ladders[#ladders + 1] = sid
	end
	if r[col.floorchange] == "down" then stairsDown = stairsDown + 1 end
	if r[col.floorchange] == "north" or r[col.floorchange] == "west" then stairsUp = stairsUp + 1 end
	ok(r[col.floorchange] == "" or r[col.category] == "stairs", "floor change only on stairs, row " .. i)
end
ok(stairsDown >= 10 and stairsUp >= 60, "stairs down and up are present")

dofile("data/lib/chaos_pair50_items.lua")
eq(#ChaosPair50.ladders, #ladders, "ladders in the ids file")
for i, id in ipairs(ladders) do
	eq(ChaosPair50.ladders[i], id, "ladder " .. i)
end
ok(#ladders >= 8, "at least eight ladders")

-- the script, with a mocked engine
local registered, ids, used = 0, {}, nil
local known = {}
for _, id in ipairs(ladders) do
	known[id] = true
end
known[ladders[#ladders]] = nil -- the server does not know the last one (an older items.otb)
function Action()
	local a = {}
	function a:id(i) ids[#ids + 1] = i end
	function a:register() registered = registered + 1; used = self end
	return a
end
function ItemType(id) return {getId = function() return known[id] and id or 0 end} end
function Position(p)
	local o = {x = p.x, y = p.y, z = p.z}
	function o:moveUpstairs() self.z = self.z - 1; self.y = self.y + 1 end
	return o
end
local pz = false
function Tile(p) return {hasFlag = function() return pz end} end
TILESTATE_PROTECTIONZONE, RETURNVALUE_PLAYERISPZLOCKED = 1, 7
ChaosPair50 = nil
dofile("data/scripts/chaos/pair50_items.lua")
eq(registered, 1, "one Action registered")
eq(#ids, #ladders - 1, "an id the server does not know is not registered")
for _, id in ipairs(ids) do
	ok(known[id], "registered id " .. id .. " is a ladder")
end

local function player(locked)
	local p = {sent = nil, to = nil}
	function p:isPzLocked() return locked end
	function p:sendCancelMessage(m) self.sent = m end
	function p:teleportTo(dest, push) self.to = dest; self.push = push end
	return p
end
local p = player(false)
eq(used.onUse(p, {}, {x = 100, y = 200, z = 8}, nil, nil, false), true, "onUse is handled")
ok(p.to ~= nil and p.to.z == 7 and p.to.x == 100 and p.to.y == 201, "the player goes up one floor (the base's moveUpstairs)")
eq(p.push, false, "no push effect")
pz = true
p = player(true)
used.onUse(p, {}, {x = 100, y = 200, z = 8}, nil, nil, false)
eq(p.sent, RETURNVALUE_PLAYERISPZLOCKED, "a pz-locked player may not enter a protection zone")
ok(p.to == nil, "and stays")
p = player(false)
used.onUse(p, {}, {x = 100, y = 200, z = 8}, nil, nil, false)
ok(p.to ~= nil, "a player without the lock may")

-- the effects table
dofile("data/lib/chaos_pair50_fx_ids.lua")
local count, first, last = 0, nil, nil
for name, v in pairs(ChaosVfx) do
	if name:match("^p50_") then
		count = count + 1
		first = (first == nil or v.id < first) and v.id or first
		last = (last == nil or v.id > last) and v.id or last
		ok(v.dx >= 0 and v.dy >= 0 and v.ms >= 0, "effect " .. name .. " offsets and duration")
		ok(name:match("_" .. v.id .. "$"), "effect name ends with its id: " .. name)
	end
end
eq(count, 600, "600 pair 50 effects")
eq(first, 4102, "first effect id")
eq(last, 4701, "last effect id")

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("pair50_items_test: OK")
