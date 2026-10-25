-- Run from the server/ folder: luajit tests/blessings_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Ember Blessings: the pure rules (blessings_core.lua + blessings_config.lua): the chance by tier and by the level gap,
-- the cap, the internal cooldown, the weighted draw, no stacking (a second proc refreshes), the cap of active blessings
-- (the weakest is replaced), expiry; then the engine file (blessings.lua) against a mocked engine: the proc on a kill
-- for the corpse owner, every effect while it runs and gone after 60 s (experience, gold, damage dealt, damage taken,
-- speed / regeneration / critical conditions, Chaos loot, rarity and orb find), PvP places, logout, the buff bar rows
-- (data/lib/chaos_buffs.lua) and the floating label's colour bytes.
local cfg = dofile("data/scripts/chaos/blessings_config.lua")
dofile("data/scripts/chaos/blessings_core.lua")
local K = ChaosBlessingsCore

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, what)
	ok(math.abs(a - b) < 1e-9, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- deterministic generator (same in LuaJIT and Lua 5.3)
local function rng(seed)
	local s = seed
	return function(a, b)
		s = (s * 16807) % 2147483647
		return a + s % (b - a + 1)
	end
end
-- a generator that always answers the lowest value (every roll hits, the first pool entry is drawn)
local function low(a, b) return a end

-- ------------------------------------------------------------------ the config
do
	local keys, total = {}, 0
	for _, e in ipairs(cfg.pool) do
		ok(not keys[e.key], "pool key once: " .. e.key)
		keys[e.key] = true
		ok((e.weight or 0) > 0, e.key .. " weight")
		ok((e.value or 0) > 0, e.key .. " value")
		ok(type(e.color) == "number" and e.color > 0 and e.color < 216 and e.color % 1 == 0, e.key .. " colour is a palette byte")
		ok(type(e.label) == "string" and #e.label > 0 and #e.label <= 20, e.key .. " label")
		ok(type(e.effect) == "string" and e.effect:match("^CONST_ME_"), e.key .. " effect name")
		ok(pcall(string.format, e.desc, e.value) and not string.format(e.desc, e.value):find("%%d"), e.key .. " desc format")
		total = total + e.weight
	end
	for _, k in ipairs({"xp", "gold", "damage", "ward", "speed", "regen", "crit", "loot", "rarity", "orb"}) do
		ok(keys[k], "pool has " .. k)
	end
	eq(total, 130, "pool weight total")
	eq(cfg.durationMs, 60000, "one minute")
	eq(cfg.maxActive, 3, "three at once")
end

-- ------------------------------------------------------------------ chance by tier and level gap
do
	eq(K.chance(cfg, "normal", 50, 50), 1.5, "normal")
	eq(K.chance(cfg, "magic", 50, 50), 4, "magic")
	eq(K.chance(cfg, "rare", 50, 50), 8, "rare")
	eq(K.chance(cfg, "legendary", 50, 50), 15, "legendary")
	eq(K.chance(cfg, "boss", 50, 50), 25, "boss")
	eq(K.chance(cfg, "nonsense", 50, 50), 1.5, "unknown tier counts as normal")
	ok(K.chance(cfg, "normal", 50, 50) < K.chance(cfg, "magic", 50, 50) and K.chance(cfg, "magic", 50, 50)
		< K.chance(cfg, "rare", 50, 50) and K.chance(cfg, "rare", 50, 50) < K.chance(cfg, "legendary", 50, 50), "tiers rise")
	-- the gap
	eq(K.levelFactor(cfg, 20, 10), 1, "within the grace (10 levels)")
	eq(K.levelFactor(cfg, 100, 90), 1, "grace edge")
	eq(K.levelFactor(cfg, 100, 80), 1, "share 0.80")
	eq(K.levelFactor(cfg, 100, 75), 1, "share 0.75")
	eq(K.levelFactor(cfg, 100, 70), 0.5, "share 0.70")
	eq(K.levelFactor(cfg, 100, 50), 0.2, "share 0.50")
	eq(K.levelFactor(cfg, 100, 40), 0, "share 0.40: trivial")
	eq(K.levelFactor(cfg, 300, 20), 0, "far below: nothing")
	eq(K.levelFactor(cfg, 100, 0), 1, "no known level")
	eq(K.levelFactor(cfg, 50, 200), 1, "a stronger monster counts in full")
	eq(K.chance(cfg, "rare", 100, 70), 4, "rare at share 0.7: half")
	eq(K.chance(cfg, "legendary", 100, 50), 3, "legendary at share 0.5: a fifth")
	eq(K.chance(cfg, "boss", 400, 100), 0, "boss far below: nothing")
	local saved = cfg.maxChance
	cfg.maxChance = 10
	eq(K.chance(cfg, "boss", 50, 50), 10, "the cap")
	cfg.maxChance = saved
end

-- ------------------------------------------------------------------ the roll: chance, cooldown, reasons
do
	local st = K.newState()
	local info = {tier = "normal", playerLevel = 50, monsterLevel = 50}
	local g, why = K.roll(cfg, st, info, 1000, low)
	ok(g ~= nil, "low roll hits")
	eq(g.action, "new", "first proc is new")
	eq(g.key, cfg.pool[1].key, "lowest draw is the first entry")
	eq(st.lastProcMs, 1000, "proc time kept")
	g, why = K.roll(cfg, st, info, 1000 + cfg.cooldownMs - 1, low)
	eq(g, nil, "inside the cooldown")
	eq(why, "cooldown", "cooldown reason")
	g = K.roll(cfg, st, info, 1000 + cfg.cooldownMs, low)
	ok(g ~= nil, "cooldown over")
	eq(g.action, "refresh", "same kind again refreshes")
	-- a miss does not start the cooldown
	local st2 = K.newState()
	g, why = K.roll(cfg, st2, info, 5000, function(a, b) return b end)
	eq(why, "miss", "high roll misses")
	eq(st2.lastProcMs, nil, "a miss sets no cooldown")
	g, why = K.roll(cfg, st2, {tier = "normal", playerLevel = 300, monsterLevel = 10}, 5000, low)
	eq(why, "trivial", "trivial monster")
	g, why = K.roll(cfg, st2, {tier = "boss", playerLevel = 50, monsterLevel = 50, blocked = "battleground"}, 5000, low)
	eq(why, "battleground", "blocked place")
	cfg.enabled = false
	g, why = K.roll(cfg, st2, info, 5000, low)
	eq(why, "disabled", "switched off")
	cfg.enabled = true
	-- the rate over many kills follows the chance
	local r, hits, n = rng(7), 0, 200000
	for i = 1, n do
		local s = K.newState()
		if K.roll(cfg, s, {tier = "rare", playerLevel = 60, monsterLevel = 60}, i, r) then
			hits = hits + 1
		end
	end
	ok(math.abs(hits / n * 100 - 8) < 0.4, "rare kills bless about 8%: " .. hits / n * 100)
	-- with one kill every 2 s the cooldown (20 s) holds the rate down: at most one proc in 10 kills
	local s, procs = K.newState(), 0
	for i = 1, 10000 do
		if K.roll(cfg, s, {tier = "boss", playerLevel = 60, monsterLevel = 60}, i * 2000, r) then
			procs = procs + 1
		end
	end
	ok(procs <= 1000, "cooldown caps procs: " .. procs)
end

-- ------------------------------------------------------------------ the draw
do
	local r, counts, n = rng(11), {}, 130000
	for _ = 1, n do
		local e = K.pick(cfg, r)
		counts[e.key] = (counts[e.key] or 0) + 1
	end
	for _, e in ipairs(cfg.pool) do
		local share = (counts[e.key] or 0) / n
		ok(math.abs(share - e.weight / 130) < 0.01, "weight of " .. e.key .. ": " .. share)
	end
	eq(K.pick({pool = {}}, r), nil, "empty pool")
end

-- ------------------------------------------------------------------ no stacking, refresh, the cap
do
	local st = K.newState()
	local g = K.grant(cfg, st, "xp", 0)
	eq(g.action, "new", "xp new")
	eq(g.untilMs, 60000, "60 s")
	eq(K.value(cfg, st, "xp", 30000), 25, "xp +25 while it runs")
	near(K.mult(cfg, st, "xp", 30000), 1.25, "xp mult")
	g = K.grant(cfg, st, "xp", 30000)
	eq(g.action, "refresh", "xp again: refresh")
	eq(st.active.xp.untilMs, 90000, "the full minute again")
	eq(K.count(st), 1, "still one blessing")
	near(K.mult(cfg, st, "xp", 31000), 1.25, "refresh does not stack the value")
	K.grant(cfg, st, "gold", 40000)
	K.grant(cfg, st, "damage", 41000)
	eq(K.count(st), 3, "three kinds side by side")
	-- a fourth kind replaces the one with the least time left (gold: ends at 100000; xp 90000)
	g = K.grant(cfg, st, "speed", 42000)
	eq(g.action, "replace", "fourth kind replaces")
	eq(g.replaced, "xp", "the weakest goes")
	eq(K.count(st), 3, "cap held")
	eq(st.active.xp, nil, "xp gone")
	-- an active kind at the cap refreshes, nothing is replaced
	g = K.grant(cfg, st, "gold", 43000)
	eq(g.action, "refresh", "active kind at the cap refreshes")
	eq(g.replaced, nil, "nothing replaced")
	-- ward lowers, the rest raises
	K.grant(cfg, st, "ward", 44000)
	near(K.mult(cfg, st, "ward", 44000), 0.85, "ward -15%")
	-- list: longest left first
	local list = K.list(cfg, st, 44000)
	eq(#list, 3, "list of three")
	eq(list[1].key, "ward", "longest first")
	eq(list[1].leftMs, 60000, "time left")
	eq(list[1].desc, "-15% damage taken from monsters.", "description with its number")
	-- ward came in at the cap too and replaced damage (ends 101000); speed ends 102000, gold 103000, ward 104000
	eq(st.active.damage, nil, "ward replaced damage")
	local gone = K.expire(st, 103500)
	eq(table.concat(gone, ","), "gold,speed", "gold and speed ran out")
	eq(K.count(st), 1, "ward left")
	eq(K.left(st, "ward", 103500), 500, "ward's time left")
	eq(K.value(cfg, st, "xp", 104000), 0, "not active: 0")
	near(K.mult(cfg, st, "xp", 104000), 1, "not active: 1")
	eq(K.scale(-101, 1.15), -116, "scale toward zero (negative)")
	eq(K.scale(100, 0.85), 85, "scale (ward)")
	eq(K.speedDelta(cfg, 220), 55, "speed +25% of the base")
	local hp, mp = K.regenAmounts(cfg, 1000, 30)
	eq(hp, 20, "regen 2% health")
	eq(mp, 1, "regen at least 1 mana")
end

-- ================================================================== the engine file against a mocked engine
local T = 1000000
os.mtime = function() return T end
local n = 0
for _, name in ipairs({"CONDITION_HASTE", "CONDITION_REGENERATION", "CONDITION_ATTRIBUTES", "CONDITION_PARAM_SUBID",
	"CONDITION_PARAM_TICKS", "CONDITION_PARAM_SPEED", "CONDITION_PARAM_HEALTHGAIN", "CONDITION_PARAM_HEALTHTICKS",
	"CONDITION_PARAM_MANAGAIN", "CONDITION_PARAM_MANATICKS", "CONDITION_PARAM_SPECIALSKILL_CRITICALHITCHANCE",
	"CONDITION_PARAM_SPECIALSKILL_CRITICALHITAMOUNT", "CONST_ME_MAGIC_GREEN", "CONST_ME_GIFT_WRAPS", "CONST_ME_HITBYFIRE",
	"CONST_ME_BLOCKHIT", "CONST_ME_MAGIC_BLUE", "CONST_ME_FIREATTACK", "CONST_ME_MAGIC_RED", "CONST_ME_ENERGYAREA",
	"MESSAGE_STATUS_DEFAULT", "MESSAGE_INFO_DESCR", "TILESTATE_PVPZONE", "RETURNVALUE_NOERROR", "ACCOUNT_TYPE_GOD",
	"COMBAT_PHYSICALDAMAGE", "COMBAT_FIREDAMAGE", "COMBAT_MANADRAIN"}) do
	n = n + 1
	_G[name] = n
end
CONDITIONID_DEFAULT, CONDITIONID_COMBAT, COMBAT_HEALING = 0, 1, 128

local events, callbacks, globals, talks = {}, {}, {}, {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_pending", {k, v}) end})
rawset(EventCallback, "register", function(self, index)
	local p = rawget(self, "_pending")
	callbacks[p[1]] = callbacks[p[1]] or {}
	table.insert(callbacks[p[1]], {fn = p[2], index = index or 0})
	rawset(self, "_pending", nil)
end)
function CreatureEvent(name)
	local e = {}
	function e.register() events[name] = e end
	function e.type() end
	return e
end
function GlobalEvent(name)
	local e = {}
	function e.interval() end
	function e.register() globals[name] = e end
	return e
end
function TalkAction(words)
	local e = {}
	function e.separator() end
	function e.register() talks[words] = e end
	return e
end
function Condition(ctype, cid)
	local c = {type = ctype, id = cid, params = {}}
	function c:setParameter(k, v) self.params[k] = v end
	return c
end
local tileFlags = {}
function Tile(pos)
	return {hasFlag = function(self, f) return tileFlags[f] == true end}
end
local effects, labels = {}, {}
local function mkPos(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function(self, id) effects[#effects + 1] = id end}
end
ChaosCombatFx = {label = function(pos, text, color) labels[#labels + 1] = {text = text, color = color} end}
ChaosTierOf = function(m) return m._tier end

local players = {}
local function mkPlayer(id)
	local p = {_id = id, _conds = {}, _msgs = {}, _events = {}, _level = 60, _stamina = 2520}
	function p:getId() return self._id end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getMaster() return nil end
	function p:getPosition() return mkPos(100, 100, 7) end
	function p:getLevel() return self._level end
	function p:getStamina() return self._stamina end
	function p:getBaseSpeed() return 220 end
	function p:getMaxHealth() return 1000 end
	function p:getMaxMana() return 500 end
	function p:addCondition(c) self._conds[c.type .. ":" .. c.id .. ":" .. c.params[CONDITION_PARAM_SUBID]] = c end
	function p:removeCondition(ctype, cid, sub) self._conds[ctype .. ":" .. cid .. ":" .. sub] = nil end
	function p:sendTextMessage(t, text) self._msgs[#self._msgs + 1] = text end
	function p:registerEvent(name) self._events[name] = true end
	function p:getGroup() return {getAccess = function() return true end} end
	function p:getAccountType() return ACCOUNT_TYPE_GOD end
	players[id] = p
	return p
end
function Player(id)
	if type(id) == "table" then
		return id
	end
	return players[id]
end
local function mkMonster(id, tier, level)
	local m = {_id = id, _tier = tier or "normal", _level = level or 60, _events = {}}
	function m:getId() return self._id end
	function m:isPlayer() return false end
	function m:isMonster() return true end
	function m:getMaster() return self._master end
	function m:getMonsterLevel() return self._level end
	function m:registerEvent(name) self._events[name] = true end
	return m
end
local function mkCorpse(ownerId, coins)
	local c = {_owner = ownerId, _items = {}}
	for _, it in ipairs(coins or {}) do
		c._items[#c._items + 1] = {id = it[1], count = it[2]}
	end
	function c:getCorpseOwner() return self._owner end
	function c:getPosition() return mkPos(100, 100, 7) end
	function c:getSize() return #self._items end
	function c:getItem(slot)
		local it = self._items[slot + 1]
		return it and {getId = function() return it.id end, getCount = function() return it.count end}
	end
	function c:addItem(id, count) self._items[#self._items + 1] = {id = id, count = count} end
	function c:value()
		local v = 0
		for _, it in ipairs(self._items) do
			v = v + it.count * (({[2160] = 10000, [2152] = 100, [2148] = 1})[it.id] or 0)
		end
		return v
	end
	return c
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/blessings.lua")
local X = ChaosBlessings
ok(X ~= nil, "engine file loaded")

local function cb(name)
	return callbacks[name] and callbacks[name][1].fn
end
eq(callbacks.onDropLoot[1].index, 2, "drop callback after the loot layer")
eq(callbacks.onGainExperience[1].index, 6, "xp callback index")

local hero = mkPlayer(1)
events.ChaosBlessingsLogin.onLogin(hero)
ok(hero._events.ChaosBlessingsTaken and hero._events.ChaosBlessingsTakenMana and hero._events.ChaosBlessingsLogout, "login registers")

-- ---- a kill: only the corpse owner rolls; a forced roll blesses
local realRandom = math.random
math.random = function(a, b)
	if a == nil then
		return 0.99
	end
	return a -- every roll hits, the first pool entry (xp) is drawn
end
local wolf = mkMonster(500, "magic", 55)
cb("onDropLoot")(wolf, mkCorpse(1, {}))
eq(K.value(cfg, X.state[1], "xp", T), 25, "a kill blessed the owner with xp")
eq(#labels, 1, "one floating label")
eq(labels[1].text, "+25% XP", "label text")
eq(type(labels[1].color), "number", "label colour is a byte")
eq(effects[#effects], CONST_ME_MAGIC_GREEN, "magic effect")
ok(hero._msgs[#hero._msgs]:find("Ember of Insight"), "message names the blessing")
-- the cooldown: the next kill rolls nothing
cb("onDropLoot")(wolf, mkCorpse(1, {}))
eq(#labels, 1, "no second proc inside the cooldown")
-- a corpse with no player owner: nothing
cb("onDropLoot")(wolf, mkCorpse(999, {}))
-- a summon's death: nothing
T = T + 30000
local summon = mkMonster(501)
summon._master = hero
cb("onDropLoot")(summon, mkCorpse(1, {}))
eq(#labels, 1, "no proc for a summon")
-- a second proc of the same kind refreshes, the label shows again
cb("onDropLoot")(wolf, mkCorpse(1, {}))
eq(#labels, 2, "second proc")
eq(X.state[1].active.xp.untilMs, T + 60000, "refreshed to the full minute")
ok(hero._msgs[#hero._msgs]:find("again"), "refresh message")
-- a trivial monster: no proc even with every roll hitting
T = T + 30000
cb("onDropLoot")(mkMonster(502, "normal", 5), mkCorpse(1, {}))
eq(#labels, 2, "no proc from a trivial monster")
-- no stamina, no blessing
hero._stamina = 0
cb("onDropLoot")(wolf, mkCorpse(1, {}))
eq(#labels, 2, "no proc without stamina")
hero._stamina = 2520
math.random = realRandom
X.clear(hero)

-- ---- every effect while it runs and gone after 60 s
local function think()
	globals.ChaosBlessingsThink.onThink(1000)
end
T = 5000000
local start = T
for _, key in ipairs({"xp", "gold", "damage"}) do
	X.give(hero, key)
end
eq(K.count(X.state[1]), 3, "three blessings")
-- experience
local xp = cb("onGainExperience")
eq(xp(hero, wolf, 1000, 1000), 1250, "+25% experience from a monster")
eq(xp(hero, summon, 1000, 1000), 1000, "no bonus for a summon's experience")
eq(xp(hero, nil, 1000, 1000), 1000, "no bonus without a source")
-- gold
local corpse = mkCorpse(1, {{2148, 80}, {2152, 2}})
math.random = function(a, b) if a == nil then return 0.99 end return b end -- no proc on this kill
cb("onDropLoot")(wolf, corpse)
math.random = realRandom
eq(corpse:value(), 420, "+50% gold: 280 -> 420")
-- damage dealt: registered by onTargetCombat, scaled in onHealthChange
local tgt = mkMonster(600)
eq(cb("onTargetCombat")(hero, tgt), RETURNVALUE_NOERROR, "target combat never blocks")
ok(tgt._events.ChaosBlessingsDealt, "dealt event on the target")
local pd, pt, sd = events.ChaosBlessingsDealt.onHealthChange(tgt, hero, -200, COMBAT_PHYSICALDAMAGE, -40, COMBAT_FIREDAMAGE, 0)
eq(pd, -230, "+15% primary")
eq(sd, -46, "+15% secondary")
pd = events.ChaosBlessingsDealt.onHealthChange(tgt, summon, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0)
eq(pd, -115, "the summon's hits too")
pd = events.ChaosBlessingsDealt.onHealthChange(tgt, hero, 100, COMBAT_HEALING, 0, COMBAT_HEALING, 0)
eq(pd, 100, "healing untouched")
pd = events.ChaosBlessingsDealt.onHealthChange(hero, mkPlayer(2), -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0)
eq(pd, -100, "no bonus on a player (no PvP effect)")
-- buff bar rows
dofile("data/lib/chaos_buffs.lua")
local B = ChaosBuffs
eq(#B.validate(), 0, "registry valid")
local rows = 0
for _, def in ipairs(B.entries) do
	if def.source == "blessings" then
		rows = rows + 1
		ok(K.entry(cfg, def.blessing) ~= nil, def.key .. " names a pool kind")
		eq(def.icon, "buff:" .. def.key, def.key .. " own icon")
	end
end
eq(rows, #cfg.pool, "one buff bar row per kind")
local items = B.sources.blessings(hero, T, B.byKey.blessing_xp)
eq(items and items[1].leftMs, 60000, "bar: xp with 60 s")
eq(items and items[1].name, "Ember of Insight", "bar: name")
eq(B.sources.blessings(hero, T, B.byKey.blessing_speed), nil, "bar: speed not active")
-- 60 s later every effect is gone
T = start + 60000
think()
eq(X.state[1] and K.count(X.state[1]) or 0, 0, "all three ended")
eq(xp(hero, wolf, 1000, 1000), 1000, "experience back to normal")
corpse = mkCorpse(1, {{2148, 80}})
math.random = function(a, b) if a == nil then return 0.99 end return b end
cb("onDropLoot")(wolf, corpse)
math.random = realRandom
eq(corpse:value(), 80, "gold back to normal")
pd = events.ChaosBlessingsDealt.onHealthChange(tgt, hero, -200, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0)
eq(pd, -200, "damage back to normal")
eq(B.sources.blessings(hero, T, B.byKey.blessing_xp), nil, "bar: gone")

-- ward, speed, regeneration
start = T
X.give(hero, "ward")
local taken = events.ChaosBlessingsTaken.onHealthChange
pd, pt, sd = taken(hero, wolf, -200, COMBAT_PHYSICALDAMAGE, -20, COMBAT_FIREDAMAGE, 0)
eq(pd, -170, "-15% from a monster")
eq(sd, -17, "-15% secondary")
eq(taken(hero, mkPlayer(3), -200, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0), -200, "no ward against players")
eq(taken(hero, summon, -200, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0), -200, "no ward against a player's summon")
eq(events.ChaosBlessingsTakenMana.onManaChange(hero, wolf, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0), -85,
	"ward on mana shield hits")
X.give(hero, "speed")
local haste = hero._conds[CONDITION_HASTE .. ":0:" .. cfg.subIds.speed]
ok(haste ~= nil, "haste condition")
eq(haste and haste.params[CONDITION_PARAM_SPEED], 55, "+25% of base speed 220")
eq(haste and haste.params[CONDITION_PARAM_TICKS], 60000, "for 60 s")
T = start + 1000
X.give(hero, "regen")
local regen = hero._conds[CONDITION_REGENERATION .. ":0:" .. cfg.subIds.regen]
eq(regen and regen.params[CONDITION_PARAM_HEALTHGAIN], 20, "2% of 1000 health")
eq(regen and regen.params[CONDITION_PARAM_MANAGAIN], 10, "2% of 500 mana")
eq(regen and regen.params[CONDITION_PARAM_HEALTHTICKS], 2000, "every 2 s")
-- refresh of speed half way: a new condition with the full minute
T = start + 30000
local g = X.give(hero, "speed")
eq(g.action, "refresh", "speed refreshed")
eq(hero._conds[CONDITION_HASTE .. ":0:" .. cfg.subIds.speed].params[CONDITION_PARAM_TICKS], 60000, "condition renewed")
-- a fourth kind past the cap: crit replaces ward (least time left), ward's effect goes
g = X.give(hero, "crit")
eq(g.replaced, "ward", "crit replaces ward")
eq(taken(hero, wolf, -200, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0), -200, "ward gone with its replacement")
local crit = hero._conds[CONDITION_ATTRIBUTES .. ":0:" .. cfg.subIds.crit]
eq(crit and crit.params[CONDITION_PARAM_SPECIALSKILL_CRITICALHITCHANCE], 10, "+10 crit chance")
eq(crit and crit.params[CONDITION_PARAM_SPECIALSKILL_CRITICALHITAMOUNT], 25, "+25 crit damage")
-- regen ends at start + 61 s, speed at start + 90 s, crit at start + 90 s
T = start + 60999
think()
ok(hero._conds[CONDITION_REGENERATION .. ":0:" .. cfg.subIds.regen] ~= nil, "regeneration still on just before its minute")
T = start + 61000
think()
eq(hero._conds[CONDITION_REGENERATION .. ":0:" .. cfg.subIds.regen], nil, "regeneration removed after its 60 s")
ok(hero._conds[CONDITION_HASTE .. ":0:" .. cfg.subIds.speed] ~= nil, "refreshed speed still on")
T = start + 90000
think()
eq(hero._conds[CONDITION_HASTE .. ":0:" .. cfg.subIds.speed], nil, "speed removed")
eq(hero._conds[CONDITION_ATTRIBUTES .. ":0:" .. cfg.subIds.crit], nil, "crit removed")

-- loot, rarity, orbs (read by loot_config.lua rateMult and loot.lua)
start = T
X.give(hero, "loot")
X.give(hero, "rarity")
X.give(hero, "orb")
local lootCfg = dofile("data/scripts/chaos/loot_config.lua")
near(lootCfg.rateMult({player = hero}), 1.4, "Chaos loot +40% through rateMult")
near(lootCfg.rateMult({player = mkPlayer(4)}), 1, "another player: no loot bonus")
near(lootCfg.rateMult({}), 1, "no player: 1")
eq(X.value(hero, "rarity"), 60, "rarity find +60")
near(X.mult(hero, "orb"), 2, "orbs x2")
near(X.mult(nil, "orb"), 1, "no player: 1")
T = start + 60000
think()
near(lootCfg.rateMult({player = hero}), 1, "loot bonus gone after 60 s")
eq(X.value(hero, "rarity"), 0, "rarity gone")
near(X.mult(hero, "orb"), 1, "orbs gone")

-- PvP places: no proc, and entering one takes the blessings away
X.give(hero, "xp")
tileFlags[TILESTATE_PVPZONE] = true
think()
eq(X.state[1], nil, "blessings fade in a PvP zone")
ok(hero._msgs[#hero._msgs]:find("fade"), "fade message")
math.random = function(a, b) if a == nil then return 0.99 end return a end
T = T + 100000
cb("onDropLoot")(wolf, mkCorpse(1, {}))
eq(X.state[1] and K.count(X.state[1]) or 0, 0, "no proc in a PvP zone")
tileFlags[TILESTATE_PVPZONE] = nil
ChaosBattleground = {isInside = function(p) return p == hero end}
cb("onDropLoot")(wolf, mkCorpse(1, {}))
eq(X.state[1] and K.count(X.state[1]) or 0, 0, "no proc in the battleground")
ChaosBattleground = nil
cb("onDropLoot")(wolf, mkCorpse(1, {}))
eq(K.count(X.state[1]), 1, "outside again: procs")
math.random = realRandom

-- logout clears, the staff command forces one
events.ChaosBlessingsLogout.onLogout(hero)
eq(X.state[1], nil, "logout clears")
talks["/blessing"].onSay(hero, "/blessing", "gold")
eq(K.value(cfg, X.state[1], "gold", T), 50, "/blessing gold")
talks["/blessing"].onSay(hero, "/blessing", "clear")
eq(X.state[1], nil, "/blessing clear")
talks["/blessing"].onSay(hero, "/blessing", "roll rare, 60, 1000")
ok(hero._msgs[#hero._msgs]:find("8.00%%"), "/blessing roll reports the chance")

-- ================================================================== the ember on the ground (ChaosPickups)
-- K.rollDrop: the draw and the cooldown without a grant
do
	local st = K.newState()
	local e = K.rollDrop(cfg, st, {tier = "boss", playerLevel = 50, monsterLevel = 50}, 1000, low)
	ok(e ~= nil and e.key == "xp", "rollDrop draws the first entry")
	eq(next(st.active), nil, "rollDrop gives nothing")
	eq(st.lastProcMs, 1000, "the 20 s cooldown starts at the roll")
	local e2, why = K.rollDrop(cfg, st, {tier = "boss", playerLevel = 50, monsterLevel = 50}, 2000, low)
	ok(e2 == nil and why == "cooldown", "no second roll inside the cooldown")
	eq(cfg.pickup.lifetimeMs, 30000, "the ember lies 30 s")
	ok(cfg.pickup.ownerWindowMs > 0 and cfg.pickup.ownerWindowMs < cfg.pickup.lifetimeMs, "an owner window shorter than the life")
end

local dropped, taken = {}, {}
ChaosPickups = {
	installed = function(key) return key == "ember" end,
	drop = function(spec)
		dropped[#dropped + 1] = spec
		return {uid = #dropped}
	end
}
local P2 = mkPlayer(2)
events.ChaosBlessingsLogin.onLogin(P2)
math.random = function(a, b)
	if a == nil then return 0.99 end
	return a
end
T = T + 100000
local labelsBefore, nDrops = #labels, #dropped
cb("onDropLoot")(mkMonster(700, "boss", 60), mkCorpse(1, {}))
math.random = realRandom
eq(#dropped, nDrops + 1, "a proc drops an ember pickup")
local spec = dropped[#dropped]
eq(spec.itemKey, "ember", "the ember item")
eq(spec.ownerId, 1, "owned by the corpse owner")
eq(spec.ttlMs, 30000, "30 s on the ground")
eq(spec.ownerWindowMs, cfg.pickup.ownerWindowMs, "the owner window")
eq(spec.name, "Ember of Insight", "named after the blessing (look text)")
ok(spec.desc:find("+25%%") and spec.desc:find("Step on it"), "the description names the effect")
eq(K.count(X.state[1]) , 0, "nothing is given at the drop")
eq(#labels, labelsBefore, "no blessing label before the pickup")
ok(hero._msgs[#hero._msgs]:find("dying ember drops") and hero._msgs[#hero._msgs]:find("30 seconds"), "the drop message")
-- taking it gives the blessing to whoever takes it (the owner, or a party member the framework let through)
eq(spec.onTake(P2), true, "the take is accepted")
eq(K.value(cfg, X.state[2], "xp", T), 25, "the taker is blessed with the full minute")
eq(X.state[2].active.xp.untilMs, T + 60000, "the minute starts at the pickup")
eq(#labels, labelsBefore + 1, "the pickup shows the label")
ok(P2._msgs[#P2._msgs]:find("A dying ember blesses you") and P2._msgs[#P2._msgs]:find("Ember of Insight"), "the pickup message")
-- a PvP place refuses the take and the ember stays
tileFlags[TILESTATE_PVPZONE] = true
eq(spec.onTake(hero), false, "no blessing in a PvP place: the ember stays")
eq(X.state[1] and K.count(X.state[1]) or 0, 0, "nothing was given there")
ok(hero._msgs[#hero._msgs]:find("no blessings in the pvp zone"), "the PvP message")
tileFlags[TILESTATE_PVPZONE] = nil
-- no free tile: the blessing goes to the owner at once
ChaosPickups.drop = function() return nil, "no tile" end
math.random = function(a, b)
	if a == nil then return 0.99 end
	return a
end
T = T + 100000
cb("onDropLoot")(mkMonster(701, "boss", 60), mkCorpse(1, {}))
math.random = realRandom
eq(K.value(cfg, X.state[1], "xp", T), 25, "no tile: given at once")
-- the items not installed: given at once, as before
ChaosPickups.installed = function() return false end
X.clear(hero)
math.random = function(a, b)
	if a == nil then return 0.99 end
	return a
end
T = T + 100000
cb("onDropLoot")(mkMonster(702, "boss", 60), mkCorpse(1, {}))
math.random = realRandom
eq(K.value(cfg, X.state[1], "xp", T), 25, "not installed: given at once")
ChaosPickups = nil

print(string.format("blessings_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
