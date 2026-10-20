-- Ember, the Help channel assistant (server/README.md "Help channel assistant"). A question in the Help channel goes,
-- as one line appended to helpai.queue in the server folder, to the sidecar server/tools/helpai.py, which asks the
-- model; its answers come back in helpai.answers, read here once a second and posted in the Help channel as "[Ember]".
-- The game thread never touches the network: it appends a line and reads a small file. Without the sidecar (no API
-- key, switched off, not installed) helpai.alive is missing or stale and nothing is queued: the channel works as before.
-- The hook: tools/patch_help_ai.py makes data/chatchannels/scripts/help.lua call ChaosHelpAI.onHelpSpeak(player,
-- type, message) at the end of onSpeak, after the base mute checks; the player's own line is never held back.
-- Pure part: helpai_core.lua (tests/helpai_test.lua); numbers and texts: helpai_config.lua.
-- Assumed engine API (TFS 1.4.2): GlobalEvent onStartup / onThink with interval, Player(name), player:getGuid(),
-- player:getName(), player:getAccountType(), player:sendChannelMessage(author, text, type, channelId),
-- sendChannelMessage(channelId, type, text) (to everyone in the channel, no author), TALKTYPE_CHANNEL_O.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosHelpAICore then
	dofile("data/scripts/chaos/helpai_core.lua")
end

Chaos.helpAIConfig = dofile("data/scripts/chaos/helpai_config.lua")
local cfg = Chaos.helpAIConfig
local H = ChaosHelpAICore
ChaosHelpAI = ChaosHelpAI or {}
local HA = ChaosHelpAI
HA.state = HA.state or H.newState()

local function log(text)
	print("[ChaosHelpAI] " .. text)
end

-- the files, replaceable by the test
HA.fs = HA.fs or {
	read = function(name, limit)
		local f = io.open(name, "rb")
		if not f then
			return nil
		end
		local text = f:read(limit or 65536)
		f:close()
		return text
	end,
	append = function(name, text)
		local f = io.open(name, "ab")
		if not f then
			return false
		end
		f:write(text)
		f:close()
		return true
	end,
	remove = function(name)
		return os.remove(name) and true or false
	end
}
HA.now = HA.now or os.time

local function bareName(value, default)
	if type(value) ~= "string" or not value:match("^[%w_%-%.]+$") or value:sub(1, 1) == "." or value:find("..", 1, true) then
		return default
	end
	return value
end
local QUEUE = bareName(cfg.queueFile, "helpai.queue")
local ANSWERS = bareName(cfg.answersFile, "helpai.answers")
local ALIVE = bareName(cfg.aliveFile, "helpai.alive")
local CHANNEL = cfg.channelId or 7
local TALK = TALKTYPE_CHANNEL_O or 8
local AUTHOR = "[" .. (cfg.botName or "Ember") .. "]"

local function langOf(player)
	if Chaos.lang then
		local ok, lang = pcall(Chaos.lang, player)
		if ok and lang == "pt-BR" then
			return "pt-BR"
		end
	end
	return "en"
end

local function isStaff(player)
	local ok, t = pcall(function()
		return player:getAccountType()
	end)
	return ok and ACCOUNT_TYPE_TUTOR ~= nil and (tonumber(t) or 0) >= ACCOUNT_TYPE_TUTOR
end

local function tell(player, text)
	pcall(function()
		player:sendChannelMessage(AUTHOR, text, TALK, CHANNEL)
	end)
end

-- the sidecar's state ("on", "budget", "off") or nil when it is not running; read at most every 2 s
function HA.sidecar(now)
	if HA.aliveAt and now - HA.aliveAt < 2 then
		return HA.alive
	end
	HA.aliveAt = now
	HA.alive = H.aliveState(HA.fs.read(ALIVE, 512), now, cfg.aliveSeconds)
	return HA.alive
end

-- called by help.lua for every line that passed the base checks; returns nothing (the line is posted as usual)
function HA.onHelpSpeak(player, talkType, message)
	if cfg.enabled == false or not player then
		return
	end
	local ok, err = pcall(function()
		-- (question, explicit), or (nil, reason, explicit)
		local q, second, third = H.detect(message, cfg, isStaff(player))
		if not q then
			if second == "short" and third and HA.sidecar(HA.now()) then
				HA.after(player, H.text(cfg, langOf(player), "short"))
			end
			return
		end
		local explicit = second
		local now = HA.now()
		local state = HA.sidecar(now)
		local lang = langOf(player)
		if state == nil then
			return -- no sidecar: the channel works as before
		end
		if state ~= "on" then
			if explicit then
				HA.after(player, H.text(cfg, lang, "off"))
			end
			return
		end
		local guid = player:getGuid()
		local allowed, reason, wait = H.allow(HA.state, cfg, guid, now, os.date("!%Y-%m-%d", now))
		if not allowed then
			if explicit then
				if reason == "cooldown" then
					HA.after(player, H.text(cfg, lang, "cooldown", cfg.cooldownSeconds or 20, math.max(1, math.ceil(wait or 1))))
				else
					HA.after(player, H.text(cfg, lang, reason == "day" and "day" or reason == "pending" and "pending" or "busy"))
				end
			end
			return
		end
		local id = H.record(HA.state, guid, player:getName(), lang, explicit, now)
		if not HA.fs.append(QUEUE, H.queueLine(id, guid, lang, q, now) .. "\n") then
			HA.state.pending[id] = nil
			log("cannot write " .. QUEUE .. " (check the server folder's rights)")
		end
	end)
	if not ok then
		log("error: " .. tostring(err))
	end
end

-- a reply to the asker only, sent after the player's own line has gone out
function HA.after(player, text)
	local name = player:getName()
	if addEvent then
		addEvent(function()
			local p = Player(name)
			if p then
				tell(p, text)
			end
		end, 100)
	else
		tell(player, text)
	end
end

local function playerFor(p)
	local player = Player(p.name)
	if player and player:getGuid() == p.guid then
		return player
	end
	return nil
end

-- one look at the answers file; returns the number of answers delivered
function HA.poll()
	local text = HA.fs.read(ANSWERS, 65536)
	if not text then
		return 0
	end
	HA.fs.remove(ANSWERS) -- the sidecar makes a new file only while this one is gone
	local now = HA.now()
	local done = 0
	for _, a in ipairs(H.parseAnswers(text)) do
		local p = H.claim(HA.state, cfg, a.id, now)
		local player = p and a.guid == p.guid and playerFor(p)
		if player then
			if a.status == "ok" and a.text ~= "" then
				local lines = H.split(a.text, cfg.maxLineChars, cfg.maxLines)
				if H.audience(HA.state, cfg, now) == "public" and sendChannelMessage then
					for i, line in ipairs(lines) do
						local prefix = AUTHOR .. " " .. (i == 1 and ("@" .. p.name .. ": ") or "")
						pcall(sendChannelMessage, CHANNEL, TALK, prefix .. line)
					end
				else
					for _, line in ipairs(lines) do
						tell(player, line)
					end
				end
				done = done + 1
			elseif a.status == "limit" or p.explicit then
				local key = a.status == "limit" and "busy" or a.status
				tell(player, H.text(cfg, p.lang, key))
			end
		end
	end
	return done
end

if cfg.enabled ~= false then
	local startup = GlobalEvent("ChaosHelpAIStartup")
	function startup.onStartup()
		-- questions and answers of a previous run are stale: their players are gone
		for _, name in ipairs({QUEUE, ANSWERS}) do
			if HA.fs.read(name, 1) then
				HA.fs.remove(name)
			end
		end
		return true
	end
	startup:register()

	local poll = GlobalEvent("ChaosHelpAI")
	function poll.onThink(interval)
		local ok, err = pcall(HA.poll)
		if not ok then
			log("error: " .. tostring(err))
		end
		return true
	end
	poll:interval(cfg.intervalMs or 1000)
	poll:register()
end
