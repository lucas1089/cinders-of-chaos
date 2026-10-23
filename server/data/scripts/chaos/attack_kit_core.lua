-- attack_kit_core.lua: pure rules of the attack kit (ChaosAttackKitCore): the damage of a kit spell, the tiles of its
-- shapes and the validation of the config (attack_kit_config.lua). No engine calls, so tests/attack_kit_test.lua runs it
-- against a mocked engine. The cast itself: data/spells/chaos/_attackkit.lua.
--
-- Owner 2026-10-23: every class has the same number of attack spells. The kit holds the 37 spells that fill the
-- shortfall (docs/CLASSES.md "Attack spell parity").

ChaosAttackKitCore = ChaosAttackKitCore or {}
local K = ChaosAttackKitCore

local floor, max, abs = math.floor, math.max, math.abs

K.SHAPES = {single = true, dot = true, circle = true, around = true, wave = true, line = true}
-- how the hit is dealt and what scales it
K.SCHOOLS = {melee = true, distance = true, magic = true, monk = true, blade = true, shuriken = true, spell = true,
	templar = true, necro = true}
-- what the hit scales with (the power term P: skill x attack, or the magic level)
K.POWERS = {melee = true, distance = true, magic = true, monk = true, blade = true, shuriken = true}

-- the unit step of the engine's directions (NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3, SOUTHWEST = 4, SOUTHEAST = 5,
-- NORTHWEST = 6, NORTHEAST = 7)
K.STEP = {[0] = {0, -1}, [1] = {1, 0}, [2] = {0, 1}, [3] = {-1, 0}, [4] = {-1, 1}, [5] = {1, 1}, [6] = {-1, -1}, [7] = {1, -1}}

-- positive min, max of one hit (a DoT: of one tick): (level / 5 + power x pMin + magic level x mMin + bMin) x scale
-- .. the same with the max terms. `power` is skill x attack, `ml` the magic level.
function K.range(spec, level, ml, power)
	local l = (level or 0) / 5
	local k = spec.scale or 1
	local lo = (l + (power or 0) * spec.pMin + (ml or 0) * spec.mMin + spec.bMin) * k
	local hi = (l + (power or 0) * spec.pMax + (ml or 0) * spec.mMax + spec.bMax) * k
	return lo, hi
end

-- average of a hit
function K.average(spec, level, ml, power)
	local lo, hi = K.range(spec, level, ml, power)
	return (lo + hi) / 2
end

-- the whole damage of one cast on one target: a DoT adds up its ticks
function K.total(spec, level, ml, power)
	local avg = K.average(spec, level, ml, power)
	if spec.shape == "dot" then
		return avg * spec.ticks
	end
	return avg
end

-- ------------------------------------------------------------------------------------------------------- shapes
-- the offsets (dx, dy) of a disc of `radius` around a tile: the corners of the square are cut for radius 2 and up, the
-- way the engine's circle areas are (radius 1 keeps the 3x3 square)
local function disc(radius)
	local list = {}
	for dy = -radius, radius do
		for dx = -radius, radius do
			if dx * dx + dy * dy <= radius * radius + radius then
				list[#list + 1] = {dx, dy}
			end
		end
	end
	return list
end

-- {x, y} of every tile a shape covers. `origin` is the centre of a circle / the caster of the others, `dir` the
-- direction of a wave or line (a number of K.STEP), `skipCentre` leaves the centre out (the caster's own tile).
function K.tiles(spec, origin, dir, skipCentre)
	local out = {}
	local shape = spec.shape
	if shape == "single" or shape == "dot" then
		out[1] = {origin.x, origin.y}
	elseif shape == "circle" or shape == "around" then
		for _, o in ipairs(disc(spec.radius or 1)) do
			if not (skipCentre and o[1] == 0 and o[2] == 0) then
				out[#out + 1] = {origin.x + o[1], origin.y + o[2]}
			end
		end
	elseif shape == "line" then
		local s = K.STEP[dir] or K.STEP[2]
		for d = 1, spec.length or 1 do
			out[#out + 1] = {origin.x + s[1] * d, origin.y + s[2] * d}
		end
	elseif shape == "wave" then
		local s = K.STEP[dir] or K.STEP[2]
		local depth, half = spec.depth or 2, spec.halfWidth or 1
		if s[1] == 0 or s[2] == 0 then
			-- straight: the wave widens by one tile each side per row, up to halfWidth
			for d = 1, depth do
				local w = math.min(half, d - 1)
				for a = -w, w do
					if s[1] == 0 then
						out[#out + 1] = {origin.x + a, origin.y + s[2] * d}
					else
						out[#out + 1] = {origin.x + s[1] * d, origin.y + a}
					end
				end
			end
		else
			-- diagonal: the tiles of the quadrant that are within depth rows
			for a = 0, depth do
				for b = 0, depth do
					if a + b >= 1 and a + b <= depth + 1 then
						out[#out + 1] = {origin.x + s[1] * a, origin.y + s[2] * b}
					end
				end
			end
		end
	end
	return out
end

-- a set {["x:y"] = true} of the tiles of a shape, for quick membership tests
function K.tileSet(spec, origin, dir, skipCentre)
	local set = {}
	for _, t in ipairs(K.tiles(spec, origin, dir, skipCentre)) do
		set[t[1] .. ":" .. t[2]] = true
	end
	return set
end

function K.contains(spec, origin, dir, pos, skipCentre)
	return K.tileSet(spec, origin, dir, skipCentre)[pos.x .. ":" .. pos.y] == true
end

-- the direction (a K.STEP key) from one tile to another, the same rule as ChaosSpell.dirTo
function K.dirTo(from, to)
	local dx, dy = to.x - from.x, to.y - from.y
	if dx == 0 and dy == 0 then
		return 2
	end
	local sx = dx > 0 and 1 or (dx < 0 and -1 or 0)
	local sy = dy > 0 and 1 or (dy < 0 and -1 or 0)
	if abs(dx) >= 2 * abs(dy) then
		sy = 0
	elseif abs(dy) >= 2 * abs(dx) then
		sx = 0
	end
	for dir, s in pairs(K.STEP) do
		if s[1] == sx and s[2] == sy then
			return dir
		end
	end
	return 2
end

-- Chebyshev distance of two tiles on one floor, nil on different floors
function K.distance(a, b)
	if a.z ~= b.z then
		return nil
	end
	return max(abs(a.x - b.x), abs(a.y - b.y))
end

-- ------------------------------------------------------------------------------------------------ validation
-- the problems of a config table (an empty list when it is sound): every spell has a known shape, school and power,
-- a unique id and words, vocations, a sane min <= max, and the area fields its shape needs
function K.validate(cfg)
	local bad = {}
	local ids, words, names = {}, {}, {}
	local function add(key, msg)
		bad[#bad + 1] = key .. ": " .. msg
	end
	for key, s in pairs(cfg.spells) do
		if not K.SHAPES[s.shape] then
			add(key, "unknown shape " .. tostring(s.shape))
		end
		if not K.SCHOOLS[s.school] then
			add(key, "unknown school " .. tostring(s.school))
		end
		if not K.POWERS[s.power] then
			add(key, "unknown power " .. tostring(s.power))
		end
		if type(s.id) ~= "number" or s.id < 1 or s.id > 255 or s.id ~= floor(s.id) then
			add(key, "id must be a whole number 1..255")
		elseif ids[s.id] then
			add(key, "id " .. s.id .. " also used by " .. ids[s.id])
		else
			ids[s.id] = key
		end
		if words[s.words or ""] then
			add(key, "words also used by " .. words[s.words])
		else
			words[s.words or ""] = key
		end
		if names[s.name or ""] then
			add(key, "name also used by " .. names[s.name])
		else
			names[s.name or ""] = key
		end
		if not s.vocations or #s.vocations == 0 then
			add(key, "no vocations")
		end
		if (s.level or 0) < 1 or (s.mana or 0) < 1 then
			add(key, "level and mana must be set")
		end
		if s.pMin > s.pMax or s.mMin > s.mMax or s.bMin > s.bMax then
			add(key, "a min term is above its max term")
		end
		if (s.scale or 1) <= 0 then
			add(key, "scale must be above 0")
		end
		if s.shape == "dot" and ((s.ticks or 0) < 1 or (s.tickMs or 0) < 100) then
			add(key, "a dot needs ticks and tickMs")
		end
		if (s.shape == "circle" or s.shape == "around") and (s.radius or 0) < 1 then
			add(key, "an area needs a radius")
		end
		if s.shape == "line" and (s.length or 0) < 1 then
			add(key, "a line needs a length")
		end
		if s.shape == "wave" and ((s.depth or 0) < 1 or (s.halfWidth or 0) < 0) then
			add(key, "a wave needs depth and halfWidth")
		end
		if s.chi and s.finisher then
			add(key, "a spell either builds chi or spends it")
		end
		if (s.chi or s.finisher) and s.school ~= "monk" then
			add(key, "chi belongs to the monk school")
		end
		if s.shape ~= "around" and (s.range or 0) < 1 then
			add(key, "a targeted spell needs a range")
		end
	end
	table.sort(bad)
	return bad
end

-- the vocation names that have `key` in their attack list, per vocation: {["Monk"] = {key, key, ...}}
function K.byVocation(cfg)
	local out = {}
	for key, s in pairs(cfg.spells) do
		for _, v in ipairs(s.vocations) do
			out[v] = out[v] or {}
			out[v][#out[v] + 1] = key
		end
	end
	for _, list in pairs(out) do
		table.sort(list)
	end
	return out
end

return K
