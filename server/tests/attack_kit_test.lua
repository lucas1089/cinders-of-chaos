-- Run from the server/ folder: luajit tests/attack_kit_test.lua && lua5.3 tests/attack_kit_test.lua (CI runs both)
-- The attack kit (owner 2026-10-23: every class has the same number of attack spells; docs/CLASSES.md "Attack spell
-- parity"): the 51 spells of attack_kit_config.lua against spells_chaos.xml and rotation_model.csv, the pure rules of
-- attack_kit_core.lua (damage, shapes) and the cast of _attackkit.lua on a mocked engine.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks, fails = 0, 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		fails = fails + 1
		print("FAIL " .. (m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end
local function near(a, b, tol, m)
	checks = checks + 1
	if math.abs(a - b) > tol * math.max(1, math.abs(b)) then
		fails = fails + 1
		print("FAIL " .. (m or "") .. ": " .. tostring(a) .. " vs " .. tostring(b))
	end
end
local function ok(c, m)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. (m or ""))
	end
end

local realDofile = dofile
dofile("data/scripts/chaos/attack_kit_core.lua")
dofile("data/scripts/chaos/attack_kit_config.lua")
local K, cfg = ChaosAttackKitCore, ChaosAttackKit.cfg

local function readAll(path)
	local f = assert(io.open(path, "r"), path)
	local s = f:read("*a")
	f:close()
	return s
end

-- ------------------------------------------------------------------------------------------------- the config
local problems = K.validate(cfg)
eq(#problems, 0, "config problems: " .. table.concat(problems, "; "))
local keys = {}
for k in pairs(cfg.spells) do keys[#keys + 1] = k end
table.sort(keys)
eq(#keys, 51, "51 kit spells")
eq(#cfg.order, 51, "the order lists every spell")
local ordered = {}
for _, k in ipairs(cfg.order) do ordered[k] = true; ok(cfg.spells[k], "order key " .. k) end
for _, k in ipairs(keys) do ok(ordered[k], k .. " is in the order") end

-- every class line gets what it needs: the per-vocation kit counts
-- (+1 everywhere since the level 500 line quest spells, phase 2 of the line spell quests)
local COUNT = {Warrior = 4, Juggernaut = 4, Berserker = 3, Ranger = 4, Deadeye = 3, Beastmaster = 5, Illusionist = 5,
	Mystic = 2, Elementalist = 2, Thief = 7, Ninja = 5, Samurai = 6, Monk = 8, Shadowfist = 5, ["Iron Sage"] = 6,
	Necromancer = 8, Lich = 7, ["Bone Lord"] = 9, Templar = 9, Inquisitor = 8, Sentinel = 9}
do -- 119 class slots: the shortfall to 12 attack spells per class (docs/CLASSES.md "Attack spell parity")
	local total = 0
	for _, v in pairs(COUNT) do total = total + v end
	eq(total, 119, "the kit fills 119 class slots")
end
local byVoc = K.byVocation(cfg)
for voc, want in pairs(COUNT) do
	eq(byVoc[voc] and #byVoc[voc] or 0, want, voc .. " kit spells")
end
for voc in pairs(byVoc) do ok(COUNT[voc], voc .. " is a known vocation") end

-- the effect names exist (an unknown name quietly falls back to a stock effect at runtime)
do
	dofile("data/lib/chaos_fx.lua")
	dofile("data/lib/chaos_vfx.lua")
	dofile("data/lib/chaos_vfx_art.lua")
	dofile("data/lib/chaos_pack41_fx_ids.lua")
	PACK41 = ChaosVfxMissile
	local dirs = {"n", "ne", "e", "se", "s", "sw", "w", "nw"}
	for _, key in ipairs(keys) do
		local s = cfg.spells[key]
		if s.fx then ok(ChaosFx[s.fx] ~= nil, key .. ": ChaosFx has " .. s.fx) end
		if s.shot then
			ok(ChaosFxMissile[s.shot] ~= nil or ChaosVfxMissile[s.shot] ~= nil, key .. ": a missile named " .. s.shot)
		end
		if s.pshot then
			ok(s.pshot:match("^proj_") ~= nil and PACK41[s.pshot] ~= nil, key .. ": a pair 41 / 42 missile named " .. s.pshot)
		end
		for voc, name in pairs(s.pshotBy or {}) do
			ok(PACK41[name] ~= nil, key .. ": " .. voc .. " missile " .. name .. " exists")
		end
		if s.vfx then
			local found = ChaosVfx[s.vfx] ~= nil
			for _, d in ipairs(dirs) do
				if ChaosVfx[s.vfx .. "_" .. d] ~= nil then found = true end
			end
			ok(found, key .. ": ChaosVfx has " .. s.vfx)
		end
		if s.hitFx then
			ok(s.hitFx:match("^CONST_ME_[A-Z_]+$") ~= nil, key .. ": hitFx " .. s.hitFx .. " is a magic effect constant")
		end
	end
end

-- an attack spell is never a Support "buff": each kit spell has its kind in the supports' override table
do
	local SC = dofile("data/lib/chaos_supports_config.lua")
	for _, key in ipairs(keys) do
		local s = cfg.spells[key]
		local want = (s.shape == "single" or s.shape == "dot") and "single" or "area"
		eq(SC.kindOverride[s.id], want, key .. ": the supports' kind of spell " .. s.id)
	end
end

-- ------------------------------------------------------------------------------- the XML (the server's list)
local xml = readAll("data/spells/chaos/spells_chaos.xml"):gsub("<!%-%-.-%-%->", "")
local inXml = {}
for tag, body in xml:gmatch("(<instant[^>]*>)(.-)</instant>") do
	local id = tonumber(tag:match('spellid="(%d+)"'))
	local vocs = {}
	for v in body:gmatch('<vocation name="([^"]+)"') do vocs[#vocs + 1] = v end
	table.sort(vocs)
	inXml[id] = {tag = tag, vocs = vocs}
end
for _, key in ipairs(keys) do
	local s = cfg.spells[key]
	local x = inXml[s.id]
	ok(x, key .. ": spellid " .. s.id .. " is in spells_chaos.xml")
	if x then
		local t = x.tag
		eq(t:match('group="([^"]+)"'), "attack", key .. " group")
		eq(t:match('name="([^"]+)"'), s.name, key .. " name")
		eq(t:match('words="([^"]+)"'), s.words, key .. " words")
		eq(tonumber(t:match('level="(%d+)"')), s.level, key .. " level")
		eq(tonumber(t:match('mana="(%d+)"')), s.mana, key .. " mana")
		eq(tonumber(t:match('groupcooldown="(%d+)"')), 2000, key .. " group cooldown")
		local cd = tonumber(t:match('%scooldown="(%d+)"'))
		-- 2, 4, 6 s, then one second a rung up to 13 s (O176, rotation_sim.py LADDER_COOLDOWNS)
		ok(cd and cd >= 2000 and cd <= 13000 and cd % 1000 == 0 and (cd > 6000 or cd % 2000 == 0), key .. " cooldown on the ladder")
		-- a line spell quest spell (quest = 1..3) is taught by its quest only
		eq(t:match('needlearn="(%d)"'), s.quest and "1" or "0", key .. " needlearn")
		if s.quest then
			eq(s.level, ({500, 800, 1200})[s.quest], key .. " quest level")
			if s.quest == 1 then eq(tonumber(t:match('%scooldown="(%d+)"')), 13000, key .. " quest 1 cooldown") end
		end
		if s.shape == "around" then
			eq(t:match('selftarget="1"') ~= nil, true, key .. " is self-targeted")
			eq(t:match('needtarget') == nil, true, key .. " needs no target")
		else
			eq(t:match('needtarget="1"') ~= nil, true, key .. " needs a target")
			eq(tonumber(t:match('range="(%d+)"')), s.range, key .. " range")
		end
		local want = {}
		for _, v in ipairs(s.vocations) do want[#want + 1] = v end
		table.sort(want)
		eq(table.concat(x.vocs, ","), table.concat(want, ","), key .. " vocations")
		-- the script exists and calls the kit with this key
		local script = t:match('script="([^"]+)"')
		local f = io.open("data/spells/" .. script, "r")
		ok(f, key .. " script " .. tostring(script))
		if f then
			local src = f:read("*a")
			f:close()
			ok(src:find("AttackKit.cast('" .. key .. "'", 1, true), key .. " script casts its key")
			ok(src:match("^%-%- " .. s.name:gsub("%p", "%%%0") .. ": "), key .. " description comment")
		end
	end
end

-- ----------------------------------------------------------------------- the rotation model (balance numbers)
local function evaluator(expr)
	local env = {avg = function(a, b) return (a + b) / 2 end, math = math, OFFHAND = 1}
	local src = "return " .. expr
	local f
	if setfenv then
		f = assert(loadstring(src))
		setfenv(f, env)
	else
		f = assert(load(src, "expr", "t", env))
	end
	return function(level, ml, power)
		env.l, env.L, env.ML, env.P = level / 5, level, ml, power
		return f()
	end
end
local model = {}
for line in readAll("data/spells/rotation_model.csv"):gmatch("[^\r\n]+") do
	local words, name, expr, t5, flags = line:match('^(.-),([^,]-),"(.-)",(%d+),([^,]*),')
	if name then model[name] = {words = words, expr = expr, t5 = tonumber(t5), flags = flags} end
end
for _, key in ipairs(keys) do
	local s = cfg.spells[key]
	local row = model[s.name]
	ok(row, key .. " has a row in rotation_model.csv")
	if row then
		eq(row.words, s.words, key .. " model words")
		if s.chi then eq(row.flags, "chi1", key .. " builder flag") end
		if s.finisher then eq(row.flags, "chi", key .. " finisher flag") end
		local f = evaluator(row.expr)
		for _, p in ipairs({{300, 100, 6050}, {600, 120, 12000}, {1000, 150, 20000}, {120, 40, 900}}) do
			near(f(p[1], p[2], p[3]), K.total(s, p[1], p[2], p[3]), 0.012, key .. " model vs core at level " .. p[1])
		end
	end
end

-- ---------------------------------------------------------------------------------------- the damage rules
do
	local s = {pMin = 0.1, pMax = 0.2, mMin = 2, mMax = 3, bMin = 10, bMax = 20, scale = 1, shape = "single"}
	local lo, hi = K.range(s, 100, 50, 1000)
	eq(lo, 20 + 100 + 100 + 10, "min of a hit")
	eq(hi, 20 + 200 + 150 + 20, "max of a hit")
	s.scale = 0.5
	lo, hi = K.range(s, 100, 50, 1000)
	eq(lo, 115, "scale halves the min")
	eq(hi, 195, "scale halves the max")
	s.shape, s.ticks = "dot", 5
	eq(K.total(s, 100, 50, 1000), 155 * 5, "a dot adds up its ticks")
	eq(K.average(s, 100, 50, 1000), 155, "average of a hit")
end

-- ----------------------------------------------------------------------------------------------- the shapes
do
	local o = {x = 100, y = 100, z = 7}
	eq(#K.tiles({shape = "circle", radius = 1}, o), 9, "circle 1 is the 3x3")
	eq(#K.tiles({shape = "circle", radius = 2}, o), 21, "circle 2 is the 5x5 without its corners")
	eq(#K.tiles({shape = "around", radius = 1}, o, nil, true), 8, "around 1 leaves the caster's tile")
	eq(#K.tiles({shape = "around", radius = 2}, o, nil, true), 20, "around 2 leaves the caster's tile")
	eq(#K.tiles({shape = "single"}, o), 1, "single")
	local line = K.tiles({shape = "line", length = 4}, o, 1) -- east
	eq(#line, 4, "line of 4")
	eq(line[4][1], 104, "the line ends 4 tiles east")
	eq(line[4][2], 100, "the line stays in its row")
	local diag = K.tiles({shape = "line", length = 3}, o, 5) -- southeast
	eq(diag[3][1] .. ":" .. diag[3][2], "103:103", "a diagonal line")
	local wave = K.tiles({shape = "wave", depth = 3, halfWidth = 2}, o, 0) -- north
	eq(#wave, 1 + 3 + 5, "a wave widens each row")
	local narrow = K.tiles({shape = "wave", depth = 2, halfWidth = 1}, o, 0)
	eq(#narrow, 1 + 3, "a short wave")
	ok(K.contains({shape = "wave", depth = 2, halfWidth = 1}, o, 0, {x = 99, y = 98}), "the wave reaches its far corner")
	ok(not K.contains({shape = "wave", depth = 2, halfWidth = 1}, o, 0, {x = 99, y = 99}), "the first row is one tile wide")
	ok(not K.contains({shape = "wave", depth = 2, halfWidth = 1}, o, 0, {x = 100, y = 102}), "a wave goes the other way not")
	local dw = K.tiles({shape = "wave", depth = 2, halfWidth = 1}, o, 5)
	ok(#dw >= 5, "a diagonal wave is a wedge")
	eq(K.dirTo(o, {x = 105, y = 100}), 1, "east")
	eq(K.dirTo(o, {x = 100, y = 95}), 0, "north")
	eq(K.dirTo(o, {x = 103, y = 103}), 5, "southeast")
	eq(K.dirTo(o, o), 2, "same tile")
	eq(K.distance(o, {x = 103, y = 98, z = 7}), 3, "distance")
	eq(K.distance(o, {x = 103, y = 98, z = 8}), nil, "another floor")
end

-- validation catches the usual mistakes
do
	local function bad(mutate, word)
		local copy = {spells = {}}
		for k, s in pairs(cfg.spells) do
			local c = {}
			for kk, vv in pairs(s) do c[kk] = vv end
			copy.spells[k] = c
		end
		mutate(copy.spells)
		local found = false
		for _, p in ipairs(K.validate(copy)) do if p:find(word, 1, true) then found = true end end
		ok(found, "validate finds " .. word)
	end
	bad(function(sp) sp.gorehook.shape = "cone" end, "unknown shape")
	bad(function(sp) sp.gorehook.id = sp.riftcleaver.id end, "also used by")
	bad(function(sp) sp.gorehook.vocations = {} end, "no vocations")
	bad(function(sp) sp.gorehook.pMin = 5 end, "above its max")
	bad(function(sp) sp.riftcleaver.length = 0 end, "needs a length")
	bad(function(sp) sp.gorehook.id = 300 end, "id must be")
	bad(function(sp) sp.hollowknuckle.finisher = true end, "either builds chi")
	bad(function(sp) sp.gorehook.chi = 1 end, "monk school")
end

-- ------------------------------------------------------------------------------------------ the cast (mocked)
local world, calls, cancels, chiLog, nextId
local function reset()
	world, calls, cancels, chiLog, nextId = {}, {}, {}, {}, 100
end
reset()

local function creature(x, y, props)
	nextId = nextId + 1
	local c = {id = nextId, pos = {x = x, y = y, z = 7}, health = 1000, monster = true}
	for k, v in pairs(props or {}) do c[k] = v end
	function c:getId() return self.id end
	function c:getPosition() return Position(self.pos) end
	function c:getHealth() return self.health end
	function c:isPlayer() return self.player == true end
	function c:getPlayer() return self.player and self or nil end
	world[c.id] = c
	return c
end
function Position(x, y, z)
	if type(x) == "table" then return {x = x.x, y = x.y, z = x.z} end
	return {x = x, y = y, z = z}
end
function Creature(id) return world[id] end

local function player(props)
	local p = creature(100, 100, {player = true, monster = false, level = 300, ml = 100, chi = 0})
	for k, v in pairs(props or {}) do p[k] = v end
	function p:getLevel() return self.level end
	function p:getMagicLevel() return self.ml end
	function p:getEffectiveSkillLevel() return 110 end
	return p
end

ChaosSpell = {
	cancel = function(pl, msg) cancels[#cancels + 1] = msg; return false end,
	targetOf = function(v) return v and v.target end,
	canAttack = function(c, t) return t ~= c and t.health > 0 and not t.safe end,
	isEnemy = function(c, t) return t ~= c and t.monster == true and not t.summon end,
	spectators = function(pos, r)
		local out = {}
		for _, c in pairs(world) do
			if math.abs(c.pos.x - pos.x) <= r and math.abs(c.pos.y - pos.y) <= r then out[#out + 1] = c end
		end
		table.sort(out, function(a, b) return a.id < b.id end)
		return out
	end,
	meleeSkillLevel = function() return 110 end,
	meleeAttack = function() return 55 end,
	distanceAttack = function() return 60 end,
	bladePower = function() return 6050 end,
	shurikenPower = function() return 5000 end,
	fx = function(pos, name) calls[#calls + 1] = {kind = "fx", name = name} end,
	vfx = function(pos, name) calls[#calls + 1] = {kind = "vfx", name = name}; return true end,
	vfxDir = function() return false end,
	vshoot = function(a, b, name) calls[#calls + 1] = {kind = "shot", name = name} end,
	pshoot = function(a, b, pname, vname, name) calls[#calls + 1] = {kind = "shot", name = pname} end,
	pulse = function(casterId, count, interval, fn)
		for step = 1, count do
			local caster = Creature(casterId)
			if not caster or fn(caster, step) == false then return end
		end
	end,
	weaponStrike = function(caster, target, lo, hi, effect, origin)
		calls[#calls + 1] = {kind = "weapon", target = target, lo = lo, hi = hi, origin = origin}
		return true
	end
}
function doTargetCombat(caster, target, ctype, lo, hi, effect, origin)
	calls[#calls + 1] = {kind = "spell", target = target, ctype = ctype, lo = -lo, hi = -hi, origin = origin}
	return true
end
TemplarSpell = {
	power = function() return 6050 end,
	values = function(pl, a, b, c, d, e, f)
		local l = pl:getLevel() / 5
		return l + 6050 * a + pl.ml * c + e, l + 6050 * b + pl.ml * d + f
	end,
	holyStrike = function(pl, t, lo, hi) calls[#calls + 1] = {kind = "holy", target = t, lo = lo, hi = hi}; return true end
}
ChaosNecro = {
	values = function(pl, f)
		local l = pl:getLevel() / 5
		return math.floor((l + pl.ml * f.mlMin + f.baseMin) * f.scale), math.floor((l + pl.ml * f.mlMax + f.baseMax) * f.scale)
	end,
	damage = function(pl, t, ctype, lo, hi) calls[#calls + 1] = {kind = "necro", target = t, lo = lo, hi = hi}; return 50 end
}
NecroSpell = {
	dot = function(casterId, targetId, key, ticks, tickMs, lo, hi)
		calls[#calls + 1] = {kind = "necrodot", target = Creature(targetId), ticks = ticks, lo = lo, hi = hi}
		return true
	end
}
ChaosMonk = {
	strikeValues = function(level, power, f, scale)
		local l = level / 5
		return (l + power * f[1] + f[2]) * scale, (l + power * f[3] + f[4]) * scale
	end,
	finisherScale = function(chi) return 0.3 + 0.14 * chi end,
	addChi = function(pl, amount) pl.chi = math.min(5, pl.chi + amount); chiLog[#chiLog + 1] = amount end
}
MonkSpell = {
	power = function() return 5225 end,
	finisher = function(pl)
		if pl.chi < 1 then return nil end
		local spent = pl.chi
		pl.chi = 0
		return spent
	end
}

dofile = function(path)
	if path:find("^data/spells/scripts/chaos/") then return end -- the spell helpers: mocked above
	return realDofile(path)
end
realDofile("data/spells/chaos/_attackkit.lua")
local A = AttackKit -- dofile stays mocked: the cast loads the school helpers on demand

local function calc(key, pl)
	local s = cfg.spells[key]
	return K.range(s, pl.level, pl.ml, ({melee = 6050, distance = 6600, magic = 0, blade = 6050, shuriken = 5000,
		monk = 5225, templar = 6050})[s.power])
end
local function hits(kind)
	local out = {}
	for _, c in ipairs(calls) do if c.kind == (kind or "spell") then out[#out + 1] = c end end
	return out
end

-- a magic single target (Phantom Needles): ORIGIN_SPELL, the energy type, values from level and magic level
do
	reset()
	local p = player()
	local t = creature(103, 100)
	ok(A.cast("phantomneedles", p, {target = t}), "Phantom Needles casts")
	local h = hits()
	eq(#h, 1, "one hit")
	eq(h[1].target, t, "on the target")
	eq(h[1].origin, ORIGIN_SPELL, "a spell hit (the class factor applies)")
	eq(h[1].ctype, COMBAT_ENERGYDAMAGE, "energy damage")
	local lo, hi = calc("phantomneedles", p)
	eq(h[1].lo, math.floor(lo), "min of the hit")
	eq(h[1].hi, math.floor(hi), "max of the hit")
	eq(#hits("shot"), 1, "a missile flies")
end

-- a melee spell needs the target next to the caster (Gutting Slash is a weapon strike of the Thief line)
do
	reset()
	local p = player()
	local far = creature(103, 100)
	eq(A.cast("guttingslash", p, {target = far}), false, "too far")
	eq(cancels[#cancels], RETURNVALUE_TOOFARAWAY, "the cancel message")
	eq(#calls, 0, "nothing was hit")
	local near1 = creature(101, 101)
	ok(A.cast("guttingslash", p, {target = near1}), "next to the caster it casts")
	local w = hits("weapon")
	eq(#w, 1, "one weapon strike")
	eq(w[1].origin, ORIGIN_MELEE, "a melee weapon hit (stealth ambush, Poison Blades)")
	eq(#hits("shot"), 0, "a melee spell throws nothing")
	-- no target, own summon or safe player
	eq(A.cast("guttingslash", p, {}), false, "no target")
	local safe = creature(101, 100, {safe = true})
	eq(A.cast("guttingslash", p, {target = safe}), false, "a target that may not be attacked")
	eq(cancels[#cancels], RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER, "the PvP message")
end

-- a circle at the target (Arrowstorm, radius 2) hits the monsters in it, never the caster's summon or a far one
do
	reset()
	local p = player()
	local t = creature(105, 100)
	local a = creature(106, 101)
	local b = creature(104, 99)
	local out = creature(108, 100)
	local pet = creature(105, 101, {summon = true})
	local corner = creature(107, 102) -- the cut corner of a radius 2 circle
	ok(A.cast("arrowstorm", p, {target = t}), "Arrowstorm casts")
	local seen = {}
	for _, h in ipairs(hits("weapon")) do seen[h.target.id] = true end
	for _, h in ipairs(hits()) do seen[h.target.id] = true end
	ok(seen[t.id] and seen[a.id] and seen[b.id], "the target and its neighbours are hit")
	ok(not seen[out.id], "a far monster is not")
	ok(not seen[pet.id], "a summon is not")
	ok(not seen[corner.id], "the corner of the circle is not")
	eq(#hits(), 3, "three hits")
end

-- a burst around the caster (Mirror Shards, radius 1) leaves the caster alone
do
	reset()
	local p = player()
	local a = creature(101, 100)
	local b = creature(99, 99)
	local out = creature(102, 100)
	ok(A.cast("mirrorshards", p, {}), "Mirror Shards casts without a target")
	local seen = {}
	for _, h in ipairs(hits()) do seen[h.target.id] = true end
	ok(seen[a.id] and seen[b.id], "the neighbours are hit")
	ok(not seen[out.id] and not seen[p.id], "not the far monster, not the caster")
end

-- a line (Rift Cleaver, 4 tiles) goes from the caster toward the target
do
	reset()
	local p = player()
	local t = creature(102, 100)
	local inLine = creature(104, 100)
	local beyond = creature(105, 100)
	local side = creature(103, 101)
	ok(A.cast("riftcleaver", p, {target = t}), "Rift Cleaver casts")
	local seen = {}
	for _, h in ipairs(hits()) do seen[h.target.id] = true end
	ok(seen[t.id] and seen[inLine.id], "the line hits the tiles in it")
	ok(not seen[beyond.id] and not seen[side.id], "not past its length or beside it")
end

-- a wave (Wraithwind, necro) goes through the Necromancer's own damage
do
	reset()
	local p = player()
	local t = creature(100, 98)
	local row2 = creature(100, 97)
	local wide = creature(101, 97)
	ok(A.cast("wraithwind", p, {target = t}), "Wraithwind casts")
	local h = hits("necro")
	ok(#h >= 2, "dealt as the caster through ChaosNecro.damage")
	eq(#hits(), 0, "not as a raw spell hit")
end

-- a damage over time (Gorehook, 5 ticks) hits once per tick; a dead host stops it
do
	reset()
	local p = player()
	local t = creature(101, 100)
	ok(A.cast("gorehook", p, {target = t}), "Gorehook casts")
	eq(#hits(), 5, "five ticks")
	reset()
	p = player()
	t = creature(101, 100)
	local oldHit = A.hit
	local ticks = 0
	A.hit = function(...) ticks = ticks + 1; if ticks == 2 then t.health = 0 end; return oldHit(...) end
	A.cast("gorehook", p, {target = t})
	A.hit = oldHit
	eq(ticks, 2, "the dot stops when the host dies")
	-- the necro line's dot is the line's own (Blightbrand)
	reset()
	p = player()
	t = creature(104, 100)
	ok(A.cast("blightbrand", p, {target = t}), "Blightbrand casts")
	local d = hits("necrodot")
	eq(#d, 1, "one dot")
	eq(d[1].ticks, 6, "six ticks")
end

-- the Templar line's strikes go through its holy strike
do
	reset()
	local p = player()
	local t = creature(101, 100)
	ok(A.cast("hallowedcut", p, {target = t}), "Hallowed Cut casts")
	local h = hits("holy")
	eq(#h, 1, "one holy strike")
	local s = cfg.spells.hallowedcut
	local lo = 60 + 6050 * s.pMin + 100 * s.mMin + s.bMin
	near(h[1].lo, lo * (s.scale or 1), 0.001, "Templar min")
end

-- the Monk line: a builder gives chi, a finisher spends it and needs some
do
	reset()
	local p = player()
	local t = creature(101, 100)
	ok(A.cast("hollowknuckle", p, {target = t}), "Hollow Knuckle casts")
	eq(p.chi, 1, "a builder gives its chi")
	eq(#hits(), 1, "and strikes")
	p.chi = 0
	reset()
	p = player()
	t = creature(101, 100)
	eq(A.cast("skysplitter", p, {target = t}), false, "a finisher without chi does nothing")
	eq(#hits(), 0, "no hit without chi")
	p.chi = 5
	ok(A.cast("skysplitter", p, {target = t}), "with 5 chi it casts")
	eq(p.chi, 0, "and spends all of it")
	local s = cfg.spells.skysplitter
	local h = hits()
	eq(#h, 1, "one strike")
	local base = 60 + 5225 * s.pMin + s.bMin
	near(h[1].lo, base * (s.scale or 1) * (0.3 + 0.14 * 5), 0.001, "a 5-chi finisher")
	-- the area builder
	reset()
	p = player()
	local a = creature(101, 101)
	ok(A.cast("quakingstomp", p, {}), "Quaking Stomp casts")
	eq(p.chi, cfg.spells.quakingstomp.chi, "the area builder gives chi too")
	eq(#hits(), 1, "hits the neighbour")
end

-- every kit spell casts cleanly against a crowd, on a mocked engine
for _, key in ipairs(keys) do
	reset()
	local p = player()
	p.chi = 5
	local t = creature(101, 100)
	for dx = -2, 6 do for dy = -2, 2 do if not (dx == 0 and dy == 0) and not (dx == 1 and dy == 0) then creature(100 + dx, 100 + dy) end end end
	local good, err = pcall(A.cast, key, p, {target = t})
	ok(good, key .. " casts without an error: " .. tostring(err))
	ok(#calls > 0, key .. " does something")
end

if fails > 0 then
	error("attack_kit_test: " .. fails .. " of " .. checks .. " checks failed")
end
print("attack_kit_test: " .. checks .. " checks passed")
