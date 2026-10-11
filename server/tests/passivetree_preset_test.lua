-- Run from the server/ folder: luajit tests/passivetree_preset_test.lua (and lua5.3; CI runs both). Mock engine API.
-- passivetree.lua: a save always goes to the active preset and may not drop its nodes (no free respec through another
-- preset slot); saves and resets are rate limited.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local events = {}
local function object(name)
	local o = {}
	return setmetatable(o, {__index = function(t, k)
		if k == "register" then return function() if name then events[name] = o end return true end end
		return function() return true end
	end})
end
CreatureEvent = function(name) return object(name) end
GlobalEvent = function(name) return object(name) end
TalkAction = function(name) return object(name) end
function addEvent() return 1 end

local rows = {}
local inserts = {}
db = {escapeString = function(s) return "'" .. tostring(s) .. "'" end, asyncQuery = function() end,
	query = function(q)
		local p, nodes = q:match("INSERT INTO `[%w_]+` %(`player_id`, `preset`, `name`, `nodes`%) VALUES %(%d+, (%d+), '[^']*', '([^']*)'%)")
		if p then
			inserts[#inserts + 1] = {preset = tonumber(p), nodes = nodes}
			local found
			for _, r in ipairs(rows) do if r.preset == tonumber(p) then r.nodes = nodes; found = true end end
			if not found then rows[#rows + 1] = {preset = tonumber(p), name = "Preset " .. p, nodes = nodes} end
			table.sort(rows, function(a, b) return a.preset < b.preset end)
		end
		return true
	end}
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.decode = function(b) return b end
Chaos.send = function() return true end
Chaos.select = function(q)
	if q:find("SELECT `preset`, `name`, `nodes`", 1, true) then
		local out = {}
		for _, r in ipairs(rows) do out[#out + 1] = {preset = r.preset, name = r.name, nodes = r.nodes} end
		return out
	end
	return {}
end
ChaosClassTree = {allowed = function() return true end, write = function() end}
local clock = 1000000
os.mtime = function() return clock end
dofile("data/scripts/chaos/ratelimit.lua")
dofile("data/scripts/chaos/passivetree.lua")
local ext = events.ChaosPassiveTreeExtended
assert(ext, "extended event registered")

local p = {msgs = {}}
function p:getGuid() return 1 end
function p:getId() return 1 end
function p:getLevel() return 500 end
function p:getStorageValue() return -1 end
function p:getVocation() return {getId = function() return 4 end} end
function p:sendExtendedOpcode() return true end
function p:registerEvent() end
local OP = ChaosOpcodes.passivetree
local function save(preset, nodes)
	clock = clock + 2000
	inserts = {}
	ext.onExtendedOpcode(p, OP, {action = "sendNodes", data = {preset = preset, nodes = nodes}})
	return #inserts > 0 and inserts[1] or nil
end

-- a legacy character whose only saved set is preset 2 (the active one): node 2
rows = {{preset = 2, name = "Preset 2", nodes = "2"}}
eq(save(1, {3}), nil, "a fresh set in another slot is refused (it would drop node 2: a free respec)")
local s = save(1, {2, 3})
eq(s and s.preset, 2, "the save goes to the active preset")
eq(s and s.nodes, "2,3", "adding nodes works")
eq(save(1, {3}), nil, "removing a saved node by saving is refused")
-- rate limit: a second save inside a second is dropped
clock = clock + 2000
inserts = {}
ext.onExtendedOpcode(p, OP, {action = "sendNodes", data = {preset = 1, nodes = {2, 3, 4}}})
ext.onExtendedOpcode(p, OP, {action = "sendNodes", data = {preset = 1, nodes = {2, 3, 4, 5}}})
eq(#inserts, 1, "the second save inside a second is dropped")

print(string.format("passivetree_preset_test: %d checks OK", checks))
