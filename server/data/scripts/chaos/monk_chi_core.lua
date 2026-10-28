-- monk_chi_core.lua: the Monk line's rules that need no engine (ChaosMonk). The sixth class (docs/CLASSES.md):
-- Monk (base) -> Shadowfist | Iron Sage. A martial artist: fights unarmed (or with a staff), builds chi with basic
-- strikes and spends it on finishers whose effect grows with the chi spent.
--
-- Every id of the line (vocations, client bytes, spells, storages, condition sub ids, opcode) is in ChaosMonk.ids
-- below, and every number in ChaosMonk.cfg. Used by:
--   monk_combat.lua                the combat glue (unarmed damage, chi from hits, crits, Pressure Points, Chi Ward,
--                                  Mantra, evasion, stuns, the chi HUD)
--   data/spells/chaos/monk|shadowfist|ironsage/   the kit (they run in the spell Lua state and load this file)
-- Unit tests: server/tests/monk_test.lua (luajit and lua5.3).
--
-- Chi lives in a player storage (ids.storage.chi) with the time of its last change (ids.storage.chiTime, os.time
-- seconds): the spells and the combat script run in different Lua states, and the storage is what both see. Chi
-- not touched for cfg.chi.decaySec is gone (read as 0).
--
-- Lua dialect: LuaJIT / Lua 5.1 semantics, also valid Lua 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

ChaosMonk = ChaosMonk or {}
local M = ChaosMonk

-- ------------------------------------------------------------------------------------------------ ids (all of them)
M.ids = {
	-- vocation ids (server/data/XML/chaos_vocations_monk.xml)
	vocation = {monk = 17, shadowfist = 18, ironsage = 19},
	-- the vocation byte of the login packet (client/base-patches/0016-chaos-vocation-ids.patch): slot 8, +10 / +20 for
	-- the two ascended classes (the Necromancer has slot 7)
	clientByte = {[17] = 8, [18] = 18, [19] = 28},
	-- spell ids (below 256: the 10.98 cooldown packet sends one byte); 73, 74 kept free for the line
	spell = {
		ashenFist = 63, sunderingPalm = 64, whirlingHeel = 65, kindledBreath = 66, mistborneStrike = 67,
		pressurePoints = 68, shadowfistFlurry = 69,
		chiWard = 70, ironPalm = 71, mantraOfStone = 72
	},
	-- extended opcode of the chi HUD (server -> client, client module game_monkchi)
	opcode = 247,
	-- player storages 7100800 - 7100809 (Chaos range)
	storage = {
		chi = 7100800, -- chi points (0 .. cfg.chi.max)
		chiTime = 7100801, -- os.time of the last chi change
		focusChi = 7100802, -- Shadowfist: chi spent by the last finisher (the crit of the focus window)
		wardAmount = 7100803, -- Chi Ward: damage the shield still absorbs (on the player that carries it)
		palmChi = 7100804 -- Iron Palm on a player: the chi the strike spent, set by the spell while its damage lands
	},
	-- condition sub ids (CONDITIONID_COMBAT); CONDITION_ATTRIBUTES timers unless noted
	subId = {
		focus = 71030, -- Shadowfist focus window after a finisher (crit chance from focusChi)
		ward = 71031, -- Chi Ward shield (timer; the amount is storage.wardAmount)
		mantra = 71032, -- Mantra of Stone: damage taken reduced
		mantraDeep = 71037, -- Mantra of Stone of an Iron Sage with the passive tree's Deep Mantra (a stronger reduction)
		-- 71033 retired (the Mistborne Step dodge window, O254): never reused
		stun = 71034, -- Iron Palm stun (CONDITION_PARALYZE on a monster, CONDITION_PACIFIED on a player)
		stunImmune = 71035, -- after a stun the monster / player cannot be stunned again for a while
		stunDr = 71038, -- a player stunned within this window is stunned for less (diminishing returns)
		breath = 71036, -- Iron Sage's Kindled Breath heal over time (CONDITION_REGENERATION)
		pressure = {71040, 71041, 71042, 71043, 71044} -- Pressure Points: one timer per stack, on the target
	},
	-- the store unlock (data/scripts/chaos/class_unlocks.lua, another module): the Monk's class key
	unlockKey = "monk"
}

local V = M.ids.vocation

-- ------------------------------------------------------------------------------------------------ numbers
M.cfg = {
	chi = {
		max = 5,
		decaySec = 12, -- chi not gained or spent for this long is lost
		perWeaponHit = 1, -- a melee weapon or fist hit of the Monk (not a spell)
		weaponHitIcdMs = 2000, -- at most one chi from weapon hits per this many ms
		ashenFist = 2, -- the builder spell
		pressurePoints = 1
	},
	-- finisher effect x (base + perChi x chi): 0.44 at 1 chi, 1.0 at 5 (the spell numbers are the 5-chi values)
	finisher = {base = 0.30, perChi = 0.14, minChi = 1},
	-- unarmed hits: the engine hits with fists for attack 7 and ignores the vocation's meleeDamage; the combat script
	-- rescales a Monk's fist hit to the attack below (and the vocation multiplier `meleeDamage`)
	unarmed = {
		attackBase = 40, attackPerLevel = 0.025, attackMax = 60, -- level 300: 47.5, level 800 and up: 60
		meleeDamage = {[17] = 1.2, [18] = 1.2, [19] = 1.1},
		engineAttack = 7,
		-- fist weapons: hand items with an attack and no weapon type (the engine still fights with fists); their
		-- attack counts when it is higher than the level value. Server ids of the fist weapons (shield-type hand items
		-- with an attack; server/tools/install_fist_weapons.py, data/lib/chaos_fist_weapons.lua, tests/fist_weapons_test.lua).
		-- 22 of them, by level: 13 claws and uniques (40000-40012: 9 plain tiers from level 1 to 2200 and 4 uniques; since
		-- pair 56 only 40000-40002 wear donor looks), the first six (36654-36659) and the three of pair 56 (48409-48411).
		-- Same order as ChaosFistWeapons.ids (the test compares them)
		fistWeapons = {40000, 36654, 40009, 40010, 40001, 36655, 40002, 36656, 36657, 36658, 36659, 48409, 40003, 48410,
			40004, 48411, 40005, 40011, 40006, 40007, 40012, 40008}
	},
	-- (spellLevelScale, a level factor of the strikes that stood in for the passive tree, was dropped with the class trees:
	-- M.levelScale is 1 unless one is set here or in Chaos.classes)
	-- dodge chance against melee / ranged hits, per vocation
	evasion = {[17] = 0.06, [18] = 0.08, [19] = 0.04},
	-- Shadowfist: a finisher opens a focus window; weapon hits and Monk strikes in it crit with critPerChi x chi spent.
	-- Measured (server/data/spells/README.md "Monk line"): the window covers nearly all of the rotation's damage at
	-- 5 chi, so the total is about (crit-free total) x (1 + 0.5 x 5 x critPerChi): 0.08 gave +20% (1258 at level 300,
	-- 26% above the Ninja), 0.025 gives +6% (1078 measured, the Ninja 1001 in the same harness).
	focus = {durationMs = 4000, critPerChi = 0.025, critMultiplier = 1.5},
	-- Pressure Points: each stack makes the target take +perStack damage from Monks, maxStacks, each stack lasts
	pressure = {perStack = 0.05, maxStacks = 5, durationMs = 8000},
	-- Shadowfist Flurry: baseHits + chi hits, one every intervalMs
	flurry = {baseHits = 2, intervalMs = 200},
	-- Iron Palm stun: baseMs + perChiMs x chi; then the monster is immune for immuneMs. Monsters with more than
	-- bossHealth max health are only slowed (no attack lock).
	stun = {baseMs = 600, perChiMs = 400, immuneMs = 4000, bossHealth = 50000, bossSlow = 0.5,
		-- on a player (PvP; monk_combat.lua, only when the strike's damage landed, so every PvP rule of the engine and the
		-- scripts applies): baseMs + perChiMs x chi, at most maxMs; no moving, no attacks, no attack spells or runes
		-- (healing and potions stay). Afterwards immuneMs of immunity; a stun within drWindowMs of the last one lasts
		-- drFactor of it (at least minMs).
		pvp = {baseMs = 500, perChiMs = 100, maxMs = 1000, minMs = 300, immuneMs = 6000, drWindowMs = 15000, drFactor = 0.5}},
	-- Chi Ward: absorb = (level x perLevel + fist x perFist) x finisher scale, for durationMs, range for a party member
	ward = {perLevel = 2.5, perFist = 8, durationMs = 8000, range = 5},
	-- Kindled Breath: heal = (level x perLevel + fist x perFist) x finisher scale; Iron Sage: + hotShare over hotTicks s
	breath = {perLevel = 2.0, perFist = 6, hotShare = 0.6, hotTicks = 6},
	-- the Iron Sage, the second healer (docs/CLASSES.md): its Kindled Breath heals the most hurt party member within
	-- `range` sqm (itself without a party) for (level x perLevel + fist x perFist) x the finisher scale, + hotShare over
	-- hotTicks s. Below the Illusionist, above every non-healer: server/data/spells/README.md "Healing".
	sageBreath = {perLevel = 0, perFist = 33, range = 5},
	-- Mantra of Stone: party members within radius take `reduction` less damage while it lasts; every pulse also heals
	-- them (and the Iron Sage) for level x heal.perLevel + fist x heal.perFist
	mantra = {reduction = 0.08, durationMs = 12000, pulseMs = 2000, radius = 6, heal = {perLevel = 1.0, perFist = 26}}
}

local function cfg()
	return M.cfg
end

M.now = os.mtime or function() return os.time() * 1000 end

-- ------------------------------------------------------------------------------------------------ vocations
function M.isMonkLine(vocId)
	return vocId == V.monk or vocId == V.shadowfist or vocId == V.ironsage
end

function M.isShadowfist(vocId)
	return vocId == V.shadowfist
end

function M.isIronSage(vocId)
	return vocId == V.ironsage
end

-- Join the class framework (Chaos.classes: ids, baseOf, the !ascend choices). Idempotent; a no-op when the entries
-- were added to chaos_constants.lua already. `classes` defaults to Chaos.classes.
function M.registerClass(classes)
	classes = classes or (Chaos and Chaos.classes)
	if type(classes) ~= "table" then
		return false
	end
	classes.ids = classes.ids or {}
	classes.ids.monk, classes.ids.shadowfist, classes.ids.ironsage = V.monk, V.shadowfist, V.ironsage
	classes.baseOf = classes.baseOf or {}
	classes.baseOf[V.monk], classes.baseOf[V.shadowfist], classes.baseOf[V.ironsage] = V.monk, V.monk, V.monk
	classes.ascension = classes.ascension or {minLevel = 100, needProtectionZone = true, choices = {}}
	classes.ascension.choices = classes.ascension.choices or {}
	classes.ascension.choices[V.monk] = {shadowfist = V.shadowfist, ironsage = V.ironsage}
	return true
end
M.registerClass()

-- The store unlock (class_unlocks.lua, another module): may this player become vocation `vocId`? true when the
-- vocation is not of the Monk line or the lock module is not installed.
function M.mayBecome(player, vocId)
	if not M.isMonkLine(vocId) then
		return true
	end
	local U = rawget(_G, "ChaosClassUnlocks")
	if U and U.canUseVocation then
		local ok, msg = U.canUseVocation(player, vocId)
		if not ok then
			return false, msg or "The Monk is locked. Unlock it in the store."
		end
	end
	return true
end

-- ------------------------------------------------------------------------------------------------ chi
-- chi left after decay: `chi` stored at os.time `changedAt`, read at os.time `nowSec`
function M.chiNow(chi, changedAt, nowSec)
	chi = math.max(0, math.min(cfg().chi.max, tonumber(chi) or 0))
	if chi == 0 then
		return 0
	end
	changedAt = tonumber(changedAt) or 0
	if changedAt <= 0 or (nowSec or 0) - changedAt >= cfg().chi.decaySec then
		return 0
	end
	return chi
end

-- chi after gaining `amount` (capped at max) and how much was really gained
function M.gain(chi, amount)
	chi = math.max(0, tonumber(chi) or 0)
	local new = math.min(cfg().chi.max, chi + math.max(0, amount or 0))
	return new, new - chi
end

-- spending: a finisher takes all chi. Returns the chi spent, or nil and the reason when there is not enough.
function M.spend(chi)
	chi = math.max(0, math.min(cfg().chi.max, tonumber(chi) or 0))
	if chi < cfg().finisher.minChi then
		return nil, "You have no chi. Build it with your strikes first."
	end
	return chi
end

-- the effect factor of a finisher that spent `chi`
function M.finisherScale(chi)
	local f = cfg().finisher
	chi = math.max(0, math.min(cfg().chi.max, chi or 0))
	if chi < f.minChi then
		return 0
	end
	return f.base + f.perChi * chi
end

-- Cooldown rule of the chi from weapon hits: a hit at `now` (ms) gives chi when the last chi from a weapon hit was
-- at least weaponHitIcdMs ago (lastMs nil = never). Returns whether it gives chi.
function M.weaponHitGivesChi(lastMs, now)
	return lastMs == nil or now - lastMs >= cfg().chi.weaponHitIcdMs
end

-- ------------------------------------------------------------------------------------------------ chi on a player
-- (storage helpers; `player` is anything with getStorageValue / setStorageValue, `nowSec` defaults to os.time())
function M.getChi(player, nowSec)
	local st = M.ids.storage
	return M.chiNow(player:getStorageValue(st.chi), player:getStorageValue(st.chiTime), nowSec or os.time())
end

function M.setChi(player, chi, nowSec)
	local st = M.ids.storage
	player:setStorageValue(st.chi, chi)
	player:setStorageValue(st.chiTime, nowSec or os.time())
	M.sendChi(player, chi)
	return chi
end

-- add chi; returns the new chi
function M.addChi(player, amount, nowSec)
	nowSec = nowSec or os.time()
	local new = M.gain(M.getChi(player, nowSec), amount)
	return M.setChi(player, new, nowSec)
end

-- a finisher spends all chi: returns the chi spent, or nil and the reason (nothing changes then)
function M.takeChi(player, nowSec)
	nowSec = nowSec or os.time()
	local spent, why = M.spend(M.getChi(player, nowSec))
	if not spent then
		return nil, why
	end
	M.setChi(player, 0, nowSec)
	return spent
end

-- the HUD message (client game_monkchi): "chi:<chi>:<max>:<decaySec>"; max 0 hides the HUD
function M.hudMessage(chi, show)
	if not show then
		return "chi:0:0:0"
	end
	return string.format("chi:%d:%d:%d", chi or 0, cfg().chi.max, cfg().chi.decaySec)
end

-- sent to the Monk line only (`hide` = true sends the hide message, e.g. after a vocation change away from it)
function M.sendChi(player, chi, hide)
	if not player.sendExtendedOpcode then
		return false
	end
	local voc = player.getVocation and player:getVocation()
	local show = voc and M.isMonkLine(voc:getId()) or false
	if not show and not hide then
		return false
	end
	pcall(player.sendExtendedOpcode, player, M.ids.opcode, M.hudMessage(chi, show))
	return true
end

-- ------------------------------------------------------------------------------------------------ unarmed
-- the attack value of a Monk's fists at `level` (fistWeaponAttack: the best fist weapon in hand, or 0)
function M.fistAttack(level, fistWeaponAttack)
	local u = cfg().unarmed
	local byLevel = math.min(u.attackMax, u.attackBase + (level or 0) * u.attackPerLevel)
	return math.max(byLevel, fistWeaponAttack or 0)
end

-- the engine's maximum weapon damage (Weapons::getMaxWeaponDamage)
function M.maxWeaponDamage(level, skill, attack, attackFactor)
	attackFactor = attackFactor or 1
	return math.floor((level or 0) / 5) + ((((skill or 0) / 4) + 1) * ((attack or 0) / 3) * 1.03) / attackFactor
end

-- factor a fist hit of the engine (attack 7, no vocation multiplier) is scaled by for a Monk
function M.unarmedFactor(vocId, level, fistSkill, fistWeaponAttack, attackFactor)
	local u = cfg().unarmed
	local engine = M.maxWeaponDamage(level, fistSkill, u.engineAttack, attackFactor)
	if engine <= 0 then
		return 1
	end
	local want = M.maxWeaponDamage(level, fistSkill, M.fistAttack(level, fistWeaponAttack), attackFactor)
		* (u.meleeDamage[vocId] or 1)
	return want / engine
end

-- the fight mode's attack factor (Player::getAttackFactor): 1 offensive, 2 balanced, 3 defensive
function M.attackFactor(fightMode)
	if fightMode == 2 then
		return 1.2
	elseif fightMode == 3 then
		return 2.0
	end
	return 1.0
end

-- "fist power" of the Monk's spell strikes: fist skill x fist attack (like the Thief's sword skill x blade attack)
function M.fistPower(level, fistSkill, fistWeaponAttack)
	return (fistSkill or 0) * M.fistAttack(level, fistWeaponAttack)
end

function M.levelScale(level)
	local s = (Chaos and Chaos.classes and Chaos.classes.spellLevelScale) or cfg().spellLevelScale
	if not s then
		return 1
	end
	return math.min(s.max, 1 + math.max(0, (level or 0) - s.from) / s.per)
end

-- min, max of a Monk strike: (level / 5 + power x a + b) for min and max, x scale (finisher scale, 1 for others)
-- x the level factor. f = {minA, minB, maxA, maxB}
function M.strikeValues(level, power, f, scale)
	local l = (level or 0) / 5
	local k = (scale or 1) * M.levelScale(level)
	return (l + power * f[1] + f[2]) * k, (l + power * f[3] + f[4]) * k
end

-- the strike formulas of the spells (min a, min b, max a, max b); the finishers' are their 5-chi values
M.formula = {
	ashenFist = {0.04, 20, 0.07, 40},
	sunderingPalm = {0.20, 60, 0.30, 120},
	whirlingHeel = {0.10, 40, 0.16, 80},
	pressurePoints = {0.05, 20, 0.08, 40},
	flurryHit = {0.035, 10, 0.055, 20},
	ironPalm = {0.12, 40, 0.18, 80}
}

-- ------------------------------------------------------------------------------------------------ the finishers
function M.flurryHits(chi)
	return cfg().flurry.baseHits + math.max(0, math.min(cfg().chi.max, chi or 0))
end

-- Shadowfist focus window: crit chance of a hit for `chi` spent by the last finisher
function M.focusCritChance(chi)
	return math.max(0, math.min(cfg().chi.max, chi or 0)) * cfg().focus.critPerChi
end

-- `roll` in [0, 1): multiplier and whether it crits
function M.focusRoll(chi, roll)
	local c = M.focusCritChance(chi)
	if c > 0 and roll < c then
		return cfg().focus.critMultiplier, true
	end
	return 1, false
end

-- Pressure Points: damage multiplier on a target with `stacks` (extraPerStack: the passive tree's Nerve Strike)
function M.pressureMultiplier(stacks, extraPerStack)
	return 1 + math.max(0, math.min(cfg().pressure.maxStacks, stacks or 0)) * (cfg().pressure.perStack + (extraPerStack or 0))
end

-- which stack slot a new stack takes: `present` = list of booleans (slot i has a stack). Returns the first free
-- slot, or nil when all are taken (the caller then only refreshes them).
function M.pressureSlot(present)
	for i = 1, cfg().pressure.maxStacks do
		if not present[i] then
			return i
		end
	end
	return nil
end

-- Iron Palm: stun ms for `chi`; a boss (maxHealth above bossHealth) is only slowed, `immune` = still immune
-- Returns ms (0 = no stun), and whether it locks attacks.
function M.stunFor(chi, maxHealth, immune)
	local s = cfg().stun
	if immune or (chi or 0) < 1 then
		return 0, false
	end
	local ms = s.baseMs + s.perChiMs * math.min(cfg().chi.max, chi)
	return ms, (maxHealth or 0) <= s.bossHealth
end

-- Iron Palm on a player: stun ms for `chi`; 0 while `immune`; `diminished` = a stun within the window of the last one
function M.pvpStunFor(chi, immune, diminished)
	local s = cfg().stun.pvp
	if immune or (chi or 0) < 1 then
		return 0
	end
	local ms = math.min(s.maxMs, s.baseMs + s.perChiMs * math.min(cfg().chi.max, chi))
	if diminished then
		ms = math.max(s.minMs, math.floor(ms * s.drFactor))
	end
	return ms
end

-- players under an Iron Palm stun: [player id] = {untilMs, blocked, noMove} (monk_combat.lua; the buff bar reads it)
M.pvpStun = M.pvpStun or {}

function M.pvpStunLeft(id, now)
	local s = M.pvpStun[id]
	if s and now < s.untilMs then
		return s.untilMs - now
	end
	return nil
end

-- Chi Ward absorb for `chi` spent
function M.wardAmount(level, fistSkill, chi)
	local w = cfg().ward
	return math.floor(((level or 0) * w.perLevel + (fistSkill or 0) * w.perFist) * M.finisherScale(chi))
end

-- a hit of `damage` (positive) on a ward of `amount`: what gets through and what is left of the ward
function M.absorb(amount, damage)
	amount, damage = math.max(0, amount or 0), math.max(0, damage or 0)
	local taken = math.min(amount, damage)
	return damage - taken, amount - taken
end

-- Kindled Breath: instant heal and (Iron Sage) heal per tick over hotTicks
function M.breathHeal(level, fistSkill, chi, ironSage)
	local b = cfg().breath
	local heal = math.floor(((level or 0) * b.perLevel + (fistSkill or 0) * b.perFist) * M.finisherScale(chi))
	local tick = 0
	if ironSage and heal > 0 then
		tick = math.floor(heal * b.hotShare / b.hotTicks)
	end
	return heal, tick
end

-- the Iron Sage's Kindled Breath on a party member: instant heal and heal per tick (hotShare over hotTicks)
function M.sageBreathHeal(level, fistSkill, chi)
	local s, b = cfg().sageBreath, cfg().breath
	local heal = math.floor(((level or 0) * s.perLevel + (fistSkill or 0) * s.perFist) * M.finisherScale(chi))
	local tick = heal > 0 and math.floor(heal * b.hotShare / b.hotTicks) or 0
	return heal, tick
end

-- the heal of a Mantra of Stone pulse on each covered player
function M.mantraHeal(level, fistSkill)
	local h = cfg().mantra.heal
	return math.floor((level or 0) * h.perLevel + (fistSkill or 0) * h.perFist)
end

-- damage taken with the Mantra of Stone (reduction: the Deep Mantra one, else the spell's)
function M.mantraDamage(damage, reduction)
	return math.floor(math.abs(damage or 0) * (1 - (reduction or cfg().mantra.reduction)) + 0.5)
end

-- Hundred Hands (Shadowfist keystone): a focus crit gives a chi when the last one was at least icdMs ago
M.lastCritChi = M.lastCritChi or {}
function M.critGivesChi(id, now, icdMs)
	local last = M.lastCritChi[id]
	if last and now - last < icdMs then
		return false
	end
	M.lastCritChi[id] = now
	return true
end

-- dodge chance of a Monk
function M.dodgeChance(vocId)
	return cfg().evasion[vocId] or 0
end

-- noDodge: Scarred Discipline (the line keystone) takes the evasion away
function M.dodges(vocId, isWeaponAttack, roll, noDodge)
	if noDodge then
		return false
	end
	return isWeaponAttack and roll < M.dodgeChance(vocId) or false
end

-- Scarred Discipline (the line keystone, class_tree.lua fx.ksScarredDiscipline): a hit taken gives fx.chi when the last
-- such chi was at least fx.icdMs ago (pure, per player id)
M.lastScarChi = M.lastScarChi or {}
function M.scarGivesChi(id, now, fx)
	local last = M.lastScarChi[id]
	if last and now - last < fx.icdMs then
		return false
	end
	M.lastScarChi[id] = now
	return true
end

-- Scarred Discipline: the factor on damage taken while holding `chi` (before this hit's chi)
function M.scarFactor(chi, fx)
	if fx and (chi or 0) >= fx.minChi then
		return 1 - fx.reduction
	end
	return 1
end

-- forget per-creature memory (logout, death)
M.lastWeaponChi = M.lastWeaponChi or {}
function M.clear(id)
	M.lastWeaponChi[id] = nil
	M.lastCritChi[id] = nil
	M.lastScarChi[id] = nil
end

return M
