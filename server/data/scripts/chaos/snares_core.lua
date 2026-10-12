-- snares_core.lua: the pure rules of the snares, traps and mines (ChaosSnaresCore). No engine calls: plain numbers and
-- tables in and out, so server/tests/snares_test.lua covers every rule. Numbers: snares_config.lua. Engine glue: the
-- spells' side, data/spells/chaos/_snares.lua. Design: docs/BUILDS.md "Snares". Lua 5.1 / LuaJIT and Lua 5.3.
--
-- A snare = {id, kind = "trap" | "mine", owner (player id), pos = {x, y, z}, element, min, max, placed, armedAt,
-- untilTime (trap: its end; mine: its fuse), detonating (a mine already queued)}.

ChaosSnaresConfig = ChaosSnaresConfig or dofile("data/scripts/chaos/snares_config.lua")

ChaosSnaresCore = ChaosSnaresCore or {}
local S = ChaosSnaresCore
S.cfg = ChaosSnaresConfig
local function cfg()
	return S.cfg
end

-- ------------------------------------------------------------------------------------------------ elements
local ALIASES = {fire = "fire", flame = "fire", ice = "ice", frost = "ice", cold = "ice", energy = "energy",
	lightning = "energy", storm = "energy", earth = "earth", poison = "earth", venom = "earth", death = "death",
	holy = "holy", light = "holy", physical = "physical", plain = "physical"}

-- the element named by a spell's parameter text ("fire", " Frost ", "poison"), nil when it names none
function S.parseElement(text)
	if type(text) ~= "string" then
		return nil
	end
	local word = text:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub('^"', "")
	return ALIASES[word]
end

function S.elementIndex(element)
	for i, e in ipairs(cfg().elements) do
		if e == element then
			return i
		end
	end
	return nil
end

-- the element of a new snare: the parameter, else the one remembered (an index), else the spell's brand rune (the
-- support number of the rune, 1-5), else physical. Returns element, remember (the index to store when a parameter named
-- one, else nil)
function S.chooseElement(param, storedIndex, brandSupport)
	local named = S.parseElement(param)
	if named then
		return named, S.elementIndex(named)
	end
	local stored = tonumber(storedIndex)
	if stored and cfg().elements[stored] then
		return cfg().elements[stored], nil
	end
	local brand = brandSupport and cfg().brands[brandSupport]
	if brand then
		return brand, nil
	end
	return "physical", nil
end

-- the support number of a rune server id (chaos_supports_config.lua: firstId + (support - 1) x 5 + level - 1)
function S.supportOfRune(runeId, firstId, perSupport)
	runeId, firstId, perSupport = tonumber(runeId), tonumber(firstId) or 32101, tonumber(perSupport) or 5
	if not runeId or runeId < firstId then
		return nil
	end
	return math.floor((runeId - firstId) / perSupport) + 1
end

-- ------------------------------------------------------------------------------------------------ caps and timing
-- what a player has: mods = {keystone = bool, snarewalker = bool, fusewright = bool}
function S.cap(kind, mods)
	local c = cfg()
	local n = c.caps[kind] or 0
	mods = mods or {}
	if mods.keystone then
		n = n + (kind == "trap" and c.keystone.traps or c.keystone.mines)
	end
	if kind == "trap" and mods.snarewalker then
		n = n + c.uniques.snarewalker.traps
	elseif kind == "mine" and mods.fusewright then
		n = n + c.uniques.fusewright.mines
	end
	return n
end

function S.armMs(kind, mods)
	local c = cfg()
	local ms = c[kind].armMs
	mods = mods or {}
	if mods.keystone then
		ms = ms * c.keystone.armFactor
	end
	if kind == "trap" and mods.snarewalker then
		ms = ms - c.uniques.snarewalker.armMs
	end
	return math.max(0, math.floor(ms))
end

-- a trap's end or a mine's fuse, counted from the moment it is armed
function S.lifeMs(kind, mods)
	local c = cfg()
	if kind == "trap" then
		return c.trap.lifeMs
	end
	return c.mine.fuseMs + ((mods and mods.fusewright) and c.uniques.fusewright.fuseMs or 0)
end

-- ------------------------------------------------------------------------------------------------ damage
-- the hit of a snare per target: min, max (positive numbers), before the tree, the class factor and the prices
function S.damage(level, power, kind, element, mods)
	local c = cfg()
	local d = c.damage
	level, power, mods = level or 0, power or 0, mods or {}
	local min = level * d.min.perLevel + power * d.min.perPower + d.min.base
	local max = level * d.max.perLevel + power * d.max.perPower + d.max.base
	local m = 1
	if kind == "mine" then
		m = m * c.mine.damageFactor * (1 + (mods.fusewright and c.uniques.fusewright.mineDamage or 0))
	elseif mods.snarewalker then
		m = m * (1 + c.uniques.snarewalker.trapDamage)
	end
	if mods.keystone then
		m = m * (1 + c.keystone.damage)
	end
	if element == "physical" then
		m = m * c.effects.physicalFactor
	elseif element == "energy" then
		m = m * c.effects.energyFactor
	end
	return math.floor(min * m), math.floor(max * m)
end

-- the burst radius of a snare (energy reaches farther)
function S.burstRadius(kind, element)
	local r = cfg()[kind].burstRadius
	if element == "energy" then
		r = r + cfg().effects.energyRadius
	end
	return r
end

-- what the element adds to a hit of `hit` (the damage dealt to one target): a table the glue turns into conditions or
-- heals. {burn = {tick, ticks}} | {slow = {percent, ms}} | {poison = {tick, ticks}} | {drain = amount} | {holy = share}
function S.elementEffect(element, hit)
	local e = cfg().effects
	hit = math.abs(hit or 0)
	if element == "fire" then
		return {burn = {tick = math.max(1, math.floor(hit * e.burnShare / e.burnTicks)), ticks = e.burnTicks}}
	elseif element == "ice" then
		return {slow = {percent = e.slowPercent, ms = e.slowMs}}
	elseif element == "earth" then
		return {poison = {tick = math.max(1, math.floor(hit * e.poisonShare / e.poisonTicks)), ticks = e.poisonTicks}}
	elseif element == "death" then
		return {drain = math.floor(hit * e.deathLeech)}
	elseif element == "holy" then
		return {holy = e.holyHeal, radius = e.holyRadius}
	end
	return {}
end

-- ------------------------------------------------------------------------------------------------ the list
-- state = {list = {snares in placing order}, seq, cursor, bursts = {queued bursts {id, at}}}
function S.newState()
	return {list = {}, seq = 0, cursor = 1, bursts = {}}
end

function S.count(state, owner, kind)
	local n = 0
	for _, s in ipairs(state.list) do
		if s.owner == owner and (not kind or s.kind == kind) then
			n = n + 1
		end
	end
	return n
end

local function removeAt(state, i)
	local s = table.remove(state.list, i)
	if state.cursor > i then
		state.cursor = state.cursor - 1
	end
	if state.cursor > #state.list then
		state.cursor = 1
	end
	return s
end

-- add a snare: returns ok, gone (the owner's oldest snares of that kind over the cap) or nil, "global" when the global
-- cap is reached
function S.add(state, snare, cap)
	if #state.list >= cfg().globalCap then
		return nil, "global"
	end
	state.seq = state.seq + 1
	snare.id = state.seq
	state.list[#state.list + 1] = snare
	local gone = {}
	while S.count(state, snare.owner, snare.kind) > cap do
		for i, s in ipairs(state.list) do
			if s.owner == snare.owner and s.kind == snare.kind then
				gone[#gone + 1] = removeAt(state, i)
				break
			end
		end
	end
	return true, gone
end

function S.remove(state, id)
	for i, s in ipairs(state.list) do
		if s.id == id then
			return removeAt(state, i)
		end
	end
	return nil
end

-- every snare of an owner goes (logout, death, area change): the removed ones
function S.clearOwner(state, owner)
	local gone = {}
	for i = #state.list, 1, -1 do
		if state.list[i].owner == owner then
			table.insert(gone, 1, removeAt(state, i))
		end
	end
	local keep = {}
	for _, b in ipairs(state.bursts) do
		if b.owner ~= owner then
			keep[#keep + 1] = b
		end
	end
	state.bursts = keep
	return gone
end

-- may the owner keep its snare? owner = nil (logged out) or {alive, pos, inPz}
function S.ownerKeeps(snare, owner)
	if not owner or not owner.alive or owner.inPz or not owner.pos then
		return false
	end
	local p, q = owner.pos, snare.pos
	if p.z ~= q.z then
		return false
	end
	return math.max(math.abs(p.x - q.x), math.abs(p.y - q.y)) <= cfg().leashSqm
end

-- the snares the scheduler visits this tick: at most n (round robin from the cursor)
function S.batch(state, n)
	local out = {}
	local total = #state.list
	if total == 0 then
		state.cursor = 1
		return out
	end
	n = math.min(n or cfg().scan.perTick, total)
	local i = state.cursor
	if i > total then
		i = 1
	end
	for _ = 1, n do
		out[#out + 1] = state.list[i]
		i = i + 1
		if i > total then
			i = 1
		end
	end
	state.cursor = i
	return out
end

-- what the scheduler does with a visited snare at `now`: "expire" (a trap past its end), "fuse" (a mine past its
-- fuse), "check" (an armed trap: look for monsters), nil (wait)
function S.visit(snare, now)
	if snare.detonating then
		return nil
	end
	if snare.armedAt and now >= snare.untilTime then
		return snare.kind == "trap" and "expire" or "fuse"
	end
	if snare.kind == "trap" and now >= snare.armedAt then
		return "check"
	end
	return nil
end

-- queue a burst (a triggered trap, a detonated mine): false when the queue is full or it is queued already
function S.queueBurst(state, snare, at)
	if snare.detonating or #state.bursts >= cfg().scan.burstQueueMax then
		return false
	end
	snare.detonating = true
	state.bursts[#state.bursts + 1] = {id = snare.id, owner = snare.owner, at = at}
	return true
end

-- Detonate Mines: every armed mine of the owner, staggerMs apart, the oldest first. Returns how many were queued.
function S.detonate(state, owner, now)
	local n = 0
	for _, s in ipairs(state.list) do
		if s.owner == owner and s.kind == "mine" and now >= s.armedAt and not s.detonating then
			if S.queueBurst(state, s, now + n * cfg().mine.staggerMs) then
				n = n + 1
			end
		end
	end
	return n
end

-- the bursts due at `now`, at most n, removed from the queue and from the list (the snare objects)
function S.drainBursts(state, now, n)
	n = n or cfg().scan.burstsPerTick
	local out, keep = {}, {}
	table.sort(state.bursts, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.id < b.id
	end)
	for _, b in ipairs(state.bursts) do
		if #out < n and b.at <= now then
			local s = S.remove(state, b.id)
			if s then
				out[#out + 1] = s
			end
		else
			keep[#keep + 1] = b
		end
	end
	state.bursts = keep
	return out
end

-- enemies {id, pos} within radius of center, nearest first (ties: lowest id), at most max
function S.pickTargets(candidates, center, radius, max)
	local list = {}
	for _, c in ipairs(candidates or {}) do
		local p = c.pos
		if p.z == center.z then
			local d = math.max(math.abs(p.x - center.x), math.abs(p.y - center.y))
			if d <= radius then
				list[#list + 1] = {id = c.id, pos = p, d = d}
			end
		end
	end
	table.sort(list, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.id < b.id
	end)
	for i = #list, (max or #list) + 1, -1 do
		list[i] = nil
	end
	return list
end

-- does a trap go off: any enemy within triggerRadius
function S.triggered(trap, candidates)
	return #S.pickTargets(candidates, trap.pos, cfg().trap.triggerRadius, 1) > 0
end

return S
