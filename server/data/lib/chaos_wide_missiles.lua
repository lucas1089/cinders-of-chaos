-- chaos_wide_missiles.lua: missile ids above 255 (O737; engine src-patch 0094, client base patch 0208; server/README.md "Missile ids
-- above 255 (O737)").
-- The engine sends a 16-bit missile id to a client that asked for it at login (the main client from base patch 0208, the Unity client
-- with its flag) and one byte to any other client: an id up to 255 as it is, an id above 255 as the fallback set here or nothing at all.
-- This file holds the gate and the fallback table:
--   * C.on(): config.lua `chaosClientPair` (README "Client pair guard") is C.PAIR (83, server/tools/client_pair.py PAIR_MISSILE_U16) or
--     more AND the engine has src-patch 0094 (Game.setMissileFallback). Below it no pair has a missile above 255.
--   * C.id(id[, fallback]): the missile a script sends. An id up to 255 as it is; an id above 255 only while C.on(), else the fallback
--     (the argument or C.FALLBACK[id]) or nil (send nothing).
--   * C.FALLBACK: [id above 255] = the one-byte missile a client without 16-bit missiles sees instead. Empty: no missile above 255 is in
--     a pair yet. The tool that appends one adds its row here (254 is never a fallback: it is CONST_ANI_WEAPONTYPE).
--   * C.apply(): every row to the engine (Game.setMissileFallback), at startup (data/scripts/chaos/wide_missiles.lua). 0 without the
--     engine patch.
-- Plain Lua, no engine call at load (server/tests/wide_missiles_test.lua).

local C = {}

C.PAIR = 83
C.MAX_BYTE = 255
C.WEAPON_TYPE = 254
C.FIRST_WIDE = 256
C.MAX_ID = 65535

C.FALLBACK = {}

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

-- the recorded pair, read once at load; tests set it by hand
C.recorded = C.recordedPair() or 0

function C.engine()
	return type(Game) == "table" and type(Game.setMissileFallback) == "function"
end

function C.on()
	return C.recorded >= C.PAIR and C.engine()
end

local function whole(v)
	return type(v) == "number" and v == math.floor(v)
end

function C.id(id, fallback)
	if not whole(id) or id < 0 or id > C.MAX_ID then
		return nil
	end
	if id <= C.MAX_BYTE then
		return id
	end
	if C.on() then
		return id
	end
	local fb = fallback or C.FALLBACK[id]
	if whole(fb) and fb >= 1 and fb <= C.MAX_BYTE and fb ~= C.WEAPON_TYPE then
		return fb
	end
	return nil
end

-- the problems of a fallback table (the engine's rule, chaoswidemissile.h Fallbacks::set, plus: 254 is never a fallback)
function C.check(tbl)
	local problems = {}
	for id, fb in pairs(tbl or C.FALLBACK) do
		if not whole(id) or id < C.FIRST_WIDE or id > C.MAX_ID then
			problems[#problems + 1] = "id " .. tostring(id) .. " is not 256..65535"
		elseif not whole(fb) or fb < 1 or fb > C.MAX_BYTE or fb == C.WEAPON_TYPE then
			problems[#problems + 1] = "fallback of " .. id .. " is not a one-byte missile (1..255, not 254)"
		end
	end
	table.sort(problems)
	return problems
end

function C.apply(tbl)
	if not C.engine() then
		return 0
	end
	local n = 0
	for id, fb in pairs(tbl or C.FALLBACK) do
		if #C.check({[id] = fb}) == 0 and Game.setMissileFallback(id, fb) then
			n = n + 1
		end
	end
	return n
end

ChaosWideMissiles = C
return C
