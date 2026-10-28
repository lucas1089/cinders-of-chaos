-- Run from the server/ folder: luajit tests/exercise_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- The exercise (training) weapons (owner request 2026-10-23; server/README.md "Training weapons"):
--   * exercise_core.lua: item -> kind, class -> line, vocation -> allowed item -> skill (every class has a weapon for the
--     skills it uses; the Monk line has its own fist weapon; the melee kind trains the best melee skill, so the
--     stage rate follows it), the refusal texts, the stage rate, the chain guard, the config check
--   * exercise_training.lua (the action) against a mocked engine: a charge only for a step that trains, the tries land on
--     the right skill, a refused class loses nothing, range / floor / protection zone, a second click starts no second
--     chain, the training flag is cleared when a chain ends and at login, an old axe / club weapon becomes the melee one
--   * the pt-BR texts, the sale lists (store, Ancestral Store) and the retired chests
dofile("data/scripts/chaos/exercise_core.lua")
local E = ChaosExercise
local cfg = E.cfg

local fails, checks = 0, 0
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

-- ------------------------------------------------------------------ the config is consistent
local problems = E.validate()
eq(#problems, 0, "config problems: " .. table.concat(problems, "; "))

-- ------------------------------------------------------------------ the classes (docs/CLASSES.md)
local NAME = {[1] = "Mystic", [3] = "Ranger", [4] = "Warrior", [5] = "Elementalist", [7] = "Deadeye", [8] = "Juggernaut",
	[10] = "Illusionist", [11] = "Thief", [12] = "Ninja", [13] = "Samurai", [14] = "Berserker", [15] = "Beastmaster",
	[17] = "Monk", [18] = "Shadowfist", [19] = "Iron Sage", [20] = "Necromancer", [21] = "Lich", [22] = "Bone Lord",
	[23] = "Templar", [24] = "Inquisitor", [25] = "Sentinel"}
local LINE = {[1] = "mystic", [5] = "mystic", [10] = "mystic", [3] = "ranger", [7] = "ranger", [15] = "ranger",
	[4] = "warrior", [8] = "warrior", [14] = "warrior", [11] = "thief", [12] = "thief", [13] = "thief",
	[17] = "monk", [18] = "monk", [19] = "monk", [20] = "necromancer", [21] = "necromancer", [22] = "necromancer",
	[23] = "templar", [24] = "templar", [25] = "templar"}
local ids = {}
for id in pairs(NAME) do
	ids[#ids + 1] = id
end
table.sort(ids)
eq(#ids, 21, "21 class vocations")
for _, id in ipairs(ids) do
	eq(E.lineOf(id), LINE[id], NAME[id] .. ": line")
end
eq(E.lineOf(0), nil, "no vocation: no line")
eq(E.lineOf(2), nil, "a retired stock vocation: no line")

-- every item id has a kind; the nine melee ids (sword, axe, club x 3 tiers) are one kind
local melee = {27732, 27734, 27738, 27740, 27744, 27746}
for _, id in ipairs({27733, 27739, 27745}) do
	eq(E.kindOf(id), "fist", "item " .. id .. " is the fist weapon")
end
for _, id in ipairs(melee) do
	eq(E.kindOf(id), "melee", "item " .. id .. " is the melee weapon")
end
eq(E.kindOf(27735), "ranged", "bow"); eq(E.kindOf(27741), "ranged", "durable bow"); eq(E.kindOf(27747), "ranged", "lasting bow")
eq(E.kindOf(27736), "rod", "rod"); eq(E.kindOf(27737), "wand", "wand")
eq(E.kindOf(27758), "shield", "shield"); eq(E.kindOf(27760), "shield", "lasting shield")
eq(E.kindOf(2160), nil, "not an exercise weapon")
local n = 0
for _ in pairs(cfg.items) do n = n + 1 end
eq(n, 21, "21 exercise weapons")

-- who may use what
local WHO = {
	melee = {warrior = true, thief = true, templar = true},
	fist = {monk = true},
	ranged = {ranger = true, thief = true},
	rod = {mystic = true, necromancer = true, templar = true},
	wand = {mystic = true, necromancer = true, templar = true},
	shield = {warrior = true, ranger = true, mystic = true, thief = true, monk = true, necromancer = true, templar = true}
}
for kind, lines in pairs(WHO) do
	for _, id in ipairs(ids) do
		eq(E.allowed(kind, id), lines[LINE[id]] == true, NAME[id] .. ": " .. kind)
	end
end
ok(not E.allowed("melee", 0), "no vocation uses nothing")
ok(not E.allowed("nonsense", 4), "an unknown kind is refused")

-- the skill each class trains with each of its weapons
local LEVELS = {sword = 10, club = 20, axe = 80}
local PERCENTS = {sword = 0, club = 0, axe = 0}
for _, id in ipairs(ids) do
	if E.allowed("melee", id) then
		eq(E.skillFor("melee", id, LEVELS, PERCENTS), "axe", NAME[id] .. ": melee weapon trains the best melee skill")
	else
		eq(E.skillFor("melee", id, LEVELS, PERCENTS), nil, NAME[id] .. ": no melee skill")
	end
	if E.allowed("fist", id) then
		eq(E.skillFor("fist", id, LEVELS, PERCENTS), "fist", NAME[id] .. ": the fist weapon trains fist fighting")
	else
		eq(E.skillFor("fist", id), nil, NAME[id] .. ": no fist weapon")
	end
	if E.allowed("ranged", id) then eq(E.skillFor("ranged", id), "distance", NAME[id] .. ": distance") end
	if E.allowed("rod", id) then eq(E.skillFor("rod", id), "magic", NAME[id] .. ": rod trains the magic level") end
	if E.allowed("wand", id) then eq(E.skillFor("wand", id), "magic", NAME[id] .. ": wand trains the magic level") end
	eq(E.skillFor("shield", id), "shield", NAME[id] .. ": shielding")
end
-- the melee weapon trains the BEST melee skill (the rate follows it): a tie goes to the first, the percent breaks it
eq(E.skillFor("melee", 4, {sword = 50, club = 50, axe = 50}, {sword = 0, club = 0, axe = 0}), "sword", "melee: a tie")
eq(E.skillFor("melee", 4, {sword = 50, club = 50, axe = 50}, {sword = 0, club = 30, axe = 10}), "club", "melee: percent decides")
eq(E.skillFor("melee", 4, nil, nil), "sword", "melee: no levels")
eq(E.skillFor("fist", 17, {sword = 500, club = 500, axe = 500}), "fist", "the Monk trains fist whatever its sword is")
eq(E.skillFor("melee", 17, {sword = 500}), nil, "the Monk has no use for the sword weapon")

-- every skill a class uses has at least one weapon it may use
local USES = {warrior = {"melee", "shield"}, ranger = {"ranged", "shield"}, mystic = {"wand", "rod", "shield"},
	thief = {"melee", "ranged", "shield"}, monk = {"fist", "shield"}, necromancer = {"wand", "rod", "shield"},
	templar = {"melee", "shield", "wand"}}
for _, id in ipairs(ids) do
	for _, kind in ipairs(USES[LINE[id]]) do
		ok(E.allowed(kind, id), NAME[id] .. " has a " .. kind .. " weapon")
	end
end
-- the Monk's old weapon (the club) trained a skill it does not use; its own fist weapon trains fist, and it has shielding
ok(E.allowed("fist", 17) and E.allowed("shield", 17), "the Monk has the fist and the shield weapon")
ok(not E.allowed("melee", 17) and not E.allowed("fist", 4), "the sword weapon is not the Monk's, the fist weapon is only its")
ok(not E.allowed("rod", 17) and not E.allowed("wand", 17), "the Monk's spells do not use the magic level: no rod, no wand")

-- refusals
local key, args = E.refusal("ranged", 17)
eq(key, "Your class cannot train with this item. It is for: %s.", "refusal key")
eq(args[1], "Ranger, Thief", "refusal names the lines")
eq((E.refusal("melee", 0)), "Your vocation cannot use this item.", "no vocation: the plain refusal")
eq(table.concat(E.lineNames("melee"), ","), "Templar,Thief,Warrior", "melee lines")
eq(table.concat(E.lineNames("fist"), ","), "Monk", "fist lines")

-- old axe / club weapons and the retired chests
eq(E.convertTo(27733, 4), 27732, "an old axe weapon (the fist one now) in a Warrior's hands -> sword")
eq(E.convertTo(27734, 4), 27732, "club -> sword")
eq(E.convertTo(27739, 11), 27738, "durable fist weapon in a Thief's hands -> durable sword")
eq(E.convertTo(27746, 23), 27744, "lasting club -> lasting sword")
eq(E.convertTo(27732, 4), nil, "the sword stays"); eq(E.convertTo(27735, 4), nil, "the bow stays")
eq(E.convertTo(27733, 17), nil, "the fist weapon stays in a Monk's hands")
eq(E.convertTo(27732, 17), 27733, "a Monk's sword weapon -> fist"); eq(E.convertTo(27738, 18), 27739, "durable sword -> durable fist")
eq(E.convertTo(27746, 19), 27745, "a Monk's lasting club -> lasting fist")
eq(E.convertTo(27735, 17), nil, "a Monk's bow is not converted (refused)")
eq(E.convertTo(27734), 27732, "no class: the club still becomes the sword")
eq(E.convertTo(27733), nil, "no class: the fist weapon stays")
for _, id in ipairs({27763, 27770, 27777}) do
	ok(E.isRetiredChest(id), "chest " .. id .. " is retired")
end
for _, id in ipairs({27762, 27769, 27776, 27761, 27768, 27775, 27764, 27767, 27781}) do
	ok(not E.isRetiredChest(id), "chest " .. id .. " is still sold")
end

-- dummies
eq(E.dummyKind(27751), "bonus", "the hall's dummy: bonus"); eq(E.dummyKind(5787), "plain", "a free dummy")
eq(E.dummyKind(2160), nil, "not a dummy")

-- the stage rate and a step
eq(E.rate(cfg.skillStages, 10, 1), 5, "stage 1"); eq(E.rate(cfg.skillStages, 60, 1), 3, "stage 2")
eq(E.rate(cfg.skillStages, 150, 1), 2, "stage 3"); eq(E.rate(cfg.skillStages, 201, 4), 4, "past the stages: the server rate")
eq(E.step("melee", 10, 1, false), 35, "skill step at 10: 7 x 5")
eq(E.step("melee", 10, 1, true), 39, "skill step on a house dummy: +10%, rounded up")
eq(E.step("wand", 60, 1, false), 1500, "magic step at 60: 500 x 3")
eq(E.step("shield", 300, 6, false), 42, "past the stages: 7 x the server rate")

-- reach
ok(E.reach("melee", 1, 1, 0), "melee: the next tile"); ok(not E.reach("melee", 2, 0, 0), "melee: two tiles is too far")
ok(E.reach("wand", 6, -7, 0), "wand: 7 tiles"); ok(not E.reach("wand", 8, 0, 0), "wand: 8 tiles is too far")
local good, why = E.reach("wand", 0, 0, 1)
ok(not good and why == "floor", "another floor never works")
ok(not E.reach("shield", 3, 0, 0), "shield: next tile only")

-- the chain guard
E.chains = {}
local g1 = E.beginChain(7, 1000)
ok(g1 ~= nil, "a first chain starts")
eq(E.beginChain(7, 1500), nil, "a second click while it lives: no second chain")
E.touchChain(7, g1, 2400)
eq(E.beginChain(7, 4000), nil, "still alive 1.6 s after its last step")
local g2 = E.beginChain(7, 4500)
ok(g2 ~= nil and g2 ~= g1, "a stalled chain is replaced")
ok(not E.isCurrent(7, g1), "the old chain is no longer current"); ok(E.isCurrent(7, g2), "the new one is")
E.endChain(7, g1)
ok(E.isCurrent(7, g2), "the old chain ending does not end the new one")
E.endChain(7, g2)
ok(E.beginChain(7, 4501) ~= nil, "after an end a chain starts at once")

-- ------------------------------------------------------------------ the action on a mocked engine
SKILL_FIST, SKILL_CLUB, SKILL_SWORD, SKILL_AXE, SKILL_DISTANCE, SKILL_SHIELD, SKILL_MAGLEVEL = 0, 1, 2, 3, 4, 5, 6
MESSAGE_INFO_DESCR = 22
ITEM_ATTRIBUTE_CHARGES = 4
TILESTATE_PROTECTIONZONE = 1
CONST_ME_HITAREA = 7
CONST_ANI_SIMPLEARROW, CONST_ANI_SMALLICE, CONST_ANI_FIRE = 1, 2, 3
configKeys = {RATE_SKILL = "rs", RATE_MAGIC = "rm"}
configManager = {getNumber = function(_, key) return key == "rs" and 2 or 3 end}
Chaos = {t = function(_, text, ...) return string.format(text, ...) end}
Chaos.storage = {}

local queue, now = {}, 0
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, at = now + delay, args = {...}} end
function os.mtime() return now end
local function runDue()
	local ran = true
	while ran do
		ran = false
		table.sort(queue, function(a, b) return a.at < b.at end)
		if queue[1] and queue[1].at <= now then
			local ev = table.remove(queue, 1)
			ev.fn((unpack or table.unpack)(ev.args))
			ran = true
		end
	end
end
local function advance(ms)
	local target = now + ms
	while true do
		table.sort(queue, function(a, b) return a.at < b.at end)
		if queue[1] and queue[1].at <= target then
			now = queue[1].at
			runDue()
		else
			break
		end
	end
	now = target
end

local effects = {}
local posMT = {}
posMT.__index = posMT
function Position(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	return setmetatable({x = x, y = y, z = z}, posMT)
end
function posMT:sendMagicEffect(e) effects[#effects + 1] = "magic" .. e end
function posMT:sendDistanceEffect(to, e) effects[#effects + 1] = "ani" .. e end
local tiles = {}
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
function Tile(p)
	return tiles[key(p)]
end
local function addTile(x, y, z, pz, dummyId)
	tiles[x .. "," .. y .. "," .. z] = {
		hasFlag = function(_, f) return pz and f == TILESTATE_PROTECTIONZONE end,
		getItemById = function(_, id) return dummyId == id and {} or nil end
	}
end

local itemTypes = {}
function ItemType(id) return {getCharges = function() return itemTypes[id] or 0 end} end

local players, nextCid = {}, 1000
local storage = {}
local function newItem(id, charges)
	local it = {id = id, attrs = {}, removed = false}
	if charges then it.attrs[ITEM_ATTRIBUTE_CHARGES] = charges end
	function it:getId() return self.id end
	function it:isItem() return true end
	function it:hasAttribute(a) return self.attrs[a] ~= nil end
	function it:getAttribute(a) return self.attrs[a] or 0 end
	function it:setAttribute(a, v) self.attrs[a] = v end
	function it:sendUpdate() it.updates = (it.updates or 0) + 1 end
	function it:remove() self.removed = true end
	function it:transform(newId, count) self.id = newId; self.attrs[ITEM_ATTRIBUTE_CHARGES] = count end
	return it
end
local function newPlayer(vocation, opts)
	opts = opts or {}
	nextCid = nextCid + 1
	local p = {cid = nextCid, voc = vocation, pos = Position(100, 100, 7), items = {}, tries = {}, mana = 0, msgs = {},
		store = {}, levels = opts.levels or {}, magic = opts.magic or 10, idle = 0}
	function p:getId() return self.cid end
	function p:getVocation() return {getId = function() return self.voc end} end
	function p:getPosition() return self.pos end
	function p:getItemById(id)
		for _, it in ipairs(self.items) do
			if it.id == id and not it.removed then return it end
		end
	end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function p:getEffectiveSkillLevel(s) return self.levels[s] or 10 end
	function p:getSkillPercent(s) return 0 end
	function p:getMagicLevel() return self.magic end
	function p:addSkillTries(s, n) self.tries[s] = (self.tries[s] or 0) + n end
	function p:addManaSpent(n) self.mana = self.mana + n end
	function p:resetIdleTime() self.idle = self.idle + 1 end
	function p:setStorageValue(k, v) self.store[k] = v end
	function p:getStorageValue(k) return self.store[k] or -1 end
	function p:registerEvent() end
	players[p.cid] = p
	return p
end
function Player(cid) return players[cid] end

-- the dummy target and the engine objects the action registers
local registered, events = {}, {}
function Action()
	local a = {ids = {}}
	function a:id(...) for _, v in ipairs({...}) do self.ids[#self.ids + 1] = v end end
	function a:allowFarUse(v) self.far = v end
	function a:register() registered[#registered + 1] = self end
	return a
end
function CreatureEvent(name)
	local c = {name = name}
	function c:register() events[name] = self end
	return c
end
dofile("data/scripts/chaos/exercise_training.lua")

eq(#registered, 2, "two actions: near and far")
local nearA, farA = registered[1], registered[2]
local covered = {}
for _, a in ipairs(registered) do for _, id in ipairs(a.ids) do covered[id] = (covered[id] or 0) + 1 end end
local count = 0
for id in pairs(cfg.items) do
	count = count + 1
	eq(covered[id], 1, "item " .. id .. " is registered once")
end
eq(count, 21, "all weapons registered")
ok(farA.far == true and not nearA.far, "ranged, rod and wand weapons work from afar, melee and shield walk")
local farSet = {}
for _, id in ipairs(farA.ids) do farSet[id] = true end
ok(farSet[27735] and farSet[27736] and farSet[27737] and not farSet[27732] and not farSet[27758], "the far list")

local function target(id, x, y, z)
	return {getId = function() return id end, isItem = function() return true end,
		getPosition = function() return Position(x, y, z) end}
end
local function setup(vocation, itemId, charges, opts)
	tiles = {}
	queue, now, effects = {}, 0, {}
	E.chains = {}
	addTile(100, 100, 7, true)
	addTile(101, 100, 7, true, 27751)
	local p = newPlayer(vocation, opts)
	local item = newItem(itemId, charges)
	p.items[1] = item
	return p, item
end
local function use(p, item, tgt)
	local a = E.kindOf(item.id) and (farSet[item.id] and farA or nearA)
	return a.onUse(p, item, nil, tgt, nil, false)
end
local DUMMY = function() return target(27751, 101, 100, 7) end

-- the Monk with the fist weapon: fist tries, a charge a step, the flag set, a step every 750 ms
do
	local p, item = setup(17, 27733, 500, {levels = {[SKILL_FIST] = 30, [SKILL_SWORD] = 150, [SKILL_AXE] = 5}})
	ok(use(p, item, DUMMY()), "Monk: used")
	eq(p.tries[SKILL_FIST], 39, "Monk: first step trains fist at stage 1 (7 x 5, +10%, rounded up)")
	eq(p.tries[SKILL_SWORD], nil, "Monk: nothing for the sword")
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 499, "Monk: one charge")
	eq(item.updates, 1, "Monk: the client gets the item again")
	eq(p.store[37100], 1, "Monk: the training flag is set")
	advance(2250)
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 496, "Monk: a charge per 750 ms")
	eq(p.tries[SKILL_FIST], 39 * 4, "Monk: four steps")
	ok(p.idle >= 4, "Monk: the idle time is reset")
	-- a second click: no second chain
	ok(use(p, item, DUMMY()), "second click used")
	eq(p.msgs[#p.msgs], "You are already training.", "second click: already training")
	advance(7500)
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 486, "one chain only: 10 more steps in 7.5 s, not 20")
	-- the player steps away: the chain ends, the flag is cleared
	p.pos = Position(100, 101, 7)
	addTile(100, 101, 7, true)
	advance(1000)
	eq(p.store[37100], 0, "stepping away clears the flag")
	eq(p.msgs[#p.msgs], "Your training has stopped.", "stepping away stops the training")
	local left = item.attrs[ITEM_ATTRIBUTE_CHARGES]
	advance(3000)
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], left, "no charge after the stop")
end

-- the Warrior with the melee weapon: the best skill (the axe) is trained at its stage rate, not the weak sword's
do
	local p, item = setup(4, 27734, 500, {levels = {[SKILL_SWORD] = 10, [SKILL_CLUB] = 20, [SKILL_AXE] = 80}})
	ok(use(p, item, DUMMY()), "Warrior: used a club weapon")
	eq(p.tries[SKILL_AXE], 24, "Warrior: the axe (best) trains, at stage 2 (7 x 3, +10%)")
	eq(p.tries[SKILL_SWORD], nil, "Warrior: not the weak sword at its fast stage")
	eq(item.id, 27732, "the old club weapon became the sword (melee) one")
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 499, "its charges are kept (and one taken)")
	advance(750)
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 498, "the converted weapon keeps training")
end
do
	local p, item = setup(4, 27746, 14400)
	use(p, item, DUMMY())
	eq(item.id, 27744, "a lasting club becomes the lasting melee weapon")
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 14399, "lasting charges kept")
end

-- the fist weapon and the conversions between it and the sword one (the old exercise axe is the fist weapon now)
do
	local p, item = setup(18, 27739, 1800, {levels = {[SKILL_FIST] = 120}})
	ok(use(p, item, DUMMY()), "Shadowfist: used the durable fist weapon")
	eq(p.tries[SKILL_FIST], 16, "Shadowfist: fist at stage 3 (7 x 2, +10%)")
	eq(item.id, 27739, "the fist weapon stays")
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 1799, "one charge")
end
do
	local p, item = setup(17, 27732, 500)
	ok(use(p, item, DUMMY()), "Monk: used a sword weapon")
	eq(item.id, 27733, "a Monk's sword weapon became the fist one")
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 499, "charges kept, one taken")
	ok(p.tries[SKILL_FIST] ~= nil and p.tries[SKILL_SWORD] == nil, "Monk: it trains fist")
	eq(#queue > 0, true, "Monk: the chain runs")
end
do
	local p, item = setup(19, 27746, 14400)
	use(p, item, DUMMY())
	eq(item.id, 27745, "a Monk's old lasting club became the lasting fist weapon")
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 14399, "lasting charges kept")
end
do
	local p, item = setup(4, 27733, 500, {levels = {[SKILL_SWORD] = 40}})
	ok(use(p, item, DUMMY()), "Warrior: used an old exercise axe")
	eq(item.id, 27732, "a Warrior's old exercise axe (the fist weapon now) became the sword one")
	ok(p.tries[SKILL_SWORD] ~= nil and p.tries[SKILL_FIST] == nil, "Warrior: melee, not fist")
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 499, "its charges are kept")
end
do
	local p, item = setup(3, 27733, 500)
	use(p, item, DUMMY())
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 500, "Ranger: the fist weapon is refused, no charge")
	eq(p.msgs[#p.msgs], "Your class cannot train with this item. It is for: Templar, Thief, Warrior.", "Ranger: told the sword weapon's lines")
end

-- a plain dummy gives no bonus; the magic level and distance
do
	local p, item = setup(1, 27737, 1800)
	addTile(103, 100, 7, true, 5787)
	ok(use(p, item, target(5787, 103, 100, 7)), "Mystic: wand from 3 tiles")
	eq(p.mana, 500 * 5, "Mystic: mana spent for the magic level at stage 1, no bonus dummy")
	ok(effects[#effects] == "ani" .. CONST_ANI_FIRE or effects[#effects - 1] == "ani" .. CONST_ANI_FIRE, "Mystic: the fire effect flies")
end
do
	local p, item = setup(21, 27736, 500)
	use(p, item, target(27751, 101, 100, 7))
	ok(p.mana > 0, "Lich trains with a rod")
end
do
	local p, item = setup(24, 27737, 500)
	use(p, item, DUMMY())
	ok(p.mana > 0, "Inquisitor trains the magic level with a wand")
end
do
	local p, item = setup(19, 27742, 500)
	use(p, item, DUMMY())
	ok(p.mana == 0 and item.attrs[ITEM_ATTRIBUTE_CHARGES] == 500, "Iron Sage: a rod is refused, no charge")
	local q, shield = setup(18, 27759, 500)
	use(q, shield, DUMMY())
	ok(q.tries[SKILL_SHIELD] ~= nil, "Shadowfist trains shielding")
end
do
	local p, item = setup(7, 27741, 500, {levels = {[SKILL_DISTANCE] = 120}})
	use(p, item, DUMMY())
	eq(p.tries[SKILL_DISTANCE], 16, "Deadeye: distance at stage 3 (7 x 2, +10%)")
end
do
	local p, item = setup(11, 27747, 500)
	use(p, item, DUMMY())
	ok(p.tries[SKILL_DISTANCE] ~= nil, "Thief trains distance with a bow")
	local q, sword = setup(12, 27738, 500)
	use(q, sword, DUMMY())
	ok(q.tries[SKILL_SWORD] ~= nil, "Ninja trains the melee skill with the melee weapon")
end
do
	local p, item = setup(20, 27758, 500)
	use(p, item, DUMMY())
	ok(p.tries[SKILL_SHIELD] ~= nil, "Necromancer trains shielding")
end
do
	local p, item = setup(25, 27744, 500, {levels = {[SKILL_SWORD] = 40, [SKILL_AXE] = 60}})
	use(p, item, DUMMY())
	ok(p.tries[SKILL_AXE] ~= nil and p.tries[SKILL_FIST] == nil, "Sentinel: the melee skill, not fist")
end

-- a refused class loses nothing and gets a text
do
	local p, item = setup(3, 27732, 500)
	ok(use(p, item, DUMMY()), "Ranger: used the melee weapon")
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 500, "a refused click takes no charge")
	ok(next(p.tries) == nil and p.mana == 0, "a refused click trains nothing")
	eq(p.msgs[#p.msgs], "Your class cannot train with this item. It is for: Templar, Thief, Warrior.", "the refusal names the classes")
	eq(#queue, 0, "no chain")
	local q, wand = setup(4, 27737, 500)
	use(q, wand, DUMMY())
	eq(wand.attrs[ITEM_ATTRIBUTE_CHARGES], 500, "Warrior: wand refused, no charge")
	local r, none = setup(0, 27732, 500)
	use(r, none, DUMMY())
	eq(r.msgs[#r.msgs], "Your vocation cannot use this item.", "no vocation")
end

-- range, floor, protection zone, a target that is no dummy, no charges, a locked class
do
	local p, item = setup(4, 27732, 500)
	addTile(103, 100, 7, true, 27751)
	use(p, item, target(27751, 103, 100, 7))
	eq(p.msgs[#p.msgs], "Get closer to the dummy.", "melee: two tiles away")
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 500, "no charge for it")

	local w, wand = setup(1, 27737, 500)
	addTile(100, 100, 6, true, 27751)
	use(w, wand, target(27751, 100, 100, 6))
	eq(w.msgs[#w.msgs], "The dummy is on another floor.", "wand: another floor, even though it may fire from afar")
	addTile(120, 100, 7, true, 27751)
	use(w, wand, target(27751, 120, 100, 7))
	eq(w.msgs[#w.msgs], "Get closer to the dummy.", "wand: a dummy 20 tiles away")
	eq(wand.attrs[ITEM_ATTRIBUTE_CHARGES], 500, "no charge for either")

	local z, zitem = setup(4, 27732, 500)
	addTile(100, 100, 7, false)
	use(z, zitem, DUMMY())
	eq(z.msgs[#z.msgs], "You can only train in a protection zone.", "outside a protection zone")
	eq(zitem.attrs[ITEM_ATTRIBUTE_CHARGES], 500, "no charge for it")

	local t, titem = setup(4, 27732, 500)
	use(t, titem, target(2160, 101, 100, 7))
	eq(t.msgs[#t.msgs], "Use it on a training dummy.", "not a dummy")
	use(t, titem, nil)
	eq(t.msgs[#t.msgs], "Use it on a training dummy.", "no target")

	local e, eitem = setup(4, 27732, 0)
	eitem.attrs[ITEM_ATTRIBUTE_CHARGES] = 0
	use(e, eitem, DUMMY())
	ok(eitem.removed, "a weapon with no charges vanishes")

	ChaosClassUnlocks = {isRestricted = function() return true end}
	local l, litem = setup(4, 27732, 500)
	use(l, litem, DUMMY())
	eq(litem.attrs[ITEM_ATTRIBUTE_CHARGES], 500, "a locked class: no charge")
	eq(l.msgs[#l.msgs], "Your class is locked: nothing is trained.", "a locked class: the text")
	ChaosClassUnlocks = nil
end

-- the last charge: the weapon vanishes, the flag is cleared
do
	local p, item = setup(4, 27732, 2)
	use(p, item, DUMMY())
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 1, "one charge left")
	advance(750)
	ok(item.removed, "the last charge used up the weapon")
	eq(p.msgs[#p.msgs], "Your training weapon vanished.", "vanished text")
	eq(p.store[37100], 0, "flag cleared at the end")
	eq(#queue, 0, "no more steps")
end

-- a charge-less new item takes the item type's charges
do
	itemTypes[27732] = 500
	local p, item = setup(4, 27732, nil)
	use(p, item, DUMMY())
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], 499, "an item with no charges attribute starts from the type's")
	itemTypes[27732] = nil
end

-- the dummy is removed / the player logs out: the chain ends, no charge after
do
	local p, item = setup(4, 27732, 500)
	use(p, item, DUMMY())
	tiles["101,100,7"].getItemById = function() return nil end
	advance(750)
	eq(p.store[37100], 0, "dummy gone: flag cleared")
	local c = item.attrs[ITEM_ATTRIBUTE_CHARGES]
	advance(3000)
	eq(item.attrs[ITEM_ATTRIBUTE_CHARGES], c, "dummy gone: no more charges")

	local q, qitem = setup(4, 27732, 500)
	use(q, qitem, DUMMY())
	players[q.cid] = nil
	advance(3000)
	eq(qitem.attrs[ITEM_ATTRIBUTE_CHARGES], 499, "logged out: the chain ends")
	eq(E.chains[q.cid], nil, "logged out: the chain is forgotten")
end

-- login / logout clear the flag
do
	local p = newPlayer(4)
	p.store[37100] = 1
	events.ChaosExerciseLogin.onLogin(p)
	eq(p.store[37100], 0, "login clears a stale flag")
	p.store[37100] = 1
	events.ChaosExerciseLogout.onLogout(p)
	eq(p.store[37100], 0, "logout clears the flag")
end

-- ------------------------------------------------------------------ texts, store, Ancestral Store
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
for _, text in ipairs({"Your vocation cannot use this item.", "Your class cannot train with this item. It is for: %s.",
		"Use it on a training dummy.", "Your class is locked: nothing is trained.", "The dummy is on another floor.",
		"Get closer to the dummy.", "You can only train in a protection zone.", "Your training weapon vanished.",
		"You are already training.", "You started training.", "Your training has stopped."}) do
	ok(pt[text] ~= nil, "pt-BR: " .. text)
	if pt[text] then
		local _, a = text:gsub("%%s", "")
		local _, b = pt[text]:gsub("%%s", "")
		eq(a, b, "pt-BR keeps the conversions: " .. text)
	end
end

local shopCfg = dofile("data/scripts/chaos/shop_config.lua")
local offered = {}
local function walk(t, depth)
	if type(t) ~= "table" or depth > 8 then return end
	if t.kind == "item" and t.id then offered[t.id] = t end
	for _, v in pairs(t) do walk(v, depth + 1) end
end
if type(shopCfg) == "table" then
	walk(shopCfg, 0)
	for _, id in ipairs(cfg.retiredChests) do
		ok(offered[id] == nil, "the store no longer sells chest " .. id)
	end
	for _, id in ipairs({27761, 27762, 27768, 27769, 27775, 27776, 27764, 27765, 27766, 27767, 27771, 27772, 27773, 27774, 27778, 27779, 27780, 27781}) do
		ok(offered[id] ~= nil, "the store still sells chest " .. id)
	end
	ok(offered[27761].name:find("Melee", 1, true) ~= nil, "the sword chest is the melee one in the store")
	-- the Monk line has its own offer in each tier, at the price of the melee one, and no melee offer names the Monk
	for _, pair in ipairs({{27761, 27762}, {27768, 27769}, {27775, 27776}}) do
		local melee, fist = offered[pair[1]], offered[pair[2]]
		ok(fist.name:find("Fist", 1, true) ~= nil, "chest " .. pair[2] .. " is the fist offer")
		eq(fist.cost, melee.cost, "the fist offer " .. pair[2] .. " costs what the melee one does")
		ok(fist.description:find("Monk", 1, true) ~= nil and fist.description:find("fist", 1, true) ~= nil,
			"the fist offer " .. pair[2] .. " says it is for the Monk and trains fist")
		ok(melee.description:find("Monk", 1, true) == nil and melee.description:find("fist", 1, true) == nil,
			"the melee offer " .. pair[1] .. " does not name the Monk or fist")
		for _, line in ipairs(cfg.kinds.fist.lines) do
			ok(line == "monk", "the fist kind is the Monk's only")
		end
	end
	-- the weapon each chest of the config belongs to has an offer
	for _, ch in ipairs(cfg.chests) do
		ok(offered[ch.melee] ~= nil and offered[ch.fist] ~= nil, "both chests of a tier are sold")
	end
end

-- the Ancestral Store hides the retired chests (commands_ui_core.lua)
dofile("data/scripts/chaos/commands_ui_core.lua")
local K = ChaosCommandsCore
if type(K) == "table" and K.storeEntries then
	local scripts = {["a.lua"] = "local ITEM_PRICE = 10\nItemType(27763)", ["b.lua"] = "local ITEM_PRICE = 10\nItemType(27761)"}
	local out = K.storeEntries({{id = 1, param = "3, 1", group = 3, label = "A", script = "a.lua"},
		{id = 2, param = "3, 2", group = 3, label = "B", script = "b.lua"}},
		function(s) return scripts[s] end, function(id) return {name = "x" .. id, clientId = 1} end)
	eq(#out, 1, "the Ancestral Store lists one of the two")
	eq(out[1] and out[1].itemId, 27761, "the sword (melee) chest stays, the club chest is hidden")
end

print(string.format("exercise_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
