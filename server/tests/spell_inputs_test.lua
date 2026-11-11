-- Run from the server/ folder: luajit tests/spell_inputs_test.lua && lua5.3 tests/spell_inputs_test.lua (CI runs both)
-- O468 (owner 2026-11-10: "How are the players' spells scaling? It needs to be by skill, magic level and character
-- level."). The guard that keeps it true: every Chaos spell script of spells_chaos.xml that deals damage or heals is cast
-- on a mocked engine (tests/fixtures/spell_probe_engine.lua, the real helpers) and its value must move with
--   (a) the character level, (b) the magic level, (c) for a spell of a weapon line the weapon skill.
-- The spells come from spells_chaos.xml, not a typed list. A spell leaves a rule only through the named tables below, each
-- with its reason. SPELL_INPUTS_REPORT=1 prints the whole table (value, shares, which inputs move it).
local checks, fails = 0, 0
local function ok(c, m)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. (m or ""))
	end
end

local function readAll(path)
	local f = assert(io.open(path, "r"), path)
	local s = f:read("*a")
	f:close()
	return s
end

-- ------------------------------------------------------------------------------------------------ the spells
local spells = {}
do
	local xml = readAll("data/spells/chaos/spells_chaos.xml")
	for attrs, body in xml:gmatch("<instant ([^>]*)>(.-)</instant>") do
		local s = {id = tonumber(attrs:match('spellid="(%d+)"')), name = attrs:match('name="([^"]+)"'),
			group = attrs:match('group="([^"]+)"'), script = attrs:match('script="([^"]+)"'), vocs = {}}
		for v in body:gmatch('<vocation name="([^"]+)"') do
			s.vocs[#s.vocs + 1] = v
		end
		spells[#spells + 1] = s
	end
end
ok(#spells >= 170, "spells_chaos.xml lists the instants (" .. #spells .. ")")

-- the 21 classes: vocation id, the weapon the typical character holds, and whether it casts (its magic level IS its skill)
local CLASS = {
	Mystic = {1, "caster"}, Ranger = {3, "distance"}, Warrior = {4, "melee"}, Elementalist = {5, "caster"}, Deadeye = {7, "distance"},
	Juggernaut = {8, "melee"}, Illusionist = {10, "caster"}, Thief = {11, "melee"}, Ninja = {12, "melee"}, Samurai = {13, "melee"},
	Berserker = {14, "melee"}, Beastmaster = {15, "distance"}, Monk = {17, "fist"}, Shadowfist = {18, "fist"}, ["Iron Sage"] = {19, "fist"},
	Necromancer = {20, "caster"}, Lich = {21, "caster"}, ["Bone Lord"] = {22, "caster"}, Templar = {23, "melee"}, Inquisitor = {24, "melee"},
	Sentinel = {25, "melee"},
}

-- the typical character (server/tools/rotation_sim.py ANCHORS; the numbers of the audit that opened O468)
local ANCHORS = {
	ml_caster = {{1, 0}, {100, 60}, {300, 100}, {600, 120}, {1000, 140}},
	ml_other = {{1, 0}, {100, 10}, {300, 25}, {600, 32}, {1000, 40}},
	skill = {{1, 10}, {100, 80}, {300, 110}, {600, 125}, {1000, 140}},
	atk_melee = {{1, 10}, {100, 45}, {300, 55}, {600, 60}, {1000, 65}},
	atk_distance = {{1, 10}, {100, 45}, {300, 60}, {600, 70}, {1000, 77}},
}
local function interp(pts, x)
	if x <= pts[1][1] then return pts[1][2] end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if x <= b[1] then return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end
	end
	return pts[#pts][2]
end
local function typical(kind, level)
	local sk = interp(ANCHORS.skill, level)
	local p = {lvl = level, ml = interp(ANCHORS[kind == "caster" and "ml_caster" or "ml_other"], level),
		sword = 10, club = 10, axe = 10, dist = 10, fist = 10, shield = 10, wtype = "none", atk = 50, hpNow = 3000}
	if kind == "melee" then
		p.sword, p.club, p.axe, p.wtype, p.atk = sk, sk, sk, "sword", interp(ANCHORS.atk_melee, level)
	elseif kind == "distance" then
		p.dist, p.wtype, p.atk = sk, "distance", interp(ANCHORS.atk_distance, level)
	elseif kind == "fist" then
		p.fist = sk
	else
		p.sword, p.club, p.axe, p.dist, p.fist = sk, sk, sk, sk, sk -- a caster's skills are irrelevant to its spells
	end
	return p
end

-- ----------------------------------------------------------------------------------------------- the exceptions
-- A spell named here is exempt from ONE rule, with the reason. Nothing else is: a new spell that ignores an input fails.
local NO_SKILL = {} -- (c) the weapon skill: a spell of a weapon line that is not driven by a weapon
local NO_LEVEL = {} -- (a) the character level
local NO_ML = {} -- (b) the magic level
local NOT_A_HIT = { -- the number the mock sees is not damage or a heal: the rules do not apply
	[247] = "Bloodrage: the number is the health the spell costs its caster (10% of the current health), not a hit",
}
local NO_VALUE = {} -- a damage spell the mock cannot cast to a number: a PROBES entry reads the number of the helper it calls
-- the helper a spell's number comes from, for a spell whose cast needs state the mock does not have (a companion out, a
-- corpse, a skeleton, a trap that bursts later): function(spellRow) returns the value of a typical cast
local PROBES = {}
local function avg(lo, hi) return (math.abs(lo) + math.abs(hi)) / 2 end
-- the Beastmaster's wolf spells: ChaosClasses.maulValuesFor(caster, key) x the mauls of one cast (Wolves.cast in _wolves.lua)
local function wolf(s)
	local key = readAll("data/spells/" .. s.script):match("Wolves%.cast%('(%w+)'")
	return function(Probe)
		local lo, hi = ChaosClasses.maulValuesFor(Probe.caster, key)
		return avg(lo, hi)
	end
end
-- a snare or a mine: the damage frozen into the snare at placement (ChaosSnares.state)
local function snare()
	return function(Probe)
		local list = ChaosSnares.state.list
		local sn = list[#list]
		return sn and avg(sn.min, sn.max) or 0
	end
end

PROBES[249], PROBES[147], PROBES[35], PROBES[39] = wolf, wolf, wolf, wolf -- Feral Command, Pack Frenzy, Pack Howl, Rending Pounce
PROBES[99], PROBES[100] = snare, snare -- Snare Trap, Seeker Mine
PROBES[185] = function() -- Corpse Explosion: a corpse in reach is needed; the burst is ChaosNecro.values(player, corpseExplosion.hit)
	return function(Probe)
		local lo, hi = ChaosNecro.values(Probe.caster, NecroSpell.cfg.corpseExplosion.hit)
		return avg(lo, hi)
	end
end
PROBES[188] = function() -- Bone Offering: a skeleton is needed; ChaosNecroCore.offeringValues of the skeleton's health
	return function(Probe)
		local lo, hi = ChaosNecroCore.offeringValues(NecroSpell.cfg, Probe.P.lvl, Probe.P.ml, 1000)
		return avg(lo, hi)
	end
end

-- ------------------------------------------------------------------------------------------------------- the run
local Probe = dofile("tests/fixtures/spell_probe_engine.lua")
ok(Probe.loadError == nil, "chaos_constants loads on the mock: " .. tostring(Probe.loadError))

local LEVEL = 500
local function measure(s, cls, p)
	Probe.set(p)
	Probe.set({voc = CLASS[cls][1]})
	if ChaosSnares and ChaosSnaresCore then
		ChaosSnares.state = ChaosSnaresCore.newState() -- one snare at a time
	end
	local res = Probe.cast(s.script)
	local dmg, heal = Probe.total(res)
	if dmg + heal <= 0 and PROBES[s.id] and not res.err then
		local okp, v = pcall(PROBES[s.id](s), Probe)
		if okp and v then
			return v, res
		end
		res.err = "probe: " .. tostring(v)
	end
	return dmg + heal, res
end

local rows, report = {}, os.getenv("SPELL_INPUTS_REPORT")
local function moved(a, b) return b > a * 1.002 end
local nValue, nAll = 0, 0
for _, s in ipairs(spells) do
	local cls = s.vocs[1]
	ok(cls and CLASS[cls], s.name .. ": a known class")
	if cls and CLASS[cls] then
		local kind = CLASS[cls][2]
		local caster = true
		for _, v in ipairs(s.vocs) do
			if CLASS[v] and CLASS[v][2] ~= "caster" then caster = false end
		end
		local base = typical(kind, LEVEL)
		local v0, res = measure(s, cls, base)
		if NOT_A_HIT[s.id] then
			v0 = 0
		elseif res.err then
			ok(false, s.name .. " (" .. s.script .. ") casts without an error: " .. res.err)
		end
		local row = {s = s, v0 = v0, cls = cls, caster = caster}
		rows[#rows + 1] = row
		if v0 <= 0 then
			if s.group ~= "support" and not NOT_A_HIT[s.id] then
				ok(NO_VALUE[s.id], s.name .. " (" .. s.script .. ") deals no damage and heals nothing on the mock and is not in NO_VALUE")
			end
		else
			nValue = nValue + 1
			local function with(over)
				local q = {}
				for k, v in pairs(base) do q[k] = v end
				for k, v in pairs(over) do q[k] = v end
				return (measure(s, cls, q))
			end
			row.level = moved(v0, with({lvl = LEVEL * 2}))
			row.ml = moved(v0, with({ml = base.ml * 2}))
			row.skill = moved(v0, with({sword = base.sword * 2, club = base.club * 2, axe = base.axe * 2, dist = base.dist * 2, fist = base.fist * 2}))
			if not NO_LEVEL[s.id] then
				ok(row.level, s.name .. " (" .. s.script .. ", " .. cls .. "): the value does not move with the character level")
			end
			if not NO_ML[s.id] then
				ok(row.ml, s.name .. " (" .. s.script .. ", " .. cls .. "): the value does not move with the magic level")
			end
			if not caster and s.group ~= "healing" and not NO_SKILL[s.id] then
				ok(row.skill, s.name .. " (" .. s.script .. ", " .. cls .. "): a weapon spell's value does not move with the weapon skill")
			end
			if row.level and row.ml and row.skill then nAll = nAll + 1 end
		end
	end
end
for id in pairs(NO_VALUE) do
	local found = false
	for _, s in ipairs(spells) do found = found or s.id == id end
	ok(found, "NO_VALUE names a spell of spells_chaos.xml: " .. tostring(id))
end

if report then
	print(string.format("%-28s %-12s %-4s %9s  level ml skill", "spell", "class", "kind", "value"))
	for _, r in ipairs(rows) do
		print(string.format("%-28s %-12s %-4s %9.0f  %s %s %s", r.s.name, r.cls, r.caster and "cast" or "weap", r.v0,
			r.level and "Y" or "-", r.ml and "Y" or "-", r.skill and "Y" or "-"))
	end
	print("spells with a value: " .. nValue .. ", moving with all three inputs: " .. nAll)
end

if fails > 0 then
	error("spell_inputs_test: " .. fails .. " failure(s)")
end
print("spell_inputs_test: " .. checks .. " checks ok (" .. nValue .. " spells with a value, " .. nAll .. " move with level, magic level and skill)")
