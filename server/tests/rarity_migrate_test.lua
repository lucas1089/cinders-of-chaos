-- Run from the server/ folder: luajit tests/rarity_migrate_test.lua (and lua5.3; CI runs both)
-- rarity_migrate.lua on a mocked engine: the login walk rewrites the old rarity ids of what a character keeps (worn items,
-- backpack, inbox, depot chests, nested containers) to the ids of today's rarities, changes nothing else, runs once per
-- character and again changes nothing.
local fails, checks = 0, 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		fails = fails + 1
		print("FAIL " .. (m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end

CONST_SLOT_HEAD, CONST_SLOT_AMMO = 1, 10
local events, timers = {}, {}
CreatureEvent = function(name)
	local e = {name = name}
	function e:type(t) self.t = t end
	function e:register() events[name] = self end
	return e
end
TalkAction = function() return {separator = function() end, register = function() end} end
function addEvent(fn, ms) timers[#timers + 1] = fn end

local function newItem(attrs, items)
	local it = {a = attrs or {}, items = items, id = 100}
	function it:getId() return self.id end
	function it:removeCustomAttribute(k) self.a[k] = nil end
	function it:getCustomAttribute(k) return self.a[k] end
	function it:setCustomAttribute(k, v) self.a[k] = v end
	function it:isContainer() return self.items ~= nil end
	function it:getItems(deep)
		local out = {}
		local function walk(list)
			for _, x in ipairs(list) do
				out[#out + 1] = x
				if deep and x.items then walk(x.items) end
			end
		end
		walk(self.items or {})
		return out
	end
	return it
end

local worn = newItem({rarity = 7, rarity_swordSkill = 4, ct_rarity_swordskill = 5, chaos_ilvl = 120})
local bagged = newItem({rarity = 13, chaos_mod_dodge = 3})
local deep = newItem({rarity = 9})
local keep = newItem({rarity = 4, chaos_ilvl = 50})
-- stackables never carry a rarity (owner 2026-10-20): a royal spear stack with one (any id) loses it, whatever it was
local stack = newItem({rarity = 3, chaos_ilvl = 40}); stack.id = 7378
local stackOld = newItem({rarity = 9}); stackOld.id = 7378
local single = newItem({rarity = 3}); single.id = 2400
function ItemType(id) return {isStackable = function() return id == 7378 end} end
local backpack = newItem({}, {bagged, newItem({}, {deep, keep, stack, stackOld, single})})
local inboxed = newItem({rarity = 15})
local depoted = newItem({rarity = 6})
local plain = newItem({})
local inbox = newItem({}, {inboxed})
local chest = newItem({}, {depoted, plain})

local storage = {}
local player = {}
function player:getId() return 1 end
function player:getName() return "Tester" end
function player:getSlotItem(slot) return slot == 1 and worn or slot == 3 and backpack or nil end
function player:getInbox() return inbox end
function player:getDepotChest(id) return id == 1 and chest or nil end
function player:getStorageValue(k) return storage[k] or -1 end
function player:setStorageValue(k, v) storage[k] = v end
Player = function(id) return id == 1 and player or nil end
Game = {getTowns = function() return {{getId = function() return 1 end}, {getId = function() return 2 end}} end}

Chaos = {} -- the script only needs the guard
dofile("data/scripts/chaos/rarity_migrate.lua")
local M = ChaosRarityMigrate
eq(M.STORAGE, 7102490, "its storage")
assert(events.ChaosRarityMigrateLogin and events.ChaosRarityMigrateLogin.t == "login", "a login event")

-- a synchronous walk
local counts = M.walk(player)
eq(worn:getCustomAttribute("rarity"), 5, "worn Mythic -> Legendary")
eq(bagged:getCustomAttribute("rarity"), 10, "Cosmic in the backpack -> Divine")
eq(deep:getCustomAttribute("rarity"), 5, "Eternal in a bag in the backpack -> Legendary")
eq(keep:getCustomAttribute("rarity"), 4, "a Rare stays")
eq(inboxed:getCustomAttribute("rarity"), 10, "Transcendent in the inbox -> Divine")
eq(depoted:getCustomAttribute("rarity"), 5, "Exotic in the depot -> Legendary")
eq(plain:getCustomAttribute("rarity"), nil, "no rarity: untouched")
eq(worn:getCustomAttribute("rarity_swordSkill"), 4, "modifier value kept") eq(worn:getCustomAttribute("ct_rarity_swordskill"), 5, "tier kept")
eq(worn:getCustomAttribute("chaos_ilvl"), 120, "item level kept") eq(bagged:getCustomAttribute("chaos_mod_dodge"), 3, "Chaos modifier kept")
eq(stack:getCustomAttribute("rarity"), nil, "a stackable loses its rarity")
eq(stackOld:getCustomAttribute("rarity"), nil, "...an old id too")
eq(stack:getCustomAttribute("chaos_ilvl"), 40, "...nothing else changes")
eq(single:getCustomAttribute("rarity"), 3, "a single item keeps its Magic")
eq(counts.stackable, 2, "two stackables counted")
eq(ChaosRarityMigrateCore.summary({[7] = 1, stackable = 2}), "Mythic x1, stackables x2", "summary names them")
eq(counts[7], 1) eq(counts[13], 1) eq(counts[9], 1) eq(counts[15], 1) eq(counts[6], 1) eq(counts[4], nil)
local again = M.walk(player)
eq(next(again), nil, "a second walk changes nothing")

-- the login: once per character, one container per tick
worn:setCustomAttribute("rarity", 8)
local login = events.ChaosRarityMigrateLogin
eq(login.onLogin(player), true, "login answers true")
for _ = 1, 20 do
	local t = table.remove(timers, 1)
	if t then t() end
end
eq(worn:getCustomAttribute("rarity"), 5, "the login walk fixed the worn item")
eq(storage[M.STORAGE], ChaosRarityMigrateCore.VERSION, "remembered")
eq(ChaosRarityMigrateCore.VERSION >= 2, true, "version 2: characters walked before the stackable rule are walked again")
worn:setCustomAttribute("rarity", 8)
login.onLogin(player)
eq(#timers, 0, "a character that was walked is not walked again")
eq(worn:getCustomAttribute("rarity"), 8, "...whatever the item holds (the readers map it)")

if fails > 0 then
	error(fails .. " failure(s) of " .. checks)
end
print("rarity_migrate_test: " .. checks .. " checks OK")
