-- Run from the server/ folder: luajit tests/harvest_event_test.lua (and lua5.3; CI runs both)
-- The Haunted Harvest (server/README.md "Haunted Harvest"): the pair 33 switch and the kit table
-- (data/lib/chaos_harvest_art.lua, chaos_pack33_kit.lua: the decay chains of the mechanics), the config
-- (harvest_event_config.lua: storages, action ids, items, the monsters it names, the charm pool, every message in
-- pt-BR), the pure rules of harvest_event_core.lua (the window over the new year, the forced state, pumpkins, graves,
-- coffins, cauldrons, the circle, the boss's phases and ward, the charm, the shop), the generated places
-- (harvest_places.lua against the kit) and then harvest_event.lua on a mocked engine: closed while the switch is off,
-- the dressing, open and shut, a pumpkin harvest, the seal and its step, the ritual circle and its portal, the boss's
-- ritual phase, the charm, the staff command and the admin panel action.
local checks, failures = 0, 0
local function check(c, m)
	checks = checks + 1
	if not c then
		failures = failures + 1
		print("FAIL " .. m)
	end
end
local function eq(a, b, m)
	check(a == b, m .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local art = dofile("data/lib/chaos_harvest_art.lua")
local kit = dofile("data/lib/chaos_pack33_kit.lua")
local cfg = dofile("data/scripts/chaos/harvest_event_config.lua")
local places = dofile("data/scripts/chaos/harvest_places.lua")
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
dofile("data/scripts/chaos/harvest_event_core.lua")
local K = ChaosHarvestCore

-- ---------------------------------------------------------------- the switch and the kit
eq(art.PAIR33, false, "the pair 33 switch is off until the pair ships")
eq(kit.first, 41093, "kit ids from 41093") eq(kit.last, 41607, "to 41607 (the boss corpse)")
local nItems = 0
for _ in pairs(kit.items) do nItems = nItems + 1 end
eq(nItems, 515, "514 kit items and the corpse")
eq(art.kit.first, 41093, "the switch file reads the kit table")
local S = kit.states
local function chain(from, to, label)
	local d = kit.decay[from]
	check(d ~= nil and d.to == to and d.seconds > 0, label)
end
for s = 1, 4 do
	chain(S.pumpkin_growth[tostring(s)], S.pumpkin_growth[tostring(s + 1)], "pumpkin stage " .. s .. " grows")
end
check(kit.decay[S.pumpkin_growth["5"]] == nil, "a ripe pumpkin waits for the harvest")
chain(S.pumpkin_growth["6"], S.pumpkin_growth["1"], "a woken pumpkin burns down to a mound")
chain(S.crypt_seal.breaking, S.crypt_seal.open, "the seal breaks open")
chain(S.crypt_seal.open, S.crypt_seal.sealed, "and seals again")
chain(S.grave.dug, S.grave.coffin_closed, "a dug grave shows its coffin")
chain(S.grave.coffin_bursting, S.grave.coffin_open_empty, "a coffin bursts open")
chain(S.grave.coffin_open_empty, S.grave.mound, "an empty grave is filled again")
chain(S.coffin_up.opening, S.coffin_up.open_skeleton, "an upright coffin opens")
chain(S.coffin_up.open_skeleton, S.coffin_up.closed, "and closes again")
chain(S.ritual_circle.lighting, S.ritual_circle.flare, "the circle flares")
chain(S.ritual_circle.flare, S.ritual_circle.portal_open, "the portal opens")
chain(S.ritual_circle.portal_open, S.ritual_circle.closing, "the portal closes")
chain(S.ritual_circle.closing, S.ritual_circle.dormant, "the circle sleeps again")
chain(S.cursed_bell.tolling, S.cursed_bell.still, "the bell falls still")
for _, rest in ipairs({S.grave.mound, S.coffin_up.closed, S.crypt_seal.sealed, S.ritual_circle.dormant,
		S.cursed_bell.still, S.cauldron.treat}) do
	check(kit.decay[rest] == nil, "a resting state " .. rest .. " never changes on its own")
end
check(kit.items.seal_sealed.block and not kit.items.seal_open.block, "the sealed seal blocks, the open one not")
check(kit.items.grave_coffin_closed.block and not kit.items.grave_mound.block, "a buried coffin blocks, a mound not")
eq(kit.items.portal_open.w, 3, "the portal is 3 x 3")

-- the monsters: every name of the switch file and the config has a file of that name and that stock look
local files = {}
for _, f in ipairs({"hexwhisker_cat", "gallows_raven", "barrowbone_archer", "barrowbone_reaver", "reapmoon_lycan",
		"thornhex_crone", "gourdmaw_brute", "strawhusk_stalker", "lamenting_shade", "boss/malvorn_the_hollow_king"}) do
	local fh = io.open("data/monster/monsters/chaos/harvest/" .. f .. ".xml", "r")
	check(fh ~= nil, "monster file " .. f)
	if fh then
		local x = fh:read("*a")
		fh:close()
		local name = x:match('<monster name="([^"]+)"')
		files[name] = {look = tonumber(x:match('<look type="(%d+)"')), lvl = tonumber(x:match('<level min="(%d+)"')),
			boss = x:find('isboss="1"', 1, true) ~= nil, x = x}
	end
end
local nMon = 0
for name, m in pairs(art.monsters) do
	nMon = nMon + 1
	check(files[name] ~= nil, name .. ": a monster file")
	eq(files[name] and files[name].look, m.stock, name .. ": the stock look while the switch is off")
	check(m.look >= 2658 and m.look <= 2667, name .. ": a kit look")
	eq(art.lookOf(name, 1), m.stock, name .. ": lookOf gives the stock look while off")
end
eq(nMon, 10, "five monsters, four critters and the boss")
eq(art.lookOf("Someone Else", 77), 77, "other monsters keep their look")
check(files[cfg.boss.name] and files[cfg.boss.name].boss, "the boss is a boss")
check(files[cfg.boss.name].x:find('HarvestKingHealth', 1, true) and files[cfg.boss.name].x:find('HarvestKingDeath', 1, true),
	"the boss carries the two creature events")
for name, m in pairs(files) do
	check(m.lvl >= 450 and m.lvl <= 660, name .. ": level in the event band")
	check(m.x:find('id="41620"', 1, true) ~= nil, name .. ": drops hollow candy")
end
local function known(name)
	return files[name] ~= nil
end
for _, list in ipairs({cfg.pumpkin.wake, cfg.grave.raise, cfg.coffin.raise, cfg.cauldron.trick, cfg.boss.court,
		{cfg.bell.raven}}) do
	for _, n in ipairs(list) do
		check(known(n), "config names the event monster " .. n)
	end
end

-- ---------------------------------------------------------------- the config
eq(cfg.storage.day, 7102800, "player storages in the block 7102800-7102809")
check(cfg.storage.pumpkinCandy <= 7102809 and cfg.storage.bossDay <= 7102809, "inside the block")
eq(cfg.globalStorage.force, 7102810, "the forced state")
check(cfg.aid.portal >= 47720 and cfg.aid.circle <= 47729 and cfg.aid.portal ~= cfg.aid.seal and cfg.aid.seal ~= cfg.aid.circle,
	"three action ids of 47720-47729")
eq(cfg.items.candy, 41620, "hollow candy") eq(cfg.items.charm, 41623, "hollow charm")
local csv = io.open("data/items/harvest_items.csv", "r"):read("*a")
for k, v in pairs(cfg.items) do
	check(csv:find("\n" .. v .. ",", 1, true) ~= nil, "item " .. k .. " is in harvest_items.csv")
end
for _, o in ipairs(cfg.shop) do
	check(o.price > 0 and #o.items > 0 and o.name, "shop offer " .. o.key)
end
local cos = dofile("data/scripts/chaos/cosmetics_config.lua")
local cosKeys = {}
for _, c in ipairs(cos.cosmetics) do cosKeys[c.key] = c end
for _, e in ipairs(cfg.charmPool) do
	check(e.kind == "cosmetic" or e.kind == "exclusive", "charm pool kind " .. e.kind)
	if e.kind == "cosmetic" then
		check(cosKeys[e.key] ~= nil, "charm pool cosmetic " .. e.key .. " exists")
	end
end
for k, v in pairs(cfg.messages) do
	check(pt[v] ~= nil, "message " .. k .. " has pt-BR")
end
check(pt[cfg.calendar.name] ~= nil and pt[cfg.calendar.description] ~= nil, "the event's name and line in pt-BR")
local cp = dofile("data/scripts/chaos/cityportals_config.lua")
check(cp.kinds.harvest and pt[cp.kinds.harvest.name] and pt[cp.kinds.harvest.text], "the Harvest Portal kind, translated")

-- ---------------------------------------------------------------- the window and the forced state
local function at(y, mo, d)
	return os.time({year = y, month = mo, day = d, hour = 12})
end
eq(K.inWindow(cfg, at(2026, 10, 24)), false, "Oct 24: before")
eq(K.inWindow(cfg, at(2026, 10, 25)), true, "Oct 25: the first day")
eq(K.inWindow(cfg, at(2026, 10, 31)), true, "Oct 31")
eq(K.inWindow(cfg, at(2026, 11, 5)), true, "Nov 5: the last day")
eq(K.inWindow(cfg, at(2026, 11, 6)), false, "Nov 6: after")
local wrap = {window = {from = {month = 12, day = 20}, to = {month = 1, day = 5}}}
eq(K.inWindow(wrap, at(2026, 12, 31)), true, "a window over the new year: Dec 31")
eq(K.inWindow(wrap, at(2027, 1, 3)), true, "Jan 3")
eq(K.inWindow(wrap, at(2027, 1, 6)), false, "Jan 6")
eq(K.isOpen(cfg, at(2026, 10, 30), 0, false), false, "never while the switch is off")
eq(K.isOpen(cfg, at(2026, 10, 30), 1, false), false, "not even forced")
eq(K.isOpen(cfg, at(2026, 10, 30), 0, true), true, "in the window")
eq(K.isOpen(cfg, at(2026, 7, 1), 1, true), true, "forced open in July")
eq(K.isOpen(cfg, at(2026, 10, 30), 2, true), false, "forced shut in the window")
eq(K.forceOf("on"), 1, "on") eq(K.forceOf(" OFF "), 2, "off") eq(K.forceOf("auto"), 0, "auto") eq(K.forceOf("x"), nil, "x")
local s, e = K.windowRange(cfg, at(2026, 10, 21))
eq(os.date("%Y-%m-%d", s), "2026-10-25", "the next window starts Oct 25")
eq(os.date("%Y-%m-%d %H:%M", e), "2026-11-05 23:59", "and ends Nov 5")
s = K.windowRange(cfg, at(2026, 12, 1))
eq(os.date("%Y-%m-%d", s), "2027-10-25", "after the window: next year's")
eq(K.dayKey(at(2026, 10, 31)), 20261031, "dayKey")
local dyn = K.dynamicEntry(cfg, at(2026, 10, 30), 0)
eq(dyn.id, "harvest", "the runtime event") eq(os.date("%Y-%m-%d", dyn.untilTime), "2026-11-05", "until the window's end")
eq(K.dynamicEntry(cfg, 1000, 1).untilTime, 1000 + 2 * cfg.tickSeconds, "two ticks ahead while forced")

-- ---------------------------------------------------------------- the mechanics
local function fixed(values)
	local i = 0
	return function(a, b)
		i = i + 1
		local v = values[i] or a
		return math.max(a, math.min(b, v))
	end
end
local r = K.pumpkin(cfg, fixed({3, 10000, 10000}), 0)
eq(r.candy, 3, "a harvest's candy") eq(r.wake, nil, "no waking on a high roll") eq(r.charm, false, "no charm")
r = K.pumpkin(cfg, fixed({4, 1, 1, 1}), 0)
check(r.wake ~= nil and r.charm, "a low roll wakes the pumpkin and finds a charm")
r = K.pumpkin(cfg, fixed({4, 10000, 10000}), cfg.pumpkin.dailyCap - 1)
eq(r.candy, 1, "the daily cap trims the last harvest")
r = K.pumpkin(cfg, fixed({4}), cfg.pumpkin.dailyCap)
check(r.capped and r.candy == 0, "capped")
r = K.grave(cfg, fixed({2, 1, 1, 2, 1, 2}))
check(r.candy == 2 and r.key and #r.raise == 2, "a grave: candy, a key, two risen")
r = K.grave(cfg, fixed({1, 10000, 10000}))
check(not r.key and #r.raise == 0, "a quiet grave")
r = K.coffin(cfg, fixed({1, 1, 1, 1}))
check(r.key == false and #r.raise == 1, "a coffin never holds a key")
check(K.cauldron(cfg, fixed({1, 1})).trick ~= nil, "trick")
eq(K.cauldron(cfg, fixed({10000, 5})).candy, 5, "treat")
local n, lit = K.circleAdd(0, cfg)
check(n == 1 and not lit, "one candle")
n, lit = K.circleAdd(cfg.circle.candles - 1, cfg)
check(n == 0 and lit, "the last candle lights the circle and the count starts again")
eq(K.bossPhase(cfg, 80, 74, {}), 1, "75 percent crossed")
eq(K.bossPhase(cfg, 80, 74, {true}), nil, "only once")
eq(K.bossPhase(cfg, 60, 20, {true}), 2, "a big hit runs the next phase first")
eq(K.bossPhase(cfg, 70, 60, {}), nil, "no threshold crossed")
eq(K.wardDamage(cfg, 1000), 500, "the ward halves the damage")
local owned = {kill_soulspark = true}
local pick = K.charmPick(cfg.charmPool, function(x) return owned[x.key] end, fixed({1}))
check(pick and pick.key ~= "kill_soulspark", "the charm picks a cosmetic the account lacks")
check(K.charmPick({{key = "a"}}, function() return true end, fixed({1})) == nil, "none left: nil")
eq(K.offer(cfg, "charm").price, 60, "an offer by key")
eq(K.offer(cfg, "1").key, cfg.shop[1].key, "an offer by number")
local o, why = K.trade(cfg, "charm", 10)
check(o == nil and why == "candy", "not enough candy")
check(K.trade(cfg, "charm", 60) ~= nil, "enough candy")
check(select(2, K.trade(cfg, "nothing", 999)) == "unknown", "an unknown offer")

-- ---------------------------------------------------------------- the generated places
local bad = K.checkPlaces(places, kit)
eq(#bad, 0, "harvest_places.lua against the kit" .. (bad[1] and (": " .. bad[1]) or ""))
eq(places.surface.plan, "haunted_harvest", "the surface plan") eq(places.catacombs.plan, "harvest_catacombs", "the crypt plan")
check(#places.pumpkins >= 20 and #places.graves >= 8 and #places.coffins >= 6 and #places.kingGraves >= 3,
	"enough pumpkins, graves and coffins")
local function inArea(p, a, w, h)
	return p.x >= a.origin.x and p.x < a.origin.x + w and p.y >= a.origin.y and p.y < a.origin.y + h and p.z == a.origin.z
end
for _, list in ipairs({places.pumpkins, places.graves, places.cauldrons, places.bells, {places.seal.anchor}}) do
	for _, p in ipairs(list) do
		check(inArea(p, places.surface, 156, 132), "a surface mechanic inside the surface area")
	end
end
for _, list in ipairs({places.coffins, places.kingGraves, {places.circle.anchor, places.circle.landing}}) do
	for _, p in ipairs(list) do
		check(inArea(p, places.catacombs, 112, 96), "a crypt mechanic inside the catacombs")
	end
end

-- ---------------------------------------------------------------- the engine file on a mocked engine
MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR, MESSAGE_STATUS_WARNING, MESSAGE_STATUS_CONSOLE_ORANGE = 19, 20, 21, 22
MESSAGE_STATUS_CONSOLE_BLUE = 4
CONST_ME_POFF, CONST_ME_MORTAREA, CONST_ME_FIREAREA, CONST_ME_TELEPORT, CONST_ME_BATS, CONST_ME_GIFT_WRAPS = 3, 18, 7, 11, 49, 40
CONST_ME_MAGIC_RED, CONST_ME_SMALLCLOUDS = 13, 12
COMBAT_HEALING, COMBAT_PHYSICALDAMAGE = 1024, 1
local world, created, monsters, log = {}, {}, {}, {}
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
local function newItem(id, pos)
	local it = {id = id, pos = pos, aid = 0, removed = false}
	function it:getId() return self.id end
	function it:isItem() return true end
	function it:transform(n) self.id = n return true end
	function it:decay() self.decaying = true return true end
	function it:getPosition() return self.pos end
	function it:setActionId(a) self.aid = a end
	function it:getActionId() return self.aid end
	function it:remove()
		local t = world[key(self.pos)]
		for i, x in ipairs(t and t.items or {}) do
			if x == self then table.remove(t.items, i) break end
		end
		self.removed = true
		return true
	end
	return it
end
local function tileAt(p, make)
	local k = key(p)
	if not world[k] and make then
		world[k] = {pos = p, ground = newItem(100, p), items = {}}
	end
	return world[k]
end
function Position(x, y, z)
	local p = {x = x, y = y, z = z}
	function p.sendMagicEffect() end
	return p
end
function Tile(p)
	local t = tileAt(p, true)
	return {getGround = function() return t.ground end,
		getItemById = function(_, id)
			for _, x in ipairs(t.items) do
				if x.id == id then return x end
			end
			return nil
		end}
end
local storages = {}
Game = {
	getStorageValue = function(k) return storages[k] or -1 end,
	setStorageValue = function(k, v) storages[k] = v end,
	createItem = function(id, count, pos)
		local it = newItem(id, Position(pos.x, pos.y, pos.z))
		table.insert(tileAt(pos, true).items, it)
		created[#created + 1] = it
		return it
	end,
	createMonster = function(name, pos) monsters[#monsters + 1] = name return {} end,
	getTowns = function() return {} end,
	getPlayers = function() return {} end,
	getSpectators = function() return {} end,
	broadcastMessage = function(text) log[#log + 1] = text end
}
local registered = {actions = {}, moves = {}, events = {}, globals = {}, talks = {}}
local function reg(kind)
	return function(name)
		local o = {name = name, ids = {}}
		function o:id(...) for _, i in ipairs({...}) do self.ids[#self.ids + 1] = i end end
		function o:aid(a) self.aidv = a end
		function o:type(t) self.t = t end
		function o:interval(ms) self.ms = ms end
		function o:separator() end
		function o:register() table.insert(registered[kind], self) end
		return o
	end
end
Action, MoveEvent, CreatureEvent, GlobalEvent, TalkAction = reg("actions"), reg("moves"), reg("events"), reg("globals"), reg("talks")
EventCallback = setmetatable({}, {__index = function() return function() end end})
function addEvent() end
json = {decode = function() return {} end}
local realPrint = print
print = function(text) log[#log + 1] = tostring(text) end
local ok, err = pcall(dofile, "data/scripts/chaos/harvest_event.lua")
print = realPrint
check(ok, "harvest_event.lua loads: " .. tostring(err))
local X = ChaosHarvest
local function findAction(id)
	for _, a in ipairs(registered.actions) do
		for _, i in ipairs(a.ids) do
			if i == id then return a end
		end
	end
end
local function findMove(aid)
	for _, m in ipairs(registered.moves) do
		if m.aidv == aid then return m end
	end
end
local function findEvent(name)
	for _, e in ipairs(registered.events) do
		if e.name == name then return e end
	end
end
check(findAction(S.pumpkin_growth["5"]) and findAction(S.grave.mound) and findAction(S.coffin_up.closed) and
	findAction(S.cauldron.treat) and findAction(S.cursed_bell.still) and findAction(cfg.items.key) and
	findAction(cfg.items.candle) and findAction(cfg.items.charm), "every mechanic has its action")
check(findMove(cfg.aid.portal) and findMove(cfg.aid.seal) and findMove(cfg.aid.circle), "the three steps")
check(findEvent("HarvestKingHealth") and findEvent("HarvestKingDeath"), "the boss's two creature events")

-- the switch off: nothing happens
local startup
for _, g in ipairs(registered.globals) do
	if g.name == "ChaosHarvestStartup" then startup = g end
end
print = function(text) log[#log + 1] = tostring(text) end
startup.onStartup()
print = realPrint
eq(#created, 0, "switch off: nothing placed")
eq(X.isOpen(at(2026, 10, 30)), false, "switch off: closed in the window")

-- the switch on: the dressing
ChaosHarvestArt.PAIR33 = true
local tp = Game.createItem(1387, 1, places.circle.teleport)
created = {}
print = function(text) log[#log + 1] = tostring(text) end
startup.onStartup()
print = realPrint
check(tp.removed, "the planned teleport under the circle is gone")
local nDecor = 0
for _, it in ipairs(created) do
	if it.id ~= 1387 then nDecor = nDecor + 1 end
end
local nMech = #places.pumpkins + #places.graves + #places.kingGraves + #places.coffins + #places.cauldrons + #places.bells + 2
eq(nDecor, #places.decor + nMech, "every set piece and mechanic placed")
check(Tile(places.seal.anchor):getItemById(S.crypt_seal.sealed) ~= nil, "the seal is sealed")
check(Tile(places.circle.anchor):getItemById(S.ritual_circle.dormant) ~= nil, "the circle sleeps")
eq(Tile(places.seal.tiles[1]):getGround():getActionId(), cfg.aid.seal, "the seal's ground carries its action id")
eq(Tile(places.circle.tiles[5]):getGround():getActionId(), cfg.aid.circle, "the circle's ground too")
created = {}
X.dress()
eq(#created, 0, "dressing twice places nothing more")

-- open and shut
local s1 = X.setForce("on")
check(X.open and s1:find("OPEN", 1, true), "forced open")
X.setForce("off")
check(not X.open, "forced shut")
X.setForce("auto")
eq(X.open, K.inWindow(cfg, os.time()), "auto: the window decides")
X.setForce("on")

-- a player
local function newPlayer()
	local p = {items = {}, st = {}, msgs = {}, pos = Position(1, 1, 7), acc = 7, group = 1}
	function p:addItem(id, n) self.items[id] = (self.items[id] or 0) + (n or 1) return true end
	function p:removeItem(id, n) self.items[id] = (self.items[id] or 0) - n return true end
	function p:getItemCount(id) return self.items[id] or 0 end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:sendTextMessage(t, text) self.msgs[#self.msgs + 1] = text end
	function p:teleportTo(pos) self.pos = pos end
	function p:getPlayer() return self end
	function p:getAccountId() return self.acc end
	function p:getPosition() return self.pos end
	function p:getId() return 5 end
	function p:getGroup() local g = self.group return {getId = function() return g end, getAccess = function() return g >= 4 end} end
	return p
end
local pl = newPlayer()
local ripe = Game.createItem(S.pumpkin_growth["5"], 1, places.pumpkins[1])
findAction(S.pumpkin_growth["5"]).onUse(pl, ripe)
check(pl.items[cfg.items.candy] and pl.items[cfg.items.candy] >= cfg.pumpkin.candy[1], "a harvest gives candy")
check(ripe.id == S.pumpkin_growth["1"] or ripe.id == S.pumpkin_growth["6"], "the pumpkin is a mound again (or woke)")
check(ripe.decaying, "and grows again")

-- the seal: a key breaks it, the step on the open seal leads down
local seal = Tile(places.seal.anchor):getItemById(S.crypt_seal.sealed)
local keyItem = newItem(cfg.items.key, pl.pos)
findAction(cfg.items.key).onUse(pl, keyItem, nil, seal)
eq(seal.id, S.crypt_seal.breaking, "the key breaks the seal")
seal:transform(S.crypt_seal.open)
findMove(cfg.aid.seal).onStepIn(pl, nil, places.seal.tiles[1], pl.pos)
eq(key(pl.pos), key(places.catacombs.arrival), "the open seal leads to the catacombs")

-- the circle: three candles light it, the open portal leads to the King's Crypt
local circle = Tile(places.circle.anchor):getItemById(S.ritual_circle.dormant)
for i = 1, cfg.circle.candles do
	findAction(cfg.items.candle).onUse(pl, newItem(cfg.items.candle, pl.pos), nil, circle)
end
eq(circle.id, S.ritual_circle.lighting, "three candles light the circle")
findMove(cfg.aid.circle).onStepIn(pl, nil, places.circle.tiles[1], pl.pos)
check(key(pl.pos) ~= key(places.circle.landing), "no way in while the portal is not open")
circle:transform(S.ritual_circle.portal_open)
findMove(cfg.aid.circle).onStepIn(pl, nil, places.circle.tiles[1], pl.pos)
eq(key(pl.pos), key(places.circle.landing), "the open portal leads into the King's Crypt")

-- the Harvest Portal
findMove(cfg.aid.portal).onStepIn(pl, nil, Position(2, 2, 7), Position(3, 3, 7))
eq(key(pl.pos), key(places.surface.arrival), "the Harvest Portal leads to the crossroads")

-- the boss: 75 percent crossed raises the court from the King's Crypt graves, then the ward
local boss = {hp = 100000, max = 100000, name = cfg.boss.name}
function boss:getId() return 900 end
function boss:getHealth() return self.hp end
function boss:getMaxHealth() return self.max end
function boss:getName() return self.name end
function boss:getPosition() return Position(0, 0, 8) end
monsters = {}
local health = findEvent("HarvestKingHealth")
boss.hp = 76000
local d1 = health.onHealthChange(boss, pl, 2000, COMBAT_PHYSICALDAMAGE, 0, 0)
eq(d1, 2000, "the hit that crosses the threshold lands in full")
eq(#monsters, #places.kingGraves * cfg.boss.perGrave, "a court member from every grave")
check(Tile(places.kingGraves[1]):getItemById(S.grave.coffin_bursting) ~= nil, "the King's graves burst")
local d2 = health.onHealthChange(boss, pl, 2000, COMBAT_PHYSICALDAMAGE, 0, 0)
eq(d2, 1000, "the ward halves the next hit")
local h2 = health.onHealthChange(boss, pl, 500, COMBAT_HEALING, 0, 0)
eq(h2, 500, "healing passes")

-- the charm
local granted = {}
ChaosCosmetics = {owns = function() return false end, grant = function(acc, k, src) granted[#granted + 1] = k .. ":" .. src return true end}
local charm = newItem(cfg.items.charm, pl.pos)
findAction(cfg.items.charm).onUse(pl, charm)
check(#granted == 1 and granted[1]:find(":harvest", 1, true), "the charm grants a cosmetic from the pool")
ChaosCosmetics.owns = function() return true end
local before = pl.items[cfg.items.candy] or 0
findAction(cfg.items.charm).onUse(pl, newItem(cfg.items.charm, pl.pos))
eq((pl.items[cfg.items.candy] or 0) - before, cfg.charmFallbackCandy, "owned all: candy instead")

-- staff: the talkaction, the panel action and the hook
local talk = registered.talks[1]
pl.group = 4
talk.onSay(pl, "/harvest", "status")
check(pl.msgs[#pl.msgs]:find("Haunted Harvest", 1, true) ~= nil, "/harvest status")
talk.onSay(pl, "/harvest", "off")
check(X.open and pl.msgs[#pl.msgs]:find("needs group", 1, true), "a gamemaster below group 5 cannot shut it")
pl.group = 5
talk.onSay(pl, "/harvest", "off")
check(not X.open, "group 5 shuts it")
local act = ChaosAdminPending["events.harvest"]
check(act and act.category == "events" and act.minGroup == 5, "the panel action")
local okA, text = act.handler(pl, {mode = "on"})
check(okA and X.open and text:find("OPEN", 1, true), "the panel opens it")
check(ChaosAdminHooks.haunted_harvest and ChaosAdminHooks.haunted_harvest.stop, "the event hook")
ChaosAdminHooks.haunted_harvest.stop()
eq(X.force(), 0, "the hook's stop sets it back to the window")

print(string.format("harvest_event_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
