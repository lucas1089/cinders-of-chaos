-- Run from the server/ folder: luajit tests/classes_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the class rules of the Thief line (data/scripts/chaos/classes.lua): the ascension, the dual-wield proc and
-- off-hand damage, the stealth outcomes, the counter window, the Bushido stacks, evasion, Poison Blades and light blades.
WEAPON_SWORD, WEAPON_CLUB, WEAPON_DISTANCE = 1, 2, 5
SLOTP_TWO_HAND = 2048

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
local C = ChaosClasses
local cfg = Chaos.classes

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

local THIEF, NINJA, SAMURAI = cfg.ids.thief, cfg.ids.ninja, cfg.ids.samurai
eq(THIEF, 11, "thief id"); eq(NINJA, 12, "ninja id"); eq(SAMURAI, 13, "samurai id")
eq(C.isThiefLine(THIEF) and C.isThiefLine(NINJA) and C.isThiefLine(SAMURAI), true, "thief line")
eq(C.isThiefLine(4), false, "knight is not")
eq(C.isNinja(NINJA), true); eq(C.isNinja(SAMURAI), false); eq(C.isSamurai(SAMURAI), true)

-- ------------------------------------------------------------------ ascension
eq(C.ascensionFor(THIEF, 100, "ninja", true, false), NINJA, "thief -> ninja")
eq(C.ascensionFor(THIEF, 250, " Samurai ", true, false), SAMURAI, "word is trimmed and case-free")
local id, why = C.ascensionFor(THIEF, 99, "ninja", true, false)
eq(id, nil, "level 99 refused"); eq(why:find("level 100") ~= nil, true, "says the level")
id, why = C.ascensionFor(THIEF, 300, "ninja", false, false)
eq(id, nil, "outside a protection zone refused"); eq(why:find("protection zone") ~= nil, true)
eq(C.ascensionFor(THIEF, 300, "ninja", true, true), nil, "in combat refused")
id, why = C.ascensionFor(THIEF, 300, "", true, false)
eq(id, nil, "no choice"); eq(why:find("ninja|samurai", 1, true) ~= nil, true, "lists the choices")
eq(C.ascensionFor(THIEF, 300, "knight", true, false), nil, "not a choice of the thief")
id, why = C.ascensionFor(NINJA, 300, "samurai", true, false)
eq(id, nil, "final: a ninja cannot switch"); eq(why:find("Vocation Change") ~= nil, true, "points to the store")
eq(C.ascensionFor(SAMURAI, 300, "ninja", true, false), nil, "final: a samurai cannot switch")
eq(C.ascensionFor(4, 300, "ninja", true, false), nil, "a knight has no ascension yet")

-- ------------------------------------------------------------------ light blades and dual wield
eq(C.isLightBlade(WEAPON_SWORD, 48), true, "one-handed sword")
eq(C.isLightBlade(WEAPON_SWORD, 48 + SLOTP_TWO_HAND), false, "two-handed sword")
eq(C.isLightBlade(WEAPON_CLUB, 48), false, "club")
eq(C.isLightBlade(nil, 48), false, "no item")

eq(C.dualWieldProc(NINJA, true, true, true, false, 300), true, "ninja, two blades, melee hit")
eq(C.dualWieldProc(THIEF, true, true, true, false, 300), false, "only the ninja")
eq(C.dualWieldProc(SAMURAI, true, true, true, false, 300), false, "not the samurai")
eq(C.dualWieldProc(NINJA, false, true, true, false, 300), false, "not on spells / ranged")
eq(C.dualWieldProc(NINJA, true, true, false, false, 300), false, "needs a blade in the off hand")
eq(C.dualWieldProc(NINJA, true, false, true, false, 300), false, "needs a blade in the main hand")
eq(C.dualWieldProc(NINJA, true, true, true, true, 300), false, "guard: no off-hand from a scripted strike")
eq(C.dualWieldProc(NINJA, true, true, true, false, 0), false, "no off-hand from a miss")

eq(C.offhandDamage(400, 50, 50, false), 200, "same blades: half the hit")
eq(C.offhandDamage(-400, 50, 50, false), 200, "sign of the hit does not matter")
eq(C.offhandDamage(400, 50, 10, false), 100, "weak off-hand: clamped at minRatio 0.5")
eq(C.offhandDamage(400, 40, 100, false), 250, "strong off-hand: clamped at maxRatio 1.25")
eq(C.offhandDamage(400, 50, 40, false), 160, "off-hand 40 / main 50")
eq(C.offhandDamage(200, 50, 50, true), 200, "against players: from the unhalved hit")
eq(C.offhandDamage(0, 50, 50, false), 0, "no hit, no strike")

-- ------------------------------------------------------------------ stealth
local m, ends = C.stealthOnAttack(true, true, 500)
eq(m, cfg.stealth.ambushMultiplier, "first weapon hit out of stealth crits"); eq(ends, true, "and ends it")
m, ends = C.stealthOnAttack(true, false, 500)
eq(m, 1, "a spell hit does not crit"); eq(ends, true, "but ends it")
m, ends = C.stealthOnAttack(false, true, 500)
eq(m, 1, "no stealth, no crit"); eq(ends, false)
m, ends = C.stealthOnAttack(true, true, 0)
eq(m, 1, "a miss changes nothing"); eq(ends, false, "a miss keeps the stealth")
eq(C.stealthOnHit(true, 120, true), true, "a hit taken ends it")
eq(C.stealthOnHit(true, 0, true), false, "a dodged / parried hit does not")
eq(C.stealthOnHit(false, 120, true), false, "nothing to end")
eq(C.monsterMayTarget(true, true), false, "monsters cannot target a stealthed player")
eq(C.monsterMayTarget(false, true), true)

-- ------------------------------------------------------------------ counter stance
eq(C.counterTake(1500, true, true), true, "melee hit inside the window is parried")
eq(C.counterTake(0, true, true), false, "window closed")
eq(C.counterTake(nil, true, true), false, "no stance")
eq(C.counterTake(1500, false, true), false, "spells and ranged hits are not parried")
eq(C.counterDamage(-300), 450, "answer: 1.5x the parried hit")

-- ------------------------------------------------------------------ bushido focus
local P = 1001
eq(C.bushidoStacks(P, 0), 0, "no buff, no stacks")
C.bushidoStart(P, 1000)
eq(C.bushidoStacks(P, 1000), cfg.bushido.startStacks, "starts with startStacks")
eq(C.bushidoStacks(P, 3999), cfg.bushido.startStacks + 2, "one stack per second")
eq(C.bushidoStacks(P, 60000 - 31000 + 1000), cfg.bushido.maxStacks, "capped")
C.bushidoOnDamaged(P, 5000)
eq(C.bushidoStacks(P, 5000), 0, "a hit taken resets the stacks")
eq(C.bushidoStacks(P, 7000), 2, "and they build again")
local mult, crit = C.bushidoRoll(P, 7000, 0.05)
eq(crit, true, "roll under 2 x 3%% crits"); eq(mult, cfg.bushido.critMultiplier)
mult, crit = C.bushidoRoll(P, 7000, 0.07)
eq(crit, false, "roll over the chance does not"); eq(mult, 1)
C.bushidoStart(P, 8000) -- recast keeps the stacks it had (3 at 8 s, startStacks 3)
eq(C.bushidoStacks(P, 8000), math.max(3, cfg.bushido.startStacks), "recast keeps the stacks")
eq(C.bushidoStacks(P, 8000 + cfg.bushido.durationMs), 0, "buff over: no stacks")
C.clear(P)
eq(C.bushidoState[P], nil, "cleared")

-- ------------------------------------------------------------------ evasion, poison
eq(C.dodges(NINJA, true, 0.11), true, "ninja dodges under 12%")
eq(C.dodges(NINJA, true, 0.13), false)
eq(C.dodges(THIEF, true, 0.07), true, "thief 8%")
eq(C.dodges(SAMURAI, true, 0.06), false, "samurai 5%")
eq(C.dodges(NINJA, false, 0.0), false, "spells are not dodged")
eq(C.dodges(4, true, 0.0), false, "knights do not dodge")
eq(C.poisonTick(400), math.floor(400 * cfg.poisonBlades.share / cfg.poisonBlades.ticks + 0.5), "poison per tick")
eq(C.poisonTick(0), 1, "at least 1")

print("classes_test: OK")
