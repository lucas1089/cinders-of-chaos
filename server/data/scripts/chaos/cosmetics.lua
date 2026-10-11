-- cosmetics.lua: cosmetic kinds of the store and the achievements (cosmetic only, never power):
--   spell effect skins  a class line's spells show a recoloured variant of their effects; every viewer sees it
--                       (data/spells/scripts/chaos/_common.lua asks ChaosCosmetics.swapFor during a cast)
--   kill effects        an effect on the monster's tile when the character lands the killing blow
--   loot label accents  the background of the character's own highlighted ground loot labels (client game_groundlabels);
--                       the rarity colours stay
--   chat name colours   the character's name in chat, for every viewer (client game_cosmetics colours the name only)
--   footprints          prints behind the walking character, for every viewer; outlines: a coloured glow behind the
--                       character, for every viewer. Both are drawn by each client (game_cosmeticfx) from the "looks"
--                       this script sends (who wears which art); the server does nothing per step
-- Data: cosmetics_config.lua. Rules: cosmetics_core.lua (server/tests/cosmetics_test.lua). Unlocks are account-wide
-- (table chaos_cosmetics, server/sql/chaos_cosmetics.sql, also created here at startup); the choice is per character
-- (storages 7100940 - 7100949). Store offers: {kind = "unlock", unlock = "cosmetic_<key>"} (shop_services.lua asks
-- ChaosCosmetics.storeUnlock). Achievement cosmetics are granted at login and when the window opens.
--
-- ============================================================== API (other scripts)
--   ChaosCosmetics.swapFor(playerId, spellId, type, name) -> variant name or nil (type fx | missile | vfx | vmissile)
--   ChaosCosmetics.storeUnlock(unlockName) -> {name, done, owned = fn(player), grant = fn(player)} | nil
--   ChaosCosmetics.storePreview(player, unlockName) -> true when it showed something (shop.lua "preview")
--   ChaosCosmetics.offerPreview(unlockName) -> the store offer's preview table for the client, or nil
--   ChaosCosmetics.grant(accountId, key, source) / revoke(accountId, key) / owns(accountId, key)
-- ==============================================================
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.cosmetics (225):
--   client -> server  open | select {kind, id, line} (id 0 = the default; line for spell skins) | preview {id} | close
--   server -> client  state {open, line, lineName, rows = [K.rows + item (client id of the icon)]}      style {accent}  (the character's own label accent)
--                     colors {names = {[name] = "#rrggbb"}, full}  (chat name colours of online characters)
--                     looks {names = {[name] = {f = print art, o = glow art, p = 1 pulse} | false}, full}  (footprints
--                     and outlines of online characters; game_cosmetics hands them to game_cosmeticfx)
--                     tryfx {kind, art, pulse}  (a preview the asking player's client draws on its own character)
--                     state also carries collection = the exclusives of every visual kind (exclusives.lua), when loaded
--                     result {ok, text}
-- Staff: /cosmetic <character>, <key | all>[, revoke]   /cosmetic <character>, sync   (achievement cosmetics and the
-- reward track of achievements.lua: granted at login, when the window opens and after new achievement unlocks)
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCosmeticsCore then
	dofile("data/scripts/chaos/cosmetics_core.lua")
end
if not ChaosVfx then
	pcall(dofile, "data/lib/chaos_vfx.lua")
end
if ChaosVfx and not ChaosVfx.bone_burst then
	pcall(dofile, "data/lib/chaos_vfx_art.lua")
end
if not ChaosFx then
	pcall(dofile, "data/lib/chaos_fx.lua")
end

ChaosCosmeticsConfig = dofile("data/scripts/chaos/cosmetics_config.lua")
ChaosCosmetics = ChaosCosmetics or {}
local M = ChaosCosmetics
local K = ChaosCosmeticsCore
local cfg = ChaosCosmeticsConfig
local OPCODE = (ChaosOpcodes and ChaosOpcodes.cosmetics) or cfg.opcode
M.core, M.config = K, cfg

M.owned = M.owned or {} -- account id -> {[key] = true}
M.active = M.active or {} -- player id -> {killfx = vfx name, lines = {[line] = id}}
M.colors = M.colors or {} -- character name -> "#rrggbb" (online characters with a chat colour)
M.looks = M.looks or {} -- character name -> {f = print art, o = glow art, p = 1} (online characters with a footprint / outline)
M.lookOwner = M.lookOwner or {} -- character name -> creature id of the session that set M.looks (a reconnect's old session
-- may log out after the new one logged in: it must not clear the new session's look)
local lastPreview = {} -- player id -> ms

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- ---------------------------------------------------------------- unlocks (account-wide)
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
			o[result.getString(id, "cosmetic")] = true
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

function M.grant(accountId, key, source)
	local c = K.byKey(cfg, key)
	if not c then
		return false, "Unknown cosmetic " .. tostring(key) .. "."
	end
	local o = ownedOf(accountId)
	if o[c.key] then
		return false, "The account owns " .. c.name .. " already."
	end
	if not db.query(K.sqlInsert(cfg, accountId, c.key, source or c.source, os.time())) then
		return false, "Could not save the cosmetic."
	end
	o[c.key] = true
	return true
end

function M.revoke(accountId, key)
	local c = K.byKey(cfg, key)
	if not c then
		return false, "Unknown cosmetic " .. tostring(key) .. "."
	end
	db.query(K.sqlDelete(cfg, accountId, c.key))
	ownedOf(accountId)[c.key] = nil
	return true
end

-- ---------------------------------------------------------------- what a character shows
local function chosenOf(player)
	local st = cfg.storage
	local chosen = {lines = {}}
	for _, kind in ipairs({"killfx", "lootbeam", "chatcolor", "footprint", "outline"}) do
		chosen[kind] = math.max(0, player:getStorageValue(st[kind]))
	end
	for _, l in ipairs(cfg.lines) do
		chosen.lines[l.key] = math.max(0, player:getStorageValue(st.skinBase + l.slot))
	end
	return chosen
end

local function owned(player, id)
	local c = K.byId(cfg, id)
	return c and M.owns(player:getAccountId(), c.key) and c or nil
end

local function send(player, action, data)
	return Chaos.sendChunked(player, OPCODE, json.encode({action = action, data = data}))
end

local function broadcastColor(name, color)
	local msg = json.encode({action = "colors", data = {names = {[name] = color or false}}})
	for _, p in ipairs(Game.getPlayers()) do
		p:sendExtendedOpcode(OPCODE, msg)
	end
end

-- footprints and outlines: one character's look to everyone online (false = none any more)
local function broadcastLook(name, look)
	local msg = json.encode({action = "looks", data = {names = {[name] = look or false}}})
	for _, p in ipairs(Game.getPlayers()) do
		p:sendExtendedOpcode(OPCODE, msg)
	end
end

-- {f, o, p} of the chosen footprint / outline (nil when the character shows neither)
local function lookOf(chosen, player)
	local foot = chosen.footprint > 0 and owned(player, chosen.footprint)
	local glow = chosen.outline > 0 and owned(player, chosen.outline)
	foot = foot and foot.kind == "footprint" and foot or nil
	glow = glow and glow.kind == "outline" and glow or nil
	if not foot and not glow then
		return nil
	end
	return {f = foot and foot.art or nil, o = glow and glow.art or nil, p = glow and glow.pulse and 1 or nil}
end

local function sameLook(a, b)
	if a == nil or b == nil then
		return a == b
	end
	return a.f == b.f and a.o == b.o and a.p == b.p
end

-- rebuild the cache of a character from its storages (a choice that is not owned any more is dropped)
local function refresh(player, announce)
	local chosen = chosenOf(player)
	local a = {lines = {}}
	local kill = chosen.killfx > 0 and owned(player, chosen.killfx)
	a.killfx = kill and kill.kind == "killfx" and kill.vfx or nil
	for line, id in pairs(chosen.lines) do
		local c = id > 0 and owned(player, id)
		if c and c.kind == "spellskin" and c.line == line then
			a.lines[line] = id
		end
	end
	M.active[player:getId()] = a
	local beam = chosen.lootbeam > 0 and owned(player, chosen.lootbeam)
	send(player, "style", {accent = beam and beam.kind == "lootbeam" and beam.accent or false})
	local chat = chosen.chatcolor > 0 and owned(player, chosen.chatcolor)
	local color = chat and chat.kind == "chatcolor" and chat.color or nil
	local name = player:getName()
	if M.colors[name] ~= color then
		M.colors[name] = color
		if announce then
			broadcastColor(name, color)
		end
	end
	local look = lookOf(chosen, player)
	M.lookOwner[name] = player:getId()
	if not sameLook(M.looks[name], look) then
		M.looks[name] = look
		if announce then
			broadcastLook(name, look)
		end
	end
end
M.refresh = refresh

-- the variant of an effect for a cast of `spellId` by player `pid` (_common.lua); nil = the default effect
function M.swapFor(pid, spellId, kind, name)
	local a = M.active[pid]
	if not a then
		return nil
	end
	local skin = K.skinForSpell(cfg, spellId, function(line) return a.lines[line] end)
	return skin and K.swap(skin, spellId, kind, name) or nil
end

-- ---------------------------------------------------------------- achievement cosmetics
local achievementNames
local function achievementName(id)
	if not achievementNames then
		achievementNames = {}
		local data = ChaosAchievements and ChaosAchievements.data
		if not data then
			local ok, d = pcall(dofile, "data/scripts/chaos/achievements_data.lua")
			data = ok and d or nil
		end
		for _, a in ipairs(data and data.list or {}) do
			achievementNames[a.id] = a.name
		end
	end
	return achievementNames[id or ""]
end

-- the reward track facts of an account: {points, categories} (achievements.lua ChaosAchievements.accountOf)
local function trackFacts(accountId)
	local A, AK = ChaosAchievements, ChaosAchievementsCore
	if not (A and A.accountOf and A.index and AK and AK.completedCategories) then
		return nil
	end
	local ok, acc = pcall(A.accountOf, accountId)
	if not ok or type(acc) ~= "table" then
		return nil
	end
	return {points = acc.points or 0, categories = AK.completedCategories(A.index, acc.ids or {})}
end
M.trackFacts = trackFacts

-- grant every achievement cosmetic the account has earned (idempotent, only adds). player = the character to tell
-- (nil: nobody, e.g. a staff re-sync of an offline account). Returns the names granted now.
local function syncAccount(accountId, player)
	local A = ChaosAchievements
	if not A or not A.has then
		return {}
	end
	accountId = tonumber(accountId) or 0
	local names = {}
	local facts = trackFacts(accountId)
	for _, key in ipairs(K.syncs(cfg, function(id) return A.has(player or accountId, id) end, ownedOf(accountId), facts)) do
		if M.grant(accountId, key, "achievement") then
			names[#names + 1] = K.byKey(cfg, key).name
		end
	end
	if #names > 0 and player then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Cosmetic unlocked: " .. table.concat(names, ", ") ..
			". Choose it in Character > Cosmetics.")
		-- the achievement reward track: a toast too (only names granted now: M.grant is false for an owned one)
		if ChaosNotify and ChaosNotify.send then
			pcall(ChaosNotify.send, player, "Reward track", table.concat(names, ", ") .. " unlocked. Choose it in Character > Cosmetics.",
				"achievement")
		end
	end
	return names
end
M.syncAccount = syncAccount

local function sync(player)
	return syncAccount(player:getAccountId(), player)
end
M.sync = sync -- achievements.lua calls it after new unlocks (the reward track)

-- ---------------------------------------------------------------- the window
local function lineOf(player)
	local voc = player:getVocation()
	return K.lineOfVocation(cfg, voc and voc:getName() or "")
end

local clientIds = {}
local function clientId(serverId)
	if not serverId or not ItemType then
		return nil
	end
	if clientIds[serverId] == nil then
		local it = ItemType(serverId)
		clientIds[serverId] = it and it:getClientId() or 0
	end
	return clientIds[serverId] > 0 and clientIds[serverId] or nil
end

function M.sendState(player, open)
	local line = lineOf(player)
	local rows = K.rows(cfg, ownedOf(player:getAccountId()), chosenOf(player), {line = line, achievementName = achievementName,
		categoryName = function(key)
			local ix = ChaosAchievements and ChaosAchievements.index
			local cat = ix and ix.catByKey and ix.catByKey[key]
			return cat and cat.name or nil
		end})
	for _, r in ipairs(rows) do
		r.item = clientId(K.byId(cfg, r.id).icon)
	end
	local l = K.index(cfg).lines[line or ""]
	-- the Collection tab: the exclusives of every visual kind and how each is earned (exclusives.lua)
	local collection
	if ChaosExclusives and ChaosExclusives.rows then
		local ok, res = pcall(ChaosExclusives.rows, player)
		collection = ok and res or nil
	end
	send(player, "state", {open = open or nil, line = line, lineName = l and l.name, rows = rows, collection = collection})
end

local function reply(player, ok, text)
	send(player, "result", {ok = ok, text = text})
end

-- id 0 = back to the default (spell skins: of `line`)
local function choose(player, kind, id, line)
	local c, reason = K.choose(cfg, ownedOf(player:getAccountId()), kind, id)
	if c == nil then
		return reply(player, false, reason)
	end
	if kind == "spellskin" then
		line = c and c.line or line
		if not K.index(cfg).lines[line or ""] then
			return reply(player, false, "Unknown class line.")
		end
	end
	player:setStorageValue(K.storageOf(cfg, kind, line), c and c.id or 0)
	refresh(player, true)
	M.sendState(player, false)
	reply(player, true, c and (c.name .. " is in use.") or "Back to the default look.")
end

-- an effect only `player` sees, at the tile in front of it (a Vfx name or a chaos_fx.lua name)
local function showTo(player, kind, name)
	local pos = player:getPosition()
	if kind == "vfx" then
		local e = ChaosVfx and ChaosVfx[name]
		if e then
			Position(pos.x + e.dx, pos.y + e.dy, pos.z):sendMagicEffect(e.id, player)
			return true
		end
	elseif kind == "fx" then
		local id = ChaosFx and ChaosFx[name]
		if id then
			pos:sendMagicEffect(id, player)
			return true
		end
	elseif kind == "missile" or kind == "vmissile" then
		local from = Position(pos.x - 3, pos.y - 2, pos.z)
		if kind == "missile" and ChaosFxMissile and ChaosFxMissile[name] then
			from:sendDistanceEffect(pos, ChaosFxMissile[name], player)
			return true
		end
		local m = ChaosVfxMissile and ChaosVfxMissile[name]
		if m then
			Position(from.x + m.dx, from.y + m.dy, from.z):sendDistanceEffect(Position(pos.x + m.dx, pos.y + m.dy, pos.z), m.id, player)
			return true
		end
	end
	return false
end

-- the preview of a cosmetic: its effects one after another, seen by the asking player only
function M.preview(player, c)
	if not c or (c.kind ~= "spellskin" and c.kind ~= "killfx" and not K.DRAWN[c.kind]) then
		return false
	end
	local pid, t = player:getId(), nowMs()
	if lastPreview[pid] and t - lastPreview[pid] < (cfg.previewCooldownMs or 1500) then
		return false
	end
	lastPreview[pid] = t
	if K.DRAWN[c.kind] then
		-- footprints and outlines: the asking client draws it on its own character for a few seconds (game_cosmeticfx)
		send(player, "tryfx", {kind = c.kind, art = c.art, pulse = c.pulse and 1 or nil})
		return true
	end
	for i, e in ipairs(K.previewOf(c)) do
		addEvent(function(id, kind, name)
			local p = Player(id)
			if p then
				showTo(p, kind, name)
			end
		end, (i - 1) * 700, pid, e.type, e.name)
	end
	return true
end

-- ---------------------------------------------------------------- the store (shop_services.lua, shop.lua)
function M.storeUnlock(unlockName)
	local c = K.ofUnlock(cfg, unlockName)
	if not c then
		return nil
	end
	return {
		name = c.name,
		done = "Choose it in Character > Cosmetics (account-wide, cosmetic only).",
		owned = function(player)
			return M.owns(player:getAccountId(), c.key)
		end,
		grant = function(player)
			local ok, err = M.grant(player:getAccountId(), c.key, "store")
			if ok then
				M.sendState(player, false)
			end
			return ok, err
		end
	}
end

function M.offerPreview(unlockName)
	return K.offerPreview(K.ofUnlock(cfg, unlockName))
end

function M.storePreview(player, unlockName)
	return M.preview(player, K.ofUnlock(cfg, unlockName))
end

-- ---------------------------------------------------------------- events
local ext = CreatureEvent("ChaosCosmeticsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if type(msg) ~= "table" or type(msg.action) ~= "string" or msg.action == "close" then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "cosmetics." .. msg.action, 300) then
		return
	end
	local ok, err = pcall(function()
		if msg.action == "open" then
			sync(player)
			M.sendState(player, true)
		elseif msg.action == "select" then
			choose(player, tostring(data.kind or ""), data.id, type(data.line) == "string" and data.line or nil)
		elseif msg.action == "preview" then
			local c = K.byId(cfg, data.id)
			if not M.preview(player, c) and c then
				reply(player, false, "Wait a moment before the next preview.")
			end
		end
	end)
	if not ok then
		print("[Chaos cosmetics] " .. msg.action .. " failed: " .. tostring(err))
	end
end
ext:register()

local login = CreatureEvent("ChaosCosmeticsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosCosmeticsExtended")
	player:registerEvent("ChaosCosmeticsLogout")
	local ok, err = pcall(function()
		sync(player)
		refresh(player, false)
		send(player, "colors", {names = M.colors, full = true})
		local color = M.colors[player:getName()]
		if color then
			broadcastColor(player:getName(), color)
		end
		send(player, "looks", {names = M.looks, full = true})
		local look = M.looks[player:getName()]
		if look then
			broadcastLook(player:getName(), look)
		end
	end)
	if not ok then
		print("[Chaos cosmetics] login failed: " .. tostring(err))
	end
	return true
end
login:register()

local logout = CreatureEvent("ChaosCosmeticsLogout")
function logout.onLogout(player)
	M.active[player:getId()] = nil
	lastPreview[player:getId()] = nil
	M.colors[player:getName()] = nil
	if M.lookOwner[player:getName()] == player:getId() then
		M.looks[player:getName()] = nil
		M.lookOwner[player:getName()] = nil
	end
	return true
end
logout:register()

-- kill effects: the killing blow (the engine's last hit) of a character on a monster that is nobody's summon
local death = CreatureEvent("ChaosCosmeticsDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	if not killer or not killer.isPlayer or not killer:isPlayer() then
		return true
	end
	local a = M.active[killer:getId()]
	if a and a.killfx and Vfx then
		Vfx(creature:getPosition(), a.killfx)
	end
	return true
end
death:register()

if EventCallback then
	local spawn = EventCallback
	spawn.onSpawn = function(self, position, startup, artificial)
		if not self:getMaster() then
			self:registerEvent("ChaosCosmeticsDeath")
		end
		return true
	end
	spawn:register()
end

-- ---------------------------------------------------------------- staff
local gm = TalkAction("/cosmetic")
function gm.onSay(player, words, param)
	if player:getGroup():getId() < cfg.staffGroup then
		return true
	end
	local name, what, mode = param:match("^%s*([^,]+)%s*,%s*([%w_]+)%s*,?%s*(%w*)%s*$")
	if not name then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Usage: /cosmetic <character>, <key | all | sync>[, revoke]")
		return false
	end
	local accountId
	local id = db.storeQuery("SELECT `account_id` FROM `players` WHERE `name` = " .. db.escapeString(name))
	if id then
		accountId = result.getNumber(id, "account_id")
		result.free(id)
	end
	if not accountId then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "No character named " .. name .. ".")
		return false
	end
	if what == "sync" then
		-- re-sync the achievement cosmetics (reward track too) of the account; only adds, never takes back
		local target = Player(name)
		local granted = syncAccount(accountId, target)
		if target then
			refresh(target, true)
			M.sendState(target, false)
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, #granted > 0 and string.format("Synced the account of %s: %s.", name,
			table.concat(granted, ", ")) or ("The account of " .. name .. " has every cosmetic it earned."))
		return false
	end
	local keys = {}
	if what == "all" then
		for _, c in ipairs(cfg.cosmetics) do
			keys[#keys + 1] = c.key
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
			ok, err = M.grant(accountId, key, "gm")
		end
		n = n + (ok and 1 or 0)
		last = err or last
	end
	local target = Player(name)
	if target then
		refresh(target, true)
		M.sendState(target, false)
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, n > 0 and string.format("%s %d cosmetic(s) for the account of %s.",
		mode == "revoke" and "Removed" or "Granted", n, name) or (last or "Nothing changed."))
	return false
end
gm:separator(" ")
gm:register()

-- ---------------------------------------------------------------- startup checks
local function catalog()
	local out = {}
	local function names(t)
		if not t then
			return nil
		end
		local s = {}
		for k in pairs(t) do
			s[k] = true
		end
		return s
	end
	out.fx, out.missile, out.vfx, out.vmissile = names(ChaosFx), names(ChaosFxMissile), names(ChaosVfx), names(ChaosVfxMissile)
	return out
end

local startup = GlobalEvent("ChaosCosmeticsStartup")
function startup.onStartup()
	ensureTable()
	local achievements
	if achievementName("level_50") then
		achievements = {}
		for id, n in pairs(achievementNames) do
			achievements[id] = n
		end
	end
	local categories, maxPoints -- the reward track (achievements.lua loaded)
	local AI, AK = ChaosAchievements and ChaosAchievements.index, ChaosAchievementsCore
	if AI and AK and AK.maxPoints then
		categories, maxPoints = {}, AK.maxPoints(AI)
		for _, c in ipairs(AI.categories or {}) do
			categories[c.key] = true
		end
	end
	local problems, warnings = K.validate(cfg, {catalog = catalog(), achievements = achievements, shop = ChaosShopConfig,
		categories = categories, maxPoints = maxPoints})
	for _, p in ipairs(problems) do
		print("[Warning - Chaos cosmetics] " .. p)
	end
	for _, w in ipairs(warnings) do
		print("[Chaos cosmetics] " .. w)
	end
	return true
end
startup:register()
