-- Run from the server/ folder: luajit tests/casting_test.lua (and lua5.3; CI runs both)
-- Cast-time spells: data/lib/chaos_casting.lua and data/scripts/chaos/casting.lua against a mocked engine: a cast
-- completes on the server's timer (fire once, nothing given back), every interrupt (moving, new paralysis, another
-- spell, death, logout, client cancel, recast, town portal) gives the stored cost back exactly once, the failure check
-- at the end (target gone, out of range, out of sight) refunds, the fallback cost measurement without spell events,
-- the cast bar messages to the caster and to the players in view, and the client cannot complete a cast.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "expected true", 2)
	end
end

-- ---------------------------------------------------------------- engine mock
CONDITION_PARALYZE, CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT, CONDITIONID_COMBAT = 1, 2, 0, 1
CONDITION_PARAM_SUBID, CONDITION_PARAM_TICKS = 1, 2
CONST_ME_POFF, CONST_ME_MAGIC_RED = 3, 19

local clock = 0
os.mtime = function() return clock end

local queue = {}
function addEvent(fn, delay, ...)
	queue[#queue + 1] = {fn = fn, at = clock + (delay or 0), args = {n = select("#", ...), ...}}
	return #queue
end
-- run everything due up to `t` (in time order, then in order of scheduling)
local function advance(t)
	local guard = 0
	while true do
		guard = guard + 1
		assert(guard < 10000, "event loop")
		local best
		for i, e in ipairs(queue) do
			if e.at <= t and (not best or e.at < queue[best].at) then
				best = i
			end
		end
		if not best then
			break
		end
		local e = table.remove(queue, best)
		clock = math.max(clock, e.at)
		e.fn((table.unpack or unpack)(e.args, 1, e.args.n))
	end
	clock = t
end

json = {
	encode = function(t) return t end, -- the mock keeps tables; Chaos.send below records them
	decode = function(s) return s end,
}
local sent = {}
Chaos = {
	send = function(player, opcode, action, data)
		sent[#sent + 1] = {to = player.name, opcode = opcode, action = action, data = data}
	end,
	decode = function(b) return type(b) == "table" and b or nil end,
}
ChaosOpcodes = {castbar = 231}

local effects = {}
function Position(x, y, z)
	local blocked
	if type(x) == "table" then
		x, y, z, blocked = x.x, x.y, x.z, x.blocked
	end
	local p = {x = x, y = y, z = z, blocked = blocked}
	function p:sendMagicEffect(id) effects[#effects + 1] = id end
	function p:isSightClear(to) return not (to.blocked) end
	return p
end
function Fx(name, fallback) return fallback end

local players, creatures = {}, {}
local function newPlayer(id, name, mana)
	local p = {id = id, name = name, mana = mana, health = 1000, pos = {x = 100, y = 100, z = 7}, conds = {}, msgs = {}}
	function p:getId() return self.id end
	function p:getPlayer() return self end
	function p:getMana() return self.mana end
	function p:addMana(n) self.mana = self.mana + n end
	function p:getHealth() return self.health end
	function p:getMaxMana() return self.maxMana or 100000 end
	function p:getMaxHealth() return self.maxHealth or 100000 end
	function p:addHealth(n) self.health = self.health + n end
	function p:getPosition() return Position(self.pos) end
	function p:sendCancelMessage(t) self.msgs[#self.msgs + 1] = t end
	function p:getCondition(t, id, sub)
		return self.conds[t .. ":" .. (sub or 0)]
	end
	function p:removeCondition(t, id, sub)
		self.conds[t .. ":" .. (sub or 0)] = nil
		self.removed = (self.removed or 0) + 1
	end
	function p:addCondition(c)
		self.conds[c.type .. ":" .. (c.sub or 0)] = c
	end
	players[id], creatures[id] = p, p
	return p
end
function Player(id)
	if type(id) == "table" then
		return id
	end
	return players[id]
end
function Creature(id) return creatures[id] end
function Condition(t, id)
	local c = {type = t, sub = 0, ticks = 0}
	function c:setParameter(k, v)
		if k == CONDITION_PARAM_SUBID then self.sub = v elseif k == CONDITION_PARAM_TICKS then self.ticks = v end
	end
	return c
end
local inView = {}
Game = {getSpectators = function() return inView end}

-- creature events / revscripts
local registry = {}
function CreatureEvent(name)
	local e = {name = name}
	function e:type(t) self.t = t end
	function e:register() registry[self.name] = self end
	return e
end

dofile("data/lib/chaos_spell_events.lua")
dofile("data/lib/chaos_casting.lua")
dofile("data/scripts/chaos/casting.lua")
local C, E = ChaosCasting, ChaosSpellEvents

-- the engine's side of a cast: playerSpellCheck .. onCastSpell .. postCastSpell (mana, cooldown) .. onSpellCast
local function engineCast(player, onCastSpell, spellId, mana, cooldownMs, variant)
	if not onCastSpell(player, variant) then
		return false
	end
	player.mana = player.mana - mana
	local cd = Condition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT)
	cd:setParameter(CONDITION_PARAM_SUBID, spellId)
	cd:setParameter(CONDITION_PARAM_TICKS, cooldownMs)
	player:addCondition(cd)
	if E.live then
		E.onSpellCast(player, "x", spellId, 1, true, mana, 0)
	end
	return true
end

local fired = 0
local checkResult = true
local spell = C.spell({
	name = "Doomtide", spellId = 206, ms = 1500, fx = {"fire_nova", CONST_ME_MAGIC_RED},
	check = function(player, ctx) if checkResult == true then return true end return false, checkResult end,
	fire = function(player, ctx) fired = fired + 1 return true end,
})

local function lastTo(name, action)
	for i = #sent, 1, -1 do
		if sent[i].to == name and (not action or sent[i].action == action) then
			return sent[i]
		end
	end
end

E.live = true
local a = newPlayer(1, "Ash", 5000)
local b = newPlayer(2, "Bea", 100)
inView = {a, b}

-- ---------------------------------------------------------------- pure step
local cast = {pos = {x = 1, y = 1, z = 7}, endMs = 100}
eq(C.step(cast, 50, {x = 1, y = 1, z = 7}, false, 10), "wait", "wait")
eq(C.step(cast, 100, {x = 1, y = 1, z = 7}, false, 10), "done", "done at end")
eq(C.step(cast, 50, {x = 2, y = 1, z = 7}, false, 10), "moved", "moved")
eq(C.step(cast, 50, {x = 1, y = 1, z = 6}, false, 10), "moved", "floor change")
eq(C.step(cast, 50, {x = 1, y = 1, z = 7}, true, 10), "paralysed", "new paralysis")
cast.paralysedAtStart = true
eq(C.step(cast, 50, {x = 1, y = 1, z = 7}, true, 10), "wait", "paralysis already there")
eq(C.step(cast, 50, {x = 1, y = 1, z = 7}, false, 0), "died", "dead")
eq(C.clampMs(10), C.cfg.minMs, "clamp low"); eq(C.clampMs(99999), C.cfg.maxMs, "clamp high"); eq(C.clampMs(1500), 1500, "clamp")
local once = {cost = {mana = 30, health = 2}}
eq(C.refundOnce(once).mana, 30, "refund once"); eq(C.refundOnce(once), nil, "never twice")

-- ---------------------------------------------------------------- 1. completes on the server's timer
clock = 1000
ok(engineCast(a, spell, 206, 1500, 45000), "cast accepted")
eq(a.mana, 3500, "mana taken at once")
ok(a:getCondition(CONDITION_SPELLCOOLDOWN, 0, 206), "cooldown set at once")
eq(C.active[1].cost.mana, 1500, "cost from the spell event")
local st = lastTo("Ash", "start")
eq(st.opcode, 231, "opcode"); eq(st.data.n, "Doomtide", "bar name"); eq(st.data.ms, 1500, "bar ms")
eq(lastTo("Bea", "other").data.c, 1, "spectator sees the cast"); eq(lastTo("Bea", "other").data.n, "Doomtide", "spectator name")
-- the client cannot complete it: only cancel exists, and any other message is ignored
registry.ChaosCastingExtended.onExtendedOpcode(a, 231, {action = "end", data = {r = "done"}})
registry.ChaosCastingExtended.onExtendedOpcode(a, 231, {action = "done"})
advance(2400)
eq(fired, 0, "not before the time"); ok(C.active[1], "still casting at 1.4 s")
advance(2600)
eq(fired, 1, "fired once at the end"); eq(C.active[1], nil, "cast over")
eq(lastTo("Ash", "end").data.r, "done", "end done"); eq(lastTo("Bea", "otherEnd").data.r, "done", "spectator end")
eq(a.mana, 3500, "no refund after success"); ok(a:getCondition(CONDITION_SPELLCOOLDOWN, 0, 206).ticks == 45000, "cooldown kept")
advance(10000); eq(fired, 1, "fires only once")

-- ---------------------------------------------------------------- 2. moving interrupts and refunds once
a.conds = {}
clock = 20000
engineCast(a, spell, 206, 1500, 45000)
eq(a.mana, 2000, "paid")
advance(20500)
a.pos = {x = 101, y = 100, z = 7}
advance(20700)
eq(fired, 1, "moved: no fire"); eq(a.mana, 3500, "moved: mana back")
local cd = a:getCondition(CONDITION_SPELLCOOLDOWN, 0, 206)
eq(cd.ticks, C.cfg.cooldownAfterRefundMs, "cooldown replaced by a short one (the client is told)")
eq(lastTo("Ash", "end").data.r, "moved", "end moved"); eq(a.msgs[#a.msgs], C.TEXTS.moved, "moved text")
ok(not C.interrupt(a, "moved"), "nothing left to interrupt"); eq(a.mana, 3500, "no second refund")
advance(30000); eq(fired, 1, "never fires after an interrupt")
a.pos = {x = 100, y = 100, z = 7}

-- ---------------------------------------------------------------- 3. death, logout, cancel, another spell, paralysis
local function startAndThen(t0, what, reason)
	a.conds = {}
	clock = t0
	local before = a.mana
	engineCast(a, spell, 206, 1500, 45000)
	advance(t0 + 300)
	what()
	advance(t0 + 3000)
	eq(fired, 1, reason .. ": no fire"); eq(a.mana, before, reason .. ": mana back exactly once")
	eq(lastTo("Ash", "end").data.r, reason, reason .. ": result")
	eq(C.active[1], nil, reason .. ": not casting")
end
-- death: the cooldown comes back, mana and health do not (the engine fills both to the new maximum after the level
-- loss; the refund used to show mana above it in the stats sent after the loss)
do
	a.conds = {}
	clock = 40000
	local before = a.mana
	engineCast(a, spell, 206, 1500, 45000)
	advance(40300)
	a.health = 0
	registry.ChaosCastingDeath.onDeath(a)
	advance(43000)
	eq(fired, 1, "died: no fire"); eq(a.mana, before - 1500, "died: no mana back to a dead player")
	eq(lastTo("Ash", "end").data.r, "died", "died: result")
	eq(C.active[1], nil, "died: not casting")
	ok(a:getCondition(CONDITION_SPELLCOOLDOWN, 0, 206) == nil or a:getCondition(CONDITION_SPELLCOOLDOWN, 0, 206).ticks ~= 45000,
		"died: cooldown refunded")
	a.health = 1000
	a.mana = before
end
-- the refund never fills past the maximum
eq(select(1, C.refundAmounts({mana = 1500, health = 0}, 3000, 4000, 500, 1000)), 1000, "mana refund clamped to the maximum")
eq(select(2, C.refundAmounts({mana = 0, health = 300}, 0, 0, 900, 1000)), 100, "health refund clamped to the maximum")
eq(select(1, C.refundAmounts({mana = 1500, health = 0}, 4500, 4000, 500, 1000)), 0, "above the maximum already: nothing")
eq(select(1, C.refundAmounts({mana = 1500, health = 0}, 100, 4000, 0, 1000)), 0, "dead: nothing")
do
	a.conds = {}
	clock = 45000
	a.maxMana = a.mana -- full before the cast: the refund brings it back to full, not above
	local before = a.mana
	engineCast(a, spell, 206, 1500, 45000)
	advance(45300)
	a.mana = a.mana + 1000 -- regeneration during the cast
	C.interrupt(a, "moved")
	advance(48000)
	eq(a.mana, before, "refund clamped: back to full, not above")
	a.maxMana = nil
end
startAndThen(50000, function() registry.ChaosCastingLogout.onLogout(a) end, "logout")
startAndThen(60000, function() registry.ChaosCastingExtended.onExtendedOpcode(a, 231, {action = "cancel"}) end, "cancel")
startAndThen(70000, function() E.onSpellCast(a, "Lightward", 217, 3, false, 300, 0) end, "spell")
startAndThen(80000, function() a.conds[CONDITION_PARALYZE .. ":0"] = {type = CONDITION_PARALYZE} end, "paralysed")
-- paralysed before the cast: not an interrupt
a.conds = {[CONDITION_PARALYZE .. ":0"] = {type = CONDITION_PARALYZE}}
clock = 90000
engineCast(a, spell, 206, 1500, 45000)
advance(92000)
eq(fired, 2, "already paralysed: the cast completes")
a.conds = {}

-- ---------------------------------------------------------------- 4. the failure check refunds
clock = 100000
checkResult = "Your target is gone."
local m = a.mana
engineCast(a, spell, 206, 1500, 45000)
advance(102000)
eq(fired, 2, "check failed: no fire"); eq(a.mana, m, "check failed: refund"); eq(lastTo("Ash", "end").data.r, "failed", "failed")
eq(a.msgs[#a.msgs], "Your target is gone.", "failure text")
checkResult = true

-- ---------------------------------------------------------------- 5. recast and the town portal
a.conds = {}
clock = 110000
m = a.mana
engineCast(a, spell, 206, 1500, 45000)
a.conds = {} -- (a second cast-time spell without the cooldown in the way)
engineCast(a, spell, 206, 1500, 45000)
eq(a.mana, m - 1500, "recast: the first one was refunded, the second paid")
advance(112000)
eq(fired, 3, "recast: only the second fires")
ChaosTownPortal = {casts = {[1] = {}}}
m = a.mana
eq(engineCast(a, spell, 206, 1500, 45000), false, "refused while a town portal channels"); eq(a.mana, m, "nothing spent")
ChaosTownPortal = nil

-- ---------------------------------------------------------------- 6. without the spell events: measured cost
E.live = false
a.conds = {}
clock = 120000
m = a.mana
spell(a) -- the engine: onCastSpell, then it takes the mana in the same task
a.mana = a.mana - 1500
C.interrupt(a, "moved") -- before the measurement ran: the refund waits for it
eq(a.mana, m - 1500, "refund waits for the cost")
advance(120001)
eq(a.mana, m, "measured cost refunded"); advance(125000); eq(a.mana, m, "still once")
clock = 130000
spell(a)
a.mana = a.mana - 1500
advance(130000)
eq(C.active[1].cost.mana, 1500, "measured after two ticks")
advance(132000)
eq(fired, 4, "fallback cast completes")
E.live = true

-- ---------------------------------------------------------------- 7. target check
local t = newPlayer(3, "Goblin", 0)
t.pos = {x = 104, y = 100, z = 7}
eq(C.targetCheck(a, 3, 7), true, "in range")
t.pos = {x = 108, y = 100, z = 7}
eq(select(2, C.targetCheck(a, 3, 7)), "Your target is out of range.", "out of range")
t.pos = {x = 104, y = 100, z = 7, blocked = true}
eq(select(2, C.targetCheck(a, 3, 7)), "Your target is out of sight.", "out of sight")
t.pos = {x = 104, y = 100, z = 6}
eq(select(2, C.targetCheck(a, 3, 7)), "Your target is out of range.", "other floor")
t.pos = {x = 104, y = 100, z = 7}; t.health = 0
eq(select(2, C.targetCheck(a, 3, 7)), "Your target is gone.", "dead target")
eq(select(2, C.targetCheck(a, 99, 7)), "Your target is gone.", "no target")

-- prepare refusing: nothing starts, nothing is spent
local refused = C.spell({name = "X", spellId = 1, ms = 1000, prepare = function() return nil, "no" end, fire = function() end})
m = a.mana
eq(engineCast(a, refused, 1, 100, 1000), false, "prepare refused"); eq(a.mana, m, "refused: no cost"); eq(C.active[1], nil, "refused: no cast")

-- player gone without a logout event: the cast is dropped
clock = 140000
engineCast(a, spell, 206, 1500, 45000)
players[1] = nil
advance(142000)
eq(C.active[1], nil, "dropped"); eq(fired, 4, "no fire for a vanished player")

print(string.format("casting_test: %d checks passed (refunds %d)", checks, C.stats.refunds))
