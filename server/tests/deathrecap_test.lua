-- Run from the server/ folder: luajit tests/deathrecap_test.lua (or lua5.3; CI runs both)
-- Death recap: the rolling log (ring order, count and age bounds), the recap math (attackers, health / mana damage,
-- element split, killing blow, time window, last hits, "Others"), PvP and monster mix, the payload bound, the
-- experience lost, the history of 5, the SQL, the opcode collision check, and deathrecap.lua against a mocked engine
-- (combat log hook -> death -> row -> login -> recap; a mode's defeat; ghost staff hidden; only own rows).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/deathrecap_config.lua")
dofile("data/scripts/chaos/deathrecap_core.lua")
local R = ChaosDeathRecap
R.configure(cfg)

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- a plain JSON encoder (sorted keys), for the size checks and the mocked json.encode
local function encode(v)
	local tv = type(v)
	if tv == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for i = 1, #v do parts[i] = encode(v[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do
			local x = v[k]
			if x == nil then x = v[tonumber(k)] end
			parts[#parts + 1] = encode(k) .. ":" .. encode(x)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif tv == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
	elseif tv == "number" then
		if v == math.floor(v) then return string.format("%d", v) end
		return string.format("%.14g", v)
	elseif tv == "boolean" then
		return tostring(v)
	end
	return "null"
end
local function copy(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, x in pairs(v) do o[k] = copy(x) end
	return o
end

local function hit(name, kind, a, el, opt)
	opt = opt or {}
	return {k = R.key(kind, name, opt.m), n = name, kind = kind, m = opt.m, el = el, a = a, c = opt.c, mp = opt.mp, pv = opt.pv}
end

-- ---------------------------------------------------------------- constants, opcode collision check
eq(ChaosOpcodes.deathRecap, 154, "opcode constant")
eq(Chaos.tables.deathRecaps, "chaos_death_recaps", "table constant")
for _, taken in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	check(taken ~= ChaosOpcodes.deathRecap, "opcode free of " .. taken)
end
for name, v in pairs(ChaosOpcodes) do
	check(name == "deathRecap" or v ~= ChaosOpcodes.deathRecap, "opcode not shared with " .. name)
end
-- 155 and 156 are promised to two other modules
check(ChaosOpcodes.deathRecap ~= 155 and ChaosOpcodes.deathRecap ~= 156, "not 155 / 156")
-- no client module registers 154 (the base client's ExtendedIds are listed above)
do
	local p = io.popen("grep -rlE '(OPCODE|Opcode)[^0-9]{0,12}154\\b' ../client/overlay/modules 2>/dev/null")
	local out = p and p:read("*a") or ""
	if p then p:close() end
	for line in out:gmatch("[^\n]+") do
		check(line:find("game_deathrecap", 1, true) ~= nil, "154 only in game_deathrecap: " .. line)
	end
end
-- no player storages: nothing in the reserved block 7101830 - 7101839 is taken by this system
for name, v in pairs(Chaos.storage) do
	check(not (type(v) == "number" and v >= 7101830 and v <= 7101839 and name:lower():find("death")), "no storage used: " .. name)
end

-- ---------------------------------------------------------------- the rolling log
R.configure({maxHits = 5, windowMs = 10000})
local log = R.newLog()
for i = 1, 8 do
	R.record(log, i * 100, hit("Rat", "c", i, "physical"))
end
eq(log.n, 5, "ring bounded by maxHits")
local hs = R.hits(log)
eq(#hs, 5, "five hits")
eq(hs[1].a, 4, "oldest kept is hit 4")
eq(hs[5].a, 8, "newest last")
for i = 2, 5 do check(hs[i].t > hs[i - 1].t, "oldest first " .. i) end
-- age: prune drops hits older than the window
R.record(log, 20000, hit("Rat", "c", 9, "physical"))
eq(R.prune(log, 20500), false, "prune keeps the recent hit")
eq(log.n, 1, "old hits pruned")
eq(R.hits(log)[1].a, 9, "the recent one stays")
eq(R.prune(log, 40000), true, "an empty log can be forgotten")
eq(log.n, 0, "all pruned")
-- after a prune the ring still works
for i = 1, 7 do R.record(log, 50000 + i, hit("Bat", "c", i, "physical")) end
eq(log.n, 5, "ring after prune bounded")
eq(R.hits(log)[1].a, 3, "ring after prune oldest")
-- a lowered cap (a /reload) starts the ring over
log = R.newLog()
for i = 1, 5 do R.record(log, i, hit("Rat", "c", i, "physical")) end
R.configure({maxHits = 3, windowMs = 10000})
R.record(log, 6, hit("Rat", "c", 6, "physical"))
check(log.n <= 3, "lowered cap bounds the ring")
-- looks bounded
R.configure({maxAttackers = 2})
log = R.newLog()
local looks = 0
for i = 1, 50 do
	local k = R.key("c", "M" .. i)
	if R.wantLook(log, k) then
		R.setLook(log, k, {type = i})
		looks = looks + 1
	end
end
eq(looks, 8, "looks bounded (2 x maxAttackers + 4)")
check(not R.wantLook(log, R.key("c", "M1")), "a known look is not asked again")

-- look conversion
local lk = R.look({lookType = 128, lookHead = 78, lookBody = 69, lookLegs = 58, lookFeet = 76, lookAddons = 3})
eq(lk.type, 128, "look type")
eq(lk.addons, 3, "look addons")
local item = R.look({lookType = 0, lookTypeEx = 2160})
eq(item.auxType, 2160, "item look")
eq(item.type, 0, "item look type 0")
eq(R.look({lookType = 0}), nil, "no look")
eq(R.look({lookType = 99999}), nil, "bad look type")
eq(R.look(nil), nil, "nil look")

-- ---------------------------------------------------------------- recap math
R.configure(cfg)
log = R.newLog()
local t0 = 100000
-- 18 s before the death: outside a 15 s window when we lower it below; first hits
R.record(log, t0 + 0, hit("Dragon", "c", 300, "fire"))
R.record(log, t0 + 1000, hit("Dragon", "c", 200, "physical", {c = true}))
R.record(log, t0 + 2000, hit("Varek", "u", 150, "energy"))
R.record(log, t0 + 2500, hit("Varek", "u", 80, "energy", {mp = true}))
R.record(log, t0 + 3000, hit("Fire Elemental", "c", 60, "fire", {m = "Varek", pv = true}))
R.record(log, t0 + 3500, hit("Environment", "e", 20, "fire"))
R.record(log, t0 + 4000, hit("Varek", "u", 40, "manadrain", {mp = true}))
R.record(log, t0 + 4200, hit("Dragon", "c", 250, "fire"))
R.setLook(log, R.key("c", "Dragon"), {type = 34})
local death = t0 + 4200
local rc = R.build(log, death, {at = 1700000000, real = true, level = 120, exp = 3000000, mode = nil})
eq(rc.v, 1, "version")
eq(rc.real, 1, "a real death")
eq(rc.tot, 1100, "total damage")
eq(rc.mp, 120, "mana damage")
eq(rc.hp, 980, "health damage")
eq(rc.el.fire, 630, "fire total")
eq(rc.el.energy, 230, "energy total")
eq(rc.el.manadrain, 40, "mana drain total")
eq(rc.el.physical, 200, "physical total")
eq(rc.nh, 8, "hits shown")
eq(rc.dur, 4200, "time window: first hit to the death")
eq(rc.win, cfg.windowMs, "window sent")
eq(rc.pvp, 1, "PvP: a player took part")
eq(#rc.att, 4, "four attackers")
eq(rc.att[1].n, "Dragon", "most damage first")
eq(rc.att[1].tot, 750, "dragon total")
eq(rc.att[1].hp, 750, "dragon health")
eq(rc.att[1].h, 3, "dragon hits")
eq(rc.att[1].c, 1, "dragon crits")
eq(rc.att[1].x, 300, "dragon max")
eq(rc.att[1].el.fire, 550, "dragon fire")
eq(rc.att[1].el.physical, 200, "dragon physical")
eq(rc.att[1].look and rc.att[1].look.type, 34, "dragon look")
eq(rc.att[1].kind, "c", "dragon kind")
eq(rc.att[2].n, "Varek", "player second")
eq(rc.att[2].tot, 270, "player total")
eq(rc.att[2].hp, 150, "player health")
eq(rc.att[2].mp, 120, "player mana (shield + drain)")
eq(rc.att[2].kind, "u", "player kind")
eq(rc.att[3].n, "Fire Elemental", "summon")
eq(rc.att[3].m, "Varek", "summon master")
eq(rc.att[4].kind, "e", "environment")
-- the totals of the rows add up
local sum = 0
for _, a in ipairs(rc.att) do sum = sum + a.tot end
eq(sum, rc.tot, "rows add up to the total")
-- the killing blow: the last health hit (the mana drain at +4000 is not it)
eq(rc.kb.n, "Dragon", "killing blow attacker")
eq(rc.kb.a, 250, "killing blow amount")
eq(rc.kb.el, "fire", "killing blow element")
-- a mana hit last: the killing blow is still the last health hit
R.record(log, death + 10, hit("Varek", "u", 33, "energy", {mp = true}))
eq(R.build(log, death + 10, {}).kb.n, "Dragon", "a mana hit never kills")
-- the engine's killer when the log missed the lethal hit
local gap = R.build(log, death + 3000, {killer = {n = "Dragon", kind = "c"}})
eq(gap.kb.n, "Dragon", "killer named after a gap")
eq(gap.kb.a, nil, "no amount: the lethal hit was not logged")
local other = R.build(log, death, {killer = {n = "Demon", kind = "c"}})
eq(other.kb.n, "Demon", "another killer than the last logged hit")
eq(other.kb.a, nil, "another killer: no amount")
local same = R.build(log, death, {killer = {n = "Dragon", kind = "c"}})
eq(same.kb.a, 250, "the same killer right after its hit: the logged hit")
-- the timeline
local rc2 = R.build(log, death, {})
eq(#rc2.last, cfg.lastHits, "timeline bounded")
eq(rc2.last[#rc2.last].dt, 0, "the last hit is the killing blow at 0 ms")
eq(rc2.last[#rc2.last].a, 250, "timeline last amount")
-- a monster-only death is no PvP; a player's summon alone is
local mlog = R.newLog()
R.record(mlog, 1, hit("Rat", "c", 5, "physical"))
eq(R.build(mlog, 1, {}).pvp, nil, "monsters only: no PvP")
R.record(mlog, 2, hit("Wolf", "c", 5, "physical", {m = "Varek", pv = true}))
eq(R.build(mlog, 2, {}).pvp, 1, "a player's summon: PvP")
-- the window: hits older than windowMs before the death are left out
R.configure({windowMs = 2000})
local wrc = R.build(log, death, {})
eq(wrc.tot, 80 + 60 + 20 + 40 + 250, "only the last 2 s")
eq(wrc.dur, 1700, "window duration from the first hit inside")
R.configure(cfg)
-- no hit: the engine's killer
local empty = R.build(R.newLog(), 5, {killer = {n = "Demon", kind = "c"}})
eq(empty.kb.n, "Demon", "killer without hits")
eq(empty.tot, 0, "nothing shown")
eq(#empty.att, 0, "no rows")
eq(R.build(R.newLog(), 5, {}).kb.n, "Unknown", "no killer at all")
eq(R.build(R.newLog(), 5, {killer = {n = "Varek", kind = "u"}}).pvp, 1, "a player killer without hits: PvP")

-- "Others": more attackers than maxAttackers
R.configure({maxAttackers = 3})
local many = R.newLog()
for i = 1, 6 do R.record(many, i, hit("Mob" .. i, "c", i * 10, "physical")) end
local mr = R.build(many, 6, {})
eq(#mr.att, 3, "two rows and Others")
eq(mr.att[1].n, "Mob6", "biggest first")
eq(mr.att[3].n, "Others", "Others row")
eq(mr.att[3].tot, 10 + 20 + 30 + 40, "Others sums the rest")
eq(mr.att[3].h, 4, "Others hits")
local exact = R.newLog()
for i = 1, 3 do R.record(exact, i, hit("Mob" .. i, "c", i, "physical")) end
eq(#R.build(exact, 3, {}).att, 3, "exactly maxAttackers: no Others")
eq(R.build(exact, 3, {}).att[3].n, "Mob1", "exactly maxAttackers: all named")
R.configure(cfg)

-- ---------------------------------------------------------------- payload bound
local big = R.newLog()
R.configure({maxHits = 60, maxAttackers = 8, maxRecapBytes = cfg.maxRecapBytes})
for i = 1, 60 do
	local name = string.rep("N", 40 - #tostring(i)) .. i
	R.record(big, i, hit(name, i % 3 == 0 and "u" or "c", 100000 + i, ({"fire", "ice", "earth", "energy", "holy", "death",
		"physical", "drown", "lifedrain", "manadrain"})[i % 10 + 1], {c = i % 2 == 0, m = i % 5 == 0 and string.rep("M", 40) or nil}))
	R.setLook(big, R.key(i % 3 == 0 and "u" or "c", name, i % 5 == 0 and string.rep("M", 40) or nil),
		{type = 1000 + i, head = 1, body = 2, legs = 3, feet = 4, addons = 3})
end
local br = R.build(big, 60, {at = 1700000000, level = 1000, exp = 99999999999, mode = "Arena", mk = "arena",
	killer = {n = "x", kind = "c"}})
local js = encode(br)
check(#js <= cfg.maxRecapBytes, "one recap fits maxRecapBytes (" .. #js .. ")")
check(R.size(br) >= #js, "the size estimate is never under the JSON (" .. R.size(br) .. " vs " .. #js .. ")")
check(#br.att <= 8, "rows bounded")
-- the whole history message: 5 summaries and the newest recap in one opcode message
local hist = {}
for i = 1, 5 do R.pushHistory(hist, R.summary(1000000 + i, br), cfg.keep) end
local msg = encode({action = "history", data = {list = hist, sel = 1000005, recap = br}})
check(#msg <= 8192, "history fits one extended opcode message (" .. #msg .. ")")
-- an absurd recap is cut further
local tiny = R.fit(copy(br), 600)
check(R.size(tiny) <= 1200, "fit cuts down (" .. R.size(tiny) .. ")")
check(#tiny.att >= 1, "fit keeps a row")
local ttot = 0
for _, a in ipairs(tiny.att) do ttot = ttot + a.tot end
eq(ttot, br.tot, "fit keeps the totals (merged into Others)")
R.configure(cfg)

-- ---------------------------------------------------------------- experience lost, history of 5, SQL
local f = R.finalize({real = 1, lvl = 120, exp = 3000000}, 119, 2850000)
eq(f.xl, 150000, "experience lost")
eq(f.ll, 1, "levels lost")
local f2 = R.finalize({real = 1, lvl = 120, exp = 3000000, xl = 7, ll = 0}, 1, 1)
eq(f2.xl, 7, "finalize once")
local f3 = R.finalize({real = 0, lvl = 50})
eq(f3.xl, 0, "a mode defeat loses nothing")
eq(R.finalize({real = 1, lvl = 50, exp = 10}, 51, 20).xl, 0, "never negative")
local list = {}
for i = 1, 7 do R.pushHistory(list, {id = i}, 5) end
eq(#list, 5, "history keeps 5")
eq(list[1].id, 7, "newest first")
eq(list[5].id, 3, "oldest kept")
local s = R.summary(9, rc)
eq(s.id, 9, "summary id")
eq(s.k, "Dragon", "summary killer")
eq(s.lvl, 120, "summary level")
check(R.trimSql("chaos_death_recaps", 42, 5):find("LIMIT 5", 1, true) ~= nil, "trim keeps 5")
check(R.trimSql("chaos_death_recaps", 42, 5):find("`player_id` = 42", 1, true) ~= nil, "trim per character")
check(R.createSql("chaos_death_recaps"):find("CREATE TABLE IF NOT EXISTS `chaos_death_recaps`", 1, true) ~= nil, "create")
check(R.hidden("arena", {"arena"}) and not R.hidden("arena", {}) and not R.hidden(nil, {"arena"}), "hidden modes")
-- the SQL file and the startup create agree on the columns
do
	local fh = assert(io.open("sql/chaos_death_recaps.sql", "r"))
	local sql = fh:read("*a")
	fh:close()
	for _, col in ipairs({"id", "player_id", "at", "seen", "data"}) do
		check(sql:find("`" .. col .. "`", 1, true) ~= nil and R.createSql("t"):find("`" .. col .. "`", 1, true) ~= nil,
			"column " .. col)
	end
end
-- combatlog.lua feeds the hook (health, mana shield, mana drain)
do
	local fh = assert(io.open("data/scripts/chaos/combatlog.lua", "r"))
	local src = fh:read("*a")
	fh:close()
	check(src:find("CL.takenHook", 1, true) ~= nil, "combat log calls the hook")
	check(src:find("dealt(creature, attacker, total, pt, origin, false, nowMs(), true)", 1, true) ~= nil, "mana shield marked")
	check(src:find('"manadrain", false, nowMs(), true)', 1, true) ~= nil, "mana drain fed")
end

-- ---------------------------------------------------------------- deathrecap.lua against a mocked engine
local registry = {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type(t) self.t = t end
	function o:register() registry[name] = self end
	return o
end
function GlobalEvent(name)
	local o = {}
	function o:type() end
	function o:register() registry[name] = self end
	return o
end
local queue = {}
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}} return #queue end
local function runEvents()
	while #queue > 0 do
		local e = table.remove(queue, 1)
		e.fn((table.unpack or unpack)(e.args))
	end
end
local clock = 5000000
os.mtime = function() return clock end
-- json: real encoding; decode returns what was encoded
local encoded = {}
json = {encode = function(t) local s = encode(t) encoded[s] = copy(t) return s end,
	decode = function(s) return copy(encoded[s]) end}
-- the database: one table, queries parsed back
local strings, rows, nextId, queries = {}, {}, 0, {}
db = {}
function db.escapeString(s) strings[#strings + 1] = s return "@" .. #strings end
function db.query(q)
	queries[#queries + 1] = q
	if q:find("^CREATE TABLE") then return true end
	local guid, at, seen, sid = q:match("^INSERT INTO `chaos_death_recaps` %(.-%) VALUES %((%d+), (%d+), (%d+), @(%d+)%)$")
	if guid then
		nextId = nextId + 1
		rows[#rows + 1] = {id = nextId, player_id = tonumber(guid), at = tonumber(at), seen = tonumber(seen),
			data = strings[tonumber(sid)]}
		return true
	end
	local g2, keep = q:match("^DELETE FROM `chaos_death_recaps` WHERE `player_id` = (%d+) .- LIMIT (%d+)%) AS `k`%)$")
	if g2 then
		g2, keep = tonumber(g2), tonumber(keep)
		local mine = {}
		for _, r in ipairs(rows) do if r.player_id == g2 then mine[#mine + 1] = r.id end end
		table.sort(mine, function(a, b) return a > b end)
		local drop = {}
		for i = keep + 1, #mine do drop[mine[i]] = true end
		local out = {}
		for _, r in ipairs(rows) do if not drop[r.id] then out[#out + 1] = r end end
		rows = out
		return true
	end
	local did, id, pg = q:match("^UPDATE `chaos_death_recaps` SET `seen` = 1, `data` = @(%d+) WHERE `id` = (%d+) AND `player_id` = (%d+)$")
	if did then
		for _, r in ipairs(rows) do
			if r.id == tonumber(id) and r.player_id == tonumber(pg) then r.seen, r.data = 1, strings[tonumber(did)] end
		end
		return true
	end
	local id2, pg2 = q:match("^UPDATE `chaos_death_recaps` SET `seen` = 1 WHERE `id` = (%d+) AND `player_id` = (%d+)$")
	if id2 then
		for _, r in ipairs(rows) do
			if r.id == tonumber(id2) and r.player_id == tonumber(pg2) then r.seen = 1 end
		end
		return true
	end
	error("unexpected query " .. q)
end
db.asyncQuery = db.query
local results, nextResult = {}, 0
function db.storeQuery(q)
	queries[#queries + 1] = q
	local guid, limit = q:match("^SELECT .- FROM `chaos_death_recaps` WHERE `player_id` = (%d+) ORDER BY `id` DESC LIMIT (%d+)$")
	assert(guid, "unexpected select " .. q)
	local mine = {}
	for _, r in ipairs(rows) do if r.player_id == tonumber(guid) then mine[#mine + 1] = r end end
	table.sort(mine, function(a, b) return a.id > b.id end)
	while #mine > tonumber(limit) do table.remove(mine) end
	if #mine == 0 then return false end
	nextResult = nextResult + 1
	results[nextResult] = {list = mine, i = 1}
	return nextResult
end
result = {
	getNumber = function(rid, col) local r = results[rid] return r.list[r.i][col] end,
	getString = function(rid, col) local r = results[rid] return r.list[r.i][col] end,
	next = function(rid) local r = results[rid] r.i = r.i + 1 return r.i <= #r.list end,
	free = function(rid) results[rid] = nil end,
}
local creatures = {}
function Player(id) local c = creatures[id] return c and c.player and c or nil end
local function mk(def)
	local c = def
	c.events = {}
	c.sent = {}
	function c:getId() return self.id end
	function c:getGuid() return self.guid end
	function c:getName() return self.name end
	function c:isPlayer() return self.player == true end
	function c:isMonster() return not self.player end
	function c:getMaster() return self.master end
	function c:getLevel() return self.level end
	function c:getExperience() return self.exp end
	function c:getHealth() return self.health end
	function c:isInGhostMode() return self.ghost == true end
	function c:canSeeCreature(o) return not o.ghost or self.staff == true end
	function c:getOutfit() return self.outfit end
	function c:registerEvent(e) self.events[e] = true end
	function c:sendExtendedOpcode(op, s) self.sent[#self.sent + 1] = {op = op, s = s} return true end
	creatures[c.id] = c
	return c
end
-- an instance for the mode defeat
Chaos.registerInstance("arena", {label = "Arena", inside = function(p) return p.inArena == true end})

dofile("data/scripts/chaos/deathrecap.lua")
local E = ChaosDeathRecap
check(registry.ChaosDeathRecapDeath and registry.ChaosDeathRecapPrepare and registry.ChaosDeathRecapLogin and
	registry.ChaosDeathRecapLogout and registry.ChaosDeathRecapExtended and registry.ChaosDeathRecapStartup, "events registered")
eq(ChaosCombatLog.takenHook, E.onTaken, "the combat log hook is set")
-- the login event sorts before the Marches' (its prepare-death runs first; the engine keeps login events by name)
check("ChaosDeathRecapLogin" < "ChaosMarchesLogin", "login order before the Marches")
registry.ChaosDeathRecapStartup.onStartup()
check(queries[1]:find("CREATE TABLE IF NOT EXISTS `chaos_death_recaps`", 1, true) ~= nil, "table created at startup")

local hero = mk({id = 0x10000001, guid = 7, name = "Aldric", player = true, level = 120, exp = 3000000, health = 500,
	outfit = {lookType = 128}})
local foe = mk({id = 0x10000002, guid = 8, name = "Varek", player = true, level = 130, exp = 4000000, health = 900,
	outfit = {lookType = 129, lookHead = 2}})
local gm = mk({id = 0x10000003, guid = 9, name = "Staff Morgan", player = true, ghost = true, level = 1, exp = 0, health = 100})
local dragon = mk({id = 0x40000001, name = "Dragon", outfit = {lookType = 34}})
local wolf = mk({id = 0x40000002, name = "War Wolf", master = foe, outfit = {lookType = 3}})
local ghostPet = mk({id = 0x40000003, name = "Skeleton", master = gm, outfit = {lookType = 33}})

registry.ChaosDeathRecapLogin.onLogin(hero)
check(hero.events.ChaosDeathRecapDeath and hero.events.ChaosDeathRecapPrepare and hero.events.ChaosDeathRecapExtended,
	"events on the player")
runEvents() -- login check: nothing stored yet
eq(#hero.sent, 0, "nothing at the first login")

local hook = ChaosCombatLog.takenHook
local function src(c) return c and {n = c.name, t = c.player and "u" or "c"} or {n = "Environment", t = "e"} end
clock = clock + 1000
hook(hero, dragon, src(dragon), 300, "fire", false, clock)
clock = clock + 500
hook(hero, foe, src(foe), 120, "energy", true, clock)
hook(hero, foe, src(foe), 50, "energy", false, clock, true) -- mana shield
clock = clock + 500
hook(hero, wolf, src(wolf), 40, "physical", false, clock)
hook(hero, gm, src(gm), 70, "death", false, clock)
hook(hero, ghostPet, src(ghostPet), 30, "physical", false, clock)
hook(hero, nil, src(nil), 15, "fire", false, clock)
hook(hero, hero, src(hero), 5, "fire", false, clock)
hook(hero, dragon, src(dragon), 0, "fire", false, clock) -- nothing
clock = clock + 200
hook(hero, dragon, src(dragon), 260, "fire", false, clock)
eq(E.logs[hero.id].n, 9, "nine hits logged")
-- O159: a mana potion (a restore) or a cost the character paid itself is no damage: never "Yourself, mana drain"
hook(hero, hero, src(hero), 1748, "manadrain", false, clock, true)
hook(hero, hero, src(hero), 300, "healing", false, clock)
eq(E.logs[hero.id].n, 9, "own mana drain / restore not logged")

-- the death (onDeath runs before the engine takes the experience)
registry.ChaosDeathRecapDeath.onDeath(hero, nil, dragon, foe)
eq(E.logs[hero.id], nil, "log forgotten after the death")
eq(#rows, 1, "one row stored")
eq(rows[1].seen, 0, "not seen yet")
eq(rows[1].player_id, 7, "row of the victim")
local stored = json.decode(rows[1].data)
eq(stored.real, 1, "a death")
eq(stored.lvl, 120, "level before")
eq(stored.kb.n, "Dragon", "killing blow")
eq(stored.pvp, 1, "PvP mix")
local byName = {}
for _, a in ipairs(stored.att) do byName[a.n] = a end
check(byName.Varek and byName.Varek.mp == 50 and byName.Varek.hp == 120 and byName.Varek.c == 1, "player row: health, mana, crit")
check(byName["War Wolf"] and byName["War Wolf"].m == "Varek", "summon with its master")
check(byName[cfg.hiddenName] ~= nil and byName[cfg.hiddenName].tot == 70, "ghost staff hidden")
check(byName["Staff Morgan"] == nil, "the ghost's name never stored")
check(byName.Skeleton and byName.Skeleton.m == cfg.hiddenName, "a ghost's summon: master hidden")
check(byName.Environment and byName.Environment.kind == "e", "environment row")
check(byName.Aldric and byName.Aldric.kind == "s", "own damage")
check(byName.Dragon and byName.Dragon.look and byName.Dragon.look.type == 34, "monster look")
check(byName[cfg.hiddenName].look == nil, "no look of a hidden attacker")
eq(stored.tot, 300 + 120 + 50 + 40 + 70 + 30 + 15 + 5 + 260, "total")
check(not rows[1].data:find("Staff Morgan", 1, true), "ghost name not in the row")

-- the next login: the experience lost is filled in, the client gets it to open
hero.level, hero.exp, hero.health = 119, 2850000, 500
hero.sent = {}
registry.ChaosDeathRecapLogin.onLogin(hero)
runEvents()
eq(#hero.sent, 1, "recap sent at login")
eq(hero.sent[1].op, 154, "on 154")
local m1 = json.decode(hero.sent[1].s)
eq(m1.action, "recap", "recap action")
eq(m1.data.auto, true, "opens by itself")
eq(m1.data.recap.xl, 150000, "experience lost")
eq(m1.data.recap.ll, 1, "level lost")
eq(rows[1].seen, 1, "seen after the login")
eq(json.decode(rows[1].data).xl, 150000, "stored with the loss")
-- a second login sends nothing
hero.sent = {}
registry.ChaosDeathRecapLogin.onLogin(hero)
runEvents()
eq(#hero.sent, 0, "a seen recap is not sent again")

-- a mode defeat: the arena cancels the death; the recap goes out at once and loses nothing
hero.inArena = true
clock = clock + 60000
hook(hero, foe, src(foe), 400, "energy", false, clock)
eq(registry.ChaosDeathRecapPrepare.onPrepareDeath(hero, foe), true, "prepare never cancels")
eq(registry.ChaosDeathRecapPrepare.onPrepareDeath(hero, foe), true, "a second lethal hit")
hero.health = 1 -- the arena set it
runEvents()
eq(#hero.sent, 1, "defeat recap sent at once")
local m2 = json.decode(hero.sent[1].s)
eq(m2.data.recap.real, 0, "a defeat")
eq(m2.data.recap.mode, "Arena", "the mode")
eq(m2.data.recap.xl, 0, "nothing lost")
eq(m2.data.recap.kb.n, "Varek", "PvP killing blow")
eq(m2.data.recap.tot, 400, "only the hits since the last death")
eq(#rows, 2, "defeat stored")
eq(rows[2].seen, 1, "defeat stored as seen")
-- a real death inside an instance: no defeat recap besides it
hero.sent = {}
hook(hero, foe, src(foe), 999, "energy", false, clock)
registry.ChaosDeathRecapPrepare.onPrepareDeath(hero, foe)
registry.ChaosDeathRecapDeath.onDeath(hero, nil, foe, foe)
runEvents()
eq(#hero.sent, 0, "a real death sends no defeat recap")
eq(#rows, 3, "the death stored once")
eq(json.decode(rows[3].data).mode, "Arena", "the death's mode")
hero.inArena = false
-- no instance: a cancelled hit (Hardcore protection) is no death
hook(hero, dragon, src(dragon), 999, "fire", false, clock)
registry.ChaosDeathRecapPrepare.onPrepareDeath(hero, dragon)
runEvents()
eq(#hero.sent, 0, "outside an instance a cancelled hit is no death")
eq(#rows, 3, "nothing stored")
-- a mode that hides its recaps
Chaos.deathRecapConfig.hideModes = {"arena"}
hero.inArena = true
hook(hero, foe, src(foe), 999, "energy", false, clock)
registry.ChaosDeathRecapPrepare.onPrepareDeath(hero, foe)
runEvents()
eq(#hero.sent, 0, "hidden mode: no recap")
Chaos.deathRecapConfig.hideModes = {}
hero.inArena = false

-- the history keeps 5 per character; another character's rows stay
local foeRows = 0
for i = 1, 2 do
	registry.ChaosDeathRecapDeath.onDeath(foe, nil, dragon, dragon)
	foeRows = foeRows + 1
end
for i = 1, 6 do
	clock = clock + 1000
	hook(hero, dragon, src(dragon), 100 + i, "fire", false, clock)
	registry.ChaosDeathRecapDeath.onDeath(hero, nil, dragon, dragon)
end
local mine, theirs = 0, 0
for _, r in ipairs(rows) do
	if r.player_id == 7 then mine = mine + 1 elseif r.player_id == 8 then theirs = theirs + 1 end
end
eq(mine, 5, "five recaps kept per character")
eq(theirs, foeRows, "the other character's rows kept")

-- the window: open -> history of 5 with the newest recap
hero.sent = {}
registry.ChaosDeathRecapExtended.onExtendedOpcode(hero, 154, json.encode({action = "open", data = {}}))
eq(#hero.sent, 1, "history sent")
local h = json.decode(hero.sent[1].s)
eq(h.action, "history", "history action")
eq(#h.data.list, 5, "five deaths listed")
eq(h.data.sel, h.data.list[1].id, "newest selected")
eq(h.data.recap.kb.a, 106, "newest recap sent")
check(#hero.sent[1].s <= 8192, "history in one message (" .. #hero.sent[1].s .. ")")
-- get an older one
local olderId = h.data.list[3].id
hero.sent = {}
registry.ChaosDeathRecapExtended.onExtendedOpcode(hero, 154, json.encode({action = "get", data = {id = olderId}}))
eq(#hero.sent, 1, "older recap sent")
eq(json.decode(hero.sent[1].s).data.id, olderId, "the asked one")
-- the display scale (display_scale_core.lua): each recap at the factor of the level the character had at that death
-- (a level-1000 death: x1000), whatever its level now; the stored rows stay raw
dofile("data/scripts/chaos/display_scale_core.lua")
ChaosDisplayScale.configure({curve = {{100, 1}, {1000, 1000}, {1500, 10000}}}) -- the scale is off (x1); its code is tested on the old curve
local newest
for _, r in ipairs(rows) do if r.player_id == 7 and (not newest or r.id > newest.id) then newest = r end end
local rawData = newest.data
local stored = json.decode(newest.data)
stored.lvl = 1000
newest.data = json.encode(stored)
local storedAfter = newest.data
hero.sent = {}
registry.ChaosDeathRecapExtended.onExtendedOpcode(hero, 154, json.encode({action = "open", data = {}}))
local hs = json.decode(hero.sent[1].s)
eq(hs.data.recap.kb.a, 106 * 1000, "a level-1000 death: the killing blow x1000")
eq(hs.data.recap.tot, stored.tot * 1000, "its total x1000")
eq(hs.data.list[1].tot, stored.tot * 1000, "its summary x1000")
eq(hs.data.list[2].tot, h.data.list[2].tot, "a level-120 death stays (x1)")
eq(hs.data.recap.exp, stored.exp, "experience stays")
eq(newest.data, storedAfter, "the stored row is not changed by the send")
newest.data = rawData
ChaosDisplayScale = nil
-- another character's id: nothing
local foeId
for _, r in ipairs(rows) do if r.player_id == 8 then foeId = r.id end end
hero.sent = {}
registry.ChaosDeathRecapExtended.onExtendedOpcode(hero, 154, json.encode({action = "get", data = {id = foeId}}))
eq(#hero.sent, 0, "another character's recap is never sent")
-- bad input
registry.ChaosDeathRecapExtended.onExtendedOpcode(hero, 154, "not json")
registry.ChaosDeathRecapExtended.onExtendedOpcode(hero, 154, json.encode({action = "get", data = {id = "x"}}))
registry.ChaosDeathRecapExtended.onExtendedOpcode(hero, 155, json.encode({action = "open"}))
eq(#hero.sent, 0, "bad input and other opcodes ignored")
-- logout forgets the log
hook(hero, dragon, src(dragon), 10, "fire", false, clock)
registry.ChaosDeathRecapLogout.onLogout(hero)
eq(E.logs[hero.id], nil, "log forgotten at logout")

print(string.format("deathrecap_test: %s (%d checks)", failures == 0 and "OK" or (failures .. " FAILED"), count))
os.exit(failures == 0 and 0 or 1)
