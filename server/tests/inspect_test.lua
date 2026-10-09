-- Run from the server/ folder: luajit tests/inspect_test.lua (and lua5.3; CI runs both).
-- Inspect Player (data/scripts/chaos/inspect_core.lua and inspect.lua) against a mocked engine: names, who may be
-- inspected from where (range, privacy, hidden staff and ghosts answer like an unknown name), the request budget, the
-- packets, and the handler: the public fields only, the equipment tooltips, the privacy toggle (default on, saved in a
-- storage), the refusals.
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/inspect_core.lua")
local I = ChaosInspect

-- ---------------------------------------------------------------- names
eq(I.cleanName("  Sir  Lancelot "), "Sir Lancelot", "spaces")
eq(I.cleanName("O'Neil-Smith"), "O'Neil-Smith", "apostrophe and hyphen")
eq(I.cleanName("a"), nil, "too short")
eq(I.cleanName(string.rep("a", 30)), nil, "too long")
eq(I.cleanName("Bob; DROP"), nil, "punctuation")
eq(I.cleanName("12345"), nil, "digits")
eq(I.cleanName(nil), nil, "nil")
eq(I.cleanName(7), nil, "number")
eq(I.reasonText("private", "Anna"), "Anna does not allow others to inspect them.", "text with name")
eq(I.reasonText("rate"), I.REASONS.rate, "text without name")
eq(I.reasonText("whatever"), I.REASONS.notfound, "unknown code")

-- ---------------------------------------------------------------- who may be inspected
local function target(over)
	local t = {online = true, staff = false, ghost = false, off = false, same = false, dx = 3, dy = -2, sameFloor = true, visible = true}
	for k, v in pairs(over or {}) do t[k] = v end
	return t
end
local ok, code = I.allowed(target(), "range")
eq(ok, true, "near and in view")
ok, code = I.allowed(target({dx = 10, dy = -10}), "range")
eq(ok, true, "ten tiles is in range")
ok, code = I.allowed(target({dx = 11}), "range")
eq(code, "range", "eleven tiles")
ok, code = I.allowed(target({sameFloor = false}), "range")
eq(code, "range", "another floor")
ok, code = I.allowed(target({visible = false}), "range")
eq(code, "range", "behind a wall")
ok, code = I.allowed(target({dx = 80, sameFloor = false, visible = false}), "name")
eq(ok, true, "by name: any distance")
ok, code = I.allowed(target({off = true}), "name")
eq(code, "private", "privacy off, by name")
ok, code = I.allowed(target({off = true}), "range")
eq(code, "private", "privacy off, right click")
ok, code = I.allowed(target({off = true, same = true}), "name")
eq(ok, true, "always yourself")
ok, code = I.allowed(target({staff = true}), "name")
eq(code, "notfound", "staff look offline")
ok, code = I.allowed(target({ghost = true}), "range")
eq(code, "notfound", "ghosts look offline")
ok, code = I.allowed(nil, "name")
eq(code, "notfound", "not online")
ok, code = I.allowed(target({online = false}), "name")
eq(code, "notfound", "offline flag")

-- ---------------------------------------------------------------- budget
local st = {}
eq(I.allow(st, 1000), true, "first request")
eq(I.allow(st, 1500), false, "inside the cooldown")
eq(I.allow(st, 2600), true, "after the cooldown")
local burst = 0
local t = 100000
local bucket = {}
for i = 1, 20 do
	t = t + 1600
	if I.allow(bucket, t) then burst = burst + 1 end
end
eq(burst < 20 and burst >= I.config.bucketSize, true, "the bucket runs dry (" .. burst .. " of 20)")

-- ---------------------------------------------------------------- packets and outfit
local rows = {}
for i = 1, 6 do rows[i] = {slot = i, size = 5000} end
local groups = I.chunk(rows, function(r) return r.size end, 12000)
eq(#groups, 3, "6 rows of 5000 bytes into 12000-byte packets")
eq(#groups[1], 2, "two per packet")
eq(#I.chunk({}, function() return 1 end), 0, "no rows, no packets")
eq(#I.chunk({{size = 99999}}, function(r) return r.size end, 100), 1, "a big row goes alone")
local o = I.outfitOf({lookType = 128, lookHead = 78, lookBody = 69, lookLegs = 58, lookFeet = 76, lookAddons = 3})
eq(o.type, 128, "outfit type")
eq(o.addons, 3, "addons")
eq(o.mount, 0, "no mount")
eq(I.outfitOf(nil).type, 0, "no outfit")

-- ---------------------------------------------------------------- handlers
local sent, events, players = {}, {}, {}
json = json or {encode = function(v) return tostring(#tostring(v)) .. string.rep("x", 10) end}
function Chaos.send(player, opcode, action, data) sent[#sent + 1] = {to = player, opcode = opcode, action = action, data = data}; return true end
Chaos.decode = function(buffer) return type(buffer) == "table" and buffer or nil end
function CreatureEvent(name) local o = {}; function o:type() end; function o:register() events[name] = o end; return o end
ACCOUNT_TYPE_GAMEMASTER = 4
MESSAGE_INFO_DESCR = 1
ChaosCrafting = {}
dofile("data/scripts/chaos/item_tooltip_core.lua")
ChaosItemTooltip.build = function(item) return {name = item.name, id = item.id} end
ChaosClasses = {isAscended = function(v) return v == 8 end}
ChaosAchievements = {stats = {[2] = {rift_tier = 7}}, pointsOf = function() return 120, 300 end}
ChaosTrials = {tierCleared = function() return 2 end}
os.mtime = nil
local clock = 100
local realTime = os.time
os.time = function() return clock end
dofile("data/scripts/chaos/inspect.lua")
local ext = events.ChaosInspectExtended

local function newPlayer(name, guid, over)
	local p = {name = name, guid = guid, pid = guid * 10, storage = {}, pos = {x = 100, y = 100, z = 7}, slots = {},
		level = 120, account = 1, ghost = false, voc = {id = 8, name = "Berserker"}, visible = true, notes = {}}
	for k, v in pairs(over or {}) do p[k] = v end
	function p:getId() return self.pid end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getLevel() return self.level end
	function p:getAccountType() return self.account end
	function p:isInGhostMode() return self.ghost end
	function p:getGroup() return {getAccess = function() return self.account >= 4 end} end
	function p:getVocation() local v = self.voc; return {getId = function() return v.id end, getName = function() return v.name end} end
	function p:getPosition() return self.pos end
	function p:canSee(pos) return self.visible end
	function p:getSlotItem(slot) return self.slots[slot] end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:getOutfit() return {lookType = 128, lookHead = 1, lookBody = 2, lookLegs = 3, lookFeet = 4, lookAddons = 1, lookMount = 0} end
	function p:getGuild() return self.guild end
	function p:getGuildLevel() return 2 end
	function p:sendTextMessage(kind, text) self.notes[#self.notes + 1] = text end
	function p:registerEvent() end
	players[name], players[p.pid] = p, p
	return p
end
function Player(v) return players[v] end
local function item(name, id) local it = {name = name, id = id}; function it:getId() return self.id end; return it end
local viewer = newPlayer("Viewer", 1, {})
local anna = newPlayer("Anna", 2, {guild = {getName = function() return "Ravens" end, getRankByLevel = function() return {name = "Officer"} end},
	pos = {x = 103, y = 98, z = 7}})
anna.slots[1] = item("Hornsworn Helm", 2496)
anna.slots[6] = item("Magic Sword", 2400)
local gm = newPlayer("Gamemaster", 3, {account = 4})
local ghost = newPlayer("Ghosty", 4, {ghost = true})
local far = newPlayer("Faraway", 5, {pos = {x = 300, y = 100, z = 7}})

local function call(player, action, data)
	sent = {}
	ext.onExtendedOpcode(player, ChaosOpcodes.inspect, {action = action, data = data})
	return sent
end
local function advance() clock = clock + 5 end

local out = call(viewer, "inspect", {name = "Anna"})
eq(out[1].opcode, 240, "opcode")
eq(out[1].action, "result", "result first")
local d = out[1].data
eq(d.name, "Anna", "name")
eq(d.level, 120, "level")
eq(d.voc, "Berserker", "vocation")
eq(d.ascended, true, "ascended class")
eq(d.guild.name, "Ravens", "guild")
eq(d.guild.rank, "Officer", "rank")
eq(d.ach, 120, "achievement points")
eq(d.rift, 7, "best rift tier")
eq(d.trials, 2, "trials tier")
eq(d.outfit.type, 128, "outfit")
eq(d.self, false, "not self")
eq(d.parts, 1, "one packet of equipment")
eq(out[2].action, "equip", "equipment")
eq(#out[2].data.rows, 2, "two items")
eq(out[2].data.rows[1].slot, 1, "slot 1")
eq(out[2].data.rows[2].tip.name, "Magic Sword", "tooltip")
for k in pairs(d) do
	local known = {name = 1, level = 1, voc = 1, vocId = 1, ascended = 1, guild = 1, ach = 1, rift = 1, trials = 1, outfit = 1, self = 1, parts = 1}
	eq(known[k], 1, "only public fields are sent: " .. k)
end

advance()
out = call(viewer, "inspect", {cid = anna.pid})
eq(out[1].action, "result", "right click, in range")
advance()
out = call(viewer, "inspect", {cid = far.pid})
eq(out[1].action, "denied", "right click, too far")
eq(out[1].data.code, "range", "range code")
advance()
out = call(viewer, "inspect", {name = "Faraway"})
eq(out[1].action, "result", "by name: any distance")
advance()
out = call(viewer, "inspect", {name = "Gamemaster"})
eq(out[1].data.code, "notfound", "staff look offline")
advance()
out = call(viewer, "inspect", {name = "Ghosty"})
eq(out[1].data.code, "notfound", "ghost looks offline")
advance()
out = call(viewer, "inspect", {name = "Nobody"})
eq(out[1].data.text, I.REASONS.notfound, "unknown name")
advance()
out = call(viewer, "inspect", {name = "Anna;"})
eq(out[1].data.code, "bad", "bad name")
advance()
out = call(viewer, "inspect", {cid = "x"})
eq(out[1].data.code, "notfound", "bad creature id")
advance()
out = call(viewer, "inspect", {name = "Viewer"})
eq(out[1].data.self, true, "yourself")
-- rate limit
out = call(viewer, "inspect", {name = "Anna"})
eq(out[1].data.code, "rate", "inside the cooldown")

-- ---------------------------------------------------------------- privacy
advance()
out = call(anna, "privacy", {})
eq(out[1].action, "privacy", "privacy answer")
eq(out[1].data.allow, true, "default: allowed")
eq(anna.storage[Chaos.storage.inspectOff], nil, "nothing stored by default")
out = call(anna, "privacy", {allow = false})
eq(out[1].data.allow, false, "switched off")
eq(anna.storage[Chaos.storage.inspectOff], 1, "stored")
eq(#anna.notes, 1, "told")
advance()
out = call(viewer, "inspect", {name = "Anna"})
eq(out[1].data.code, "private", "refused")
eq(out[1].data.text, "Anna does not allow others to inspect them.", "refusal text")
advance()
out = call(viewer, "inspect", {cid = anna.pid})
eq(out[1].data.code, "private", "refused on right click too")
advance()
out = call(anna, "inspect", {name = "Anna"})
eq(out[1].action, "result", "you can always inspect yourself")
advance()
out = call(anna, "privacy", {allow = true})
eq(out[1].data.allow, true, "switched on again")
advance()
out = call(viewer, "inspect", {name = "Anna"})
eq(out[1].action, "result", "inspectable again")
eq(call(viewer, "bogus", {})[1], nil, "unknown action")
os.time = realTime
print("inspect_test: " .. checks .. " checks ok")
