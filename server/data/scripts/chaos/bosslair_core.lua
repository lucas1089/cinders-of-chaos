-- Boss lairs: pure logic (no engine calls). Used by bosslair.lua and bossspawns.lua, tested by tests/bosslair_test.lua.
-- The client pair gate, the tiles of a lair, the spawn rule and the config check. Lua 5.1 / LuaJIT and Lua 5.3.
-- Overview: server/README.md "Talath's lair (O616)".

ChaosBossLairCore = ChaosBossLairCore or {}
local L = ChaosBossLairCore

-- the recorded client pair: the `chaosClientPair = N` line of config.lua (README "Client pair guard"); nil without one
function L.parsePair(text)
	if type(text) ~= "string" then
		return nil
	end
	local v = text:match("^%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*$") or text:match("\n%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*")
	return v and tonumber(v) or nil
end

function L.recordedPair(path)
	local f = io.open(path or "config.lua", "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return L.parsePair(text)
end

-- a lair is open while the client pair is the lair's or more (a lair without `pair` is always open)
function L.open(lair, pair)
	if type(lair) ~= "table" then
		return false
	end
	return (tonumber(pair) or 0) >= (tonumber(lair.pair) or 0)
end

local function lower(s)
	return type(s) == "string" and s:lower() or nil
end

-- the lair of a monster type name, or nil
function L.byMonster(cfg, name)
	local want = lower(name)
	if not want then
		return nil
	end
	for _, lair in ipairs(type(cfg) == "table" and cfg.lairs or {}) do
		if lower(lair.monster) == want then
			return lair
		end
	end
	return nil
end

-- true when the engine may place a monster of this type: every monster but the boss of a closed lair
function L.allowSpawn(cfg, name, pair)
	if type(cfg) ~= "table" or cfg.enabled == false then
		return true
	end
	local lair = L.byMonster(cfg, name)
	return lair == nil or L.open(lair, pair)
end

-- absolute position of an offset {dx, dy, dz} from the lair's origin, or nil
function L.offset(lair, off)
	if type(lair) ~= "table" or type(lair.at) ~= "table" or type(off) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(lair.at.x), tonumber(lair.at.y), tonumber(lair.at.z)
	if not (x and y and z and tonumber(off[1]) and tonumber(off[2])) then
		return nil
	end
	return {x = x + off[1], y = y + off[2], z = z + (tonumber(off[3]) or 0)}
end

function L.arrival(lair)
	return L.offset(lair, lair and lair.arrival)
end

function L.bossPos(lair)
	return L.offset(lair, lair and lair.boss)
end

-- what a player who steps on the portal gets: "enter" and the arrival, or "level" (too low) / "closed" (the gate)
function L.enter(lair, pair, level)
	if not L.open(lair, pair) then
		return "closed"
	end
	if (tonumber(level) or 0) < (tonumber(lair.minLevel) or 0) then
		return "level"
	end
	local to = L.arrival(lair)
	if not to then
		return "closed"
	end
	return "enter", to
end

local function isPos(p)
	return type(p) == "table" and tonumber(p.x) and tonumber(p.y) and tonumber(p.z) and true or false
end

-- problems of the config (an empty list when it is sound)
function L.validate(cfg)
	local out, seen, mons = {}, {}, {}
	if type(cfg) ~= "table" or type(cfg.lairs) ~= "table" then
		return {"no lairs"}
	end
	if type(cfg.aid) ~= "number" or cfg.aid < 47890 or cfg.aid > 47899 then
		out[#out + 1] = "aid is not in the block 47890-47899"
	end
	for i, lair in ipairs(cfg.lairs) do
		local k = type(lair.key) == "string" and lair.key or ("#" .. i)
		if seen[k] then
			out[#out + 1] = k .. ": key twice"
		end
		seen[k] = true
		local m = lower(lair.monster)
		if not m then
			out[#out + 1] = k .. ": no monster"
		elseif mons[m] then
			out[#out + 1] = k .. ": monster in two lairs"
		else
			mons[m] = true
		end
		if not (isPos(lair.at) and isPos(lair.portal) and isPos(lair.back)) then
			out[#out + 1] = k .. ": at, portal and back are positions"
		elseif lair.portal.x == lair.back.x and lair.portal.y == lair.back.y and lair.portal.z == lair.back.z then
			out[#out + 1] = k .. ": the way back leads onto the portal"
		end
		if not L.arrival(lair) or not L.bossPos(lair) then
			out[#out + 1] = k .. ": arrival and boss are offsets from the origin"
		end
		if type(lair.respawn) ~= "number" or lair.respawn < 60 then
			out[#out + 1] = k .. ": no respawn time"
		end
		if lair.pair ~= nil and (type(lair.pair) ~= "number" or lair.pair < 1) then
			out[#out + 1] = k .. ": pair is not a client pair"
		end
	end
	return out
end

return L
