-- templar_aura_core.lua: the Templar line (docs/CLASSES.md, the seventh class): Templar (base) -> Inquisitor |
-- Sentinel. Every id and number of the line is in ChaosTemplar.cfg below (one table), followed by the rules that need
-- no engine: the party defence aura (which members a Templar covers, which aura wins, what it takes off a hit, the
-- Sentinel's regeneration), Radiant Strikes, Judgement, Zealotry, Aegis of Faith and the heals.
--
-- Pure: no engine calls, no events. Loaded by data/scripts/chaos/templar_combat.lua (scripts Lua state) and by the
-- spells through data/spells/chaos/_templar.lua (spells Lua state). Unit tests: server/tests/templar_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Times are milliseconds from whatever clock the caller passes (os.mtime on the server). State (aura, Zealotry
-- stacks) is per creature id and lives in memory: it does not survive a relog or a /reload, which is fine for
-- effects of a few seconds.

ChaosTemplar = ChaosTemplar or {}
local M = ChaosTemplar

M.cfg = {
	-- ------------------------------------------------------------------ ids (reserved for the Templar line)
	ids = {
		-- vocation ids (server/data/XML/chaos_vocations_templar.xml)
		vocation = {templar = 23, inquisitor = 24, sentinel = 25},
		-- the client's class byte: base slot 9, + 10 / + 20 for the two ascended classes
		-- (client/base-patches/0016-chaos-vocation-ids.patch maps it back to the vocation ids)
		clientByte = {templar = 9, inquisitor = 19, sentinel = 29},
		-- spell ids (spells_chaos.xml). Below 256: the 10.98 cooldown packet sends the id as one byte. Free on the
		-- server (stock spells.xml, the Chaos block) and in the client's spell list
		spell = {
			radiantSmite = 189, consecration = 190, vowOfMending = 191, -- Templar (all three classes)
			judgement = 198, purgingNova = 199, zealotry = 250, -- Inquisitor
			rebuke = 251, aegisOfFaith = 252, layOnHands = 253 -- Sentinel
		},
		-- condition sub ids (CONDITIONID_COMBAT, CONDITION_ATTRIBUTES without attributes = a timer). The spells and
		-- templar_combat.lua run in different Lua states; the conditions are the state both see.
		-- Next to chaos_constants.lua (71001-71014), the Necromancer (71020-71023) and the Monk (71030-71044); 71050-71053.
		-- auraRegen: the Sentinel aura's regeneration on a covered player (CONDITION_REGENERATION, refreshed every second)
		subId = {judgement = 71050, zealotry = 71051, aegis = 71052, auraRegen = 71053},
		-- the class key of the store unlock (class_unlocks.lua, ChaosClassUnlocks)
		unlockKey = "templar"
	},
	-- !ascend words of the base class (Chaos.classes.ascension.choices[23])
	ascension = {inquisitor = 24, sentinel = 25},

	-- ------------------------------------------------------------------ the defence aura (passive, always on)
	-- Every second (thinkMs) each Templar-line player covers itself and the members of its party on its floor within
	-- `radius` sqm. A covered player takes `reduction` less damage (after the engine's own reductions) and, from a
	-- Sentinel, regenerates regenPct of its maximum health per second. Auras do not stack: the strongest one counts
	-- (higher reduction, then higher regeneration). A covered state lasts holdMs, so a member who steps out of range
	-- keeps it until the next check misses it.
	aura = {
		thinkMs = 1000,
		holdMs = 1500,
		fxMs = 4000, -- how often the aura shows around a Templar
		byVocation = {
			[23] = {radius = 4, reduction = 0.06, regenPct = 0},
			[24] = {radius = 3, reduction = 0.04, regenPct = 0},
			[25] = {radius = 5, reduction = 0.12, regenPct = 0.004}
		}
	},

	-- ------------------------------------------------------------------ weapon hits
	-- Radiant Strikes (passive): every melee weapon hit is followed by a holy strike of `share` of the hit
	-- (monster holy resistances apply: undead and demons take more). Dealt delayMs later inside a guard flag, so it
	-- never triggers itself.
	radiant = {share = {[23] = 0.15, [24] = 0.25, [25] = 0.10}, delayMs = 120},

	-- ------------------------------------------------------------------ Inquisitor
	-- Judgement (spell): the target takes `bonus` more holy damage from every source (the party's too) for durationMs
	judgement = {durationMs = 8000, bonus = 0.20},
	-- Zealotry (spell): while the buff lasts every melee weapon hit adds a stack (max maxStacks); each stack is
	-- +perStack damage on everything the Inquisitor deals. The stacks drop to zero decayMs after the last hit.
	zealotry = {durationMs = 20000, perStack = 0.04, maxStacks = 10, decayMs = 3000},
	-- Purging Nova (spell): heals the Inquisitor for healShare of the damage it deals, at most healCapPct of its
	-- maximum health per cast (the line's "little sustain")
	purgingNova = {healShare = 0.10, healCapPct = 0.05},

	-- ------------------------------------------------------------------ Sentinel
	-- Aegis of Faith (spell, needs a shield): damage taken -reduction for durationMs (the block window)
	aegis = {durationMs = 5000, reduction = 0.40},
	-- Rebuke (spell): taunts every monster within radius and slows it
	rebuke = {radius = 4, durationMs = 6000, slow = 0.25},
	-- Lay on Hands (spell): heals one party member (or the Sentinel) within range for pct of its maximum health
	-- plus magic level x perMagicLevel
	layOnHands = {pct = 0.35, perMagicLevel = 10, range = 5},

	-- ------------------------------------------------------------------ Templar
	-- Vow of Mending (spell, self heal): pct of the maximum health + level / 5 + magic level x perMagicLevel
	vowOfMending = {pct = 0.08, perMagicLevel = 4},
	-- Consecration (spell): pulses holy damage on enemies within radius of the cast tile; allies standing in it are
	-- healed allyHeal x a pulse
	consecration = {pulses = 6, intervalMs = 1000, radius = 2, allyHeal = 0.3},

	-- (spellLevelScale, a level factor of the strikes that stood in for the passive tree, was dropped with the class
	-- trees: M.levelScale is 1 unless one is set here)
	spellLevelScale = nil
}

local function cfg()
	return M.cfg
end

M.now = os.mtime or function() return os.time() * 1000 end

-- ------------------------------------------------------------------------------------------------ vocations
local V = M.cfg.ids.vocation

function M.isTemplarLine(vocId)
	return vocId == V.templar or vocId == V.inquisitor or vocId == V.sentinel
end

function M.isInquisitor(vocId)
	return vocId == V.inquisitor
end

function M.isSentinel(vocId)
	return vocId == V.sentinel
end

-- the base class of the line (itself for the Templar), nil for any other vocation
function M.baseOf(vocId)
	return M.isTemplarLine(vocId) and V.templar or nil
end

-- ------------------------------------------------------------------------------------------------ the aura
-- the aura of a vocation; bonus = the passive tree's changes {reduction, radius, regenPct, bastion, scale} or nil
-- (scale: Penitent's Wrath, a factor on the whole reduction, Bastion's share included)
function M.auraOf(vocId, bonus)
	local a = cfg().aura.byVocation[vocId]
	if not a or not bonus then
		return a
	end
	return {radius = a.radius + (bonus.radius or 0),
		reduction = (a.reduction + (bonus.reduction or 0)) * (bonus.scale or 1),
		regenPct = (a.regenPct or 0) + (bonus.regenPct or 0), bastion = bonus.bastion}
end

-- distance in sqm (the larger of the two axes), math.huge on another floor
function M.distance(a, b)
	if not a or not b or a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- which of `players` a Templar covers. templar = {id, voc, pos, party}, players = list of {id, pos, party, dead};
-- `party` is any value that is equal for members of one party (nil = no party). The Templar always covers itself.
function M.coveredBy(templar, players)
	local aura = M.auraOf(templar.voc, templar.bonus)
	local out = {}
	if not aura then
		return out
	end
	for _, p in ipairs(players) do
		if not p.dead then
			if p.id == templar.id then
				out[#out + 1] = p.id
			elseif templar.party ~= nil and p.party == templar.party and M.distance(templar.pos, p.pos) <= aura.radius then
				out[#out + 1] = p.id
			end
		end
	end
	return out
end

-- a is a stronger aura than b
function M.stronger(a, b)
	if not b then
		return true
	end
	if a.reduction ~= b.reduction then
		return a.reduction > b.reduction
	end
	return (a.regenPct or 0) > (b.regenPct or 0)
end

-- One aura check: templars = list of {id, voc, pos, party}, players = every candidate (templars included) as
-- M.coveredBy takes them. Returns [player id] = {reduction, regenPct, source = templar id, untilMs}.
function M.collectAuras(templars, players, now)
	local hold = cfg().aura.holdMs
	local best = {}
	for _, t in ipairs(templars) do
		local aura = M.auraOf(t.voc, t.bonus)
		if aura then
			for _, id in ipairs(M.coveredBy(t, players)) do
				local candidate = {reduction = aura.reduction, regenPct = aura.regenPct or 0, source = t.id, untilMs = now + hold,
					bastion = aura.bastion}
				if M.stronger(candidate, best[id]) then
					best[id] = candidate
				end
			end
		end
	end
	return best
end

-- state[id] = the aura a player is under (M.collectAuras); expired entries read as none
M.auraState = M.auraState or {}

-- replace the aura states with a fresh check (keeping a still-valid older state when it is stronger, so a second
-- Templar's think in the same second cannot weaken it)
function M.applyAuras(fresh, now)
	for id, s in pairs(M.auraState) do
		if now >= s.untilMs then
			M.auraState[id] = nil
		end
	end
	for id, s in pairs(fresh) do
		local old = M.auraState[id]
		if not old or now >= old.untilMs or not M.stronger(old, s) then
			M.auraState[id] = s
		end
	end
end

function M.activeAura(id, now)
	local s = M.auraState[id]
	if s and now < s.untilMs then
		return s
	end
	return nil
end

-- keep the sign of an engine damage value, scale its size, round half up
function M.scale(value, factor)
	local v = math.floor(math.abs(value or 0) * factor + 0.5)
	return (value or 0) < 0 and -v or v
end

-- the factor on damage a player takes: the aura and Aegis of Faith multiply. aegisShare: the share of Aegis of Faith
-- that counts (1 = the Sentinel's own; Bastion's party cover: partyShare)
function M.damageTakenFactor(aura, aegisActive, aegisShare)
	local f = 1
	if aura then
		f = f * (1 - aura.reduction)
	end
	if aegisActive then
		f = f * (1 - cfg().aegis.reduction * (aegisShare or 1))
	end
	return f
end

-- health the Sentinel's aura gives back per check (0 at full health; at least 1 when anything is missing)
function M.regenAmount(health, maxHealth, aura)
	if not aura or (aura.regenPct or 0) <= 0 or (maxHealth or 0) <= 0 or health >= maxHealth then
		return 0
	end
	local amount = math.max(1, math.floor(maxHealth * aura.regenPct + 0.5))
	return math.min(amount, maxHealth - health)
end

-- ------------------------------------------------------------------------------------------------ weapon hits
-- the holy strike after a melee weapon hit of `hit`. The engine halves damage between players before
-- onHealthChange sees it and halves the scripted strike again, so against a player it is computed from the unhalved hit.
function M.radiantDamage(vocId, hit, targetIsPlayer, extraShare)
	local share = cfg().radiant.share[vocId]
	hit = math.abs(hit or 0)
	if not share or hit <= 0 then
		return 0
	end
	share = share + (extraShare or 0)
	local value = hit * share
	if targetIsPlayer then
		value = value * 2
	end
	return math.floor(value + 0.5)
end

-- the factor on damage of `isHoly` type a creature takes while it is judged
function M.judgementFactor(isHoly, judged)
	if isHoly and judged then
		return 1 + cfg().judgement.bonus
	end
	return 1
end

-- ------------------------------------------------------------------------------------------------ Zealotry
-- zeal[id] = {stacks = n, lastHit = ms}
M.zeal = M.zeal or {}

function M.zealStacks(id, now)
	local z = M.zeal[id]
	if not z then
		return 0
	end
	if now - z.lastHit >= cfg().zealotry.decayMs then
		M.zeal[id] = nil
		return 0
	end
	return z.stacks
end

-- a melee weapon hit while the buff is up: one more stack
function M.zealHit(id, now)
	local stacks = M.zealStacks(id, now)
	M.zeal[id] = {stacks = math.min(cfg().zealotry.maxStacks, stacks + 1), lastHit = now}
	return M.zeal[id].stacks
end

-- the damage factor of everything the Inquisitor deals (1 without the buff)
function M.zealMultiplier(id, now, buffActive)
	if not buffActive then
		M.zeal[id] = nil
		return 1
	end
	return 1 + M.zealStacks(id, now) * cfg().zealotry.perStack
end

-- ------------------------------------------------------------------------------------------------ heals
-- Purging Nova's heal for the damage it dealt
function M.novaHeal(dealt, maxHealth)
	local n = cfg().purgingNova
	local heal = math.floor(math.abs(dealt or 0) * n.healShare + 0.5)
	return math.min(heal, math.floor((maxHealth or 0) * n.healCapPct + 0.5))
end

function M.layOnHandsAmount(maxHealth, magicLevel)
	local l = cfg().layOnHands
	return math.floor((maxHealth or 0) * l.pct + (magicLevel or 0) * l.perMagicLevel + 0.5)
end

function M.vowAmount(maxHealth, level, magicLevel)
	local v = cfg().vowOfMending
	return math.floor((maxHealth or 0) * v.pct + (level or 0) / 5 + (magicLevel or 0) * v.perMagicLevel + 0.5)
end

-- Lay on Hands without a name: the candidate (list of {id, health, maxHealth}) with the lowest health share;
-- ties go to the first in the list (the caller puts the Sentinel last, so others come first)
function M.pickHealTarget(candidates)
	local best, bestRatio
	for _, c in ipairs(candidates) do
		if (c.maxHealth or 0) > 0 then
			local ratio = c.health / c.maxHealth
			if not bestRatio or ratio < bestRatio then
				best, bestRatio = c, ratio
			end
		end
	end
	return best and best.id or nil
end

-- ------------------------------------------------------------------------------------------------ spells
-- the level factor of the line's spell strikes
function M.levelScale(level)
	local s = cfg().spellLevelScale
	if not s then
		return 1
	end
	return math.min(s.max, 1 + math.max(0, (level or 0) - s.from) / s.per)
end

-- positive min, max of a holy strike: level / 5 + power x (pMin | pMax) + magic level x (mMin | mMax) + base,
-- times the level factor. power = melee skill x weapon attack (the spells compute it)
function M.strikeValues(level, power, magicLevel, pMin, pMax, mMin, mMax, baseMin, baseMax)
	local k = M.levelScale(level)
	local l = (level or 0) / 5
	return (l + power * pMin + magicLevel * mMin + baseMin) * k, (l + power * pMax + magicLevel * mMax + baseMax) * k
end

-- ------------------------------------------------------------------------------------------------ Penitent's Wrath
-- the line keystone (class_tree.lua fx.ksPenitentWrath): the holy strike that answers a hit of `taken` (what the
-- Templar really lost, after every reduction), 0 for nothing taken
function M.penitentDamage(taken, magicLevel, fx)
	taken = math.abs(taken or 0)
	if taken <= 0 or not fx then
		return 0
	end
	return math.floor(taken * fx.share + (magicLevel or 0) * fx.perMagicLevel)
end

-- at most one answer every fx.icdMs per Templar (state per id)
M.penitentLast = M.penitentLast or {}
function M.penitentReady(id, now, fx)
	local last = M.penitentLast[id]
	if last and now - last < fx.icdMs then
		return false
	end
	M.penitentLast[id] = now
	return true
end

-- forget everything about a creature (logout, death)
function M.clear(id)
	M.zeal[id] = nil
	M.auraState[id] = nil
	M.penitentLast[id] = nil
end

return M
