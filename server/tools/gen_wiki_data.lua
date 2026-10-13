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
	"data/scripts/chaos/dungeons_difficulty.lua", "data/monster/monsters/chaos/**.xml", "tools/late_game_spawns.csv",
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

local function sentence(list)
	if #list <= 1 then
		return list[1] or ""
	end
	return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
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
	D.guildboss = cfg("guildboss_config")
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
	D.antibot = cfg("antibot_config")
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
		p[#p + 1] = string.format("At level %d a %s ascends into one of two classes: the Ascendant Oracle in the temple starts the quest.",
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
	local saved = {getTreeNodes = getTreeNodes, getCustomStatString = getCustomStatString}
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
					for _, x in ipairs(variants) do
						local keys = VARIANT_CLASSES[x.key] or {x.key}
						local e = {id = "tree:" .. id .. ":" .. x.key, name = x.v.name, classes = classNames(keys), text = lines(x.v),
							node = id}
						keystones[#keystones + 1] = e
						addFor(keys, e)
					end
				else
					local e = {id = "tree:" .. id, name = n.name, classes = classNames(n.classes), text = lines(n), node = id}
					keystones[#keystones + 1] = e
					addFor(n.classes, e)
				end
			elseif n.isMastery and n.masteries then
				local rows = {}
				for _, m in ipairs(n.masteries) do
					rows[#rows + 1] = {m.name, table.concat(statText(m.customStats or {}), " ")}
				end
				masteries[#masteries + 1] = {id = "tree:" .. id, name = n.name, classes = classNames(n.classes), rows = rows,
					node = id}
			elseif n.name and n.name ~= "Attribute" and not n.name:find("^Wrath") and lines(n) ~= "" then
				notables[#notables + 1] = {id = "tree:" .. id, name = n.name, classes = classNames(n.classes), text = lines(n),
					node = id}
			end
		end
	end
	getTreeNodes, getCustomStatString = saved.getTreeNodes, saved.getCustomStatString
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
	for _, cat in ipairs(PG.categories) do
		for _, s in ipairs(cat.stats) do
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
			{h = "Paragon", p = {string.format("After level %d: %d Paragon point per level, spent on small capped stats.",
				PG.startLevel, PG.pointsPerLevel)},
				cols = {"Group", "Stat", "Per point", "Points", "At most"}, w = {18, 30, 16, 16, 20}, rows = pRows}
		}}
	for _, k in ipairs(T.keystones) do
		out[#out + 1] = {id = k.id, name = k.name, color = COLORS.tree, group = "keystone",
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
		out[#out + 1] = {id = m.id, name = m.name, color = "#9fdc7f", group = "mastery",
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
				{h = "More", p = {"Schedule, rules and rewards: World bosses."}, links = {"boss:world"}}}}
	end
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
				G.minLevel, G.maxAttempts, seconds(G.boss.enrageAt))}}}}
	return out
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
	out[#out + 1] = {id = "dungeon:about", name = "Dungeons", color = COLORS.dungeon, group = "dungeon",
		sub = string.format("Queue, %d difficulties, speed and flawless challenges.", dc.maxDifficulty),
		sections = {
			{h = "How they work", p = {
				"Step on a dungeon's entry or open Adventure > Dungeons: pick a difficulty and join the queue; the group goes in together.",
				string.format("Kill the dungeon's monsters, then its boss. A run lasts at most %s. Each finished difficulty unlocks the next one.",
					seconds(dc.maxTimeSeconds)),
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
			string.format("Enter through the portal next to the temple: %d to %d seeded rooms (combat, elite, treasure, shrine, merchant) and a boss at the end, %s at most.",
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
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- monsters: the Chaos monsters that spawn somewhere (late game areas, invasions, bosses, goblins)
-- ---------------------------------------------------------------------------------------------------------------
local MONSTER_DIRS = {"", "ascended/", "goblins/", "guildboss/", "omens/", "raid/", "world_bosses/", "wildwood/"}

function W.monsterFiles()
	local out = {}
	local listing = io.popen("cd data/monster/monsters/chaos && find . -name '*.xml' | LC_ALL=C sort")
	local text = listing:read("*a")
	listing:close()
	for path in text:gmatch("[^\n]+") do
		local data = readFile("data/monster/monsters/chaos/" .. path:gsub("^%./", ""))
		local head = data and data:match("<monster%s([^>]*)>")
		if head then
			local a = attrs(head)
			local hp = data:match("<health[^>]-max=\"(%d+)\"")
			local lmin, lmax = data:match("<level[^>]-min=\"(%d+)\"[^>]-max=\"(%d+)\"")
			out[a.name:lower()] = {name = a.name, exp = tonumber(a.experience) or 0, hp = tonumber(hp) or 0,
				level = lmin and (lmin == lmax and lmin or (lmin .. "-" .. lmax)) or nil, dir = path:match("^%./(.-)/") or ""}
		end
	end
	return out
end

function W.monsterEntries(D)
	local files = W.monsterFiles()
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
			out[#out + 1] = {id = "monster:" .. k:gsub("[^%w]+", "-"), name = m.name, color = COLORS.monster,
				sub = table.concat(where[k], "; ") .. ".",
				sections = {{h = "Monster", cols = {"", ""}, w = {35, 65}, rows = rows},
					{h = "Where", p = where[k]}}}
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
		elseif s == "pouch" or s == "templeScroll" then
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

function W.storeEntries(D)
	local out = {}
	local summary, sumLinks = {}, {}
	local typeCount = {}
	for ci, cat in ipairs(D.shop.categories) do
		local rows = {}
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
					rows = rows}
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
	local rows = {}
	for _, n in ipairs(cfgA.nodes or {}) do
		if n.kind == "keystone" or n.kind == "notable" then
			rows[#rows + 1] = {n.name, n.kind == "keystone" and "Keystone" or "Notable", n.branch or "core",
				table.concat(A.nodeLines(cfgA, n), " ")}
		end
	end
	table.sort(rows, function(a, b)
		if a[2] ~= b[2] then
			return a[2] < b[2]
		end
		return a[1] < b[1]
	end)
	local maxPts = A.maxPoints(cfgA, D.rift)
	return {id = "rift:atlas", name = "Rift Atlas", color = COLORS.basics, group = "key",
		sub = string.format("First completions give points; spend them on a map of rift bonuses (%d points in all).", maxPts),
		sections = {
			{h = "Points", p = {string.format("Points come only from first completions: each theme and tier sealed (%d), each tier without a death (%d), each tier within its Swift time (%d) and each Omen guardian (%d). %d points in all.",
				cfgA.points.cell, cfgA.points.flawless, cfgA.points.swift, cfgA.points.omen, maxPts),
				string.format("Nodes cost %d (small), %d (notable) and %d (keystone) points; you hold at most %d keystone. Refunding a node costs %s gold or %d %s.",
					cfgA.costs.small, cfgA.costs.notable, cfgA.costs.keystone, cfgA.keystoneMax, money(cfgA.respec.gold),
					cfgA.respec.orbCount, cfgA.respec.orbName)}},
			{h = "Notables and keystones", cols = {"Node", "Kind", "Branch", "Effect"}, w = {22, 12, 20, 46}, rows = rows}}}
end

-- ---------------------------------------------------------------------------------------------------------------
-- facts: the numbers of the written guides ({{key}} in the guide files)
-- ---------------------------------------------------------------------------------------------------------------
function W.facts(D, vocs, spells, T, typeCount)
	local f = {}
	local C0 = D.C0
	f["class.ascensionLevel"] = C0.classes.ascension.minLevel
	f["class.lines"] = #LINE_ORDER
	local locked, free, cost = {}, {}, nil
	for key, c in sortedPairs(D.unlocks.classes) do
		if c.locked then
			locked[#locked + 1] = c.name
			cost = c.unlock.store and c.unlock.store.cost or cost
		end
	end
	f["class.lockedCount"] = #locked
	f["class.lockedNames"] = sentence(locked)
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
	f["class.unlockCost"] = cost or 0
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
	f["item.rarities"] = #Cc.config.rarityNames
	f["item.rarityFirst"] = Cc.config.rarityNames[1]
	f["item.rarityLast"] = Cc.config.rarityNames[#Cc.config.rarityNames]
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
	f["store.categories"] = #D.shop.categories
	-- new players
	f["newplayer.tutorial"] = true
	return f
end

-- ---------------------------------------------------------------------------------------------------------------
-- the whole wiki data
-- ---------------------------------------------------------------------------------------------------------------
-- systems behind an off switch: their entries stay listed with soon = true (the website shows "coming soon"), so the
-- wiki never presents them as live. Entry id prefix -> the switch.
function W.switches(D)
	return {
		{"boss:world", D.C0.worldBoss.enabled == true}, {"boss:raid", D.raid.enabled == true},
		{"boss:ascended", D.uberCfg.enabled == true}, {"boss:guild", D.guildboss.enabled == true},
		{"dungeon:descent", D.descent.enabled == true}, {"event:invasion", D.invasion.enabled == true},
		{"event:siege", D.siege.enabled == true}
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

local CODEX_TABS = {modifiers = true, powers = true, orbs = true, gems = true, uniques = true, sets = true, rift = true,
	supports = true, materials = true, basics = true}

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
	table.insert(codex.rift.entries, W.atlasEntry(D))
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
		{id = "store", name = "Store", entries = store}
	}
	return {
		generator = "server/tools/gen_wiki_data.lua",
		sources = W.SOURCES,
		facts = W.facts(D, vocs, spells, T, typeCount),
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
