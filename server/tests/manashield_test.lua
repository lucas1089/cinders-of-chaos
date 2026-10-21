-- Run from the server/ folder: luajit tests/manashield_test.lua (and lua5.3; CI runs both)
-- The classic Magic Shield (server/README.md "Magic Shield"; owner 2026-10-21): Ward of the Mind takes a hit from the
-- mana first and only the rest from the health, for the Mystic and Ranger lines only. Tests:
--   * the core (manashield_core.lua): the split, the classes, the providers, the rescale, the marks;
--   * the glue (manashield.lua) against a mocked engine that runs a hit the way combatChangeHealth does (the mana events
--     on the whole hit, the mana drained, the health events on the rest): a scaling system pays the same whether the
--     mana shield is up or not, no double scaling, side effects once, parity off;
--   * the class lists agree: manashield_config.lua, server/tools/patch_spell_cap.py CAP, add_vocations.py
--     LINE_STOCK_SPELLS and the client's spelldata.lua (ChaosCappedSpells, ChaosStockSpellLines).
local count, failures = 0, 0
local function eq(a, b, what)
	count = count + 1
	if a ~= b then
		failures = failures + 1
		print("FAIL " .. tostring(what) .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end

local CLOCK = 1000000
os.mtime = function() return CLOCK end -- luacheck: ignore

dofile("data/scripts/chaos/manashield_config.lua")
dofile("data/scripts/chaos/manashield_core.lua")
local S = ChaosManaShield

-- ------------------------------------------------------------------ the classic split
local m, h = S.split(100, 300)
eq(m, 100, "a hit the mana covers: all from the mana"); eq(h, 0, "nothing from the health")
m, h = S.split(500, 300)
eq(m, 300, "a bigger hit: the whole mana"); eq(h, 200, "the rest from the health")
m, h = S.split(80, 0)
eq(m, 0, "no mana: nothing from it"); eq(h, 80, "all from the health")
m, h = S.split(0, 50)
eq(m + h, 0, "no hit")

-- ------------------------------------------------------------------ the classes (docs/CLASSES.md ids)
for _, v in ipairs({1, 5, 10, 3, 7, 15}) do
	eq(S.allowed(v), true, "Mystic and Ranger lines: " .. v)
end
for _, v in ipairs({4, 8, 14, 11, 12, 13, 17, 18, 19, 20, 21, 22, 23, 24, 25, 0}) do
	eq(S.allowed(v), false, "no other class: " .. v)
end

-- ------------------------------------------------------------------ providers
S.providers = {}
S.provide("b_double", {hit = function(_, _, amount) return amount * 2 end})
S.provide("a_none", {hit = function() return nil end})
S.provide("c_error", {hit = function() error("boom") end})
S.provide("bad", {}) -- no hit function: ignored
eq(S.providers.bad, nil, "a provider needs a hit function")
local new, keys = S.apply(nil, nil, 150, {})
eq(new, 300, "x2"); eq(#keys, 1, "only the provider that applied"); eq(keys[1], "b_double", "its key")
eq(S.lastError ~= nil and S.lastError:find("c_error", 1, true) ~= nil, true, "an error is kept, the hit goes on")
local _, _, over = S.decide(nil, nil, 150, 300, {})
eq(over, false, "300 against 300 mana: the mana takes it all")
_, _, over = S.decide(nil, nil, 151, 300, {})
eq(over, true, "302 against 300 mana: the health events follow")

-- ------------------------------------------------------------------ rescale
local p, s = S.rescale(-60, -40, 100, 200)
eq(p, -120, "primary keeps its share and sign"); eq(s, -80, "secondary too")
p, s = S.rescale(70, 0, 70, 35)
eq(p, 35, "no secondary: the primary takes the whole"); eq(s, 0, "secondary stays 0")
p, s = S.rescale(-10, -5, 15, 0)
eq(p + s, 0, "to nothing")
p, s = S.rescale(-33, -33, 66, 100)
eq(math.abs(p) + math.abs(s), 100, "the sum is exact")

-- ------------------------------------------------------------------ marks
S.marks = {}
S.mark(7, 99, CLOCK, {"x", "y"})
eq(S.consume(7, "x", 98, CLOCK), false, "another attacker: not this hit")
S.mark(7, 99, CLOCK, {"x", "y"})
eq(S.consume(7, "z", 99, CLOCK), false, "a system that did not apply")
eq(S.consume(7, "x", 99, CLOCK), true, "x: scaled already")
eq(S.consume(7, "x", 99, CLOCK), false, "asked once per hit")
eq(S.consume(7, "y", 99, CLOCK + 3), true, "y, a few ms later in the same call")
eq(S.marks[7], nil, "every key consumed: gone")
S.mark(7, 99, CLOCK, {"x"})
eq(S.consume(7, "x", 99, CLOCK + 500), false, "a stale mark (its health events never came)")
eq(S.marks[7], nil, "and it is dropped")

-- ------------------------------------------------------------------ the glue against a mocked engine
COMBAT_HEALING, COMBAT_MANADRAIN, COMBAT_PHYSICALDAMAGE, CONDITION_MANASHIELD = 1, 2, 3, 4
ORIGIN_MELEE = 1
local registry = {}
function CreatureEvent(name)
	local e = {name = name}
	function e.register() registry[name] = e end
	return e
end
local function creature(id, player)
	local c = {id = id, mana = 0, health = 1000, conds = {}, events = {}}
	function c:getId() return self.id end
	function c:isPlayer() return player end
	function c:getMana() return self.mana end
	function c:hasCondition(t) return self.conds[t] == true end
	function c:registerEvent(n) self.events[#self.events + 1] = n end
	return c
end
Chaos = Chaos or {}
S.providers, S.marks = {}, {}
dofile("data/scripts/chaos/manashield.lua")

-- a system like the tiers: x2 on the monster's hits in its health event, a side effect per hit
local sideEffects = 0
local MULT = 2
S.provide("tiers", {
	hit = function(_, attacker, amount) return attacker.monster and math.floor(amount * MULT) or nil end,
	absorbed = function() sideEffects = sideEffects + 1 end
})
local function systemHealth(target, attacker, pd, pt, sd, st)
	if attacker.monster then
		if not S.scaled(target, attacker, "tiers") then
			pd, sd = math.floor(pd * MULT), math.floor(sd * MULT)
		end
		sideEffects = sideEffects + 1
	end
	return pd, pt, sd, st
end

-- combatChangeHealth (engine) for a damage hit: values positive here
local function engineHit(target, attacker, amount)
	local pd, pt, sd, st = amount, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE
	local fromMana = 0
	if target:isPlayer() and target:hasCondition(CONDITION_MANASHIELD) and math.min(target.mana, pd + sd) ~= 0 then
		for _, name in ipairs(target.events) do
			local ev = registry[name]
			if ev and ev.onManaChange then
				pd, pt, sd, st = ev.onManaChange(target, attacker, pd, pt, sd, st, ORIGIN_MELEE)
			end
		end
		local total = pd + sd
		if total == 0 then
			return 0, 0
		end
		fromMana = math.min(target.mana, total)
		target.mana = target.mana - fromMana
		pd = pd - fromMana
		if pd < 0 then
			sd, pd = math.max(0, sd + pd), 0
		end
	end
	if pd + sd == 0 then
		return fromMana, 0
	end
	pd, pt, sd, st = systemHealth(target, attacker, pd, pt, sd, st)
	target.health = target.health - (pd + sd)
	return fromMana, pd + sd
end

local hero = creature(1, true)
registry.Chaos1ManaShieldLogin.onLogin(hero)
eq(hero.events[1], "ChaosManaShieldMana", "login registers the mana event")
local monster = creature(50, false)
monster.monster = true
local friend = creature(2, true)

-- no shield: the system scales in its health event (the reference)
local fm, fh = engineHit(hero, monster, 100)
eq(fm, 0, "no shield: no mana"); eq(fh, 200, "no shield: x2 on the health")
eq(sideEffects, 1, "side effect once")

-- shield up, enough mana: the mana pays the scaled hit, no health event, the side effect still once
hero.conds[CONDITION_MANASHIELD] = true
hero.mana, sideEffects = 500, 0
fm, fh = engineHit(hero, monster, 100)
eq(fm, 200, "shield: the mana pays x2"); eq(fh, 0, "nothing from the health")
eq(sideEffects, 1, "the side effect ran once (absorbed)")
eq(next(S.marks), nil, "no mark when the mana took it all")

-- shield up, not enough mana: the mana pays what it has, the health the rest of the x2 hit, scaled once
hero.mana, hero.health, sideEffects = 150, 1000, 0
fm, fh = engineHit(hero, monster, 100)
eq(fm, 150, "the whole mana"); eq(fh, 50, "the health pays the rest of 200, not x2 again")
eq(fm + fh, 200, "the same 200 as without the shield")
eq(sideEffects, 1, "the side effect ran once (the health event)")
eq(next(S.marks), nil, "the mark was consumed")

-- no mana left: the engine skips the mana events, the system scales the health as usual
hero.mana = 0
fm, fh = engineHit(hero, monster, 100)
eq(fm, 0, "no mana"); eq(fh, 200, "x2 on the health")

-- what the glue leaves alone: another player's hit (no provider applies), healing, mana drain, no shield, self
hero.mana = 500
fm, fh = engineHit(hero, friend, 100)
eq(fm, 100, "PvP: the mana pays the hit as it is"); eq(fh, 0, "nothing more")
local r = registry.ChaosManaShieldMana.onManaChange
eq(r(hero, monster, 100, COMBAT_HEALING, 0, COMBAT_HEALING, 0), 100, "healing untouched")
eq(r(hero, monster, 100, COMBAT_MANADRAIN, 0, COMBAT_MANADRAIN, 0), 100, "mana drain untouched")
eq(r(hero, hero, 100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0), 100, "own hit untouched")
hero.conds[CONDITION_MANASHIELD] = nil
eq(r(hero, monster, 100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0), 100, "no shield: untouched")
hero.conds[CONDITION_MANASHIELD] = true

-- a replacement (the Trials: a hit becomes a share of the maximum health; 0 while shielded after a fall)
S.provide("tiers", {hit = function() return 0 end})
hero.mana = 500
fm, fh = engineHit(hero, monster, 100)
eq(fm + fh, 0, "a hit the system cancels takes no mana")
eq(hero.mana, 500, "mana kept")

-- parity off: the mana pays the hit as the engine hands it
S.cfg.parity = false
S.provide("tiers", {hit = function(_, _, amount) return amount * 2 end})
eq(r(hero, monster, 100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_PHYSICALDAMAGE, 0), 100, "parity off: as it is")
S.cfg.parity = true

-- logout drops a mark
S.mark(hero:getId(), 50, CLOCK, {"tiers"})
registry.ChaosManaShieldLogout.onLogout(hero)
eq(S.marks[hero:getId()], nil, "logout clears the mark")

-- ------------------------------------------------------------------ the class lists agree
local function read(path)
	local f = assert(io.open(path, "r"))
	local t = f:read("*a")
	f:close()
	return t
end
local NAME = {Mystic = 1, Elementalist = 5, Illusionist = 10, Ranger = 3, Deadeye = 7, Beastmaster = 15}
local function idsOf(list)
	local ids = {}
	for name in list:gmatch("'([^']+)'") do
		ids[#ids + 1] = NAME[name] or -1
	end
	table.sort(ids)
	return table.concat(ids, ",")
end
local want = {}
for _, v in ipairs(S.cfg.vocations) do want[#want + 1] = v end
table.sort(want)
want = table.concat(want, ",")
local cap = read("tools/patch_spell_cap.py"):match("'support/magic_shield.lua': %(44, 'Ward of the Mind', (%b())%)")
eq(cap and idsOf(cap), want, "patch_spell_cap.py CAP keeps the config's classes")
local av = read("tools/add_vocations.py")
eq(av:find("('support/magic_shield.lua', 'utamo vita', (MYSTIC_LINE, RANGER_LINE))", 1, true) ~= nil, true,
	"add_vocations.py gives it the Mystic and Ranger lines")
eq(idsOf(av:match("MYSTIC_LINE = (%b[])") .. av:match("RANGER_LINE = (%b[])")), want, "the two lines are the six")
local spelldata = read("../client/overlay/modules/game_chaosspells/spelldata.lua")
local function luaIds(text)
	local ids = {}
	for n in text:gmatch("%d+") do ids[#ids + 1] = tonumber(n) end
	table.sort(ids)
	return table.concat(ids, ",")
end
local capped = spelldata:match('ChaosCappedSpells = {.-%["tor ael"%] = (%b{})')
local lines = spelldata:match('ChaosStockSpellLines = {.-%["tor ael"%] = (%b{})')
eq(capped and luaIds(capped), want, "client: the cap keeps the six (spelldata.lua)")
eq(lines and luaIds(lines), want, "client: the six get it (spelldata.lua)")

if failures > 0 then
	print(string.format("manashield_test: %d of %d checks FAILED", failures, count))
	os.exit(1)
end
print(string.format("manashield_test: all %d checks passed", count))
