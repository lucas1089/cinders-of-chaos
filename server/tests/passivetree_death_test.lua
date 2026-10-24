-- Run from the server/ folder: luajit tests/passivetree_death_test.lua (and lua5.3; CI runs both). Mock engine API.
-- O190 (beta 2026-10-24: "the skill tree keeps resetting when the player dies", a Ninja): a death takes levels, the
-- character logs in again, and the login emptied every preset that held more nodes than the points of the lower level.
-- Death -> level loss -> relogin must keep the tree for every class and ascension, around every point threshold and
-- past level 1100; a transient state (vocation or storage not readable yet) must not remove anything either.
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

local rows, writes = {}, 0
db = {escapeString = function(s) return "'" .. tostring(s) .. "'" end, asyncQuery = function() end,
	query = function(q)
		writes = writes + 1
		local p, nodes = q:match("INSERT INTO `[%w_]+` %(`player_id`, `preset`, `name`, `nodes`%) VALUES %(%d+, (%d+), '[^']*', '([^']*)'%)")
		if p then
			for _, r in ipairs(rows) do if r.preset == tonumber(p) then r.nodes = nodes end end
		elseif q:find("UPDATE", 1, true) then
			error("login must not write an UPDATE: " .. q)
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
dofile("data/scripts/chaos/classes.lua")
dofile("data/scripts/chaos/ratelimit.lua")
dofile("data/scripts/chaos/passivetree_core.lua")
dofile("data/scripts/chaos/passivetree_config.lua")
dofile("data/scripts/chaos/class_tree.lua")
dofile("data/scripts/chaos/passivetree.lua")
local login = events.ChaosPassiveTreeLogin
assert(login, "login event registered")
local Core = ChaosPassiveTreeCore
local tree = Chaos.load("passivetree_data.lua")
local cfg = Chaos.passive

local function mkPlayer(vocId, level)
	local st = {[Chaos.storage.passiveRework] = 6} -- the rework refunds of old versions are done (not what is tested)
	local p = {msgs = {}}
	function p:getGuid() return 1 end
	function p:getId() return 1 end
	function p:getLevel() return level end
	function p:getStorageValue(k) local v = st[k]; if v == nil then return -1 end return v end
	function p:setStorageValue(k, v) st[k] = v end
	function p:getVocation() if vocId == nil then return nil end return {getId = function() return vocId end} end
	function p:sendExtendedOpcode() return true end
	function p:registerEvent() end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	return p
end
local function points(level) return math.floor(math.max(0, level - cfg.startLevel) / cfg.levelsPerPoint) end

-- a connected allocation of `count` nodes this class may hold (breadth first from the root)
local function allocate(classKey, count)
	local out, seen, queue, head = {}, {[tree.root] = true}, {tree.root}, 1
	while head <= #queue and #out < count do
		local cur = queue[head]; head = head + 1
		for _, nb in ipairs(tree.nodes[cur].n or {}) do
			if not seen[nb] and ChaosClassTree.allowed(tree.nodes[nb], classKey) then
				seen[nb] = true
				queue[#queue + 1] = nb
				if #out < count then out[#out + 1] = nb end
			end
		end
	end
	return out
end

local classes = {}
for key, id in pairs(Chaos.classes.ids) do classes[#classes + 1] = {key = key, id = id} end
table.sort(classes, function(a, b) return a.id < b.id end)
assert(#classes >= 20, "every class and ascension is covered (" .. #classes .. ")")

local bases = {100, 500, 1000, 1099, 1100, 1101, 1105, 1106, 1500, 2192}
local losses = {1, 2, 3, 4, 5, 6, 20, 150}
local count = 0
for _, c in ipairs(classes) do
	for _, L in ipairs(bases) do
		for d = -1, 1 do -- the neighbours of every threshold
			local level = L + d
			local alloc = allocate(c.key, points(level))
			if #alloc < 3 then error("no allocation for " .. c.key) end
			for _, loss in ipairs(losses) do
				local after = math.max(1, level - loss)
				local saved = Core.formatAlloc(alloc, {})
				rows = {{preset = 1, name = "Preset 1", nodes = saved}}
				writes = 0
				local p = mkPlayer(c.id, after)
				login.onLogin(p)
				eq(rows[1].nodes, saved, c.key .. " keeps its tree at " .. level .. " -> " .. after)
				eq(writes, 0, c.key .. " login writes nothing for a plain level loss")
				eq(#p.msgs > 0, Core.debt(#alloc, points(after)) > 0,
					c.key .. " is told only when over budget (" .. level .. " -> " .. after .. ")")
				count = count + 1
			end
		end
	end
end
assert(count > 1000, "matrix size " .. count)

-- the Ninja: a tree built as a Thief is still whole after the ascension to Ninja and a death
do
	local alloc = allocate("thief", points(1000))
	local saved = Core.formatAlloc(alloc, {})
	rows = {{preset = 1, name = "Preset 1", nodes = saved}}
	login.onLogin(mkPlayer(Chaos.classes.ids.ninja, 1000 - 7))
	eq(rows[1].nodes, saved, "Ninja keeps the Thief's tree after a death")
end

-- a transient state removes nothing: vocation not readable yet, a huge exchange count
do
	local alloc = allocate("ninja", points(900))
	local saved = Core.formatAlloc(alloc, {})
	rows = {{preset = 1, name = "Preset 1", nodes = saved}}
	writes = 0
	login.onLogin(mkPlayer(nil, 900))
	eq(rows[1].nodes, saved, "no vocation yet: nothing removed")
	eq(writes, 0, "no vocation yet: nothing written")
	local p = mkPlayer(Chaos.classes.ids.ninja, 900)
	p:setStorageValue(Chaos.storage.paragonConverted, 100000)
	login.onLogin(p)
	eq(rows[1].nodes, saved, "a huge exchange count removes nothing")
end

-- no spending in debt; the same tree validates again once the level is back
do
	local level = 1000
	local alloc = allocate("ninja", points(level))
	local saved = Core.formatAlloc(alloc, {})
	rows = {{preset = 1, name = "Preset 1", nodes = saved}}
	local p = mkPlayer(Chaos.classes.ids.ninja, level - 12)
	login.onLogin(p)
	eq(rows[1].nodes, saved, "kept")
	local ids = ChaosPassiveTree.internal.validateNodes(p, alloc)
	eq(ids, nil, "a save while over budget is refused")
	ids = ChaosPassiveTree.internal.validateNodes(mkPlayer(Chaos.classes.ids.ninja, level), alloc)
	assert(ids and #ids == #alloc, "the same tree validates again at the old level")
end

eq(Core.debt(10, 4), 6, "debt")
eq(Core.debt(3, 4), 0, "no debt")
print(string.format("passivetree_death_test: %d checks OK", checks))
