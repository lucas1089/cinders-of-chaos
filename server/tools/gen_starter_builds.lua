-- Regenerates the data of the Starter Builds guide (O448) from the Recommended builds of the passive tree:
--   website/overlay/plugins/chaos/guide/starter_builds_data.json   page?plugin=chaos&p=starterbuilds (starter_builds_lib.php)
-- Run from the server/ folder:
--   luajit tools/gen_starter_builds.lua            write the file
--   luajit tools/gen_starter_builds.lua --check    exit 1 when the file differs from what the data gives (CI)
--   lua5.3 works the same; the output is byte-identical under both (CI checks both).
-- Per class its three Recommended builds (passive_builds_config.lua `roles`, the node paths of passive_builds_data.lua):
--   * from the game, never typed: the name and the kind of the build, the one-line "what it does" (the build's own text up to
--     its price, English from the config and Brazilian Portuguese from i18n_strings.lua), the keystones by name with the point
--     of the build each one arrives at, the card sets the class can reach (cards_config.lua), and an import code for every
--     point cut (23, 73, 123 and 248 points: levels 100, 300, 500 and 1000). A code is ChaosBuildShare.encode of the first N
--     nodes of the build. Every cut is checked with the tree rules the loadouts use (PassiveBuildsCore.planSlot: known nodes,
--     the class's own, every node touching the start or an earlier one, at most 3 keystones, ChaosPassiveTreeCore) and
--     decoded again; a cut that is not a legal tree is dropped and listed under "dropped" in the data (none is today);
--   * from tools/starter_builds_config.lua, written by hand: how a build plays, its price in words, the spells to lean on
--     (checked against the class's spells in the client spell list), what to wear (the weapon family of the Warrior, Thief
--     and Templar lines, O454; checked against the weapons of the class) and the card set that fits (checked reachable).
-- The guide is QUALITATIVE (owner rule, 2026-11-10): no computed number. A percent sign or the letters DPS in any text, a
-- text over 240 characters (a style) and a dash stop the run. The price of a build in the game has figures; the guide
-- has its own words for it.
-- No clock, no random, no pairs() order. Pure helpers are exported for tests/starter_builds_test.lua: set
-- STARTER_GEN_NO_MAIN = true before dofile().

local Gen = {}
local unpack = table.unpack or unpack

local OUT = "../website/overlay/plugins/chaos/guide/starter_builds_data.json"
local NODES = "../client/overlay/modules/game_passivetree/treedata/nodes.lua"
local SPELLS = "../client/overlay/modules/game_chaosspells/spelldata.lua"
Gen.OUT = OUT
Gen.STYLE_MAX = 240

-- ---------------------------------------------------------------------------------------------------------------
-- pure helpers
-- ---------------------------------------------------------------------------------------------------------------
function Gen.quote(s)
	s = tostring(s)
	s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
	return "\"" .. s .. "\""
end

-- the problem with a guide text, or nil: a percent sign, the letters DPS, a dash, an empty text
function Gen.textProblem(text)
	if type(text) ~= "string" or text == "" then
		return "empty text"
	end
	if text:find("%%") then
		return "holds a percent sign"
	end
	if text:upper():find("DPS", 1, true) then
		return "holds the letters DPS"
	end
	if text:find("\226\128\148", 1, true) or text:find("\226\128\147", 1, true) then
		return "holds an em or en dash"
	end
	return nil
end

-- a {english, portuguese} pair: both texts, no problem
function Gen.pairProblem(pair, allowSame)
	if type(pair) ~= "table" or #pair ~= 2 then
		return "not an {english, portuguese} pair"
	end
	for i, text in ipairs(pair) do
		local why = Gen.textProblem(text)
		if why then
			return (i == 1 and "English " or "Portuguese ") .. why
		end
	end
	if pair[1] == pair[2] and not allowSame then
		return "the Portuguese text is the English one"
	end
	return nil
end

-- the number of characters of a UTF-8 text
function Gen.chars(text)
	local n = 0
	for _ in tostring(text):gmatch("[^\128-\191]") do
		n = n + 1
	end
	return n
end

-- ordered objects for the JSON writer: O({"key", value}, ...)
local function O(...)
	return {__ordered = {...}}
end
local function bi(pair)
	return O({"en", pair[1]}, {"pt-BR", pair[2]})
end

function Gen.json(value, indent)
	indent = indent or ""
	local t = type(value)
	if t == "string" then
		return Gen.quote(value)
	elseif t == "number" then
		return string.format("%d", value)
	elseif t == "boolean" then
		return value and "true" or "false"
	elseif t == "table" then
		local inner = indent .. "  "
		if value.__ordered then
			local parts = {}
			for _, kv in ipairs(value.__ordered) do
				parts[#parts + 1] = inner .. Gen.quote(kv[1]) .. ": " .. Gen.json(kv[2], inner)
			end
			if #parts == 0 then
				return "{}"
			end
			return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
		end
		if #value == 0 then
			return "[]"
		end
		local scalar = true
		for _, v in ipairs(value) do
			if type(v) == "table" then
				scalar = false
			end
		end
		local parts = {}
		for _, v in ipairs(value) do
			parts[#parts + 1] = scalar and Gen.json(v, inner) or (inner .. Gen.json(v, inner))
		end
		if scalar then
			return "[" .. table.concat(parts, ", ") .. "]"
		end
		return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
	end
	error("cannot write a " .. t)
end

local function readFile(path)
	local fh = io.open(path, "rb")
	if not fh then
		return nil
	end
	local text = fh:read("*a")
	fh:close()
	return text
end

-- ---------------------------------------------------------------------------------------------------------------
-- the game
-- ---------------------------------------------------------------------------------------------------------------
local function loadGame()
	local G = {}
	dofile("data/scripts/chaos/chaos_constants.lua")
	dofile("data/scripts/chaos/classes.lua")
	dofile("data/scripts/chaos/passivetree_config.lua")
	dofile("data/scripts/chaos/passivetree_core.lua")
	dofile("data/scripts/chaos/buildshare_core.lua")
	dofile("data/scripts/chaos/passive_builds_core.lua")
	G.PC, G.B, G.PB = ChaosPassiveTreeCore, ChaosBuildShare, PassiveBuildsCore
	G.tree = dofile("data/scripts/chaos/passivetree_data.lua")
	G.builds = dofile("data/scripts/chaos/passive_builds_data.lua")
	G.cfg = dofile("data/scripts/chaos/passive_builds_config.lua")
	G.pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
	dofile("data/scripts/chaos/cards_core.lua")
	G.cards, G.cardsCore = ChaosCardsConfig, ChaosCardsCore
	-- the client's node names (a keystone has one name per class variant)
	local savedTr, savedGet = rawget(_G, "tr"), rawget(_G, "getTreeNodes")
	_G.tr = function(text, ...)
		if select("#", ...) > 0 then
			return string.format(text, ...)
		end
		return text
	end
	dofile(NODES)
	G.nodes = getTreeNodes()
	_G.tr, _G.getTreeNodes = savedTr, savedGet
	dofile(SPELLS)
	G.spells = ChaosSpellData
	G.C0 = Chaos
	return G
end

Gen.loadGame = loadGame

-- the spell names of a class (vocation id) in the client spell list: {[name] = true}
local function classSpells(G, vocId)
	local set = {}
	for _, s in ipairs(G.spells) do
		for _, v in ipairs(s.vocations) do
			if v == vocId then
				set[s.name] = true
			end
		end
	end
	return set
end

-- the sets a class can reach: per element of the card sets, the number of convert lines (cards_config.lua families) of the
-- class that carry a card of it; a set is reachable with `need` of them (the same count tests/cards_test.lua --sets prints)
local function reachableSets(G, className)
	local C, K = G.cards, G.cardsCore
	local out = {}
	for _, element in ipairs(C.sets.order) do
		local n = 0
		for _, fam in ipairs(C.families) do
			if fam.kind == "convert" and K.castsLine(className, fam) then
				for _, el in ipairs(fam.elements) do
					if el == element then
						n = n + 1
					end
				end
			end
		end
		if n >= C.sets.need then
			out[element] = true
		end
	end
	return out
end

local function weaponsOf(G, className)
	for _, row in ipairs(G.cards.classes) do
		if row.name == className then
			return row.weapons
		end
	end
	return {}
end

-- the keystones of an order: {{name, point}} in the order they arrive
local function keystonesOf(G, order, variant)
	local out = {}
	local seen = {}
	for i, id in ipairs(order) do
		if not seen[id] and G.PC.isKeystone(G.tree.nodes[id]) then
			seen[id] = true
			local n = G.nodes[id]
			local name = (n[variant] and n[variant].name) or n.name
			out[#out + 1] = {name = name, point = i}
		end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- the data
-- ---------------------------------------------------------------------------------------------------------------
-- Returns the data (ordered objects), the JSON text, and a list of notes ("dropped cut ..."). Raises an error with a plain
-- message when a text or a rule of the guide is broken.
function Gen.build(S, G)
	G = G or loadGame()
	S = S or dofile("tools/starter_builds_config.lua")
	local problems, notes = {}, {}
	local function bad(msg)
		problems[#problems + 1] = msg
	end
	local passive = G.C0.passive
	local cuts = {23, 73, 123, 248}
	local levelOf = function(points)
		return passive.startLevel + points * passive.levelsPerPoint
	end
	-- the page texts
	local function checkPair(pair, label)
		local why = Gen.pairProblem(pair)
		if why then
			bad(label .. ": " .. why)
		end
	end
	checkPair(S.intro, "intro")
	for i, pair in ipairs(S.howTo) do
		checkPair(pair, "howTo " .. i)
	end
	local headingKeys = {}
	for key in pairs(S.headings) do
		headingKeys[#headingKeys + 1] = key
	end
	table.sort(headingKeys)
	for _, key in ipairs(headingKeys) do
		local pair = S.headings[key]
		local why = Gen.pairProblem(pair, key == "builds" or key == "keystones")
		if why then
			bad("heading " .. key .. ": " .. why)
		end
	end
	local kindKeys = {}
	for key in pairs(S.kinds) do
		kindKeys[#kindKeys + 1] = key
	end
	table.sort(kindKeys)
	for _, key in ipairs(kindKeys) do
		local why = Gen.pairProblem(S.kinds[key], true)
		if why then
			bad("kind " .. key .. ": " .. why)
		end
	end
	for _, element in ipairs(G.cards.sets.order) do
		local set = S.sets[element]
		if not set then
			bad("no card set text for " .. element)
		else
			checkPair(set.text, "set " .. element)
		end
	end
	local priceKeys, priceUsed = {}, {}
	for key, pair in pairs(S.prices) do
		priceKeys[#priceKeys + 1] = key
		checkPair(pair, "price " .. key)
	end
	table.sort(priceKeys)

	local classes, buildCount, codeCount = {}, 0, 0
	local usedBuild = {}
	local known = {}
	for _, c in ipairs(S.classes) do
		local vocId = G.C0.classes.ids[c.key]
		if not vocId then
			bad("class " .. c.key .. " is not a class of the game")
		else
			known[c.key] = true
			checkPair(c.line, "class line " .. c.key)
			local variant = ChaosClasses.keystoneKey(vocId)
			local className = nil
			for _, row in ipairs(G.cards.classes) do
				if row.id == vocId then
					className = row.name
				end
			end
			if className ~= c.name then
				bad("class " .. c.key .. ": the name " .. c.name .. " is not the cards' name " .. tostring(className))
			end
			local spellSet = classSpells(G, vocId)
			local reach = reachableSets(G, className or c.name)
			local weapons = weaponsOf(G, className or c.name)
			local melee = false
			local weaponWords = {}
			for _, w in ipairs(weapons) do
				if w == "sword" or w == "club" or w == "axe" then
					weaponWords[w] = true
				end
			end
			-- the weapon families of O454 are for the Warrior, Thief and Templar lines
			local line = G.C0.classes.baseOf[vocId]
			melee = line == G.C0.classes.ids.warrior or line == G.C0.classes.ids.thief or line == G.C0.classes.ids.templar
			local base = G.C0.classes.baseOf[vocId]
			local lineName
			for name, id in pairs(G.C0.classes.ids) do
				if id == base then
					lineName = name
				end
			end
			local classId = G.B.lineIndex(lineName or "")
			local roles = G.cfg.roles[c.key]
			if not roles or #roles ~= 3 then
				bad("class " .. c.key .. " has no three Recommended builds")
				roles = roles or {}
			end
			local list = {}
			for _, role in ipairs(roles) do
				local id = c.key .. "_" .. role.id
				local entry = S.builds[id]
				usedBuild[id] = true
				local data = G.PB.find(G.builds, c.key, id)
				if not entry then
					bad(id .. ": no entry in starter_builds_config.lua")
				elseif not data then
					bad(id .. ": no generated build")
				else
					buildCount = buildCount + 1
					-- the words
					local why = Gen.pairProblem(entry.style)
					if why then
						bad(id .. " style: " .. why)
					else
						for i, text in ipairs(entry.style) do
							if Gen.chars(text) > Gen.STYLE_MAX then
								bad(id .. " style " .. (i == 1 and "(English)" or "(Portuguese)") .. " is " .. Gen.chars(text) .. " characters, at most " .. Gen.STYLE_MAX)
							end
						end
					end
					local price = S.prices[entry.price or ""]
					if not price then
						bad(id .. ": unknown price " .. tostring(entry.price))
					else
						priceUsed[entry.price] = true
					end
					why = Gen.pairProblem(entry.gear)
					if why then
						bad(id .. " gear: " .. why)
					end
					-- the spells of the class kit
					if type(entry.spells) ~= "table" or #entry.spells < 2 or #entry.spells > 4 then
						bad(id .. ": 2 to 4 spells")
					else
						local seenSpell = {}
						for _, name in ipairs(entry.spells) do
							if not spellSet[name] then
								bad(id .. ": " .. name .. " is not a spell of the " .. c.name)
							end
							if seenSpell[name] then
								bad(id .. ": " .. name .. " twice")
							end
							seenSpell[name] = true
						end
					end
					-- the weapon family (O454): the Warrior, Thief and Templar lines name the family, and only a family
					-- the class fights with
					if type(entry.gear) == "table" and type(entry.gear[1]) == "string" then
						local mentioned = {}
						for _, word in ipairs({"sword", "axe", "club"}) do
							if entry.gear[1]:lower():find(word, 1, true) then
								mentioned[#mentioned + 1] = word
							end
						end
						if melee and #mentioned == 0 then
							bad(id .. ": gear names no weapon family (sword, axe or club)")
						end
						for _, word in ipairs(mentioned) do
							if not weaponWords[word] then
								bad(id .. ": gear names a " .. word .. ", which the " .. c.name .. " does not fight with")
							end
						end
					end
					-- the card set
					local cards
					if type(entry.cards) == "string" then
						if not reach[entry.cards] then
							bad(id .. ": the " .. entry.cards .. " set is not reachable for the " .. c.name)
						elseif not S.sets[entry.cards] then
							bad(id .. ": unknown set " .. entry.cards)
						else
							local set = S.sets[entry.cards]
							cards = O({"set", entry.cards}, {"name", bi(set.name)}, {"text", bi(set.text)})
						end
					elseif type(entry.cards) == "table" then
						checkPair(entry.cards, id .. " cards")
						cards = O({"none", bi(entry.cards)})
					else
						bad(id .. ": no cards entry")
					end
					-- what it does: the role's own line up to its price, English and Portuguese
					local what, ptWhat
					local text = role.text or ""
					what = text:match("^(.-) Price: ")
					local ptText = G.pt[text]
					ptWhat = ptText and ptText:match("^(.-) Preço: ")
					if not what or not ptWhat then
						bad(id .. ": the role text has no \"Price:\" split in both languages")
						what, ptWhat = what or "", ptWhat or ""
					else
						checkPair({what, ptWhat}, id .. " what")
					end
					-- the keystones and the cuts
					local keystones = keystonesOf(G, data.order, variant)
					local kslist = {}
					for _, k in ipairs(keystones) do
						kslist[#kslist + 1] = O({"name", k.name}, {"point", k.point})
					end
					local codes, dropped = {}, {}
					for _, points in ipairs(cuts) do
						if points <= #data.order then
							local prefix = {}
							for i = 1, points do
								prefix[i] = data.order[i]
							end
							local sp, reason = G.PB.planSlot(G.tree, {id = id, kind = "role", order = prefix, masteries = data.masteries or {}},
								{classKey = c.key, points = points})
							local drop
							if not sp then
								drop = "the first " .. points .. " nodes are not a legal tree (" .. tostring(reason) .. ")"
							elseif #sp.ids ~= points then
								drop = "the first " .. points .. " nodes gave " .. #sp.ids
							elseif G.PC.countKeystones(G.tree, sp.ids) > G.PC.keystoneMax() then
								drop = "the first " .. points .. " nodes hold more than " .. G.PC.keystoneMax() .. " keystones"
							end
							if drop then
								dropped[#dropped + 1] = O({"points", points}, {"why", drop})
								notes[#notes + 1] = "dropped " .. id .. " at " .. points .. ": " .. drop
							else
								local code = G.B.encode({classId = classId, nodes = sp.ids, masteries = sp.masteries})
								local back = G.B.decode(code)
								local same = back and #back.nodes == #sp.ids and back.classId == classId
								if same then
									local want = {}
									for _, id2 in ipairs(sp.ids) do
										want[id2] = true
									end
									for _, id2 in ipairs(back.nodes) do
										same = same and want[id2] == true
									end
								end
								if not same then
									bad(id .. ": the code of " .. points .. " points does not decode to the same nodes")
								end
								codes[#codes + 1] = O({"points", points}, {"level", levelOf(points)},
									{"keystones", G.PC.countKeystones(G.tree, sp.ids)}, {"code", code})
								codeCount = codeCount + 1
							end
						end
					end
					local fields = {
						{"id", id}, {"name", role.name}, {"kind", bi(S.kinds[role.kind] or {role.kind, role.kind})},
						{"what", bi({what, ptWhat})}, {"style", bi(entry.style or {"", ""})}, {"price", bi(price or {"", ""})},
						{"keystones", kslist}, {"spells", entry.spells or {}}, {"gear", bi(entry.gear or {"", ""})},
						{"cards", cards or O()}, {"codes", codes}
					}
					if #dropped > 0 then
						fields[#fields + 1] = {"dropped", dropped}
					end
					list[#list + 1] = O(unpack(fields))
				end
			end
			classes[#classes + 1] = O({"key", c.key}, {"name", c.name}, {"line", bi(c.line)}, {"builds", list})
		end
	end
	for _, id in ipairs((function()
		local ids = {}
		for key in pairs(S.builds) do
			ids[#ids + 1] = key
		end
		table.sort(ids)
		return ids
	end)()) do
		if not usedBuild[id] then
			bad(id .. ": an entry of no Recommended build of the page")
		end
	end
	for _, key in ipairs(priceKeys) do
		if not priceUsed[key] then
			bad("price " .. key .. " is used by no build")
		end
	end
	if #problems > 0 then
		error("starter builds: " .. #problems .. " problem(s)\n  " .. table.concat(problems, "\n  "), 0)
	end
	local cutList = {}
	for _, points in ipairs(cuts) do
		cutList[#cutList + 1] = O({"points", points}, {"level", levelOf(points)})
	end
	local headings = {}
	for _, key in ipairs(headingKeys) do
		headings[#headings + 1] = {key, bi(S.headings[key])}
	end
	local howTo = {}
	for _, pair in ipairs(S.howTo) do
		howTo[#howTo + 1] = bi(pair)
	end
	local kinds = {}
	for _, key in ipairs(kindKeys) do
		kinds[#kinds + 1] = {key, bi(S.kinds[key])}
	end
	local data = O({"version", 1}, {"format", "CB" .. G.B.VERSION}, {"intro", bi(S.intro)}, {"howTo", howTo},
		{"headings", O(unpack(headings))}, {"cuts", cutList}, {"classes", classes})
	local text = "{\"_generated\": \"by server/tools/gen_starter_builds.lua from passive_builds_config.lua, passive_builds_data.lua and " ..
		"starter_builds_config.lua; do not edit, CI checks it is up to date\",\n" .. Gen.json(data):sub(3) .. "\n"
	return data, text, notes, {builds = buildCount, codes = codeCount}
end

-- ---------------------------------------------------------------------------------------------------------------
-- main
-- ---------------------------------------------------------------------------------------------------------------
if not STARTER_GEN_NO_MAIN then
	local check = arg and arg[1] == "--check"
	local ok, data, text, notes, counts = pcall(Gen.build)
	if not ok then
		io.stderr:write(tostring(data) .. "\n")
		os.exit(1)
	end
	if check then
		local current = readFile(OUT)
		if current ~= text then
			io.stderr:write("gen_starter_builds: " .. OUT .. " is out of date. Run: cd server && luajit tools/gen_starter_builds.lua\n")
			os.exit(1)
		end
		print(string.format("gen_starter_builds: %d builds, %d codes, up to date", counts.builds, counts.codes))
	else
		local fh = assert(io.open(OUT, "wb"))
		fh:write(text)
		fh:close()
		for _, note in ipairs(notes) do
			print(note)
		end
		print(string.format("gen_starter_builds: wrote %s (%d builds, %d codes, %d cuts dropped)", OUT, counts.builds, counts.codes, #notes))
	end
end

return Gen
