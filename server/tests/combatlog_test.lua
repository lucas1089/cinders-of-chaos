-- Run from the server/ folder: luajit tests/combatlog_test.lua (and lua5.3; CI runs both)
-- DPS meter and combat log. Part 1, the pure logic (combatlog_core.lua): sources and their attribution order, the
-- spells.xml index, the hit buffer, fight segmentation and labels, bounded rows, the session (hunt pause and reset),
-- the views sent to the client, the party brief, the sweep. Part 2, the engine glue (combatlog.lua) against a mocked
-- engine: weapon attacks, damage over time, summons, spells through the supports' cast context and the engine's
-- precast event, delayed spell hits named by CL.asSpell (the snares), runes, procs labelled by the calling file
-- (doTargetCombat wrapper, helper libraries, ORIGIN_NONE hits measured), thorns, damage taken by monster and element, mana shield, healing done / received / overhealing, bosses,
-- the party view with realms and sharing, the opcode actions and the hunt reset. Part 3, a synthetic benchmark
-- (20 characters x 10 hits/s): printed, with a generous upper bound so a slow CI machine does not fail it.

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

dofile("data/scripts/chaos/combatlog_core.lua")
local CL = ChaosCombatLog
local cfg = dofile("data/scripts/chaos/combatlog_config.lua")
CL.configure(cfg)
local DMG, HEAL, TAKEN, RECV = CL.DMG, CL.HEAL, CL.TAKEN, CL.RECV

-- ---------------------------------------------------------------- config
ok(cfg.idleMs >= 3000 and cfg.idleMs <= 15000, "fight idle time")
eq(cfg.keepFights, 10, "last 10 fights")
ok(cfg.maxRowsSent <= cfg.maxRows, "rows sent within the kept rows")
for file, def in pairs(cfg.procLabels) do
	ok(file:match("%.lua$") and type(def.name) == "string" and def.name ~= "", "proc label " .. file)
	ok(({p = true, x = true, m = true, i = true})[def.kind], "proc kind " .. file)
end

-- ---------------------------------------------------------------- spells.xml
local XML = [[
<spells>
	<!-- <instant name="Commented" words="x" spellid="999" /> -->
	<instant group="attack" spellid="201" name="Witchfire Bolt" words="kah pyr vesh" script="chaos/sorcerer/witchfire_bolt.lua" />
	<instant group="healing" spellid="2" name="Mend &amp; Hold" words="exura" script="healing/light_healing.lua" />
	<rune group="attack" spellid="201" name="Frostfall Rune" id="2274" script="attack/avalanche_rune.lua" />
	<rune group="attack" spellid="21" name="Death Mark Rune" id="2268" script="attack/sudden_death_rune.lua" />
	<conjure name="Conjure Arrow" words="exevo con" spellid="51" />
	<instant group="support" name="Death Mark Rune" words="rhun gal nyx" script="conjuring/sudden_death_rune.lua" />
</spells>]]
local idx = CL.parseSpells(XML)
eq(idx.count, 6, "six spells")
eq(idx.byName["witchfire bolt"].words, "kah pyr vesh", "words")
eq(idx.byName["mend & hold"].name, "Mend & Hold", "entities")
eq(idx.byName["frostfall rune"].rune, 2274, "rune item id")
eq(idx.byName["commented"], nil, "comments skipped")
eq(idx.byId[201].name, "Witchfire Bolt", "an id shared by a rune: the instant spell wins")
eq(idx.byId[21].name, "Death Mark Rune", "a rune id")
eq(idx.byName["death mark rune"].rune, 2268, "the conjure spell of the same name does not hide the rune")
eq(CL.parseSpells(nil).count, 0, "no file")

-- ---------------------------------------------------------------- sources and attribution
local O = CL.ORIGIN
local bolt = CL.castSource(idx.byName["witchfire bolt"])
eq(bolt.k, "s:Witchfire Bolt", "spell key")
eq(bolt.i, "kah pyr vesh", "spell icon = words")
local rune = CL.castSource(idx.byName["death mark rune"], 3155)
eq(rune.t, "r", "rune kind")
eq(rune.i, 3155, "rune icon = client id")
eq(CL.source("s", "Witchfire Bolt"), bolt, "sources are cached")
local supports = CL.procSource(cfg.procLabels["supports.lua"])
local minions = CL.procSource(cfg.procLabels["necro_lib.lua"])
eq(minions.helper, true, "necro library is a helper")

local function cls(tab, h) return CL.classify(tab, h) end
eq(cls(DMG, {origin = O.MELEE, weapon = "axe"}).n, "Axe attacks", "melee by weapon")
eq(cls(DMG, {origin = O.MELEE}).n, "Fist attacks", "no weapon: fist")
eq(cls(DMG, {origin = O.RANGED}).n, "Distance attacks", "ranged")
eq(cls(DMG, {origin = O.WAND}).n, "Wand attacks", "wand")
eq(cls(DMG, {origin = O.CONDITION, el = "earth"}).n, "Poison", "poison tick")
eq(cls(DMG, {origin = O.CONDITION, el = "fire"}).i, "burning", "burn tick icon")
eq(cls(DMG, {origin = O.CONDITION, el = "physical"}).n, "Bleeding", "bleed tick")
eq(cls(DMG, {origin = O.CONDITION, el = "lifedrain"}).n, "Damage over time", "other tick")
eq(cls(DMG, {origin = O.SPELL}).n, "Other", "a spell origin without a cast")
eq(cls(DMG, {origin = O.MELEE, cast = bolt}), bolt, "the cast wins over the origin")
eq(cls(DMG, {origin = O.SPELL, cast = bolt, summon = "Bone Golem"}).n, "Bone Golem", "a summon wins over the cast")
eq(cls(DMG, {origin = O.SPELL, cast = bolt, proc = supports}).n, "Spell supports", "a proc wins over the cast")
eq(cls(DMG, {origin = O.SPELL, cast = bolt, proc = minions}), bolt, "a helper library: the cast wins")
eq(cls(DMG, {origin = O.SPELL, proc = minions}).n, "Minions", "a helper library outside a cast")
eq(cls(HEAL, {origin = O.SPELL}).n, "Other healing", "heal without a source")
eq(cls(HEAL, {origin = O.CONDITION}).n, "Regeneration", "heal over time")
eq(cls(RECV, {origin = O.SPELL, cast = bolt}), bolt, "received from an own spell")
eq(CL.takenSource(nil).n, "Environment", "no attacker")
eq(CL.takenSource("c", "Dragon").k, "c:Dragon", "monster")
eq(CL.takenSource("u", "Tester").t, "u", "player")

-- ---------------------------------------------------------------- fights, buffer, session
local sword = CL.weaponSource("sword")
local poison = CL.dotSource("earth")
local a = CL.newActor(0)
eq(CL.add(a, 1000, HEAL, bolt, 0, false, 0), false, "nothing to count")
CL.add(a, 1000, HEAL, bolt, 50, false, 10)
eq(a.fight, nil, "healing alone starts no fight")
CL.add(a, 2000, DMG, sword, 100, false, 0, "physical", "Dragon")
ok(a.fight and a.fight.id == 1, "damage starts fight 1")
eq(a.fight.start, 2000, "fight start")
CL.add(a, 2500, DMG, sword, 300, true, 0, "physical", "Dragon")
CL.add(a, 3000, DMG, bolt, 200, false, 0, "fire", "Dragon Lord")
CL.add(a, 3500, TAKEN, CL.takenSource("c", "Dragon"), 80, false, 0, "fire")
eq(a.fight.tabs[DMG].total, 0, "buffered until the tick")
eq(CL.tick(a, 4000), true, "tick folds the buffer")
local f1 = a.fight
local t = f1.tabs[DMG]
eq(t.total, 600, "fight damage")
eq(t.rows[sword.k].hits, 2, "sword hits")
eq(t.rows[sword.k].crits, 1, "sword crits")
eq(t.rows[sword.k].max, 300, "sword max")
eq(t.el.physical, 400, "physical part")
eq(t.el.fire, 200, "fire part")
eq(f1.tabs[TAKEN].total, 80, "taken")
eq(f1.tabs[HEAL].total, 50, "the heal before the fight's first hit is in the same tick: counted")
eq(a.session.tabs[DMG].total, 600, "session damage")
eq(a.session.tabs[HEAL].over, 10, "overhealing")
eq(CL.duration(a, f1), 1500, "live duration: first to last hit")
eq(CL.fightLabel(f1), "Dragon +1", "most damaged target and how many others")
eq(CL.tick(a, 9000), false, "quiet but not yet idle")
ok(a.fight, "still in the fight 5.5 s later")
CL.tick(a, 9600)
eq(a.fight, nil, "ended 6 s after the last hit")
eq(#a.fights, 1, "one finished fight")
eq(a.fights[1].label, "Dragon +1", "label kept")
eq(a.fights[1].dur, 1500, "duration kept")
eq(a.session.dur, 1500, "session combat time")

-- a gap longer than idleMs inside add: the old fight ends with what was buffered before the gap
CL.add(a, 20000, DMG, poison, 30, false, 0, "earth", "Rat")
CL.add(a, 30000, DMG, poison, 40, false, 0, "earth", "Cave Rat")
eq(#a.fights, 2, "a new hit after the idle time ends the fight first")
eq(a.fights[1].tabs[DMG].total, 30, "the old fight got its buffered hit")
eq(a.fights[1].dur, cfg.minFightMs, "a one-hit fight counts minFightMs")
eq(a.fight.id, 3, "fight 3 runs")
CL.tick(a, 30500)
eq(a.fight.tabs[DMG].total, 40, "fight 3")

-- damage from no attacker (a fire field) neither starts nor extends a fight
local env = CL.newActor(0)
CL.add(env, 100, TAKEN, CL.takenSource(nil), 20, false, 0, "fire")
eq(env.fight, nil, "a field starts no fight")
CL.tick(env, 150)
CL.add(env, 200, DMG, sword, 10, false, 0, "physical", "Rat")
CL.add(env, 5000, TAKEN, CL.takenSource(nil), 20, false, 0, "fire")
eq(env.last, 200, "nor extends one")
CL.tick(env, 5100)
eq(env.fight.tabs[TAKEN].total, 20, "but counts in the running fight")
eq(env.session.tabs[TAKEN].total, 40, "and in the session")

-- keystone notes (source kind k): counted as a hit, never added to the tab, the elements or the targets, never start a fight
local kn = CL.newActor(0)
local deadeye = CL.source("k", "Keystone: Deadeye", "keystone")
CL.add(kn, 100, DMG, deadeye, 30, true, 5, "fire", "Rat", "Boss")
CL.tick(kn, 200)
eq(kn.fight, nil, "a note starts no fight")
eq(kn.session.tabs[DMG].total, 0, "a note is not added to the tab's total")
eq(kn.session.tabs[DMG].over, 0, "nor its overhealing")
eq(kn.session.tabs[DMG].rows["k:Keystone: Deadeye"].total, 30, "the row keeps how much it changed")
eq(kn.session.tabs[DMG].rows["k:Keystone: Deadeye"].hits, 1, "and how often")
eq(kn.session.tabs[DMG].rows["k:Keystone: Deadeye"].crits, 0, "a note is never a critical hit")
eq(next(kn.session.tabs[DMG].el), nil, "no element")
eq(kn.bufBoss, nil, "no boss")
CL.add(kn, 300, DMG, deadeye, 0, false, 0)
CL.tick(kn, 400)
eq(kn.session.tabs[DMG].rows["k:Keystone: Deadeye"].hits, 2, "a note of 0 still counts as a hit")
CL.add(kn, 500, DMG, sword, 40, false, 0, "physical", "Rat")
CL.add(kn, 600, DMG, deadeye, 10, false, 0)
CL.tick(kn, 700)
eq(kn.fight.tabs[DMG].total, 40, "a fight of real hits: the note is beside them")
eq(kn.fight.tabs[DMG].rows["k:Keystone: Deadeye"].total, 10, "and in the fight's rows")
eq(CL.view(kn, kn.fight).t[DMG].tot, 40, "the view's total leaves the note out")
local sawNote
for _, row in ipairs(CL.view(kn, kn.fight).t[DMG].r) do
	if row[1] == "k:Keystone: Deadeye" then
		sawNote = row
	end
end
ok(sawNote and sawNote[2] == "k" and sawNote[3] == "Keystone: Deadeye" and sawNote[4] == "keystone", "the client gets kind k, the name and the icon")
-- a full table drops a note (no "Other" row for it)
local kf = CL.newActor(0)
for i = 1, cfg.maxRows do
	CL.add(kf, 100, DMG, CL.source("s", "Spell" .. i, ""), 1, false, 0)
end
CL.add(kf, 100, DMG, deadeye, 50, false, 0)
CL.tick(kf, 200)
eq(kf.fight.tabs[DMG].n, cfg.maxRows, "a note does not take the Other row of a full table")
eq(kf.fight.tabs[DMG].total, cfg.maxRows, "and adds nothing")
-- notes are sent after the real sources, a limited number of them, and never push a source out of the rows sent
local ks = CL.newActor(0)
for i = 1, cfg.maxRowsSent + 3 do
	CL.add(ks, 100, DMG, CL.source("s", "Src" .. i, ""), i, false, 0)
end
for i = 1, cfg.maxRows - (cfg.maxRowsSent + 3) do -- the table has room for them
	CL.add(ks, 100, DMG, CL.source("k", "Keystone: N" .. i, "keystone"), 1000 + i, false, 0)
end
CL.tick(ks, 200)
local sentRows = CL.view(ks, ks.fight).t[DMG].r
eq(#sentRows, cfg.maxRowsSent + (cfg.maxNotesSent or 10), "rows sent: the limit of sources plus the limit of notes")
eq(sentRows[1][2], "s", "a source first, though the notes are larger")
eq(sentRows[cfg.maxRowsSent][2], "s", "the last source row")
eq(sentRows[cfg.maxRowsSent + 1][3], "Keystone: N" .. (cfg.maxRows - cfg.maxRowsSent - 3), "then the largest note")
eq(sentRows[#sentRows][2], "k", "and a note last")
-- a keystone's own heal (kind p) in the healing tab counts like any other source
local kh = CL.newActor(0)
CL.add(kh, 100, HEAL, CL.source("p", "Keystone: Undying Rage", "keystone"), 40, false, 0)
CL.tick(kh, 200)
eq(kh.session.tabs[HEAL].total, 40, "a keystone's own heal is counted")
eq(kh.fight, nil, "healing alone starts no fight")

-- boss label, taken-only label
local b = CL.newActor(0)
CL.add(b, 100, DMG, sword, 10, false, 0, "physical", "Rat")
CL.add(b, 200, DMG, sword, 5, false, 0, "physical", "Ashen Tyrant", "Ashen Tyrant")
CL.tick(b, 300)
eq(CL.fightLabel(b.fight), "Ashen Tyrant", "a boss names the fight")
eq(CL.view(b, b.fight).boss, 1, "boss flag")
local c = CL.newActor(0)
CL.add(c, 100, TAKEN, CL.takenSource("c", "Orc"), 10, false, 0, "physical")
CL.add(c, 100, TAKEN, CL.takenSource("c", "Orc Berserker"), 30, false, 0, "physical")
CL.tick(c, 200)
eq(CL.fightLabel(c.fight), "Orc Berserker", "only taken: the main attacker")

-- the last 10 fights
local d = CL.newActor(0)
for i = 1, 13 do
	CL.add(d, i * 10000, DMG, sword, i, false, 0, "physical", "T" .. i)
	CL.tick(d, i * 10000 + 7000)
end
eq(#d.fights, 10, "ten kept")
eq(d.fights[1].id, 13, "newest first")
eq(d.fights[10].id, 4, "oldest kept")
eq(d.session.tabs[DMG].total, 91, "the session keeps everything")
eq(CL.find(d, 3), nil, "fight 3 dropped")
eq(CL.find(d, 4).id, 4, "fight 4 found")
eq(CL.find(d, "c").id, 13, "no current fight: the last one")

-- session off (hunt paused), session reset, full reset
local e = CL.newActor(0)
e.sessionOn = false
CL.add(e, 100, DMG, sword, 50, false, 0, "physical", "Rat")
CL.tick(e, 200)
eq(e.fight.tabs[DMG].total, 50, "the fight counts while the hunt is paused")
eq(e.session.tabs[DMG].total, 0, "the session does not")
e.sessionOn = true
CL.add(e, 300, DMG, sword, 25, false, 0, "physical", "Rat")
CL.tick(e, 400)
eq(e.session.tabs[DMG].total, 25, "counts again")
CL.resetSession(e, 500)
eq(e.session.tabs[DMG].total, 0, "session reset")
ok(e.fight, "the fight stays")
CL.reset(e, 600)
eq(e.fight, nil, "reset: no fight")
eq(#e.fights, 0, "reset: no fights")
ok(CL.idle(e), "idle after reset")

-- bounded rows: beyond maxRows a source lands in "Other"
local g = CL.newActor(0)
for i = 1, cfg.maxRows + 5 do
	CL.add(g, 100, DMG, CL.source("s", "Spell " .. i, ""), i, false, 0, "fire", "Rat")
end
CL.tick(g, 200)
local rows = g.fight.tabs[DMG].rows
eq(g.fight.tabs[DMG].n, cfg.maxRows + 1, "maxRows + the Other row")
ok(rows["o:Other"], "Other row")
eq(rows["o:Other"].total, (cfg.maxRows + 1 + cfg.maxRows + 5) * 5 / 2, "Other holds the rest")
local sum = 0
for _, r in pairs(rows) do
	sum = sum + r.total
end
eq(sum, g.fight.tabs[DMG].total, "rows add up to the total")
ok(g.keys <= 3 * cfg.maxRows, "the buffer is bounded too")
-- the target table of a fight is bounded
local tg = CL.newActor(0)
for i = 1, cfg.maxTargets + 10 do
	CL.add(tg, 100, DMG, sword, 1, false, 0, "physical", "Mob " .. i)
end
CL.tick(tg, 200)
eq(tg.fight.nTargets, cfg.maxTargets, "targets bounded")

-- ---------------------------------------------------------------- views
local st = CL.state(a, "c")
eq(st.sel, "c", "follows the fights")
eq(st.v.id, 3, "the current fight")
eq(st.v.live, 1, "live")
eq(st.segs[1][1], "s", "session first")
eq(st.segs[2][1], 3, "then the current fight")
eq(st.segs[3][1], 2, "then the finished ones")
eq(#st.segs, 4, "session + current + 2 finished")
eq(st.segs[1][4], 670, "session damage in the list")
local v = CL.state(a, 1).v
eq(v.id, 1, "a chosen fight")
eq(v.t[1].tot, 600, "damage tab total")
eq(v.t[1].r[1][3], "Sword attacks", "largest row first")
eq(v.t[1].r[1][5], 400, "row total")
eq(v.t[1].r[1][6], 2, "row hits")
eq(v.t[1].r[1][7], 1, "row crits")
eq(v.t[1].r[1][8], 300, "row max")
eq(v.t[1].r[2][4], "kah pyr vesh", "spell icon")
eq(v.t[3].r[1][3], "Dragon", "taken by monster")
eq(v.t[3].el.fire, 80, "taken by element")
eq(CL.state(a, 99).sel, "c", "an unknown fight: back to the current one")
eq(CL.state(a, "s").v.id, "s", "the session")
eq(#CL.state(g, "c").v.t[1].r, cfg.maxRowsSent, "rows sent are limited")
eq(CL.state(CL.newActor(0), "c").v, nil, "nothing yet")
eq(CL.perSecond(600, 1500), 400, "per second")
eq(CL.perSecond(600, 0), 0, "no time")

local br = CL.brief(a)
eq(br.fd, 40, "brief: current fight damage")
eq(br.live, 1, "brief: live")
eq(br.sd, 670, "brief: session damage")
ok(br.fdur >= cfg.minFightMs, "brief: duration")
eq(br.r, nil, "brief: no breakdown")

local actors = {x = CL.newActor(0), y = CL.newActor(0)}
actors.x.offlineAt = 0
actors.y.offlineAt = 1000000
eq(CL.sweep(actors, 1900000, 1800000), 1, "sweep the old one")
ok(actors.y and not actors.x, "the recent one kept")

-- ======================================================================================== part 2: engine glue
-- ---------------------------------------------------------------- engine mock
ORIGIN_NONE, ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED = 0, 1, 2, 3, 4
COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_FIREDAMAGE = 1, 2, 4, 8
COMBAT_UNDEFINEDDAMAGE, COMBAT_LIFEDRAIN, COMBAT_MANADRAIN, COMBAT_HEALING = 16, 32, 64, 128
COMBAT_DROWNDAMAGE, COMBAT_ICEDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_DEATHDAMAGE = 256, 512, 1024, 2048
WEAPON_NONE, WEAPON_SWORD, WEAPON_CLUB, WEAPON_AXE, WEAPON_SHIELD, WEAPON_DISTANCE, WEAPON_WAND = 0, 1, 2, 3, 4, 5, 6
CONST_SLOT_RIGHT, CONST_SLOT_LEFT = 5, 6
CONDITION_MANASHIELD = 1 -- any value
RETURNVALUE_NOERROR = 0

local clock = 100000
os.mtime = function() return clock end

local events, callbacks, globals = {}, {}, {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type() end
	function o:register() events[name] = o end
	return o
end
EventCallback = setmetatable({register = function() end}, {__newindex = function(t, k, v) callbacks[k] = v end})
function GlobalEvent(name)
	local o = {}
	function o:interval() end
	function o:register() globals[name] = o end
	return o
end

local queued = {}
function addEvent(fn, ms, ...)
	queued[#queued + 1] = {fn = fn, args = {...}, n = select("#", ...)}
	return #queued
end
local unpack = unpack or table.unpack
local function runEvents()
	local list = queued
	queued = {}
	for _, e in ipairs(list) do
		e.fn(unpack(e.args, 1, e.n))
	end
end

local itemTypes = {
	[2400] = {cid = 2400, wt = WEAPON_SWORD}, [2431] = {cid = 2431, wt = WEAPON_AXE},
	[2190] = {cid = 2190, wt = WEAPON_WAND}, [2268] = {cid = 3155, wt = WEAPON_NONE},
}
function ItemType(id)
	local t = itemTypes[id] or {cid = id, wt = WEAPON_NONE}
	return {getClientId = function() return t.cid end, getWeaponType = function() return t.wt end}
end

local byId, nextId = {}, 1
local C = {}
C.__index = C
local function creature(o)
	o.id = o.id or nextId
	nextId = nextId + 1
	o.events = {}
	o.conds = o.conds or {}
	o.slots = o.slots or {}
	byId[o.id] = setmetatable(o, C)
	return o
end
function C:getId() return self.id end
function C:getGuid() return self.guid end
function C:getName() return self.name end
function C:isPlayer() return self.kind == "player" end
function C:isMonster() return self.kind == "monster" end
function C:getMaster() return self.master end
function C:getHealth() if self.removed then return nil end return self.hp end
function C:getMaxHealth() return self.maxHp end
function C:getMana() return self.mana or 0 end
function C:hasCondition(c) return self.conds[c] == true end
function C:getParty() return self.party end
function C:sendExtendedOpcode(op, buffer) self.lastOpcode = op return true end
function C:getSlotItem(slot)
	local id = self.slots[slot]
	return id and {getId = function() return id end} or nil
end
function C:registerEvent(name)
	for _, n in ipairs(self.events) do
		if n == name then return false end
	end
	self.events[#self.events + 1] = name
	return true
end
function C:getType() local boss = self.boss; return {isBoss = function() return boss == true end} end
function Creature(id) if type(id) == "table" then return id end return byId[id] end
function Player(id)
	local c = type(id) == "table" and id or byId[id]
	return c and c.kind == "player" and not c.offline and c or nil
end

-- the engine's damage path (Game::combatChangeHealth): health events (unless ORIGIN_NONE), then the change
local function engineHit(attacker, target, ctype, value, origin, crit)
	if not target or target.removed then return false end
	local pd, pt, sd, st = value, ctype, 0, COMBAT_NONE or 0
	if origin ~= ORIGIN_NONE then
		for _, name in ipairs(target.events) do
			local ev = events[name]
			if ev and ev.onHealthChange then
				pd, pt, sd, st = ev.onHealthChange(target, attacker, pd, pt, sd, st, origin, crit or false)
			end
		end
	end
	if ctype == COMBAT_HEALING then
		target.hp = math.min(target.maxHp, target.hp + math.abs(pd))
	else
		target.hp = math.max(0, target.hp - math.abs(pd) - math.abs(sd))
	end
	return true
end

-- the raw engine functions, before combatlog.lua wraps them. Like the engine (getNumber(L, 7, ORIGIN_SPELL)): a
-- missing origin is ORIGIN_SPELL, an explicit nil reads as 0 (ORIGIN_NONE)
local rawArgCount
function doTargetCombat(...)
	rawArgCount = select("#", ...)
	local cid, target, ctype, mn, mx, effect, origin = ...
	if origin == nil then
		origin = rawArgCount >= 7 and ORIGIN_NONE or ORIGIN_SPELL
	end
	return engineHit(Creature(cid), Creature(target), ctype, math.abs(mn), origin)
end
local areaTargets = {}
function doAreaCombat(cid, ctype, pos, area, mn, mx, effect, origin)
	for _, t in ipairs(areaTargets) do
		engineHit(Creature(cid), t, ctype, math.abs(mn), origin or ORIGIN_SPELL)
	end
	return true
end

-- what the client gets
local sent = {}
local decodeBox = {}
json = {
	encode = function(t) sent[#sent + 1] = t; return "#" .. #sent end,
	decode = function(s) return decodeBox[s] end,
}

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/lib/chaos_spell_events.lua")
-- the spell supports' cast context (data/spells/chaos/_supports.lua)
local supportsCtx
ChaosSupportsSpell = {cast = function() if supportsCtx then return supportsCtx[1], supportsCtx[2] end return nil end}
-- hunt sessions (only the clock matters here)
ChaosHunt = {sessions = {}, running = function(s) return not s.paused end}

dofile("data/scripts/chaos/combatlog.lua")
CL.loadSpells(XML)
ok(doTargetCombat == CL.wrappedTargetCombat, "doTargetCombat wrapped")
ok(doAreaCombat == CL.wrappedAreaCombat, "doAreaCombat wrapped")
local rawBefore = CL.rawTargetCombat
dofile("data/scripts/chaos/combatlog.lua") -- a /reload
CL.loadSpells(XML)
eq(CL.rawTargetCombat, rawBefore, "a reload wraps the original again, not the wrapper")

local function login(p)
	events.ChaosCombatLogLogin.onLogin(p)
	return p
end
local hero = login(creature({kind = "player", name = "Hero", guid = 1, hp = 1000, maxHp = 1000, mana = 500,
	slots = {[CONST_SLOT_LEFT] = 2400}}))
local mage = login(creature({kind = "player", name = "Mage", guid = 2, hp = 800, maxHp = 1000, mana = 500}))
local dragon = creature({kind = "monster", name = "Dragon", hp = 100000, maxHp = 100000})
local boss = creature({kind = "monster", name = "Ashen Tyrant", hp = 100000, maxHp = 100000, boss = true})
local golem = creature({kind = "monster", name = "Bone Golem", hp = 500, maxHp = 500, master = hero})
for _, n in ipairs({"ChaosCombatLogHealth", "ChaosCombatLogMana", "ChaosCombatLogLogout", "ChaosCombatLogExtended"}) do
	ok(hero:registerEvent(n) == false, "registered at login: " .. n)
end
-- attacking registers the health event on the monster
callbacks.onTargetCombat(hero, dragon)
callbacks.onTargetCombat(hero, boss)
callbacks.onTargetCombat(golem, dragon)
ok(dragon.events[1] == "ChaosCombatLogHealth", "registered on the target")

local function heroRows(tab, seg)
	local actor = CL.actors[hero.guid]
	CL.flush(actor)
	local s = CL.find(actor, seg or "c")
	local out = {}
	for _, r in pairs(s.tabs[tab].rows) do
		out[r.src.n] = r
	end
	return out, s
end

-- weapon attacks, crit, wand, distance
engineHit(hero, dragon, COMBAT_PHYSICALDAMAGE, 120, ORIGIN_MELEE, true)
engineHit(hero, dragon, COMBAT_PHYSICALDAMAGE, 80, ORIGIN_MELEE)
hero.slots[CONST_SLOT_LEFT] = 2190
engineHit(hero, dragon, COMBAT_ENERGYDAMAGE, 50, 5) -- ORIGIN_WAND has no Lua constant
engineHit(hero, dragon, COMBAT_PHYSICALDAMAGE, 40, ORIGIN_RANGED)
hero.slots[CONST_SLOT_LEFT] = nil
hero.slots[CONST_SLOT_RIGHT] = 2431
engineHit(hero, dragon, COMBAT_PHYSICALDAMAGE, 10, ORIGIN_MELEE)
local r = heroRows(DMG)
eq(r["Sword attacks"].total, 200, "sword")
eq(r["Sword attacks"].crits, 1, "crit from the engine's 8th argument")
eq(r["Wand attacks"].total, 50, "wand")
eq(r["Distance attacks"].total, 40, "distance")
eq(r["Axe attacks"].total, 10, "weapon in the other hand")
-- damage over time (the condition owner is the attacker)
engineHit(hero, dragon, COMBAT_EARTHDAMAGE, 7, ORIGIN_CONDITION)
engineHit(hero, dragon, COMBAT_FIREDAMAGE, 9, ORIGIN_CONDITION)
r = heroRows(DMG)
eq(r["Poison"].total, 7, "poison tick")
eq(r["Burning"].total, 9, "burn tick")
-- a summon hits for its master
engineHit(golem, dragon, COMBAT_PHYSICALDAMAGE, 33, ORIGIN_MELEE)
r = heroRows(DMG)
eq(r["Bone Golem"].total, 33, "summon")

-- a spell through the engine's precast / cast events (synchronous part), then outside it
ChaosSpellEvents.onSpellPreCast(hero, "Witchfire Bolt", 201, 1, true, 70, 0)
engineHit(hero, dragon, COMBAT_FIREDAMAGE, 300, ORIGIN_SPELL)
ChaosSpellEvents.onSpellCast(hero, "Witchfire Bolt", 201, 1, true, 70, 0)
engineHit(hero, dragon, COMBAT_FIREDAMAGE, 5, ORIGIN_SPELL)
r = heroRows(DMG)
eq(r["Witchfire Bolt"].total, 300, "spell between precast and cast")
eq(r["Other"].total, 5, "after the cast: other")
-- a failed cast never reaches onSpellCast: the context is gone after the dispatcher tick
ChaosSpellEvents.onSpellPreCast(hero, "Witchfire Bolt", 201, 1, true, 70, 0)
runEvents()
engineHit(hero, dragon, COMBAT_FIREDAMAGE, 4, ORIGIN_SPELL)
eq(heroRows(DMG)["Other"].total, 9, "stale precast cleared")
-- a rune
ChaosSpellEvents.onSpellPreCast(hero, "Death Mark Rune", 21, 1, true, 0, 0)
engineHit(hero, dragon, COMBAT_DEATHDAMAGE, 222, ORIGIN_SPELL)
ChaosSpellEvents.onSpellCast(hero, "Death Mark Rune", 21, 1, true, 0, 0)
r = heroRows(DMG)
eq(r["Death Mark Rune"].total, 222, "rune")
eq(r["Death Mark Rune"].src.i, 3155, "rune icon: the client id")
-- the supports' cast context (also in the addEvent callbacks of a wrapped spell)
supportsCtx = {hero.id, 201}
engineHit(hero, dragon, COMBAT_FIREDAMAGE, 111, ORIGIN_SPELL)
supportsCtx = {mage.id, 201}
engineHit(hero, dragon, COMBAT_FIREDAMAGE, 1, ORIGIN_SPELL)
supportsCtx = nil
r = heroRows(DMG)
eq(r["Witchfire Bolt"].total, 411, "supports cast context")
eq(r["Other"].total, 10, "another character's cast context is not ours")

-- procs labelled by the calling file
local function chunk(path, body)
	local f = assert((loadstring or load)(body, "@" .. path))
	return f
end
local supportsFile = chunk("data/scripts/chaos/supports.lua",
	"local a, t = ... local r = pcall(doTargetCombat, a, t, COMBAT_FIREDAMAGE, -60, -60, 0, ORIGIN_SPELL) return r")
local itemModsFile = chunk("data/scripts/chaos/item_mods.lua",
	"local a, t = ... local r = doTargetCombatHealth(a:getId(), t:getId(), COMBAT_PHYSICALDAMAGE, -25, -25, 0) return r")
local rarityFile = chunk("data/scripts/chaos/rarity_elements.lua",
	"local a, t = ... local r = doTargetCombat(a, t, COMBAT_ICEDAMAGE, -70, -70, 0, ORIGIN_NONE) return r")
local necroFile = chunk("data/scripts/chaos/necro_lib.lua",
	"local a, t = ... local r = doTargetCombat(a, t, COMBAT_DEATHDAMAGE, -15, -15, 0, ORIGIN_SPELL) return r")
local spellFile = chunk("data/spells/scripts/chaos/_common.lua",
	"local a, t = ... local r = doTargetCombat(a, t, COMBAT_HOLYDAMAGE, -20, -20, 0) return r")
local questFile = chunk("data/movements/scripts/some_trap.lua",
	"local a, t = ... local r = doTargetCombat(a, t, COMBAT_FIREDAMAGE, -3, -3, 0) return r")
local potionFile = chunk("data/actions/scripts/other/potions.lua",
	"local a, t = ... local r = doTargetCombat(a, t, COMBAT_HEALING, 90, 90, 0) return r")
local areaFile = chunk("data/scripts/chaos/weapon_styles.lua",
	"local a = ... local r = pcall(doAreaCombat, a, COMBAT_PHYSICALDAMAGE, {}, {}, -12, -12, 0) return r")
-- doTargetCombatHealth as data/global.lua has it (the wrapper skips that frame)
doTargetCombatHealth = chunk("data/global.lua", "return doTargetCombat(...)")

supportsFile(hero, dragon)
itemModsFile(hero, dragon)
local before = dragon.hp
rarityFile(hero, dragon)
eq(before - dragon.hp, 70, "the ORIGIN_NONE hit happened")
eq(rawArgCount, 7, "an explicit origin is passed on")
necroFile(hero, dragon)
supportsCtx = {hero.id, 201}
necroFile(hero, dragon) -- the library called by a spell: the spell
spellFile(hero, dragon) -- a spell script: the cast
-- no origin given (ChaosSpell.damageTarget / healTarget): the engine must get no origin argument at all, so it uses its
-- default ORIGIN_SPELL and the health events (tree bonus, class factor, keystones, healing rules) run; an explicit nil
-- was ORIGIN_NONE
eq(rawArgCount, 6, "a call without an origin reaches the engine without one")
supportsFile(hero, dragon) -- a support proc inside a cast: the support
supportsCtx = nil
questFile(hero, dragon)
areaTargets = {dragon}
areaFile(hero)
r = heroRows(DMG)
eq(r["Spell supports"].total, 120, "support procs, also inside a cast")
eq(r["Thorns"].total, 25, "thorns through doTargetCombatHealth (global.lua frame skipped)")
eq(r["Thorns"].src.t, "x", "thorns are reflect")
eq(r["Item elements"].total, 70, "an ORIGIN_NONE hit measured by the wrapper")
eq(r["Minions"].total, 15, "the helper library outside a cast")
eq(r["Witchfire Bolt"].total, 411 + 15 + 20, "the helper library and the spell file inside the cast")
eq(r["Other"].total, 13, "an unlisted file: other")
eq(r["Arrow splash"].total, 12, "doAreaCombat labelled")

-- keystone labels (keystone_labels.lua): procs named after the keystone, notes, restore after errors
local KL = ChaosKeystoneLabels
ok(KL.sink and KL.sink.run and KL.sink.note, "the combat log registered with the keystone labels")
local ksFile = chunk("data/scripts/chaos/passivetree_keystones.lua",
	"local a, t, flag, v = ... local r = ChaosKeystoneLabels.run(flag, pcall, doTargetCombat, a, t, COMBAT_PHYSICALDAMAGE, -v, -v, 0, ORIGIN_SPELL) return r")
local ksPlain = chunk("data/scripts/chaos/passivetree_keystones.lua",
	"local a, t, v = ... local r = pcall(doTargetCombat, a, t, COMBAT_PHYSICALDAMAGE, -v, -v, 0, ORIGIN_SPELL) return r")
ksFile(hero, dragon, "ksCleavingArc", 44)
ksFile(hero, dragon, "ksCleavingArc", 6)
ksFile(hero, dragon, "ksArcaneEcho", 9)
ksPlain(hero, dragon, 3) -- a keystone hit without a label keeps the file's "Keystones" row
ksFile(hero, dragon, "ksNoSuchKeystone", 2) -- a flag without a label: the file's row
supportsFile(hero, dragon)
r = heroRows(DMG)
eq(r["Keystone: Cleaving Arc"].total, 50, "a keystone proc is named after the keystone")
eq(r["Keystone: Cleaving Arc"].hits, 2, "with its hits")
eq(r["Keystone: Cleaving Arc"].src.t, "p", "kind p")
eq(r["Keystone: Cleaving Arc"].src.i, "keystone", "the keystone icon")
eq(r["Keystone: Arcane Echo"].total, 9, "another keystone, another row")
eq(r["Keystones"].total, 3 + 2, "unlabelled keystone hits keep the shared row")
eq(r["Spell supports"].total, 120 + 60, "a later proc is labelled by its file again")
-- inside a cast the keystone still wins (a proc is never the spell)
supportsCtx = {hero.id, 201}
ksFile(hero, dragon, "ksCleavingArc", 5)
supportsCtx = nil
eq(heroRows(DMG)["Keystone: Cleaving Arc"].total, 55, "a keystone proc inside a cast is the keystone")
-- an error inside run restores the outer label
local boom = chunk("data/scripts/chaos/passivetree_keystones.lua", "local KL = ChaosKeystoneLabels local r = KL.run('ksCleavingArc', function() error('boom') end) return r")
local okb, errb = pcall(boom)
ok(not okb and tostring(errb):find("boom"), "an error inside run goes on")
ksPlain(hero, dragon, 1)
eq(heroRows(DMG)["Keystones"].total, 3 + 2 + 1, "after an error the label is back to the file's")
-- notes
local dmgTotal = select(2, heroRows(DMG)).tabs[DMG].total
ok(KL.note(hero, "ksDeadeye", 31), "a note is recorded")
KL.note(hero, "ksDeadeye", 9)
KL.note(hero, "ksDivineVerdict", 0)
r = heroRows(DMG)
eq(r["Keystone: Deadeye"].total, 40, "a note row: how much it changed")
eq(r["Keystone: Deadeye"].hits, 2, "and how often")
eq(r["Keystone: Deadeye"].src.t, "k", "kind k")
eq(r["Keystone: Divine Verdict"].hits, 1, "a note without an amount counts")
eq(select(2, heroRows(DMG)).tabs[DMG].total, dmgTotal, "notes add nothing to the damage total")
-- the tab follows the label file
KL.note(hero, "ksImmovable", 70)
eq(heroRows(TAKEN)["Keystone: Immovable"].total, 70, "Immovable is in the damage taken tab")
local healTotal = select(2, heroRows(HEAL)).tabs[HEAL].total
KL.note(hero, "ksUndyingRage", 25)
eq(heroRows(HEAL)["Keystone: Undying Rage"].total, 25, "a keystone's own heal is in the healing tab")
eq(select(2, heroRows(HEAL)).tabs[HEAL].total, healTotal + 25, "and counts, Chaos.heal runs no health event")
-- safe calls
eq(KL.note(hero, "ksNoSuchKeystone", 5), false, "an unknown flag is ignored")
eq(KL.note(nil, "ksDeadeye", 5), false, "no character is ignored")
eq(KL.note(dragon, "ksDeadeye", 5), false, "a monster is ignored")
eq(select(2, heroRows(DMG)).tabs[DMG].total, dmgTotal, "still nothing added")
-- the meter's own switch
Chaos.combatLogConfig.enabled = false
eq(KL.note(hero, "ksDeadeye", 5), false, "the meter is off: no note")
Chaos.combatLogConfig.enabled = true
-- a spell's own delayed hits outside every cast context (the snares' scheduler, data/spells/chaos/_snares.lua): named
-- by CL.asSpell; another character's name is not ours; nothing is left behind, also after an error
local snareFile = chunk("data/spells/chaos/_snares.lua",
	"local a, t, v = ... local r = doTargetCombat(a, t, COMBAT_FIREDAMAGE, -v, -v, 0, ORIGIN_SPELL) return r")
CL.asSpell(hero.id, 201, snareFile, hero, dragon, 50)
CL.asSpell(mage.id, 201, snareFile, hero, dragon, 2)
CL.asSpell(hero.id, 201, function()
	CL.asSpell(hero.id, 999, snareFile, hero, dragon, 4) -- an unknown spell id: the outer name is not lost
	snareFile(hero, dragon, 6)
end)
ok(not pcall(CL.asSpell, hero.id, 201, error, "boom"), "an error is passed on")
snareFile(hero, dragon, 3)
r = heroRows(DMG)
eq(r["Witchfire Bolt"].total, 411 + 15 + 20 + 50 + 6, "delayed spell hits named by CL.asSpell")
eq(r["Other"].total, 13 + 2 + 4 + 3, "another character's name, an unknown id and after it: other")
-- the wrapper passes errors and results through and leaves no label behind
local okCall, err = pcall(doTargetCombat, hero, dragon, COMBAT_FIREDAMAGE)
ok(okCall or err, "wrapper call")
eq(doTargetCombat(hero, nil, COMBAT_FIREDAMAGE, -1, -1, 0), false, "result passed through")
hero.slots = {}
engineHit(hero, dragon, COMBAT_PHYSICALDAMAGE, 1, ORIGIN_MELEE)
eq(heroRows(DMG)["Fist attacks"].total, 1, "no label left on the stack, empty hands: fist")

-- damage taken: by monster and element, environment, mana shield, boss fight label
engineHit(dragon, hero, COMBAT_FIREDAMAGE, 150, ORIGIN_SPELL)
engineHit(dragon, hero, COMBAT_PHYSICALDAMAGE, 50, ORIGIN_MELEE)
engineHit(nil, hero, COMBAT_FIREDAMAGE, 20, ORIGIN_CONDITION)
hero.conds[CONDITION_MANASHIELD] = true
events.ChaosCombatLogMana.onManaChange(hero, dragon, 40, COMBAT_ICEDAMAGE, 0, 0, ORIGIN_SPELL)
hero.conds[CONDITION_MANASHIELD] = nil
events.ChaosCombatLogMana.onManaChange(hero, dragon, -40, COMBAT_MANADRAIN, 0, 0, ORIGIN_SPELL)
-- O159: a mana potion is doTargetCombat(player, who, COMBAT_MANADRAIN, +v): a restore, no hit taken, not "Yourself"
do
	local fed = {}
	local old = ChaosCombatLog.takenHook
	ChaosCombatLog.takenHook = function(...) fed[#fed + 1] = {...} end
	events.ChaosCombatLogMana.onManaChange(hero, hero, 500, COMBAT_MANADRAIN, 500, COMBAT_MANADRAIN, ORIGIN_NONE)
	eq(#fed, 0, "a mana restore is no hit taken")
	events.ChaosCombatLogMana.onManaChange(hero, dragon, -40, COMBAT_MANADRAIN, 0, 0, ORIGIN_SPELL)
	eq(#fed, 1, "a real mana drain is still fed to the recap")
	ChaosCombatLog.takenHook = old
end
local tr, seg = heroRows(TAKEN)
eq(tr["Dragon"].total, 240, "taken by monster, the mana shield part included")
eq(tr["Environment"].total, 20, "no attacker")
eq(seg.tabs[TAKEN].el.fire, 170, "taken by element")
eq(seg.tabs[TAKEN].el.ice, 40, "mana shield hit by element")
-- overkill is not counted
local rat = creature({kind = "monster", name = "Rat", hp = 30, maxHp = 30})
callbacks.onTargetCombat(hero, rat)
engineHit(hero, rat, COMBAT_PHYSICALDAMAGE, 500, ORIGIN_MELEE)
eq(heroRows(DMG)["Fist attacks"].total, 31, "capped at the target's health")
-- boss
engineHit(hero, boss, COMBAT_PHYSICALDAMAGE, 10, ORIGIN_MELEE)
local _, cur = heroRows(DMG)
eq(cur.boss, "Ashen Tyrant", "boss fight")

-- healing done, received, overhealing; a heal by another player; a potion
hero.hp = 900
ChaosSpellEvents.onSpellPreCast(hero, "Mend & Hold", 2, 2, false, 20, 0)
engineHit(hero, hero, COMBAT_HEALING, 150, ORIGIN_SPELL)
ChaosSpellEvents.onSpellCast(hero, "Mend & Hold", 2, 2, false, 20, 0)
local hr = heroRows(HEAL)
eq(hr["Mend & Hold"].total, 100, "healing up to the missing health")
eq(hr["Mend & Hold"].over, 50, "overhealing")
local rr = heroRows(RECV)
eq(rr["Mend & Hold"].total, 100, "own heal received")
hero.hp = 500
engineHit(mage, hero, COMBAT_HEALING, 200, ORIGIN_SPELL)
rr = heroRows(RECV)
eq(rr["Mage"].total, 200, "received from another player")
CL.flush(CL.actors[mage.guid])
eq(CL.find(CL.actors[mage.guid], "s").tabs[HEAL].total, 200, "the healer's healing done")
hero.hp = 600
potionFile(hero, hero)
eq(heroRows(HEAL)["Potions"].total, 90, "potion label")
-- a measured heal (ORIGIN_NONE): what the health really went up by
hero.hp = 990
doTargetCombat(hero, hero, COMBAT_HEALING, 50, 50, 0, ORIGIN_NONE)
eq(heroRows(HEAL)["Other healing"].total, 10, "a measured heal is not capped twice")

-- ---------------------------------------------------------------- opcode, party, realms, share, hunt
local OPCODE = ChaosOpcodes.combatLog
eq(OPCODE, 204, "opcode 204")
local function msg(p, action, data)
	local key = "k" .. tostring(math.random(1, 1e9))
	decodeBox[key] = {action = action, data = data}
	events.ChaosCombatLogExtended.onExtendedOpcode(p, OPCODE, key)
	return sent[#sent]
end
local n0 = #sent
msg(hero, "seg", {id = "s"})
eq(#sent, n0, "nothing before open")
local out = msg(hero, "open", {seg = "c", party = false, share = true})
eq(out.action, "state", "state on open")
eq(out.data.sel, "c", "current fight")
eq(out.data.party, nil, "no party list unless asked")
out = msg(hero, "seg", {id = "s"})
eq(out.data.v.id, "s", "session chosen")
out = msg(hero, "seg", {id = "bogus"})
eq(out.data.sel, "c", "bad id: current")
-- party: a member of another realm or that does not share is not listed
local partyObj = {}
local rogue = login(creature({kind = "player", name = "Rogue", guid = 3, hp = 100, maxHp = 100}))
local stranger = login(creature({kind = "player", name = "Stranger", guid = 4, hp = 100, maxHp = 100}))
function partyObj:getLeader() return hero end
function partyObj:getMembers() return {mage, rogue, stranger} end
hero.party, mage.party, rogue.party, stranger.party = partyObj, partyObj, partyObj, partyObj
engineHit(rogue, dragon, COMBAT_PHYSICALDAMAGE, 70, ORIGIN_MELEE)
engineHit(stranger, dragon, COMBAT_PHYSICALDAMAGE, 70, ORIGIN_MELEE)
msg(rogue, "open", {seg = "c", share = false})
ChaosSeason = {current = function() return {id = 1} end,
	realmOf = function(p) return p == stranger and 1 or 0 end}
out = msg(hero, "party", {on = true})
local names = {}
for _, m in ipairs(out.data.party) do
	names[m.n] = m
end
ok(names.Hero and names.Hero.self == 1, "self listed")
ok(names.Mage, "a sharing member of the same realm")
eq(names.Rogue, nil, "a member that does not share")
eq(names.Stranger, nil, "a member of another realm")
eq(names.Mage.r, nil, "totals only")
ok(names.Mage.sh >= 200, "the member's session healing")
ChaosSeason = nil
msg(rogue, "share", {on = true})
out = msg(hero, "party", {on = true})
eq(#out.data.party, 4, "everybody shares, no season")
-- the tick pushes only when something changed
clock = clock + 2000
local before2 = #sent
globals.ChaosCombatLogThink.onThink(1000)
local pushed = #sent - before2
clock = clock + 2000
local before3 = #sent
globals.ChaosCombatLogThink.onThink(1000)
eq(#sent, before3, "nothing changed: nothing pushed")
engineHit(hero, dragon, COMBAT_PHYSICALDAMAGE, 5, ORIGIN_MELEE)
clock = clock + 2000
globals.ChaosCombatLogThink.onThink(1000)
ok(#sent > before3, "a new hit: pushed")
ok(pushed >= 0, "first tick")
-- the display scale (display_scale_core.lua, server/README.md "Display scale"): the state a viewer gets is x the factor
-- of its own level (totals, rows, elements, the party's totals); hits, crits and durations stay; the meter's own
-- numbers stay raw; a new factor (a level up) is a new state for the push
dofile("data/scripts/chaos/display_scale_core.lua")
ChaosDisplayScale.configure({curve = {{100, 1}, {1000, 1000}, {1500, 10000}}}) -- the scale is off (x1); its code is tested on the old curve
function C:getLevel() return self.level or 1 end
local plainState = msg(hero, "seg", {id = "s"}).data
hero.level = 1000
local scaledState = msg(hero, "seg", {id = "s"}).data
local pt, st = plainState.v.t[DMG], scaledState.v.t[DMG]
ok(pt.tot > 0, "the session has damage")
eq(st.tot, pt.tot * 1000, "scaled: damage total")
eq(scaledState.v.t[HEAL].tot, plainState.v.t[HEAL].tot * 1000, "scaled: healing total")
eq(st.r[1][5], pt.r[1][5] * 1000, "scaled: a row's total")
eq(st.r[1][8], pt.r[1][8] * 1000, "scaled: a row's max hit")
eq(st.r[1][6], pt.r[1][6], "hits stay")
eq(st.r[1][7], pt.r[1][7], "crits stay")
local elSum, rowSum = 0, 0
for _, a in pairs(st.el) do elSum = elSum + a end
for _, r in ipairs(st.r) do if r[2] ~= "k" then rowSum = rowSum + r[5] end end
local plainElSum = 0
for _, a in pairs(pt.el) do plainElSum = plainElSum + a end
eq(elSum, plainElSum * 1000, "elements x1000")
ok(rowSum <= st.tot, "the shown rows add up within the shown total")
eq(scaledState.segs[1][4], plainState.segs[1][4] * 1000, "segment list: damage")
eq(scaledState.segs[1][3], plainState.segs[1][3], "segment list: duration stays")
eq(scaledState.v.dur, plainState.v.dur, "duration stays")
local function byName(list) local o = {} for _, m in ipairs(list or {}) do o[m.n] = m end return o end
local pp, sp = byName(plainState.party), byName(scaledState.party)
eq(sp.Mage.sh, pp.Mage.sh * 1000, "a party member's totals in the viewer's scale")
eq(sp.Mage.sdur, pp.Mage.sdur, "a party member's duration stays")
eq(CL.actors[hero.guid].session.tabs[DMG].total, pt.tot, "the meter's own numbers stay raw")
mage.level = 300
local mageView = msg(mage, "open", {seg = "s", party = true, share = true}).data
eq(byName(mageView.party).Hero.sd, pp.Hero.sd * 5, "another viewer: its own scale (level 300: x5)")
msg(mage, "close", {})
-- the factor is part of the push signature: a level change alone pushes the state again
clock = clock + 2000
globals.ChaosCombatLogThink.onThink(1000)
local beforeLevel = #sent
hero.level = 700
clock = clock + 2000
globals.ChaosCombatLogThink.onThink(1000)
ok(#sent > beforeLevel, "a new factor: pushed")
eq(sent[#sent].data.v.t[DMG].tot, pt.tot * 100, "level 700: x100")
hero.level, mage.level = nil, nil
C.getLevel = nil
-- hunt: paused hunt keeps the session still, a hunt reset starts it over
ChaosHunt.sessions[hero.guid] = {paused = true}
local sBefore = CL.actors[hero.guid].session.tabs[DMG].total
engineHit(hero, dragon, COMBAT_PHYSICALDAMAGE, 1000, ORIGIN_MELEE)
CL.flush(CL.actors[hero.guid])
eq(CL.actors[hero.guid].session.tabs[DMG].total, sBefore, "hunt paused: the session waits")
ChaosHunt.sessions[hero.guid] = nil
CL.onHuntReset(hero)
eq(CL.actors[hero.guid].session.tabs[DMG].total, 0, "hunt reset: session starts over")
out = msg(hero, "reset", {})
eq(#out.data.segs, 1, "meter reset: only the session")
msg(hero, "close", {})
eq(CL.watch[hero.id], nil, "closed")
-- logout ends the fight, keeps the numbers; the sweep drops them later
engineHit(hero, dragon, COMBAT_PHYSICALDAMAGE, 3, ORIGIN_MELEE)
events.ChaosCombatLogLogout.onLogout(hero)
eq(CL.actors[hero.guid].fight, nil, "logout ends the fight")
eq(#CL.actors[hero.guid].fights, 1, "and keeps it")

-- ======================================================================================== part 3: benchmark
-- 20 characters x 10 hits per second for 10 minutes (120,000 hits) through CL.add, a tick per second for each, and a
-- state built for each of them every second (as if every one had the meter open: the worst case).
local function bench(label, fn)
	local t0 = os.clock()
	local n = fn()
	local dt = os.clock() - t0
	return dt, n
end
local players, seconds, rate = 20, 600, 10
local srcs = {CL.weaponSource("sword"), bolt, rune, CL.dotSource("earth"), supports.src, CL.source("m", "Bone Golem")}
local taken = CL.takenSource("c", "Dragon")
local pool = {}
for i = 1, players do
	pool[i] = CL.newActor(0)
end
local hits = 0
local tAdd = bench("add", function()
	for sec = 1, seconds do
		local base = sec * 1000
		for i = 1, players do
			local actor = pool[i]
			for k = 1, rate do
				CL.add(actor, base + k * 100, DMG, srcs[(k + i) % #srcs + 1], 100 + k, k % 4 == 0, 0, "fire",
					(sec % 40 < 30) and "Dragon" or nil)
				hits = hits + 1
			end
			CL.add(actor, base + 500, TAKEN, taken, 50, false, 0, "fire")
			hits = hits + 1
		end
		if sec % 40 == 35 then
			for i = 1, players do
				CL.tick(pool[i], base + 9000) -- a pause: the fights end
			end
		end
	end
	return hits
end)
-- ticks and state builds, separately
local tTick = bench("tick", function()
	for sec = 1, seconds do
		for i = 1, players do
			CL.add(pool[i], 700000 + sec * 1000, DMG, srcs[1], 10, false, 0, "fire", "Dragon")
			CL.tick(pool[i], 700000 + sec * 1000 + 1)
		end
	end
end)
local tState = bench("state", function()
	for sec = 1, 60 do
		for i = 1, players do
			CL.state(pool[i], "c")
		end
	end
end)
local usPerHit = tAdd / hits * 1e6
local usPerTick = tTick / (seconds * players) * 1e6
local usPerState = tState / (60 * players) * 1e6

-- the engine path (combatlog.lua onHealth with the mocked engine: Lua stand-ins for the C getters)
local benchDragon = creature({kind = "monster", name = "Dragon", hp = 1e12, maxHp = 1e12})
local tEngine, engineHits = bench("engine", function()
	local n = 0
	local wielder = login(creature({kind = "player", name = "Bench", guid = 99, hp = 1000, maxHp = 1000,
		slots = {[CONST_SLOT_LEFT] = 2400}}))
	for k = 1, 50000 do
		clock = clock + 10
		CL.onHealth(benchDragon, wielder, -100, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE, k % 5 == 0)
		n = n + 1
	end
	return n
end)
local usEngine = tEngine / engineHits * 1e6
-- one second of the server with 20 fighting characters: 220 hits through the engine glue, 20 ticks, 20 states
local msPerSecond = (math.max(usEngine, usPerHit) * players * (rate + 1) + usPerTick * players + usPerState * players) / 1000
print(string.format("combatlog benchmark (%s): %d hits, %.2f us/hit (core), %.2f us/hit (engine glue, mocked " ..
	"getters), %.1f us/tick, %.1f us/state; 20 characters x 10 hits/s = %.3f ms of CPU per second (%.3f%%)",
	jit and jit.version or _VERSION, hits, usPerHit, usEngine, usPerTick, usPerState, msPerSecond, msPerSecond / 10))
ok(usPerHit < 50, "core hit cost bounded")
ok(msPerSecond < 50, "20 x 10 hits/s stays well under 5% of one core")

print("combatlog_test: OK (" .. checks .. " checks)")
