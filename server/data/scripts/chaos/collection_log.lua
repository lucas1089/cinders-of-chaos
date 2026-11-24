-- collection_log.lua: the Collection log (O753), engine glue. Rules collection_log_core.lua, numbers collection_log_config.lua,
-- client game_collectionlog (Hunt > Records > Collection Log). server/README.md "Collection log (O753)".
--   ChaosCollectionLog.note(player, itemId, n)   a unique / set piece / raid unique dropped for this character: one row of
--        chaos_collection_log (count, first and last date). Called by loot.lua (L.rollUniques with an owner), itemsets.lua
--        (grantChase), pocketboss.lua, pinnacle.lua and raid.lua. Cards are read from the Deck of Cards (no note).
--   extended opcode ChaosOpcodes.collectionLog (170), JSON {action, data}:
--        client -> server  sync
--        server -> client  state {rows = [{i, c, n, g, s, k, d}], groups = [{k, l, a}], pity = [{k, l, a, d, n}], owned, seen,
--                          total}   (over 8192 bytes: Chaos.send splits it, the client joins it)
-- Owned = in the log, in chaos_conquest_seen (the drops of before O753) or a Deck copy; seen = a monster that lists it was
-- killed (chaos_bestiary). Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCollectionLogCore then
	dofile("data/scripts/chaos/collection_log_core.lua")
end

ChaosCollectionLog = ChaosCollectionLog or {}
local X = ChaosCollectionLog
local CL = ChaosCollectionLogCore

X.config = X.config or dofile("data/scripts/chaos/collection_log_config.lua")
local OPCODE = ChaosOpcodes.collectionLog or X.config.opcode

local function cfg()
	return X.config
end

local function T()
	return cfg().table
end

local function log(msg)
	print("[Chaos collection log] " .. tostring(msg))
end

local tableReady = false
local function ensureTable()
	if tableReady then
		return true
	end
	if not (db and db.query) then
		return false
	end
	local ok, res = pcall(db.query, CL.sqlCreate(T()))
	tableReady = ok and res ~= false
	return tableReady
end

-- ---------------------------------------------------------------- the drops
X.cache = X.cache or {} -- guid -> {[id] = {count, at}} once read
function X.note(player, itemId, n)
	if not (cfg().enabled and player and tonumber(itemId)) then
		return false
	end
	if Chaos.isTester and Chaos.isTester(player) then
		return false
	end
	local guid = player:getGuid()
	local now = os.time()
	n = math.max(1, math.floor(tonumber(n) or 1))
	if ensureTable() then
		pcall(db.query, CL.sqlNote(T(), guid, itemId, n, now))
	end
	local c = X.cache[guid]
	if c then
		local o = c[tonumber(itemId)]
		if o then
			o.count = o.count + n
		else
			c[tonumber(itemId)] = {count = n, at = now}
		end
	end
	return true
end

local function ownedOf(guid)
	if X.cache[guid] then
		return X.cache[guid]
	end
	local logRows, seenRows = {}, {}
	if ensureTable() then
		local ok, rows = pcall(Chaos.select, CL.sqlSelect(T(), guid), {{"item_id", "n"}, {"count", "n"}, {"first_at", "n"}})
		logRows = ok and rows or {}
	end
	local ok2, rows2 = pcall(Chaos.select, string.format("SELECT `item_id`, `at` FROM `chaos_conquest_seen` WHERE `player_id` = %d",
		guid), {{"item_id", "n"}, {"at", "n"}})
	seenRows = ok2 and rows2 or {}
	X.cache[guid] = CL.merge(logRows, seenRows)
	return X.cache[guid]
end

local function killedOf(guid)
	local k = {}
	pcall(function()
		for _, r in ipairs(Chaos.select(string.format("SELECT `monster` FROM `chaos_bestiary` WHERE `player_id` = %d AND " ..
				"`kills` > 0", guid), {{"monster", "s"}})) do
			k[tostring(r.monster):lower()] = true
		end
	end)
	return k
end

-- ---------------------------------------------------------------- the catalog (built once)
local function itemName(id)
	local ok, name = pcall(function() return ItemType(id):getName() end)
	return ok and name and name ~= "" and name or tostring(id)
end

local function clientId(id)
	local ok, cid = pcall(function() return ItemType(id):getClientId() end)
	return ok and tonumber(cid) or id
end

function X.catalog()
	if X.catalogCache then
		return X.catalogCache
	end
	local pin = {}
	local P = Chaos.pinnacleConfig
	for _, b in ipairs(P and P.bosses or {}) do
		if b.unique and b.unique.id then
			pin[b.unique.id] = true
		end
	end
	local raid = {}
	local R = ChaosRaidConfig
	for _, u in ipairs(R and R.uniques or {}) do
		raid[#raid + 1] = {id = u.id, name = u.name}
	end
	local cards = {}
	if ChaosCardsCore and ChaosCardsCore.cardIds then
		for _, id in ipairs(ChaosCardsCore.cardIds()) do
			cards[#cards + 1] = {id = id, name = itemName(id)}
		end
	end
	local order = {}
	for i, g in ipairs(cfg().groupOrder or {}) do
		order[g] = i
	end
	local cat = CL.catalog({uniques = ChaosUniqueItems or {}, raid = raid, cards = cards, pinnacle = pin, order = order})
	local setNames = {}
	for _, s in ipairs(ChaosItemSets and ChaosItemSets.sets or {}) do
		if s.key then
			setNames[s.key] = s.name
		end
	end
	for _, r in ipairs(cat) do
		r.c = clientId(r.id)
	end
	X.catalogCache = cat
	X.groupsCache = CL.groups(cfg(), cat, setNames)
	return cat
end

-- ---------------------------------------------------------------- the window
function X.payload(player)
	local guid = player:getGuid()
	local cat = X.catalog()
	local owned = {}
	for id, o in pairs(ownedOf(guid)) do
		owned[id] = o
	end
	if ChaosCardDeck and ChaosCardDeck.owned then
		for _, r in ipairs(cat) do
			if r.g == "card" then
				local n = ChaosCardDeck.owned(player, r.id)
				if n > 0 then
					owned[r.id] = {count = n, at = owned[r.id] and owned[r.id].at or 0}
				end
			end
		end
	end
	local rows = CL.rows(cat, {owned = owned, killed = killedOf(guid)})
	for i, r in ipairs(rows) do
		r.c = cat[i].c
	end
	local sum = CL.summary(rows)
	return {rows = rows, groups = X.groupsCache, pity = ChaosChasePity and ChaosChasePity.view(player) or {},
		owned = sum.owned, seen = sum.seen, total = sum.total}
end

function X.send(player)
	return Chaos.send(player, OPCODE, "state", X.payload(player))
end

local ext = CreatureEvent("ChaosCollectionLogExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE or not cfg().enabled then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "sync" or Chaos.limited(player, "collectionlog.sync", cfg().rateLimitMs) then
		return
	end
	local ok, err = pcall(X.send, player)
	if not ok then
		log(err)
	end
end
ext:register()

local login = CreatureEvent("ChaosCollectionLogLogin")
function login.onLogin(player)
	player:registerEvent("ChaosCollectionLogExtended")
	player:registerEvent("ChaosCollectionLogLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosCollectionLogLogout")
function logout.onLogout(player)
	X.cache[player:getGuid()] = nil
	return true
end
logout:register()

local startup = GlobalEvent("ChaosCollectionLogStartup")
function startup.onStartup()
	ensureTable()
	return true
end
startup:register()
