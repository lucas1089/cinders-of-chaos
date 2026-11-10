-- dot_core.lua: damage over time that is worth casting (O474; numbers: dot_config.lua). Pure logic plus the one storage flag
-- that makes a scripted tick known to the damage events. Tests: server/tests/dot_core_test.lua. Lua 5.1 / LuaJIT and 5.3.
--
-- What it holds:
--   * ChaosDot.isTick(origin, attacker, creature): the one predicate "this is a damage over time tick". True for an engine
--     condition tick (ORIGIN_CONDITION) and for a scripted tick, a pulse of a dot spell that ChaosDot.run dealt. The gear
--     "Damage over Time" modifier, the trial nodes, the spread uniques, Contagion Rite, the Cinder Sigil, the combat log and the
--     monster armour all ask it. A tick rolls no on-hit ailment and no leech and skips monster armour.
--   * the sizes: side dots (a share of the cast's own hit), Blightswarm (its old total in fewer ticks), one gear ailment stack.
--   * the rules: where a dot moves on when its host dies (pickJump), gear ailment stacks (stackAdd / stackStep).
--   * the PvP timing and the condition icon helpers.
-- The spell scripts run in another Lua state than the damage events: this file is loaded in both (the spells' _common.lua loads
-- it too), and the tick flag is a player storage (ChaosDotConfig.storage): the id of the creature the scripted tick hits.

ChaosDot = ChaosDot or {}
local D = ChaosDot

local floor, abs, max, min = math.floor, math.abs, math.max, math.min
local unpack = table.unpack or unpack

local function cfg()
	return ChaosDotConfig or {}
end
D.cfg = cfg

-- ------------------------------------------------------------------------------------------------ the predicate
-- true while a scripted tick is dealt to `creature` by the player `attacker` (ChaosDot.run raised the flag)
function D.flagged(attacker, creature)
	if not attacker or not creature or not attacker.isPlayer or not attacker:isPlayer() then
		return false
	end
	local key = cfg().storage
	if not key then
		return false
	end
	local ok, v = pcall(attacker.getStorageValue, attacker, key)
	if not ok or type(v) ~= "number" or v <= 0 then
		return false
	end
	local okId, id = pcall(creature.getId, creature)
	return okId and id == v
end

-- an engine condition tick, or a scripted tick of a player on `creature`
function D.isTick(origin, attacker, creature)
	if ORIGIN_CONDITION ~= nil and origin == ORIGIN_CONDITION then
		return true
	end
	return D.flagged(attacker, creature)
end

-- run fn(...) with the tick flag of `caster` raised for `target`; the flag is put back (also when fn fails, whose error goes on)
function D.run(caster, target, fn, ...)
	local key = cfg().storage
	local raised, prev = false, -1
	if key and caster and target and caster.setStorageValue and caster.isPlayer and caster:isPlayer() then
		raised = pcall(function()
			prev = caster:getStorageValue(key)
			caster:setStorageValue(key, target:getId())
		end)
	end
	local res = {pcall(fn, ...)}
	if raised then
		pcall(caster.setStorageValue, caster, key, prev)
	end
	if not res[1] then
		error(res[2], 0)
	end
	return unpack(res, 2)
end

-- ------------------------------------------------------------------------------------------------------ sizes
-- the tick of a side dot: `share` of the cast's own hit (lo, hi positive) over `ticks` ticks (not rounded)
function D.sideTick(lo, hi, side)
	side = side or cfg().side
	return side.share * ((lo + hi) / 2) / side.ticks
end

-- the total of the side dot
function D.sideTotal(lo, hi, side)
	side = side or cfg().side
	return D.sideTick(lo, hi, side) * side.ticks
end

-- Blightswarm: its old tick (the old total over the old ticks) spread over the new ticks
function D.swarmTick(oldTick, swarm)
	swarm = swarm or cfg().swarm
	return oldTick * swarm.oldTicks / swarm.ticks
end

-- one gear ailment stack: `share` percent of the hit over `rounds` ticks, whole points, at least 1
function D.ailmentTick(hit, share, rounds)
	rounds = rounds or cfg().ailment.rounds
	return max(1, floor(abs(tonumber(hit) or 0) * (tonumber(share) or 0) / 100 / rounds + 1e-9))
end

-- --------------------------------------------------------------------------------------------- a dot moves on
-- The next host of a dot whose host died: the nearest of `candidates` ({id, pos, alive, player, summon, busy}) within
-- `radius` of `pos` (same floor, squares like a king's move), nil when none. Players and summons are never picked, nor a
-- creature that already carries the same dot (busy). Ties: the lower id.
function D.pickJump(candidates, pos, radius)
	local best, bestDist
	if not pos then
		return nil
	end
	for _, c in ipairs(candidates or {}) do
		if c.alive and not c.player and not c.summon and not c.busy and c.pos and c.pos.z == pos.z then
			local d = max(abs(c.pos.x - pos.x), abs(c.pos.y - pos.y))
			if d <= radius and (not best or d < bestDist or (d == bestDist and (c.id or 0) < (best.id or 0))) then
				best, bestDist = c, d
			end
		end
	end
	return best
end

-- ------------------------------------------------------------------------------------------------ gear ailment stacks
-- A stack list is {{tick, left}, ...}. Adds a stack of `tick` for `rounds` ticks: while there is room it is added; at the cap
-- the weakest of the old stacks (the lowest tick, then the fewest ticks left) is replaced, unless the new one is weaker than
-- every old one (it is the weakest of the four then and is dropped). Returns the list and whether the new stack was kept.
function D.stackAdd(list, tick, rounds, maxStacks)
	list = list or {}
	maxStacks = maxStacks or cfg().ailment.maxStacks
	rounds = rounds or cfg().ailment.rounds
	if #list < maxStacks then
		list[#list + 1] = {tick = tick, left = rounds}
		return list, true
	end
	local wi
	for i, s in ipairs(list) do
		if not wi or s.tick < list[wi].tick or (s.tick == list[wi].tick and s.left < list[wi].left) then
			wi = i
		end
	end
	if wi and tick >= list[wi].tick then
		list[wi] = {tick = tick, left = rounds}
		return list, true
	end
	return list, false
end

-- One beat of a stack list: the damage of every stack (their sum) and one tick used up on each; spent stacks leave the list.
-- Returns the sum (0 for an empty list).
function D.stackStep(list)
	local sum = 0
	local i = 1
	while list[i] do
		local s = list[i]
		sum = sum + s.tick
		s.left = s.left - 1
		if s.left <= 0 then
			table.remove(list, i)
		else
			i = i + 1
		end
	end
	return sum
end

-- ----------------------------------------------------------------------------------------------------- PvP timing
-- the old timing and size of a dot against a player: {ticks, tickMs, firstMs, mult} (nil fields: unchanged), or nil
function D.pvpSide(key)
	local p = cfg().pvp
	return p and p.side and p.side[key] or nil
end

-- the opts of ChaosSpell.scriptedDot for a side dot or Blightswarm against a player: the old ticks, gap and first tick with the
-- old tick `base` (the script's own old formula), or nil
function D.pvpSideOpts(key, base)
	local o = D.pvpSide(key)
	if not o then
		return nil
	end
	return {ticks = o.ticks, tickMs = o.tickMs, firstMs = o.firstMs, base = base}
end

function D.pvpKit(key)
	local p = cfg().pvp
	local k = p and p.kit
	if not k then
		return nil
	end
	return {tickMs = k.tickMs, firstMs = k.firstMs, mult = k.mult and k.mult[key] or 1}
end

function D.pvpNecro(key)
	local p = cfg().pvp
	local n = p and p.necro
	if not n then
		return nil
	end
	return {tickMs = n.tickMs, firstMs = n.firstMs, mult = key == "soulrot" and n.soulRotMult or 1}
end

-- ---------------------------------------------------------------------------------------------- the condition icon
-- the engine condition type that shows a dot of combat type `ctype` (a COMBAT_ constant), or nil: the config's table by name
function D.iconType(ctype)
	local icon = cfg().icon
	if not icon or icon.enabled == false then
		return nil
	end
	for name, condName in pairs(icon.byType or {}) do
		local c = _G["COMBAT_" .. name:upper() .. "DAMAGE"]
		if c ~= nil and c == ctype then
			return _G[condName]
		end
	end
	return nil
end

-- A zero-damage condition of type `condType` on `target` for `durationMs` with the dot icon's own sub id: it shows the icon,
-- a cure removes it, it never replaces a real condition (another sub id). Returns the sub id when it was added, else nil.
function D.addIcon(target, condType, durationMs, owner)
	local icon = cfg().icon
	if not icon or not condType or not Condition or not target or not target.addCondition then
		return nil
	end
	local ok, added = pcall(function()
		local c = Condition(condType, CONDITIONID_COMBAT)
		c:setParameter(CONDITION_PARAM_SUBID, icon.subId)
		if owner then
			c:setParameter(CONDITION_PARAM_OWNER, owner)
		end
		c:setParameter(CONDITION_PARAM_DELAYED, true)
		c:addDamage(1, durationMs, 0)
		return target:addCondition(c)
	end)
	if ok and added then
		return icon.subId
	end
	return nil
end

-- true while the icon condition added by addIcon is still on `target` (a cure removed it when false)
function D.iconHeld(target, condType)
	local icon = cfg().icon
	if not icon or not condType or not target or not target.getCondition then
		return true
	end
	local ok, c = pcall(target.getCondition, target, condType, CONDITIONID_COMBAT, icon.subId)
	return not ok or c ~= nil
end

return D
