-- ChaosFxOwner (O567; server/README.md "Effect owner marks"): which map effects are the caster's own, so the client's Options >
-- Effects can draw "my effects" and "other players' effects" at their own opacity (client game_effectopacity; base patch 0202).
--
-- The client cannot tell whose spell drew an effect: the 10.98 effect packet has no source. Here the spell side says so. While a
-- player's spell runs (the cast context of ChaosSupportsSpell: the script itself and every addEvent callback it started, so the
-- later waves of a big spell too), Position:sendMagicEffect and Position:sendDistanceEffect note the effect (kind, tile, id) in the
-- caster's buffer. One dispatcher tick later the buffer goes to that player as ONE small message on ChaosOpcodes.fxOwner:
--     marks {b = {x, y, z}, m = {kind, dx, dy, id, kind, dx, dy, id, ...}}    kind 0 effect, 1 missile; dx, dy from the base b
-- and the client gives those effects (found by tile and id, a tile or two around it) and missiles the own alpha. Nothing else
-- changes: the packets to everybody stay as they were, this is a second message to the caster alone.
-- Cheap by design: only for a player whose client said `hello {need = 1}` (its two sliders differ; the storage C.STORAGE is 1
-- while it is, the rest of the time -1), so with the default 100 / 100 an effect costs a cast-context lookup and a table lookup (the
-- storage is read once a second per player). At most C.cfg.maxMarks marks per message (the rest stay "other"), a repeated mark is sent once,
-- a mark of another floor or farther than 127 tiles from the base is dropped.
-- Not marked, so drawn with the "other players'" opacity: effects the engine sends itself (hit splashes, engine area effects),
-- the effects of monsters and of other players, and anything a revscript sends outside a cast. A script that sends effects of
-- a player outside the spell context can wrap them in ChaosFxOwner.as(player, function() ... end).
-- Pure parts (C.add, C.payload, C.key) and the glue are tested by tests/fx_owner_test.lua. Lua 5.1 / LuaJIT / 5.3.

ChaosFxOwner = ChaosFxOwner or {}
local C = ChaosFxOwner

C.OPCODE = 164          -- ChaosOpcodes.fxOwner (chaos_constants.lua)
C.STORAGE = 7103120     -- Chaos.storage.fxOwner: 1 while the player's client wants marks
C.KIND_EFFECT = 0
C.KIND_MISSILE = 1
C.cfg = C.cfg or {
	maxMarks = 300,     -- marks of one message (the client reads 400)
	maxOffset = 127,    -- |dx|, |dy| from the base
}

C.bufs = C.bufs or {}   -- player id -> the buffer of this tick
C.wish = C.wish or {}   -- player id -> {v = wants marks, t = os.time() of the read}: the storage is read once a second
C.forced = nil          -- player id set by C.as
C.installed = C.installed or false

local rawAddEvent = addEvent

-- ---------------------------------------------------------------- pure parts

-- the key of a mark, so a repeat of it is sent once
function C.key(kind, dx, dy, id)
	return kind .. ":" .. dx .. ":" .. dy .. ":" .. id
end

-- an empty buffer based at x, y, z (the first tile noted)
function C.newBuffer(x, y, z)
	return {x = x, y = y, z = z, m = {}, n = 0, seen = {}}
end

-- adds a mark; true when it was added. A tile of another floor, one too far from the base, a bad id, a repeat and a full buffer
-- are refused.
function C.add(buf, kind, x, y, z, id)
	if type(buf) ~= "table" or buf.n >= C.cfg.maxMarks then
		return false
	end
	id = tonumber(id)
	if not id or id < 1 or id > 65535 or id ~= math.floor(id) then
		return false
	end
	if z ~= buf.z then
		return false
	end
	local dx, dy = x - buf.x, y - buf.y
	local far = C.cfg.maxOffset
	if dx > far or dx < -far or dy > far or dy < -far then
		return false
	end
	local key = C.key(kind, dx, dy, id)
	if buf.seen[key] then
		return false
	end
	buf.seen[key] = true
	local m = buf.m
	m[#m + 1] = kind
	m[#m + 1] = dx
	m[#m + 1] = dy
	m[#m + 1] = id
	buf.n = buf.n + 1
	return true
end

-- the message data of a buffer, nil when it holds nothing
function C.payload(buf)
	if type(buf) ~= "table" or buf.n == 0 then
		return nil
	end
	return {b = {buf.x, buf.y, buf.z}, m = buf.m}
end

-- ---------------------------------------------------------------- who casts

-- player id of the spell running now (the spell side's cast context), nil outside a player's cast
local function spellCaster()
	local W = ChaosSupportsSpell
	if W and W.cast then
		local pid = W.cast()
		return pid
	end
	return nil
end

-- the player id the effects sent now belong to, nil when none
function C.owner()
	return C.forced or spellCaster()
end

-- runs fn(...) with the effects it sends noted as the player's own (a player object or an id); nested runs restore the outer one
function C.as(player, fn, ...)
	local pid = player
	if type(player) ~= "number" then
		local ok, id = pcall(function() return player:getId() end)
		pid = ok and id or nil
	end
	local outer = C.forced
	C.forced = pid
	local ok, err = pcall(fn, ...)
	C.forced = outer
	if not ok then
		error(err, 0)
	end
end

-- ---------------------------------------------------------------- the player's wish

-- does the player's client want marks (its storage is 1). A function so a test can replace it.
function C.wants(pid)
	local ok, player = pcall(Player, pid)
	if not ok or not player then
		return false
	end
	local okS, v = pcall(function() return player:getStorageValue(C.STORAGE) end)
	return okS and v == 1
end

-- wants(pid) read at most once a second per player (a cast sends many effects in a tick)
function C.wishes(pid)
	local e = C.wish[pid]
	local t = os.time()
	if e and e.t == t then
		return e.v
	end
	local v = C.wants(pid)
	C.wish[pid] = {v = v, t = t}
	return v
end

-- the hello of the client (fxowner.lua): need on or off; off drops what is waiting
function C.setNeed(player, need)
	pcall(function() player:setStorageValue(C.STORAGE, need and 1 or -1) end)
	local ok, id = pcall(function() return player:getId() end)
	if ok then
		C.wish[id] = {v = need and true or false, t = os.time()}
		if not need then
			C.bufs[id] = nil
		end
	end
end

-- ---------------------------------------------------------------- noting and sending

-- the message to the player: hook for the glue and the tests (Chaos.send when it is there, else the opcode directly)
function C.send(player, data)
	if Chaos and Chaos.send then
		return Chaos.send(player, C.OPCODE, "marks", data)
	end
	return player:sendExtendedOpcode(C.OPCODE, json.encode({action = "marks", data = data}))
end

-- one tick later: the buffer of player pid goes out
function C.flush(pid)
	local buf = C.bufs[pid]
	C.bufs[pid] = nil
	local data = buf and C.payload(buf)
	if not data then
		return false
	end
	local ok, player = pcall(Player, pid)
	if not ok or not player then
		return false
	end
	local okSend, err = pcall(C.send, player, data)
	if not okSend then
		print("[ChaosFxOwner] send: " .. tostring(err))
		return false
	end
	return true
end

-- an effect (kind) at pos with id was sent now: noted for the caster when the caster's client wants marks
function C.note(kind, pos, id)
	local pid = C.owner()
	if not pid then
		return false
	end
	local buf = C.bufs[pid]
	if buf == nil and not C.wishes(pid) then
		return false
	end
	local x, y, z
	local okPos = pcall(function() x, y, z = pos.x, pos.y, pos.z end)
	if not okPos or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return false
	end
	if buf == nil then
		buf = C.newBuffer(x, y, z)
		C.bufs[pid] = buf
		if rawAddEvent then
			rawAddEvent(C.flush, 0, pid)
		end
	end
	return C.add(buf, kind, x, y, z, id)
end

-- forget a player (logout)
function C.forget(pid)
	C.bufs[pid] = nil
	C.wish[pid] = nil
end

-- ---------------------------------------------------------------- the wrappers

-- wraps Position:sendMagicEffect(effect) and Position:sendDistanceEffect(to, effect): the same call goes on unchanged, after the
-- note. Installed once per Lua state; a reload of this file keeps the first wrappers (they call C.note by name).
function C.install(P)
	P = P or Position
	if C.installed or type(P) ~= "table" then
		return false
	end
	local rawMagic, rawDistance = P.sendMagicEffect, P.sendDistanceEffect
	if type(rawMagic) ~= "function" and type(rawDistance) ~= "function" then
		return false
	end
	C.installed = true
	if type(rawMagic) == "function" then
		P.sendMagicEffect = function(self, effect, ...)
			if C.owner() then
				pcall(C.note, C.KIND_EFFECT, self, effect)
			end
			return rawMagic(self, effect, ...)
		end
	end
	if type(rawDistance) == "function" then
		P.sendDistanceEffect = function(self, to, effect, ...)
			if C.owner() then
				pcall(C.note, C.KIND_MISSILE, self, effect)
			end
			return rawDistance(self, to, effect, ...)
		end
	end
	return true
end

return C
