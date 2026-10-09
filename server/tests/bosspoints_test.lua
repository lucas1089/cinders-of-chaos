-- Run from the server/ folder: luajit tests/bosspoints_test.lua (or lua5.3; CI runs both)
-- Boss passive points (bosspoints_core.lua, bosspoints_config.lua) and bosspoints.lua against a mocked engine: the
-- boss list, damage-map and party credit, one point per boss and character, the old kills checked once at login,
-- and passivetree.lua counting the points in the tree budget (so a reset keeps them).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/bosspoints_config.lua")
dofile("data/scripts/chaos/bosspoints_core.lua")
local K = ChaosBossPointsCore

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

-- ---------------------------------------------------------------- the list
local index = K.build(cfg)
check(#index.problems == 0, "config has no problems: " .. table.concat(index.problems, "; "))
check(index.total == 10, "ten bosses (about 10 points)")
local worldBosses = 0
for _, b in ipairs((Chaos.worldBoss or {}).bosses or {}) do
	check(K.isBoss(index, b.name) ~= nil, "world boss listed: " .. b.name)
	worldBosses = worldBosses + 1
end
check(worldBosses == 5, "the five world bosses of chaos_constants.lua")
check(K.isBoss(index, "ASCENSION WARDEN") and K.isBoss(index, "ascension warden").id == 6, "type name, any case")
check(K.isBoss(index, "Warden of Iron") == nil, "the dressed name is not the type name")
check(K.isBoss(index, "Demon") == nil and K.isBoss(index, nil) == nil, "other monsters")
local seenIds, lastId = {}, 0
for _, b in ipairs(index.list) do
	check(not seenIds[b.id] and b.id > lastId and b.id <= cfg.maxId, "ids unique and sorted: " .. b.id)
	seenIds[b.id], lastId = true, b.id
	check(b.retro.bestiary or b.retro.stat or b.retro.storage, "every boss has an old-kill source: " .. b.name)
end
local aq = dofile("data/scripts/chaos/ascension_quest_config.lua")
check(index.byId[6].retro.storage.key == aq.storage.stage, "Trial retro storage = the ascension quest stage")
check(aq.trial.guardianMonster == index.byId[6].name, "Trial guardian type")
check(cfg.storageBase + cfg.maxId < 7101500 and cfg.storageBase > 7101309, "storage range clear of guilds/ascension")
local bad = K.build({maxId = 5, bosses = {{id = 1, name = "A"}, {id = 1, name = "B"}, {id = 9, name = "C"}, {id = 2, name = "a"}}})
check(#bad.problems == 3 and bad.total == 1, "bad config entries are reported and skipped")

-- counting / state
local flags = {[1] = true, [6] = true, [15] = true}
local function has(id) return flags[id] == true end
check(K.count(index, has) == 2, "only listed bosses count")
local st = K.state(index, has)
check(st.got == 2 and st.total == 10 and st.label == "Boss points 2/10" and #st.bosses == 10, "state")
check(st.bosses[1].done and not st.bosses[2].done and st.bosses[6].done, "state flags")

-- killers: damage map + last hit / most damage, each once, stable
local players = {}
local function P(id, x, y, z, party)
	local p = {id = id, pos = {x = x, y = y, z = z or 7}, party = party}
	players[id] = p
	return p
end
local a, b, c, far, mate, other = P(1, 100, 100), P(2, 105, 100), P(3, 100, 120), P(4, 300, 300), P(5, 110, 110), P(6, 100, 100, 6)
local summonOf = {[90] = a}
local function resolve(id) return players[id] or summonOf[id] end
local killers = K.killers({3, 90, 2, 77}, resolve, {b, nil, a}, function(p) return p.id end)
check(#killers == 3 and killers[1] == b and killers[2] == c and killers[3] == a, "damage map sorted, summons -> master, once")

-- party credit (the bounty board's): members within range on the same floor
local party = {a, mate, far, other}
for _, p in ipairs(party) do p.party = party end
local credited = K.credit({a}, function(p) return p.party end, function(p) return p.pos end, cfg.partyRange,
	function(p) return p.id end)
local got = {}
for _, p in ipairs(credited) do got[p.id] = true end
check(got[1] and got[5] and not got[4] and not got[6], "party in range only (not far, not another floor)")

-- old kills
local ids = K.retroIds(index, {bestiary = {["the rotmother"] = 2, ["apocalypse"] = 0, ["gaz'haragoth"] = 1},
	stats = {wb_kaelgor = 1, wb_skaldra = 0}, storage = function(key) return key == 7101000 and 4 or -1 end})
local set = {}
for _, id in ipairs(ids) do set[id] = true end
check(set[1] and set[3] and set[6] and set[10] and not set[2] and not set[8], "retro sources: stats, bestiary, storage")
check(#K.retroIds(index, {storage = function() return 2 end}) == 0, "Trial not won: no retro point")

-- ---------------------------------------------------------------- bosspoints.lua + passivetree.lua (mocked engine)
local registered, callbacks, sentOpcodes, texts = {}, {}, {}, {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type() end
	function o:register() registered[name] = o end
	return o
end
EventCallback = setmetatable({}, {__newindex = function(t, k, v) callbacks[k] = v end, __index = {register = function() end}})
json = {encode = function(t) return t end}
db = {escapeString = function(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end, query = function() end}
local dbRows = {bestiary = {}, stats = {}}
local presets = {}
function Chaos.select(q, cols)
	if q:find("information_schema") then
		return {{n = 1}}
	elseif q:find("chaos_bestiary") then
		local guid = tonumber(q:match("`player_id` = (%d+)"))
		local out = {}
		for monster, kills in pairs(dbRows.bestiary[guid] or {}) do
			if q:find("'" .. monster:gsub("'", "''"):gsub("%p", "%%%0") .. "'") then out[#out + 1] = {monster = monster, kills = kills} end
		end
		return out
	elseif q:find("chaos_achievement_stats") then
		local guid = tonumber(q:match("`player_id` = (%d+)"))
		local out = {}
		for stat, v in pairs(dbRows.stats[guid] or {}) do out[#out + 1] = {stat = stat, value = v} end
		return out
	elseif q:find("chaos_passive_tree") then
		local guid = tonumber(q:match("`player_id` = (%d+)"))
		return presets[guid] and {{preset = 1, name = "Preset 1", nodes = presets[guid]}} or {}
	end
	return {}
end
function Chaos.send(player, opcode, action, data)
	sentOpcodes[#sentOpcodes + 1] = {player = player, action = action, data = data}
	return true
end

local creatures = {}
local function newPlayer(id, guid, level, pos)
	local p = {id = id, guid = guid, level = level, storage = {}, pos = pos or {x = 100, y = 100, z = 7}}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return "P" .. self.id end
	function p:getLevel() return self.level end
	function p:isPlayer() return true end
	function p:getMaster() return nil end
	function p:getParty() return self.party end
	function p:getPosition() local s = self; return {x = s.pos.x, y = s.pos.y, z = s.pos.z, sendMagicEffect = function() end} end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:sendTextMessage(_, text) texts[#texts + 1] = {player = self, text = text} end
	function p:sendExtendedOpcode(op, msg) self.toasts = (self.toasts or 0) + 1 end
	function p:getVocation() return {getId = function() return 4 end} end
	creatures[id] = p
	return p
end
function Creature(id) return creatures[id] end
local function newMonster(id, typeName, shownName, damage)
	local m = {id = id, typeName = typeName, shownName = shownName or typeName, damage = damage or {}, events = {}}
	function m:getName() return self.shownName end
	function m:getType() local s = self; return {name = function() return s.typeName end} end
	function m:getMaster() return nil end
	function m:isPlayer() return false end
	function m:registerEvent(name) self.events[name] = true end
	function m:getDamageMap() return self.damage end
	creatures[id] = m
	return m
end
local function partyOf(members)
	local party = {members = members}
	function party:getMembers() local out = {}; for i = 2, #self.members do out[#out + 1] = self.members[i] end; return out end
	function party:getLeader() return self.members[1] end
	for _, m in ipairs(members) do m.party = party end
	return party
end

dofile("data/scripts/chaos/passivetree.lua")
dofile("data/scripts/chaos/bosspoints.lua")
local B = ChaosBossPoints
local T = ChaosPassiveTree.internal
check(registered.ChaosBossPointsDeath and registered.ChaosBossPointsLogin and callbacks.onSpawn, "events registered")

-- spawn: only the listed bosses (by type) get the death event
local boss = newMonster(5000, "Apocalypse")
local warden = newMonster(5001, "Ascension Warden", "Warden of Iron")
local demon = newMonster(5002, "Demon")
callbacks.onSpawn(boss); callbacks.onSpawn(warden); callbacks.onSpawn(demon)
check(boss.events.ChaosBossPointsDeath and warden.events.ChaosBossPointsDeath and not demon.events.ChaosBossPointsDeath,
	"death event on bosses only (the renamed Warden too)")

-- a party kill: two damage dealers (one through a summon), a healer in the party nearby, a member far away,
-- a stranger who never hit
local tank = newPlayer(11, 101, 300)
local mage = newPlayer(12, 102, 300, {x = 104, y = 100, z = 7})
local healer = newPlayer(13, 103, 300, {x = 110, y = 108, z = 7})
local afar = newPlayer(14, 104, 300, {x = 500, y = 500, z = 7})
local stranger = newPlayer(15, 105, 300)
partyOf({tank, mage, healer, afar})
local summon = {id = 900}
function summon:isPlayer() return false end
function summon:getMaster() return mage end
creatures[900] = summon
boss.damage = {[11] = {total = 5000}, [900] = {total = 3000}}
local base = T.totalPoints(tank)
check(base == math.floor((300 - 8) / 4), "level points before")
registered.ChaosBossPointsDeath.onDeath(boss, nil, tank, summon)
check(B.has(tank, 8) and B.has(mage, 8) and B.has(healer, 8), "damage dealers and the party in range get the point")
check(not B.has(afar, 8) and not B.has(stranger, 8), "far member and stranger do not")
check(T.totalPoints(tank) == base + 1, "+1 passive point in the tree budget")
local toastsBefore = tank.toasts or 0
check(toastsBefore >= 1, "a toast was sent")
local lastInfo
for _, s in ipairs(sentOpcodes) do if s.player == tank and s.action == "bossPoints" then lastInfo = s.data end end
check(lastInfo and lastInfo.got == 1 and lastInfo.total == 10 and lastInfo.label == "Boss points 1/10", "window info sent")
local sentPoints = false
for _, s in ipairs(sentOpcodes) do if s.player == tank and s.action == "sendPoints" then sentPoints = s.data end end
check(sentPoints == base + 1, "free points refreshed after the kill")

-- second kill of the same boss: nothing more
registered.ChaosBossPointsDeath.onDeath(boss, nil, tank, tank)
check(T.totalPoints(tank) == base + 1 and (tank.toasts or 0) == toastsBefore, "only the first kill counts")

-- the Warden of the Trial (solo)
warden.damage = {[11] = {total = 6000}}
registered.ChaosBossPointsDeath.onDeath(warden, nil, tank, tank)
check(B.count(tank) == 2 and T.totalPoints(tank) == base + 2, "Trial Warden point")

-- a reset keeps the points (they are not nodes): a full tree of base + 2 nodes stays valid
presets[101] = nil
check(T.totalPoints(tank) == base + 2, "points independent of the saved tree")
check(Chaos.storage.passiveExtraPoints and true, "extra points storage still used")
tank.storage[Chaos.storage.passiveExtraPoints] = 1
check(T.totalPoints(tank) == base + 3, "tutorial extra point + boss points add up")

-- old kills, once per character at login
local veteran = newPlayer(21, 201, 600)
dbRows.bestiary[201] = {["the rotmother"] = 3, ["gaz'haragoth"] = 1, ["apocalypse"] = 0, ["demon"] = 400}
dbRows.stats[201] = {wb_kaelgor = 2}
veteran.storage[7101000] = 4 -- ascended through the quest
registered.ChaosBossPointsLogin.onLogin(veteran)
check(B.count(veteran) == 4, "retro: Kaelgor (stat), Rotmother + Gaz'haragoth (bestiary), Warden (Trial stage)")
check(veteran.storage[cfg.storageBase] == cfg.retroVersion, "retro marked done")
local retroText = texts[#texts].text
check(retroText:find("+4", 1, true) and retroText:find("Boss points 4/10", 1, true), "retro message")
dbRows.bestiary[201]["apocalypse"] = 5
registered.ChaosBossPointsLogin.onLogin(veteran)
check(B.count(veteran) == 4, "retro runs once (a later kill counts through the death event)")
local newbie = newPlayer(22, 202, 20)
local before = #texts
registered.ChaosBossPointsLogin.onLogin(newbie)
check(B.count(newbie) == 0 and #texts == before and newbie.storage[cfg.storageBase] == cfg.retroVersion, "no old kills: silent")

-- disabled: no points, no events
Chaos.bossPoints.enabled = false
check(B.count(tank) == 0, "disabled: the points leave the budget")
Chaos.bossPoints.enabled = true

print(string.format("bosspoints_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
