-- Run from the server/ folder: luajit tests/pvp_scale_test.lua && lua5.3 tests/pvp_scale_test.lua (CI runs both)
-- O473 (2026-11-10): the PvP damage scale. A hit a player (or a summon or companion of a player) deals to ANOTHER player is
-- multiplied by a factor of the ATTACKER's level (pvp_balance_config.lua damageScale, pvp_scale_core.lua), applied once in
-- ChaosPassiveDealt for every path. A monster's hit, a heal and a hit on a monster are never scaled. What this holds:
--   * the table of the design's first fit and its interpolation (geometric between two rows, flat outside);
--   * the real event: player against player, monster against player, player against monster, a heal, a summon of a player, a
--     summon of nobody, oneself, a keystone proc (a share of a hit that was scaled already), both parts of a hit, the pool and the
--     scale together (the pool first, then the scale).
local checks, fails = 0, 0
local function ok(c, m)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. (m or ""))
	end
end
local function near(a, b, tol, m)
	ok(math.abs(a - b) <= tol * math.max(1, math.abs(b)), (m or "") .. ": " .. tostring(a) .. " vs " .. tostring(b))
end

local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
Chaos = {storage = {}, tables = {}, passive = {}}
function Chaos.load() end
ChaosOpcodes = {}
local registered = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
rawset(EventCallback, "register", function(self) local l = rawget(self, "_last"); registered[l[1]] = l[2] end)
function CreatureEvent(name) local o = {}; function o:register() registered[name] = o end; return o end
function Condition(t) local c = {t = t, p = {}}; function c:setTicks(x) end; function c:setParameter(k, v) self.p[k] = v end; return c end
function addEvent() end
os.mtime = function() return 1000 end
dofile("data/scripts/chaos/passivetree_effects.lua")
local ev = registered["ChaosPassiveDealt"]
local S = ChaosPvpScale
local cfg = dofile("data/scripts/chaos/pvp_balance_config.lua")

-- ============================================================================================== the table
local want = {{100, 1.24}, {200, 1.09}, {300, 1.06}, {500, 0.98}, {700, 0.95}, {1000, 0.68}, {1500, 0.69}, {2000, 0.65}}
ok(#cfg.damageScale == #want, "eight rows")
for i, row in ipairs(want) do
	ok(cfg.damageScale[i][1] == row[1] and cfg.damageScale[i][2] == row[2], "row " .. i .. ": " .. row[1] .. " -> " .. row[2])
	near(S.factor(row[1]), row[2], 1e-12, "the factor at the row " .. row[1])
	if i > 1 then
		ok(cfg.damageScale[i][1] > cfg.damageScale[i - 1][1], "levels ascend")
	end
end
near(S.factor(1), 1.24, 1e-12, "below the first row: the first factor")
near(S.factor(50), 1.24, 1e-12, "level 50")
near(S.factor(5000), 0.65, 1e-12, "above the last row: the last factor")
near(S.factor(150), math.exp(0.5 * math.log(1.24) + 0.5 * math.log(1.09)), 1e-12, "between 100 and 200: geometric, halfway")
near(S.factor(600), math.exp(0.5 * math.log(0.98) + 0.5 * math.log(0.95)), 1e-12, "between 500 and 700")
near(S.factor(750), math.exp(math.log(0.95) + (math.log(0.68) - math.log(0.95)) * 50 / 300), 1e-12, "between 700 and 1000")
ok(S.factor(1250) > 0.68 and S.factor(1250) < 0.69, "between 1000 and 1500 (it rises there)")
ok(S.factor(nil) == 1 and S.factor("x") == 1, "no level: 1")
ok(S.factor(500, {damageScale = {}}) == 1 and S.factor(500, {}) == 1, "no table: 1")
for level = 1, 2200 do
	local f = S.factor(level)
	ok(f >= 0.65 - 1e-9 and f <= 1.24 + 1e-9, "every level inside [0.65, 1.24]") -- cheap: 2200 checks
	if f < 0.65 - 1e-9 or f > 1.24 + 1e-9 then break end
end

-- ============================================================================================== the event
ChaosPassiveLineFactor = function() return 1 end
local function player(id, level)
	local p = {}
	function p:isPlayer() return true end
	function p:getId() return id end
	function p:getLevel() return level end
	return p
end
local function monster(id, master)
	local m = {}
	function m:isPlayer() return false end
	function m:getId() return id end
	function m:getMaster() return master end
	return m
end
local function run(target, attacker, damage, ctype, origin, sdamage, stype)
	local p, _, s = ev.onHealthChange(target, attacker, -damage, ctype or COMBAT_FIREDAMAGE, -(sdamage or 0), stype or COMBAT_NONE,
		origin or ORIGIN_SPELL)
	return -p, -s
end
local a500, a1000, victim = player(7, 500), player(8, 1000), player(9, 500)
ChaosPassiveCache[7], ChaosPassiveCache[8] = {}, {}
-- player against player: the attacker's level
ok(run(victim, a500, 1000) == 980, "level 500 attacker: x0.98 (" .. run(victim, a500, 1000) .. ")")
ok(run(victim, a1000, 1000) == 680, "level 1000 attacker: x0.68")
ok(run(victim, player(10, 100), 1000) == 1240, "level 100: x1.24")
-- the victim's level does not matter
ok(run(player(11, 2000), a500, 1000) == 980, "the target's level is not read")
-- every origin of a player's hit
for _, origin in ipairs({ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED, ORIGIN_WAND, ORIGIN_CONDITION, ORIGIN_NONE}) do
	ok(run(victim, a500, 1000, COMBAT_PHYSICALDAMAGE, origin) == 980, "origin " .. origin .. ": scaled once")
end
-- both parts
local p1, p2 = run(victim, a500, 1000, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE, 400, COMBAT_FIREDAMAGE)
ok(p1 == 980 and p2 == 392, "both parts of a hit are scaled: " .. p1 .. ", " .. p2)
-- against a monster: never
local mon = monster(500)
ok(run(mon, a1000, 1000) == 1000, "a hit on a monster is not scaled")
-- a monster's hit on a player: never (no passive state, no master)
ok(run(victim, monster(501), 1000) == 1000, "a monster against a player is not scaled")
-- a heal: never
do
	local h = ev.onHealthChange(victim, a1000, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
	ok(h == 1000, "a heal on another player is not scaled")
	h = ev.onHealthChange(victim, a1000, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_NONE)
	ok(h == 1000, "(nor an ORIGIN_NONE heal)")
end
-- oneself: never
ok(run(a500, a500, 1000) == 1000, "damage to oneself is not scaled")
-- a summon or companion of a player: the owner's level
local summon = monster(600, a1000)
ok(run(victim, summon, 1000) == 680, "a summon of a level 1000 player: x0.68")
ok(run(mon, summon, 1000) == 1000, "a summon against a monster: not scaled")
ok(run(a1000, summon, 1000) == 1000, "a summon does not scale a hit on its own owner")
local pet = monster(601, a500)
local pp, _, ps = ev.onHealthChange(victim, pet, -1000, COMBAT_PHYSICALDAMAGE, -200, COMBAT_FIREDAMAGE, ORIGIN_MELEE)
ok(pp == -980 and ps == -196, "a companion: both parts, its owner's level")
ok(run(victim, monster(602, monster(603)), 1000) == 1000, "a summon of a monster is a monster")
-- a keystone proc is a share of a hit that was scaled already
ChaosKeystones = {depth = 1}
ok(run(victim, a500, 1000) == 1000, "a keystone proc: not scaled again")
ok(run(victim, summon, 1000) == 1000, "(nor a summon's proc)")
ChaosKeystones.depth = 0
-- the pool first, then the scale
ChaosPassiveCache[7] = {incrementFire = 50, paragonDamage = 10}
ok(run(victim, a500, 1000) == math.floor(1000 * 1.6 * 0.98 + 1e-6), "pool x1.60 then x0.98 (" .. run(victim, a500, 1000) .. ")")
ok(run(mon, a500, 1000) == 1600, "against a monster the pool alone")
-- the same table is what pvp_model.py reads: one table
local f = io.open("data/scripts/chaos/pvp_balance_config.lua", "r")
local text = f:read("*a")
f:close()
ok(text:find("damageScale = {{100, 1.24}, {200, 1.09}, {300, 1.06}, {500, 0.98}, {700, 0.95}, {1000, 0.68}, {1500, 0.69}, {2000, 0.65}}", 1, true),
	"the table sits in pvp_balance_config.lua, one line")
-- the other PvP rules stay: the battleground level normalisation is a separate step, the arena adds none
local bg = dofile("data/scripts/chaos/battleground_config.lua")
ok(bg.normalise and bg.normalise.exponent, "the battleground's own level normalisation is untouched")

if fails > 0 then
	error(fails .. " of " .. checks .. " pvp scale checks failed")
end
print("pvp_scale_test: " .. checks .. " checks OK")
