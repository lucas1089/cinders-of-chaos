-- Run from the server/ folder: luajit tests/professions_test.lua (and lua5.3; CI runs both)
-- Professions: the pure rules (professions_core.lua: config check, the level curve, tiers, yields, the experience bonus
-- and its cap, the weekly demand (deterministic, the same numbers under both interpreters), the broker's daily
-- diminishing price and cap, the gold per hour bound against hunting, node spots, fishing places) and the engine part
-- (professions.lua) against a mocked engine: a node gather with its channel, the per-player node cooldown, moving and
-- damage interrupting, flaying a tagged corpse, the angling roll, selling at the broker (and not away from it), Sell All,
-- the experience bonus on monster experience only, the buff bar entry, achievements and the weekly board.

local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end
local function has(text, part, label)
	check(type(text) == "string" and text:find(part, 1, true) ~= nil, label .. " (" .. tostring(text) .. ")")
end

local cfg = dofile("data/scripts/chaos/professions_config.lua")
dofile("data/scripts/chaos/professions_core.lua")
local K = ChaosProfessionsCore
local idx = K.index(cfg)

-- ---------------------------------------------------------------- config
local errors = K.validate(cfg)
eq(#errors, 0, "config valid: " .. table.concat(errors, "; "))
eq(cfg.opcode, 195, "opcode")
eq(#cfg.professions, 4, "four professions")
eq(#cfg.materials, 4 * #cfg.tiers, "a material per profession and tier")
for _, m in ipairs(cfg.materials) do
	check(m.id >= 32351 and m.id <= 32370, "material id range " .. m.id)
	check(m.description:find("Material Broker", 1, true) ~= nil, "material text names the broker " .. m.id)
end
for _, n in ipairs(cfg.nodes) do
	check(n.id >= 32371 and n.id <= 32399, "node id range " .. n.id)
	check(n.prof == "delving" or n.prof == "wortcunning", "nodes only for the node professions " .. n.id)
end
do
	local bad = dofile("data/scripts/chaos/professions_config.lua")
	bad.tiers[3].price = 10 -- cheaper than tier 2
	bad.materials[2].id = bad.materials[1].id -- twice
	bad.demand.slots = {1, 1}
	check(#K.validate(bad) >= 3, "a broken config is reported (" .. #K.validate(bad) .. ")")
end
-- the owner's rule: nothing in the professions makes gear or orbs (no crafting outputs, no orb ids)
for _, m in ipairs(cfg.materials) do
	check(m.id ~= 29856 and m.id ~= 29857 and m.id ~= 29855, "no orb among the materials")
end

-- ---------------------------------------------------------------- the level curve
eq(K.xpNeed(cfg, 1), 38, "level 1 -> 2 needs 38")
eq(K.xpNeed(cfg, 99), 30 + 8 * 99 + math.floor(0.45 * 99 * 99), "level 99 -> 100")
eq(K.xpNeed(cfg, 100), nil, "nothing past 100")
for l = 2, 99 do
	check(K.xpNeed(cfg, l) > K.xpNeed(cfg, l - 1), "the curve rises at " .. l)
end
local total = K.totalXp(cfg, 100)
check(total > 150000 and total < 250000, "total to 100: " .. total)
do
	local e = {level = 1, xp = 0}
	eq(K.addXp(cfg, e, 37), 0, "not yet")
	eq(K.addXp(cfg, e, 1), 1, "level 2")
	eq(e.xp, 0, "rest 0")
	eq(K.addXp(cfg, e, K.xpNeed(cfg, 2) + K.xpNeed(cfg, 3) + 5), 2, "two levels at once")
	eq(e.level, 4, "level 4")
	eq(e.xp, 5, "rest kept")
	eq(K.addXp(cfg, e, 10 ^ 9), 96, "to the cap")
	eq(e.level, 100, "level 100")
	eq(e.xp, 0, "no experience past the cap")
	eq(K.addXp(cfg, e, 500), 0, "nothing more at 100")
	eq(K.percent(cfg, e), 100, "full bar at 100")
	eq(K.percent(cfg, {level = 1, xp = 19}), 50, "half way")
end

-- ---------------------------------------------------------------- tiers and yields
eq(K.profTier(cfg, 1), 1, "profession 1: tier 1")
eq(K.profTier(cfg, 39), 2, "profession 39: tier 2")
eq(K.profTier(cfg, 100), 5, "profession 100: tier 5")
eq(K.charTier(cfg, 1), 1, "a level 1 character gathers tier 1")
eq(K.charTier(cfg, 250), 4, "level 250: tier 4")
eq(K.gatherTier(cfg, 5, 100, 120), 3, "the character level caps the tier")
eq(K.gatherTier(cfg, 5, 45, 900), 3, "the profession level caps the tier")
eq(K.gatherTier(cfg, 2, 100, 900), 2, "the place caps the tier")
eq(K.gatherXp(cfg, 3, 45), 30, "a gather at the own tier: full experience")
eq(K.gatherXp(cfg, 2, 45), math.floor(18 * 0.6 + 0.5), "one tier below: x0.6")
eq(K.gatherXp(cfg, 1, 45), math.floor(10 * 0.25 + 0.5), "two tiers below: x0.25")
eq(K.extraChance(cfg, 1, 1), 0, "no extra at the tier's own level")
eq(K.extraChance(cfg, 1, 100), cfg.yield.extraMax, "extra chance capped")
check(math.abs(K.avgYield(cfg, 5, 100) - 1.23) < 1e-9, "average yield at tier 5 with 100: 1.23")
do
	local seq = {0.0, 0.0}
	local i = 0
	local function fixed()
		i = i + 1
		return seq[i] or 0.99
	end
	eq(K.yieldCount(cfg, 1, 100, fixed), 3, "extra and lucky: 3")
	i, seq = 0, {0.99, 0.99}
	eq(K.yieldCount(cfg, 1, 100, fixed), 1, "neither: 1")
	i, seq = 0, {0.5}
	local r = K.resolve(cfg, idx, {prof = "flaying", placeTier = 2, profLevel = 30, charLevel = 60, chance = 0.4}, fixed)
	eq(r.count, 0, "a flay can miss")
	eq(r.xp, math.floor(K.gatherXp(cfg, 2, 30) / 2), "a miss gives half the experience")
	i, seq = 0, {0.1, 0.99, 0.99}
	r = K.resolve(cfg, idx, {prof = "flaying", placeTier = 2, profLevel = 30, charLevel = 60, chance = 0.4}, fixed)
	eq(r.count, 1, "a hit gives a hide")
	eq(r.mat.id, 32362, "the tier 2 hide")
end
eq(K.charXp(cfg, 8), math.floor((K.expForLevel(9) - K.expForLevel(8)) * cfg.charXpShare), "character experience is small")
eq(K.expForLevel(1), 0, "stock level 1")
eq(K.expForLevel(2), 100, "stock level 2")
check(K.charXp(cfg, 500) < (K.expForLevel(501) - K.expForLevel(500)) / 500, "a gather is far below a level")

-- ---------------------------------------------------------------- the experience bonus and its cap
eq(K.bonusPct(cfg, {delving = 1, wortcunning = 1, flaying = 1, angling = 1}), 0, "a new character: +0%")
eq(K.bonusPct(cfg, {delving = 11, wortcunning = 1, flaying = 1, angling = 1}), 0.25, "10 levels: +0.25%")
eq(K.bonusPct(cfg, {delving = 50, wortcunning = 50, flaying = 50, angling = 50}), 4.96, "all at 50: +4.96%")
eq(K.bonusPct(cfg, {delving = 100, wortcunning = 100, flaying = 100, angling = 100}), 10, "all at 100: the cap +10%")
eq(K.bonusPct(cfg, {delving = 100, wortcunning = 100, flaying = 100, angling = 99}), 9.99, "395 levels: just below the cap")
check(K.bonusPct(cfg, {delving = 100, wortcunning = 100, flaying = 100, angling = 90}) < 10, "below the cap until the end")
eq(K.bonusPct(cfg, 10000), cfg.bonus.cap, "never above the cap")
eq(K.applyBonus(1000, 10), 1100, "+10% of 1000")
eq(K.applyBonus(1000, 0), 1000, "no bonus")
eq(K.applyBonus(999, 2.53), 1024, "rounded down")

-- ---------------------------------------------------------------- weekly demand: deterministic
local w1 = 20261005
local d1, d2 = K.demand(cfg, w1), K.demand(cfg, w1)
local changed = false
local d3 = K.demand(cfg, 20261012)
for _, m in ipairs(cfg.materials) do
	eq(d1[m.id], d2[m.id], "same week, same demand " .. m.id)
	if d3[m.id] ~= d1[m.id] then
		changed = true
	end
end
check(changed, "another week, another demand")
for _, p in ipairs(cfg.professions) do
	local got = {}
	for t = 1, #cfg.tiers do
		got[#got + 1] = d1[idx.matOf[p.key][t].id]
	end
	table.sort(got)
	local want = {}
	for i, v in ipairs(cfg.demand.slots) do
		want[i] = v
	end
	table.sort(want)
	eq(table.concat(got, ","), table.concat(want, ","), "every slot once for " .. p.key)
end
-- the exact draw of one week: the same under LuaJIT and Lua 5.3 (CI runs both)
local expect = {
	[32351] = 1, [32352] = 0.75, [32353] = 1, [32354] = 1.25, [32355] = 1.5,
	[32356] = 1.25, [32357] = 1, [32358] = 0.75, [32359] = 1, [32360] = 1.5,
	[32361] = 1, [32362] = 0.75, [32363] = 1.5, [32364] = 1.25, [32365] = 1,
	[32366] = 1.25, [32367] = 0.75, [32368] = 1.5, [32369] = 1, [32370] = 1
}
for id, v in pairs(expect) do
	eq(d1[id], v, "demand of week " .. w1 .. " for " .. id)
end
-- weeks and days
local t0 = os.time({year = 2026, month = 10, day = 11, hour = 12}) -- a Sunday
eq(K.week(t0, 6), 20261005, "the week of a Sunday starts on its Monday")
eq(K.week(os.time({year = 2026, month = 10, day = 12, hour = 5}), 6), 20261005, "Monday before the roll hour: last week")
eq(K.week(os.time({year = 2026, month = 10, day = 12, hour = 7}), 6), 20261012, "Monday after the roll hour: new week")
eq(K.day(os.time({year = 2026, month = 10, day = 12, hour = 5}), 6), 20261011, "before the roll hour: yesterday")
eq(K.nextWeek(t0, 6) - t0, 18 * 3600, "next week 18 hours after Sunday noon")

-- ---------------------------------------------------------------- prices and the daily cap
local ash = idx.mat[32351]
eq(K.unitPrice(cfg, ash, 1), 20, "base price")
eq(K.unitPrice(cfg, ash, 1.5), 30, "demand x1.5")
eq(K.latePrice(cfg, ash, 1.5), 15, "late price half")
local q = K.quote(cfg, ash, 1, 0, 50)
eq(q.units, 50, "50 sold")
eq(q.gold, 1000, "50 at full price")
q = K.quote(cfg, ash, 1, 90, 30)
eq(q.full, 10, "10 at full price")
eq(q.late, 20, "20 at the late price")
eq(q.gold, 10 * 20 + 20 * 10, "full then late")
q = K.quote(cfg, ash, 1, 190, 30)
eq(q.units, 10, "only up to the cap")
eq(q.left, 0, "nothing left today")
eq(K.quote(cfg, ash, 1, 200, 5).units, 0, "the cap is reached")
eq(K.dailyMax(cfg, ash), 100 * 30 + 100 * 15, "the most a day of ashstone ore pays")
for _, m in ipairs(cfg.materials) do
	local tier = cfg.tiers[m.tier]
	-- one material's best day stays below an hour of hunting at the tier's level
	check(K.dailyMax(cfg, m) < K.huntIncome(cfg, tier.charLevel), "a day of " .. m.name .. " < an hour of hunting")
end

-- ---------------------------------------------------------------- gold per hour against hunting
eq(K.huntIncome(cfg, 100), 358839, "hunting at 100 (README Respec)")
eq(K.huntIncome(cfg, 200), 358839 + (881866 - 358839) * 0.5, "linear between the points")
eq(K.huntIncome(cfg, 1), 19000, "below the first point")
local worst = 0
for _, r in ipairs(K.balance(cfg)) do
	check(r.gold > 0, "a profession pays at " .. r.prof .. " tier " .. r.tier)
	check(r.share < cfg.balance.maxShare, string.format("%s tier %d: %.0f gold/h is below %.0f%% of hunting (%.0f)", r.prof,
		r.tier, r.gold, cfg.balance.maxShare * 100, r.hunt))
	check(r.gold < r.hunt, "below hunting " .. r.prof .. " " .. r.tier)
	worst = math.max(worst, r.share)
end
check(worst > 0.05, "the professions are worth something (best share " .. worst .. ")")
-- the node professions are bounded by the nodes: 6 minutes per node and character
eq(K.gathersPerHour(cfg, "delving", 1), 100, "10 nodes, 6 minutes: 100 gathers an hour")
eq(K.gathersPerHour(cfg, "angling", 1), 120, "angling: 1200 rolls, 10%")

-- ---------------------------------------------------------------- places
do
	local area = {key = "t", tier = 2, center = {x = 100, y = 100, z = 7}, r = 10, nodes = {delving = 6, wortcunning = 4},
		pos = {delving = {{x = 100, y = 100}}}}
	local free = function(x, y, z) return (x + y) % 3 ~= 0 end
	local a = K.pickSpots(area, cfg, free, K.rng(K.seedOf("t")))
	local b = K.pickSpots(area, cfg, free, K.rng(K.seedOf("t")))
	eq(#a.delving, 7, "6 random + 1 fixed delving spots")
	eq(#a.wortcunning, 4, "4 wortcunning spots")
	eq(a.delving[1].x, 100, "the fixed spot first")
	local all = {}
	for _, prof in ipairs({"delving", "wortcunning"}) do
		for i, s in ipairs(a[prof]) do
			eq(s.x, b[prof][i].x, "same seed, same spot x")
			eq(s.y, b[prof][i].y, "same seed, same spot y")
			check(K.inArea(area, s), "spot in the area")
			all[#all + 1] = s
		end
	end
	for i = 1, #all do
		for j = i + 1, #all do
			check(math.abs(all[i].x - all[j].x) >= cfg.nodeSpacing or math.abs(all[i].y - all[j].y) >= cfg.nodeSpacing,
				"spots apart")
		end
	end
	local none = K.pickSpots(area, cfg, function() return false end, K.rng(1))
	eq(#none.wortcunning, 0, "no free tile: no node")
end
local dragon = idx.area.dragon_scar
eq(K.fishingPlace(cfg, {x = dragon.center.x + 3, y = dragon.center.y, z = dragon.center.z}), 3, "fishing at Dragon Scar: tier 3")
eq(K.fishingPlace(cfg, {x = 1, y = 1, z = 7}), cfg.angling.defaultTier, "anywhere else: the default tier")
eq(K.flayTier(cfg, 120), 3, "a level 120 beast: tier 3")

-- ---------------------------------------------------------------- engine (professions.lua) against a mocked engine
MESSAGE_STATUS_SMALL, MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR, MESSAGE_STATUS_DEFAULT = 1, 2, 3, 4
TILESTATE_PROTECTIONZONE, TILESTATE_TELEPORT, TILESTATE_FLOORCHANGE = 1, 2, 4
CONST_PROP_BLOCKSOLID, CONST_PROP_BLOCKPATH = 1, 2
CONST_ME_BLOCKHIT, CONST_ME_SMALLPLANTS, CONST_ME_DRAWBLOOD, CONST_ME_WATERSPLASH, CONST_ME_FIREWORK_YELLOW = 9, 45, 1, 2, 29
COMBAT_HEALING, COMBAT_PHYSICALDAMAGE = 128, 1

local function deep(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in pairs(t) do
		o[k] = deep(v)
	end
	return o
end
local registry = {}
json = {
	encode = function(t) registry[#registry + 1] = deep(t); return "J" .. #registry end,
	decode = function(s) return deep(registry[tonumber(tostring(s):match("^J(%d+)$") or -1)]) end
}

local events, globalEvents, actions, callbacks = {}, {}, {}, {}
CreatureEvent = function(name)
	local e = {register = function() end, type = function() end}
	events[name] = e
	return e
end
GlobalEvent = function(name)
	local e = {register = function() end, interval = function() end}
	globalEvents[name] = e
	return e
end
Action = function()
	local a = {ids = {}}
	function a:id(n) self.ids[#self.ids + 1] = n end
	function a:register() actions[#actions + 1] = self end
	return a
end
local pendingCb = {}
EventCallback = setmetatable({}, {
	__newindex = function(_, k, v) pendingCb = {k, v} end,
	__index = function(_, k)
		if k == "register" then
			return function(_, prio) callbacks[pendingCb[1]] = {fn = pendingCb[2], prio = prio} end
		end
	end
})
TalkAction = function() return {separator = function() end, register = function() end} end

local clock = 1000000
os.mtime = function() return clock end
local timers = {}
addEvent = function(fn, ms, ...) timers[#timers + 1] = {fn = fn, at = clock + ms, args = {...}} end
local unpack = table.unpack or unpack
local function run(ms)
	local stop = clock + ms
	while clock < stop do
		clock = clock + 100
		local due = {}
		for i = #timers, 1, -1 do
			if timers[i].at <= clock then
				due[#due + 1] = table.remove(timers, i)
			end
		end
		for i = #due, 1, -1 do
			due[i].fn(unpack(due[i].args))
		end
	end
end

-- the map: tiles with items
local tiles = {}
local function key(x, y, z) return x .. ":" .. y .. ":" .. z end
local itemSeq = 0
local function newItem(id, pos)
	itemSeq = itemSeq + 1
	local it = {id = id, custom = {}, uid = itemSeq, pos = pos, owner = 0}
	function it:getId() return self.id end
	function it:isItem() return true end
	function it:getPosition() return self.pos end
	function it:getCustomAttribute(k) return self.custom[k] end
	function it:setCustomAttribute(k, v) self.custom[k] = v end
	function it:getCorpseOwner() return self.owner end
	return it
end
local function newTile(x, y, z)
	local t = {items = {}, pz = false}
	function t:getGround() return true end
	function t:hasFlag(f) return f == TILESTATE_PROTECTIONZONE and self.pz end
	function t:getHouse() return nil end
	function t:hasProperty() return false end
	function t:getItems() return self.items end
	function t:getTopCreature() return nil end
	function t:getItemById(id)
		for _, it in ipairs(self.items) do
			if it.id == id then
				return it
			end
		end
		return nil
	end
	tiles[key(x, y, z)] = t
	return t
end
Tile = function(pos) return tiles[key(pos.x, pos.y, pos.z)] end
Position = function(x, y, z)
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
for x = 490, 510 do
	for y = 490, 510 do
		newTile(x, y, 7)
	end
end
local npcs = {}
local playersById = {}
Game = {
	createItem = function(id, n, pos)
		local t = Tile(pos)
		local it = newItem(id, {x = pos.x, y = pos.y, z = pos.z})
		t.items[#t.items + 1] = it
		return it
	end,
	getPlayers = function()
		local out = {}
		for _, p in pairs(playersById) do
			out[#out + 1] = p
		end
		return out
	end,
	getTowns = function() return {} end,
	createNpc = function(name, pos) return nil end,
	getSpectators = function(pos, multi, onlyPlayers, a, b, c, d)
		local out = {}
		for _, n in ipairs(npcs) do
			if math.abs(n.pos.x - pos.x) <= a and math.abs(n.pos.y - pos.y) <= c and n.pos.z == pos.z then
				out[#out + 1] = n
			end
		end
		return out
	end
}
ItemType = function(id) return {getClientId = function() return id - 30000 end, getName = function() return "item" end} end
Player = function(id)
	if type(id) == "table" then
		return id
	end
	return playersById[id]
end

-- the database
local dbRows = {levels = {}, sales = {}}
db = {
	escapeString = function(s) return "'" .. tostring(s) .. "'" end,
	query = function(q) return true end,
	asyncQuery = function(q)
		local pid, prof, lv, xp, g = q:match("INSERT INTO `chaos_professions` .- VALUES %((%d+), '(%w+)', (%d+), (%d+), (%d+)%)")
		if pid then
			dbRows.levels[pid .. ":" .. prof] = {level = tonumber(lv), xp = tonumber(xp), gathered = tonumber(g)}
		end
		local p2, id, day, sold = q:match("INSERT INTO `chaos_professions_sales` .- VALUES %((%d+), (%d+), (%d+), (%d+)%)")
		if p2 then
			dbRows.sales[p2 .. ":" .. id] = {day = tonumber(day), sold = tonumber(sold)}
		end
		return true
	end
}

dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.select = function(q, cols)
	local out = {}
	local pid = q:match("`player_id` = (%d+)")
	if q:find("FROM `chaos_professions` ", 1, true) then
		for k, r in pairs(dbRows.levels) do
			local p, prof = k:match("^(%d+):(%w+)$")
			if p == pid then
				out[#out + 1] = {prof = prof, level = r.level, xp = r.xp, gathered = r.gathered}
			end
		end
	elseif q:find("FROM `chaos_professions_sales`", 1, true) then
		for k, r in pairs(dbRows.sales) do
			local p, id = k:match("^(%d+):(%d+)$")
			if p == pid then
				out[#out + 1] = {item_id = tonumber(id), day = r.day, sold = r.sold}
			end
		end
	end
	return out
end
local sent = {}
Chaos.send = function(player, op, action, data) sent[#sent + 1] = {op = op, action = action, data = deep(data)} end
Chaos.sendChunked = function(player, op, text)
	local m = json.decode(text)
	sent[#sent + 1] = {op = op, action = m.action, data = m.data}
end
Chaos.monsterTypeName = function(creature) return creature.name end
ChaosRateLimit = nil
local achieved, boards = {}, {}
ChaosAchievements = {set = function(player, stat, value) achieved[stat] = math.max(achieved[stat] or 0, value) end}
ChaosLeaderboard = {record = function(board, who, value, mode) boards[board] = (boards[board] or 0) + value end}

local function newPlayer(guid, level, x, y)
	local p = {guid = guid, id = 0x10000000 + guid, level = level, pos = {x = x, y = y, z = 7}, inv = {}, inbox = {}, bank = 0,
		exp = 0, messages = {}, cancels = {}, target = nil}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return "Gatherer" .. self.guid end
	function p:getLevel() return self.level end
	function p:getPosition() return Position(self.pos.x, self.pos.y, self.pos.z) end
	function p:getTarget() return self.target end
	function p:getItemCount(id) return self.inv[id] or 0 end
	function p:addItem(id, n) self.inv[id] = (self.inv[id] or 0) + n return true end
	function p:removeItem(id, n)
		if (self.inv[id] or 0) < n then
			return false
		end
		self.inv[id] = self.inv[id] - n
		return true
	end
	function p:getInbox() return {addItem = function(_, id, n) p.inbox[id] = (p.inbox[id] or 0) + n end} end
	function p:getBankBalance() return self.bank end
	function p:setBankBalance(v) self.bank = v end
	function p:sendTextMessage(t, text) self.messages[#self.messages + 1] = text end
	function p:sendCancelMessage(text)
		self.cancels[#self.cancels + 1] = text
		self.messages[#self.messages + 1] = text
	end
	function p:addExperience(n) self.exp = self.exp + n end
	function p:registerEvent() end
	function p:getGroup() return {getId = function() return 1 end} end
	function p:isMonster() return false end
	playersById[p.id] = p
	return p
end

math.randomseed(7)
dofile("data/scripts/chaos/professions.lua")
local P = ChaosProfessions
eq(ChaosOpcodes.professions, 195, "opcode constant")
eq(Chaos.tables.professions, "chaos_professions", "table constant")
eq(Chaos.tables.professionSales, "chaos_professions_sales", "sales table constant")
-- the opcode collision check (server/README.md): the reference server's opcodes, the reference client's own, every Chaos one
for _, taken in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	check(taken ~= ChaosOpcodes.professions, "opcode free of " .. taken)
end
for name, v in pairs(ChaosOpcodes) do
	check(name == "professions" or v ~= ChaosOpcodes.professions, "opcode not shared with " .. name)
end
eq(callbacks.onGainExperience.prio, 6, "the experience callback at index 6")
eq(callbacks.onDropLoot.prio, 4, "the loot callback at index 4")
eq(#actions, 1, "one node action")
eq(#actions[1].ids, #cfg.nodes, "the action covers every node")

-- a test area on the mocked tiles
local area = {key = "test_area", name = "Test Grounds", tier = 2, center = {x = 500, y = 500, z = 7}, r = 8,
	nodes = {delving = 4, wortcunning = 2}, fishing = true, pos = {delving = {{x = 501, y = 500}}}}
eq(P.addArea(area), 7, "seven nodes placed")
eq(P.addArea(area), 7, "placed again: the same seven")
local nodeOnMap = Tile({x = 501, y = 500, z = 7}):getItemById(32372)
check(nodeOnMap ~= nil, "a tier 2 vein on the fixed spot")

local player = newPlayer(7, 150, 500, 500)
events.ChaosProfessionsLogin.onLogin(player)
eq(achieved.prof_delving, 1, "achievement stats at login")
eq(achieved.prof_total, 4, "achievement total at login")
local function op(action, data)
	sent = {}
	events.ChaosProfessionsExtended.onExtendedOpcode(player, 195, json.encode({action = action, data = data}))
	for _, s in ipairs(sent) do
		if s.action == "state" then
			return s.data
		end
	end
	return sent[#sent] and sent[#sent].data
end
local st = op("open")
eq(#st.profs, 4, "state: four professions")
eq(#st.demand, 20, "state: twenty materials")
eq(st.broker, false, "no broker near")
eq(st.bonus, 0, "no bonus yet")
local testRow
for _, a in ipairs(st.areas) do
	if a.n == "Test Grounds" then
		testRow = a
	end
end
check(testRow ~= nil, "the area is listed")
eq(testRow.nodes[1].k, "delving", "delving nodes listed")
eq(testRow.nodes[1].r, 5, "five delving nodes ready")

-- gather the vein: the tool is needed for a plain use
local nodeAct = actions[1]
nodeAct.onUse(player, nodeOnMap, {x = 501, y = 500, z = 7})
has(player.messages[#player.messages], "pick", "no pick: refused")
player.inv[2553] = 1
sent = {}
nodeAct.onUse(player, nodeOnMap, {x = 501, y = 500, z = 7})
local bar
for _, s in ipairs(sent) do
	if s.op == 231 and s.action == "start" then
		bar = s.data
	end
end
check(bar ~= nil and bar.ms == 3000, "the cast bar starts for 3 s")
run(2000)
eq(player:getItemCount(32351), 0, "nothing before the end")
run(1500)
-- a tier 2 vein, but Delving 1 gathers tier 1: ashstone ore
check(player:getItemCount(32351) >= 1, "an ashstone ore after the channel")
eq(player:getItemCount(32352), 0, "no bloodiron below Delving 20")
eq(P.players[7].levels.delving.xp, 10, "10 profession experience")
check(player.exp > 0, "a little character experience")
-- the same node again: the per-player cooldown
nodeAct.onUse(player, nodeOnMap, {x = 501, y = 500, z = 7})
-- the cooldown is counted on the wall clock: a second may tick between the gather and this use (CI read 5:59)
local cdText = player.messages[#player.messages] or ""
check(cdText:find("ready for you again in 6:00", 1, true) or cdText:find("ready for you again in 5:59", 1, true),
	"node cooldown (" .. cdText .. ")")
-- another player may gather it at once (per-player cooldown, not shared depletion)
local other = newPlayer(8, 60, 500, 501)
events.ChaosProfessionsLogin.onLogin(other)
other.inv[2553] = 1
P.onTool(other, {getId = function() return 2553 end}, nodeOnMap, {x = 501, y = 500, z = 7})
check(P.channels[other:getId()] ~= nil, "another character gathers the same node")
-- moving interrupts
other.pos = {x = 499, y = 501, z = 7}
run(400)
eq(P.channels[other:getId()], nil, "moving interrupts")
has(other.cancels[#other.cancels], "moved", "moved message")
-- damage interrupts
other.pos = {x = 500, y = 501, z = 7}
P.onTool(other, {getId = function() return 2553 end}, nodeOnMap, {x = 501, y = 500, z = 7})
events.ChaosProfessionsHurt.onHealthChange(other, nil, 50, COMBAT_PHYSICALDAMAGE, 0, 0)
run(400)
eq(P.channels[other:getId()], nil, "damage interrupts")
has(other.cancels[#other.cancels], "Combat", "combat message")
-- healing does not
P.onTool(other, {getId = function() return 2553 end}, nodeOnMap, {x = 501, y = 500, z = 7})
events.ChaosProfessionsHurt.onHealthChange(other, nil, 50, COMBAT_HEALING, 0, 0)
run(3500)
check(other:getItemCount(32351) >= 1, "healing does not interrupt")
-- the wrong tool on a node
check(P.onTool(other, {getId = function() return 2405 end}, nodeOnMap, {x = 501, y = 500, z = 7}), "a sickle on a vein: handled")
has(other.messages[#other.messages], "Use a pick", "the right tool is named")
-- anything else goes on to the stock tool
eq(P.onTool(other, {getId = function() return 2553 end}, newItem(1234, {x = 500, y = 499, z = 7}), {x = 500, y = 499, z = 7}),
	false, "the stock pick keeps its own uses")

-- flaying: a beast corpse is tagged at the death
local wolf = {name = "wolf", getMaster = function() return nil end, getName = function() return "Wolf" end,
	getType = function() return {experience = function() return 18 end, maxHealth = function() return 25 end} end}
local corpse = Game.createItem(5968, 1, {x = 499, y = 500, z = 7})
callbacks.onDropLoot.fn(wolf, corpse)
local tag = corpse.custom.chaos_flay
check(type(tag) == "number" and tag % 10 == 1, "a wolf corpse is tagged tier 1")
local rat = {name = "dragon", getMaster = function() return nil end, getName = function() return "Dragon" end,
	getType = function() return {experience = function() return 700 end, maxHealth = function() return 1000 end} end}
local corpse2 = Game.createItem(3104, 1, {x = 498, y = 500, z = 7})
callbacks.onDropLoot.fn(rat, corpse2)
eq(corpse2.custom.chaos_flay, nil, "a dragon is no beast")
local knife = {getId = function() return 5908 end}
check(P.onTool(player, knife, corpse, {x = 499, y = 500, z = 7}), "the knife on a tagged corpse: handled")
run(2700)
eq(corpse.custom.chaos_flayed, 1, "the corpse is flayed")
check(P.players[7].levels.flaying.xp > 0, "flaying experience")
P.onTool(player, knife, corpse, {x = 499, y = 500, z = 7})
has(player.messages[#player.messages], "flayed already", "once per corpse")
corpse.custom.chaos_flayed = nil
corpse.owner = 0x10000000 + 99
P.onTool(player, knife, corpse, {x = 499, y = 500, z = 7})
has(player.messages[#player.messages], "not the owner", "only the owner")

-- angling: one roll per 3 s at most; a catch at the place's tier
P.players[7].levels.angling = {level = 25, xp = 0, gathered = 0}
local beforeFish = P.players[7].levels.angling.xp
local rolls = 0
local realRandom = math.random
math.random = function(a, b)
	if not a then
		rolls = rolls + 1
		return 0.01 -- every roll catches
	end
	return realRandom(a, b)
end
P.onFishCast(player, {getId = function() return 2580 end}, nil, {x = 503, y = 503, z = 7})
P.onFishCast(player, {getId = function() return 2580 end}, nil, {x = 503, y = 503, z = 7})
math.random = realRandom
check(player:getItemCount(32367) >= 1, "a gloomcarp from the tier 2 water")
eq(P.players[7].levels.angling.xp, beforeFish + 18, "one roll only within 3 s")

-- selling: away from a broker
local carried = player:getItemCount(32352)
st = op("sell", {id = 32352})
has(sent[1] and sent[1].data.text, "Material Broker", "no broker near: refused")
eq(player:getItemCount(32352), carried, "nothing taken")
-- at a broker
npcs[1] = {pos = {x = 502, y = 502, z = 7}, isNpc = function() return true end, getName = function() return "Material Broker" end}
player.inv[32352] = 150
local mult = P.demand()[32352]
st = op("sell", {id = 32352})
eq(st.broker, true, "at the broker")
local full = cfg.broker.fullPerDay
local price = K.unitPrice(cfg, idx.mat[32352], mult)
local late = K.latePrice(cfg, idx.mat[32352], mult)
eq(player.bank, full * price + 50 * late, "100 at full, 50 at the late price, to the bank")
eq(player:getItemCount(32352), 0, "the ores are taken")
player.inv[32352] = 80
op("sell", {id = 32352})
eq(player:getItemCount(32352), 30, "only up to the daily cap (200)")
local bank = player.bank
op("sell", {id = 32352})
eq(player.bank, bank, "the cap is reached: nothing more today")
has(sent[1] and sent[1].data.text, "no more", "the cap message")
-- the next day the cap opens again (the day comes from the clock)
P.offset = 86400
op("sell", {id = 32352})
eq(player:getItemCount(32352), 0, "a new day: sold again")
P.offset = 0
-- Sell All
player.inv[32351], player.inv[32356] = 10, 5
bank = player.bank
st = op("sellAll")
check(player.bank > bank, "Sell All pays")
eq(player:getItemCount(32351) + player:getItemCount(32356), 0, "Sell All takes every material")

-- the experience bonus: monster experience only, capped
local xp = callbacks.onGainExperience.fn
local monster = {isMonster = function() return true end, getMaster = function() return nil end}
eq(xp(player, monster, 1000, 1000), 1000, "no bonus at level 1")
for _, p in ipairs(cfg.professions) do
	P.players[7].levels[p.key] = {level = 100, xp = 0, gathered = 0, dirty = true}
end
events.ChaosProfessionsLogout.onLogout(player)
events.ChaosProfessionsLogin.onLogin(player)
eq(P.players[7].levels.delving.level, 100, "levels saved and loaded")
eq(xp(player, monster, 1000, 1000), 1100, "+10% at the cap")
eq(xp(player, nil, 1000, 1000), 1000, "no bonus without a monster")
local summon = {isMonster = function() return true end, getMaster = function() return player end}
eq(xp(player, summon, 1000, 1000), 1000, "no bonus for a summon")
eq(achieved.prof_total, 400, "achievement total 400")
-- the buff bar
local item = P.buffItem(player, {})
has(item.name, "+10%", "buff name")
eq(item.pct, 10, "buff percent")
eq(P.buffItem(other, {}), nil, "no buff without a bonus")
dofile("data/lib/chaos_buffs.lua")
local def = ChaosBuffs.byKey.professions
check(def ~= nil and def.icon == "buff:professions", "registered in the buff bar")
local list = ChaosBuffs.sources.professions(player, 0, def)
eq(list[1].stacks, 10, "the whole percent on the icon")
-- the weekly board
globalEvents.ChaosProfessionsFlush.onThink(60000)
check((boards.professions or 0) > 0, "materials on the weekly board: " .. tostring(boards.professions))
-- the owner's rule in the leaderboard: the title only
local lb = dofile("data/scripts/chaos/leaderboard_config.lua")
local found
for _, b in ipairs(lb.boards) do
	if b.key == cfg.board then
		found = b
	end
end
check(found ~= nil and found.noReward == true, "the Gatherers board gives a title, no orbs")

print(string.format("professions_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
