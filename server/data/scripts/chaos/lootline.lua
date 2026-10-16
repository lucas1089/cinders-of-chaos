-- One loot line per kill, the engine side (server/README.md "One loot line per kill"; rules lootline_core.lua).
-- The onDropLoot callbacks of one corpse run one after the other (lower index first): 0 the stock loot and its
-- "Loot of ..." line, 1 the Chaos loot layer (loot.lua), 2.7 the store pouches (pouches.lua), up to 99. This file
--   * opens a record for the kill at index `beginIndex` (before the stock callback),
--   * holds back the stock line: while a record is open, a MESSAGE_LOOT "Loot of ..." sent to the corpse owner (or
--     broadcast to the owner's party) is kept instead of sent (Player.sendTextMessage and Party.broadcastPartyLoot are
--     wrapped once; every other message passes unchanged),
--   * takes the Chaos bonus items (ChaosLootLine.addBonus, loot.lua), the rarity raises of stock items
--     (ChaosLootLine.addUpgrade, loot.lua: the stock entry shows the final rarity, {} from Rare on) and the pouch line
--     (ChaosLootLine.addPouch, pouches.lua); without this file they send their own lines as before,
--   * sends the one line at index `flushIndex` (after the autoloot, the Rarity Autoloot and the empty corpse check):
--     to the owner with the pouch part, to the other party members without it.
-- A record that a failed callback left open is sent when the next kill opens one.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosLootLineCore then
	dofile("data/scripts/chaos/lootline_core.lua")
end

ChaosLootLine = ChaosLootLine or {}
local X = ChaosLootLine
local K = ChaosLootLineCore

X.beginIndex = -1
X.flushIndex = 100
X.current = nil -- {id = monster id, owner = owner creature id, monster = name description, stock, bonus = {}, pouch,
-- party = true when the stock line was broadcast}

local function idOf(c)
	local ok, id = pcall(function() return c:getId() end)
	return ok and id or nil
end

local function lootMode()
	return MESSAGE_LOOT or MESSAGE_INFO_DESCR
end

-- the original methods (kept across /reload: the wrappers are installed once)
X.orig = X.orig or {}
if Player and not X.orig.send then
	X.orig.send = Player.sendTextMessage
	Player.sendTextMessage = function(self, mode, text, ...)
		local rec = X.current
		if rec and not rec.stock and mode == lootMode() and K.isStockLine(text) and idOf(self) == rec.owner then
			rec.stock = text
			return true
		end
		return X.orig.send(self, mode, text, ...)
	end
end
if Party and not X.orig.broadcast then
	X.orig.broadcast = Party.broadcastPartyLoot
	Party.broadcastPartyLoot = function(self, text, ...)
		local rec = X.current
		if rec and not rec.stock and K.isStockLine(text) then
			rec.stock = text
			rec.party = true
			return true
		end
		return X.orig.broadcast(self, text, ...)
	end
end

local function send(player, text)
	if X.orig.send then
		return X.orig.send(player, lootMode(), text)
	end
	return player:sendTextMessage(lootMode(), text)
end

-- the recipient's translator (Chaos.t, i18n_core.lua); English without it
local function tr(player)
	return function(key, ...)
		if Chaos and Chaos.t then
			return Chaos.t(player, key, ...)
		end
		return K.english(key, ...)
	end
end

local function members(party)
	local out = {}
	local okL, leader = pcall(function() return party:getLeader() end)
	if okL and leader then
		out[#out + 1] = leader
	end
	local okM, list = pcall(function() return party:getMembers() end)
	for _, m in ipairs(okM and list or {}) do
		out[#out + 1] = m
	end
	return out
end

-- send the record's line(s) and close it
function X.flush()
	local rec = X.current
	X.current = nil
	if not rec then
		return false
	end
	local owner = Player(rec.owner)
	if not owner then
		return false
	end
	local party = rec.party and owner:getParty() or nil
	if party then
		for _, m in ipairs(members(party)) do
			local line = K.compose(rec, idOf(m) == rec.owner, tr(m))
			if line then
				send(m, line)
			end
		end
		return true
	end
	local line = K.compose(rec, true, tr(owner))
	if line then
		send(owner, line)
	end
	return line ~= nil
end

-- a record is open for this monster's corpse
function X.active(monster)
	local rec = X.current
	return rec ~= nil and rec.id == idOf(monster)
end

-- the Chaos loot layer's items ({"2 ember shards", "{Ashbringer}"}): true when they join the kill's line
function X.addBonus(monster, items)
	if not X.active(monster) then
		return false
	end
	local rec = X.current
	for _, s in ipairs(items or {}) do
		rec.bonus[#rec.bonus + 1] = tostring(s)
	end
	return true
end

-- a rarity the Chaos loot layer raised on a stock item (loot.lua): {name = the item's name, from = the rarity name the
-- stock line shows (nil: none), to = the new one}. True when the stock entry is rewritten at the flush (else the caller
-- lists it as a bonus item)
function X.addUpgrade(monster, upgrade)
	if not X.active(monster) or type(upgrade) ~= "table" or not upgrade.name or not upgrade.to then
		return false
	end
	local rec = X.current
	rec.upgrades = rec.upgrades or {}
	rec.upgrades[#rec.upgrades + 1] = {name = tostring(upgrade.name), from = upgrade.from, to = tostring(upgrade.to)}
	return true
end

-- the pouch line ("Looted: ... (notes)."): true when it joins the kill's line
function X.addPouch(monster, text)
	if not X.active(monster) or not text then
		return false
	end
	X.current.pouch = text
	return true
end

local function begin(monster, corpse)
	if X.current then
		X.flush()
	end
	local ok, ownerId = pcall(function() return corpse:getCorpseOwner() end)
	local owner = ok and ownerId and Player(ownerId) or nil
	if not owner then
		return
	end
	local desc
	if Chaos and Chaos.monsterNameDescription then
		local okD, d = pcall(Chaos.monsterNameDescription, monster)
		desc = okD and d or nil
	end
	-- the rarity names of the stock line (loot_config.lua gear.names) and the {} rarity (pouches_config.lua lootLine)
	local names = ChaosLootConfig and ChaosLootConfig.gear and ChaosLootConfig.gear.names or nil
	local pc = ChaosPouchesConfig
	local flag = pc and pc.lootLine and pc.lootLine.flagRarity or nil
	X.current = {id = idOf(monster), owner = idOf(owner), monster = desc, bonus = {}, names = names, flag = flag}
end

if EventCallback then
	local openCb = EventCallback
	openCb.onDropLoot = function(self, corpse)
		local ok, err = pcall(begin, self, corpse)
		if not ok then
			X.current = nil
			print("[Chaos lootline] onDropLoot failed: " .. tostring(err))
		end
	end
	openCb:register(X.beginIndex)

	local flushCb = EventCallback
	flushCb.onDropLoot = function(self, corpse)
		local ok, err = pcall(X.flush)
		if not ok then
			X.current = nil
			print("[Chaos lootline] onDropLoot failed: " .. tostring(err))
		end
	end
	flushCb:register(X.flushIndex)
end

return X
