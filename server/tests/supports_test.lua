-- Run from the server/ folder: luajit tests/supports_test.lua (and lua5.3; CI runs both)
-- Spell supports: data/lib/chaos_supports.lua (ids, names, texts, socket counts, compatibility, caps, combat maths,
-- the cast context, spells.xml parsing, drops and rewards), the spell side data/spells/chaos/_supports.lua (the
-- onCastSpell wrapper: context while the script and its delayed events run, Thrift and Quickening after the cast,
-- Reprisal storages) and data/scripts/chaos/supports.lua against a mocked engine (socketing, removing for gold or
-- shattering, the third socket, combining, the hit effects: brand, Sunder, Keen Edge, Hex, Mercy, the extra hits of
-- Fork / Shatter / Breadth / Deathburst / Surge / Echo, Bloodthirst, Siphon, Reprisal).

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
COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_FIREDAMAGE = 1, 2, 4, 8
COMBAT_HEALING, COMBAT_ICEDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_DEATHDAMAGE = 256, 512, 1024, 2048
ORIGIN_NONE, ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED = 0, 1, 2, 3, 4
CONST_ME_NONE, CONST_ME_MAGIC_BLUE, CONST_ME_MAGIC_GREEN, CONST_ME_BLOCKHIT = 0, 1, 2, 3
CONST_ME_ENERGYAREA, CONST_ME_EXPLOSIONHIT, CONST_ME_EXPLOSIONAREA, CONST_ME_ENERGYHIT = 4, 5, 6, 7
CONST_ME_HITAREA, CONST_ME_PURPLEENERGY, CONST_ANI_ENERGY = 8, 9, 10
CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT, CONDITION_PARAM_SUBID, CONDITION_PARAM_TICKS = 1, 0, 1, 2
MESSAGE_INFO_DESCR, MESSAGE_STATUS_CONSOLE_BLUE, SKILL_LEVEL, TILESTATE_PROTECTIONZONE = 1, 2, 8, 1
RETURNVALUE_NOERROR, INDEX_WHEREEVER, FLAG_NOLIMIT = 0, -1, 1
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_ATTACK_SPEED = 1, 2, 3
SLOTP_TWO_HAND = 2048

function ItemType(id)
	return {getClientId = function() return 20000 + id % 1000 end, getName = function() return "item" end,
		getSlotPosition = function() return 0 end, getWeaponType = function() return 0 end,
		isStackable = function() return true end, getAbilities = function() return {} end}
end

-- deferred events: run by flushEvents (delay ignored, in order)
local events = {}
function addEvent(fn, delay, ...)
	events[#events + 1] = {fn = fn, args = {n = select("#", ...), ...}}
	return #events
end
local function flushEvents()
	local guard = 0
	while #events > 0 do
		guard = guard + 1
		assert(guard < 1000, "event loop")
		local e = table.remove(events, 1)
		e.fn((table.unpack or unpack)(e.args, 1, e.args.n))
	end
end

local creatures = {}
local hits = {} -- doTargetCombat log
local nextId = 1

local Cr = {}
Cr.__index = Cr
function Cr:getId() return self.id end
function Cr:isPlayer() return self.player == true end
function Cr:isMonster() return not self.player end
function Cr:getMaster() return nil end
function Cr:getHealth() return self.health end
function Cr:getMaxHealth() return self.maxHealth or 1000 end
function Cr:getName() return self.name or "Demon" end
function Cr:getPosition()
	local p = self.pos
	return Position(p.x, p.y, p.z)
end
function Cr:getTile() return {hasFlag = function() return false end} end
function Cr:registerEvent(name) self.events = self.events or {}; self.events[name] = true return true end
function Cr:getType()
	local res = self.res
	return {getElementList = function() return res or {} end}
end
-- player parts
function Cr:getLevel() return self.level end
function Cr:getStorageValue(k) return self.storage[k] or -1 end
function Cr:setStorageValue(k, v)
	if v == -1 then self.storage[k] = nil else self.storage[k] = v end
end
function Cr:getItemCount(id) return self.items[id] or 0 end
function Cr:removeItem(id, n)
	if (self.items[id] or 0) < n then return false end
	self.items[id] = self.items[id] - n
	return true
end
function Cr:addItem(id, n) self.items[id] = (self.items[id] or 0) + (n or 1) return true end
function Cr:getBankBalance() return self.bank or 0 end
function Cr:setBankBalance(v) self.bank = v end
function Cr:removeMoney(v)
	if (self.gold or 0) < v then return false end
	self.gold = self.gold - v
	return true
end
function Cr:getMaxMana() return self.maxMana or 1000 end
function Cr:addMana(n) self.mana = (self.mana or 0) + n end
function Cr:getVocation() local v = self.voc return {getId = function() return v end} end
function Cr:sendTextMessage(_, text) self.lastText = text end
function Cr:sendCancelMessage(text) self.lastCancel = text end
function Cr:sendExtendedOpcode(op, buffer) self.sent = self.sent or {}; self.sent[#self.sent + 1] = buffer end
function Cr:getInbox() return nil end
function Cr:getGroup() return {getAccess = function() return false end} end
function Cr:getCondition(t, id, sub)
	return self.conditions and self.conditions[sub]
end
function Cr:removeCondition(t, id, sub) if self.conditions then self.conditions[sub] = nil end end
function Cr:addCondition(c) self.conditions = self.conditions or {}; self.conditions[c.sub] = c end

local function newCreature(t)
	t.id = nextId
	nextId = nextId + 1
	t.storage = t.storage or {}
	t.items = t.items or {}
	setmetatable(t, Cr)
	creatures[t.id] = t
	return t
end
function Creature(id)
	if type(id) == "table" then return id end
	local c = creatures[id]
	return c and c.health > 0 and c or nil
end
function Player(id)
	local c = Creature(id)
	return c and c.player and c or nil
end

function Position(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end, sendDistanceEffect = function() end}
end

Game = {getSpectators = function(center, _, _, rx)
	local out = {}
	for _, c in pairs(creatures) do
		if c.health > 0 and c.pos.z == center.z and math.abs(c.pos.x - center.x) <= rx
				and math.abs(c.pos.y - center.y) <= rx then
			out[#out + 1] = c
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end}

function doTargetCombat(attacker, target, ctype, min, max, effect, origin)
	hits[#hits + 1] = {attacker = attacker, target = target, type = ctype, amount = min, origin = origin}
	if ctype ~= COMBAT_HEALING then
		target.health = target.health + min
	end
	return true
end

local function Condition(t, id)
	local c = {t = t, ticks = 0, sub = 0}
	function c:setParameter(k, v)
		if k == CONDITION_PARAM_SUBID then self.sub = v elseif k == CONDITION_PARAM_TICKS then self.ticks = v end
	end
	function c:getTicks() return self.ticks end
	return c
end
_G.Condition = Condition

local registered = {}
function CreatureEvent(name)
	local e = {name = name}
	function e:register() registered[name] = self end
	function e:type() end
	return e
end
EventCallback = setmetatable({}, {__index = function() return function() end end})
function EventCallback:register() registered.targetCombat = self.onTargetCombat end
local actions = 0
function Action()
	return {id = function() actions = actions + 1 end, allowFarUse = function() end, register = function() end}
end
function TalkAction() return {separator = function() end, register = function() end} end
function GlobalEvent(name)
	local e = {name = name}
	function e:register() registered[name] = self end
	return e
end
json = {encode = function() return "{}" end, decode = function() return {} end}

-- ---------------------------------------------------------------- the libraries
dofile("data/scripts/chaos/chaos_constants.lua")
ChaosCrafting = {} -- keep supports.lua from loading the whole crafting library
dofile("data/lib/chaos_gems.lua")
dofile("data/lib/chaos_supports.lua")
local S = ChaosSupports
local cfg = S.config

-- ---------------------------------------------------------------- ids and names
eq(S.TYPES, 20, "twenty supports")
eq(S.LEVELS, 5, "five levels")
eq(S.runeId(1, 1), 32101, "first rune")
eq(S.lastId, 32200, "last rune")
for i = 1, S.TYPES do
	for l = 1, S.LEVELS do
		local r = S.runeOf(S.runeId(i, l))
		eq(r.type.index, i, "type of rune")
		eq(r.level, l, "level of rune")
	end
end
eq(S.runeOf(32100), nil, "below range")
eq(S.runeOf(32201), nil, "above range")
eq(S.isRune(32035), false, "a gem is no rune")
local fork = S.byKey.fork
local epicFork = S.runeId(fork.index, 3)
eq(epicFork, 32148, "epic fork id")
eq(S.runeName(epicFork), "Epic Fork Rune", "rune name")
eq(S.itemName(fork.index, 3, true), "epic fork runes", "items.xml plural")
eq(S.effectText(epicFork), "The hit forks to 2 more enemies within 3 sqm for 45% of it", "effect text")
eq(S.effectText(S.runeId(1, 5)), "60% of the spell's damage becomes fire damage", "brand text")
eq(S.levelsText("quickening"), "Cooldown -6/9/12/15/18%", "levels text")
eq(S.levelColor(S.runeId(1, 5)), cfg.levelColors[5], "mythic colour")
ok(S.description(fork.index, 5):find("Fits single target spells%.") ~= nil, "description fits")
ok(S.description(fork.index, 5):find("combine") == nil, "mythic does not combine")
ok(S.description(1, 1):find("^A support rune for a spell socket: 20%% of") ~= nil, "description starts lower case")
-- every support: values rise, fits are known kinds, sprite exists, a group-mate never fits nothing
local kinds = {single = true, area = true, heal = true, buff = true}
for _, t in ipairs(cfg.supports) do
	eq(#t.values, 5, t.key .. " values")
	for l = 2, 5 do
		ok(t.values[l] >= t.values[l - 1], t.key .. " values rise")
	end
	ok(#t.fits > 0, t.key .. " fits something")
	for _, k in ipairs(t.fits) do
		ok(kinds[k], t.key .. " kind " .. k)
	end
	ok(cfg.sprites[t.sprite], t.key .. " sprite")
end

-- ---------------------------------------------------------------- socket counts
eq(S.socketCount(29, 30, false), 0, "below the spell level")
eq(S.socketCount(30, 30, false), 1, "one socket")
eq(S.socketCount(89, 30, false), 1, "second at 90")
eq(S.socketCount(90, 30, false), 2, "second socket")
eq(S.socketCount(20, 15, false), 1, "second at least 80")
eq(S.socketCount(80, 15, false), 2, "second at 80")
eq(S.socketCount(500, 30, false), 2, "third needs the orbs")
eq(S.socketCount(199, 30, true), 2, "third at least 200")
eq(S.socketCount(200, 30, true), 3, "third socket")
eq(S.socketCount(449, 300, true), 2, "third at spell level + 150")
eq(S.socketCount(450, 300, true), 3, "third at 450 for a level 300 spell")

-- ---------------------------------------------------------------- compatibility
local function sock(a, b, c)
	return {opened = false, runes = {a or 0, b or 0, c or 0}}
end
local ember, rime = S.runeId(1, 2), S.runeId(2, 1)
local mercy = S.runeId(S.byKey.mercy.index, 1)
local quick = S.runeId(S.byKey.quickening.index, 4)
local breadth = S.runeId(S.byKey.breadth.index, 1)
eq(S.canSocket(sock(), 1, ember, "area"), 1, "brand in an area spell")
eq(S.canSocket(sock(), 1, ember, "single"), 1, "brand in a single target spell")
ok(select(2, S.canSocket(sock(), 1, ember, "heal")):find("does not fit"), "no brand in a heal")
ok(select(2, S.canSocket(sock(), 1, mercy, "area")):find("does not fit"), "mercy only heals")
eq(S.canSocket(sock(), 1, mercy, "heal"), 1, "mercy in a heal")
eq(S.canSocket(sock(), 1, quick, "buff"), 1, "quickening in a buff")
ok(select(2, S.canSocket(sock(), 1, breadth, "single")):find("does not fit"), "breadth is area only")
ok(select(2, S.canSocket(sock(), 1, epicFork, "area")):find("does not fit"), "fork is single only")
eq(select(2, S.canSocket(sock(ember), 2, rime, "area")), S.reasons.group, "one brand per spell")
ok(select(2, S.canSocket(sock(ember), 2, S.runeId(1, 4), "area")):find("already has"), "one of a kind")
eq(S.canSocket(sock(ember), 2, quick, "area"), 2, "second socket")
eq(select(2, S.canSocket(sock(ember), 1, quick, "area")), S.reasons.full, "full")
eq(select(2, S.canSocket(sock(), 1, quick, "area", 2)), S.reasons.locked, "closed socket")
eq(select(2, S.canSocket(sock(), 1, 12345, "area")), S.reasons.notRune, "not a rune")
eq(select(2, S.canSocket(sock(), 1, quick, nil)), S.reasons.noSpell, "no kind")

-- ---------------------------------------------------------------- effects and caps
local fx = S.effects({ember, quick, 0})
eq(fx.emberbrand.value, 30, "brand value")
eq(fx.emberbrand.element, "fire", "brand element")
eq(fx.quickening.value, 15, "quickening value")
local capped = S.effects({S.runeId(S.byKey.quickening.index, 5), S.runeId(S.byKey.quickening.index, 5)})
eq(capped.quickening.value, cfg.caps.quickening, "summed and capped")
eq(S.effects({ember, quick}, 1).quickening, nil, "a closed socket does not count")

-- ---------------------------------------------------------------- combat maths
eq(S.scale(100, 12), 112, "scale")
eq(S.scale(-100, 12), -112, "scale keeps the sign")
eq(S.part(-101, 50), -50, "part toward zero")
local pd, pt, sd, st = S.convert(100, COMBAT_PHYSICALDAMAGE, 0, 0, 40, COMBAT_FIREDAMAGE)
eq(pd, 60, "primary keeps 60"); eq(sd, 40, "40 fire"); eq(st, COMBAT_FIREDAMAGE, "fire type")
pd, pt, sd, st = S.convert(100, COMBAT_PHYSICALDAMAGE, 0, 0, 40, COMBAT_FIREDAMAGE, function(t)
	return t == COMBAT_FIREDAMAGE and 50 or 0
end)
eq(sd, 20, "the moved part takes the fire resistance")
pd, pt, sd, st = S.convert(80, COMBAT_PHYSICALDAMAGE, 0, 0, 50, COMBAT_FIREDAMAGE, function(t)
	return t == COMBAT_PHYSICALDAMAGE and 20 or (t == COMBAT_FIREDAMAGE and -10 or 0)
end)
eq(pd, 40, "primary half"); eq(sd, 55, "loses 20% physical, takes 10% fire weakness")
pd, pt, sd, st = S.convert(100, COMBAT_PHYSICALDAMAGE, 30, COMBAT_ICEDAMAGE, 40, COMBAT_FIREDAMAGE)
eq(pd, 100, "another element in the secondary part: unchanged"); eq(st, COMBAT_ICEDAMAGE, "secondary stays")
pd = S.convert(100, COMBAT_FIREDAMAGE, 0, 0, 40, COMBAT_FIREDAMAGE)
eq(pd, 100, "already fire")
eq(S.penetrate(50, 50, 18), 68, "sunder 18 of 50%")
eq(S.penetrate(50, 10, 18), 55, "sunder never below 0 resistance")
eq(S.penetrate(50, 0, 18), 50, "no resistance, nothing")
eq(S.penetrate(50, -20, 18), 50, "weakness stays")
eq(S.penetrate(0, 100, 18), 0, "immune stays immune")

-- ---------------------------------------------------------------- context
local serial, id = S.ctxDecode(S.ctxEncode(1234, 201))
eq(serial, 1234, "serial"); eq(id, 201, "spell id")
eq(S.ctxDecode(-1), nil, "no context")
eq(select(2, S.ctxDecode(S.ctxEncode(1000001, 7))), 7, "serial wraps")

-- ---------------------------------------------------------------- spells.xml
local xml = [[<spells>
	<instant group="attack" spellid="201" name="Witchfire Bolt" words="kah pyr vesh" level="30" mana="70" cooldown="4000" script="chaos/sorcerer/hexfire_bolt.lua">
		<vocation name="Mystic" />
	</instant>
	<instant group="healing" spellid="1" name="Light Healing" words="exura" lvl="8" mana="20" cooldown="1000" script="healing/light_healing.lua" />
	<instant group="support" name="Unscribed Rune" words="rhun nul" level="20" mana="50" script="conjuring/blank_rune.lua" />
	<instant spellid="7" name="A" words="a b" level="1" script="attack/a.lua" />
	<instant spellid="7" name="B" words="b c" level="1" script="attack/b.lua" />
	<instant spellid="9" name="House" words="aleta sio" script="house/edit.lua" />
	<!-- <instant spellid="10" name="Old" words="x" script="x.lua" /> -->
	<instant spellid="11" name="Monster" words="#####" script="monster/x.lua" />
	<instant spellid="12" name="Mana" words="m" manapercent="20" script="support/m.lua" />
</spells>]]
local entries = S.parseSpellsXml(xml)
eq(#entries, 8, "instants parsed, comments skipped")
eq(entries[1].mana, 70, "mana"); eq(entries[1].cooldown, 4000, "cooldown"); eq(entries[2].level, 8, "lvl attribute")
local el = S.eligible(entries)
ok(el[201] and el[1] and el[12], "chaos, stock and mana-percent spells")
eq(el[7], nil, "a shared id gets no sockets")
eq(el[9], nil, "no house spells")
eq(el[11], nil, "no monster spells")
eq(el[12].manaPercent, 20, "mana percent")
cfg.stockSpells = false
eq(S.eligible(entries)[1], nil, "stockSpells = false: Chaos spells only")
ok(S.eligible(entries)[201], "chaos spell stays")
cfg.stockSpells = true
eq(S.kindOf(201, "damage", "single"), "single", "kind single")
eq(S.kindOf(206, "damage", "area"), "area", "kind area")
eq(S.kindOf(208, "heal", "self"), "heal", "kind heal")
eq(S.kindOf(209, "buff", "self"), "buff", "kind buff")
eq(S.kindOf(211, "summon", "self"), "buff", "summon is a buff")
eq(S.kindOf(202, "damage", "area"), "single", "override")
eq(S.kindOf(1, "conjure", "self"), nil, "conjure: none")

-- ---------------------------------------------------------------- drops and rewards
local seq = {}
local function dice(a, b)
	local v = table.remove(seq, 1)
	if v == nil then return a end
	assert(v >= a and v <= b, "dice " .. v .. " outside " .. a .. ".." .. b)
	return v
end
seq = {1000001 - 1}
eq(#S.rollDrop("normal", 10, 1, dice), 0, "a normal monster mostly drops nothing")
seq = {1, 1, 1}
local drop = S.rollDrop("normal", 10, 1, dice)
eq(#drop, 1, "a drop"); eq(drop[1], S.runeId(1, 1), "level 1 emberbrand")
seq = {1, 1, 1, 1}
eq(S.rollDrop("boss", 10, 1, dice)[1], S.runeId(1, 2), "a boss drop can be a level better")
eq(#S.rollDrop("normal", 10, 0, dice), 0, "rate 0")
seq = {1, 1, 1}
local rr = S.rewardRunes("rift", {tier = 7}, dice)
eq(#rr, 1, "rift tier 7: one rune (1.0)"); eq(S.runeOf(rr[1].id).level, 1, "lowest level with dice 1")
seq = {}
eq(#S.rewardRunes("bounty", {type = "hunt", band = 1}, function(a, b) return b end), 0, "bounty chance missed")
ok(#S.rewardRunes("bounty", {type = "boss", band = 3}, function(a, b) return a end) == 1, "bounty boss")
eq(S.listText({{id = epicFork, count = 2}, {id = S.runeId(1, 1), count = 1}}),
	"2 Epic Fork Runes, Common Emberbrand Rune", "list text")
eq(S.combineResult(S.runeId(3, 4)), S.runeId(3, 5), "combine")
eq(select(2, S.combineResult(S.runeId(3, 5))), "mythic", "mythic does not combine")
eq(S.removeCost(S.runeId(3, 4)), 60000, "remove cost")

-- ---------------------------------------------------------------- the spell side (_supports.lua)
local caster = newCreature({player = true, level = 300, voc = 1, pos = {x = 100, y = 100, z = 7}, health = 3000,
	maxHealth = 3000, maxMana = 2000, mana = 0})
ChaosSupportsSpell = nil
dofile("data/spells/chaos/_supports.lua")
local W = ChaosSupportsSpell
ok(W and W.wrap and W.install, "spell side loaded")
-- spells.xml of the test: script -> spell
local spellsXml = {["chaos/sorcerer/hexfire_bolt.lua"] = {id = 201, name = "Witchfire Bolt", level = 30, mana = 200,
	cooldown = 10000}}
local castCtx, delayedCtx
local original = function(creature, variant)
	castCtx = creature:getStorageValue(cfg.storageContext)
	addEvent(function()
		delayedCtx = creature:getStorageValue(cfg.storageContext)
		addEvent(function() end, 10)
	end, 100)
	return true
end
local wrapped = W.wrap(spellsXml["chaos/sorcerer/hexfire_bolt.lua"], original)
-- Thrift 3 (12%) and Quickening 2 (9%) in the spell, Reprisal 1
S.setRune(caster, 201, 1, S.runeId(S.byKey.thrift.index, 3))
S.setRune(caster, 201, 2, S.runeId(S.byKey.quickening.index, 2))
caster.conditions = {[201] = Condition(CONDITION_SPELLCOOLDOWN)}
caster.conditions[201].sub, caster.conditions[201].ticks = 201, 10000
eq(wrapped(caster, {}), true, "the wrapper returns the script's result")
local s1, sp1 = S.ctxDecode(castCtx)
eq(sp1, 201, "context while the script runs"); eq(s1, 1, "first serial")
eq(caster.storage[cfg.storageContext], nil, "context cleared after the script")
flushEvents()
eq(select(2, S.ctxDecode(delayedCtx)), 201, "context in the delayed event of the cast")
eq(caster.storage[cfg.storageContext], nil, "context cleared after the delayed event")
eq(caster.mana, 24, "Thrift: 12% of 200 mana back")
eq(caster.conditions[201].ticks, 9100, "Quickening: 9% of the 10 s cooldown off")
-- a third socket of Reprisal is closed (no orbs): nothing
S.setRune(caster, 201, 3, S.runeId(S.byKey.reprisal.index, 1))
wrapped(caster, {})
eq(caster.storage[cfg.storageReprisal], nil, "a closed socket does nothing")
S.setOpened(caster, 201)
wrapped(caster, {})
eq(caster.storage[cfg.storageReprisal], 201, "Reprisal: spell remembered")
ok(caster.storage[cfg.storageReprisalUntil] >= os.time() + 7, "Reprisal: window")
flushEvents()
-- a cancelled cast: no refund
caster.mana = 0
eq(W.wrap(spellsXml["chaos/sorcerer/hexfire_bolt.lua"], function() return false end)(caster, {}), false, "cancel")
flushEvents()
eq(caster.mana, 0, "no refund on a cancelled cast")
-- monsters casting the spell: untouched
local monster0 = newCreature({pos = {x = 1, y = 1, z = 7}, health = 10})
eq(W.wrap(spellsXml["chaos/sorcerer/hexfire_bolt.lua"], function(c) return c == monster0 end)(monster0, {}), true,
	"monster cast passes through")
-- errors of the script surface and the context is cleared
local okErr = pcall(W.wrap(spellsXml["chaos/sorcerer/hexfire_bolt.lua"], function() error("boom") end), caster, {})
eq(okErr, false, "error passes through")
eq(caster.storage[cfg.storageContext], nil, "context cleared after an error")
for i = 1, 3 do S.setRune(caster, 201, i, 0) end
-- the hook: a chunk loaded with the engine's chunk name defines onCastSpell on a private env -> wrapped when the
-- script is a known spell, left alone otherwise
eq(W.scriptOf(1), nil, "no script path outside a spell file")
local function loadAs(src, name, env)
	if setfenv then
		local f = loadstring(src, name)
		setfenv(f, env)
		return f
	end
	return load(src, name, "t", env)
end
local env = {}
W.install(env)
local realList = W.spellsByScript
W.spellsByScript = function() return spellsXml end
local before = W.wrapped
loadAs("function onCastSpell(c, v) return c:getStorageValue(" .. cfg.storageContext .. ") end",
	"@data/spells/scripts/chaos/sorcerer/hexfire_bolt.lua", env)()
eq(W.wrapped, before + 1, "known script wrapped")
eq(select(2, S.ctxDecode(env.onCastSpell(caster, {}))), 201, "the wrapped script runs with the context")
env.onCastSpell = nil -- the engine clears the global after reading it
loadAs("function onCastSpell(c, v) return 'orig' end", "@data/spells/scripts/attack/unknown.lua", env)()
eq(env.onCastSpell(caster, {}), "orig", "unknown script: not wrapped")
eq(W.wrapped, before + 1, "count unchanged")
W.spellsByScript = realList
flushEvents()
-- ---------------------------------------------------------------- the same through the spell events (engine patch 0008)
local E = ChaosSpellEvents
ok(E and E.onSpellCost and E.onSpellCooldown, "ChaosSpellEvents loaded with the spell side")
W.spellsByScript = function() return spellsXml end
S.setRune(caster, 201, 1, S.runeId(S.byKey.thrift.index, 3)) -- 12%
S.setRune(caster, 201, 2, S.runeId(S.byKey.quickening.index, 2)) -- 9%
E.live = false
local mana, health = E.onSpellCost(caster, "Witchfire Bolt", 201, 1, true, 200)
eq(mana, 176, "Thrift: a real discount, 200 - 12%"); eq(health, 0)
eq(E.live, true, "the first event marks the events as live")
eq(E.onSpellCooldown(caster, "Witchfire Bolt", 201, 1, true, "spell", 10000), 9100, "Quickening on the spell cooldown")
eq(E.onSpellCooldown(caster, "Witchfire Bolt", 201, 1, true, "group", 2000), 2000, "the group cooldown stays")
eq(E.onSpellCost(caster, "Unknown", 999, 1, true, 100), 100, "a spell without supports: unchanged")
-- the item modifiers join under the support caps (ChaosItemMods totals of the player)
local savedBonus = W.itemBonus
W.itemBonus = function() return {cdr = 25, manacost = 10} end
eq(E.onSpellCost(caster, "Witchfire Bolt", 201, 1, true, 200), 156, "12% + 10% = 22% off")
eq(E.onSpellCost(caster, "Unknown", 999, 1, true, 100), 90, "items alone on any spell")
eq(E.onSpellCooldown(caster, "Witchfire Bolt", 201, 1, true, "spell", 10000), 7000, "9% + 25% capped at 30%")
eq(E.onSpellCooldown(caster, "Unknown", 999, 1, true, "spell", 1200), 1000, "never below the 1 s floor")
eq(E.onSpellCooldown(caster, "Unknown", 999, 1, true, "spell", 800), 800, "a shorter cooldown stays")
-- with the events live the wrapper gives nothing back afterwards (no double discount)
caster.mana = 0
caster.conditions[201].ticks = 10000
wrapped(caster, {})
flushEvents()
eq(caster.mana, 0, "no refund tick when the events are live")
eq(caster.conditions[201].ticks, 10000, "no cooldown rewrite either")
E.live = false
wrapped(caster, {})
flushEvents()
eq(caster.mana, 44, "fallback without the events: (12% + 10%) of 200 back")
W.itemBonus = savedBonus
-- chaining: handlers in order, each sees the previous result; a broken one is skipped
E.set("cost", "test_double", function(p, n, id, g, a, m, h) return m * 2, h + 3 end)
E.set("cost", "test_broken", function() error("boom") end)
local m2, h2 = E.onSpellCost(caster, "Unknown", 999, 1, true, 100)
eq(m2, 200, "chained"); eq(h2, 3, "health cost from a handler")
eq(E.remove("cost", "test_double"), true); E.remove("cost", "test_broken")
eq(E.onSpellPreCast(caster, "x", 1, 1, true, 10, 0), true, "no pre-cast handler: go on")
E.set("precast", "test_no", function() return false end)
eq(E.onSpellPreCast(caster, "x", 1, 1, true, 10, 0), false, "a handler can cancel")
E.remove("precast", "test_no")
eq(E.discount(200, 12), 176); eq(E.shorten(10000, 9, 1000), 9100)
for i = 1, 3 do S.setRune(caster, 201, i, 0) end
W.spellsByScript = realList


-- ---------------------------------------------------------------- the scripts side (supports.lua)
dofile("data/scripts/chaos/supports.lua")
eq(actions, 100, "one use action per rune")
local catalog = {
	[201] = {id = 201, name = "Witchfire Bolt", words = "kah pyr vesh", level = 30, kind = "single", element = "fire",
		vocations = {[1] = true}, mana = 70, cooldown = 4000},
	[206] = {id = 206, name = "Doomtide", words = "drai zhul infr doma", level = 300, kind = "area", vocations = {[5] = true},
		mana = 1500, cooldown = 45000},
	[208] = {id = 208, name = "Purifying Wellspring", words = "saen vas aquen", level = 40, kind = "heal",
		vocations = {[1] = true}, mana = 160, cooldown = 6000},
}
S.catalog = function() return catalog end
local hit = registered.ChaosSupportsHit.onHealthChange
ok(hit, "hit event")

local me = newCreature({player = true, level = 100, voc = 1, pos = {x = 50, y = 50, z = 7}, health = 2000,
	maxHealth = 2000, maxMana = 1000, mana = 0, bank = 0, gold = 0})
registered.ChaosSupportsLogin.onLogin(me)
ok(me.events.ChaosSupportsHit, "hit event on the player")
-- socketing
local brand = S.runeId(S.byKey.emberbrand.index, 3) -- 40%
me.items[brand] = 1
local okS, text = S.socket(me, 201, brand)
ok(okS, text)
eq(me.items[brand], 0, "the rune is used")
eq(S.read(me, 201).runes[1], brand, "stored in socket 1")
ok(text:find("Epic Emberbrand Rune socketed into Witchfire Bolt %(socket 1%)"), text)
me.items[brand] = 1
eq(select(2, S.socket(me, 201, brand)), string.format(S.reasons.same, "Emberbrand"), "one of a kind")
eq(select(2, S.socket(me, 206, brand)), S.reasons.noSpell, "not in the class kit")
me.items[mercy] = 1
ok(select(2, S.socket(me, 201, mercy)):find("does not fit"), "mercy does not fit a bolt")
local keen = S.runeId(S.byKey.keenedge.index, 5) -- 8%, +50%
me.items[keen] = 1
ok(S.socket(me, 201, keen), "keen edge into socket 2 (level 100 >= 90)")
local hexR = S.runeId(S.byKey.hex.index, 5) -- 8%
me.items[hexR] = 1
eq(select(2, S.socket(me, 201, hexR)), S.reasons.full, "two sockets at level 100")
ok(select(2, S.unlock(me, 201)):find("needs level 200"), "third socket needs level 200")
me.level = 200
ok(select(2, S.unlock(me, 201)):find("takes 2"), "third socket needs orbs")
me.items[ChaosGems.config.socketOrb.id] = 2
ok(S.unlock(me, 201), "third socket opened")
eq(me.items[ChaosGems.config.socketOrb.id], 0, "orbs used")
eq(select(2, S.unlock(me, 201)), S.reasons.opened, "only once")
ok(S.socket(me, 201, hexR), "hex into socket 3")
ok(registered.targetCombat, "target callback")

-- a hit of the spell: brand 40% fire, monster resists fire 50%: 100 phys -> 60 phys + 20 fire
local demon = newCreature({pos = {x = 52, y = 50, z = 7}, health = 5000, res = {[COMBAT_FIREDAMAGE] = 50}})
registered.targetCombat(me, demon)
ok(demon.events and demon.events.ChaosSupportsHit, "event on the target of a player with runes")
S.random = function(a, b) return b end -- no Keen Edge
me.storage[cfg.storageContext] = S.ctxEncode(5, 201)
local a, at, b, bt = hit(demon, me, 100, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_SPELL)
eq(a, 60, "physical part"); eq(b, 20, "fire part after the fire resistance"); eq(bt, COMBAT_FIREDAMAGE, "fire")
-- the hit hexed the demon: +8% from anyone (also without a context)
me.storage[cfg.storageContext] = nil
local other = newCreature({player = true, level = 50, pos = {x = 53, y = 50, z = 7}, health = 100})
eq((hit(demon, other, 100, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE)), 108, "hexed: +8% from everyone")
-- no context: no brand
eq((hit(demon, me, 100, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE)), 108, "weapon hit: only the hex")
-- Keen Edge crits
S.random = function(a, b) return a end
me.storage[cfg.storageContext] = S.ctxEncode(6, 201)
a, at, b = hit(demon, me, 100, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_SPELL)
-- hex first (108), brand 40% (43 moved, 21 after the fire resistance), then the crit +50%
eq(a, 97, "crit on the physical part"); eq(b, 31, "crit on the fire part")
me.storage[cfg.storageContext] = nil
flushEvents()

-- the extra hits: fork / shatter on a single target spell (swap the runes)
for i = 1, 3 do S.setRune(me, 201, i, 0) end
S.setRune(me, 201, 1, S.runeId(S.byKey.fork.index, 5)) -- 3 targets, 55%
S.setRune(me, 201, 2, S.runeId(S.byKey.shatter.index, 5)) -- 40%
S.setRune(me, 201, 3, S.runeId(S.byKey.bloodthirst.index, 5)) -- 6%
S.refreshActive(me)
local t1 = newCreature({pos = {x = 60, y = 60, z = 7}, health = 1000})
local n1 = newCreature({pos = {x = 61, y = 60, z = 7}, health = 1000}) -- next to t1
local n2 = newCreature({pos = {x = 63, y = 60, z = 7}, health = 1000}) -- 3 sqm
local far = newCreature({pos = {x = 70, y = 60, z = 7}, health = 1000})
hits = {}
me.health = 1000
me.storage[cfg.storageContext] = S.ctxEncode(7, 201)
hit(t1, me, 200, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_SPELL)
me.storage[cfg.storageContext] = nil
flushEvents()
local byTarget = {}
for _, h in ipairs(hits) do
	byTarget[h.target.id] = (byTarget[h.target.id] or 0) + h.amount
end
eq(byTarget[n1.id], -110, "fork 55% to the neighbour")
eq(byTarget[n2.id], -110, "fork 55% to the one 3 sqm away")
eq(byTarget[far.id], nil, "nothing to the far one")
eq(byTarget[demon.id], nil, "the demon is too far")
eq(byTarget[me.id], 12, "bloodthirst 6% of 200")

-- area spell at level 300: Breadth, Deathburst, Echo
catalog[206].vocations[1] = true
me.level = 460
local echoR = S.runeId(S.byKey.echo.index, 5) -- 35%, 50%
for _, r in ipairs({S.runeId(S.byKey.breadth.index, 5), S.runeId(S.byKey.deathburst.index, 5), echoR}) do
	me.items[r] = 1
	ok(S.socket(me, 206, r) or true, "socket " .. r)
end
me.items[ChaosGems.config.socketOrb.id] = 2
ok(S.unlock(me, 206), "open the third socket of Doomtide")
ok(S.socket(me, 206, echoR), "echo into socket 3")
local x1 = newCreature({pos = {x = 80, y = 80, z = 7}, health = 50})
local x2 = newCreature({pos = {x = 81, y = 80, z = 7}, health = 1000})
local x3 = newCreature({pos = {x = 83, y = 80, z = 7}, health = 1000}) -- 2 sqm from x2, missed
hits = {}
S.random = function(a, b) return a end -- echo procs
me.storage[cfg.storageContext] = S.ctxEncode(8, 206)
hit(x1, me, 100, COMBAT_FIREDAMAGE, 0, 0, ORIGIN_SPELL) -- kills x1 (50 health)
x1.health = 0
hit(x2, me, 300, COMBAT_FIREDAMAGE, 0, 0, ORIGIN_SPELL)
me.storage[cfg.storageContext] = nil
flushEvents()
byTarget = {}
for _, h in ipairs(hits) do
	byTarget[h.target.id] = (byTarget[h.target.id] or 0) + h.amount
end
-- breadth: 2 sqm (level 5), 55% of the average 200 = 110 to x3; deathburst 50% of 100 = 50 to x2 (2 sqm of x1);
-- echo: x2 again for 50% of 300 = 150 (x1 is dead)
eq(byTarget[x3.id], -110, "breadth to the missed one")
eq(byTarget[x2.id], -50 - 150, "deathburst + echo on x2")
eq(byTarget[x1.id], nil, "nothing on the dead one")

-- Mercy on a heal
me.items[mercy] = 1
me.level = 400
ok(S.socket(me, 208, mercy), "mercy into the heal")
me.storage[cfg.storageContext] = S.ctxEncode(9, 208)
eq((hit(me, me, 100, COMBAT_HEALING, 0, 0, ORIGIN_SPELL)), 105, "mercy +5%")
me.storage[cfg.storageContext] = nil
eq((hit(me, me, 100, COMBAT_HEALING, 0, 0, ORIGIN_SPELL)), 100, "a heal of another source")

-- Reprisal: hit taken within the window strikes back
S.setRune(me, 208, 2, 0)
local repr = S.runeId(S.byKey.reprisal.index, 5) -- 100%
me.items[repr] = 1
ok(S.socket(me, 208, repr), "reprisal into the heal")
me.storage[cfg.storageReprisal] = 208
me.storage[cfg.storageReprisalUntil] = os.time() + 5
local biter = newCreature({pos = {x = 51, y = 50, z = 7}, health = 1000})
hits = {}
S.random = function(a, b) return a end
hit(me, biter, 200, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE)
flushEvents()
eq(#hits, 1, "struck back once"); eq(hits[1].target, biter, "at the attacker"); eq(hits[1].amount, -200, "100% of 200")
hit(me, biter, 200, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_MELEE)
flushEvents()
eq(#hits, 1, "internal cooldown")

-- removing: keep for gold, shatter for free
local sockNow = S.read(me, 208)
eq(sockNow.runes[1], mercy, "mercy in socket 1")
local okR, why = S.unsocket(me, 208, 1, true)
ok(not okR and why:find("2000 gold"), "removal costs gold")
me.bank = 5000
ok(S.unsocket(me, 208, 1, true), "removed for gold")
eq(me.bank, 3000, "paid from the bank"); eq(me.items[mercy], 1, "the rune comes back")
ok(S.unsocket(me, 208, 2, false), "shattered")
eq(me.items[repr], 0, "a shattered rune is gone")
eq(select(2, S.unsocket(me, 208, 2, false)), S.reasons.empty, "nothing left")
-- combining
me.items[S.runeId(4, 2)] = 3
ok(S.combine(me, S.runeId(4, 2)), "three combine")
eq(me.items[S.runeId(4, 3)], 1, "one of the next level")
eq(select(2, S.combine(me, S.runeId(4, 2))), S.reasons.needThree, "needs three")
-- the window answer lists the class kit and the runes
me.sent = {}
local sentState = false
json.encode = function(t)
	if t.action == "state" then
		sentState = t.data
	end
	return "{}"
end
S.sendState(me)
ok(sentState and #sentState.spells == 3, "three spells in the window")
eq(sentState.spells[1].id, 201, "sorted by level")
eq(sentState.spells[1].count, 3, "three sockets on the bolt")
ok(#sentState.runes >= 2, "carried runes")
-- a big answer goes out in parts of at most 6000 bytes, one per tick
local big = string.rep("x", 13000)
json.encode = function(t) return t.action == "part" and ("P" .. t.data.index .. "/" .. t.data.total .. ":" .. #t.data.text) or big end
me.sent = {}
local sends = {}
Chaos.send = function(p, op, action, data) sends[#sends + 1] = data return true end
S.sendBig(me, "state", {})
flushEvents()
eq(#sends, 3, "three parts"); eq(sends[1].total, 3, "total"); eq(#sends[1].text, 6000, "first part")
eq(#sends[3].text, 1000, "last part"); eq(sends[1].text .. sends[2].text .. sends[3].text, big, "joined again")
eq(#me.sent, 0, "nothing sent whole")

-- the loot hook
local corpseItems = {}
local corpse = {addItem = function(_, id, n) corpseItems[#corpseItems + 1] = id return true end}
local names = S.lootDrop(corpse, "boss", 400, 1000, function(a, b) return a end)
eq(#names, 1, "a boss with a huge rate drops a rune"); ok(S.isRune(corpseItems[1]), "into the corpse")

print(string.format("supports_test: %d checks OK", checks))
