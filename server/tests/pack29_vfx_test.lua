-- Run from the server/ folder: luajit tests/pack29_vfx_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Pair 29 VFX packs (data/lib/chaos_pack29_vfx.lua): every name the tables send is in the client spec
-- (art_import/pack29_vfx.csv) and the ids file, and every spec name is sent by something or listed as unused; the
-- auras and hit splashes the engine sends by id have offset 0, 0; the missiles fit u8; off (the pair 29 switch),
-- nothing is sent, the ids file is not loaded and no engine override is set; on, the engine rows, auras, holds,
-- celebrations and boss blasts; the call sites are wired.
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

dofile("data/lib/chaos_pack29_fx.lua")
dofile("data/lib/chaos_pack29_vfx.lua")
local Q, V = ChaosPack29Fx, ChaosPack29Vfx
eq(Q.PAIR29, false, "the shipped pair 29 switch is off")

-- the client spec
local spec, specNames = {}, {}
for line in (readFile("../client/tools/sprites/art_import/pack29_vfx.csv") or ""):gmatch("[^\n]+") do
	local kind, name = line:match("^(%a+),([%w_]+),")
	if kind == "effect" or kind == "missile" then
		spec[name] = kind
		specNames[#specNames + 1] = name
	end
end
eq(#specNames, 66, "the spec lists 50 effects and 16 missiles")

-- every table name is a spec effect (or missile), and every spec name is used or listed unused
local used = {}
local function uses(name, kind, what)
	ok(spec[name] == kind, what .. ": " .. tostring(name) .. " is a spec " .. kind)
	used[name] = true
end
for state, name in pairs(V.auras) do
	uses(name, "effect", "aura " .. state)
end
for ctype, state in pairs(V.conditionTicks) do
	ok(V.auras[state] ~= nil, "condition tick " .. ctype .. " has an aura")
end
for race, name in pairs(V.raceHits) do
	uses(name, "effect", "race " .. race)
	ok(race >= 1 and race <= 5, "a race id")
end
for ctype, name in pairs(V.elementHits) do
	uses(name, "effect", "element " .. ctype)
end
for key, name in pairs(V.missiles) do
	uses(name, "missile", "missile " .. key)
end
for key, name in pairs(V.names) do
	uses(name, "effect", "spell name " .. key)
end
for kind, v in pairs(V.celebrations) do
	for _, name in ipairs(type(v) == "table" and v or {v}) do
		uses(name, "effect", "celebration " .. kind)
	end
end
for _, name in pairs(V.bossBlast) do
	uses(name, "effect", "boss blast")
end
for word, state in pairs(V.words) do
	ok(V.auras[state] ~= nil, word .. " has an aura")
end
local unused = {}
for _, name in ipairs(V.unused) do
	unused[name] = true
	ok(spec[name] ~= nil, "unused " .. name .. " is in the spec")
end
local states = {}
for state in pairs(V.auras) do states[#states + 1] = state end
-- an aura counts as used when something holds or shows its state
local sent = {}
for _, state in pairs(V.conditionTicks) do sent[state] = true end
for _, state in pairs(V.words) do sent[state] = true end
for _, s in ipairs({"slowed", "stunned", "frozen", "shocked", "confused", "regeneration", "invulnerable", "enraged"}) do
	sent[s] = true
end
for _, state in ipairs(states) do
	local name = V.auras[state]
	used[name] = sent[state] or false
end
for _, name in ipairs(specNames) do
	ok(used[name] or unused[name], name .. " is sent by something or listed unused")
	ok(not (used[name] and unused[name]), name .. " is not both used and unused")
end

-- the ids file: every spec name, the engine-sent effects at 0, 0, missiles fit u8, after the Mystic ids
ChaosVfx, ChaosVfxMissile = {}, {}
dofile("data/lib/chaos_pack29_vfx_ids.lua")
for _, name in ipairs(specNames) do
	local e = (spec[name] == "missile" and ChaosVfxMissile or ChaosVfx)[name]
	ok(e ~= nil, name .. " in the ids file")
	if e and spec[name] == "missile" then
		ok(e.id >= 170 and e.id <= 255, name .. ": a missile id after pair 29's Mystic ones, fits u8")
	elseif e then
		ok(e.id >= 780, name .. ": an effect after pair 29's Mystic ones")
	end
end
for _, name in pairs(V.auras) do
	local e = ChaosVfx[name]
	ok(e and e.dx == 0 and e.dy == 0, name .. ": the engine sends it by id, offset 0, 0")
end
for _, name in pairs(V.raceHits) do
	local e = ChaosVfx[name]
	ok(e and e.dx == 0 and e.dy == 0, name .. ": the engine sends it by id, offset 0, 0")
end

-- pure parts
eq(V.auraFor("burning"), "cond_burning", "auraFor")
eq(V.auraFor("nothing"), nil, "auraFor of an unknown state")
eq(V.pick("fx", "ice_shatter"), "blast_ice", "pick a spell hit")
eq(V.pick("missile", "ice_shatter"), nil, "pick: effects only")
eq(V.pick("fx", "fire_explosion"), nil, "pick: a large pack effect keeps its art")
eq(V.celebration("levelup"), "fw_grand", "the level-up firework")
eq(V.celebration("reward", function(n) return n end), V.celebrations.reward[#V.celebrations.reward], "reward roll")
eq(V.bossBlastFor(50000), "blast_boss", "a boss blast")
eq(V.bossBlastFor(2000000), "blast_massive", "a world boss blast")
V.resetThrottle()
eq(V.allow("1:burning", 1000, 500), true, "throttle: first")
eq(V.allow("1:burning", 1400, 500), false, "throttle: while it plays")
eq(V.allow("1:burning", 1500, 500), true, "throttle: when it ended")
eq(V.allow("2:burning", 1400, 500), true, "throttle: per creature")

-- engine rows from fake ids and constants
local G = {COMBAT_FIREDAMAGE = 8, COMBAT_EARTHDAMAGE = 4, COMBAT_ENERGYDAMAGE = 2, COMBAT_PHYSICALDAMAGE = 1,
	COMBAT_ICEDAMAGE = 512, COMBAT_DEATHDAMAGE = 2048, COMBAT_ARCANEDAMAGE = 8192, CONST_ANI_FIRE = 4}
local hits, shots = V.engineRows(G, ChaosVfx, ChaosVfxMissile, {fire_bolt = 116})
local byKind = {[0] = 0, [1] = 0, [2] = 0}
for _, h in ipairs(hits) do
	byKind[h[1]] = byKind[h[1]] + 1
	if h[1] == 2 and h[2] == 8 then
		eq(h[3], ChaosVfx.cond_burning.id, "a fire tick shows the burning aura")
	end
	if h[1] == 0 and h[2] == 2 then
		eq(h[3], ChaosVfx.hit_blood.id, "a physical hit on blood: the splash")
	end
	if h[1] == 1 and h[2] == 512 then
		eq(h[3], ChaosVfx.blast_ice.id, "an ice hit: the ice blast")
		eq(h[4] .. "," .. h[5], "1,1", "the blast at its offset")
	end
end
eq(byKind[2], 6, "six condition ticks")
eq(byKind[0], 2, "two races")
eq(byKind[1], 6, "six element hits")
eq(#shots, 2, "the missiles known in the fake constants")
eq(shots[1][1], 4, "CONST_ANI_FIRE first")
eq(shots[1][2], ChaosVfxMissile.bolt_fire.id, "as the fire bolt")
eq(shots[2][1], 116, "the procedural fire bolt")

-- off: nothing, the ids file not loaded, the engine overrides cleared only
local engine = {}
Game = {
	setHitEffect = function(...) engine[#engine + 1] = {"hit", ...} return true end,
	setMissileEffect = function(...) engine[#engine + 1] = {"shot", ...} return true end,
	clearEffectOverrides = function() engine[#engine + 1] = {"clear"} return true end,
}
ChaosVfx, ChaosVfxMissile = {}, {}
local vfxSent = {}
Vfx = function(pos, name) vfxSent[#vfxSent + 1] = name return ChaosVfx[name] ~= nil end
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function(self, id) vfxSent[#vfxSent + 1] = id end} end
local function creature(id)
	return {getId = function() return id end, getPosition = function() return {x = 1, y = 1, z = 7} end}
end
Q.PAIR29, V.loaded = false, nil
eq(V.live(), false, "off: not live")
eq(V.show(creature(5), "burning"), false, "off: no aura")
eq(V.celebrate({x = 1, y = 1, z = 7}, "levelup", 29), false, "off: the stock firework")
eq(vfxSent[#vfxSent], 29, "off: the fallback went out")
eq(V.bossDeath({x = 1, y = 1, z = 7}, 10), false, "off: no boss blast")
eq(V.applyEngine(), 0, "off: no override")
eq(#engine, 1, "off: only the clear")
eq(ChaosVfx.cond_burning, nil, "off: ids not loaded")
eq(V.swapFor("fx", "ice_shatter"), nil, "off: no spell blast")

-- on
Q.PAIR29, V.loaded = true, nil
V.resetThrottle()
COMBAT_FIREDAMAGE, CONST_ANI_FIRE = 8, 4
eq(V.live(), true, "on: live (the ids file loaded)")
eq(V.swapFor("fx", "ice_shatter"), "blast_ice", "on: the spell blast")
eq(V.show(creature(5), "burning"), true, "on: the aura")
eq(vfxSent[#vfxSent], "cond_burning", "on: the burning aura went out")
eq(V.show(creature(5), "burning"), false, "on: not again while it plays")
eq(V.celebrate({x = 1, y = 1, z = 7}, "achievement", 29), true, "on: the firework")
eq(vfxSent[#vfxSent], "fw_star", "on: the achievement star")
eq(V.bossDeath({x = 1, y = 1, z = 7}, 10), true, "on: the boss blast")
engine = {}
local n = V.applyEngine()
ok(n >= 14, "on: the overrides set (" .. n .. ")")
eq(engine[1][1], "clear", "on: cleared first")
-- hold: one chain per creature and state, re-sent until the end
local events = {}
addEvent = function(fn, ms) events[#events + 1] = {fn, ms} end
local alive = {[7] = creature(7)}
Creature = function(id) return alive[id] end
local t = 100000
V.now = nil
os.mtime = function() return t end
V.resetThrottle()
eq(V.hold(alive[7], "stunned", 3000), true, "hold: started")
eq(#events, 1, "hold: one event")
eq(V.hold(alive[7], "stunned", 4000), true, "hold: a running chain")
eq(#events, 1, "hold: no second chain")
t = t + ChaosVfx.cond_stunned.ms
events[1][1]()
eq(vfxSent[#vfxSent], "cond_stunned", "hold: sent again")
eq(#events, 2, "hold: the next step")
alive[7] = nil
events[2][1]()
eq(#events, 2, "hold: ends when the creature is gone")
eq(V.held["7:stunned"], nil, "hold: forgotten")
eq(V.onWord(creature(8), "word_feared"), true, "a status word holds its aura")
eq(vfxSent[#vfxSent], "cond_fear", "the fear aura")
os.mtime, addEvent, Creature, Game, Vfx, Position = nil, nil, nil, nil, nil, nil
COMBAT_FIREDAMAGE, CONST_ANI_FIRE = nil, nil
Q.PAIR29, V.loaded = false, nil

-- the call sites
local function has(path, text, what)
	ok((readFile(path) or ""):find(text, 1, true) ~= nil, what)
end
has("data/spells/chaos/_common.lua", "pcall(V.swapFor, kind, name)", "_common.lua asks the blasts after the Mystic swaps")
has("data/spells/chaos/_common.lua", 'pcall(ChaosPack29Vfx.hold, target, "slowed", ticks)', "ChaosSpell.slow holds slowed")
has("data/spells/chaos/ironsage/iron_palm.lua", "ChaosPack29Vfx.hold", "Iron Palm holds stunned")
has("data/scripts/chaos/monk_combat.lua", 'ChaosPack29Vfx.hold, victim, "stunned", ms', "the monk's pvp stun")
has("data/scripts/chaos/item_mods.lua", '"frozen", a.chillMs', "item chill holds frozen")
has("data/scripts/chaos/item_mods.lua", '"shocked", M.config.ailment.shockMs', "item shock holds shocked")
has("data/lib/chaos_status_fx.lua", "ChaosPack29Vfx.onWord", "status words hold their aura")
has("data/scripts/chaos/boss_mechanics.lua", 'pcall(V.show, boss, "invulnerable")', "boss immune phase")
has("data/scripts/chaos/boss_mechanics.lua", 'pcall(V.show, boss, "enraged")', "boss soft enrage")
has("data/scripts/chaos/bosspoints.lua", "ChaosPack29Vfx.bossDeath", "boss death blast")
has("data/scripts/chaos/bosspoints.lua", '"boss", CONST_ME_FIREWORK_YELLOW', "boss point firework")
has("data/scripts/chaos/achievements.lua", '"achievement", CONST_ME_FIREWORK_YELLOW', "achievement firework")
for _, f in ipairs({"worldboss.lua", "guildboss.lua", "raid.lua"}) do
	has("data/scripts/chaos/" .. f, 'ChaosPack29Vfx.celebrate(', f .. " boss reward firework")
end
has("data/scripts/chaos/pack29_vfx.lua", "V.applyEngine", "startup sets the engine overrides")
has("data/scripts/chaos/pack29_vfx.lua", '"levelup"', "the level-up firework")

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("pack29 vfx test: OK")
