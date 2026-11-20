-- Run from the server/ folder: luajit tests/greater_rift_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The Greater Rift (O668): the rule and the climb (rift_core.lua R.greater*), the config, the ladder's pure part
-- (greater_ladder_core.lua), the keys and the run's end with rift.lua loaded for real on a mocked engine (key attributes, the
-- crash refund, the key a sealed or failed run leaves, the purchase with omen fragments), and greater_ladder.lua on a scripted
-- database (the personal best rewards, tester bots left out, the pinnacle call, the weekly board, the season end).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then fails = fails + 1; print("FAIL " .. what) end
end
local function eq(a, b, what) ok(a == b, tostring(what) .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b, tol, what) ok(math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " ~ " .. tostring(b)) end

-- ------------------------------------------------------------------ engine mocks (as rift_refund_test.lua)
local events = {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function() events[name or (kind .. "#" .. tostring(e))] = e end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent = eventMock("creature"), eventMock("global"), eventMock("talk"),
	eventMock("action"), eventMock("move")
EventCallback = setmetatable({}, {__index = function() return function() end end})
GAME_STATE_NORMAL, GAME_STATE_CLOSED, GAME_STATE_SHUTDOWN = 1, 2, 3
local queries = {}
db = {query = function(q) queries[#queries + 1] = q return true end, storeQuery = function() return false end,
	escapeString = function(s) return "'" .. s .. "'" end}
result = {free = function() end}
local function pos(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
Position = pos
local created = {}
local function newItem(id)
	local it = {id = id, attrs = {}}
	function it:getId() return self.id end
	function it:setActionId(a) self.aid = a end
	function it:getActionId() return self.aid or 0 end
	function it:setCustomAttribute(k, v) self.attrs[k] = v end
	function it:getCustomAttribute(k) return self.attrs[k] end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:getAttribute(k) return self.attrs[k] end
	function it:remove() self.removed = true return true end
	return it
end
local online = {}
Game = {
	getGameState = function() return GAME_STATE_NORMAL end,
	createItem = function(id) local it = newItem(id) created[#created + 1] = it return it end,
	getPlayers = function() return online end,
	getSpectators = function() return {} end,
	getExperienceStage = function() return 1 end,
	broadcastMessage = function() end,
}
ItemType = function(id) return {getId = function() return id end, getName = function() return "item" .. id end} end
local players = {}
Player = function(id)
	if type(id) == "string" then
		for _, p in pairs(players) do if p.name == id then return p end end
		return nil
	end
	return players[id]
end
Monster = function() return nil end
json = {encode = function() return "{}" end, decode = function() return {} end}
Tile = function() return nil end
addEvent = function() return 0 end

dofile("data/scripts/chaos/rift.lua")
local RF, R = ChaosRift, ChaosRiftCore
local cfg = ChaosRiftConfig
local G = cfg.greater
local ST = Chaos.storage.riftRun

-- ------------------------------------------------------------------ 1. the config
eq(G.firstTier, cfg.maxTier + 1, "the first Greater tier is the one above maxTier")
ok(G.maxShownTier < R.omenMarker, "the refund marker's tiers stay under the Omen markers")
ok(R.greaterOn(cfg), "the Greater Rift is on")
do
	local prev = 0
	for _, st in ipairs(G.clock.steps) do
		ok(st.fraction > prev and st.fraction <= 1, "the clock steps rise and stay inside the clock")
		prev = st.fraction
	end
	eq(G.clock.steps[1].up, 3, "the fastest step climbs 3 tiers")
	eq(G.clock.steps[#G.clock.steps].up, 1, "the slowest step climbs 1 tier")
	eq(G.clock.steps[#G.clock.steps].fraction, 1, "the last step is the whole clock")
	ok(G.rewards.maxPerRun >= G.clock.steps[1].up, "a run's personal best pays at least the 3 tiers a key can climb")
	local last = 0
	for _, b in ipairs(G.rewards.brackets) do
		if b.upTo then
			ok(b.upTo > last, "bracket places rise")
			last = b.upTo
		end
	end
	ok(G.rewards.brackets[#G.rewards.brackets].minTier ~= nil, "the last bracket pays everybody who reached a tier")
end

-- ------------------------------------------------------------------ 2. the rule
do
	local i0, i1, i10 = R.greaterInfo(cfg, 0), R.greaterInfo(cfg, 1), R.greaterInfo(cfg, 10)
	eq(i0.health, 1, "g 0: no extra health"); eq(i0.damage, 1, "g 0: no extra damage")
	near(i1.health, 1 + G.rule.health, 1e-12, "g 1 health"); near(i1.damage, 1 + G.rule.damage, 1e-12, "g 1 damage")
	near(i10.health, (1 + G.rule.health) ^ 10, 1e-9, "g 10 health compounds")
	eq(i10.shown, 25, "g 10 shows tier 25")
	eq(i10.level, R.tierInfo(cfg, cfg.maxTier).minLevel + 10 * G.rule.levelStep, "the shown level climbs by levelStep")
	ok(R.greaterInfo(cfg, 500).reward <= G.rule.rewardCap, "the reward factor stops at its cap")
	local fx = R.applyGreater(cfg, {health = 2, damage = 3}, 10)
	near(fx.health, 2 * i10.health, 1e-9, "applyGreater: health"); near(fx.damage, 3 * i10.damage, 1e-9, "applyGreater: damage")
	eq(fx.greater, 10, "applyGreater: marks the run")
	local plain = R.applyGreater(cfg, {health = 2, damage = 3}, nil)
	eq(plain.health, 2, "no Greater tier: unchanged"); eq(plain.greater, nil, "no mark")
	local off = setmetatable({greater = setmetatable({enabled = false}, {__index = G})}, {__index = cfg})
	eq(R.applyGreater(off, {health = 2}, 10).health, 2, "switched off: unchanged")
	eq(R.shownTier(off, {tier = 15, greater = 10}), 15, "switched off: the key shows tier 15")
	eq(R.shownTier(cfg, {tier = 15, greater = 3}), 18, "shown tier of a key")
	eq(R.shownTier(cfg, {tier = 9}), 9, "shown tier of a plain key")
	eq(R.shownTier(cfg, {tier = 15, greater = 5000}), G.maxShownTier, "shown tier is capped")
	eq(R.greaterOf(cfg, 15), 0, "g of tier 15"); eq(R.greaterOf(cfg, 16), 1, "g of tier 16"); eq(R.greaterOf(cfg, 40), 25, "g of tier 40")
	local rr = R.greaterReward(cfg, {gold = 1000, chaos = 2, divine = 1}, 10, function(a, b) return a end)
	eq(rr.gold, math.floor(1000 * R.greaterInfo(cfg, 10).reward), "the chest's gold x the factor")
	eq(R.greaterReward(cfg, {gold = 1000}, nil, nil).gold, 1000, "a plain rift's chest is untouched")
	eq(R.displayLevel(cfg, 15, true, false, 4), R.tierInfo(cfg, 15).minLevel + 4 * G.rule.levelStep, "the shown level of a Greater monster")
	eq(R.displayLevel(cfg, 15, true, false, nil), R.tierInfo(cfg, 15).minLevel, "the shown level of a plain tier 15 monster")
	eq(R.displayLevel(cfg, 15, false, false, 4), nil, "no density: no shown level")
end

-- ------------------------------------------------------------------ 3. the clock and the climb
do
	local limit = 1000
	eq(R.greaterUp(cfg, 500, limit), 3, "half the clock: +3"); eq(R.greaterUp(cfg, 501, limit), 2, "just over half: +2")
	eq(R.greaterUp(cfg, 750, limit), 2, "three quarters: +2"); eq(R.greaterUp(cfg, 751, limit), 1, "over three quarters: +1")
	eq(R.greaterUp(cfg, 1000, limit), 1, "the whole clock: +1"); eq(R.greaterUp(cfg, 1001, limit), 0, "past the clock: nothing")
	eq(R.greaterNext(cfg, 5, true, 400, limit), 8, "sealed in 40%: g 5 -> 8")
	eq(R.greaterNext(cfg, 5, true, 990, limit), 6, "sealed late: g 5 -> 6")
	eq(R.greaterNext(cfg, 5, false, 0, limit), 4, "failed: g 5 -> 4")
	eq(R.greaterNext(cfg, 1, false, 0, limit), 0, "failed at tier 16: a plain tier 15 key")
	eq(R.greaterNext(cfg, 0, false, 0, limit), 0, "failed at g 0: stays 0")
	eq(R.greaterNext(cfg, 0, true, 100, limit), 3, "a first Greater clear in time: +3")
	eq(R.greaterNext(cfg, G.maxShownTier - cfg.maxTier, true, 1, limit), G.maxShownTier - cfg.maxTier, "the top of the numbers holds")
	eq(R.greaterClock(cfg, 1260), math.floor(1260 * G.clock.mult), "the clock of a band")
	-- O674: the run's limit. A Greater run keeps the key's band clock (tier 15: 1260 s, 21 minutes) on a layout of any band; a plain run follows the layout
	eq(cfg.layout.sizes[3][3], 1260, "the tier 15 band is 1260 s")
	for band = 1, #cfg.layout.sizes do
		eq(R.runLimit(cfg, {tier = cfg.maxTier, greater = 2}, band), math.floor(1260 * G.clock.mult), "a Greater key on a layout of band " .. band .. ": the tier 15 clock")
		eq(R.runLimit(cfg, {tier = cfg.maxTier}, band), cfg.layout.sizes[band][3], "a plain key follows the layout's band " .. band)
	end
	eq(R.runLimit(cfg, {tier = 3}, nil), cfg.timeLimit, "no layout band: the config's limit")
	eq(R.runLimit(cfg, {tier = cfg.maxTier, greater = 1}, 1), R.greaterClock(cfg, R.timeLimit(cfg, cfg.maxTier)), "the Greater limit is the model's (greater_numbers.lua)")
	-- a key of every g: the name, the description, the marker
	local rnd = function(a, b) return a end
	local key = R.greaterKey(cfg, 7, rnd, true)
	eq(key.tier, cfg.maxTier, "a Greater key stores tier 15"); eq(key.greater, 7, "and the climb")
	ok(#key.mods >= 1, "with modifiers")
	eq(R.greaterKey(cfg, 0, rnd).greater, nil, "g 0 is a plain key")
	eq(R.keyName(cfg, 15, 7), "Greater Rift Key (Tier 22)", "the key's name")
	eq(R.keyName(cfg, 6), "Rift Key (Tier 6)", "a plain key's name")
	ok(R.describe(cfg, key):find("Greater Rift tier 22", 1, true) ~= nil, "the description names the shown tier")
	eq(R.markerGreater(cfg, 22), 7, "the marker of tier 22 is g 7"); eq(R.markerGreater(cfg, 15), nil, "tier 15 is no Greater marker")
	eq(R.markerGreater(cfg, 6), nil, "nor a low tier"); eq(R.markerGreater(cfg, 1001), nil, "nor an Omen marker")
	ok(R.markerOmen(cfg, 22) == nil, "the Omen decoder leaves the Greater marker alone")
	-- the drop: chance, and always at the pity'th sealed tier 15 rift in a row
	local lo, hi = function() return 1 end, function(a, b) return b end
	ok(R.greaterDrop(cfg, 0, lo), "a low roll drops"); ok(not R.greaterDrop(cfg, 0, hi), "a high roll does not")
	ok(R.greaterDrop(cfg, G.key.drop.pity - 1, hi), "the pity'th rift in a row always drops")
	ok(not R.greaterDrop(cfg, G.key.drop.pity - 2, hi), "one before it does not")
end

-- ------------------------------------------------------------------ 4. the personal best rewards
do
	local p = R.greaterBestRewards(cfg, 0, 18)
	eq(#p, 3, "from nothing to tier 18: the 3 highest tiers (16, 17, 18)")
	eq(p[1].tier, 16, "first paid tier"); eq(p[3].tier, 18, "last paid tier")
	ok(p[3].gold > p[1].gold and p[3].fate >= p[1].fate and p[3].upheaval > p[1].upheaval, "a higher tier pays more")
	eq(#R.greaterBestRewards(cfg, 18, 18), 0, "no new tier: nothing")
	eq(#R.greaterBestRewards(cfg, 20, 18), 0, "a lower tier: nothing")
	local q = R.greaterBestRewards(cfg, 20, 22)
	eq(#q, 2, "a jump of two new tiers pays two"); eq(q[1].tier, 21, "from the tier after the best")
	eq(#R.greaterBestRewards(cfg, 16, 40), G.rewards.maxPerRun, "a big jump pays at most maxPerRun tiers")
	eq(R.greaterBestRewards(cfg, 16, 40)[1].tier, 38, "the highest ones")
	eq(R.greaterBestRewards(cfg, 3, 17)[1].tier, 15 + 1 + 0 > 16 and 16 or 15 + 1, "never below the first Greater tier")
	near(R.greaterPinnacleChance(cfg, 15), 0, 1e-12, "no pinnacle chance at tier 15")
	ok(R.greaterPinnacleChance(cfg, 20) > 0, "a pinnacle chance above it")
	ok(R.greaterPinnacleChance(cfg, 200) <= G.rewards.pinnacle.chance * G.rewards.pinnacle.cap, "capped")
end

-- ------------------------------------------------------------------ 5. the ladder's pure part
local K = ChaosGreaterCore
dofile("data/scripts/chaos/greater_ladder_core.lua")
K = ChaosGreaterCore
do
	eq(K.modeOf(1), "solo"); eq(K.modeOf(2), "party"); eq(K.modeOf(5), "party"); eq(K.modeOf(nil), "solo")
	local row, improved = K.merge(nil, 18, 600)
	ok(improved and row.best_tier == 18 and row.best_time == 600 and row.runs == 1, "first result")
	row, improved = K.merge(row, 18, 700)
	ok(not improved and row.best_time == 600 and row.runs == 2, "a slower run at the same tier is no improvement")
	row, improved = K.merge(row, 18, 500)
	ok(improved and row.best_time == 500, "a faster run at the same tier improves")
	row, improved = K.merge(row, 17, 100)
	ok(not improved and row.best_tier == 18, "a lower tier never improves, however fast")
	row, improved = K.merge(row, 19, 1200)
	ok(improved and row.best_tier == 19 and row.best_time == 1200, "a higher tier improves, however slow")
	eq(K.baseline({{best_tier = 17}, {best_tier = 21}, {best_tier = 0}}), 21, "the baseline is the best over the modes")
	eq(K.baseline({}), 0, "the baseline of nothing is 0")
	local groups = {{key = "knight", name = "Knight", ids = {4, 8}}, {key = "mage", name = "Mage", ids = {1, 5}}}
	eq(K.groupOf(groups, 8), "knight", "class group"); eq(K.groupOf(groups, 99), nil, "unknown class")
	local rows = {
		{guid = 1, name = "A", voc = 4, tier = 30, time = 900, group = 1}, {guid = 2, name = "B", voc = 8, tier = 30, time = 800, group = 1},
		{guid = 3, name = "C", voc = 4, tier = 28, time = 100, group = 1}, {guid = 4, name = "D", voc = 1, tier = 35, time = 100, group = 1},
		{guid = 5, name = "God", voc = 4, tier = 99, time = 1, group = 5}, {guid = 6, name = "E", voc = 4, tier = 30, time = 800, group = 1},
		{guid = 7, name = "Z", voc = 4, tier = 0, time = 1, group = 1}}
	local all = K.rank(rows, 4)
	eq(#all, 5, "staff and tier 0 are left out")
	eq(all[1].name, "D", "the highest tier first")
	eq(all[2].place, 2, "equal tier and time share the place"); eq(all[3].place, 2, "...both second")
	eq(all[4].place, 4, "the next place is skipped (1, 2, 2, 4)"); eq(all[5].name, "C", "lowest last")
	local kn = K.board(rows, groups, "knight", 4, 2)
	eq(#kn, 2, "a class board is cut at its limit"); eq(kn[1].tier, 30, "knights only")
	local mg = K.board(rows, groups, "mage", 4)
	eq(#mg, 1, "mage board"); eq(mg[1].name, "D", "the mage")
	eq(K.bracketFor(cfg, 1, 40).name, "Greater Champion", "place 1"); eq(K.bracketFor(cfg, 2, 40).name, "Greater Vanguard", "place 2")
	eq(K.bracketFor(cfg, 10, 40).name, "Greater Delver", "place 10"); eq(K.bracketFor(cfg, 50, 40).name, "Greater Seeker", "place 50")
	eq(K.bracketFor(cfg, 51, 25).name, "Greater Rifter", "a low place with a tier that counts")
	eq(K.bracketFor(cfg, 51, 17), nil, "a low place and a low tier: nothing")
	local sr = {}
	for _, r in ipairs(rows) do sr[#sr + 1] = {guid = r.guid, name = r.name, voc = r.voc, tier = r.tier, time = r.time, group = r.group, mode = "solo"} end
	sr[#sr + 1] = {guid = 1, name = "A", voc = 4, tier = 30, time = 900, group = 1, mode = "party"}
	local aw = K.awards(cfg, sr, groups)
	local by = {}
	for _, a in ipairs(aw) do by[a.guid .. a.mode] = a end
	eq(by["4solo"].bracket.name, "Greater Champion", "the lone mage wins its class board")
	eq(by["2solo"].place, 1, "the fastest knight is first on the knights' board"); eq(by["2solo"].bracket.name, "Greater Champion", "...with the first bracket")
	eq(by["6solo"].place, 1, "an equal result shares the place"); eq(by["1solo"].place, 3, "the next knight is third")
	eq(by["1solo"].bracket.name, "Greater Vanguard", "...in the second bracket")
	eq(by["1party"].place, 1, "the party board is its own"); eq(by["5solo"], nil, "staff gets no award")
	eq(by["7solo"], nil, "tier 0 gets no award")
	eq(K.timeText(754), "12:34", "time text")
	local season, startT, endT = K.seasonOf(cfg, {seasonEpoch = 1000000}, 1000000 + 31 * 86400)
	eq(season, 2, "the 31st day is season 2 of 30-day windows"); eq(endT - startT, G.ladder.seasonDays * 86400, "season length")
	eq(select(1, K.seasonOf(cfg, {seasonEpoch = nil}, os.time())), 1, "no epoch: season 1")
end

-- ------------------------------------------------------------------ 6. keys and the crash refund on rift.lua
local temple = pos(100, 100, 7)
local nextId = 0
local function newPlayer(guid, name)
	nextId = nextId + 1
	local p = {id = 1000 + nextId, guid = guid, name = name, storage = {}, db = {}, items = {}, msgs = {}, at = pos(1, 1, 7), level = 1200,
		counts = {}}
	p.getId = function() return p.id end
	p.getGuid = function() return p.guid end
	p.getName = function() return p.name end
	p.getStorageValue = function(_, k) return p.storage[k] or -1 end
	p.setStorageValue = function(_, k, v) p.storage[k] = v end
	p.save = function() for k, v in pairs(p.storage) do p.db[k] = v end end
	p.addItemEx = function(_, item) p.items[#p.items + 1] = item return RETURNVALUE_NOERROR end
	p.getInbox = function() return nil end
	p.sendTextMessage = function(_, _, text) p.msgs[#p.msgs + 1] = text end
	p.sendCancelMessage = function(_, text) p.msgs[#p.msgs + 1] = text end
	p.teleportTo = function(_, to) p.at = to end
	p.getPosition = function() return p.at end
	p.getTown = function() return {getTemplePosition = function() return temple end} end
	p.registerEvent = function() end
	p.unregisterEvent = function() end
	p.sendExtendedOpcode = function() end
	p.removeCondition = function() end
	p.getCondition = function() return nil end
	p.addCondition = function() end
	p.getLevel = function() return p.level end
	p.getItemCount = function(_, id) return p.counts[id] or 0 end
	p.removeItem = function(_, id, c) if (p.counts[id] or 0) >= c then p.counts[id] = p.counts[id] - c return true end return false end
	p.getVocation = function() return {getId = function() return 4 end} end
	p.getBankBalance = function() return p.bank or 0 end
	p.setBankBalance = function(_, v) p.bank = v end
	players[p.id] = p
	online[#online + 1] = p
	return p
end
local function keysOf(p)
	local list = {}
	for _, it in ipairs(p.items) do
		if it.id == cfg.key.itemId then list[#list + 1] = it end
	end
	return list
end
local function lastKey(p)
	return RF.readKey(keysOf(p)[#keysOf(p)])
end
do
	local k = RF.createKey({tier = 15, greater = 3, mods = {{key = cfg.mods[1].key, value = cfg.mods[1].range[1]}}})
	eq(k.attrs.rift_tier, 15, "the key stores tier 15"); eq(k.attrs.rift_greater, 3, "and the climb")
	eq(k.attrs[ITEM_ATTRIBUTE_NAME], "Greater Rift Key (Tier 18)", "the item's name")
	ok(tostring(k.attrs[ITEM_ATTRIBUTE_DESCRIPTION]):find("Greater Rift tier 18", 1, true) ~= nil, "the item's description")
	local back = RF.readKey(k)
	eq(back.tier, 15, "read: tier"); eq(back.greater, 3, "read: climb"); eq(#back.mods, 1, "read: modifiers")
	local plain = RF.createKey({tier = 6, mods = {}})
	eq(plain.attrs.rift_greater, nil, "a plain key stores no climb"); eq(RF.readKey(plain).greater, nil, "and reads none")
	eq(plain.attrs[ITEM_ATTRIBUTE_NAME], "Rift Key (Tier 6)", "a plain key's name")
end

local function openRun(opener, others, key, startAgo, limit)
	local slot = 1 + (opener.guid % 7)
	local c = R.slotCenter(cfg, slot)
	local L = {start = {x = c.x, y = c.y, z = c.z}}
	local fx = R.applyGreater(cfg, R.effects(cfg, key.mods, key.tier), key.greater)
	local run = R.newRun(cfg, os.time() - (startAgo or 0), 10, 8, fx)
	run.id, run.slot, run.L, run.key, run.plan, run.fx = slot, slot, L, key, {boss = "x"}, fx
	run.greater = key.greater
	run.bonus, run.players, run.size, run.lives, run.revive = {}, {}, 1 + #(others or {}), 3, {}
	run.openerGuid, run.typeNames, run.claimed, run.finishers = opener.guid, {}, {}, {}
	run.startTime = os.time() - (startAgo or 0)
	run.limit = limit or 1260
	run.state = "running"
	RF.runs[slot] = run
	local list = {opener}
	for _, o in ipairs(others or {}) do list[#list + 1] = o end
	for _, p in ipairs(list) do
		run.players[p.id] = {id = p.id, guid = p.guid, name = p.name, entry = pos(50, 50, 7), xp = {base = 0}}
		RF.runOf[p.id] = run
		p.at = pos(L.start.x, L.start.y, L.start.z)
	end
	opener:setStorageValue(ST, R.shownTier(cfg, key))
	for i = 1, 3 do
		opener:setStorageValue(ST + i, key.mods[i] and R.packMod(cfg, key.mods[i]) or 0)
	end
	opener:setStorageValue(ST + 4, os.time())
	opener:save()
	return run
end
local function restart()
	RF.runs, RF.runOf, RF.noRefund, RF.revive, RF.pending = {}, {}, {}, {}, {}
end

local login = events.ChaosRiftLogin.onLogin
local gkey = {tier = 15, greater = 6, mods = {{key = cfg.mods[1].key, value = cfg.mods[1].range[1]}}}

-- a crash during a Greater run: the marker holds the shown tier, the login gives the Greater key back, once
do
	restart()
	local a = newPlayer(21, "CrashG")
	openRun(a, {}, gkey)
	eq(a.db[ST], 21, "the marker holds the shown tier")
	restart()
	local a2 = newPlayer(21, "CrashG")
	for k, v in pairs(a.db) do a2.storage[k] = v end
	login(a2)
	eq(#keysOf(a2), 1, "the crash refund gives one key")
	local k = lastKey(a2)
	eq(k.tier, 15, "refund: tier 15"); eq(k.greater, 6, "refund: the same climb")
	eq(#k.mods, 1, "refund: the same modifiers")
end

-- a clean shutdown refunds the Greater key through the same marker
do
	restart()
	local a = newPlayer(22, "ShutG")
	local run = openRun(a, {}, gkey)
	local shutdown = events.ChaosRiftShutdown.onShutdown
	shutdown()
	ok(run.ended, "the run ended")
	eq(#keysOf(a), 1, "shutdown: the key comes back"); eq(lastKey(a).greater, 6, "shutdown: as a Greater key")
end

-- ------------------------------------------------------------------ 7. the end of a run: the key a sealed or failed run leaves
local recorded = {}
ChaosGreater = {record = function(info) recorded[#recorded + 1] = info return {} end}
do
	restart()
	local a, b = newPlayer(31, "Opener"), newPlayer(32, "Friend")
	-- sealed in 400 s of 1260 (31%): +3
	local run = openRun(a, {b}, {tier = 15, greater = 6, mods = {}}, 400, 1260)
	run.finishers = {[a.guid] = {name = a.name}, [b.guid] = {name = b.name}}
	recorded = {}
	-- O686 phase 7: the Rift Seals hook (spell_awakening.lua): every player of the run, the shown tier, climbed when sealed
	local sealCalls = {}
	_G.ChaosSpellAwakening = {onRiftRun = function(p, tier, climbed) sealCalls[#sealCalls + 1] = {p.guid, tier, climbed} return 1 end}
	local out = RF.greaterSettle(run, true)
	eq(#sealCalls, 2, "seals: the hook runs for both players of the run")
	eq(sealCalls[1][2], 21, "seals: the shown tier")
	eq(sealCalls[1][3], true, "seals: a sealed run climbs")
	_G.ChaosSpellAwakening = nil
	eq(out.next, 9, "sealed in time: the key climbs 3 tiers")
	eq(#keysOf(a), 1, "the opener gets a key"); eq(lastKey(a).greater, 9, "a Greater key of g 9")
	eq(#keysOf(b), 0, "the friend gets none")
	eq(#recorded, 1, "the ladder is told once"); eq(recorded[1].tier, 21, "the shown tier of the run"); eq(recorded[1].players, 2, "the party size")
	ok(recorded[1].finishers[a.guid] ~= nil and recorded[1].finishers[b.guid] ~= nil, "every finisher is recorded")
	eq(recorded[1].secs, out.secs, "the seconds")
	ok(RF.greaterSettle(run, true) == nil, "a second settle does nothing"); eq(#keysOf(a), 1, "and no second key")

	-- sealed late (1000 of 1260 = 79%): +1
	restart()
	local c = newPlayer(33, "Late")
	run = openRun(c, {}, {tier = 15, greater = 6, mods = {}}, 1000, 1260)
	run.finishers = {[c.guid] = {name = c.name}}
	eq(RF.greaterSettle(run, true).next, 7, "sealed late: +1")

	-- failed: one tier down
	restart()
	local d = newPlayer(34, "Failer")
	run = openRun(d, {}, {tier = 15, greater = 6, mods = {}}, 1300, 1260)
	recorded = {}
	RF._fail(run, "Time is up!")
	eq(#keysOf(d), 1, "a failed Greater Rift still leaves a key"); eq(lastKey(d).greater, 5, "one tier lower")
	eq(#recorded, 0, "a failed run is not on the ladder")
	ok(run.settled, "settled")

	-- failed at tier 16: a plain tier 15 key
	restart()
	local e = newPlayer(35, "Bottom")
	run = openRun(e, {}, {tier = 15, greater = 1, mods = {}}, 1300, 1260)
	RF._fail(run, "No lives are left!")
	eq(#keysOf(e), 1, "a key at the bottom"); eq(lastKey(e).greater, nil, "a plain key"); eq(lastKey(e).tier, 15, "of tier 15")

	-- a plain rift that fails keeps losing its key
	restart()
	local f = newPlayer(36, "Plain")
	run = openRun(f, {}, {tier = 15, mods = {}}, 1300, 1260)
	RF._fail(run, "Time is up!")
	eq(#keysOf(f), 0, "a plain rift that fails: the key is lost")

	-- the opener is offline when it fails: the key is lost, nothing breaks
	restart()
	local g = newPlayer(37, "Gone")
	run = openRun(g, {}, {tier = 15, greater = 6, mods = {}}, 1300, 1260)
	players[g.id], online[#online] = nil, nil
	RF._fail(run, "Nobody came back in time.")
	eq(#keysOf(g), 0, "an offline opener gets nothing")
end

-- the Omen arena never takes the Greater path
do
	restart()
	local a = newPlayer(38, "Omen")
	local run = openRun(a, {}, {tier = 15, mods = {}, omen = "bloodmoon"}, 100, 1260)
	run.omen = "bloodmoon"
	eq(RF.greaterSettle(run, true), nil, "no Greater settle for an Omen run")
end

-- ------------------------------------------------------------------ 8. buying a key with omen fragments
do
	local frag = cfg.omen.fragment.id
	local a = newPlayer(41, "Buyer")
	ok(not RF.buyGreaterKey(a), "no fragments: refused"); eq(#keysOf(a), 0, "no key")
	a.counts[frag] = G.key.fragmentCost * 5
	a.level = 900
	ok(not RF.buyGreaterKey(a), "too low a level: refused"); eq(a.counts[frag], G.key.fragmentCost * 5, "the fragments stay")
	a.level = 1100
	ok(RF.buyGreaterKey(a), "bought"); eq(a.counts[frag], G.key.fragmentCost * 4, "the cost is taken")
	eq(#keysOf(a), 1, "one key"); eq(lastKey(a).greater, 1, "tier 16")
	for _ = 2, G.key.boughtPerDay do ok(RF.buyGreaterKey(a), "bought again") end
	ok(not RF.buyGreaterKey(a), "the day's limit holds"); eq(#keysOf(a), G.key.boughtPerDay, "keys of the day")
	a.storage[G.key.boughtStorage + 1] = 19990101 -- yesterday: a new day
	ok(RF.buyGreaterKey(a), "a new day, a new purchase")
end

-- ------------------------------------------------------------------ 9. the ladder engine on a scripted database
dofile("data/scripts/chaos/greater_ladder.lua")
local GL = ChaosGreater
ok(GL.record ~= nil and GL.deliverPending ~= nil, "the ladder engine loaded")
local rowsFor = {} -- pattern -> rows
Chaos.select = function(q, cols)
	for pat, rows in pairs(rowsFor) do
		if q:find(pat, 1, true) then return rows end
	end
	return {}
end
local lbCalls = {}
ChaosLeaderboard = {record = function(board, who, value, mode) lbCalls[#lbCalls + 1] = {board, who, value, mode} return {} end,
	classGroups = function() return {{key = "knight", name = "Knight", ids = {4, 8}}} end}
local pinnacle = {}
local function reset()
	queries, lbCalls, pinnacle = {}, {}, {}
	rowsFor = {}
	Chaos.testerGuids = {}
end
local function count(pat)
	local c = 0
	for _, q in ipairs(queries) do if q:find(pat, 1, true) then c = c + 1 end end
	return c
end
do
	reset()
	local a = newPlayer(51, "Ladder")
	local out = GL.record({tier = 18, secs = 700, players = 1, finishers = {[51] = {name = "Ladder", player = a}}})
	ok(out[51] ~= nil, "a finisher is recorded"); ok(out[51].improved, "first result improves")
	eq(out[51].rewards, 3, "three new tiers: three personal best rewards (16, 17, 18)")
	eq(count("INSERT INTO `chaos_greater_rift`"), 1, "one ladder row written")
	eq(count("INSERT IGNORE INTO `chaos_greater_rift_rewards`"), 3, "three reward rows")
	eq(#lbCalls, 1, "the weekly board"); eq(lbCalls[1][1], "greater_solo", "the solo board"); eq(lbCalls[1][3], 18, "with the shown tier")
	eq(lbCalls[1][4], "max", "kept as a best")
	-- the rewards rows were all unpaid in the scripted DB: delivery of nothing since the scripted select returns none
	reset()
	rowsFor["FROM `chaos_greater_rift` WHERE"] = {{mode = 0, voc = 4, best_tier = 20, best_time = 800, runs = 3}}
	out = GL.record({tier = 21, secs = 900, players = 3, finishers = {[51] = {name = "Ladder", player = a}, [52] = {name = "Mate"}}})
	eq(out[51].rewards, 1, "a best of 20 and a party clear of 21: one new tier (over both modes)")
	eq(count("INSERT INTO `chaos_greater_rift`"), 2, "both finishers on the ladder")
	eq(lbCalls[1][1], "greater_party", "the party board")
	-- a lower tier than the best of the other mode pays nothing
	reset()
	rowsFor["FROM `chaos_greater_rift` WHERE"] = {{mode = 0, voc = 4, best_tier = 30, best_time = 800, runs = 3}}
	out = GL.record({tier = 24, secs = 900, players = 2, finishers = {[51] = {name = "Ladder", player = a}}})
	eq(out[51].rewards, 0, "tier 24 after a solo best of 30: no reward")
	ok(out[51].improved, "but it is the first party result")
	-- a tester bot is on no ladder and gets nothing
	reset()
	Chaos.testerGuids[53] = "Bot"
	local bot = newPlayer(53, "Bot")
	out = GL.record({tier = 18, secs = 700, players = 1, finishers = {[53] = {name = "Bot", player = bot}, [51] = {name = "Ladder", player = a}}})
	eq(out[53], nil, "a tester bot is skipped"); ok(out[51] ~= nil, "the real player is not")
	eq(count("INSERT INTO `chaos_greater_rift` "), 1, "one ladder row, the player's")
	eq(#lbCalls, 1, "one weekly board entry")
	-- below the first Greater tier nothing is written
	reset()
	eq(next(GL.record({tier = 15, secs = 100, players = 1, finishers = {[51] = {name = "Ladder", player = a}}})), nil, "tier 15 is no Greater result")
	eq(#queries, 0, "no query")
	-- the pinnacle fragment: guarded, works without the system, calls it with a won roll
	reset()
	local realRandom = math.random
	math.random = function() return 1 end
	GL.record({tier = 40, secs = 900, players = 1, finishers = {[51] = {name = "Ladder", player = a}}})
	ok(true, "no pinnacle system: no error")
	ChaosPinnacle = {grantFragment = function(player, source, ctx) pinnacle[#pinnacle + 1] = {player, source, ctx} end}
	GL.record({tier = 40, secs = 900, players = 1, finishers = {[51] = {name = "Ladder", player = a}}})
	eq(#pinnacle, 1, "the pinnacle system is called on a won roll"); eq(pinnacle[1][2], "greater_rift", "with the source")
	eq(pinnacle[1][3].tier, 40, "and the tier")
	math.random = function() return 100000 end
	GL.record({tier = 40, secs = 900, players = 1, finishers = {[51] = {name = "Ladder", player = a}}})
	eq(#pinnacle, 1, "a lost roll does not call it")
	ChaosPinnacle = {grantFragment = function() error("pinnacle broke") end}
	math.random = function() return 1 end
	GL.record({tier = 40, secs = 900, players = 1, finishers = {[51] = {name = "Ladder", player = a}}})
	ok(true, "a failing pinnacle system never breaks the run's end")
	math.random = realRandom
	ChaosPinnacle = nil
end

-- delivery: the unpaid rows go to the character once, marked first
do
	reset()
	local a = newPlayer(61, "Paid")
	rowsFor["WHERE `player_id` = 61 AND `rewarded` = 0"] = {
		{season = 3, kind = "pb", slot = 17, tier = 17, place = 0, label = "", fate = 2, upheaval = 4, fragments = 12, gold = 175000},
		{season = 2, kind = "season", slot = 0, tier = 30, place = 1, label = "Greater Champion", fate = 40, upheaval = 80, fragments = 150, gold = 0}}
	local given = {}
	Chaos.giveItem = function(player, id, count) given[id] = (given[id] or 0) + count return count end
	eq(GL.deliverPending(a), 2, "two rows delivered")
	eq(count("UPDATE `chaos_greater_rift_rewards` SET `rewarded` = 1"), 2, "each marked paid")
	local first
	for i, q in ipairs(queries) do if q:find("UPDATE", 1, true) then first = first or i end end
	ok(first == 1, "the mark is written before the items")
	eq(given[cfg.greater.rewards.best.orbFate.id], 42, "Orbs of Fate"); eq(given[cfg.greater.rewards.best.orbUpheaval.id], 84, "Orbs of Upheaval")
	eq(given[cfg.greater.rewards.best.fragments.id], 162, "omen fragments"); eq(a.bank, 175000, "gold to the bank")
	ok(#a.msgs >= 2, "a message each")
end

-- the season end: the brackets are written once per character and mode; the check pays seasons that ended, once
do
	reset()
	local rank = {{player_id = 71, name = "One", group_id = 1, voc = 4, best_tier = 40, best_time = 900},
		{player_id = 72, name = "Two", group_id = 1, voc = 8, best_tier = 38, best_time = 900},
		{player_id = 73, name = "Staff", group_id = 5, voc = 4, best_tier = 90, best_time = 1}}
	rowsFor["FROM `chaos_greater_rift` t JOIN"] = rank
	local awards = GL.processSeason(5)
	eq(#awards, 4, "two characters on two boards: solo and party rows share the scripted rank")
	eq(count("INSERT IGNORE INTO `chaos_greater_rift_rewards`"), 4, "one reward row per character and mode")
	local champion = 0
	for _, q in ipairs(queries) do if q:find("Greater Champion", 1, true) then champion = champion + 1 end end
	eq(champion, 2, "the first of the knights, solo and party, gets the first bracket")
	ok(count("'season'") == 4, "kind season")
	-- the check: the stored season is the marker
	reset()
	local cfgRows = {}
	local realStore = db.storeQuery
	local stored = {}
	db.storeQuery = function(q)
		if q:find("server_config", 1, true) and q:find("SELECT", 1, true) and stored.v then return 1 end
		return false
	end
	result.getString = function() return tostring(stored.v) end
	local realQuery = db.query
	db.query = function(q)
		queries[#queries + 1] = q
		local v = q:match("VALUES %('chaos_greater_rift_season_done', '(%-?%d+)'%)")
		if v then stored.v = tonumber(v) end
		return true
	end
	local cur = GL.currentSeason()
	eq(GL.checkSeasons(true), 0, "a new server pays nothing")
	eq(stored.v, cur - 1, "and stores the season before this one")
	stored.v = cur - 3
	rowsFor["FROM `chaos_greater_rift` t JOIN"] = {}
	eq(GL.checkSeasons(true), 2, "two ended seasons are paid")
	eq(stored.v, cur - 1, "the marker is the last one paid")
	eq(GL.checkSeasons(true), 0, "once")
	db.storeQuery, db.query = realStore, realQuery
end

-- the text window
do
	reset()
	local a = newPlayer(81, "Reader")
	rowsFor["FROM `chaos_greater_rift` WHERE"] = {{mode = 0, voc = 4, best_tier = 33, best_time = 754, runs = 4}}
	local text = GL.text(a)
	ok(text:find("tier 33 in 12:34", 1, true) ~= nil, "the character's own best is in the text")
	ok(text:find("Top", 1, true) ~= nil, "the boards are in the text")
end

print(string.format("greater_rift_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
