-- Run from the server/ folder: luajit tests/guildboss_test.lua (and lua5.3; CI runs both)
-- The weekly guild boss: the pure rules (guildboss_core.lua) with the real guildboss_config.lua (the week, the fuel and
-- its gold / material rates, the summon checks with the weekly lockout, scaling and the balance targets, rewards (the
-- gold pool and its split: exact sum, floor, proportionality, a single winner), banners, the board), the arena grid
-- (inside its cells, clear of every other runtime area), the stone in the guild hall layout, the monster XML; then
-- guildboss.lua against a mocked engine: donations, the summon (one conditional UPDATE that spends the need), a failed
-- attempt keeping half of the need, a kill (healing counted, the shares to the banks, persisted and logged), the lockout.
dofile("data/scripts/chaos/uber_core.lua")
dofile("data/scripts/chaos/guildboss_core.lua")
dofile("data/scripts/chaos/guild_core.lua")
local B = ChaosGuildBossCore
local U = ChaosUberCore
local cfg = dofile("data/scripts/chaos/guildboss_config.lua")
local gcfg = dofile("data/scripts/chaos/guild_config.lua")

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

-- ---------------------------------------------------------------- week
local monday = os.time({year = 2026, month = 10, day = 12, hour = 6, min = 0, sec = 0})
eq(B.weekKey(cfg, monday), 20261012, "Monday 06:00 starts the week")
eq(B.weekKey(cfg, monday - 1), 20261005, "a second earlier is last week")
eq(B.weekKey(cfg, monday + 6 * 86400 + 3600), 20261012, "Sunday is the same week")
eq(B.nextReset(cfg, monday + 3600), monday + 7 * 86400, "the next reset")

-- ---------------------------------------------------------------- fuel
eq(B.need(5, cfg), 625, "need at guild level 5")
eq(B.need(10, cfg), 750, "need at guild level 10")
eq(B.need(20, cfg), 1000, "need at guild level 20")
local e, g = B.goldEmbers(1234567, cfg)
eq(e, 123, "embers of gold")
eq(g, 1230000, "only whole embers are paid")
eq((B.goldEmbers(cfg.gold.min - 1, cfg)), nil, "under the minimum")
eq((B.goldEmbers("abc", cfg)), nil, "not a number")
eq((B.goldEmbers(0 / 0, cfg)), nil, "NaN")
local m = B.material(cfg, "fate")
eq(m.id, 29857, "Orb of Fate")
eq(B.material(cfg, 29856).key, "upheaval", "by id")
eq(B.material(cfg, "gold"), nil, "unknown material")
local take, emb = B.materialEmbers(m, 3, cfg)
eq(take, 3, "takes what is carried")
eq(emb, 75, "3 x 25 embers")
take, emb = B.materialEmbers(B.material(cfg, "shard"), 1000, cfg)
eq(take, cfg.maxPerDonation, "capped per donation")
eq(emb, cfg.maxPerDonation * 2, "embers of the cap")
eq(B.fuelAfterFail(10, 750, cfg), 10 + 375, "a failed attempt keeps half of the need")
local ids = {}
for _, mat in ipairs(cfg.materials) do
	ok(not ids[mat.id], "material ids unique")
	ids[mat.id] = true
	ok(mat.embers > 0, "material embers")
end

-- ---------------------------------------------------------------- summon checks and the weekly lockout
local function info(over)
	local i = {enabled = true, guildId = 4, rank = 3, hasHall = true, rentLocked = false, inHall = true, fuel = 800, need = 750,
		killed = false, attempts = 0, players = 5, running = false}
	for k, v in pairs(over or {}) do
		i[k] = v
	end
	return i
end
eq(B.summonError(info(), cfg), nil, "ready")
eq(B.summonError(info({rank = 2}), cfg), nil, "a vice-leader summons")
ok(B.summonError(info({rank = 1}), cfg), "a member cannot")
ok(B.summonError(info({guildId = 0}), cfg), "no guild")
ok(B.summonError(info({hasHall = false}), cfg):find("guild hall"), "no hall")
ok(B.summonError(info({rentLocked = true}), cfg):find("rent"), "rent locked")
ok(B.summonError(info({inHall = false}), cfg):find("Stand"), "outside the hall")
ok(B.summonError(info({killed = true}), cfg):find("already slew"), "the weekly lockout")
ok(B.summonError(info({running = true}), cfg), "a run in progress")
ok(B.summonError(info({attempts = cfg.maxAttempts}), cfg):find("summons"), "attempts used")
ok(B.summonError(info({fuel = 749}), cfg):find("749"), "not enough fuel")
ok(B.summonError(info({players = cfg.minPlayers - 1}), cfg):find("members"), "too few members")
ok(B.summonError(info(), {enabled = false}), "disabled")

-- ---------------------------------------------------------------- scaling and the balance targets
eq(B.healthMult(cfg, 1), 1, "one player")
eq(B.healthMult(cfg, 5), 1 + cfg.boss.healthPerExtraPlayer * 4, "five players")
eq(B.livesFor(cfg, 1), cfg.lives.base, "lives alone")
eq(B.livesFor(cfg, 4), cfg.lives.base + 1, "one more life per 3 more players")
eq(B.livesFor(cfg, 20), cfg.lives.base + 6, "lives of 20")
for key, target in pairs(cfg.targets) do
	local n = tonumber(key:match("%d+"))
	local tt = B.killTime(cfg, n)
	ok(math.abs(tt - target) <= target * 0.1, string.format("kill time of %d players %.0f s near %d", n, tt, target))
	ok(tt < cfg.boss.enrageAt, "before the enrage with " .. n)
end
ok(B.killTime(cfg, cfg.maxPlayers) < cfg.boss.enrageAt, "a full guild kills before the enrage")
ok(B.addHealthMult(cfg, 10) > 1, "adds scale")
local prev = 0
for _, ph in ipairs(cfg.boss.phases) do
	ok(ph.at <= 1 and (prev == 0 or ph.at < prev), "phases in order")
	prev = ph.at
	for _, name in ipairs(ph.patterns) do
		ok(cfg.patterns[name], "pattern " .. name .. " has a shape")
	end
end
-- the monster XML: health and names as the config says
local xml = io.open("data/monster/monsters/chaos/guildboss/gorvath_the_banner_eater.xml"):read("*a")
ok(xml:find('name="' .. cfg.boss.boss .. '"', 1, true), "boss name in the XML")
eq(tonumber(xml:match('<health now="(%d+)"')), cfg.bossHealth, "bossHealth matches the XML")
local addXml = io.open("data/monster/monsters/chaos/guildboss/banner_wraith.xml"):read("*a")
ok(addXml:find('name="' .. cfg.boss.add .. '"', 1, true), "add name in the XML")

-- ---------------------------------------------------------------- rewards, banners, board
local dmg = {[1] = 900000, [2] = 90000, [3] = 5000, [4] = 0}
local present = {[1] = true, [2] = true, [3] = true, [4] = true}
local won = B.rewarded(dmg, {[4] = true}, present, cfg)
ok(won[1] and won[2], "damage dealers")
ok(not won[3], "under 1% of the damage")
ok(won[4], "a healer")
ok(not B.rewarded(dmg, {}, {[1] = true}, cfg)[2], "absent players get nothing")
-- the gold pool of a kill and its split by contribution
eq(B.goldPool(1, cfg), 250000, "pool of one rewarded participant")
eq(B.goldPool(5, cfg), 1250000, "pool of 5")
eq(B.goldPool(10, cfg), 2500000, "pool of 10")
eq(B.goldPool(20, cfg), 2500000, "pool capped at 10 participants")
-- a net gold sink: the largest pool is at most half of the cheapest stone's fuel in gold (guild level 1)
ok(B.goldPool(cfg.reward.pool.maxPlayers, cfg) <= 0.5 * B.need(1, cfg) * cfg.gold.perEmber, "the pool is at most 50% of the fuel")
local orbs = {}
for _, o in ipairs(cfg.reward.orbs) do
	orbs[o.id] = o.count
end
eq(orbs[29856], 3, "3 Orbs of Upheaval each")
eq(orbs[29857], 1, "1 Orb of Fate each")
eq(B.goldPool(0, cfg), 0, "no winners, no pool")
local function sum(t)
	local n = 0
	for _, v in pairs(t) do
		n = n + v
	end
	return n
end
-- single participant: all of it
local sh = B.splitGold(1500000, {[7] = true}, {[7] = 650000}, {}, cfg)
eq(sh[7], 1500000, "a single participant gets the whole pool")
sh = B.splitGold(1500000, {[7] = true}, {}, {}, cfg)
eq(sh[7], 1500000, "a single participant without damage too")
-- proportionality and the floor
local pool5 = B.goldPool(5, cfg)
local winners5 = {[1] = true, [2] = true, [3] = true, [4] = true, [5] = true}
local dmg5 = {[1] = 400000, [2] = 200000, [3] = 100000, [4] = 100000, [5] = 0}
local heal5 = {[5] = 200000}
local list5
sh, list5 = B.splitGold(pool5, winners5, dmg5, heal5, cfg)
eq(sum(sh), pool5, "the shares sum to the pool")
local floorGold = math.floor(pool5 * cfg.reward.floorShare / 5)
eq(floorGold, 62500, "the floor of a 5-player kill")
for guid in pairs(winners5) do
	ok(sh[guid] >= floorGold, "every winner gets at least the floor")
end
eq(sh[3], sh[4], "equal contribution, equal share")
eq(sh[2] - floorGold, 2 * (sh[3] - floorGold), "twice the contribution, twice the variable part")
eq(sh[2], sh[5], "healing counts like damage")
ok(sh[1] > sh[2] and sh[2] > sh[3], "more contribution, more gold")
eq(list5[1].guid, 1, "the top contributor first")
eq(sh[1], floorGold + (pool5 - 5 * floorGold) * 4 / 10, "the top share: floor + 40% of the rest")
-- the minimum share: a winner with no contribution at all still gets the floor
sh = B.splitGold(pool5, winners5, {[1] = 10 ^ 9}, {}, cfg)
eq(sh[2], floorGold, "no contribution: exactly the floor")
eq(sh[1], pool5 - 4 * floorGold, "the rest to the only contributor")
-- rounding: an awkward pool and weights, the remainder to the top contributor
local w3 = {[11] = true, [12] = true, [13] = true}
sh = B.splitGold(1000001, w3, {[11] = 1, [12] = 1, [13] = 1}, {}, cfg)
eq(sum(sh), 1000001, "the shares sum to an odd pool exactly")
eq(sh[11], sh[12] + 2, "the rounding remainder to the top contributor (lowest guid on a tie)")
eq(sh[12], sh[13], "the others round down evenly")
sh = B.splitGold(7777777, w3, {[11] = 333, [12] = 777, [13] = 1}, {[13] = 5}, cfg)
eq(sum(sh), 7777777, "uneven weights sum exactly")
ok(sh[12] > sh[11] and sh[11] > sh[13], "order of the shares")
math.randomseed(70)
for _ = 1, 200 do
	local n = math.random(1, 20)
	local w, d, h = {}, {}, {}
	for i = 1, n do
		w[i] = true
		d[i] = math.random(0, 3) == 0 and 0 or math.random(1, 2000000)
		h[i] = math.random(0, 2) == 0 and math.random(1, 300000) or nil
	end
	local p = B.goldPool(n, cfg) + math.random(0, 99)
	local s2 = B.splitGold(p, w, d, h, cfg)
	eq(sum(s2), p, "random split sums to the pool")
	for i = 1, n do
		ok(s2[i] >= math.floor(p * cfg.reward.floorShare / n), "random split keeps the floor")
	end
end
eq(next((B.splitGold(1000, {}, {}, {}, cfg))), nil, "no winners, no shares")
eq(B.gxp(5, cfg), 500, "guild XP of 5")
eq(B.gxp(40, cfg), cfg.gxp.max, "guild XP capped")
local tier, name, nextAt = B.banner(0, cfg)
eq(tier, 0, "no banner")
eq(nextAt, 1, "first at 1 kill")
tier, name, nextAt = B.banner(4, cfg)
eq(tier, 2, "tier 2 at 4 kills")
eq(name, "Cinder Banner", "its name")
eq(nextAt, 10, "next at 10")
tier, name, nextAt = B.banner(99, cfg)
eq(tier, #cfg.banners, "the top tier")
eq(nextAt, nil, "nothing after the top")
local board = B.rankGuilds({{id = 1, killed = false, damage = 9 * 10 ^ 6}, {id = 2, killed = true, seconds = 500, damage = 1},
	{id = 3, killed = true, seconds = 420, damage = 1}, {id = 4, killed = false, damage = 10 ^ 6}})
eq(board[1].id, 3, "fastest kill first")
eq(board[2].id, 2, "then the slower kill")
eq(board[3].id, 1, "then the most damage")
eq(board[4].rank, 4, "ranks")
eq(B.clockText(421), "7:01", "clock")
eq(B.money(1500000), "1,500,000", "money")

-- ---------------------------------------------------------------- the arena grid
local g = cfg.grid
local cells = {}
for slot = 1, g.slots do
	local L = U.layout(cfg, slot)
	local col, row = (slot - 1) % g.cols, math.floor((slot - 1) / g.cols)
	local x1, y1 = g.origin.x + col * g.spacing, g.origin.y + row * g.spacing
	for _, list in ipairs({L.floorList, L.anteList, L.wallList}) do
		for _, t in ipairs(list) do
			ok(t.x >= x1 and t.x < x1 + g.spacing and t.y >= y1 and t.y < y1 + g.spacing, "slot " .. slot .. " inside its cell")
		end
	end
	eq(U.slotAt(cfg, L.center), slot, "slotAt of slot " .. slot)
	ok(U.inArena(L, L.bossSpawn) and U.inArena(L, L.entry) and U.inAnte(L, L.portal), "spawn, entry and gate")
	cells[#cells + 1] = L
end
local box = {x1 = g.origin.x, y1 = g.origin.y, x2 = g.origin.x + g.cols * g.spacing - 1,
	y2 = g.origin.y + math.ceil(g.slots / g.cols) * g.spacing - 1}
local function grid(c)
	local rows = c.rows or math.ceil((c.slots or c.maxSlots or c.cols) / c.cols)
	return {x1 = c.origin.x, y1 = c.origin.y, x2 = c.origin.x + c.cols * c.spacing - 1, y2 = c.origin.y + rows * c.spacing - 1}
end
local others = {
	rift = grid(dofile("data/scripts/chaos/rift_config.lua").grid),
	raid = grid(dofile("data/scripts/chaos/raid_config.lua").grid),
	descent = grid(dofile("data/scripts/chaos/descent_config.lua").grid),
	ascended = grid(dofile("data/scripts/chaos/uber_config.lua").grid),
	trials = grid(dofile("data/scripts/chaos/trials_config.lua").room.grid),
	arena = grid(dofile("data/scripts/chaos/arena_config.lua").grid),
	ascension = grid(dofile("data/scripts/chaos/ascension_quest_config.lua").trial.grid),
	halls = {x1 = gcfg.hall.origin.x, y1 = gcfg.hall.origin.y, x2 = gcfg.hall.origin.x + gcfg.hall.columns * gcfg.hall.stride - 1,
		y2 = gcfg.hall.origin.y + math.ceil(gcfg.hall.maxSlots / gcfg.hall.columns) * gcfg.hall.stride - 1}
}
-- the grids of systems that may not be installed (read when their config is there)
for _, f in ipairs({"battleground_config.lua", "hideout_config.lua"}) do
	local h = io.open("data/scripts/chaos/" .. f)
	if h then
		h:close()
		local okc, c = pcall(dofile, "data/scripts/chaos/" .. f)
		local gr = okc and type(c) == "table" and (c.grid or (c.map and c.map.grid)) or nil
		if gr and gr.origin and gr.cols and gr.spacing then
			others[f] = grid(gr)
		end
	end
end
for k, o in pairs(others) do
	local apart = box.x2 < o.x1 or o.x2 < box.x1 or box.y2 < o.y1 or o.y2 < box.y1
	ok(apart, "the guild boss grid is clear of " .. k)
end
ok(box.x1 >= 3000 and box.x2 <= 16000 and box.y1 >= 3000 and box.y2 <= 16000, "within the empty map area")
eq(box.x1, 11264, "x from 11264")
eq(box.x2, 11455, "x to 11455")
eq(box.y2, 10095, "y to 10095")

-- the stone in the guild hall: on the floor, on no other fixture
local L = ChaosGuildCore.layout(1, gcfg)
local stone = {x = L.origin.x + L.w - 1, y = L.origin.y + 11}
ok(stone.x > L.box.x1 and stone.x < L.box.x2 and stone.y > L.box.y1 and stone.y < L.box.y2, "the stone inside the walls")
local taken = {L.exit, L.arrival, L.bench, L.depot, L.dummyMonster}
for _, list in ipairs({L.hub, L.dummies, L.trophies, L.basins, L.flags}) do
	for _, p in ipairs(list) do
		taken[#taken + 1] = p
	end
end
for _, p in ipairs(taken) do
	ok(not (p.x == stone.x and p.y == stone.y), "the stone is not on a fixture")
end

-- ====================================================================== guildboss.lua against a mocked engine
local NOW = monday + 3 * 86400
os.time = (function(orig)
	return function(t)
		if t then
			return orig(t)
		end
		return NOW
	end
end)(os.time)
os.mtime = function() return NOW * 1000 end
local registry = {}
local function event(kind)
	return function(name)
		local ev = {name = name}
		function ev.register() registry[name or kind] = ev end
		function ev.interval() end
		function ev.separator() end
		function ev.aid() end
		function ev.type() end
		return ev
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = event("c"), event("g"), event("t"), event("a"), event("m")
MESSAGE_INFO_DESCR, MESSAGE_STATUS_SMALL, MESSAGE_EVENT_ADVANCE, CONST_ME_TELEPORT = 1, 2, 3, 4
local events = {}
function addEvent(fn, ms, ...)
	events[#events + 1] = {fn = fn, ms = ms, args = {...}}
end
function Position(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
Tile = function() return nil end
ItemType = function(id) return {getId = function() return id end, getClientId = function() return id end,
	getName = function() return "item" end, getPluralName = function() return "items" end} end
Game = {createTile = function() return {getGround = function() return nil end} end, createItem = function()
	return {setActionId = function() end, setAttribute = function() end} end, getPlayers = function() return {} end,
	broadcastMessage = function() end}
-- database
local WEEK = {}
local SPOILS = {}
local guildLog = {}
local lastExec
db = {escapeString = function(s) return "'" .. tostring(s) .. "'" end, asyncQuery = function() return true end}
function db.query(q)
	local gid, wk, fuel = q:match("VALUES %((%d+), (%d+), (%d+), %d+%) ON DUPLICATE KEY UPDATE `fuel`")
	if gid then
		local key = gid .. ":" .. wk
		WEEK[key] = WEEK[key] or {fuel = 0, attempts = 0, killed_at = 0, best_seconds = 0, damage = 0, players = 0}
		WEEK[key].fuel = WEEK[key].fuel + tonumber(fuel)
		return true
	end
	local keep, gid2, wk2 = q:match("UPDATE `chaos_guildboss_week` SET `fuel` = `fuel` %+ (%d+), `damage`.-WHERE `guild_id` = (%d+) AND `week` = (%d+)")
	if keep then
		local r = WEEK[gid2 .. ":" .. wk2]
		r.fuel = r.fuel + tonumber(keep)
		return true
	end
	local pool, gidp, wkp = q:match("UPDATE `chaos_guildboss_week` SET `pool` = (%d+) WHERE `guild_id` = (%d+) AND `week` = (%d+)")
	if pool then
		WEEK[gidp .. ":" .. wkp].pool = tonumber(pool)
		return true
	end
	local spoilPid, spoils = q:match("INSERT INTO `chaos_guildboss_contrib` %(.-`spoils`.-VALUES %(%d+, %d+, (%d+), '[^']*', (%d+),")
	if spoilPid then
		SPOILS[tonumber(spoilPid)] = tonumber(spoils)
		return true
	end
	local killed, gid3, wk3 = q:match("UPDATE `chaos_guildboss_week` SET `killed_at` = (%d+).-WHERE `guild_id` = (%d+) AND `week` = (%d+)")
	if killed then
		WEEK[gid3 .. ":" .. wk3].killed_at = tonumber(killed)
	end
	return true
end
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.select = function(q)
	local gid, wk = q:match("FROM `chaos_guildboss_week` WHERE `guild_id` = (%d+) AND `week` = (%d+)")
	if gid then
		local r = WEEK[gid .. ":" .. wk]
		return r and {{fuel = r.fuel, attempts = r.attempts, killed_at = r.killed_at, best_seconds = r.best_seconds, damage = r.damage,
			players = r.players, pool = r.pool}} or {}
	end
	return {}
end
Chaos.send = function() return true end
Chaos.giveItem = function(player, id, n) return n end
-- the guild system
local members = {}
local bankPaid = 0
ChaosGuild = {
	nameOf = function() return "Ashen Wolves" end,
	levelOf = function() return 10 end,
	hallOf = function(gid) return gid == 4 and {slot = 1, upgrades = {}} or nil end,
	rentStateOf = function() return "paid" end,
	inHall = function(pos) return pos.hall and 1 or nil, pos.hall and 4 or nil end,
	onlineMembers = function() return members end,
	tellGuild = function() end,
	logRow = function(gid, who, action, amount, _, _, text) guildLog[#guildLog + 1] = {action = action, amount = amount, text = text} end,
	addStat = function() end,
	addXp = function() end,
	payFromPlayer = function(player, n)
		if player.money < n then
			return false
		end
		player.money = player.money - n
		bankPaid = bankPaid + n
		return true
	end,
	exec = function(q)
		lastExec = q
		local need, gid, wk, need2, max = q:match("SET `fuel` = `fuel` %- (%d+), `attempts` = `attempts` %+ 1.-WHERE `guild_id` = (%d+) " ..
			"AND `week` = (%d+) AND `fuel` >= (%d+) AND `killed_at` = 0 AND `attempts` < (%d+)")
		local r = gid and WEEK[gid .. ":" .. wk]
		if r and r.fuel >= tonumber(need2) and r.killed_at == 0 and r.attempts < tonumber(max) then
			r.fuel = r.fuel - tonumber(need)
			r.attempts = r.attempts + 1
			return 1
		end
		return 0
	end
}
function ChaosGuild.guildOf(player)
	return player.gid, "Ashen Wolves", player.rank
end
local function member(id, rank, level, money)
	local p = {id = id, gid = 4, rank = rank, level = level, money = money, pos = {x = 9230, y = 9230, z = 7, hall = true, sendMagicEffect = function() end}, msgs = {},
		events = {}, items = {}}
	function p:getId() return self.id end
	function p:getGuid() return 1000 + self.id end
	function p:getName() return "M" .. self.id end
	function p:getLevel() return self.level end
	function p:getPosition() return self.pos end
	function p:teleportTo(pos) self.pos = pos end
	function p:registerEvent(e) self.events[e] = true end
	function p:unregisterEvent(e) self.events[e] = nil end
	function p:removeCondition() end
	function p:getTown() return {getTemplePosition = function() return Position(100, 100, 7) end} end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:getItemCount(id) return self.items[id] or 0 end
	function p:removeItem(id, n) self.items[id] = (self.items[id] or 0) - n return true end
	function p:addItem(id, n) self.items[id] = (self.items[id] or 0) + n return true end
	function p:save() return not self.saveFails end
	function p:setStorageValue(k, v) self.storage = v end
	p.bank, p.hp, p.maxHp = 0, 1000, 1000
	function p:isPlayer() return true end
	function p:getHealth() return self.hp end
	function p:getMaxHealth() return self.maxHp end
	function p:getBankBalance() return self.bank end
	function p:setBankBalance(v) self.bank = v end
	function p:getInbox() return nil end
	members[#members + 1] = p
	return p
end
local leader = member(1, 3, 500, 100000000)
local m2 = member(2, 1, 400, 0)
local m3 = member(3, 1, 100, 0) -- under minLevel: stays behind
Player = function(id)
	for _, p in ipairs(members) do
		if p.id == id then
			return p
		end
	end
end
Chaos.guildBossConfig = nil
dofile("data/scripts/chaos/guildboss.lua")
local GB = ChaosGuildBoss
Chaos.guildBossConfig.darkActive = false
local week = B.weekKey(cfg, NOW)
local key = "4:" .. week

-- donations: gold (whole embers) and materials
-- the character is saved before the fuel row is credited; a failed save gives the gold back and credits nothing
leader.saveFails = true
local bankBefore = leader.bank
local okd, text = GB.handle(leader, "bossGold", {amount = 5000000})
eq(okd, false, "no donation when the save fails")
eq(WEEK[key] == nil or WEEK[key].fuel == 0, true, "no fuel credited without a save")
eq(leader.bank, (bankBefore or 0) + 5000000, "the gold went back to the bank balance")
leader.money, leader.bank, bankPaid = leader.money + 5000000, bankBefore, 0
leader.items[29857] = 4
eq((GB.handle(leader, "bossItem", {key = "fate"})), false, "no material donation when the save fails")
eq(leader.items[29857], 4, "the orbs are given back")
leader.items[29857] = nil
leader.saveFails = false
NOW = NOW + 2
okd, text = GB.handle(leader, "bossGold", {amount = 5000000})
eq(okd, true, "gold donation: " .. tostring(text))
eq(WEEK[key].fuel, 500, "5,000,000 gold = 500 embers")
eq(bankPaid, 5000000, "the gold is paid (a sink)")
leader.items[29857] = 4
NOW = NOW + 2
okd = GB.handle(leader, "bossItem", {key = "fate"})
eq(okd, true, "material donation")
eq(WEEK[key].fuel, 600, "4 Orbs of Fate = 100 embers")
eq(leader.items[29857], 0, "the orbs are taken")
NOW = NOW + 2
eq((GB.handle(m2, "bossGold", {amount = 1000000})), false, "a member without gold")
NOW = NOW + 2
eq((GB.handle(leader, "bossSummon", {})), false, "not enough fuel (600 of 750)")
GB.handle(leader, "bossGold", {amount = 2000000})
eq(WEEK[key].fuel, 800, "800 embers")
NOW = NOW + 2
eq((GB.handle(m2, "bossSummon", {})), false, "a member cannot summon")

-- the summon: the need leaves the stone in one conditional UPDATE, the members in the hall come along
NOW = NOW + 2
okd, text = GB.handle(leader, "bossSummon", {})
eq(okd, true, "summoned: " .. tostring(text))
eq(WEEK[key].fuel, 50, "800 - 750 embers")
eq(WEEK[key].attempts, 1, "one attempt")
ok(lastExec:find("`killed_at` = 0") and lastExec:find("`attempts` < " .. cfg.maxAttempts), "the conditional UPDATE")
ok(GB.isInside(leader) and GB.isInside(m2), "both in the arena")
ok(not GB.isInside(m3), "the low level member stays")
local run = GB.guildRun[4]
eq(run.size, 2, "two players")
eq(run.lives, B.livesFor(cfg, 2), "lives")
ok(U.slotAt(cfg, leader.pos), "the leader stands in a guild boss slot")
NOW = NOW + 2
eq((GB.handle(leader, "bossSummon", {})), false, "no second summon while the run lasts")

-- a failed attempt keeps half of the need
GB._fail(run, "Test.")
eq(WEEK[key].fuel, 50 + 375, "half of the need back")
eq(GB.guildRun[4], nil, "the run is over")
ok(not GB.isInside(leader), "everyone left")

-- a kill: one gold pool, split by contribution, to each rewarded member's bank; orbs each; the split persisted
WEEK[key].fuel = 800
NOW = NOW + 2
okd, text = GB.handle(leader, "bossSummon", {})
eq(okd, true, "second summon: " .. tostring(text))
run = GB.guildRun[4]
run.damage[leader:getGuid()] = 600000
run.damage[m2:getGuid()] = 200000
leader.hp = 400
GB._countHealing(leader, m2, 999999)
eq(run.healing[m2:getGuid()], 600, "healing counts the missing health only")
GB._countHealing(m2, m2, 500)
eq(run.healing[m2:getGuid()], 600, "healing oneself does not count")
eq(run.healing[leader:getGuid()], nil, "no healing from the leader")
leader.hp = 1000
run.healing[m2:getGuid()] = 100000
leader.msgs, m2.msgs = {}, {}
GB._success(run)
local pool2 = B.goldPool(2, cfg)
eq(WEEK[key].pool, pool2, "the pool is kept in the week row")
local sh2 = B.splitGold(pool2, {[leader:getGuid()] = true, [m2:getGuid()] = true},
	{[leader:getGuid()] = 600000, [m2:getGuid()] = 200000}, {[m2:getGuid()] = 100000}, cfg)
eq(leader.bank, sh2[leader:getGuid()], "the leader's share to the bank")
eq(m2.bank, sh2[m2:getGuid()], "the healer's share to the bank")
eq(leader.bank + m2.bank, pool2, "the bank credits sum to the pool")
ok(leader.bank > m2.bank, "more contribution, more gold")
eq(SPOILS[leader:getGuid()], leader.bank, "the leader's share persisted")
eq(SPOILS[m2:getGuid()], m2.bank, "the healer's share persisted")
local logged = 0
for _, row in ipairs(guildLog) do
	if row.action == "boss" and row.text:find("share of the guild boss gold") then
		logged = logged + row.amount
	end
end
eq(logged, pool2, "the guild log holds the split")
local spoilMsg
for _, t in ipairs(leader.msgs) do
	if t:find("Spoils of the guild boss") then
		spoilMsg = t
	end
end
ok(spoilMsg and spoilMsg:find(B.money(leader.bank), 1, true) and spoilMsg:find(B.money(pool2), 1, true), "the kill message shows the share and the pool")
ok(spoilMsg:find("Orbs", 1, true) or spoilMsg:find("items", 1, true), "orbs still given")
eq(WEEK[key].killed_at, NOW, "killed this week")
local v = GB.view(leader)
eq(v.pool, pool2, "the view carries the pool")
-- the exit after the kill: everyone back in the hall
local exitEv = events[#events]
eq(exitEv.ms, cfg.exitDelay * 1000, "the exit is queued")
exitEv.fn((table.unpack or unpack)(exitEv.args))
ok(not GB.isInside(leader) and GB.guildRun[4] == nil, "everyone left after the kill")

-- the lockout: once the guild killed it this week, no summon and no more donations
WEEK[key].killed_at = NOW
WEEK[key].fuel = 5000
NOW = NOW + 2
local okk, why = GB.handle(leader, "bossSummon", {})
eq(okk, false, "locked out")
ok(why:find("already slew"), "lockout text")
NOW = NOW + 2
eq((GB.handle(leader, "bossGold", {amount = 1000000})), false, "no donations after the kill")
GB.syncLockout(leader)
eq(leader.storage, B.nextReset(cfg, NOW), "the Boss Spawns cooldown: the next reset")
-- next week: a new row, the lockout is gone
NOW = NOW + 7 * 86400
GB.syncLockout(leader)
eq(leader.storage, 0, "no lockout next week")
eq(GB.weekRow(4).killed_at, 0, "a fresh week")

-- instance limits (instance_limits.lua): warnings before the limit, the staff list and close (a
-- failed attempt: half of the need stays as fuel)
do
	dofile("data/scripts/chaos/instance_limits.lua")
	local week2 = B.weekKey(cfg, NOW)
	local key2 = "4:" .. week2
	if not WEEK[key2] then
		local row = {}
		for k, v in pairs(WEEK[key]) do row[k] = v end
		row.attempts, row.killed_at, row.pool = 0, 0, 0
		WEEK[key2] = row
	end
	WEEK[key2].fuel = 800
	NOW = NOW + 2
	local oks, why2 = GB.handle(leader, "bossSummon", {})
	eq(oks, true, "limits: summoned: " .. tostring(why2))
	local r = GB.guildRun[4]
	local gcfg = Chaos.guildBossConfig
	local limit = gcfg.boss.limit
	gcfg.boss.limit = 290
	r.bossDueAt = os.mtime() + 11000
	GB._tick(r.slot, r.id)
	r.bossDueAt = os.mtime() + 10000
	leader.msgs = {}
	GB._tick(r.slot, r.id)
	local warned = false
	for _, t in ipairs(leader.msgs) do
		if t:find(gcfg.boss.boss .. ": 5 minutes left", 1, true) then warned = true end
	end
	ok(warned, "limits: the 5 minute warning")
	gcfg.boss.limit = limit
	local found
	for _, x in ipairs(ChaosInstanceLimits.runs()) do
		if x.key == "guildboss" then found = x end
	end
	ok(found and found.id == r.id and found.players == 2, "limits: listed")
	local fuel = WEEK[key2].fuel
	local okc = Chaos.instances.guildboss.close(r.id)
	ok(okc and r.state == "failed" and GB.guildRun[4] == nil, "limits: a staff close fails the attempt")
	eq(WEEK[key2].fuel, fuel + B.fuelAfterFail(0, r.need, cfg), "limits: half of the need stays (the failure rule)")
end

print(string.format("guildboss_test: %d checks OK", checks))
