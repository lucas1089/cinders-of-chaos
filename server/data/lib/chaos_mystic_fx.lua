-- Mystic line effects (Tier A of the 2026-10-16 effect pass; owner: "I found the effects of the Mystic spells very
-- poor"): helpers the Mystic, Elementalist and Illusionist spells use to send the larger effects of the pair (pack,
-- class, large and pair 27 sets, server/data/spells/README_FX.md "Mystic line effects") and to time an impact to the
-- missile's arrival. Every effect name is optional: when the pair or a switch lacks it, nothing is sent and the
-- caller keeps its old effect (the 1x1 tile effects of an area stay when no large effect covers it).
-- Also wraps two base-server stock spells (Bewitching Hex, Arcane Ripple): server/tools/patch_mystic_stock_fx.py
-- adds a load and a wrap of onCastSpell to their scripts.
-- Pair 29 (Tier B, data/lib/chaos_pack29_fx.lua, switch ChaosPack29Fx.PAIR29): send, later and shoot take the casting
-- spell's pair 29 name (M.alt), the stock spells theirs (M.stockName); off, the names here.
-- Pure parts (flightMs, ring, inCone, stockPlan) are tested by tests/mystic_fx_test.lua. Lua 5.1 / LuaJIT / 5.3.

ChaosMysticFx = ChaosMysticFx or {}
local M = ChaosMysticFx

-- ms a missile flies from one tile to another in the client: 150 * sqrt(distance in tiles), as the client's missile
-- path does; 0 on the same tile
function M.flightMs(from, to)
	if not from or not to then
		return 0
	end
	local dx, dy = to.x - from.x, to.y - from.y
	local d = math.sqrt(dx * dx + dy * dy)
	if d <= 0 then
		return 0
	end
	return math.floor(150 * math.sqrt(d))
end

-- `n` tiles round `centre` at radius `r` (whole tiles, deterministic angles starting at `phase` radians)
function M.ring(centre, r, n, phase)
	local out = {}
	n = n or 4
	phase = phase or 0.4
	for k = 0, n - 1 do
		local a = phase + 2 * math.pi * k / n
		local x = centre.x + math.floor(r * math.cos(a) + 0.5)
		local y = centre.y + math.floor(r * math.sin(a) + 0.5)
		out[#out + 1] = {x = x, y = y, z = centre.z}
	end
	return out
end

-- direction steps (NORTH 0, EAST 1, SOUTH 2, WEST 3, the diagonals 4..7 as the engine numbers them)
local STEP = {[0] = {0, -1}, [1] = {1, 0}, [2] = {0, 1}, [3] = {-1, 0}, [4] = {-1, 1}, [5] = {1, 1}, [6] = {-1, -1},
	[7] = {1, -1}}

-- is `pos` inside the cone a wave spell of length `len` covers from `origin` facing `dir` (forward distance 1..len,
-- sideways at most half the forward distance + 1; the shape of the stock waves)
function M.inCone(origin, dir, pos, len)
	local s = STEP[dir]
	if not s or not origin or not pos or pos.z ~= origin.z then
		return false
	end
	local dx, dy = pos.x - origin.x, pos.y - origin.y
	local fwd, side
	if s[1] ~= 0 and s[2] ~= 0 then
		fwd = math.min(dx * s[1], dy * s[2])
		side = math.abs(dx * s[1] - dy * s[2])
	else
		fwd = dx * s[1] + dy * s[2]
		side = math.abs(dx * s[2] - dy * s[1])
	end
	return fwd >= 1 and fwd <= len and side <= math.floor(fwd / 2) + 1
end

-- -------------------------------------------------------------------------------------------- sending
local LIBS = {
	{"ChaosBigFx", "data/lib/chaos_big_fx.lua"},
	{"ChaosClassFx", "data/lib/chaos_class_fx.lua"},
	{"ChaosPack27Fx", "data/lib/chaos_pack27_fx.lua"},
	{"ChaosPackFx", "data/lib/chaos_pack_fx.lua"},
	{"ChaosPack29Fx", "data/lib/chaos_pack29_fx.lua"},
}

-- every effect set whose switch is on has its ids in ChaosVfx (each lib loads its ids file once)
function M.ensure()
	if not ChaosVfx and dofile then
		pcall(dofile, "data/lib/chaos_vfx.lua")
	end
	for _, l in ipairs(LIBS) do
		local lib = _G[l[1]]
		if not lib and dofile then
			pcall(dofile, l[2])
			lib = _G[l[1]]
		end
		if lib and lib.live then
			pcall(lib.live)
		end
	end
end

function M.known(name)
	M.ensure()
	return type(name) == "string" and ChaosVfx ~= nil and ChaosVfx[name] ~= nil and Vfx ~= nil
end

-- the pair 29 name (data/lib/chaos_pack29_fx.lua, switch ChaosPack29Fx.PAIR29) of an effect (kind "send") or missile
-- this helper sends for the casting spell, else the same name
function M.alt(kind, name)
	local Q, W = ChaosPack29Fx, ChaosSupportsSpell
	if type(name) ~= "string" or not Q or not Q.PAIR29 or not Q.swapFor or not W or not W.cast then
		return name
	end
	local pid, spellId = W.cast()
	local ok, alt = pcall(Q.swapFor, spellId, kind, name)
	return pid and ok and alt or name
end

-- send exactly effect `name` at pos (no large or class swap: the names here are the final ones; a large or class swap
-- of the casting spell would otherwise turn a ring burst into another large effect; only the casting spell's pair 29
-- name, M.alt); true when sent
function M.send(pos, name)
	M.ensure()
	name = M.alt("send", name)
	if not pos or not M.known(name) then
		return false
	end
	return Vfx(Position(pos.x, pos.y, pos.z), name) and true or false
end

-- the first of `names` that is sent; its name or nil
function M.sendFirst(pos, names)
	for _, n in ipairs(names) do
		if M.send(pos, n) then
			return n
		end
	end
	return nil
end

-- send `name` at pos after `ms` (0: now)
function M.later(ms, pos, name)
	if not pos then
		return
	end
	local p = {x = pos.x, y = pos.y, z = pos.z}
	if not ms or ms <= 0 or not addEvent then
		return M.send(p, name)
	end
	addEvent(function() M.send(p, name) end, ms)
	return true
end

-- a missile (pack or pair 27 name) from -> to; true when sent
function M.shoot(from, to, name)
	M.ensure()
	name = M.alt("missile", name)
	if not from or not to or not VfxShoot or not ChaosVfxMissile or not ChaosVfxMissile[name] then
		return false
	end
	return VfxShoot(Position(from.x, from.y, from.z), Position(to.x, to.y, to.z), name) and true or false
end

-- the per-tile effect of an area: none when a large effect covers the area, else the old one
function M.tileFx(covered, old)
	if covered then
		return CONST_ME_NONE or 0
	end
	return old
end

-- -------------------------------------------------------------------------------------------- stock spells
-- the base-server scripts patched by server/tools/patch_mystic_stock_fx.py: what each gets
M.STOCK = {
	bewitching_hex = {
		missile = "arcane_bolt", impact = "arcane_hit", tick = "tick_curse", ticks = 4, tickMs = 2000,
		-- the effect and missile ids the base script sets, replaced (CONST_ME_NONE / CONST_ANI_NONE) when the new
		-- ones are in the pair
		effect = 218, distance = 84,
	},
	arcane_ripple = {mouth = "arcane_hit", hit = "px674_arcane", len = 6, hitMs = 300},
}

-- the pair 29 name of a stock spell's effect or missile (ChaosPack29Fx.stock, switch on and in the pair), else `name`
function M.stockName(key, kind, name)
	local Q = ChaosPack29Fx
	local alt = Q and Q.PAIR29 and Q.stockFor and Q.stockFor(key, kind, name)
	return alt or name
end

-- the plan of a stock spell's sends (pure): list of {ms, kind, name, at}; at = "caster", "front", "target", "hits"
function M.stockPlan(key, flight)
	local s = M.STOCK[key]
	if not s then
		return {}
	end
	local plan = {}
	if key == "bewitching_hex" then
		plan[#plan + 1] = {0, "missile", M.stockName(key, "missile", s.missile), "target"}
		plan[#plan + 1] = {flight or 0, "effect", s.impact, "target"}
		for i = 1, s.ticks do
			plan[#plan + 1] = {(flight or 0) + i * s.tickMs, "effect", M.stockName(key, "fx", s.tick), "target"}
		end
	elseif key == "arcane_ripple" then
		plan[#plan + 1] = {0, "effect", s.mouth, "front"}
		plan[#plan + 1] = {s.hitMs, "effect", s.hit, "hits"}
	end
	return plan
end

-- the id a stock script sets for its own effect: none when the replacement is in the pair
function M.stockEffect(key, id)
	local s = M.STOCK[key]
	if s and s.impact and M.known(s.impact) then
		return CONST_ME_NONE or 0
	end
	return id
end

function M.stockMissile(key, id)
	local s = M.STOCK[key]
	if s and s.missile and ChaosVfxMissile and ChaosVfxMissile[s.missile] and VfxShoot then
		return CONST_ANI_NONE or 0
	end
	return id
end

local function monstersInCone(caster, len)
	local out = {}
	if not Game or not Game.getSpectators then
		return out
	end
	local origin = caster:getPosition()
	local dir = caster:getDirection()
	for _, c in ipairs(Game.getSpectators(origin, false, false, len, len, len, len) or {}) do
		if c ~= caster and c:isMonster() and M.inCone(origin, dir, c:getPosition(), len) then
			out[#out + 1] = c:getPosition()
		end
	end
	return out
end

local function targetOf(creature, variant)
	local t = variant and variant.getNumber and Creature(variant:getNumber())
	if not t and creature.getTarget then
		t = creature:getTarget()
	end
	return t
end

-- the base script's onCastSpell, wrapped: the new sends go out after a successful cast
function M.wrapStock(key, fn)
	if type(fn) ~= "function" or not M.STOCK[key] then
		return fn
	end
	return function(creature, variant, ...)
		local done = fn(creature, variant, ...)
		if not done then
			return done
		end
		local ok, err = pcall(function()
			local from = creature:getPosition()
			if key == "bewitching_hex" then
				local target = targetOf(creature, variant)
				if not target then
					return
				end
				local to = target:getPosition()
				local plan = M.stockPlan(key, M.flightMs(from, to))
				local tid = target:getId()
				for _, step in ipairs(plan) do
					if step[2] == "missile" then
						M.shoot(from, to, step[3])
					else
						local name, ms = step[3], step[1]
						local function fire()
							local t = Creature(tid)
							if t then
								M.send(t:getPosition(), name)
							end
						end
						if ms <= 0 or not addEvent then
							fire()
						else
							addEvent(fire, ms)
						end
					end
				end
			elseif key == "arcane_ripple" then
				local s = M.STOCK[key]
				local d = STEP[creature:getDirection()] or {0, 1}
				M.send({x = from.x + d[1], y = from.y + d[2], z = from.z}, s.mouth)
				for _, p in ipairs(monstersInCone(creature, s.len)) do
					M.later(s.hitMs, p, s.hit)
				end
			end
		end)
		if not ok and print then
			print("[ChaosMysticFx] " .. key .. ": " .. tostring(err))
		end
		return done
	end
end
