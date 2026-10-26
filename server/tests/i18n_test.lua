-- Run from the server/ folder: luajit tests/i18n_test.lua (and lua5.3; CI runs both)
-- Server texts in the player's language (server/README.md "Server texts in pt-BR (Chaos.t)"): i18n_core.lua (lookup,
-- formats, fallbacks, deferred texts, the language of a player, broadcasts) on a mocked engine, i18n.lua (the hello
-- on opcode 157 sets the language), the NPC helpers (langOf, npcText, npcMessages), and the strings table
-- (i18n_strings.lua, one table, no key twice): every pt-BR entry keeps the % conversions of its key in order, and every key the
-- converted sites use (Chaos.t, ChaosI18n.msg, Chaos.broadcast, ChaosI18n.text, a core's T(lang, ...), an NPC's
-- t(cid, ...), the helpers listed per file, the boss warnings of boss_mechanics_config.lua, the raid call-outs K.ANNOUNCE,
-- the config texts the converted sites read, the NPC XML lines) has a pt-BR entry. English is the key itself.

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
-- one table: no key written twice in i18n_strings.lua (a Lua table constructor would keep the last one silently)
do
	local fh = io.open("data/scripts/chaos/i18n_strings.lua", "r")
	local src = fh:read("*a")
	fh:close()
	local seen, entries = {}, 0
	for key in src:gmatch('\n\t\t%[("[^\n]-")%] =') do
		entries = entries + 1
		check(not seen[key], "i18n_strings.lua: key written twice: " .. key)
		seen[key] = true
	end
	eq(entries, n, "every entry of i18n_strings.lua is one key of the table")
end

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
local TR = {"[^%w_.]tr%([^,]+,%s*"} -- lib and spell files: a local tr() that calls Chaos.t when it is loaded
local SITES = {
	["autosell.lua"] = {}, ["autosell_core.lua"] = CORE_T, ["boss_mechanics.lua"] = {}, ["records.lua"] = {},
	["records_core.lua"] = CORE_T, ["leaderboard_core.lua"] = CORE_T, ["worldboss.lua"] = {"pushBack%(player, fromPosition,%s*"},
	["invasion.lua"] = {},
	["worldevents.lua"] = {}, ["rift.lua"] = RUN, ["raid.lua"] = RUN, ["season.lua"] = {}, ["arena_season.lua"] = {},
	["daily.lua"] = {}, ["descent.lua"] = {}, ["itemsets.lua"] = {}, ["guildwar.lua"] = {}, ["uber.lua"] = {},
	["ascension.lua"] = {}, ["season_modes.lua"] = {}, ["shop_services.lua"] = {},
	-- the store, quests, achievements, new players, instances and the systems' chat lines
	["shop.lua"] = {"message%(player,%s*"}, ["shop_core.lua"] = CORE_T, ["ascension_quest.lua"] = {},
	["ascension_quest_core.lua"] = CORE_T, ["trials.lua"] = {"say%(tr,%s*", "box%(player,%s*"}, ["trials_core.lua"] = CORE_T,
	["achievements_core.lua"] = CORE_T, ["daily_core.lua"] = CORE_T, ["newplayer.lua"] = {}, ["newplayer_core.lua"] = CORE_T,
	["newplayer_tutorial.lua"] = {}, ["instance_limits.lua"] = {}, ["instance_limits_core.lua"] = CORE_T, ["stash.lua"] = {},
	["bank.lua"] = {}, ["townportal.lua"] = {}, ["pouches.lua"] = {}, ["store_food.lua"] = {}, ["potions.lua"] = {},
	["pact.lua"] = {"message%(player,%s*"},
	["pact_perks.lua"] = {}, ["hideout.lua"] = {}, ["autoloot.lua"] = {}, ["lootfilter.lua"] = {}, ["notifications.lua"] = {},
	["class_unlocks.lua"] = {}, ["professions.lua"] = {"msg%(player,%s*"}, ["charms.lua"] = {}, ["pets.lua"] = {}, ["necro_minions.lua"] = {},
	["pack_items.lua"] = {}, ["nameplate.lua"] = {}, ["guild.lua"] = {}, ["guild_hall.lua"] = {}, ["season_journey.lua"] = {},
	["infinitytower.lua"] = {}, ["infinitytower_run.lua"] = {}, ["arena.lua"] = {"msg%(%w+,%s*"},
	["battleground.lua"] = {"msg%(%w+,%s*"}, ["mentor.lua"] = {}, ["referral.lua"] = {}, ["beta.lua"] = {},
	["pvpzone.lua"] = {}, ["multiclient.lua"] = {}, ["antibot.lua"] = {}, ["events_schedule.lua"] = {},
	["commands_ui.lua"] = {}, ["spellbook.lua"] = {}, ["supports.lua"] = {}, ["loadouts.lua"] = {}, ["crafting.lua"] = {},
	["chronicle.lua"] = {}, ["atlas.lua"] = {}, ["siege.lua"] = {"pushBack%(player, fromPosition,%s*"}, ["guildboss.lua"] = {},
	["leaderboard.lua"] = {},
	["market.lua"] = {}, ["hideout.lua"] = {}, ["gamble.lua"] = {}, ["cosmetics.lua"] = {}, ["transmog.lua"] = {},
	["trials_effects.lua"] = {}, ["paragon.lua"] = {}, ["passivetree.lua"] = {}, ["bosspoints.lua"] = {}, ["gems.lua"] = {},
	["salvage.lua"] = {}, ["archery.lua"] = {}, ["blessings.lua"] = {},
	["cursedchest.lua"] = {"say%(%w+,%s*", "toast%(%w+,%s*", "tellAll%(ev,%s*"}, ["candlemarks.lua"] = {}, ["catchup.lua"] = {},
	["pocketboss.lua"] = {"tell%(run,%s*", "fail%(run,%s*", "K%.T%(%s*"}, ["pocketboss_core.lua"] = CORE_T,
	-- factions, bestiary, season pass, community goal, dungeons, goblins and Chaos loot; reasons returned to the window
	["factions.lua"] = {"return nil,%s*"}, ["factions_core.lua"] = CORE_T, ["bestiary.lua"] = {},
	["bestiary_core.lua"] = CORE_T, ["seasonpass.lua"] = {"notice%(player,%s*"}, ["seasonpass_core.lua"] = CORE_T,
	["community.lua"] = {}, ["community_core.lua"] = CORE_T, ["dungeons.lua"] = {},
	["treasure_goblin.lua"] = {}, ["loot.lua"] = {}, ["rift_core.lua"] = CORE_T, ["infinitytower_run.lua"] = {},
	["conquest.lua"] = {"result%(player,%s*%a+,%s*"}, ["harvest_event.lua"] = {"tell%(player,%s*"},
	["waystone_tiers.lua"] = {},
	["exercise_training.lua"] = {"say%(player,%s*", "stop%(pid,%s*gen,%s*"},
	-- staff command replies (O147) and the small lines of spells and the casting lib
	["achievements.lua"] = {}, ["admin/actions_pack30_gallery.lua"] = {}, ["admin/testkit.lua"] = {},
	["creator_codes.lua"] = {}, ["exclusives.lua"] = {}, ["orbexchange.lua"] = {}, ["patchnotes.lua"] = {},
	["treestats.lua"] = {}, ["reports.lua"] = {},
	["../../lib/chaos_casting.lua"] = TR, ["../../spells/chaos/_snares.lua"] = TR,
	["../../spells/chaos/ironsage/chi_ward.lua"] = TR, ["../../spells/chaos/sentinel/aegis_of_faith.lua"] = TR,
	["../../spells/chaos/shared/sense_prey.lua"] = TR, ["prizes.lua"] = {}, ["respec.lua"] = {}, ["vigils.lua"] = {},
	["admin/actions_players.lua"] = {}, ["../../lib/chaos_unique_items.lua"] = TR,
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

-- Cores and engine files whose reasons are returned as English text and translated where they are shown
-- (Chaos.tx / ChaosI18n.translate: an exact key, else the pt-BR template the formatted text came from). Every English
-- sentence they return or format needs a pt-BR entry. REASONS lists the files; the value is a list of Lua patterns of
-- sentences that stay English on purpose (staff lines, log rows, item descriptions of one text for all viewers).
local REASONS = {
	["guild_core.lua"] = {"^%%s %%s put in", "^%%s %%s took out", "^%%s %%s deposited", "^%%s %%s withdrew", "^This portal$"},
	["guild.lua"] = {"^Guild level $", "^%%s: ", "^%%s %(%%d%): ", "^That guild has no hall", "^/guild", "^Teleported",
		"^Use it to travel", "^%%s %(%%d%) reached guild level", "^guild "},
	["guild_hall.lua"] = {"^The banner of $", "^Teleport to ", "^The guild's crafting bench", "^The guild depot%. Drop", "^Guild Siege",
		"^World bosses", "^ The Ashen", "^Records: ", "^Guild level %%d %(", "^Rent of %%s: ", "^That guild has no hall", "^Guild bank$",
		"^%%d way", "^%%d guild hall"},
	["buildshare_core.lua"] = {"^Preset ", "^class "}, ["buildshare.lua"] = {},
	["reports_core.lua"] = {"^New bug report", "^New player report", "^Character position", "^Reported map tile", "^Level %%d"},
	["salvage_core.lua"] = {}, ["salvage.lua"] = {"^Main backpack", "^Set piece$"}, ["crafting.lua"] = {"^Rift Key$"},
	["guildwar_core.lua"] = {}, ["guildwar.lua"] = {"^War declared$", "^%%s declares war: ", "^%%s %%(%%d%%) offered war", "^%%d: ", "^No war offers",
		"^%%d war offer", "^War %%d ended", "^Offer %%d expired", "^Chaos guildwar"},
	["market_core.lua"] = {}, ["market_config.lua"] = {}, ["market_orders_core.lua"] = {},
	["market_notify_core.lua"] = {"^While you were away", "^Market sales", "^Orb Exchange", "^Chaos Coin", "^your "},
	["market.lua"] = {"^Market sweep", "^Buy orders%%s", "^Offer %%d", "^No such offer", "^/market", "^Chaos Coins$"},
}
local SQL = {"^SELECT", "^INSERT", "^UPDATE", "^DELETE", "^WHERE", "^FROM", "^ON DUP", "^CREATE", "^ALTER"}
local nReason = 0
for f, skips in pairs(REASONS) do
	local fh = io.open("data/scripts/chaos/" .. f, "r")
	check(fh ~= nil, "source " .. f)
	if fh then
		local src = fh:read("*a")
		fh:close()
		for line in src:gmatch("[^\n]+") do
			if not line:find("^%s*%-%-") then
				local pos = 1
				while true do
					local a, b = line:find('"', pos, true)
					if not a then break end
					local j, buf = b + 1, {}
					while j <= #line and line:sub(j, j) ~= '"' do
						if line:sub(j, j) == "\\" then
							buf[#buf + 1] = line:sub(j + 1, j + 1)
							j = j + 2
						else
							buf[#buf + 1] = line:sub(j, j)
							j = j + 1
						end
					end
					pos = j + 1
					local lit = table.concat(buf)
					local sentence = lit:find("^%u[%l ]") and lit:find("%a+[ ]%a") and not lit:find("`") and not lit:find("^%u+ ")
					for _, x in ipairs(SQL) do
						if lit:find(x) then sentence = false end
					end
					for _, x in ipairs(skips) do
						if lit:find(x) then sentence = false end
					end
					if sentence then
						nReason = nReason + 1
						check(pt[lit] ~= nil, f .. ": no pt-BR for \"" .. lit .. "\"")
					end
				end
			end
		end
	end
end
check(nReason >= 80, "the returned reasons are found (" .. nReason .. ")")

-- translate: the formatted English text a core returned finds its pt-BR template
eq(I.translate("pt-BR", "Unknown upgrade."), "Melhoria desconhecida.", "translate: an exact key")
eq(I.translate("pt-BR", "Your guild needs guild level 7 for a guild hall."),
	"Sua guild precisa do level de guild 7 para um guild hall.", "translate: a number taken out of the text")
eq(I.translate("pt-BR", "The guild bank holds 1,500 gold; the hall costs 50,000."),
	"O banco da guild tem 1,500 de ouro; o hall custa 50,000.", "translate: two texts")
eq(I.translate("pt-BR", "Ashen Wolf needs level 120."), "Ashen Wolf precisa do nível 120.", "translate: a name in the text")
eq(I.translate("pt-BR", "Nothing like this in the table."), "Nothing like this in the table.", "translate: unknown stays English")
eq(I.translate("en", "Unknown upgrade."), "Unknown upgrade.", "translate: English is the text")
eq(I.translate("pt-BR", I.msg("Removed %s.", "Gold Coin")), "Gold Coin removido.", "translate: a deferred text")
eq(I.translate("pt-BR", ""), "", "translate: empty")
eq(I.translate("pt-BR", nil), nil, "translate: nil")
do
	local pl = newPlayer(77)
	pl:setStorageValue(I.STORAGE, 1)
	eq(Chaos.tx(pl, "Unknown upgrade."), "Melhoria desconhecida.", "Chaos.tx in the player's language")
	eq(Chaos.tx(newPlayer(78), "Unknown upgrade."), "Unknown upgrade.", "Chaos.tx: English player")
end

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

-- the "stays behind" reasons (rift, Ascended arena, Descent, raid): the third person and, through ChaosI18n.you,
-- the second
local nReasons = 0
for _, f in ipairs({"rift.lua", "uber.lua", "descent.lua", "raid.lua"}) do
	local fh = io.open("data/scripts/chaos/" .. f, "r")
	local src = fh:read("*a")
	fh:close()
	for seg in src:gmatch('ChaosI18n%.msg%(([^\n]*\n?[^\n]*)') do
		for _, lit in ipairs(literals(seg)) do
			if lit:find("^is ") or lit:find("^needs ") or lit:find("^has ") then
				nReasons = nReasons + 1
				check(pt[lit] ~= nil, f .. ": reason without pt-BR: " .. lit)
				local you = I.you(lit)
				check(pt[you.key] ~= nil, f .. ": second person without pt-BR: " .. you.key)
			end
		end
	end
end
check(nReasons >= 20, "the stays-behind reasons are found (" .. nReasons .. ")")
eq(tostring(I.you(I.msg("needs level %d for a tier %d rift", 80, 5))), "need level 80 for a tier 5 rift", "you: the arguments kept")
eq(tostring(I.you("has used today's free descent and carries no Ember Sigil")),
	"have used today's free descent and carry no Ember Sigil", "you: carries -> carry")
eq(I.resolve(I.msg("You stay behind from %s's rift: you %s.", "Ana", I.you(I.msg("is in a fight"))), "pt-BR"),
	"Você fica fora da rift de Ana: você está em luta.", "a stays-behind line in pt-BR")

-- texts that come from configs: the Oracle's paths and the guardians' hints, the Trials' stories, the tutorial, the
-- welcome, the achievements' categories and descriptions, the factions' lore, the world buffs
for _, p in pairs(aq.paths) do check(pt[p] ~= nil, "ascension path without pt-BR: " .. p) end
for _, g in pairs(aq.guardians) do check(pt[g.hint] ~= nil, "guardian hint without pt-BR: " .. g.hint) end
for _, fam in pairs(dofile("data/scripts/chaos/trials_config.lua").families or {}) do
	check(pt[fam.story] ~= nil, "trial story without pt-BR: " .. tostring(fam.story))
end
local npcfg = dofile("data/scripts/chaos/newplayer_config.lua")
for _, k in ipairs({npcfg.welcome.title, npcfg.welcome.text, npcfg.welcome.toast, npcfg.welcome.firstToast,
		npcfg.welcome.helper.hint}) do
	check(pt[k] ~= nil, "welcome text without pt-BR: " .. k)
end
for _, k in ipairs({npcfg.tutorial.arrival.title, npcfg.tutorial.arrival.text, npcfg.tutorial.arrival.toast}) do
	check(pt[k] ~= nil, "tutorial arrival text without pt-BR: " .. k)
end
for _, l in ipairs(npcfg.tutorial.lessons) do
	for _, k in ipairs({l.title, l.text, l.toast, l.craftHint}) do
		check(pt[k] ~= nil, "tutorial lesson text without pt-BR: " .. k)
	end
end
-- the season pass challenges, the community goal's stages, token reward and week modifiers, the unique drop and
-- goblin lines, the bestiary's stage names, the rift coffer's directions
for _, kind in pairs(dofile("data/scripts/chaos/seasonpass_config.lua").challenges) do
	if type(kind) == "table" then
		for _, pool in pairs(kind) do
			for _, c in pairs(type(pool) == "table" and pool or {}) do
				if type(c) == "table" and c.text then
					check(pt[c.text] ~= nil, "season pass challenge without pt-BR: " .. c.text)
				end
			end
		end
	end
end
local cc = dofile("data/scripts/chaos/community_config.lua")
for _, st in ipairs(cc.goal.stages) do check(pt[st.text] ~= nil, "community stage without pt-BR: " .. st.text) end
check(pt[cc.goal.rewards.token.text] ~= nil, "community token reward without pt-BR")
for _, m in ipairs(cc.week.pool) do check(pt[m.text] ~= nil, "week modifier without pt-BR: " .. m.text) end
local lc = dofile("data/scripts/chaos/loot_config.lua")
check(pt[lc.unique.message] ~= nil and pt[lc.unique.broadcastText] ~= nil, "the unique drop lines have pt-BR")
local gc = dofile("data/scripts/chaos/treasure_goblin_config.lua")
for _, k in ipairs({gc.appearText, gc.escapeText, gc.killText}) do check(pt[k] ~= nil, "goblin line without pt-BR: " .. k) end
local bc = dofile("data/scripts/chaos/bestiary_config.lua")
for i = 2, 3 do check(pt[bc.stageNames[i]:lower()] ~= nil, "bestiary stage without pt-BR: " .. bc.stageNames[i]) end
for _, d in ipairs({"north", "south", "east", "west", "north-east", "north-west", "south-east", "south-west", "centre",
		"far side"}) do
	check(pt[d] ~= nil, "rift coffer direction without pt-BR: " .. d)
end
local ach = dofile("data/scripts/chaos/achievements_data.lua")
for _, c in ipairs(ach.categories) do check(pt[c.name] ~= nil, "achievement category without pt-BR: " .. tostring(c.name)) end
for _, a in ipairs(ach.list) do check(pt[a.desc] ~= nil, "achievement description without pt-BR: " .. tostring(a.desc)) end
for _, a in ipairs(ach.list) do check(pt[a.name] ~= nil, "achievement name without pt-BR: " .. tostring(a.name)) end
-- Conquest Tokens: the labels of the sources, the pity groups and the vendor groups
do
	local cq = dofile("data/scripts/chaos/conquest_config.lua")
	for _, tbl in ipairs({cq.sources, cq.pity, cq.vendor.groups}) do
		for _, e in pairs(tbl) do check(pt[e.label] ~= nil, "conquest label without pt-BR: " .. tostring(e.label)) end
	end
end
-- the Seasonal Journey: journey, chapter and objective texts, the appearance / outfit / mount reward lines
for _, j in pairs(dofile("data/scripts/chaos/season_journey_config.lua").journeys) do
	check(pt[j.name] ~= nil, "journey name without pt-BR: " .. j.name)
	for _, ch in ipairs(j.chapters) do
		check(pt[ch.name] ~= nil, "journey chapter without pt-BR: " .. ch.name)
		check(pt[ch.text] ~= nil, "journey chapter text without pt-BR: " .. tostring(ch.text))
		for _, o in ipairs(ch.objectives) do check(pt[o.text] ~= nil, "journey objective without pt-BR: " .. o.text) end
		for _, r in ipairs(ch.rewards or {}) do
			if r.kind ~= "items" and r.kind ~= "passxp" and r.kind ~= "title" then
				check(pt[r.name] ~= nil, "journey reward without pt-BR: " .. tostring(r.name))
			end
		end
	end
end
for _, f in ipairs(dofile("data/scripts/chaos/factions_config.lua").factions) do
	check(pt[f.lore] ~= nil, "faction lore without pt-BR: " .. f.name)
end
for _, b in ipairs(Chaos.shopServices.worldBuffs) do check(pt[b.text] ~= nil, "world buff text without pt-BR: " .. b.id) end
-- mentor.lua and referral.lua send their config's messages as deferred texts (say); stash.lua its config's messages
-- and the Stow Everything reasons
for _, cfgFile in ipairs({"mentor_config.lua", "referral_config.lua", "stash_config.lua"}) do
	for k, v in pairs(dofile("data/scripts/chaos/" .. cfgFile).messages) do
		check(pt[v] ~= nil, cfgFile .. " message " .. k .. " without pt-BR")
	end
end
for k, v in pairs(dofile("data/scripts/chaos/stash_config.lua").reasons) do
	check(pt[v] ~= nil, "stash_config.lua reason " .. k .. " without pt-BR")
end

-- the NPCs: their XML greet / farewell / walk away / trade lines (ChaosI18n.npcMessages) and their scripts' lines
local NPC_XML = {"Ascendant Oracle", "Loot Buyer", "Material Broker", "Mordecai Ashwager", "Keeper of Trials",
	"Wandering Merchant", "Warden Ysolde", "Forgemaster Brannoc", "Cantor Velith", "Elder Bramwyn",
	"Osric the Chandler", "Iselde Varrow", "Widow Hessa", "Veyra the Apothecary"}
for _, name in ipairs(NPC_XML) do
	local fh = io.open("data/npc/" .. name .. ".xml", "r")
	check(fh ~= nil, "npc xml " .. name)
	if fh then
		local xml = fh:read("*a")
		fh:close()
		for key, value in xml:gmatch('<parameter key="message_(%w+)" value="([^"]*)"') do
			check(pt[value] ~= nil, name .. ".xml message_" .. key .. " without pt-BR: " .. value)
		end
	end
end
for _, f in ipairs({"loot_buyer.lua", "ascendant_oracle.lua", "material_broker.lua", "mordecai_ashwager.lua",
		"chaos_faction_npc.lua", "keeper_of_trials.lua", "wandering_merchant.lua", "osric_the_chandler.lua", "iselde_varrow.lua", "widow_hessa.lua", "veyra_the_apothecary.lua"}) do
	local fh = io.open("data/npc/scripts/" .. f, "r")
	check(fh ~= nil, "npc script " .. f)
	if fh then
		local src = fh:read("*a")
		fh:close()
		check(src:find("ChaosI18n.npcMessages(npcHandler)", 1, true) ~= nil, f .. ": the XML lines in the player's language")
		for _, pre in ipairs({"[^%w_.:]t%(%s*cid,%s*", "[^%w_.:]t%(%s*player,%s*", "ChaosI18n%.text%(%s*lang,%s*"}) do
			for seg in src:gmatch(pre .. "([^\n]*\n?[^\n]*)") do
				for _, lit in ipairs(literals(seg)) do
					if lit:find("%a%a") then
						check(pt[lit] ~= nil, f .. ": no pt-BR for \"" .. lit .. "\"")
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- NPC scripts (their own Lua state: the stored language)
local npcP = newPlayer(9)
eq(I.langOf(npcP), "en", "an NPC reads English by default")
storages["9:" .. I.STORAGE] = 1
eq(I.langOf(npcP), "pt-BR", "and the stored language")
eq(I.npcText(npcP, "Your loss."), "Azar o seu.", "npcText")
Player = function(cid) return cid == 9 and npcP or nil end
eq(I.langOf(9), "pt-BR", "langOf a creature id")
local handler = {messages = {}, callbacks = {}}
function handler:getMessage(t) return self.messages[t] end
function handler:setMessage(t, v) self.messages[t] = v end
function handler:getCallback(t) return self.callbacks[t] end
function handler:setCallback(t, f) self.callbacks[t] = f end
MESSAGE_GREET, MESSAGE_FAREWELL, MESSAGE_WALKAWAY, MESSAGE_SENDTRADE = 1, 2, 3, 4
CALLBACK_GREET, CALLBACK_FAREWELL, CALLBACK_CREATURE_DISAPPEAR, CALLBACK_ONTRADEREQUEST = 11, 12, 13, 14
handler.messages[MESSAGE_GREET] = "Bring me more, |PLAYERNAME|."
handler.messages[MESSAGE_WALKAWAY] = "Your loss."
local oldGreet = 0
handler.callbacks[CALLBACK_GREET] = function(cid) oldGreet = oldGreet + 1 return false end
I.npcMessages(handler)
eq(handler.callbacks[CALLBACK_GREET](9), false, "the script's own greet callback still decides")
eq(oldGreet, 1, "and runs")
eq(handler.messages[MESSAGE_GREET], "Traga mais, |PLAYERNAME|.", "greet in pt-BR")
eq(handler.messages[MESSAGE_WALKAWAY], "Azar o seu.", "walk away in pt-BR")
eq(handler.callbacks[CALLBACK_FAREWELL](8), true, "no callback before: true")
eq(handler.messages[MESSAGE_GREET], "Bring me more, |PLAYERNAME|.", "another (unknown) player: English again")
Player = nil

-- a few converted texts end to end in pt-BR
dofile("data/scripts/chaos/ascension_quest_core.lua")
local Q = ChaosAscensionQuestCore
eq(Q.formatWait(600, "pt-BR"), "10 minutos", "ascension wait in pt-BR")
eq(Q.formatWait(600), "10 minutes", "and English by default")
check(Q.proofText(3, "pt-BR"):find("Você tem 3 de", 1, true) ~= nil, "the Proof text in pt-BR")
dofile("data/scripts/chaos/instance_limits_core.lua")
eq(ChaosInstanceLimitsCore.busyText("rifts", 240, 2, "pt-BR"),
	"Sem vaga livre em rifts. Tente de novo em ~4 min. Você é o 2º da fila: vai ser avisado quando uma vaga ficar livre.",
	"busy text in pt-BR")
dofile("data/scripts/chaos/shop_core.lua")
eq(ChaosShopCore.coinGiftProblem({perDay = 100}, {now = 0, amount = 101}, "pt-BR"),
	"Você pode presentear no máximo 100 Chaos Coins por dia (restam 100 hoje).", "a store refusal in pt-BR")

dofile("data/scripts/chaos/factions_core.lua")
local FK = ChaosFactionsCore
local lab = {lab = {"Deliver %s", {"3 Ember Shards"}, "5,000"}}
lab.label = FK.label(lab)
eq(lab.label, "Deliver 3 Ember Shards and 5,000 gold", "a delivery contract in English")
eq(FK.label(lab, "pt-BR"), "Entregue 3 Ember Shards e 5,000 de ouro", "and in pt-BR")
dofile("data/scripts/chaos/bestiary_core.lua")
eq(select(2, ChaosBestiaryCore.canAccept(nil, {}, {}, "pt-BR")), "Essa task não está no seu quadro.", "a kill task refusal in pt-BR")
dofile("data/scripts/chaos/rift_core.lua")
eq(ChaosRiftCore.atlasNote({density = 12, lives = 1}, "pt-BR"), "Atlas: +12% packs, +1 vida", "the atlas HUD note in pt-BR")
eq(ChaosRiftCore.atlasNote({density = 12, lives = 2}), "Atlas: +12% packs, +2 lives", "and in English")
dofile("data/scripts/chaos/achievements_core.lua")
eq(ChaosAchievementsCore.nameOf({name = "Blooded"}, "pt-BR"), "Batizado em Sangue", "an achievement name in pt-BR")
eq(ChaosAchievementsCore.nameOf({name = "Blooded"}), "Blooded", "and in English")
eq(select(1, ChaosAchievementsCore.toast({name = "Hardened", points = 10}, "", "pt-BR")), "Calejado", "the unlock toast title in pt-BR")
dofile("data/scripts/chaos/season_journey_core.lua")
do
	local JK = ChaosSeasonJourneyCore
	local jj = {chapters = {{key = "a", name = "First Embers", level = 0, text = "Face the heart of the fire.", objectives = {
		{key = "o1", text = "Reach level 100", stat = "level", target = 100}}, rewards = {{kind = "passxp", amount = 5},
		{kind = "look", id = 1, slot = "x", name = "Magma Monocle appearance"}}},
		{key = "b", name = "Ash and Iron", level = 150, objectives = {}}}, name = "The Ashen Pilgrimage"}
	local header, chapters = JK.view(jj, {level = 10, stats = {}, flags = {}, done = {}, claimed = {}}, {lang = "pt-BR"})
	eq(header.name, "A Peregrinação das Cinzas", "journey name in pt-BR")
	eq(chapters[1].name, "Primeiras Brasas", "chapter name in pt-BR")
	eq(chapters[1].objectives[1].text, "Chegue ao nível 100", "objective in pt-BR")
	eq(chapters[1].rewards[1].text, "5 de XP do passe", "pass XP reward in pt-BR")
	eq(chapters[1].rewards[2].text, "Aparência Magma Monocle", "appearance reward in pt-BR")
	eq(chapters[2].lockedWhy, "Termine Primeiras Brasas primeiro.", "locked reason in pt-BR")
	local h2, c2 = JK.view(jj, {level = 10, stats = {}, flags = {}, done = {}, claimed = {}}, {})
	eq(c2[2].lockedWhy, "Finish First Embers first.", "and in English")
end

-- Party Finder: the refusals of the core are keys the engine translates on display (O147)
dofile("data/scripts/chaos/party_finder_core.lua")
do
	local PK = ChaosPartyFinderCore or Chaos.partyFinderCore
	check(PK ~= nil and PK.reasons ~= nil, "party finder core is loaded")
	for k, text in pairs(PK and PK.reasons or {}) do
		check(pt[text] ~= nil, "party finder reason " .. k .. " has a pt-BR text")
	end
	for k, text in pairs(PK and PK.closeText or {}) do
		check(pt[text] ~= nil, "party finder close text " .. k .. " has a pt-BR text")
	end
	eq(I.text("pt-BR", "Leave your party first."), "Saia do seu grupo primeiro.", "a refusal in pt-BR")
	eq(I.text("en", "Leave your party first."), "Leave your party first.", "and in English")
end

-- Hideout: the refusals of hideout_core.lua are English keys hideout.lua translates when it sends them (O147)
do
	local fh = io.open("data/scripts/chaos/hideout_core.lua", "r")
	local src = fh:read("*a")
	fh:close()
	local n = 0
	for lit in src:gmatch('return [%w, ]-"([%u][^"\n]-%.)"') do
		if not lit:find("%.%.") and not lit:find("^%u%l+ %l+$") then
			n = n + 1
			check(pt[lit] ~= nil, "hideout_core refusal has a pt-BR text: " .. lit)
		end
	end
	check(n >= 15, "hideout_core refusals found (" .. n .. ")")
end

-- Town Portal: K.blockReason takes the translator (townportal.lua passes Chaos.t); the keys are in the table (O147)
dofile("data/scripts/chaos/townportal_core.lua")
do
	local TK = ChaosTownPortalCore
	local function T(key, ...) return I.text("pt-BR", key, ...) end
	eq(TK.blockReason({skull = true}, T), "Você não pode abrir um town portal com skull.", "portal refusal in pt-BR")
	eq(TK.blockReason({skull = true}), "You cannot open a town portal while you carry a skull.", "and in English")
	eq(TK.blockReason({cooldownLeft = 1}, T), "Seu Town Portal estará pronto de novo em 1 segundo.", "one second in pt-BR")
	eq(TK.blockReason({cooldownLeft = 7}, T), "Seu Town Portal estará pronto de novo em 7 segundos.", "seconds in pt-BR")
	eq(TK.blockReason({cooldownLeft = 7}), "Your Town Portal is ready again in 7 seconds.", "seconds in English")
	eq(TK.blockReason({instance = "a raid"}, T), "Você não pode abrir um town portal em a raid: saia pela saída própria.", "instance label")
	for _, f in ipairs({"casting", "tutorial", "noTown", "arena", "worldBoss", "siege", "rift", "dungeon", "tower", "hideout",
		"marches", "pzLocked", "skull", "pz"}) do
		local text = TK.blockReason({[f] = true})
		check(text ~= nil and pt[text] ~= nil, "town portal refusal " .. f .. " has a pt-BR text")
	end
end

print(string.format("i18n_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
