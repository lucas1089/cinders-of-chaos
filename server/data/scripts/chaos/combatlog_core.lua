-- DPS meter and combat log, pure logic (no engine calls): sources (what a hit is attributed to), the per-character
-- buffer that sums hits between two ticks, fight segmentation (a fight starts with the first damage dealt or taken and
-- ends idleMs after the last), the last fights and the session total, bounded row tables and the compact views sent to
-- the client. Used by combatlog.lua; tested (and benchmarked) by server/tests/combatlog_test.lua.
-- Lua 5.1 / LuaJIT and 5.3 compatible.
--
-- A source: {k = key ("<kind>:<name>"), t = kind, n = name, i = icon}. Kinds:
--   dealt and healing  s spell (icon: its words), r rune (icon: the rune's client item id), w weapon attack,
--                      d damage over time / regeneration, p proc (supports, keystones, item powers ...),
--                      x reflect / thorns, m summon / minion / pet, i item use (potions), o other,
--                      k keystone effect: a note of a keystone that changed a hit (a factor, a block) or fired without
--                      a hit of its own. Its total is how much it changed (CL.note); it is already inside the other
--                      rows, so a k row never adds to the tab's total, the elements or the targets and never starts a fight
--   taken              c creature (monster), u player, e environment (no attacker)
-- A segment (the session or a fight): {id ("s" or the fight serial), label, start, last (ms), dur (ms, the session:
-- the sum of its fights), boss (name), tabs = {damage dealt, healing done, damage taken, healing received},
-- targets = {[name] = damage}, nTargets}
-- A tab: {total, over (overhealing), rows = {[key] = row}, n, el = {[element] = amount}}
-- A row: {src, total, hits, crits, max, over}

ChaosCombatLog = ChaosCombatLog or {}
local CL = ChaosCombatLog
local floor, mmax = math.floor, math.max

CL.DMG, CL.HEAL, CL.TAKEN, CL.RECV = 1, 2, 3, 4
local DMG, HEAL, TAKEN, RECV = 1, 2, 3, 4
local NTABS = 4
-- CombatOrigin of the engine (enums.h; ORIGIN_WAND has no Lua constant in the base engine)
CL.ORIGIN = CL.ORIGIN or {NONE = 0, CONDITION = 1, SPELL = 2, MELEE = 3, RANGED = 4, WAND = 5}

local DEFAULTS = {idleMs = 6000, minFightMs = 1000, keepFights = 10, maxRows = 40, maxRowsSent = 25, maxTargets = 16,
	maxSourceCache = 4000, maxNotesSent = 10}
CL.cfg = CL.cfg or DEFAULTS

function CL.configure(cfg)
	local c = {}
	for k, v in pairs(DEFAULTS) do
		c[k] = v
	end
	for k, v in pairs(cfg or {}) do
		c[k] = v
	end
	CL.cfg = c
	return c
end

-- ---------------------------------------------------------------- sources
CL.cache = CL.cache or {}
CL.cacheSize = CL.cacheSize or 0

function CL.source(kind, name, icon)
	local byKind = CL.cache[kind]
	if not byKind then
		byKind = {}
		CL.cache[kind] = byKind
	end
	local s = byKind[name]
	if s then
		return s
	end
	if CL.cacheSize >= CL.cfg.maxSourceCache then
		-- rows key on s.k, so a new table for the same source still lands in the same row
		CL.cache, CL.cacheSize = {}, 0
		byKind = {}
		CL.cache[kind] = byKind
	end
	s = {k = kind .. ":" .. name, t = kind, n = name, i = icon or ""}
	byKind[name] = s
	CL.cacheSize = CL.cacheSize + 1
	return s
end

CL.WEAPONS = {
	sword = {"Sword attacks", "sword"}, axe = {"Axe attacks", "axe"}, club = {"Club attacks", "club"},
	fist = {"Fist attacks", "fist"}, distance = {"Distance attacks", "distance"}, wand = {"Wand attacks", "wand"},
}
-- damage over time by element (the condition that ticks): name and icon (the buff bar's own icons)
CL.DOTS = {
	physical = {"Bleeding", "bleeding"}, fire = {"Burning", "burning"}, earth = {"Poison", "poison"},
	energy = {"Electrified", "energy"}, ice = {"Freezing", "freezing"}, holy = {"Dazzled", "dazzled"},
	death = {"Cursed", "cursed"}, drown = {"Drowning", "drowning"},
}

function CL.weaponSource(weapon)
	local d = CL.WEAPONS[weapon] or CL.WEAPONS.fist
	return CL.source("w", d[1], d[2])
end

function CL.dotSource(element)
	local d = CL.DOTS[element]
	if not d then
		return CL.source("d", "Damage over time", "dot")
	end
	return CL.source("d", d[1], d[2])
end

function CL.otherSource(tab)
	if tab == HEAL or tab == RECV then
		return CL.source("o", "Other healing", "other")
	end
	return CL.source("o", "Other", "other")
end

-- a spell or rune of the spells.xml index (CL.parseSpells); runeCid = the rune's client item id
function CL.castSource(entry, runeCid)
	if entry.rune then
		return CL.source("r", entry.name, runeCid or 0)
	end
	return CL.source("s", entry.name, entry.words or "")
end

-- a proc label of the config ({name, kind, icon, helper}) -> {src, helper}; other = true: "Other" / "Other healing"
function CL.procSource(def)
	return {src = CL.source(def.kind or "p", def.name, def.icon or "other"), helper = def.helper and true or false,
		other = def.other and true or false}
end

function CL.takenSource(kind, name)
	if not name or name == "" then
		return CL.source("e", "Environment", "env")
	end
	return CL.source(kind == "u" and "u" or "c", name, kind == "u" and "player" or "monster")
end

-- What a hit dealt or healed by a character is attributed to. h = {origin, el (element name), weapon (sword, axe,
-- club, fist, distance, wand), cast (source of the spell / rune running now), proc ({src, helper} of the script
-- that called doTargetCombat), summon (name, when a summon of the character hit)}. Order: a proc (unless it is a
-- helper library called by a spell), the summon, the cast, then the origin of the hit.
function CL.classify(tab, h)
	local proc = h.proc
	if proc and not (proc.helper and h.cast) then
		if proc.other then
			return CL.otherSource(tab)
		end
		return proc.src
	end
	if h.summon then
		return CL.source("m", h.summon, "summon")
	end
	if h.cast then
		return h.cast
	end
	local O = CL.ORIGIN
	local origin = h.origin
	if tab == HEAL or tab == RECV then
		if origin == O.CONDITION then
			return CL.source("d", "Regeneration", "regen")
		end
		return CL.otherSource(HEAL)
	end
	if origin == O.CONDITION then
		return CL.dotSource(h.el)
	elseif origin == O.MELEE then
		return CL.weaponSource(h.weapon == "distance" and "fist" or h.weapon or "fist")
	elseif origin == O.RANGED then
		return CL.weaponSource("distance")
	elseif origin == O.WAND then
		return CL.weaponSource("wand")
	end
	return CL.otherSource(DMG)
end

-- ---------------------------------------------------------------- spells.xml
local ENTITIES = {amp = "&", apos = "'", quot = "\"", lt = "<", gt = ">"}

-- {byName = {[lower name] = entry}, byId = {[spell id] = entry}}; entry = {name, words, id, rune = item id or nil}.
-- byId prefers the instant spell of an id (the supports' cast context carries instant spell ids); byName prefers the
-- rune of a name (the spell that conjures a rune is often called like it).
function CL.parseSpells(text)
	local out = {byName = {}, byId = {}, count = 0}
	if type(text) ~= "string" then
		return out
	end
	text = text:gsub("<!%-%-.-%-%->", "")
	for tag, attrText in text:gmatch("<(%a+)(%s[^>]-)/?>") do
		tag = tag:lower()
		if tag == "instant" or tag == "rune" or tag == "conjure" then
			local a = {}
			for k, v in attrText:gmatch("([%w_]+)%s*=%s*\"([^\"]*)\"") do
				a[k:lower()] = (v:gsub("&(%a+);", function(e) return ENTITIES[e] or ("&" .. e .. ";") end))
			end
			if a.name and a.name ~= "" then
				local e = {name = a.name, words = a.words, id = tonumber(a.spellid),
					rune = tag == "rune" and tonumber(a.id) or nil}
				-- a conjure spell may carry its rune's name: the rune keeps it (the cast that deals damage)
				local key = a.name:lower()
				if tag == "rune" or not out.byName[key] then
					out.byName[key] = e
				end
				if e.id and (tag == "instant" or not out.byId[e.id]) then
					out.byId[e.id] = e
				end
				out.count = out.count + 1
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- actors and segments
local function newTab()
	return {total = 0, over = 0, rows = {}, n = 0, el = {}}
end

local function newSeg(id, label, now)
	return {id = id, label = label, start = now, last = now, dur = 0, tabs = {newTab(), newTab(), newTab(), newTab()},
		targets = {}, nTargets = 0}
end
CL.newSeg = newSeg

-- one per character: the session, the current fight, the finished fights (newest first) and the hit buffer
function CL.newActor(now)
	return {session = newSeg("s", "Session", now), fight = nil, fights = {}, serial = 0, last = 0, ver = 0,
		sessionOn = true, buf = {{}, {}, {}, {}}, list = {}, nlist = 0, keys = 0, bufEl = {{}, {}, {}, {}}, bufTargets = {},
		bufBoss = nil}
end

local function liveDur(actor, f)
	return mmax(CL.cfg.minFightMs, actor.last - f.start)
end

function CL.startFight(actor, now)
	actor.serial = actor.serial + 1
	actor.fight = newSeg(actor.serial, nil, now)
	actor.ver = actor.ver + 1
	return actor.fight
end

local function mergeRow(tab, e)
	local key = e.src.k
	local row = tab.rows[key]
	local memo = e.src.t == "k"
	if not row then
		if tab.n >= CL.cfg.maxRows then
			if memo then
				return -- a note has no "Other" row: the table is full, the note is dropped
			end
			local o = CL.otherSource(e.tab)
			key = o.k
			row = tab.rows[key]
			if not row then
				row = {src = o, total = 0, hits = 0, crits = 0, max = 0, over = 0}
				tab.rows[key] = row
				tab.n = tab.n + 1
			end
		else
			row = {src = e.src, total = 0, hits = 0, crits = 0, max = 0, over = 0}
			tab.rows[key] = row
			tab.n = tab.n + 1
		end
	end
	row.total = row.total + e.total
	row.hits = row.hits + e.hits
	row.crits = row.crits + e.crits
	row.over = row.over + e.over
	if e.max > row.max then
		row.max = e.max
	end
	if not memo then
		tab.total = tab.total + e.total
		tab.over = tab.over + e.over
	end
end

local function addTarget(f, name, amount)
	local t = f.targets
	if t[name] then
		t[name] = t[name] + amount
	elseif f.nTargets < CL.cfg.maxTargets then
		t[name] = amount
		f.nTargets = f.nTargets + 1
	end
end

-- fold the buffer into the current fight and (while it counts) the session; true when something was folded
function CL.flush(actor)
	local n = actor.nlist
	if n == 0 and not actor.bufBoss then
		return false
	end
	local f = actor.fight
	local s = actor.sessionOn ~= false and actor.session or nil
	local list = actor.list
	for i = 1, n do
		local e = list[i]
		if f then
			mergeRow(f.tabs[e.tab], e)
		end
		if s then
			mergeRow(s.tabs[e.tab], e)
		end
		e.total, e.hits, e.crits, e.max, e.over, e.on = 0, 0, 0, 0, 0, false
		list[i] = nil
	end
	actor.nlist = 0
	for tab = 1, NTABS do
		local t = actor.bufEl[tab]
		for el, amount in pairs(t) do
			if f then
				f.tabs[tab].el[el] = (f.tabs[tab].el[el] or 0) + amount
			end
			if s then
				s.tabs[tab].el[el] = (s.tabs[tab].el[el] or 0) + amount
			end
			t[el] = nil
		end
	end
	for name, amount in pairs(actor.bufTargets) do
		if f then
			addTarget(f, name, amount)
		end
		actor.bufTargets[name] = nil
	end
	if actor.bufBoss then
		if f and not f.boss then
			f.boss = actor.bufBoss
		end
		actor.bufBoss = nil
	end
	-- the buffer keeps one entry per source it saw; bounded
	if actor.keys > 3 * CL.cfg.maxRows then
		actor.buf, actor.keys = {{}, {}, {}, {}}, 0
	end
	actor.ver = actor.ver + 1
	return true
end

-- the label of a fight: the boss, else the most damaged target (+ how many others), else the main attacker
function CL.fightLabel(f)
	if f.boss then
		return f.boss
	end
	local best, bestAmount = nil, -1
	for name, amount in pairs(f.targets or {}) do
		if amount > bestAmount or (amount == bestAmount and name < best) then
			best, bestAmount = name, amount
		end
	end
	if best then
		if (f.nTargets or 0) > 1 then
			return best .. " +" .. (f.nTargets - 1)
		end
		return best
	end
	local top
	for _, row in pairs(f.tabs[TAKEN].rows) do
		if not top or row.total > top.total or (row.total == top.total and row.src.n < top.src.n) then
			top = row
		end
	end
	return top and top.src.n or "Fight"
end

function CL.endFight(actor)
	local f = actor.fight
	if not f then
		return nil
	end
	CL.flush(actor)
	f.last = actor.last
	f.dur = liveDur(actor, f)
	f.label = CL.fightLabel(f)
	f.targets = nil -- only needed for the label
	if actor.sessionOn ~= false then
		actor.session.dur = actor.session.dur + f.dur
	end
	table.insert(actor.fights, 1, f)
	for i = #actor.fights, CL.cfg.keepFights + 1, -1 do
		actor.fights[i] = nil
	end
	actor.fight = nil
	actor.ver = actor.ver + 1
	return f
end

-- One hit (or heal) of a character. tab: CL.DMG (dealt), CL.HEAL (healing done), CL.TAKEN (damage taken), CL.RECV
-- (healing received). amount:
-- what counted (damage capped at the target's health, healing at the missing health), over: overhealing, el: element
-- name, target: the name of what was hit (dealt only: names the fight), boss: a boss name when the hit was on (or from)
-- a boss. Damage dealt or taken starts a fight (or a new one after idleMs); healing alone does not, nor damage taken
-- from no attacker (a field, a trap: source kind "e"); both still count in a running fight and the session.
function CL.add(actor, now, tab, src, amount, crit, over, el, target, boss)
	amount, over = amount or 0, over or 0
	local memo = src.t == "k" -- a keystone note: counted as a hit even when it changed nothing measurable
	if amount <= 0 and over <= 0 and not memo then
		return false
	end
	if memo then
		amount, over, crit, el, target, boss = mmax(0, amount), 0, false, nil, nil, nil
	end
	-- damage taken without an attacker (fields, traps) neither starts nor extends a fight
	if not memo and (tab == DMG or (tab == TAKEN and src.t ~= "e")) then
		if actor.fight and now - actor.last > CL.cfg.idleMs then
			CL.endFight(actor)
		end
		if not actor.fight then
			CL.startFight(actor, now)
		end
		actor.last = now
	end
	local b = actor.buf[tab]
	local key = src.k
	local e = b[key]
	if not e then
		e = {tab = tab, src = src, total = 0, hits = 0, crits = 0, max = 0, over = 0, on = false}
		b[key] = e
		actor.keys = actor.keys + 1
	end
	if not e.on then
		e.on = true
		local n = actor.nlist + 1
		actor.nlist = n
		actor.list[n] = e
	end
	e.total = e.total + amount
	e.hits = e.hits + 1
	if crit then
		e.crits = e.crits + 1
	end
	if amount > e.max then
		e.max = amount
	end
	e.over = e.over + over
	if el then
		local t = actor.bufEl[tab]
		t[el] = (t[el] or 0) + amount
	end
	if target and tab == DMG then
		actor.bufTargets[target] = (actor.bufTargets[target] or 0) + amount
	end
	if boss then
		actor.bufBoss = boss
	end
	return true
end

-- once per tick: fold the buffer, end a fight that went quiet. True when something changed.
function CL.tick(actor, now)
	local changed = CL.flush(actor)
	if actor.fight and now - actor.last > CL.cfg.idleMs then
		CL.endFight(actor)
		changed = true
	end
	return changed
end

-- the session starts over (the hunt session was reset); fights stay
function CL.resetSession(actor, now)
	CL.flush(actor)
	actor.session = newSeg("s", "Session", now)
	actor.ver = actor.ver + 1
end

-- everything starts over: session, fights, the buffer
function CL.reset(actor, now)
	actor.session = newSeg("s", "Session", now)
	actor.fight, actor.fights = nil, {}
	actor.buf, actor.list, actor.nlist, actor.keys = {{}, {}, {}, {}}, {}, 0, 0
	actor.bufEl, actor.bufTargets, actor.bufBoss = {{}, {}, {}, {}}, {}, nil
	actor.ver = actor.ver + 1
end

-- true while nothing is pending or running (the tick can skip the character)
function CL.idle(actor)
	return actor.nlist == 0 and not actor.fight and not actor.bufBoss
end

-- ---------------------------------------------------------------- views
-- "s" = the session, "c" = the current fight or else the last one, a number = that fight
function CL.find(actor, id)
	if id == "s" then
		return actor.session
	end
	if id == nil or id == "c" then
		return actor.fight or actor.fights[1]
	end
	id = tonumber(id)
	if actor.fight and actor.fight.id == id then
		return actor.fight
	end
	for _, f in ipairs(actor.fights) do
		if f.id == id then
			return f
		end
	end
	return nil
end

function CL.duration(actor, seg)
	if seg == actor.session then
		local d = seg.dur
		if actor.fight and actor.sessionOn ~= false then
			d = d + liveDur(actor, actor.fight)
		end
		return d
	elseif seg == actor.fight then
		return liveDur(actor, seg)
	end
	return seg.dur
end

function CL.perSecond(value, ms)
	if not ms or ms <= 0 then
		return 0
	end
	return floor(value * 1000 / ms)
end

local function byTotal(a, b)
	if a.total ~= b.total then
		return a.total > b.total
	end
	return a.src.k < b.src.k
end

-- the rows of a tab, largest first, at most `limit`; keystone notes (kind k) come after the real sources, at most
-- CL.cfg.maxNotesSent of them, so a note never pushes a source out of the rows sent
function CL.sortedRows(tab, limit)
	local rows, notes = {}, {}
	for _, row in pairs(tab.rows) do
		if row.src.t == "k" then
			notes[#notes + 1] = row
		else
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, byTotal)
	if limit then
		for i = #rows, limit + 1, -1 do
			rows[i] = nil
		end
	end
	if #notes > 0 then
		table.sort(notes, byTotal)
		for i = 1, math.min(#notes, CL.cfg.maxNotesSent or 10) do
			rows[#rows + 1] = notes[i]
		end
	end
	return rows
end

local function tabView(tab, limit)
	local out = {tot = tab.total, ov = tab.over, el = {}, r = {}}
	for el, amount in pairs(tab.el) do
		out.el[el] = amount
	end
	for i, row in ipairs(CL.sortedRows(tab, limit)) do
		local s = row.src
		out.r[i] = {s.k, s.t, s.n, s.i, row.total, row.hits, row.crits, row.max, row.over}
	end
	return out
end

-- one segment for the client: {id, label, dur (ms), live, boss, t = {damage, healing, taken, received}} with tab views
-- {tot, ov, el = {[element] = amount}, r = [[key, kind, name, icon, total, hits, crits, max, over]]}
function CL.view(actor, seg)
	local limit = CL.cfg.maxRowsSent
	local label = seg.label
	if not label then
		label = CL.fightLabel(seg)
	end
	return {id = seg.id, label = label, dur = CL.duration(actor, seg), live = seg == actor.fight and 1 or 0,
		boss = seg.boss and 1 or 0,
		t = {tabView(seg.tabs[DMG], limit), tabView(seg.tabs[HEAL], limit), tabView(seg.tabs[TAKEN], limit),
			tabView(seg.tabs[RECV], limit)}}
end

-- the segment list of the dropdown: session, the current fight, the finished fights
-- [[id, label, dur, damage, healing, taken, live, boss, received]]
function CL.segments(actor)
	local out = {}
	local function add(seg)
		local t = seg.tabs
		out[#out + 1] = {seg.id, seg.label or CL.fightLabel(seg), CL.duration(actor, seg), t[DMG].total, t[HEAL].total,
			t[TAKEN].total, seg == actor.fight and 1 or 0, seg.boss and 1 or 0, t[RECV].total}
	end
	add(actor.session)
	if actor.fight then
		add(actor.fight)
	end
	for _, f in ipairs(actor.fights) do
		add(f)
	end
	return out
end

-- the whole state for the client: the list, the chosen segment ("c" follows the fights) and its view
function CL.state(actor, segId)
	local id = segId
	if id ~= "s" and id ~= "c" then
		id = tonumber(id) or "c"
	end
	local seg = CL.find(actor, id)
	if not seg and id ~= "c" then
		id = "c"
		seg = CL.find(actor, id)
	end
	return {sel = id, segs = CL.segments(actor), v = seg and CL.view(actor, seg) or nil,
		live = actor.fight and 1 or 0, share = actor.share and 1 or 0}
end

-- the totals a party member shows (no breakdown): the current (or last) fight and the session
-- {fd, fh, ft, fdur, live, sd, sh, st, sdur}
function CL.brief(actor)
	local f = actor.fight or actor.fights[1]
	local s = actor.session
	local out = {fd = 0, fh = 0, ft = 0, fdur = 0, live = actor.fight and 1 or 0,
		sd = s.tabs[DMG].total, sh = s.tabs[HEAL].total, st = s.tabs[TAKEN].total, sdur = CL.duration(actor, s)}
	if f then
		out.fd, out.fh, out.ft, out.fdur = f.tabs[DMG].total, f.tabs[HEAL].total, f.tabs[TAKEN].total,
			CL.duration(actor, f)
	end
	return out
end

-- characters kept after logout for keepMs; returns how many were dropped
function CL.sweep(actors, now, keepMs)
	local dropped = 0
	for key, a in pairs(actors) do
		if a.offlineAt and now - a.offlineAt > keepMs then
			actors[key] = nil
			dropped = dropped + 1
		end
	end
	return dropped
end

return CL
