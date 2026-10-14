-- Run from the server/ folder: luajit tests/i18n_test.lua (and lua5.3; CI runs both)
-- Server texts in the player's language (server/README.md "Server texts in pt-BR (Chaos.t)"): i18n_core.lua (lookup,
-- formats, fallbacks, deferred texts, the language of a player, broadcasts) on a mocked engine, i18n.lua (the hello
-- on opcode 157 sets the language), and the strings table: every pt-BR entry keeps the % conversions of its key in
-- order, and every key the converted sites use (Chaos.t, ChaosI18n.msg, Chaos.broadcast, ChaosI18n.text, the boss
-- warnings of boss_mechanics_config.lua, the raid call-outs K.ANNOUNCE) has a pt-BR entry. English is the key itself.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- ---------------------------------------------------------------- mocked engine
local storages = {}
local sent = {}
local function newPlayer(id)
	local p = {id = id}
	function p:getId() return self.id end
	function p:getStorageValue(k) return storages[self.id .. ":" .. k] or -1 end
	function p:setStorageValue(k, v) storages[self.id .. ":" .. k] = v end
	function p:sendTextMessage(t, text) sent[#sent + 1] = {id = self.id, type = t, text = text} end
	function p:registerEvent() end
	return p
end
local online = {}
local broadcasts = {}
Game = {
	getPlayers = function() return online end,
	broadcastMessage = function(text, t) broadcasts[#broadcasts + 1] = text end
}
local events = {}
function CreatureEvent(name)
	local ev = {name = name}
	function ev:type(t) self.t = t end
	function ev:register() events[self.name] = self end
	return ev
end
json = {decode = function(s)
	local action = s:match('"action"%s*:%s*"([^"]*)"')
	local lang = s:match('"lang"%s*:%s*"([^"]*)"')
	return {action = action, lang = lang}
end}

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
local I = ChaosI18n

-- ---------------------------------------------------------------- the lookup
eq(I.normalize("pt-BR"), "pt-BR", "pt-BR")
eq(I.normalize("pt_br"), "pt-BR", "pt_br")
eq(I.normalize("PT"), "pt-BR", "pt")
eq(I.normalize("en-US"), "en", "en-US")
eq(I.normalize("de"), nil, "an unknown language")
eq(I.normalize(nil), nil, "nil")
eq(I.text("en", "Removed %s.", "Gold Coin"), "Removed Gold Coin.", "English is the key")
eq(I.text("pt-BR", "Removed %s.", "Gold Coin"), "Gold Coin removido.", "pt-BR")
eq(I.text("pt-BR", "Not in the table %d.", 5), "Not in the table 5.", "a key without a translation: English")
eq(I.text("de", "Removed %s.", "x"), "Removed x.", "an unknown language: English")
eq(I.text("pt-BR", "List cleared."), "Lista limpa.", "no arguments")
eq(I.text("pt-BR", "Removed %s."), "%s removido.", "no arguments: the pattern as it is")
local fm = I.formats("%d of %s, 5%% and %.1f")
eq(#fm, 3, "formats: three") eq(fm[1], "d", "d") eq(fm[2], "s", "s") eq(fm[3], "f", "f")

-- deferred texts
local m = I.msg("%s is slain by %s!", "Ysgrath", "Ann")
eq(tostring(m), "Ysgrath is slain by Ann!", "a deferred text is English for tostring")
eq(I.resolve(m, "pt-BR"), "Ysgrath foi morto por Ann!", "and pt-BR when resolved")
local nested = I.msg("%s, raid #%d: %d of %d bosses slain this week. %s", "The Ashen Sepulchre", 3, 1, 4,
	I.msg("Next: %s.", "Ossarch"))
eq(I.resolve(nested, "pt-BR"), "The Ashen Sepulchre, raid #3: 1 de 4 chefes mortos nesta semana. Próximo: Ossarch.",
	"a deferred argument is resolved in the same language")
eq(I.resolve("Time is up!", "pt-BR"), "O tempo acabou!", "a plain key resolves")
eq(I.resolve("Unknown words", "pt-BR"), "Unknown words", "an unknown plain text stays")

-- ---------------------------------------------------------------- players
local a, b = newPlayer(1), newPlayer(2)
eq(Chaos.lang(a), "en", "English by default")
check(Chaos.setLang(a, "pt-BR"), "setLang")
eq(Chaos.lang(a), "pt-BR", "the session's language")
eq(storages["1:" .. I.STORAGE], 1, "kept in the storage")
I.players[1] = nil
eq(Chaos.lang(a), "pt-BR", "after a relog: from the storage")
check(not Chaos.setLang(a, "xx"), "an unknown language is refused")
eq(Chaos.lang(a), "pt-BR", "and changes nothing")
eq(Chaos.t(a, "Removed %s.", "X"), "X removido.", "Chaos.t in pt-BR")
eq(Chaos.t(b, "Removed %s.", "X"), "Removed X.", "Chaos.t in English")
eq(Chaos.t(a, I.msg("Next: %s.", "Y")), "Próximo: Y.", "Chaos.t of a deferred text")
eq(Chaos.t(nil, "Removed %s.", "X"), "Removed X.", "no player: English")

-- broadcasts: one Game.broadcastMessage while everyone reads English, else one line per player
online = {b}
local english = Chaos.broadcast(1, "%s is slain!", "Boss")
eq(#broadcasts, 1, "everyone English: the engine broadcast") eq(broadcasts[1], "Boss is slain!", "its text")
eq(english, "Boss is slain!", "the English text is returned")
online = {a, b}
sent = {}
Chaos.broadcast(1, "%s is slain!", "Boss")
eq(#broadcasts, 1, "a pt-BR reader: no engine broadcast")
eq(#sent, 2, "one line each")
eq(sent[1].text, "Boss foi morto!", "pt-BR line") eq(sent[2].text, "Boss is slain!", "English line")
sent = {}
Chaos.broadcast(1, function(lang) return lang == "pt-BR" and "oi" or "hi" end)
eq(sent[1].text, "oi", "a builder: pt-BR") eq(sent[2].text, "hi", "a builder: English")

-- ---------------------------------------------------------------- the hello (i18n.lua)
ChaosOpcodes.displayScale = 157
dofile("data/scripts/chaos/i18n.lua")
local c = newPlayer(3)
check(events.ChaosI18nOpcode ~= nil, "the opcode event")
events.ChaosI18nOpcode.onExtendedOpcode(c, 157, '{"action":"hello","lang":"pt-BR"}')
eq(Chaos.lang(c), "pt-BR", "the hello sets the language")
events.ChaosI18nOpcode.onExtendedOpcode(c, 157, '{"action":"hello"}')
eq(Chaos.lang(c), "pt-BR", "a hello without a language changes nothing")
events.ChaosI18nOpcode.onExtendedOpcode(c, 158, '{"action":"hello","lang":"en"}')
eq(Chaos.lang(c), "pt-BR", "another opcode changes nothing")
events.ChaosI18nOpcode.onExtendedOpcode(c, 157, '{"action":"hello","lang":"en"}')
eq(Chaos.lang(c), "en", "back to English")
events.ChaosI18nLogout.onLogout(c)
eq(I.players[3], nil, "the session's language is forgotten at logout")

-- ---------------------------------------------------------------- the table
local pt = I.strings["pt-BR"]
local n = 0
for key, text in pairs(pt) do
	n = n + 1
	check(type(text) == "string" and text ~= "", "pt-BR text of " .. key)
	local fk, ft = I.formats(key), I.formats(text)
	local same = #fk == #ft
	for i = 1, #fk do
		same = same and fk[i] == ft[i]
	end
	check(same, "the same % conversions in the same order: " .. key)
	check(select(2, key:gsub("{spell}", "")) == select(2, text:gsub("{spell}", "")), "{spell} kept: " .. key)
end
check(n >= 150, "the pt-BR table has its entries (" .. n .. ")")

-- every key a converted site uses has a pt-BR entry. The first argument of Chaos.t / ChaosI18n.msg /
-- Chaos.broadcast / ChaosI18n.text and of a core's T(...) helper: its literals (a `cond and "a" or "b"` gives both).
local function literals(seg)
	local out = {}
	local i = 1
	while i <= #seg do
		local c = seg:sub(i, i)
		if c == '"' then
			local j = i + 1
			local buf = {}
			while seg:sub(j, j) ~= '"' do
				if seg:sub(j, j) == "\\" then
					local e = seg:sub(j + 1, j + 1)
					buf[#buf + 1] = e == "n" and "\n" or e
					j = j + 2
				else
					buf[#buf + 1] = seg:sub(j, j)
					j = j + 1
				end
			end
			out[#out + 1] = table.concat(buf)
			i = j + 1
		elseif c == "(" or c == "{" or c == "[" then
			break -- a nested call or table: the first argument ends being a plain literal choice
		elseif c == "," or c == ")" then
			break
		else
			i = i + 1
		end
	end
	return out
end
local COMMON = {"Chaos%.t%([^,]+,%s*", "ChaosI18n%.msg%(%s*", "Chaos%.broadcast%([%w_.]+,%s*", "ChaosI18n%.text%(%s*lang,%s*"}
local RUN = {"fail%(run,%s*", "say%(run,%s*", "alert%(run,%s*"}
local CORE_T = {"[^%w_.]T%(%s*lang,%s*", "[^%w_.:]T%(%s*"}
local SITES = {
	["autosell.lua"] = {}, ["autosell_core.lua"] = CORE_T, ["boss_mechanics.lua"] = {}, ["records.lua"] = {},
	["records_core.lua"] = CORE_T, ["leaderboard_core.lua"] = CORE_T, ["worldboss.lua"] = {}, ["invasion.lua"] = {},
	["worldevents.lua"] = {}, ["rift.lua"] = RUN, ["raid.lua"] = RUN, ["season.lua"] = {}, ["arena_season.lua"] = {},
	["daily.lua"] = {}, ["descent.lua"] = {}, ["itemsets.lua"] = {}, ["guildwar.lua"] = {}, ["uber.lua"] = {},
	["ascension.lua"] = {}, ["season_modes.lua"] = {}, ["shop_services.lua"] = {}
}
local used = 0
for f, extra in pairs(SITES) do
	local fh = io.open("data/scripts/chaos/" .. f, "r")
	check(fh ~= nil, "source " .. f)
	if fh then
		local src = fh:read("*a")
		fh:close()
		local prefixes = {}
		for _, x in ipairs(COMMON) do prefixes[#prefixes + 1] = x end
		for _, x in ipairs(extra) do prefixes[#prefixes + 1] = x end
		for _, pre in ipairs(prefixes) do
			for seg in src:gmatch(pre .. "([^\n]*\n?[^\n]*)") do
				for _, lit in ipairs(literals(seg)) do
					if lit:find("%a%a") then
						used = used + 1
						check(pt[lit] ~= nil, f .. ": no pt-BR for \"" .. lit .. "\"")
					end
				end
			end
		end
	end
end
check(used >= 100, "the sites use their keys (" .. used .. ")")

-- the boss warnings and the raid call-outs are keys too
local cfg = dofile("data/scripts/chaos/boss_mechanics_config.lua")
local function walk(t, seen)
	if seen[t] then
		return
	end
	seen[t] = true
	for k, v in pairs(t) do
		if (k == "text" or k == "doneText") and type(v) == "string" then
			check(pt[v] ~= nil, "boss warning without pt-BR: " .. v)
		elseif type(v) == "table" then
			walk(v, seen)
		end
	end
end
walk(cfg, {})
local rh = io.open("data/scripts/chaos/raid_core.lua", "r")
local rsrc = rh:read("*a")
rh:close()
local announce = rsrc:match("K%.ANNOUNCE = (%b{})")
check(announce ~= nil, "raid K.ANNOUNCE found")
for lit in (announce or ""):gmatch('"([^"]+)"') do
	check(pt[lit] ~= nil, "raid call-out without pt-BR: " .. lit)
end
local aq = dofile("data/scripts/chaos/ascension_quest_config.lua")
check(pt[aq.broadcast] ~= nil, "the ascension broadcast has pt-BR")

print(string.format("i18n_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
