-- Ground loot labels: pure logic (no engine calls), shared by groundloot.lua and server/tests/groundloot_test.lua.
--   ChaosGroundLoot.config                      tunables (range, request sizes, budget, message size)
--   ChaosGroundLoot.parsePos(v)                 {x, y, z} from client input ([x, y, z] or {x =, y =, z =}), or nil
--   ChaosGroundLoot.parseIid(v)                 the client's per-item id: 0 = none, nil = malformed
--   ChaosGroundLoot.inView(playerPos, pos)      same floor and within config.rangeX / rangeY squares
--   ChaosGroundLoot.parseTiles(list, playerPos) the distinct valid positions of a "look" request, at most config.maxTiles
--   ChaosGroundLoot.allow(state, now, cost)     request budget (token bucket per player)
--   ChaosGroundLoot.expiry(decayState, ms)      whole seconds until a decaying item is gone, or nil
--   ChaosGroundLoot.lootExpiry(first, chain)    seconds until a corpse's loot is gone (its decay stages summed)
--   ChaosGroundLoot.isCorpse(t)                 a container lying as a corpse (t = {container, corpseType, owner})
--   ChaosGroundLoot.wireItem(info, s, e)        one ground item for the client
--   ChaosGroundLoot.wireCorpse(s, id, infos, e) one lootable corpse for the client (contents in short)
--   ChaosGroundLoot.clip(text, n)               text safe for the label (no control characters), at most n bytes
--   ChaosGroundLoot.pack(tiles, encode, max)    the tile answers split into JSON payloads of at most max bytes
-- info = ChaosLootFilter.itemInfo(item): {clientId, count, name, rarity, unique, orb, power, category, bestTier, level}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosGroundLoot = ChaosGroundLoot or {}
local G = ChaosGroundLoot

G.config = {
	rangeX = 8, -- tiles a player may ask about: same floor, at most this far (the client shows 15 x 11 squares)
	rangeY = 6,
	maxTiles = 30, -- positions per "look" request (the client batches what changed)
	maxItemsPerTile = 10, -- ground items described per tile (the client draws at most 40 labels in all)
	maxCorpseItems = 12, -- items of a corpse summarised in its label tooltip
	bucketSize = 120, -- request budget per player, in tiles (a tooltip costs 2): 120 at once, then 60 per second
	bucketPerSecond = 60,
	maxNameLength = 40,
	maxPayload = 7000 -- one extended opcode message holds 8192 bytes; leave room for the envelope
}

local floor = math.floor

local function int(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge or v ~= floor(v) then
		return nil
	end
	return v
end

function G.parsePos(v)
	if type(v) ~= "table" then
		return nil
	end
	local x, y, z = int(v.x or v[1]), int(v.y or v[2]), int(v.z or v[3])
	if not x or not y or not z then
		return nil
	end
	if x < 0 or x > 0xFFFE or y < 0 or y > 0xFFFE or z < 0 or z > 15 then
		return nil
	end
	return {x = x, y = y, z = z}
end

-- the client's per-item id (custom attribute chaos_iid) as sent: a decimal string (JSON numbers lose digits), a number,
-- or absent / "0" for items without one. Returns the number (0 = none) or nil when malformed.
function G.parseIid(v)
	if v == nil then
		return 0
	end
	if type(v) == "string" then
		if not v:match("^%d+$") or #v > 17 then
			return nil
		end
		return tonumber(v)
	end
	return int(v) and v >= 0 and v or nil
end

function G.inView(playerPos, pos)
	if not playerPos or not pos or playerPos.z ~= pos.z then
		return false
	end
	return math.abs(playerPos.x - pos.x) <= G.config.rangeX and math.abs(playerPos.y - pos.y) <= G.config.rangeY
end

-- {valid = {{x, y, z}, ...}, refused = {{x, y, z}, ...}}: refused = well-formed but out of view (answered empty, so
-- the client does not ask again at once); malformed entries are dropped; duplicates are kept once
function G.parseTiles(list, playerPos)
	local valid, refused, seen = {}, {}, {}
	if type(list) ~= "table" then
		return {valid = valid, refused = refused}
	end
	local n = 0
	for _, v in ipairs(list) do
		n = n + 1
		if n > G.config.maxTiles then
			break
		end
		local p = G.parsePos(v)
		if p then
			local key = p.x .. ":" .. p.y .. ":" .. p.z
			if not seen[key] then
				seen[key] = true
				if G.inView(playerPos, p) then
					valid[#valid + 1] = p
				else
					refused[#refused + 1] = p
				end
			end
		end
	end
	return {valid = valid, refused = refused}
end

-- state = {tokens, at} (kept by the caller per player); now in ms; true when the request may run
function G.allow(state, now, cost)
	local size, rate = G.config.bucketSize, G.config.bucketPerSecond
	cost = cost or 1
	if state.at == nil then
		state.tokens, state.at = size, now
	end
	local elapsed = math.max(0, now - state.at)
	state.tokens = math.min(size, state.tokens + elapsed * rate / 1000)
	state.at = now
	if state.tokens < cost then
		return false
	end
	state.tokens = state.tokens - cost
	return true
end

-- decayState: the item's ITEM_ATTRIBUTE_DECAYSTATE (1 = decaying); ms: its ITEM_ATTRIBUTE_DURATION (the time left)
function G.expiry(decayState, ms)
	ms = tonumber(ms)
	if tonumber(decayState) ~= 1 or not ms or ms <= 0 then
		return nil
	end
	return math.ceil(ms / 1000)
end

-- Seconds until the loot of a decaying corpse is gone. A corpse decays in stages (a fresh corpse lasts 10 s, then
-- the "slain" ones minutes each); a stage that is still a container keeps the items, the first one that is not (or
-- decays to nothing) loses them. first = seconds left of the current stage (G.expiry), chain = the stages after it,
-- {{container = bool, seconds = its duration (0 = it does not decay)}, ...}. nil = the loot does not go away.
function G.lootExpiry(first, chain)
	if not first then
		return nil
	end
	local total = first
	for _, st in ipairs(chain or {}) do
		if not st.container then
			return total
		end
		local sec = tonumber(st.seconds) or 0
		if sec <= 0 then
			return nil
		end
		total = total + sec
	end
	return total -- the chain was cut short: at least this long
end

-- t = {container = bool, corpseType = ItemType:isCorpse(), owner = Container:getCorpseOwner()}
function G.isCorpse(t)
	return t.container == true and (t.corpseType == true or (tonumber(t.owner) or 0) ~= 0)
end

function G.clip(text, n)
	text = tostring(text or ""):gsub("[%c]", " ")
	n = n or G.config.maxNameLength
	if #text > n then
		text = text:sub(1, n)
	end
	return text
end

local function flags(info, t)
	t.r = (tonumber(info.rarity) or 0) > 0 and info.rarity or nil
	t.u = info.unique and 1 or nil
	t.o = info.orb and 1 or nil
	t.pw = info.power and 1 or nil
	t.g = info.category or "other"
	t.t = (tonumber(info.bestTier) or 0) > 0 and info.bestTier or nil
	return t
end

-- s = the item's index on its tile (Tile:getThingIndex), e = seconds until it decays (nil = it does not)
function G.wireItem(info, s, e)
	return flags(info, {s = s, id = info.clientId, c = info.count, nm = G.clip(info.name), il = (tonumber(info.level) or 0) > 0 and info.level or nil, e = e})
end

-- infos = itemInfo of every item in the corpse (only for a corpse the player may loot)
function G.wireCorpse(s, clientId, infos, e)
	local items = {}
	for i, info in ipairs(infos) do
		if i > G.config.maxCorpseItems then
			break
		end
		items[i] = flags(info, {c = info.count, nm = G.clip(info.name)})
	end
	return {s = s, id = clientId, k = 1, n = #infos, i = items, e = e}
end

-- tiles = {{p = {x, y, z}, i = {...}}, ...}; encode = json.encode. Returns {payload, ...} (each a JSON "tiles" message
-- of at most max bytes). A tile that alone would not fit is sent with its first items only.
function G.pack(tiles, encode, max)
	max = max or G.config.maxPayload
	local out, batch = {}, {}
	local function flush()
		if #batch > 0 then
			out[#out + 1] = encode({action = "tiles", data = {t = batch}})
			batch = {}
		end
	end
	for _, tile in ipairs(tiles) do
		batch[#batch + 1] = tile
		if #encode({action = "tiles", data = {t = batch}}) > max then
			batch[#batch] = nil
			flush()
			batch[1] = tile
			while #encode({action = "tiles", data = {t = batch}}) > max and #tile.i > 0 do
				tile.i[#tile.i] = nil
			end
		end
	end
	flush()
	return out
end

return G
