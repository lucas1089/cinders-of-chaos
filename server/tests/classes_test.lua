-- Run from the server/ folder: luajit tests/classes_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the class rules (data/scripts/chaos/classes.lua): the ascension of the four base classes and the free switch,
-- the migration of the old vocations (mapping, SQL, message), the keystone variants, the Berserker's Rage and Bloodrage,
-- the Beastmaster companion's scaling, and the Thief line: the dual-wield proc and off-hand damage, the stealth
-- outcomes, the counter window, the Bushido stacks, evasion, Poison Blades and light blades.
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
eq(id, nil, "no choice"); eq(why:find("ninja or samurai", 1, true) ~= nil, true, "lists the choices")
eq(C.ascensionFor(THIEF, 300, "knight", true, false), nil, "not a choice of the thief")
id, why = C.ascensionFor(NINJA, 300, "samurai", true, false)
eq(id, nil, "final: a ninja cannot switch"); eq(why:find("Vocation Change") ~= nil, true, "points to the store")
eq(C.ascensionFor(SAMURAI, 300, "ninja", true, false), nil, "final: a samurai cannot switch")
eq(C.ascensionFor(4, 300, "ninja", true, false), nil, "not a choice of the warrior")

-- ------------------------------------------------------------------ the other base classes
local ids = cfg.ids
eq(ids.warrior, 4); eq(ids.juggernaut, 8); eq(ids.berserker, 14); eq(ids.ranger, 3); eq(ids.deadeye, 7)
eq(ids.beastmaster, 15); eq(ids.mystic, 1); eq(ids.elementalist, 5); eq(ids.illusionist, 10)
for word, want in pairs({juggernaut = 8, berserker = 14}) do eq(C.ascensionFor(4, 100, word, true, false), want, "warrior " .. word) end
for word, want in pairs({deadeye = 7, beastmaster = 15}) do eq(C.ascensionFor(3, 100, word, true, false), want, "ranger " .. word) end
for word, want in pairs({elementalist = 5, illusionist = 10}) do eq(C.ascensionFor(1, 100, word, true, false), want, "mystic " .. word) end
id, why = C.ascensionFor(4, 300, "", true, false)
eq(why:find("berserker or juggernaut", 1, true) ~= nil, true, "lists the warrior's choices: " .. why)
eq(C.ascensionFor(3, 300, "berserker", true, false), nil, "not a choice of the ranger")
eq(C.ascensionFor(1, 99, "illusionist", true, false), nil, "level rule for every class")
id, why = C.ascensionFor(8, 300, "berserker", true, false)
eq(id, nil, "final: a juggernaut cannot switch"); eq(why:find("Vocation Change") ~= nil, true)
eq(C.ascensionFor(2, 300, "illusionist", true, false), nil, "retired ids have no ascension")
eq(C.ascensionFor(0, 300, "juggernaut", true, false), nil, "no vocation")
-- the free switch of the migration: an old Elite Knight (Juggernaut) may become a Berserker once, at any level
local fid, free = C.ascensionFor(8, 50, "berserker", true, false, 14)
eq(fid, 14, "free switch to berserker"); eq(free, true, "marked as the free switch")
eq(select(2, C.ascensionFor(4, 100, "juggernaut", true, false)), false, "a normal ascension is not the free switch")
id, why = C.ascensionFor(8, 300, "juggernaut", true, false, 14)
eq(id, nil, "already a juggernaut"); eq(why:find("stays") ~= nil, true, "the switch is kept")
id, why = C.ascensionFor(8, 300, "elementalist", true, false, 14)
eq(id, nil, "only the other class of the line"); eq(why:find("to berserker", 1, true) ~= nil, true, why)
eq(C.ascensionFor(8, 300, "berserker", false, false, 14), nil, "free switch: still a protection zone")
eq(C.ascensionFor(8, 300, "berserker", true, true, 14), nil, "free switch: not in combat")
eq(C.ascensionFor(7, 300, "beastmaster", true, false, 15), 15, "old royal paladin -> beastmaster")
eq(C.baseOf(14), 4); eq(C.baseOf(15), 3); eq(C.baseOf(10), 1); eq(C.baseOf(2), nil, "retired")
eq(C.isAscended(14), true); eq(C.isAscended(4), false); eq(C.isAscended(0), false)

-- ------------------------------------------------------------------ keystone variants
local keys = {[4] = "knight", [8] = "knight", [14] = "knight", [3] = "paladin", [7] = "paladin", [15] = "paladin",
  [1] = "sorcerer", [5] = "sorcerer", [10] = "illusionist"}
for v, k in pairs(keys) do eq(C.keystoneKey(v), k, "keystone key " .. v) end
eq(C.keystoneKey(12), nil, "the Thief line has no tree entry yet")

-- ------------------------------------------------------------------ migration
local function mig(v) local p = C.migrationFor(v); return p and p.to, p and p.freeSwitch, p and p.resetTree end
local want = {[1] = 1, [2] = 1, [3] = 3, [4] = 4, [5] = 5, [6] = 10, [7] = 7, [8] = 8, [9] = 1, [10] = 10}
for old, new in pairs(want) do
  local to, sw, reset = mig(old)
  eq(to, new, "old " .. old); eq(reset, true, "tree reset " .. old)
end
eq(select(2, mig(8)), 14, "elite knight: free switch to berserker"); eq(select(2, mig(7)), 15, "royal paladin: to beastmaster")
eq(select(2, mig(4)), nil, "knight: no free switch (it chooses at ascension)"); eq(select(2, mig(5)), nil)
eq(C.migrationFor(11), nil, "the Thief line is left alone"); eq(C.migrationFor(14), nil); eq(C.migrationFor(0), nil)
-- every new id the migration produces is a class
for old in pairs(want) do eq(C.baseOf((mig(old))) ~= nil, true, "lands on a class " .. old) end
local sql = C.migrationSql("chaos_passive_tree")
eq(#sql, 1 + 2 + 1 + 3, "storage, two free switches, tree, three retired ids")
eq(sql[1]:find("`player_storage`") ~= nil and sql[1]:find(tostring(cfg.storage.migratedFrom)) ~= nil, true, "remembers the old vocation")
eq(sql[2]:find("WHERE `vocation` = 7") ~= nil and sql[2]:find(", 15 FROM") ~= nil, true, sql[2])
eq(sql[3]:find("WHERE `vocation` = 8") ~= nil and sql[3]:find(", 14 FROM") ~= nil, true, sql[3])
eq(sql[4]:find("UPDATE `chaos_passive_tree` SET `nodes` = ''", 1, true) ~= nil, true, "tree reset")
eq(sql[5], "UPDATE `players` SET `vocation` = 1 WHERE `vocation` = 2", "druid -> mystic")
eq(sql[6], "UPDATE `players` SET `vocation` = 10 WHERE `vocation` = 6", "elder druid -> illusionist")
eq(sql[7], "UPDATE `players` SET `vocation` = 1 WHERE `vocation` = 9", "illusionist -> mystic")
for i = 1, 4 do assert(sql[i]:find("vocation") and sql[i]:find("players"), "storages and tree run before the ids move") end
local text = C.migrationMessage("Elite Knight", "Juggernaut", "berserker", true)
eq(text:find("Elite Knight is now Juggernaut") ~= nil, true, text); eq(text:find("(berserker): Character > Services", 1, true) ~= nil, true, text)
eq(text:find("passive tree") ~= nil, true, "mentions the reset")
eq(C.migrationMessage("Druid", "Mystic", nil, true):find("ascend") == nil, true, "no switch offered")

-- ------------------------------------------------------------------ berserker rage
local r = cfg.rage
eq(C.rageMultiplier(1000, 1000, false), 1, "full health: no rage")
eq(math.abs(C.rageMultiplier(300, 1000, false) - (1 + r.maxBonus)) < 1e-9, true, "30% health: full rage")
eq(math.abs(C.rageMultiplier(100, 1000, false) - (1 + r.maxBonus)) < 1e-9, true, "below: capped")
eq(math.abs(C.rageMultiplier(650, 1000, false) - (1 + r.maxBonus / 2)) < 1e-9, true, "halfway: half the rage")
assert(C.rageMultiplier(800, 1000, false) < C.rageMultiplier(700, 1000, false), "grows as health drops")
eq(math.abs(C.rageMultiplier(1000, 1000, true) - (1 + cfg.bloodrage.bonus)) < 1e-9, true, "bloodrage adds on top")
eq(C.rageMultiplier(0, 0, false), 1, "no max health: no rage")
eq(C.bloodrageCleave(-400), 160, "cleave: 40% of the hit")
eq(C.bloodrageCost(1000), 100, "bloodrage costs 10% of the health"); eq(C.bloodrageCost(1), 0, "never the last point")

-- ------------------------------------------------------------------ beastmaster companion
eq(C.companionCap(100), 1, "one companion"); eq(C.companionCap(399), 1); eq(C.companionCap(400), 2, "two from level 400")
eq(C.companionHealth(0), cfg.companion.health.base)
eq(C.companionHealth(1000), cfg.companion.health.base + 1000 * cfg.companion.health.perLevel, "health scales with level")
local lo, hi = C.biteValues(1000, 140)
local avg = 1000 * cfg.companion.biteLevel + 140 * cfg.companion.biteSkill
eq(lo, math.floor(avg * (1 - cfg.companion.spread)), "bite min"); eq(hi, math.floor(avg * (1 + cfg.companion.spread)), "bite max")
local lo3, hi3 = C.biteValues(300, 110)
assert(hi3 < hi and lo3 < lo, "bites scale with level and skill")
eq(C.isBerserker(14), true); eq(C.isBeastmaster(15), true); eq(C.isBeastmaster(7), false)

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

-- ------------------------------------------------------------------ the Monk, Necromancer and Templar lines
-- (ids and choices in chaos_constants.lua; each line's own rules: tests/monk_test.lua, necro_test.lua, templar_test.lua)
eq(cfg.ids.monk, 17); eq(cfg.ids.shadowfist, 18); eq(cfg.ids.ironsage, 19)
eq(C.ascensionFor(17, 100, "shadowfist", true, false), 18, "monk -> shadowfist")
eq(C.ascensionFor(17, 100, "ironsage", true, false), 19, "monk -> iron sage")
eq(C.ascensionFor(17, 99, "ironsage", true, false), nil, "monk: level 100")
eq(C.ascensionFor(18, 300, "ironsage", true, false), nil, "final: a shadowfist cannot switch")
eq(C.ascensionFor(11, 300, "shadowfist", true, false), nil, "not a choice of the thief")
eq(C.baseOf(19), 17, "iron sage line"); eq(C.isAscended(18), true); eq(C.isThiefLine(17), false)
eq(C.keystoneKey(17), nil, "the Monk has no passive tree entry yet")

eq(C.ascensionFor(20, 100, "lich", true, false), 21, "necromancer -> lich")
eq(C.ascensionFor(20, 300, " BoneLord ", true, false), 22, "necromancer -> bone lord (trimmed, case-free)")
eq(C.ascensionFor(20, 99, "lich", true, false), nil, "necromancer level 99 refused")
eq(C.ascensionFor(21, 300, "bonelord", true, false), nil, "an ascended lich cannot ascend again")
eq(C.baseOf(22), 20, "bone lord's base"); eq(C.isAscended(21), true, "lich is ascended")
eq(C.keystoneKey(20), nil, "no passive tree entry yet")
local necroCfg = dofile("data/scripts/chaos/necro_config.lua")
for key, vid in pairs(necroCfg.ids) do eq(cfg.ids[key], vid, "Chaos.classes.ids." .. key .. " = necro_config.lua") end

eq(cfg.ids.templar, 23); eq(cfg.ids.inquisitor, 24); eq(cfg.ids.sentinel, 25)
eq(C.ascensionFor(23, 100, "inquisitor", true, false), 24, "templar -> inquisitor")
eq(C.ascensionFor(23, 100, "sentinel", true, false), 25, "templar -> sentinel")
eq(C.ascensionFor(24, 300, "sentinel", true, false), nil, "final: an inquisitor cannot switch")
eq(C.baseOf(25), 23, "sentinel line"); eq(C.isAscended(23), false); eq(C.keystoneKey(23), nil)

-- the vocation change words name every class of the three lines
for _, w in ipairs({"monk", "shadowfist", "ironsage", "necromancer", "lich", "bonelord", "templar", "inquisitor", "sentinel"}) do
	eq(Chaos.shopServices.vocations[w] ~= nil, true, "!changevocation " .. w)
	eq(("|" .. Chaos.shopServices.vocationWords .. "|"):find("|" .. w .. "|", 1, true) ~= nil, true, "word list names " .. w)
end

print("classes_test: OK")
