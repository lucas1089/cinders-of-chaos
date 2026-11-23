-- chaos_wst_more_fx.lua: the effects of the purchased 32 px effect sets that no pair held before (O735, client pair 82; the
-- art is in the sprite pair only, client/tools/sprites/gen_wst_more_fx.py, docs/CREDITS.md). The ids, send offsets, play
-- times and element tags are the generated data/lib/chaos_wst_more_fx_ids.lua (ids 5442..). No spell or system sends them
-- yet: this is the one door a sender uses, so nothing goes out to a client that does not draw them.
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 82 or more, read from the file at load (C.ON). Below
-- 82 every call returns false and sends nothing.
--
--   if not (ChaosWstMoreFx and ChaosWstMoreFx.at(pos, "m3_hoarfrost_fog_breath_e")) then <the effect of before> end
-- at / to return true when the effect went out. C.entry(name) gives {id, dx, dy, ms, el} or nil. Plain Lua, no engine call
-- at load (server/tests/more_pack_fx_test.lua).

local C = {}

C.PAIR = 82

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

C.ON = (C.recordedPair() or 0) >= C.PAIR

-- the generated table, read once when the gate is on
function C.ids()
	if not C.ON then
		return nil
	end
	if not ChaosWstMoreFxIds and dofile then
		pcall(dofile, "data/lib/chaos_wst_more_fx_ids.lua")
	end
	return ChaosWstMoreFxIds
end

-- the entry of an effect name, or nil (gate off, no such name)
function C.entry(name)
	local I = type(name) == "string" and C.ids() or nil
	return I and I.effects[name] or nil
end

-- the 8 names of a heading set (cone, wave) by a direction 0..7 = n ne e se s sw w nw, or nil
C.DIRS = {"n", "ne", "e", "se", "s", "sw", "w", "nw"}
function C.heading(base, dir)
	local d = C.DIRS[(tonumber(dir) or -1) + 1]
	return d and C.entry(base .. "_" .. d) and (base .. "_" .. d) or nil
end

local function xyz(pos)
	if type(pos) ~= "table" and type(pos) ~= "userdata" then
		return nil
	end
	local ok, x, y, z = pcall(function()
		return pos.x, pos.y, pos.z
	end)
	if not ok or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return nil
	end
	return x, y, z
end

-- the effect `name` at a position; who = one player (only that client) or nil (everybody near)
function C.to(who, pos, name)
	local e = C.entry(name)
	if not e or not Position then
		return false
	end
	local x, y, z = xyz(pos)
	if not x then
		return false
	end
	local p = Position(x + e.dx, y + e.dy, z)
	if who then
		p:sendMagicEffect(e.id, who)
	else
		p:sendMagicEffect(e.id)
	end
	return true
end

function C.at(pos, name)
	return C.to(nil, pos, name)
end

ChaosWstMoreFx = C
return C
