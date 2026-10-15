-- Run from the server/ folder: luajit tests/packtools_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The pack tools (2026-10-15, data/spells/chaos/_packtools.lua): Palm Shockwave (194), Shadow Ricochet (195), Iron Chain
-- (196), Bone Shrapnel (197), Sanctified Ground (108), Shield Wave (109), Fan of Knives (136). The pure parts (hits,
-- jumps, the fan's targets), each spell script on a mocked engine (who is hit, the target the plain hit and the pack
-- `pack` x it, players never the pack share), the spell entries, the rotation model rows (1 + 4 x pack) and the
-- supports' kind.
local failures, checks = 0, 0
local function ok(v, m)
	checks = checks + 1
	if not v then
		failures = failures + 1
		print("FAIL: " .. tostring(m))
	end
end
local function eq(a, b, m)
	ok(a == b, tostring(m) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

-- ------------------------------------------------------------------ a small engine
ORIGIN_NONE, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED = 0, 2, 3, 4
COMBAT_PHYSICALDAMAGE, COMBAT_HOLYDAMAGE = 1, 2
CONST_ME_HITAREA, CONST_ME_DRAWBLOOD, CONST_ME_HOLYDAMAGE, CONST_ME_HOLYAREA, CONST_ME_GROUNDSHAKER = 1, 2, 3, 4, 5
CONST_ME_MORTAREA, CONST_ME_BLOCKHIT, CONST_ME_NONE = 6, 7, 0
CONST_ANI_DEATH, CONST_ANI_ENERGY, CONST_ANI_ETHEREALSPEAR, CONST_ANI_THROWINGKNIFE = 1, 2, 3, 4
RETURNVALUE_YOUCANONLYUSEITONCREATURES, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER = 10, 11
function Position(p) return p end

local creatures, hits, chi, queue = {}, {}, 0, {}
local nextId = 1
local function mk(kind, x, y, opts)
	opts = opts or {}
	local c = {id = nextId, kind = kind, pos = {x = x, y = y, z = opts.z or 7}, level = opts.level or 300,
		voc = opts.voc or 17, safe = opts.safe, target = nil}
	nextId = nextId + 1
	function c:getId() return self.id end
	function c:getPosition() return self.pos end
	function c:getLevel() return self.level end
	function c:getVocation() local v = self.voc return {getId = function() return v end} end
	function c:isMonster() return self.kind == "monster" end
	function c:isPlayer() return self.kind == "player" end
	function c:getPlayer() return self.kind == "player" and self or nil end
	function c:getMaster() return nil end
	function c:getHealth() return 1000 end
	function c:getTarget() return self.target end
	function c:registerEvent() end
	function c:isRemoved() return false end
	creatures[#creatures + 1] = c
	return c
end
local function reset()
	creatures, hits, chi, queue = {}, {}, 0, {}
end
local function near(c, pos, r)
	return c.pos.z == pos.z and math.max(math.abs(c.pos.x - pos.x), math.abs(c.pos.y - pos.y)) <= r
end
function doTargetCombat(caster, target, ctype, mn, mx, effect, origin)
	hits[#hits + 1] = {target = target, min = -mn, max = -mx, type = ctype, origin = origin}
	return true
end

local BASE = {min = 100, max = 200} -- every helper's plain hit in this engine
ChaosSupportsSpell = {cast = function() return nil end}
ChaosSpell = {
	isEnemy = function(caster, t) return t ~= caster and t:isMonster() end,
	canAttack = function(caster, t) return t ~= caster and not t.safe end,
	enemiesAround = function(caster, pos, r)
		local out = {}
		for _, c in ipairs(creatures) do
			if c ~= caster and c:isMonster() and near(c, pos, r) then out[#out + 1] = c end
		end
		return out
	end,
	spectators = function(pos, r)
		local out = {}
		for _, c in ipairs(creatures) do
			if near(c, pos, r) then out[#out + 1] = c end
		end
		return out
	end,
	targetOf = function(variant) return variant and variant.target end,
	cancel = function() return false end,
	shoot = function() end, vshoot = function() end, fx = function() end, vfxOr = function() end,
	pulse = function(id, count, interval, fn)
		for step = 1, count do
			queue[#queue + 1] = {fn = fn, step = step}
		end
	end,
	shurikenPower = function() return 6600 end,
	weaponStrike = function(caster, t, mn, mx, effect, origin)
		hits[#hits + 1] = {target = t, min = mn, max = mx, origin = origin}
		return true
	end,
}
local function playerById(id)
	for _, c in ipairs(creatures) do
		if c.id == id then return c end
	end
end
local function runPulses(caster)
	for _, q in ipairs(queue) do
		q.fn(caster, q.step)
	end
	queue = {}
end
MonkSpell = {
	values = function() return BASE.min, BASE.max end,
	meleeTarget = function(player, variant)
		local t = variant and variant.target
		if not t or t == player then return nil end
		return t
	end,
}
ChaosMonk = {addChi = function(player, n) chi = chi + n end}
ChaosNecro = {
	values = function() return BASE.min, BASE.max end,
	damage = function(caster, t, ctype, mn, mx, effect, origin)
		if not ChaosSpell.canAttack(caster, t) then return 0 end
		hits[#hits + 1] = {target = t, min = mn, max = mx, type = ctype, origin = origin}
		return 1
	end,
}
NecroSpell = {class = function() return true end, target = function(player, variant) return variant and variant.target end,
	fx = function() end}
TemplarSpell = {values = function() return BASE.min, BASE.max end}
local realDofile = dofile
dofile("data/spells/chaos/_blades.lua")
dofile("data/spells/chaos/_packtools.lua")
local T = ChaosPackTools
local C = T.cfg
ok(T and C, "ChaosPackTools loaded")
dofile = function(path)
	if path:find("data/spells/scripts/chaos/_", 1, true) then
		return nil -- the helpers: the mocks above, ChaosBlades and ChaosPackTools are loaded
	end
	return realDofile(path)
end
local function script(path)
	onCastSpell = nil
	realDofile("data/spells/chaos/" .. path)
	ok(onCastSpell, path .. " defines onCastSpell")
	return onCastSpell
end
local function byTarget()
	local m = {}
	for _, h in ipairs(hits) do
		m[h.target] = h
	end
	return m
end
local function packHit(key)
	return math.floor(BASE.min * C[key].pack), math.floor(BASE.max * C[key].pack)
end

-- ------------------------------------------------------------------ the pure parts
do
	local a, b = T.hitFor(100, 200, 2.5, true, false)
	ok(a == 100 and b == 200, "the target: the plain hit")
	a, b = T.hitFor(100, 200, 2.5, false, true)
	ok(a == 100 and b == 200, "a player: the plain hit")
	a, b = T.hitFor(100, 201, 2.5, false, false)
	ok(a == 250 and b == 502, "a pack monster: pack x it, rounded down")
	local mn, mx = T.strikeRange(300, 1000, {0.04, 20, 0.07, 40}, 1)
	ok(mn == 60 + 40 + 20 and mx == 60 + 70 + 40, "a strike's range")
	-- jumps: nearest first, within reach of the one before, none twice
	local cands = {{id = 2, pos = {x = 11, y = 10, z = 7}}, {id = 3, pos = {x = 13, y = 10, z = 7}},
		{id = 4, pos = {x = 17, y = 10, z = 7}}, {id = 5, pos = {x = 10, y = 11, z = 6}}}
	local j = T.jumpTargets({id = 1, pos = {x = 10, y = 10, z = 7}}, cands, 4, 3)
	ok(#j == 2 and j[1].id == 2 and j[2].id == 3, "jumps: 2 then 3; 4 is too far from 3, 5 on another floor")
	eq(#T.jumpTargets({id = 1, pos = {x = 10, y = 10, z = 7}}, cands, 1, 3), 1, "at most n jumps")
	local f = T.nearest({x = 10, y = 10, z = 7}, cands, 5, 3, 2)
	ok(#f == 1 and f[1].id == 3, "the fan: within reach, not the skipped target")
	for key, c in pairs(C) do
		ok(c.pack and c.pack >= 1, key .. ": the pack takes at least the plain hit")
	end
end

-- ------------------------------------------------------------------ Palm Shockwave (Monk line)
do
	reset()
	local cast = script("monk/palm_shockwave.lua")
	local monk = mk("player", 100, 100, {voc = 17})
	local t = mk("monster", 101, 100)
	local n1, n2 = mk("monster", 103, 100), mk("monster", 102, 102)
	local far = mk("monster", 104, 100)
	local ally = mk("player", 102, 100)
	eq(cast(monk, {}, false), false, "no target: refused")
	eq(cast(monk, {target = t}, false), true, "on the target next to it")
	local h = byTarget()
	ok(h[t] and h[t].min == BASE.min and h[t].max == BASE.max, "the target: an Ashen Fist")
	local pmn, pmx = packHit("shockwave")
	ok(h[n1] and h[n1].min == pmn and h[n1].max == pmx, "2 sqm from the target: the pack hit")
	ok(h[n2] and h[n2].min == pmn, "the other one in the wave")
	ok(not h[far] and not h[ally] and not h[monk], "not 3 sqm away, not a player, not the Monk")
	eq(chi, C.shockwave.chi, "builds chi like an Ashen Fist")
	eq(h[t].origin, ORIGIN_SPELL, "a Monk strike (spell origin)")
end

-- ------------------------------------------------------------------ Shadow Ricochet / Iron Chain
for _, case in ipairs({{"shadowfist/shadow_ricochet.lua", "ricochet", 18}, {"ironsage/iron_chain.lua", "chain", 19}}) do
	reset()
	local cast = script(case[1])
	local c = C[case[2]]
	local p = mk("player", 100, 100, {voc = case[3]})
	local t = mk("monster", 102, 100)
	local hop1 = mk("monster", 102 + c.reach, 100)
	local hop2 = mk("monster", 102 + 2 * c.reach, 100)
	local away = mk("monster", 102 + 4 * c.reach + 1, 100)
	local foe = mk("player", 102, 101)
	eq(cast(p, {target = t}, false), true, case[2] .. ": cast")
	local h = byTarget()
	local pmn = packHit(case[2])
	ok(h[t] and h[t].min == BASE.min, case[2] .. ": the target the plain hit")
	ok(h[hop1] and h[hop1].min == pmn and h[hop2] and h[hop2].min == pmn, case[2] .. ": the jumps the pack hit")
	ok(not h[away], case[2] .. ": out of reach of the last jump")
	ok(not h[foe], case[2] .. ": never jumps to a player")
	eq(#hits, 3, case[2] .. ": three hits")
	eq(chi, c.chi, case[2] .. ": chi once")
	-- a player target takes the plain hit; one it may not attack refuses the cast
	reset()
	p = mk("player", 100, 100, {voc = case[3]})
	local pt = mk("player", 101, 100)
	eq(cast(p, {target = pt}, false), true, case[2] .. ": on a player")
	eq(hits[1] and hits[1].min, BASE.min, case[2] .. ": a player target, the plain hit")
	pt.safe = true
	hits = {}
	eq(cast(p, {target = pt}, false), false, case[2] .. ": a player it may not attack")
	eq(#hits, 0, case[2] .. ": nothing hit")
end

-- ------------------------------------------------------------------ Bone Shrapnel
do
	reset()
	local cast = script("necromancer/bone_shrapnel.lua")
	local nec = mk("player", 100, 100, {voc = 20})
	local t = mk("monster", 105, 100)
	local n1, n2 = mk("monster", 106, 101), mk("monster", 104, 99)
	local far = mk("monster", 107, 100)
	local foe = mk("player", 106, 100)
	eq(cast(nec, {target = t}, false), true, "Bone Shrapnel: cast")
	local h = byTarget()
	local pmn, pmx = packHit("shrapnel")
	ok(h[t] and h[t].min == BASE.min and h[t].max == BASE.max, "the target: a Bone Spear")
	ok(h[n1] and h[n1].min == pmn and h[n1].max == pmx and h[n2] and h[n2].min == pmn, "around it: the pack hit")
	ok(not h[far] and not h[foe], "not 2 sqm away, not a player next to it")
end

-- ------------------------------------------------------------------ Sanctified Ground
do
	reset()
	local cast = script("templar/sanctified_ground.lua")
	local tp = mk("player", 100, 100, {voc = 23})
	local t = mk("monster", 101, 100)
	tp.target = t
	local n1 = mk("monster", 102, 102)
	local far = mk("monster", 103, 100)
	local foe = mk("player", 99, 100)
	local friend = mk("player", 100, 99, {safe = true})
	eq(cast(tp, {}, false), true, "Sanctified Ground: cast")
	eq(#queue, C.sanctified.pulses, "its pulses")
	runPulses(tp)
	local count = {}
	for _, h in ipairs(hits) do
		count[h.target] = (count[h.target] or 0) + 1
		eq(h.type, COMBAT_HOLYDAMAGE, "holy")
	end
	eq(count[t], C.sanctified.pulses, "the target every pulse")
	eq(count[n1], C.sanctified.pulses, "the pack every pulse")
	ok(not count[far] and not count[friend], "not 3 sqm away, not a player it may not attack")
	eq(count[foe], C.sanctified.pulses, "a player the PvP rules allow: hit")
	local h = byTarget()
	local pmn = math.floor(math.floor(BASE.min * C.sanctified.scale) * C.sanctified.pack)
	eq(h[t].min, math.floor(BASE.min * C.sanctified.scale), "the target: a third of a Radiant Smite a pulse")
	eq(h[n1].min, pmn, "the pack: pack x it")
	eq(h[foe].min, math.floor(BASE.min * C.sanctified.scale), "a player: never the pack share")
	-- a third of the Templar's Radiant Smite a pulse (ChaosTemplar.cfg.radiantSmite.scale[23])
	local core = readFile("data/scripts/chaos/templar_aura_core.lua") or ""
	local smite = tonumber(core:match("radiantSmite%s*=%s*{scale%s*=%s*{[^}]*%[23%]%s*=%s*([%d%.]+)"))
	ok(smite and math.abs(C.sanctified.scale * C.sanctified.pulses - smite) < 0.002, "3 pulses = one Radiant Smite")
	local sen = tonumber(core:match("radiantSmite%s*=%s*{scale%s*=%s*{[^}]*%[25%]%s*=%s*([%d%.]+)"))
	eq(C.shieldWave.scale, sen, "Shield Wave: a Radiant Smite of the Sentinel")
end

-- ------------------------------------------------------------------ Shield Wave
do
	reset()
	local cast = script("sentinel/shield_wave.lua")
	local s = mk("player", 100, 100, {voc = 25})
	local t = mk("monster", 101, 100)
	local inWave, inWave2 = mk("monster", 103, 101), mk("monster", 102, 99)
	local behind = mk("monster", 99, 100)
	local beyond = mk("monster", 104, 100)
	eq(cast(s, {target = t}, false), true, "Shield Wave: cast")
	local h = byTarget()
	local pmn = math.floor(math.floor(BASE.min * C.shieldWave.scale) * C.shieldWave.pack)
	eq(h[t] and h[t].min, math.floor(BASE.min * C.shieldWave.scale), "the target: a Radiant Smite")
	ok(h[inWave] and h[inWave].min == pmn and h[inWave2], "the wave: the pack hit")
	ok(not h[behind] and not h[beyond], "not behind, not past 3 rows")
end

-- ------------------------------------------------------------------ Fan of Knives
do
	reset()
	local cast = script("thief/fan_of_knives.lua")
	local th = mk("player", 100, 100, {voc = 11})
	local t = mk("monster", 102, 100)
	local others = {}
	for i = 1, 6 do
		others[i] = mk("monster", 100 + (i % 3) - 1, 103 + math.floor(i / 4))
	end
	local far = mk("monster", 105, 100)
	eq(cast(th, {target = t}, false), true, "Fan of Knives: cast")
	eq(#hits, 1 + C.fan.extra, "the target and 5 more")
	for _, h in ipairs(hits) do
		eq(h.origin, ORIGIN_RANGED, "ranged weapon strikes")
		ok(h.target ~= far, "not past its reach")
	end
	local l = 300 / 5
	local mn = (l + 6600 * C.fan.minK + C.fan.minBase) * C.fan.scale
	ok(math.abs(hits[1].min - mn) < 1e-6, "the target: a Shuriken Toss of the Thief")
	local toss = readFile("data/spells/chaos/thief/shuriken_toss.lua") or ""
	eq(tonumber(toss:match("local SCALE%s*=%s*{[^}]*%[11%]%s*=%s*([%d%.]+)")), C.fan.scale, "the Thief's Toss scale")
end
dofile = realDofile

-- ------------------------------------------------------------------ entries, model rows, supports
do
	local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
	local csv = readFile("data/spells/rotation_model.csv") or ""
	local SC = dofile("data/lib/chaos_supports_config.lua")
	local spells = {
		{194, "Palm Shockwave", "drai gal dhun", "monk/palm_shockwave.lua", {"Monk", "Shadowfist", "Iron Sage"}, "shockwave"},
		{195, "Shadow Ricochet", "kah umh dhun", "shadowfist/shadow_ricochet.lua", {"Shadowfist"}, "ricochet"},
		{196, "Iron Chain", "kah brak vinc", "ironsage/iron_chain.lua", {"Iron Sage"}, "chain"},
		{197, "Bone Shrapnel", "drai oss krak", "necromancer/bone_shrapnel.lua", {"Necromancer"}, "shrapnel"},
		{108, "Sanctified Ground", "drai sol sanct", "templar/sanctified_ground.lua", {"Templar"}, "sanctified"},
		{109, "Shield Wave", "drai sol aeg", "sentinel/shield_wave.lua", {"Sentinel"}, "shieldWave"},
		{136, "Fan of Knives", "drai vas nyx shur", "thief/fan_of_knives.lua", {"Thief"}, "fan"},
	}
	local ids, words = {}, {}
	for a in xml:gmatch("<instant ([^>]*)>") do
		local id, w = a:match('spellid="(%d+)"'), a:match('words="([^"]+)"')
		ids[id] = (ids[id] or 0) + 1
		words[w] = (words[w] or 0) + 1
	end
	for _, s in ipairs(spells) do
		local e = xml:match('<instant [^>]*name="' .. s[2] .. '"[^>]*>.-</instant>') or ""
		eq(e:match('spellid="(%d+)"'), tostring(s[1]), s[2] .. " id")
		eq(e:match('words="([^"]+)"'), s[3], s[2] .. " words")
		eq(e:match('group="(%a+)"'), "attack", s[2] .. ": attack group")
		eq(e:match('groupcooldown="(%d+)"'), "2000", s[2] .. ": the 2 s attack group")
		eq(e:match('script="chaos/([^"]+)"'), s[4], s[2] .. " script")
		ok(readFile("data/spells/chaos/" .. s[4]), s[2] .. " script file")
		local n = 0
		for _ in e:gmatch("<vocation ") do n = n + 1 end
		eq(n, #s[5], s[2] .. ": its classes only")
		for _, v in ipairs(s[5]) do
			ok(e:find('<vocation name="' .. v .. '" />', 1, true), s[2] .. " for the " .. v)
		end
		eq(ids[tostring(s[1])], 1, s[2] .. ": id used once")
		eq(words[s[3]], 1, s[2] .. ": words used once")
		local t5 = tonumber(csv:match("\n" .. s[3]:gsub("%-", "%%-") .. ',' .. s[2] .. ',"[^"]*",([%d%.]+),'))
		eq(t5, 1 + 4 * C[s[6]].pack, s[2] .. ": rotation model 1 + 4 x pack")
		eq(SC.kindOverride[s[1]], "area", s[2] .. ": the supports' area kind")
	end
	ok(C.sanctified.radius == 2 and C.shockwave.radius == 2, "the 5-dummy pack is in reach")
end

if failures > 0 then
	print(failures .. " failure(s) of " .. checks)
	os.exit(1)
end
print("packtools_test: " .. checks .. " checks, ok")
