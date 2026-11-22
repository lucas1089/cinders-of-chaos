-- chaos_awakened_fx.lua: the awakened spell look kit (O711, client pair 76; our own art, client/tools/sprites/gen_awakened_fx.py,
-- docs/SPELL_UPGRADES.md 3.4). A LOOKUP ONLY: the data and the gate. Which kit an awakened cast sends, and where, is
-- data/lib/chaos_awakened_look.lua with the rules of data/scripts/chaos/awakened_look_config.lua.
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 76 or more, read from the file at load (C.on). A client
-- on an older pair has no effect 5354+ and its missiles 43, 47, 52, 147-151 are blank or other art, so below 76 every answer is
-- nil and the caller draws what it draws today.
--   C.effect(element, shape)  -> {id, dx, dy, ms} of the effect, or nil (gate off, unknown element or shape)
--   C.missile(element)        -> {id, dx, dy} of the projectile (1 x 1, 3 x 3 direction patterns), or nil
-- Elements: fire ice energy earth death holy physical arcane. Shapes: single circle around line wave.
-- The ids and send offsets are the generated data/lib/chaos_awakened_fx_ids.lua. Plain Lua, no engine call at load
-- (server/tests/awakened_fx_test.lua).

local C = {}

C.PAIR = 76
C.ELEMENTS = {"fire", "ice", "energy", "earth", "death", "holy", "physical", "arcane"}
C.SHAPES = {"single", "circle", "around", "line", "wave"}

function C.parsePair(text)
	if type(text) ~= "string" then
		return nil
	end
	local v = text:match("^%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*$") or text:match("\n%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*")
	return v and tonumber(v) or nil
end

function C.recordedPair(path)
	local f = io.open(path or "config.lua", "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return C.parsePair(text)
end

-- the gate, read once at load; tests set it by hand
C.on = (C.recordedPair() or 0) >= C.PAIR

local function ids()
	if not ChaosAwakenedFxIds and dofile then
		pcall(dofile, "data/lib/chaos_awakened_fx_ids.lua")
	end
	return ChaosAwakenedFxIds
end

function C.effect(element, shape)
	if not C.on then
		return nil
	end
	local I = ids()
	local e = I and I.effects and I.effects["af_" .. tostring(element) .. "_" .. tostring(shape)]
	if not e then
		return nil
	end
	return {id = e.id, dx = e.dx, dy = e.dy, ms = e.ms}
end

function C.missile(element)
	if not C.on then
		return nil
	end
	local I = ids()
	local m = I and I.missiles and I.missiles["af_" .. tostring(element) .. "_proj"]
	if not m then
		return nil
	end
	return {id = m.id, dx = m.dx, dy = m.dy}
end

ChaosAwakenedFx = C
return C
