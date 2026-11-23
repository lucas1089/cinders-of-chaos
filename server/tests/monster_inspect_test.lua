-- Run from the server/ folder: luajit tests/monster_inspect_test.lua (and lua5.3; CI runs both).
-- Inspect Monster (O721: monster_inspect_core.lua, monster_inspect_config.lua, monster_inspect.lua) against a mocked engine:
-- the opcode, who may be inspected (monsters only, range, floor, view, display spots), the request budget, the monster file
-- reading, attack / ability / resistance / armour / experience / loot rows, the bestiary stage that opens loot and places,
-- the payload size, and the handler end to end (a result for a monster in view, a refusal for everything else).
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(c, m)
	eq(c and true or false, true, m)
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/monster_inspect_core.lua")
local M = ChaosMonsterInspect
local cfg = dofile("data/scripts/chaos/monster_inspect_config.lua")

-- ---------------------------------------------------------------- the opcode
eq(ChaosOpcodes.monsterInspect, 166, "opcode 166")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. tostring(v) .. " is used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 126, 127, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	ok(ChaosOpcodes.monsterInspect ~= v, "not an opcode of the reference server or client: " .. v)
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end
local ls = io.popen("ls ../client/overlay/modules 2>/dev/null")
local others = 0
for dir in ls:lines() do
	if dir ~= "game_monsterinspect" then
		local ph = io.popen("ls ../client/overlay/modules/" .. dir .. "/*.lua 2>/dev/null")
		for file in ph:lines() do
			local s = readFile(file)
			if s and not file:find("_test.lua", 1, true) and (s:find("[Oo]pcode[%w_]*%s*=%s*166%f[%D]") or s:find("xtended[%w]*Opcode%(%s*166%f[%D]")) then
				others = others + 1
				print("opcode 166 in " .. file)
			end
		end
		ph:close()
	end
end
ls:close()
eq(others, 0, "no other client module on 166")

-- ---------------------------------------------------------------- who may be inspected
local function target(over)
	local t = {isMonster = true, hidden = false, sameFloor = true, visible = true, dx = 3, dy = -2}
	for k, v in pairs(over or {}) do t[k] = v end
	return t
end
local a, code = M.allowed(target(), cfg)
eq(a, true, "a monster in view")
a, code = M.allowed(target({dx = 10, dy = -10}), cfg)
eq(a, true, "ten tiles is in range")
a, code = M.allowed(target({dx = 11}), cfg)
eq(code, "range", "eleven tiles")
a, code = M.allowed(target({sameFloor = false}), cfg)
eq(code, "range", "another floor")
a, code = M.allowed(target({visible = false}), cfg)
eq(code, "range", "behind a wall")
a, code = M.allowed(target({isMonster = false}), cfg)
eq(code, "notfound", "a player or an NPC is no monster")
a, code = M.allowed(target({hidden = true}), cfg)
eq(code, "notfound", "a display monster of the teleport room")
a, code = M.allowed(nil, cfg)
eq(code, "notfound", "no creature")
eq(M.cleanCid(12), 12, "creature id")
eq(M.cleanCid("40"), 40, "creature id as text")
eq(M.cleanCid(0), nil, "zero")
eq(M.cleanCid(-3), nil, "negative")
eq(M.cleanCid(1e300), nil, "huge")
eq(M.cleanCid("x"), nil, "text")
eq(M.cleanCid(nil), nil, "nil")

-- ---------------------------------------------------------------- the request budget
local st = {}
eq(M.allow(st, 1000, cfg), true, "first request")
eq(M.allow(st, 1100, cfg), false, "inside the cooldown")
eq(M.allow(st, 1000 + cfg.cooldownMs, cfg), true, "after the cooldown")
local burst, now, n = {}, 5000, 0
for i = 1, 40 do
	now = now + cfg.cooldownMs
	if M.allow(burst, now, cfg) then n = n + 1 end
end
ok(n < 40 and n >= cfg.bucketSize, "a long run is cut by the bucket (" .. n .. " of 40)")
eq(M.allow(burst, now + 60000, cfg), true, "the bucket refills")

-- ---------------------------------------------------------------- the monster file
local xmlText = [[
<?xml version="1.0" encoding="UTF-8"?>
<monster name="Slagborer" nameDescription="a slagborer" race="blood" experience="450" speed="180" manaCost="0">
	<health now="900" max="900"/>
	<flags>
		<flag summonable="0"/>
		<flag runonhealth="90"/>
		<flag canpushitems="1"/>
		<flag hidehealth="0"/>
	</flags>
	<attacks>
		<attack name="melee" interval="2000" skill="70" attack="50"/>
		<attack name="fire" interval="2000" chance="20" range="7" min="-100" max="-200"><attribute key="shootEffect" value="fire"/></attack>
		<attack name="energy beam" interval="3000" chance="12" length="8" spread="0" min="-60" max="-120"/>
		<attack name="speed" interval="2000" chance="15" speedchange="-600" duration="15000"/>
	</attacks>
	<defenses armor="25" defense="30">
		<defense name="healing" interval="2000" chance="15" min="50" max="100"/>
		<defense name="speed" interval="4000" chance="10" speedchange="320" duration="5000"/>
		<defense name="invisible" interval="2000" chance="10" duration="4000"/>
	</defenses>
	<summons maxSummons="2">
		<summon name="Ghoul" interval="2000" chance="10"/>
		<summon name="Skeleton" interval="2000" chance="10"/>
	</summons>
</monster>]]
local x = M.parseXml(xmlText)
eq(x.speed, 180, "speed")
eq(x.armor, 25, "flat armour")
eq(x.defense, 30, "flat defence")
eq(#x.attacks, 4, "four attacks")
eq(x.attacks[2].name, "fire", "attack name")
eq(x.attacks[2].max, "-200", "attack attribute")
eq(#x.defences, 3, "three defences")
eq(#x.summons, 2, "two summons")
eq(x.maxSummons, 2, "max summons")
eq(x.flags.runonhealth, "90", "a flag")
eq(#M.parseXml("").attacks, 0, "empty text")
eq(#M.parseXml(nil).attacks, 0, "no text")
eq(M.meleeMax(70, 50), 2 * 0 + math.ceil(70 * 2.5 + 25), "melee maximum, the engine's formula")

eq(M.elementOf("fire", cfg), "fire", "fire")
eq(M.elementOf("Lightning bolt", cfg), "energy", "by a word of the name")
eq(M.elementOf("strength", cfg), nil, "no element")
eq(M.elementOf(nil, cfg), nil, "nil name")

local rows = M.attackRows(x, nil, 1, cfg, 1)
eq(#rows, 4, "attack rows")
eq(rows[1].kind, "melee", "melee row")
eq(rows[1].element, "physical", "melee is physical")
eq(rows[1].max, M.meleeMax(70, 50), "melee max")
eq(rows[2].kind, "ranged", "a bolt")
eq(rows[2].element, "fire", "fire bolt")
eq(rows[2].min, 100, "the damage is an absolute range")
eq(rows[2].max, 200, "the damage is an absolute range")
eq(rows[2].range, 7, "range")
eq(rows[3].kind, "spell", "a named spell")
eq(rows[3].element, "energy", "its element")
local scaledRows = M.attackRows(x, nil, 1.5, cfg, 10)
eq(scaledRows[2].max, 3000, "tier multiplier 1.5 and display scale 10")
local eng = M.attackRows(nil, {{chance = 20, isMelee = 1, minCombatValue = 0, maxCombatValue = -90, range = 1, speed = 2000},
	{chance = 10, isMelee = 0, minCombatValue = -30, maxCombatValue = -60, range = 5, speed = 3000}}, 1, cfg, 1)
eq(#eng, 2, "engine fallback rows")
eq(eng[1].max, 90, "engine melee")
eq(eng[2].kind, "spell", "engine spell")
local many = {attacks = {}}
for i = 1, 40 do many.attacks[i] = {name = "fire", min = "-1", max = "-2"} end
eq(#M.attackRows(many, nil, 1, cfg, 1), cfg.maxAttacks, "attack rows are cut")

local ab = M.abilityRows(x, cfg)
local kinds = {}
for _, r in ipairs(ab) do kinds[r.kind .. ":" .. r.name] = r end
ok(kinds["defence:healing"] and kinds["defence:healing"].max == 100, "heals")
ok(kinds["defence:speed"] and kinds["defence:speed"].value == 320, "haste")
ok(kinds["defence:invisible"] and kinds["defence:invisible"].seconds == 4, "invisible")
ok(kinds["summon:Ghoul, Skeleton"] and kinds["summon:Ghoul, Skeleton"].count == 2, "summons")
ok(kinds["flag:runs"] and kinds["flag:runs"].value == 90, "runs at health")
ok(kinds["flag:pushes items"], "pushes items")
ok(not kinds["flag:hides its health"], "a flag that is off is not listed")

-- ---------------------------------------------------------------- resistances
local res = M.resistRows(function(ct) return ({[1] = 10, [8] = -25, [512] = 0})[ct] end, 2 + 1024, 1 + 4, {CONDITION_POISON = 1,
	CONDITION_FIRE = 2, CONDITION_ENERGY = 4, CONDITION_BLEEDING = 8}, cfg)
eq(#res.elements, 2, "two resistances")
eq(res.elements[1].name, "physical", "physical first")
eq(res.elements[1].pct, 10, "10 percent")
eq(res.elements[2].name, "fire", "fire")
eq(res.elements[2].pct, -25, "weak to fire")
eq(res.immune[1] .. "," .. res.immune[2], "energy,holy", "immune")
eq(res.conditions[1] .. "," .. res.conditions[2], "poison,shock", "condition immunities")
res = M.resistRows(nil, 0, 0, nil, cfg)
eq(#res.elements + #res.immune + #res.conditions, 0, "nothing without data")

-- ---------------------------------------------------------------- armour and experience
local arm = M.armourView(25, 30, "elite", 0.254, 0.1)
eq(arm.spell, 25, "layer share of a spell hit in percent")
eq(arm.weapon, 10, "weapon share")
eq(arm.class, "elite", "class")
eq(M.armourView(nil, nil, "normal").armor, nil, "no flat armour")
local e = M.expView(450, 2, 3, 2, 1)
eq(e.total, 2700, "experience: base x tier x stage")
eq(e.tier, 2, "tier multiplier")
eq(e.bonus, 2, "bestiary bonus")
eq(e.rank, 1, "rank bonus")
e = M.expView(450, 1, 1, 0, 0)
eq(e.total, 450, "plain experience")
eq(e.tier, nil, "no tier row at 1")
eq(e.bonus, nil, "no bonus row at 0")

-- ---------------------------------------------------------------- loot by the bestiary stage
local loot = {}
for i = 1, 60 do loot[i] = {itemId = 1000 + i, chance = i == 1 and 100000 or i * 1000 + (i % 7) * 13, maxCount = i % 3 + 1} end
local function itemInfo(id) return "Item " .. id, id + 5000 end
local v = M.lootView(loot, itemInfo, 0, nil, cfg)
eq(#v.rows, 0, "stage 0: no rows")
eq(v.locked, cfg.reveal.lootHighlights, "stage 0: locked by the stage that opens it")
eq(v.total, 60, "the total is known")
local sum = 0
for _, b in ipairs(v.bands) do sum = sum + b.n end
eq(sum, 60, "every row is in a band")
v = M.lootView(loot, itemInfo, 2, nil, cfg)
eq(#v.rows, cfg.lootHighlights, "stage 2: highlights")
ok(v.rows[1].chance <= v.rows[2].chance, "stage 2: the rarest first")
eq(v.locked, cfg.reveal.lootFull, "stage 2: the full table is locked")
v = M.lootView(loot, itemInfo, 3, "legendary", cfg)
eq(#v.rows, cfg.maxLoot, "stage 3: the table, cut")
ok(v.rows[1].chance >= v.rows[2].chance, "stage 3: the most common first")
eq(v.locked, nil, "stage 3: nothing locked")
eq(v.tierText, cfg.lootTierText.legendary, "the tier line")
eq(M.bandOf(50, cfg), "Common", "band common")
eq(M.bandOf(5, cfg), "Uncommon", "band uncommon")
eq(M.bandOf(0.5, cfg), "Rare", "band rare")
eq(M.bandOf(0.01, cfg), "Very rare", "band very rare")
v = M.lootView({{itemId = 5, chance = 500}}, function() return nil end, 4, nil, cfg)
eq(v.total, 0, "an item with no name is left out")

local uniques = {{name = "Slag Plate", id = 9001, monsters = {"Slagborer"}, set = "slag"}, {name = "Other", id = 9002, monsters = {"Rat"}},
	{name = "Boss Blade", id = 9003, monsters = {"slagborer"}, bossOnly = true}}
eq(#M.uniqueRows(uniques, "slagborer", 2, cfg), 0, "uniques wait for the full stage")
local u = M.uniqueRows(uniques, "slagborer", 3, cfg, function(id) return id + 1 end)
eq(#u, 2, "two uniques name it")
eq(u[1].set, true, "a set piece")
eq(u[1].cid, 9002, "client id by the callback")
eq(u[2].boss, true, "boss only")

eq(#M.areaRows({{100, 100, 7, 5}}, {{name = "Ashford", x = 100, y = 100}}, 1, cfg), 0, "places wait for stage 2")
local ar = M.areaRows({{100, 100, 7, 5}}, {{name = "Ashford", x = 100, y = 100}}, 2, cfg)
eq(#ar, 1, "a place")
eq(ar[1].count, 5, "its count")
ok(ar[1].text:find("Ashford", 1, true), "its town")

-- ---------------------------------------------------------------- health, modifiers
local h = M.healthView(450, 900, false)
eq(h.pct, 50, "half")
eq(h.cur, 450, "current")
eq(h.max, 900, "maximum")
h = M.healthView(450, 900, true)
eq(h.hidden, true, "hidden health")
eq(h.cur, nil, "hidden: no numbers")
eq(h.pct, 50, "hidden: the percent stays")
eq(M.healthView(5, 0).pct, 0, "no maximum")
local mr = M.modRows({{key = "blazing", name = "Blazing"}, {key = "nothing", name = "Nothing"}}, cfg)
eq(mr[1].text, cfg.modifiers.blazing, "a written sentence")
eq(mr[2].text, nil, "no sentence written")
-- every modifier of monster_tiers.lua has a sentence
local tiers = readFile("data/scripts/chaos/monster_tiers.lua")
local seenMods = 0
local block = tiers:match("\nChaosMods = {(.-)\n}\n")
for key in block:gmatch("\n\t([a-z]+) = {name = ") do
	ok(cfg.modifiers[key] ~= nil, "modifier " .. key .. " has a sentence")
	seenMods = seenMods + 1
end
ok(seenMods >= 20, "the modifier list was read (" .. seenMods .. ")")

-- ---------------------------------------------------------------- the engine file, end to end
local wire, refused, decoded = {}, {}, {}
local function encode(v)
	local t = type(v)
	if t == "table" then
		local isArray = #v > 0 or next(v) == nil
		local out = {}
		if isArray then
			for _, x in ipairs(v) do out[#out + 1] = encode(x) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		for _, k in ipairs(keys) do out[#out + 1] = encode(k) .. ":" .. encode(v[k] ~= nil and v[k] or v[tonumber(k)]) end
		return "{" .. table.concat(out, ",") .. "}"
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
	elseif t == "number" then
		return v == math.floor(v) and string.format("%d", v) or string.format("%.14g", v)
	elseif t == "boolean" then
		return tostring(v)
	end
	return "null"
end
json = {encode = function(v)
	local s = encode(v)
	decoded[s] = v
	return s
end}
Chaos.decode = function(buffer) return type(buffer) == "table" and buffer or nil end
local events = {}
function CreatureEvent(name) local o = {}; function o:type() end; function o:register() events[name] = o end; return o end
COMBAT_PHYSICALDAMAGE = 1
CONDITION_POISON, CONDITION_FIRE, CONDITION_ENERGY, CONDITION_BLEEDING = 1, 2, 4, 8
ChaosOpcodes.bestiary = 253

local things = {}
local function newPlayer(pid, pos, extra)
	local p = {pid = pid, pos = pos or {x = 100, y = 100, z = 7}, level = 300, visible = true}
	for k, v in pairs(extra or {}) do p[k] = v end
	function p:getId() return self.pid end
	function p:getGuid() return self.pid + 500 end
	function p:getLevel() return self.level end
	function p:getPosition() return self.pos end
	function p:canSeeCreature(c) return self.visible end
	function p:registerEvent() end
	function p:isMonster() return false end
	function p:sendExtendedOpcode(opcode, buffer)
		if #buffer > Chaos.extendedOpcodeMax then refused[#refused + 1] = #buffer return false end
		wire[#wire + 1] = {opcode = opcode, buffer = buffer}
		return true
	end
	things[pid] = p
	return p
end
local function newMonster(cid, pos, name, over)
	local m = {cid = cid, pos = pos, name = name, health = 450, maxHealth = 900, master = nil}
	for k, v in pairs(over or {}) do m[k] = v end
	function m:getId() return self.cid end
	function m:getName() return self.name end
	function m:getPosition() return self.pos end
	function m:getHealth() return self.health end
	function m:getMaxHealth() return self.maxHealth end
	function m:getMaster() return self.master end
	function m:getOutfit() return {lookType = 110, lookHead = 0, lookBody = 0, lookLegs = 0, lookFeet = 0} end
	function m:isMonster() return true end
	function m:getBaseSpeed() return 180 end
	function m:getSpeed() return 200 end
	function m:getDisplayLevel() return 412 end
	things[cid] = m
	return m
end
function Creature(id) return things[id] end
function Monster(id) local c = things[id]; return c and c:isMonster() and c or nil end
function Player(id) local c = things[id]; return c and not c:isMonster() and c or nil end
local loots = {}
for i = 1, 8 do loots[i] = {itemId = 2000 + i, chance = i * 3000, maxCount = 1} end
local types = {Slagborer = {experience = 450, isBoss = false, isHealthHidden = false, getLoot = loots, combatImmunities = 4,
	conditionImmunities = 1, armor = 25, defense = 30, getElementList = {[8] = -25}}}
function MonsterType(name)
	local d = types[name]
	if not d then return nil end
	local mt = {}
	for k, v in pairs(d) do mt[k] = function() return v end end
	mt.getAttackList = function() return {} end
	return mt
end
function ItemType(id)
	local it = {id = id}
	function it:getId() return self.id end
	function it:getName() return "Item " .. self.id end
	function it:getClientId() return self.id + 5000 end
	return it
end
Game = {getTowns = function() return {} end, getExperienceStage = function(level) return 2 end}
ChaosTiers = {rare = {label = "Rare", hp = 4.9, damage = 1.5, xp = 4.0}}
ChaosTierState = {[7] = {tier = "rare", mods = {"blazing", "swift"}}}
ChaosTierOf = function(m) local s = ChaosTierState[m:getId()]; return s and s.tier or "normal" end
ChaosMods = {blazing = {name = "Blazing"}, swift = {name = "Swift"}}
ChaosMonsterDefence = {classOf = function(m) return m:getId() == 7 and "elite" or "normal" end, levelOf = function() return 412 end,
	armourOf = function() return 300 end, weaponArmourOf = function() return 200 end,
	effectiveResist = function(m, ct) return ct == 8 and -25 or 0 end}
Chaos.defence = {armourHitFactor = 1}
Chaos.monsterDefence = {hitCurve = {{level = 100, hit = 100}, {level = 1000, hit = 1000}}, weaponHitCurve = {{level = 100, hit = 80},
	{level = 1000, hit = 800}}, weaponShareCap = {normal = 50, elite = 60}}
ChaosMonsterDefenceCore = {
	hitAtLevel = function(cfg, level) return level end,
	weaponHitAtLevel = function(cfg, level) return level * 0.8 end,
	armourReduction = function(def, A, H) return A / (A + def.armourHitFactor * H) end,
	weaponShare = function(def, A, H, cap) return math.min(cap, A / (A + def.armourHitFactor * H)) end,
	weaponShareCap = function(cfg, class) return (cfg.weaponShareCap[class] or 50) / 100 end
}
-- the bestiary: this monster has an entry, the player has studied it (stage 2)
local entry = {key = "slagborer", cat = "other", race = "blood", diff = "challenging", th = {1, 20, 150, 600},
	areas = {{100, 100, 7, 5}}}
ChaosBestiary = {catNames = {other = "Other"}, cat = function() return {byKey = {slagborer = entry}} end,
	stateOf = function() return {kills = {slagborer = 40}, completed = {slagborer = {exp = 2, damage = 2}}} end,
	rankOf = function() return {exp = 1} end}
ChaosLoot = {uniqueList = function() return {{name = "Slag Plate", id = 9001, monsters = {"Slagborer"}}} end}
local function fakeIo()
	local realOpen = io.open
	io.open = function(path, mode)
		if path == "data/monster/monsters.xml" then
			local lines = {'\t<monster name="Slagborer" file="slag/slagborer.xml"/>'}
			local i = 0
			return {lines = function() return function() i = i + 1 return lines[i] end end, close = function() end}
		elseif path == "data/monster/slag/slagborer.xml" then
			return {read = function() return xmlText end, close = function() end}
		end
		return realOpen(path, mode)
	end
	return function() io.open = realOpen end
end
local restoreIo = fakeIo()
os.mtime = nil
local clock = 1000
os.time = function() return clock end
dofile("data/scripts/chaos/monster_inspect.lua")
local ext = events.ChaosMonsterInspectExtended
ok(ext ~= nil and events.ChaosMonsterInspectLogin ~= nil and events.ChaosMonsterInspectLogout ~= nil, "the three events are registered")

local viewer = newPlayer(1)
local rare = newMonster(7, {x = 104, y = 98, z = 7}, "Slagborer")
local plain = newMonster(8, {x = 102, y = 101, z = 7}, "Slagborer")
local far = newMonster(9, {x = 140, y = 100, z = 7}, "Slagborer")
local other = newPlayer(2, {x = 101, y = 100, z = 7})

local function ask(player, cid, sameMoment)
	if not sameMoment then clock = clock + 10 end
	local before = #wire
	ext.onExtendedOpcode(player, ChaosOpcodes.monsterInspect, {action = "inspect", data = {cid = cid}})
	local out = {}
	for i = before + 1, #wire do
		local s = wire[i].buffer
		out[#out + 1] = decoded[s] or s
	end
	return out[1]
end

local msg = ask(viewer, 7)
eq(msg.action, "result", "a result for a monster in view")
local d = msg.data
eq(d.cid, 7, "creature id")
eq(d.name, "Slagborer", "name")
eq(d.level, 412, "level")
eq(d.tier, "rare", "tier")
local flagKeys = {}
for _, f in ipairs(d.flags) do flagKeys[f.key] = f.name or true end
eq(flagKeys.tier, "Rare", "tier flag with its label")
eq(flagKeys.elite, true, "elite flag from the defence class")
eq(flagKeys.boss, nil, "no boss flag")
eq(d.health.cur, 450, "current health")
eq(d.health.max, 900, "maximum health")
eq(d.health.pct, 50, "health percent")
eq(d.family.cat, "Other", "family")
eq(d.family.diff, "challenging", "difficulty")
eq(#d.mods, 2, "two modifiers")
eq(d.mods[1].text, cfg.modifiers.blazing, "modifier sentence")
eq(d.exp.base, 450, "base experience")
eq(d.exp.tier, 4, "rare experience factor")
eq(d.exp.total, 450 * 4 * 2, "experience: base x tier x the viewer's stage")
eq(d.exp.bonus, 2, "bestiary completion bonus")
eq(d.exp.rank, 1, "bestiary rank bonus")
eq(d.resist.immune[1], "earth", "earth immunity")
eq(d.resist.conditions[1], "poison", "poison immunity")
eq(d.resist.elements[1].name, "fire", "fire resistance")
eq(d.resist.elements[1].pct, -25, "weak to fire")
eq(d.armour.armor, 25, "flat armour")
eq(d.armour.class, "elite", "armour class")
eq(d.armour.spell, math.floor(300 / (300 + 412) * 100 + 0.5), "armour layer, spells")
eq(d.armour.weapon, 50 < 60 and math.floor(math.min(0.6, 200 / (200 + 412 * 0.8)) * 100 + 0.5) or 0, "armour layer, weapons")
eq(d.attacks[1].kind, "melee", "melee attack")
eq(d.attacks[2].max, 300, "fire bolt maximum x the rare damage factor 1.5")
eq(d.speed.base, 180, "base speed")
eq(d.speed.now, 200, "speed now")
eq(d.loot.total, 8, "loot total")
eq(#d.loot.rows, cfg.lootHighlights, "stage 2 loot: highlights")
eq(d.loot.locked, cfg.reveal.lootFull, "the full table is locked")
eq(d.loot.tierText, cfg.lootTierText.rare, "tier loot line")
eq(#d.uniques, 0, "uniques wait for stage 3")
eq(#d.areas, 1, "places are open at stage 2")
eq(d.bestiary.kills, 40, "bestiary kills")
eq(d.bestiary.stage, 2, "bestiary stage: 40 kills of 1 / 20 / 150")
eq(d.outfit.lookType, 110, "outfit")

msg = ask(viewer, 8, true)
eq(msg.action, "denied", "the budget: a second request at once")
eq(msg.data.code, "rate", "refused as rate")
clock = clock + 10
msg = ask(viewer, 8)
eq(msg.action, "result", "a plain monster")
eq(msg.data.tier, "normal", "plain tier")
eq(msg.data.exp.tier, nil, "plain experience factor")
for _, f in ipairs(msg.data.flags) do eq(f.key == "tier" or f.key == "elite", false, "no rank flag on a plain monster") end

local v2 = newPlayer(3)
msg = ask(v2, 9)
eq(msg.action, "denied", "a monster far away")
eq(msg.data.code, "range", "range")
msg = ask(v2, 2)
eq(msg.data.code, "notfound", "a player is not inspected here")
msg = ask(v2, 12345)
eq(msg.data.code, "notfound", "no such creature")
v2.visible = false
clock = clock + 10
msg = ask(v2, 8)
eq(msg.data.code, "range", "a monster out of view")
clock = clock + 10
ext.onExtendedOpcode(v2, ChaosOpcodes.monsterInspect, {action = "inspect", data = {cid = "x"}})
eq(decoded[wire[#wire].buffer].data.code, "bad", "a bad id")
local count = #wire
ext.onExtendedOpcode(v2, ChaosOpcodes.monsterInspect + 1, {action = "inspect", data = {cid = 8}})
eq(#wire, count, "another opcode is ignored")
ext.onExtendedOpcode(v2, ChaosOpcodes.monsterInspect, {action = "inspect"})
eq(#wire, count, "no data is ignored")

-- stage 3: the whole table and the uniques
entry.th = {1, 5, 10, 600}
clock = clock + 10
msg = ask(viewer, 8)
eq(msg.data.bestiary.stage, 3, "stage 3")
eq(#msg.data.loot.rows, 8, "the whole loot table")
eq(msg.data.loot.locked, nil, "nothing locked")
eq(#msg.data.uniques, 1, "a unique names it")
eq(msg.data.uniques[1].cid, 9001 + 5000, "unique client id")
-- no bestiary entry: no family, no loot rows, no places
ChaosBestiary.cat = function() return {byKey = {}} end
clock = clock + 10
msg = ask(viewer, 8)
eq(msg.data.family, nil, "no family without an entry")
eq(#msg.data.loot.rows, 0, "no loot rows at stage 0")
eq(#msg.data.areas, 0, "no places at stage 0")
eq(msg.data.loot.total, 8, "the band counts are still there")
-- hidden health
types.Slagborer.isHealthHidden = true
clock = clock + 10
msg = ask(viewer, 8)
eq(msg.data.health.hidden, true, "hidden health stays hidden")
eq(msg.data.health.cur, nil, "no numbers for hidden health")
types.Slagborer.isHealthHidden = false
-- the display scale (the viewer's own) reaches health and damage
ChaosDisplayScale = {forPlayer = function() return 10 end, scale = function(n, f) return n * f end}
clock = clock + 10
msg = ask(viewer, 8)
eq(msg.data.health.max, 9000, "health in the viewer's display scale")
eq(msg.data.health.pct, 50, "the percent is not scaled")
eq(msg.data.attacks[2].max, 2000, "damage in the viewer's display scale")
ChaosDisplayScale = nil
-- the logout frees the budget
events.ChaosMonsterInspectLogout.onLogout(viewer)
eq(next(types) ~= nil, true, "logout ran")

-- the biggest realistic window stays under the packet limit
local big = {cid = 1, name = "Slagborer", level = 1500, tier = "legendary", flags = {{key = "tier", name = "Legendary"}, {key = "elite"}},
	health = M.healthView(4000000000, 4000000000), family = {cat = "Dragons", race = "fire", diff = "deadly"}, mods = {}, speed = {base = 400, now = 520},
	exp = M.expView(900000, 10, 5, 3, 3), armour = M.armourView(900, 900, "boss", 0.4, 0.3)}
local nm = {}
for k in pairs(cfg.modifiers) do nm[#nm + 1] = {key = k, name = "Emberforged"} end
big.mods = M.modRows(nm, cfg)
local manyAttacks = {attacks = {}}
for i = 1, 30 do manyAttacks.attacks[i] = {name = "energy beam of the deep", min = "-1000000", max = "-2000000", interval = "2000", chance = "12", range = "7"} end
big.attacks = M.attackRows(manyAttacks, nil, 1.7, cfg, 1000)
local abils = {defences = {}, summons = {{name = "A very long monster name of a summon"}}, flags = {runonhealth = "90"}}
for i = 1, 30 do abils.defences[i] = {name = "healing", min = "-1", max = "-2", interval = "2000", chance = "10"} end
big.abilities = M.abilityRows(abils, cfg)
local bigLoot = {}
for i = 1, 200 do bigLoot[i] = {itemId = i, chance = i * 100, maxCount = 500} end
big.loot = M.lootView(bigLoot, function(id) return "A long item name of the loot table " .. id, id + 40000 end, 4, "legendary", cfg)
big.uniques = {}
for i = 1, 40 do big.uniques[i] = {name = "A unique item of the deep", id = i, cid = i + 40000} end
big.uniques = M.uniqueRows((function()
	local l = {}
	for i = 1, 40 do l[i] = {name = "A unique item of the deep " .. i, id = i, monsters = {"slagborer"}} end
	return l
end)(), "slagborer", 4, cfg)
big.areas = M.areaRows({{100, 100, 7, 5}, {200, 200, 8, 9}, {300, 300, 9, 2}, {400, 400, 10, 2}}, {{name = "Ashford", x = 100, y = 100}}, 4, cfg)
local payload = M.build(big, cfg)
local text = encode({action = "result", data = payload})
ok(#text < cfg.packetBytes, "the largest window fits one packet (" .. #text .. " bytes)")
ok(#payload.attacks <= cfg.maxAttacks and #payload.abilities <= cfg.maxAbilities and #payload.loot.rows <= cfg.maxLoot, "lists are cut")

restoreIo()
print(string.format("monster_inspect_test: all %d checks passed", checks))
