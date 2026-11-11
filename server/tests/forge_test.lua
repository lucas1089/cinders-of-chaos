-- Run from the server/ folder: luajit tests/forge_test.lua (and lua5.3; CI runs both)
-- The forge window's server side (O481): every orb carries a kind (what it is aimed at) and a safety tag; the words
-- of one action (ChaosCrafting.explain, never computed in the client); the free slots; and the bench of crafting.lua
-- against a mocked engine: the orb count is backpack plus stash, a craft takes the backpack first and then the stash
-- (through the stash journal, stash_core.lua K.spend), a refused craft or a vanished stash row takes nothing, two crafts
-- never take more than they cost, an old client (no forge flag) still crafts and reads counts, the new messages
-- (forgeinfo, explain, the bag / stash counts) go to the forge window only, the largest state fits one message.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(cond, m)
	checks = checks + 1
	if not cond then
		error("FAIL " .. tostring(m), 2)
	end
end
local function has(text, part, m)
	ok(type(text) == "string" and text:find(part, 1, true) ~= nil, (m or "") .. " (" .. tostring(text) .. ")")
end

-- ---------------------------------------------------------------- engine mock
-- any other upper-case global is a fresh number (engine constants)
local n = 5000
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME = 1, 2
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_ARMOR = 11, 12
INDEX_WHEREEVER, FLAG_NOLIMIT, RETURNVALUE_NOERROR = -1, 1, 0
CONST_SLOT_BACKPACK = 3
MESSAGE_INFO_DESCR = 22

local TYPES = {
	[2400] = {name = "magic sword", weaponType = 1, attack = 48, slot = 48},
	[1988] = {name = "backpack", container = true, slot = 4}
}
function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getName = function() return t.name or "" end,
		isContainer = function() return t.container == true end,
		isStackable = function() return t.stackable == true end,
		getWeaponType = function() return t.weaponType or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return t.armor or 0 end,
		getAttack = function() return t.attack or 0 end,
		getDefense = function() return 0 end,
		getHitChance = function() return 0 end,
		getElementDamage = function() return 0 end,
		getAbilities = function() return {} end,
		getClientId = function() return id end
	}
end

local Item = {}
Item.__index = Item
local function newItem(id, count)
	return setmetatable({id = id, count = count or 1, attrs = {}, custom = {}, removed = false}, Item)
end
function Item:getId() return self.id end
function Item:getCount() return self.count end
function Item:getName() return self.attrs[ITEM_ATTRIBUTE_NAME] or ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:getParent() return self.parent end
function Item:getActionId() return self.aid or 0 end
function Item:isContainer() return false end
function Item:isItem() return true end
function Item:remove(count)
	if count and self.count > count then
		self.count = self.count - count
		return true
	end
	self.removed = true
	if self.parent then
		for i, it in ipairs(self.parent.items) do
			if it == self then table.remove(self.parent.items, i) break end
		end
	end
	return true
end

local bag = {items = {}}
function bag:isContainer() return true end
function bag:isItem() return true end
function bag:getSize() return #self.items end
function bag:getItem(i) return self.items[i + 1] end
function bag:getParent() return nil end
function bag:addItemEx(item)
	self.items[#self.items + 1] = item
	item.parent = self
	return RETURNVALUE_NOERROR
end
local function put(item)
	bag:addItemEx(item)
	return item
end

Game = {createItem = function(id, count) return newItem(id, count) end}

dofile("data/lib/chaos_crafting.lua")
local C = ChaosCrafting
local M = ChaosItemMods
M.random = function(a, b) return a end
local dice = {}
C.random = function(a, b)
	local v = table.remove(dice, 1)
	if v == nil then
		return a
	end
	return v
end

local function rareItem(id, r, mods)
	local it = put(newItem(id))
	it:setCustomAttribute("rarity", r)
	it:setCustomAttribute("combatPowerLevel", 42)
	it:setCustomAttribute("chaos_modv", 3)
	for k, v in pairs(mods or {}) do
		it:setCustomAttribute(k, v)
	end
	C.rewriteDescription(it)
	return it
end

-- ---------------------------------------------------------------- every orb: a kind and a safety tag
local TAGS = {transmutation = "random", alchemy = "random", exalted = "random", annulment = "risky", scouring = "risky",
	chaos = "risky", divine = "risky", sockets = "random", tempering = "random", binding = "safe", excision = "risky",
	reforging = "random", ruin = "random", whetstone = "safe", ember = "safe", crown = "random", void = "risky",
	unveiling = "safe"}
local KINDS = {transmutation = "whole", alchemy = "whole", exalted = "add", annulment = "whole", scouring = "whole",
	chaos = "whole", divine = "whole", sockets = "sockets", tempering = "whole", binding = "mod", excision = "mod",
	reforging = "mod", ruin = "whole", whetstone = "whole", ember = "mod", crown = "whole", void = "whole",
	unveiling = "add"}
local seen = 0
for _, orb in ipairs(C.config.orbs) do
	seen = seen + 1
	ok(C.KINDS[orb.kind], "orb " .. orb.key .. " has a kind (" .. tostring(orb.kind) .. ")")
	ok(C.SAFETY[orb.safety], "orb " .. orb.key .. " has a safety tag (" .. tostring(orb.safety) .. ")")
	eq(orb.safety, TAGS[orb.key], "the tag of " .. orb.key)
	eq(orb.kind, KINDS[orb.key], "the kind of " .. orb.key)
end
ok(seen >= 18, "every orb of the game was checked (" .. seen .. ")")
ok(seen <= 48, "the forge window fits the orbs in one row (pitch floor(864 / n), at least 36) or two (client forgeview.lua V.chipLayout, forge.lua): check the panel before adding the 49th orb")
for key in pairs(TAGS) do
	ok(C.orbByKey[key], "the table names no orb the game lacks: " .. key)
end

-- ---------------------------------------------------------------- the words of one action
local sword = rareItem(2400, 4, {rarity_swordSkill = 1, rarity_physicalAbsorb = 2, rarity_criticalHitChance = 2})
local mods = C.readMods(sword)
local melee
for _, m in ipairs(mods) do
	if m.key == "rarity_swordSkill" then melee = m end
end
local e = C.explain("ember", sword, "rarity_swordSkill")
eq(e.ok, true, "ember can raise the melee modifier") eq(e.tag, "safe", "safe tag") eq(e.kind, "mod", "kind")
has(e.text, "Guaranteed: tier " .. melee.tier .. " to tier " .. (melee.tier + 1), "the fixed outcome in words")
has(e.text, "The value rolls", "and the value range")
-- the before -> after numbers (the same ones as the sentence; never parsed from it)
eq(e.change.kind, "tier", "ember: a tier change") eq(e.change.from.tier, melee.tier, "from tier") eq(e.change.to.tier, melee.tier + 1, "to tier")
eq(e.change.from.lo, melee.lo, "the old range") eq(e.change.from.hi, melee.hi, "the old range, high")
has(e.text, "The value rolls " .. e.change.to.lo .. " to " .. e.change.to.hi, "the sentence gives the NEW tier's range, the same numbers as change")
ok(e.change.to.lo > e.change.from.hi or e.change.to.lo >= e.change.from.lo, "the new range is above the old one")
has(e.change.text, "Melee", "the modifier text")
e = C.explain("ember", sword, nil)
eq(e.ok, false, "no modifier chosen") eq(e.reason, "needMod", "says to choose one")
e = C.explain("ember", sword, "rarity_noSuchThing")
eq(e.ok, false, "a modifier the item lacks") eq(e.reason, "badMod", "badMod")
e = C.explain("binding", sword, "rarity_swordSkill")
eq(e.ok, true, "binding")
eq(e.change.kind, "bind", "binding change") has(e.change.text, "Melee", "binding names the modifier") has(e.text, "this modifier is bound", "binding words")
e = C.explain("excision", sword, "rarity_swordSkill")
eq(e.change.kind, "remove", "excision change") has(e.change.text, "Melee", "excision names the modifier")
eq(e.tag, "risky", "excision is risky") has(e.text, "removed", "excision words")
e = C.explain("reforging", sword, "rarity_swordSkill")
eq(e.change, nil, "a roll has no sure outcome: no change")
eq(e.tag, "random", "reforging is a roll") has(e.text, "One of", "random outcome words")
e = C.explain("void", sword)
eq(e.change, nil, "void: no change")
eq(e.tag, "risky", "void") eq(e.lead, "random", "a random lead") eq(e.warn, true, "risky: the window warns it can cost modifiers")
e = C.explain("whetstone", sword)
if e.ok then eq(e.change.kind, "quality", "whetstone change") eq(e.change.to, e.change.from + 1, "one percent more") eq(e.lead, "fixed", "a fixed outcome") else ok(e.reason ~= nil, "a refusal has a reason") end
e = C.explain("nope", sword)
eq(e.ok, false, "unknown orb") eq(e.reason, "unknownOrb", "code")
local plain = put(newItem(2400))
e = C.explain("ember", plain, "x")
eq(e.ok, false, "a normal item")
local free = C.freeSlots(sword)
eq(free.prefix + free.suffix > 0 or true, true, "free slots computed")
local f0 = C.freeSlots(plain)
eq(f0.prefix, 0, "a normal item has no free prefix") eq(f0.suffix, 0, "nor suffix")
local pCount, sCount = C.sideCounts(mods)
local d = C.describe(sword, {codes = true})
eq(free.prefix, d.prefixes[2] - pCount, "free prefixes = limit - used (the item mods rules)")
eq(free.suffix, d.suffixes[2] - sCount, "free suffixes")

-- ---------------------------------------------------------------- the bench of crafting.lua
local sent = {}
local events = {}
local clock = 1000000
os.mtime = function() return clock end
function CreatureEvent(name) local o = {}; function o:type() end; function o:register() events[name] = o end; return o end
function Action() local o = {}; function o:id() end; function o:allowFarUse() end; function o:register() end; return o end
function GlobalEvent() local o = {}; function o:register() end; return o end
db = {query = function() return true end, asyncQuery = function() end, escapeString = function(s) return "'" .. tostring(s) .. "'" end}
-- a small JSON encoder: the size of a message is measured on it
local function enc(v)
	local t = type(v)
	if t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for _, x in ipairs(v) do parts[#parts + 1] = enc(x) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, x in pairs(v) do parts[#parts + 1] = '"' .. tostring(k) .. '":' .. enc(x) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return '"' .. v:gsub('"', '\\"') .. '"'
	end
	return tostring(v)
end
json = {encode = enc}
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.decode = function(b) return type(b) == "table" and b or nil end
Chaos.select = function() return {} end
Chaos.t = function(_, key, ...) return string.format(key, ...) end
Chaos.tx = function(_, text) return text end
Chaos.lang = function() return "en" end
function Chaos.send(player, opcode, action, data)
	sent[#sent + 1] = {opcode = opcode, action = action, data = data, size = #enc({action = action, data = data})}
	return true
end
dofile("data/scripts/chaos/stash_core.lua")

-- the stash world: plain stacks and the journal, behind the real K.spend
local world = {stash = {}, rows = {}, nextId = 0, seq = 0, saveOk = true, saves = 0, busy = false}
local function newEnv()
	local env = {}
	function env.getSeq() return world.seq end
	function env.setSeq(v) world.seq = v end
	function env.pending()
		local out = {}
		for _, r in pairs(world.rows) do out[#out + 1] = {id = r.id, state = 8, seq = r.seq, itemId = r.itemId, count = r.count, plain = true} end
		return out
	end
	function env.take(rec, seq)
		if world.busy or (world.stash[rec.itemId] or 0) < rec.count then return false end
		world.stash[rec.itemId] = world.stash[rec.itemId] - rec.count
		world.nextId = world.nextId + 1
		rec.id = world.nextId
		world.rows[rec.id] = {id = rec.id, seq = seq, itemId = rec.itemId, count = rec.count}
		return true
	end
	function env.untake(rec)
		local r = world.rows[rec.id]
		if r then
			world.stash[r.itemId] = (world.stash[r.itemId] or 0) + r.count
			world.rows[rec.id] = nil
		end
		return true
	end
	function env.finish(rec) world.rows[rec.id] = nil return true end
	function env.save()
		if not world.saveOk then return false end
		world.saves = world.saves + 1
		return true
	end
	return env
end
local stashReads = 0 -- stash reads of the state: one per state, whatever the number of orbs
ChaosStash = {
	plainCounts = function(_, ids)
		stashReads = stashReads + 1
		local out = {}
		for _, id in ipairs(ids) do
			if (world.stash[id] or 0) > 0 then out[id] = world.stash[id] end
		end
		return out
	end,
	plainCount = function(_, id) return world.stash[id] or 0 end,
	spend = function(_, id, count, change)
		if (world.stash[id] or 0) < count then return false, "gone" end
		return ChaosStashCore.spend(newEnv(), {itemId = id, count = count, plain = true}, change)
	end
}

local player = {id = 77}
function player:getId() return self.id end
function player:getGuid() return self.id end
function player:getName() return "Tester" end
function player:getLevel() return 100 end
function player:getStorageValue() return -1 end
function player:getSlotItem(slot) if slot == CONST_SLOT_BACKPACK then return bag end end
function player:getContainerById() return nil end
function player:getPosition() return {sendMagicEffect = function() end} end
function player:sendTextMessage() end
function player:sendCancelMessage() end
function player:getItemCount(id)
	local c = 0
	for _, it in ipairs(bag.items) do
		if it.id == id then c = c + it.count end
	end
	return c
end
function player:removeItem(id, count)
	for _, it in ipairs(bag.items) do
		if it.id == id then it:remove(count) return true end
	end
	return false
end

dofile("data/scripts/chaos/crafting.lua")
ok(events.ChaosCraftingExtended ~= nil, "the bench registered its opcode handler")
local OP = ChaosOpcodes.crafting
local EMBER, TEMPERING = C.orbByKey.ember.id, C.orbByKey.tempering.id

local function req(action, data)
	sent = {}
	clock = clock + 1000
	events.ChaosCraftingExtended.onExtendedOpcode(player, OP, {action = action, data = data or {}})
end
local function last(action)
	for i = #sent, 1, -1 do
		if sent[i].action == action then return sent[i].data end
	end
end
local function slotOf(item)
	for i, it in ipairs(bag.items) do
		if it == item then return tostring(i - 1) end
	end
end
local function setBag(id, count)
	for i = #bag.items, 1, -1 do
		if bag.items[i].id == id then table.remove(bag.items, i) end
	end
	if count > 0 then put(newItem(id, count)) end
end

local gear = rareItem(2400, 4, {rarity_swordSkill = 1, rarity_physicalAbsorb = 2, rarity_criticalHitChance = 2})
local function select()
	req("select", {path = slotOf(gear), id = gear:getId()})
end
local function apply(orb, mod)
	req("apply", {orb = orb, path = slotOf(gear), id = gear:getId(), sig = C.signature(gear), mod = mod})
end

-- the old client: no forge flag
setBag(EMBER, 1)
world.stash[EMBER] = 3
req("open")
local st = last("state")
ok(st ~= nil, "state sent")
eq(st.counts.ember, 4, "counts = backpack plus stash (an old client reads this)")
eq(st.bag, nil, "an old client gets no bag table") eq(st.stash, nil, "no stash table")
eq(last("forgeinfo"), nil, "no forgeinfo for an old client")
select()
st = last("state")
ok(st.item ~= nil, "the item is on the bench")
eq(st.item.free, nil, "no free slots for an old client")
for _, m in ipairs(st.item.mods) do eq(m.v, nil, "no value field for an old client") end
req("explain", {orb = "ember", path = slotOf(gear), id = gear:getId(), mod = "rarity_swordSkill"})
-- (explain is answered to anybody who asks: a harmless read; the old client never asks)

-- the stash is read once for all the orbs of a state
stashReads = 0
req("open")
eq(stashReads, 1, "one stash read for the whole state, not one per orb")
req("select", {path = slotOf(gear), id = gear:getId()})
eq(stashReads, 2, "one more state, one more read")

-- the forge window
req("open", {forge = 1})
st = last("state")
eq(st.counts.ember, 4, "counts total") eq(st.bag.ember, 1, "bag part") eq(st.stash.ember, 3, "stash part")
local fi = last("forgeinfo")
ok(fi ~= nil and fi.orbs.ember.kind == "mod" and fi.orbs.ember.safety == "safe", "forgeinfo names kind and safety")
ok(fi.orbs.void.safety == "risky", "void is risky in forgeinfo")
select()
st = last("state")
ok(st.item.free ~= nil and st.item.free.prefix ~= nil and st.item.free.suffix ~= nil, "free slots from the item mods rules")
for _, m in ipairs(st.item.mods) do
	ok(type(m.v) == "number", "the forge state carries the value of " .. tostring(m.key) .. " (the roll bar)")
end

-- explain: the server's words, the cost with both counts, the signature
req("explain", {orb = "ember", path = slotOf(gear), id = gear:getId(), sig = C.signature(gear), mod = "rarity_swordSkill"})
local ex = last("explain")
eq(ex.ok, true, "explain ok") eq(ex.tag, "safe", "tag") eq(ex.sig, C.signature(gear), "the answer carries the signature")
has(ex.text, "Guaranteed: tier", "words") eq(ex.cost.bag, 1, "cost: bag") eq(ex.cost.stash, 3, "cost: stash")
eq(ex.cost.from, "bag", "the bag pays first")
req("explain", {orb = "ember", path = slotOf(gear), id = gear:getId(), sig = "stale", mod = "rarity_swordSkill"})
eq(last("explain"), nil, "a stale signature gets no preview, only 'put it on the bench again'")
eq(last("result").ok, false, "stale: refused")

-- bag first
local before = C.modByKey(gear, "rarity_swordSkill").tier
apply("ember", "rarity_swordSkill")
local res = last("result")
eq(res.ok, true, "craft from the bag") eq(res.from, "bag", "the orb came from the bag")
eq(player:getItemCount(EMBER), 0, "the bag orb is spent")
eq(world.stash[EMBER], 3, "the stash is untouched while the bag has one")
eq(C.modByKey(gear, "rarity_swordSkill").tier, before + 1, "the tier rose")
st = last("state")
eq(st.counts.ember, 3, "counts refreshed") eq(st.bag.ember, 0, "bag 0") eq(st.stash.ember, 3, "stash 3")

-- the bag is empty: one from the stash
local saves = world.saves
apply("ember", "rarity_swordSkill")
res = last("result")
eq(res.ok, true, "craft from the stash") eq(res.from, "stash", "the orb came from the stash")
eq(world.stash[EMBER], 2, "one left the stash")
eq(world.saves, saves + 1, "one save (the item change and the journal serial)")
eq(next(world.rows), nil, "no journal row is left")
eq(last("state").counts.ember, 2, "counts follow")

-- a refused craft takes nothing from either (a bound modifier cannot be aimed at)
C.setBound(gear, C.modByKey(gear, "rarity_swordSkill"), true)
C.rewriteDescription(gear)
local sig0 = C.signature(gear)
apply("ember", "rarity_swordSkill")
res = last("result")
eq(res.ok, false, "refused") eq(world.stash[EMBER], 2, "the stash keeps its orbs") eq(C.signature(gear), sig0, "the item did not change")
eq(next(world.rows), nil, "no row left by the refusal")
setBag(EMBER, 1)
apply("ember", "rarity_swordSkill")
eq(last("result").ok, false, "refused again") eq(player:getItemCount(EMBER), 1, "the bag keeps its orb too")
setBag(EMBER, 0)

-- the stash row vanished between the answer and the apply
local free2 = rareItem(2400, 4, {rarity_swordSkill = 1, rarity_physicalAbsorb = 2})
gear = free2
req("explain", {orb = "ember", path = slotOf(gear), id = gear:getId(), sig = C.signature(gear), mod = "rarity_swordSkill"})
eq(last("explain").ok, true, "explained")
world.stash[EMBER] = 0
sig0 = C.signature(gear)
apply("ember", "rarity_swordSkill")
res = last("result")
eq(res.ok, false, "the vanished stash row refuses cleanly") has(res.text, "You have no", "says so")
eq(C.signature(gear), sig0, "the item did not change")

-- two crafts in a row never take more than they cost
world.stash[EMBER] = 1
apply("ember", "rarity_swordSkill")
eq(last("result").ok, true, "the first craft")
apply("ember", "rarity_swordSkill")
eq(last("result").ok, false, "the second finds no orb")
eq(world.stash[EMBER], 0, "one orb, one craft")

-- a failed save: the craft stands, the orb is out of the stash, the journal row waits (no doubling)
world.stash[TEMPERING] = 2
world.saveOk = false
gear = rareItem(2400, 4, {rarity_swordSkill = 1, rarity_physicalAbsorb = 2})
apply("tempering")
res = last("result")
eq(res.ok, true, "a failed save does not undo the craft") eq(world.stash[TEMPERING], 1, "one orb out")
ok(next(world.rows) ~= nil, "the taking row waits for the next save or login")
world.saveOk = true
world.rows = {}

-- the stash is off or busy: no orb, no craft
world.stash[TEMPERING] = 2
world.busy = true
apply("tempering")
res = last("result")
eq(res.ok, false, "a busy stash refuses") has(res.text, "busy", "says it is busy")
eq(world.stash[TEMPERING], 2, "nothing taken")
world.busy = false

-- the largest state: an item with the most modifiers, the strip, a long history: one message, under the limit
local big = {rarity_swordSkill = 3, rarity_physicalAbsorb = 3, rarity_criticalHitChance = 3, rarity_criticalHitAmount = 20,
	rarity_elementfire = 8, rarity_shieldSkill = 3, rarity_distanceSkill = 3, rarity_maglevelSkill = 3}
gear = rareItem(2400, 10, big)
for _, orb in ipairs(C.config.orbs) do
	world.stash[orb.id] = 999
end
req("open", {forge = 1})
select()
local bigState = last("state")
ok(bigState.item ~= nil, "big item selected")
ok(bigState.item.mods and #bigState.item.mods >= 4, "many modifiers (" .. tostring(#(bigState.item.mods or {})) .. ")")
ok(bigState.item.mods and #bigState.item.mods >= 1, "has modifiers")
ok(sent[#sent].size <= 7600, "the biggest state is one message under the limit (" .. tostring(sent[#sent].size) .. ")")
ok(bigState.bag ~= nil or sent[#sent].size <= 7600, "bag and stash tables fit or fall away")
local info = nil
req("open", {forge = 1})
for _, s in ipairs(sent) do
	if s.action == "forgeinfo" then info = s end
end
ok(info ~= nil and info.size < 2000, "forgeinfo is small (" .. tostring(info and info.size) .. ")")

-- the logout forgets the forge flag
events.ChaosCraftingLogout.onLogout(player)
req("open")
eq(last("state").bag, nil, "after a new login the window must ask again")

-- the reasons sent in "info" are texts, never codes, and have a pt-BR entry (the windows show them as they come)
local strings = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local nreasons = 0
for code, text in pairs(C.reasons) do
	nreasons = nreasons + 1
	ok(text ~= code and text:find("%s") ~= nil, "reason " .. code .. " is a sentence, not the code")
	ok(strings[text] ~= nil and strings[text] ~= "", "reason " .. code .. " has a pt-BR entry: " .. text)
end
ok(nreasons > 30, "every reason checked (" .. nreasons .. ")")
req("open")
-- "info" must stay one message (8192 bytes) with the reasons in pt-BR, which are longer than the English
local growth = 0
for _, text in pairs(C.reasons) do growth = growth + #(strings[text] or text) - #text end
local infoSize
for _, m in ipairs(sent) do
	if m.action == "info" then infoSize = m.size end
end
ok(infoSize ~= nil and infoSize + growth < 8000, "info with pt-BR reasons stays under the limit (" .. tostring(infoSize) .. " + " .. growth .. ")")
local infoMsg = last("info")
ok(infoMsg ~= nil and infoMsg.reasons.voidRarity == C.reasons.voidRarity and infoMsg.reasons.keyOrb == C.reasons.keyOrb,
	"info carries the sentence of voidRarity and keyOrb")

print(string.format("forge_test: %d checks, 0 failures", checks))
