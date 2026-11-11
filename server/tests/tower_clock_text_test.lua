-- Run from the server/ folder: luajit tests/tower_clock_text_test.lua (and lua5.3; CI runs both)
-- O484: the Infinity Tower has two clocks and each warning names its own. The sentences (instance_limits_core.lua
-- K.wholeRunText, K.floorLeftText) in English and pt-BR, the hook of IL.warn (limits.sentence) and that every other
-- instance keeps the shared sentence byte for byte.
local checks, failures = 0, 0
local function eq(a, b, label)
	checks = checks + 1
	if a ~= b then
		failures = failures + 1
		print("FAIL " .. label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
	end
end

local storages = {}
local function newPlayer(id)
	local p = {id = id, msgs = {}}
	function p:getId() return self.id end
	function p:getStorageValue(k) return storages[self.id .. ":" .. k] or -1 end
	function p:setStorageValue(k, v) storages[self.id .. ":" .. k] = v end
	function p:sendTextMessage(t, text) self.msgs[#self.msgs + 1] = text end
	function p:registerEvent() end
	return p
end
CreatureEvent = function() local o = {}; function o:type() end; function o:register() end; return o end
Game = {getPlayers = function() return {} end, broadcastMessage = function() end}
json = {decode = function() return {} end}
MESSAGE_STATUS_WARNING = 22
MESSAGE_EVENT_ADVANCE = 19
local toasts = {}
ChaosNotify = {send = function(p, title, body) toasts[#toasts + 1] = {title = title, body = body} end}

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/instance_limits.lua")
local K, IL = ChaosInstanceLimitsCore, ChaosInstanceLimits
local en, pt = newPlayer(1), newPlayer(2)
Chaos.setLang(en, "en")
Chaos.setLang(pt, "pt-BR")

-- the pure sentences
eq(K.wholeRunText("Infinity Tower", 60, 3600, "en"),
	"Infinity Tower: the whole run ends in 1 minute (60 minute limit). Everyone inside leaves then.", "run, en, 1 minute")
eq(K.wholeRunText("Infinity Tower", 60, 3600, "pt-BR"),
	"Infinity Tower: a corrida inteira termina em 1 minuto (limite de 60 minutos). Todos lá dentro saem.", "run, pt-BR, 1 minute")
eq(K.wholeRunText("Infinity Tower", 300, 3600, "en"),
	"Infinity Tower: the whole run ends in 5 minutes (60 minute limit). Everyone inside leaves then.", "run, en, 5 minutes")
eq(K.wholeRunText("Infinity Tower", 300, 3600, "pt-BR"),
	"Infinity Tower: a corrida inteira termina em 5 minutos (limite de 60 minutos). Todos lá dentro saem.", "run, pt-BR, 5 minutes")
eq(K.wholeRunText("Infinity Tower", 10, 3600, "en"),
	"Infinity Tower: the whole run ends in 10 seconds (60 minute limit). Everyone inside leaves then.", "run, en, 10 seconds")
eq(K.wholeRunText("Infinity Tower", 10, 3600, "pt-BR"),
	"Infinity Tower: a corrida inteira termina em 10 segundos (limite de 60 minutos). Todos lá dentro saem.", "run, pt-BR, 10 seconds")
eq(K.wholeRunText("Infinity Tower", 60, 5400, "en"),
	"Infinity Tower: the whole run ends in 1 minute (90 minute limit). Everyone inside leaves then.", "the limit comes from the argument")
eq(K.floorLeftText(57, 60, "en"), "Floor 57: 1 minute left to clear it.", "floor, en, 1 minute")
eq(K.floorLeftText(57, 60, "pt-BR"), "Andar 57: falta 1 minuto para limpar.", "floor, pt-BR, 1 minute")
eq(K.floorLeftText(3, 10, "en"), "Floor 3: 10 seconds left to clear it.", "floor, en, 10 seconds")
eq(K.floorLeftText(3, 10, "pt-BR"), "Andar 3: faltam 10 segundos para limpar.", "floor, pt-BR, 10 seconds")
eq(K.inText(120, "en"), "2 minutes", "inText minutes")
eq(K.inText(1, "pt-BR"), "1 segundo", "inText one second")

-- IL.warn with the hook: each player in their language, the toast names the clock
local run = {}
local limits = {warnAt = {300, 60, 10}, sentence = function(p, lang, mark, leftText, name)
	return K.wholeRunText(name, mark, 3600, lang), nil, Chaos.t(p, "Whole run: %s", leftText)
end}
IL.warn(run, 400, {en, pt}, "Infinity Tower", limits)
IL.warn(run, 60, {en, pt}, "Infinity Tower", limits)
eq(en.msgs[#en.msgs], "Infinity Tower: the whole run ends in 1 minute (60 minute limit). Everyone inside leaves then.", "warn, en")
eq(pt.msgs[#pt.msgs], "Infinity Tower: a corrida inteira termina em 1 minuto (limite de 60 minutos). Todos lá dentro saem.", "warn, pt-BR")
eq(toasts[#toasts].title, "Infinity Tower", "toast title")
eq(toasts[#toasts - 1].body, "Whole run: 1 minute left", "toast body names the whole run (en)")
eq(toasts[#toasts].body, "Corrida inteira: falta 1 minuto", "toast body names the whole run (pt-BR)")

-- every other instance keeps the shared sentence
IL.warn({_limits = {lastLeft = 400}}, 300, {en}, "Rift")
eq(en.msgs[#en.msgs], "Rift: 5 minutes left. Everyone inside is sent out when the time runs out.", "shared sentence, en")
IL.warn({_limits = {lastLeft = 400}}, 300, {pt}, "Rift")
eq(pt.msgs[#pt.msgs], "Rift: faltam 5 minutos. Todos lá dentro saem quando o tempo acabar.", "shared sentence, pt-BR")

if failures > 0 then print(failures .. " of " .. checks .. " checks failed"); os.exit(1) end
print("tower clock text: " .. checks .. " checks passed")
