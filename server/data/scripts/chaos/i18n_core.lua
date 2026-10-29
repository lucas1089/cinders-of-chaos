-- Server texts in the player's language (server/README.md "Server texts in pt-BR (Chaos.t)"; tests/i18n_test.lua).
-- This file: the lookup (ChaosI18n) and the shared helpers it puts on Chaos: Chaos.t(player, key, ...),
-- Chaos.lang(player), Chaos.setLang(player, lang), Chaos.broadcast(type, key, ...). A file that calls them starts with
--     if not ChaosI18n then dofile("data/scripts/chaos/i18n_core.lua") end
-- i18n.lua takes the client's language from its hello (opcode 157, {action = "hello", lang = "pt-BR" | "en"}).
--
-- A key is the English text itself, a string.format pattern ("Auto Seller: sold %d item%s ..."): English needs no
-- table, and a site that is not in the table yet still shows its English. i18n_strings.lua holds one table per
-- language other than English: {["pt-BR"] = {[english] = translation}}. A translation
-- keeps the % conversions of its key in the same order (string.format has no positional arguments); the test checks it.
-- Text sent to the client is UTF-8: the client turns it into cp1252 (client base patch 0028).
-- Lua 5.1 / LuaJIT compatible.

local unpack = unpack or table.unpack
ChaosI18n = ChaosI18n or {}
local I = ChaosI18n

I.DEFAULT = "en"
I.LANGS = {en = true, ["pt-BR"] = true}

if not I.strings then
	I.strings = dofile("data/scripts/chaos/i18n_strings.lua")
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

-- A reason a pure core returns already formatted ("Your guild needs guild level 3 for a guild hall."): I.translate
-- finds the pt-BR template it came from. A key with % conversions is turned into a Lua pattern once (%d -> a number,
-- other conversions -> any text); the longest literal part is tried first, and a key with less than 12 literal
-- characters is never used this way. An exact key wins. The captures are fed back to the pt-BR pattern, so one entry
-- covers every value. A text without an entry is returned as it is (English).
local matchers = {}
local function build(lang)
	local list = {}
	for key, tr in pairs(I.strings[lang] or {}) do
		if key:find("%%[-+ #0]*%d*%.?%d*[diouxXeEfgGqsc]") then
			local convs, lits, pat, i, ok = 0, 0, {"^"}, 1, true
			while i <= #key do
				local c = key:sub(i, i)
				if c == "%" then
					if key:sub(i + 1, i + 1) == "%" then
						pat[#pat + 1] = "%%"
						lits = lits + 1
						i = i + 2
					else
						local spec, conv = key:match("^%%([-+ #0]*%d*%.?%d*)([diouxXeEfgGqsc])", i)
						if not conv then
							ok = false
							break
						end
						convs = convs + 1
						pat[#pat + 1] = (conv == "d" or conv == "i" or conv == "u") and "(%-?%d+)" or "(.-)"
						i = i + 1 + #spec + 1
					end
				else
					pat[#pat + 1] = (c:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
					lits = lits + 1
					i = i + 1
				end
			end
			if ok and convs > 0 and lits >= 12 then
				pat[#pat + 1] = "$"
				list[#list + 1] = {pattern = table.concat(pat), tr = tr, lits = lits, key = key}
			end
		end
	end
	table.sort(list, function(a, b)
		if a.lits ~= b.lits then
			return a.lits > b.lits
		end
		return a.key < b.key
	end)
	return list
end

-- forget the compiled templates (a test that adds table entries calls it)
function I.resetMatchers()
	matchers = {}
end

function I.translate(lang, text)
	if I.isMsg(text) then
		return I.resolve(text, lang)
	end
	if type(text) ~= "string" or text == "" then
		return text
	end
	lang = I.normalize(lang) or I.DEFAULT
	local t = I.strings[lang]
	if not t or lang == I.DEFAULT then
		return text
	end
	if t[text] then
		return I.text(lang, text)
	end
	-- a fixed text with percent signs ("+20% max health for 20s"): its key writes them as %%, the translation too
	if text:find("%", 1, true) then
		local escaped = text:gsub("%%", "%%%%")
		if t[escaped] then
			return (t[escaped]:gsub("%%%%", "%%"))
		end
	end
	matchers[lang] = matchers[lang] or build(lang)
	for _, m in ipairs(matchers[lang]) do
		local caps = {text:match(m.pattern)}
		if #caps > 0 then
			local out = format(m.tr, unpack(caps))
			if out then
				return out
			end
		end
	end
	return text
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

-- A party member's reason in the third person ("is in a fight", "needs level %d": a key or a deferred text) -> the
-- same reason in the second person ("are in a fight", "need level %d"), a deferred text: the "stays behind" lines of
-- rifts, Ascended arenas, the Descent and the raid ("%s stays behind: %s." to the opener, "... you %s." to the member).
-- Both forms are keys of i18n_strings.lua.
function I.you(why)
	local key, args, n = why, {}, 0
	if I.isMsg(why) then
		key, args, n = why.key, why.args, why.n
	end
	key = tostring(key):gsub("^is ", "are "):gsub("^needs ", "need "):gsub("^has ", "have "):gsub(" carries ", " carry ")
	return I.msg(key, unpack(args, 1, n))
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

	-- Chaos.tx(player, reason): the text a core returned (a plain or formatted English text, or a deferred text) in the
	-- player's language; see ChaosI18n.translate
	function C.tx(player, text)
		return I.translate(C.lang(player), text)
	end

	-- Chaos.yell(creature, what, talktype, ...): a boss shout or a monster's line in each listener's language. `what` is a
	-- key (with the arguments) or a function(lang) -> text; talktype defaults to TALKTYPE_MONSTER_YELL. While every listener
	-- reads English (or the engine cannot list them) it is the plain creature:say of before; otherwise each listener gets
	-- the line in own language through creature:say(text, type, false, listener, position), which only that player sees.
	-- Returns the English text.
	function C.yell(creature, what, talktype, ...)
		talktype = talktype or TALKTYPE_MONSTER_YELL
		local args, n = {...}, select("#", ...)
		local function textIn(lang)
			if type(what) == "function" then
				return what(lang)
			end
			if n == 0 then
				return I.text(lang, what)
			end
			return I.text(lang, what, unpack(args, 1, n))
		end
		local english = textIn(I.DEFAULT)
		if not creature then
			return english
		end
		local listeners
		if Game and Game.getSpectators and creature.getPosition then
			local yelling = talktype == TALKTYPE_MONSTER_YELL
			local ok, list = pcall(Game.getSpectators, creature:getPosition(), false, true, yelling and 18 or 8,
				yelling and 18 or 8, yelling and 14 or 6, yelling and 14 or 6)
			if ok and type(list) == "table" then
				for _, p in ipairs(list) do
					if C.lang(p) ~= I.DEFAULT then
						listeners = list
						break
					end
				end
			end
		end
		if not listeners then
			creature:say(english, talktype)
			return english
		end
		local pos = creature:getPosition()
		for _, p in ipairs(listeners) do
			creature:say(textIn(C.lang(p)), talktype, false, p, pos)
		end
		return english
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

	-- Chaos.partyMessage(party, messageType, what, ...): one line for the whole party (the party loot line of a kill), each
	-- member reading it in own language. `what` is a key (with the arguments), a deferred text (I.msg) or a
	-- function(lang) -> text. While every member reads English (or the members cannot be listed) it is the one
	-- party:broadcastPartyLoot of before. Returns the English text.
	function C.partyMessage(party, messageType, what, ...)
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
		local english = textIn(I.DEFAULT)
		local members = {}
		local okL, leader = pcall(function() return party:getLeader() end)
		if okL and leader then
			members[#members + 1] = leader
		end
		local okM, list = pcall(function() return party:getMembers() end)
		for _, m in ipairs(okM and type(list) == "table" and list or {}) do
			members[#members + 1] = m
		end
		local other = false
		for _, p in ipairs(members) do
			if C.lang(p) ~= I.DEFAULT then
				other = true
				break
			end
		end
		if not other then
			party:broadcastPartyLoot(english)
			return english
		end
		for _, p in ipairs(members) do
			p:sendTextMessage(messageType, textIn(C.lang(p)))
		end
		return english
	end
end

if Chaos then
	I.install(Chaos)
end

return I
