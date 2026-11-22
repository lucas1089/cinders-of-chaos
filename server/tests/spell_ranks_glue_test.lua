-- Run from the server/ folder: luajit tests/spell_ranks_glue_test.lua && lua5.3 tests/spell_ranks_glue_test.lua (CI runs both)
-- O686 phase 2: spell_ranks.lua on a mocked engine: the spell catalogue of spells.xml, the combat log hooks (damage by spell id,
-- heals), the experience callback (index -9, the base experience rebuilt from rawExp, never the staged `exp`), SP, rank ups, the
-- storage, the account echo, the opcode, and that nothing changes while the switch is off.

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, tol, what)
	ok(math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " vs " .. tostring(b))
end

-- ---------------------------------------------------------------- the mocked engine
local registered = {callbacks = {}, events = {}, globals = {}, talks = {}}
local function evObj(kind)
	return function(name)
		local o = {name = name, kind = kind}
		function o:type(t) self.t = t end
		function o:register() registered.events[name] = self end
		function o:interval(i) self.i = i end
		function o:separator() end
		return o
	end
end
CreatureEvent = evObj("creature")
GlobalEvent = evObj("global")
TalkAction = evObj("talk")
EventCallback = {register = function(self, index) registered.callbacks[#registered.callbacks + 1] = {fn = self.onGainExperience, index = index} end}
MESSAGE_STATUS_DEFAULT, MESSAGE_INFO_DESCR = 1, 2
ORIGIN_SPELL, COMBAT_HEALING = 3, 9

local scheduled = {}
function addEvent(fn, delay, ...) scheduled[#scheduled + 1] = {fn = fn, delay = delay, args = {...}} end
local clock = 1000000
os.mtime = function() return clock end

local dbQueries, dbRows = {}, {}
db = {
	query = function(q) dbQueries[#dbQueries + 1] = q return true end,
	asyncQuery = function(q) dbQueries[#dbQueries + 1] = q end,
	storeQuery = function(q) return nil end,
}

json = {encode = function(t) return "json" end, decode = function(s) return nil end}
dofile("data/scripts/chaos/chaos_constants.lua")
local sent = {}
Chaos.send = function(player, opcode, action, data) sent[#sent + 1] = {opcode = opcode, action = action, data = data} return true end
Chaos.select = function(q, cols)
	if q:find("chaos_spell_ranks", 1, true) then
		return dbRows
	end
	return {}
end
Chaos.t = function(player, fmt, ...) return string.format(fmt, ...) end

-- the combat log table the hooks hang on
ChaosCombatLog = {}
-- xpcap: the real core; baseOf as xpcap.lua computes it, with stage 10 and no tier
dofile("data/scripts/chaos/xpcap_core.lua")
local STAGE = 10
ChaosXpCap.baseOf = function(player, source, rawExp, entered)
	if rawExp and rawExp > 0 then
		return ChaosXpCap.base(rawExp, source.level or 0, STAGE, 1)
	end
	return nil
end

-- a small spells.xml: two attacks, an ultimate, a heal, a support, a rune
local XML = [[
<spells>
	<instant group="attack" spellid="200" name="Bolt" words="a b" level="10" mana="40" cooldown="4000" groupcooldown="2000" script="chaos/x/a.lua"/>
	<instant group="attack" spellid="201" name="Wave" words="a c" level="10" mana="40" cooldown="10000" groupcooldown="2000" script="chaos/x/b.lua"/>
	<instant group="attack" spellid="202" name="Doom" words="a d" level="10" mana="40" cooldown="40000" groupcooldown="2000" script="chaos/x/c.lua"/>
	<instant group="healing" spellid="208" name="Mend" words="a e" level="10" mana="40" cooldown="2000" groupcooldown="2000" script="chaos/x/d.lua"/>
	<instant group="support" spellid="210" name="Ward" words="a f" level="10" mana="40" cooldown="2000" groupcooldown="2000" script="chaos/x/e.lua"/>
	<instant group="attack" spellid="203" name="Dup" words="a g" level="10" mana="40" cooldown="4000" script="chaos/x/f.lua"/>
	<instant group="attack" spellid="203" name="Dup2" words="a h" level="10" mana="40" cooldown="4000" script="chaos/x/g.lua"/>
	<rune group="attack" spellid="204" name="Rune" id="2268" level="10" mana="40" cooldown="2000"/>
</spells>]]

-- ---------------------------------------------------------------- creatures
local storages = {}
local messages = {}
local function newPlayer(id, level, account)
	storages[id] = storages[id] or {}
	local p = {id = id, level = level, account = account or id * 10}
	function p:getId() return self.id end
	function p:getLevel() return self.level end
	function p:getAccountId() return self.account end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getGuid() return self.id end
	function p:getStorageValue(k) local v = storages[self.id][k] return v == nil and -1 or v end
	function p:setStorageValue(k, v) storages[self.id][k] = v end
	function p:sendTextMessage(t, text) messages[#messages + 1] = text end
	function p:registerEvent() end
	return p
end
local function newMonster(id, maxHealth, level)
	local m = {id = id, max = maxHealth, level = level or 100}
	function m:getId() return self.id end
	function m:getMaxHealth() return self.max end
	function m:isMonster() return true end
	function m:isPlayer() return false end
	function m:getMaster() return self.master end
	function m:getName() return self.name or "Troll" end
	return m
end
Player = function(id) return nil end

-- ---------------------------------------------------------------- load the glue
dofile("data/scripts/chaos/spell_ranks.lua")
local R = ChaosSpellRanks
local P = ChaosSpellRanksCore
local cfg = ChaosSpellRanksConfig
-- O709 (owner 2026-11-21): the repository ships the upgrades on and tracking SP; every character starts from rank zero
eq(cfg.enabled, true, "ships switched on")
eq(cfg.track, true, "ships tracking SP")
do
	-- a character with no storage at all logs in on the shipped (on) config: rank 0 everywhere, the version written, no error line
	local printed = {}
	local realPrint = print
	print = function(...) printed[#printed + 1] = table.concat({...}, " ") end
	local fresh = newPlayer(990, 150, 9901)
	registered.events.ChaosSpellRanksLogin.onLogin(fresh)
	local state = ChaosSpellRanks.state(fresh)
	print = realPrint
	for _, line in ipairs(printed) do
		ok(not line:find("login:", 1, true), "a new character logs in without an error: " .. line)
	end
	ok(ChaosSpellRanks.players[990] ~= nil, "a new character: the state exists")
	for _, rank in pairs(ChaosSpellRanks.players[990].rank) do
		eq(rank, 0, "a new character: rank 0")
	end
	eq(state.on, true, "a new character: the state says on")
	eq(#state.s, 0, "a new character: no spell has a point")
	eq(fresh:getStorageValue(cfg.storage.version), cfg.version, "a new character: the version is written")
	ChaosSpellRanks.players[990] = nil
end
cfg.enabled = false -- the cases below are the off path and their own switch on; they start from off

eq(#registered.callbacks, 1, "one experience callback")
eq(registered.callbacks[1].index, -9, "at index -9: after the pace curve (-10), before every bonus")
ok(registered.events.ChaosSpellRanksLogin and registered.events.ChaosSpellRanksLogout and registered.events.ChaosSpellRanksExtended, "login, logout and opcode events")
eq(registered.events.ChaosSpellRanksExtended.t, "extendedopcode", "the opcode event type")
ok(registered.events.ChaosSpellRanksThink and registered.events.ChaosSpellRanksStartup, "startup and think events")
ok(ChaosCombatLog.spellHook == R.onDamage and ChaosCombatLog.healSpellHook == R.onHeal, "the combat log hooks are attached")
ok(ChaosSpellEvents.handlers.cost[#ChaosSpellEvents.handlers.cost].key == "spellranks", "a cost handler on the spell events")

-- ---------------------------------------------------------------- the catalogue
local cat = R.loadCatalog(XML)
ok(cat[200] and cat[201] and cat[202] and cat[208], "attack and healing instants are ranked")
ok(not cat[210], "a support spell is not ranked in phase 2")
ok(not cat[203], "an id used twice is dropped")
ok(not cat[204], "a rune is no instant")
ok(R.healIds[208] and not R.healIds[200], "heal ids")
eq(cat[200].scale, 1.0, "Bolt weight 1.0")
eq(cat[201].scale, 0.8, "Wave weight 0.8")
eq(cat[202].scale, 0.35, "Doom weight 0.35 (ultimate)")
eq(cat[208].scale, 0.7, "Mend weight 0.7 (heal)")

-- ---------------------------------------------------------------- login: state from the storage block
local pl = newPlayer(1, 100, 11)
local login = registered.events.ChaosSpellRanksLogin
login.onLogin(pl)
local st = R.players[1]
ok(st, "state loaded at login")
eq(st.rank[200], 0, "a fresh character: rank 0")
eq(storages[1][cfg.storage.version], cfg.version, "the block version is written")
eq(#dbQueries >= 1, true, "the echo table was ensured")

-- ---------------------------------------------------------------- the damage tables
local mon = newMonster(500, 1000, 100)
R.onDamage(pl, nil, mon, 300, 200) -- Bolt
R.onDamage(pl, nil, mon, 100, 201) -- Wave
R.onDamage(pl, nil, mon, 600, nil) -- an auto attack
local info = R.tracked[500]
eq(info.by[1].total, 1000, "the table counts every hit")
eq(info.by[1].spells[200], 300, "damage by spell id")
eq(info.max, 1000, "the monster's maximum health")
local minion = newMonster(501, 1000)
minion.name = "Bone Golem"
R.onDamage(pl, minion, mon, 50, nil)
eq(info.by[1].spells[186], 50, "a summon's hit is credited to the spell named for it")
-- a monster with a master (a summon or clone) never pays
local clone = newMonster(502, 1000)
clone.master = {}
R.onDamage(pl, nil, clone, 500, 200)
ok(R.tracked[502].ignore, "a clone is ignored")
eq(R.tracked[502].by[1], nil, "nothing recorded on a clone")
-- a trainer never pays
ChaosCombatLog.isTrainer = function(c) return c.id == 503 end
local dummy = newMonster(503, 100000)
R.onDamage(pl, nil, dummy, 500, 200)
ok(R.tracked[503].ignore, "a trainer is ignored")
ChaosCombatLog.isTrainer = nil

-- ---------------------------------------------------------------- the kill: the base experience, not the staged one
local xp = registered.callbacks[1].fn
mon.level = 100
local rawExp = 5000
-- the chain gave the character far more than the base: stage x10, potion x2, bonuses
local staged = 5000 * 3 * STAGE * 2 * 1.5
local out = xp(pl, mon, staged, rawExp)
eq(out, staged, "the callback returns the experience unchanged")
local base = ChaosXpCap.base(rawExp, 100, STAGE, 1)
local K = P.killValue(base, 100, cfg)
near(st.sp[200], K * 300 / 1050, 1e-12, "SP of Bolt = K x its share (300 of 1050), from the base experience")
near(st.sp[201], K * 100 / 1050, 1e-12, "SP of Wave = K x its share (100 of 1050; x1: not 4 ranks under anything yet)")
ok(st.sp[200] < P.killValue(staged, 100, cfg) * 0.3, "the staged experience would have paid more: it is not used")
eq(st.sp[186], nil, "a support's rank waits for its phase (Bone Golem not in the catalogue)")
ok(st.dirty[200], "the SP are marked to be written")
eq(storages[1][cfg.storage.spBase + 200], nil, "not written yet: the flush writes")
-- a second read of the same monster table by a party member without a table gets nothing
local member = newPlayer(2, 100, 21)
login.onLogin(member)
xp(member, mon, staged, rawExp)
eq(next(R.players[2].dirty), nil, "a member that dealt nothing earns nothing")
ok(#scheduled >= 1 and scheduled[#scheduled].delay == cfg.credit.afterDeathMs, "the table is dropped after the kill")
scheduled[#scheduled].fn(table.unpack and table.unpack(scheduled[#scheduled].args) or unpack(scheduled[#scheduled].args))
eq(R.tracked[500], nil, "dropped")

-- ---------------------------------------------------------------- flush and logout
R.flush(pl)
eq(storages[1][cfg.storage.spBase + 200], floor and nil or math.floor(st.sp[200] * cfg.spUnit + 0.5), "the flush writes SP in 1/spUnit")
eq(next(st.dirty), nil, "clean after the flush")
registered.events.ChaosSpellRanksLogout.onLogout(pl)
eq(R.players[1], nil, "state dropped at logout")
login.onLogin(pl)
near(R.players[1].sp[200], st.sp[200], 1 / cfg.spUnit, "SP come back from the storage")

-- ---------------------------------------------------------------- ranks: climbing, the message, the packed storage
st = R.players[1]
local mon2 = newMonster(510, 1000, 100)
local function kill(monster, hits, level, rawExpKill)
	for id, dmg in pairs(hits) do
		R.onDamage(pl, nil, monster, dmg, id)
	end
	xp(pl, monster, 1, rawExpKill)
end
-- give Bolt the SP of rank 4 minus a little, then one kill
st.sp[200] = P.cumCost(4, cfg) - 1e-6
st.rank[200] = 3
messages = {}
-- a huge kill, all damage Bolt: clamped to 0.05 hours, so rank 5+ at once
kill(mon2, {[200] = 1000}, 100, 1e12)
ok(st.rank[200] >= 4, "the rank rose: " .. st.rank[200])
eq(P.unpack(storages[1][cfg.storage.rankBase + 200]), st.rank[200], "the packed rank is stored")
ok(#messages >= 1 and messages[#messages]:find("Bolt reached rank", 1, true), "the player is told")
-- the climb is capped by the clamp: one kill never gives more than 3 minutes of K
local before = st.sp[200]
local mon3 = newMonster(511, 1000, 100)
kill(mon3, {[200] = 1000}, 100, 1e15)
near(st.sp[200] - before, 0.05, 1e-9, "a boss kill pays at most 3 minutes of K")

-- phase 6: a rank-up is pushed to the client at once, with the switch on only (the client polls `open` rarely)
sent = {}
st.sp[200], st.rank[200] = P.cumCost(9, cfg) - 1e-6, 8
kill(newMonster(514, 1000, 100), {[200] = 1000}, 100, 1e12)
ok(st.rank[200] >= 9, "the rank rose again")
eq(#sent, 0, "switch off: no rank message")
cfg.enabled = true
sent = {}
st.sp[200], st.rank[200] = P.cumCost(10, cfg) - 1e-6, 9
kill(newMonster(515, 1000, 100), {[200] = 1000}, 100, 1e12)
cfg.enabled = false
eq(#sent, 1, "switch on: one rank message for the one rank-up")
eq(sent[1].action, "rank", "a rank message")
eq(sent[1].opcode, 168, "on opcode 168")
local pushed = sent[1].data.s[1]
eq(pushed[1], 200, "of Bolt")
eq(pushed[2], st.rank[200], "its new rank")
local _, intoNow, costNow = P.rankOf(st.sp[200], R.catalog[200].scale, cfg)
near(pushed[3], intoNow, 0.001, "SP into the rank, as the state message gives it")
near(pushed[4], costNow, 0.001, "SP the next rank costs")

-- catch-up: a spell 5 ranks under the best of its weight earns double
st.sp[201], st.rank[201] = 0, 0 -- Wave weight band2
local waveBefore = st.sp[201]
st.rank[200] = 4
R.players[1].best = {band1 = 10, band2 = 10}
local mon4 = newMonster(512, 1000, 100)
kill(mon4, {[201] = 1000}, 100, 5000)
local base4 = ChaosXpCap.base(5000, 100, STAGE, 1)
near(st.sp[201] - waveBefore, P.killValue(base4, 100, cfg) * 2, 1e-12, "catch-up: x2 for a spell far under the best of its weight")

-- ---------------------------------------------------------------- testers and exclusions
local bot = newPlayer(3, 100, 31)
storages[3][Chaos.storage.tester] = 1
login.onLogin(bot)
ok(R.players[3].tester, "a tester is marked")
local mon5 = newMonster(513, 1000, 100)
R.onDamage(bot, nil, mon5, 1000, 200)
eq(R.tracked[513], nil, "a tester's damage is not even tracked")
-- O686 phase 8 (live pass): `testersEarn = true` is the switch of a live run with tester bots; it was dead (onDamage and onHeal dropped
-- a tester's hit before P.counts could read it), so a bot never earned a point
cfg.testersEarn = true
local monT = newMonster(517, 1000, 100)
R.onDamage(bot, nil, monT, 1000, 200)
ok(R.tracked[517] ~= nil, "testersEarn: a tester's damage is tracked")
cfg.testersEarn = false
-- the level gate
local low = newPlayer(4, 5, 41)
login.onLogin(low)
local mon6 = newMonster(514, 1000, 100)
R.onDamage(low, nil, mon6, 1000, 200)
xp(low, mon6, 100, 100)
eq(next(R.players[4].dirty), nil, "the tutorial earns nothing")
-- under 2% of the monster's health
local mon7 = newMonster(515, 100000, 100)
R.onDamage(pl, nil, mon7, 500, 200)
local sp7 = st.sp[200]
xp(pl, mon7, 100, 5000)
eq(st.sp[200], sp7, "under 2% of the health: nothing")
-- no experience from the engine (a dummy that pays none)
local mon8 = newMonster(516, 1000, 100)
R.onDamage(pl, nil, mon8, 1000, 200)
xp(pl, mon8, 0, 0)
eq(st.sp[200], sp7, "no experience: no SP")
-- a player as the source
local sp9 = st.sp[200]
xp(pl, newPlayer(9, 100), 100, 100)
eq(st.sp[200], sp9, "a player's death pays nothing")

-- ---------------------------------------------------------------- the heal pool
local ally = newPlayer(7, 100, 71)
ally.getMaxHealth = function() return 2000 end
local mon9 = newMonster(517, 1000, 100)
R.onDamage(pl, nil, mon9, 1000, 200)
R.onHeal(pl, ally, 500, 208, clock)
st.best = {}
local mendBefore = st.sp[208] or 0
local boltBefore = st.sp[200]
xp(pl, mon9, 100, 5000)
local base9 = ChaosXpCap.base(5000, 100, STAGE, 1)
local K9 = P.killValue(base9, 100, cfg)
ok(st.sp[208] > mendBefore, "a heal before the kill earns the heal spell SP")
near(st.sp[208] - mendBefore, K9 * 0.2, 1e-9, "the pool is 20% of K")
near(st.sp[200] - boltBefore, K9 * 0.8, 1e-9, "damage keeps 80%")
-- a heal of an unranked spell or a non-heal id is ignored
R.heals[1] = nil
R.onHeal(pl, ally, 500, 200, clock)
eq(R.heals[1], nil, "an attack spell id is no heal")

-- ---------------------------------------------------------------- the account echo
dbRows = {{spell_id = 200, best_rank = 14}, {spell_id = 208, best_rank = 3}}
local alt = newPlayer(5, 100, 51)
login.onLogin(alt)
local sa = R.players[5]
eq(sa.rank[200], 7, "echo: a new character starts at half the best rank (14 -> 7)")
eq(sa.rank[208], 1, "echo: 3 -> 1 on a heal (the SP of rank 1 x 0.7)")
eq(P.unpack(storages[5][cfg.storage.rankBase + 200]), 7, "the echo floor is written as the rank")
ok(sa.dirty[200], "the floor's SP are written at the next flush")
dbRows = {}
-- a rank up writes the account's best rank
local before = #dbQueries
local mon10 = newMonster(518, 1000, 100)
sa.sp[201], sa.rank[201] = P.cumCost(1, cfg) * 0.8 - 1e-9, 0
R.onDamage(alt, nil, mon10, 1000, 201)
xp(alt, mon10, 1, 1e12)
ok(sa.rank[201] >= 1, "alt climbed")
local wrote = false
for i = before + 1, #dbQueries do
	if dbQueries[i]:find("INSERT INTO `chaos_spell_ranks`", 1, true) and dbQueries[i]:find("GREATEST", 1, true) then
		wrote = true
	end
end
ok(wrote, "a rank up writes the echo table with GREATEST")
-- the tester never writes the table
before = #dbQueries
local bst = R.players[3]
bst.sp[200] = P.cumCost(1, cfg) - 1e-9
-- (a tester earns nothing at all, so the table is untouched by construction)
eq(#dbQueries, before, "a tester writes nothing")

-- ---------------------------------------------------------------- reassigned ids
cfg.reassigned = {[200] = 2}
storages[6] = {[cfg.storage.version] = 1, [cfg.storage.spBase + 200] = 100000, [cfg.storage.rankBase + 200] = P.pack(5, 1, 1, false)}
local old = newPlayer(6, 100, 61)
login.onLogin(old)
eq(R.players[6].rank[200], 0, "a stored version below the id's version clears the rank")
eq(storages[6][cfg.storage.spBase + 200], 0, "and its SP")
cfg.reassigned = {}

-- ---------------------------------------------------------------- the wire
sent = {}
local ext = registered.events.ChaosSpellRanksExtended
Chaos.decode = function(b) return b end
ext.onExtendedOpcode(pl, 999, {action = "open"})
eq(#sent, 0, "another opcode is ignored")
ext.onExtendedOpcode(pl, 168, {action = "open"})
eq(#sent, 1, "open answers once")
eq(sent[1].opcode, 168, "on opcode 168")
eq(sent[1].action, "state", "a state message")
eq(sent[1].data.on, false, "off while the switch is off")
ok(#sent[1].data.s >= 1, "the spells with SP are listed")
local row = sent[1].data.s[1]
eq(#row, 4, "id, rank, SP into the rank, SP the next rank costs")
sent = {}
ext.onExtendedOpcode(pl, 168, {action = "close"})
eq(#sent, 0, "an unknown action is ignored")

-- ---------------------------------------------------------------- switched off: no effect; switched on: the handlers
local costFn, cdFn
for _, h in ipairs(ChaosSpellEvents.handlers.cost) do
	if h.key == "spellranks" then costFn = h.fn end
end
for _, h in ipairs(ChaosSpellEvents.handlers.cooldown) do
	if h.key == "spellranks" then cdFn = h.fn end
end
storages[1][cfg.storage.rankBase + 200] = P.pack(20, 0, 0, false)
eq((costFn(pl, "Bolt", 200, 1, true, 100, 0)), 100, "off: the mana is unchanged")
eq(cdFn(pl, "Bolt", 200, 1, true, "spell", 4000), 4000, "off: the cooldown is unchanged")
eq(ChaosSpellRanks.healthFactor(2500), 1, "off: monster health x1")
cfg.enabled = true
eq((costFn(pl, "Bolt", 200, 1, true, 100, 0)), 80, "on: rank 20 takes 20% off the mana")
eq(cdFn(pl, "Bolt", 200, 1, true, "spell", 4000), 3600, "on: rank 20 takes 10% off the cooldown")
eq(cdFn(pl, "Bolt", 200, 1, true, "group", 4000), 4000, "on: the group cooldown is never touched")
eq((costFn(pl, "Ward", 210, 1, false, 100, 0)), 100, "on: an unranked spell is unchanged")
cfg.enabled = false

-- ---------------------------------------------------------------- the tick drops stale tables and writes
R.tracked[900] = {last = clock - cfg.credit.staleMs - 1, by = {}}
R.tracked[901] = {last = clock, by = {}}
R.tick(clock)
eq(R.tracked[900], nil, "a monster nothing has hit for a while is dropped")
ok(R.tracked[901] ~= nil, "a fresh one stays")

-- ---------------------------------------------------------------- off by `track`
cfg.track = false
local pt = newPlayer(8, 100, 81)
login.onLogin(pt)
local mon11 = newMonster(519, 1000, 100)
R.onDamage(pt, nil, mon11, 1000, 200)
xp(pt, mon11, 100, 5000)
eq(next(R.players[8].dirty), nil, "track = false: no SP")
cfg.track = true

print(string.format("spell_ranks_glue_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
