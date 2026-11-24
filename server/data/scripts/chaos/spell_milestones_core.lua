-- Spell path milestones (O752): pure logic, no engine calls. Numbers: spell_milestones_config.lua; engine: spell_milestones.lua,
-- spell_forms.lua, spell_awakening.lua; model: tools/progression_model.lua --spells / --check; tests: tests/spell_milestones_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosSpellMilestonesCore = ChaosSpellMilestonesCore or {}
local M = ChaosSpellMilestonesCore

local floor, max = math.floor, math.max

local function num(v, d)
	v = tonumber(v)
	if v == nil or v ~= v then
		return d
	end
	return v
end

-- the order of kinds at one level (the toast and the client name the first)
M.KINDS = {"spell", "slot", "awaken", "form2", "form1", "socket3", "socket2"}
local ORDER = {}
for i, k in ipairs(M.KINDS) do
	ORDER[k] = i
end

-- the level of the first row of `rows` whose `below` is above `learn` (a row with no `below` takes the rest); nil for no rows
function M.band(rows, learn)
	learn = num(learn, 0)
	for _, r in ipairs(rows or {}) do
		if r.below == nil or learn < r.below then
			return r.level
		end
	end
	return nil
end

-- the level the Form tier (1 or 2) of a spell learned at `learn` opens
function M.formLevel(cfg, tier, learn)
	learn = max(0, floor(num(learn, 0)))
	local one = learn + num(cfg.formI and cfg.formI.add, 0)
	if tier == 1 then
		return one
	end
	return max(one, num(M.band(cfg.formII, learn), 0))
end

-- the level a spell learned at `learn` may be awakened at (0: only the slot decides)
function M.awakenLevel(cfg, learn)
	return max(0, num(M.band(cfg.awaken, max(0, floor(num(learn, 0)))), 0))
end

-- the level awakening slot n needs (0 for a slot the table has no row for)
function M.slotLevel(cfg, slot)
	return num((cfg.slots or {})[floor(num(slot, 0))], 0)
end

-- the support socket levels of a spell (chaos_supports_config.lua second / third): second, third
function M.socketLevels(scfg, learn)
	learn = num(learn, 0)
	return max(scfg.second.min, learn + scfg.second.add), max(scfg.third.min, learn + scfg.third.add)
end

-- every milestone of one class. spells: {{id, name, level, forms = bool, awaken = bool, sockets = bool}, ...}; scfg: the supports
-- config (nil: no socket milestones). Returns a list sorted by level, then by M.KINDS: {level, kind, id, name, slot}
function M.list(cfg, spells, scfg)
	local out = {}
	local function add(level, kind, s, slot)
		out[#out + 1] = {level = level, kind = kind, id = s and s.id, name = s and s.name, slot = slot}
	end
	local slot1 = M.slotLevel(cfg, 1)
	for _, s in ipairs(spells or {}) do
		local learn = max(0, floor(num(s.level, 0)))
		add(learn, "spell", s)
		if s.sockets and scfg then
			local a, b = M.socketLevels(scfg, learn)
			add(a, "socket2", s)
			add(b, "socket3", s)
		end
		if s.forms then
			add(M.formLevel(cfg, 1, learn), "form1", s)
			add(M.formLevel(cfg, 2, learn), "form2", s)
		end
		if s.awaken then
			local a = M.awakenLevel(cfg, learn)
			if a > slot1 then
				add(a, "awaken", s)
			end
		end
	end
	for i in ipairs(cfg.slots or {}) do
		add(M.slotLevel(cfg, i), "slot", nil, i)
	end
	table.sort(out, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		if a.kind ~= b.kind then
			return (ORDER[a.kind] or 99) < (ORDER[b.kind] or 99)
		end
		return num(a.id, 0) < num(b.id, 0)
	end)
	return out
end

-- the stretches without a milestone that touch [from, to]: {{from = a, to = b, gap = b - a}, ...} in level order, and the longest.
-- The stretch from the last milestone to `to` counts (the cap); one that ends at or below `from` does not.
function M.gaps(list, from, to)
	local levels, seen = {}, {}
	for _, e in ipairs(list or {}) do
		if e.level <= to and not seen[e.level] then
			seen[e.level] = true
			levels[#levels + 1] = e.level
		end
	end
	table.sort(levels)
	local out, best = {}, {from = from, to = from, gap = 0}
	local function take(a, b)
		if b > from and b - a > 0 then
			local g = {from = a, to = b, gap = b - a}
			out[#out + 1] = g
			if g.gap > best.gap then
				best = g
			end
		end
	end
	for i = 2, #levels do
		take(levels[i - 1], levels[i])
	end
	if #levels > 0 and levels[#levels] < to then
		take(levels[#levels], to)
	end
	return out, best
end

-- the milestones of `list` inside [from, to] (a count for the model view)
function M.count(list, from, to)
	local n = 0
	for _, e in ipairs(list or {}) do
		if e.level >= from and e.level <= to then
			n = n + 1
		end
	end
	return n
end

-- the problems of the rule (strings, empty when sound). classes: {[name] = list of M.list}
function M.problems(cfg, classes)
	local out, names = {}, {}
	for name in pairs(classes) do
		names[#names + 1] = name
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local gaps = M.gaps(classes[name], cfg.from, cfg.to)
		for _, g in ipairs(gaps) do
			if g.gap > cfg.limit then
				out[#out + 1] = string.format("spell milestones: %s goes %d levels without one (%d to %d), the limit is %d "
					.. "(spell_milestones_config.lua)", name, g.gap, g.from, g.to, cfg.limit)
			end
		end
	end
	return out
end

-- the milestones at the first level above `level` (nil when none is left): {level, entries}
function M.nextAfter(list, level)
	level = num(level, 0)
	local at, entries = nil, {}
	for _, e in ipairs(list or {}) do
		if e.level > level then
			if at == nil then
				at = e.level
			end
			if e.level ~= at then
				break
			end
			entries[#entries + 1] = e
		end
	end
	if not at then
		return nil
	end
	return {level = at, entries = entries}
end

-- the milestones a level-up from `old` to `new` reaches (old < level <= new), only the kinds of `kinds` (nil: all)
function M.reached(list, old, new, kinds)
	old, new = num(old, 0), num(new, 0)
	local out = {}
	for _, e in ipairs(list or {}) do
		if e.level > old and e.level <= new and (not kinds or kinds[e.kind]) then
			out[#out + 1] = e
		end
	end
	return out
end

-- the wire form of the gates and the next milestone for the client (opcode 168 state field `ms`): small, no spell list
--   {f1 = add, f2 = {{below, level}, ...}, aw = {{below, level}, ...}, sl = {slot levels}, nx = {l, k, n, s} | nil}
-- below 0 means "no below" (the last row)
function M.wire(cfg, nxt)
	local function rows(list)
		local out = {}
		for _, r in ipairs(list or {}) do
			out[#out + 1] = {r.below or 0, r.level}
		end
		return out
	end
	local w = {f1 = num(cfg.formI and cfg.formI.add, 0), f2 = rows(cfg.formII), aw = rows(cfg.awaken), sl = cfg.slots or {}}
	if nxt and nxt.entries and nxt.entries[1] then
		local e = nxt.entries[1]
		w.nx = {l = nxt.level, k = e.kind, n = e.name, s = e.slot, c = #nxt.entries}
	end
	return w
end

return M
