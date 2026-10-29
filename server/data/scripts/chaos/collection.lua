-- collection.lua: the collection score. Every cosmetic an account owns gives points; milestones grant purely visual
-- rewards once and keep them (titles, a name plate frame, a footstep trail, a chat colour). Rules: collection_core.lua
-- (server/tests/collection_test.lua), numbers: collection_config.lua, README "Collection score".
--
-- Counted, from data that already exists (nothing is listed by hand):
--   cosmetics   the chaos_cosmetics unlocks of the account (cosmetics.lua): spell skins, kill / level-up / rare-loot
--               effects, emotes, loot labels, chat colours, footprints, outlines
--   wardrobe    outfits and addons, mounts, wings, auras, shaders the character owns (wardrobe.lua); a character that
--               owns everything by its group counts none of it
--   frames      the name plate frames the character owns (the store's frame storages)
--   titles      the titles the character holds (titles.lua), up to the cap
-- Wardrobe items, frames and titles are kept in chaos_collection when first seen, so a character's purchases stay in the
-- score of the account (every character adds its own) and a title that expired still counts. Cosmetics are read live.
-- The score is checked at login, when the Cosmetics window opens and after a store delivery or a cosmetic grant.
-- Rewards: a title (the "collection" source of titles.lua, with a plate frame), a cosmetic of source "collection"
-- (ChaosCosmetics.grant). Granted once per account (the "m:<milestone>" row), never taken back.
--
-- API: ChaosCollection.refresh(player) -> view | nil    ChaosCollection.view(player)    ChaosCollection.touch(accountId)
--      ChaosCollection.scoreOf(accountId) -> score of the last check
-- No opcode of its own: the cosmetics `state` carries `score` (cosmetics.lua sendState). Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosCollectionCore then
	dofile("data/scripts/chaos/collection_core.lua")
end

ChaosCollectionConfig = dofile("data/scripts/chaos/collection_config.lua")
ChaosCollection = ChaosCollection or {}
local M = ChaosCollection
local K = ChaosCollectionCore
local cfg = ChaosCollectionConfig
M.core, M.config = K, cfg

M.state = M.state or {} -- account id -> {entries = {[entry] = true}, claimed = {[milestone key] = time}, score}
local pending = {} -- account id -> true while a sweep is scheduled
local ctxCache

local function log(text)
	print("[Chaos collection] " .. text)
end

-- ---------------------------------------------------------------- stored entries
local function stateOf(accountId)
	accountId = tonumber(accountId) or 0
	local st = M.state[accountId]
	if st then
		return st
	end
	st = {entries = {}, claimed = {}, score = 0}
	local id = db.storeQuery(K.sqlSelect(cfg, accountId))
	if id then
		repeat
			local entry, at = result.getString(id, "entry"), result.getNumber(id, "at")
			local key = entry:match("^m:(.+)$")
			if key then
				st.claimed[key] = at
			else
				st.entries[entry] = true
			end
		until not result.next(id)
		result.free(id)
	end
	M.state[accountId] = st
	return st
end

local function store(accountId, entry)
	db.query(K.sqlInsert(cfg, accountId, entry, os.time()))
end

-- ---------------------------------------------------------------- the catalogue the points come from
local function context()
	if ctxCache then
		return ctxCache
	end
	local C = ChaosCosmeticsConfig
	local shop = ChaosShopConfig
	if not (C and shop and ChaosWardrobe and ChaosWardrobe.catalogueOf) then
		return nil
	end
	local cosmetics = {}
	for _, c in ipairs(C.cosmetics or {}) do
		cosmetics[c.key] = c
	end
	-- the Chaos outfit shaders (while their switch is on) are unlocks of the account like a cosmetic, priced in
	-- cosmetics_config.lua
	for _, s in ipairs((C.outfitShaders and C.outfitShaders.enabled) and C.outfitShaders.list or {}) do
		cosmetics[s.key] = {key = s.key, kind = "shader", source = "store", price = s.price}
	end
	local ok, entry = pcall(ChaosWardrobe.catalogueOf, 1)
	local ix = K.lookIndex(ok and entry and entry.cat or nil)
	local ex = ChaosExclusivesConfig and ChaosExclusivesConfig.exclusives or {}
	ctxCache = {cosmetics = cosmetics, prices = K.priceMap(shop, ix), exclusive = K.exclusiveSet(ex, ix)}
	return ctxCache
end
M.context = context

-- ---------------------------------------------------------------- what a character owns now
local function isStaff(player)
	local g = player:getGroup()
	return g and g:getAccess() == true
end

local function characterEntries(player)
	local out = {}
	if ChaosWardrobe and ChaosWardrobe.list and (cfg.staffCountsWardrobe or not isStaff(player)) then
		local okL, list = pcall(ChaosWardrobe.list, player)
		if okL and type(list) == "table" then
			for _, key in ipairs(K.wardrobeOwned(list)) do
				out[#out + 1] = "w:" .. key
			end
		end
	end
	local SC = ChaosShopCore
	if SC and SC.FRAMES and SC.frameStorage then
		for i, frame in ipairs(SC.FRAMES) do
			local key = SC.frameStorage(Chaos.storage, i)
			if key and player:getStorageValue(key) > 0 then
				out[#out + 1] = "f:" .. frame
			end
		end
	end
	if ChaosTitles and ChaosTitles.of and not isStaff(player) then
		local okT, titles = pcall(ChaosTitles.of, player)
		for _, t in ipairs(okT and titles or {}) do
			if type(t.key) == "string" and not t.key:find("^collection:") and t.key ~= "staff" then
				out[#out + 1] = "t:" .. K.sqlKey(t.key)
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- the check
local function notify(player, names)
	local text = table.concat(names, ", ")
	player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Collection reward unlocked: %s.", text))
	if ChaosNotify and ChaosNotify.send then
		pcall(ChaosNotify.send, player, "Collection", text .. " unlocked.", "achievement")
	end
end

local function claim(player, st, milestone)
	local accountId = player:getAccountId()
	local now = os.time()
	st.claimed[milestone.key] = now
	store(accountId, "m:" .. milestone.key)
	local names = {}
	for _, r in ipairs(milestone.rewards or {}) do
		if r.kind == "cosmetic" and ChaosCosmetics and ChaosCosmetics.grant then
			ChaosCosmetics.grant(accountId, r.key, "collection")
			names[#names + 1] = (context() and context().cosmetics[r.key] or {}).name or r.key
		elseif r.kind == "title" then
			names[#names + 1] = r.text
		end
	end
	log(string.format("%s (account %d) reached %d points: %s", player:getName(), accountId, milestone.points, table.concat(names, ", ")))
	notify(player, names)
	return names
end

-- Checks the account from this character: new wardrobe items, frames and titles are stored, the score is added up, the
-- milestones reached are claimed. Returns the window's view (collection_core.lua K.view) or nil without the catalogue.
function M.refresh(player)
	local ctx = context()
	if not ctx then
		return nil
	end
	local accountId = player:getAccountId()
	local st = stateOf(accountId)
	for _, entry in ipairs(characterEntries(player)) do
		if not st.entries[entry] then
			st.entries[entry] = true
			store(accountId, entry)
		end
	end
	local entries = {}
	for entry in pairs(st.entries) do
		entries[#entries + 1] = entry
	end
	if ChaosCosmetics and ChaosCosmetics.ownedOf then
		for key in pairs(ChaosCosmetics.ownedOf(accountId)) do
			entries[#entries + 1] = "c:" .. key
		end
	end
	table.sort(entries)
	local score, groups = K.score(cfg, ctx, entries)
	st.score = score
	local claimedNow = false
	for _, m in ipairs(K.due(cfg, score, st.claimed)) do
		claim(player, st, m)
		claimedNow = true
	end
	if claimedNow and ChaosNameplate and ChaosNameplate.refresh then
		pcall(ChaosNameplate.refresh, player)
	end
	return K.view(cfg, score, groups, st.claimed, ctx.cosmetics)
end

function M.view(player)
	local ok, v = pcall(M.refresh, player)
	if not ok then
		log("check failed: " .. tostring(v))
		return nil
	end
	return v
end

function M.scoreOf(accountId)
	local st = M.state[tonumber(accountId) or 0]
	return st and st.score or 0
end

-- a purchase or a grant changed what the account owns: check it in a moment (once, however many come together)
function M.touch(accountId)
	accountId = tonumber(accountId) or 0
	if pending[accountId] then
		return
	end
	pending[accountId] = true
	addEvent(function(id)
		pending[id] = nil
		for _, p in ipairs(Game.getPlayers()) do
			if p:getAccountId() == id then
				if ChaosCosmetics and ChaosCosmetics.sendState then
					pcall(ChaosCosmetics.sendState, p, false) -- checks the score and tells the window
				else
					M.view(p)
				end
				return
			end
		end
	end, cfg.syncDelayMs or 2500, accountId)
end

-- ---------------------------------------------------------------- titles
local function registerTitles()
	if not (ChaosTitles and ChaosTitles.register) then
		return false
	end
	ChaosTitles.register("collection", function(player)
		local st = stateOf(player:getAccountId())
		local out = K.titlesOf(cfg, st.claimed)
		return #out > 0 and out or nil
	end)
	return true
end
registerTitles()

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosCollectionLogin")
function login.onLogin(player)
	M.touch(player:getAccountId())
	return true
end
login:register()

local logout = CreatureEvent("ChaosCollectionLogout")
function logout.onLogout(player)
	local id = player:getAccountId()
	addEvent(function(accountId)
		for _, p in ipairs(Game.getPlayers()) do
			if p:getAccountId() == accountId then
				return
			end
		end
		M.state[accountId] = nil -- the last character of the account left: read it again next time
	end, 1000, id)
	return true
end
logout:register()

local startup = GlobalEvent("ChaosCollectionStartup")
function startup.onStartup()
	db.query(K.sqlCreate(cfg))
	registerTitles()
	-- a store delivery and a cosmetic grant change the score: the check follows them (wrapped once, no edit there)
	local S = ChaosShop
	if S and S.deliver and not S.collectionWrapped then
		local original = S.deliver
		S.deliver = function(player, offer, ...)
			local r = original(player, offer, ...)
			if r == true then
				pcall(M.touch, player:getAccountId())
			end
			return r
		end
		S.collectionWrapped = true
	end
	local C = ChaosCosmetics
	if C and C.grant and not C.collectionWrapped then
		local original = C.grant
		C.grant = function(accountId, key, source)
			local ok, err = original(accountId, key, source)
			if ok and source ~= "collection" then
				pcall(M.touch, accountId)
			end
			return ok, err
		end
		C.collectionWrapped = true
	end
	local problems = K.validate(cfg, {cosmetics = ChaosCosmeticsConfig and ChaosCosmeticsConfig.cosmetics,
		frames = ChaosNameplate and ChaosNameplate.FRAMES})
	for _, p in ipairs(problems) do
		print("[Warning - Chaos collection] " .. p)
	end
	return true
end
startup:register()
