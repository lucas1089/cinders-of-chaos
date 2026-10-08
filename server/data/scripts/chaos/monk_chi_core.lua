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
		ashenFist = 63, sunderingPalm = 64, whirlingHeel = 65, kindledBreath = 66, mistborneStep = 67,
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
		wardAmount = 7100803 -- Chi Ward: damage the shield still absorbs (on the player that carries it)
	},
	-- condition sub ids (CONDITIONID_COMBAT); CONDITION_ATTRIBUTES timers unless noted
	subId = {
		focus = 71030, -- Shadowfist focus window after a finisher (crit chance from focusChi)
		ward = 71031, -- Chi Ward shield (timer; the amount is storage.wardAmount)
		mantra = 71032, -- Mantra of Stone: damage taken reduced
		roll = 71033, -- Mistborne Step: dodge window
		stun = 71034, -- Iron Palm stun (CONDITION_PARALYZE on the monster)
		stunImmune = 71035, -- after a stun the monster cannot be stunned again for a while
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
		-- attack counts when it is higher than the level value. Item ids, empty until such items exist.
		fistWeapons = {}
	},
	-- spell strikes x (1 + (level - from) / per), at most max: stands in for the passive tree, like the Thief line
	-- (Chaos.classes.spellLevelScale when it exists)
	spellLevelScale = {from = 300, per = 700, max = 2.2},
	-- dodge chance against melee / ranged hits, per vocation; Mistborne Step adds `roll` for rollMs
	evasion = {[17] = 0.06, [18] = 0.08, [19] = 0.04, roll = 0.25, rollMs = 2000},
	-- Shadowfist: a finisher opens a focus window; weapon hits and Monk strikes in it crit with critPerChi x chi spent
	focus = {durationMs = 4000, critPerChi = 0.08, critMultiplier = 1.5},
	-- Pressure Points: each stack makes the target take +perStack damage from Monks, maxStacks, each stack lasts
	pressure = {perStack = 0.05, maxStacks = 5, durationMs = 8000},
	-- Shadowfist Flurry: baseHits + chi hits, one every intervalMs
	flurry = {baseHits = 2, intervalMs = 200},
	-- Iron Palm stun: baseMs + perChiMs x chi; then the monster is immune for immuneMs. Monsters with more than
	-- bossHealth max health are only slowed (no attack lock).
	stun = {baseMs = 600, perChiMs = 400, immuneMs = 4000, bossHealth = 50000, bossSlow = 0.5},
	-- Chi Ward: absorb = (level x perLevel + fist x perFist) x finisher scale, for durationMs, range for a party member
	ward = {perLevel = 2.5, perFist = 8, durationMs = 8000, range = 5},
	-- Kindled Breath: heal = (level x perLevel + fist x perFist) x finisher scale; Iron Sage: + hotShare over hotTicks s
	breath = {perLevel = 2.0, perFist = 6, hotShare = 0.6, hotTicks = 6},
	-- Mantra of Stone: party members within radius take `reduction` less damage while it lasts
	mantra = {reduction = 0.08, durationMs = 12000, pulseMs = 2000, radius = 6},
	-- Mistborne Step: dash range
	step = {maxSteps = 3}
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

-- Pressure Points: damage multiplier on a target with `stacks`
function M.pressureMultiplier(stacks)
	return 1 + math.max(0, math.min(cfg().pressure.maxStacks, stacks or 0)) * cfg().pressure.perStack
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

-- damage taken with the Mantra of Stone
function M.mantraDamage(damage)
	return math.floor(math.abs(damage or 0) * (1 - cfg().mantra.reduction) + 0.5)
end

-- dodge chance of a Monk (rolling: Mistborne Step's window)
function M.dodgeChance(vocId, rolling)
	local e = cfg().evasion
	local c = e[vocId] or 0
	if rolling and M.isMonkLine(vocId) then
		c = c + e.roll
	end
	return c
end

function M.dodges(vocId, isWeaponAttack, rolling, roll)
	return isWeaponAttack and roll < M.dodgeChance(vocId, rolling) or false
end

-- forget per-creature memory (logout, death)
M.lastWeaponChi = M.lastWeaponChi or {}
function M.clear(id)
	M.lastWeaponChi[id] = nil
end

return M
