-- Run from the server/ folder: luajit tests/inspect_test.lua (and lua5.3; CI runs both).
-- Inspect Player (data/scripts/chaos/inspect_core.lua and inspect.lua) against a mocked engine: names, who may be
-- inspected from where (range, privacy, hidden staff and ghosts answer like an unknown name), the request budget, the
-- packets, and the handler: the public fields only, the equipment tooltips, the privacy toggle (default on, saved in a
-- storage), the refusals, the passive tree packet (sent after the equipment, only when the inspect is allowed), and
-- the wire: every message within the engine's 8192-byte extended opcode limit, joined and read by the client's own
-- playerinspect_logic.lua, for the largest realistic equipment (ten rich items, about 45 KB of rows) and a huge row.
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
local tp = I.treePayload("Anna", {nodes = {2, "9", 3.5, -1}, masteries = {{id = 665, choice = 2}, {id = "x"}}, cls = "ninja",
	line = "thief", vocation = "ninja; drop", total = 70})
eq(#tp.nodes, 2, "tree: whole positive ids only")
eq(tp.nodes[2], 9, "tree: numbers")
eq(#tp.masteries, 1, "tree: valid masteries only")
eq(tp.cls, "ninja", "tree: class key")
eq(tp.vocation, nil, "tree: a key must be a plain word")
eq(tp.spent, 2, "tree: points spent")
eq(#I.treePayload("x", nil).nodes, 0, "tree: no view")

-- ---------------------------------------------------------------- handlers
local sent, events, players = {}, {}, {}
-- a compact JSON encoder like the engine's (sizes are what goes on the wire); `decoded` maps every encoded message back
-- to its table, so the test reads what the client would decode
local decoded = {}
local function encode(v)
	local t = type(v)
	if t == "table" then
		local out = {}
		if next(v) == nil or v[1] ~= nil then
			for i = 1, #v do out[i] = encode(v[i]) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		for _, k in ipairs(keys) do out[#out + 1] = encode(k) .. ":" .. encode(v[k]) end
		return "{" .. table.concat(out, ",") .. "}"
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
	elseif t == "number" then
		return v == math.floor(v) and string.format("%d", v) or string.format("%.14g", v)
	elseif t == "boolean" then
		return tostring(v)
	end
	return "null"
end
json = {encode = function(v)
	local s = encode(v)
	decoded[s] = v
	return s
end}
-- every message goes on the wire as the engine sends it: Player.sendExtendedOpcode of extended_opcode.lua refuses a
-- payload over Chaos.extendedOpcodeMax (8192 bytes); the real Chaos.sendChunked (chaos_constants.lua) cuts big ones
local wire, refused = {}, {}
local realSend = Chaos.send
function Chaos.send(player, opcode, action, data)
	sent[#sent + 1] = {to = player, opcode = opcode, action = action, data = data}
	return realSend(player, opcode, action, data)
end
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
ChaosPassiveTree = {publicView = function(p) return {nodes = {626, 627, 628, 665}, masteries = {{id = 665, choice = 3}},
	cls = "ninja", line = "thief", vocation = "ninja", total = 28} end}
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
	function p:sendExtendedOpcode(opcode, buffer)
		if #buffer > Chaos.extendedOpcodeMax then
			refused[#refused + 1] = #buffer
			return false
		end
		wire[#wire + 1] = {to = self, opcode = opcode, buffer = buffer}
		return true
	end
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
	sent, wire, refused = {}, {}, {}
	ext.onExtendedOpcode(player, ChaosOpcodes.inspect, {action = action, data = data})
	return sent
end
local function advance() clock = clock + 5 end

-- what the client gets: the wire joined by its own L.joinPart (game_playerinspect playerinspect_logic.lua) and decoded
dofile("../client/overlay/modules/game_playerinspect/playerinspect_logic.lua")
local L = PlayerInspectLogic
local function inbox()
	local msgs, parts = {}, {}
	for _, m in ipairs(wire) do
		eq(m.opcode, 240, "everything on the inspect opcode")
		local whole = L.joinPart(parts, m.buffer)
		if whole then
			msgs[#msgs + 1] = assert(decoded[whole], "the client decodes every message")
		end
	end
	eq(parts.buf, nil, "no message left half joined")
	return msgs
end
-- the client window's state after an answer (playerinspect.lua onExtendedOpcode)
local function clientState(msgs)
	local st = L.newState()
	for _, m in ipairs(msgs) do
		if m.action == "result" then L.onResult(st, m.data)
		elseif m.action == "equip" then L.onEquip(st, m.data)
		elseif m.action == "tree" then L.onTree(st, m.data) end
	end
	return st
end

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
local msgs = inbox()
eq(#msgs, 3, "result, equipment, tree")
eq(msgs[2].action, "equip", "equipment")
eq(#msgs[2].data.rows, 2, "two items")
eq(msgs[2].data.rows[1].slot, 1, "slot 1")
eq(msgs[2].data.rows[2].tip.name, "Magic Sword", "tooltip")
eq(msgs[2].data.part, 1, "part 1")
for k in pairs(d) do
	local known = {name = 1, level = 1, voc = 1, vocId = 1, ascended = 1, guild = 1, ach = 1, rift = 1, trials = 1, outfit = 1, self = 1, parts = 1,
		tree = 1}
	eq(known[k], 1, "only public fields are sent: " .. k)
end
eq(d.tree, true, "a tree follows")
eq(msgs[3].action, "tree", "the tree packet last")
eq(msgs[3].data.name, "Anna", "the tree of the inspected player")
eq(#msgs[3].data.nodes, 4, "tree nodes")
local cs = clientState(msgs)
eq(L.complete(cs), true, "the client has every part")
eq(cs.tips[6].name, "Magic Sword", "the client shows the sword")
eq(L.treeButtonText(cs), "Passive Tree (4)", "and the tree button")

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
eq(#wire, 1, "only the refusal: no equipment, no tree for a private character")
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

-- ---------------------------------------------------------------- ChaosInspect.equipPackets
do
	local rows = {}
	for slot = 1, 10 do rows[slot] = {slot = slot, tip = {name = string.rep("n", 90 + slot)}} end
	local packets = I.equipPackets("Anna", rows, json.encode, 400)
	eq(#packets > 3, true, "small limit, several packets")
	local seen = 0
	for i, p in ipairs(packets) do
		eq(#p <= 400, true, "packet " .. i .. " within the limit, message included (" .. #p .. " bytes)")
		local m = decoded[p]
		eq(m.action, "equip", "an equip message")
		eq(m.data.name, "Anna", "with the name")
		eq(m.data.part, i, "numbered")
		seen = seen + #m.data.rows
	end
	eq(seen, 10, "every row once")
	eq(#I.equipPackets("Anna", {}, json.encode), 0, "nothing worn, no packet")
	local one = I.equipPackets("Anna", {{slot = 4, tip = {desc = string.rep("x", 900)}}, {slot = 5, tip = {}}}, json.encode, 400)
	eq(#one, 2, "a row over the limit goes alone")
	eq(#one[1] > 400, true, "and is the one packet over it (Chaos.sendChunked cuts it)")
	eq(#I.equipPackets("Anna", rows, json.encode)[1] <= I.config.packetBytes, true, "default limit")
	eq(I.config.packetBytes <= Chaos.extendedOpcodeMax, true, "the limit fits one extended opcode message")
end

-- ---------------------------------------------------------------- the largest realistic equipment answer
-- Ten worn items as rich as they get, in the shape item_tooltip_core.lua T.build gives them (labels and texts as the
-- real ones): Transcendent, item level 150, an Orb of Ruin's extra slot (7 modifiers, one a legendary power), 30%
-- quality, three sockets with perfect gems, an open veiled slot, every skill, stat and protection of the type, a
-- transmog look; one is a unique set piece with its set's pieces and bonuses and a 300-character flavour text. With
-- the real builder such an item is 4.0-4.4 KB of JSON; so is this one. The old answer cut rows at about 12000 bytes:
-- three of these in one packet, over the engine's 8192-byte limit, so the engine refused it (no equipment at all).
local function bigTip(slot)
	local function row(k, l, v, fmt) return {k = k, l = l, v = v, fmt = fmt} end
	local base = {row("armor", "Armour", 33)}
	for i, l in ipairs({"Fist", "Club", "Sword", "Axe", "Distance", "Shielding"}) do base[#base + 1] = row("skill" .. i, l, 3) end
	base[#base + 1] = row("maxhealth", "Max Health", 200)
	base[#base + 1] = row("maxmana", "Max Mana", 200)
	base[#base + 1] = row("maglevel", "Magic Level", 3)
	for i, l in ipairs({"Physical", "Energy", "Earth", "Fire", "Life Drain", "Mana Drain", "Death", "Water", "Arcane"}) do
		base[#base + 1] = row("protect" .. i, l .. " Protection", 5, "pct")
	end
	base[#base + 1] = row("speed", "Speed", 20)
	local mods, stats = {}, {}
	for _, b in ipairs(base) do stats[#stats + 1] = b end
	local defs = {{"chaos_mod_energyshield", "Maximum Energy Shield", "Maximum Energy Shield +176"},
		{"chaos_mod_monsterreduction", "Damage Taken from Monsters", "Damage Taken from Monsters -3%"},
		{"chaos_mod_energyshieldpct", "Maximum Energy Shield", "Maximum Energy Shield +16%"},
		{"chaos_mod_thorns", "Thorns", "Thorns +39"},
		{"chaos_mod_manacost", "Mana Cost Reduction", "Mana Cost Reduction +8%"},
		{"chaos_mod_smolderaura", "Smoldering Aura", "Smoldering Aura: monsters within 2 sqm take 78 fire damage per second"},
		{"chaos_mod_esrecharge", "Faster Energy Shield Recharge", "Faster Energy Shield Recharge +26%"}}
	for i, m in ipairs(defs) do
		mods[i] = {k = m[1], l = m[2], t = m[3], v = 176, g = "chaos", lo = 85, hi = 135, tr = 8, sd = i <= 4 and "p" or "s",
			bd = i == 1 or nil, pw = i == 6 or nil}
		stats[#stats + 1] = row(m[1], m[2], 176, "pct")
	end
	local gems = {{"Perfect Ruby", "Max Health +200", "#ff5a4a"}, {"Perfect Sapphire", "Max Mana +150", "#5a8cff"},
		{"Perfect Emerald", "Movement Speed +3%", "#4fd06a"}}
	local list = {}
	for i, g in ipairs(gems) do
		list[i] = {name = g[1], text = g[2], color = g[3]}
		stats[#stats + 1] = row("gem_" .. i, g[2]:match("^(.-) %+"), 200)
	end
	stats[#stats + 1] = row("veil_gravebound", "Gravebound", 16, "pct")
	local tip = {key = "1873000000123:3054", id = 3466, count = 1, name = "Emberwrought Cuirass of the Ashen Vigil",
		kind = "armor", slot = "Armour", cmp = {slot}, rarity = 15, rarityName = "Transcendent", level = 150, maxTier = 8,
		sides = {p = 4, s = 3, max = 3, mp = 4, ms = 3}, quality = {q = 30, cap = 30}, base = base, mods = mods,
		sockets = {count = 3, max = 3, list = list}, stats = stats, weight = 120.5,
		veil = {s = "open", n = "Gravebound", t = "16% less damage from monsters while you are below 35% health", tr = 4,
			tn = "V4", lo = 13, hi = 16, h = true},
		req = {level = 250, voc = "knights, paladins and berserkers"}, look = {cid = 3206, name = "strange ring"}}
	if slot == 1 then
		tip.unique = {name = tip.name, set = {key = "embers", name = "Embers of Aranoth", have = 6, total = 6, pieces = {},
			bonuses = {{n = 2, t = "Magic Level +1, Fire Resistance +6%", on = true},
				{n = 4, t = "Damage Taken from Monsters -5%, Block Chance +4%", on = true},
				{n = 6, t = "Maximum Health +6%, Pyre Bulwark: a hit you block or dodge sets the attacker ablaze for 40% of it as fire over 6 s", on = true}}}}
		for i, n in ipairs({"Hornsworn Helm", "Cindermail Coat", "Emberveil Greaves", "Bloodstep Boots", "Emberwarden", "Cinderclaw Band"}) do
			tip.unique.set.pieces[i] = {n = n, eq = true, lv = 70 + 30 * i}
		end
		tip.desc = string.rep("Sworn to a master who answers to no one above. ", 7):sub(1, 300)
	end
	return tip
end
ChaosItemTooltip.build = function(item) return item.tip or {name = item.name, id = item.id} end
local loaded = newPlayer("Loaded", 6, {})
local rowBytes, total = {}, 0
for _, slot in ipairs(I.SLOTS) do -- 1-9 and the badge slot (13)
	loaded.slots[slot] = item("Gear " .. slot, 3000 + slot)
	loaded.slots[slot].tip = bigTip(slot)
	rowBytes[slot] = #json.encode({slot = slot, tip = loaded.slots[slot].tip})
	total = total + rowBytes[slot]
	eq(rowBytes[slot] >= 4000 and rowBytes[slot] <= 5500, true, "a realistic rich tooltip (" .. rowBytes[slot] .. " bytes)")
end
eq(total > 40000, true, "ten rich items: " .. total .. " bytes of rows")
-- what the old cut (rows of about 12000 bytes) would send: every such packet is over the engine's limit
local old = I.chunk((function() local r = {} for _, s in ipairs(I.SLOTS) do r[#r + 1] = {slot = s, tip = loaded.slots[s].tip} end return r end)(),
	function(r) return #json.encode(r) end, 12000)
local oldMax = 0
for i, g in ipairs(old) do
	oldMax = math.max(oldMax, #json.encode({action = "equip", data = {name = "Loaded", rows = g, part = i}}))
end
eq(oldMax > Chaos.extendedOpcodeMax, true, "the old 12000-byte cut: a packet of " .. oldMax .. " bytes")

advance()
out = call(viewer, "inspect", {name = "Loaded"})
eq(#refused, 0, "the engine refuses nothing")
local biggest = 0
for _, m in ipairs(wire) do biggest = math.max(biggest, #m.buffer) end
eq(biggest <= Chaos.extendedOpcodeMax, true, "every message fits one extended opcode (" .. biggest .. " bytes)")
eq(biggest <= I.config.packetBytes, true, "every equipment packet within packetBytes")
msgs = inbox()
cs = clientState(msgs)
eq(msgs[1].action, "result", "result first")
eq(msgs[1].data.parts, #msgs - 2, "parts = the equipment packets that follow")
eq(msgs[1].data.parts, 10, "two rich items are over 8000 bytes: one per packet")
eq(msgs[#msgs].action, "tree", "the tree after the equipment")
eq(L.complete(cs), true, "the client has every equipment packet")
for _, slot in ipairs(I.SLOTS) do
	eq(cs.tips[slot] ~= nil and cs.tips[slot].name, loaded.slots[slot].tip.name, "slot " .. slot .. " arrives whole")
	eq(#cs.tips[slot].mods, 7, "slot " .. slot .. ": every modifier")
	eq(cs.tips[slot].sockets.list[3].name, "Perfect Emerald", "slot " .. slot .. ": every socket")
end
eq(#cs.tips[1].unique.set.pieces, 6, "the set pieces arrive")
eq(#cs.tips[1].desc, 300, "the flavour text arrives")

-- a single row bigger than one message (not a real item today, but nothing caps a tooltip): it goes alone, cut by
-- Chaos.sendChunked into S/P/E parts that the client's L.joinPart joins
loaded.slots[4].tip.desc = string.rep("x", 9000)
advance()
out = call(viewer, "inspect", {name = "Loaded"})
eq(#refused, 0, "a huge row is not refused")
local split = 0
for _, m in ipairs(wire) do
	eq(#m.buffer <= Chaos.extendedOpcodeMax, true, "each part fits")
	if m.buffer:sub(1, 1) ~= "{" then split = split + 1 end
end
eq(split >= 2, true, "the huge row went in parts")
cs = clientState(inbox())
eq(L.complete(cs), true, "complete with the huge row")
eq(#cs.tips[4].desc, 9000, "the huge row arrives whole")
eq(cs.tips[5].name, loaded.slots[5].tip.name, "and the rows after it")
os.time = realTime
print("inspect_test: " .. checks .. " checks ok")
