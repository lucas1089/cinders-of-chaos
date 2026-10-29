-- Regenerates website/overlay/plugins/chaos/wiki/wiki_data.json (the reference data of the website's wiki,
-- page.php?plugin=chaos&p=wiki) from the real server data files, so the wiki never drifts from the game.
-- Run from the server/ folder (the libraries dofile() their neighbours relative to it):
--   luajit tools/gen_wiki_data.lua            write the website file
--   luajit tools/gen_wiki_data.lua --check    exit 1 when the website file differs from what the data gives (CI)
--   lua5.3 works the same; the output is byte-identical under both (CI checks both).
-- The Codex generator (tools/gen_codex_data.lua) is loaded as a library and its tabs are taken as they are (modifiers,
-- powers, orbs, gems, uniques, sets, rift, supports, materials, basics): one parser for both. This file adds the
-- classes and their spells (data/XML/chaos_vocations*.xml, data/spells/chaos/spells_chaos.xml and the first comment of
-- each spell script), the passive tree (the client's treedata/nodes.lua and its stat texts), bosses, dungeons and events,
-- the Chaos monsters that spawn somewhere, the store, and `facts`: the numbers the written wiki guides quote
-- ({{key}} in website/overlay/plugins/chaos/wiki/guides/*.md; "::: if key" blocks hide what is switched off).
-- Entries of a system behind an off switch carry soon = true (W.switches). No clock, no random, no pairs() order.
-- Entry format (the Codex's, client/overlay/modules/game_codex/codex.lua): {id, name, sub, color, sections =
-- {{h, p = {paragraphs}, cols, rows, links}}}; the website renders it (wiki_lib.php).

local OUT_DEFAULT = "../website/overlay/plugins/chaos/wiki/wiki_data.json"
local TREE_DIR = "../client/overlay/modules/game_passivetree/"

CODEX_GEN_NO_MAIN = true
local Gen = dofile("tools/gen_codex_data.lua")
CODEX_GEN_NO_MAIN = nil
local num, signed, per10k, range = Gen.num, Gen.signed, Gen.per10k, Gen.range
local floor = math.floor

local W = {}
W.SOURCES = {"tools/gen_codex_data.lua (and every file it reads)", "data/XML/chaos_vocations*.xml",
	"data/spells/chaos/spells_chaos.xml", "data/spells/chaos/*/*.lua (first comment)",
	"data/scripts/chaos/chaos_constants.lua", "data/scripts/chaos/*_config.lua", "data/scripts/chaos/class_unlocks_core.lua",
	"data/scripts/chaos/dungeons_difficulty.lua", "data/scripts/chaos/display_scale_core.lua",
	"data/monster/monsters/chaos/**.xml", "tools/late_game_spawns.csv",
	"client/overlay/modules/game_passivetree/treedata/nodes.lua", "client/overlay/modules/game_passivetree/passivetree.lua"}

-- ---------------------------------------------------------------------------------------------------------------
-- JSON writer (sorted keys, the Codex's key order first; short values on one line)
-- ---------------------------------------------------------------------------------------------------------------
local KEY_ORDER = {"id", "name", "h", "sub", "color", "tab", "group", "soon", "p", "cols", "w", "rows", "links",
	"sections", "entries"}
local KEY_RANK = {}
for i, k in ipairs(KEY_ORDER) do
	KEY_RANK[k] = i
end

local function isArray(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		local ra, rb = KEY_RANK[a] or 1000, KEY_RANK[b] or 1000
		if ra ~= rb then
			return ra < rb
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

function W.jstr(s)
	s = tostring(s)
	s = s:gsub("[%c\"\\]", function(c)
		if c == "\"" then
			return "\\\""
		elseif c == "\\" then
			return "\\\\"
		elseif c == "\n" then
			return "\\n"
		elseif c == "\t" then
			return "\\t"
		elseif c == "\r" then
			return "\\r"
		end
		return string.format("\\u%04x", c:byte())
	end)
	return "\"" .. s .. "\""
end

local function scalar(v)
	local tv = type(v)
	if tv == "number" then
		return num(v)
	elseif tv == "string" then
		return W.jstr(v)
	elseif tv == "boolean" then
		return tostring(v)
	end
	return nil
end

local function inline(v)
	local s = scalar(v)
	if s then
		return s
	end
	if type(v) ~= "table" then
		error("cannot write " .. type(v))
	end
	local parts = {}
	if isArray(v) then
		for _, x in ipairs(v) do
			parts[#parts + 1] = inline(x)
		end
		return "[" .. table.concat(parts, ", ") .. "]"
	end
	for _, k in ipairs(sortedKeys(v)) do
		parts[#parts + 1] = W.jstr(k) .. ": " .. inline(v[k])
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

function W.json(v, indent)
	indent = indent or ""
	local s = scalar(v)
	if s then
		return s
	end
	local one = inline(v)
	if #one + #indent * 4 <= 116 then
		return one
	end
	local parts = {}
	local inner = indent .. "\t"
	if isArray(v) then
		for _, x in ipairs(v) do
			parts[#parts + 1] = inner .. W.json(x, inner)
		end
		return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
	end
	for _, k in ipairs(sortedKeys(v)) do
		parts[#parts + 1] = inner .. W.jstr(k) .. ": " .. W.json(v[k], inner)
	end
	return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

-- ---------------------------------------------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------------------------------------------
local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local function attrs(s)
	local t = {}
	for k, v in s:gmatch("([%w_]+)%s*=%s*\"([^\"]*)\"") do
		t[k] = v
	end
	return t
end

local function sortedPairs(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local i = 0
	return function()
		i = i + 1
		if keys[i] ~= nil then
			return keys[i], t[keys[i]]
		end
	end
end

local function seconds(s)
	s = tonumber(s) or 0
	if s >= 60 and s % 60 == 0 then
		return num(s / 60) .. " min"
	end
	return num(s) .. " s"
end

local function msText(ms)
	return seconds((tonumber(ms) or 0) / 1000)
end

local function cap1(s)
	return (tostring(s):gsub("^%l", string.upper))
end

local function titleCase(s)
	return (tostring(s):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

local function hhmm(h, m)
	return string.format("%02d:%02d", floor(tonumber(h) or 0), floor(tonumber(m) or 0))
end

local WEEKDAY_EN = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
-- the Portuguese guides quote the days too ({{siege.whenPt}})
local WEEKDAY_PT = {"domingo", "segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado"}

local function list(t, sep)
	local out = {}
	for i, v in ipairs(t) do
		out[i] = tostring(v)
	end
	return table.concat(out, sep or ", ")
end

-- "a, b and c" (last = " e " for the pt-BR guides)
local function sentence(list, last)
	if #list <= 1 then
		return list[1] or ""
	end
	return table.concat(list, ", ", 1, #list - 1) .. (last or " and ") .. list[#list]
end

local function money(v)
	v = floor(tonumber(v) or 0)
	local s = tostring(v)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local COLORS = {class = "#f6cf72", spell = "#9fdc7f", tree = "#e8b84a", boss = "#ff7050", dungeon = "#c0a0ff",
	event = "#ffb050", monster = "#d6c9ae", store = "#ff70c0", basics = "#d6c9ae"}

-- ---------------------------------------------------------------------------------------------------------------
-- loading
-- ---------------------------------------------------------------------------------------------------------------
local function cfg(name)
	return dofile("data/scripts/chaos/" .. name .. ".lua")
end

function W.load()
	local D = Gen.load()
	D.codex = Gen.build(D)
	D.raid = cfg("raid_config")
	D.uberCfg = cfg("uber_config")
	D.descent = cfg("descent_config")
	D.invasion = cfg("invasion_config")
	D.siege = cfg("siege_config")
	D.harvest = cfg("harvest_event_config")
	D.harvestArt = dofile("data/lib/chaos_harvest_art.lua")
	D.guildboss = cfg("guildboss_config")
	D.pocket = cfg("pocketboss_config")
	D.mech = cfg("boss_mechanics_config")
	dofile("data/scripts/chaos/boss_mechanics_core.lua")
	D.goblin = cfg("treasure_goblin_config")
	D.atlas = cfg("atlas_config")
	D.season = cfg("season_config")
	D.boards = cfg("leaderboard_config")
	D.orbx = cfg("orbexchange_config")
	D.market = cfg("market_config")
	D.factions = cfg("factions_config")
	D.mentor = cfg("mentor_config")
	D.pvpzone = cfg("pvpzone_config")
	D.arena = cfg("arena_config")
	D.bg = cfg("battleground_config")
	D.guild = cfg("guild_config")
	D.guildwar = cfg("guildwar_config")
	D.pets = cfg("pets_config")
	D.newplayer = cfg("newplayer_config")
	D.ascq = cfg("ascension_quest_config")
	D.pact = cfg("pact_config")
	D.seasonpass = cfg("seasonpass_config")
	D.coins = cfg("shop_coins_config")
	D.respec = cfg("respec_config")
	D.difficulty = cfg("dungeons_difficulty")
	D.pace = cfg("pace_config")
	D.areagen = cfg("areagen_config")
	D.antibot = cfg("antibot_config")
	D.scale = cfg("display_scale_config")
	dofile("data/scripts/chaos/class_unlocks_core.lua")
	D.unlocks = ChaosClassUnlocksCore.config
	dofile("data/scripts/chaos/atlas_core.lua")
	D.A = ChaosAtlasCore
	D.C0 = Chaos
	return D
end

-- ---------------------------------------------------------------------------------------------------------------
-- classes and spells
-- ---------------------------------------------------------------------------------------------------------------
-- the vocation entries: {[id] = {id, name, gainhp, gainmana, gaincap, attackspeed, basespeed}}
function W.vocations()
	local out = {}
	for _, f in ipairs({"chaos_vocations.xml", "chaos_vocations_monk.xml", "chaos_vocations_necro.xml",
			"chaos_vocations_templar.xml"}) do
		local text = assert(readFile("data/XML/" .. f), "missing data/XML/" .. f)
		for head in text:gmatch("<vocation%s([^>]*)>") do
			local a = attrs(head)
			local id = tonumber(a.id)
			out[id] = {id = id, name = a.name, hp = tonumber(a.gainhp), mana = tonumber(a.gainmana), cap = tonumber(a.gaincap),
				attackspeed = tonumber(a.attackspeed), speed = tonumber(a.basespeed)}
		end
	end
	return out
end

-- the first comment of a spell script, joined ("-- Rime Bloom: ice burst ..." -> "ice burst ...")
function W.spellText(path, name)
	local text = readFile(path)
	if not text then
		return ""
	end
	local lines = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local c = line:match("^%-%-%s?(.*)$")
		if not c then
			break
		end
		lines[#lines + 1] = c
	end
	local s = table.concat(lines, " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	local prefix = name .. ":"
	if s:sub(1, #prefix) == prefix then
		s = s:sub(#prefix + 1):gsub("^%s+", "")
	end
	return cap1(s)
end

function W.spells(vocs)
	local xml = assert(readFile("data/spells/chaos/spells_chaos.xml"))
	local nameToId = {}
	for id, v in pairs(vocs) do
		nameToId[v.name] = id
	end
	local out = {}
	for head, body in xml:gmatch("<instant%s([^>]*)>(.-)</instant>") do
		local a = attrs(head)
		local classes = {}
		for v in body:gmatch("<vocation name=\"([^\"]+)\"") do
			classes[#classes + 1] = assert(nameToId[v], "unknown vocation " .. v)
		end
		local mana = tonumber(a.mana) or 0
		out[#out + 1] = {id = tonumber(a.spellid), name = a.name, words = a.words, level = tonumber(a.level) or 1,
			mana = mana, manaPercent = (mana == 0 and tonumber(a.manapercent)) or nil, cooldown = tonumber(a.cooldown) or 0,
			group = a.group, premium = a.premium == "1", classes = classes,
			text = W.spellText("data/spells/" .. a.script, a.name)}
	end
	table.sort(out, function(x, y)
		if x.level ~= y.level then
			return x.level < y.level
		end
		return x.id < y.id
	end)
	return out
end

local function costText(s)
	if s.manaPercent then
		return num(s.manaPercent) .. "% max mana"
	end
	return num(s.mana)
end

-- class key (chaos_constants.lua ids) by vocation id
local function classKeys(C0)
	local out = {}
	for k, id in pairs(C0.classes.ids) do
		out[id] = k
	end
	return out
end

-- the lines in the order of the class tables: base id -> {base, asc1, asc2}
local LINE_ORDER = {4, 3, 1, 11, 17, 20, 23}

function W.lines(D, vocs)
	local out = {}
	for _, base in ipairs(LINE_ORDER) do
		local choices = D.C0.classes.ascension.choices[base]
		local asc = {}
		for word, id in sortedPairs(choices) do
			asc[#asc + 1] = {word = word, id = id}
		end
		table.sort(asc, function(a, b) return a.id < b.id end)
		out[#out + 1] = {base = base, asc = asc}
	end
	return out
end

function W.classEntries(D, vocs, spells, treeByClass)
	local keyOf = classKeys(D.C0)
	local lockOf = {}
	for key, c in sortedPairs(D.unlocks.classes) do
		for _, v in ipairs(c.vocations) do
			lockOf[v] = {key = key, c = c}
		end
	end
	local out = {}
	for _, line in ipairs(W.lines(D, vocs)) do
		local base = vocs[line.base]
		local ids = {line.base}
		for _, a in ipairs(line.asc) do
			ids[#ids + 1] = a.id
		end
		local inLine = {}
		for _, id in ipairs(ids) do
			inLine[id] = true
		end
		-- stats per class
		local statRows = {}
		for _, id in ipairs(ids) do
			local v = vocs[id]
			statRows[#statRows + 1] = {v.name, num(v.hp), num(v.mana), num(v.cap), msText(v.attackspeed), num(v.speed)}
		end
		-- ascensions
		local ascRows = {}
		for _, a in ipairs(line.asc) do
			local text = D.ascq.paths[a.word] or vocs[a.id].name
			ascRows[#ascRows + 1] = {vocs[a.id].name, cap1(text) .. "."}
		end
		-- spells of the line
		local spellRows, spellLinks = {}, {}
		for _, s in ipairs(spells) do
			local who = {}
			for _, c in ipairs(s.classes) do
				if inLine[c] then
					who[#who + 1] = vocs[c].name
				end
			end
			if #who > 0 then
				spellRows[#spellRows + 1] = {s.name, s.words, num(s.level), costText(s), msText(s.cooldown),
					#who == #ids and "whole line" or table.concat(who, ", ")}
				spellLinks[#spellLinks + 1] = "spell:" .. s.id
			end
		end
		-- keystones and notables the line may take
		local ksRows, ksLinks = {}, {}
		for _, k in ipairs(treeByClass[keyOf[line.base]] or {}) do
			ksRows[#ksRows + 1] = {k.name, k.classes}
			ksLinks[#ksLinks + 1] = k.id
		end
		local lock = lockOf[line.base]
		local p = {}
		if lock and lock.c.locked then
			local methods = {}
			for kind, spec in sortedPairs(lock.c.unlock) do
				local m = ChaosClassUnlocksCore.methods[kind]
				methods[#methods + 1] = m and m.describe(spec, lock.c) or kind
			end
			p[#p + 1] = "Unlockable class: " .. table.concat(methods, "; or ") .. ". The unlock is for every character of the account."
		else
			p[#p + 1] = "Open to every account from the start."
		end
		p[#p + 1] = string.format("At level %d a %s ascends into one of two classes: the Ascendant Oracle in the teleport room's market starts the quest.",
			D.C0.classes.ascension.minLevel, base.name)
		local g = D.ascq.guardians[line.base] or D.ascq.guardians.default
		local sections = {
			{h = "Overview", p = p},
			{h = "Ascended classes", cols = {"Class", "Path"}, w = {25, 75}, rows = ascRows},
			{h = "Per level and base values", p = {"Health, mana and capacity gained per level; the base attack interval and speed."},
				cols = {"Class", "Health", "Mana", "Capacity", "Attack", "Speed"}, w = {24, 14, 14, 16, 16, 16}, rows = statRows},
			{h = "Ascension trial", p = {string.format("The Trial: alone against the %s for %s. %s", g.name,
				seconds(D.ascq.trial.timeLimitSeconds), g.hint),
				string.format("Before it, Proof of Strength: %d points from rare (%d) and legendary (%d) monsters of at least %s x your level.",
					D.ascq.proof.needed, D.ascq.proof.points.rare, D.ascq.proof.points.legendary, num(D.ascq.proof.levelShare))}},
			{h = "Spells", cols = {"Spell", "Words", "Level", "Mana", "Cooldown", "Classes"}, w = {22, 22, 9, 12, 12, 23},
				rows = spellRows, links = spellLinks}
		}
		if #ksRows > 0 then
			sections[#sections + 1] = {h = "Keystones of the line", cols = {"Keystone", "Classes"}, w = {40, 60}, rows = ksRows,
				links = ksLinks}
		end
		local ascNames = {}
		for _, a in ipairs(line.asc) do
			ascNames[#ascNames + 1] = vocs[a.id].name
		end
		out[#out + 1] = {id = "class:" .. keyOf[line.base], name = base.name, color = COLORS.class,
			sub = string.format("Base class; ascends into the %s or the %s.%s", ascNames[1], ascNames[2],
				(lock and lock.c.locked) and " Unlockable." or ""),
			sections = sections}
	end
	return out
end

function W.spellEntries(spells, vocs)
	local out = {}
	for _, s in ipairs(spells) do
		local who = {}
		for _, c in ipairs(s.classes) do
			who[#who + 1] = vocs[c].name
		end
		out[#out + 1] = {id = "spell:" .. s.id, name = s.name, color = COLORS.spell,
			sub = string.format("\"%s\", level %d, %s mana, cooldown %s", s.words, s.level, costText(s), msText(s.cooldown)),
			sections = {
				{h = "Effect", p = {s.text ~= "" and s.text or "-"}},
				{h = "Spell", cols = {"", ""}, w = {35, 65}, rows = {
					{"Words", s.words}, {"Level", num(s.level)}, {"Mana", costText(s)}, {"Cooldown", msText(s.cooldown)},
					{"Kind", cap1(s.group)}, {"Classes", table.concat(who, ", ")}}}
			}}
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- passive tree (the client tree is the source: names, texts and stats; the server copy is generated from it)
-- ---------------------------------------------------------------------------------------------------------------
local VARIANT_CLASSES = {knight = {"warrior"}, paladin = {"ranger"}, sorcerer = {"mystic", "elementalist"}}

function W.tree(D, vocs)
	local saved = {getTreeNodes = getTreeNodes, getCustomStatString = getCustomStatString, tr = rawget(_G, "tr")}
	if not saved.tr then -- the client's tr() (client_chaos_locale): the wiki text is English
		tr = function(text, ...)
			if select("#", ...) > 0 then
				return string.format(text, ...)
			end
			return text
		end
	end
	dofile(TREE_DIR .. "treedata/nodes.lua")
	dofile(TREE_DIR .. "passivetree.lua")
	local nodes = getTreeNodes()
	local statText = getCustomStatString
	local keyOf = classKeys(D.C0)
	local nameOfKey = {}
	for id, k in pairs(keyOf) do
		nameOfKey[k] = vocs[id].name
	end
	local allClasses = {}
	for _, line in ipairs(W.lines(D, vocs)) do
		allClasses[#allClasses + 1] = keyOf[line.base]
		for _, a in ipairs(line.asc) do
			allClasses[#allClasses + 1] = keyOf[a.id]
		end
	end
	local function classNames(keys)
		if not keys then
			return "every class"
		end
		local set = {}
		for _, k in ipairs(keys) do
			set[k] = true
		end
		local names = {}
		for _, k in ipairs(allClasses) do
			if set[k] then
				names[#names + 1] = nameOfKey[k]
			end
		end
		return #names == #allClasses and "every class" or table.concat(names, ", ")
	end
	local function lines(n)
		if type(n.stats) == "table" and #n.stats > 0 then
			return table.concat(n.stats, " "):gsub("%s+", " ")
		end
		return table.concat(statText(n.customStats or {}), " ")
	end
	local ids = {}
	local real = 0
	for id, n in pairs(nodes) do
		ids[#ids + 1] = id
		if not n.hidden and not n.isStartNode then
			real = real + 1
		end
	end
	table.sort(ids)
	local keystones, notables, masteries = {}, {}, {}
	local byClass = {}
	local function addFor(keys, item)
		for _, k in ipairs(keys or allClasses) do
			byClass[k] = byClass[k] or {}
			table.insert(byClass[k], item)
		end
	end
	for _, id in ipairs(ids) do
		local n = nodes[id]
		if not n.hidden and not n.isStartNode then
			if n.isKeystone then
				local variants = {}
				for vkey, v in sortedPairs(n) do
					if type(v) == "table" and v.name and v.customStats then
						variants[#variants + 1] = {key = vkey, v = v}
					end
				end
				if #variants > 0 then
					-- variants with the same name and text are one keystone of several classes (the Thief, Necromancer,
					-- Monk and Templar lines give the same pair to all their classes; Ricochet is the Ranger's and the
					-- Beastmaster's); its id is that of the variant of the class that comes first (the base class)
					local rank = {}
					for i, k in ipairs(allClasses) do
						rank[k] = i
					end
					local groups, order = {}, {}
					for _, x in ipairs(variants) do
						local gk = x.v.name .. "\0" .. lines(x.v)
						if not groups[gk] then
							groups[gk] = {x = x, keys = {}, rank = math.huge}
							order[#order + 1] = gk
						end
						local g = groups[gk]
						for _, k in ipairs(VARIANT_CLASSES[x.key] or {x.key}) do
							table.insert(g.keys, k)
							if (rank[k] or math.huge) < g.rank then
								g.rank, g.x = rank[k], x
							end
						end
					end
					for _, gk in ipairs(order) do
						local g = groups[gk]
						local x, keys = g.x, g.keys
						local e = {id = "tree:" .. id .. ":" .. x.key, name = x.v.name, classes = classNames(keys), text = lines(x.v),
							node = id, iconKey = x.v.icon or n.icon}
						keystones[#keystones + 1] = e
						addFor(keys, e)
					end
				else
					local e = {id = "tree:" .. id, name = n.name, classes = classNames(n.classes), text = lines(n), node = id,
						iconKey = n.icon}
					keystones[#keystones + 1] = e
					addFor(n.classes, e)
				end
			elseif n.isMastery and n.masteries then
				local rows = {}
				for _, m in ipairs(n.masteries) do
					rows[#rows + 1] = {m.name, table.concat(statText(m.customStats or {}), " ")}
				end
				masteries[#masteries + 1] = {id = "tree:" .. id, name = n.name, classes = classNames(n.classes), rows = rows,
					node = id, iconKey = n.icon}
			elseif n.name and n.name ~= "Attribute" and not n.name:find("^Wrath") and lines(n) ~= "" then
				notables[#notables + 1] = {id = "tree:" .. id, name = n.name, classes = classNames(n.classes), text = lines(n),
					node = id}
			end
		end
	end
	getTreeNodes, getCustomStatString = saved.getTreeNodes, saved.getCustomStatString
	tr = saved.tr
	local byName = function(a, b)
		if a.name == b.name then
			return a.id < b.id
		end
		return a.name < b.name
	end
	table.sort(keystones, byName)
	table.sort(notables, byName)
	table.sort(masteries, byName)
	for _, l in pairs(byClass) do
		table.sort(l, byName)
	end
	return {keystones = keystones, notables = notables, masteries = masteries, byClass = byClass, count = real}
end

function W.treeEntries(D, T)
	local P, PG = D.C0.passive, D.C0.paragon
	local out = {}
	local pts = {}
	for _, lv in ipairs({100, 300, 500, 1000}) do
		pts[#pts + 1] = {num(lv), num(floor((lv - P.startLevel) / P.levelsPerPoint))}
	end
	local pRows = {}
	local pgMax = 0
	for _, cat in ipairs(PG.categories) do
		for _, s in ipairs(cat.stats) do
			pgMax = pgMax + s.maxPoints
			pRows[#pRows + 1] = {cat.name, s.name, "+" .. num(s.perPoint) .. "%", num(s.maxPoints),
				"+" .. num(s.perPoint * s.maxPoints) .. "%"}
		end
	end
	out[#out + 1] = {id = "tree:about", name = "The passive tree", color = COLORS.basics,
		sub = "Points, presets, resets and the Paragon track.",
		sections = {
			{h = "Points", p = {string.format("One point every %d levels above level %d (passive tree points from bosses come on top). Keystones change how you play; notables are strong named nodes on the paths. Every class sees the main tree, and the Thief, Monk, Necromancer and Templar lines also a class section.",
				P.levelsPerPoint, P.startLevel),
				string.format("Up to %d presets. A full reset costs %s gold x your level; a single node can be refunded too.",
					P.maxPresets, money(P.resetCostPerLevel))},
				cols = {"Level", "Points (about)"}, w = {50, 50}, rows = pts},
			{h = "Paragon", p = {string.format("After level %d: %d Paragon point per level up to level %d, then one every %d levels (all of the track by level %d), spent on small capped stats.",
				PG.startLevel, PG.pointsPerLevel, PG.slowFrom, PG.levelsPerPointSlow,
				PG.slowFrom + (pgMax - (PG.slowFrom - PG.startLevel) * PG.pointsPerLevel) * PG.levelsPerPointSlow)},
				cols = {"Group", "Stat", "Per point", "Points", "At most"}, w = {18, 30, 16, 16, 20}, rows = pRows}
		}}
	for _, k in ipairs(T.keystones) do
		out[#out + 1] = {id = k.id, name = k.name, color = COLORS.tree, group = "keystone", iconKey = k.iconKey,
			sub = "Keystone. " .. k.classes .. ".", sections = {
				{h = "Effect", p = {k.text}},
				{h = "Who", p = {"Classes: " .. k.classes .. "."}}}}
	end
	for _, k in ipairs(T.notables) do
		out[#out + 1] = {id = k.id, name = k.name, color = "#c8b890", group = "notable",
			sub = "Notable. " .. k.text, sections = {
				{h = "Effect", p = {k.text}},
				{h = "Who", p = {"Classes: " .. k.classes .. "."}}}}
	end
	for _, m in ipairs(T.masteries) do
		out[#out + 1] = {id = m.id, name = m.name, color = "#9fdc7f", group = "mastery", iconKey = m.iconKey,
			sub = "Mastery: pick one effect. " .. m.classes .. ".", sections = {
				{h = "Effects", p = {"The node costs a point like any other; you choose one effect and can change it later for the price of a single-node refund."},
					cols = {"Effect", "Stats"}, w = {30, 70}, rows = m.rows},
				{h = "Who", p = {"Classes: " .. m.classes .. "."}}}}
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- bosses, dungeons and events
-- ---------------------------------------------------------------------------------------------------------------
local function rewardItems(D, list)
	local out = {}
	for _, x in ipairs(list or {}) do
		local name = x.name
		if not name then
			for _, o in ipairs(D.C.config.orbs) do
				if o.id == x.id then
					name = o.name
				end
			end
		end
		if x.id == 2160 then
			name = "crystal coin"
		elseif x.id == 2152 then
			name = "platinum coin"
		end
		out[#out + 1] = num(x.count) .. " " .. (name or ("item " .. x.id))
	end
	return table.concat(out, ", ")
end

local function scheduleHours(wb)
	local hours = {}
	for h = 0, 23 do
		if (h - wb.offsetHours) % wb.intervalHours == 0 then
			hours[#hours + 1] = hhmm(h, 0)
		end
	end
	return hours
end

-- the boss mechanics of a profile (boss_mechanics_config.lua): rows of {mechanic, warning, counterplay}
local MECHKIND = {circle = "circle", cone = "cone", line = "line", ring = "ring", cross = "cross", puddles = "puddles",
	follow = "follows you", marks = "marks", channel = "channel", soak = "soak", los = "line of sight"}
local function mechRows(D, key)
	local p = D.mech.profiles[key]
	if not p then
		return nil
	end
	local G = ChaosBossMechCore
	local rows = {}
	local function warnText(spec)
		local ms = G.warnMs(spec, p.difficulty or 0.2, p.fair)
		if spec.kind == "channel" then
			ms = math.max(ms, spec.channelMs or 8000)
		elseif spec.kind == "los" then
			ms = math.max(ms, spec.hideMs or 3000)
		end
		return string.format("%.1f s", ms / 1000)
	end
	for _, t in ipairs(p.telegraphs or {}) do
		rows[#rows + 1] = {t.label .. " (" .. MECHKIND[t.kind] .. (t.minTier and (", tier " .. t.minTier .. "+") or "") .. ")",
			warnText(t), t.tip}
	end
	for _, m in ipairs(p.timed or {}) do
		rows[#rows + 1] = {m.label .. " (" .. MECHKIND[m.kind] .. ")", warnText(m), m.tip}
	end
	for _, a in ipairs(p.adds or {}) do
		rows[#rows + 1] = {a.name .. " (adds, " .. a.mode .. ")", floor(a.at * 100 + 0.5) .. "% health", a.tip}
	end
	if p.debuff then
		rows[#rows + 1] = {p.debuff.label .. " (stacks)", "on its hits", p.debuff.tip}
	end
	if p.softEnrage then
		rows[#rows + 1] = {"Soft enrage", seconds(p.softEnrage.at), string.format("+%d%% damage a minute after that: keep the damage up.",
			floor(p.softEnrage.perMin * 100 + 0.5))}
	end
	return rows
end
local function mechSection(D, key, intro)
	local rows = mechRows(D, key)
	if not rows or #rows == 0 then
		return nil
	end
	return {h = "Mechanics", p = {intro or "Red marks pulse on the ground where the hit will land; the hit lands only on the tiles still marked, so walk out. A bar under the monster bar names the next mechanic and counts down."},
		cols = {"Mechanic", "Warning", "Counterplay"}, w = {30, 14, 56}, rows = rows}
end
W.mechRows = mechRows

function W.bossEntries(D)
	local out = {}
	local wb = D.C0.worldBoss
	local r = wb.reward
	local podium = {}
	for _, c in ipairs(r.podium.categories) do
		podium[#podium + 1] = string.format("%s (title %s)", c.name, c.title)
	end
	local bossLinks = {}
	for i, b in ipairs(wb.bosses) do
		bossLinks[i] = "boss:world:" .. i
	end
	local bossNames = {}
	for i, b in ipairs(wb.bosses) do
		bossNames[i] = {b.name, cap1(b.element)}
	end
	out[#out + 1] = {id = "boss:world", name = "World bosses", color = COLORS.boss, group = "world",
		sub = string.format("Every %d hours (%s server time), level %d+, up to %d players.", wb.intervalHours,
			table.concat(scheduleHours(wb), ", "), wb.minLevel, wb.maxPlayers),
		sections = {
			{h = "The event", p = {
				string.format("Portals open next to the temples; the boss appears %s later and leaves after %s if it is still alive. %s",
					seconds(wb.gatherSeconds), seconds(wb.fightMinutes * 60), wb.mode == "rotation" and "The bosses take turns." or "The boss is random."),
				string.format("Level %d or more; at most %d players in the lobby and the arena. No player-vs-player damage inside.", wb.minLevel,
					wb.maxPlayers),
				"Your score is your damage on the boss plus the healing you did on others and the damage you survived (tanking counts half)."}},
			{h = "Rewards", p = {
				string.format("Everyone with a score of at least %s%% of the boss's health: %s gold to the bank and a share of %s by score; %s, plus a share of %s.",
					num(r.minScorePercent), money(r.bankGold), money(r.bankGoldPool), rewardItems(D, r.base), rewardItems(D, r.pool)),
				string.format("A boss gear item: %s + share x %s; a boss-only unique: %s + share x %s.", per10k(r.gearChance),
					per10k(r.gearShareBonus), per10k(r.uniqueChance), per10k(r.uniqueShareBonus)),
				string.format("The top %d in %s get extra orbs, a better unique chance and a title for %d days.", r.podium.top,
					sentence(podium), wb.roles.titleDays)}},
			{h = "The bosses", cols = {"Boss", "Element"}, w = {60, 40}, rows = bossNames, links = bossLinks}
		}}
	for i, b in ipairs(wb.bosses) do
		local rows = {}
		for _, ph in ipairs(b.phases) do
			local what = {}
			if ph.adds then
				what[#what + 1] = string.format("%d x %s (%s health)", ph.adds.count, ph.adds.name, money(ph.adds.health))
			end
			if ph.enrage then
				what[#what + 1] = "enrage: a pulse hits everyone around it"
			end
			rows[#rows + 1] = {floor(ph.at * 100 + 0.5) .. "%", table.concat(what, "; "), ph.yell or ""}
		end
		local pulse = b.pulse
		out[#out + 1] = {id = "boss:world:" .. i, name = b.name, color = COLORS.boss, group = "world",
			sub = "World boss, " .. b.element .. ".", sections = {
				{h = "Overview", p = {b.intro, string.format("Enraged, it pulses %s damage (%s-%s) within %d sqm every %d s.%s", pulse.type,
					money(pulse.min), money(pulse.max), pulse.radius, pulse.every,
					pulse.healPerHit and string.format(" Every player hit heals it by %s.", money(pulse.healPerHit)) or "")}},
				{h = "Phases", cols = {"Health", "What happens", "Yell"}, w = {14, 46, 40}, rows = rows},
				mechSection(D, b.name:lower()),
				{h = "More", p = {"Schedule, rules and rewards: World bosses."}, links = {"boss:world"}}}}
		if not out[#out].sections[3] then
			table.remove(out[#out].sections, 3)
		end
	end
	-- pocket bosses (pocketboss_config.lua, server/README.md "Pocket bosses")
	local pk = D.pocket
	local catNames = {world = "World bosses", island = "Island bosses", raid = "Raid bosses (random raids)"}
	local prow = {}
	for _, key in ipairs({"world", "island", "raid"}) do
		local c = pk.categories[key]
		if c then
			prow[#prow + 1] = {catNames[key], num(c.minLevel or wb.minLevel), floor(c.xpMult * 100 + 0.5) .. "%",
				floor(c.lootMult * 100 + 0.5) .. "%", num(c.minutes) .. " min", num(c.tokens)}
		end
	end
	out[#out + 1] = {id = "boss:pocket", name = "Pocket bosses", color = COLORS.boss, group = "world",
		sub = string.format("A private copy of a world, island or raid boss, any time: %d charges a day per boss.", pk.charges.daily),
		sections = {
			{h = "How it works", p = {
				"Open it with the Pocket button of the Boss Spawns window (Adventure > Boss Spawns), alone or with your party from a protection zone; every member spends a charge.",
				string.format("%d charges per boss and day (new ones at %02d:00 server time). Bonus charges stay over the reset: at most %d held and %d added a day.",
					pk.charges.daily, pk.charges.resetHour or 0, pk.charges.bonusMax, pk.charges.bonusPerDay),
				"The boss is scaled to the party size. A lethal hit carries you out without dying; the charge stays spent.",
				string.format("After a boss's scheduled or contested fight rewarded you, its pocket waits %d minutes.", floor((pk.noStackSeconds or 0) / 60))}},
			{h = "Rewards", p = {
				"Less than the scheduled fight: experience and the corpse are cut (even the items that always drop are not sure), Conquest Tokens on top.",
				string.format("World bosses also give each player %s of their event's base orbs and one roll of the boss's set at %s.",
					floor(pk.categories.world.lootMult * 100 + 0.5) .. "%", per10k(wb.reward.gearChance * pk.categories.world.lootMult)),
				"The boss passive point counts for a pocket kill too: nobody is locked out by the clock."},
				cols = {"Bosses", "Level", "Experience", "Loot", "Time", "Tokens"}, w = {30, 10, 16, 12, 16, 16}, rows = prow},
			{h = "The scheduled fights", p = {string.format("Island and raid bosses spawned in the world give every helper whose damage and healing reach %s%% of the boss's health a personal loot roll; the corpse owner keeps the corpse.",
				num(pk.contested.minPercent))}, links = {"boss:world"}}
		}}
	-- the raid
	local rc = D.raid
	local rRows, rLinks = {}, {}
	for _, b in ipairs(rc.bosses) do
		rRows[#rRows + 1] = {b.name, seconds(b.enrageAt), b.final and "final boss" or ""}
		rLinks[#rLinks + 1] = "boss:raid:" .. b.key
	end
	local uRows = {}
	for _, u in ipairs(rc.uniques or {}) do
		local from = {}
		for _, k in ipairs(u.bosses) do
			for _, b in ipairs(rc.bosses) do
				if b.key == k then
					from[#from + 1] = b.name
				end
			end
		end
		uRows[#uRows + 1] = {u.name, table.concat(from, ", ")}
	end
	local vRows = {}
	for _, v in ipairs((rc.vendor and rc.vendor.offers) or {}) do
		vRows[#vRows + 1] = {v.name, num(v.price), num(v.weekly)}
	end
	local raidSections = {
		{h = "The raid", p = {
			string.format("A weekly raid for %d to %d players of level %d or more: %d bosses behind trash in a sealed zone. The week resets on %s at %s.",
				rc.minPlayers, rc.maxPlayers, rc.minLevel, #rc.bosses, WEEKDAY_EN[rc.resetDay], hhmm(rc.resetHour, 0)),
			"Loot is personal, once a week per boss and character. A raid can be left and continued later the same week.",
			"A lethal hit is caught: you land in the entry hall, healed, and wait for the fight to end. No real death."}},
		{h = "Bosses", cols = {"Boss", "Enrage after", ""}, w = {55, 25, 20}, rows = rRows, links = rLinks}}
	if #uRows > 0 then
		raidSections[#raidSections + 1] = {h = "Raid uniques", cols = {"Unique", "Drops from"}, w = {45, 55}, rows = uRows}
	end
	if #vRows > 0 then
		raidSections[#raidSections + 1] = {h = "Sepulchre Marks vendor", cols = {"Offer", "Marks", "Per week"}, w = {50, 25, 25},
			rows = vRows}
	end
	out[#out + 1] = {id = "boss:raid", name = rc.name, color = COLORS.boss, group = "raid",
		sub = string.format("Weekly raid, %d-%d players, level %d+.", rc.minPlayers, rc.maxPlayers, rc.minLevel),
		sections = raidSections}
	local MECH = {sunder = "sunder (tank swap)", cleave = "frontal cleave", marks = "marked tiles", soak = "soak circles",
		adds = "adds", sweep = "sweeps", totem = "effigies to break", hex = "a hex to cleanse"}
	for _, b in ipairs(rc.bosses) do
		local rows = {}
		for _, ph in ipairs(b.phases or {}) do
			local m = {}
			for _, k in ipairs(ph.mech or {}) do
				m[#m + 1] = MECH[k] or k
			end
			rows[#rows + 1] = {floor(ph.at * 100 + 0.5) .. "%", ph.name, table.concat(m, ", ")}
		end
		out[#out + 1] = {id = "boss:raid:" .. b.key, name = b.name, color = COLORS.boss, group = "raid",
			sub = rc.name .. (b.final and ", final boss." or "."), sections = {
				{h = "Phases", p = {string.format("Enrages after %s.", seconds(b.enrageAt))}, cols = {"From health", "Phase", "Mechanics"},
					w = {18, 30, 52}, rows = rows},
				{h = "More", p = {"The raid: " .. rc.name .. "."}, links = {"boss:raid"}}}}
	end
	-- the Ascended Omens and the Cinderheart
	local U = D.uberCfg
	local kRows = {}
	for _, k in ipairs(U.kinds) do
		kRows[#kRows + 1] = {k.name, k.boss, k.omenBoss or "(the last step)"}
	end
	out[#out + 1] = {id = "boss:ascended", name = "Ascended Omens and the Cinderheart", color = COLORS.boss, group = "ascended",
		sub = "The top challenge above the Omen Keys, up to " .. U.maxPlayers .. " players.",
		sections = {
			{h = "The chain", p = {
				string.format("An Omen guardian kill gives every finisher a %d%% chance of an Ascended Shard of that omen; rifts of tier 13-15 give a shard too.",
					U.shardChance.omen),
				string.format("%d shards of one omen make an Ascended Sigil. The sigil opens that omen's Ascended arena (up to %d players); the kill gives a relic.",
					U.shardCost, U.maxPlayers),
				"One relic of each omen makes a Cinderheart Sigil, which opens the Cinderheart's arena."}},
			{h = "Bosses", cols = {"Omen", "Ascended boss", "Omen guardian"}, w = {25, 40, 35}, rows = kRows},
			{h = "Mechanics on top of the phases", p = {"Each Ascended boss and the Cinderheart add these to their telegraphs, hazards and adds."},
				cols = {"Boss", "Mechanic", "Counterplay"}, w = {22, 30, 48}, rows = (function()
					local rows = {}
					for _, k in ipairs(U.kinds) do
						for _, r in ipairs(mechRows(D, k.boss:lower()) or {}) do
							rows[#rows + 1] = {k.boss, r[1], r[3]}
						end
					end
					return rows
				end)()},
			{h = "Rewards (per finisher)", cols = {"Fight", "Gold", "Orbs", "Unique rolls"}, w = {25, 25, 30, 20}, rows = {
				{"Ascended", money(U.reward.ascended.gold), string.format("%d Upheaval, %d Fate, %d Exalted", U.reward.ascended.chaos,
					U.reward.ascended.divine, U.reward.ascended.exalted), num(U.reward.ascended.uniqueRolls)},
				{"Cinderheart", money(U.reward.cinder.gold), string.format("%d Upheaval, %d Fate, %d Exalted", U.reward.cinder.chaos,
					U.reward.cinder.divine, U.reward.cinder.exalted), num(U.reward.cinder.uniqueRolls)}}}
		}}
	-- the weekly guild boss
	local G = D.guildboss
	out[#out + 1] = {id = "boss:guild", name = G.boss.boss, color = COLORS.boss, group = "guild",
		sub = string.format("The weekly guild boss, %d-%d players of level %d+.", G.minPlayers, G.maxPlayers, G.minLevel),
		sections = {{h = "The fight", p = {
			"Guild members feed the Summoning Stone in the guild hall with materials, then summon the boss into an instanced arena.",
			string.format("%d to %d players of level %d or more; %d attempts a week. It enrages after %s.", G.minPlayers, G.maxPlayers,
				G.minLevel, G.maxAttempts, seconds(G.boss.enrageAt))}},
			mechSection(D, G.boss.boss:lower(), "On top of its telegraphs, pools and adds:")}}
	-- the other bosses with mechanics (boss_mechanics_config.lua): the Omen guardians, the rift guardians, the Hollow Vault,
	-- the generated areas' bosses and the dormant donor bosses
	local others = {
		{"Omen guardians", {"sangrith the bloodmoon herald", "morvane the hollow crown", "thalcyra the stormbound seer"}},
		{"Rift guardians (every tier; more from tier 8 and 12)", {"rift_guardian"}},
		{"Dungeons and hunting grounds", {"vault keeper ossrim", "ossivane the gravecage", "forgewarden kharzun",
			"vaelith the fallen seraph", "azhkarrath the chained wyrm", "the emberdeep maw", "the ossuary warden", "cinderwing"}},
		{"Dormant bosses (not spawned yet)", {"ormathulak", "talath", "gloomfire", "saga", "legendary warrior"}}}
	local mSections = {{h = "How to read a mechanic", p = {
		"A red mark pulses on every tile the hit will land on, from 1.5 to 3 seconds before it (harder content warns later). The hit lands only on the tiles still marked: walk out. There is always a safe tile you can reach in time at normal speed.",
		"Orange warnings name the big casts, and a bar under the monster bar names the next mechanic with a countdown: red = move out, purple = kill the totem, green = stand in the circle, blue = hide behind a pillar."}}}
	for _, grp in ipairs(others) do
		local rows = {}
		for _, key in ipairs(grp[2]) do
			local p = D.mech.profiles[key]
			for _, r in ipairs(mechRows(D, key) or {}) do
				rows[#rows + 1] = {key == "rift_guardian" and "Rift guardian" or titleCase(key), r[1], r[2], r[3]}
			end
		end
		mSections[#mSections + 1] = {h = grp[1], cols = {"Boss", "Mechanic", "Warning", "Counterplay"}, w = {18, 24, 10, 48},
			rows = rows}
	end
	out[#out + 1] = {id = "boss:mechanics", name = "Boss mechanics", color = COLORS.boss, group = "world",
		sub = "Telegraphs, adds, totems, soaks and pillars: what each boss does and how to answer it.", sections = mSections}
	return out
end

-- the generated dungeons of areagen_config.lua, in config order: {def, d, monsters} (monsters: the count the generator
-- places, from the same seed)
function W.generatedDungeons(D)
	local out = {}
	local A = ChaosAreaGenCore
	if not A then
		dofile("data/scripts/chaos/areagen_core.lua")
		A = ChaosAreaGenCore
	end
	for _, def in ipairs(D.areagen.areas) do
		if def.dungeon and def.enabled ~= false then
			local m = A.generate(D.areagen, def, {})
			out[#out + 1] = {def = def, d = def.dungeon, monsters = m.stats.monsters}
		end
	end
	return out
end

local DUNGEON_THEME = {vault = "Dark stone halls", marrow = "Catacombs of dark sand, slate and bones",
	crucible = "A forge cut into the rock, split by lava cracks and pools", sanctum = "A drowned shrine of wet caves and gilded chapels",
	throne = "The burnt court of the wyrms: basalt, lava, marble and gilded halls"}
function W.dungeonTheme(def)
	return DUNGEON_THEME[def.theme] or "Generated halls"
end

function W.dungeonEntries(D)
	local out = {}
	local dc = D.C0.dungeons
	local diffRows = {}
	for i, l in ipairs(D.difficulty.levels) do
		diffRows[#diffRows + 1] = {num(i), num(l.health) .. "%", num(l.damage) .. "%", "+" .. num(l.experience) .. "%",
			"+" .. num(l.gold) .. "%", "+" .. num(l.loot) .. "%"}
	end
	local listRows, listLinks = {}, {}
	for id, x in sortedPairs(dc.extra) do
		listRows[#listRows + 1] = {x.title, titleCase(x.bossName)}
		listLinks[#listLinks + 1] = "dungeon:" .. id
	end
	-- the generated dungeons (areagen_config.lua areas with `dungeon`: the Hollow Vault and the deep dungeons 6-9),
	-- registered at startup by areagen.lua
	local gen = W.generatedDungeons(D)
	for _, g in ipairs(gen) do
		listRows[#listRows + 1] = {g.d.title, g.def.boss.name}
		listLinks[#listLinks + 1] = "dungeon:" .. g.d.id
	end
	out[#out + 1] = {id = "dungeon:about", name = "Dungeons", color = COLORS.dungeon, group = "dungeon",
		sub = string.format("Queue, %d difficulties, speed and flawless challenges.", dc.maxDifficulty),
		sections = {
			{h = "How they work", p = {
				"Step on a dungeon's entry or open Adventure > Dungeons: pick a difficulty and join the queue; the group goes in together.",
				string.format("Kill %d%% of the dungeon's monsters to unlock its boss, then kill the boss. A run lasts at most %s. Each finished difficulty unlocks the next one.",
					dc.progressNeeded, seconds(dc.maxTimeSeconds)),
				"Speed and flawless challenges give points; solo and group rankings keep the best times."}},
			{h = "Dungeons", cols = {"Dungeon", "Boss"}, w = {50, 50}, rows = listRows, links = listLinks},
			{h = "Difficulty", p = {"What each difficulty does to the dungeon's monsters (health, damage) and to your rewards (experience, gold, an extra loot roll)."},
				cols = {"Level", "Health", "Damage", "Experience", "Gold", "Extra loot"}, w = {12, 16, 16, 20, 16, 20}, rows = diffRows}
		}}
	for id, x in sortedPairs(dc.extra) do
		local ch = {}
		for _, c in ipairs(x.challenges or {}) do
			ch[#ch + 1] = {c.title, c.desc, num(c.points)}
		end
		out[#out + 1] = {id = "dungeon:" .. id, name = x.title, color = COLORS.dungeon, group = "dungeon",
			sub = "Dungeon. Boss: " .. titleCase(x.bossName) .. ".", sections = {
				{h = "Overview", p = {"Boss: " .. titleCase(x.bossName) .. ". The level and group size come from the dungeon's entry."}},
				{h = "Challenges", cols = {"Challenge", "Goal", "Points"}, w = {30, 55, 15}, rows = ch},
				{h = "More", p = {"Queue and difficulty: Dungeons."}, links = {"dungeon:about"}}}}
	end
	local DD = D.difficulty
	for _, g in ipairs(gen) do
		local def, d = g.def, g.d
		local ch = {}
		for _, c in ipairs(d.challenges or {}) do
			ch[#ch + 1] = {c.title, c.desc, num(c.points)}
		end
		local mons = {}
		for _, row in ipairs(def.spawns.monsters) do
			mons[#mons + 1] = row[1]
		end
		local sections = {
			{h = "Overview", p = {
				string.format("%s, level %s and up, alone (the queue sends one player in). A run lasts %s; the speed challenge asks for %s.",
					W.dungeonTheme(def), num(d.level), seconds(d.time), seconds(math.floor((d.challenges[1].maxMs or 0) / 1000))),
				string.format("%d %s of %s x %s, %d monsters of level %s-%s in packs: %s. The boss room stays shut behind a gate until %d%% of them are dead; then it opens and the boss appears%s.",
					def.floors or 1, (def.floors or 1) == 1 and "floor" or "floors (a hole leads down)", num(def.size[1]),
					num(def.size[2]), g.monsters, num(def.spawns.level[1]), num(def.spawns.level[2]), table.concat(mons, ", "),
					D.C0.dungeons.progressNeeded, (def.floors or 1) > 1 and " on the lowest floor" or ""),
				string.format("Boss: %s (level %s). Its health grows by its own curve, %s%% to %s%% from difficulty 1 to 6%s; damage, experience, gold and loot follow the difficulty table.",
					def.boss.name, num(def.boss.level), num(d.bossHealth[1]), num(d.bossHealth[#d.bossHealth]),
					d.trashHealth and string.format(", the other monsters' %s%% to %s%%", num(d.trashHealth[1]),
						num(d.trashHealth[#d.trashHealth])) or "")}}}
		sections[#sections + 1] = mechSection(D, def.boss.name:lower(), "The boss fight:")
		if d.chest then
			local rows = {}
			local names = {}
			for _, row in ipairs(ChaosRarity.list) do
				names[row.id] = row.name
			end
			for i = 1, #DD.levels do
				local c = DD.chest(d.chest, i)
				rows[#rows + 1] = {num(i), money(c.gold), num(c.pieces), names[c.rarity] or num(c.rarity), "+" .. num(c.itemLevel),
					num(c.currency)}
			end
			sections[#sections + 1] = {h = "Boss chest", p = {
				"Every finisher gets the boss chest at the end of a won run, straight into the backpack (the inbox when it is full): gold to the bank, pieces of the boss's own gear with at least the rarity below (item find can raise it), at the boss's item level plus the bonus, and orb rolls."},
				cols = {"Difficulty", "Gold", "Gear", "Rarity", "Item level", "Orb rolls"}, w = {14, 18, 12, 20, 18, 18}, rows = rows}
		end
		sections[#sections + 1] = {h = "Challenges", cols = {"Challenge", "Goal", "Points"}, w = {30, 55, 15}, rows = ch}
		sections[#sections + 1] = {h = "More", p = {"Queue and difficulty: Dungeons."}, links = {"dungeon:about"}}
		out[#out + 1] = {id = "dungeon:" .. d.id, name = d.title, color = COLORS.dungeon, group = "dungeon",
			sub = string.format("Dungeon, level %s. Boss: %s.", num(d.level), def.boss.name), sections = sections}
	end
	-- the Infinity Tower
	local tw = D.C0.tower
	local mRows = {}
	for _, m in ipairs(tw.milestones) do
		mRows[#mRows + 1] = {money(m.points), rewardItems(D, m.items)}
	end
	local cRows = {}
	for i, c in ipairs(tw.seasonEnd.chests) do
		cRows[#cRows + 1] = {num(i), c.name, rewardItems(D, c.items)}
	end
	out[#out + 1] = {id = "dungeon:tower", name = "Infinity Tower", color = COLORS.dungeon, group = "tower",
		sub = string.format("Floors as waves; %d-day tower seasons.", tw.seasonLengthDays),
		sections = {
			{h = "The tower", p = {string.format("Climb floor after floor of waves and boss floors (Adventure > Infinity Tower). Each floor is worth %s points; the ranking keeps the best floor and time.",
				money(tw.pointsPerFloor)),
				string.format("Tower seasons last %d days: points, milestones and the ranking start over each season.", tw.seasonLengthDays)}},
			{h = "Milestones", cols = {"Points", "Reward"}, w = {30, 70}, rows = mRows},
			{h = "Season end (top 3)", cols = {"Place", "Chest", "Holds"}, w = {12, 30, 58}, rows = cRows}}}
	-- the Ember Descent
	local ds = D.descent
	out[#out + 1] = {id = "dungeon:descent", name = ds.name, color = COLORS.dungeon, group = "descent",
		sub = string.format("A roguelike run of %d-%d rooms for 1-%d players of level %d+.", ds.rooms.min, ds.rooms.max,
			ds.maxPlayers, ds.minLevel),
		sections = {{h = "The run", p = {
			string.format("Enter through the portal at the temple: %d to %d seeded rooms (combat, elite, treasure, shrine, merchant) and a boss at the end, %s at most.",
				ds.rooms.min, ds.rooms.max, seconds(ds.timeLimit)),
			"After a room pick one of three boons; curses make it harder and pay more. Embers are spent at the merchant.",
			string.format("%d free run a day and a weekly seeded run with its own leaderboard; an Ember Sigil (forged from %d shards and %s gold) gives one more run.",
				ds.freePerDay, ds.sigil.craft.shards, money(ds.sigil.craft.gold))}}}}
	return out
end

function W.eventEntries(D)
	local out = {}
	local ev = D.C0.events
	local rows = {}
	for _, e in ipairs(ev.list) do
		local when = {}
		if e.weekdays then
			for _, d in ipairs(e.weekdays) do
				when[#when + 1] = WEEKDAY_EN[d]
			end
		else
			when[#when + 1] = "days " .. list(e.monthdays) .. " of the month"
		end
		rows[#rows + 1] = {e.name, table.concat(when, ", "), e.description}
	end
	out[#out + 1] = {id = "event:calendar", name = "Event calendar", color = COLORS.event, group = "calendar",
		sub = "Recurring bonus days: experience, loot, monster tiers, tower points.",
		sections = {{h = "Events", p = {"Every event lasts the whole server day. Adventure > Events shows the calendar."},
			cols = {"Event", "When", "What"}, w = {20, 25, 55}, rows = rows}}}
	-- invasions
	local inv = D.invasion
	local sched = {}
	for _, s in ipairs(inv.schedule) do
		local days = {}
		for _, d in ipairs(s.weekdays) do
			days[#days + 1] = WEEKDAY_EN[d]
		end
		sched[#sched + 1] = table.concat(days, ", ") .. " " .. hhmm(s.hour, s.minute)
	end
	local fRows = {}
	for key, f in sortedPairs(inv.factions or {}) do
		local bosses = {}
		for _, b in ipairs(f.bosses or {}) do
			bosses[#bosses + 1] = b.rename or b.name
		end
		fRows[#fRows + 1] = {f.name, table.concat(bosses, ", ")}
	end
	table.sort(fRows, function(a, b) return a[1] < b[1] end)
	out[#out + 1] = {id = "event:invasion", name = "Invasions", color = COLORS.event, group = "invasion",
		sub = "Waves of invaders at a town or hunting ground, then their boss.",
		sections = {
			{h = "When", p = {string.format("Scheduled: %s (server time). There is also a chance of one random invasion a day.", sentence(sched))}},
			{h = "The fight", p = {
				string.format("%d waves in %s; the last one brings the boss. Players of level %d or more see the HUD and get rewards by contribution.",
					inv.waves.count, seconds(inv.timeLimitMinutes * 60), inv.minLevel),
				"Win and everyone nearby gets the Victory buff; lose and the invaders occupy the place for a while."}},
			{h = "Invaders", cols = {"Host", "Bosses"}, w = {40, 60}, rows = fRows}}}
	-- the guild siege
	local sg = D.siege
	out[#out + 1] = {id = "event:siege", name = "Guild Siege", color = COLORS.event, group = "siege",
		sub = string.format("Weekly, %s %s: guilds fight for the Chaos Obelisk.", WEEKDAY_EN[sg.weekday], hhmm(sg.hour, sg.minute)),
		sections = {{h = "The siege", p = {
			string.format("Every %s at %s (server time). Guilds with at least %d members of level %d or more sign up; %d to %d guilds per bracket fight for %s minutes.",
				WEEKDAY_EN[sg.weekday], hhmm(sg.hour, sg.minute), sg.minMembers, sg.minLevel, sg.minGuilds, sg.perBracket,
				num(sg.matchMinutes)),
			"Points for holding the obelisk and for kills. Nobody really dies inside.",
			string.format("The winner: %s gold to each member's bank and the title %s for %d days; the others %s gold.",
				money(sg.reward.winner.bankGold), sg.title, sg.titleDays, money(sg.reward.others.bankGold))}}}}
	-- treasure goblins
	local gb = D.goblin
	local kinds = {}
	for _, k in ipairs(gb.kinds or {}) do
		kinds[#kinds + 1] = k.name
	end
	out[#out + 1] = {id = "event:goblin", name = "Treasure goblins", color = COLORS.event, group = "goblin",
		sub = "Rare monsters that run away with loot.",
		sections = {{h = "Goblins", p = {"Any monster may turn into a treasure goblin when it spawns. Catch it before it escapes: goblins drop extra loot and count on the Goblin Slayer board.",
			"Kinds: " .. sentence(kinds) .. "."}}}}
	out[#out + 1] = dofile("tools/wiki_nemesis.lua")(cfg("nemesis_config"), COLORS.event)
	out[#out + 1] = W.harvestEntry(D)
	return out
end

-- the Haunted Harvest (harvest_event_config.lua): the window, the way in, the mechanics, its monsters and Widow Hessa
local MONTH_EN = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
	"November", "December"}
function W.harvestEntry(D)
	local H = D.harvest
	local function day(d)
		return MONTH_EN[d.month] .. " " .. d.day
	end
	local files = W.monsterFiles()
	local mons = {}
	for _, m in pairs(files) do
		if m.dir == "harvest" or m.dir:match("^harvest/") then
			mons[#mons + 1] = m
		end
	end
	table.sort(mons, function(a, b)
		if a.exp ~= b.exp then
			return a.exp < b.exp
		end
		return a.name < b.name
	end)
	local mRows = {}
	for _, m in ipairs(mons) do
		mRows[#mRows + 1] = {m.name, tostring(m.level or ""), ChaosSalvageCore.thousands(m.hp),
			ChaosSalvageCore.thousands(m.exp)}
	end
	local shop = {}
	for _, o in ipairs(H.shop) do
		shop[#shop + 1] = {o.name, num(o.price)}
	end
	local b = H.boss
	local phases = {}
	for _, p in ipairs(b.phases) do
		phases[#phases + 1] = p .. "%"
	end
	return {id = "event:harvest", name = "Haunted Harvest", color = COLORS.event, group = "harvest",
		sub = string.format("Every year from %s to %s: a cursed harvest village for levels 450-650.", day(H.window.from),
			day(H.window.to)),
		sections = {
			{h = "Getting there", p = {
				string.format("From %s to %s (server time) a Harvest Portal stands next to the temples of Cinderhold and Mirewake. It leads to the crossroads camp, where Widow Hessa trades hollow candy. The exit portals lead back to your temple.",
					day(H.window.from), day(H.window.to)),
				"The village: pumpkin fields, a corn maze, the hamlet of the hedge witches, the dead orchard, the gibbet hill, the graveyard and the ruined chapel. Under the chapel lie the catacombs and the King's Crypt."}},
			{h = "Things to do", p = {
				string.format("Pumpkins ripen on their own. Harvest a ripe one for %d-%d hollow candy (at most %d a day from pumpkins); now and then the pumpkin wakes up.",
					H.pumpkin.candy[1], H.pumpkin.candy[2], H.pumpkin.dailyCap),
				string.format("Dig a fresh grave in the graveyard, then open the coffin: %d-%d candy, a sexton's key (%d%%), or the dead climb out.",
					H.grave.candy[1], H.grave.candy[2], H.grave.keyChance),
				string.format("The candy cauldrons of the hamlet: trick or treat (%d-%d candy). The cursed bell on the gibbet hill calls a flock of ravens.",
					H.cauldron.candy[1], H.cauldron.candy[2]),
				"A sexton's key breaks the crypt seal in the ruined chapel for a few minutes: step on it to reach the catacombs. Upright coffins there can wake skeletons."}},
			{h = "The Hollow King", p = {
				string.format("%d ritual candles on the circle of the ritual chamber open a short-lived portal into the King's Crypt, the only way to %s.",
					H.circle.candles, b.name),
				string.format("At %s of his health the crypt's graves burst and raise his court, and a ward halves the damage he takes for %d seconds. The first kill of the day gives %d hollow candy on top of the loot.",
					sentence(phases), b.wardSeconds, b.dailyCandy)}},
			{h = "Monsters", cols = {"Monster", "Level", "Health", "Experience"}, w = {40, 20, 20, 20}, rows = mRows},
			{h = "Widow Hessa", p = {"Every monster of the event drops hollow candy. Widow Hessa at the crossroads trades it (candy cannot be sold). A hollow charm unlocks a haunted cosmetic your account does not own yet."},
				cols = {"Trade", "Hollow candy"}, w = {70, 30}, rows = shop}}}
end

-- ---------------------------------------------------------------------------------------------------------------
-- monsters: the Chaos monsters that spawn somewhere (late game areas, invasions, bosses, goblins)
-- ---------------------------------------------------------------------------------------------------------------
local MONSTER_DIRS = {"", "ascended/", "goblins/", "guildboss/", "omens/", "raid/", "world_bosses/", "wildwood/"}

-- item names for the loot tables: data/items/base_item_names.csv, the art tables (server_id, name), then the comment
-- after a loot line of any monster file (<item id="2148" .../><!-- gold coin -->), the first in file order
function W.itemNames(texts)
	local names = {}
	local function csv(path, idCol, nameCol)
		local text = readFile(path) or ""
		local head
		for line in text:gmatch("[^\n]+") do
			local cols = {}
			for c in (line .. ","):gmatch("([^,]*),") do
				cols[#cols + 1] = c
			end
			if not head then
				head = {}
				for i, c in ipairs(cols) do
					head[c] = i
				end
				if not head[idCol] or not head[nameCol] then
					return
				end
			else
				local id, name = tonumber(cols[head[idCol]]), cols[head[nameCol]]
				if id and name and name ~= "" and not names[id] then
					names[id] = name
				end
			end
		end
	end
	csv("data/items/base_item_names.csv", "id", "name")
	for _, f in ipairs({"art_items", "theme_items", "fist_items", "fist_claws", "weapons800", "donor_items", "owner_decor", "dark_tiles"}) do
		csv("data/items/" .. f .. ".csv", "server_id", "name")
	end
	for _, data in ipairs(texts) do
		for id, name in data:gmatch('<item id="(%d+)"[^>]-/?>[ \t]*<!%-%-%s*(.-)%s*%-%->') do
			id = tonumber(id)
			if id and not names[id] and name ~= "" then
				names[id] = name
			end
		end
	end
	return names
end

-- the loot list of a monster file as MonsterType:getLoot() gives it to the Bestiary: {itemId, chance, maxCount}
function W.lootOf(data)
	local out = {}
	local loot = data:match("<loot>(.-)</loot>")
	for tag in (loot or ""):gmatch("<item%s([^>]*)>") do
		local a = attrs(tag)
		local id = tonumber(a.id)
		if id then
			out[#out + 1] = {itemId = id, chance = tonumber(a.chance) or 0, maxCount = tonumber(a.countmax) or 1}
		end
	end
	return out
end

function W.monsterFiles()
	local out = {}
	local listing = io.popen("cd data/monster/monsters/chaos && find . -name '*.xml' | LC_ALL=C sort")
	local text = listing:read("*a")
	listing:close()
	local texts = {}
	for path in text:gmatch("[^\n]+") do
		local data = readFile("data/monster/monsters/chaos/" .. path:gsub("^%./", ""))
		local head = data and data:match("<monster%s([^>]*)>")
		if head then
			local a = attrs(head)
			local hp = data:match("<health[^>]-max=\"(%d+)\"")
			local lmin, lmax = data:match("<level[^>]-min=\"(%d+)\"[^>]-max=\"(%d+)\"")
			out[a.name:lower()] = {name = a.name, exp = tonumber(a.experience) or 0, hp = tonumber(hp) or 0,
				level = lmin and (lmin == lmax and lmin or (lmin .. "-" .. lmax)) or nil, dir = path:match("^%./(.-)/") or "",
				loot = W.lootOf(data)}
			texts[#texts + 1] = data
		end
	end
	return out, W.itemNames(texts)
end

-- a loot chance in percent: 1 decimal from 1%, 3 below (the Item Finder's K.percent)
local function lootPct(p)
	p = tonumber(p) or 0
	local function trim(v, d)
		local t = string.format("%." .. d .. "f", v)
		if t:find("%.") then
			t = t:gsub("0+$", ""):gsub("%.$", "")
		end
		return t
	end
	if p <= 0 then
		return "0%"
	elseif p >= 100 then
		return "100%"
	elseif p >= 1 then
		return trim(p, 1) .. "%"
	elseif p >= 0.001 then
		return trim(p, 3) .. "%"
	end
	return "<0.001%"
end

-- the loot table of a monster entry: the Bestiary's full list (bestiary_core.lua C.loot at stage 3, its lootMax rows,
-- the most likely first) and the uniques that name the monster (chaos_unique_items.lua monsters)
function W.lootSections(D, key, m, names)
	if not ChaosBestiaryCore or not ChaosBestiaryCore.loot then
		dofile("data/scripts/chaos/bestiary_core.lua")
	end
	D.bestiaryCfg = D.bestiaryCfg or cfg("bestiary_config")
	local list = ChaosBestiaryCore.loot(m.loot, function(id)
		return names[id] or ("item " .. id), id
	end, 3, D.bestiaryCfg)
	local secs = {}
	local rows = {}
	for _, l in ipairs(list) do
		rows[#rows + 1] = {l.name, lootPct(l.chance), (tonumber(l.max) or 1) > 1 and ("1-" .. l.max) or "1"}
	end
	if #rows > 0 then
		secs[#secs + 1] = {h = "Loot", cols = {"Item", "Chance per kill", "Count"}, w = {56, 26, 18}, rows = rows}
	end
	local uniques = {}
	for _, u in ipairs(D.uniques or {}) do
		for _, mk in ipairs(u.monsters or {}) do
			if mk == key then
				uniques[#uniques + 1] = {u.name, u.bossOnly and "Boss-only unique" or ("Unique, " .. tostring(u.minTier) ..
					" or stronger"), links = {"unique:" .. u.id}}
			end
		end
	end
	table.sort(uniques, function(a, b) return a[1] < b[1] end)
	if #uniques > 0 then
		local urows = {}
		for _, r in ipairs(uniques) do
			urows[#urows + 1] = {r[1], r[2]}
		end
		secs[#secs + 1] = {h = "Uniques it can drop", cols = {"Unique", "From"}, w = {50, 50}, rows = urows}
	end
	return secs
end

function W.monsterEntries(D)
	local files, names = W.monsterFiles()
	local where = {}
	local function add(name, text)
		local k = name:lower()
		where[k] = where[k] or {}
		for _, t in ipairs(where[k]) do
			if t == text then
				return
			end
		end
		table.insert(where[k], text)
	end
	-- late game areas
	local csv = readFile("tools/late_game_spawns.csv") or ""
	local first = true
	for line in csv:gmatch("[^\n]+") do
		if first then
			first = false
		else
			local cols = {}
			for c in (line .. ","):gmatch("([^,]*),") do
				cols[#cols + 1] = c
			end
			if cols[1] and cols[9] then
				add(cols[9], "Late game area: " .. cols[1])
			end
		end
	end
	for _, b in ipairs(D.C0.worldBoss.bosses) do
		add(b.name, "World boss")
	end
	for _, b in ipairs(D.raid.bosses) do
		add(b.name, "Raid boss: " .. D.raid.name)
	end
	for _, k in ipairs(D.uberCfg.kinds) do
		add(k.boss, "Ascended boss")
	end
	for _, k in ipairs(D.rift.omen.kinds) do
		add(k.boss, "Omen guardian")
	end
	add(D.guildboss.boss.boss, "Weekly guild boss")
	for _, k in ipairs(D.goblin.kinds or {}) do
		add(k.name, "Treasure goblin")
	end
	for key, f in sortedPairs(D.invasion.factions or {}) do
		for _, m in ipairs(f.monsters or {}) do
			add(m.name, "Invasion: " .. f.name)
		end
		for _, b in ipairs(f.bosses or {}) do
			add(b.name, "Invasion boss: " .. f.name)
		end
	end
	local out = {}
	for k, m in sortedPairs(files) do
		if where[k] and m.dir ~= "pets" then
			local rows = {{"Health", money(m.hp)}, {"Experience", money(m.exp)}}
			if m.level then
				rows[#rows + 1] = {"Level", m.level}
			end
			-- pack combat (pace_config.lua): a late game hunt's monster spawns on the map, so it is paced
			local pc = D.pace
			local lateGame = false
			for _, t in ipairs(where[k]) do
				lateGame = lateGame or t:find("^Late game area") ~= nil
			end
			if lateGame and pc and pc.enabled ~= false and m.level then
				local lo, hi = tostring(m.level):match("^(%d+)%-?(%d*)$")
				local L = math.floor(((tonumber(lo) or 0) + (tonumber(hi) or tonumber(lo) or 0)) / 2)
				local function lin(points, x)
					if x <= points[1][1] then
						return points[1][2]
					end
					for i = 2, #points do
						local a, b = points[i - 1], points[i]
						if x <= b[1] then
							return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
						end
					end
					return points[#points][2]
				end
				rows[#rows + 1] = {"In hunts (pack combat)", string.format(
					"health x%.3f, experience and loot per kill x%.3f / x%.3f, damage x%.2f at level %d (Basics: Pack combat)",
					lin(pc.scaled.health, L), math.min(1, lin(pc.scaled.xp, L) * (pc.scale and pc.scale.xp or 1)),
					math.min(1, lin(pc.scaled.loot, L) * (pc.scale and pc.scale.loot or 1)), lin(pc.damage, L), L)}
			end
			out[#out + 1] = {id = "monster:" .. k:gsub("[^%w]+", "-"), name = m.name, color = COLORS.monster,
				sub = table.concat(where[k], "; ") .. ".",
				sections = {{h = "Monster", cols = {"", ""}, w = {35, 65}, rows = rows},
					{h = "Where", p = where[k]}}}
			for _, sec in ipairs(W.lootSections(D, k, m, names)) do
				table.insert(out[#out].sections, sec)
			end
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- the store: what each offer is (cosmetic, service, convenience, consumable, class unlock, ...)
-- ---------------------------------------------------------------------------------------------------------------
local TYPE_NAME = {cosmetic = "Cosmetic", service = "Service", convenience = "Convenience", boost = "Boost",
	consumable = "Consumable item", crafting = "Crafting item", class = "Class unlock", premium = "Premium time",
	pet = "Pet (small abilities)", bundle = "Bundle", seasonpass = "Season pass", pact = "Chaos Pact",
	storage = "Account storage"}
-- categories whose offers are one type whatever their kind
local CATEGORY_TYPE = {["Season Pass"] = "seasonpass", ["Chaos Pact"] = "pact", ["Storage & Slots"] = "storage",
	["Depot Tabs"] = "storage"}

function W.offerType(o)
	local k = o.kind
	if k == "wings" or k == "aura" or k == "shader" or k == "outfit" or k == "addons" or k == "mount" or k == "frame" then
		return "cosmetic"
	elseif k == "premium" then
		return "premium"
	elseif k == "bundle" then
		return "bundle"
	elseif k == "unlock" then
		local u = tostring(o.unlock)
		if u:find("^unlock") then
			return "class"
		elseif u:find("^pet") then
			return "pet"
		elseif u:find("^portal_") or u:find("^transmog_") or u:find("^cosmetic_") or u:find("^hideout") then
			return "cosmetic"
		end
		return "convenience"
	elseif k == "service" then
		local s = o.service
		if s == "stamina" or s == "blessings" or s == "worldBuff" then
			return "boost"
		elseif s == "pouch" or s == "templeScroll" or s == "storeFood" then
			return "convenience"
		end
		return "service"
	elseif k == "item" then
		if o.id == 28095 or o.id == 27990 then
			return "boost"
		elseif o.id == 2365 then
			return "convenience"
		end
		return "consumable"
	end
	return "service"
end

-- the sprite of a store offer's row (website/README.md "Sprite images"): an item by server id, an outfit with both
-- addons, a mount look, a bundle's or name plate's icon item; false when the offer has no picture of its own
function W.offerSprite(o)
	if o.kind == "item" and tonumber(o.id) then
		return {item = o.id}
	elseif (o.kind == "outfit" or o.kind == "addons") and tonumber(o.looktype) then
		return {outfit = o.looktype, addons = 3}
	elseif o.kind == "mount" and tonumber(o.clientid) then
		return {outfit = o.clientid}
	elseif tonumber(o.icon) then
		return {item = o.icon}
	end
	return false
end

-- a category whose offers all have a sale window (availableUntil, the Founder Pack, O322) is left out: the wiki lists what the
-- store always sells, and a limited pack would stay on the page after its sale
function W.timeLimited(cat)
	for _, o in ipairs(cat.offers or {}) do
		if not o.availableUntil then
			return false
		end
	end
	return #(cat.offers or {}) > 0
end

function W.storeEntries(D)
	local out = {}
	local summary, sumLinks = {}, {}
	local typeCount = {}
	for ci, cat in ipairs(D.shop.categories) do
		if W.timeLimited(cat) then
			cat = {name = cat.name, offers = {}}
		end
		local rows, sprites, anySprite = {}, {}, false
		local lo, hi
		local types = {}
		local typeSeen = {}
		for _, o in ipairs(cat.offers or {}) do
			local t = W.offerType(o)
			if cat.name == "Crafting" and o.kind == "item" and o.id ~= 2365 then
				t = "crafting"
			end
			t = CATEGORY_TYPE[cat.name] or t
			typeCount[t] = (typeCount[t] or 0) + 1
			if not typeSeen[t] then
				typeSeen[t] = true
				types[#types + 1] = TYPE_NAME[t]
			end
			local cost = o.cost
			if cost then
				lo = lo and math.min(lo, cost) or cost
				hi = hi and math.max(hi, cost) or cost
			end
			if o.name then
				local note = {}
				if o.weeklyLimit then
					note[#note + 1] = o.weeklyLimit .. " a week"
				end
				if o.oncePerAccount then
					note[#note + 1] = "once per account"
				end
				if o.maxLevel then
					note[#note + 1] = "up to level " .. o.maxLevel
				end
				if o.seasonBlocked then
					note[#note + 1] = "not for season characters"
				end
				sprites[#rows + 1] = W.offerSprite(o)
				anySprite = anySprite or sprites[#rows + 1] ~= false
				rows[#rows + 1] = {o.name, cost and num(cost) or (o.pct and ("-" .. num(o.pct) .. "% of the parts") or ""),
					TYPE_NAME[t], ((o.description or "") .. (#note > 0 and (" (" .. table.concat(note, ", ") .. ")") or ""))}
			end
		end
		local n = #(cat.offers or {})
		if n > 0 then
			local id = "store:" .. ci
			local priceText = lo and (lo == hi and num(lo) or (num(lo) .. "-" .. num(hi))) or "-"
			summary[#summary + 1] = {cat.name, num(n), priceText, table.concat(types, ", ")}
			sumLinks[#sumLinks + 1] = id
			local sections = {{h = "Category", p = {string.format("%d offers, %s Chaos Coins. %s.", n, priceText,
				table.concat(types, ", "))}}}
			if #rows > 0 then
				sections[#sections + 1] = {h = "Offers", cols = {"Offer", "Coins", "Type", "What it is"}, w = {24, 10, 16, 50},
					rows = rows, sprites = anySprite and sprites or nil}
			else
				sections[#sections + 1] = {h = "Offers", p = {"Each one is shown with a preview in the store window (Store > " .. cat.name .. ")."}}
			end
			out[#out + 1] = {id = id, name = cat.name, color = COLORS.store, group = "category",
				sub = string.format("%d offers, %s coins. %s.", n, priceText, table.concat(types, ", ")), sections = sections}
		end
	end
	local tRows = {}
	for _, t in ipairs({"cosmetic", "pet", "convenience", "service", "storage", "pact", "seasonpass", "boost", "consumable",
			"crafting", "class", "premium", "bundle"}) do
		if typeCount[t] then
			tRows[#tRows + 1] = {TYPE_NAME[t], num(typeCount[t])}
		end
	end
	table.insert(out, 1, {id = "store:about", name = "The store", color = COLORS.store, group = "about",
		sub = "Chaos Coins, the categories and what each offer is.",
		sections = {
			{h = "Chaos Coins", p = {"The store is in the game (the Store button). Prices are in Chaos Coins, which belong to the account. Coins are a thank-you for a voluntary donation on the website, and can also be traded on the market for gold."}},
			{h = "Categories", cols = {"Category", "Offers", "Coins", "Types"}, w = {22, 12, 16, 50}, rows = summary, links = sumLinks},
			{h = "Offers by type", cols = {"Type", "Offers"}, w = {60, 40}, rows = tRows}}})
	return out, typeCount
end

-- ---------------------------------------------------------------------------------------------------------------
-- the Rift Atlas (in the rift tab)
-- ---------------------------------------------------------------------------------------------------------------
function W.atlasEntry(D)
	local cfgA, A = D.atlas, D.A
	local items = {}
	for _, n in ipairs(cfgA.nodes or {}) do
		if n.kind == "keystone" or n.kind == "notable" then
			items[#items + 1] = {row = {n.name, n.kind == "keystone" and "Keystone" or "Notable", n.branch or "core",
				table.concat(A.nodeLines(cfgA, n), " ")}, icon = W.atlasNodeIcon(n)}
		end
	end
	table.sort(items, function(a, b)
		if a.row[2] ~= b.row[2] then
			return a.row[2] < b.row[2]
		end
		if a.row[1] ~= b.row[1] then
			return a.row[1] < b.row[1]
		end
		return a.icon < b.icon
	end)
	local rows, icons = {}, {}
	for i, it in ipairs(items) do
		rows[i], icons[i] = it.row, it.icon
	end
	local maxPts = A.maxPoints(cfgA, D.rift)
	return {id = "rift:atlas", name = "Rift Atlas", color = COLORS.basics, group = "key",
		sub = string.format("First completions give points; spend them on a map of rift bonuses (%d points in all).", maxPts),
		sections = {
			{h = "Points", p = {string.format("Points come only from first completions: each theme and tier sealed (%d), each tier without a death (%d), each tier within its Swift time (%d) and each Omen guardian (%d). %d points in all.",
				cfgA.points.cell, cfgA.points.flawless, cfgA.points.swift, cfgA.points.omen, maxPts),
				string.format("Nodes cost %d (small), %d (notable) and %d (keystone) points; you hold at most %d keystone. Refunding a node costs %s gold or %d %s.",
					cfgA.costs.small, cfgA.costs.notable, cfgA.costs.keystone, cfgA.keystoneMax, money(cfgA.respec.gold),
					cfgA.respec.orbCount, cfgA.respec.orbName)}},
			{h = "Notables and keystones", cols = {"Node", "Kind", "Branch", "Effect"}, w = {22, 12, 20, 46}, rows = rows,
				icons = icons}}}
end

-- the rift themes and their guardians (an entry of the rift tab; the looks of rift_config.lua)
function W.riftThemesEntry(D)
	local R = D.rift
	local tRows, tIcons, gRows, gIcons = {}, {}, {}, {}
	for _, th in ipairs(R.themes or {}) do
		local lay = R.layout and R.layout.themes and R.layout.themes[th.name] or {}
		local kinds = {}
		for _, k in ipairs(lay.kinds or {}) do
			kinds[#kinds + 1] = k[1]
		end
		local names = R.looks and R.looks.names and R.looks.names[th.name] or {}
		local slug = W.riftThemeSlug(th.name)
		tRows[#tRows + 1] = {th.name, sentence(kinds), names.guardian or "-"}
		tIcons[#tIcons + 1] = W.ICON .. "rt-" .. slug .. ".png"
		if names.guardian then
			gRows[#gRows + 1] = {names.guardian, th.name, string.format("%s, %s, %s", names.minion or "-", names.brute or "-",
				names.elite or "-")}
			gIcons[#gIcons + 1] = W.ICON .. "rg-" .. slug .. ".png"
		end
	end
	return {id = "rift:themes", name = "Rift Themes and Guardians", color = COLORS.basics, group = "key",
		sub = string.format("The %d rift themes, their maps and the guardian at the end of each.", #tRows),
		sections = {
			{h = "Themes", p = {"A key opens a rift of a random theme; the theme decides the map, the monsters' looks and the guardian."},
				cols = {"Theme", "Map", "Guardian"}, w = {30, 35, 35}, rows = tRows, icons = tIcons},
			{h = "Guardians", p = {"The guardian appears when enough of the rift's monsters are dead. Its pack wears the theme's looks."},
				cols = {"Guardian", "Theme", "Its pack"}, w = {28, 24, 48}, rows = gRows, icons = gIcons}}}
end

-- ---------------------------------------------------------------------------------------------------------------
-- facts: the numbers of the written guides ({{key}} in the guide files)
-- ---------------------------------------------------------------------------------------------------------------
function W.facts(D, vocs, spells, T, typeCount)
	local f = {}
	local C0 = D.C0
	f["class.ascensionLevel"] = C0.classes.ascension.minLevel
	f["class.lines"] = #LINE_ORDER
	local locked, free, cost, level = {}, {}, nil, nil
	for key, c in sortedPairs(D.unlocks.classes) do
		if c.locked then
			locked[#locked + 1] = c.name
			cost = c.unlock.store and c.unlock.store.cost or cost
			level = c.unlock.level and c.unlock.level.min or level
		end
	end
	f["class.lockedCount"] = #locked
	f["class.lockedNames"] = sentence(locked)
	f["class.lockedNamesPt"] = sentence(locked, " e ")
	local open = {}
	local lockedSet = {}
	for _, n in ipairs(locked) do
		lockedSet[n] = true
	end
	for _, base in ipairs(LINE_ORDER) do
		if not lockedSet[vocs[base].name] then
			open[#open + 1] = vocs[base].name
		end
	end
	f["class.openNames"] = sentence(open)
	f["class.openNamesPt"] = sentence(open, " e ")
	f["class.unlockCost"] = cost or 0
	f["class.unlockLevel"] = level or 0
	f["class.openCount"] = #LINE_ORDER - #locked
	f["class.count"] = #LINE_ORDER * 3
	f["spell.count"] = #spells
	f["ascension.proofPoints"] = D.ascq.proof.needed
	f["ascension.trialTime"] = seconds(D.ascq.trial.timeLimitSeconds)
	f["ascension.retry"] = seconds(D.ascq.trial.cooldownSeconds)
	f["tree.nodes"] = T.count
	f["tree.keystones"] = #T.keystones
	f["tree.notables"] = #T.notables
	f["tree.levelsPerPoint"] = C0.passive.levelsPerPoint
	f["tree.startLevel"] = C0.passive.startLevel
	f["tree.points300"] = floor((300 - C0.passive.startLevel) / C0.passive.levelsPerPoint)
	f["tree.points1000"] = floor((1000 - C0.passive.startLevel) / C0.passive.levelsPerPoint)
	f["tree.resetPerLevel"] = money(C0.passive.resetCostPerLevel)
	f["tree.presets"] = C0.passive.maxPresets
	f["paragon.startLevel"] = C0.paragon.startLevel
	-- items
	local M, Cc = D.M, D.C
	f["item.rarities"] = ChaosRarity.COUNT -- seven, Unique included
	f["item.rarityFirst"] = ChaosRarity.list[1].name
	f["item.rarityLast"] = ChaosRarity.list[ChaosRarity.COUNT].name
	f["item.rarityList"] = table.concat(Cc.config.rarityNames, ", ") .. " and Unique"
	do -- "1 / 2 / 3 / 4 / 5 / 6": the modifiers a new item of Common .. Divine gets
		local counts = {}
		for rank = 1, #Cc.config.rarityNames do
			counts[rank] = tostring(M.modCount(ChaosRarity.idOfRank(rank)))
		end
		f["item.rarityMods"] = table.concat(counts, " / ")
	end
	f["item.maxItemLevel"] = M.config.itemLevel.max
	f["item.tiers"] = M.config.maxTier
	f["item.powersFrom"] = Cc.rarityName(M.config.powers.minRarity)
	f["item.qualityCap"] = M.config.quality.cap
	f["item.uniques"] = #D.uniques
	f["item.sets"] = #(D.itemSets and D.itemSets.sets or {})
	local mods, powers, orbs = 0, 0, 0
	for _, t in ipairs(D.codex.tabs) do
		if t.id == "modifiers" then
			mods = #t.entries
		elseif t.id == "powers" then
			powers = #t.entries
		end
	end
	for _, o in ipairs(Cc.config.orbs) do
		orbs = orbs + 1
	end
	f["item.modifiers"] = mods
	f["item.powers"] = powers
	f["orb.count"] = orbs
	f["gem.types"] = #D.G.config.types
	f["gem.tiers"] = #D.G.config.tiers
	f["gem.maxSockets"] = D.G.MAX_SOCKETS
	f["support.count"] = #D.S.config.supports
	f["support.sockets"] = D.S.config.maxSockets
	-- rifts
	local R = D.rift
	f["rift.maxTier"] = R.maxTier
	f["rift.maxPlayers"] = R.maxPlayers
	f["rift.maxMods"] = R.key.maxMods
	f["rift.mods"] = #R.mods
	f["rift.omenMinTier"] = R.omen.minTier
	f["rift.omenKeyCost"] = R.omen.keyCost
	f["rift.bossAt"] = R.bossAt
	-- the level each rift tier needs (the leveling guide's brackets)
	for i, t in ipairs(R.tiers) do
		f["rift.level" .. i] = t.minLevel
	end
	f["bounty.maxActive"] = D.bounty.maxActive
	f["bounty.weeklyNeed"] = D.bounty.weeklyNeed
	for _, t in ipairs(cfg("trials_config").tiers) do
		f["trial." .. t.key .. "Level"] = t.minLevel
	end
	f["atlas.points"] = D.A.maxPoints(D.atlas, R)
	-- bosses and events
	local wb = C0.worldBoss
	f["worldboss.on"] = wb.enabled == true
	f["worldboss.minLevel"] = wb.minLevel
	f["worldboss.maxPlayers"] = wb.maxPlayers
	f["worldboss.times"] = table.concat(scheduleHours(wb), ", ")
	f["worldboss.count"] = #wb.bosses
	f["worldboss.interval"] = wb.intervalHours
	f["raid.on"] = D.raid.enabled == true
	f["raid.name"] = D.raid.name
	f["raid.minLevel"] = D.raid.minLevel
	f["raid.minPlayers"] = D.raid.minPlayers
	f["raid.maxPlayers"] = D.raid.maxPlayers
	f["raid.bosses"] = #D.raid.bosses
	f["raid.reset"] = WEEKDAY_EN[D.raid.resetDay] .. " " .. hhmm(D.raid.resetHour, 0)
	f["raid.resetPt"] = WEEKDAY_PT[D.raid.resetDay] .. " às " .. hhmm(D.raid.resetHour, 0)
	f["ascended.on"] = D.uberCfg.enabled == true
	f["ascended.maxPlayers"] = D.uberCfg.maxPlayers
	f["descent.on"] = D.descent.enabled == true
	f["descent.name"] = D.descent.name
	f["descent.minLevel"] = D.descent.minLevel
	f["descent.maxPlayers"] = D.descent.maxPlayers
	f["dungeon.count"] = 0
	for _ in pairs(C0.dungeons.extra) do
		f["dungeon.count"] = f["dungeon.count"] + 1
	end
	-- and the generated ones (the Hollow Vault, the deep dungeons 6-9), registered by areagen.lua at startup
	for _, def in ipairs(D.areagen.areas) do
		if def.dungeon and def.enabled ~= false then
			f["dungeon.count"] = f["dungeon.count"] + 1
		end
	end
	f["dungeon.difficulties"] = C0.dungeons.maxDifficulty
	f["tower.seasonDays"] = C0.tower.seasonLengthDays
	f["invasion.on"] = D.invasion.enabled == true
	f["invasion.minLevel"] = D.invasion.minLevel
	f["siege.on"] = D.siege.enabled == true
	f["siege.when"] = WEEKDAY_EN[D.siege.weekday] .. " " .. hhmm(D.siege.hour, D.siege.minute)
	f["siege.whenPt"] = WEEKDAY_PT[D.siege.weekday] .. " às " .. hhmm(D.siege.hour, D.siege.minute)
	f["siege.minLevel"] = D.siege.minLevel
	f["guildboss.on"] = D.guildboss.enabled == true
	f["guildboss.minLevel"] = D.guildboss.minLevel
	f["pocket.on"] = D.pocket.enabled == true
	f["pocket.charges"] = D.pocket.charges.daily
	f["pocket.raidLevel"] = D.pocket.categories.raid.minLevel
	f["pocket.islandLevel"] = D.pocket.categories.island.minLevel
	f["events.count"] = #C0.events.list
	-- seasons
	local s1 = D.season.seasons[1]
	f["season.name"] = s1 and s1.name or ""
	local function ymd(n)
		n = tonumber(n) or 0
		return string.format("%04d-%02d-%02d", floor(n / 10000), floor(n / 100) % 100, n % 100)
	end
	f["season.start"] = s1 and ymd(s1.start) or ""
	f["season.finish"] = s1 and ymd(s1.finish) or ""
	f["season.modifier"] = s1 and s1.modifier and s1.modifier.description or ""
	f["season.modifierName"] = s1 and s1.modifier and s1.modifier.name or ""
	f["season.joinMaxLevel"] = D.season.join.maxLevel
	f["season.modes"] = D.season.modes and 1 or 0
	f["seasonpass.tiers"] = D.seasonpass.tiers and #D.seasonpass.tiers or (D.seasonpass.maxTier or 0)
	f["tower.pointsPerFloor"] = money(C0.tower.pointsPerFloor)
	f["boards.count"] = #D.boards.boards
	f["boards.reset"] = hhmm(D.boards.resetHour, 0)
	-- economy
	f["market.minLevel"] = D.market.minLevel
	f["market.tax"] = D.market.tax.gold
	f["market.listingFee"] = D.market.listingFee.pct
	f["market.durations"] = list(D.market.durations, "/")
	f["orbx.minLevel"] = D.orbx.minLevel
	f["orbx.goldFee"] = num(D.orbx.fees.goldBps / 100)
	f["orbx.durations"] = list(D.orbx.durations, "/")
	f["daily.days"] = #C0.daily.rewards
	-- item prices (data/lib/chaos_item_prices_data.lua, server/README.md "Item prices")
	local IP = dofile("data/lib/chaos_item_prices_data.lua")
	f["prices.uncommon"] = num(IP.rarityMult[2])
	f["prices.magic"] = num(IP.rarityMult[3])
	f["prices.rare"] = num(IP.rarityMult[4])
	f["prices.legendary"] = num(IP.rarityMult[5])
	f["prices.top"] = num(IP.rarityMult[#IP.rarityMult])
	f["prices.perLevel"] = num(100 / IP.ilvlDiv)
	f["prices.maxLevel"] = num(1 + 150 / IP.ilvlDiv)
	-- social
	f["mentor.on"] = D.mentor.enabled == true
	f["mentor.exp"] = num(D.mentor.bonus.exp * 100)
	f["mentor.damage"] = num(D.mentor.bonus.damageTaken * 100)
	f["mentor.graduation"] = D.mentor.graduationLevel
	f["mentor.minLevel"] = D.mentor.mentor.minCharacterLevel
	f["mentor.apprenticeMax"] = D.mentor.apprentice.maxLevel
	f["guild.maxLevel"] = D.guild.maxLevel
	f["guild.hallLevel"] = D.guild.hall.level
	f["guildwar.on"] = D.guildwar.enabled == true
	f["guildwar.minVictim"] = D.guildwar.kills.minVictimLevel
	f["factions.on"] = D.factions.enabled == true
	f["factions.count"] = #D.factions.factions
	local fnames = {}
	for _, x in ipairs(D.factions.factions) do
		fnames[#fnames + 1] = x.name
	end
	f["factions.names"] = sentence(fnames)
	-- pvp
	f["pvpzone.on"] = D.pvpzone.enabled == true
	f["pvpzone.name"] = D.pvpzone.name
	f["pvpzone.minLevel"] = D.pvpzone.minLevel
	f["bg.on"] = D.bg.enabled == true
	f["bg.minLevel"] = D.bg.minLevel
	f["arena.on"] = D.arena.enabled ~= false
	f["arena.minLevel"] = D.arena.minLevel
	f["multiclient.perIp"] = C0.multiClient.maxPerIp
	-- reports
	f["reports.minLevel"] = D.antibot.reports.minLevel or 8
	f["reports.perDay"] = D.antibot.reports.perDay
	-- store
	f["store.cosmetic"] = typeCount.cosmetic or 0
	local offers = 0
	for _, n in pairs(typeCount) do
		offers = offers + n
	end
	f["store.offers"] = offers
	f["store.service"] = (typeCount.service or 0) + (typeCount.convenience or 0) + (typeCount.storage or 0)
	f["store.unlockCost"] = cost or 0
	local alwaysOn = 0
	for _, cat in ipairs(D.shop.categories) do
		if not W.timeLimited(cat) then
			alwaysOn = alwaysOn + 1
		end
	end
	f["store.categories"] = alwaysOn
	-- new players
	f["newplayer.tutorial"] = true
	-- the milestone gifts (newplayer_config.lua milestones) and Next Goals (goals_config.lua; the progression guide)
	local gifts = {}
	for _, m in ipairs(D.newplayer.milestones or {}) do
		gifts[#gifts + 1] = tostring(m.level)
	end
	f["newplayer.giftLevels"] = sentence(gifts)
	f["newplayer.giftLevelsPt"] = #gifts > 1 and (table.concat(gifts, ", ", 1, #gifts - 1) .. " e " .. gifts[#gifts]) or
		(gifts[1] or "")
	local goals = cfg("goals_config")
	f["goals.bands"] = #goals.bands
	f["goals.count"] = #goals.goals
	f["goals.lastBand"] = goals.bands[#goals.bands].from
	return f
end

-- ---------------------------------------------------------------------------------------------------------------
-- art: the icon of every tab and entry, the guides' hero images and the tabs' banners (website/README.md "Wiki art")
-- ---------------------------------------------------------------------------------------------------------------
-- An icon is a path under the chaos plugin's assets/ folder. website/tools/gen_wiki_art.py reads this file's output
-- and draws every wiki/i/<name>.png and wiki/hero/<name>.webp it names, only from our own committed art:
--   k-<theme>-<glyph>    the Chaos spell icon kit (client/tools/gen_spell_icons.py: COL themes, GLYPH drawings)
--   orb-<theme>-<glyph>  a glowing orb with a kit glyph            gem-<rrggbb>  a cut gem of that colour
--   sp-<clientId>        a Chaos spell's painted icon (client images/game/spells_painted/, gen_painted_icons.py)
--   tr-<iconKey>         a painted keystone or mastery (images/passivetree/painted_nodes.png, treedata/painted.lua)
--   sup-<key>            a support rune (images/game/supports/, sprites/gen_support_runes_art.py icons)
--   it-<set>-<kind>      an item of a themed set (client/tools/sprites/art_import/theme/items_<set>.png)
--   gm-<key>-<tier>      a socket gem's look (client/tools/sprites/art_import/gems.png, gen_gem_art.py)
--   top-<name>           a top menu button (client images/chaos/topbutton_<name>.png, gen_theme_art.py)
--   img/class-<key>.png  the website's class badges (website/tools/gen_site_art.py)
-- The art of an icon only illustrates the entry: a unique shows a themed piece of its slot, not its own sprite.
-- The real sprite is a separate field (`sprite`, W.entrySprite, and `sprites` of the store's offer rows): the website
-- draws it from our client pair only when that art is ours and published (website/README.md "Sprite images").
W.SOURCES[#W.SOURCES + 1] = "client/overlay/modules/game_chaosspells/spelldata.lua"
W.SOURCES[#W.SOURCES + 1] = "client/overlay/modules/game_passivetree/treedata/painted.lua"
W.SOURCES[#W.SOURCES + 1] = "client/tools/gen_spell_icons.py"

local ICON = "wiki/i/"
local function kit(theme, glyph)
	return ICON .. "k-" .. theme .. "-" .. glyph .. ".png"
end
local function orb(theme, glyph)
	return ICON .. "orb-" .. theme .. "-" .. glyph .. ".png"
end
local function top(name)
	return ICON .. "top-" .. name .. ".png"
end
local function item(set, kind)
	return ICON .. "it-" .. set .. "-" .. kind .. ".png"
end
local function gem(hex)
	return ICON .. "gem-" .. tostring(hex):gsub("^#", ""):lower() .. ".png"
end
-- a socket gem's own look (its Perfect tier unless named)
local function gemLook(key, tier)
	return ICON .. "gm-" .. key .. "-" .. tostring(tier or 5) .. ".png"
end
local function classBadge(key)
	return "img/class-" .. key .. ".png"
end
W.icon = {kit = kit, orb = orb, top = top, item = item, gem = gem, gemLook = gemLook, class = classBadge}

-- element words of the data -> kit theme
local ELEMENT_THEME = {fire = "fire", ice = "frost", energy = "light", earth = "poison", death = "shadow", holy = "holy",
	physical = "steel", arcane = "arcane", blood = "blood", lightning = "light", poison = "poison"}

local function themeOfText(text, fallback)
	local t = tostring(text):lower()
	for _, w in ipairs({"fire", "ice", "energy", "earth", "death", "holy", "physical", "arcane", "lightning", "poison"}) do
		if t:find(w, 1, true) then
			return ELEMENT_THEME[w]
		end
	end
	return fallback
end

-- the reference tabs
local TAB_ICON = {classes = top("skills"), spells = top("spells"), tree = top("passivetree"), basics = top("help"),
	modifiers = kit("arcane", "nodes"), powers = kit("fire", "flame"), uniques = item("sunsworn", "sword"),
	sets = item("oathsteel", "armor"), orbs = orb("arcane", "swirl"), gems = gemLook("ruby"),
	supports = ICON .. "sup-emberbrand.png", rift = ICON .. "rx-portal.png", dungeons = top("dungeons"),
	bosses = kit("blood", "skull"), events = top("events"), monsters = kit("shadow", "ghost"),
	materials = kit("nature", "leaf"), lore = kit("ember", "eye"), store = top("vip")}
-- the banner's tint
local TAB_TONE = {classes = "#f6cf72", spells = "#9fdc7f", tree = "#e8b84a", basics = "#d6c9ae", modifiers = "#7d96ff",
	powers = "#ff9a3c", uniques = "#ff9c3a", sets = "#58c878", orbs = "#e8b84a", gems = "#ff5a4a", supports = "#ff8228",
	rift = "#a064e6", dungeons = "#c0a0ff", bosses = "#ff7050", events = "#ffb050", monsters = "#d6c9ae",
	materials = "#7ec46a", lore = "#c9a27a", store = "#ff70c0"}

local BASICS = {["basics:items"] = top("inventory"), ["basics:rarity"] = kit("light", "crystal"),
	["basics:tiers"] = kit("steel", "arrowup"), ["basics:itemlevel"] = kit("ember", "arrowup"),
	["basics:sides"] = kit("steel", "twin"), ["basics:quality"] = kit("steel", "hammer"),
	["basics:basebonus"] = kit("steel", "shield"), ["basics:pace"] = kit("blood", "burst")}
local MOD_GLYPH = {chaos = "rift", skill = "sword", absorb = "shield", element = "burst", special = "eye"}
local MOD_THEME = {chaos = "arcane", skill = "steel", absorb = "water", element = "fire", special = "holy"}
local POWERS = {arclightning = {"light", "bolt"}, bloodrush = {"blood", "drop"}, crimsonburst = {"blood", "burst"},
	critecho = {"steel", "twin"}, deathblast = {"shadow", "skull"}, echoshot = {"steel", "arrows"},
	emberstep = {"ember", "dash"}, frostward = {"frost", "shield"}, hunterrush = {"poison", "dash"},
	lastbreath = {"holy", "cross"}, shattersplash = {"frost", "crystal"}, smolderaura = {"fire", "flame"}}
local ORBS = {transmutation = {"light", "arrowup"}, alchemy = {"holy", "crystal"}, exalted = {"arcane", "nodes"},
	annulment = {"shadow", "smoke"}, scouring = {"water", "wave"}, chaos = {"arcane", "swirl"}, divine = {"holy", "cross"},
	sockets = {"steel", "ring"}, tempering = {"ember", "hammer"}, binding = {"steel", "shield"},
	excision = {"blood", "daggers"}, reforging = {"fire", "hammer"}, ruin = {"blood", "burst"},
	ember = {"fire", "flame"}, crown = {"holy", "banner"}, void = {"shadow", "rift"},
	whetstone = {"steel", "sword"}, unveiling = {"arcane", "eye"}}
-- the other currency: by a word of the name
local CURRENCY = {{"crown", orb("holy", "banner")}, {"dawn", orb("light", "burst")}, {"ember", orb("fire", "flame")},
	{"echoes", orb("arcane", "twin")}, {"void", orb("shadow", "rift")}, {"omen fragment", ICON .. "rx-omenfragment.png"},
	{"omen key", ICON .. "rx-omenkey.png"}, {"rift key", ICON .. "rk-5.png"}, {"shard", kit("bone", "crystal")}}
-- the rifts (website/tools/wiki_rift_art.py draws these: painted, one frame per side)
local function rift(kind, name)
	return ICON .. kind .. "-" .. name .. ".png"
end
local RIFT_THEME_SLUG = {["Abyssal Rift"] = "abyss", ["Obsidian Hall"] = "hall", ["Ashen Crypt"] = "crypt",
	["Forsaken Sanctum"] = "sanctum"}
function W.riftThemeSlug(name)
	return RIFT_THEME_SLUG[name] or "abyss"
end
W.ICON = ICON
-- the omen guardian with a portrait of our own rift looks; the others show their omen's emblem
local OMEN_PORTRAIT = {storm = rift("rg", "seer")}
-- a Rift Atlas node: a star map medallion of its branch, its own glyph (atlas_config.lua)
function W.atlasNodeIcon(n)
	local branch = n.branch and W.riftThemeSlug(n.branch) or "core"
	return rift("an", (n.kind or "notable") .. "-" .. branch .. "-" .. tostring(n.glyph or "reward"))
end
-- a rift modifier: rm-<side>-<key>; the side (prefix, suffix or boon) comes from the modifier's own data
function W.riftModIcon(m)
	local side = m.boon and "boon" or (m.side == "prefix" or m.side == "suffix") and m.side or "boon"
	return rift("rm", side .. "-" .. m.key)
end
local RIFT_KEY_ICON = rift("rk", "9")
local RIFT_ENTRY = {keys = RIFT_KEY_ICON, tiers = rift("rx", "portal"), omens = rift("rx", "omenkey"),
	atlas = rift("rx", "atlas"), themes = rift("rt", "abyss")}
local DUNGEON_WORDS = {{"bone", kit("bone", "skull")}, {"element", kit("arcane", "swirl")},
	{"chevalier", kit("steel", "sword")}, {"root", kit("nature", "thorns")}, {"vault", kit("arcane", "gate")},
	{"marrow", kit("bone", "skull")}, {"crucible", kit("steel", "hammer")}, {"sanctum", kit("holy", "burst")},
	{"throne", kit("fire", "burst")}}
local BOSS_ELEMENT_GLYPH = {fire = "meteor", ice = "crystal", earth = "thorns", death = "skull", physical = "greataxe"}
local RAID_BOSS = {ulthar = {"bone", "skull"}, morwen = {"fire", "ghost"}, colossus = {"bone", "golem"},
	hexmaw = {"shadow", "eye"}, sovereign = {"ember", "banner"}}
local MAT_GLYPH = {Delving = "mountain", Wortcunning = "leaf", Flaying = "paw", Angling = "wave"}
local MAT_THEME = {Common = "steel", Fine = "nature", Rare = "frost", Grim = "shadow", Infernal = "fire"}
local STORE = {["Starter"] = top("daily"), ["Bundles"] = top("stash"), ["Outfits"] = kit("arcane", "hood"),
	["Outfit Addons"] = kit("holy", "hood"), ["Mounts"] = kit("nature", "paw"), ["Wings"] = kit("holy", "arrowup"),
	["Auras"] = kit("light", "ring"), ["Head Accessories"] = kit("holy", "burst"), ["Capes"] = kit("arcane", "hood"),
	["Outfit Shaders"] = kit("arcane", "swirl"), ["Name Plates"] = kit("steel", "banner"),
	["Portal Styles"] = kit("arcane", "gate"), ["Spell Effects"] = kit("fire", "burst"), ["Kill Effects"] = kit("blood", "skull"),
	["Loot Labels"] = kit("light", "eye"), ["Chat Colours"] = top("console"), ["Footprints"] = kit("ember", "kick"),
	["Outlines"] = kit("light", "shield"), ["Hideout Decorations"] = kit("ember", "banner"),
	["Appearances"] = kit("arcane", "twin"), ["Pets"] = kit("nature", "fang"), ["Crafting"] = kit("steel", "hammer"),
	["Potions"] = kit("blood", "drop"), ["XP Boosts"] = kit("light", "arrowup"), ["Blessings"] = kit("holy", "shield"),
	["Runes"] = kit("arcane", "burst"), ["World Buffs"] = kit("holy", "burst"),
	["Services"] = top("options"), ["Convenience"] = top("autoloot"), ["Classes"] = kit("holy", "sword"),
	["Training"] = kit("steel", "sword"), ["Chaos Pact"] = top("battlepass"), ["Storage & Slots"] = top("stash"),
	["Depot Tabs"] = top("stash"), ["Season Pass"] = top("battlepass"), ["Premium Time"] = top("vip")}
-- the ten unique sets: a themed piece that matches the set's look (set strip, kind)
local SETS = {bloodsworn = {"oathsteel", "axe"}, cinderstorm = {"sunsworn", "rod"}, duskstalker = {"voidmourn", "helmet"},
	embers = {"sunsworn", "spellbook"}, gallows = {"cryptbone", "crossbow"}, hollowpack = {"wildroot", "amulet"},
	lichbound = {"cryptbone", "wand"}, mirrorweave = {"moonsilver", "armor"}, ashwarden = {"oathsteel", "shield"},
	thornwake = {"wildroot", "bow"}}
-- a unique's slot (the first words of its line) -> item kind; "weapon" and "Distance weapon" look at the name
local SLOT_KIND = {["Body armour"] = "armor", ["Helmet"] = "helmet", ["Legs"] = "legs", ["Boots"] = "boots",
	["Ring"] = "ring", ["Amulet"] = "amulet", ["Shield"] = "shield", ["Sword"] = "sword", ["Axe"] = "axe",
	["Club"] = "club", ["Wand / rod"] = "wand", ["Spellbook"] = "spellbook", ["Backpack"] = "backpack",
	["Quiver"] = "arrow"}
local WEAPON_WORDS = {{"crossbow", "crossbow"}, {"arbalest", "crossbow"}, {"bow", "bow"}, {"axe", "axe"},
	{"cleaver", "axe"}, {"hammer", "club"}, {"maul", "club"}, {"mace", "club"}, {"club", "club"}, {"staff", "rod"},
	{"rod", "rod"}, {"wand", "wand"}, {"sceptre", "rod"}, {"tome", "spellbook"}, {"grimoire", "spellbook"},
	{"shield", "shield"}, {"blade", "sword"}, {"sword", "sword"}, {"edge", "sword"}, {"fang", "sword"}}
-- the set strip of a unique: by a word of its name and text, else by its id
local UNIQUE_SET_WORDS = {{"blood", "sunsworn"}, {"crimson", "sunsworn"}, {"ember", "sunsworn"}, {"sun", "sunsworn"},
	{"dawn", "oathsteel"}, {"holy", "oathsteel"}, {"oath", "oathsteel"}, {"void", "voidmourn"}, {"shadow", "voidmourn"},
	{"night", "voidmourn"}, {"dusk", "voidmourn"}, {"bone", "cryptbone"}, {"grave", "cryptbone"}, {"lich", "cryptbone"},
	{"soul", "cryptbone"}, {"thorn", "wildroot"}, {"wild", "wildroot"}, {"root", "wildroot"}, {"beast", "wildroot"},
	{"moon", "moonsilver"}, {"silver", "moonsilver"}, {"frost", "moonsilver"}, {"star", "moonsilver"}}
local SET_STRIPS = {"cryptbone", "voidmourn", "wildroot", "moonsilver", "sunsworn", "oathsteel"}

function W.uniqueIcon(e)
	local slot = tostring(e.sub or ""):match("^([^,]+),") or ""
	local name = tostring(e.name or ""):lower()
	local kind = SLOT_KIND[slot]
	if not kind then
		for _, w in ipairs(WEAPON_WORDS) do
			if name:find(w[1], 1, true) then
				kind = w[2]
				break
			end
		end
		kind = kind or (slot:find("Distance") and "bow") or "sword"
	end
	local text = name .. " " .. tostring(e.sub or ""):lower()
	local set
	for _, w in ipairs(UNIQUE_SET_WORDS) do
		if text:find(w[1], 1, true) then
			set = w[2]
			break
		end
	end
	if not set then
		local n = tonumber(tostring(e.id):match("(%d+)$")) or 0
		set = SET_STRIPS[n % #SET_STRIPS + 1]
	end
	return item(set, kind)
end

function W.loadArtSources(D)
	local saved = ChaosSpellData
	dofile("../client/overlay/modules/game_chaosspells/spelldata.lua")
	-- a spell's painted icon when it has one, else its drawing of the icon kit (gen_spell_icons.py ICONS: name, theme,
	-- glyph; a spell newer than the painted set, e.g. Blade Flurry and Iaido Sweep)
	local kitOf = {}
	local py = readFile("../client/tools/gen_spell_icons.py") or ""
	for q, name, theme, glyph in py:gmatch("%((['\"])(.-)%1, '(%a+)', '(%a+)'%)") do
		kitOf[name] = {theme, glyph}
	end
	local clientOf = {}
	for _, s in ipairs(ChaosSpellData) do
		if readFile("../client/overlay/data/images/game/spells_painted/" .. s.clientId .. ".png") then
			clientOf[s.id] = s.clientId
		elseif kitOf[s.name] then
			clientOf[s.id] = kitOf[s.name]
		end
	end
	ChaosSpellData = saved
	local savedP = getPaintedTreeIcons
	dofile(TREE_DIR .. "treedata/painted.lua")
	local painted = getPaintedTreeIcons()
	getPaintedTreeIcons = savedP
	-- the rift data: modifiers by key, the omen of each guardian (and of each Ascended boss)
	local mods, omenOf, omenByName, omenByBoss = {}, {}, {}, {}
	if D then
		for _, m in ipairs(D.rift.mods or {}) do
			mods[m.key] = m
		end
		for _, k in ipairs(D.rift.omen.kinds or {}) do
			omenByName[k.name] = k.key
			omenByBoss[k.boss] = k.key
			omenOf[k.boss:lower()] = OMEN_PORTRAIT[k.key] or rift("ro", k.key)
			for _, u in ipairs(D.uberCfg.kinds or {}) do
				if u.omenBoss == k.boss then
					omenOf[tostring(u.boss):lower()] = rift("ro", k.key .. "-asc")
				end
			end
		end
	end
	return {clientOf = clientOf, painted = painted, mods = mods, omenOf = omenOf, omenByName = omenByName,
		omenByBoss = omenByBoss}
end

-- the icon of one entry of tab `tab`
function W.entryIcon(tab, e, src)
	local id = tostring(e.id)
	local rest = id:match("^[^:]+:(.*)$") or ""
	if tab == "classes" then
		return classBadge(rest)
	elseif tab == "spells" then
		local c = src.clientOf[tonumber(rest)]
		if type(c) == "table" then
			return kit(c[1], c[2])
		end
		return c and (ICON .. "sp-" .. c .. ".png") or kit("arcane", "burst")
	elseif tab == "tree" then
		if id == "tree:about" then
			return top("passivetree")
		elseif e.iconKey and src.painted[e.iconKey] then
			return ICON .. "tr-" .. e.iconKey .. ".png"
		elseif e.group == "mastery" then
			return kit("nature", "nodes")
		elseif e.group == "keystone" then
			return kit("holy", "nodes")
		end
		return kit("light", "nodes")
	elseif tab == "basics" then
		return BASICS[id] or top("help")
	elseif tab == "modifiers" then
		local g = e.group or "special"
		local theme = (g == "element" or g == "absorb") and themeOfText(e.name, MOD_THEME[g]) or MOD_THEME[g] or "holy"
		return kit(theme, MOD_GLYPH[g] or "eye")
	elseif tab == "powers" then
		local p = POWERS[rest] or {"fire", "flame"}
		return kit(p[1], p[2])
	elseif tab == "uniques" then
		return W.uniqueIcon(e)
	elseif tab == "sets" then
		local s = SETS[rest] or {"oathsteel", "armor"}
		return item(s[1], s[2])
	elseif tab == "orbs" then
		if ORBS[rest] then
			return orb(ORBS[rest][1], ORBS[rest][2])
		end
		local name = tostring(e.name):lower()
		for _, c in ipairs(CURRENCY) do
			if name:find(c[1], 1, true) then
				return c[2]
			end
		end
		return orb("arcane", "swirl")
	elseif tab == "gems" then
		return rest == "sockets" and kit("steel", "ring") or gemLook(rest)
	elseif tab == "supports" then
		return ICON .. "sup-" .. rest .. ".png"
	elseif tab == "rift" then
		if src.mods[rest] then
			return W.riftModIcon(src.mods[rest])
		end
		return RIFT_ENTRY[rest] or rift("rx", "portal")
	elseif tab == "dungeons" then
		if id == "dungeon:about" then
			return top("dungeons")
		elseif id == "dungeon:tower" then
			return top("infinitytower")
		elseif id == "dungeon:descent" then
			return kit("fire", "flame")
		end
		local name = tostring(e.name):lower()
		for _, w in ipairs(DUNGEON_WORDS) do
			if name:find(w[1], 1, true) then
				return w[2]
			end
		end
		return kit("shadow", "gate")
	elseif tab == "bosses" then
		if id == "boss:world" then
			return kit("blood", "skull")
		elseif id == "boss:raid" then
			return kit("ember", "gate")
		elseif id == "boss:ascended" then
			return rift("rx", "ascended")
		elseif id == "boss:guild" then
			return kit("holy", "banner")
		elseif id:find("^boss:world:") then
			local el = tostring(e.sub):match("World boss, (%a+)") or "physical"
			return kit(ELEMENT_THEME[el] or "blood", BOSS_ELEMENT_GLYPH[el] or "skull")
		end
		local r = RAID_BOSS[id:match("^boss:raid:(.*)$") or ""] or {"bone", "skull"}
		return kit(r[1], r[2])
	elseif tab == "events" then
		local EV = {["event:calendar"] = top("events"), ["event:invasion"] = kit("blood", "banner"),
			["event:siege"] = top("pvp"), ["event:goblin"] = kit("light", "paw")}
		return EV[id] or top("events")
	elseif tab == "monsters" then
		local sub = tostring(e.sub)
		if src.omenOf[tostring(e.name):lower()] then
			return src.omenOf[tostring(e.name):lower()]
		end
		if sub:find("boss") or sub:find("Omen guardian") then
			return kit("blood", "skull")
		elseif sub:find("Treasure goblin") then
			return kit("light", "paw")
		elseif sub:find("^Invasion") then
			return kit("ember", "banner")
		end
		return kit("shadow", "ghost")
	elseif tab == "materials" then
		if id == "mat:professions" then
			return kit("steel", "hammer")
		end
		local prof, tier = tostring(e.sub):match("^(%a+), tier %d+ %((%a+)%)")
		return kit(MAT_THEME[tier] or "steel", MAT_GLYPH[prof] or "dots")
	elseif tab == "store" then
		return id == "store:about" and top("vip") or STORE[e.name] or top("vip")
	elseif tab == "lore" then
		-- the lore of the world (lore_data.lua): by the kind of the entry (the Codex's filter group)
		local g = e.group or ""
		local LORE = {world = kit("ember", "flame"), rift = rift("rx", "portal"), omen = rift("rx", "ascended"),
			raid = kit("ember", "gate"), worldboss = kit("blood", "skull"), deep = kit("shadow", "gate"),
			chronicle = kit("ember", "flame")}
		return LORE[g] or kit("ember", "eye")
	end
	return nil
end

-- the guides: slug -> the hero image's motif. emblem = the big icon in the middle, icons = the ring around it,
-- tone = the tint of the scene. website/overlay/plugins/chaos/wiki_lib.php lists the same slugs (its test checks).
W.GUIDE_ORDER = {"start", "progression", "leveling", "classes", "tree", "items", "rifts", "dungeons", "bosses", "seasons",
	"economy", "social", "pvp", "store", "rules", "faq"}

function W.guideArt(src)
	local function painted(n)
		local keys = {}
		for k in pairs(src.painted) do
			if k:find("^ks") then
				keys[#keys + 1] = k
			end
		end
		table.sort(keys)
		local out = {}
		for i = 1, math.min(n, #keys) do
			out[i] = ICON .. "tr-" .. keys[floor((i - 1) * #keys / n) + 1] .. ".png"
		end
		return out
	end
	local classes = {}
	for _, k in ipairs({"warrior", "ranger", "mystic", "thief", "monk", "necromancer", "templar"}) do
		classes[#classes + 1] = classBadge(k)
	end
	local G = {
		start = {tone = "#e8b84a", emblem = kit("holy", "gate"),
			icons = {top("quests"), top("spells"), top("passivetree"), top("daily"), top("inventory"), top("market")}},
		progression = {tone = "#ffb050", emblem = top("quests"),
			icons = {top("dungeons"), kit("blood", "skull"), top("infinitytower"), orb("arcane", "swirl"), top("market"),
				kit("holy", "banner")}},
		leveling = {tone = "#f0a040", emblem = kit("steel", "arrowup"),
			icons = {top("quests"), top("daily"), top("passivetree"), top("dungeons"), RIFT_KEY_ICON,
				kit("blood", "skull")}},
		classes = {tone = "#f6cf72", emblem = kit("holy", "cross"), icons = classes},
		tree = {tone = "#e8b84a", emblem = top("passivetree"), icons = painted(6)},
		items = {tone = "#ff9c3a", emblem = orb("arcane", "swirl"),
			icons = {item("sunsworn", "sword"), item("moonsilver", "helmet"), item("voidmourn", "armor"),
				item("oathsteel", "shield"), item("cryptbone", "wand"), item("wildroot", "bow")}},
		rifts = {tone = "#a064e6", emblem = rift("rx", "portal"),
			icons = {RIFT_KEY_ICON, rift("rx", "clear"), rift("rg", "crypt"), rift("rx", "lives"), rift("rx", "chest"),
				rift("rx", "atlas"), rift("rx", "omenkey")}},
		dungeons = {tone = "#c0a0ff", emblem = top("dungeons"),
			icons = {kit("bone", "skull"), kit("arcane", "swirl"), top("infinitytower"), kit("fire", "flame"),
				kit("steel", "sword"), kit("nature", "thorns")}},
		bosses = {tone = "#ff7050", emblem = kit("blood", "skull"),
			icons = {kit("fire", "meteor"), kit("frost", "crystal"), kit("poison", "thorns"), kit("shadow", "skull"),
				kit("ember", "gate"), kit("holy", "banner")}},
		seasons = {tone = "#ffb050", emblem = top("ranking"),
			icons = {top("battlepass"), top("events"), kit("holy", "banner"), top("infinitytower"), top("daily")}},
		economy = {tone = "#d9a53a", emblem = top("market"),
			icons = {top("bank"), orb("holy", "crystal"), orb("arcane", "swirl"), kit("frost", "wave"),
				kit("nature", "leaf"), top("stash")}},
		social = {tone = "#7ec46a", emblem = top("community"),
			icons = {kit("holy", "banner"), top("pvp"), kit("water", "drop"), top("quests"), kit("arcane", "twin")}},
		pvp = {tone = "#e03a1e", emblem = top("pvp"),
			icons = {kit("steel", "sword"), kit("blood", "skull"), kit("ember", "gate"), kit("steel", "shield"),
				kit("holy", "banner")}},
		store = {tone = "#ff70c0", emblem = top("vip"),
			icons = {kit("arcane", "hood"), kit("nature", "paw"), kit("holy", "arrowup"), kit("light", "ring"),
				top("battlepass"), top("stash")}},
		rules = {tone = "#b8160f", emblem = kit("holy", "shield"),
			icons = {top("notifications"), kit("light", "eye"), top("help"), kit("steel", "hammer")}},
		faq = {tone = "#d6c9ae", emblem = top("help"),
			icons = {top("options"), top("quests"), top("spells"), top("market"), top("community")}}
	}
	local out = {}
	for _, slug in ipairs(W.GUIDE_ORDER) do
		local g = assert(G[slug], "no art for guide " .. slug)
		out[#out + 1] = {id = slug, icon = g.emblem, hero = "wiki/hero/guide-" .. slug .. ".webp", tone = g.tone,
			icons = g.icons}
	end
	return out
end

-- the icons the guides may name in a step ("=> @name | ...") and the icons of the callout boxes
function W.stepIcons()
	return {account = top("options"), download = top("console"), create = top("skills"), tutorial = kit("holy", "gate"),
		temple = top("quests"), level = kit("steel", "arrowup"), ascend = kit("holy", "cross"), drop = kit("blood", "skull"),
		bench = kit("steel", "hammer"), orb = orb("arcane", "swirl"), key = RIFT_KEY_ICON, rift = rift("rx", "portal"),
		guardian = kit("shadow", "skull"), chest = rift("rx", "chest"), atlas = rift("rx", "atlas"),
		omen = rift("rx", "omenkey"), riftclear = rift("rx", "clear"), riftguardian = rift("rg", "crypt"),
		lives = rift("rx", "lives"), season = top("ranking"), ladder = top("battlepass"), reward = top("daily"),
		salvage = kit("bone", "crystal"), sell = top("market"), gem = gem("#ff5a4a"),
		-- the callout boxes ("> [tip] ...")
		tip = kit("light", "eye"), warn = kit("blood", "burst"), note = top("help")}
end

-- icons in the first cell of some tables (`icons`, one per row): the key of each rift tier, the omens' emblems
function W.sectionIcons(e, src)
	for _, sec in ipairs(e.sections or {}) do
		local icons, any = {}, false
		for i, row in ipairs(sec.rows or {}) do
			local icon = ""
			if e.id == "rift:tiers" and sec.h == "Tiers" and tonumber(row[1]) then
				icon = rift("rk", tostring(math.floor(tonumber(row[1]))))
			elseif e.id == "rift:omens" and sec.h == "Guardians" and src.omenByName[row[1]] then
				icon = rift("ro", src.omenByName[row[1]])
			elseif e.id == "boss:ascended" and sec.h == "Bosses" then
				local k = src.omenByBoss[row[3]]
				icon = k and rift("ro", k .. "-asc") or rift("rx", "ascended")
			end
			icons[i] = icon
			any = any or icon ~= ""
		end
		if any and not sec.icons then
			sec.icons = icons
		end
	end
end

-- icons, banners and the art table; the entries' iconKey (a helper) and art (a client image) are dropped
-- the real sprite of an entry (website/README.md "Sprite images"): {item = <server id>} for a unique, the first piece
-- of a set; the website shows it only when the item's art is ours and published, else the themed icon above
function W.entrySprite(tab, e)
	if tab == "uniques" then
		local sid = tonumber(tostring(e.id):match("^unique:(%d+)$"))
		return sid and {item = sid} or nil
	elseif tab == "sets" then
		for _, s in ipairs(e.sections or {}) do
			for _, l in ipairs(s.links or {}) do
				local sid = tonumber(tostring(l):match("^unique:(%d+)$"))
				if sid then
					return {item = sid}
				end
			end
		end
	end
	return nil
end

function W.decorate(tabs, src)
	for _, t in ipairs(tabs) do
		t.icon = TAB_ICON[t.id]
		t.banner = "wiki/hero/tab-" .. t.id .. ".webp"
		t.tone = TAB_TONE[t.id] or "#d6c9ae"
		for _, e in ipairs(t.entries) do
			e.icon = W.entryIcon(t.id, e, src)
			e.sprite = W.entrySprite(t.id, e)
			e.iconKey = nil
			e.art = nil -- a client image path (the Codex's gem strip); the wiki shows its icon instead
			W.sectionIcons(e, src)
		end
	end
end

-- ---------------------------------------------------------------------------------------------------------------
-- the whole wiki data
-- ---------------------------------------------------------------------------------------------------------------
-- systems behind an off switch: their entries stay listed with soon = true (the website shows "coming soon"), so the
-- wiki never presents them as live. Entry id prefix -> the switch.
function W.switches(D)
	return {
		{"boss:world", D.C0.worldBoss.enabled == true}, {"boss:raid", D.raid.enabled == true},
		{"boss:pocket", D.pocket.enabled == true},
		{"boss:ascended", D.uberCfg.enabled == true}, {"boss:guild", D.guildboss.enabled == true},
		{"dungeon:descent", D.descent.enabled == true}, {"event:invasion", D.invasion.enabled == true},
		{"event:siege", D.siege.enabled == true},
		{"event:harvest", D.harvest.enabled == true and D.harvestArt.PAIR33 == true}
	}
end

function W.markSoon(D, lists)
	local sw = W.switches(D)
	for _, l in ipairs(lists) do
		for _, e in ipairs(l) do
			for _, x in ipairs(sw) do
				if not x[2] and e.id:sub(1, #x[1]) == x[1] then
					e.soon = true
				end
			end
		end
	end
end

-- the expected effort of every unique (goals_core.lua K.effortText): its chance per kill of the weakest tier that rolls
-- it (loot_config.lua unique: chance x tierMult, at most maxChance, before item find) as "~1 in N legendary kills", a
-- row of the entry's Sources table (the Conquest vendor's price is already there, gen_codex_data.lua conquestRows)
function W.uniqueEffort(D, u)
	if not ChaosGoalsCore then
		dofile("data/scripts/chaos/goals_core.lua")
	end
	local K = ChaosGoalsCore
	local lu = D.loot.unique
	local parts = {}
	for _, t in ipairs(u.bossOnly and {"boss"} or {"legendary", "boss"}) do
		local mult = tonumber(lu.tierMult[t]) or 0
		if mult > 0 then
			local p = math.min(tonumber(lu.maxChance) or 10000, (tonumber(u.chance) or 0) * mult) / 10000
			local text = K.effortText(p, t)
			if text then
				parts[#parts + 1] = text
			end
		end
	end
	if #parts == 0 then
		return nil
	end
	local where = (u.monsters and #u.monsters > 0) and " of the listed monsters" or ""
	return table.concat(parts, ", ") .. where .. (u.ascended and " (before item find)." or
		" (before item find; rift and Omen chests roll it too).")
end

function W.addUniqueEffort(D, tab)
	local byId = {}
	for _, u in ipairs(D.uniques or {}) do
		byId["unique:" .. u.id] = u
	end
	for _, e in ipairs(tab and tab.entries or {}) do
		local u = byId[e.id]
		local text = u and W.uniqueEffort(D, u)
		if text then
			for _, sec in ipairs(e.sections or {}) do
				if sec.h == "Sources" and sec.rows then
					local rows = {}
					for _, r in ipairs(sec.rows) do
						rows[#rows + 1] = r
					end
					table.insert(rows, 2, {"Expected effort", text})
					sec.rows = rows
				end
			end
		end
	end
end

local CODEX_TABS = {modifiers = true, powers = true, orbs = true, gems = true, uniques = true, sets = true, rift = true,
	supports = true, materials = true, basics = true, lore = true}

function W.build(D)
	local vocs = W.vocations()
	local spells = W.spells(vocs)
	local T = W.tree(D, vocs)
	local store, typeCount = W.storeEntries(D)
	local codex = {}
	for _, t in ipairs(D.codex.tabs) do
		if CODEX_TABS[t.id] then
			-- the shared sections (the orb table of every modifier) are put in place
			local entries = {}
			for _, e in ipairs(t.entries) do
				local copy = {}
				for k, v in pairs(e) do
					if k ~= "f" and k ~= "tv" and k ~= "tiers" and k ~= "items" then
						copy[k] = v
					end
				end
				local secs = {}
				for _, s in ipairs(e.sections or {}) do
					secs[#secs + 1] = s.ref and D.codex.shared[s.ref] or s
				end
				copy.sections = secs
				entries[#entries + 1] = copy
			end
			codex[t.id] = {id = t.id, name = t.name, entries = entries}
		end
	end
	W.addUniqueEffort(D, codex.uniques)
	table.insert(codex.rift.entries, W.atlasEntry(D))
	table.insert(codex.rift.entries, W.riftThemesEntry(D))
	local dungeons, bosses, events = W.dungeonEntries(D), W.bossEntries(D), W.eventEntries(D)
	W.markSoon(D, {dungeons, bosses, events})
	local tabs = {
		{id = "classes", name = "Classes", entries = W.classEntries(D, vocs, spells, T.byClass)},
		{id = "spells", name = "Spells", entries = W.spellEntries(spells, vocs)},
		{id = "tree", name = "Passive tree", entries = W.treeEntries(D, T)},
		codex.basics, codex.modifiers, codex.powers, codex.uniques, codex.sets, codex.orbs, codex.gems, codex.supports,
		codex.rift,
		{id = "dungeons", name = "Dungeons", entries = dungeons},
		{id = "bosses", name = "Bosses", entries = bosses},
		{id = "events", name = "Events", entries = events},
		{id = "monsters", name = "Monsters", entries = W.monsterEntries(D)},
		codex.materials,
		codex.lore,
		{id = "store", name = "Store", entries = store}
	}
	local src = W.loadArtSources(D)
	W.decorate(tabs, src)
	return {
		generator = "server/tools/gen_wiki_data.lua",
		sources = W.SOURCES,
		facts = W.facts(D, vocs, spells, T, typeCount),
		art = {guides = W.guideArt(src), steps = W.stepIcons()},
		tabs = tabs
	}
end

function W.render(data)
	return W.json(data, "") .. "\n"
end

function W.counts(data)
	local out = {}
	for _, t in ipairs(data.tabs) do
		out[#out + 1] = t.id .. " " .. #t.entries
	end
	return table.concat(out, ", ")
end

function W.main(args)
	local check, out = false, OUT_DEFAULT
	for _, a in ipairs(args or {}) do
		if a == "--check" then
			check = true
		else
			out = a
		end
	end
	local data = W.build(W.load())
	local text = W.render(data)
	if check then
		if readFile(out) ~= text then
			io.stderr:write(out .. " is stale: run  cd server && luajit tools/gen_wiki_data.lua\n")
			os.exit(1)
		end
		print("wiki data up to date (" .. W.counts(data) .. ")")
		return
	end
	local f = assert(io.open(out, "wb"))
	f:write(text)
	f:close()
	print("wrote " .. out .. " (" .. W.counts(data) .. ")")
end

if not WIKI_GEN_NO_MAIN then
	W.main(arg)
end

return W
