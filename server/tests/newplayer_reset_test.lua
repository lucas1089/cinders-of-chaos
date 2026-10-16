-- Run from the server/ folder: luajit tests/newplayer_reset_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Tutorial reset (newplayer_core.lua NP.takeSnapshot / NP.tutorialReset / NP.skillTriesFilter / NP.kitDueAfterTutorial)
-- on a mocked engine player: leaving the island by the exit or by a skip puts back the character the island started
-- with (level, experience, skills, magic level, max health / mana / capacity, full health and mana), takes back the
-- lent items and the free passive point, clears the island's storages; logout, death and a second skip included.
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/newplayer_core.lua")
local NP = ChaosNewPlayer
local cfg = NP.cfg()

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local ORB, ARMOR, TAG = cfg.orbId, cfg.tutorial.orbItem.id, NP.lentTag()

-- ------------------------------------------------------------------ the mocked engine
local function expForLevel(level)
	local l = level - 1
	return math.floor((50 * l * l * l - 150 * l * l + 400 * l) / 3)
end

local function newItem(id, count, attrs)
	local item = {id = id, count = count or 1, attrs = attrs or {}, items = nil}
	function item:getId() return self.id end
	function item:getCount() return self.count end
	function item:getCustomAttribute(k) return self.attrs[k] end
	function item:setCustomAttribute(k, v) self.attrs[k] = v end
	function item:isContainer() return self.items ~= nil end
	function item:getItems(recursive)
		local out = {}
		for _, it in ipairs(self.items or {}) do
			out[#out + 1] = it
			if recursive and it.items then
				for _, inner in ipairs(it:getItems(true)) do
					out[#out + 1] = inner
				end
			end
		end
		return out
	end
	function item:remove(n)
		local parent = self.parent
		if n and n < self.count then
			self.count = self.count - n
			return true
		end
		if parent and parent.items then
			for i, it in ipairs(parent.items) do
				if it == self then
					table.remove(parent.items, i)
					return true
				end
			end
		elseif self.owner then
			self.owner.slots[self.slot] = nil
			return true
		end
		return false
	end
	return item
end

local function container(id, attrs)
	local c = newItem(id, 1, attrs)
	c.items = {}
	function c:add(it)
		it.parent = self
		table.insert(self.items, it)
		return it
	end
	return c
end

-- a mocked engine EventCallback chain for skill tries: a x2 world buff first (shop_services.lua index 5), then the
-- island's filter (NP.skillTriesFilter, index 1000), as newplayer_tutorial.lua registers it
local function triesChain(player, tries)
	tries = tries * 2
	return NP.skillTriesFilter(player:getId(), player:getStorageValue(NP.key("stage")), tries)
end

local VOC = {
	getRequiredSkillTries = function(_, skill, level) return 10 * level end,
	getRequiredManaSpent = function(_, level) return 100 * level end
}

local nextId = 1
local function newPlayer(level)
	local p = {storage = {}, slots = {}, level = level, exp = expForLevel(level), health = 0, mana = 0,
		maxHealth = 150 + 5 * (level - 1), maxMana = 5 * (level - 1), cap = 400 + 10 * (level - 1), magic = 0, manaSpent = 0,
		skills = {}, id = nextId, inbox = container(14404)}
	nextId = nextId + 1
	for s = 0, 6 do
		p.skills[s] = {level = 10, tries = 0}
	end
	p.health, p.mana = p.maxHealth, p.maxMana
	function p:getId() return self.id end
	function p:getStorageValue(k) local v = self.storage[k]; if v == nil then return -1 end; return v end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:getVocation() return VOC end
	function p:getLevel() return self.level end
	function p:getExperience() return self.exp end
	local function relevel(pl)
		local lvl = 1
		while pl.exp >= expForLevel(lvl + 1) do
			lvl = lvl + 1
		end
		local d = lvl - pl.level
		pl.level = lvl
		pl.maxHealth = pl.maxHealth + 5 * d
		pl.maxMana = pl.maxMana + 5 * d
		pl.cap = pl.cap + 10 * d
		pl.health = math.min(pl.health, pl.maxHealth)
		pl.mana = math.min(pl.mana, pl.maxMana)
	end
	-- the engine's addExperience passes the experience callbacks: a 50% bonus here (the overshoot the reset removes)
	function p:addExperience(n) self.exp = self.exp + math.floor(n * 1.5); relevel(self) end
	function p:removeExperience(n) self.exp = math.max(0, self.exp - n); relevel(self) end
	function p:getBaseMagicLevel() return self.magic end
	function p:getManaSpent() return self.manaSpent end
	function p:addManaSpent(n)
		n = triesChain(self, n)
		self.manaSpent = self.manaSpent + n
		while self.manaSpent >= VOC:getRequiredManaSpent(self.magic + 1) do
			self.manaSpent = self.manaSpent - VOC:getRequiredManaSpent(self.magic + 1)
			self.magic = self.magic + 1
		end
	end
	function p:getSkillLevel(s) return self.skills[s].level end
	function p:getSkillTries(s) return self.skills[s].tries end
	function p:addSkillTries(s, n)
		n = triesChain(self, n)
		local sk = self.skills[s]
		sk.tries = sk.tries + n
		while sk.tries >= VOC:getRequiredSkillTries(s, sk.level + 1) do
			sk.tries = sk.tries - VOC:getRequiredSkillTries(s, sk.level + 1)
			sk.level = sk.level + 1
		end
	end
	function p:getMaxHealth() return self.maxHealth end
	function p:setMaxHealth(v) self.maxHealth = v; self.health = math.min(self.health, v) end
	function p:getMaxMana() return self.maxMana end
	function p:setMaxMana(v) self.maxMana = v; self.mana = math.min(self.mana, v) end
	function p:getCapacity() return self.cap end
	function p:setCapacity(v) self.cap = v end
	function p:getHealth() return self.health end
	function p:getMana() return self.mana end
	function p:addHealth(n) self.health = math.min(self.maxHealth, self.health + n) end
	function p:addMana(n) self.mana = math.max(0, math.min(self.maxMana, self.mana + n)) end
	function p:getSlotItem(slot) return self.slots[slot] end
	function p:equip(slot, item) item.owner, item.slot = self, slot; self.slots[slot] = item; return item end
	function p:getInbox() return self.inbox end
	local function all(pl)
		local out = {}
		for slot = 1, 10 do
			local it = pl.slots[slot]
			if it then
				out[#out + 1] = it
				if it.items then
					for _, inner in ipairs(it:getItems(true)) do out[#out + 1] = inner end
				end
			end
		end
		return out
	end
	function p:getItemCount(id)
		local n = 0
		for _, it in ipairs(all(self)) do
			if it.id == id then n = n + it.count end
		end
		return n
	end
	function p:removeItem(id, n)
		if self:getItemCount(id) < n then return false end
		for _, it in ipairs(all(self)) do
			if it.id == id and n > 0 then
				local take = math.min(n, it.count)
				it:remove(take)
				n = n - take
			end
		end
		return true
	end
	return p
end

local function stage(p, v) p:setStorageValue(NP.key("stage"), v) end
local function flagsOf(p) return p:getStorageValue(NP.key("flags")) end
local PASSIVE = Chaos.storage.passiveExtraPoints

-- what the island does to a character, as newplayer_tutorial.lua does it
local function playIsland(p, opts)
	opts = opts or {}
	stage(p, 1)
	p:setStorageValue(NP.key("done"), 0)
	p:setStorageValue(NP.key("flags"), 0)
	p:setStorageValue(NP.key("kills"), 3)
	p:setStorageValue(NP.key("islandUsed"), 120)
	-- station 1: rats give experience (x10 stage), the fighting tries a skill (blocked on the island)
	p:addExperience(200)
	p:addSkillTries(2, 500) -- sword
	p:addManaSpent(5000)
	p:setStorageValue(NP.key("done"), NP.stationBit(1))
	-- station 2: the mana top-up raises the max mana of a level 1 character
	stage(p, 2)
	p:setMaxMana(10)
	p:addMana(10)
	p:setStorageValue(NP.key("flags"), 16)
	-- station 3: the free passive point
	p:setStorageValue(PASSIVE, math.max(0, p:getStorageValue(PASSIVE)) + 1)
	p:setStorageValue(NP.key("flags"), NP.setBit(flagsOf(p), 4))
	-- station 4: the island's backpack (none before), a tagged leather armor and an Orb of Upheaval
	stage(p, 4)
	local bp = p:getSlotItem(3)
	if not bp then
		bp = p:equip(3, container(1988, {[TAG] = 1}))
	end
	if not opts.untaggedArmor then
		bp:add(newItem(ARMOR, 1, {[TAG] = 1}))
	else
		bp:add(newItem(ARMOR, 1))
	end
	bp:add(newItem(ORB, 1))
	p:setStorageValue(NP.key("orbBase"), p:getItemCount(ORB))
	p:setStorageValue(NP.key("flags"), NP.setBit(flagsOf(p), 8))
	if opts.useOrb then
		p:removeItem(ORB, 1)
		p:setStorageValue(NP.key("done"), NP.setBit(p:getStorageValue(NP.key("done")), NP.stationBit(4)))
	end
	-- damage taken
	p.health = 3
	return bp
end

-- ------------------------------------------------------------------ a fresh level 1 character skips at station 4
do
	local p = newPlayer(1)
	ok(NP.takeSnapshot(p), "snapshot at the tutorial's start")
	playIsland(p)
	ok(p:getLevel() > 1, "the rats raised the level")
	eq(p:getSkillLevel(2), 10, "no skill gain on the island (onGainSkillTries filter)")
	eq(p:getBaseMagicLevel(), 0, "no magic level gain on the island")
	eq(p:getItemCount(ARMOR), 1, "lent armor held")
	eq(p:getItemCount(ORB), 1, "lent orb held")
	-- skip: the stage is final first (NP.tutorialFinish), then the reset
	stage(p, cfg.stageSkipped)
	local r = NP.tutorialReset(p)
	ok(r.snapshot, "the reset found the snapshot")
	eq(p:getLevel(), 1, "level back to 1")
	eq(p:getExperience(), 0, "experience back to 0")
	eq(p:getMaxHealth(), 150, "max health of a fresh character")
	eq(p:getMaxMana(), 0, "the station 2 mana raise is taken back")
	eq(p.cap, 400, "capacity of a fresh character")
	eq(p:getHealth(), 150, "full health")
	eq(p:getSlotItem(3), nil, "the island's backpack went (the kit brings its own)")
	eq(p:getItemCount(ARMOR), 0, "lent armor taken back")
	eq(p:getItemCount(ORB), 0, "lent orb taken back")
	eq(p:getStorageValue(PASSIVE), 0, "the free passive point taken back")
	ok(r.passive, "report: passive point")
	for _, key in ipairs({"done", "kills", "orbBase", "flags", "islandUsed"}) do
		eq(p:getStorageValue(NP.key(key)), -1, "island storage cleared: " .. key)
	end
	eq(p:getStorageValue(NP.key("stage")), cfg.stageSkipped, "the stage stays skipped")
	eq(NP.readSnapshot(p), nil, "snapshot cleared")
	-- the skip used twice: nothing more is taken (the passive point is not taken twice, the level stays)
	p:setStorageValue(PASSIVE, 2) -- points earned elsewhere afterwards
	p:addExperience(100)
	local lvl, xp = p:getLevel(), p:getExperience()
	local r2 = NP.tutorialReset(p)
	ok(not r2.snapshot and not r2.passive and r2.items == 0, "second reset: nothing to undo")
	eq(p:getStorageValue(PASSIVE), 2, "second reset keeps other passive points")
	eq(p:getLevel(), lvl, "second reset keeps the level")
	eq(p:getExperience(), xp, "second reset keeps the experience")
	-- after the island the skills train again
	p:addSkillTries(2, 100)
	ok(p:getSkillLevel(2) > 10, "skills train normally after the island")
end

-- ------------------------------------------------------------------ the exit (done): the same reset, the used orb stays used
do
	local p = newPlayer(1)
	local own = p:equip(3, container(1988)) -- a backpack of its own (website kit): it stays
	own:add(newItem(2120, 1)) -- its rope
	NP.takeSnapshot(p)
	playIsland(p, {useOrb = true})
	stage(p, cfg.stageDone)
	local r = NP.tutorialReset(p)
	eq(p:getLevel(), 1, "done: level back to 1 too")
	eq(p:getMaxMana(), 0, "done: mana raise taken back")
	ok(p:getSlotItem(3) == own, "done: the character's own backpack stays")
	eq(p:getItemCount(2120), 1, "done: its own rope stays")
	eq(p:getItemCount(ARMOR), 0, "done: the crafted armor taken back")
	eq(p:getItemCount(ORB), 0, "done: no orb to take (it was used)")
	eq(r.items, 1, "done: one lent item (the armor)")
end

-- ------------------------------------------------------------------ an armor without its tag, an orb the character had
do
	local p = newPlayer(1)
	local own = p:equip(3, container(1988))
	own:add(newItem(ORB, 2)) -- two orbs of its own
	own:add(newItem(ARMOR, 1)) -- and a leather armor of its own
	NP.takeSnapshot(p)
	playIsland(p, {untaggedArmor = true})
	stage(p, cfg.stageSkipped)
	NP.tutorialReset(p)
	eq(p:getItemCount(ARMOR), 1, "untagged: one lent armor taken, its own stays")
	eq(p:getItemCount(ORB), 2, "its own orbs stay")
end

-- ------------------------------------------------------------------ logout, staff restart, death in the tutorial
do
	local p = newPlayer(8) -- created at level 8 (a website that starts characters higher)
	p.skills[2] = {level = 15, tries = 40}
	p.magic, p.manaSpent = 3, 250
	NP.takeSnapshot(p)
	stage(p, 1)
	-- a logout: the storages are the character's (kept by the database); a new session reads the same snapshot
	local saved = {}
	for k, v in pairs(p.storage) do saved[k] = v end
	p.storage = saved
	ok(NP.readSnapshot(p) ~= nil, "the snapshot survives a logout")
	eq(NP.readSnapshot(p).level, 8, "snapshot level")
	-- a staff restart of the island keeps the first snapshot
	p:addExperience(5000)
	ok(not NP.takeSnapshot(p), "a second start keeps the first snapshot")
	eq(NP.readSnapshot(p).exp, expForLevel(8), "still the first experience")
	-- a death on the way: experience, a skill and magic level lost
	p:removeExperience(p:getExperience() - expForLevel(7) - 10)
	p.skills[2] = {level = 14, tries = 3}
	p.magic, p.manaSpent = 2, 0
	stage(p, cfg.stageSkipped)
	local r = NP.tutorialReset(p)
	eq(p:getLevel(), 8, "death: level raised back to 8")
	eq(p:getExperience(), expForLevel(8), "death: the exact experience (the bonus overshoot removed)")
	eq(p:getSkillLevel(2), 15, "death: sword raised back")
	eq(p:getSkillTries(2), 40, "death: the exact tries (past the x2 buff)")
	eq(p:getBaseMagicLevel(), 3, "death: magic level raised back")
	eq(p:getManaSpent(), 250, "death: the exact mana spent")
	ok(r.skillsRaised >= 2, "report: levels raised")
	eq(p:getMaxHealth(), 150 + 5 * 7, "death: max health of level 8")
	eq(p:getHealth(), p:getMaxHealth(), "full health")
	eq(p:getMana(), p:getMaxMana(), "full mana")
end

-- ------------------------------------------------------------------ high experience round trip, no snapshot
do
	local p = newPlayer(1)
	p.exp = 123456789012
	p.level = 1500
	NP.takeSnapshot(p)
	eq(NP.readSnapshot(p).exp, 123456789012, "experience beyond 32 bits round trips")
	NP.clearSnapshot(p)
	for offset = 0, NP.SNAP_SIZE - 1 do
		eq(p.storage[NP.snapKey("saved") + offset], -1, "cleared " .. offset)
	end
	-- a character that began the island before the reset existed: items and the point go, stats stay
	local q = newPlayer(1)
	playIsland(q)
	stage(q, cfg.stageSkipped)
	local lvl = q:getLevel()
	local r = NP.tutorialReset(q)
	ok(not r.snapshot, "no snapshot")
	eq(q:getLevel(), lvl, "no snapshot: the level is left alone")
	eq(q:getItemCount(ARMOR), 0, "no snapshot: lent armor still taken")
	eq(q:getHealth(), q:getMaxHealth(), "no snapshot: full health")
end

-- ------------------------------------------------------------------ filters and keys
do
	eq(NP.skillTriesFilter(99, 1, 7), 0, "on the island: no tries")
	eq(NP.skillTriesFilter(99, 5, 7), 0, "station 5: no tries")
	eq(NP.skillTriesFilter(99, cfg.stageSkipped, 7), 7, "after the island: unchanged")
	eq(NP.skillTriesFilter(99, -1, 7), 7, "never on the island: unchanged")
	NP.exactTries[99] = 42
	eq(NP.skillTriesFilter(99, 1, 7), 42, "the reset's exact amount")
	NP.exactTries[99] = nil
	eq(NP.snapKey("saved"), 7102750, "snapshot block start")
	ok(NP.snapKey("skillTries", 6) <= 7102750 + NP.SNAP_SIZE - 1, "snapshot inside its block")
	ok(NP.kitDueAfterTutorial(-1, cfg.stageSkipped), "skipped without the kit: kit at login")
	ok(NP.kitDueAfterTutorial(-1, cfg.stageDone), "done without the kit: kit at login")
	ok(not NP.kitDueAfterTutorial(1700000000, cfg.stageDone), "kit given: never twice")
	ok(not NP.kitDueAfterTutorial(-1, 2), "still on the island: no kit")
	ok(not NP.kitDueAfterTutorial(-1, -1), "never on the island: the first login path decides")
end

-- ------------------------------------------------------------------ the Windows package's test characters
-- tools/windows/test_accounts.sql marks them as having skipped the island (kit at the first login) and puts them in
-- the temple of the main city: its numbers must follow the Lua side
do
	local f = io.open("../tools/windows/test_accounts.sql", "r")
	ok(f ~= nil, "test_accounts.sql found")
	if f then
		local sql = f:read("*a")
		f:close()
		local key, value = sql:match("SELECT `id`, (%d+), (%d+) FROM `players`")
		eq(tonumber(key), NP.key("stage"), "test characters: the tutorial stage storage")
		eq(tonumber(value), cfg.stageSkipped, "test characters: stage skipped")
		local poi = dofile("data/chaos_poi.lua")
		local temple
		for _, e in ipairs(poi.marks or {}) do
			if type(e) == "table" and e.k == "temple" and e.n == "Temple of Cinderhold" then
				temple = e
			end
		end
		ok(temple ~= nil, "Cinderhold's temple in chaos_poi.lua")
		local rows = 0
		for town, x, y, z in sql:gmatch("1, (%d+), (%d+), (%d+), (%d+), 0") do
			rows = rows + 1
			eq(tonumber(town), cfg.homeTown.id, "test characters live in the main city")
			if temple then
				ok(tonumber(x) == temple.x and tonumber(y) == temple.y and tonumber(z) == temple.z, "test characters start in its temple")
			end
		end
		eq(rows, 2, "both character inserts set town and temple")
		local names = 0
		for _ in sql:gmatch("'Test %a+'") do
			names = names + 1
		end
		eq(names, 8, "four test characters, each created and marked")
	end
end

-- ------------------------------------------------------------------ the wearable kit on arrival (2026-10-16)
-- A Thief wears the kit's leather armor (the same id as the island's crafted one) and carries the Everfull potions
-- before the snapshot: the reset takes back only what the island lent, the kit stays.
local EVERFULL_H, EVERFULL_M = 32085, 32086
local function wearThiefKit(p)
	local kit = NP.kitFor(11)
	local parts = NP.kitParts(kit, p:getLevel())
	local slots = {head = 1, armor = 4, left = 6, legs = 7, feet = 8}
	for _, w in ipairs(parts.wear) do
		p:equip(slots[w.slot], newItem(w.id, w.count))
	end
	local bp = p:equip(3, container(kit.backpackId))
	bp:add(newItem(EVERFULL_H, 1, {chaos_storebound = 1, chaos_locked = 2}))
	bp:add(newItem(EVERFULL_M, 1, {chaos_storebound = 1, chaos_locked = 2}))
	return bp
end
do
	local p = newPlayer(1)
	local bp = wearThiefKit(p)
	eq(p:getItemCount(ARMOR), 1, "the Thief wears the kit's leather armor")
	NP.takeSnapshot(p)
	playIsland(p)
	ok(p:getSlotItem(3) == bp, "the island used the kit's backpack (no island backpack)")
	eq(p:getItemCount(ARMOR), 2, "the kit's armor and the island's crafted one")
	stage(p, cfg.stageSkipped)
	NP.tutorialReset(p)
	eq(p:getItemCount(ARMOR), 1, "wearable kit: the island's armor went, the worn one stays")
	ok(p:getSlotItem(4) and p:getSlotItem(4).id == ARMOR, "still wearing it")
	ok(p:getSlotItem(3) == bp, "the kit's backpack stays")
	eq(p:getItemCount(EVERFULL_H) + p:getItemCount(EVERFULL_M), 2, "the Everfull potions stay")
	eq(p:getItemCount(2399), 0, "the rest of the kit (throwing stars) is not given before the island ends")
end
-- a character already on the island when the wearable kit came (the owner's): the snapshot's counts follow it, so an
-- armor without its tag never takes the kit's
do
	local p = newPlayer(1)
	NP.takeSnapshot(p)
	stage(p, 1)
	wearThiefKit(p)
	ok(NP.snapshotAddItems(p), "the snapshot is told about the kit")
	eq(NP.readSnapshot(p).armorCount, 1, "the kit's armor counted")
	playIsland(p, {untaggedArmor = true})
	stage(p, cfg.stageDone)
	NP.tutorialReset(p)
	eq(p:getItemCount(ARMOR), 1, "untagged island armor taken, the kit's stays")
end
-- the level 1 stats corrected while on the island: the reset puts the corrected values back, not the old ones
do
	local p = newPlayer(1)
	p.maxHealth, p.health, p.maxMana, p.mana, p.cap = 150, 150, 0, 0, 40000
	NP.takeSnapshot(p)
	stage(p, 2)
	local fix = NP.statsFix(1, 1, {maxHealth = p.maxHealth, maxMana = p.maxMana, cap = p.cap}, {hp = 5, mana = 30, cap = 10})
	p:setMaxMana(fix.maxMana)
	ok(NP.snapshotSetStats(p, fix), "the snapshot gets the corrected stats")
	playIsland(p)
	stage(p, cfg.stageSkipped)
	NP.tutorialReset(p)
	eq(p:getMaxMana(), 90, "after the reset: the Mystic's level 1 mana")
	eq(p:getMana(), 90, "and full")
end
ok(not NP.snapshotAddItems(newPlayer(1)), "no snapshot: nothing to change")

print(string.format("newplayer_reset_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
