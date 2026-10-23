-- Live spectator for the admin app (spectate.lua; server/README.md "Live spectator"): the pure part.
-- chaos-ctl.sh spectate NAME queues "spectate NAME" (remote_cmd.lua); while that watch lasts the engine writes, once a
-- second, a snapshot of what the watched player sees: the tiles around it on its floor (ground and items in drawing
-- order, as client ids), the creatures on them (name, outfit, direction, health %, skull) and the player's own stats.
-- server/tools/spectate_render.py draws it with the client's sprites. Read only: nothing in the game changes.
-- Tested by tests/spectate_test.lua against a mocked engine. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosSpectateCore = ChaosSpectateCore or {}
local K = ChaosSpectateCore

K.VERSION = 1

-- a character name, the same rule as remote_cmd_core.lua and chaos-ctl.sh: a letter, then letters, spaces, ' and -
function K.isName(name)
	return type(name) == "string" and #name >= 3 and #name <= 29 and name:match("^%a[%a '%-]*$") ~= nil
end

-- the method m of an engine object, called when the object has it (some are missing on older engines and in tests)
local function call(o, m, ...)
	if o == nil then
		return nil
	end
	local f = o[m]
	if type(f) ~= "function" then
		return nil
	end
	return f(o, ...)
end
K.call = call

local function int(v, default)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return default or 0
	end
	return math.floor(v)
end
K.int = int

-- ------------------------------------------------------------------------------------------------ the watch
-- state = {name, untilT}. Returns true when this starts a new watch (none before, another name, or the old one ended).
function K.watch(state, name, now, cfg)
	local current = K.active(state, now)
	local fresh = current == nil or current:lower() ~= name:lower()
	state.name = name
	state.untilT = now + int(type(cfg) == "table" and cfg.watchSeconds or 20, 20)
	return fresh
end

-- the watched name, or nil when there is no watch or it ended (then it is forgotten)
function K.active(state, now)
	if state.name and state.untilT and now <= state.untilT then
		return state.name
	end
	state.name, state.untilT = nil, nil
	return nil
end

-- ------------------------------------------------------------------------------------------------ the snapshot
-- The area: x0, y0 (top-left) and its width and height, around pos.
function K.area(pos, cfg)
	cfg = cfg or {}
	local l, r, u, d = int(cfg.left, 8), int(cfg.right, 9), int(cfg.up, 6), int(cfg.down, 7)
	return pos.x - l, pos.y - u, l + r + 1, u + d + 1
end

-- The items of a tile, bottom to top as the client draws them: the ground, the top items (borders, walls, arches:
-- the renderer sorts them by their client flags) and the other items oldest first. TFS keeps a tile's things as
-- ground, top items, creatures, then the other items newest first (Tile::getThing). With more than maxItems the newest
-- are kept. api.item(item) -> a client id, {client id, count or fluid}, or nil (skipped).
function K.tileItems(tile, api, maxItems)
	maxItems = int(maxItems, 12)
	local out = {}
	local function push(item)
		if item ~= nil and #out < maxItems then
			local e = api.item(item)
			if e ~= nil then
				out[#out + 1] = e
			end
		end
	end
	local idx = 0
	local ground = call(tile, "getGround")
	if ground then
		push(ground)
		idx = 1
	end
	local nTop = int(call(tile, "getTopItemCount"), 0)
	local nCre = int(call(tile, "getCreatureCount"), 0)
	local nDown = int(call(tile, "getDownItemCount"), 0)
	for i = 0, nTop - 1 do
		push(call(tile, "getThing", idx + i))
	end
	local downStart = idx + nTop + nCre
	local take = math.min(nDown, math.max(0, maxItems - #out))
	for i = take - 1, 0, -1 do
		push(call(tile, "getThing", downStart + i))
	end
	return out
end

-- One creature: where it stands, its look and what the client shows over it. api.clientId(server id) for a creature
-- that looks like an item (lookTypeEx).
function K.creature(c, x, y, api, watched)
	local o = call(c, "getOutfit") or {}
	local look = {
		t = int(o.lookType), h = int(o.lookHead), b = int(o.lookBody), l = int(o.lookLegs), f = int(o.lookFeet),
		a = int(o.lookAddons), m = int(o.lookMount), x = 0
	}
	if look.t == 0 and int(o.lookTypeEx) > 0 and api.clientId then
		look.x = int(api.clientId(int(o.lookTypeEx)))
	end
	local hp, maxhp = int(call(c, "getHealth")), int(call(c, "getMaxHealth"))
	local pct = 0
	if maxhp > 0 then
		pct = math.max(0, math.min(100, math.ceil(hp * 100 / maxhp)))
	end
	local kind = "other"
	if call(c, "isPlayer") then
		kind = "player"
	elseif call(c, "isMonster") then
		kind = "monster"
	elseif call(c, "isNpc") then
		kind = "npc"
	end
	local e = {
		x = x, y = y, name = tostring(call(c, "getName") or ""):sub(1, 40), o = look,
		d = int(call(c, "getDirection"), 2) % 4, hp = pct, skull = int(call(c, "getSkull")), k = kind
	}
	if watched then
		e.me = true
	end
	return e
end

-- whether the watched player's own client would draw this creature (not an invisible one, not a staff member in ghost
-- mode); the watched player is always drawn
function K.visible(c, watched)
	if watched then
		return true
	end
	if call(c, "isInvisible") then
		return false
	end
	if call(c, "isPlayer") and call(c, "isInGhostMode") then
		return false
	end
	return true
end

-- the snapshot of what player sees; watch is the name the line asked for (chaos-ctl.sh finds its answer by it).
-- api = {tile(x, y, z), item(item), clientId(server id)}
function K.snapshot(api, player, watch, now, cfg)
	cfg = cfg or {}
	local pos = player:getPosition()
	local x0, y0, w, h = K.area(pos, cfg)
	local me = call(player, "getId")
	local tiles, creatures = {}, {}
	local maxCre = int(cfg.maxCreatures, 80)
	for ty = 0, h - 1 do
		for tx = 0, w - 1 do
			local x, y = x0 + tx, y0 + ty
			local tile = api.tile(x, y, pos.z)
			local list = {}
			if tile then
				list = K.tileItems(tile, api, cfg.maxItemsPerTile)
				for _, c in ipairs(call(tile, "getCreatures") or {}) do
					local watched = me ~= nil and call(c, "getId") == me
					if #creatures < maxCre and K.visible(c, watched) then
						creatures[#creatures + 1] = K.creature(c, x, y, api, watched)
					end
				end
			end
			tiles[#tiles + 1] = list
		end
	end
	local voc = call(player, "getVocation")
	return {
		v = K.VERSION, watch = watch, t = int(now), online = true,
		name = tostring(call(player, "getName") or watch), level = int(call(player, "getLevel")),
		voc = tostring(call(voc, "getName") or ""),
		hp = int(call(player, "getHealth")), maxhp = int(call(player, "getMaxHealth")),
		mp = int(call(player, "getMana")), maxmp = int(call(player, "getMaxMana")),
		cap = int(int(call(player, "getFreeCapacity")) / 100), soul = int(call(player, "getSoul")),
		stamina = int(call(player, "getStamina")), skull = int(call(player, "getSkull")),
		pos = {x = int(pos.x), y = int(pos.y), z = int(pos.z)},
		x0 = x0, y0 = y0, w = w, h = h, tiles = tiles, creatures = creatures
	}
end

-- the answer when the watched name is not online
function K.offline(watch, now)
	return {v = K.VERSION, watch = watch, t = int(now), online = false}
end

-- writes text to name through name .. ".tmp" and a rename, so a reader never sees half a file. fs = {write, rename,
-- remove}. A rename that cannot replace the old file (Windows) removes it first.
function K.writeAtomic(fs, name, text)
	local tmp = name .. ".tmp"
	if not fs.write(tmp, text, "w") then
		return false
	end
	if fs.rename(tmp, name) then
		return true
	end
	if fs.remove then
		fs.remove(name)
	end
	return fs.rename(tmp, name) and true or false
end

return K
