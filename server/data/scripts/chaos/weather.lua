-- Weather (client game_chaosweather, extended opcode ChaosOpcodes.weather = 114; server/README.md "Weather on the client
-- (O208)"). This replaces the base weather's rain (customs/globalevents/rain.lua, switched off by tools/patch_base_rain.py),
-- which sent a map effect to every player every 100 ms. Here the server only decides the weather (weather_core.lua: the
-- base's dice, the areas of weather_config.lua) and sends a player one small JSON message
--     set {k = "rain", i = 1..3, f = fadeMs}   or   set {k = "none", f = fadeMs}
-- when he logs in, asks (client -> server `hello`), crosses into or out of a weather area, or the weather changes. A
-- GlobalEvent looks at the players every tickMs (3 s). The client draws the rain itself.
-- Staff: /weather rain [1-3] | clear | info. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosWeather or not ChaosWeather.decide then
	dofile("data/scripts/chaos/weather_core.lua")
end
ChaosWeatherConfig = dofile("data/scripts/chaos/weather_config.lua")

local W = ChaosWeather
local OPCODE = (ChaosOpcodes and ChaosOpcodes.weather) or 114
W.state = W.state or W.newState()
W.sent = W.sent or {}

local function cfg()
	return ChaosWeatherConfig
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function log(text)
	print("[ChaosWeather] " .. tostring(text))
end

-- sends one player what he should see (only when it changed, or always with force); true when a message went out
function W.sync(player, force)
	local msg = W.decide(W.sent, player:getId(), W.state, cfg(), player:getPosition(), force)
	if not msg then
		return false
	end
	return Chaos.send(player, OPCODE, "set", msg)
end

-- every online player; returns how many got a message
function W.syncAll(force)
	local sent = 0
	for _, player in ipairs(Game.getPlayers()) do
		if W.sync(player, force) then
			sent = sent + 1
		end
	end
	return sent
end

function W.tick()
	W.roll(W.state, cfg(), math.random, nowMs())
	return W.syncAll(false)
end

local think = GlobalEvent("ChaosWeatherThink")
function think.onThink(interval)
	if cfg().enabled ~= false then
		local ok, err = pcall(W.tick)
		if not ok then
			log(err)
		end
	end
	return true
end
think:interval(cfg().tickMs)
think:register()

local startup = GlobalEvent("ChaosWeatherStartup")
function startup.onStartup()
	W.startup(W.state, cfg(), math.random, nowMs())
	W.sent = {}
	return true
end
startup:type("startup")
startup:register()

-- login: the client may not listen yet, so it also asks with `hello` once its module is up (the first send is a try)
local login = CreatureEvent("ChaosWeatherLogin")
function login.onLogin(player)
	player:registerEvent("ChaosWeatherExtended")
	player:registerEvent("ChaosWeatherLogout")
	if cfg().enabled ~= false then
		local id = player:getId()
		addEvent(function()
			local p = Player(id)
			if p then
				pcall(W.sync, p, true)
			end
		end, 1500)
	end
	return true
end
login:register()

local logout = CreatureEvent("ChaosWeatherLogout")
function logout.onLogout(player)
	W.forget(W.sent, player:getId())
	return true
end
logout:register()

local ext = CreatureEvent("ChaosWeatherExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE or cfg().enabled == false then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "hello" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "weather.hello", 1000) then
		return
	end
	pcall(W.sync, player, true)
end
ext:type("extendedopcode")
ext:register()

-- ---------------------------------------------------------------- staff
local talk = TalkAction("/weather")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() or player:getGroup():getId() < 4 then
		return false
	end
	local cmd, arg = tostring(param or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local s = W.state
	if cmd == "rain" then
		W.set(s, cfg(), true, math.random, tonumber(arg), nowMs())
	elseif cmd == "clear" then
		W.set(s, cfg(), false, math.random, nil, nowMs())
	end
	local n = (cmd == "rain" or cmd == "clear") and W.syncAll(false) or 0
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Weather: %s%s, next roll in %d s; %d player(s) told.",
		s.raining and "rain" or "clear", s.raining and (" " .. s.intensity) or "",
		math.max(0, math.floor(((s.nextRollAt or 0) - nowMs()) / 1000)), n))
	return false
end
talk:separator(" ")
talk:register()
