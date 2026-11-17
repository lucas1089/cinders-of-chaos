-- Status layer (O597; server/README.md "Status layer (O597)"): which of 14 statuses a creature shows, told to the clients
-- near it. The client (game_statusfx) plays the pair effects of a status on the creature: start once, loop while the
-- status holds, stop once. This file is the pure part (no engine call; server/tests/status_vfx_test.lua); the engine
-- glue is scripts/chaos/status_vfx.lua.
--
-- A creature's statuses are one number, a bit mask in the order of ChaosStatusVfxIds.order (bit i - 1 = order[i]):
--   burn freeze shock poison curse root soak stun confuse haste bless regen shield rage
-- Sources:
--   * engine conditions (S.conditions): fire, freezing, energy, poison, cursed, paralyse, drown, drunk, haste, a
--     spell's regeneration, mana shield. Read by the glue's scan.
--   * marks (S.mark): the Chaos call sites that know a state. They all go through ChaosPack29Vfx.show / hold
--     (slows, stuns, chill and shock, status words, boss phases, blessings, rages, shields), so that library hands
--     its states over here (S.states) while the layer is live and no longer sends its own pair 29 aura.
-- Haste is brief (S.brief): shown for S.briefMs after it starts, not for as long as it lasts (most characters are
-- hasted all the time).
-- Gate: ChaosStatusVfxIds.on (config.lua chaosClientPair >= 73). Off: nothing here does anything.
-- Lua 5.1 / LuaJIT / 5.3.

if not ChaosStatusVfxIds then
	local ok = pcall(dofile, "data/lib/chaos_status_vfx_ids.lua")
	if not ok or not ChaosStatusVfxIds then
		error("chaos_status_vfx.lua: data/lib/chaos_status_vfx_ids.lua is missing")
	end
end

ChaosStatusVfx = ChaosStatusVfx or {}
local S = ChaosStatusVfx
local I = ChaosStatusVfxIds

S.OPCODE = 165
S.scanMs = 500          -- the glue's scan
S.viewX, S.viewY = 9, 7 -- the tiles around a watcher that are told
S.maxPairs = 60         -- creature / mask pairs per message
S.maxMarks = 4000       -- marks kept at once (the oldest scan drops the ended ones)
S.briefMs = 2500
S.brief = {haste = true}
S.showSlackMs = 700     -- a mark from a single show lasts the aura's length plus this

-- status -> bit value
S.bits = {}
do
	local b = 1
	for _, name in ipairs(I.order) do
		S.bits[name] = b
		b = b * 2
	end
end

-- a state of chaos_pack29_vfx.lua -> its status (bleeding, fear, silenced and petrified have none)
S.states = {
	burning = "burn", poison = "poison", frozen = "freeze", slowed = "root", shocked = "shock", cursed = "curse",
	stunned = "stun", confused = "confuse", regeneration = "regen", blessed = "bless", enraged = "rage",
	invulnerable = "shield",
}

-- engine conditions: {status, condition type name, condition id name or false (any id), players only}
S.conditions = {
	{"burn", "CONDITION_FIRE", false, false},
	{"freeze", "CONDITION_FREEZING", false, false},
	{"shock", "CONDITION_ENERGY", false, false},
	{"poison", "CONDITION_POISON", false, false},
	{"curse", "CONDITION_CURSED", false, false},
	{"root", "CONDITION_PARALYZE", false, false},
	{"soak", "CONDITION_DROWN", false, false},
	{"confuse", "CONDITION_DRUNK", false, true},
	{"haste", "CONDITION_HASTE", false, true},
	{"regen", "CONDITION_REGENERATION", "CONDITIONID_COMBAT", true}, -- a spell's regeneration, not the food one
	{"shield", "CONDITION_MANASHIELD", false, true},
}

function S.live()
	return I.on == true
end

-- O613 (owner 2026-11-17): a status that another pair 73 effect draws is not shown by the layer. A slowed creature
-- shows the pack's gravity press (data/lib/chaos_area_fx.lua C.status, sent by ChaosPack29Vfx.show / hold), so `root`
-- yields while that effect is live: no mark from the state, no bit from the paralyse condition. One row; an empty
-- table gives the root status back to the layer.
S.yield = {root = "slowed"}   -- status -> the pack 29 state the other effect draws

function S.yielded(status)
	local state = S.yield[status]
	if not state then
		return false
	end
	if ChaosAreaFx == nil then
		ChaosAreaFx = false
		pcall(dofile, "data/lib/chaos_area_fx.lua")
	end
	local A = ChaosAreaFx
	if not A or not A.statusName then
		return false
	end
	local ok, name = pcall(A.statusName, state)
	return ok and name ~= nil
end

local function hasBit(mask, bit)
	return mask % (bit * 2) >= bit
end
S.hasBit = hasBit

-- the mask of a list of status names (unknown names are skipped)
function S.maskOf(names)
	local m = 0
	for _, n in ipairs(names) do
		local b = S.bits[n]
		if b and not hasBit(m, b) then
			m = m + b
		end
	end
	return m
end

-- the status names of a mask, in bit order
function S.namesOf(mask)
	local out = {}
	for _, n in ipairs(I.order) do
		if hasBit(mask, S.bits[n]) then
			out[#out + 1] = n
		end
	end
	return out
end

-- the constants of S.conditions looked up in a globals table: {bit, type, id or nil, hasId, playersOnly} rows
function S.resolve(G)
	local rows = {}
	for _, c in ipairs(S.conditions) do
		local ctype = G[c[2]]
		local id = c[3] and G[c[3]] or nil
		if ctype and S.bits[c[1]] and (not c[3] or id) then
			rows[#rows + 1] = {S.bits[c[1]], ctype, id, c[3] ~= false, c[4]}
		end
	end
	return rows
end

-- the condition part of a creature's mask; probe(type, id or nil) -> true when the creature has it
function S.conditionMask(rows, isPlayer, probe)
	local m = 0
	for i = 1, #rows do
		local r = rows[i]
		if (isPlayer or not r[5]) and not hasBit(m, r[1]) and probe(r[2], r[3]) then
			m = m + r[1]
		end
	end
	return m
end

-- ---------------------------------------------------------------- marks
S.marks = S.marks or {}   -- creature id -> {status -> until ms}
S.markCount = S.markCount or 0

function S.mark(id, status, ms, now)
	if not S.bits[status] or type(id) ~= "number" or type(ms) ~= "number" or ms <= 0 then
		return false
	end
	local t = S.marks[id]
	if not t then
		if S.markCount >= S.maxMarks then
			return false
		end
		t = {}
		S.marks[id] = t
		S.markCount = S.markCount + 1
	end
	local untilMs = now + ms
	if not t[status] or t[status] < untilMs then
		t[status] = untilMs
	end
	return true
end

-- a pack 29 state on a creature id for ms; false when the state has no status (the caller sends its own aura)
function S.markState(id, state, ms, now)
	local status = S.states[state]
	return status ~= nil and not S.yielded(status) and S.mark(id, status, ms, now)
end

-- the marks' part of a creature's mask; ended marks are dropped
function S.markMask(id, now)
	local t = S.marks[id]
	if not t then
		return 0
	end
	local m, any = 0, false
	for status, untilMs in pairs(t) do
		if untilMs > now then
			m = m + S.bits[status]
			any = true
		else
			t[status] = nil
		end
	end
	if not any then
		S.marks[id] = nil
		S.markCount = math.max(0, S.markCount - 1)
	end
	return m
end

-- drop every ended mark (the glue calls it now and then, so the marks of creatures nobody looks at do not pile up)
function S.pruneMarks(now)
	local ids = {}
	for id in pairs(S.marks) do
		ids[#ids + 1] = id
	end
	for _, id in ipairs(ids) do
		S.markMask(id, now)
	end
	return S.markCount
end

function S.forget(id)
	if S.marks[id] then
		S.marks[id] = nil
		S.markCount = math.max(0, S.markCount - 1)
	end
	S.since[id] = nil
end

-- ---------------------------------------------------------------- brief statuses
S.since = S.since or {}   -- creature id -> {status -> ms it was first seen}

-- a mask with the brief statuses cut to their first S.briefMs
function S.cutBrief(id, mask, now)
	for status in pairs(S.yield) do -- O613: a status another effect draws
		local b = S.bits[status]
		if b and hasBit(mask, b) and S.yielded(status) then
			mask = mask - b
		end
	end
	local t = S.since[id]
	for name in pairs(S.brief) do
		local b = S.bits[name]
		if b and hasBit(mask, b) then
			if not t then
				t = {}
				S.since[id] = t
			end
			t[name] = t[name] or now
			if now - t[name] >= S.briefMs then
				mask = mask - b
			end
		elseif t and t[name] then
			t[name] = nil
			if next(t) == nil then
				S.since[id] = nil
				t = nil
			end
		end
	end
	return mask
end

-- ---------------------------------------------------------------- what a watcher is told
-- known: the watcher's {creature id -> mask it was last told (never 0)}; visible: {creature id -> mask now}.
-- Returns the flat list {id, mask, id, mask, ...} of what changed (mask 0: the creature shows nothing any more, also
-- one that left the view) in id order, and updates `known`.
function S.changes(known, visible)
	local ids = {}
	for id, mask in pairs(visible) do
		if (known[id] or 0) ~= mask then
			ids[#ids + 1] = id
		end
	end
	for id in pairs(known) do
		if visible[id] == nil then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do
		local mask = visible[id] or 0
		out[#out + 1] = id
		out[#out + 1] = mask
		known[id] = mask ~= 0 and mask or nil
	end
	return out
end

-- a flat list cut into lists of at most S.maxPairs pairs
function S.batches(list)
	local out = {}
	local per = S.maxPairs * 2
	for i = 1, #list, per do
		local part = {}
		for j = i, math.min(#list, i + per - 1) do
			part[#part + 1] = list[j]
		end
		out[#out + 1] = part
	end
	return out
end

-- the answer to a client's hello: the effect ids, flat {start, loop, stop} per status in bit order, and the lengths
function S.hello()
	if not S.live() then
		return {on = 0}
	end
	local e, ms = {}, {}
	for _, name in ipairs(I.order) do
		local s = I.status[name]
		e[#e + 1] = s.start; e[#e + 1] = s.loop; e[#e + 1] = s.stop
		ms[#ms + 1] = s.startMs; ms[#ms + 1] = s.loopMs; ms[#ms + 1] = s.stopMs
	end
	return {on = 1, e = e, ms = ms}
end

return S
