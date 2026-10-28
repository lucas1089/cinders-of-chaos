-- Item links in chat, the pure part (ChaosItemLink): the wire format of a link in a chat message, the short-lived
-- snapshot cache, the limits. No engine calls; data/scripts/chaos/itemlink.lua does the protocol and reads the items.
-- Tested by server/tests/itemlink_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- How a link travels. The chat itself is the stock one (local say, party, guild, channels, private messages): the
-- server has no hook on every path, so a link is a capability in plain text.
--   1. Shift+click on an item: the client sends `register` (ChaosOpcodes.itemLink, see itemlink.lua); the server checks
--      the player carries the item, snapshots its tooltip (item_tooltip_core.lua) under a random link id and answers
--      the text of the link.
--   2. The client puts that text in the message and sends it as ordinary speech. The text of one link is
--          [Item Name]{<r><id>}       r = rarity as one hex digit (0 = normal .. f = 15) or u (a unique), id = 9 characters a-z 0-9
--      ASCII only (the Tibia chat is Latin-1): other clients show "[Item Name]{3k7f2m9qax}", ours shows the name in the
--      rarity colour and hides the rest.
--   3. A client that received the message and hovers the link asks `get {id}`; the server answers the snapshot.
-- The id is the secret: 36^9 values, random from the system's random source, so an item that was not linked in a message
-- the player received cannot be asked for (and guesses are counted, see `strikes`). A link lives `ttl` seconds.

ChaosItemLink = ChaosItemLink or {}
local L = ChaosItemLink

L.config = {
	ttl = 600, -- seconds a snapshot lives (10 minutes)
	maxLinks = 2000, -- snapshots kept in all (the least recently used go first)
	perOwner = 40, -- snapshots kept per player (the oldest go first)
	perMessage = 3, -- links in one message
	idLength = 9,
	maxNameLength = 56, -- room for a prefix, a long base name and a suffix
	registerSize = 6, -- register budget per player: 6 items at once, then one per 4 seconds
	registerPerSecond = 0.25,
	getSize = 20, -- lookups: 20 at once, then 10 per second
	getPerSecond = 10,
	strikeLimit = 8, -- unknown / expired ids asked in strikeWindow seconds ...
	strikeWindow = 60,
	strikeBlock = 60 -- ... block lookups of that player for this many seconds
}

L.CHANNEL_HELP = 7 -- data/chatchannels/chatchannels.xml
L.ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"

local floor = math.floor

-- ---------------------------------------------------------------------------------------------------------------
-- ids and the text of a link
-- ---------------------------------------------------------------------------------------------------------------
-- bytes: function(n) -> string of n random bytes (the caller passes the system source); rand: math.random fallback
function L.makeId(bytes, rand)
	local n = L.config.idLength
	local raw = bytes and bytes(n) or nil
	local out = {}
	for i = 1, n do
		local v
		if raw and #raw >= i then
			-- 252 = 7 * 36 is the largest multiple of 36 below 256: the rest would make a-j more likely
			local b = raw:byte(i)
			v = b < 252 and b % 36 + 1 or nil
		end
		v = v or (rand or math.random)(1, 36)
		out[i] = L.ALPHABET:sub(v, v)
	end
	return table.concat(out)
end

function L.validId(id)
	return type(id) == "string" and #id == L.config.idLength and id:match("^[a-z0-9]+$") ~= nil
end

-- the name as it stands in the message: no brackets or braces (they would end the link early), printable ASCII only,
-- a capital first letter
function L.cleanName(name)
	name = tostring(name or "")
	name = name:gsub("[%c]", " "):gsub("[%[%]{}]", ""):gsub("[\128-\255]", "?"):gsub("%s+", " ")
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	if #name > L.config.maxNameLength then
		name = name:sub(1, L.config.maxNameLength):gsub("%s+$", "")
	end
	if name == "" then
		name = "Item"
	end
	return (name:gsub("^%l", string.upper)) -- item names come in lower case ("magic sword"): capital first, like the tooltip
end

-- one character: 0-9 a-f the rarity (0 = normal), u a unique item
function L.rarityDigit(rarity, unique)
	if unique then
		return "u"
	end
	rarity = floor(tonumber(rarity) or 0)
	if rarity < 0 then
		rarity = 0
	elseif rarity > 15 then
		rarity = 15
	end
	return string.format("%x", rarity)
end

-- "[Name]{<r><id>}"
function L.token(name, rarity, id, unique)
	return "[" .. L.cleanName(name) .. "]{" .. L.rarityDigit(rarity, unique) .. id .. "}"
end

-- links in a message: {{name, id, rarity, first, last}} in order (byte positions of the whole "[...]{...}")
function L.parse(text)
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	local pos = 1
	while true do
		local s, e, name, r, id = text:find("%[([^%[%]{}%c]+)%]{([%xu])(%w%w%w%w%w%w%w%w%w)}", pos)
		if not s then
			break
		end
		if L.validId(id) then
			out[#out + 1] = {name = name, id = id, rarity = tonumber(r, 16) or 0, unique = r == "u", first = s, last = e}
		end
		pos = e + 1
	end
	return out
end

function L.hasLink(text)
	return #L.parse(text) > 0
end

-- ---------------------------------------------------------------------------------------------------------------
-- budgets
-- ---------------------------------------------------------------------------------------------------------------
-- token bucket: state = {tokens, at} (kept by the caller per player), now in ms, cost in tokens. true when allowed.
function L.allow(state, now, cost, size, perSecond)
	cost = cost or 1
	if state.at == nil then
		state.tokens, state.at = size, now
	end
	if now > state.at then
		state.tokens = math.min(size, state.tokens + (now - state.at) * perSecond / 1000)
	end
	state.at = now
	if state.tokens < cost then
		return false
	end
	state.tokens = state.tokens - cost
	return true
end

function L.allowRegister(state, now, cost)
	return L.allow(state, now, cost, L.config.registerSize, L.config.registerPerSecond)
end

function L.allowGet(state, now, cost)
	return L.allow(state, now, cost, L.config.getSize, L.config.getPerSecond)
end

-- A player who keeps asking for ids that do not exist is guessing (or replaying very old messages): after strikeLimit
-- misses in strikeWindow seconds lookups stop for strikeBlock seconds. state = {misses = {times}, blockedUntil}.
function L.blocked(state, nowSec)
	return (state.blockedUntil or 0) > nowSec
end

function L.strike(state, nowSec)
	local c = L.config
	state.misses = state.misses or {}
	local kept = {}
	for _, t in ipairs(state.misses) do
		if nowSec - t < c.strikeWindow then
			kept[#kept + 1] = t
		end
	end
	kept[#kept + 1] = nowSec
	state.misses = kept
	if #kept >= c.strikeLimit then
		state.blockedUntil = nowSec + c.strikeBlock
		state.misses = {}
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------------------------------------------
-- the snapshot cache
-- ---------------------------------------------------------------------------------------------------------------
-- entries: id -> {id, owner (player guid), ownerName, key, tip, at (seconds), seq (use order)}
function L.newCache()
	return {entries = {}, count = 0, seq = 0, byKey = {}, owners = {}}
end

local function drop(cache, id)
	local e = cache.entries[id]
	if not e then
		return
	end
	cache.entries[id] = nil
	cache.count = cache.count - 1
	local dk = e.key and (e.owner .. "|" .. e.key)
	if dk and cache.byKey[dk] == id then
		cache.byKey[dk] = nil
	end
	local list = cache.owners[e.owner]
	if list then
		for i, v in ipairs(list) do
			if v == id then
				table.remove(list, i)
				break
			end
		end
		if #list == 0 then
			cache.owners[e.owner] = nil
		end
	end
end

-- removes what expired; returns how many
function L.purge(cache, nowSec)
	local gone = {}
	for id, e in pairs(cache.entries) do
		if nowSec - e.at >= L.config.ttl then
			gone[#gone + 1] = id
		end
	end
	for _, id in ipairs(gone) do
		drop(cache, id)
	end
	return #gone
end

local function evictLeastUsed(cache)
	local oldest, oldestSeq
	for id, e in pairs(cache.entries) do
		if not oldestSeq or e.seq < oldestSeq then
			oldest, oldestSeq = id, e.seq
		end
	end
	if oldest then
		drop(cache, oldest)
	end
end

-- stores a snapshot. opts = {owner = guid, ownerName, key = dedup key or nil, tip, now (seconds), id = new id}
-- The same key (the same item in the same state) of the same owner returns its live link again, with a fresh lifetime.
-- Returns the entry.
function L.put(cache, opts)
	local c = L.config
	local now = opts.now
	local dk = opts.key and (opts.owner .. "|" .. opts.key)
	local dedup = dk and cache.byKey[dk]
	if dedup then
		local e = cache.entries[dedup]
		if e and now - e.at < c.ttl then
			e.at = now
			cache.seq = cache.seq + 1
			e.seq = cache.seq
			return e
		end
		drop(cache, dedup)
	end
	local id = opts.id
	if cache.entries[id] then -- a collision of two random ids: not worth a retry loop, drop the old one
		drop(cache, id)
	end
	cache.seq = cache.seq + 1
	local e = {id = id, owner = opts.owner, ownerName = opts.ownerName, key = opts.key, tip = opts.tip, at = now,
		seq = cache.seq}
	cache.entries[id] = e
	cache.count = cache.count + 1
	if dk then
		cache.byKey[dk] = id
	end
	local list = cache.owners[opts.owner]
	if not list then
		list = {}
		cache.owners[opts.owner] = list
	end
	list[#list + 1] = id
	while #list > c.perOwner do
		drop(cache, list[1])
	end
	while cache.count > c.maxLinks do
		evictLeastUsed(cache)
	end
	return e
end

-- the entry of a link id, nil when unknown or expired (and then removed); a hit counts as a use for the LRU order
function L.get(cache, id, nowSec)
	if not L.validId(id) then
		return nil
	end
	local e = cache.entries[id]
	if not e then
		return nil
	end
	if nowSec - e.at >= L.config.ttl then
		drop(cache, id)
		return nil
	end
	cache.seq = cache.seq + 1
	e.seq = cache.seq
	return e
end

-- seconds left of a link
function L.remaining(entry, nowSec)
	return math.max(0, L.config.ttl - (nowSec - entry.at))
end

-- ---------------------------------------------------------------------------------------------------------------
-- rules
-- ---------------------------------------------------------------------------------------------------------------
-- where a link may be sent: the client names the context of the chat tab {kind = "say" | "party" | "guild" | "private" |
-- "channel", id = channel id}. Returns true, or false and a reason. canTutor: the player is a tutor or above.
function L.contextAllowed(ctx, canTutor)
	if ctx == nil then
		return true
	end
	if type(ctx) ~= "table" then
		return false, "bad context"
	end
	local kind = ctx.kind
	if kind == "channel" and tonumber(ctx.id) == L.CHANNEL_HELP and not canTutor then
		return false, "Item links are not allowed in the Help channel."
	end
	if kind == "npc" or kind == "loot" or kind == "log" then
		return false, "Items cannot be linked here."
	end
	return true
end

-- a position the player may link: the inventory (slots 1-10) or a container they have open; never the ground
function L.linkablePos(decoded)
	return decoded ~= nil and (decoded.kind == "slot" or decoded.kind == "container")
end

return L
