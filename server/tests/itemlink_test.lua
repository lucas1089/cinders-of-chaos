-- Run from the server/ folder: luajit tests/itemlink_test.lua (and lua5.3; CI runs both).
-- Item links in chat (data/scripts/chaos/itemlink_core.lua and itemlink.lua) against a mocked engine: ids, the text of a
-- link and how it is parsed, names, the snapshot cache (ttl, dedup, per-owner and global limits, LRU), the budgets and the
-- strike counter, the context rules (Help channel), and the handlers: only carried items are linked, at most 3 per message,
-- the snapshot is the item's tooltip, lookups of unknown ids are refused and counted.
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/itemlink_core.lua")
local K = ChaosItemLink

-- ---------------------------------------------------------------- ids
local fixed = string.char(0, 35, 36, 71, 250, 251, 252, 255, 7)
local id = K.makeId(function(n) return fixed:sub(1, n) end, function() return 36 end)
eq(#id, 9, "id length")
eq(id, "a9a9899" .. "9h", "bytes map to a-z0-9 (0 -> a, 35 -> 9, 36 -> a); 252 and 255 are rejected (bias) and use the fallback")
eq(K.validId(id), true, "valid id")
eq(K.validId("ABCDEFGHI"), false, "upper case")
eq(K.validId("abc"), false, "short")
eq(K.validId(nil), false, "nil")
eq(K.validId("abcdefgh!"), false, "punctuation")
local seen, dup = {}, 0
for i = 1, 500 do
	local v = K.makeId(nil, math.random)
	if seen[v] then dup = dup + 1 end
	seen[v] = true
	eq(K.validId(v), true, "random id valid")
end
eq(dup, 0, "no duplicates in 500 ids")

-- ---------------------------------------------------------------- the text of a link
eq(K.cleanName("Sword [of] {Doom}"), "Sword of Doom", "brackets and braces removed")
eq(K.cleanName("  A\tB\n  C "), "A B C", "control characters and spaces")
eq(K.cleanName(""), "Item", "empty name")
eq(K.cleanName(nil), "Item", "nil name")
eq(K.cleanName("magic sword"), "Magic sword", "capital first letter")
eq(K.cleanName("caf\195\169"), "Caf??", "non ASCII bytes")
eq(#K.cleanName(string.rep("x", 100)), K.config.maxNameLength, "name length")
eq(K.rarityDigit(0), "0", "digit 0")
eq(K.rarityDigit(10), "a", "digit 10")
eq(K.rarityDigit(15), "f", "digit 15")
eq(K.rarityDigit(99), "f", "clamped")
eq(K.rarityDigit(-3), "0", "clamped low")
eq(K.rarityDigit(0, true), "u", "unique")
local uq = K.parse(K.token("Soulreaper", 0, "abcdefghi", true))
eq(uq[1].unique, true, "a unique link parses")
eq(uq[1].rarity, 0, "unique: rarity 0")
eq(K.parse("[Soulreaper]{0abcdefghi}")[1].unique, false, "normal is not unique")
local tok = K.token("Blade of Dawn", 4, "k7f2m9qax")
eq(tok, "[Blade of Dawn]{4k7f2m9qax}", "token")
eq(#tok, 27, "token length")
local text = "look " .. tok .. " and " .. K.token("Ring", 10, "abcdefghi") .. "!"
local links = K.parse(text)
eq(#links, 2, "two links")
eq(links[1].name, "Blade of Dawn", "name 1")
eq(links[1].id, "k7f2m9qax", "id 1")
eq(links[1].rarity, 4, "rarity 1")
eq(text:sub(links[1].first, links[1].last), tok, "range 1")
eq(links[2].rarity, 10, "rarity 2")
eq(#K.parse("[Name]{4short}"), 0, "short id is not a link")
eq(#K.parse("[Name]{4ABCDEFGHI}"), 0, "upper case id is not a link")
eq(K.parse("[Na[me]{4k7f2m9qax}")[1].name, "me", "a bracket in a name: the link starts at the last one")
eq(#K.parse("no link here [just brackets] {braces}"), 0, "plain text")
eq(#K.parse(nil), 0, "nil text")
eq(K.hasLink("hi " .. tok), true, "hasLink")
eq(K.hasLink("hi"), false, "hasLink false")

-- ---------------------------------------------------------------- budgets
local b = {}
for i = 1, K.config.registerSize do
	eq(K.allowRegister(b, 1000, 1), true, "register budget " .. i)
end
eq(K.allowRegister(b, 1000, 1), false, "register over budget")
eq(K.allowRegister(b, 1000 + 3000, 1), false, "3 s: not yet (one per 4 s)")
eq(K.allowRegister(b, 1000 + 4100, 1), true, "4 s: one more")
eq(K.allowRegister({}, 0, 7), false, "more than the whole bucket")
local g = {}
local ok = 0
for i = 1, 30 do if K.allowGet(g, 5000, 1) then ok = ok + 1 end end
eq(ok, K.config.getSize, "get burst")
eq(K.allowGet(g, 5000 + 200, 1), true, "get refill")

local s = {}
for i = 1, K.config.strikeLimit - 1 do eq(K.strike(s, 100 + i), false, "strike " .. i) end
eq(K.blocked(s, 110), false, "not blocked yet")
eq(K.strike(s, 120), true, "the last strike blocks")
eq(K.blocked(s, 121), true, "blocked")
eq(K.blocked(s, 120 + K.config.strikeBlock + 1), false, "block over")
local s2 = {}
for i = 1, K.config.strikeLimit - 1 do K.strike(s2, i) end
eq(K.strike(s2, 1000), false, "old strikes expire")

-- ---------------------------------------------------------------- cache
local cache = K.newCache()
local e1 = K.put(cache, {owner = 1, ownerName = "A", key = "1:k", tip = {name = "x"}, now = 100, id = "aaaaaaaaa"})
eq(cache.count, 1, "stored")
eq(K.get(cache, "aaaaaaaaa", 101).owner, 1, "get")
eq(K.get(cache, "bbbbbbbbb", 101), nil, "unknown")
eq(K.get(cache, "short", 101), nil, "invalid id")
local e1b = K.put(cache, {owner = 1, ownerName = "A", key = "1:k", tip = {name = "y"}, now = 200, id = "ccccccccc"})
eq(e1b.id, "aaaaaaaaa", "same item, same link")
eq(cache.count, 1, "no second entry")
eq(K.remaining(e1b, 200), K.config.ttl, "lifetime renewed")
local e2 = K.put(cache, {owner = 2, ownerName = "B", key = "1:k", tip = {name = "z"}, now = 200, id = "ddddddddd"})
eq(e2.id, "ddddddddd", "another owner, another link")
eq(cache.count, 2, "two entries")
eq(K.get(cache, "aaaaaaaaa", 200 + K.config.ttl - 1) ~= nil, true, "alive just before the ttl")
eq(K.get(cache, "aaaaaaaaa", 200 + K.config.ttl), nil, "expired at the ttl")
eq(cache.count, 1, "expired entry removed")
eq(K.put(cache, {owner = 1, key = "1:k", tip = {}, now = 900, id = "eeeeeeeee"}).id, "eeeeeeeee", "after expiry: a new link")
eq(K.purge(cache, 900 + K.config.ttl + 1), 2, "purge counts")
eq(cache.count, 0, "purged")

-- per owner: the oldest go first
cache = K.newCache()
for i = 1, K.config.perOwner + 5 do
	K.put(cache, {owner = 7, tip = {}, now = 10, id = string.format("o%08d", i)})
end
eq(cache.count, K.config.perOwner, "per owner limit")
eq(K.get(cache, "o00000001", 11), nil, "oldest dropped")
eq(K.get(cache, string.format("o%08d", K.config.perOwner + 5), 11) ~= nil, true, "newest kept")

-- global: least recently used first
local old = K.config.maxLinks
K.config.maxLinks, K.config.perOwner = 5, 100
cache = K.newCache()
for i = 1, 5 do K.put(cache, {owner = i, tip = {}, now = 10, id = "g0000000" .. i}) end
K.get(cache, "g00000001", 11) -- use the first one
K.put(cache, {owner = 9, tip = {}, now = 12, id = "g00000006"})
eq(cache.count, 5, "global limit")
eq(K.get(cache, "g00000001", 13) ~= nil, true, "recently used link stays")
eq(K.get(cache, "g00000002", 13), nil, "least recently used goes")
K.config.maxLinks, K.config.perOwner = old, 40

-- ---------------------------------------------------------------- rules
eq(K.contextAllowed(nil, false), true, "no context")
eq(K.contextAllowed({kind = "say"}, false), true, "say")
eq(K.contextAllowed({kind = "party"}, false), true, "party")
eq(K.contextAllowed({kind = "guild"}, false), true, "guild")
eq(K.contextAllowed({kind = "private"}, false), true, "private")
eq(K.contextAllowed({kind = "channel", id = 3}, false), true, "world chat")
eq(K.contextAllowed({kind = "channel", id = 7}, false), false, "help channel, player")
eq(K.contextAllowed({kind = "channel", id = "7"}, false), false, "help channel, id as text")
eq(K.contextAllowed({kind = "channel", id = 7}, true), true, "help channel, tutor")
eq(K.contextAllowed({kind = "npc"}, true), false, "npc")
eq(K.contextAllowed("x", true), false, "malformed")
eq(K.linkablePos({kind = "slot", slot = 1}), true, "slot")
eq(K.linkablePos({kind = "container", cid = 0, index = 0}), true, "container")
eq(K.linkablePos({kind = "map", x = 1, y = 1, z = 7, stackpos = 0}), false, "ground")
eq(K.linkablePos(nil), false, "nothing")

-- ---------------------------------------------------------------- handlers
local sent, events = {}, {}
function Chaos.send(player, opcode, action, data) sent[#sent + 1] = {to = player, opcode = opcode, action = action, data = data}; return true end
Chaos.decode = function(buffer) return type(buffer) == "table" and buffer or nil end
function CreatureEvent(name) local o = {}; function o:type() end; function o:register() events[name] = o end; return o end
function addEvent() return 1 end
ACCOUNT_TYPE_TUTOR = 2
ChaosCrafting = {customNumber = function(item, key) return key == "chaos_iid" and item.iid or 0 end}
local built = 0
dofile("data/scripts/chaos/item_tooltip_core.lua")
ChaosItemTooltip.build = function(item, opts)
	built = built + 1
	return {name = item.name, rarity = item.rarity, unique = item.unique and {name = item.name} or nil, id = item.id, key = item.iid and (tostring(item.iid) .. ":1") or nil}
end
os.mtime = nil
local clock = 1000
local realTime = os.time
os.time = function() return clock end
dofile("data/scripts/chaos/itemlink.lua")
local ext = events.ChaosItemLinkExtended

local function item(name, rarity, iid, owner)
	local it = {name = name, rarity = rarity, iid = iid, id = 100}
	function it:getId() return self.id end
	function it:getTopParent() return self.top end
	it.top = owner
	return it
end
local function newPlayer(name, guid, tutor)
	local p = {name = name, guid = guid, pid = guid * 10, slots = {}, containers = {}}
	function p:getId() return self.pid end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getAccountType() return tutor and 2 or 1 end
	function p:getSlotItem(slot) return self.slots[slot] end
	function p:getContainerById(cid) return self.containers[cid] end
	function p:getContainerIndex() return 0 end
	return p
end
local alice, bob = newPlayer("Alice", 1), newPlayer("Bob", 2)
local sword = item("Blade of Dawn", 4, 555, alice)
local ring = item("Strange Ring", 0, nil, alice)
local stolen = item("Bob's Bow", 3, 777, bob)
alice.slots[6] = sword
alice.slots[9] = ring
alice.slots[5] = stolen -- not hers: its top parent is Bob
alice.containers[0] = {getItem = function(self, i) return i == 2 and sword or nil end}

local function call(player, action, data)
	sent = {}
	ext.onExtendedOpcode(player, ChaosOpcodes.itemLink, {action = action, data = data})
	return sent[1]
end
local function pos(slot) return {x = 0xFFFF, y = slot, z = 0} end

local r = call(alice, "register", {n = 1, items = {{pos = pos(6), iid = "555"}}, ctx = {kind = "say"}})
eq(r.opcode, 249, "opcode")
eq(r.action, "registered", "registered")
eq(r.data.n, 1, "nonce echoed")
eq(#r.data.links, 1, "one link")
local token = r.data.links[1].token
local lk = K.parse(token)
eq(#lk, 1, "the token parses")
eq(lk[1].name, "Blade of Dawn", "token name")
eq(lk[1].rarity, 4, "token rarity")
r = call(alice, "get", {id = lk[1].id})
eq(r.action, "link", "link answer")
eq(r.data.tip.name, "Blade of Dawn", "snapshot is the tooltip")
eq(r.data.owner, "Alice", "owner")
eq(r.data.left, K.config.ttl, "time left")
-- another player may ask: the id is the capability
r = call(bob, "get", {id = lk[1].id})
eq(r.data.tip ~= nil, true, "a receiver gets the snapshot")
-- a container item
r = call(alice, "register", {n = 2, items = {{pos = {x = 0xFFFF, y = 0x40, z = 2}}}})
eq(r.action, "registered", "container item")
eq(K.parse(r.data.links[1].token)[1].id, lk[1].id, "the same item in the same state: the same link")
-- plain item without a per-item id
r = call(alice, "register", {n = 3, items = {{pos = pos(9)}}})
eq(r.action, "registered", "plain item")
eq(K.parse(r.data.links[1].token)[1].rarity, 0, "plain: rarity 0")
-- not hers
r = call(alice, "register", {n = 4, items = {{pos = pos(5), iid = "777"}}})
eq(r.action, "refused", "item of another player")
r = call(alice, "register", {n = 5, items = {{pos = pos(6), iid = "999"}}})
eq(r.action, "refused", "wrong iid: the item moved")
r = call(alice, "register", {n = 6, items = {{pos = pos(2)}}})
eq(r.action, "refused", "empty slot")
r = call(alice, "register", {n = 7, items = {{pos = {x = 0xFFFF, y = 0x41, z = 0}}}})
eq(r.action, "refused", "container that is not open")
r = call(alice, "register", {n = 8, items = {{pos = {x = 1000, y = 1000, z = 7, s = 0}}}})
eq(r.action, "refused", "ground position")
r = call(alice, "register", {n = 9, items = {{pos = pos(6)}, {pos = pos(6)}, {pos = pos(9)}, {pos = pos(9)}}})
eq(r.action, "refused", "four items")
eq(r.data.reason, "You can link up to 3 items in one message.", "reason")
r = call(alice, "register", {n = 10, items = {{pos = pos(9)}}, ctx = {kind = "channel", id = 7}})
eq(r.action, "refused", "help channel")
r = call(newPlayer("Tutor", 5, true), "register", {n = 11, items = {}, ctx = {kind = "channel", id = 7}})
eq(r, nil, "nothing to link: no answer")
-- budget: every request costs its items, found or not; Alice is out of it by now
r = call(alice, "register", {n = 20, items = {{pos = pos(9)}}})
eq(r.action, "refused", "the register budget stops the flood")
eq(r.data.reason, "You are linking items too fast.", "reason")
clock = clock + 5
r = call(alice, "register", {n = 21, items = {{pos = pos(9)}}})
eq(r.action, "registered", "one more after 5 seconds")
-- lookups of unknown ids are refused and counted
local carol = newPlayer("Carol", 3)
for i = 1, K.config.strikeLimit do
	r = call(carol, "get", {id = string.format("z%08d", i)})
	eq(r.data.gone, true, "unknown id " .. i)
end
r = call(carol, "get", {id = lk[1].id})
eq(r, nil, "after the strikes: blocked, even for a real id")
-- expiry
clock = clock + K.config.ttl + 5
r = call(bob, "get", {id = lk[1].id})
eq(r.data.gone, true, "expired")
-- malformed
r = call(bob, "get", {id = 12345})
eq(r.data.gone, true, "number as id")
eq(call(bob, "get", "x"), nil, "malformed data")
-- help channel hook
eq(K.helpBlocks(alice, "hello " .. token), true, "help blocks a link from a player")
eq(K.helpBlocks(alice, "hello"), false, "help allows text")
eq(K.helpBlocks(newPlayer("T", 9, true), token), false, "help allows a tutor")
-- login sends the capability
events.ChaosItemLinkLogin.onLogin({registerEvent = function() end, getId = function() return 1 end})
os.time = realTime
print("itemlink_test: " .. checks .. " checks ok")
