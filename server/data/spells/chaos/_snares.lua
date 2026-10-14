-- Snares, the spells' side (ChaosSnares): Snare Trap, Seeker Mine and Detonate Mines (spells_chaos.xml 99, 100, 104).
-- Rules: data/scripts/chaos/snares_core.lua, numbers: snares_config.lua, design: docs/BUILDS.md "Snares",
-- server/README.md "Snares".
--
-- A snare is a spot in memory, not an item: nothing is created on the map, nothing is saved. One scheduler (addEvent
-- every scan.tickMs, running only while snares exist) visits at most scan.perTick snares a tick (round robin) and fires
-- at most scan.burstsPerTick bursts; a visit drops the snare when its owner logged out, died, changed floor, went past
-- the leash or into a protection zone. The scheduler runs outside any spell's cast context (the supports' raw addEvent),
-- so a snare's hits are not a cast of the spell (no support effects, no Effigy, no Sigil); the snare's hits set the
-- storage marker snares_config.lua storage.hit on the owner while they are dealt, which the scripts' side reads
-- (Snarewright's Creed: the price spares them). The combat log still names them by their spell (ChaosCombatLog.asSpell,
-- combatlog.lua): Snare Trap, Seeker Mine, Detonate Mines for the mines it sets off.
-- Targets: monsters that are not a player's summon (ChaosSpell.isEnemy), never players.

if ChaosSnares then
	return
end
ChaosSnares = {}
local M = ChaosSnares

if not ChaosSnaresCore then
	dofile("data/scripts/chaos/snares_core.lua")
end
if not ChaosArchetypesCore then
	pcall(dofile, "data/scripts/chaos/archetypes_core.lua") -- the keystone flags (storage) and the unique keys
end
-- pack effects (data/lib/chaos_pack_fx.lua, switch ChaosPackFx.PACK_FX, on since 2026-10-13; off: exactly the stock effect as before)
if not ChaosPackFx then
	pcall(dofile, "data/lib/chaos_pack_fx.lua")
end
local function packFx(pos, use, stock)
	if ChaosPackFx then
		return ChaosPackFx.send(pos, use, stock)
	end
	if stock then
		pos:sendMagicEffect(stock)
	end
	return false
end
local S = ChaosSnaresCore
local function cfg()
	return ChaosSnaresConfig
end

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- the scheduler must not carry a cast context (data/spells/chaos/_supports.lua swaps addEvent during a cast)
local function rawAdd(fn, delay, ...)
	local raw = ChaosSupportsSpell and ChaosSupportsSpell.rawAddEvent or addEvent
	return raw(fn, delay, ...)
end

M.state = S.newState()
local running = false

local TYPES = {fire = "COMBAT_FIREDAMAGE", ice = "COMBAT_ICEDAMAGE", energy = "COMBAT_ENERGYDAMAGE",
	earth = "COMBAT_EARTHDAMAGE", death = "COMBAT_DEATHDAMAGE", holy = "COMBAT_HOLYDAMAGE",
	physical = "COMBAT_PHYSICALDAMAGE"}
local AREA_FX = {fire = "CONST_ME_FIREAREA", ice = "CONST_ME_ICEAREA", energy = "CONST_ME_ENERGYAREA",
	earth = "CONST_ME_GREEN_RINGS", death = "CONST_ME_MORTAREA", holy = "CONST_ME_HOLYAREA",
	physical = "CONST_ME_EXPLOSIONAREA"}
local SHOT = {fire = "CONST_ANI_FIRE", ice = "CONST_ANI_ICE", energy = "CONST_ANI_ENERGY", earth = "CONST_ANI_EARTH",
	death = "CONST_ANI_DEATH", holy = "CONST_ANI_HOLY", physical = "CONST_ANI_LARGEROCK"}
local function const(name, fallback)
	local v = name and _G[name]
	return v or fallback
end

-- ------------------------------------------------------------------------------------------------ the player
-- what the player has for the snares: the keystone (the archetype flag storage) and the worn snare uniques
function M.mods(player)
	local A, AC = ChaosArchetypesCore, ChaosArchetypesConfig
	if not A or not AC then
		return {}
	end
	local worn = A.wornUniques(player)
	return {keystone = A.maskHas(player:getStorageValue(AC.storage), "arSnarewright"), snarewalker = worn.snarewalker,
		fusewright = worn.fusewright}
end

-- the power the snares scale with: the best of the bow, the blade and the shuriken (ChaosSpell helpers)
function M.power(player)
	local best = player:getEffectiveSkillLevel(SKILL_DISTANCE) * ChaosSpell.distanceAttack(player)
	if ChaosSpell.bladePower then
		best = math.max(best, ChaosSpell.bladePower(player))
	end
	if ChaosSpell.shurikenPower then
		best = math.max(best, ChaosSpell.shurikenPower(player))
	end
	return best
end

-- the support number of the first brand rune socketed in the spell (spell supports), nil without one
local function brandOf(player, spellId)
	local sc = ChaosSupports and ChaosSupports.config or {}
	local base, firstId = sc.storageBase or 7110000, sc.firstId or 32101
	for slot = 1, 3 do
		local support = S.supportOfRune(player:getStorageValue(base + spellId * 4 + slot), firstId, 5)
		if support and cfg().brands[support] then
			return support
		end
	end
	return nil
end

local function paramOf(variant)
	if type(variant) ~= "table" and type(variant) ~= "userdata" then
		return ""
	end
	local ok, s = pcall(function()
		return variant.string or (variant.getString and variant:getString())
	end)
	return ok and type(s) == "string" and s or ""
end

local function inPz(pos)
	local tile = Tile(pos)
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function standable(pos)
	local tile = Tile(pos)
	return tile ~= nil and tile:getGround() ~= nil and not tile:hasFlag(TILESTATE_BLOCKSOLID)
		and not tile:hasFlag(TILESTATE_PROTECTIONZONE) and not tile:hasFlag(TILESTATE_FLOORCHANGE)
end

-- where a thrown snare lands: the attack target's tile (in range and sight), else up to `range` sqm ahead (the last
-- open tile in sight), else the caster's own tile
function M.landing(player, range)
	local from = player:getPosition()
	local target = player:getTarget()
	if target then
		local tp = target:getPosition()
		if tp.z == from.z and math.max(math.abs(tp.x - from.x), math.abs(tp.y - from.y)) <= range
				and from:isSightClear(tp, true) and standable(tp) then
			return Position(tp.x, tp.y, tp.z)
		end
	end
	local best = Position(from.x, from.y, from.z)
	local dir = player:getDirection()
	for i = 1, range do
		local p = ChaosSpell.stepPos(from, dir, i)
		if not standable(p) or not from:isSightClear(p, true) then
			break
		end
		best = p
	end
	return best
end

-- ------------------------------------------------------------------------------------------------ the bursts
local function enemiesNear(owner, pos, radius, needSight)
	local list = {}
	local center = Position(pos.x, pos.y, pos.z)
	for _, c in ipairs(Game.getSpectators(center, false, false, radius, radius, radius, radius) or {}) do
		if ChaosSpell.isEnemy(owner, c) then
			local cp = c:getPosition()
			if not needSight or center:isSightClear(cp, true) then
				list[#list + 1] = {id = c:getId(), pos = {x = cp.x, y = cp.y, z = cp.z}}
			end
		end
	end
	return list
end

local function setMarker(player, on)
	pcall(function()
		player:setStorageValue(cfg().storage.hit, on and 1 or -1)
	end)
end

local function applyEffect(owner, target, snare, hit)
	local fxs = S.elementEffect(snare.element, hit)
	if fxs.burn and Condition then
		local c = Condition(CONDITION_FIRE)
		c:setParameter(CONDITION_PARAM_OWNER, owner:getId())
		c:setParameter(CONDITION_PARAM_DELAYED, true)
		c:addDamage(fxs.burn.ticks, 1000, -fxs.burn.tick)
		target:addCondition(c)
	elseif fxs.poison and Condition then
		local c = Condition(CONDITION_POISON)
		c:setParameter(CONDITION_PARAM_OWNER, owner:getId())
		c:setParameter(CONDITION_PARAM_DELAYED, true)
		c:addDamage(fxs.poison.ticks, 1000, -fxs.poison.tick)
		target:addCondition(c)
	elseif fxs.slow then
		ChaosSpell.slow(target, fxs.slow.ms, fxs.slow.percent)
	end
	return fxs
end

local function burst(snare)
	local owner = Player(snare.owner)
	if not owner then
		return
	end
	local radius = S.burstRadius(snare.kind, snare.element)
	local center = Position(snare.pos.x, snare.pos.y, snare.pos.z)
	packFx(center, "snare_" .. tostring(snare.element), const(AREA_FX[snare.element], CONST_ME_EXPLOSIONAREA or CONST_ME_POFF))
	local targets = S.pickTargets(enemiesNear(owner, snare.pos, radius, true), snare.pos, radius,
		cfg()[snare.kind].maxTargets)
	local ctype = const(TYPES[snare.element], COMBAT_PHYSICALDAMAGE)
	local avg = math.floor((snare.min + snare.max) / 2)
	local drained, holy = 0, nil
	local function hits()
		for _, t in ipairs(targets) do
			local c = Creature(t.id)
			if c and c:getHealth() > 0 then
				local ok, err = pcall(doTargetCombat, owner, c, ctype, -snare.min, -snare.max, CONST_ME_NONE, ORIGIN_SPELL)
				if not ok then
					print("[ChaosSnares] " .. tostring(err))
				end
				c = Creature(t.id)
				if c and c:getHealth() > 0 then
					local fxs = applyEffect(owner, c, snare, avg)
					drained = drained + (fxs.drain or 0)
					holy = holy or fxs.holy and fxs
				elseif snare.element == "death" then
					drained = drained + (S.elementEffect("death", avg).drain or 0)
				end
			end
		end
	end
	setMarker(owner, true)
	-- the combat log (combatlog.lua, the same Lua state) names the hits by the snare's spell
	local CLog = ChaosCombatLog
	local ok, err
	if CLog and CLog.asSpell then
		ok, err = pcall(CLog.asSpell, owner:getId(), S.spellOf(snare), hits)
	else
		ok, err = pcall(hits)
	end
	setMarker(owner, false)
	if not ok then
		print("[ChaosSnares] burst: " .. tostring(err))
	end
	if drained > 0 and owner:getHealth() > 0 then
		owner:addHealth(drained)
	end
	if holy and #targets > 0 then
		for _, ally in ipairs(ChaosSpell.alliesAround(owner, center, holy.radius, false)) do
			if ally:isPlayer() and ally:getHealth() > 0 then
				ally:addHealth(math.floor(ally:getMaxHealth() * holy.holy))
				packFx(ally:getPosition(), "snare_holy_heal", CONST_ME_MAGIC_BLUE or CONST_ME_POFF)
			end
		end
	end
end

-- ------------------------------------------------------------------------------------------------ the scheduler
local function drop(snare)
	S.remove(M.state, snare.id)
	Position(snare.pos.x, snare.pos.y, snare.pos.z):sendMagicEffect(CONST_ME_POFF)
end

local tick
local function schedule()
	if not running then
		running = true
		rawAdd(tick, cfg().scan.tickMs)
	end
end

tick = function()
	running = false
	local t = now()
	local state = M.state
	local owners = {}
	for _, s in ipairs(S.batch(state, cfg().scan.perTick)) do
		local info = owners[s.owner]
		if info == nil then
			local p = Player(s.owner)
			info = p and {player = p, alive = p:getHealth() > 0, pos = p:getPosition(), inPz = inPz(p:getPosition())} or false
			owners[s.owner] = info
		end
		if not S.ownerKeeps(s, info or nil) then
			drop(s)
		else
			local what = S.visit(s, t)
			if what == "expire" then
				drop(s)
			elseif what == "fuse" then
				S.queueBurst(state, s, t)
			elseif what == "check" then
				if S.triggered(s, enemiesNear(info.player, s.pos, cfg().trap.triggerRadius, false)) then
					S.queueBurst(state, s, t)
				elseif t >= (s.nextFx or 0) then
					s.nextFx = t + 2000
					Position(s.pos.x, s.pos.y, s.pos.z):sendMagicEffect(CONST_ME_SMALLCLOUDS or CONST_ME_POFF)
				end
			end
		end
	end
	for _, s in ipairs(S.drainBursts(state, t)) do
		local ok, err = pcall(burst, s)
		if not ok then
			print("[ChaosSnares] burst: " .. tostring(err))
		end
	end
	if #state.list > 0 or #state.bursts > 0 then
		schedule()
	end
end
M.tick = tick

-- every snare of a player goes (the scripts' side calls it at logout and death when it shares this Lua state)
function M.clearOwner(pid)
	for _, s in ipairs(S.clearOwner(M.state, pid)) do
		Position(s.pos.x, s.pos.y, s.pos.z):sendMagicEffect(CONST_ME_POFF)
	end
end

-- ------------------------------------------------------------------------------------------------ the spells
-- Snare Trap (kind "trap") and Seeker Mine (kind "mine")
function M.cast(creature, kind, variant)
	local player = creature and creature:getPlayer()
	if not player then
		return false
	end
	local c = cfg()
	local mods = M.mods(player)
	local spellId = kind == "trap" and c.spells.trap or c.spells.mine
	local element, remember = S.chooseElement(paramOf(variant), player:getStorageValue(c.storage.element),
		brandOf(player, spellId))
	if remember then
		player:setStorageValue(c.storage.element, remember)
	end
	local pos = M.landing(player, c[kind].throwRange)
	if inPz(pos) then
		return ChaosSpell.cancel(player, "You cannot place a snare in a protection zone.")
	end
	local min, max = S.damage(player:getLevel(), M.power(player), kind, element, mods)
	local t = now()
	local armedAt = t + S.armMs(kind, mods)
	local snare = {kind = kind, owner = player:getId(), pos = {x = pos.x, y = pos.y, z = pos.z}, element = element,
		min = min, max = max, placed = t, armedAt = armedAt, untilTime = armedAt + S.lifeMs(kind, mods)}
	local ok, gone = S.add(M.state, snare, S.cap(kind, mods))
	if not ok then
		return ChaosSpell.cancel(player, "There are too many snares here already.")
	end
	for _, g in ipairs(gone) do
		Position(g.pos.x, g.pos.y, g.pos.z):sendMagicEffect(CONST_ME_POFF)
	end
	local from = player:getPosition()
	if from.x ~= pos.x or from.y ~= pos.y then
		from:sendDistanceEffect(pos, const(SHOT[element], CONST_ANI_SMALLSTONE or 1))
	end
	pos:sendMagicEffect(kind == "trap" and (CONST_ME_BLOCKHIT or CONST_ME_POFF) or (CONST_ME_FIREATTACK or CONST_ME_POFF))
	player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR or 1, string.format("%s %s (%s): %d of %d.",
		kind == "trap" and "Trap" or "Mine", "set", element, S.count(M.state, player:getId(), kind), S.cap(kind, mods)))
	schedule()
	return true
end

-- Detonate Mines: every armed mine of the caster goes off
function M.detonate(creature)
	local player = creature and creature:getPlayer()
	if not player then
		return false
	end
	local n = S.detonate(M.state, player:getId(), now())
	if n == 0 then
		return ChaosSpell.cancel(player, "You have no armed mine.")
	end
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_RED or CONST_ME_POFF)
	schedule()
	return true
end

return M
