-- Run from the server/ folder: luajit tests/catchup_test.lua (and lua5.3; CI runs both)
-- Time-friendly progression (server/README.md "Time-friendly progression (catchup)"): the rules of catchup_core.lua
-- (the leveling model, rested pool, returning player, alt catch-up, stamina factors, the experience with its ceiling,
-- loot and token factors, the config's own checks) and catchup.lua against a mocked engine (login: pool, boost started
-- and written, welcome once, best level; the experience callback spends the pool; advance; the buff bar items; the
-- loot and offline stamina API; season characters; logout).

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end
local function near(a, b, label, tol)
	check(type(a) == "number" and math.abs(a - b) <= (tol or 1e-6), label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/catchup_core.lua")
local K = ChaosCatchupCore
local cfg = dofile("data/scripts/chaos/catchup_config.lua")

-- ---------------------------------------------------------------- config
eq(#K.validate(cfg), 0, "the live config is valid: " .. table.concat(K.validate(cfg), "; "))
check(cfg.stamina.lootMult > 0, "low stamina never zeroes the loot")
eq(cfg.stamina.lowAt, 840, "the stock 14 h line")
check(cfg.stamina.offlineMult > 1, "faster offline regeneration")
check(cfg.xpIndex > 85 and cfg.xpIndex < 90, "after the experience cap (85), before the dungeon difficulty (90)")
local bad = {stamina = {lootMult = 0, xpMult = 0.5, offlineMult = 0.5}, maxXpMult = 0.5, model = {{1, 100, 0.3}, {50, 40, 1}},
	storage = {x = 7100000}}
eq(#K.validate(bad), 5, "a bad config: zero loot, slow regeneration, ceiling, model, storage")

-- ---------------------------------------------------------------- the leveling model
eq(K.expForLevel(1), 0, "level 1: 0 experience")
eq(K.expForLevel(2), 100, "level 2: 100 (the engine's formula)")
eq(K.expForLevel(8), 4200, "level 8: 4200")
near(K.hoursPerLevel(cfg, 50), 0.3 / 99, "1-100: 0.3 h over 99 levels")
near(K.hoursPerLevel(cfg, 950), 25.5 / 100, "900-1000")
near(K.hoursPerLevel(cfg, 1200), 25.5 / 100, "past the last band: its hours per level")
local perMin = K.xpPerMinute(cfg, 400)
near(perMin, (K.expForLevel(401) - K.expForLevel(400)) / (7.3 / 200 * 60), "experience per model minute at 400", 1e-3)

-- ---------------------------------------------------------------- rested
near(K.restedAfter(cfg, 0, 600), 0, "inside the grace: nothing")
near(K.restedAfter(cfg, 0, 600 + 3600), 2.5, "an hour offline: 2.5 minutes")
near(K.restedAfter(cfg, 0, 600 + 23 * 3600), 57.5, "a day away (23 h): about an hour")
eq(K.restedAfter(cfg, 0, 30 * 86400), cfg.rested.capMinutes, "the cap")
eq(K.restedAfter(cfg, 170, 600 + 8 * 3600), 180, "a full pool stays at the cap")
near(K.restedAfter(cfg, 200, 0), 180, "a pool above the cap (config lowered) is cut")
eq(K.restedAfter({rested = {enabled = false}}, 12, 86400), 12, "switched off: unchanged")

-- the Rested Vial (Candlemarks)
local vp, va = K.addVials(cfg, 0, 1)
eq(vp, 60, "a vial: 60 minutes"); eq(va, 60, "60 added")
vp, va = K.addVials(cfg, 150, 1)
eq(vp, 180, "never past the cap"); eq(va, 30, "30 added")
vp, va = K.addVials(cfg, 180, 2)
eq(va, 0, "a full pool takes nothing")
eq(select(2, K.addVials(cfg, 0, 0)), 0, "zero vials: nothing")
eq(select(2, K.addVials(cfg, 0, 99)), 0, "a silly count: nothing")

-- ---------------------------------------------------------------- returning and alts
local T0 = 1800000000
check(not K.isReturning(cfg, 0, T0), "a new account is not returning")
check(not K.isReturning(cfg, T0 - 13 * 86400, T0), "13 days: no")
check(K.isReturning(cfg, T0 - 14 * 86400, T0), "14 days: returning")
eq(K.returningUntil(cfg, T0), T0 + 7 * 86400, "7 days of boost")
eq(K.altPct(cfg, 300, 500), 100, "best 500, level 300: full +100%")
eq(K.altPct(cfg, 400, 500), 100, "100 below (best x 0.2): still full")
eq(K.altPct(cfg, 450, 500), 50, "50 below: half")
eq(K.altPct(cfg, 500, 500), 0, "at the best: none")
eq(K.altPct(cfg, 600, 500), 0, "above the best: none")
eq(K.altPct(cfg, 10, 40), 0, "best below minBest: none")
eq(K.altPct(cfg, 60, 70), 50, "small best: the fade is minFade (20)")

-- ---------------------------------------------------------------- stamina
eq(K.staminaLootMult(cfg, 2000), 1, "full stamina: full loot")
eq(K.staminaLootMult(cfg, 840), 0.5, "at 14 h: half loot")
eq(K.staminaLootMult(cfg, 0), 0.5, "empty stamina: still half, never zero")
eq(K.staminaXpFactor(cfg, 0), 1, "the base script already halves the experience: nothing more")
near(K.staminaXpFactor({stamina = {lowAt = 840, xpMult = 0.75, baseXpMult = 0.5}}, 100), 1.5, "a softer rule on top of the base")
eq(K.staminaXpFactor(cfg, 841), 1, "above the line: 1")

-- ---------------------------------------------------------------- experience
local out, spent = K.xpGain(cfg, 1000, {level = 400, stamina = 2000, pool = 0, best = 0})
eq(out, 1000, "no bonus: unchanged")
eq(spent, 0, "no pool spent")
out, spent = K.xpGain(cfg, 1000, {level = 400, stamina = 2000, pool = 100, best = 0, xpPerMin = 100})
eq(out, 2000, "rested: +100%")
near(spent, 10, "the bonus paid by the pool: 1000 / 100 per minute")
out, spent = K.xpGain(cfg, 1000, {level = 400, stamina = 2000, pool = 2, best = 0, xpPerMin = 100})
eq(out, 1200, "a small pool pays what it holds")
near(spent, 2, "and is empty")
out = K.xpGain(cfg, 1000, {level = 400, stamina = 2000, pool = 0, best = 0, returning = true})
eq(out, 1500, "returning: +50%")
out = K.xpGain(cfg, 1000, {level = 300, stamina = 2000, pool = 0, best = 500})
eq(out, 2000, "alt: +100%")
out = K.xpGain(cfg, 1000, {level = 300, stamina = 2000, pool = 0, best = 500, returning = true})
eq(out, 3000, "returning and alt: x3 (1.5 x 2)")
out, spent = K.xpGain(cfg, 1000, {level = 300, stamina = 2000, pool = 50, best = 500, returning = true, xpPerMin = 100})
eq(out, 3000, "everything at once: the ceiling (maxXpMult 3)")
eq(spent, 0, "the ceiling left no room: the pool is kept")
out, spent = K.xpGain(cfg, 1000, {level = 450, stamina = 2000, pool = 50, best = 500, xpPerMin = 100})
eq(out, 3000, "alt +50% and rested: capped at x3")
near(spent, 15, "the rested part: 1500 of bonus")
out = K.xpGain(cfg, 1000, {level = 300, stamina = 2000, pool = 50, best = 500, returning = true, season = true})
eq(out, 1000, "a season character: no bonus")
eq((K.xpGain(cfg, 0, {pool = 50})), 0, "no experience, no bonus")
eq((K.xpGain({enabled = false}, 1000, {pool = 50, returning = true})), 1000, "switched off")

-- ---------------------------------------------------------------- loot and tokens
eq(K.lootMult(cfg, {stamina = 2000}), 1, "loot: nothing special")
eq(K.lootMult(cfg, {stamina = 100}), 0.5, "loot: low stamina")
eq(K.lootMult(cfg, {stamina = 2000, returning = true}), 1.25, "loot: returning")
eq(K.lootMult(cfg, {stamina = 100, returning = true}), 0.625, "loot: both")
eq(K.lootMult(cfg, {stamina = 2000, returning = true, season = true}), 1, "loot: a season character keeps no boost")
eq(K.lootMult({enabled = false, stamina = {lowAt = 840}}, {stamina = 100}), 0, "switched off: the stock rule (nothing)")
eq(K.tokenMult(cfg, {returning = true}), 1.5, "tokens: returning")
eq(K.tokenMult(cfg, {}), 1, "tokens: none")

-- ---------------------------------------------------------------- catchup.lua on a mocked engine
local now = T0
os.time = function(t)
	if t then
		return T0
	end
	return now
end
SKILL_LEVEL = 8
MESSAGE_EVENT_ADVANCE = 19
local rows = {players = {}, catchup = {}}
local queries = {}
db = {query = function(q)
	queries[#queries + 1] = q
	local acc, untilAt = q:match("VALUES %((%d+), (%d+),")
	if acc then
		rows.catchup[tonumber(acc)] = tonumber(untilAt)
	end
	return true
end}
local seasonGuids = {}
ChaosSeason = {realmOf = function(p) return seasonGuids[p:getGuid()] and 1 or 0 end,
	realmOfGuid = function(g) return seasonGuids[g] and 1 or 0 end}
Chaos = {t = function(_, fmt, ...) return string.format(fmt, ...) end,
	select = function(q, cols)
		local acc = tonumber(q:match("`account_id` = (%d+)"))
		if q:find("MAX%(`lastlogout`%)") then
			local m = 0
			for _, r in pairs(rows.players) do
				if r.account == acc then
					m = math.max(m, r.lastlogout)
				end
			end
			return {{t = m}}
		elseif q:find("FROM `players`") then
			local out = {}
			for id, r in pairs(rows.players) do
				if r.account == acc then
					out[#out + 1] = {id = id, level = r.level}
				end
			end
			return out
		elseif q:find("chaos_catchup") then
			return rows.catchup[acc] and {{returning_until = rows.catchup[acc]}} or {}
		end
		return {}
	end}
local online = {}
Game = {getPlayers = function() return online end}
local events, callbacks = {}, {}
function CreatureEvent(name)
	local ev = {name = name}
	function ev:type(t) self.t = t end
	function ev:register() events[self.name] = self end
	return ev
end
EventCallback = setmetatable({}, {__index = function(t, k)
	if k == "register" then
		return function(self, idx)
			callbacks[#callbacks + 1] = {fn = rawget(self, "onGainExperience"), idx = idx}
		end
	end
end})

local function newPlayer(id, account, level, stamina, lastlogout)
	rows.players[id] = {account = account, level = level, lastlogout = lastlogout or 0}
	local p = {id = id, account = account, level = level, stamina = stamina, st = {}, msgs = {}, lastLogout = lastlogout or 0}
	function p:getId() return self.id end
	function p:getGuid() return self.id end
	function p:getAccountId() return self.account end
	function p:getLevel() return self.level end
	function p:getStamina() return self.stamina end
	function p:getLastLogout() return self.lastLogout end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function p:registerEvent() end
	return p
end
local function said(p, needle)
	for _, m in ipairs(p.msgs) do
		if m:find(needle, 1, true) then
			return true
		end
	end
	return false
end
local monster = {isMonster = function() return true end}
local playerSource = {isMonster = function() return false end}

dofile("data/scripts/chaos/catchup.lua")
local CU = ChaosCatchup
check(events.ChaosCatchupLogin and events.ChaosCatchupLogout and events.ChaosCatchupAdvance, "events registered")
eq(callbacks[1] and callbacks[1].idx, cfg.xpIndex, "the experience callback at its index")
local xpcb = callbacks[1].fn

-- an account away for 20 days with a level 500 main; its level 300 alt logs in after 3 days... of being away 20
local main = newPlayer(1, 10, 500, 2520, T0 - 20 * 86400)
local alt = newPlayer(2, 10, 300, 600, T0 - 20 * 86400)
online = {alt}
events.ChaosCatchupLogin.onLogin(alt)
eq(rows.catchup[10], T0 + 7 * 86400, "the boost started and was written")
check(said(alt, "Welcome back!"), "welcomed")
check(not said(alt, "Next Goals"), "no Next Goals line while that panel does not exist")
check(said(alt, "You are rested"), "rested message")
eq(alt.st[cfg.storage.rested], 18000, "20 days away: the pool is full (180 minutes)")
check(said(alt, "Catch-up: +100%"), "the alt is told its catch-up")
check(CU.isReturning(alt), "returning")
eq(CU.lootMult(alt), 0.625, "low stamina x returning loot")
eq(CU.staminaLootMult(alt), 0.5, "the stock pass: half")
eq(CU.offlineStaminaMult(alt), 2, "offline regeneration x2")
eq(CU.tokenMult(alt), 1.5, "token drops x1.5")
-- the experience: ceiling x3 (returning 1.5 x alt 2), the pool is kept
eq(xpcb(alt, monster, 1000, 1000), 3000, "experience x3 at the ceiling")
eq(xpcb(alt, playerSource, 1000, 1000), 1000, "a player kill: unchanged")
eq(CU.restedMinutes(alt), 180, "nothing spent under the ceiling")
-- the buff bar
local it = CU.buffItem(alt, "low")
check(it and it.desc:find("50%% loot"), "low stamina debuff")
it = CU.buffItem(alt, "rested")
eq(it and it.stacks, 180, "rested: minutes as stacks")
it = CU.buffItem(alt, "returning")
eq(it and it.leftMs, 7 * 86400 * 1000, "returning: the time left")
it = CU.buffItem(alt, "alt")
eq(it and it.stacks, 100, "alt: the percent")
-- a second login of the account in the boost: no second welcome for the same character
alt.msgs = {}
events.ChaosCatchupLogout.onLogout(alt)
online = {}
alt.lastLogout = now
now = now + 3600
online = {alt}
events.ChaosCatchupLogin.onLogin(alt)
check(not said(alt, "Welcome back!"), "welcomed once per boost")
check(CU.isReturning(alt), "the boost read back from the table")
-- the main joins while the alt is online: welcomed too, its level counts
main.lastLogout = T0 - 20 * 86400
online = {alt, main}
events.ChaosCatchupLogin.onLogin(main)
check(said(main, "Welcome back!"), "every character of the account is welcomed once")
eq(CU.buffItem(main, "alt"), nil, "the best character has no catch-up")
-- the alt passes the best: no more catch-up
events.ChaosCatchupAdvance.onAdvance(alt, SKILL_LEVEL, 300, 520)
alt.level = 520
eq(CU.buffItem(alt, "alt"), nil, "a new best: no catch-up")
events.ChaosCatchupAdvance.onAdvance(alt, SKILL_LEVEL, 520, 521)
main.level = 500
eq(CU.buffItem(main, "alt").stacks, 20, "the old main, 21 below 521: +20% (fade 104 levels)")
-- full stamina, no alt, the boost ends: the rested pool pays
now = T0 + 8 * 86400
main.stamina = 2520
local x = xpcb(main, monster, 1000, 1000)
near(x, 2 * (1 + K.altPct(cfg, 500, 521) / 100) * 1000, "after the boost: alt x1.2 and rested x2", 1e-6)
-- the pool drains: experience bigger than the pool
local fresh = newPlayer(3, 20, 100, 2520, T0 + 8 * 86400 - 600 - 3600)
online = {fresh}
events.ChaosCatchupLogin.onLogin(fresh)
near(CU.restedMinutes(fresh), 2.5, "an hour offline: 2.5 minutes")
check(not said(fresh, "Welcome back!"), "an hour away is no return")
local per = K.xpPerMinute(cfg, 100)
local big = per * 10
near(xpcb(fresh, monster, big, big), big + per * 2.5, "the pool pays what it holds", 1e-3)
near(CU.restedMinutes(fresh), 0, "and is empty")
eq(fresh.st[cfg.storage.rested], 0, "the storage follows")
eq(CU.buffItem(fresh, "rested"), nil, "an empty pool: no buff")
-- a season character: stamina rules only
seasonGuids[4] = true
local seasonal = newPlayer(4, 30, 100, 2520, T0 - 30 * 86400)
online = {seasonal}
events.ChaosCatchupLogin.onLogin(seasonal)
check(not said(seasonal, "rested") and not said(seasonal, "Welcome back!"), "a season character: no bonus messages")
eq(xpcb(seasonal, monster, 1000, 1000), 1000, "a season character: no bonus experience")
eq(CU.buffItem(seasonal, "returning"), nil, "a season character: no returning buff")
-- a new account (no logout ever): no boost
local newbie = newPlayer(5, 40, 1, 2520, 0)
online = {newbie}
events.ChaosCatchupLogin.onLogin(newbie)
eq(rows.catchup[40], nil, "a new account starts no boost")
-- the Next Goals panel when it exists
local hinted
ChaosNextGoals = {hint = function(p, why) hinted = why end}
local back = newPlayer(6, 50, 50, 2520, now - 15 * 86400)
online = {back}
events.ChaosCatchupLogin.onLogin(back)
eq(hinted, "returning", "the panel is asked for a hint")
check(said(back, "Next Goals"), "and the player is pointed at it")
ChaosNextGoals = nil
-- switched off: the stock loot rule
ChaosCatchupConfig.enabled = false
eq(CU.staminaLootMult(alt.stamina and newPlayer(7, 60, 10, 100, 0)), 0, "switched off: low stamina, no stock loot")
eq(CU.offlineStaminaMult(back), 1, "switched off: stock regeneration")
ChaosCatchupConfig.enabled = true
-- the Rested Vial API (the Candlemarks shop calls ChaosRested.addVials)
check(ChaosRested and ChaosRested.addVials, "ChaosRested.addVials exists")
local vialer = newPlayer(8, 70, 50, 2520, 0)
online = {vialer}
events.ChaosCatchupLogin.onLogin(vialer)
eq(ChaosRested.addVials(vialer, 1), true, "a vial is drunk")
near(CU.restedMinutes(vialer), 60, "60 minutes of rest")
check(said(vialer, "Rested Vial: +60 minutes"), "told")
ChaosRested.addVials(vialer, 2)
near(CU.restedMinutes(vialer), 180, "up to the cap")
eq(ChaosRested.addVials(vialer, 1), false, "a full rest refuses (the shop refunds)")
eq(ChaosRested.addVials(seasonal, 1), false, "a season character does not rest")
-- logout writes the pool
events.ChaosCatchupLogout.onLogout(main)
check(main.st[cfg.storage.rested] ~= nil, "logout keeps the pool in its storage")

print(string.format("catchup_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
