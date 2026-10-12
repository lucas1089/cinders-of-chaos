-- Run from the server/ folder: luajit tests/healing_rules_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Covers the healer rules (healing_rules_core.lua): the spell ids, the formulas, Weaver's Grace, Mirror Mend's targets,
-- the PvP state; and the glue (healing_rules.lua): heals on players scaled by Weaver's Grace and the PvP reduction,
-- PvP combat noted from player damage, the arena and the fight lock.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function near(a, b, m) if math.abs(a - b) > 1e-6 then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

dofile("data/scripts/chaos/healing_rules_core.lua")
local H = ChaosHealing
local cfg = H.cfg

-- ------------------------------------------------------------------ ids: below 256, outside the reserved blocks
for name, id in pairs(cfg.ids.spell) do
	assert(id > 0 and id < 256, name .. " below 256 (one byte in the cooldown packet)")
	assert(not (id >= 63 and id <= 74), name .. " not the Monk's block")
	assert(not (id >= 180 and id <= 191), name .. " not the Necromancer / Templar block")
	assert(id ~= 198 and id ~= 199, name .. " not the Templar's ids")
	assert(not (id >= 200 and id <= 253), name .. " not the Chaos / Templar block")
end
assert(cfg.ids.spell.mirrorMend ~= cfg.ids.spell.lucidReverie, "two ids")
-- the XML block uses the same ids and scripts
local xml = io.open("data/spells/chaos/spells_chaos.xml"):read("*a")
assert(xml:find('spellid="' .. cfg.ids.spell.mirrorMend .. '" name="Mirror Mend"', 1, true), "Mirror Mend in spells_chaos.xml")
assert(xml:find('spellid="' .. cfg.ids.spell.lucidReverie .. '" name="Lucid Reverie"', 1, true), "Lucid Reverie in spells_chaos.xml")
for _, id in pairs(cfg.ids.spell) do
	local _, count = xml:gsub('spellid="' .. id .. '"', "")
	eq(count, 1, "spell id " .. id .. " used once")
end

-- ------------------------------------------------------------------ formulas
local mn, mx = H.values(300, 100, cfg.mirrorMend)
near(mn, 300 * 0.3 + 100 * 11 + 40, "Mirror Mend min, level 300 ml 100"); near(mx, 300 * 0.3 + 100 * 17 + 80, "max")
mn, mx = H.values(1000, 140, cfg.lucidReverie)
near(mn, 1000 * 0.16 + 140 * 0.9 + 10, "Lucid Reverie pulse min"); near(mx, 1000 * 0.16 + 140 * 1.3 + 20, "max")

-- ------------------------------------------------------------------ Weaver's Grace and the PvP reduction
near(H.healMultiplier({healerVoc = 10, selfHeal = false}), 1 + cfg.weaversGrace.othersBonus, "Illusionist heals another")
near(H.healMultiplier({healerVoc = 10, selfHeal = true}), 1, "not on itself")
near(H.healMultiplier({healerVoc = 1, selfHeal = false}), 1, "the Mystic has no Weaver's Grace")
near(H.healMultiplier({healerVoc = 25, selfHeal = false}), 1, "the Sentinel neither")
near(H.healMultiplier({healerVoc = 1, selfHeal = true, pvp = true}), cfg.pvp.healingTaken, "PvP: everyone's heals")
near(H.healMultiplier({healerVoc = 10, selfHeal = false, pvp = true}), (1 + cfg.weaversGrace.othersBonus) * cfg.pvp.healingTaken,
	"PvP: Weaver's Grace too")
eq(H.scale(1000, 1.08), 1080); eq(H.scale(-1000, 0.7), -700); eq(H.scale(0, 2), 0)

-- ------------------------------------------------------------------ Mirror Mend targets
local function c(id, h, m) return {id = id, health = h, maxHealth = m or 1000} end
local p, m = H.mirrorTargets({c(1, 900), c(2, 300), c(3, 600), c(4, 1000)}, 1)
eq(p, 2, "the most hurt member"); eq(m, 3, "the mirror: the next most hurt")
p, m = H.mirrorTargets({c(1, 100), c(2, 500), c(3, 1000)}, 1)
eq(p, 2, "a hurt member before the caster"); eq(m, 1, "the mirror may heal the caster")
p, m = H.mirrorTargets({c(1, 400), c(2, 1000), c(3, 1000)}, 1)
eq(p, 1, "nobody else hurt: the caster"); eq(m, nil, "no mirror on full health")
p, m = H.mirrorTargets({c(1, 400)}, 1)
eq(p, 1, "alone: the caster"); eq(m, nil)
p, m = H.mirrorTargets({c(1, 900), c(2, 300), c(3, 600)}, 1, 3)
eq(p, 3, "the named member"); eq(m, 2, "the mirror on the most hurt other")
p, m = H.mirrorTargets({c(1, 900), c(2, 300)}, 1, 99)
eq(p, nil, "a name outside the candidates: nothing")
p, m = H.mirrorTargets({c(1, 1000), c(5, 500, 2000), c(4, 1000, 4000)}, 1)
eq(p, 4, "health share, not health: 25% before 25.0x%"); eq(m, 5)
p = H.mirrorTargets({c(3, 500), c(2, 500)}, 1)
eq(p, 2, "ties: the lowest id")

-- ------------------------------------------------------------------ PvP state
local st = {}
eq(H.recentPvp(st, 7, 1000), false)
H.markPvp(st, 7, 1000)
eq(H.recentPvp(st, 7, 1000 + cfg.pvp.windowMs), true, "within the window")
eq(H.recentPvp(st, 7, 1001 + cfg.pvp.windowMs), false, "after the window")
eq(st[7], nil, "forgotten")

-- ------------------------------------------------------------------ glue (healing_rules.lua) with a mock engine
local registered, events = {}, {}
function CreatureEvent(name)
	local e = {name = name}
	function e:register() registered[name] = self end
	return e
end
function addEvent(fn, ms, ...) events[#events + 1] = {fn = fn, args = {...}} end
local NOW = 50000
os.mtime = function() return NOW end
local creatures = {}
local function mk(id, kind, voc, master)
	local o = {id = id, kind = kind, voc = voc, master = master, pz = false, reg = {}}
	function o:getId() return self.id end
	function o:isPlayer() return self.kind == "player" end
	function o:getVocation() local v = self.voc; return {getId = function() return v end} end
	function o:getMaster() return self.master end
	function o:isPzLocked() return self.pz end
	function o:getPosition() return {x = 100, y = 100, z = 7} end
	function o:registerEvent(name) self.reg[name] = true end
	creatures[id] = o
	return o
end
Player = function(id) local x = creatures[id]; return x and x.kind == "player" and x or nil end
ChaosArena = {isInside = function(pl) return pl.inArena == true end}
dofile("data/scripts/chaos/healing_rules.lua")
local ev = registered["ChaosHealing"]
assert(ev and registered["ChaosHealingLogin"] and registered["ChaosHealingLogout"], "events registered")

local illu = mk(1, "player", 10)
local mystic = mk(2, "player", 1)
local knight = mk(3, "player", 8)
local foe = mk(4, "player", 12)
local wolf = mk(50, "monster", 0, foe)
local monster = mk(60, "monster", 0, nil)

registered["ChaosHealingLogin"].onLogin(knight)
events[1].fn(); events = {}
assert(knight.reg["ChaosHealing"], "registered on the player one tick after login")

eq(ev.onHealthChange(knight, illu, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL), 1160, "Illusionist heals the knight: +16%")
eq(ev.onHealthChange(illu, illu, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL), 1000, "its self heal unchanged")
eq(ev.onHealthChange(knight, mystic, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL), 1000, "the Mystic's heal unchanged")
eq(ev.onHealthChange(knight, nil, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_NONE), 1000, "no healer")
eq(ev.onHealthChange(monster, illu, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL), 1000, "only players")

-- a monster's hit is no PvP; a player's summon's is, for the victim and the summon's owner
eq(ev.onHealthChange(knight, monster, -500, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), -500, "damage untouched")
eq(H.inPvp(knight), false, "monster damage is no PvP")
ev.onHealthChange(knight, wolf, -500, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(H.inPvp(knight), true, "hit by a player's summon"); eq(H.inPvp(foe), true, "its owner too")
eq(ev.onHealthChange(knight, illu, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL), 812, "PvP: 1000 x 1.16 x 0.70")
eq(ev.onHealthChange(knight, knight, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL), 700, "PvP: self heals too")
eq(ev.onHealthChange(foe, nil, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_NONE), 700, "PvP: any heal (potions)")
NOW = NOW + cfg.pvp.windowMs + 1
eq(ev.onHealthChange(knight, illu, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL), 1160, "window over")
ev.onHealthChange(knight, knight, -100, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(H.inPvp(knight), false, "own damage is no PvP")
ev.onHealthChange(knight, foe, 0, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(H.inPvp(knight), false, "a hit cut to 0 (protection, arena countdown) is no PvP")
mystic.pz = true
eq(H.inPvp(mystic), true, "fight-locked by attacking a player")
mystic.pz = false
illu.inArena = true
eq(ev.onHealthChange(illu, illu, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL), 700, "inside an arena match")
illu.inArena = false
ChaosSiege = {state = {phase = "match"}, locate = function(pos) return "arena" end}
eq(H.inPvp(illu), true, "the siege arena during a match")
ChaosSiege.state.phase = "idle"
eq(H.inPvp(illu), false, "not between matches")
ChaosSiege = nil

ev.onHealthChange(knight, foe, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
registered["ChaosHealingLogout"].onLogout(knight)
eq(H.inPvp(knight), false, "forgotten at logout")
print("healing rules: all asserts passed")
