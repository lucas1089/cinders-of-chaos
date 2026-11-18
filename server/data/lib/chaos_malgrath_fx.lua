-- chaos_malgrath_fx.lua: the attacks of Malgrath, the Drowned Crown, as effects that carry its body (O637, client pair 74; the
-- art is in the sprite pair only, client/tools/sprites/gen_malgrath_boss.py). Owner 2026-11-18: "an arena boss that always faces
-- the front". The body poses of an attack cannot play in an outfit, so each of its attacks is an effect of the pair that draws the
-- boss (its body and its effect layers together) at the pixel grid of its outfit, and the server hides the boss for as long as it
-- plays: the picture is the same, pixel for pixel, as the standing boss with the attack added. Looks only: no damage, no timing of
-- a mechanic, no area (boss_mechanics.lua draws the marks and does the hits as it always did).
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 74 or more, read from the file at load (C.ON). Below it nothing
-- here answers: the boss is not spawned either (bosslair_config.lua), so a client without outfit 3530 never meets it.
--
--   C.pose(id, name, warnMs)  an attack: the effect `name` starts so that it ends with the warning (delay = warnMs - its length,
--                             at once when it is longer), hides the boss, freezes it on its tile, shows it again at the end.
--   C.rise(boss)              the arrival: the rise effect plays while the boss is hidden (called at its first think).
--   C.death(pos)              the death: the collapse plays on the boss's tile; the boss is gone already, nothing is hidden.
-- One effect at a time: a pose that starts while another plays is dropped (the boss only draws one attack at once). A boss that
-- dies or vanishes while hidden has nothing to show again. The ids and send offsets are the generated
-- data/lib/chaos_malgrath_fx_ids.lua. Plain Lua, no engine call at load (server/tests/malgrath_fx_test.lua).

local C = {}

C.PAIR = 74
C.MONSTER = "Malgrath, the Drowned Crown"

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
C.ON = (C.recordedPair() or 0) >= C.PAIR

-- the effects of the boss in the order of the sprite pair: name -> {id, dx, dy, w, h, ms}
function C.ids()
	if not ChaosMalgrathFxIds and dofile then
		pcall(dofile, "data/lib/chaos_malgrath_fx_ids.lua")
	end
	return ChaosMalgrathFxIds
end

-- the gate on and the ids known: the generated table is merged once into ChaosVfx, so Vfx(pos, name) sends each at its offset
function C.live()
	if not C.ON then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		local I = C.ids()
		if I and ChaosVfx then
			for name, e in pairs(I.effects) do
				ChaosVfx[name] = {id = e.id, dx = e.dx, dy = e.dy, ms = e.ms}
			end
			C.loaded = true
		end
	end
	return C.loaded
end

-- the length of an effect in ms, or nil for a name that is none of the boss's
function C.length(name)
	local I = C.ids()
	local e = I and I.effects[name]
	return e and e.ms or nil
end

C.playing = {}  -- boss id -> true while an effect plays
C.saved = {}    -- boss id -> {outfit, speed delta} while the boss is hidden

local function monster(id)
	return Monster and Monster(id) or nil
end

-- hide the boss and freeze it on its tile (its speed to nothing); what it was is kept for C.show
function C.hide(boss)
	local id = boss:getId()
	if C.saved[id] then
		return false
	end
	local saved = {outfit = boss:getOutfit(), delta = 0}
	local ok = pcall(function()
		saved.delta = -boss:getSpeed()
		boss:changeSpeed(saved.delta)
	end)
	if not ok then
		saved.delta = 0
	end
	C.saved[id] = saved
	pcall(function() boss:setOutfit({lookType = 0, lookTypeEx = 0}) end)
	return true
end

-- the boss as it was; nothing when it is gone
function C.show(id)
	local saved = C.saved[id]
	C.saved[id] = nil
	C.playing[id] = nil
	local boss = monster(id)
	if not (saved and boss) then
		return false
	end
	pcall(function() boss:setOutfit(saved.outfit) end)
	if saved.delta ~= 0 then
		pcall(function() boss:changeSpeed(-saved.delta) end)
	end
	return true
end

-- play the effect `name` on the boss's tile now, the boss hidden until it ends. False when none plays (gate, name, boss gone, busy)
function C.play(id, name)
	if not C.live() or C.playing[id] or not (ChaosVfx and ChaosVfx[name]) then
		return false
	end
	local boss = monster(id)
	if not boss then
		return false
	end
	C.playing[id] = true
	C.hide(boss)
	Vfx(boss:getPosition(), name, true)
	addEvent(C.show, (ChaosVfx[name].ms or 0) + 40, id)   -- the last frame is done when the effect's length has passed
	return true
end

-- an attack: ends with the warning
function C.pose(id, name, warnMs)
	local ms = C.length(name)
	if not (C.live() and ms) then
		return false
	end
	local delay = math.max(0, (tonumber(warnMs) or 0) - ms)
	if delay <= 0 then
		return C.play(id, name)
	end
	addEvent(C.play, delay, id, name)
	return true
end

-- the arrival: the rise while the boss is hidden
function C.rise(boss)
	return boss and C.play(boss:getId(), "mg_spawn_rise") or false
end

-- the death: the collapse on the boss's tile (the engine has removed the boss; it is no creature any more)
function C.death(pos)
	if not (C.live() and pos and ChaosVfx and ChaosVfx.mg_death) then
		return false
	end
	return Vfx(pos, "mg_death", true) and true or false
end

ChaosMalgrathFx = C
return C
