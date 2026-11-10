-- Run from the server/ folder: luajit tests/player_defence_test.lua (CI runs it with LuaJIT and Lua 5.3)
--   luajit tests/player_defence_test.lua --table   prints the tables of the README "Player defence (O464)"
-- Player defence (O464): player_defence_core.lua (avoidance, armour by hit size, the physical reduction, the four resistances,
-- the level penalty, the engine's absorb taken out again) and the engine file player_defence.lua against a mocked engine:
-- a small, a median and a five times median hit for a low, a median and a high armour character at levels 100, 500 and 1000;
-- what each layer ignores (attack, spell, tick, field, scripted hit); the penalty marks and the notices; a negative
-- resistance; the caps; PvP; the sources of the groups; the mana shield provider; the registration order.

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
local function near(a, b, tol, what)
	ok(math.abs(a - b) <= tol, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local PRINT_TABLE = arg and arg[1] == "--table"

-- ---------------------------------------------------------------- engine mock
COMBAT_NONE, COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_FIREDAMAGE = 0, 1, 2, 4, 8
COMBAT_UNDEFINEDDAMAGE, COMBAT_LIFEDRAIN, COMBAT_MANADRAIN, COMBAT_HEALING = 16, 32, 64, 128
COMBAT_DROWNDAMAGE, COMBAT_ICEDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_DEATHDAMAGE = 256, 512, 1024, 2048
COMBAT_WATERDAMAGE, COMBAT_ARCANEDAMAGE = 4096, 8192
ORIGIN_NONE, ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED, ORIGIN_WAND = 0, 1, 2, 3, 4, 5
RETURNVALUE_NOERROR = 0
CONST_ME_BLOCKHIT = 3
MESSAGE_EVENT_ADVANCE = 19
SKILL_LEVEL = 8
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")

local events = {}
function CreatureEvent(name)
	local e = {name = name}
	function e:register() events[name] = self end
	function e:type() end
	return e
end
local callbacks = {}
EventCallback = setmetatable({register = function(self, prio) callbacks[#callbacks + 1] = rawget(self, "_pending") end},
	{__newindex = function(t, k, v) rawset(t, "_pending", {k, v}) end})

local storage = {}
local function position()
	return {effects = {}, sendMagicEffect = function(self, e) self.effects[#self.effects + 1] = e end}
end
local abilityOf = {}
function ItemType(id)
	return {getAbilities = function() return abilityOf[id] end, getArmor = function() return 0 end}
end
local nextId = 0x10000000
local function newPlayer(opts)
	opts = opts or {}
	nextId = nextId + 1
	local p = {id = nextId, level = opts.level or 100, slots = {}, messages = {}, pos = position(), registered = {}}
	function p:getId() return self.id end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getMaster() return nil end
	function p:getLevel() return self.level end
	function p:getPosition() return self.pos end
	function p:getSlotItem(slot) return self.slots[slot] end
	function p:getStorageValue(k) return storage[self.id .. ":" .. k] or -1 end
	function p:setStorageValue(k, v) storage[self.id .. ":" .. k] = v end
	function p:sendTextMessage(t, text) self.messages[#self.messages + 1] = text end
	function p:registerEvent(name) self.registered[#self.registered + 1] = name end
	return p
end
local function newMonster(master)
	nextId = nextId + 1
	local m = {id = nextId, master = master}
	function m:getId() return self.id end
	function m:isPlayer() return false end
	function m:isMonster() return true end
	function m:getMaster() return self.master end
	return m
end

-- the totals of ChaosItemMods the layer reads
local bonusOf = {}
ChaosItemMods = {config = {absorbCeiling = 75}, playerBonus = function(p, key) return (bonusOf[p:getId()] or {})[key] or 0 end}

dofile("data/scripts/chaos/player_defence.lua")
local PD = ChaosPlayerDefence
local C = ChaosPlayerDefenceCore
local K = C.engineConstants()
local DEF = Chaos.defence
local CFG = Chaos.playerDefence
local ev = events.ChaosPlayerDefence
ok(ev ~= nil, "the event exists")

-- ---------------------------------------------------------------- the shared numbers and the config
eq(DEF.armourHitFactor, 0.07, "armourHitFactor")
eq(DEF.physicalReductionCap, 90, "physicalReductionCap")
eq(DEF.resistCap, 75, "resistCap")
eq(DEF.blockCap, 75, "blockCap")
eq(DEF.resistFloor, -100, "resistFloor")
eq(CFG.dodgeCap, 75, "dodgeCap")
eq(CFG.suppressCap, 100, "suppressCap")
eq(CFG.suppressLess, 50, "a suppressed hit deals 50% less")
eq(Chaos.playerDefence.penalty.marks[1].level, 250, "first mark")
eq(Chaos.playerDefence.penalty.marks[1].points, 30, "first penalty")
eq(Chaos.playerDefence.penalty.marks[2].level, 500, "second mark")
eq(Chaos.playerDefence.penalty.marks[2].points, 60, "second penalty (total)")

-- the four groups
local GROUP_OF = PD.groupOf
eq(GROUP_OF[K.fire], "fire", "fire is fire")
for _, n in ipairs({"ice", "water", "drown"}) do eq(GROUP_OF[K[n]], "cold", n .. " is cold") end
for _, n in ipairs({"energy", "holy", "arcane"}) do eq(GROUP_OF[K[n]], "lightning", n .. " is lightning") end
for _, n in ipairs({"earth", "death", "lifedrain", "manadrain"}) do eq(GROUP_OF[K[n]], "chaos", n .. " is chaos") end
eq(GROUP_OF[K.physical], nil, "physical is not a resistance")

-- ---------------------------------------------------------------- the level penalty
eq(C.penalty(CFG, 1), 0, "level 1")
eq(C.penalty(CFG, 249), 0, "level 249")
eq(C.penalty(CFG, 250), 30, "level 250")
eq(C.penalty(CFG, 499), 30, "level 499")
eq(C.penalty(CFG, 500), 60, "level 500")
eq(C.penalty(CFG, 1500), 60, "level 1500")
do
	local off = {penalty = {enabled = false, marks = CFG.penalty.marks}}
	eq(C.penalty(off, 900), 0, "the switch turns the penalty off")
	eq(C.warning(off, 245), nil, "... and the warnings")
	eq(C.crossed(off, 249, 250), nil, "... and the notice")
end
eq(C.warning(CFG, 239), nil, "no warning at 239")
eq(C.warning(CFG, 240).level, 250, "warning at 240")
eq(C.warning(CFG, 249).level, 250, "warning at 249")
eq(C.warning(CFG, 250), nil, "no warning at the mark")
eq(C.warning(CFG, 489), nil, "no warning at 489")
eq(C.warning(CFG, 490).level, 500, "warning at 490")
eq(C.warning(CFG, 499).points, 60, "the warning names the penalty")
eq(C.crossed(CFG, 249, 250).points, 30, "crossing 250")
eq(C.crossed(CFG, 499, 500).points, 60, "crossing 500")
eq(C.crossed(CFG, 250, 251), nil, "no mark between")
eq(C.crossed(CFG, 100, 600).points, 60, "a jump over both: the highest")

-- ---------------------------------------------------------------- the resistance
do
	local ctx = {level = 100, area = 0, capDelta = 0, pen = 0}
	eq(C.resistance(DEF, CFG, 40, ctx), 40, "plain sum")
	eq(C.resistance(DEF, CFG, 200, ctx), 75, "capped at 75")
	ctx.capDelta = 15
	eq(C.resistance(DEF, CFG, 200, ctx), 90, "a raise of the cap")
	ctx.capDelta = -25
	eq(C.resistance(DEF, CFG, 200, ctx), 50, "an area lowers the cap")
	ctx.capDelta = 0
	ctx.level = 250
	eq(C.resistance(DEF, CFG, 40, ctx), 10, "the penalty comes off the sum: 40 - 30")
	eq(C.resistance(DEF, CFG, 200, ctx), 75, "overcap survives the penalty: 200 - 30 is still over 75")
	eq(C.resistance(DEF, CFG, 100, ctx), 70, "100 - 30 is 70, under the cap")
	ctx.level = 500
	eq(C.resistance(DEF, CFG, 40, ctx), -20, "40 - 60: negative, the damage rises")
	eq(C.resistance(DEF, CFG, 0, ctx), -60, "no resistance at level 500")
	ctx.area = 20
	eq(C.resistance(DEF, CFG, 100, ctx), 20, "an area penalty comes off the sum too")
	ctx.area = 0
	ctx.pen = 10
	eq(C.resistance(DEF, CFG, 200, ctx), 65, "penetration comes off after the cap: 75 - 10")
	ctx.pen = 400
	eq(C.resistance(DEF, CFG, 200, ctx), -100, "the floor is -100")
end

-- ---------------------------------------------------------------- armour by hit size, the physical total
near(C.armourShare(DEF, 100, 1000), 100 / 170, 1e-12, "armour 100 against a 1000 hit")
eq(C.armourShare(DEF, 0, 1000), 0, "no armour")
eq(C.armourShare(DEF, 100, 0), 0, "no hit")
near(C.physicalTotal(DEF, 0.5, 30), 0.8, 1e-12, "armour share and reduction add")
eq(C.physicalTotal(DEF, 0.7, 50), 0.9, "the total is capped at 90")
eq(C.physicalTotal(DEF, 0, -30), -0.3, "a weakness raises the damage")
eq(C.physicalTotal(DEF, 0, -500), -1, "never below -100")

-- ---------------------------------------------------------------- a context for the hit function
local function sums(phys, fire, cold, lightning, chaos)
	local s = C.newSums(CFG)
	s.phys = phys or 0
	s.group.fire, s.group.cold, s.group.lightning, s.group.chaos = fire or 0, cold or 0, lightning or 0, chaos or 0
	return s
end
local rolls
local function rollAll(v) -- every roll of 1..100 gives v
	rolls = v
end
local function ctxOf(o)
	o = o or {}
	return {def = DEF, cfg = CFG, k = K, groupOf = GROUP_OF, sums = o.sums or sums(), A = o.A or 0, dodge = o.dodge or 0,
		block = o.block or 0, suppress = o.suppress or 0, level = o.level or 100, area = o.area or 0, capDelta = o.capDelta or 0,
		pen = o.pen or 0, physPen = o.physPen or 0, engineKeep = o.engineKeep, rand = function(n) return rolls or 100 end}
end
local function defend(ctx, value, ctype, origin, secondary, stype)
	local p, s, info = C.defend(ctx, {primary = -value, ptype = ctype, secondary = secondary and -secondary or 0, stype = stype,
		origin = origin})
	return -p, -s, info
end

-- ---------------------------------------------------------------- the table: a small, a median and a 5x median hit
-- the median class hit of the level (monster_defence_config.lua hitCurve); low / median / high armour characters of the
-- survival model (server/tools/survival_model.py: the armour of the 21 classes at the hunting level)
dofile("data/scripts/chaos/monster_defence_core.lua")
local MCFG = dofile("data/scripts/chaos/monster_defence_config.lua")
local ARMOUR = {[100] = {low = 56, median = 60, high = 72}, [500] = {low = 72, median = 76, high = 92},
	[1000] = {low = 85, median = 90, high = 109}}
local table_rows = {}
for _, level in ipairs({100, 500, 1000}) do
	local med = ChaosMonsterDefenceCore.hitAtLevel(MCFG, level)
	for _, kind in ipairs({"low", "median", "high"}) do
		local A = ARMOUR[level][kind]
		for _, hit in ipairs({{"small", 0.2 * med}, {"median", med}, {"5x median", 5 * med}}) do
			local H = math.floor(hit[2] + 0.5)
			local got = defend(ctxOf({A = A, level = level}), H, K.physical, ORIGIN_MELEE)
			local share = A / (A + 0.07 * H)
			near(got, H * (1 - share), 1, "armour table " .. level .. " " .. kind .. " " .. hit[1])
			table_rows[#table_rows + 1] = string.format("%5d %-6s A %3d  %-9s %6d -> %6d  armour %5.1f%%", level, kind, A, hit[1], H, got,
				100 * share)
		end
	end
end
if PRINT_TABLE then
	for _, r in ipairs(table_rows) do
		print(r)
	end
end

-- ---------------------------------------------------------------- what each layer ignores
do
	rollAll(1) -- every roll succeeds
	local c = ctxOf({dodge = 50, block = 50, suppress = 50})
	-- attack hits: dodge first
	local _, _, info = defend(c, 100, K.physical, ORIGIN_MELEE)
	eq(info.dodged, true, "melee: dodged"); eq(info.kind, "attack", "melee is an attack")
	_, _, info = defend(c, 100, K.fire, ORIGIN_RANGED)
	eq(info.dodged, true, "ranged fire: dodged (any type)")
	_, _, info = defend(c, 100, K.physical, ORIGIN_WAND)
	eq(info.dodged, true, "a wand hit is an attack")
	-- no dodge, block next
	c = ctxOf({block = 50})
	local v
	v, _, info = defend(c, 100, K.ice, ORIGIN_MELEE)
	eq(info.blocked, true, "block: any damage type of an attack"); eq(v, 0, "blocked: nothing lands")
	-- a spell is neither dodged nor blocked, but suppressed
	c = ctxOf({dodge = 100, block = 100, suppress = 50})
	v, _, info = defend(c, 100, K.fire, ORIGIN_SPELL)
	eq(info.dodged, nil, "spell: no dodge"); eq(info.blocked, nil, "spell: no block"); eq(info.suppressed, true, "spell: suppressed")
	eq(v, 50, "suppressed: 50% less")
	-- suppression of a physical spell, then armour on what is left
	c = ctxOf({suppress = 100, A = 100})
	v = defend(c, 1000, K.physical, ORIGIN_SPELL)
	near(v, 500 * (1 - 100 / (100 + 0.07 * 500)), 1, "a suppressed physical spell: armour sees the halved hit")
	-- ticks and fields: no avoidance, no suppression, no armour
	c = ctxOf({dodge = 100, block = 100, suppress = 100, A = 1000})
	v, _, info = defend(c, 100, K.fire, ORIGIN_CONDITION)
	eq(info.kind, "tick", "condition is a tick"); eq(v, 100, "a tick: nothing avoided, no resistance: 100")
	v = defend(c, 100, K.physical, ORIGIN_CONDITION)
	eq(v, 100, "a physical tick: no armour")
	-- a physical tick meets the physical reduction only
	c = ctxOf({sums = sums(40), A = 1000})
	v = defend(c, 100, K.physical, ORIGIN_CONDITION)
	eq(v, 60, "a physical tick: the reduction of 40")
	c = ctxOf({sums = sums(95), A = 1000})
	v = defend(c, 100, K.physical, ORIGIN_CONDITION)
	eq(v, 10, "a physical tick: the reduction is capped at 90")
	-- the others meet their resistance
	c = ctxOf({sums = sums(0, 0, 50, 0, 0)})
	v = defend(c, 100, K.ice, ORIGIN_CONDITION)
	eq(v, 50, "an ice tick meets the cold resistance")
	v = defend(c, 100, K.drown, ORIGIN_CONDITION)
	eq(v, 50, "a drown tick meets the cold resistance too")
	-- a scripted hit (no origin): no avoidance, no armour, resistance and the reduction yes
	c = ctxOf({dodge = 100, block = 100, A = 1000, sums = sums(20, 30)})
	v, _, info = defend(c, 100, K.fire, ORIGIN_NONE)
	eq(info.kind, "other", "a scripted hit"); eq(v, 70, "a scripted fire hit: the fire resistance, no dodge")
	v = defend(c, 100, K.physical, ORIGIN_NONE)
	eq(v, 80, "a scripted physical hit: the reduction only, no armour")
	-- healing and untyped damage are left alone
	local p = C.defend(c, {primary = 50, ptype = K.healing, origin = ORIGIN_SPELL})
	eq(p, 50, "healing is not touched")
	p = C.defend(c, {primary = -50, ptype = K.undefined, origin = ORIGIN_NONE})
	eq(p, -50, "untyped damage is not touched")
	-- the secondary part follows its own type
	c = ctxOf({sums = sums(0, 50, 0, 0), A = 0})
	local pd, sd = defend(c, 100, K.physical, ORIGIN_MELEE, 100, K.fire)
	eq(pd, 100, "primary physical: no armour, no reduction"); eq(sd, 50, "secondary fire: the resistance")
	rolls = nil
end

-- ---------------------------------------------------------------- caps of the avoidance
do
	local rolled = {}
	local c = ctxOf({dodge = 200, block = 200})
	c.rand = function(n) rolled[#rolled + 1] = n; return 76 end
	local _, _, info = defend(c, 100, K.physical, ORIGIN_MELEE)
	eq(info.dodged, nil, "dodge is capped at 75: a roll of 76 fails")
	eq(info.blocked, nil, "block is capped at 75 (blockCap): a roll of 76 fails")
	c.rand = function() return 75 end
	_, _, info = defend(c, 100, K.physical, ORIGIN_MELEE)
	eq(info.dodged, true, "a roll of 75 dodges at the cap")
	c = ctxOf({suppress = 250})
	c.rand = function() return 100 end
	_, _, info = defend(c, 100, K.fire, ORIGIN_SPELL)
	eq(info.suppressed, true, "suppression goes to 100")
end

-- ---------------------------------------------------------------- negative resistance, the caps in a hit
do
	local c = ctxOf({sums = sums(0, 10, 0, 0, 0), level = 500}) -- fire 10 - 60 = -50
	eq(defend(c, 100, K.fire, ORIGIN_SPELL), 150, "a negative resistance raises the hit: fire -50")
	c = ctxOf({sums = sums(0, 0, 0, 0, 200)})
	eq(defend(c, 100, K.earth, ORIGIN_SPELL), 25, "chaos capped at 75")
	eq(defend(c, 100, K.lifedrain, ORIGIN_SPELL), 25, "life drain is chaos")
	c = ctxOf({sums = sums(0, 0, 0, 0, 200), capDelta = 10})
	eq(defend(c, 100, K.earth, ORIGIN_SPELL), 15, "a raise of the cap by 10")
	c = ctxOf({sums = sums(0, 0, 0, 0, 200), capDelta = -25})
	eq(defend(c, 100, K.earth, ORIGIN_SPELL), 50, "the rift modifier lowers the cap by 25")
	c = ctxOf({sums = sums(100), A = 100000})
	near(defend(c, 1000, K.physical, ORIGIN_MELEE), 100, 1, "physical: armour and reduction together are capped at 90")
	c = ctxOf({sums = sums(0, 0, 0, 0, 0), level = 1000})
	eq(defend(c, 100, K.energy, ORIGIN_SPELL), 160, "level 1000 and no resistance: -60")
	-- a hit that arrives never rounds to nothing
	c = ctxOf({sums = sums(0, 75)})
	eq(defend(c, 2, K.fire, ORIGIN_SPELL), 1, "a hit of 2 at 75: 1 (never nothing)")
	-- the physical weakness of a worn piece
	c = ctxOf({sums = sums(-30)})
	eq(defend(c, 100, K.physical, ORIGIN_MELEE), 130, "a physical weakness of -30")
end

-- ---------------------------------------------------------------- the four groups and "all elements"
do
	local s = C.newSums(CFG)
	C.addType(s, GROUP_OF, K, K.ice, 10); C.addType(s, GROUP_OF, K, K.water, 5); C.addType(s, GROUP_OF, K, K.drown, 3)
	eq(s.group.cold, 18, "ice, water and drown add up in cold, at full value")
	C.addType(s, GROUP_OF, K, K.holy, 4); C.addType(s, GROUP_OF, K, K.energy, 6); C.addType(s, GROUP_OF, K, K.arcane, 2)
	eq(s.group.lightning, 12, "energy, holy and arcane add up in lightning")
	C.addType(s, GROUP_OF, K, K.earth, 7); C.addType(s, GROUP_OF, K, K.death, 8); C.addType(s, GROUP_OF, K, K.manadrain, 1)
	eq(s.group.chaos, 16, "earth, death and mana drain add up in chaos")
	C.addType(s, GROUP_OF, K, K.physical, 25)
	eq(s.phys, 25, "physical goes to the physical reduction")
	C.addAll(s, CFG, 10)
	eq(s.group.fire, 10, "all elements: fire"); eq(s.group.cold, 28, "all elements: cold"); eq(s.group.lightning, 22, "all elements: lightning")
	eq(s.group.chaos, 16, "all elements: not chaos")
end

-- ---------------------------------------------------------------- the engine's absorb comes out again
do
	-- two worn pieces with 20 and 10 percent fire absorb: the engine kept 0.8 x 0.9 = 0.72
	near(C.engineKeep({20, 10}, 0, 75), 0.72, 1e-12, "engine keep: two pieces")
	-- the storages at 50: equipment may take at most 25 / 50 of the hit, so it keeps at least 0.5 of it
	near(C.engineKeep({60, 60}, 50, 75), 0.5, 1e-12, "engine keep: patch 0049 raises it back (storage 50)")
	eq(C.engineKeep({60}, 75, 75), 1, "engine keep: storages at the ceiling, the equipment takes nothing")
	eq(C.engineKeep({-20}, 0, 75), 1.2, "engine keep: a weakness adds")
	eq(C.engineKeep({}, 30, 75), 1, "engine keep: nothing worn")
	eq(C.unscale(-72, 0.72), -100, "unscale: back to the raw hit")
	eq(C.unscale(-1, 0.5), -2, "unscale of a 1")
	-- a fire hit of 1000 raw, the engine took 28% (two pieces): the layer works on 1000 again and counts the same 28 (20 and 10
	-- add to 30 at full value) as a source of fire
	local c = ctxOf({sums = sums(0, 30), engineKeep = function(t) if t == K.fire then return 0.72 end end})
	eq(defend(c, 720, K.fire, ORIGIN_SPELL), 700, "720 arrives, the engine kept 0.72: 1000 raw, fire 30: 700")
	local _, _, info = defend(c, 720, K.fire, ORIGIN_SPELL)
	eq(info.undone, true, "the undo is reported")
	-- the same worn absorb on a physical hit
	c = ctxOf({sums = sums(30), engineKeep = function(t) if t == K.physical then return 0.7 end end})
	eq(defend(c, 700, K.physical, ORIGIN_MELEE), 700, "physical: 1000 raw, reduction 30: 700 as the engine had it")
end

-- ---------------------------------------------------------------- PvP: penetration of a player attacker
do
	local c = ctxOf({sums = sums(0, 50), pen = 20})
	eq(defend(c, 100, K.fire, ORIGIN_SPELL), 70, "elemental penetration: 50 - 20")
	c = ctxOf({A = 100, physPen = 10})
	local plain = defend(ctxOf({A = 100}), 1000, K.physical, ORIGIN_MELEE)
	local pen = defend(c, 1000, K.physical, ORIGIN_MELEE)
	near(plain, 1000 * (1 - 100 / 170), 1, "physical, no penetration")
	near(pen, 1000 * (1 - (100 / 170 - 0.10)), 1, "physical penetration: points off the armour share")
	c = ctxOf({A = 100, physPen = 90})
	eq(defend(c, 1000, K.physical, ORIGIN_MELEE), 1000, "physical penetration: the armour share goes down to 0 and no lower")
end

-- ---------------------------------------------------------------- the engine file: sources, event, mana shield
do
	local foe = newMonster()
	local p = newPlayer({level = 100})
	-- storages: gear rarity and tree, fire 20 + 15, ice 10, water 5, physical 40; holy 8
	storage[p.id .. ":977544"], storage[p.id .. ":977562"] = 20, 15
	storage[p.id .. ":977549"] = 10
	storage[p.id .. ":977570"] = 5
	storage[p.id .. ":977545"] = 25; storage[p.id .. ":977563"] = 15
	storage[p.id .. ":977550"] = 8
	-- a worn piece with 12 fire absorb and 5 death absorb (the engine's ability table: index = log2(type) + 1)
	p.slots[1] = {getId = function() return 5000 end}
	abilityOf[5000] = {absorbPercent = {[4] = 12, [12] = 5, [1] = 0}} -- fire 8 -> index 4, death 2048 -> index 12
	bonusOf[p.id] = {fireres = 6, coldres = 7, lightningres = 8, chaosres = 9, allres = 10, dodge = 5, block = 4, spellsuppress = 30,
		armour = 50}
	ChaosItemSets = {resistances = function(pl, pvp) return pvp and {fire = 1} or {fire = 4, energy = 3} end}
	ChaosCharms = {resistOf = function(pl, t) return t == K.ice and 2 or 0 end}
	ChaosGems = {resistOf = function(pl, t) return t == K.arcane and 6 or 0 end}
	PD.invalidate(p)
	local st = PD.state(p, false)
	-- fire: 20 + 15 storages, 12 worn, 6 mod, 10 all, 4 set = 67; cold: 10 + 5 + 7 + 10 + 2 = 34; lightning: 8 + 8 + 10 + 3 + 6 = 35;
	-- chaos: 5 worn death + 9 = 14 (no all elements)
	eq(st.sums.group.fire, 59.5, "sources of fire: gear storage 20, the tree's 15 counted half (7.5), worn, modifier, all elements, sets")
	eq(st.sums.group.cold, 31.5, "sources of cold: ice, water, charm, modifier, all elements")
	eq(st.sums.group.lightning, 35, "sources of lightning: holy, set energy, gem arcane, modifier, all elements")
	eq(st.sums.group.chaos, 14, "sources of chaos: a worn death, the modifier, NOT all elements")
	eq(st.sums.phys, 40, "physical reduction: both storages")
	eq(st.dodge, 5, "dodge from the totals"); eq(st.block, 4, "block"); eq(st.suppress, 30, "suppression")
	eq(st.A, 50, "armour: the modifier (no armour on the pieces)")
	local pvp = PD.state(p, true)
	eq(pvp.sums.group.fire, 56.5, "item sets give their PvP share against a player (fire 1 instead of 4)")
	eq(pvp.sums.group.lightning, 32, "... lightning 0 instead of 3")
	-- the resistance with the penalty
	local r = PD.resistances(p)
	eq(r.fire, 59.5, "resistances at level 100: 59.5, no penalty")
	p.level = 500
	PD.invalidate(p)
	r = PD.resistances(p)
	eq(r.fire, -0.5, "at level 500: 59.5 - 60"); eq(r.chaos, -46, "chaos 14 - 60")
	p.level = 100
	PD.invalidate(p)

	-- the event on a hit: a fire spell from a monster, 1000 raw; the engine took 12 percent of it (the worn piece)
	math.random = function(n) return 100 end -- no dodge, no block, no suppression
	local pd, pt, sd, st2 = ev.onHealthChange(p, foe, -880, K.fire, 0, K.none, ORIGIN_SPELL)
	-- the engine kept 0.88 (12 absorb, storage 35 so the ceiling floor is 0.25 / 0.65 = 0.385: not reached): raw 1000; fire 67: 330
	eq(pd, -405, "the event: raw 1000 at fire 59.5")
	eq(pt, K.fire, "the type is kept")
	-- the layer is off: nothing changes
	CFG.enabled = false
	pd = ev.onHealthChange(p, foe, -880, K.fire, 0, K.none, ORIGIN_SPELL)
	eq(pd, -880, "switched off: the hit passes")
	CFG.enabled = true
	-- healing and no-damage hits pass
	pd = ev.onHealthChange(p, foe, 500, K.healing, 0, K.none, ORIGIN_SPELL)
	eq(pd, 500, "healing passes")
	-- the player hits itself: not touched
	pd = ev.onHealthChange(p, p, -100, K.fire, 0, K.none, ORIGIN_SPELL)
	eq(pd, -100, "a hit on yourself passes")
	-- an attack hit: dodge 5, a roll of 5 dodges
	math.random = function(n) return 5 end
	pd = ev.onHealthChange(p, foe, -100, K.physical, 0, K.none, ORIGIN_MELEE)
	eq(pd, 0, "dodged")
	ok(#p.pos.effects > 0 and p.pos.effects[1] == CONST_ME_BLOCKHIT, "the block effect is sent")
	-- a roll of 6: no dodge; block 4: no
	math.random = function(n) return 6 end
	pd = ev.onHealthChange(p, foe, -1000, K.physical, 0, K.none, ORIGIN_MELEE)
	-- armour 50 against 1000: 50 / (50 + 70) = 41.7%, plus the reduction 40 = 81.7%
	near(pd, -183, 1, "a melee hit: armour 41.7% and reduction 40%")
	-- a tick of fire: no avoidance, the resistance
	math.random = function(n) return 1 end
	pd = ev.onHealthChange(p, nil, -88, K.fire, 0, K.none, ORIGIN_CONDITION)
	eq(pd, -41, "a fire tick with no attacker (the engine's item absorb comes out and the resistance goes in)")

	-- a player attacker: its penetration counts, item sets give the PvP share
	local foePlayer = newPlayer({level = 300})
	bonusOf[foePlayer.id] = {elepen = 20, physpen = 0}
	math.random = function(n) return 100 end
	PD.invalidate(p)
	pd = ev.onHealthChange(p, foePlayer, -880, K.fire, 0, K.none, ORIGIN_SPELL)
	-- pvp: fire 64; minus 20 penetration = 44 -> 1000 x 0.56
	eq(pd, -635, "PvP: sets give their PvP share, the attacker's penetration comes off")
	-- a summon counts as its master
	local summon = newMonster(foePlayer)
	pd = ev.onHealthChange(p, summon, -880, K.fire, 0, K.none, ORIGIN_SPELL)
	eq(pd, -635, "a player's summon counts as a player")
	ChaosItemSets, ChaosCharms, ChaosGems = nil, nil, nil
end

-- ---------------------------------------------------------------- the mana shield provider
do
	local prov = ChaosManaShield.providers.zdefence
	ok(prov ~= nil and type(prov.hit) == "function", "the mana shield provider exists under a key that sorts after the others")
	for key in pairs(ChaosManaShield.providers) do
		ok(key <= "zdefence", "provider key " .. key .. " sorts before or equal")
	end
	local p = newPlayer({level = 100})
	bonusOf[p.id] = {fireres = 50}
	PD.invalidate(p)
	local foe = newMonster()
	math.random = function(n) return 100 end
	eq(prov.hit(p, foe, 1000, {primaryType = K.fire, origin = ORIGIN_SPELL}), 500, "the mana pays the mitigated amount")
	-- the health event of the same hit leaves the rest alone when the mana shield marked it
	ChaosManaShield.mark = ChaosManaShield.mark or function() end
	ChaosManaShield.mark(p:getId(), foe:getId(), ChaosManaShield.now(), {"zdefence"})
	local pd = ev.onHealthChange(p, foe, -1000, K.fire, 0, K.none, ORIGIN_SPELL)
	eq(pd, -1000, "a hit the mana shield scaled is left as it is")
	pd = ev.onHealthChange(p, foe, -1000, K.fire, 0, K.none, ORIGIN_SPELL)
	eq(pd, -500, "the next hit is handled again")
end

-- ---------------------------------------------------------------- the tree counts half, at most 30
do
	eq(CFG.tree.share, 0.5, "tree share"); eq(CFG.tree.cap, 30, "tree cap")
	eq(C.treeCounted(CFG, 20), 10, "below the cap: half")
	eq(C.treeCounted(CFG, 60), 30, "at the cap")
	eq(C.treeCounted(CFG, 116), 30, "over the cap")
	eq(C.treeCounted({tree = {share = 1}}, 116), 116, "share 1 and no cap: as before")
	eq(C.treeCounted({}, 116), 116, "no tree table: as before")
	-- every group, from the second storages; the physical reduction in full; gear in full; PvP the same
	local p = newPlayer({level = 100})
	local second = {fire = 977562, ice = 977567, energy = 977564, earth = 977565, death = 977569, physical = 977563}
	storage[p.id .. ":" .. second.fire] = 40      -- fire group: 20
	storage[p.id .. ":" .. second.ice] = 100      -- cold group: capped at 30
	storage[p.id .. ":" .. second.energy] = 10    -- lightning: 5
	storage[p.id .. ":" .. second.earth] = 30     -- chaos: 15 + 40 death / 2 = 20 -> 35 -> cap 30
	storage[p.id .. ":" .. second.death] = 40
	storage[p.id .. ":" .. second.physical] = 55  -- physical: in full
	storage[p.id .. ":977544"] = 10               -- gear fire: in full
	bonusOf[p.id] = {}
	PD.invalidate(p)
	for _, pvp in ipairs({false, true}) do
		local g = PD.state(p, pvp).sums
		eq(g.group.fire, 30, "fire: 10 gear + half of 40")
		eq(g.group.cold, 30, "cold: half of 100 is 50, held at 30")
		eq(g.group.lightning, 5, "lightning: half of 10")
		eq(g.group.chaos, 30, "chaos: half of 70 is 35, held at 30")
		eq(g.phys, 55, "the tree's physical reduction is not touched")
	end
	-- the engine's patch 0049 still sees the full storages
	eq(PD.state(p, false).storage[K.fire], 50, "the engine reads both storages in full")
	CFG.tree = nil
	PD.invalidate(p)
	eq(PD.state(p, false).sums.group.cold, 100, "without a tree rule the full tree counts")
	CFG.tree = {share = 0.5, cap = 30}
	PD.invalidate(p)
end

-- the tree's own text says it (numbers from the config), in both languages; physical resist is not touched
do
	dofile("data/scripts/chaos/passivetree_stats_config.lua")
	local st = ChaosPassiveStatsConfig.stats
	local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
	for _, k in ipairs({"absorbFire", "absorbIce", "absorbEarth", "absorbLife", "absorbAllElements"}) do
		ok(st[k][2]:find("counts as half a point, and the tree gives at most 30.", 1, true), k .. " text names the tree rule")
		ok(pt[st[k][2]] and pt[st[k][2]]:find("meio ponto", 1, true), k .. " pt-BR")
	end
	ok(not st.absorbPhysical[2]:find("half a point", 1, true), "physical resist text unchanged")
end

-- ---------------------------------------------------------------- class evasion is one of the dodge sources
do
	local p = newPlayer({level = 100})
	bonusOf[p.id] = {dodge = 5}
	local foe = newMonster()
	local opened = {}
	ChaosPlayerDefenceSources.dodge.testclass = function(player) return 20 end
	ChaosPlayerDefenceSources.onDodge.testclass = function(player, attacker) opened[#opened + 1] = attacker:getId() end
	PD.invalidate(p)
	eq(PD.state(p, false).dodge, 25, "the gear's 5 and the class evasion's 20 add up")
	math.random = function(n) return 25 end
	eq(ev.onHealthChange(p, foe, -100, K.physical, 0, K.none, ORIGIN_MELEE), 0, "ONE roll against the sum: 25 dodges")
	eq(#opened, 1, "the class hook runs when the player dodged")
	eq(opened[1], foe:getId(), "with the attacker")
	math.random = function(n) return 26 end
	eq(ev.onHealthChange(p, foe, -100, K.physical, 0, K.none, ORIGIN_MELEE), -100, "26 does not")
	eq(#opened, 1, "no hook without a dodge")
	-- a spell is never dodged, class evasion included
	math.random = function(n) return 1 end
	eq(ev.onHealthChange(p, foe, -100, K.fire, 0, K.none, ORIGIN_SPELL), -100, "a spell is not dodged")
	ChaosPlayerDefenceSources.dodge.testclass = nil
	ChaosPlayerDefenceSources.onDodge.testclass = nil
	PD.invalidate(p)
end

-- ---------------------------------------------------------------- the rift modifier Frayed Wards lowers the cap
do
	local p = newPlayer({level = 100})
	bonusOf[p.id] = {fireres = 100}
	local foe = newMonster()
	math.random = function(n) return 100 end
	PD.invalidate(p)
	eq(PD.resistances(p).fire, 75, "no run: the cap of 75")
	ChaosRift = {runOf = {[p.id] = {state = "running", fx = {maxResistLower = 15}}}}
	PD.invalidate(p)
	eq(PD.resistances(p).fire, 60, "a run with Frayed Wards 15: the cap is 60")
	local pd = ev.onHealthChange(p, foe, -1000, K.fire, 0, K.none, ORIGIN_SPELL)
	eq(pd, -400, "the hit meets 60")
	ChaosRift = {runOf = {[p.id] = {state = "ended", fx = {maxResistLower = 15}}}}
	PD.invalidate(p)
	eq(PD.resistances(p).fire, 75, "a run that is over: no change")
	ChaosRift = {runOf = {[p.id] = {state = "running", fx = {maxResistLower = 25}}}}
	bonusOf[p.id] = {fireres = 40}
	PD.invalidate(p)
	eq(PD.resistances(p).fire, 40, "a sum under the lowered cap is not touched")
	ChaosRift = nil
	PD.invalidate(p)
end

-- ---------------------------------------------------------------- the notices at login and level up
do
	local p = newPlayer({level = 100})
	eq(PD.notify(p, nil), nil, "level 100: nothing to say")
	p.level = 245
	eq(PD.notify(p, nil), "warning", "login at 245: the warning")
	eq(#p.messages, 1, "one message")
	ok(p.messages[1]:find("250", 1, true) and p.messages[1]:find("30", 1, true), "it names the level and the penalty: " .. p.messages[1])
	eq(PD.notify(p, nil), nil, "once per level: the second login at 245 says nothing")
	p.level = 246
	eq(PD.notify(p, 245), "warning", "level up to 246: told again (a new level)")
	p.level = 250
	eq(PD.notify(p, 249), "crossed", "level 250: the mark is crossed")
	ok(p.messages[#p.messages]:find("30", 1, true), "the notice names the penalty")
	eq(PD.notify(p, nil), nil, "at the mark itself nothing more at login")
	p.level = 490
	eq(PD.notify(p, nil), "warning", "login at 490: the warning of the 60 mark")
	ok(p.messages[#p.messages]:find("500", 1, true) and p.messages[#p.messages]:find("60", 1, true), "it names 500 and 60")
	p.level = 500
	eq(PD.notify(p, 499), "crossed", "level 500: crossed")
	-- pt-BR
	local q = newPlayer({level = 245})
	Chaos.setLang(q, "pt-BR")
	PD.notify(q, nil)
	ok(q.messages[1] and q.messages[1]:find("resistências", 1, true), "the warning in pt-BR: " .. tostring(q.messages[1]))
	q.level = 250
	PD.notify(q, 249)
	ok(q.messages[#q.messages]:find("penalidade", 1, true), "the crossing in pt-BR: " .. tostring(q.messages[#q.messages]))
	-- the advance event
	local r = newPlayer({level = 249})
	r.level = 250
	events.ChaosPlayerDefenceAdvance.onAdvance(r, SKILL_LEVEL, 249, 250)
	ok(#r.messages == 1, "the advance event tells the player")
end

-- ---------------------------------------------------------------- the storage key
do
	local key = CFG.storage.lastWarned
	ok(key >= 7100000 and key <= 7127999, "the key is in the reserved blocks")
	local clash
	for name, v in pairs(Chaos.storage) do
		if v == key then clash = name end
	end
	eq(clash, nil, "no storage of chaos_constants.lua uses it")
	eq(key, 7103080, "the block 7103080 - 7103089 of the README table")
end

-- ---------------------------------------------------------------- registration
do
	local p = newPlayer()
	events.Chaos0ZPlayerDefenceLogin.onLogin(p)
	local set = {}
	for _, n in ipairs(p.registered) do set[n] = true end
	ok(set.ChaosPlayerDefence and set.ChaosPlayerDefenceAdvance and set.ChaosPlayerDefenceLogout, "login registers the events")
	ok("Chaos0TierLogin" < "Chaos0ZPlayerDefenceLogin" and "Chaos0ZPlayerDefenceLogin" < "Chaos1ManaShieldLogin", "login name order")
	eq(PD.active(), true, "active by default")
end

if PRINT_TABLE then
	return
end
print(string.format("player defence tests: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
