-- Run from the server/ folder: luajit tests/bossspawns_test.lua (or lua5.3; CI runs both)
-- Boss spawns tracker: the list (bossspawns_config.lua + the world boss, invasion, tower, trial and dungeon sources),
-- raid file parsing, place matching, alive / kill state, every respawn rule's status, the window payload, and
-- bossspawns.lua against a mocked engine (onSpawn -> scan -> death -> SQL row -> payload).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/bossspawns_config.lua")
dofile("data/scripts/chaos/bossspawns_core.lua")
local K = ChaosBossSpawnsCore
local invCfg = dofile("data/scripts/chaos/invasion_config.lua")
local trialsCfg = dofile("data/scripts/chaos/trials_config.lua")

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- the Infinity Tower boss list, read from infinitytower_run.lua's text (that file needs the engine to load)
local function towerBosses()
	local f = assert(io.open("data/scripts/chaos/infinitytower_run.lua", "r"))
	local text = f:read("*a")
	f:close()
	local body = text:match("bosses%s*=%s*(%b{})")
	local list = {}
	for name in body:gmatch('"([^"]+)"') do
		list[#list + 1] = name
	end
	return list, tonumber(text:match("bossEvery%s*=%s*(%d+)"))
end
local tNames, tEvery = towerBosses()
check(#tNames >= 10, "tower bosses read from infinitytower_run.lua")

local sources = {worldBoss = Chaos.worldBoss, invasion = invCfg, towerBosses = tNames, towerEvery = tEvery,
	trials = trialsCfg, ascension = true, ascensionLevel = Chaos.classes.ascension.minLevel,
	dungeonsExtra = Chaos.dungeons.extra, dungeonsBase = nil, dungeonCooldown = 50203}

-- ---------------------------------------------------------------- the list
local idx = K.build(cfg, sources)
eq(#idx.problems, 0, "no config problems (" .. table.concat(idx.problems, "; ") .. ")")
local perCat = {}
for _, e in ipairs(idx.list) do
	perCat[e.category] = (perCat[e.category] or 0) + 1
	check(type(e.name) == "string" and e.name ~= "", e.key .. " has a name")
	check(e.key:match("^[%w_]+$") ~= nil and #e.key <= 48, e.key .. " key fits the SQL column")
	if e.pos then
		check(tonumber(e.pos.x) and tonumber(e.pos.y) and tonumber(e.pos.z), e.key .. " position")
	end
end
eq(perCat.world, 5, "five world bosses")
eq(perCat.island, 10, "ten island bosses")
check((perCat.raid or 0) >= 25, "raid bosses listed")
check((perCat.lair or 0) >= 10, "lair bosses listed")
eq(perCat.invasion, 9, "one entry per invasion faction boss")
eq(perCat.omen, 4, "rift guardian and three omens")
eq(perCat.dungeon, 4, "four dungeons")
eq(perCat.tower, #tNames, "one tower entry per tower boss")
eq(perCat.trial, 8, "seven trial bosses and the Ascension Warden")
eq(perCat.rare, 1, "treasure goblin")
for _, c in ipairs(cfg.categories) do
	check(perCat[c.key] ~= nil, "category " .. c.key .. " has entries")
end
-- omen bosses: the rift config's kinds
local rift = dofile("data/scripts/chaos/rift_config.lua")
for _, kind in ipairs(rift.omen.kinds) do
	check(idx.byType[kind.boss:lower()] ~= nil, "omen boss listed: " .. kind.boss)
end
-- world bosses in rotation order with the arena centre
local w1 = idx.byKey.world_1
eq(w1.name, Chaos.worldBoss.bosses[1].name, "rotation order")
eq(w1.pos.x, 5016, "arena centre x")
eq(w1.level, Chaos.worldBoss.minLevel, "world boss level")
-- invasion: renamed bosses by their shown name, sorted by level
local grashnak = idx.byKey.invasion_warchief_grashnak
check(grashnak ~= nil and grashnak.monster == "Orc Warlord" and grashnak.shown == "Warchief Grashnak", "renamed invasion boss")
-- tower floors
eq(idx.byKey.tower_1.name, "The Old Widow", "tower names in title case")
check(idx.byKey.tower_1.rule.how:find("10, " .. (10 + #tNames * 10)) ~= nil, "tower floors repeat")
eq(idx.byKey.tower_8.name, "Zulazza the Corruptor", "small words stay small")
-- trials
local tw = idx.byKey.trial_warrior
check(tw and tw.name == "Gauntlet Champion" and tw.look.type == 131 and tw.level == 100, "trial boss with its look and level")
eq(idx.byKey.ascension_warden.rule.cooldown, 7101002, "ascension cooldown storage")
eq(idx.byKey.dungeon_1.name, "Prince Skeletal", "dungeon default name")
eq(idx.byKey.dungeon_1.rule.cooldown, 50203, "dungeon cooldown storage")

-- duplicates and bad entries are reported, not added
local bad = K.build({categories = {{key = "a", name = "A"}}, bosses = {
	{key = "x", category = "a", name = "X", rule = {type = "ondemand"}},
	{key = "x", category = "a", name = "X2", rule = {type = "ondemand"}},
	{key = "y", category = "nope", name = "Y", rule = {type = "ondemand"}},
	{key = "z", category = "a", name = "Z"}}})
eq(#bad.list, 1, "only the valid entry")
eq(#bad.problems, 3, "three problems")

-- dungeon entries with the base DUNGEON_SYSTEM table
local dl = K.dungeonEntries(Chaos.dungeons.extra, {[1] = {Name = "Bones Dungeon", Level = 150, NeedParty = true, AmountParty = 2,
	DungeonPos = {x = 31662, y = 32143, z = 8}, FromPos = {x = 31630, y = 32134, z = 8}, ToPos = {x = 31851, y = 32300, z = 8}}},
	{defaults = {}, how = "queue"})
eq(dl[1].loc, "Bones Dungeon", "dungeon place from the base table")
eq(dl[1].party, 2, "party size")
check(K.inPlace(dl[1], {x = 31700, y = 32200, z = 8}) and not K.inPlace(dl[1], {x = 31700, y = 32200, z = 7}), "dungeon box")
check(not K.inPlace(dl[2], {x = 1, y = 1, z = 7}), "a dungeon without its box is never matched")

-- ---------------------------------------------------------------- raids
local raidsXml = [[
<?xml version="1.0" encoding="UTF-8"?>
<raids>
	<!-- <raid name="Old" file="old.xml" interval2="10" margin="1" /> -->
	<raid name="Ferumbras" file="liberty_bay/ferumbras.xml" interval2="720" margin="60" />
	<raid name="Ghazbaran" file="rimeholt/ghazbaran.xml" interval2="1440" margin="100" enabled="0" />
	<raid name="Rats" file="cinderhold/rats.xml" interval2="500" margin="70" />
</raids>]]
local list = K.parseRaidList(raidsXml)
eq(#list, 3, "commented raid skipped")
eq(list[1].interval, 720, "interval2")
eq(list[2].enabled, false, "disabled raid")
local spawns = K.parseRaidSpawns([[<raid><announce delay="0" type="event" message="x" />
	<singlespawn delay="100000" name="Ferumbras" x="32125" y="32688" z="4"/></raid>]])
eq(#spawns, 1, "one single spawn")
list[1].spawns = spawns
list[2].spawns = {{name = "Ghazbaran", x = 1, y = 1, z = 15}}
list[3].spawns = {}
local ridx = K.build(cfg, {})
eq(K.applyRaids(ridx, list), 1, "one raid boss found")
local fer = ridx.byKey.raid_ferumbras
eq(fer.rule.interval, 720, "interval from the file")
eq(fer.pos.x, 32125, "position from the file")
eq(ridx.byKey.raid_ghazbaran.missing, true, "disabled raid -> left out")
eq(ridx.byKey.raid_morgaroth.missing, true, "raid not on this server -> left out")

-- ---------------------------------------------------------------- matching
local function keysOf(es)
	local out = {}
	for _, e in ipairs(es) do
		out[#out + 1] = e.key
	end
	table.sort(out)
	return table.concat(out, ",")
end
eq(keysOf(K.match(idx, {type = "Orshabaal", pos = {x = 33120, y = 31700, z = 7}}, 40)), "raid_orshabaal", "raid by place")
eq(keysOf(K.match(idx, {type = "orshabaal", pos = {x = 31663, y = 32760, z = 12}}, 40)), "lair_orshabaal", "lair by place, any case")
eq(keysOf(K.match(idx, {type = "Orshabaal", pos = {x = 2100, y = 2100, z = 7}}, 40)), "", "tower copy matches nothing")
eq(keysOf(K.match(idx, {type = "Orshabaal", shown = "Orshabaal", pos = {x = 32365, y = 32245, z = 7}, invasion = true}, 40)),
	"invasion_orshabaal", "the running invasion's boss")
eq(keysOf(K.match(idx, {type = "Orc Warlord", shown = "Orc Warlord", pos = {x = 32365, y = 32245, z = 7}}, 40)), "",
	"a plain orc warlord is no invasion boss")
eq(keysOf(K.match(idx, {type = "Orc Warlord", shown = "Warchief Grashnak", pos = {x = 0, y = 0, z = 7}, invasion = true}, 40)),
	"invasion_warchief_grashnak", "renamed invasion boss by its shown name")
eq(keysOf(K.match(idx, {type = "Kaelgor the Infernal Warlord", pos = {x = 5016, y = 5010, z = 7}}, 40)), "world_1", "world boss in the arena")
eq(keysOf(K.match(idx, {type = "Treasure Goblin", pos = {x = 1, y = 2, z = 3}}, 40)), "treasure_goblin", "anywhere")
eq(keysOf(K.match(idx, {type = "Demodras", pos = {x = 31705, y = 32838, z = 14}}, 40)), "lair_demodras", "one floor of slack")
eq(keysOf(K.match(idx, {type = "Demodras", pos = {x = 31705, y = 32838, z = 12}}, 40)), "", "not three floors away")
eq(K.nearestTown({x = 10, y = 10, z = 7}, {{name = "A", pos = {x = 0, y = 0, z = 7}}, {name = "B", pos = {x = 12, y = 30, z = 7}}}), "A",
	"nearest town")

-- ---------------------------------------------------------------- times
local wed = os.time({year = 2026, month = 10, day = 7, hour = 10, min = 0, sec = 0}) -- a Wednesday
eq(os.date("*t", wed).wday, 4, "test day is a Wednesday")
local t = K.nextWeekly({{day = 4, hour = 20, min = 0}}, wed)
eq(os.date("%a %H:%M", t), os.date("%a %H:%M", wed + 10 * 3600), "same day later")
t = K.nextWeekly({{day = 4, hour = 8, min = 0}}, wed)
eq(t - wed, 7 * 86400 - 2 * 3600, "same weekday, already passed -> next week")
t = K.nextWeekly({{day = 1, hour = 0, min = 0}, {day = 5, hour = 1, min = 30}}, wed)
eq(os.date("%a %H:%M", t), "Thu 01:30", "earliest of several times")
eq(os.date("%H", K.nextSlot(wed, 6, 3)), "15", "world boss slot 03/09/15/21")
eq(os.date("%H", K.nextSlot(wed + 5 * 3600, 6, 3)), "21", "next slot")
eq(K.minutesText(1440), "1d", "a day")
eq(K.minutesText(90), "1h 30m", "hours and minutes")
eq(K.minutesText(45), "45m", "minutes")
eq(K.weeklyText({{day = 7, hour = 12, min = 0}}), "Sat 12:00", "weekly text")

-- ---------------------------------------------------------------- statuses
local st = K.newState()
local ctx = {now = wed, state = st, cooldowns = {}}
local function status(key)
	return K.status(idx.byKey[key], ctx)
end
-- weekly: scheduled until it spawns, then alive until slain
local s = status("thalador")
eq(s.st, "scheduled", "island scheduled")
eq(s.at, wed + 10 * 3600, "island at Wed 20:00")
K.onSpawn(st, "thalador", 101, wed)
eq(status("thalador").st, "alive", "island alive")
K.onDeath(st, "thalador", 101, wed + 60, "Hero")
eq(status("thalador").st, "scheduled", "island slain -> next week")
eq(st.kills.thalador.killer, "Hero", "killer kept")
eq(st.kills.thalador.count, 1, "kill counted")
-- timer: unknown, alive, respawn countdown, due
eq(status("lair_bibby").st, "unknown", "never seen")
K.onSpawn(st, "lair_bibby", 200, wed)
eq(status("lair_bibby").st, "alive", "lair alive")
K.onDeath(st, "lair_bibby", 200, wed + 100, "Hero")
s = status("lair_bibby")
eq(s.st, "respawn", "lair respawn")
eq(s.at, wed + 100 + 3600, "back an hour after the kill")
ctx.now = wed + 100 + 3601
eq(status("lair_bibby").st, "due", "timer over, nobody saw it come")
K.onSpawn(st, "lair_bibby", 201, ctx.now)
eq(status("lair_bibby").st, "alive", "came back")
ctx.now = wed
-- counted timer boss: alive while all copies stand, a copy down -> its countdown
K.onSpawn(st, "lair_demodras", 301, wed)
K.onSpawn(st, "lair_demodras", 302, wed)
K.onSpawn(st, "lair_demodras", 303, wed)
eq(status("lair_demodras").st, "alive", "three of three")
K.onDeath(st, "lair_demodras", 302, wed, "Hero")
eq(status("lair_demodras").st, "respawn", "one down -> countdown")
eq(K.aliveCount(st, "lair_demodras"), 2, "two left")
-- raid
s = status("raid_ferumbras")
eq(s.st, "random", "raid random")
check(s.text:find("1d") ~= nil and s.text:find("2h") ~= nil, "raid text: " .. s.text)
eq(s.short, "About every 1d", "raid short text")
-- chance
eq(status("treasure_goblin").st, "random", "goblin rare")
-- world boss rotation
ctx.worldBoss = {enabled = true, mode = "rotation", interval = 6, count = 5, nextIndex = 2, nextAt = wed + 5 * 3600}
s = status("world_2")
eq(s.st, "scheduled", "next world boss")
eq(s.at, wed + 5 * 3600, "its slot")
eq(status("world_1").at, wed + 5 * 3600 + 4 * 6 * 3600, "the boss before comes last")
eq(status("world_4").at, wed + 5 * 3600 + 2 * 6 * 3600, "two slots later")
ctx.worldBoss.active = {index = 1, phase = "gather", spawnAt = wed + 60}
eq(status("world_1").st, "scheduled", "gathering")
eq(status("world_1").at, wed + 60, "appears at spawnAt")
ctx.worldBoss.active.phase = "fight"
eq(status("world_1").st, "alive", "fight")
ctx.worldBoss = {enabled = true, mode = "random", interval = 6, count = 5, nextAt = wed + 3600}
eq(status("world_3").at, wed + 3600, "random mode: every boss may come next slot")
ctx.worldBoss = {enabled = false, count = 5}
eq(status("world_3").st, "ondemand", "schedule off")
-- invasion
eq(status("invasion_warchief_grashnak").st, "random", "no invasion planned")
ctx.invasions = {{at = wed + 9 * 3600, boss = "Warchief Grashnak", text = "Orc Warband invades Cinderhold"}}
s = status("invasion_warchief_grashnak")
eq(s.st, "scheduled", "invasion planned")
eq(s.text, "Orc Warband invades Cinderhold", "invasion text")
ctx.invasionActive = {boss = "Warchief Grashnak"}
eq(status("invasion_warchief_grashnak").st, "alive", "invasion running")
-- on demand and the player's cooldown
eq(status("dungeon_1").st, "ondemand", "dungeon on demand")
ctx.cooldowns[50203] = wed + 1800
s = status("dungeon_1")
eq(s.st, "cooldown", "dungeon cooldown")
eq(s.at, wed + 1800, "cooldown end")
ctx.cooldowns[50203] = wed - 1
eq(status("dungeon_1").st, "ondemand", "cooldown over")

-- prune: creatures gone without a death
K.onSpawn(st, "raid_ferumbras", 900, wed)
eq(status("raid_ferumbras").st, "alive", "raid alive")
eq(K.prune(st, function(cid) return cid ~= 900 end), 1, "one creature gone")
eq(status("raid_ferumbras").st, "random", "not alive after prune")
eq(st.kills.raid_ferumbras, nil, "leaving is no kill")

-- ---------------------------------------------------------------- payload
ctx.now = wed
local p = K.payload(idx, ctx)
eq(#p.cats, #cfg.categories, "every category with rows")
eq(p.cats[1].k, "world", "categories in config order")
local byKey = {}
for _, r in ipairs(p.rows) do
	byKey[r.k] = r
end
eq(byKey.thalador["in"], 10 * 3600, "seconds to the next weekly time")
eq(byKey.thalador.by, "Hero", "killer in the row")
check(byKey.thalador.at ~= nil, "a far time also as text")
eq(byKey.lair_demodras["in"], 120, "a short wait has no time text")
eq(byKey.lair_demodras.at, nil, "no time text under 6 hours")
eq(byKey.lair_demodras.alive, 2, "alive count in the row")
eq(byKey.world_1.p, nil, "no coordinates for the arena")
eq(byKey.world_1.ln, "Portals at every temple", "the arena's note instead")
eq(byKey.raid_ferumbras.p.z, 4, "raid coordinates")
eq(byKey.trial_warrior.o.type, 131, "outfit in the row")
eq(byKey.dungeon_1.st, "ondemand", "dungeon row")
for _, r in ipairs(p.rows) do
	if r.sh then
		check(#r.sh <= 26, r.k .. " short text fits the status column: " .. r.sh)
	end
	if r.st == "ondemand" or r.st == "random" then
		check(r.sh ~= nil, r.k .. " has a short text")
	end
end
-- the encoded payload needs Chaos.sendChunked (over one extended opcode message)
local function enc(v)
	local tv = type(v)
	if tv == "table" then
		local parts = {}
		for k2, v2 in pairs(v) do
			parts[#parts + 1] = string.format("%q:%s", tostring(k2), enc(v2))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif tv == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end
local size = #enc(p)
check(size > 8192 and size < 64000, "payload size " .. size .. " needs chunks and stays small")
-- missing entries are left out
ridx.byKey.raid_morgaroth.missing = true
local rp = K.payload(ridx, {now = wed, state = K.newState(), cooldowns = {}})
for _, r in ipairs(rp.rows) do
	check(r.k ~= "raid_morgaroth", "missing raid left out")
end
-- persistence rows
local st2 = K.newState()
eq(K.loadKills(st2, {{boss_key = "lair_bibby", last_kill = wed, killer = "", kills = 4}, {boss_key = "gone", last_kill = 5, killer = "x", kills = 1},
	{boss_key = "thalador", last_kill = 0, killer = "", kills = 0}}, idx), 1, "known keys with a kill only")
eq(st2.kills.lair_bibby.killer, nil, "empty killer -> nil")
eq(st2.kills.lair_bibby.count, 4, "kill count")

-- ---------------------------------------------------------------- bossspawns.lua against a mocked engine
local registry, globals, spawnCb = {}, {}, nil
function CreatureEvent(name)
	local o = {}
	function o:type() end
	function o:register() registry[name] = o end
	return o
end
function GlobalEvent(name)
	local o = {}
	function o:register() globals[name] = o end
	return o
end
EventCallback = setmetatable({register = function() end}, {__newindex = function(_, k, v) if k == "onSpawn" then spawnCb = v end end})
local queue = {}
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}} return #queue end
local function runEvents()
	while #queue > 0 do
		local e = table.remove(queue, 1)
		e.fn((table.unpack or unpack)(e.args))
	end
end
local queries, rows = {}, {}
db = {query = function(q) queries[#queries + 1] = q return true end, escapeString = function(s) return "'" .. tostring(s) .. "'" end,
	storeQuery = function() return false end}
db.asyncQuery = db.query
local sent = {}
json = {encode = function(t) sent[#sent + 1] = t return string.rep("x", 9000) end, decode = function(s) return {action = s} end}
local creatures, nextId = {}, 1000
local function mkMonster(typeName, shown, pos)
	local c = {id = 0, typeName = typeName, shown = shown or typeName, pos = pos, events = {}}
	function c:getId() return self.id end
	function c:isMonster() return true end
	function c:isPlayer() return false end
	function c:getMaster() return nil end
	function c:getName() return self.shown end
	function c:getType() local tn = self.typeName return {name = function() return tn end} end
	function c:getPosition() return self.pos end
	function c:registerEvent(e) self.events[e] = true end
	return c
end
local function place(c)
	nextId = nextId + 1
	c.id = nextId
	creatures[c.id] = c
	return c
end
Monster = function(id) return creatures[id] end
MonsterType = function(name)
	if name == "Morgaroth" then return nil end
	return {outfit = function() return {lookType = 35, lookHead = 1} end}
end
Position = function(x, y, z) return {x = x, y = y, z = z} end
Game = {getSpectators = function(pos, _, _, r)
	local out = {}
	for _, c in pairs(creatures) do
		if c.pos.z == pos.z and math.abs(c.pos.x - pos.x) <= r and math.abs(c.pos.y - pos.y) <= r then out[#out + 1] = c end
	end
	return out
end, getTowns = function()
	return {{getName = function() return "Cinderhold" end, getTemplePosition = function() return {x = 32369, y = 32241, z = 7} end}}
end, getStorageValue = function() return -1 end}
DUNGEON_SYSTEM = nil
ChaosTowerRunConfig = {bosses = tNames, bossEvery = tEvery}
local limited = 0
ChaosRateLimit = {allow = function() limited = limited + 1 return limited == 1 or limited > 2 end}
local realTime = os.time
os.time = function(tt) if tt then return realTime(tt) end return wed end
io.open = (function(orig)
	return function(path, mode)
		if path == "data/raids/raids.xml" then
			return {read = function() return raidsXml end, close = function() end}
		elseif path == "data/raids/liberty_bay/ferumbras.xml" then
			return {read = function() return '<singlespawn name="Ferumbras" x="32124" y="32687" z="4"/>' end, close = function() end}
		end
		return orig(path, mode)
	end
end)(io.open)
print_ = print
local logged = {}
print = function(s) logged[#logged + 1] = s end
dofile("data/scripts/chaos/bossspawns.lua")
local S = ChaosBossSpawns
check(spawnCb ~= nil and registry.ChaosBossSpawnsDeath ~= nil and registry.ChaosBossSpawnsExtended ~= nil, "events registered")
-- a raid boss appears: onSpawn (id 0), then the scan finds it
local fer2 = mkMonster("Ferumbras", nil, {x = 32124, y = 32687, z = 4})
check(spawnCb(fer2, fer2.pos, false, true) == true, "spawn allowed")
check(fer2.events.ChaosBossSpawnsDeath, "death event on the boss")
place(fer2)
runEvents()
check(S.tracked[fer2.id] ~= nil, "tracked after the scan")
eq(K.aliveCount(S.state, "raid_ferumbras"), 1, "alive")
eq(S.index.byKey.raid_ferumbras.rule.interval, 720, "raids.xml read at startup")
eq(S.index.byKey.raid_morgaroth.missing, true, "raid not in raids.xml left out")
-- an ordinary monster is ignored
local rat = mkMonster("Rat", nil, {x = 1, y = 1, z = 7})
spawnCb(rat, rat.pos, false, false)
check(not rat.events.ChaosBossSpawnsDeath, "no death event on a rat")
-- the kill
local hero = {isPlayer = function() return true end, getName = function() return "Hero" end}
registry.ChaosBossSpawnsDeath.onDeath(fer2, nil, hero, hero)
creatures[fer2.id] = nil
eq(K.aliveCount(S.state, "raid_ferumbras"), 0, "dead")
eq(S.state.kills.raid_ferumbras.killer, "Hero", "kill stored")
local saved = false
for _, q in ipairs(queries) do
	if q:find("INSERT INTO `chaos_boss_spawns`", 1, true) and q:find("'raid_ferumbras'", 1, true) then saved = true end
end
check(saved, "kill written to chaos_boss_spawns")
-- a lair boss that leaves without dying
local bib = place(mkMonster("Bibby Bloodbath", nil, {x = 32622, y = 31826, z = 7}))
spawnCb(bib, bib.pos, true, false)
runEvents()
eq(K.aliveCount(S.state, "lair_bibby"), 1, "lair boss alive")
creatures[bib.id] = nil
-- the window
local player = {getStorageValue = function(_, k) return k == 7101002 and wed + 600 or -1 end, getId = function() return 1 end,
	sendExtendedOpcode = function(_, op, part) sent.parts = (sent.parts or 0) + 1 sent.op = op return true end}
registry.ChaosBossSpawnsExtended.onExtendedOpcode(player, ChaosOpcodes.bossSpawns, "open")
local msg = sent[#sent]
eq(msg.action, "list", "list sent")
eq(sent.op, ChaosOpcodes.bossSpawns, "on the boss spawns opcode")
eq(sent.parts, 2, "9000 bytes go in two chunks")
local rowsByKey = {}
for _, r in ipairs(msg.data.rows) do rowsByKey[r.k] = r end
eq(rowsByKey.raid_ferumbras.by, "Hero", "kill in the list")
eq(rowsByKey.lair_bibby.st, "unknown", "left without dying: not alive, no kill")
eq(rowsByKey.lair_bibby.loc, "Orc fortress", "configured place")
eq(rowsByKey.lair_apocalypse.loc, "near Cinderhold", "nearest town for a place without a name")
eq(rowsByKey.ascension_warden.st, "cooldown", "the player's own cooldown")
eq(rowsByKey.raid_morgaroth, nil, "missing raid not sent")
eq(rowsByKey.raid_ferumbras.o.type, 35, "outfit from the monster type")
eq(msg.data.refresh, cfg.refreshSeconds, "refresh period")
local before = #sent
registry.ChaosBossSpawnsExtended.onExtendedOpcode(player, ChaosOpcodes.bossSpawns, "refresh")
eq(#sent, before, "rate limited")
registry.ChaosBossSpawnsExtended.onExtendedOpcode(player, ChaosOpcodes.bossSpawns, "bogus")
eq(#sent, before, "unknown action ignored")
registry.ChaosBossSpawnsExtended.onExtendedOpcode(player, ChaosOpcodes.bossSpawns, "refresh")
eq(#sent, before + 1, "refresh answered")
print = print_

-- opcode: unique among the Chaos opcodes
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	check(not seen[v], "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end

print(string.format("bossspawns_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
