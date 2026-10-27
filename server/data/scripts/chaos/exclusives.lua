-- exclusives.lua: the visual exclusives that are never sold (exclusives_config.lua; rules in exclusives_core.lua, tests in
-- server/tests/exclusives_test.lua). Overview: server/README.md "Exclusives".
--
-- Unlocks are account-wide and not tradeable (table chaos_exclusives, server/sql/chaos_exclusives.sql, also created at
-- startup): a boss drop is a direct unlock for the account of the player who rolled it, never an item. What an unlock
-- gives is applied to each character of the account at its login (idempotent) and at once to the characters online:
--   outfit / addons   both looks with both addons (Player:addOutfitAddon)
--   mount, wings, aura, shader    Player:addMount / addWings / addAura / addShader
--   frame             the frame's ownership storage (shop_core.lua frameStorage), as a store frame
--   portal            townportal.lua asks ChaosExclusives.owns for route "boss" styles
--   transmog          ChaosTransmog.grantSet (account-wide there too)
--   pet               ChaosPets.grant on every character (pets are per character)
--   cosmetic          ChaosCosmetics.grant (footprints and outlines of source "boss")
-- Sources:
--   achievement   achievements_data.lua reward.exclusives; granted when the account has the achievement: at login, when
--                 the wardrobe opens and after every new unlock (ChaosAchievements.syncTrack is wrapped, no edit there)
--   boss          ChaosExclusives.bossKill(player, killKey) / worldBossKill(player, bossName), one guarded line in
--                 worldboss.lua, raid.lua, uber.lua and guildboss.lua for every player that gets the kill's rewards:
--                 a personal roll (exclusives_core.lua K.roll); a hit unlocks one reward of the group the account
--                 does not own yet
-- The wardrobe (client game_cosmetics, Collection tab) gets ChaosExclusives.rows(player) in its state (cosmetics.lua).
-- Staff: /exclusive <character>, <key | all>[, revoke]    /exclusive <character>, roll <kill key>   (group 4+)
-- Lua 5.1 / LuaJIT compatible.

if not (Chaos and Chaos.t) then
	if not Chaos then
		dofile("data/scripts/chaos/chaos_constants.lua")
	end
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosExclusivesCore then
	dofile("data/scripts/chaos/exclusives_core.lua")
end
if not ChaosShopCore then
	dofile("data/scripts/chaos/shop_core.lua")
end

ChaosExclusivesConfig = dofile("data/scripts/chaos/exclusives_config.lua")
ChaosExclusives = ChaosExclusives or {}
local M = ChaosExclusives
local K = ChaosExclusivesCore
local cfg = ChaosExclusivesConfig
M.core, M.config = K, cfg
M.owned = M.owned or {} -- account id -> {[key] = true}

local function log(text)
	print("[Chaos exclusives] " .. text)
end

local function achievementsData()
	if ChaosAchievements and ChaosAchievements.data then
		return ChaosAchievements.data
	end
	local ok, d = pcall(dofile, "data/scripts/chaos/achievements_data.lua")
	return ok and d or nil
end

-- the achievements window names the rewards (achievements_core.lua K.rewardText reads reward.exclusives names)

-- ---------------------------------------------------------------- ownership (account-wide)
local function ensureTable()
	db.query(K.sqlCreate(cfg))
end

local function ownedOf(accountId)
	accountId = tonumber(accountId) or 0
	local o = M.owned[accountId]
	if o then
		return o
	end
	o = {}
	local id = db.storeQuery(K.sqlSelect(cfg, accountId))
	if id then
		repeat
			o[result.getString(id, "exclusive")] = true
		until not result.next(id)
		result.free(id)
	end
	M.owned[accountId] = o
	return o
end
M.ownedOf = ownedOf

function M.owns(accountId, key)
	return ownedOf(accountId)[key or ""] == true
end

-- ---------------------------------------------------------------- applying an unlock to a character
local function frameStorage(frame)
	local i = ChaosShopCore.frameIndex(frame)
	return i and ChaosShopCore.frameStorage(Chaos.storage, i) or nil
end

-- gives what exclusive `e` stands for to an online character (idempotent); fresh = it was unlocked just now
function M.apply(player, e, fresh)
	local kind = e.kind
	if kind == "outfit" or kind == "addons" then
		for _, look in ipairs({e.male, e.female}) do
			if not player:hasOutfit(look, 3) then
				player:addOutfitAddon(look, 3)
			end
		end
	elseif kind == "mount" then
		if not player:hasMount(e.id) then
			player:addMount(e.id)
		end
	elseif kind == "wings" then
		if player.addWings then
			player:addWings(e.id)
		end
	elseif kind == "aura" then
		if player.addAura then
			player:addAura(e.id)
		end
	elseif kind == "shader" then
		if player.addShader then
			player:addShader(e.id)
		end
	elseif kind == "frame" then
		local key = frameStorage(e.frame)
		if key and player:getStorageValue(key) <= 0 then
			player:setStorageValue(key, 1)
			if fresh then
				player:setStorageValue(Chaos.storage.shopFrameActive, ChaosShopCore.frameIndex(e.frame))
				if ChaosNameplate and ChaosNameplate.refresh then
					pcall(ChaosNameplate.refresh, player)
				end
			end
		end
	elseif kind == "transmog" then
		if ChaosTransmog and ChaosTransmog.grantSet then
			ChaosTransmog.grantSet(player:getAccountId(), e.set, "boss")
		end
	elseif kind == "pet" then
		local P = ChaosPets
		if P and P.grant and not (P.owns and P.owns(player, e.species)) then
			P.grant(player, e.species, e.source, not fresh)
		end
	elseif kind == "cosmetic" then
		local C = ChaosCosmetics
		if C and C.grant and not C.owns(player:getAccountId(), e.cosmetic) then
			C.grant(player:getAccountId(), e.cosmetic, e.source)
		end
	end
	-- portal: owned through M.owns (townportal.lua route "boss"); nothing to store on the character
end

-- every unlock of the account, on this character (login)
function M.applyAll(player)
	for key in pairs(ownedOf(player:getAccountId())) do
		local e = K.byKey(cfg, key)
		if e then
			local ok, err = pcall(M.apply, player, e, false)
			if not ok then
				log("apply " .. key .. " to " .. player:getName() .. ": " .. tostring(err))
			end
		end
	end
end

-- the account's characters online (a grant reaches them at once)
local function onlineOf(accountId)
	local out = {}
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == accountId then
			out[#out + 1] = p
		end
	end
	return out
end

-- unlock `key` for an account; player = the character that earned it (told; nil for a staff grant of an offline one)
function M.grant(accountId, key, source, player)
	local e = K.byKey(cfg, key)
	if not e then
		return false, "Unknown exclusive " .. tostring(key) .. "."
	end
	accountId = tonumber(accountId) or 0
	local o = ownedOf(accountId)
	if o[e.key] then
		return false, "The account owns " .. e.name .. " already."
	end
	if not db.query(K.sqlInsert(cfg, accountId, e.key, source or e.source, os.time())) then
		return false, "Could not save the unlock."
	end
	o[e.key] = true
	for _, p in ipairs(onlineOf(accountId)) do
		local ok, err = pcall(M.apply, p, e, p == player)
		if not ok then
			log("apply " .. e.key .. " to " .. p:getName() .. ": " .. tostring(err))
		end
	end
	return true
end

function M.revoke(accountId, key)
	local e = K.byKey(cfg, key)
	if not e then
		return false, "Unknown exclusive " .. tostring(key) .. "."
	end
	db.query(K.sqlDelete(cfg, accountId, e.key))
	ownedOf(accountId)[e.key] = nil
	return true
end

local function tell(player, title, text)
	text = Chaos.tx(player, text)
	title = Chaos.t(player, title)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	if ChaosNotify and ChaosNotify.send then
		pcall(ChaosNotify.send, player, title, text, "achievement")
	end
end

-- ---------------------------------------------------------------- achievements
local function hasFn(player)
	local A = ChaosAchievements
	return function(id)
		if not (A and A.has) then
			return false
		end
		local ok, v = pcall(A.has, player, id)
		return ok and v == true
	end
end

-- grant the achievement exclusives the account earned (only adds); returns the names granted now
function M.sync(player)
	local data = achievementsData()
	if not data then
		return {}
	end
	local accountId = player:getAccountId()
	local names = {}
	for _, key in ipairs(K.syncs(cfg, data, hasFn(player), ownedOf(accountId))) do
		if M.grant(accountId, key, "achievement", player) then
			local e = K.byKey(cfg, key)
			names[#names + 1] = K.rewardName(cfg, e)
		end
	end
	if #names > 0 then
		tell(player, "Exclusive unlocked", Chaos.t(player, "Unlocked for your account: %s. See Character > Cosmetics > Collection.",
			table.concat(names, ", ")))
	end
	return names
end

-- achievements.lua calls syncTrack after every new unlock: the exclusives sync rides along (wrapped once, no edit there)
local function wrapAchievements()
	local A = ChaosAchievements
	if A and A.syncTrack and not A.exclusivesWrapped then
		local original = A.syncTrack
		A.syncTrack = function(player)
			original(player)
			local ok, err = pcall(M.sync, player)
			if not ok then
				log("sync " .. player:getName() .. ": " .. tostring(err))
			end
		end
		A.exclusivesWrapped = true
	end
end
M.wrapAchievements = wrapAchievements

-- ---------------------------------------------------------------- boss drops
M.rng = M.rng or math.random

-- one eligible player's personal roll for a kill (killKey: "raid_sovereign", "cinder", ...); returns the key or nil
function M.bossKill(player, killKey)
	local g = K.groupForKill(cfg, killKey)
	if not g or not player then
		return nil
	end
	local accountId = player:getAccountId()
	local key = K.roll(g, ownedOf(accountId), M.rng)
	if not key then
		return nil
	end
	local ok = M.grant(accountId, key, "boss", player)
	if not ok then
		return nil
	end
	local e = K.byKey(cfg, key)
	local k = K.kind(cfg, e.kind) or {}
	tell(player, "Rare drop!", Chaos.t(player, "Rare drop from %s: %s (%s), unlocked for your whole account. %s",
		g.name, e.name, Chaos.t(player, k.name or e.kind):lower(), Chaos.t(player, k.use or "")))
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_RED or CONST_ME_FIREWORK_YELLOW or 29)
	log(string.format("%s (account %d) rolled %s at %s", player:getName(), accountId, key, killKey))
	return key
end

function M.worldBossKill(player, bossName)
	local kill = K.worldBossKill(cfg, bossName)
	return kill and M.bossKill(player, kill) or nil
end

-- ---------------------------------------------------------------- the wardrobe's Collection tab
local clientIds = {}
local function clientItem(serverId)
	if clientIds[serverId] == nil then
		local it = ItemType and ItemType(serverId)
		clientIds[serverId] = it and it:getClientId() or 0
	end
	return clientIds[serverId] > 0 and clientIds[serverId] or nil
end

function M.rows(player)
	return K.rows(cfg, ownedOf(player:getAccountId()), achievementsData(), {clientItem = clientItem,
		female = player:getSex() == PLAYERSEX_FEMALE})
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosExclusivesLogin")
function login.onLogin(player)
	wrapAchievements()
	local ok, err = pcall(function()
		M.sync(player)
		M.applyAll(player)
	end)
	if not ok then
		log("login " .. player:getName() .. ": " .. tostring(err))
	end
	return true
end
login:register()

local startup = GlobalEvent("ChaosExclusivesStartup")
function startup.onStartup()
	ensureTable()
	wrapAchievements()
	local data = achievementsData()
	local ok, shop = pcall(dofile, "data/scripts/chaos/shop_config.lua")
	local okT, transmog = pcall(dofile, "data/scripts/chaos/transmog_config.lua")
	local okP, pets = pcall(dofile, "data/scripts/chaos/pets_config.lua")
	local okR, portal = pcall(dofile, "data/scripts/chaos/townportal_config.lua")
	local okC, cosmetics = pcall(dofile, "data/scripts/chaos/cosmetics_config.lua")
	for _, p in ipairs(K.validate(cfg, {achievements = data, shop = ok and shop or nil, transmog = okT and transmog or nil,
		pets = okP and pets or nil, portal = okR and portal or nil, cosmetics = okC and cosmetics or nil,
		frames = ChaosNameplate and ChaosNameplate.FRAMES or nil})) do
		print("[Warning - Chaos exclusives] " .. p)
	end
	return true
end
startup:register()

-- ---------------------------------------------------------------- staff
local gm = TalkAction("/exclusive")
function gm.onSay(player, words, param)
	if player:getGroup():getId() < cfg.staffGroup then
		return true
	end
	local name, what, mode = param:match("^%s*([^,]+)%s*,%s*([%w_]+)%s*,?%s*([%w_]*)%s*$")
	if not name then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Usage: /exclusive <character>, <key | all>[, revoke]  or  /exclusive <character>, roll, <kill key>"))
		return false
	end
	-- staff never give value (docs/GM_HANDBOOK.md section 2): a grant or a roll needs an administrator, a revoke does not
	if not Chaos.staffCommand(player, words, param, mode ~= "revoke") then
		return false
	end
	local target = Player(name)
	if what == "roll" then
		if not target then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s is not online.", name))
			return false
		end
		local key = M.bossKill(target, mode)
		player:sendTextMessage(MESSAGE_INFO_DESCR, key and Chaos.t(player, "Rolled %s.", key) or Chaos.t(player, "No drop (missed, owned or no group)."))
		return false
	end
	local accountId
	local id = db.storeQuery("SELECT `account_id` FROM `players` WHERE `name` = " .. db.escapeString(name))
	if id then
		accountId = result.getNumber(id, "account_id")
		result.free(id)
	end
	if not accountId then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "No character named %s.", name))
		return false
	end
	local keys = {}
	if what == "all" then
		for _, e in ipairs(cfg.exclusives) do
			keys[#keys + 1] = e.key
		end
	else
		keys[1] = what
	end
	local n, last = 0, nil
	for _, key in ipairs(keys) do
		local ok, err
		if mode == "revoke" then
			ok, err = M.revoke(accountId, key)
		else
			ok, err = M.grant(accountId, key, "gm", target)
		end
		n = n + (ok and 1 or 0)
		last = err or last
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, n > 0 and (mode == "revoke" and Chaos.t(player, "Removed %d exclusive(s) for the account of %s.", n, name)
		or Chaos.t(player, "Granted %d exclusive(s) for the account of %s.", n, name)) or Chaos.t(player, last or "Nothing changed."))
	return false
end
gm:separator(" ")
gm:register()
