-- templar_aura_core.lua: the Templar line (docs/CLASSES.md, the seventh class): Templar (base) -> Inquisitor |
-- Sentinel. Every id and number of the line is in ChaosTemplar.cfg below (one table), followed by the rules that need
-- no engine: the party defence aura (which members a Templar covers, which aura wins, what it takes off a hit, the
-- Sentinel's regeneration), Radiant Strikes, Judgement, Aegis of Faith and the heals.
--
-- Pure: no engine calls, no events. Loaded by data/scripts/chaos/templar_combat.lua (scripts Lua state) and by the
-- spells through data/spells/chaos/_templar.lua (spells Lua state). Unit tests: server/tests/templar_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Times are milliseconds from whatever clock the caller passes (os.mtime on the server). State (aura) is per creature id
-- and lives in memory: it does not survive a relog or a /reload, which is fine for effects of a few seconds.

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
			judgement = 198, purgingNova = 199, crusadersSweep = 250, -- Inquisitor (was Zealotry until O254)
			rebuke = 251, aegisOfFaith = 252, layOnHands = 253 -- Sentinel
		},
		-- condition sub ids (CONDITIONID_COMBAT, CONDITION_ATTRIBUTES without attributes = a timer). The spells and
		-- templar_combat.lua run in different Lua states; the conditions are the state both see.
		-- Next to chaos_constants.lua (71001-71014), the Necromancer (71020-71023) and the Monk (71030-71044); 71050-71053.
		-- auraRegen: the Sentinel aura's regeneration on a covered player (CONDITION_REGENERATION, refreshed every second)
		subId = {judgement = 71050, aegis = 71052, auraRegen = 71053}, -- 71051 retired (Zealotry, O254): never reused
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
		-- What the clients are told (O315, the foot aura): the client draws the sigil under a Templar-line player's feet and,
		-- inside a party, a faint frame over the aura's range, so the server sends no periodic effect any more (it was the
		-- "beat" every 4 s). A player near a Templar gets the list of Templar-line players within `viewRange` sqm (same
		-- floor; a bit more than the widest screen) with the line, the radius and whether the viewer shares a party with it,
		-- only when that list changed (checked every think, never faster than minGapMs, so at most one message a second).
		sync = {viewRange = 16, minGapMs = 900}, -- the think runs every 1000 ms; 900 absorbs timer jitter
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

	-- Radiant Smite (spell): its damage x scale by vocation. The rotation pass (2026-10-14, server/data/spells/README.md
	-- "Rotations") took its cooldown from 4 s to 2 s so the line always has an attack spell ready; the scale keeps
	-- each class's spell damage where it was (computed with server/tools/rotation_sim.py). early: below that level the
	-- Inquisitor has no Purging Nova yet, so Radiant Smite takes more of its turns.
	radiantSmite = {scale = {[23] = 0.56, [24] = 0.69, [25] = 0.56}, early = {[24] = {below = 120, scale = 0.55}}},

	-- ------------------------------------------------------------------ Inquisitor
	-- Judgement (spell): the target takes `bonus` more holy damage from every source (the party's too) for durationMs
	judgement = {durationMs = 8000, bonus = 0.20},
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

-- ------------------------------------------------------------------------------------------------ what the clients see
-- The client draws the foot aura of every Templar-line player it sees (a sigil in the line's tint) and, while the Templar
-- is in a party, a frame over the aura's range for the Templar and its party members (client game_chestaura, O315).

-- 1 Templar, 2 Inquisitor, 3 Sentinel; nil for any other vocation
function M.lineOf(vocId)
	if vocId == V.templar then
		return 1
	elseif vocId == V.inquisitor then
		return 2
	elseif vocId == V.sentinel then
		return 3
	end
	return nil
end

-- templars = list of {id, voc, pos, party, bonus, dead} (the ones M.collectAuras takes), viewers = list of {id, pos, party}.
-- Returns [viewer id] = list of {i = Templar id, l = line, r = radius, p = 1 when the Templar is in a party and the viewer
-- is the Templar or shares that party, else 0}, sorted by Templar id. A viewer sees a Templar within sync.viewRange sqm on its
-- floor, and always itself; a viewer without any Templar in view has no entry. r includes the passive tree's bonus radius.
function M.syncEntries(templars, viewers)
	local range = cfg().aura.sync.viewRange
	local out = {}
	for _, t in ipairs(templars) do
		local line = M.lineOf(t.voc)
		local aura = line and not t.dead and M.auraOf(t.voc, t.bonus) or nil
		if aura then
			for _, v in ipairs(viewers) do
				if v.id == t.id or M.distance(t.pos, v.pos) <= range then
					local shared = t.party ~= nil and (v.id == t.id or v.party == t.party)
					local list = out[v.id]
					if not list then
						list = {}
						out[v.id] = list
					end
					list[#list + 1] = {i = t.id, l = line, r = aura.radius, p = shared and 1 or 0}
				end
			end
		end
	end
	for _, list in pairs(out) do
		table.sort(list, function(a, b) return a.i < b.i end)
	end
	return out
end

-- a string that is equal for equal lists (nil or empty: "")
function M.syncKey(entries)
	local parts = {}
	for _, e in ipairs(entries or {}) do
		parts[#parts + 1] = e.i .. ":" .. e.l .. ":" .. e.r .. ":" .. e.p
	end
	return table.concat(parts, ";")
end

-- sent[viewer id] = the key of the list the viewer last got (absent: it knows no Templar). Returns the list to send
-- ({} to tell the viewer that the last Templar is gone) when it differs from what the viewer has, else nil.
function M.syncDecide(sent, viewerId, entries)
	local key = M.syncKey(entries)
	local had = sent[viewerId]
	if key == "" then
		if had == nil then
			return nil
		end
		sent[viewerId] = nil
		return {}
	end
	if had == key then
		return nil
	end
	sent[viewerId] = key
	return entries
end

-- forget a viewer (logout); syncPrune forgets every viewer that is not in `online` (set of ids)
function M.syncForget(sent, viewerId)
	sent[viewerId] = nil
end

function M.syncPrune(sent, online)
	for id in pairs(sent) do
		if not online[id] then
			sent[id] = nil
		end
	end
end

-- state of the sender: what each viewer got, and when the last check ran
M.syncSent = M.syncSent or {}
M.syncLastMs = M.syncLastMs or nil

-- true when a check may run now (at most one per sync.minGapMs); marks the time when it does
function M.syncDue(now)
	if M.syncLastMs and now - M.syncLastMs < cfg().aura.sync.minGapMs then
		return false
	end
	M.syncLastMs = now
	return true
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
-- extra: another factor that multiplies (Mantle of Dawn, quest_buffs_core.lua), nil = 1
function M.damageTakenFactor(aura, aegisActive, aegisShare, extra)
	local f = extra or 1
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

-- Radiant Smite's damage scale for a vocation at a level (cfg.radiantSmite; 1 for a vocation it does not list)
function M.smiteScale(vocId, level)
	local c = cfg().radiantSmite
	local early = c.early and c.early[vocId]
	if early and level and level < early.below then
		return early.scale
	end
	return c.scale[vocId] or 1
end

-- ------------------------------------------------------------------------------------------------ weapon hits
-- the holy strike after a melee weapon hit of `hit`. The engine halves damage between players before
-- onHealthChange sees it and halves the scripted strike again, so against a player it is computed from the unhalved hit.
-- mult: a factor on the strike (Mantle of Dawn, quest_buffs_core.lua), nil = 1
function M.radiantDamage(vocId, hit, targetIsPlayer, extraShare, mult)
	local share = cfg().radiant.share[vocId]
	hit = math.abs(hit or 0)
	if not share or hit <= 0 then
		return 0
	end
	share = share + (extraShare or 0)
	local value = hit * share * (mult or 1)
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
	M.auraState[id] = nil
	M.penitentLast[id] = nil
	M.syncSent[id] = nil
end

return M
