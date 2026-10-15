-- Run from the server/ folder: luajit tests/pocketboss_test.lua (and lua5.3; CI runs both)
-- Pocket bosses: the pure rules (pocketboss_core.lua) with the real pocketboss_config.lua (the boss list from the world
-- bosses and the Boss Spawns entries, daily charges and the reset, bonus charges and their caps, refunds, the entry and
-- party checks, health / damage / experience / loot scaling, the world boss reward at the reduced rate, no stacking,
-- the personal loot of the contested fights), the arena grid (clear of the other runtime areas); then pocketboss.lua
-- against a mocked engine: a solo and a party pocket (each member spends a charge, written before the teleport), a
-- logout keeps the charge spent, a restart gives it back, the kill (tokens, experience x0.6, loot factor, world
-- reward), the API for the online-time shop (addCharges, bosses), the world boss event blocking its pocket for an hour,
-- and the personal loot of an island boss for every helper above the threshold.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/uber_core.lua")
dofile("data/scripts/chaos/pocketboss_core.lua")
local K = ChaosPocketBossCore
local U = ChaosUberCore
local cfg = dofile("data/scripts/chaos/pocketboss_config.lua")
local spawnsCfg = dofile("data/scripts/chaos/bossspawns_config.lua")

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	eq(not not v, true, m)
end
-- a fixed random source: rand(n) -> 1..n, rand(a, b) -> a..b, rand() -> 0..1, from a list of fractions
local function fixed(list)
	local i = 0
	return function(a, b)
		i = i % #list + 1
		local f = list[i]
		if a == nil then
			return f
		end
		if b == nil then
			a, b = 1, a
		end
		return math.min(b, a + math.floor(f * (b - a + 1)))
	end
end

-- ====================================================================== the list
local entries = {}
for _, e in ipairs(spawnsCfg.bosses) do
	entries[#entries + 1] = e
end
entries[#entries + 1] = {key = "raid_gone", category = "raid", name = "Gone", monster = "Gone", missing = true}
local index = K.list(cfg, Chaos.worldBoss, entries)
local counts = {}
for _, b in ipairs(index.list) do
	counts[b.category] = (counts[b.category] or 0) + 1
	ok(cfg.categories[b.category], "only pocket categories: " .. b.key)
	ok(b.settings and b.settings.xpMult and b.settings.lootMult, "settings of " .. b.key)
end
eq(counts.world, #Chaos.worldBoss.bosses, "every world boss")
eq(counts.world, 5, "five world bosses")
eq(counts.island, 10, "the ten island bosses")
ok((counts.raid or 0) >= 20, "the raid-spawn bosses")
eq(counts.lair, nil, "no lair boss")
eq(counts.sepulchre, nil, "no Ashen Sepulchre boss (its loot is the weekly lockout)")
eq(counts.guild, nil, "no guild boss")
eq(counts.omen, nil, "no rift boss")
eq(index.byKey.raid_gone, nil, "a monster the server lacks is left out")
eq(index.byKey.world_1.name, "Kaelgor the Infernal Warlord", "world_1 as in the Boss Spawns window")
eq(index.byKey.world_1.minLevel, Chaos.worldBoss.minLevel, "the world boss level requirement is the event's")
eq(index.byKey.world_1.worldIndex, 1, "world index")
eq(index.byKey.raid_moloveth.minLevel, 250, "Moloveth's override")
eq(index.byKey.raid_moloveth.settings.tokens, 2, "Moloveth's tokens override")
eq(index.byKey.raid_vargra.settings.tokens, cfg.categories.raid.tokens, "the category's tokens")
eq(index.byKey.dreadscale.minLevel, cfg.categories.island.minLevel, "island level")
ok(index.byType["moloveth"], "by type")
local ex = K.list({categories = cfg.categories, exclude = {"world_2"}}, Chaos.worldBoss, entries)
eq(ex.byKey.world_2, nil, "excluded key")
-- every override names a listed boss
for key in pairs(cfg.overrides) do
	ok(index.byKey[key], "override of a listed boss: " .. key)
end
for cat, c in pairs(cfg.categories) do
	ok(c.xpMult > 0 and c.xpMult < 1, cat .. ": the pocket gives less experience")
	ok(c.lootMult > 0 and c.lootMult < 1, cat .. ": the pocket gives less loot")
	ok(c.minutes >= 5 and c.minutes <= 30, cat .. ": time limit")
	ok(K.scale(c.health, 5) <= c.health.max + 1e-9 and K.scale(c.health, 1) == c.health.solo, cat .. ": health curve")
	ok(K.scale(c.damage, 1) <= 1, cat .. ": a solo pocket hits softer or the same")
end

-- ====================================================================== charges and the reset
local day1 = os.time({year = 2026, month = 10, day = 15, hour = 12, min = 0, sec = 0})
eq(K.dayKey(day1, 0), 20261015, "day key")
eq(K.dayKey(os.time({year = 2026, month = 10, day = 16, hour = 5, min = 59}), 6), 20261015, "before the reset hour: yesterday")
eq(K.dayKey(os.time({year = 2026, month = 10, day = 16, hour = 6, min = 0}), 6), 20261016, "at the reset hour: today")
eq(K.nextReset(day1, 0), 12 * 3600, "12 h to midnight")
local s = K.charges(cfg, nil, day1)
eq(s.left, cfg.charges.daily, "a new character: the daily charges")
eq(s.max, 3, "3 a day")
local row = nil
local kinds = {}
for i = 1, 3 do
	local kind
	row, kind = K.spend(cfg, row, day1)
	kinds[i] = kind
end
eq(kinds[1], "daily", "daily first")
eq(K.charges(cfg, row, day1).left, 0, "three spent")
local row4, kind4, why4 = K.spend(cfg, row, day1)
eq(kind4, nil, "a fourth is refused")
ok(why4 and why4[1]:find("No pocket charges", 1, true), "reason")
eq(row4.used, 3, "nothing spent on a refusal")
-- the next day: the daily charges are back
local day2 = day1 + 86400
eq(K.charges(cfg, row, day2).left, 3, "reset the next day")
eq(K.charges(cfg, row, day1 + 11 * 3600 + 3599).left, 0, "still spent a second before midnight")
-- bonus charges (the online-time shop)
local brow, added, bwhy = K.addBonus(cfg, row, 2, day1)
eq(added, 2, "two bonus charges")
eq(K.charges(cfg, brow, day1).left, 2, "spendable today")
brow, added = K.addBonus(cfg, brow, 5, day1)
eq(added, 1, "the daily cap: 3 a day")
brow, added, bwhy = K.addBonus(cfg, brow, 1, day1)
eq(added, 0, "no more today")
ok(bwhy and bwhy[1]:find("today", 1, true), "the reason")
eq(K.charges(cfg, brow, day2).left, 3 + 3, "bonus charges stay over the reset, on top of the daily ones")
brow = K.addBonus(cfg, brow, 3, day2)
eq(K.charges(cfg, brow, day2).bonus, cfg.charges.bonusMax, "held at most bonusMax")
local _, a2, w2 = K.addBonus(cfg, brow, 1, day2 + 86400)
eq(a2, 0, "full: nothing added")
ok(w2[1]:find("most", 1, true), "full reason")
for _, bad in ipairs({0, -1, 1.5, "x", 0 / 0}) do
	local _, a = K.addBonus(cfg, nil, bad, day1)
	eq(a, 0, "bad bonus count " .. tostring(bad))
end
-- daily before bonus
local mix = K.addBonus(cfg, nil, 1, day1)
local _, k1 = K.spend(cfg, mix, day1)
eq(k1, "daily", "a daily charge before a bonus one")
local mrow = mix
for _ = 1, 3 do
	mrow = K.spend(cfg, mrow, day1)
end
local _, k4 = K.spend(cfg, mrow, day1)
eq(k4, "bonus", "then the bonus one")
-- a refund (restart): the daily of the same day, else a bonus charge
local rr = K.refund(cfg, row, "daily", day1)
eq(K.charges(cfg, rr, day1).left, 1, "daily refund")
local rb = K.refund(cfg, row, "daily", day2)
eq(K.charges(cfg, rb, day2).left, 3, "a refund of yesterday's daily charge on a new day changes nothing")
local rbon = K.refund(cfg, nil, "bonus", day1)
eq(K.charges(cfg, rbon, day1).bonus, 1, "bonus refund")
-- a stored row with bad values counts as zero
eq(K.charges(cfg, {day = "x", used = -4, bonus = 99}, day1).left, 3 + cfg.charges.bonusMax, "bad row values clamped")

-- ====================================================================== entering
local boss = index.byKey.world_1
local good = {enabled = true, boss = boss, level = 400, pz = true, needPz = true, charges = K.charges(cfg, nil, day1)}
eq(K.enterError(good), nil, "may enter")
local function why(info)
	local w = K.enterError(info)
	return w and w[1] or nil
end
local function with(t)
	local o = {}
	for k, v in pairs(good) do
		o[k] = v
	end
	for k, v in pairs(t) do
		o[k] = v
	end
	return o
end
ok(why(with({enabled = false})):find("off", 1, true), "switched off")
ok(why(with({boss = false})):find("no pocket", 1, true), "unknown boss")
ok(why(with({level = 299})):find("level", 1, true), "level 300 like the world boss event")
ok(why(with({instance = "a rift"})):find("Leave", 1, true), "inside another instance")
ok(why(with({pz = false})):find("protection zone", 1, true), "protection zone")
ok(why(with({inFight = true})):find("combat", 1, true), "in combat")
ok(why(with({cooldown = 5})):find("Wait", 1, true), "re-entry cooldown")
ok(why(with({noStack = 1800})):find("less than an hour", 1, true), "no stacking with the event")
ok(why(with({charges = K.charges(cfg, row, day1)})):find("No pocket charges", 1, true), "no charges")
-- party members
local mgood = {boss = boss, level = 400, charges = K.charges(cfg, nil, day1)}
eq(K.memberError(mgood), nil, "member may come")
eq(K.memberError({boss = boss, level = 200, charges = mgood.charges})[1], "level %d needed", "member level")
eq(K.memberError({boss = boss, level = 400, charges = K.charges(cfg, row, day1)})[1], "no charges left", "member without charges")
eq(K.memberError({boss = boss, level = 400, far = true, charges = mgood.charges})[1], "too far away", "member far away")
eq(K.memberError({boss = boss, level = 400, noStack = 10, charges = mgood.charges})[1],
	"rewarded by this boss's event within the hour", "member rewarded by the event")

-- ====================================================================== scaling and rewards
local w = cfg.categories.world
eq(K.scale(w.health, 1), 0.03, "world solo health 3%")
eq(K.scale(w.health, 5), 0.13, "5 players")
eq(K.scale(w.health, 40), w.health.max, "capped")
eq(K.scale(nil, 3), 1, "no curve")
eq(K.scale(w.damage, 0), w.damage.solo, "0 players counts as 1")
eq(K.scaleExp(1000, 0.6, function() return 0.5 end), 600, "experience x0.6")
eq(K.scaleExp(1, 0.6, function() return 0.3 end), 1, "a fraction rounds up at random")
eq(K.scaleExp(1, 0.6, function() return 0.7 end), 0, "or down")
eq(K.scaleExp(0, 0.6), 0, "no experience")
eq(K.scaleExp(500, 1), 500, "x1 untouched")
-- the world boss reward at the reduced rate: over many rolls, gear at gearChance x 0.6
local wr = Chaos.worldBoss.reward
local kael = Chaos.worldBoss.bosses[1]
local gears, uniques, orbs = 0, 0, 0
local seed = 12345
local function lcg(a, b)
	seed = (seed * 16807) % 2147483647
	local f = seed / 2147483647
	if a == nil then
		return f
	end
	if b == nil then
		a, b = 1, a
	end
	return a + math.floor(f * (b - a + 1))
end
local N = 20000
for _ = 1, N do
	local r = K.worldReward(wr, kael, 0.6, {111, 222}, lcg)
	if r.gear then
		gears = gears + 1
		ok(r.gearRarity >= wr.gearRarity[1] and r.gearRarity <= wr.gearRarity[2], "gear rarity")
		local inList = false
		for _, id in ipairs(kael.gear) do
			inList = inList or id == r.gear
		end
		ok(inList, "a piece of the boss's own set")
	end
	if r.unique then
		uniques = uniques + 1
	end
	for _, it in ipairs(r.items) do
		if it.id == 29856 then
			orbs = orbs + it.count
		end
	end
end
local gearRate = gears / N
ok(math.abs(gearRate - wr.gearChance * 0.6 / 10000) < 0.01, "gear at 60% of the event's base chance: " .. gearRate)
ok(gearRate < wr.gearChance / 10000, "less than the event")
ok(math.abs(orbs / N - 3 * 0.6) < 0.05, "base orbs x0.6: " .. orbs / N)
ok(uniques / N < wr.uniqueChance / 10000, "unique below the event's chance")
local none = K.worldReward(wr, kael, 0.6, {}, lcg, {base = false, gear = false, unique = false})
eq(#none.items + (none.gear and 1 or 0) + (none.unique and 1 or 0), 0, "every part can be switched off")
-- no stacking
eq(K.noStackLeft(nil, day1, 3600), 0, "never rewarded")
eq(K.noStackLeft(day1 - 600, day1, 3600), 3000, "50 minutes left")
eq(K.noStackLeft(day1 - 4000, day1, 3600), 0, "over")
eq(K.noStackLeft(day1, day1, 0), 0, "switched off")
local ev = K.noteEvent(cfg, (K.spend(cfg, nil, day1)), day1 + 5)
eq(ev.eventAt, day1 + 5, "noteEvent sets the time")
eq(ev.used, 1, "and keeps the charges")
eq((K.spend(cfg, ev, day1)).eventAt, day1 + 5, "a spend keeps the event time")
eq((K.addBonus(cfg, ev, 1, day1)).eventAt, day1 + 5, "a bonus keeps the event time")
-- the personal loot of the contested fights
local stats = {[1] = {name = "Owner", damage = 500000}, [2] = {name = "Helper", damage = 30000},
	[3] = {name = "Healer", damage = 0, healing = 25000}, [4] = {name = "Leech", damage = 1000}}
local list = K.contestEligible(stats, 1000000, cfg.contested, 1)
eq(#list, 2, "two helpers above 2% of 1,000,000")
eq(list[1].name, "Helper", "best first")
eq(list[2].name, "Healer", "healing counts")
local capped = K.contestEligible(stats, 1000000, {minPercent = 0, maxPlayers = 1}, nil)
eq(#capped, 1, "maxPlayers")
eq(capped[1].name, "Owner", "without an owner everyone counts")
local loot = {{itemId = 2160, chance = 100000, maxCount = 60}, {itemId = 29879, chance = 6000}, {itemId = 0, chance = 100000},
	{itemId = 5, chance = 0}}
local rolled = K.personalRoll(loot, 1, fixed({0.0}))
eq(#rolled, 2, "an always and a rare item with a low roll; bad entries left out")
eq(rolled[1].id, 2160, "the always item")
local high = K.personalRoll(loot, 1, fixed({0.99}))
eq(#high, 1, "a high roll: only the always item")
-- the Boss Spawns list: raid rows by pocket level then name, every other row in place
local rows = {{k = "world_1", c = "world", n = "Kaelgor"}, {k = "raid_vargra", c = "raid", n = "Vargra"},
	{k = "raid_moloveth", c = "raid", n = "Moloveth"}, {k = "raid_briarfang", c = "raid", n = "Briarfang"},
	{k = "lair_tibb", c = "lair", n = "Tibb"}, {k = "dreadscale", c = "island", n = "Dreadscale"}, {k = "azazel", c = "island", n = "Azazel"}}
K.tidy(rows, {world_1 = 300, raid_vargra = 150, raid_moloveth = 250, raid_briarfang = 150, dreadscale = 250, azazel = 250},
	cfg.sortSpawns)
local order = {}
for i, r in ipairs(rows) do
	order[i] = r.k
end
eq(table.concat(order, " "), "world_1 raid_briarfang raid_vargra raid_moloveth lair_tibb dreadscale azazel",
	"raid by level and name, the rest as sent")
eq(rows[1].pl, 300, "pocket level on the row")
eq(rows[5].pl, nil, "no pocket, no level")
eq(K.clockText(3725), "1h 02m", "clock")
eq(K.clockText(65), "1m 05s", "clock m")

-- ====================================================================== the arena grid
local g = cfg.grid
local x1, y1 = g.origin.x, g.origin.y
local x2, y2 = x1 + g.cols * g.spacing - 1, y1 + math.ceil(g.slots / g.cols) * g.spacing - 1
local others = {
	{"guild boss", dofile("data/scripts/chaos/guildboss_config.lua").grid},
	{"raid", {origin = {x = 10400, y = 10000}, cols = 2, slots = 4, spacing = 256}},
	{"battleground", dofile("data/scripts/chaos/battleground_config.lua").grid},
	{"hideouts", {origin = {x = 12288, y = 12288}, cols = 16, slots = 256, spacing = 32}}
}
for _, o in ipairs(others) do
	local og = o[2]
	local ox1, oy1 = og.origin.x, og.origin.y
	local ox2 = ox1 + og.cols * og.spacing - 1
	local oy2 = oy1 + math.ceil((og.slots or (og.cols * (og.rows or 1))) / og.cols) * og.spacing - 1
	ok(x2 < ox1 or x1 > ox2 or y2 < oy1 or y1 > oy2, "grid clear of the " .. o[1])
end
for slot = 1, g.slots do
	local L = U.layout(cfg, slot)
	for _, list in ipairs({L.floorList, L.anteList, L.wallList}) do
		for _, t in ipairs(list) do
			if U.slotAt(cfg, t) ~= slot then
				error("slot " .. slot .. ": tile " .. t.x .. "," .. t.y .. " outside its cell")
			end
		end
	end
end
checks = checks + 1

-- ====================================================================== pocketboss.lua against a mocked engine
local NOW = day1
os.time = (function(orig)
	return function(t)
		if t then
			return orig(t)
		end
		return NOW
	end
end)(os.time)
os.mtime = function() return NOW * 1000 end
local registry, callbacks = {}, {}
local function event(kind)
	return function(name)
		local ev = {name = name}
		function ev.register() registry[name or kind] = ev end
		function ev.separator() end
		function ev.aid() end
		function ev.type() end
		return ev
	end
end
CreatureEvent, GlobalEvent, TalkAction, MoveEvent = event("c"), event("g"), event("t"), event("m")
do
	local pending = {}
	EventCallback = setmetatable({}, {__newindex = function(_, k, v) pending[k] = v end, __index = function(_, k)
		if k == "register" then
			return function(_, idx)
				for name, fn in pairs(pending) do
					callbacks[name] = callbacks[name] or {}
					table.insert(callbacks[name], {fn = fn, idx = idx})
				end
				pending = {}
			end
		end
	end})
end
local events = {}
function addEvent(fn, ms, ...)
	events[#events + 1] = {fn = fn, ms = ms, args = {...}, at = NOW * 1000 + (ms or 0)}
end
local function runEvents(untilMs)
	local guard = 0
	while true do
		local best, bi
		for i, e in ipairs(events) do
			if e.at <= untilMs and (not best or e.at < best.at) then
				best, bi = e, i
			end
		end
		if not best then
			return
		end
		table.remove(events, bi)
		guard = guard + 1
		if guard > 100000 then
			error("event loop")
		end
		NOW = math.max(NOW, math.floor(best.at / 1000))
		best.fn((table.unpack or unpack)(best.args))
	end
end
local function advance(secs)
	NOW = NOW + secs
	runEvents(NOW * 1000)
end
local function pos(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
Position = pos
local tiles = {}
Tile = function(p)
	local t = tiles[p.x .. "," .. p.y .. "," .. p.z]
	return t
end
local monsters = {}
local nextMid = 5000
local function newMonster(name, p)
	nextMid = nextMid + 1
	local m = {id = nextMid, name = name, hp = 1000000, maxHp = 1000000, pos = p, events = {}}
	function m:getId() return self.id end
	function m:getName() return self.name end
	function m:isMonster() return true end
	function m:isPlayer() return false end
	function m:getMaster() return nil end
	function m:getHealth() return self.hp end
	function m:getMaxHealth() return self.maxHp end
	function m:setMaxHealth(v) self.maxHp = v end
	function m:addHealth(v) self.hp = self.hp + v end
	function m:getPosition() return self.pos end
	function m:registerEvent(e) self.events[e] = true end
	function m:getTarget() return {} end
	function m:teleportTo(p2) self.pos = p2 end
	function m:remove() monsters[self.id] = nil end
	function m:getType() return {getLoot = function() return {{itemId = 2160, chance = 100000, maxCount = 10},
		{itemId = 7777, chance = 100000}} end} end
	monsters[m.id] = m
	return m
end
Monster = function(id) return monsters[id] end
MonsterType = function(name) return name ~= "Gone" and {} or nil end
local created = {}
Game = {
	createTile = function(p)
		local t = {items = {}, creatures = {}}
		function t:getGround() return self.ground end
		function t:getItemById() return nil end
		function t:getItems() return {} end
		function t:getCreatures() return {} end
		function t:hasFlag() return false end
		tiles[p.x .. "," .. p.y .. "," .. p.z] = t
		return t
	end,
	createItem = function(id, count, p)
		if p then
			local t = tiles[p.x .. "," .. p.y .. "," .. p.z]
			if t and not t.ground then
				t.ground = id
			end
		end
		return {setActionId = function() end, getId = function() return id end}
	end,
	createMonster = function(name, p)
		local m = newMonster(name, p)
		for _, cb in ipairs(callbacks.onSpawn or {}) do
			cb.fn(m, p, false, true)
		end
		created[#created + 1] = m
		return m
	end,
	getPlayers = function() return {} end,
	getSpectators = function() return {} end,
	getGameState = function() return 1 end,
	broadcastMessage = function() end
}
GAME_STATE_SHUTDOWN, GAME_STATE_CLOSED = 99, 98
-- the database
local ROWS, queries = {}, {}
db = {escapeString = function(s) return "'" .. tostring(s) .. "'" end}
function db.query(q)
	queries[#queries + 1] = q
	local pid, key, d, u, b, bd, ba, kill, ev = q:match("VALUES %((%d+), '([^']+)', (%d+), (%d+), (%d+), (%d+), (%d+), (%d+), (%d+)%)")
	if pid then
		local r = ROWS[pid .. ":" .. key] or {kills = 0}
		r.day, r.used, r.bonus, r.bonus_day, r.bonus_added = tonumber(d), tonumber(u), tonumber(b), tonumber(bd), tonumber(ba)
		r.kills = r.kills + tonumber(kill)
		r.event_at = tonumber(ev)
		r.boss_key = key
		r.pid = tonumber(pid)
		ROWS[pid .. ":" .. key] = r
	end
	return true
end
Chaos.select = function(q)
	local pid = q:match("WHERE `player_id` = (%d+)")
	local out = {}
	for _, r in pairs(ROWS) do
		if tostring(r.pid) == pid then
			out[#out + 1] = r
		end
	end
	return out
end
local sent = {}
Chaos.send = function(p, op, action, data)
	sent[#sent + 1] = {p = p, op = op, action = action, data = data}
	return true
end
Chaos.giveItem = function(player, id, count)
	player.items[id] = (player.items[id] or 0) + count
	return count
end
Chaos.heal = function(c, amount) c.hp = math.min(c.maxHp, c.hp + amount) end
ChaosBossSpawns = {ensure = function() return {list = entries, byType = {}} end}
local tokens = {}
ChaosConquest = {grant = function(p, source, amount)
	tokens[#tokens + 1] = {name = p:getName(), source = source, amount = amount}
end}
ItemType = function(id) return {getName = function() return "item " .. id end, getId = function() return id end} end

local players = {}
local function newPlayer(id, level)
	local p = {id = id, level = level, pos = pos(100, 100, 7), msgs = {}, events = {}, items = {}, hp = 2000, maxHp = 2000,
		pz = true}
	function p:getId() return self.id end
	function p:getGuid() return 100 + self.id end
	function p:getName() return "P" .. self.id end
	function p:getLevel() return self.level end
	function p:getPosition() return self.pos end
	function p:teleportTo(p2) self.pos = pos(p2.x, p2.y, p2.z) end
	function p:registerEvent(e) self.events[e] = true end
	function p:unregisterEvent(e) self.events[e] = nil end
	function p:removeCondition() end
	function p:hasCondition() return false end
	function p:isPzLocked() return false end
	function p:getParty() return self.party end
	function p:getTown() return {getTemplePosition = function() return pos(100, 100, 7) end} end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getMaster() return nil end
	function p:getHealth() return self.hp end
	function p:getMaxHealth() return self.maxHp end
	function p:getInbox() return nil end
	function p:addItemEx() return 0 end
	players[id] = p
	return p
end
Player = function(id)
	if type(id) == "string" then
		for _, p in pairs(players) do
			if p:getName() == id then
				return p
			end
		end
		return nil
	end
	return players[id]
end
-- protection zone: the mock tile under a player at 100,100
tiles["100,100,7"] = {hasFlag = function() return true end, getGround = function() return 1 end}
tiles["200,200,7"] = {hasFlag = function() return false end, getGround = function() return 1 end}

dofile("data/scripts/chaos/pocketboss.lua")
local PB = ChaosPocketBoss
Chaos.pocketBossConfig.darkActive = false
local pcfg = Chaos.pocketBossConfig

-- the API for the online-time shop
local bl = PB.bosses()
ok(#bl >= 35, "bosses(): every pocket boss")
eq(bl[1].key, "world_1", "world bosses first")
eq(bl[1].minLevel, 300, "minLevel")
ok(bl[1].name, "name")
local a = newPlayer(1, 400)
local added = PB.addCharges(a, "world_1", 2)
eq(added, 2, "addCharges")
eq(ROWS["101:world_1"].bonus, 2, "stored in the database at once")
eq(PB.charges(a, "world_1").left, 5, "3 daily + 2 bonus")
local zero, zwhy = PB.addCharges(a, "nope", 1)
eq(zero, 0, "unknown boss")
ok(zwhy, "unknown boss reason")
eq((PB.addCharges(a, "world_1", 5)), 1, "the daily cap of bonus charges")

-- a solo pocket: refused outside a protection zone, then opened
a.pos = pos(200, 200, 7)
local okE, text = PB.enter(a, "world_1")
eq(okE, false, "not from outside a protection zone")
ok(text:find("protection zone", 1, true), text)
a.pos = pos(100, 100, 7)
local low = newPlayer(9, 100)
eq((PB.enter(low, "world_1")), false, "level 300 for a world boss")
okE, text = PB.enter(a, "world_1")
eq(okE, true, "opened: " .. tostring(text))
eq(ROWS["101:world_1"].used, 1, "the charge is written before the teleport")
ok(PB.isInside(a), "inside")
ok(U.slotAt(pcfg, a.pos), "standing in a pocket slot")
ok(a.events.ChaosPocketBossPlayerHit and a.events.ChaosPocketBossPrepareDeath, "fight events on")
eq((PB.enter(a, "world_1")), false, "no second pocket from inside")
local run = PB.runOf[a:getId()]
eq(run.size, 1, "solo")
-- the boss comes after startDelay, its health scaled for one player
advance(pcfg.startDelay + 1)
local bossM = Monster(run.bossId)
ok(bossM, "the boss appeared")
eq(bossM.maxHp, math.floor(1000000 * 0.03), "health x the solo curve")
ok(bossM.events.ChaosPocketBossDeath, "death event")
eq(bossM.events.ChaosPocketContestHealth, nil, "a pocket boss never counts as the contested fight")
eq(PB.lootMultOf(bossM), 0.6, "loot factor of a pocket monster")
ok(PB.isWorldBoss(bossM), "the pocket world boss drops at the world boss item level")
eq(PB.lootMultOf(newMonster("Rat", pos(50, 50, 7))), 1, "elsewhere x1")
-- its hits on the player x the damage curve
local hit = registry.ChaosPocketBossPlayerHit.onHealthChange
local dmg = hit(a, bossM, -1000, 1, 0, 1, 0)
eq(dmg, -500, "a solo pocket: the boss hits for half")
local norm = hit(a, newMonster("Rat", pos(50, 50, 7)), -100, 1, 0, 1, 0)
eq(norm, -100, "other monsters untouched")
-- experience of a pocket monster x0.6
local xp = callbacks.onGainExperience[1].fn
math.randomseed(1)
local total = 0
for _ = 1, 100 do
	total = total + xp(a, bossM, 1000, 1000)
end
eq(total, 60000, "experience x0.6")
eq(xp(a, newMonster("Rat", pos(50, 50, 7)), 1000, 1000), 1000, "elsewhere untouched")
-- the kill: tokens, the world boss reward, the corpse open for exitDelay, then out
registry.ChaosPocketBossDeath.onDeath(bossM)
advance(0)
eq(run.state, "success", "success")
eq(#tokens, 1, "Conquest Tokens")
eq(tokens[1].source, "pocketboss:world_1", "source key")
eq(tokens[1].amount, pcfg.categories.world.tokens, "token amount")
eq(ROWS["101:world_1"].kills, 1, "kill counted")
ok(PB.isInside(a), "still inside to loot")
advance(pcfg.exitDelay + 1)
ok(not PB.isInside(a), "sent back after exitDelay")
eq(a.pos.x, 100, "back where they came from")
eq(PB.runs[run.slot], nil, "the slot is free")

-- a party: each member spends a charge; a member without charges stays behind
local b, c = newPlayer(2, 400), newPlayer(3, 400)
local party = {getLeader = function() return a end, getMembers = function() return {b, c} end}
a.party, b.party, c.party = party, party, party
b.pos, c.pos = pos(102, 100, 7), pos(103, 101, 7)
ROWS["103:dreadscale"] = {pid = 103, boss_key = "dreadscale", day = 20261015, used = 3, bonus = 0, bonus_day = 0, bonus_added = 0, kills = 0}
PB.rows[103] = nil
NOW = NOW + pcfg.enterCooldown + 1
okE, text = PB.enter(a, "dreadscale")
eq(okE, true, "party pocket: " .. tostring(text))
run = PB.runOf[a:getId()]
eq(run.size, 2, "two came")
ok(PB.isInside(b) and not PB.isInside(c), "the member without charges stayed")
eq(ROWS["101:dreadscale"].used, 1, "leader spent one")
eq(ROWS["102:dreadscale"].used, 1, "member spent one")
eq(ROWS["103:dreadscale"].used, 3, "the one left behind spent none")
ok(c.msgs[#c.msgs]:find("no charges left", 1, true), "told why")
advance(pcfg.startDelay + 1)
bossM = Monster(run.bossId)
eq(bossM.maxHp, math.floor(1000000 * K.scale(pcfg.categories.island.health, 2)), "health for two")
-- a logout inside: out, the charge stays spent
registry.ChaosPocketBossLogout.onLogout(b)
ok(not PB.isInside(b), "logout: out")
PB.rows[102] = nil
eq(PB.charges(b, "dreadscale").left, 2, "no refund on logout")
-- a lethal hit: caught, out, no death
a.hp = 100
local p1 = hit(a, bossM, -5000, 1, 0, 1, 0)
eq(p1, -99, "the lethal hit leaves 1 health")
advance(0)
ok(not PB.isInside(a), "the fallen player is out")
eq(a.hp, a.maxHp, "healed")
eq(PB.runs[run.slot], nil, "the last one out closes the pocket")
eq(Monster(run.bossId), nil, "the boss is removed")

-- a restart with a pocket open gives the charge back
NOW = NOW + pcfg.enterCooldown + 1
a.party, b.party, c.party = nil, nil, nil
a.pos = pos(100, 100, 7)
okE = PB.enter(a, "raid_moloveth")
eq(okE, true, "Moloveth's pocket")
eq(ROWS["101:raid_moloveth"].used, 1, "spent")
registry.ChaosPocketBossShutdown.onShutdown()
eq(ROWS["101:raid_moloveth"].used, 0, "given back at the restart")
ok(not PB.isInside(a), "out")
-- logging in inside the grid (after a crash) sends the character to its temple
local L1 = U.layout(pcfg, 1)
a.pos = pos(L1.entry.x, L1.entry.y, L1.entry.z)
registry.ChaosPocketBossLogin.onLogin(a)
eq(a.pos.x, 100, "a login inside the grid goes to the temple")

-- the world boss event blocks its pocket for an hour (no stacking)
ChaosWorldBoss = {state = {index = 2}, deliver = function() end}
registry.ChaosPocketBossLogin.onLogin(a)
ChaosWorldBoss.deliver(a, {})
eq(ROWS["101:world_2"].event_at, NOW, "the event reward is written to chaos_pocketboss.event_at")
-- a restart: every memory of the module is gone, the database row stays
PB.rows = {}
NOW = NOW + pcfg.enterCooldown + 1
okE, text = PB.enter(a, "world_2")
eq(okE, false, "rewarded by Skaldra's event: her pocket waits, also after a restart")
ok(text:find("less than an hour", 1, true), text)
eq(ROWS["101:world_2"].used, 0, "the refused opening spent nothing")
NOW = NOW + 3600
okE = PB.enter(a, "world_2")
eq(okE, true, "an hour later it opens")
ok(ROWS["101:world_2"].event_at > 0 and ROWS["101:world_2"].used == 1, "spending a charge keeps the event time")
PB._fail(PB.runOf[a:getId()], "Test.")

-- the opcode actions are rate limited and take only a string key
ok(PB.actions.pocketEnter and PB.actions.pocketLeave and PB.actions.pocketInfo, "actions")
PB.actions.pocketEnter(a, {k = {}})
PB.actions.pocketEnter(a, {k = string.rep("x", 200)})
PB.actions.pocketEnter(a, nil)
ok(not PB.isInside(a), "bad keys open nothing")

-- the contested fight: an island boss spawned by the base server; every helper above 2% gets a personal roll
local owner, helper, healer, leech = newPlayer(11, 500), newPlayer(12, 500), newPlayer(13, 500), newPlayer(14, 500)
local isle = newMonster("Dreadscale The Ancient", pos(32314, 31524, 9))
isle.maxHp, isle.hp = 1000000, 1000000
for _, cb in ipairs(callbacks.onSpawn) do
	cb.fn(isle, isle.pos, false, false)
end
ok(isle.events.ChaosPocketContestHealth and isle.events.ChaosPocketContestDeath, "the island boss is tracked")
ChaosBossSpawnsCore = {match = function(_, info)
	if info.type == "Dreadscale The Ancient" then
		return {{key = "dreadscale", category = "island", name = "Dreadscale the Ancient"}}
	end
	return {}
end}
Chaos.monsterTypeName = function(m) return m.name end
Chaos.bossSpawnsConfig = {radius = 40}
local ch = registry.ChaosPocketContestHealth.onHealthChange
ch(isle, owner, -600000, 1, 0, 1, 0)
ch(isle, helper, -50000, 1, 0, 1, 0)
ch(isle, leech, -1000, 1, 0, 1, 0)
-- the healer heals the helper, who fights the boss
helper.hp = 1000
helper.pos = pos(32316, 31524, 9)
registry.ChaosPocketContestHeal.onHealthChange(helper, healer, 900, COMBAT_HEALING, 0, 1, 0)
eq(PB.contest[isle.id].healing[healer:getGuid()], 900, "healing on a fighter counts (capped at the missing health)")
registry.ChaosPocketContestHeal.onHealthChange(helper, healer, 30000, COMBAT_HEALING, 0, 1, 0)
local corpse = {getCorpseOwner = function() return owner.id end}
PB.contest[isle.id].healing[healer:getGuid()] = 25000 -- as if healed over the fight
registry.ChaosPocketContestDeath.onDeath(isle, corpse, owner, owner)
eq(helper.items[2160] ~= nil, true, "the helper got a personal roll")
eq(healer.items[2160] ~= nil, true, "the healer too")
eq(owner.items[2160], nil, "the corpse owner has the corpse, no extra roll")
eq(leech.items[2160], nil, "under 2%: nothing")
ok(helper.msgs[#helper.msgs]:find("Personal loot", 1, true), "told")
eq(PB.contest[isle.id], nil, "forgotten")
-- the event reward blocks the helper's pocket of Dreadscale for an hour
helper.pos = pos(100, 100, 7)
okE, text = PB.enter(helper, "dreadscale")
eq(okE, false, "no pocket right after the contested reward")
-- a lair spawn of a type that is also a raid boss is not contested (its place decides)
local lair = newMonster("Ul'thazmor", pos(32322, 31932, 6))
ch(lair, owner, -1000, 1, 0, 1, 0)
eq(PB.contest[lair.id], false, "not an island / raid spawn: no personal loot")

print(string.format("pocketboss_test: %d checks passed", checks))
