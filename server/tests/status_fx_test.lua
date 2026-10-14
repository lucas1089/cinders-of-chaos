-- Run from the server/ folder: luajit tests/status_fx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Status words (data/lib/chaos_status_fx.lua): the switch is one plain line, off until a pair with effects 656-673 is
-- published; every word the server sends is in the client spec (art_import/status_fx.csv) and in the generated ids
-- (chaos_status_fx_ids.lua, status_fx_catalog.csv) at the same id; every spell of the map exists in spells_chaos.xml
-- under that name; every use is sent by a call site; off, a call sends exactly the stock effect (or nothing); on, the
-- word at its offset tile, one per creature in targetMs and perCast creatures per cast.
local failures = 0
local function ok(c, msg)
	if not c then
		failures = failures + 1
		print("FAIL " .. msg)
	end
end
local function eq(a, b, msg)
	ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function readFile(p)
	local f = io.open(p, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- engine mocks: effects and Vfx calls are recorded
local effects, vfxSent = {}, {}
local PosMT = {}
PosMT.__index = PosMT
function PosMT:sendMagicEffect(id) effects[#effects + 1] = {id = id, x = self.x, y = self.y} end
Position = function(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	return setmetatable({x = x, y = y, z = z}, PosMT)
end
local function reset() effects, vfxSent = {}, {} end
local clock = 100000
ORIGIN_CONDITION = 1
os.mtime = function() return clock end

dofile("data/lib/chaos_status_fx.lua")
local C = ChaosStatusFx

-- the switch: one plain line, off
local src = readFile("data/lib/chaos_status_fx.lua") or ""
eq(src:match("\nC%.STATUS_FX = (%a+)\n"), "false", "the switch is one plain line, off until the pair is published")

-- the client spec and the generated ids agree, in spec order from 656
local spec, order = {}, {}
for line in (readFile("../client/tools/sprites/art_import/status_fx.csv") or ""):gmatch("[^\n]+") do
	local name, w, h, dx, dy, alpha = line:match("^effect,([%w_]+),[^,]+,(%d+),(%d+),%d+,%d+,(%d+),(%d+),(%a+),")
	if name then
		spec[name] = {w = tonumber(w), h = tonumber(h), dx = tonumber(dx), dy = tonumber(dy), alpha = alpha}
		order[#order + 1] = name
	end
end
eq(#order, 18, "18 words in the client spec")
local ids = {}
for name, id, dx, dy in (readFile("data/lib/chaos_status_fx_ids.lua") or ""):gmatch("ChaosVfx%.([%w_]+) = {id = (%d+), dx = (%d+), dy = (%d+)") do
	ids[name] = {id = tonumber(id), dx = tonumber(dx), dy = tonumber(dy)}
end
local catalog = {}
for line in (readFile("data/spells/status_fx_catalog.csv") or ""):gmatch("[^\n]+") do
	local id, name = line:match("^effect,(%d+),([%w_]+),")
	if id then catalog[name] = tonumber(id) end
end
for i, name in ipairs(order) do
	local s, d = spec[name], ids[name]
	ok(d ~= nil, name .. ": in chaos_status_fx_ids.lua")
	if d then
		eq(d.id, 655 + i, name .. ": id in spec order after the large effects (655)")
		eq(d.dx .. "," .. d.dy, s.dx .. "," .. s.dy, name .. ": send offset of the spec")
	end
	eq(catalog[name], 655 + i, name .. ": catalog id")
	eq(s.w .. "x" .. s.h .. " " .. s.alpha, "3x3 soft", name .. ": 3x3, soft alpha")
end
eq(#C.words, #order, "C.words lists every word")
for i, name in ipairs(C.words) do
	eq(name, order[i], "C.words in spec order " .. i)
end

-- every spell of the map is a Chaos spell of that id, and its word is in the pair
local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
local spellName = {}
for id, name in xml:gmatch('spellid="(%d+)" name="([^"]+)"') do
	spellName[tonumber(id)] = name
end
local mapped = 0
for id, word in pairs(C.spells) do
	mapped = mapped + 1
	ok(spellName[id] ~= nil, "spell " .. id .. " exists in spells_chaos.xml")
	ok(spec[word] ~= nil, "spell " .. id .. ": word " .. word .. " is in the spec")
	local comment = src:match("%[" .. id .. "%] = \"[%w_]+\",%s*%-%- ([^\n]+)")
	eq(comment, spellName[id], "spell " .. id .. ": the comment names the spell")
end
ok(mapped >= 10, "spells mapped")
eq(C.wordOfSpell(205), "word_frozen", "Frozen Crypt freezes")
eq(C.wordOfSpell(1), nil, "a spell without a word")

-- every use names a word of the spec and has a call site; every call site's use exists
local sites = {
	stun = "data/spells/chaos/ironsage/iron_palm.lua",
	lay_on_hands = "data/spells/chaos/sentinel/lay_on_hands.lua",
	rift_revive = "data/scripts/chaos/rift.lua",
	channel_oblivion = "data/scripts/chaos/boss_mechanics.lua",
}
for use, word in pairs(C.uses) do
	ok(spec[word] ~= nil, "use " .. use .. ": word in the spec")
	local file = sites[use]
	ok(file ~= nil, "use " .. use .. ": a call site is listed here")
	local text = file and readFile(file) or ""
	if use:match("^channel_") then
		ok(text:find('ChaosStatusFx.send(boss:getPosition(), "channel_" .. tostring(ch.spec.key)', 1, true) ~= nil,
			use .. ": boss_mechanics.lua sends channel_<key>")
		ok((readFile("data/scripts/chaos/boss_mechanics_config.lua") or ""):find('key = "' .. use:sub(9) .. '", label = "[^"]+", kind = "channel"') ~= nil,
			use .. ": a channel mechanic of that key")
	else
		ok(text:find('ChaosStatusFx.send(', 1, true) and text:find('"' .. use .. '"', 1, true), use .. ": sent by " .. tostring(file))
	end
end
ok((readFile("data/scripts/chaos/combat_fx.lua") or ""):find("ChaosStatusFx.onSpellHit(creature, attacker, origin)", 1, true) ~= nil,
	"combat_fx.lua passes spell hits on")

-- ---------------------------------------------------------------- off: the stock effect only
C.STATUS_FX = false
reset()
eq(C.send(Position(10, 10, 7), "rift_revive", 11, 1), false, "off: no word")
eq(#effects, 1, "off: the stock effect"); eq(effects[1] and effects[1].id, 11, "off: the call site's effect")
reset()
eq(C.send(Position(10, 10, 7), "stun", nil, 1), false, "off, no fallback")
eq(#effects, 0, "off, no fallback: nothing")

-- creature / player mocks for the spell path
local storage = {}
local function creature(id, x)
	return {getId = function() return id end, getPosition = function() return Position(x, 10, 7) end,
		isPlayer = function() return id < 100 end,
		getStorageValue = function(_, k) return storage[id .. ":" .. k] or -1 end}
end
local caster = creature(1, 5)
storage["1:" .. C.storageContext] = 42 * 1000 + 205 -- serial 42, Frozen Crypt
eq(C.onSpellHit(creature(500, 10), caster), false, "off: no word on a spell hit")

-- ---------------------------------------------------------------- on
C.STATUS_FX = true
ChaosVfx = {}
dofile("data/lib/chaos_status_fx_ids.lua")
function Vfx(pos, name)
	local e = ChaosVfx[name]
	if not e then return false end
	vfxSent[#vfxSent + 1] = {name = name, id = e.id, x = pos.x + e.dx, y = pos.y + e.dy}
	return true
end
C.loaded = nil
C.resetThrottle()
ok(C.live(), "on: live with the ids")
reset()
eq(C.send(Position(10, 10, 7), "rift_revive", 11, 1), true, "on: the word")
eq(#effects, 0, "on: no stock effect")
eq(vfxSent[1] and vfxSent[1].name, "word_revived_rise", "on: rift revive word")
eq(vfxSent[1] and vfxSent[1].x .. "," .. vfxSent[1].y, "11,11", "on: at the target + (1, 1)")
reset()
eq(C.send(Position(10, 10, 7), "rift_revive", 11, 1), false, "throttled on the same creature")
eq(#effects, 1, "throttled: the stock effect instead")
clock = clock + C.targetMs
reset()
eq(C.send(Position(10, 10, 7), "rift_revive", 11, 1), true, "after targetMs: the word again")
reset()
eq(C.send(Position(10, 10, 7), "nothing_such", 11), false, "unknown use: stock")
eq(#effects, 1, "unknown use: the stock effect")

-- spell hits: the word of the cast's spell, perCast creatures per cast, one per creature
C.resetThrottle()
reset()
local hits = 0
for i = 1, 6 do
	if C.onSpellHit(creature(500 + i, 10 + i), caster) then hits = hits + 1 end
end
eq(hits, C.perCast, "an area cast shows perCast words")
eq(vfxSent[1] and vfxSent[1].name, "word_frozen", "Frozen Crypt: FROZEN!")
storage["1:" .. C.storageContext] = 43 * 1000 + 205 -- the next cast
clock = clock + 100
eq(C.onSpellHit(creature(501, 11), caster), false, "the same creature again within targetMs")
eq(C.onSpellHit(creature(520, 30), caster), true, "a new cast, a new creature")
eq(C.onSpellHit(creature(521, 31), caster, ORIGIN_CONDITION), false, "damage over time (ORIGIN_CONDITION) shows no word")
storage["1:" .. C.storageContext] = -1
eq(C.onSpellHit(creature(530, 40), caster), false, "no cast running: no word")
storage["1:" .. C.storageContext] = 44 * 1000 + 3 -- a spell without a word
eq(C.onSpellHit(creature(531, 41), caster), false, "a spell without a word")
storage["1:" .. C.storageContext] = 45 * 1000 + 205
eq(C.onSpellHit(creature(532, 42), creature(600, 1)), false, "a monster's hit: no word")

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("status_fx_test: OK")
