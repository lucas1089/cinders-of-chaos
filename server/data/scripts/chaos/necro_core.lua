-- necro_core.lua: the Necromancer line's pure logic (no engine calls): classes, minion caps and scaling, spell
-- values, curse / damage-over-time math, corpse and target choice, the leash and the protection-zone rest.
-- Used by necro_minions.lua and necromancer_combat.lua (scripts Lua state) and the spells (spells Lua state, through
-- data/spells/chaos/necromancer/_necro.lua). Tests: server/tests/necro_test.lua. Numbers: necro_config.lua.
-- Every function takes the config table first. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosNecroCore = ChaosNecroCore or {}
local N = ChaosNecroCore

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

-- ------------------------------------------------------------------ classes
-- "necromancer" | "lich" | "bonelord" for a vocation id of the line, else nil
function N.classOf(cfg, vocId)
	for key, id in pairs(cfg.ids) do
		if id == vocId then
			return key
		end
	end
	return nil
end

function N.isLine(cfg, vocId)
	return N.classOf(cfg, vocId) ~= nil
end

-- the Necromancer's ascension (!ascend lich|bonelord): the vocation id for `word`, or nil
function N.ascensionId(cfg, word)
	word = (tostring(word or "")):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%s_-]", "")
	return cfg.ascension[word]
end

-- ------------------------------------------------------------------ minions
local function classCfg(cfg, classKey)
	return cfg.minions.classes[classKey]
end

-- the minion kind a class raises with Raise Dead ("skeleton" | "shade"), nil for no class
function N.raiseKind(cfg, classKey)
	local c = classCfg(cfg, classKey)
	return c and c.kind or nil
end

-- the count of the last step {level, count} reached at `level`, + bonus when there is any
local function stepCap(steps, level, bonus)
	local count = 0
	for _, step in ipairs(steps) do
		if (level or 0) >= step[1] then
			count = step[2]
		end
	end
	if count > 0 then
		count = count + (bonus or 0)
	end
	return count
end

-- how many minions of `kind` a class of `level` may have out (the golem: Bone Lord only); bonus: more of a kind the class
-- raises at all (the passive tree's Legion)
function N.minionCap(cfg, classKey, kind, level, bonus)
	if kind == "golem" then
		return classKey == "bonelord" and cfg.minions.golemClass.count or 0
	end
	local c = classCfg(cfg, classKey)
	if c and cfg.minions[kind] and cfg.minions[kind].summon then
		-- a summon spell's minion (warrior / archer / mage): only the total cap limits it
		return N.totalCap(cfg, classKey, level, bonus)
	end
	if not c or c.kind ~= kind then
		return 0
	end
	return stepCap(c.caps, level, bonus)
end

-- the most minions of every kind together at `level` (the class's `total` steps + the passive tree's Legion bonus); 0 for
-- no class
function N.totalCap(cfg, classKey, level, bonus)
	local c = classCfg(cfg, classKey)
	if not c or not c.total then
		return 0
	end
	return stepCap(c.total, level, bonus)
end

-- room for one more minion: `list` = the owner's minions {kind} in summon order (oldest first). Returns the indexes of
-- `list` to dismiss (oldest first; often empty) so that one more fits under the total cap, or nil, reason when the
-- class has no minions at all. The total cap wins over every per-kind cap.
function N.makeRoom(cfg, classKey, level, list, bonus)
	local cap = N.totalCap(cfg, classKey, level, bonus)
	if cap <= 0 then
		return nil, "Only a necromancer can raise minions."
	end
	local out = {}
	for i = 1, max(0, #(list or {}) + 1 - cap) do
		out[#out + 1] = i
	end
	return out
end

-- class factors of a minion kind: hit, health (the golem has its own)
local function factors(cfg, classKey, kind)
	if kind == "golem" then
		return cfg.minions.golemClass.hit, cfg.minions.golemClass.health
	end
	local c = classCfg(cfg, classKey)
	if not c then
		return 1, 1
	end
	return c.hit, c.health
end

-- extra: a factor on top (the passive tree's Bone Colossus for the golem)
function N.minionHealth(cfg, classKey, kind, level, ml, extra)
	local k = cfg.minions[kind]
	local h = k.health
	local _, f = factors(cfg, classKey, kind)
	return max(1, floor((h.base + (level or 0) * h.perLevel + (ml or 0) * h.perMl) * f * (k.mult and k.mult.health or 1) * (extra or 1)))
end

-- positive min, max of one minion hit; `aura` = Banner of Bones is up on the owner (true: the banner's bonus; a number:
-- that bonus, the passive tree's Banner Bearer included); extra: a factor on top (Bone Colossus for the golem)
function N.minionHit(cfg, classKey, kind, level, ml, aura, extra)
	local k = cfg.minions[kind]
	local h = k.hit
	local f = factors(cfg, classKey, kind)
	local avg = ((level or 0) * h.a + (ml or 0) * h.b) * f * (k.mult and k.mult.hit or 1) * (extra or 1)
	if aura then
		avg = avg * (1 + (type(aura) == "number" and aura or cfg.bannerOfBones.damage))
	end
	local s = cfg.minions.spread
	return floor(avg * (1 - s)), floor(avg * (1 + s))
end

-- Covenant of the Grave (the line keystone, class_tree.lua fx.ksGraveCovenant; nil = not held): the factors on a
-- minion's hit and health (every kind) and on the owner's own spells. classKey: the owner's class (fx.classMinionHit
-- gives a class its own minion hit bonus; nil = the line's)
function N.covenant(fx, classKey)
	if not fx then
		return 1, 1, 1
	end
	local hit = fx.minionHit or 0
	if classKey and fx.classMinionHit and fx.classMinionHit[classKey] then
		hit = fx.classMinionHit[classKey]
	end
	return 1 + hit, 1 + (fx.minionHealth or 0), 1 - (fx.ownSpell or 0)
end

-- share of a skeleton hit that strikes the other enemies next to its target (Bone Lord), 0 for the others
function N.splashShare(cfg, classKey, kind)
	if kind ~= "skeleton" then
		return 0
	end
	local c = classCfg(cfg, classKey)
	return c and c.splash or 0
end

-- damage a minion takes: x (1 - reduction) while the owner's Banner of Bones is up
function N.minionDamageTaken(cfg, damage, aura)
	if not aura or damage == 0 then
		return damage
	end
	local v = floor(abs(damage) * (1 - cfg.bannerOfBones.reduction) + 0.5)
	return damage < 0 and -v or v
end

-- How a Raise Dead cast goes: classKey, level, have = minions of the raised kind out, corpses = usable corpses in
-- reach. Returns {raise = n minions, fromCorpses = n corpses used, fromNothing = bool, extraMana = n} or nil, reason.
function N.raisePlan(cfg, classKey, level, have, corpses, bonus)
	local kind = N.raiseKind(cfg, classKey)
	if not kind then
		return nil, "Only a necromancer can raise the dead."
	end
	local free = N.minionCap(cfg, classKey, kind, level, bonus) - (have or 0)
	if free <= 0 then
		return nil, "Your army is complete."
	end
	local r = cfg.raiseDead
	local n = min(free, r.perCast[classKey] or 1, corpses or 0)
	if n > 0 then
		return {raise = n, fromCorpses = n, fromNothing = false, extraMana = 0}
	end
	return {raise = 1, fromCorpses = 0, fromNothing = true, extraMana = floor(r.mana * r.nothingManaFactor)}
end

-- A corpse Raise Dead or Corpse Explosion may use. info = {isCorpse, items = items inside, owner = corpse owner id
-- (0 / nil = nobody), playerCorpse}. allowed = {[id] = true} the caster and its party.
function N.corpseUsable(info, allowed)
	if not info or not info.isCorpse or info.playerCorpse then
		return false
	end
	if (info.items or 0) > 0 then
		return false
	end
	local owner = info.owner or 0
	return owner == 0 or (allowed and allowed[owner]) or false
end

-- the usable corpses of `list` ({info..., dist}) nearest first, at most `count`
function N.pickCorpses(list, allowed, count)
	local out = {}
	for _, c in ipairs(list or {}) do
		if N.corpseUsable(c, allowed) then
			out[#out + 1] = c
		end
	end
	table.sort(out, function(a, b)
		if a.dist ~= b.dist then
			return a.dist < b.dist
		end
		return (a.order or 0) < (b.order or 0)
	end)
	while #out > (count or #out) do
		out[#out] = nil
	end
	return out
end

-- Chebyshev distance on one floor (math.huge across floors)
function N.distance(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return max(abs(a.x - b.x), abs(a.y - b.y))
end

-- the leash: "teleport" when a minion strays farther than leashRange or onto another floor, else "stay"
function N.leash(cfg, minionPos, ownerPos)
	if N.distance(minionPos, ownerPos) > cfg.minions.leashRange then
		return "teleport"
	end
	return "stay"
end

-- What a minion hits this think: the owner's target when the minion reaches it, else its own target when it
-- reaches that, else nil. Each = {id, pos, alive}; range = the kind's reach.
function N.minionTarget(minionPos, range, ownerTarget, ownTarget)
	for _, t in ipairs({ownerTarget, ownTarget}) do
		if t and t.alive and N.distance(minionPos, t.pos) <= range then
			return t
		end
	end
	return nil
end

-- the skeleton Bone Offering sacrifices: the one nearest to the target (never the golem). minions = {kind, pos, id}
function N.pickSacrifice(minions, targetPos)
	local best, bestDist
	for _, m in ipairs(minions or {}) do
		if m.kind == "skeleton" then
			local d = N.distance(m.pos, targetPos)
			if not best or d < bestDist or (d == bestDist and (m.id or 0) < (best.id or 0)) then
				best, bestDist = m, d
			end
		end
	end
	return best
end

-- the next host of a Soul Rot whose target died: the nearest of `candidates` ({id, pos, alive}) within radius of
-- `pos`, nil when none
function N.rotJump(candidates, pos, radius)
	local best, bestDist
	for _, c in ipairs(candidates or {}) do
		if c.alive then
			local d = N.distance(c.pos, pos)
			if d <= radius and (not best or d < bestDist or (d == bestDist and (c.id or 0) < (best.id or 0))) then
				best, bestDist = c, d
			end
		end
	end
	return best
end

-- ------------------------------------------------------------------ spells
function N.levelScale(cfg, level)
	local s = cfg.levelScale
	if not s then
		return 1
	end
	return min(s.max, 1 + max(0, (level or 0) - s.from) / s.per)
end

-- Lich Soul Hoard: spell damage factor for `have` shades out of `cap`. tree = the passive tree's Hoarded Souls
-- ({perFreeSlot, withShade}) or nil: a higher bonus per empty slot, and withShade while every slot is taken
function N.soulHoard(cfg, classKey, cap, have, tree)
	if classKey ~= "lich" then
		return 1
	end
	local free = max(0, (cap or 0) - (have or 0))
	if tree then
		return 1 + (free > 0 and free * tree.perFreeSlot or tree.withShade)
	end
	return 1 + free * cfg.soulHoard.perFreeSlot
end

-- positive min, max of a formula f = {mlMin, mlMax, baseMin, baseMax, scale} for level and magic level, with the
-- level scale and an extra factor (Soul Hoard, curse ticks of the Lich ...)
function N.values(cfg, f, level, ml, extra)
	local l = (level or 0) / 5
	local k = (f.scale or 1) * N.levelScale(cfg, level) * (extra or 1)
	return floor((l + (ml or 0) * f.mlMin + f.baseMin) * k), floor((l + (ml or 0) * f.mlMax + f.baseMax) * k)
end

-- average of a min, max pair
function N.avg(a, b)
	return (a + b) / 2
end

-- Withering Curse: amplify of the class's curse; curse ticks min, max
function N.curseAmplify(cfg, classKey)
	return cfg.witheringCurse.amplify[classKey] or 0
end

function N.curseTick(cfg, classKey, level, ml, hoard)
	local w = cfg.witheringCurse
	return N.values(cfg, w.tick, level, ml, (classKey == "lich" and w.tickLich or 1) * (hoard or 1))
end

-- damage a cursed creature takes: x (1 + amplify); players are never amplified (the curse only rots them)
function N.cursedDamage(damage, amplify, targetIsPlayer)
	if targetIsPlayer or (amplify or 0) <= 0 or damage == 0 then
		return damage
	end
	local v = floor(abs(damage) * (1 + amplify) + 0.5)
	return damage < 0 and -v or v
end

-- the stronger of two curses (sub ids) on a creature: amplify for the conditions present
function N.activeAmplify(cfg, hasCurse, hasLichCurse)
	if hasLichCurse then
		return cfg.witheringCurse.amplify.lich
	end
	if hasCurse then
		return max(cfg.witheringCurse.amplify.necromancer, cfg.witheringCurse.amplify.bonelord)
	end
	return 0
end

-- Life Siphon: health back for damage dealt
function N.siphonHeal(cfg, dealt)
	return floor(max(0, dealt or 0) * cfg.lifeSiphon.heal)
end

-- Bone Offering: min, max of the burst for a skeleton with `health` left
function N.offeringValues(cfg, level, ml, health)
	local o = cfg.boneOffering
	local a, b = N.values(cfg, o.hit, level, ml)
	local bonus = floor(max(0, health or 0) * o.healthShare)
	return a + bonus, b + bonus
end

-- damage the Bone Lord takes under Bone Offering's shield
function N.shielded(cfg, damage, active)
	if not active or damage == 0 then
		return damage
	end
	local v = floor(abs(damage) * (1 - cfg.boneOffering.shield) + 0.5)
	return damage < 0 and -v or v
end

-- ------------------------------------------------------------------ the protection-zone rest
-- rest[playerId] = {at = os.time, list = {{kind, ratio}}}: minions put to rest while the owner stands in a
-- protection zone. restOf returns the list to raise again (and forgets it), or nil when nothing or too old.
function N.restPut(rest, playerId, now, list)
	if #list == 0 then
		return
	end
	local r = rest[playerId]
	if r then
		for _, m in ipairs(list) do
			r.list[#r.list + 1] = m
		end
		r.at = now
	else
		rest[playerId] = {at = now, list = list}
	end
end

function N.restTake(cfg, rest, playerId, now)
	local r = rest[playerId]
	rest[playerId] = nil
	if not r or now - r.at > cfg.minions.restKeepSeconds then
		return nil
	end
	return r.list
end

-- which of the resting minions may rise for the class now (caps may have changed: vocation change, level loss)
function N.restFilter(cfg, classKey, level, list, bonus)
	local out, count = {}, {}
	for _, m in ipairs(list or {}) do
		local c = count[m.kind] or 0
		if c < N.minionCap(cfg, classKey, m.kind, level, bonus) and #out < N.totalCap(cfg, classKey, level, bonus) then
			out[#out + 1] = m
			count[m.kind] = c + 1
		end
	end
	return out
end

-- minions over the cap or of a kind the class does not raise (after a vocation change or a level loss): returns
-- the indexes of `list` ({kind}) to dismiss, newest (last) first
function N.overCap(cfg, classKey, level, list, bonus)
	local count, out, dropped = {}, {}, {}
	for i, m in ipairs(list or {}) do
		local c = (count[m.kind] or 0) + 1
		count[m.kind] = c
		if c > N.minionCap(cfg, classKey, m.kind, level, bonus) then
			out[#out + 1] = i
			dropped[i] = true
		end
	end
	-- the total cap: of what is left, the newest go
	local kept = {}
	for i = 1, #(list or {}) do
		if not dropped[i] then
			kept[#kept + 1] = i
		end
	end
	for j = #kept, N.totalCap(cfg, classKey, level, bonus) + 1, -1 do
		out[#out + 1] = kept[j]
	end
	table.sort(out, function(a, b) return a > b end)
	return out
end

-- every minion kind (monster types of necro_*.xml)
N.kinds = {"skeleton", "shade", "golem", "warrior", "archer", "mage"}

-- the minion kind of a monster name, nil for any other monster
function N.kindOf(cfg, name)
	name = (name or ""):lower()
	for _, kind in ipairs(N.kinds) do
		if cfg.minions[kind].monster:lower() == name then
			return kind
		end
	end
	return nil
end

return N
