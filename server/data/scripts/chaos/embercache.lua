-- The Ember Cache, the Daily Spark and the day book (client game_embercache, extended opcode ChaosOpcodes.emberCache =
-- 174; server/README.md "Ember Cache, Daily Spark and the day book"). Rules: embercache_core.lua and daybook_core.lua
-- (pure, tests/embercache_test.lua); numbers: embercache_config.lua.
--
-- Every activity gives Ember points; the day's first points count double and light the Daily Spark, the week's points
-- fill three Ember Cache milestones. Rewards are given at once (gold to the bank, items to the backpack, else the inbox)
-- with a toast. The day book shows what the character did today; the last day of play is told at the next login.
--
-- Where the points come from (hooks installed at startup and again every minute, through ChaosWrapChain):
--   kills         CreatureEvent kill: monsters without a master; party members on the same floor near the kill count
--                 it too (each kill once per character)
--   counters      ChaosAchievements.progress (wrapped): the counters of embercache_config.lua `stats`
--   journey       ChaosSeasonJourney.emit (wrapped): dungeon_clears, descent_runs (dungeons.lua, descent.lua)
--   tower         ChaosTower.recordRun (wrapped): a run with a floor cleared
-- The day book: experience (EventCallback onGainExperience at cfg.expIndex), kills, loot and supplies of the hunt
-- tracker (ChaosHunt.addLoot / addSupply wrapped; counted while the tracker runs, as in its window), deaths, levels,
-- time online, Ember points.
--
-- Protocol (JSON {action, data}):
--   client -> server  open | close | get
--   server -> client  state {open = 1 | nil, week, day, src, book} (embercache_core.lua K.view, daybook_core.lua D.view)
-- Assumed engine API (TFS 1.4): Player storages, getBankBalance/setBankBalance, addItem, getInbox, getParty,
-- CreatureEvent login/logout/kill/death/extendedopcode, EventCallback onGainExperience, GlobalEvent startup/think.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/embercache_core.lua")
dofile("data/scripts/chaos/daybook_core.lua")
if not (ChaosWrapChain and ChaosWrapChain.wrap) then
	dofile("data/scripts/chaos/wrapchain_core.lua")
end
ChaosEmberCacheConfig = dofile("data/scripts/chaos/embercache_config.lua")

ChaosEmberCache = ChaosEmberCache or {}
local E = ChaosEmberCache
local K = ChaosEmberCacheCore
local D = ChaosDayBookCore
local OPCODE = ChaosOpcodes.emberCache or 174

E.st = E.st or {} -- player id -> cache state
E.book = E.book or {} -- player id -> day book
E.loginAt = E.loginAt or {} -- player id -> os.time() the running stretch started (seconds not in the book yet)
E.watch = E.watch or {} -- player id -> true while the window is open
E.pushAt = E.pushAt or {} -- player id -> os.mtime of the last push
E.lastKill = E.lastKill or {} -- player id -> creature id of the last kill credited
E.sessionGuid = E.sessionGuid or setmetatable({}, {__mode = "k"}) -- hunt session -> guid

local function cfg()
	return ChaosEmberCacheConfig
end

local function log(text)
	print("[Chaos ember cache] " .. text)
end

for _, p in ipairs(K.validate(cfg())) do
	log("embercache_config.lua: " .. p)
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- ---------------------------------------------------------------- storages
local function getter(player, base)
	return function(off) return player:getStorageValue(base + off) end
end

local function setter(player, base)
	return function(off, v) player:setStorageValue(base + off, v) end
end

local function stateOf(player)
	local id = player:getId()
	local st = E.st[id]
	if not st then
		st = K.load(cfg(), getter(player, cfg().storage.base))
		E.st[id] = st
	end
	return st
end

local function save(player)
	local id = player:getId()
	if E.st[id] then
		K.save(cfg(), E.st[id], setter(player, cfg().storage.base))
	end
	if E.book[id] then
		D.save(cfg(), E.book[id], setter(player, cfg().daybook.base))
	end
end

-- the day book of today; a new day closes the old one (told at login, see recap)
local function bookOf(player, t)
	local id = player:getId()
	t = t or os.time()
	local b = E.book[id]
	if not b then
		b = D.load(cfg(), getter(player, cfg().daybook.base))
		E.book[id] = b
	end
	local day = K.day(t, cfg().resetHour)
	if b.day ~= day then
		local old
		if b.day ~= 0 and E.loginAt[id] then
			b.seconds = b.seconds + math.max(0, t - E.loginAt[id])
			E.loginAt[id] = t
		end
		old, b = D.roll(b, day, player:getLevel())
		E.book[id] = b
		return b, old
	end
	return b
end

-- ---------------------------------------------------------------- texts
local function itemText(player, list)
	local parts = {}
	for _, it in ipairs(list or {}) do
		local ok, name = pcall(function() return ItemType(it.id):getName() end)
		name = ok and name and name ~= "" and name or ("item " .. it.id)
		parts[#parts + 1] = (it.count > 1 and (it.count .. "x ") or "") .. name
	end
	return table.concat(parts, ", ")
end

-- pack farming effects (data/lib/chaos_pack27_fx.lua, switch ChaosPack27Fx.PAIR27_FX, off): an effect on the player
-- for a buff state or reward; nothing while the switch is off
if not ChaosPack27Fx then
	pcall(dofile, "data/lib/chaos_pack27_fx.lua")
end
local function packFx(player, use)
	local P = ChaosPack27Fx
	if P and P.PAIR27_FX and P.send and player and player.getPosition then
		pcall(function() P.send(player:getPosition(), use) end)
	end
end

local function toast(player, title, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text)
	packFx(player, "embercache")
	if ChaosNotify and ChaosNotify.send then
		pcall(ChaosNotify.send, player, Chaos.t(player, title), text)
	end
end

-- ---------------------------------------------------------------- rewards
local function giveItems(player, list)
	local inbox = 0
	for _, it in ipairs(list or {}) do
		local ok, item = pcall(function() return player:addItem(it.id, it.count, false) end)
		if not ok or not item then
			local box = player:getInbox()
			local okBox = box and pcall(function() return box:addItem(it.id, it.count) end)
			if okBox then
				inbox = inbox + 1
			else
				log("could not give " .. it.count .. "x " .. it.id .. " to " .. player:getName())
			end
		end
	end
	return inbox
end

function E.give(player, reward)
	local gold = K.gold(reward, player:getLevel(), cfg().income)
	if gold > 0 then
		player:setBankBalance(player:getBankBalance() + gold)
	end
	local inbox = giveItems(player, reward.items)
	return gold, inbox
end

local function rewardText(player, gold, list, inbox)
	local items = itemText(player, list)
	local text
	if items ~= "" then
		text = Chaos.t(player, "%d gold to your bank and %s.", gold, items)
	else
		text = Chaos.t(player, "%d gold to your bank.", gold)
	end
	if inbox > 0 then
		text = text .. " " .. Chaos.t(player, "Your backpack was full: see your inbox.")
	end
	return text
end

-- ---------------------------------------------------------------- state push
local function itemInfo(id)
	local ok, cid, name = pcall(function()
		local it = ItemType(id)
		return it:getClientId(), it:getName()
	end)
	if ok then
		return cid, name
	end
	return id, "item " .. id
end

function E.view(player)
	local t = os.time()
	local st = stateOf(player)
	K.roll(st, t, cfg())
	local b = bookOf(player, t)
	local v = K.view(st, cfg(), t, player:getLevel(), itemInfo)
	local id = player:getId()
	v.book = D.view(b, player:getLevel(), E.loginAt[id] and (t - E.loginAt[id]) or 0)
	return v
end

local function send(player, open)
	local v = E.view(player)
	if open then
		v.open = 1
	end
	E.pushAt[player:getId()] = nowMs()
	Chaos.send(player, OPCODE, "state", v)
end
E.send = send

local function maybePush(player)
	local id = player:getId()
	if E.watch[id] and nowMs() - (E.pushAt[id] or 0) >= (cfg().pushMs or 2000) then
		send(player, false)
	end
end

-- ---------------------------------------------------------------- crediting
-- `units` of a source for an online character: points, the Spark, the milestones
function E.credit(player, source, units)
	local c = cfg()
	if not c.enabled or not player then
		return 0
	end
	local t = os.time()
	local st = stateOf(player)
	K.roll(st, t, c)
	local raw = K.addUnits(st, c, source, units)
	if raw <= 0 then
		K.save(c, st, setter(player, c.storage.base))
		return 0
	end
	local res = K.addPoints(st, c, raw)
	local b = bookOf(player, t)
	D.add(b, "points", res.counted)
	-- the state is written before anything is given
	save(player)
	if res.spark then
		local gold, inbox = E.give(player, c.daily.reward)
		toast(player, "Daily Spark", Chaos.t(player, "Daily Spark lit: %s", rewardText(player, gold, c.daily.reward.items,
			inbox)))
	end
	for _, i in ipairs(res.tiers) do
		local tier = c.tiers[i]
		local gold, inbox = E.give(player, tier)
		toast(player, "Ember Cache", Chaos.t(player, "Ember Cache milestone %d of %d: %s", i, #c.tiers,
			rewardText(player, gold, tier.items, inbox)))
	end
	maybePush(player)
	return res.counted
end

-- who: a player, a guid, or {guid, name} (the shapes ChaosAchievements.progress takes) -> the online player or nil
local function online(who)
	if type(who) == "userdata" or (type(who) == "table" and who.getGuid) then
		return who
	end
	local guid = type(who) == "table" and tonumber(who.guid) or tonumber(who)
	if not guid then
		return nil
	end
	for _, p in ipairs(Game.getPlayers()) do
		if p:getGuid() == guid then
			return p
		end
	end
	return nil
end
E.online = online

local function creditMapped(map, who, key, amount)
	local m = map and map[key]
	if not m then
		return
	end
	local n = (amount == nil and 1 or tonumber(amount) or 0) * (m[2] or 1)
	if n <= 0 then
		return
	end
	local p = online(who)
	if p then
		E.credit(p, m[1], n)
	end
end

-- the characters who get a kill: the killer, and its party members on the same floor near the monster
function E.killers(player, pos)
	local out = {player}
	local party = player.getParty and player:getParty()
	if not party or not pos then
		return out
	end
	local members = party:getMembers() or {}
	members[#members + 1] = party:getLeader()
	local range = cfg().partyRange or 30
	for _, m in ipairs(members) do
		if m and m:getId() ~= player:getId() then
			local p = m:getPosition()
			if p.z == pos.z and math.abs(p.x - pos.x) <= range and math.abs(p.y - pos.y) <= range then
				out[#out + 1] = m
			end
		end
	end
	return out
end

function E.onKill(player, target)
	if not cfg().enabled or not player or not player:isPlayer() or not target or not target:isMonster()
			or target:getMaster() then
		return
	end
	local tid = target:getId()
	for _, p in ipairs(E.killers(player, target:getPosition())) do
		local pid = p:getId()
		if E.lastKill[pid] ~= tid then
			E.lastKill[pid] = tid
			D.add(bookOf(p), "kills", 1)
			E.credit(p, "kill", 1)
		end
	end
end

-- ---------------------------------------------------------------- day book feeds
local function hookLog(e)
	log("hook: " .. tostring(e))
end

-- the character of a hunt session (ChaosHunt.sessions[guid] = session)
local function playerOfSession(s)
	local guid = E.sessionGuid[s]
	if not guid then
		for g, x in pairs(ChaosHunt and ChaosHunt.sessions or {}) do
			if x == s then
				guid = g
				E.sessionGuid[s] = g
				break
			end
		end
	end
	return guid and online(guid) or nil
end

local function onLoot(res, s, corpse)
	local p = s and playerOfSession(s)
	if not p then
		return
	end
	local b = bookOf(p)
	D.add(b, "loot", tonumber(res[1]) or 0)
	for _, e in pairs(corpse or {}) do
		local n = math.floor(tonumber(e.n) or 0)
		if n > 0 then
			if e.u then
				D.add(b, "uniques", n)
			elseif e.o then
				D.add(b, "orbs", n)
			elseif (tonumber(e.r) or 0) > 0 then
				D.add(b, "rares", n)
			end
		end
	end
end

local function onSupply(res, s)
	local p = s and playerOfSession(s)
	if p then
		D.add(bookOf(p), "sup", tonumber(res[1]) or 0)
	end
end

function E.installHooks()
	local W = ChaosWrapChain
	W.wrap(ChaosAchievements, "progress", "embercache_ach", function(res, who, key, amount)
		creditMapped(cfg().stats, who, key, amount)
	end, hookLog)
	W.wrap(ChaosSeasonJourney, "emit", "embercache_emit", function(res, who, stat, value, mode)
		if mode == nil or mode == "add" then
			creditMapped(cfg().emits, who, stat, value)
		end
	end, hookLog)
	W.wrap(ChaosTower, "recordRun", "embercache_tower", function(res, player, floorsCleared)
		if player and (tonumber(floorsCleared) or 0) > 0 then
			local p = online(player)
			if p then
				E.credit(p, "tower", 1)
			end
		end
	end, hookLog)
	W.wrap(ChaosHunt, "addLoot", "embercache_loot", onLoot, hookLog)
	W.wrap(ChaosHunt, "addSupply", "embercache_supply", onSupply, hookLog)
end

-- ---------------------------------------------------------------- login: the last day of play
function E.recap(player, old)
	if not D.used(old) or old.seconds < (cfg().recapMinSeconds or 0) then
		return false
	end
	local text = Chaos.t(player, "Your last day of play (%s): %s experience, %d kills, %s gold of loot, %d Ember points.",
		D.date(old.day), D.short(old.xp), old.kills, D.short(old.loot), old.points)
	toast(player, "Day book", text)
	return true
end

function E.login(player)
	local id = player:getId()
	E.st[id], E.book[id], E.lastKill[id] = nil, nil, nil
	local t = os.time()
	local b = E.book[id] or D.load(cfg(), getter(player, cfg().daybook.base))
	E.book[id] = b
	local day = K.day(t, cfg().resetHour)
	if b.day ~= day then
		local old = b
		E.book[id] = D.new(day, player:getLevel())
		E.recap(player, old)
	end
	E.loginAt[id] = t
	local st = stateOf(player)
	K.roll(st, t, cfg())
	save(player)
end

function E.logout(player)
	local id = player:getId()
	local t = os.time()
	local b = bookOf(player, t)
	if E.loginAt[id] then
		b.seconds = b.seconds + math.max(0, t - E.loginAt[id])
	end
	save(player)
	E.st[id], E.book[id], E.loginAt[id], E.watch[id], E.pushAt[id], E.lastKill[id] = nil, nil, nil, nil, nil, nil
end

-- ---------------------------------------------------------------- events
local xp = EventCallback
xp.onGainExperience = function(player, source, exp, rawExp)
	if cfg().enabled and player and (tonumber(exp) or 0) > 0 then
		local ok, err = pcall(function() D.add(bookOf(player), "xp", exp) end)
		if not ok then
			log("experience: " .. tostring(err))
		end
	end
	return exp
end
xp:register(cfg().expIndex or 1001)

local kill = CreatureEvent("ChaosEmberCacheKill")
function kill.onKill(player, target)
	local ok, err = pcall(E.onKill, player, target)
	if not ok then
		log("kill: " .. tostring(err))
	end
	return true
end
kill:register()

local death = CreatureEvent("ChaosEmberCacheDeath")
function death.onDeath(creature)
	if creature and creature:isPlayer() then
		pcall(function() D.add(bookOf(creature), "deaths", 1) end)
	end
	return true
end
death:register()

local login = CreatureEvent("ChaosEmberCacheLogin")
function login.onLogin(player)
	player:registerEvent("ChaosEmberCacheKill")
	player:registerEvent("ChaosEmberCacheDeath")
	player:registerEvent("ChaosEmberCacheLogout")
	player:registerEvent("ChaosEmberCacheExtended")
	local ok, err = pcall(E.login, player)
	if not ok then
		log("login: " .. tostring(err))
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosEmberCacheLogout")
function logout.onLogout(player)
	local ok, err = pcall(E.logout, player)
	if not ok then
		log("logout: " .. tostring(err))
	end
	return true
end
logout:type("logout")
logout:register()

-- ---------------------------------------------------------------- the junk orb offering (cfg().offering)
-- The window's "Offer junk orbs" button: "offerQuote" answers what an offer would take and give (action "offer"), and
-- "offer" does it. Everything is decided here from the backpack: the client sends no number. The orbs leave the
-- backpack before a single point is credited, a refused removal credits only what was taken (the rest goes back).
local BACKPACK = CONST_SLOT_BACKPACK or 3

local function attr(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	return ok and v or nil
end

local function call(item, method)
	local ok, v = pcall(function() return item[method](item) end)
	return ok and v or nil
end

-- the junk orb stacks in the backpack and the bags in it: {itemId -> {stacks, total}}; locked orbs (the item lock,
-- "chaos_locked") and store orbs never count
local function junkStacks(player)
	local want = {}
	for _, id in ipairs((cfg().offering or {}).orbs or {}) do
		want[id] = true
	end
	local out = {}
	local function walk(container, depth)
		for i = 0, (tonumber(call(container, "getSize")) or 0) - 1 do
			local item = container:getItem(i)
			if item then
				local id = item:getId()
				local locked = tonumber(attr(item, "chaos_locked")) or 0
				if want[id] and locked == 0 and call(item, "isStoreItem") ~= true then
					local e = out[id]
					if not e then
						e = {stacks = {}, total = 0}
						out[id] = e
					end
					e.stacks[#e.stacks + 1] = item
					e.total = e.total + math.max(1, tonumber(call(item, "getCount")) or 1)
				end
				if call(item, "isContainer") == true and depth < 6 then
					walk(item, depth + 1)
				end
			end
		end
	end
	local bag = player:getSlotItem(BACKPACK)
	if bag and call(bag, "isContainer") == true then
		walk(bag, 1)
	end
	return out
end

local function offerPlan(player)
	local st = stateOf(player)
	K.roll(st, os.time(), cfg())
	local stacks = junkStacks(player)
	local have = {}
	for id, e in pairs(stacks) do
		have[id] = e.total
	end
	return K.offerPlan(cfg(), have, st.caps.offering), stacks
end

-- n orbs out of the stacks; returns how many left the backpack
local function takeFrom(stacks, n)
	local taken = 0
	for _, item in ipairs(stacks or {}) do
		if taken >= n then
			break
		end
		local count = math.max(1, tonumber(call(item, "getCount")) or 1)
		local k = math.min(count, n - taken)
		local ok
		if k < count then
			ok = item:remove(k)
		else
			ok = item:remove()
		end
		if not ok then
			break
		end
		taken = taken + k
	end
	return taken
end

local function offerLimited(player)
	return Chaos.limited and Chaos.limited(player, "embercache.offering", (cfg().offering or {}).requestMs or 1500)
end

-- what an offer would do now (the confirmation of the window)
function E.offerQuote(player)
	if not cfg().enabled or offerLimited(player) then
		return nil
	end
	local plan = offerPlan(player)
	local quote = {orbs = plan.orbs, points = plan.points, room = plan.room, per = plan.per, carried = plan.carried}
	Chaos.send(player, OPCODE, "offer", quote)
	return quote
end

-- the offer: whole points only, at most the day's room. Returns the points credited.
function E.offer(player)
	if not cfg().enabled or offerLimited(player) then
		return 0
	end
	local plan, stacks = offerPlan(player)
	if plan.points <= 0 then
		if plan.room <= 0 then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player,
				"You have offered all the junk orbs the Ember Cache takes today. More tomorrow."))
		else
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player,
				"You need at least %d junk orbs in your backpack (locked orbs do not count).", plan.per))
		end
		return 0
	end
	local taken, got = 0, {}
	for _, t in ipairs(plan.take) do
		local n = takeFrom(stacks[t.id] and stacks[t.id].stacks, t.n)
		got[#got + 1] = {id = t.id, n = n}
		taken = taken + n
		if n < t.n then
			break
		end
	end
	local points = math.min(plan.points, math.floor(taken / plan.per))
	-- a removal the engine refused: what does not make a whole point goes back
	local back = taken - points * plan.per
	for i = #got, 1, -1 do
		if back <= 0 then
			break
		end
		local k = math.min(back, got[i].n)
		if k > 0 then
			local rest = k - Chaos.giveItem(player, got[i].id, k)
			local inbox = rest > 0 and player:getInbox()
			if inbox then
				inbox:addItem(got[i].id, rest)
			end
			back = back - k
		end
	end
	if points <= 0 then
		return 0
	end
	local counted = E.credit(player, "offering", points)
	local left = math.max(0, plan.room - points)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
		"You offered %d junk orbs to the Ember Cache: %d Ember points (%d more points today).", points * plan.per,
		counted, left))
	log(string.format("%s offered %d junk orbs for %d points", player:getName(), points * plan.per, points))
	send(player, false)
	return points
end

local ext = CreatureEvent("ChaosEmberCacheExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	if Chaos.limited and Chaos.limited(player, "embercache." .. tostring(msg.action), 300) then
		return
	end
	local action = msg.action
	if action == "open" then
		E.watch[player:getId()] = true
		send(player, true)
	elseif action == "close" then
		E.watch[player:getId()] = nil
	elseif action == "get" then
		send(player, false)
	elseif action == "offerQuote" then
		E.offerQuote(player)
	elseif action == "offer" then
		E.offer(player)
	end
end
ext:type("extendedopcode")
ext:register()

local startup = GlobalEvent("ChaosEmberCacheStartup")
function startup.onStartup()
	E.installHooks()
	return true
end
startup:register()

-- hooks again after a /reload of a wrapped script; open windows refreshed
local think = GlobalEvent("ChaosEmberCacheThink")
function think.onThink()
	E.installHooks()
	for _, p in ipairs(Game.getPlayers()) do
		if E.watch[p:getId()] then
			pcall(send, p, false)
		end
	end
	return true
end
think:interval(60000)
think:register()
