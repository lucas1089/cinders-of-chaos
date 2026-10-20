-- Run from the server/ folder: luajit tests/blades_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The Thief line's area strikes (2026-10-15, pack farming; data/spells/chaos/_blades.lua): Blade Flurry (73, Thief,
-- Ninja, Samurai) and Iaido Sweep (74, Samurai). The pure parts (ranges, class scales, the sweep's tiles), the casts on
-- a mocked engine (who is hit, with what), the two spell scripts, the spell entries and the data that reads them
-- (rotation_model.csv, the supports' kinds, the class effects).
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
ORIGIN_NONE, ORIGIN_MELEE, ORIGIN_RANGED, ORIGIN_SPELL = 0, 3, 4, 2
CONST_ME_DRAWBLOOD, CONST_ME_HITAREA, CONST_ME_POFF = 1, 2, 3
RETURNVALUE_YOUCANONLYUSEITONCREATURES, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER = 10, 11
NORTH, EAST, SOUTH, WEST, SOUTHEAST = 0, 1, 2, 3, 6

local creatures, strikes, effects, cancels = {}, {}, {}, {}
local nextId = 1
local function mk(kind, x, y, opts)
	opts = opts or {}
	local c = {id = nextId, kind = kind, pos = {x = x, y = y, z = opts.z or 7}, level = opts.level or 300,
		voc = opts.voc or 11, master = opts.master, health = 1000}
	nextId = nextId + 1
	function c:getId() return self.id end
	function c:getPosition() return self.pos end
	function c:getLevel() return self.level end
	function c:getVocation() local v = self.voc return {getId = function() return v end} end
	function c:isMonster() return self.kind == "monster" end
	function c:getPlayer() return self.kind == "player" and self or nil end
	function c:getMaster() return self.master end
	function c:getHealth() return self.health end
	creatures[#creatures + 1] = c
	return c
end

local POWER = 110 * 55 -- sword 110 x a blade of attack 55 (the C4 level 300 gear)
ChaosSupportsSpell = {cast = function() return nil end}
ChaosSpell = {
	bladePower = function() return POWER end,
	enemiesAround = function(caster, pos, radius)
		local out = {}
		for _, c in ipairs(creatures) do
			if c ~= caster and c:isMonster() and not (c.master and c.master.kind == "player") and c.pos.z == pos.z
					and math.max(math.abs(c.pos.x - pos.x), math.abs(c.pos.y - pos.y)) <= radius then
				out[#out + 1] = c
			end
		end
		return out
	end,
	weaponStrike = function(caster, target, min, max, effect, origin)
		strikes[#strikes + 1] = {caster = caster, target = target, min = min, max = max, effect = effect, origin = origin}
		return true
	end,
	vfxOr = function(pos, vname, name, fallback) effects[#effects + 1] = {kind = "vfxOr", name = vname, pos = pos} end,
	vfxDir = function(pos, base, dir) effects[#effects + 1] = {kind = "vfxDir", name = base, pos = pos, dir = dir}; return true end,
	fx = function(pos, name) effects[#effects + 1] = {kind = "fx", name = name, pos = pos} end,
	dirTo = function(a, b) return (b.x > a.x and b.y > a.y) and SOUTHEAST or (b.x > a.x and EAST or SOUTH) end,
	targetOf = function(variant) return variant and variant.target end,
	canAttack = function(caster, target) return target ~= caster and not target.safe end,
	cancel = function(player, msg) cancels[#cancels + 1] = msg; return false end,
}
local function reset()
	creatures, strikes, effects, cancels = {}, {}, {}, {}
end

dofile("data/spells/chaos/_blades.lua")
local B = ChaosBlades
ok(B and B.cfg and B.cfg.flurry and B.cfg.sweep, "ChaosBlades loaded")

-- ------------------------------------------------------------------ ranges and scales
do
	local f = B.cfg.flurry
	local mn, mx = B.flurryRange(300, POWER, 11)
	eq(mn, math.floor((60 + POWER * 0.050 + 20) * 1.33), "Thief 300: min")
	eq(mx, math.floor((60 + POWER * 0.080 + 40) * 1.33), "Thief 300: max")
	eq(B.flurryScale(11, 60), 1.33, "Thief: one scale")
	eq(B.flurryScale(12, 150), f.early[12].scale, "Ninja below 180: the early scale")
	eq(B.flurryScale(12, 180), f.scale[12], "Ninja from 180")
	eq(B.flurryScale(13, 119), f.early[13].scale, "Samurai below 120: the early scale")
	eq(B.flurryScale(13, 120), f.scale[13], "Samurai from 120")
	eq(B.flurryScale(99, 300), f.defaultScale, "another vocation: the default")
	local a, b = B.flurryRange(1000, 140 * 65, 11)
	ok(a > mn and b > mx and a < b, "grows with level and power")
	eq(select(1, B.flurryRange(0, 0, 11)), math.floor(20 * 1.33), "the base part alone")

	-- one hit on a lone target matches a Shuriken Toss of the class (same formula, its class scale; the Ninja's off-hand
	-- strike adds half of each hit), so single-target damage stays where it was: within 10%
	local toss = readFile("data/spells/chaos/thief/shuriken_toss.lua") or ""
	local tscale = {}
	for v, k in (toss:match("local SCALE%s*=%s*(%b{})") or ""):gmatch("%[(%d+)%]%s*=%s*([%d%.]+)") do
		tscale[tonumber(v)] = tonumber(k)
	end
	local tearly = {}
	for v, below, k in (toss:match("local EARLY%s*=%s*(%b{})") or ""):gmatch("%[(%d+)%]%s*=%s*{below%s*=%s*(%d+),%s*scale%s*=%s*([%d%.]+)}") do
		tearly[tonumber(v)] = {below = tonumber(below), scale = tonumber(k)}
	end
	ok(tscale[11] and tscale[12] and tscale[13], "Shuriken Toss scales read")
	local OFFHAND = {[12] = 1.5}
	for _, v in ipairs({11, 12, 13}) do
		for _, lv in ipairs({60, 150, 300, 1000}) do
			local t = (tearly[v] and lv < tearly[v].below) and tearly[v].scale or tscale[v]
			local fl = B.flurryScale(v, lv) * (OFFHAND[v] or 1)
			ok(math.abs(fl / t - 1) <= 0.10, "Blade Flurry ~ Shuriken Toss per hit: voc " .. v .. " level " .. lv ..
				" (" .. fl .. " / " .. t .. ")")
		end
	end

	-- Iaido Sweep: about half of an Iaijutsu per monster (Iaijutsu: (l + P x 0.20-0.30 + 60-120))
	local smin, smax = B.sweepRange(300, POWER)
	local imin, imax = 60 + POWER * 0.20 + 60, 60 + POWER * 0.30 + 120
	local ratio = (smin + smax) / (imin + imax)
	ok(ratio > 0.3 and ratio < 0.55, "Iaido Sweep: about half an Iaijutsu x its scale (" .. ratio .. ")")
	eq(smin, math.floor((60 + POWER * 0.10 + 30) * B.cfg.sweep.scale), "Iaido Sweep 300: min")
end

-- ------------------------------------------------------------------ the sweep's tiles
do
	local sx, sy = B.stepTowards({x = 10, y = 10}, {x = 12, y = 10})
	ok(sx == 1 and sy == 0, "east")
	sx, sy = B.stepTowards({x = 10, y = 10}, {x = 12, y = 11})
	ok(sx == 1 and sy == 0, "mostly east: east")
	sx, sy = B.stepTowards({x = 10, y = 10}, {x = 11, y = 11})
	ok(sx == 1 and sy == 1, "south-east")
	sx, sy = B.stepTowards({x = 10, y = 10}, {x = 10, y = 8})
	ok(sx == 0 and sy == -1, "north")
	sx, sy = B.stepTowards({x = 10, y = 10}, {x = 10, y = 10})
	ok(sx == 0 and sy == 1, "the same tile: south")

	local east = B.sweepTiles(1, 0)
	eq(#east, 6, "east: 3 x 2 tiles")
	local set = {}
	for _, t in ipairs(east) do set[t.x .. "," .. t.y] = true end
	for _, k in ipairs({"1,-1", "1,0", "1,1", "2,-1", "2,0", "2,1"}) do ok(set[k], "east has " .. k) end
	eq(#B.sweepTiles(0, -1), 6, "north: 6 tiles")
	eq(#B.sweepTiles(-1, 0), 6, "west: 6 tiles")
	local se = B.sweepTiles(1, 1)
	eq(#se, 7, "south-east: the 7 nearest tiles of the quarter")
	set = {}
	for _, t in ipairs(se) do set[t.x .. "," .. t.y] = true end
	ok(set["1,1"] and set["2,0"] and set["0,2"] and set["2,1"] and set["1,2"], "south-east tiles")
	ok(not set["2,2"], "the far corner is left out")
	local o = {x = 10, y = 10, z = 7}
	ok(not B.inSweep(o, 1, 0, {x = 10, y = 10, z = 7}), "not the caster's tile")
	ok(not B.inSweep(o, 1, 0, {x = 9, y = 10, z = 7}), "not behind")
	ok(not B.inSweep(o, 1, 0, {x = 11, y = 10, z = 6}), "not another floor")
	ok(not B.inSweep(o, 1, 0, {x = 13, y = 10, z = 7}), "not past the depth")
	ok(not B.inSweep(o, 1, 0, {x = 11, y = 12, z = 7}), "not wider than 3")
end

-- ------------------------------------------------------------------ Blade Flurry on the mocked engine
do
	reset()
	local thief = mk("player", 100, 100, {voc = 11})
	local around = {}
	for _, d in ipairs({{1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}}) do
		around[#around + 1] = mk("monster", 100 + d[1], 100 + d[2])
	end
	local twoAway = mk("monster", 102, 101)
	local far = mk("monster", 103, 100)
	local below = mk("monster", 101, 100, {z = 8})
	local other = mk("player", 99, 100)
	other.kind = "player"
	local pet = mk("monster", 100, 101)
	pet.master = other
	eq(B.cfg.flurry.radius, 2, "the 5x5 square around the caster (since the second pass)")
	eq(B.flurry(thief, "whirlwind"), 9, "the 8 monsters next to it and the one 2 sqm away are struck")
	eq(#strikes, 9, "9 strikes")
	local mn, mx = B.flurryRange(300, POWER, 11)
	local hit = {}
	for _, s in ipairs(strikes) do
		hit[s.target] = true
		eq(s.origin, ORIGIN_MELEE, "a melee weapon strike")
		ok(s.min == mn and s.max == mx and s.caster == thief, "the class's range")
	end
	for _, m in ipairs(around) do ok(hit[m], "an adjacent monster is struck") end
	ok(hit[twoAway], "2 sqm away: struck")
	ok(not hit[far] and not hit[below] and not hit[other] and not hit[pet], "not 3 sqm away, another floor, a player or a pet")
	eq(effects[1] and effects[1].name, "whirlwind", "the spin at the caster")

	-- a Samurai's flurry uses its own scale
	reset()
	local sam = mk("player", 100, 100, {voc = 13})
	mk("monster", 101, 100)
	B.flurry(sam, "whirlwind")
	local smn = B.flurryRange(300, POWER, 13)
	eq(strikes[1] and strikes[1].min, smn, "Samurai: its scale")

	-- the spell script (installed path data/spells/scripts/chaos/ in the server; here data/spells/chaos/)
	reset()
	local realDofile = dofile
	dofile = function(path)
		if path:find("_common.lua", 1, true) or path:find("_blades.lua", 1, true) then
			return nil -- ChaosSpell is the mock above, ChaosBlades is loaded
		end
		return realDofile(path)
	end
	realDofile("data/spells/chaos/thief/blade_flurry.lua")
	local ninja = mk("player", 50, 50, {voc = 12})
	mk("monster", 51, 50)
	mk("monster", 49, 49)
	eq(onCastSpell(ninja, {}, false), true, "Blade Flurry casts without a target")
	eq(#strikes, 2, "the script strikes the monsters around")
	eq(strikes[1].min, (B.flurryRange(300, POWER, 12)), "Ninja: its scale")
	eq(effects[1] and effects[1].name, "whirlwind", "the script names its spin effect (a class effect may stand in)")

	-- ------------------------------------------------------------------ Iaido Sweep
	reset()
	realDofile("data/spells/chaos/samurai/iaido_sweep.lua")
	sam = mk("player", 100, 100, {voc = 13})
	local target = mk("monster", 101, 100)
	local inCut = mk("monster", 102, 99)
	local inCut2 = mk("monster", 101, 101)
	local behind = mk("monster", 99, 100)
	local side = mk("monster", 100, 101)
	local tooFar = mk("monster", 103, 100)
	local bystander = mk("player", 102, 100)
	eq(onCastSpell(sam, {}, false), false, "no target: refused")
	eq(cancels[1], RETURNVALUE_YOUCANONLYUSEITONCREATURES, "the creature message")
	eq(onCastSpell(sam, {target = sam}, false), false, "itself: refused")
	eq(onCastSpell(sam, {target = target}, false), true, "on a monster in reach")
	local hitS = {}
	for _, s in ipairs(strikes) do
		hitS[s.target] = (hitS[s.target] or 0) + 1
		eq(s.origin, ORIGIN_MELEE, "sweep: a melee weapon strike")
	end
	eq(hitS[target], 1, "the target once")
	ok(hitS[inCut] and hitS[inCut2], "the monsters in the cut")
	ok(not hitS[behind] and not hitS[side] and not hitS[tooFar], "not behind, beside or past the cut")
	ok(not hitS[bystander], "a player in the cut who is not the target is not hit")
	eq(#strikes, 3, "three strikes")
	local smin2, smax2 = B.sweepRange(300, POWER)
	ok(strikes[1].min == smin2 and strikes[1].max == smax2, "the target: the sweep's range")
	for i = 2, #strikes do
		ok(strikes[i].min == math.floor(smin2 * B.cfg.sweep.pack) and strikes[i].max == math.floor(smax2 * B.cfg.sweep.pack),
			"a monster of the pack: pack x the hit")
	end
	ok(B.cfg.sweep.pack > 1, "the pack takes more than the target")
	eq(effects[1] and effects[1].kind, "vfxDir", "a directional cut")
	eq(effects[1] and effects[1].name, "heavy_cleave", "the heavy cleave")
	ok(effects[1] and effects[1].pos.x == 101 and effects[1].pos.y == 100, "on the first tile of the cut")
	-- a player target is struck (PvP rules: ChaosSpell.canAttack)
	reset()
	sam = mk("player", 100, 100, {voc = 13})
	local foe = mk("player", 101, 100)
	eq(onCastSpell(sam, {target = foe}, false), true, "on a player target")
	eq(#strikes, 1, "the player target is struck")
	eq(strikes[1].min, smin2, "a player target: the plain hit, never the pack share")
	foe.safe = true
	strikes = {}
	eq(onCastSpell(sam, {target = foe}, false), false, "a player it may not attack: refused")
	eq(#strikes, 0, "nothing struck")
	dofile = realDofile
end

-- ------------------------------------------------------------------ the spell entries and the data that reads them
do
	local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
	local function entry(name)
		return xml:match('<instant [^>]*name="' .. name .. '"[^>]*>.-</instant>')
	end
	local fl, sw = entry("Blade Flurry"), entry("Iaido Sweep")
	ok(fl and sw, "both spells in spells_chaos.xml")
	fl, sw = fl or "", sw or ""
	eq(fl:match('spellid="(%d+)"'), "73", "Blade Flurry id")
	eq(fl:match('words="([^"]+)"'), "drai vas kaen", "Blade Flurry words")
	eq(fl:match('group="(%a+)"'), "attack", "Blade Flurry: attack group")
	eq(fl:match('level="(%d+)"'), "50", "Blade Flurry level")
	eq(fl:match(' cooldown="(%d+)"'), "10000", "Blade Flurry cooldown (the cooldown ladder, 2026-10-20: was 8 s)")
	eq(fl:match('groupcooldown="(%d+)"'), "2000", "Blade Flurry group cooldown")
	ok(fl:find('selftarget="1"', 1, true), "Blade Flurry: around the caster")
	for _, v in ipairs({"Thief", "Ninja", "Samurai"}) do
		ok(fl:find('<vocation name="' .. v .. '" />', 1, true), "Blade Flurry for the " .. v)
	end
	eq(sw:match('spellid="(%d+)"'), "74", "Iaido Sweep id")
	eq(sw:match('words="([^"]+)"'), "drai gal kaen", "Iaido Sweep words")
	eq(sw:match('level="(%d+)"'), "200", "Iaido Sweep level")
	eq(sw:match(' cooldown="(%d+)"'), "8000", "Iaido Sweep cooldown (second pass)")
	eq(sw:match('range="(%d+)"'), tostring(B.cfg.sweep.reach), "Iaido Sweep reach = its range")
	ok(sw:find('needtarget="1"', 1, true), "Iaido Sweep needs a target")
	ok(sw:find('<vocation name="Samurai" />', 1, true) and not sw:find('"Thief"', 1, true), "Iaido Sweep: Samurai only")
	for _, e in ipairs({fl, sw}) do
		local script = e:match('script="chaos/([^"]+)"')
		ok(script and readFile("data/spells/chaos/" .. script), "script file " .. tostring(script))
	end
	local ids, words = {}, {}
	for a in xml:gmatch("<instant ([^>]*)>") do
		local id, w = a:match('spellid="(%d+)"'), a:match('words="([^"]+)"')
		ids[id] = (ids[id] or 0) + 1
		words[w] = (words[w] or 0) + 1
	end
	eq(ids["73"], 1, "id 73 used once"); eq(ids["74"], 1, "id 74 used once")
	eq(words["drai vas kaen"], 1, "words used once"); eq(words["drai gal kaen"], 1, "words used once")

	local csv = readFile("data/spells/rotation_model.csv") or ""
	ok(csv:find("\ndrai vas kaen,Blade Flurry,", 1, true), "rotation_model.csv: Blade Flurry")
	ok(csv:find("\ndrai gal kaen,Iaido Sweep,", 1, true), "rotation_model.csv: Iaido Sweep")
	-- the model's 5-dummy pack: Blade Flurry hits all 5 (the 5x5 square), Iaido Sweep 1 + 4 x pack
	eq(tonumber(csv:match('\ndrai vas kaen,Blade Flurry,"[^"]*",([%d%.]+),')), 5, "Blade Flurry: 5 of the dummies")
	eq(tonumber(csv:match('\ndrai gal kaen,Iaido Sweep,"[^"]*",([%d%.]+),')), 1 + 4 * B.cfg.sweep.pack, "Iaido Sweep: 1 + 4 x pack")
	local SC = dofile("data/lib/chaos_supports_config.lua")
	eq(SC.kindOverride[73], "area", "supports: Blade Flurry is an area spell")
	eq(SC.kindOverride[74], "area", "supports: Iaido Sweep is an area spell")
	dofile("data/lib/chaos_class_fx.lua")
	eq(ChaosClassFx.pick("ninja", 73, "whirlwind"), "ninja_vanish", "the Ninja's flurry")
	eq(ChaosClassFx.pick("samurai", 73, "whirlwind"), "samurai_parry", "the Samurai's flurry")
	eq(ChaosClassFx.pick("thief", 73, "whirlwind"), nil, "the Thief's: the default spin")
end

if failures > 0 then
	print(failures .. " failure(s) of " .. checks)
	os.exit(1)
end
print("blades_test: " .. checks .. " checks, ok")
