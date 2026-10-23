-- Run from the server/ folder: luajit tests/waystone_mods_test.lua (or lua5.3; CI runs both)
-- Waystone modifiers: waystone_mods_core.lua (rarity by prefixes and suffixes, rolls within the room, the tier gate,
-- the orbs the map way, rewards and caps, effects through rift_core.lua, texts) and waystone_mods.lua against a mocked
-- engine (the item, the take, a run, the monsters' health and speed, hits both ways, healing, rewards, the end).
local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- a seeded rand(a, b)
local seed = 12345
local function rand(a, b)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return a + seed % (b - a + 1)
end

dofile("data/scripts/chaos/waystone_mods_core.lua")
local W = ChaosWaystoneModsCore
local R = ChaosRiftCore
local cfg = dofile("data/scripts/chaos/waystone_mods_config.lua")

-- ================================================================== the pool
local pre, suf = 0, 0
for _, d in ipairs(cfg.mods) do
	if d.side == "suffix" then suf = suf + 1 else pre = pre + 1 end
	check(d.side == "prefix" or d.side == "suffix", d.key .. ": a side")
	check(d.reward ~= nil, d.key .. ": a reward")
	check(d.boon == nil, d.key .. ": no boon (rift only)")
end
eq(pre, 16, "16 prefixes (the monsters)")
eq(suf, 9, "9 suffixes (the players)")
for _, k in ipairs({"teeming", "swarm", "gilded", "coffer", "twin", "echo", "waning", "fragile", "brood", "wrath", "warband"}) do
	eq(R.modDef(cfg, k), nil, k .. ": rift only")
end
eq(R.modText(cfg, {key = "dread", value = 50}), "The map's boss has +50% health and damage", "dread names the map's boss")

-- ================================================================== rarity
local function mods(list)
	local out = {}
	for _, k in ipairs(list) do
		local d = R.modDef(cfg, k)
		out[#out + 1] = {key = k, value = d.range[1]}
	end
	return out
end
eq(W.rarityOf(cfg, {}), 1, "no modifiers: Normal")
eq(W.rarityOf(cfg, mods({"vitality"})), 2, "one prefix: Magic")
eq(W.rarityOf(cfg, mods({"vitality", "withering"})), 2, "a prefix and a suffix: Magic")
eq(W.rarityOf(cfg, mods({"vitality", "brutality"})), 3, "two prefixes: Rare")
eq(W.rarityName(cfg, 3), "Rare", "names")
local six = mods({"vitality", "brutality", "haste", "withering", "blight", "searing"})
eq(W.rarityOf(cfg, six), 3, "3 + 3: Rare")
local text = W.encode(six) .. ",warding:10,sapping:10"
local back = W.decode(cfg, text)
eq(#back, 6, "decode: at most six")
local p, s = W.sides(cfg, back)
eq(p, 3, "three prefixes kept")
eq(s, 3, "three suffixes kept")
eq(#W.decode(cfg, "vitality:30,withering:1,parched:1"), 2, "a group once (no regeneration twice)")
eq(#W.decode(cfg, "teeming:30"), 0, "a rift-only modifier is dropped")
eq(#W.decode(cfg, nil), 0, "nothing")

-- ================================================================== rolls
for i = 1, 300 do
	local ws = W.roll(cfg, 1 + i % 15, "Magic", rand)
	local pp, ss = W.sides(cfg, ws.mods)
	check(#ws.mods >= 1 and #ws.mods <= 2 and pp <= 1 and ss <= 1, "magic room " .. i)
	ws = W.roll(cfg, 1 + i % 15, "Rare", rand)
	pp, ss = W.sides(cfg, ws.mods)
	check(#ws.mods >= 3 and #ws.mods <= 6 and pp <= 3 and ss <= 3, "rare room " .. i)
	eq(W.rarityOf(cfg, ws.mods), 3, "a rare roll is Rare " .. i)
	for _, m in ipairs(ws.mods) do
		local d = R.modDef(cfg, m.key)
		check(ws.tier >= (d.minTier or 1), "minTier " .. m.key)
		check(m.value >= d.range[1] and m.value <= d.range[2], "range " .. m.key)
		if d.tiers and ws.tier <= 5 then
			check((R.modTier(d, m.value) or 1) <= 3, "tiers 1-5 roll I-III: " .. m.key)
		end
	end
	for a = 1, #ws.mods do
		for b = a + 1, #ws.mods do
			check(not R.modConflict(R.modDef(cfg, ws.mods[a].key), R.modDef(cfg, ws.mods[b].key)), "no conflict " .. i)
		end
	end
end
eq(#W.roll(cfg, 5, "Normal", rand).mods, 0, "Normal: none")
local seen = {Normal = 0, Magic = 0, Rare = 0}
for _ = 1, 2000 do
	local ws = W.rollDrop(cfg, 8, rand)
	seen[W.rarityName(cfg, W.rarityOf(cfg, ws.mods))] = seen[W.rarityName(cfg, W.rarityOf(cfg, ws.mods))] + 1
end
check(seen.Normal > 900 and seen.Normal < 1300, "drops: about 55% Normal (" .. seen.Normal .. ")")
check(seen.Rare > 180 and seen.Rare < 430, "drops: about 15% Rare (" .. seen.Rare .. ")")

-- ================================================================== orbs
local function ws(t, list) return {tier = t, mods = mods(list or {})} end
local ok, why = W.orbCheck(cfg, "transmutation", ws(3, {"vitality"}))
check(not ok and why == "wsNeedNormal", "Awakening needs a Normal one")
ok, why = W.orbApply(cfg, "transmutation", ws(3), rand)
eq(W.rarityOf(cfg, why.mods), 2, "Awakening: Magic")
eq(#why.mods, 1, "one modifier")
ok, why = W.orbApply(cfg, "alchemy", ws(9), rand)
check(#why.mods >= 4 and #why.mods <= 6, "Gilding: Rare with 4-6")
eq(W.rarityOf(cfg, why.mods), 3, "Gilding: Rare")
-- Grafting on a Magic one: the open side only
local mg = ws(9, {"vitality"})
ok = W.orbApply(cfg, "exalted", mg, rand)
check(ok, "Grafting on a Magic one with room")
local mp, ms = W.sides(cfg, mg.mods)
check(mp == 1 and ms == 1, "the suffix side (augmentation)")
ok, why = W.orbCheck(cfg, "exalted", mg)
check(not ok and why == "wsMagicFull", "a full Magic one: Fate first")
ok, why = W.orbCheck(cfg, "exalted", ws(9))
check(not ok and why == "wsNoMods", "Grafting needs a Magic or Rare one")
-- Fate: Magic -> Rare (always, whichever side was filled)
for i = 1, 100 do
	local one = ws(9, {i % 2 == 0 and "vitality" or "withering"})
	W.orbApply(cfg, "divine", one, rand)
	eq(W.rarityOf(cfg, one.mods), 3, "Fate makes a Magic one Rare " .. i)
	eq(#one.mods, 2, "one more " .. i)
end
local rare = ws(12, {"vitality", "brutality", "withering"})
W.orbApply(cfg, "divine", rare, rand)
eq(#rare.mods, 3, "Fate on a Rare one: the same count")
eq(rare.mods[1].key, "vitality", "the same modifiers")
-- Grafting on a Rare one up to six
local full = ws(12, {"vitality", "brutality", "haste", "withering", "blight", "searing"})
ok, why = W.orbCheck(cfg, "exalted", full)
check(not ok and why == "wsFull", "six: full")
-- Upheaval keeps the rarity
for i = 1, 50 do
	local r = ws(12, {"vitality", "brutality", "withering"})
	W.orbApply(cfg, "chaos", r, rand)
	eq(W.rarityOf(cfg, r.mods), 3, "Upheaval on a Rare one: Rare " .. i)
	local m2 = ws(12, {"vitality"})
	W.orbApply(cfg, "chaos", m2, rand)
	eq(W.rarityOf(cfg, m2.mods), 2, "Upheaval on a Magic one: Magic " .. i)
end
local un = ws(12, {"vitality", "brutality", "withering"})
W.orbApply(cfg, "annulment", un, rand)
eq(#un.mods, 2, "Unmaking: one off")
W.orbApply(cfg, "scouring", un, rand)
eq(#un.mods, 0, "Erasure: Normal")
ok, why = W.orbCheck(cfg, "sockets", ws(1))
check(not ok and why == "wsSockets", "no sockets")
ok, why = W.orbCheck(cfg, "tempering", ws(1, {"vitality"}))
check(not ok and why == "wsOrb", "another orb refuses")
ok, why = W.orbCheck(cfg, "chaos", ws(1))
check(not ok and why == "wsNoMods", "Upheaval needs modifiers")
eq(W.orbPreview(cfg, "alchemy", ws(1)), "Normal -> Rare, 4-6 modifiers", "preview")

-- ================================================================== rewards and effects
local b = W.bonuses(cfg, mods({"vitality", "withering"}), 5)
eq(b.quantity, math.floor(0.5 * 20 + 15 + 0.5), "quantity: Vitality 0.5 x 20 + Withering 15")
eq(b.experience, math.floor(0.25 * 20 + 15 + 0.5), "experience")
eq(b.waystone, 24, "waystone: 12 a modifier")
local big = {}
for _, d in ipairs(cfg.mods) do
	if d.side == "prefix" and #big < 3 and not d.group then big[#big + 1] = {key = d.key, value = d.range[2]} end
end
for _, k in ipairs({"withering", "blight", "searing"}) do big[#big + 1] = {key = k, value = R.modDef(cfg, k).range[2]} end
b = W.bonuses(cfg, big, 15)
local caps = R.bonusCaps(cfg, big)
check(b.quantity <= caps.quantity and b.rarity <= caps.rarity and b.experience <= caps.experience, "caps")
eq(b.waystone, 72, "waystone cap 72 (six)")
local fx = W.effects(cfg, mods({"vitality", "brutality", "haste", "withering", "blight", "searing"}), 7)
eq(fx.health, 1.2, "Vitality +20%: x1.2 (no rift tier steps)")
eq(fx.damage, 1.15, "Brutality +15%")
eq(fx.speed, 40, "Haste")
check(fx.noRegen, "Withering")
eq(fx.healMult, 0.8, "Blight -20%")
eq(fx.hexElem, 0.1, "Searing +10%")
eq(fx.packDamage, 1, "no rift density")
fx = W.effects(cfg, {}, 15)
eq(fx.health, 1, "no modifiers at tier XV: x1 (the level is the tier's own)")
eq(fx.damage, 1, "and x1 damage")
eq(W.eliteChance(cfg, 1), 0, "no Elites: no extra chance")
eq(W.eliteChance(cfg, 2), 8, "Elites +100%: +8%")

-- ================================================================== texts
local r3 = ws(4, {"vitality", "brutality", "withering"})
eq(W.itemName(cfg, r3), "Rare Waystone Tier IV", "name")
eq(W.itemName(cfg, ws(4)), "Waystone Tier IV", "a Normal one keeps the base name")
local d = W.describe(cfg, r3, 1400)
check(d:find("Rare. Opens a map of monster level 1400.", 1, true) ~= nil, "description: rarity and level")
check(d:find("Prefixes: Monsters have +20% health", 1, true) ~= nil, "prefixes listed")
check(d:find("Suffixes: Players do not regenerate health", 1, true) ~= nil, "suffixes listed")
check(d:find("+3% waystone drops", 1, true) == nil and d:find("+36% waystone drops", 1, true) ~= nil, "rewards listed")

-- ================================================================== the engine file
Chaos = {t = function(_, f, ...) return string.format(f, ...) end, percentBase = function(p) return p:getMaxHealth() end}
local events = {}
CreatureEvent = function(name)
	local ev = {name = name}
	function ev:type() end
	function ev:register() events[name] = self end
	return ev
end
local clock = 1000
os.time = function() return clock end -- luacheck: ignore
local pending = {}
addEvent = function(f, ms, ...) pending[#pending + 1] = {f = f, args = {...}} end
Position = function(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
COMBAT_HEALING, COMBAT_PHYSICALDAMAGE, COMBAT_FIREDAMAGE, COMBAT_ICEDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_NONE = 128, 1, 8, 512, 2, 0
ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_ARTICLE = 1, 2, 3
local hits = {}
doTargetCombatHealth = function(cid, target, kind, a) hits[#hits + 1] = {cid = cid, target = target, kind = kind, amount = a} end
Game = {getSpectators = function() return {} end}
dofile("data/scripts/chaos/waystone_tiers_core.lua")
ChaosWaystoneTiers = {config = dofile("data/scripts/chaos/waystone_tiers_config.lua")}
dofile("data/scripts/chaos/waystone_mods.lua")
local WM = ChaosWaystoneMods

local function item(id, attrs, count)
	local it = {id = id, attrs = attrs or {}, custom = {}, count = count or 1, removed = 0}
	function it:getId() return self.id end
	function it:getCount() return self.count end
	function it:getCustomAttribute(k) return self.custom[k] end
	function it:setCustomAttribute(k, v) self.custom[k] = v end
	function it:removeCustomAttribute(k) self.custom[k] = nil end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:removeAttribute(k) self.attrs[k] = nil end
	function it:remove(n) self.removed = self.removed + (n or self.count) self.count = self.count - (n or self.count) return true end
	function it:isContainer() return false end
	return it
end
eq(WM.isWaystone(item(41951)), true, "Tier VII is a waystone")
eq(WM.isWaystone(item(2160)), false, "gold is not")
local wsItem = item(29848)
WM.write(wsItem, {tier = 4, mods = mods({"vitality", "brutality", "withering"})})
eq(wsItem.attrs[ITEM_ATTRIBUTE_NAME], "Rare Waystone Tier IV", "written name")
check(wsItem.attrs[ITEM_ATTRIBUTE_DESCRIPTION]:find("monster level 1400", 1, true) ~= nil, "written description (level)")
local read = WM.read(wsItem)
eq(read.tier, 4, "read tier")
eq(#read.mods, 3, "read modifiers")
WM.write(wsItem, {tier = 4, mods = {}})
eq(wsItem.custom[cfg.attribute], nil, "Normal again: attribute off")
eq(wsItem.attrs[ITEM_ATTRIBUTE_NAME], nil, "and the base name (stacks again)")

-- the take: the used one, else the fewest modifiers
local normal, magic, rareI = item(29848, nil, 3), item(29848), item(29848)
WM.write(magic, {tier = 4, mods = mods({"vitality"})})
WM.write(rareI, {tier = 4, mods = mods({"vitality", "brutality", "withering"})})
local bag = {getItems = function() return {rareI, magic, normal} end, isContainer = function() return true end,
	getId = function() return 1988 end}
CONST_SLOT_FIRST, CONST_SLOT_LAST = 1, 1
local player = {guid = 5, id = 77, msgs = {}}
function player:getGuid() return self.guid end
function player:getId() return self.id end
function player:getSlotItem() return bag end
function player:isPlayer() return true end
for _, it in ipairs({normal, magic, rareI}) do
	it.getTopParent = function() return player end
end
local okT, got = WM.take(player, 29848)
check(okT and #got == 0, "from the window: the fewest modifiers (a Normal one)")
eq(normal.count, 2, "one off the Normal stack")
WM.choose(player, rareI)
okT, got = WM.take(player, 29848)
check(okT and #got == 3, "the waystone used on the device")
eq(rareI.removed, 1, "that one is taken")
WM.choose(player, magic)
clock = clock + 1000
okT, got = WM.take(player, 29848)
check(okT and #got == 0, "a choice from long ago: the fewest again")
okT = WM.take(player, 41959)
eq(okT, false, "none of that tier")
clock = 1000

-- a run: monsters of the map
local T5 = {x = 33400, y = 33200, z = 7} -- map 9 (base tier V)
local run = WM.begin(9, 11, mods({"vitality", "haste", "warding", "reflection", "withering", "searing", "blight"}))
check(run ~= nil, "a run with modifiers")
eq(WM.runAt(T5), run, "its map")
local function monster(hp)
	local m = {hp = hp, health = hp, speed = 0, events = {}, id = 500}
	function m:getId() return self.id end
	function m:getMaxHealth() return self.hp end
	function m:getHealth() return self.health end
	function m:setMaxHealth(v) self.hp = v end
	function m:setHealth(v) self.health = v end
	function m:changeSpeed(v) self.speed = self.speed + v end
	function m:registerEvent(n) self.events[n] = true end
	function m:getPosition() return T5 end
	function m:getName() return "Plague Warbringer" end
	function m:isPlayer() return false end
	function m:getMaster() return nil end
	return m
end
local mon = monster(100000)
local e = {map = 9, tier = 5, run = 11, boss = false}
WM.applyMonster(mon, e, false)
eq(mon.hp, 120000, "Vitality +20%")
eq(mon.speed, 40, "Haste +40")
check(mon.events.ChaosWaystoneModsHealth and mon.events.ChaosWaystoneModsDeath, "its events")
WM.applyMonster(mon, e, false)
eq(mon.hp, 120000, "applied once")
-- a player hits it: Warding cuts the fire part, Reflection sends a share back
local pl = {id = 77}
function pl:isPlayer() return true end
function pl:getId() return 77 end
local p1, _, s1 = WM.monsterTaken(mon, pl, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE)
eq(p1, -900, "Warding 10%: fire 1000 -> 900")
eq(s1, 0, "no secondary")
eq(#hits, 1, "Reflection")
eq(hits[1].amount, -45, "5% of what landed")
-- it hits a player: Searing Hex on the fire part
local hp = WM.playerHit(pl, mon, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE)
eq(hp, -1100, "Searing +10% elemental")
hp = WM.playerHit(pl, mon, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE)
eq(hp, -1000, "physical: no hex")
local other = monster(1)
other.id = 501
hp = WM.playerHit(pl, other, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE)
eq(hp, -1000, "a monster outside the run: unchanged")
-- healing in the map
pl.getPosition = function() return T5 end
local heal = events.ChaosWaystoneModsPlayerHit.onHealthChange(pl, nil, 1000, COMBAT_HEALING, 0, COMBAT_NONE)
eq(heal, 800, "Blighted Mending -20%")
pl.getPosition = function() return {x = 1, y = 1, z = 7} end
heal = events.ChaosWaystoneModsPlayerHit.onHealthChange(pl, nil, 1000, COMBAT_HEALING, 0, COMBAT_NONE)
eq(heal, 1000, "outside the map: full")
-- rewards
local q = 1 + run.bonus.quantity / 100
eq(WM.lootMult({monster = mon}), q, "quantity of the run")
eq(WM.lootMult({monster = other}), q, "a monster standing in the map counts too")
other.getPosition = function() return {x = 1, y = 1, z = 7} end
eq(WM.lootMult({monster = other}), 1, "outside: x1")
eq(WM.rarityFind(mon), run.bonus.rarity, "rarity of the run")
eq(WM.expMult(mon), 1 + run.bonus.experience / 100, "experience of the run")
check(run.bonus.waystone == 84 or run.bonus.waystone == 72, "waystone bonus capped")
-- a new run of the map without modifiers: the old ones come off
WM.begin(9, 12, {})
eq(WM.runAt(T5), nil, "no run with modifiers")
WM.applyMonster(mon, e, false)
eq(mon.hp, 100000, "health back")
eq(mon.speed, 0, "speed back")
-- the run ends by time
run = WM.begin(9, 11, mods({"vitality"}))
clock = clock + cfg.runSeconds + 1
eq(WM.runAt(T5), nil, "over after runSeconds")
eq(WM.runs[9], nil, "and forgotten")
-- drops roll a rarity inside only
local dropped = item(41951)
WM.rollDrop(dropped, 7, false)
eq(dropped.custom[cfg.attribute], nil, "outside: Normal")
local rolled = 0
for _ = 1, 200 do
	local it = item(41951)
	WM.rollDrop(it, 7, true)
	if it.custom[cfg.attribute] then rolled = rolled + 1 end
end
check(rolled > 60 and rolled < 130, "inside: about 45% with modifiers (" .. rolled .. ")")

print(string.format("waystone_mods_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
