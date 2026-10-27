-- Patch notes window (client game_patchnotes), extended opcode 244 (JSON {action, data}).
-- The notes are Markdown-ish files in data/patchnotes/<id>.md (format: patchnotes_core.lua). They are read by the
-- server, so new notes need no client update: drop a file in the folder; it is picked up within `rescanSeconds`
-- (or at once with /patchnotes reload).
--
--   server -> client  list {weeks = [{id, title, date, new}], selected, open, auto, autoEnabled, dailyFirst}
--                       open: show the window now (menu or !patchnotes)
--                       auto: login auto-open of an unseen week; the client shows it only once the Daily Reward
--                             window is closed or did not show (dailyFirst: the server expects it to show)
--                     note {id, title, date, part, parts, intro = [text], sections = [{name, kind, cont,
--                           items = [{text, level, lead}]}]}   a long note comes in several parts (PN.parts); a section
--                           with cont = true continues the previous part's last section
--                     changelog {available, server = {date}, published, entries = [{id, date, ts, pr, text, tags,
--                           client, pending}]}   the Changelog tab (changelog_core.lua): every change that shipped,
--                           from data/changelog/changelog.json (server/tools/gen_changelog.py, run by the kit update);
--                           over 8192 bytes it goes through Chaos.sendChunked (the client listens with
--                           ProtocolGame.registerExtendedJSONOpcode)
--   client -> server  open {id?} | get {id} | seen {id} (the week was shown) | auto {enabled} | changelog
--                     closed (the window was closed: the next window of the login queue may open)
--
-- Login order: when daily.lua's login window queue (ChaosLoginWindows) exists, the auto-open is one entry of it
-- ("patchnotes", order Chaos.dailyStreak.loginOrder.patchnotes or 30, after the Daily Reward's 20): the server sends it
-- only after the client reported the daily window closed (or it was not wanted), and `closed` lets the queue go on.
-- Without that queue, the server sends it after the daily's own login delay with dailyFirst, and the client waits
-- for the daily window by itself (PatchNotesView.autoStep). Either way the client also never shows it over a visible
-- daily window, and the client daily window waits while this one (id patchNotesWindow) is on screen.
--
-- "Last seen" and the "Don't show automatically" setting are per account (table chaos_patchnotes, created here if
-- missing; also in sql/chaos_patchnotes.sql), so a new week opens once per account, not once per character.

if not (Chaos and Chaos.t) then
	if not Chaos then
		dofile("data/scripts/chaos/chaos_constants.lua")
	end
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/patchnotes_core.lua")
dofile("data/scripts/chaos/changelog_core.lua")

local PN = ChaosPatchNotes
local CL = ChaosChangelog
local OPCODE = ChaosOpcodes.patchnotes
local TABLE = "chaos_patchnotes"

PN.config = {
	dir = "data/patchnotes/",
	rescanSeconds = 60, -- the folder is listed again at most this often
	-- login: sent after the Daily Reward's own login delay, so the client already knows whether that window is up
	loginExtraMs = 1500,
	loginFallbackMs = 4500, -- when Chaos.daily has no openDelayMs
	changelogFile = "data/changelog/changelog.json",
	changelogCooldown = 5 -- seconds between two changelog requests of one player (the answer is up to ~40 KB)
}
local cfg = PN.config

PN.notes, PN.byId, PN.scannedAt = {}, {}, nil

local function log(msg)
	print("[ChaosPatchNotes] " .. msg)
end

-- ---------------------------------------------------------------- files
local function listDir(dir)
	if not io.popen then
		return nil
	end
	local windows = package and package.config and package.config:sub(1, 1) == "\\"
	local cmd = windows and ('dir /b "' .. dir:gsub("/", "\\") .. '" 2>nul') or ("ls -1 '" .. dir .. "' 2>/dev/null")
	local ok, handle = pcall(io.popen, cmd)
	if not ok or not handle then
		return nil
	end
	local out = handle:read("*a")
	handle:close()
	return out
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local body = f:read("*a")
	f:close()
	return body
end

-- reads every notes file; `force` ignores rescanSeconds. Without io.popen, data/patchnotes/index.txt (one file name
-- per line) is the list.
function PN.scan(force)
	local now = os.time()
	if not force and PN.scannedAt and now - PN.scannedAt < cfg.rescanSeconds then
		return PN.notes
	end
	PN.scannedAt = now
	local listing = listDir(cfg.dir)
	if not listing or listing == "" then
		listing = readFile(cfg.dir .. "index.txt") or ""
	end
	local notes, byId = {}, {}
	local twins = PN.twinNames(listing)
	for _, name in ipairs(PN.fileNames(listing)) do
		local body = readFile(cfg.dir .. name)
		if body then
			local id = name:sub(1, -4)
			local ok, note = pcall(PN.parse, body, id)
			if ok and note then
				-- the pt-BR twin <id>.pt-br.md: shown to players whose language is pt-BR; English where it is missing
				local twin = twins[id] and readFile(cfg.dir .. twins[id])
				if twin then
					local tok, tr = pcall(PN.parse, twin, id)
					if tok and tr then
						local why = PN.compare(note, tr)
						if why then
							log(twins[id] .. " does not match " .. name .. " (" .. why .. ")")
						end
						note.tr = {[PN.TWIN_LANG] = tr}
					else
						log("could not parse " .. twins[id] .. ": " .. tostring(tr))
					end
				end
				notes[#notes + 1] = note
				byId[id] = note
			else
				log("could not parse " .. name .. ": " .. tostring(note))
			end
		end
	end
	PN.sort(notes)
	local changed = #notes ~= #PN.notes or (notes[1] and PN.notes[1] and notes[1].id ~= PN.notes[1].id)
	PN.notes, PN.byId = notes, byId
	if changed or force then
		log(string.format("%d notes file(s), newest %s", #notes, notes[1] and notes[1].id or "-"))
	end
	return notes
end

-- ---------------------------------------------------------------- changelog
-- The file is read again at most every rescanSeconds; a missing, oversize or broken file keeps what was loaded before
-- (or none). The encoded answer is kept, so a request costs no JSON encoding.
local changelog = {raw = nil, buffer = nil, count = 0, at = nil, warned = nil}

local function readCapped(path, limit)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local body = f:read(limit + 1)
	f:close()
	return body
end

function PN.loadChangelog(force)
	local now = os.time()
	if not force and changelog.at and now - changelog.at < cfg.rescanSeconds then
		return changelog.buffer
	end
	changelog.at = now
	local raw = readCapped(cfg.changelogFile, CL.limits.fileBytes)
	if raw == changelog.raw and changelog.buffer then
		return changelog.buffer
	end
	local cl, why
	if raw then
		cl, why = CL.decode(raw, json and json.decode)
	end
	if raw and not cl then
		if changelog.warned ~= why then
			changelog.warned = why
			log("changelog file refused (" .. tostring(why) .. "): " .. (changelog.buffer and "the last good one stays" or "none shown"))
		end
		return changelog.buffer
	end
	changelog.raw, changelog.warned = raw, nil
	changelog.count = cl and #cl.entries or 0
	local ok, buffer = pcall(json.encode, {action = "changelog", data = CL.payload(cl)})
	if ok and type(buffer) == "string" then
		changelog.buffer = buffer
	end
	return changelog.buffer
end

local lastChangelog = {} -- player id -> os.time of the last answer

function PN.sendChangelog(player)
	local id, now = player:getId(), os.time()
	if lastChangelog[id] and now - lastChangelog[id] < cfg.changelogCooldown then
		return false
	end
	lastChangelog[id] = now
	local buffer = PN.loadChangelog()
	if not buffer then
		return false
	end
	if #buffer > Chaos.extendedOpcodeMax then
		return Chaos.sendChunked(player, OPCODE, buffer)
	end
	player:sendExtendedOpcode(OPCODE, buffer)
	return true
end

-- ---------------------------------------------------------------- account state
local tableReady = false
local function ensureTable()
	if tableReady then
		return true
	end
	tableReady = db.query("CREATE TABLE IF NOT EXISTS `" .. TABLE .. "` (" ..
		"`account_id` int(11) NOT NULL, `seen_key` varchar(80) NOT NULL DEFAULT '', " ..
		"`auto_open` tinyint(1) NOT NULL DEFAULT 1, `updated` bigint(20) NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8") and true or false
	return tableReady
end

-- returns seenKey ("" when never seen), autoEnabled
function PN.state(player)
	ensureTable()
	local rows = Chaos.select("SELECT `seen_key`, `auto_open` FROM `" .. TABLE .. "` WHERE `account_id` = " ..
		player:getAccountId(), {{"seen_key", "s"}, {"auto_open", "n"}})
	local row = rows[1]
	if not row then
		return "", true
	end
	return row.seen_key or "", row.auto_open ~= 0
end

local function save(player, seenKey, autoEnabled)
	ensureTable()
	db.query(string.format("INSERT INTO `%s` (`account_id`, `seen_key`, `auto_open`, `updated`) VALUES (%d, %s, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `seen_key` = VALUES(`seen_key`), `auto_open` = VALUES(`auto_open`), `updated` = VALUES(`updated`)",
		TABLE, player:getAccountId(), db.escapeString(seenKey or ""), autoEnabled and 1 or 0, os.time()))
end

function PN.markSeen(player, note)
	local seenKey, autoEnabled = PN.state(player)
	local key = PN.maxKey(seenKey, PN.key(note))
	if key ~= seenKey then
		save(player, key, autoEnabled)
	end
end

-- ---------------------------------------------------------------- the Daily Reward at login
-- Without the login window queue only: true when the stock Daily Reward window is expected to open at this login
-- (openOnLogin and today's reward not claimed by this character). The client does not trust this blindly: it waits
-- for the daily window to be closed, or not to show up within a few seconds.
function PN.dailyFirst(player)
	local daily = Chaos.daily
	if not daily or not daily.openOnLogin then
		return false
	end
	return player:getStorageValue(Chaos.storage.dailyLastClaim) ~= Chaos.dayKey()
end

local function loginDelay()
	local daily = Chaos.daily
	if daily and tonumber(daily.openDelayMs) then
		return tonumber(daily.openDelayMs) + cfg.loginExtraMs
	end
	return cfg.loginFallbackMs
end

-- ---------------------------------------------------------------- protocol
local function langOf(player)
	return Chaos.lang and Chaos.lang(player) or "en"
end

function PN.sendList(player, opts)
	opts = opts or {}
	local notes = PN.scan()
	local seenKey, autoEnabled = PN.state(player)
	local selected = opts.selected and PN.byId[opts.selected] and opts.selected or (notes[1] and notes[1].id) or ""
	Chaos.send(player, OPCODE, "list", {
		weeks = PN.summary(notes, seenKey, nil, langOf(player)),
		selected = selected,
		open = opts.open and true or false,
		auto = opts.auto and true or false,
		autoEnabled = autoEnabled,
		dailyFirst = opts.dailyFirst and true or false
	})
	return selected
end

function PN.sendNote(player, id)
	local note = PN.byId[id]
	if not note then
		return false
	end
	-- in parts (PN.parts): one large message did not arrive in the test client
	for _, part in ipairs(PN.parts(PN.localize(note, langOf(player)))) do
		Chaos.send(player, OPCODE, "note", part)
	end
	return true
end

function PN.open(player, id)
	local selected = PN.sendList(player, {open = true, selected = id})
	if selected ~= "" then
		PN.sendNote(player, selected)
	end
end

-- the unseen week to open by itself at this login, or nil
function PN.loginNote(player)
	local seenKey, autoEnabled = PN.state(player)
	return PN.autoOpen(PN.scan(), seenKey, autoEnabled)
end

local function sendAuto(player, dailyFirst)
	local note = PN.loginNote(player)
	if note then
		PN.sendList(player, {auto = true, selected = note.id, dailyFirst = dailyFirst})
		PN.sendNote(player, note.id)
	end
end

-- daily.lua's login window queue, or nil when this server has none
local function loginQueue()
	local LW = rawget(_G, "ChaosLoginWindows")
	if type(LW) == "table" and type(LW.register) == "function" and type(LW.closed) == "function" then
		return LW
	end
	return nil
end

-- join it (at load and again at startup, so the order the scripts load in does not matter; register replaces)
local function joinLoginQueue()
	local LW = loginQueue()
	if LW then
		local order = Chaos.dailyStreak and Chaos.dailyStreak.loginOrder and Chaos.dailyStreak.loginOrder.patchnotes or 30
		LW.register("patchnotes", order, function(player)
			return PN.loginNote(player) ~= nil
		end, function(player)
			sendAuto(player, false)
		end)
	end
	return LW
end
joinLoginQueue()

local login = CreatureEvent("ChaosPatchNotesLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPatchNotesExtended")
	player:registerEvent("ChaosPatchNotesLogout")
	if loginQueue() then
		return true -- the queue sends it in its turn
	end
	addEvent(function(cid)
		local p = Player(cid)
		if p then
			sendAuto(p, PN.dailyFirst(p))
		end
	end, loginDelay(), player:getId())
	return true
end
login:type("login")
login:register()

local ext = CreatureEvent("ChaosPatchNotesExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	-- per action (ratelimit.lua): requests that hit the database cannot be flooded
	if Chaos.limited and Chaos.limited(player, "patchnotes." .. tostring(msg.action), 300) then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	local id = PN.validId(data.id) and data.id or nil
	if msg.action == "open" then
		PN.open(player, id)
	elseif msg.action == "get" then
		PN.scan()
		if id then
			PN.sendNote(player, id)
		end
	elseif msg.action == "seen" then
		local note = id and PN.byId[id]
		if note then
			PN.markSeen(player, note)
		end
	elseif msg.action == "changelog" then
		PN.sendChangelog(player)
	elseif msg.action == "closed" then
		local LW = loginQueue()
		if LW then
			LW.closed(player, "patchnotes")
		end
	elseif msg.action == "auto" then
		local seenKey = PN.state(player)
		save(player, seenKey, data.enabled == true)
	end
end
ext:type("extendedopcode")
ext:register()

local startup = GlobalEvent("ChaosPatchNotesStartup")
function startup.onStartup()
	joinLoginQueue()
	ensureTable()
	PN.scan(true)
	PN.loadChangelog(true)
	local dc = rawget(_G, "ChaosDiscordConfig")
	addEvent(function() PN.tryPost() end, ((dc and dc.patchnotes and dc.patchnotes.startDelaySeconds) or 30) * 1000)
	return true
end
startup:register()

-- ---------------------------------------------------------------- Discord
-- A note not announced yet goes to the Discord queue (ANNOUNCE channel) in English and pt-BR; patchnotes_core.lua
-- PN.discordRun decides, the last note announced is kept in server_config (discord_config.lua patchnotes.postedKey).
local function configGet(key)
	local id = db.storeQuery("SELECT `value` FROM `server_config` WHERE `config` = " .. db.escapeString(key))
	if not id then
		return ""
	end
	local v = result.getString(id, "value")
	result.free(id)
	return v or ""
end

local function configSet(key, value)
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE " ..
		"`value` = VALUES(`value`)", db.escapeString(key), db.escapeString(value)))
end

function PN.postDiscord()
	local DC, X, D = rawget(_G, "ChaosDiscordConfig"), rawget(_G, "ChaosDiscord"), rawget(_G, "ChaosDiscordCore")
	if not (DC and X and X.queue and D) or DC.enabled == false or not DC.patchnotes or not D.enabled(DC, "patchnotes") then
		return 0
	end
	local o = DC.patchnotes
	PN.scan()
	return PN.discordRun({
		notes = PN.notes, today = os.date("%Y-%m-%d"), postedKey = configGet(o.postedKey), opts = o,
		event = function(title, text) return D.patchnotes(DC, title, text) end,
		queue = function(ev) return X.queue(ev) end,
		save = function(key) configSet(o.postedKey, key) end,
		log = log
	})
end

local function tryPost()
	local ok, err = pcall(PN.postDiscord)
	if not ok then
		log("Discord post failed: " .. tostring(err))
	end
end

PN.tryPost = tryPost

local post = GlobalEvent("ChaosPatchNotesDiscord")
function post.onThink(interval)
	tryPost()
	return true
end
local dcfg = rawget(_G, "ChaosDiscordConfig")
if not dcfg then
	pcall(dofile, "data/scripts/chaos/discord_config.lua")
	dcfg = rawget(_G, "ChaosDiscordConfig")
end
if post.interval then
	post:interval(((dcfg and dcfg.patchnotes and dcfg.patchnotes.checkSeconds) or 3600) * 1000)
end
post:register()

local logout = CreatureEvent("ChaosPatchNotesLogout")
function logout.onLogout(player)
	lastChangelog[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

-- !patchnotes opens the window. Staff (/patchnotes): reload (read the folder and the changelog now), unseen (forget this account's
-- last seen week, to test the login auto-open), status.
local function onCommand(player, words, param)
	param = (param or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if words == "/patchnotes" and player:getGroup():getAccess() and param ~= "" then
		if param == "reload" then
			PN.scan(true)
			PN.loadChangelog(true)
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Patch notes reloaded: %d file(s), newest %s; changelog %d entries.", #PN.notes, PN.notes[1] and PN.notes[1].id or "-", changelog.count))
		elseif param == "unseen" then
			local _, autoEnabled = PN.state(player)
			save(player, "", autoEnabled)
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Patch notes: this account has seen nothing now."))
		else
			local seenKey, autoEnabled = PN.state(player)
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Patch notes: %d file(s), newest %s; this account " ..
				"last saw %s, auto-open %s.", #PN.notes, PN.notes[1] and PN.notes[1].id or "-",
				seenKey ~= "" and seenKey or "nothing", autoEnabled and "on" or "off"))
		end
		return false
	end
	PN.open(player)
	return false
end

-- staff only (players open the window from the menu)
local talk = TalkAction("/patchnotes")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false -- players open it from the menu
	end
	return onCommand(player, words, param)
end
talk:separator(" ")
talk:register()
