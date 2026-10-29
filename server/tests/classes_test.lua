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
local keys = {[4] = "knight", [8] = "juggernaut", [14] = "berserker", [3] = "paladin", [7] = "deadeye", [15] = "beastmaster",
  [1] = "sorcerer", [5] = "sorcerer", [10] = "illusionist"}
for v, k in pairs(keys) do eq(C.keystoneKey(v), k, "keystone key " .. v) end
eq(C.keystoneKey(12), "ninja", "the class sections: the class key")
-- class keys and lines (the passive tree's class nodes)
local classKeys = {[4] = "warrior", [8] = "juggernaut", [14] = "berserker", [3] = "ranger", [7] = "deadeye",
  [15] = "beastmaster", [1] = "mystic", [5] = "elementalist", [10] = "illusionist", [11] = "thief", [12] = "ninja",
  [13] = "samurai", [17] = "monk", [18] = "shadowfist", [19] = "ironsage", [20] = "necromancer", [21] = "lich",
  [22] = "bonelord", [23] = "templar", [24] = "inquisitor", [25] = "sentinel"}
for v, k in pairs(classKeys) do eq(C.classKey(v), k, "class key " .. v) end
eq(C.classKey(2), nil, "retired"); eq(C.lineKey(13), "thief"); eq(C.lineKey(25), "templar"); eq(C.lineKey(8), "warrior")
eq(C.lineKey(0), nil)

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
-- O306: auto bites on their own constants, the spells' bite untouched
local alo, ahi = C.autoBiteValues(1000, 140)
local aavg = 1000 * cfg.companion.autoLevel + 140 * cfg.companion.autoSkill
eq(alo, math.floor(aavg * (1 - cfg.companion.spread)), "auto bite min"); eq(ahi, math.floor(aavg * (1 + cfg.companion.spread)), "auto bite max")
assert(ahi > hi, "the companion's own bite is above a spell's bite")
local blo, bhi = C.autoBiteValues(1000, 140, 1.35)
assert(bhi > ahi and blo > alo, "Pack Alpha raises the auto bite")
eq(C.companionLevel(412), 412, "the companion shows its owner's level"); eq(C.companionLevel(0), 1, "at least 1")
-- a hit on a companion: cfg.taken of it, less with Pack Alpha
eq(C.companionDamageTaken(1000, 0), math.floor(1000 * cfg.companion.taken + 0.5), "taken share")
assert(C.companionDamageTaken(1000, 0.25) < C.companionDamageTaken(1000, 0), "Pack Alpha cuts more")
eq(C.companionDamageTaken(0, 0.25), 0, "no damage")
eq(C.companionRescale(1000, 500, 2000), 1000, "same share"); eq(C.companionRescale(1000, 1, 10), 1, "at least 1")
eq(C.companionRescale(0, 0, 700), 700, "no old maximum: full")

-- every path of a companion scales the same (O306 beta report: a wolf was shown at level 12 or 300, the level of the wild
-- War Wolf or of the hunt it stood in, never its owner's). A mock monster born as the spawn callback leaves it.
local function mockMonster(shown, maxHp, hp)
	local m = {shown = shown, maxHp = maxHp, hp = hp}
	function m:getMaxHealth() return self.maxHp end
	function m:setMaxHealth(v) self.maxHp = v; self.hp = math.min(self.hp, v) end
	function m:getHealth() return self.hp end
	function m:addHealth(_, v) self.hp = math.min(self.maxHp, self.hp + v) end
	function m:setDisplayLevel(v) self.shown = v end
	function m:getDisplayLevel() return self.shown end
	return m
end
local function owner(level) return {getLevel = function() return level end} end
local wild = {{12, 140, 140}, {300, 140, 140}, {12, 6500, 6500}} -- the spawn callback's level (wild, or the hunt's) and health
for _, w in ipairs(wild) do
	local o = owner(400)
	local m = mockMonster(w[1], w[2], w[3])
	eq(C.syncCompanion(o, m, true), true, "a fresh companion changes")
	eq(m.shown, 400, "spawn: shown level is the owner's (" .. w[1] .. ")")
	eq(m.maxHp, C.companionHealth(400), "spawn: maximum health"); eq(m.hp, m.maxHp, "spawn: full health")
	eq(C.syncCompanion(o, m, false), false, "the tick leaves a synced companion alone")
	-- the owner levels up: the tick, the call-back (Wild Bond with a companion out) and a login all end in the same state
	m.hp = m.maxHp / 2
	o = owner(450)
	eq(C.syncCompanion(o, m, false), true, "level up: changed")
	eq(m.shown, 450, "level up: shown level"); eq(m.maxHp, C.companionHealth(450), "level up: maximum health")
	eq(m.hp, math.floor(C.companionHealth(450) / 2 + 0.5), "level up: the same share of health")
	local fresh = mockMonster(w[1], w[2], w[3])
	C.syncCompanion(o, fresh, true)
	eq(fresh.shown, m.shown, "same shown level on every path"); eq(fresh.maxHp, m.maxHp, "same maximum health on every path")
end
local old = mockMonster(nil, 6500, 100) -- an engine without setDisplayLevel: health still scales
old.setDisplayLevel, old.getDisplayLevel = nil, nil
C.syncCompanion(owner(100), old, true)
eq(old.maxHp, C.companionHealth(100), "no display method: health scales")

eq(C.isBerserker(14), true); eq(C.isBeastmaster(15), true); eq(C.isBeastmaster(7), false)

-- ------------------------------------------------------------------ light blades and dual wield
eq(C.isLightBlade(WEAPON_SWORD, 48), true, "one-handed sword")
eq(C.isLightBlade(WEAPON_SWORD, 48 + SLOTP_TWO_HAND), false, "two-handed sword")
eq(C.isLightBlade(WEAPON_CLUB, 48), false, "club")
eq(C.isLightBlade(nil, 48), false, "no item")

eq(C.dualWieldProc(NINJA, true, true, true, false, 300), true, "ninja, two blades, melee hit")
eq(C.dualWieldProc(THIEF, true, true, true, false, 300), true, "the thief dual wields since 2026-10-23")
eq(C.dualWieldProc(4, true, true, true, false, 300), false, "not the warrior")
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
-- 2026-10-17 (owner: "O poison do thief é muito fraco"): a tick is 30% of the hit (share 1.2 over 4 ticks) for the Thief and
-- the Samurai, 18% for the Ninja (classScale 0.6: the Deadeye keeps its lead); 15% before
eq(cfg.poisonBlades.share, 1.2, "Poison Blades share 1.2 (was 0.6)")
eq(C.poisonTick(1000, 0, THIEF), 300, "Thief: a tick is 30% of the hit")
eq(C.poisonTick(1000, 0, SAMURAI), 300, "Samurai: 30%")
eq(C.poisonTick(1000, 0, NINJA), 180, "Ninja: 18% (classScale 0.6)")
eq(C.poisonTick(1000, 0.3, THIEF), 390, "Thief with the Creed's +30%")
eq(C.poisonTick(1000, 0, 4), 300, "a vocation without a classScale: the plain share")

-- ------------------------------------------------------------------ the Monk, Necromancer and Templar lines
-- (ids and choices in chaos_constants.lua; each line's own rules: tests/monk_test.lua, necro_test.lua, templar_test.lua)
eq(cfg.ids.monk, 17); eq(cfg.ids.shadowfist, 18); eq(cfg.ids.ironsage, 19)
eq(C.ascensionFor(17, 100, "shadowfist", true, false), 18, "monk -> shadowfist")
eq(C.ascensionFor(17, 100, "ironsage", true, false), 19, "monk -> iron sage")
eq(C.ascensionFor(17, 99, "ironsage", true, false), nil, "monk: level 100")
eq(C.ascensionFor(18, 300, "ironsage", true, false), nil, "final: a shadowfist cannot switch")
eq(C.ascensionFor(11, 300, "shadowfist", true, false), nil, "not a choice of the thief")
eq(C.baseOf(19), 17, "iron sage line"); eq(C.isAscended(18), true); eq(C.isThiefLine(17), false)
eq(C.keystoneKey(17), "monk", "the Monk: its class section")

eq(C.ascensionFor(20, 100, "lich", true, false), 21, "necromancer -> lich")
eq(C.ascensionFor(20, 300, " BoneLord ", true, false), 22, "necromancer -> bone lord (trimmed, case-free)")
eq(C.ascensionFor(20, 99, "lich", true, false), nil, "necromancer level 99 refused")
eq(C.ascensionFor(21, 300, "bonelord", true, false), nil, "an ascended lich cannot ascend again")
eq(C.baseOf(22), 20, "bone lord's base"); eq(C.isAscended(21), true, "lich is ascended")
eq(C.keystoneKey(20), "necromancer", "its class section")
local necroCfg = dofile("data/scripts/chaos/necro_config.lua")
for key, vid in pairs(necroCfg.ids) do eq(cfg.ids[key], vid, "Chaos.classes.ids." .. key .. " = necro_config.lua") end

eq(cfg.ids.templar, 23); eq(cfg.ids.inquisitor, 24); eq(cfg.ids.sentinel, 25)
eq(C.ascensionFor(23, 100, "inquisitor", true, false), 24, "templar -> inquisitor")
eq(C.ascensionFor(23, 100, "sentinel", true, false), 25, "templar -> sentinel")
eq(C.ascensionFor(24, 300, "sentinel", true, false), nil, "final: an inquisitor cannot switch")
eq(C.baseOf(25), 23, "sentinel line"); eq(C.isAscended(23), false); eq(C.keystoneKey(23), "templar")

-- the vocation change words name every class of the three lines
for _, w in ipairs({"monk", "shadowfist", "ironsage", "necromancer", "lich", "bonelord", "templar", "inquisitor", "sentinel"}) do
	eq(Chaos.shopServices.vocations[w] ~= nil, true, "!changevocation " .. w)
	eq(("|" .. Chaos.shopServices.vocationWords .. "|"):find("|" .. w .. "|", 1, true) ~= nil, true, "word list names " .. w)
end

-- ------------------------------------------------------------------ class outfits: 1559 retired, the replacement switch
do
	local MYSTIC, ELEMENTALIST, ILLUSIONIST = 1, 5, 10
	local r = cfg.outfitReplacement
	eq(r.enabled, true, "the replacement switch (pair 29) is on")
	local shipped = r.enabled
	r.enabled = false -- the checks below set the switch themselves
	eq(r.replaces, 1559, "it replaces the Archmage")
	eq(r.outfit.lookType, 2235, "the pair 29 Archmage, male"); eq(r.outfit.female, 2236, "the pair 29 Archmage, female")
	eq(r.outfit.name, "Archmage", "named Archmage"); eq(r.outfit.addons, 3, "with both addons")
	eq(C.isRetiredOutfit(1559), true, "1559 is retired"); eq(C.isRetiredOutfit(1558), false, "the Ranger's is not")
	eq(cfg.retiredOutfits[1].name, "Archmage (old)", "kept wearable under its old name")
	-- nobody is given 1559 or the pair 29 looks while the switch is off, at a login or a class change
	for vocId = 0, 30 do
		for _, sex in ipairs({0, 1}) do
			for _, o in ipairs(C.classOutfitsFor(vocId, sex)) do
				eq(o.lookType ~= 1559 and o.lookType ~= 2235 and o.lookType ~= 2236, true, "vocation " .. vocId .. " is given 1559 or 2235/2236")
			end
			eq(C.outfitSwap(vocId, 1559, sex), nil, "switch off: no swap for vocation " .. vocId)
		end
	end
	for _, v in ipairs({MYSTIC, ELEMENTALIST, ILLUSIONIST}) do
		eq(#C.classOutfitsFor(v), 0, "the Mystic line has no donor art outfit while the switch is off")
	end
	eq(C.classOutfitsFor(12)[1].lookType, 1505, "the other classes keep theirs (Ninja)")
	-- the switch line is one plain line (install_outfits.py and gen_shop_cosmetics.py read it)
	local src = io.open("data/scripts/chaos/chaos_constants.lua"):read("*a")
	eq(src:match("\n\toutfitReplacement = {\n\t\tenabled = (%a+),\n"), tostring(shipped), "the switch is one plain line")
	-- on, with no outfit set: still nothing
	local outfit = r.outfit
	r.enabled, r.outfit = true, nil
	eq(#C.classOutfitsFor(MYSTIC), 0, "on without an outfit: nothing given")
	eq(C.outfitSwap(MYSTIC, 1559), nil, "on without an outfit: no swap")
	-- on, with the pair 29 outfit: the Mystic line gets the look of its sex with both addons, wearers of 1559 (or of
	-- the other sex's Archmage) are moved, other classes untouched
	r.outfit = outfit
	for _, v in ipairs({MYSTIC, ELEMENTALIST, ILLUSIONIST}) do
		local male, female = C.classOutfitsFor(v, 1), C.classOutfitsFor(v, 0)
		eq(#male, 1, "one outfit for vocation " .. v); eq(male[1].lookType, 2235, "his Archmage")
		eq(female[1].lookType, 2236, "her Archmage"); eq(male[1].addons, 3, "both addons")
		eq(C.classOutfitsFor(v)[1].lookType, 2235, "no sex given: the male look")
		eq(C.outfitSwap(v, 1559, 1), 2235, "1559 wearer moved, his look, vocation " .. v)
		eq(C.outfitSwap(v, 1559, 0), 2236, "1559 wearer moved, her look, vocation " .. v)
		eq(C.outfitSwap(v, 2235, 0), 2236, "the other sex's Archmage moved, vocation " .. v)
		eq(C.outfitSwap(v, 2236, 0), nil, "her own Archmage stays, vocation " .. v)
		eq(C.outfitSwap(v, 2060, 1), nil, "another look stays, vocation " .. v)
	end
	eq(C.outfitSwap(4, 1559, 1), nil, "a Warrior wearing 1559 keeps it")
	eq(#C.classOutfitsFor(4), 1, "the Warrior keeps only its own"); eq(C.classOutfitsFor(4)[1].lookType, 1551, "Warborn")
	-- one look for both sexes (no `female`): the same look type for both
	r.outfit = {lookType = 2999, name = "Archmage"}
	eq(C.classOutfitsFor(MYSTIC, 0)[1].lookType, 2999, "one look: hers"); eq(C.outfitSwap(MYSTIC, 1559, 0), 2999, "one look: moved")
	r.outfit = outfit
	-- off again: back to nothing
	r.enabled = false
	eq(#C.classOutfitsFor(MYSTIC), 0, "off again"); eq(C.outfitSwap(MYSTIC, 1559), nil, "off again: no swap")
	r.enabled = shipped
end

-- ------------------------------------------------------------------ dual wield for the Thief, attack speed (2026-10-23)
do
	eq(C.isDualWielder(THIEF) and C.isDualWielder(NINJA), true, "thief and ninja dual wield")
	eq(C.isDualWielder(SAMURAI), false, "the samurai keeps one sword"); eq(C.isDualWielder(17), false, "monk")

	-- the vocation table (chaos_vocations*.xml) against Chaos.classes.attackSpeed: the Thief ties with the Monk and is
	-- faster than every class outside the two lines; the ascended classes tie with the Monk line's
	local speeds = {}
	for _, f in ipairs({"chaos_vocations", "chaos_vocations_monk", "chaos_vocations_necro", "chaos_vocations_templar"}) do
		local fh = assert(io.open("data/XML/" .. f .. ".xml", "r"))
		local text = fh:read("*a"); fh:close()
		for tag in text:gmatch("<vocation [^>]*>") do
			local id, spd = tag:match('id="(%d+)"'), tag:match('attackspeed="(%d+)"')
			if id and spd then speeds[tonumber(id)] = tonumber(spd) end
		end
	end
	local MONK = cfg.ids.monk
	eq(speeds[THIEF], speeds[MONK], "thief attacks as fast as the monk")
	eq(speeds[NINJA], speeds[18], "ninja ties with the shadowfist"); eq(speeds[SAMURAI], speeds[19], "samurai ties with the iron sage")
	for id, spd in pairs(speeds) do
		local line = C.isThiefLine(id) or cfg.baseOf[id] == MONK
		if not line then
			eq(spd, 2000, "vocation " .. id .. " keeps the stock interval")
			assert(speeds[THIEF] < spd, "the thief is faster than vocation " .. id)
		end
	end
	for id, a in pairs(cfg.attackSpeed) do
		eq(speeds[id], a.now, "attackSpeed table matches the xml for " .. id)
		assert(a.now < a.was, "shortened")
		eq(C.speedComp(id), a.now / a.was, "speedComp " .. id)
	end
	eq(C.speedComp(4), 1, "warrior: no compensation"); eq(C.speedComp(MONK), 1, "monk: none")
	-- damage per second: hit x comp / now interval = hit / was interval
	for id, a in pairs(cfg.attackSpeed) do
		assert(math.abs(C.speedComp(id) / a.now - 1 / a.was) < 1e-12, "dps unchanged for " .. id)
	end

	-- dual neutral: two equal daggers: the Thief's main + off-hand strike deal one old hit; the Ninja is not cut
	local n = C.dualNeutral(THIEF, 20, 20)
	assert(math.abs(n - 1 / 1.5) < 1e-12, "thief main hit x 2/3")
	local main = 300 * n
	local off = C.offhandDamage(main, 20, 20, false, 0)
	assert(math.abs(main + off - 300) <= 1, "thief swing total is the old hit")
	eq(C.dualNeutral(NINJA, 20, 20), 1, "ninja not cut"); eq(C.dualNeutral(SAMURAI, 20, 20), 1, "samurai")
	assert(math.abs(C.dualNeutral(THIEF, 20, 40) - 1 / (1 + 0.5 * 1.25)) < 1e-12, "clamped high")
	assert(math.abs(C.dualNeutral(THIEF, 20, 2) - 1 / (1 + 0.5 * 0.5)) < 1e-12, "clamped low")
	-- Twin Fangs stays a bonus on top of the neutral cut
	assert(C.offhandDamage(main, 20, 20, false, 0.15) > off, "twin fangs adds")

	-- the one-time second dagger of a Thief made before
	eq(C.offhandGrant(THIEF, -1, true, nil), "grant", "thief with a dagger and an empty off hand")
	eq(C.offhandGrant(THIEF, 0, true, nil), "grant", "flag 0")
	eq(C.offhandGrant(THIEF, 1700000000, true, nil), nil, "once only")
	eq(C.offhandGrant(THIEF, -1, true, "blade"), "mark", "already two blades: mark, give nothing")
	eq(C.offhandGrant(THIEF, -1, true, "other"), nil, "a shield stays")
	eq(C.offhandGrant(THIEF, -1, false, nil), nil, "no main-hand blade (new character before the kit)")
	eq(C.offhandGrant(NINJA, -1, true, nil), nil, "ninja: not granted"); eq(C.offhandGrant(SAMURAI, -1, true, nil), nil, "samurai")
	eq(C.offhandGrant(4, -1, true, nil), nil, "warrior")
	assert(cfg.storage.offhandGranted == 7100204 and cfg.storage.offhandGranted ~= cfg.storage.freeSwitch, "own storage key")

	-- login sync and grant on a mocked player
	local stor, items, given = {}, {}, {}
	local function mk(voc, left, right)
		local p = {}
		items[CONST_SLOT_LEFT] = left; items[CONST_SLOT_RIGHT] = right
		function p:getVocation() return {getId = function() return voc end} end
		function p:getStorageValue(k) return stor[k] or -1 end
		function p:setStorageValue(k, v) stor[k] = v end
		function p:getSlotItem(slot) return items[slot] end
		function p:addItem(id, n, drop, sub, slot)
			given[#given + 1] = {id, slot}
			items[slot] = {getId = function() return id end}
			return items[slot]
		end
		function p:sendTextMessage() end
		return p
	end
	CONST_SLOT_LEFT, CONST_SLOT_RIGHT, MESSAGE_EVENT_ADVANCE = 6, 5, 1
	function ItemType(id)
		return {getWeaponType = function() return id == 2379 and WEAPON_SWORD or WEAPON_CLUB end,
			getSlotPosition = function() return 48 end}
	end
	local dagger = {getId = function() return 2379 end}
	local shield = {getId = function() return 2525 end}
	stor = {}; given = {}
	local p = mk(THIEF, dagger, nil)
	C.syncDualWield(p); eq(stor[cfg.storage.dualWield], 1, "thief: dual wield storage 1")
	eq(C.grantOffhand(p), "grant", "granted"); eq(#given, 1, "one dagger"); eq(given[1][1], 2379, "a dagger")
	eq(given[1][2], CONST_SLOT_RIGHT, "in the off hand")
	assert(stor[cfg.storage.offhandGranted] > 0, "flag set")
	eq(C.grantOffhand(p), nil, "second login: nothing"); eq(#given, 1, "still one")
	items[CONST_SLOT_RIGHT] = nil; eq(C.grantOffhand(p), nil, "the dagger sold: never again"); eq(#given, 1, "still one dagger")
	stor = {}; given = {}
	p = mk(THIEF, dagger, shield); eq(C.grantOffhand(p), nil, "shield: nothing"); eq(#given, 0, "no dagger")
	eq(stor[cfg.storage.offhandGranted], nil, "flag open")
	p = mk(THIEF, dagger, dagger); eq(C.grantOffhand(p), "mark", "two daggers: marked"); eq(#given, 0, "nothing given")
	assert(stor[cfg.storage.offhandGranted] > 0, "marked")
	stor = {}; p = mk(NINJA, dagger, nil); C.syncDualWield(p); eq(stor[cfg.storage.dualWield], 1, "ninja still dual wields")
	stor = {}; p = mk(SAMURAI, dagger, nil); C.syncDualWield(p); eq(stor[cfg.storage.dualWield] or -1, -1, "samurai does not")
end

print("classes_test: OK")
