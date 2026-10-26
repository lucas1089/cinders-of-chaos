-- O260, the engine side of: an early power spike (the first unique), pity, the server drop feed and the personal drop
-- records. The rules and numbers: retention_loot_core.lua, retention_loot_config.lua (tests/retention_loot_test.lua);
-- server/README.md "Early spike, pity, drop feed and personal records (O260)". loot.lua calls three functions per kill:
--   ChaosRetentionLoot.begin(monster, owner, tier)                      -> the kill's state (nil: nothing to do)
--   ChaosRetentionLoot.adjustRarity(state, current, target)             -> the rarity id of one gear drop (pity)
--   ChaosRetentionLoot.finish(state, monster, owner, corpse, pos, L, bonus)   first unique, pity counter, feed, records
-- The Drops channel: tools/patch_drops_channel.py adds it to data/chatchannels/chatchannels.xml and writes
-- chatchannels/scripts/drops.lua, which calls channelJoin / channelLeave below. Members get each line in their language.
-- Assumed engine API (TFS 1.4): Player:sendChannelMessage(author, text, type, channelId), Player:sendTextMessage,
-- Container:getItem / addItem, Position:sendMagicEffect. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end
dofile("data/scripts/chaos/retention_loot_core.lua")
ChaosRetentionLootConfig = dofile("data/scripts/chaos/retention_loot_config.lua")

ChaosRetentionLoot = ChaosRetentionLoot or {}
local RL = ChaosRetentionLoot
local C = RetentionLootCore
RL.feed = RL.feed or C.feedNew()
RL.members = RL.members or {} -- player id -> true: the players in the Drops channel
RL.options = RL.options or {} -- player id -> "off" | "unique" | "legendary": the client option "Drop Feed" (default: legendary)

local function cfg()
	return ChaosRetentionLootConfig
end

local function globalByName(name, default)
	local v = name and rawget(_G, name)
	return v ~= nil and v or default
end

local function pcallv(fn, ...)
	local ok, v = pcall(fn, ...)
	if ok then
		return v
	end
	return nil
end

-- ---------------------------------------------------------------- the kill
-- is this a normal hunting kill: not a boss, a summon, a rift, a waystone map, a pocket boss or a tester
local function huntingKill(monster, owner, tier)
	local p = cfg().pity
	if p.skipTiers and p.skipTiers[tier] then
		return false
	end
	if pcallv(function() return monster:getMaster() end) then
		return false
	end
	if ChaosRift and ChaosRift.contentOf and pcallv(ChaosRift.contentOf, monster, owner) then
		return false
	end
	if ChaosWaystoneTiers and ChaosWaystoneTiers.entryOf and pcallv(ChaosWaystoneTiers.entryOf, monster) then
		return false
	end
	if ChaosWaystoneMods and ChaosWaystoneMods.runOfMonster and pcallv(ChaosWaystoneMods.runOfMonster, monster) then
		return false
	end
	if ChaosPocketBoss and ChaosPocketBoss.lootMultOf and (tonumber(pcallv(ChaosPocketBoss.lootMultOf, monster)) or 1) ~= 1 then
		return false
	end
	return true
end

function RL.begin(monster, owner, tier)
	local c = cfg()
	if not c.enabled or not owner then
		return nil
	end
	local tester = Chaos.isTester(owner)
	local state = {tier = tier, tester = tester, hunting = not tester and huntingKill(monster, owner, tier), boosted = false}
	state.pityCount = C.pityRead(owner:getStorageValue(c.pity.storage))
	state.pityDue = state.hunting and C.pityDue(c, state.pityCount) or false
	return state
end

-- one gear drop (loot.lua step 2): `current` and `target` are rarity ids; the pity raises the first drop of a due kill
-- that is magic or better by one rarity. Returns the id the drop gets.
function RL.adjustRarity(state, current, target)
	if not state or not state.pityDue or state.boosted then
		return target
	end
	local R = ChaosRarity
	local final = R.rank(target) > R.rank(current) and target or current
	local boosted = C.pityBoost(cfg(), R.rank(final))
	if not boosted then
		return target
	end
	state.boosted = true
	return R.idOfRank(boosted)
end

-- ---------------------------------------------------------------- what the corpse holds
-- {item, name, rank (1..7), unique, value} of every rarity gear piece and unique at the top level of the corpse
local function scan(corpse)
	local list = {}
	for slot = 0, corpse:getSize() - 1 do
		local item = corpse:getItem(slot)
		if item and item:isItem() then
			local unique = ChaosCrafting and ChaosCrafting.isUnique and ChaosCrafting.isUnique(item) or false
			local rank = 0
			if unique then
				rank = 7
			else
				local id = ChaosCrafting and ChaosCrafting.rarityOf and ChaosCrafting.rarityOf(item) or 0
				if id > 0 then
					rank = ChaosRarity.rank(id)
				end
			end
			if rank > 0 then
				local value = ChaosItemPrices and ChaosItemPrices.sellPrice and tonumber(pcallv(ChaosItemPrices.sellPrice, item, 1)) or 0
				list[#list + 1] = {item = item, rank = rank, unique = unique, value = value}
			end
		end
	end
	return list
end

-- ---------------------------------------------------------------- 1. the first unique
local function giveFirstUnique(state, owner, corpse, corpsePos, L, bonus)
	local c = cfg()
	local f = c.firstUnique
	local action, newRaw = C.firstUniqueStep(c, owner:getStorageValue(f.storage), owner:getLevel(), state.tester)
	if action == "skip" then
		return
	end
	if action == "count" then
		owner:setStorageValue(f.storage, newRaw)
		return
	end
	local voc = pcallv(function() return owner:getVocation():getName() end) or ""
	local entry = C.pickUnique(c, voc, owner:getLevel(), ChaosUniqueByName)
	if not entry then
		print("[Chaos retention] no first unique for the class " .. tostring(voc) .. ": nothing given")
		owner:setStorageValue(f.storage, newRaw)
		return
	end
	local item = L.addToCorpse(corpse, entry.id, 1)
	if not item then
		return -- the corpse took nothing: try again on the next kill
	end
	if ChaosMakeUnique then
		ChaosMakeUnique(item)
	end
	owner:setStorageValue(f.storage, newRaw)
	bonus[#bonus + 1] = "{" .. entry.name .. "}"
	corpsePos:sendMagicEffect(globalByName(f.effect, f.fallbackEffect))
	owner:sendTextMessage(globalByName("MESSAGE_EVENT_ADVANCE", 19), Chaos.t(owner, f.message, entry.name))
	state.gift = item
end

-- ---------------------------------------------------------------- 3. the drop feed
local function defaultType()
	local f = cfg().feed
	return globalByName(f.defaultType, f.fallbackType or 19)
end

-- the players that get the line, and the channel's members among them
local function post(owner, item, kind, itemName, token)
	local c = cfg()
	local f = c.feed
	local name, level = owner:getName(), owner:getLevel()
	local talk = globalByName("TALKTYPE_CHANNEL_O", 8)
	local msgType = defaultType()
	for _, p in ipairs(Game.getPlayers()) do
		if C.shown(c, kind, RL.options[p:getId()] or f.defaultOption) then
			local text = C.feedLine(c, name, level, token, Chaos.t(p, f.text))
			p:sendTextMessage(msgType, text)
			if RL.members[p:getId()] then
				p:sendChannelMessage("", text, talk, f.channelId)
			end
		end
	end
	if f.discord and ChaosDiscord and ChaosDiscord.drop then
		pcall(ChaosDiscord.drop, name, level, itemName, kind)
	end
end

local function feed(state, owner, list)
	local c = cfg()
	local f = c.feed
	if not f.enabled or state.tester or not list[1] then
		return
	end
	local isStaff = pcallv(function() return owner:getGroup():getAccess() end)
	if isStaff then
		return
	end
	-- the best find of the kill
	local best, bestKind
	for _, e in ipairs(list) do
		local kind = C.feedKind(c, e.rank, e.unique)
		if kind and (not best or C.feedRank(c, kind) > C.feedRank(c, bestKind)
			or (C.feedRank(c, kind) == C.feedRank(c, bestKind) and e.rank > best.rank)) then
			best, bestKind = e, kind
		end
	end
	if not best then
		return
	end
	if not C.feedAllow(RL.feed, c, owner:getGuid(), os.time()) then
		return
	end
	local token, name
	if ChaosItemLink and ChaosItemLink.linkFor then
		local ok, t, n = pcall(ChaosItemLink.linkFor, owner, best.item)
		if ok then
			token, name = t, n
		end
	end
	local plain = name or C.cleanName(pcallv(function() return best.item:getName() end) or "Item")
	post(owner, best.item, bestKind, plain, token or ("[" .. plain .. "]"))
end

-- ---------------------------------------------------------------- 4. personal records
local function records(owner, list)
	if not cfg().records.enabled or not ChaosRecords or not ChaosRecords.submit or not ChaosRecords.personalBests then
		return
	end
	local rank, value = C.dropBest(list)
	if rank <= 0 then
		return
	end
	local pc = (Chaos.recordsConfig or {}).personal or {}
	local bests = ChaosRecords.personalBests(owner:getGuid())
	local K = ChaosRecordsCore
	if pc.rarity and rank > (bests[K.slot(pc.rarity, nil, nil)] or 0) then
		ChaosRecords.submit({board = pc.rarity, value = rank, members = {owner}, size = 1})
	end
	if pc.value and value > (bests[K.slot(pc.value, nil, nil)] or 0) then
		ChaosRecords.submit({board = pc.value, value = value, members = {owner}, size = 1})
	end
end

-- ---------------------------------------------------------------- the end of a kill
function RL.finish(state, monster, owner, corpse, corpsePos, L, bonus)
	if not state then
		return
	end
	local c = cfg()
	local list = scan(corpse)
	-- 2. the pity counter: the gear and uniques as they are now
	if state.hunting then
		local bestRank = C.dropBest(list)
		local count = C.pityFinish(c, state.pityCount, true, state.boosted, bestRank)
		if count ~= state.pityCount then
			owner:setStorageValue(c.pity.storage, count)
		end
	end
	-- 3, 4. the feed and the records, before the gift joins the corpse (it never posts)
	local ok, err = pcall(feed, state, owner, list)
	if not ok then
		print("[Chaos retention] drop feed: " .. tostring(err))
	end
	if not state.tester then
		ok, err = pcall(records, owner, list)
		if not ok then
			print("[Chaos retention] records: " .. tostring(err))
		end
	end
	-- 1. the first unique
	ok, err = pcall(giveFirstUnique, state, owner, corpse, corpsePos, L, bonus)
	if not ok then
		print("[Chaos retention] first unique: " .. tostring(err))
	end
end

-- ---------------------------------------------------------------- the Drops channel (chatchannels/scripts/drops.lua)
function RL.channelJoin(player)
	RL.members[player:getId()] = true
	return true
end

function RL.channelLeave(player)
	RL.members[player:getId()] = nil
	return true
end

-- the client option (game_dropfeed): feedopt {mode = "off" | "unique" | "legendary"} on the records opcode 229; the other
-- actions of that opcode are records.lua's and leaderboard.lua's
function RL.setOption(player, mode)
	if mode ~= "off" and mode ~= "unique" and mode ~= "legendary" then
		return false
	end
	RL.options[player:getId()] = mode
	return true
end

local ext = CreatureEvent("ChaosRetentionLootExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= (ChaosOpcodes and ChaosOpcodes.leaderboard or 229) then
		return
	end
	local msg = Chaos.decode and Chaos.decode(buffer)
	if type(msg) ~= "table" or msg.action ~= "feedopt" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "retention.feedopt", 300) then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	RL.setOption(player, data.mode)
end
ext:type("extendedopcode")
ext:register()

local logout = CreatureEvent("ChaosRetentionLootLogout")
function logout.onLogout(player)
	RL.members[player:getId()] = nil
	RL.options[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

local login = CreatureEvent("ChaosRetentionLootLogin")
function login.onLogin(player)
	player:registerEvent("ChaosRetentionLootLogout")
	player:registerEvent("ChaosRetentionLootExtended")
	return true
end
login:type("login")
login:register()

return RL
