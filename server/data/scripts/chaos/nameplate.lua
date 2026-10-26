-- Name plates (client game_nameplate, extended opcode ChaosOpcodes.nameplate)
--
-- Over every player the client draws a stack: the active title (coloured by its source), the guild in braces, and the
-- name on a small frame (base patch 0022). This script tells the clients what to draw; the titles come from the
-- registry in titles.lua (ChaosTitles.register), the guild from the engine (player:getGuild()).
--
-- When plates are sent (one line per player, see nameplate_core.lua for the format):
--   login            the player's own plate to everyone who sees them (and to the player), and the plates of the
--                    players around to the player
--   appearing        the client asks for creature ids it has no plate for (q|id,id,...), batched
--   changes          every checkSeconds the plates of online players are rebuilt; a changed plate (new title, title
--                    gone, guild joined or left, frame) goes to everyone who sees the player. !title and
--                    ChaosNameplate.refresh(player) send at once.
-- The active title: the one chosen with !title <name> (stored by key in chaos_player_titles), else the default: staff
-- titles first, then the most recently earned. !title none hides it.
--
-- Public API:
--   ChaosNameplate.refresh(player)   rebuild and send the plate now if it changed (call after granting a title)
--   ChaosNameplate.plateOf(player)   {cid, title, color, guild, frame} as sent
--   ChaosTitles.register(...)         see titles.lua
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosNameplate or not ChaosNameplate.collect then
	dofile("data/scripts/chaos/nameplate_core.lua")
end
if not ChaosTitles or not ChaosTitles.register then
	dofile("data/scripts/chaos/titles.lua")
end

local N = ChaosNameplate
local T = ChaosTitles
local OPCODE = ChaosOpcodes.nameplate or 248
local TABLE = "chaos_player_titles"
local CHECK_SECONDS = 5
local QUERY_MAX = 40 -- ids per client query
local SEND_CHUNK = 30 -- plates per message

N.choice = N.choice or {} -- guid -> chosen title key ("none" = hidden; nil = default)
N.sent = N.sent or {} -- cid -> last encoded plate sent to spectators

local function log(msg)
	print("[ChaosNameplate] " .. msg)
end

-- ---------------------------------------------------------------- stored choice
local tableReady = false
local function ensureTable()
	if not tableReady then
		tableReady = db.query("CREATE TABLE IF NOT EXISTS `" .. TABLE .. "` (" ..
			"`player_id` int(11) NOT NULL, `title_key` varchar(64) NOT NULL DEFAULT '', " ..
			"`updated` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
			and true or false
	end
	return tableReady
end

local function loadChoice(player)
	ensureTable()
	local rows = Chaos.select("SELECT `title_key` FROM `" .. TABLE .. "` WHERE `player_id` = " .. player:getGuid(),
		{{"title_key", "s"}})
	local key = rows[1] and rows[1].title_key or ""
	N.choice[player:getGuid()] = key ~= "" and key or nil
end

local function saveChoice(player, key)
	ensureTable()
	N.choice[player:getGuid()] = key
	if key then
		db.query(string.format("INSERT INTO `%s` (`player_id`, `title_key`, `updated`) VALUES (%d, %s, %d) " ..
			"ON DUPLICATE KEY UPDATE `title_key` = VALUES(`title_key`), `updated` = VALUES(`updated`)",
			TABLE, player:getGuid(), db.escapeString(key), os.time()))
	else
		db.query(string.format("DELETE FROM `%s` WHERE `player_id` = %d", TABLE, player:getGuid()))
	end
end

-- ---------------------------------------------------------------- plates
function N.plateOf(player)
	local title = N.pick(T.of(player), N.choice[player:getGuid()])
	local guild = player:getGuild()
	return {
		cid = player:getId(),
		title = title and title.text or "",
		color = title and title.color or "",
		guild = guild and guild:getName() or "",
		frame = N.frameOf(title, T.frameOf(player))
	}
end

local function sendLines(target, lines)
	for i = 1, #lines, SEND_CHUNK do
		local last = math.min(#lines, i + SEND_CHUNK - 1)
		target:sendExtendedOpcode(OPCODE, table.concat(lines, "\n", i, last))
	end
end

local function spectatorsOf(player)
	return Game.getSpectators(player:getPosition(), true, true) or {}
end

-- send the player's plate to everyone who sees them (themselves included)
local function broadcast(player, line)
	for _, spectator in ipairs(spectatorsOf(player)) do
		spectator:sendExtendedOpcode(OPCODE, line)
	end
end

function N.refresh(player, force)
	if not player or not player:isPlayer() then
		return false
	end
	local line = N.encode(N.plateOf(player))
	if force or N.sent[player:getId()] ~= line then
		N.sent[player:getId()] = line
		broadcast(player, line)
		return true
	end
	return false
end

-- plates of the given creature ids (players only) to one player
local function sendPlates(target, ids)
	local lines = {}
	for _, id in ipairs(ids) do
		local p = Player(id)
		if p and N.mayQuery(target, p) then
			local line = N.sent[id] or N.encode(N.plateOf(p))
			N.sent[id] = line
			lines[#lines + 1] = line
		end
	end
	if #lines > 0 then
		sendLines(target, lines)
	end
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosNameplateLogin")
function login.onLogin(player)
	player:registerEvent("ChaosNameplateExtended")
	player:registerEvent("ChaosNameplateLogout")
	loadChoice(player)
	N.sent[player:getId()] = nil
	addEvent(function(cid)
		local p = Player(cid)
		if not p then
			return
		end
		N.refresh(p, true)
		local ids = {}
		for _, other in ipairs(spectatorsOf(p)) do
			if other ~= p then
				ids[#ids + 1] = other:getId()
			end
		end
		sendPlates(p, ids)
	end, 1500, player:getId())
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosNameplateLogout")
function logout.onLogout(player)
	N.sent[player:getId()] = nil
	N.choice[player:getGuid()] = nil
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosNameplateExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local ids = N.decodeQuery(buffer, QUERY_MAX)
	if #ids > 0 then
		sendPlates(player, ids)
	end
end
ext:type("extendedopcode")
ext:register()

-- rebuild every online player's plate; send the ones that changed. Each player is checked once per CHECK_SECONDS, spread
-- over that many one-second slices by creature id (400 players: 80 per tick instead of 400 in one 50-100 ms tick)
local slice = 0
local think = GlobalEvent("ChaosNameplateThink")
function think.onThink(interval)
	slice = (slice + 1) % CHECK_SECONDS
	for _, player in ipairs(Game.getPlayers()) do
		if player:getId() % CHECK_SECONDS == slice then
			N.refresh(player)
		end
	end
	return true
end
think:interval(1000)
think:register()

local startup = GlobalEvent("ChaosNameplateStartup")
function startup.onStartup()
	ensureTable()
	local names = {}
	for _, s in ipairs(T.sources) do
		names[#names + 1] = s.name
	end
	log(string.format("opcode %d, title sources: %s", OPCODE, table.concat(names, ", ")))
	return true
end
startup:register()

-- ---------------------------------------------------------------- title choice (the Achievements window)
local function describe(t, active)
	return t.text .. (t == active and " (active)" or "")
end

local function onTitle(player, words, param)
	param = N.clean(param)
	local list = T.of(player)
	local choice = N.choice[player:getGuid()]
	local lower = param:lower()
	if lower == "" then
		if #list == 0 then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player,
				"You hold no titles yet. Titles come from the weekly leaderboards, the guild siege, seasons and more; they show above your name."))
			return false
		end
		local active = N.pick(list, choice)
		local parts = {}
		for _, t in ipairs(list) do
			parts[#parts + 1] = describe(t, active)
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Your titles: %s%s. Pick one in the Achievements window.",
			table.concat(parts, ", "), choice == "none" and Chaos.t(player, " (hidden)") or ""))
		return false
	end
	if lower == "none" or lower == "off" or lower == "hide" then
		saveChoice(player, "none")
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Your title is hidden."))
	elseif lower == "auto" or lower == "default" then
		saveChoice(player, nil)
		local t = N.pick(list, nil)
		player:sendTextMessage(MESSAGE_INFO_DESCR, t and Chaos.t(player, "Your title follows the newest you earn: %s.", t.text)
			or Chaos.t(player, "Your title follows the newest you earn."))
	else
		local t = N.find(list, param)
		if not t then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "You do not hold the title \"%s\".", param))
			return false
		end
		saveChoice(player, t.key)
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Your title is now %s.", t.text))
	end
	N.refresh(player)
	return false
end

-- the Achievements window's title selector (achievements.lua, action "title"): "auto", "none" or a title's text
function N.setTitle(player, choice)
	return onTitle(player, "", choice)
end

