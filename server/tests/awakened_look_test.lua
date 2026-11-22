-- Run from the server/ folder: luajit tests/awakened_look_test.lua && lua5.3 tests/awakened_look_test.lua (CI runs both)
-- O711: an awakened spell sends the awakened look kit when chaosClientPair >= 76 (data/lib/chaos_awakened_look.lua, the rules in
-- data/scripts/chaos/awakened_look_config.lua, the kit data/lib/chaos_awakened_fx.lua). On a mocked engine with the real Vfx / VfxShoot of
-- chaos_vfx.lua, the real Combat wrapper of chaos_spell_forms.lua and the real awakening state (bit 9 of the packed state):
--   * the element rule and the shape rule (one place each), every shape of awakened.csv mapped, a Form's conversion takes the new element;
--   * at pair 76 every send of an awakened cast is the kit: the effect ONCE a cast on the anchor tile, every projectile the kit projectile,
--     the combat's own area effect off, the doAreaCombat tile effect off, a line / wave that does not face east a single on the target;
--   * at pair 75, for a spell that is not awakened, with the awakening off, or when the lookup answers nil, the sent effect list is the list
--     of a run without the look lib, byte for byte (the same cast, serialised and compared);
--   * PvP is no gate: the look is cosmetic (README "Awakened spell looks (O711)").

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

-- ---------------------------------------------------------------- a small engine
local sent = {}
local PosMeta = {}
PosMeta.__index = PosMeta
function PosMeta:sendMagicEffect(id)
	sent[#sent + 1] = "ME " .. id .. " " .. self.x .. "," .. self.y .. "," .. self.z
end
function PosMeta:sendDistanceEffect(to, id)
	sent[#sent + 1] = "ANI " .. id .. " " .. self.x .. "," .. self.y .. " -> " .. to.x .. "," .. to.y
end
function Position(x, y, z)
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
	return setmetatable({x = x, y = y, z = z}, PosMeta)
end
local function take()
	local out = table.concat(sent, "\n")
	sent = {}
	return out
end

EAST, SOUTH = 1, 2
COMBAT_PARAM_EFFECT, COMBAT_PARAM_DISTANCEEFFECT, CONST_ME_NONE = 1, 2, 0

local storage = {}
local direction = EAST
local PID = 77
local player = {}
function player:getId() return PID end
function player:getPosition() return Position(100, 100, 7) end
function player:getDirection() return direction end
function player:getStorageValue(k) return storage[k] or -1 end
function Player(id) if id == PID then return player end return nil end
local target = {}
function target:getPosition() return Position(105, 100, 7) end
function Creature(id) if id == 5 then return target end return nil end

-- the cast context of data/spells/chaos/_supports.lua: player, spell, and a serial that tells casts apart
local castSpell, serial = nil, 1
ChaosSupportsSpell = {
	cast = function() if castSpell then return PID, castSpell end return nil end,
	context = function() if castSpell then return {pid = PID, spell = castSpell, value = serial * 1000 + castSpell} end return nil end,
}

dofile("data/lib/chaos_vfx.lua")
ChaosAreaFx = false -- the area swap of O607 is not under test here

-- the real Forms lib (the Combat wrapper) on a fake Combat, and the real awakening state
ChaosSpellRanksConfig = dofile("data/scripts/chaos/spell_ranks_config.lua")
ChaosSpellRanksConfig.enabled = true
dofile("data/scripts/chaos/spell_ranks_core.lua")
local P = ChaosSpellRanksCore
local RC = ChaosSpellRanksConfig
dofile("data/lib/chaos_spell_forms.lua")
dofile("data/lib/chaos_spell_awakening.lua")
local AW = ChaosSpellAwakening
local FM = ChaosSpellForms
local rows = AW.table()
ok(next(rows) ~= nil, "awakened.csv is read")

local seenParams = {}
local FakeCombat = {setParameter = function(self, key, value) self.p = self.p or {}; self.p[key] = value end,
	execute = function(self, creature, variant)
		seenParams[#seenParams + 1] = {effect = self.p and self.p[COMBAT_PARAM_EFFECT], ani = self.p and self.p[COMBAT_PARAM_DISTANCEEFFECT]}
		return true
	end}
Combat = FakeCombat
FM.combatInstalled = false
ok(FM.installCombat(), "the Combat wrapper is installed")
local function newCombat(effect, ani)
	local c = setmetatable({}, {__index = FakeCombat})
	c:setParameter(COMBAT_PARAM_EFFECT, effect)
	if ani then
		c:setParameter(COMBAT_PARAM_DISTANCEEFFECT, ani)
	end
	return c
end

local areaCalls = {}
function doAreaCombat(cid, ctype, pos, area, min, max, effect, origin)
	areaCalls[#areaCalls + 1] = {effect = effect, origin = origin}
	return true
end
local rawArea = doAreaCombat -- the engine's own, to run the baseline (no look lib) cast

dofile("data/lib/chaos_awakened_fx.lua")
dofile("data/lib/chaos_awakened_look.lua")
local L = ChaosAwakenedLook
local FX = ChaosAwakenedFx
local cfg = ChaosAwakenedLookConfig
ok(L and FX and cfg, "the look lib, the kit and the config are loaded")
ok(L.installLegacy(), "doAreaCombat is wrapped")
ok(not L.installLegacy(), "once")
local look = L

-- an awakened spell: rank 20, both Forms, bit 9
local function awaken(id, on)
	storage[RC.storage.rankBase + id] = on == false and P.pack(20, 1, 1, false) or P.pack(20, 1, 1, true)
end
local function pick(shape, withElement)
	local ids = {}
	for id, r in pairs(rows) do
		if r.shape == shape and ((r.element ~= nil) == withElement) then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	return ids[1]
end

-- ---------------------------------------------------------------- 1. the rules
eq(look.element("fire", nil), "fire", "an element of the kit")
eq(look.element(nil, nil), "arcane", "no element: the arcane kit")
eq(look.element("fire", "ice"), "ice", "a conversion Form shows the new element")
eq(look.element(nil, "death"), "death", "a conversion on a spell with no element")
eq(look.element("plasma", nil), "arcane", "an element the kit lacks: the arcane kit")
eq(cfg.fallbackElement, "arcane", "the fallback is the eighth kit element")
for _, el in ipairs({"fire", "ice", "energy", "earth", "death", "holy", "physical", "arcane"}) do
	eq(look.element(el, nil), el, "the kit element " .. el)
end
eq(look.shape("single", true), "single", "single")
eq(look.shape("circle", false), "circle", "circle")
eq(look.shape("around", false), "around", "around")
eq(look.shape("self", true), "around", "a self spell: the ring round the caster")
eq(look.shape("line", true), "line", "a line facing east")
eq(look.shape("wave", true), "wave", "a wave facing east")
eq(look.shape("line", false), "single", "a line not facing east: a single on the target")
eq(look.shape("wave", false), "single", "a wave not facing east: a single on the target")
eq(look.shape("zigzag", true), "single", "an unknown shape")
-- every shape of awakened.csv has a kit shape the kit really has
local shapes = {}
for _, r in pairs(rows) do
	shapes[r.shape] = true
end
for s in pairs(shapes) do
	local k = cfg.shape[s]
	ok(k ~= nil, "awakened.csv shape " .. s .. " is in the shape table")
	local known = false
	for _, ks in ipairs(FX.SHAPES) do
		known = known or ks == k
	end
	ok(known, "the kit has the shape " .. tostring(k))
end
for s, a in pairs(cfg.anchor) do
	ok(a == "target" or a == "caster", "anchor of " .. s)
end

-- ---------------------------------------------------------------- 2. one scripted cast, recorded
-- the cast of a spell: three named effects (an area of tiles), two projectiles, a combat with an area effect and a projectile, a legacy area
local function script(variantPos, baseline)
	local c = newCombat(12, 5)
	Vfx(Position(105, 100, 7), "ember_crown")
	Vfx(Position(106, 101, 7), "ember_crown")
	Vfx(Position(104, 99, 7), "frost_bastion")
	VfxShoot(Position(100, 100, 7), Position(105, 100, 7), "fireball")
	VfxShoot(Position(100, 100, 7), Position(107, 100, 7), "arcane_bolt")
	c:execute(player, {pos = variantPos or Position(105, 100, 7)})
	local area = baseline and rawArea or doAreaCombat
	area(PID, 1, Position(105, 100, 7), {}, -10, -20, 38, 3)
	return take(), seenParams[#seenParams], areaCalls[#areaCalls]
end
local function cast(spellId, baseline)
	serial = serial + 1
	castSpell = spellId
	seenParams, areaCalls = {}, {}
	local out, params, area = script(nil, baseline)
	castSpell = nil
	return out, params, area
end

local SINGLE_ID = pick("single", true)
local SPELL = SINGLE_ID
ok(SPELL ~= nil, "a single target spell with an element")
awaken(SPELL)

-- the baseline: the look lib is not there at all (today's engine)
local saveLook = ChaosAwakenedLook
ChaosAwakenedLook = nil
FX.on = true
local base, baseParams, baseArea = cast(SPELL, true)
ChaosAwakenedLook = saveLook
ok(#base > 0, "the baseline cast sends effects")
eq(baseParams.effect, 12, "baseline: the combat's own effect")
eq(baseParams.ani, 5, "baseline: the combat's own projectile")
eq(baseArea.effect, 38, "baseline: the doAreaCombat tile effect")

-- pair 75 and below: the gate is off, the cast is the baseline byte for byte
for _, pair in ipairs({0, 73, 75}) do
	FX.on = pair >= FX.PAIR
	local out, params, area = cast(SPELL)
	eq(out, base, "pair " .. pair .. ": the sent effects are the baseline, byte for byte")
	eq(params.effect, 12, "pair " .. pair .. ": the combat effect")
	eq(params.ani, 5, "pair " .. pair .. ": the combat projectile")
	eq(area.effect, 38, "pair " .. pair .. ": the tile effect")
end

-- pair 76, but the spell is not awakened / the awakening is off / the lookup answers nil
FX.on = true
awaken(SPELL, false)
eq((cast(SPELL)), base, "not awakened: the baseline")
awaken(SPELL)
ChaosSpellRanksConfig.enabled = false
eq((cast(SPELL)), base, "the spell upgrades off: the baseline")
ChaosSpellRanksConfig.enabled = true
local savedEffect, savedMissile = FX.effect, FX.missile
FX.effect = function() return nil end
eq((cast(SPELL)), base, "the lookup answers nil: the baseline")
FX.effect = savedEffect
eq((cast(SPELL)), (cast(SPELL)), "a cast is the same cast twice")
castSpell = nil
Vfx(Position(105, 100, 7), "ember_crown")
local outside = take()
FX.on = false
Vfx(Position(105, 100, 7), "ember_crown")
eq(outside, take(), "outside any cast: the same effect at pair 76 and below")
FX.on = true

-- ---------------------------------------------------------------- 3. pair 76: the kit
local function kitOf(spellId, facing)
	direction = facing or EAST
	local r = rows[spellId]
	castSpell = spellId -- the picks of the test (Form I 1, Form II 1) may convert the element: the real Forms lib says so
	local conv = FM.castConversion(player)
	castSpell = nil
	local el = look.element(r.element, conv)
	local sh = look.shape(r.shape, direction == EAST)
	return FX.effect(el, sh), FX.missile(el), el, sh
end
local function anchor(shape, e)
	if cfg.anchor[shape] == "caster" then
		return (100 + e.dx) .. "," .. (100 + e.dy) .. ",7"
	end
	return nil
end

local function expectedKit(spellId, facing)
	local e, m = kitOf(spellId, facing)
	return e, m
end

direction = EAST
do
	local e, m, el, sh = kitOf(SPELL)
	ok(e and m, "the kit has the effect and the projectile of the single spell")
	local out, params, area = cast(SPELL)
	local lines = {}
	for l in out:gmatch("[^\n]+") do
		lines[#lines + 1] = l
	end
	-- the effect once: the first named send (target tile 105,100) at its kit offset; the later sends of the cast send nothing
	local expectEffects = 0
	for _, l in ipairs(lines) do
		if l:sub(1, 2) == "ME" then
			expectEffects = expectEffects + 1
		end
	end
	eq(expectEffects, 1, "the kit effect goes out once a cast, not once a tile")
	ok(lines[1] == "ME " .. e.id .. " " .. (105 + e.dx) .. "," .. (100 + e.dy) .. ",7", "the kit effect on the target tile at its send offset: " .. tostring(lines[1]))
	eq(lines[2], "ANI " .. m.id .. " 100,100 -> 105,100", "every projectile is the kit projectile: the first")
	eq(lines[3], "ANI " .. m.id .. " 100,100 -> 107,100", "every projectile is the kit projectile: the second")
	eq(#lines, 3, "nothing else is sent")
	eq(params.effect, CONST_ME_NONE, "the combat's own area effect is off while the kit plays")
	eq(params.ani, m.id, "the combat's projectile is the kit projectile")
	eq(area.effect, CONST_ME_NONE, "the doAreaCombat tile effect is off")
	eq(area.origin, 3, "the other arguments of doAreaCombat pass through")
end

-- the parameters of the combat are given back after the cast
do
	castSpell, serial = SPELL, serial + 1
	local c = newCombat(12, 5)
	c:execute(player, {pos = Position(105, 100, 7)})
	eq(c.p[COMBAT_PARAM_EFFECT], 12, "the combat's effect is restored")
	eq(c.p[COMBAT_PARAM_DISTANCEEFFECT], 5, "the combat's projectile is restored")
	take()
	castSpell = nil
	-- a combat with no projectile gets none
	castSpell, serial = SPELL, serial + 1
	seenParams = {}
	newCombat(12, nil):execute(player, {pos = Position(105, 100, 7)})
	eq(seenParams[1].ani, nil, "a combat that sends no projectile sends none")
	take()
	castSpell = nil
end

-- every shape: the kit shape of awakened.csv, the anchor tile
for _, shape in ipairs({"single", "circle", "around", "line", "wave", "self"}) do
	local id = pick(shape, true) or pick(shape, false)
	ok(id ~= nil, "a spell of the shape " .. shape)
	if id then
		awaken(id)
		direction = EAST
		local e, _, el, sh = kitOf(id)
		ok(e ~= nil, shape .. ": the kit effect exists")
		castSpell, serial = id, serial + 1
		Vfx(Position(105, 100, 7), "ember_crown")
		castSpell = nil
		local expect = anchor(sh, e) and ("ME " .. e.id .. " " .. anchor(sh, e)) or ("ME " .. e.id .. " " .. (105 + e.dx) .. "," .. (100 + e.dy) .. ",7")
		eq(take(), expect, shape .. " (" .. el .. " " .. sh .. "): the kit effect on its anchor")
	end
end

-- every element and the arcane fallback: the spell's element picks the kit
for _, c in ipairs({{"fire", "fire"}, {"ice", "ice"}, {"death", "death"}, {"holy", "holy"}, {"physical", "physical"}}) do
	local found
	for id, r in pairs(rows) do
		if r.element == c[1] then
			found = id
			break
		end
	end
	if found then
		awaken(found)
		direction = EAST
		local e, _, el = kitOf(found)
		eq(el, c[2], "the kit element of a " .. c[1] .. " spell")
		castSpell, serial = found, serial + 1
		Vfx(Position(105, 100, 7), "ember_crown")
		castSpell = nil
		local out = take()
		ok(out:find("ME " .. e.id .. " ", 1, true) ~= nil, "a " .. c[1] .. " spell sends its kit effect " .. e.id)
	end
end
do
	local id = pick("single", false)
	awaken(id)
	local e, _, el = kitOf(id)
	eq(el, "arcane", "a spell with no element of its own takes the arcane kit")
	eq(rows[id].element, nil, "(the row has no element)")
end

-- a line or a wave that does not face east: a single on the target
do
	local id = pick("line", true)
	awaken(id)
	local e, _, el, sh = kitOf(id, SOUTH)
	eq(sh, "single", "a line facing south takes the single")
	castSpell, serial = id, serial + 1
	Vfx(Position(105, 100, 7), "ember_crown")
	castSpell = nil
	eq(take(), "ME " .. e.id .. " " .. (105 + e.dx) .. "," .. (100 + e.dy) .. ",7", "the single on the target tile")
	direction = EAST
end

-- a Form that converts the element: the kit of the new element
do
	local id = pick("circle", true)
	awaken(id)
	direction = EAST
	local fireOrOther = rows[id].element
	local newEl = fireOrOther == "ice" and "fire" or "ice"
	local saveConv = FM.castConversion
	FM.castConversion = function() return newEl end
	local e = FX.effect(newEl, "circle")
	castSpell, serial = id, serial + 1
	Vfx(Position(105, 100, 7), "ember_crown")
	castSpell = nil
	eq(take(), "ME " .. e.id .. " " .. (105 + e.dx) .. "," .. (100 + e.dy) .. ",7", "a conversion Form: the kit of " .. newEl .. ", not of " .. tostring(fireOrOther))
	FM.castConversion = function() return "plasma" end
	castSpell, serial = id, serial + 1
	Vfx(Position(105, 100, 7), "ember_crown")
	castSpell = nil
	local arc = FX.effect("arcane", "circle")
	eq(take(), "ME " .. arc.id .. " " .. (105 + arc.dx) .. "," .. (100 + arc.dy) .. ",7", "a conversion to an element the kit lacks: arcane")
	FM.castConversion = saveConv
end

-- a new cast plays the kit again, the same cast once
do
	local id = SPELL
	awaken(id)
	local e = kitOf(id)
	castSpell, serial = id, serial + 1
	Vfx(Position(105, 100, 7), "ember_crown")
	Vfx(Position(105, 100, 7), "ember_crown")
	eq(select(2, take():gsub("ME", "")), 1, "the same cast: once")
	serial = serial + 1
	Vfx(Position(105, 100, 7), "ember_crown")
	eq(select(2, take():gsub("ME", "")), 1, "the next cast: once again")
	castSpell = nil
end

-- the effects of the Forms and the signature (raw sends) are not touched
do
	castSpell, serial = SPELL, serial + 1
	Vfx(Position(105, 100, 7), "ember_crown", true)
	local out = take()
	eq(out, "ME " .. ChaosVfx.ember_crown.id .. " " .. (105 + ChaosVfx.ember_crown.dx) .. "," .. (100 + ChaosVfx.ember_crown.dy) .. ",7", "Vfx(pos, name, true) is untouched in an awakened cast")
	castSpell = nil
end

-- ---------------------------------------------------------------- 4. PvP is no gate, the lib asks no PvP rule
do
	local f = assert(io.open("data/lib/chaos_awakened_look.lua", "r"))
	local text = f:read("*a")
	f:close()
	ok(not text:find("[Pp][Vv][Pp]%s*[=%(]") and not text:find("isPvp") and not text:find("pvp%."), "the look lib reads no PvP state")
end

print(string.format("awakened_look_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
