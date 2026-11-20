-- Run from the server/ folder: luajit tests/spell_combos_test.lua && lua5.3 tests/spell_combos_test.lua (CI runs both)
-- O686 phase 6: spell combos. Part A: spell_combos_core.lua and spell_combos_config.lua (every row fires, the window, the limits, the
-- element, the band 10..20%, the model numbers, the pt-BR names). Part B: spell_combos.lua with the real ChaosPassiveDealt of
-- passivetree_effects.lua on a mocked engine (the bonus on the hit of the second spell, PvP off, switch off, the Form conversion, the
-- heal combo, the credit stays with the second spell, the client message).

local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, tol, what)
	ok(type(a) == "number" and math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " vs " .. tostring(b))
end

local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/scripts/chaos/spell_combos_core.lua")
local C = ChaosSpellCombosCore
local cfg = dofile("data/scripts/chaos/spell_combos_config.lua")

-- ---------------------------------------------------------------- A1. the config
eq(#C.check(cfg), 0, "the config is sound: " .. table.concat(C.check(cfg), "; "))
eq(#cfg.rows, 13, "13 rows: 6 reactions, 6 signature combos, 1 heal combo")
local kinds = {reaction = 0, class = 0, heal = 0}
local names, ids = {}, {}
for _, r in ipairs(cfg.rows) do
	kinds[r.kind] = kinds[r.kind] + 1
	ok(r.bonus >= 0.10 - 1e-9 and r.bonus <= 0.20 + 1e-9, r.id .. ": the bonus is +10% to +20% (owner 2026-11-20)")
	ok(not names[r.name] and not ids[r.id], r.id .. ": name and id are unique")
	names[r.name], ids[r.id] = true, true
end
eq(kinds.reaction, 6, "6 element reactions")
eq(kinds.class, 6, "6 signature combos")
eq(kinds.heal, 1, "1 heal combo")
-- the design's table (4.2), row by row
local design = {
	steam_burst = 0.10, thermal_shock = 0.12, overload = 0.12, pyre_of_the_dead = 0.15, mudslide = 0.10, consecrated_ash = 0.15,
	pinned_shot = 0.20, meat_grinder = 0.20, anvil_chain = 0.18, backstab = 0.20, rotting_curse = 0.18, psychic_shatter = 0.20,
	echoing_mend = 0.15,
}
for id, bonus in pairs(design) do
	local r = C.row(cfg, id)
	ok(r ~= nil, id .. " is a row")
	if r then
		near(r.bonus, bonus, 1e-9, id .. " bonus")
	end
end
-- a bonus outside the band is refused by the check
do
	local bad = {band = cfg.band, rows = {{id = "x", name = "X", pt = "X", kind = "reaction", first = {element = "ice"},
		second = {element = "fire"}, bonus = 0.25, weight = 1}}}
	ok(#C.check(bad) >= 1, "a 25% row fails the check")
	bad.rows[1].bonus = 0.09
	ok(#C.check(bad) >= 1, "a 9% row fails the check")
end

-- the spell ids name the spells of the design (data/spells/forms.csv: id, spell)
local formName = {}
for line in readFile("data/spells/forms.csv"):gmatch("[^\r\n]+") do
	local id, name = line:match('^(%d+),("?[^",]+"?),')
	if id then
		formName[tonumber(id)] = (name:gsub('"', ""))
	end
end
local want = {
	pinned_shot = {{[99] = "Snare Trap", [100] = "Seeker Mine"}, {[218] = "Final Verdict", [144] = "Twin Verdict", [19] = "Sunspear"}},
	meat_grinder = {{[2] = "Gorehook"}, {[220] = "Reaping Gyre", [105] = "Butcher's Gyre", [221] = "Earthbreaker"}},
	anvil_chain = {{[196] = "Iron Chain"}, {[84] = "Quaking Stomp"}},
	backstab = {{[240] = "Shadow Step"}, {[45] = "Gutting Slash", [157] = "Death Between Heartbeats"}},
	rotting_curse = {{[182] = "Withering Curse"}, {[183] = "Soul Rot", [113] = "Blightbrand", [185] = "Corpse Explosion"}},
	psychic_shatter = {{[53] = "Bewitching Hex"}, {[228] = "Shattered Psyche", [43] = "Dreamrot"}},
	echoing_mend = {{[96] = "Mirror Mend"}, {[97] = "Lucid Reverie"}},
}
for id, sides in pairs(want) do
	local r = C.row(cfg, id)
	for s, side in ipairs({r.first.spells, r.second.spells}) do
		local n = 0
		for _, sid in ipairs(side) do
			n = n + 1
			eq(formName[sid], sides[s][sid], id .. ": spell id " .. sid .. " is " .. tostring(sides[s][sid]))
		end
		local expected = 0
		for _ in pairs(sides[s]) do
			expected = expected + 1
		end
		eq(n, expected, id .. ": side " .. s .. " lists every spell of the design")
		-- the Codex text (`show`) names every spell of the side
		for _, sid in ipairs(side) do
			ok(r.show and r.show:find(formName[sid], 1, true) ~= nil, id .. ": the Codex text names " .. tostring(formName[sid]))
		end
	end
end

-- the pt-BR text of every name is in the client's locale file, equal to `pt`
do
	local pt = readFile("../client/overlay/modules/client_chaos_locale/pt_br.lua")
	for _, r in ipairs(cfg.rows) do
		local want = '["' .. r.name .. '"] = "' .. r.pt .. '"'
		ok(pt:find(want, 1, true) ~= nil, r.name .. ": pt_br.lua has " .. want)
	end
end

-- ---------------------------------------------------------------- A2. the model numbers
near(C.meanBonus(cfg), 0.151, 0.001, "the weighted mean bonus is about 15%")
near(C.typicalGain(cfg), 0.06, 0.002, "the typical rotation gains about +6% (design 5.1)")
ok(C.typicalGain(cfg) <= cfg.model.typicalMax, "the typical gain is inside its limit")
near(C.bestGain(cfg), 0.08, 1e-9, "the best legal rotation gains +8% (design 4.1)")
ok(C.bestGain(cfg) <= cfg.model.bestMax + 1e-9, "the best gain is inside its limit")

-- ---------------------------------------------------------------- A3. the rules
local function pos(x, y)
	return {x = x, y = y, z = 7}
end
local function rank5() return 5 end
local function rank4() return 4 end
local function rank0() return 0 end

-- one scenario: a first cast (element or spell id), the second hit; returns the id of the row that fired or nil
local function scenario(first, second, o)
	o = o or {}
	local st = o.state or C.newState()
	local t0 = o.t0 or 100000
	local e = C.cast(st, cfg, first.spell or 1, t0, o.firstTarget or 50, o.firstPos or pos(10, 10))
	if first.element then
		e.hit, e.element = true, first.element
	end
	local t1 = t0 + (o.gap or 1500)
	C.cast(st, cfg, second.spell or 2, t1, o.secondTarget or 50, pos(10, 10))
	local row, factor = C.onHit(st, cfg, {spell = second.spell or 2, now = (o.hitAt or t1 + 50), element = second.element, heal = second.heal,
		target = o.hitTarget or 50, pos = o.hitPos or pos(10, 10), pvp = o.pvp, rankOf = o.rank or rank5})
	return row and row.id or nil, factor, st
end

-- every reaction fires, by the elements of the two hits
for _, r in ipairs(cfg.rows) do
	if r.kind == "reaction" then
		local id, factor = scenario({element = r.first.element, spell = 1}, {element = r.second.element, spell = 2}, {rank = rank0})
		eq(id, r.id, r.id .. ": " .. r.first.element .. " then " .. r.second.element .. " fires with no rank (free for every class)")
		near(factor, 1 + r.bonus, 1e-9, r.id .. ": the factor is 1 + the bonus")
	end
end
-- the order matters, and a pair that is no reaction does nothing
eq((scenario({element = "fire", spell = 1}, {element = "fire", spell = 2})), nil, "fire then fire is no combo")
eq((scenario({element = "ice", spell = 1}, {element = "ice", spell = 2})), nil, "ice then ice is no combo")
eq((scenario({element = "fire", spell = 1}, {element = "energy", spell = 2})), nil, "fire then energy is no combo")
eq((scenario({element = "holy", spell = 1}, {element = "fire", spell = 2})), nil, "holy then fire is no combo (only fire then holy)")
eq((scenario({element = "physical", spell = 1}, {element = "fire", spell = 2})), nil, "physical then fire is no combo")
eq((scenario({spell = 1}, {element = "fire", spell = 2})), nil, "a first cast that never hit has no element: no reaction")

-- every signature and heal combo fires for every pair of its spell lists at rank 5, and only then
for _, r in ipairs(cfg.rows) do
	if r.kind ~= "reaction" then
		for _, a in ipairs(r.first.spells) do
			for _, b in ipairs(r.second.spells) do
				local heal = r.kind == "heal"
				local id, factor = scenario({spell = a}, {spell = b, heal = heal, element = (not heal) and "physical" or nil})
				eq(id, r.id, r.id .. ": " .. a .. " then " .. b .. " at rank 5")
				near(factor, 1 + r.bonus, 1e-9, r.id .. ": factor")
				eq((scenario({spell = a}, {spell = b, heal = heal}, {rank = rank4})), nil, r.id .. ": rank 4 opens nothing (design 4.2: rank 5)")
				eq((scenario({spell = b}, {spell = a, heal = heal})), nil, r.id .. ": the order matters (" .. b .. " then " .. a .. ")")
			end
		end
	end
end
-- a heal combo needs a heal, a damage combo a damage hit
eq((scenario({spell = 96}, {spell = 97, heal = false, element = "holy"})), nil, "Echoing Mend needs the second hit to be a heal")
eq((scenario({spell = 99}, {spell = 218, heal = true})), nil, "Pinned Shot needs a damage hit")
-- one of the two spells at rank 5 is not enough
do
	local function oneOnly(id)
		return function(sid) return sid == id and 5 or 0 end
	end
	eq((scenario({spell = 99}, {spell = 218, element = "holy"}, {rank = oneOnly(99)})), nil, "only the first spell at rank 5: no signature combo")
	eq((scenario({spell = 99}, {spell = 218, element = "holy"}, {rank = oneOnly(218)})), nil, "only the second spell at rank 5: no signature combo")
end

-- the window: 4 s from the first cast to the second
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {gap = 4000})), "steam_burst", "4000 ms: inside the window")
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {gap = 4001})), nil, "4001 ms: outside the window")
-- the same target, or within 2 sqm of where the first spell hit
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {firstTarget = 50, hitTarget = 51, hitPos = pos(12, 10)})),
	"steam_burst", "another target 2 sqm away: inside")
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {firstTarget = 50, hitTarget = 51, hitPos = pos(13, 10)})),
	nil, "another target 3 sqm away: outside")
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {firstTarget = 50, hitTarget = 50, hitPos = pos(40, 40)})),
	"steam_burst", "the same target: always near")
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {firstTarget = 50, hitTarget = 51, hitPos = {x = 10, y = 10, z = 8}})),
	nil, "another floor is never near")
-- the pending combo expires after 1 s without a hit
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {hitAt = 100000 + 1500 + 1000})), "steam_burst", "a hit 1000 ms after the cast: still counts")
eq((scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {hitAt = 100000 + 1500 + 1001})), nil, "a hit 1001 ms after the cast: the cast missed")

-- only the first hit of a cast asks: an area spell's second target gets nothing
do
	local id, _, st = scenario({element = "ice", spell = 1}, {element = "fire", spell = 2})
	eq(id, "steam_burst", "the first hit of the cast")
	local row, f = C.onHit(st, cfg, {spell = 2, now = 101600, element = "fire", target = 51, pos = pos(10, 11), rankOf = rank0})
	eq(row, nil, "the second hit of the same cast: no combo")
	eq(f, 1, "factor 1")
	-- a tick of a spell nobody cast just now never combos
	row = C.onHit(st, cfg, {spell = 77, now = 101600, element = "fire", target = 51, pos = pos(10, 11), rankOf = rank0})
	eq(row, nil, "a hit of a spell with no fresh cast: no combo")
end

-- the limits: the same combo on the same target waits 6 s, a player has a pause of 1.2 s between combos
do
	local st = C.newState()
	local function pair(t, target, first, second)
		C.cast(st, cfg, 1, t, target, pos(10, 10)).hit = true
		local e = st.ring[#st.ring]
		e.element = first
		C.cast(st, cfg, 2, t + 100, target, pos(10, 10))
		local row = C.onHit(st, cfg, {spell = 2, now = t + 150, element = second, target = target, pos = pos(10, 10), rankOf = rank0})
		return row and row.id or nil
	end
	eq(pair(1000, 50, "ice", "fire"), "steam_burst", "the first combo fires")
	eq(pair(2000, 50, "ice", "fire"), nil, "the same combo on the same target 1 s later: no (global pause and repeat)")
	eq(pair(3000, 50, "ice", "fire"), nil, "the same combo on the same target 2 s later: no (repeat 6 s)")
	eq(pair(3000, 51, "ice", "fire"), "steam_burst", "the same combo on another target after the pause: yes")
	eq(pair(3500, 52, "ice", "fire"), nil, "a combo 0.5 s after another: no (global pause 1.2 s)")
	eq(pair(7000, 50, "ice", "fire"), "steam_burst", "the same combo on the first target after 6 s: yes")
end

-- at most one combo a cast: the best row of the matches (the highest bonus)
do
	local st = C.newState()
	local a = C.cast(st, cfg, 1, 1000, 50, pos(10, 10))
	a.hit, a.element = true, "ice"
	local b = C.cast(st, cfg, 3, 1200, 50, pos(10, 10))
	b.hit, b.element = true, "death"
	C.cast(st, cfg, 2, 1500, 50, pos(10, 10))
	local row, f = C.onHit(st, cfg, {spell = 2, now = 1550, element = "fire", target = 50, pos = pos(10, 10), rankOf = rank0})
	eq(row and row.id, "pyre_of_the_dead", "ice and death before fire: one combo, the better one (15% over 10%)")
	near(f, 1.15, 1e-9, "its factor")
end

-- PvP: no combo, and the entry of the cast is closed
do
	local id, factor, st = scenario({element = "ice", spell = 1}, {element = "fire", spell = 2}, {pvp = true})
	eq(id, nil, "PvP: no combo")
	eq(factor, 1, "PvP: factor 1")
	eq(st.lastAt, nil, "PvP: no pause started")
end

-- the ring keeps the last four casts
do
	local st = C.newState()
	for i = 1, 7 do
		C.cast(st, cfg, i, i * 100, nil, nil)
	end
	eq(#st.ring, 4, "the ring holds 4 casts")
	eq(st.ring[1].spell, 4, "the oldest are gone")
end

-- the element of a hit
eq(C.elementOf("fire", 100, nil, 0, cfg), "fire", "one part")
eq(C.elementOf("physical", 100, "fire", 0, cfg), "physical", "an empty part is no part")
eq(C.elementOf("physical", 100, "ice", 30, cfg), "ice", "a weapon line spell: the element part at 30% wins over physical")
eq(C.elementOf("physical", 100, "ice", 20, cfg), "physical", "the element part at 20% does not")
eq(C.elementOf("fire", 50, "ice", 100, cfg), "ice", "two elements: the larger part")
eq(C.elementOf(nil, 0, nil, 0, cfg), nil, "no parts")
eq(C.apply(-1000, 1.1), -1100, "apply rounds a damage")
eq(C.apply(1000, 1.15), 1150, "apply rounds a heal")
eq(C.apply(-7, 1), -7, "factor 1 keeps the amount")

-- ---------------------------------------------------------------- B. the engine side on a mocked engine
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
Chaos = {storage = {}, tables = {}, passive = {}}
function Chaos.load() end
ChaosOpcodes = {spellRanks = 168}
local sent = {}
function Chaos.send(player, opcode, action, data) sent[#sent + 1] = {opcode = opcode, action = action, data = data} return true end
local registered = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
rawset(EventCallback, "register", function(self) local l = rawget(self, "_last"); registered[l[1]] = l[2] end)
function CreatureEvent(name)
	local o = {}
	function o:register() registered[name] = o end
	function o:type() end
	return o
end
function Condition() local c = {p = {}}; function c:setTicks() end; function c:setParameter(k, v) self.p[k] = v end; return c end
function addEvent() end
local clock = 5000000
os.mtime = function() return clock end
local dealtCalls = 0
function doTargetCombat() dealtCalls = dealtCalls + 1 end

dofile("data/scripts/chaos/passivetree_effects.lua")
local ev = registered["ChaosPassiveDealt"]
dofile("data/scripts/chaos/spell_ranks_core.lua")
local RC = dofile("data/scripts/chaos/spell_ranks_config.lua")
ChaosSpellRanksConfig = RC
dofile("data/scripts/chaos/spell_combos.lua")
local M = ChaosSpellCombos
local P = ChaosSpellRanksCore
local R = ChaosSpellRanks
ok(registered["ChaosSpellCombosLogout"] and registered["ChaosSpellCombosLogin"], "login and logout events")

local storage = {}
local castSpell
ChaosSupportsSpell = {cast = function(pid) return 900, castSpell end}
local function newPlayer(voc)
	local p = {pos = {x = 100, y = 100, z = 7}}
	function p:getId() return 900 end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getVocation() return {getId = function() return voc or 2 end} end
	function p:getLevel() return 300 end
	function p:getStorageValue(k) return storage[k] or -1 end
	function p:getPosition() return self.pos end
	function p:getTarget() return self.target end
	function p:registerEvent() end
	return p
end
local function newMonster(id, x, y)
	local m = {id = id, pos = {x = x or 101, y = y or 100, z = 7}}
	function m:getId() return id end
	function m:isPlayer() return false end
	function m:isMonster() return true end
	function m:getMaster() return self.master end
	function m:getPosition() return self.pos end
	function m:getName() return "Troll" end
	return m
end
local function setRank(id, rank)
	storage[RC.storage.rankBase + id] = P.pack(rank, 0, 0, false)
end
local function cast(p, id, aggressive)
	ChaosSpellEvents.onSpellCast(p, "S" .. id, id, 1, aggressive ~= false, 0, 0)
	castSpell = id
end
local function hit(p, target, ctype, amount, ctype2, amount2)
	local d1, _, d2 = ev.onHealthChange(target, p, amount, ctype, amount2 or 0, ctype2 or COMBAT_NONE, ORIGIN_SPELL)
	return d1, d2
end
local function tick(ms)
	clock = clock + ms
end

local p = newPlayer(2) -- vocation 2: the class spell factor is 1
local troll = newMonster(501)
p.target = troll
RC.track = false

-- switched off (the shipped state): a fire spell after an ice spell is plain
eq(RC.enabled, false, "the shipped switch is off")
cast(p, 300)
eq(M.states[900], nil, "switch off: no ring is kept")
eq((hit(p, troll, COMBAT_ICEDAMAGE, -1000)), -1000, "switch off: an ice hit is plain")
tick(1500)
cast(p, 301)
eq((hit(p, troll, COMBAT_FIREDAMAGE, -1000)), -1000, "switch off: ice then fire gives nothing")
eq(#sent, 0, "switch off: no message")

-- ranks on, combos off by their own switch
RC.enabled = true
cfg = ChaosSpellCombosConfig
cfg.enabled = false
tick(10000)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(1500)
cast(p, 301)
eq((hit(p, troll, COMBAT_FIREDAMAGE, -1000)), -1000, "combos off: ice then fire gives nothing")
cfg.enabled = true
eq(#sent, 0, "combos off: no message")

-- Steam Burst: ice then fire, free for every class, rank 0
tick(10000)
cast(p, 300)
eq((hit(p, troll, COMBAT_ICEDAMAGE, -1000)), -1000, "the first spell of a pair is plain")
tick(1500)
cast(p, 301)
local d1, d2 = hit(p, troll, COMBAT_FIREDAMAGE, -1000, COMBAT_NONE, 0)
eq(d1, -1100, "ice then fire: Steam Burst +10% on the hit of the second spell")
eq(#sent, 1, "one message to the client")
eq(sent[1].action, "combo", "a combo message")
eq(sent[1].opcode, 168, "on opcode 168")
eq(sent[1].data.id, "steam_burst", "its id")
eq(sent[1].data.n, "Steam Burst", "its English name")
eq(sent[1].data.x, 101, "the target's x")
eq(sent[1].data.z, 7, "the target's floor")
-- the credit: the bonus is inside the hit of the second spell, in its cast context; no extra hit exists
eq(select(2, ChaosSupportsSpell.cast()), 301, "the combat log reads the SECOND spell for the hit (it gets the credit, bonus included)")
eq(dealtCalls, 0, "no extra hit was dealt (nothing else can be credited)")
-- the second hit of the same cast (an area spell's next target) gets nothing
local troll2 = newMonster(502, 102, 100)
eq((hit(p, troll2, COMBAT_FIREDAMAGE, -1000)), -1000, "the second target of the same cast: plain")
-- the secondary part is scaled with the primary
tick(10000)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(1500)
cast(p, 301)
d1, d2 = hit(p, troll, COMBAT_FIREDAMAGE, -1000, COMBAT_FIREDAMAGE, -200)
eq(d1, -1100, "primary +10%")
eq(d2, -220, "secondary +10% too")

-- the rank multiplies first, the combo on the ranked hit: rank 20 is +18% then +12% (Thermal Shock, fire then ice)
tick(10000)
cast(p, 301)
hit(p, troll, COMBAT_FIREDAMAGE, -1000)
tick(1500)
setRank(302, 20)
cast(p, 302)
d1 = hit(p, troll, COMBAT_ICEDAMAGE, -1000)
near(d1, -math.floor(1000 * 1.18 * 1.12 + 0.5), 2, "rank 20 +18% and Thermal Shock +12% on the ranked hit (the bonus grows with the rank)")
eq(sent[#sent].data.id, "thermal_shock", "Thermal Shock")

-- the element after a Form conversion counts: a physical spell that converts to ice, after fire
tick(10000)
cast(p, 301)
hit(p, troll, COMBAT_FIREDAMAGE, -1000)
tick(1500)
local FE = ChaosSpellForms
local oldActive, oldConv = FE.active, FE.conversion
FE.active = function() return {{kind = "SHIFT", element = "ice"}} end
FE.conversion = function() return "ice" end
cast(p, 303)
d1 = hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)
eq(d1, -1120, "fire then a spell converted to ice: Thermal Shock (the Form's element counts)")
FE.active, FE.conversion = oldActive, oldConv
tick(10000)
cast(p, 301)
hit(p, troll, COMBAT_FIREDAMAGE, -1000)
tick(1500)
cast(p, 303)
eq((hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)), -1000, "the same physical spell with no Form: no reaction")

-- PvP: never
tick(10000)
local rival = newMonster(600)
function rival:isPlayer() return true end
function rival:isMonster() return false end
sent = {}
cast(p, 305)
local pvpBase = hit(p, rival, COMBAT_FIREDAMAGE, -1000) -- the level scaling of damage between players, no combo in it
tick(10000)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(1500)
cast(p, 301)
eq((hit(p, rival, COMBAT_FIREDAMAGE, -1000)), pvpBase, "PvP: ice then fire on another player gives nothing (the hit is the plain PvP hit)")
eq(#sent, 0, "PvP: no message")
-- a summon of a player is no target either
tick(10000)
local pet = newMonster(601)
pet.master = newPlayer(2)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(1500)
cast(p, 301)
eq((hit(p, pet, COMBAT_FIREDAMAGE, -1000)), -1000, "a player's summon is no target")

-- a weapon hit, a proc and another player's cast are never touched
tick(10000)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(1500)
cast(p, 301)
local w = ev.onHealthChange(troll, p, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
eq(w, -1000, "a weapon hit has no combo")
ChaosKeystones = {depth = 1}
w = hit(p, troll, COMBAT_FIREDAMAGE, -1000)
eq(w, -1000, "a hit inside the proc guard (every extra hit of a Form) has no combo")
ChaosKeystones = nil
eq((hit(p, troll, COMBAT_FIREDAMAGE, -1000)), -1100, "the real first hit still has it (the guarded hit did not close the cast)")

-- a Signature combo: Gorehook (2) then Reaping Gyre (220), both rank 5
tick(10000)
setRank(2, 5)
setRank(220, 5)
cast(p, 2)
hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)
tick(2000)
cast(p, 220)
d1 = hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)
near(d1, -math.floor(1000 * R.factor(p, 220, false, false) * 1.20 + 0.5), 2, "Meat Grinder +20% on the ranked hit")
eq(sent[#sent].data.id, "meat_grinder", "Meat Grinder")
tick(10000)
setRank(2, 4)
cast(p, 2)
hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)
tick(2000)
cast(p, 220)
d1 = hit(p, troll, COMBAT_PHYSICALDAMAGE, -1000)
near(d1, -math.floor(1000 * R.factor(p, 220, false, false) + 0.5), 2, "rank 4 on the hook: no Meat Grinder")

-- the heal combo: Mirror Mend (96) then Lucid Reverie (97), a heal on an ally, +15%
tick(10000)
setRank(96, 5)
setRank(97, 5)
local ally = newMonster(700)
function ally:isPlayer() return true end
function ally:isMonster() return false end
p.target = nil
cast(p, 96)
hit(p, ally, COMBAT_HEALING, 1000)
tick(1500)
cast(p, 97)
local h1 = hit(p, ally, COMBAT_HEALING, 1000)
near(h1, math.floor(1000 * R.factor(p, 97, true, false) * 1.15 + 0.5), 2, "Echoing Mend +15% on the heal")
eq(sent[#sent].data.id, "echoing_mend", "Echoing Mend")

-- a stale ring: a cast that is not followed by a hit within the window is forgotten, and logout clears the state
tick(10000)
cast(p, 300)
hit(p, troll, COMBAT_ICEDAMAGE, -1000)
tick(4500)
cast(p, 301)
eq((hit(p, troll, COMBAT_FIREDAMAGE, -1000)), -1000, "the ice cast is older than 4 s: no combo")
registered["ChaosSpellCombosLogout"].onLogout(p)
eq(M.states[900], nil, "logout drops the state")

print(string.format("spell_combos_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
