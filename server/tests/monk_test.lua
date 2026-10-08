-- Run from the server/ folder: luajit tests/monk_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the Monk line's rules (data/scripts/chaos/monk_chi_core.lua): the ids, joining the class framework (the
-- !ascend choices through classes.lua), the store gate, chi gain / spend / decay on a mocked player, the weapon-hit
-- chi cooldown, finisher scaling, the unarmed damage factor, the Shadowfist focus crit, Pressure Points, the Iron
-- Palm stun rules, Chi Ward absorption, Kindled Breath, the Mantra, evasion and the HUD message.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
dofile("data/scripts/chaos/monk_chi_core.lua")
local M = ChaosMonk
local C = ChaosClasses
local cfg = M.cfg

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function near(a, b, m) if math.abs(a - b) > 1e-6 then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

-- ------------------------------------------------------------------ ids
local MONK, SF, IS = 17, 18, 19
eq(M.ids.vocation.monk, MONK); eq(M.ids.vocation.shadowfist, SF); eq(M.ids.vocation.ironsage, IS)
eq(M.ids.clientByte[MONK], 8); eq(M.ids.clientByte[SF], 18); eq(M.ids.clientByte[IS], 28)
local seen = {}
for name, id in pairs(M.ids.spell) do
	eq(id >= 63 and id <= 74, true, "spell id in 63-74: " .. name)
	eq(seen[id], nil, "spell id unique: " .. id)
	seen[id] = true
end
for k, v in pairs(M.ids.storage) do
	eq(v >= 7100800 and v <= 7100809, true, "storage in the Monk range: " .. k)
end
eq(M.isMonkLine(MONK) and M.isMonkLine(SF) and M.isMonkLine(IS), true, "monk line")
eq(M.isMonkLine(11), false, "thief is not"); eq(M.isMonkLine(20), false, "the necromancer's ids are not")
eq(M.isShadowfist(SF), true); eq(M.isShadowfist(IS), false); eq(M.isIronSage(IS), true)

-- ------------------------------------------------------------------ the class framework and !ascend
eq(Chaos.classes.baseOf[SF], MONK, "joined baseOf"); eq(Chaos.classes.ids.ironsage, IS, "joined ids")
eq(M.registerClass(), true, "idempotent")
eq(C.isAscended(SF), true); eq(C.isAscended(MONK), false); eq(C.baseOf(IS), MONK)
eq(C.ascensionFor(MONK, 100, "shadowfist", true, false), SF, "monk -> shadowfist")
eq(C.ascensionFor(MONK, 300, " IronSage ", true, false), IS, "monk -> iron sage (trimmed, case-free)")
local id, why = C.ascensionFor(MONK, 300, "", true, false)
eq(id, nil, "no choice"); eq(why:find("ironsage|shadowfist", 1, true) ~= nil, true, "lists the choices: " .. why)
eq(C.ascensionFor(MONK, 99, "shadowfist", true, false), nil, "level 100")
eq(C.ascensionFor(MONK, 300, "ninja", true, false), nil, "not a choice of the monk")
id, why = C.ascensionFor(SF, 300, "ironsage", true, false)
eq(id, nil, "final"); eq(why:find("Vocation Change") ~= nil, true)
eq(C.ascensionFor(11, 300, "shadowfist", true, false), nil, "not a choice of the thief")
eq(C.ascensionFor(11, 300, "ninja", true, false), 12, "the thief's own choice still works")

-- the store gate (class_unlocks.lua is another module): open without it, closed when it says so
eq(M.mayBecome({}, SF), true, "no lock module: allowed")
eq(M.mayBecome({}, 12), true, "other classes are not the Monk's business")
ChaosClassUnlocks = {canUseVocation = function(player, vocId) return player.unlocked, "locked" end}
local ok, msg = M.mayBecome({unlocked = false}, MONK)
eq(ok, false, "locked"); eq(msg, "locked")
eq(M.mayBecome({unlocked = true}, IS), true, "unlocked")
ChaosClassUnlocks = nil

-- ------------------------------------------------------------------ chi rules
eq(cfg.chi.max, 5)
eq(M.chiNow(3, 1000, 1005), 3, "fresh")
eq(M.chiNow(3, 1000, 1000 + cfg.chi.decaySec), 0, "decayed")
eq(M.chiNow(9, 1000, 1001), 5, "clamped to max")
eq(M.chiNow(-1, 0, 5), 0, "unset storage")
local new, gained = M.gain(4, 2)
eq(new, 5, "gain caps"); eq(gained, 1, "only 1 really gained")
eq(select(1, M.gain(0, 2)), 2)
eq(M.spend(0), nil, "no chi, no finisher"); eq(select(2, M.spend(0)):find("no chi") ~= nil, true)
eq(M.spend(3), 3, "spends all")
-- weapon-hit chi cooldown
eq(M.weaponHitGivesChi(nil, 5000), true, "first hit")
eq(M.weaponHitGivesChi(5000, 5000 + cfg.chi.weaponHitIcdMs - 1), false, "inside the cooldown")
eq(M.weaponHitGivesChi(5000, 5000 + cfg.chi.weaponHitIcdMs), true, "after it")

-- on a mocked player (storages, HUD messages)
local function mockPlayer(voc)
	local p = {st = {}, sent = {}, voc = voc}
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:getVocation() local v = self.voc return {getId = function() return v end} end
	function p:sendExtendedOpcode(op, msg) self.sent[#self.sent + 1] = {op, msg} end
	return p
end
local p = mockPlayer(MONK)
eq(M.getChi(p, 100), 0, "starts empty")
eq(M.addChi(p, 2, 100), 2); eq(M.addChi(p, 2, 101), 4); eq(M.addChi(p, 2, 102), 5, "capped")
eq(p.sent[#p.sent][1], M.ids.opcode, "HUD opcode"); eq(p.sent[#p.sent][2], "chi:5:5:12", "HUD message")
eq(M.getChi(p, 102 + cfg.chi.decaySec - 1), 5, "kept while fresh")
eq(M.takeChi(p, 103), 5, "finisher takes all"); eq(M.getChi(p, 103), 0, "empty after")
eq(M.takeChi(p, 104), nil, "nothing to take")
M.addChi(p, 3, 200)
eq(M.getChi(p, 200 + cfg.chi.decaySec), 0, "decays")
eq(M.takeChi(p, 200 + cfg.chi.decaySec), nil, "decayed chi cannot be spent")
local other = mockPlayer(11)
eq(M.sendChi(other, 3), false, "no HUD for other classes")
eq(M.sendChi(other, 0, true), true, "the hide message"); eq(other.sent[1][2], "chi:0:0:0")

-- ------------------------------------------------------------------ finisher scaling
eq(M.finisherScale(0), 0, "0 chi: nothing")
near(M.finisherScale(1), 0.44, "1 chi"); near(M.finisherScale(5), 1.0, "5 chi is the formula value")
near(M.finisherScale(9), 1.0, "clamped")
for c = 1, 4 do eq(M.finisherScale(c) < M.finisherScale(c + 1), true, "grows with chi " .. c) end
eq(M.flurryHits(1), 3); eq(M.flurryHits(5), 7); eq(M.flurryHits(8), 7, "clamped")
local a1, b1 = M.strikeValues(300, 5000, M.formula.sunderingPalm, M.finisherScale(5))
local a2, b2 = M.strikeValues(300, 5000, M.formula.sunderingPalm, M.finisherScale(1))
near(a2 / a1, 0.44, "min scales"); near(b2 / b1, 0.44, "max scales")
near(M.levelScale(300), 1); near(M.levelScale(1000), 2); near(M.levelScale(5000), Chaos.classes.spellLevelScale.max)
local lo, hi = M.strikeValues(1000, 5000, M.formula.ashenFist)
near(lo, (200 + 5000 * 0.04 + 20) * 2, "level 1000 strike x2")

-- ------------------------------------------------------------------ unarmed
near(M.fistAttack(300), 47.5); eq(M.fistAttack(1000), cfg.unarmed.attackMax); eq(M.fistAttack(8), 40.2)
eq(M.fistAttack(300, 80), 80, "a better fist weapon wins")
near(M.maxWeaponDamage(300, 110, 7), 60 + (28.5 * 7 / 3 * 1.03), "engine formula")
local f = M.unarmedFactor(MONK, 300, 110, 0, 1)
near(f, (60 + 28.5 * 47.5 / 3 * 1.03) * 1.2 / (60 + 28.5 * 7 / 3 * 1.03), "fist factor")
eq(f > 4 and f < 6, true, "about x5 at level 300: " .. f)
eq(M.unarmedFactor(IS, 300, 110, 0, 1) < f, true, "the iron sage hits softer")
eq(M.unarmedFactor(MONK, 300, 110, 0, 2) > 0, true, "defensive mode still scales")
near(M.attackFactor(1), 1); near(M.attackFactor(2), 1.2); near(M.attackFactor(3), 2)
eq(M.fistPower(300, 110), 110 * 47.5)

-- ------------------------------------------------------------------ shadowfist focus, pressure points
near(M.focusCritChance(5), 0.40); near(M.focusCritChance(0), 0)
eq(select(2, M.focusRoll(5, 0.39)), true, "crit"); eq(select(2, M.focusRoll(5, 0.40)), false, "no crit")
eq(M.focusRoll(5, 0.1), cfg.focus.critMultiplier)
eq(select(2, M.focusRoll(0, 0)), false, "no chi, no crit")
near(M.pressureMultiplier(0), 1); near(M.pressureMultiplier(5), 1.25); near(M.pressureMultiplier(9), 1.25)
eq(M.pressureSlot({}), 1); eq(M.pressureSlot({true, true, false}), 3)
eq(M.pressureSlot({true, true, true, true, true}), nil, "full: only refresh")

-- ------------------------------------------------------------------ iron palm stun
local ms, locks = M.stunFor(5, 10000, false)
eq(ms, 2600); eq(locks, true, "a normal monster is stunned")
eq(M.stunFor(1, 10000, false), 1000)
eq(M.stunFor(0, 10000, false), 0, "no chi, no stun")
eq(M.stunFor(5, 10000, true), 0, "immune after a stun")
ms, locks = M.stunFor(5, cfg.stun.bossHealth + 1, false)
eq(ms > 0 and not locks, true, "a boss is only slowed")

-- ------------------------------------------------------------------ chi ward, breath, mantra
eq(M.wardAmount(300, 110, 5), math.floor(300 * 2.5 + 110 * 8), "ward at 5 chi")
eq(M.wardAmount(300, 110, 0), 0, "no chi")
local through, left = M.absorb(1000, 300)
eq(through, 0); eq(left, 700)
through, left = M.absorb(200, 300)
eq(through, 100, "the rest gets through"); eq(left, 0)
eq(select(1, M.absorb(0, 300)), 300, "no ward")
local heal, tick = M.breathHeal(300, 110, 5, false)
eq(heal, 300 * 2 + 110 * 6); eq(tick, 0, "only the iron sage heals over time")
heal, tick = M.breathHeal(300, 110, 5, true)
eq(tick, math.floor(heal * 0.6 / 6), "iron sage heal over time")
eq(M.mantraDamage(-1000), 920, "8% less"); eq(M.mantraDamage(0), 0)

-- ------------------------------------------------------------------ evasion
near(M.dodgeChance(MONK), 0.06); near(M.dodgeChance(SF), 0.08); near(M.dodgeChance(IS), 0.04)
near(M.dodgeChance(MONK, true), 0.31, "rolling")
eq(M.dodgeChance(4, true), 0, "not a monk")
eq(M.dodges(SF, true, false, 0.05), true); eq(M.dodges(SF, false, false, 0.0), false, "spells are not dodged")
eq(M.dodges(IS, true, false, 0.05), false)

print("monk tests OK")
