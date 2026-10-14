-- Server texts in the player's language (server/README.md "Server texts in pt-BR (Chaos.t)"; tests/i18n_test.lua).
-- This file: the lookup (ChaosI18n) and the shared helpers it puts on Chaos: Chaos.t(player, key, ...),
-- Chaos.lang(player), Chaos.setLang(player, lang), Chaos.broadcast(type, key, ...). A file that calls them starts with
--     if not ChaosI18n then dofile("data/scripts/chaos/i18n_core.lua") end
-- i18n.lua takes the client's language from its hello (opcode 157, {action = "hello", lang = "pt-BR" | "en"}).
--
-- A key is the English text itself, a string.format pattern ("Auto Seller: sold %d item%s ..."): English needs no
-- table, and a site that is not in the table yet still shows its English. i18n_strings.lua (and the files of I.MORE,
-- merged in) holds one table per language other than English: {["pt-BR"] = {[english] = translation}}. A translation
-- keeps the % conversions of its key in the same order (string.format has no positional arguments); the test checks it.
-- Text sent to the client is UTF-8: the client turns it into cp1252 (client base patch 0028).
-- Lua 5.1 / LuaJIT compatible.

local unpack = unpack or table.unpack
ChaosI18n = ChaosI18n or {}
local I = ChaosI18n

I.DEFAULT = "en"
I.LANGS = {en = true, ["pt-BR"] = true}

-- More tables of the same shape, merged in after it (a key already in i18n_strings.lua keeps that text)
I.MORE = {"i18n_strings_more.lua"}

if not I.strings then
	I.strings = dofile("data/scripts/chaos/i18n_strings.lua")
	for _, f in ipairs(I.MORE) do
		for lang, t in pairs(dofile("data/scripts/chaos/" .. f)) do
			I.strings[lang] = I.strings[lang] or {}
			local into = I.strings[lang]
			for k, v in pairs(t) do
				if into[k] == nil then
					into[k] = v
				end
			end
		end
	end
end
I.strings.en = I.strings.en or {}

-- "pt-BR", "pt_br", "pt", "PT-br" -> "pt-BR"; "en", "en-US" -> "en"; anything else -> nil
function I.normalize(lang)
	if type(lang) ~= "string" then
		return nil
	end
	local l = lang:lower():gsub("_", "-")
	if l == "pt" or l:sub(1, 3) == "pt-" then
		return "pt-BR"
	end
	if l == "en" or l:sub(1, 3) == "en-" then
		return "en"
	end
	return nil
end

local function format(pattern, ...)
	if select("#", ...) == 0 then
		return pattern
	end
	local ok, s = pcall(string.format, pattern, ...)
	return ok and s or nil
end

-- the text of `key` in `lang` (English when the language or the key has none), formatted with the arguments
function I.text(lang, key, ...)
	key = tostring(key)
	local t = I.strings[I.normalize(lang) or I.DEFAULT]
	local s = t and t[key]
	if s then
		local out = format(s, ...)
		if out then
			return out
		end
	end
	return format(key, ...) or key
end

-- A deferred text: ChaosI18n.msg("Wave %d of %d: %s reach %s!", ...) keeps the key and the arguments, so a broadcast
-- can write it in each player's language (I.resolve). tostring() of one is its English text (logs). An argument may
-- be a deferred text too.
local MSG = {}
MSG.__tostring = function(m)
	return I.resolve(m, I.DEFAULT)
end
MSG.__concat = function(a, b)
	return tostring(a) .. tostring(b)
end

function I.msg(key, ...)
	return setmetatable({key = key, n = select("#", ...), args = {...}}, MSG)
end

function I.isMsg(x)
	return getmetatable(x) == MSG
end

-- the text of a string (a key: its translation, else itself) or of a deferred text, in `lang`
function I.resolve(x, lang)
	if not I.isMsg(x) then
		if type(x) == "string" then
			return I.text(lang, x)
		end
		return x
	end
	local args = {}
	for i = 1, x.n do
		local v = x.args[i]
		args[i] = I.isMsg(v) and I.resolve(v, lang) or v
	end
	return I.text(lang, x.key, unpack(args, 1, x.n))
end

-- the % conversions of a pattern, in order ("%d of %s, 5%%" -> {"d", "s"})
function I.formats(s)
	local out = {}
	for conv in tostring(s):gsub("%%%%", ""):gmatch("%%[-+ #0]*%d*%.?%d*([diouxXeEfgGqsc])") do
		out[#out + 1] = conv
	end
	return out
end

-- storage value <-> language (Chaos.storage.language: 1 = pt-BR, anything else = English)
function I.toStorage(lang)
	return I.normalize(lang) == "pt-BR" and 1 or 0
end

function I.fromStorage(value)
	return tonumber(value) == 1 and "pt-BR" or "en"
end

-- ------------------------------------------------------------------ NPC scripts
-- An NPC script runs in its own Lua state, which never sees the client's hello (i18n.lua): there the language is the
-- stored one (Chaos.setLang keeps it in storage I.STORAGE), read again for every line.
--   ChaosI18n.langOf(player | cid)              "pt-BR" or "en"
--   ChaosI18n.npcText(player | cid, key, ...)    the text in that language
--   ChaosI18n.npcMessages(npcHandler)           the NPC's greet / farewell / walk away / trade lines (its XML
--                                               message_* parameters are the keys) in the language of the player it
--                                               answers; call it after the script's own setCallback lines
function I.langOf(player)
	if type(player) == "number" and Player then
		player = Player(player)
	end
	if (type(player) ~= "userdata" and type(player) ~= "table") or not player.getStorageValue then
		return I.DEFAULT
	end
	return I.fromStorage(player:getStorageValue(I.STORAGE))
end

function I.npcText(player, key, ...)
	return I.text(I.langOf(player), key, ...)
end

function I.npcMessages(npcHandler)
	local types = {MESSAGE_GREET, MESSAGE_FAREWELL, MESSAGE_WALKAWAY, MESSAGE_SENDTRADE}
	local keys = {}
	for _, mt in pairs(types) do
		local text = npcHandler:getMessage(mt)
		if type(text) == "string" and text ~= "" then
			keys[mt] = text
		end
	end
	local function apply(cid)
		local lang = I.langOf(cid)
		for mt, key in pairs(keys) do
			npcHandler:setMessage(mt, I.text(lang, key))
		end
	end
	for _, cb in pairs({CALLBACK_GREET, CALLBACK_FAREWELL, CALLBACK_CREATURE_DISAPPEAR, CALLBACK_ONTRADEREQUEST}) do
		local old = npcHandler:getCallback(cb)
		npcHandler:setCallback(cb, function(cid, ...)
			apply(cid)
			if old then
				return old(cid, ...)
			end
			return true
		end)
	end
	return keys
end

-- ------------------------------------------------------------------ the helpers on Chaos
-- Storages 7101830 - 7101839 reserved (server/README.md "Storage keys"): +0 is 1 for pt-BR, kept over logins so the
-- texts sent before the next hello are in the right language too.
I.STORAGE = 7101830
I.players = I.players or {}

function I.install(C)
	-- the player's language: "pt-BR" or "en" (this session's, else the stored one, else English)
	function C.lang(player)
		if type(player) ~= "userdata" and type(player) ~= "table" then
			return I.DEFAULT
		end
		local id = player.getId and player:getId()
		local lang = id and I.players[id]
		if lang then
			return lang
		end
		lang = player.getStorageValue and I.fromStorage(player:getStorageValue(I.STORAGE)) or I.DEFAULT
		if id then
			I.players[id] = lang
		end
		return lang
	end

	function C.setLang(player, lang)
		lang = I.normalize(lang)
		if not player or not lang then
			return false
		end
		I.players[player:getId()] = lang
		if player.setStorageValue then
			player:setStorageValue(I.STORAGE, I.toStorage(lang))
		end
		return true
	end

	-- Chaos.t(player, "English %s pattern", ...): the text in the player's language
	function C.t(player, key, ...)
		local lang = C.lang(player)
		if I.isMsg(key) then
			return I.resolve(key, lang)
		end
		local n = select("#", ...)
		if n == 0 then
			return I.text(lang, key)
		end
		local args = {...}
		for i = 1, n do
			if I.isMsg(args[i]) then
				args[i] = I.resolve(args[i], lang)
			end
		end
		return I.text(lang, key, unpack(args, 1, n))
	end

	-- a broadcast in each player's language. `what` is a key (with the arguments), a deferred text (I.msg) or a
	-- function(lang) -> text; it returns the English text. While
	-- nobody online reads another language it is the one Game.broadcastMessage of before (the English text).
	function C.broadcast(messageType, what, ...)
		local args, n = {...}, select("#", ...)
		local function textIn(lang)
			if type(what) == "function" then
				return what(lang)
			end
			if n == 0 then
				return I.resolve(what, lang)
			end
			return I.resolve(I.msg(what, unpack(args, 1, n)), lang)
		end
		local players = Game and Game.getPlayers and Game.getPlayers() or {}
		local other = false
		for _, p in ipairs(players) do
			if C.lang(p) ~= I.DEFAULT then
				other = true
				break
			end
		end
		local english = textIn(I.DEFAULT)
		if not other then
			if Game and Game.broadcastMessage then
				Game.broadcastMessage(english, messageType)
			end
			return english
		end
		for _, p in ipairs(players) do
			p:sendTextMessage(messageType, textIn(C.lang(p)))
		end
		return english
	end
end

if Chaos then
	I.install(Chaos)
end

return I
