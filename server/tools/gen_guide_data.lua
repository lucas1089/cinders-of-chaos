-- Regenerates the two files of the beginner help (O373) from the "How it works" cards, unlocks_config.lua and the top menu:
--   client/overlay/modules/game_helpsearch/helpsearch_data.lua    the in-game help search (first steps, unlock entries,
--                                                                 the level and the top menu path of each card)
--   website/overlay/plugins/chaos/guide/guide_data.json            the website's beginner guide (page?plugin=chaos&p=guide)
-- Run from the server/ folder:
--   luajit tools/gen_guide_data.lua            write both files
--   luajit tools/gen_guide_data.lua --check    exit 1 when a file differs from what the data gives (CI)
--   lua5.3 works the same; the output is byte-identical under both (CI checks both).
-- Sources: the cards are built here by tools/gen_howitworks_data.lua (Gen.make, the same code that writes the client's
-- howitworks_data.lua, so the guide never lags behind the cards); the order and the tips of the first steps are
-- tools/guide_config.lua; the level of a card is the lowest level of its unlock entries (unlocks_config.lua), else the
-- "Level N+" of its "who" row; the menu path is read from client_chaos_topbar/chaos_topbar.lua (CATEGORIES).
-- No clock, no random, no pairs() order. Pure helpers are exported for tests/guide_gen_test.lua: set
-- GUIDE_GEN_NO_MAIN = true before dofile().

local Guide = {}

local OUT_CLIENT = "../client/overlay/modules/game_helpsearch/helpsearch_data.lua"
local OUT_WEB = "../website/overlay/plugins/chaos/guide/guide_data.json"
local TOPBAR = "../client/overlay/modules/client_chaos_topbar/chaos_topbar.lua"

-- ---------------------------------------------------------------------------------------------------------------
-- pure helpers
-- ---------------------------------------------------------------------------------------------------------------
function Guide.quote(s)
	s = tostring(s)
	s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
	return "\"" .. s .. "\""
end

-- the level a "who" sentence names first: "Level 100+ ...", "World boss: level 300+", "Every player from level 8"
function Guide.levelOfText(text)
	text = tostring(text or "")
	local n = text:match("^[Ll]evel (%d+)") or text:match("[Ll]evel (%d+)%+") or text:match("from level (%d+)")
	return n and tonumber(n) or nil
end

-- the top menu of the client: {text, module = first module, path = "Category > [More >] Entry"} in menu order.
-- Category lines: `{ id = 'x', text = 'Name', ...`; entries: `entry('Text', ...` four spaces deep, a sub-menu's six.
function Guide.parseMenu(source)
	local out, category, parent = {categories = {}}, nil, nil
	for line in (source .. "\n"):gmatch("(.-)\r?\n") do
		local id, cat = line:match("^%s*{ id = '([%w_]+)', text = '([^']+)'")
		if cat then
			category, parent = cat, nil
			out.categories[id] = cat
		elseif category then
			local indent, text, rest = line:match("^( *)entry%('([^']+)',(.*)$")
			if text then
				local module = rest:match("modules = { '([%w_]+)'")
				if #indent <= 4 then
					parent = rest:find("sub = {", 1, true) and text or nil
					if not parent then
						out[#out + 1] = {text = text, module = module, path = category .. " > " .. text}
					end
				elseif parent then
					out[#out + 1] = {text = text, module = module, path = category .. " > " .. parent .. " > " .. text}
				end
			end
		end
		if line:match("^}") then
			category = nil
		end
	end
	return out
end

-- an entry a module adds itself (`api.addEntry, 'social', { text = 'Mentors', icon = 'vip', modules = { 'game_mentor' }`,
-- or a `menuEntry = { text = ... }` handed over): the entry, or nil. `categories` maps a category id to its text.
function Guide.addedEntry(source, module, categories)
	local id = source:match("addEntry, '([%w_]+)'")
	local text = source:match("{ text = '([^']+)', icon = '[%w_]+', modules = { '" .. module:gsub("%p", "%%%0") .. "' }")
	local cat = id and categories[id]
	if cat and text then
		return {text = text, module = module, path = cat .. " > " .. text}
	end
	return nil
end

-- the menu path of a card: the menu text of one of its unlock entries, else the first entry that opens its window
function Guide.menuOf(card, unlockByKey, menu)
	for _, u in ipairs(card.unlocks or {}) do
		local e = unlockByKey[u]
		for _, m in ipairs(menu) do
			if e and m.text == e.menu then
				return m.path
			end
		end
	end
	for _, m in ipairs(menu) do
		if card.window and m.module == card.window then
			return m.path
		end
	end
	return nil
end

-- the level of a card (nil: any level)
function Guide.levelOf(card, unlockByKey)
	local best
	for _, u in ipairs(card.unlocks or {}) do
		local e = unlockByKey[u]
		if e and (not best or e.level < best) then
			best = e.level
		end
	end
	if best then
		return best
	end
	for _, r in ipairs(card.rows or {}) do
		if r.id == "who" then
			return Guide.levelOfText(r.en)
		end
	end
	return nil
end

-- everything both files need: cards with level and menu, the steps, the level groups, the unlock entries
function Guide.build(cards, unlocks, menu, G)
	local unlockByKey, cardByKey = {}, {}
	for _, e in ipairs(unlocks) do
		unlockByKey[e.key] = e
	end
	local out = {intro = G.intro, headings = G.headings, cards = {}, order = {}, steps = {}, levels = {}, anytime = {},
		unlocks = {}}
	for _, c in ipairs(cards) do
		local card = {key = c.key, title = c.title, rows = c.rows, level = Guide.levelOf(c, unlockByKey),
			menu = Guide.menuOf(c, unlockByKey, menu)}
		local w = G.words and G.words[c.key]
		if w then
			assert(w[1] and w[2], "guide_config.lua words." .. c.key .. ": needs en and pt")
			card.words = {en = w[1], pt = w[2]}
		end
		cardByKey[c.key] = card
		out.cards[#out.cards + 1] = card
	end
	for k in pairs(G.words or {}) do
		assert(cardByKey[k], "guide_config.lua words: no How it works card " .. tostring(k))
	end
	local inSteps = {}
	for i, s in ipairs(G.steps) do
		assert(cardByKey[s.card], "guide_config.lua steps[" .. i .. "]: no How it works card " .. tostring(s.card))
		assert(not inSteps[s.card], "guide_config.lua: the card " .. s.card .. " is a step twice")
		assert(type(s.tip) == "table" and s.tip[1] and s.tip[2], "guide_config.lua steps[" .. i .. "]: a tip needs en and pt")
		inSteps[s.card] = true
		out.steps[#out.steps + 1] = {card = s.card, en = s.tip[1], pt = s.tip[2]}
	end
	-- the rest by level (lowest first, card order inside a level), then the cards of any level
	local byLevel, levels = {}, {}
	for _, card in ipairs(out.cards) do
		if not inSteps[card.key] then
			if card.level then
				if not byLevel[card.level] then
					byLevel[card.level] = {}
					levels[#levels + 1] = card.level
				end
				table.insert(byLevel[card.level], card.key)
			else
				out.anytime[#out.anytime + 1] = card.key
			end
		end
	end
	table.sort(levels)
	for _, l in ipairs(levels) do
		out.levels[#out.levels + 1] = {level = l, cards = byLevel[l]}
	end
	for _, e in ipairs(unlocks) do
		local card
		for _, c in ipairs(cards) do
			for _, u in ipairs(c.unlocks or {}) do
				if u == e.key and not card then
					card = c.key
				end
			end
		end
		out.unlocks[#out.unlocks + 1] = {key = e.key, level = e.level, menu = e.menu, card = card,
			title = {en = e.title[1], pt = e.title[2]},
			why = {en = e.why[1][1] .. " " .. e.why[2][1], pt = e.why[1][2] .. " " .. e.why[2][2]}}
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- writers
-- ---------------------------------------------------------------------------------------------------------------
local function pair(t)
	return "{en = " .. Guide.quote(t.en) .. ", pt = " .. Guide.quote(t.pt) .. "}"
end

function Guide.renderClient(d)
	local q = Guide.quote
	local out = {
		"-- GENERATED by server/tools/gen_guide_data.lua from the How it works cards, unlocks_config.lua, tools/guide_config.lua",
		"-- and the top menu. Do not edit: cd server && luajit tools/gen_guide_data.lua (CI checks it with --check).",
		"-- Format and use: client/overlay/modules/game_helpsearch/helpcore.lua. pt-BR texts are UTF-8.",
		"HelpSearchData = {",
		"\tintro = " .. pair(d.intro) .. ",",
		"\tsteps = {"
	}
	for _, s in ipairs(d.steps) do
		out[#out + 1] = "\t\t{card = " .. q(s.card) .. ", en = " .. q(s.en) .. ", pt = " .. q(s.pt) .. "},"
	end
	out[#out] = out[#out]:gsub(",$", "")
	out[#out + 1] = "\t},"
	out[#out + 1] = "\t-- card key -> {level (nil: any level), menu = top menu path, words = extra search words}"
	out[#out + 1] = "\tcards = {"
	for _, c in ipairs(d.cards) do
		local parts = {}
		if c.level then
			parts[#parts + 1] = "level = " .. string.format("%d", c.level)
		end
		if c.menu then
			parts[#parts + 1] = "menu = " .. q(c.menu)
		end
		if c.words then
			parts[#parts + 1] = "words = " .. pair(c.words)
		end
		out[#out + 1] = "\t\t[" .. q(c.key) .. "] = {" .. table.concat(parts, ", ") .. "},"
	end
	out[#out] = out[#out]:gsub(",$", "")
	out[#out + 1] = "\t},"
	out[#out + 1] = "\tunlocks = {"
	for _, u in ipairs(d.unlocks) do
		out[#out + 1] = "\t\t{key = " .. q(u.key) .. ", level = " .. string.format("%d", u.level) .. ", menu = " .. q(u.menu) ..
			(u.card and (", card = " .. q(u.card)) or "") .. ", title = " .. pair(u.title) .. ", why = " .. pair(u.why) .. "},"
	end
	out[#out] = out[#out]:gsub(",$", "")
	out[#out + 1] = "\t}"
	out[#out + 1] = "}"
	out[#out + 1] = "return HelpSearchData"
	out[#out + 1] = ""
	return table.concat(out, "\n")
end

-- JSON (the website): fixed key order, two-language texts as {"en": ..., "pt-BR": ...} (chaos_bi() of i18n_lib.php)
local function jstr(s)
	s = tostring(s):gsub("[%c\"\\]", function(c)
		if c == "\"" then
			return "\\\""
		elseif c == "\\" then
			return "\\\\"
		elseif c == "\n" then
			return "\\n"
		elseif c == "\t" then
			return "\\t"
		end
		return string.format("\\u%04x", c:byte())
	end)
	return "\"" .. s .. "\""
end

local function jpair(t)
	return "{\"en\": " .. jstr(t.en) .. ", \"pt-BR\": " .. jstr(t.pt) .. "}"
end

local function jlist(items)
	local parts = {}
	for i, v in ipairs(items) do
		parts[i] = jstr(v)
	end
	return "[" .. table.concat(parts, ", ") .. "]"
end

function Guide.renderWeb(d)
	local out = {"{"}
	local function add(s)
		out[#out + 1] = s
	end
	add("\t\"generated\": \"server/tools/gen_guide_data.lua from the How it works cards, unlocks_config.lua and tools/guide_config.lua\",")
	add("\t\"intro\": " .. jpair(d.intro) .. ",")
	local h = d.headings
	add("\t\"headings\": {\"steps\": " .. jpair(h.steps) .. ", \"levels\": " .. jpair(h.levels) .. ", \"anytime\": " ..
		jpair(h.anytime) .. ",")
	local rows = {}
	for _, id in ipairs({"what", "who", "levels", "drops", "death", "often"}) do
		rows[#rows + 1] = "\t\t\t" .. jstr(id) .. ": " .. jpair(h.rows[id])
	end
	add("\t\t\"rows\": {\n" .. table.concat(rows, ",\n") .. "\n\t\t}\n\t},")
	local steps = {}
	for _, s in ipairs(d.steps) do
		steps[#steps + 1] = "\t\t{\"card\": " .. jstr(s.card) .. ", \"tip\": " .. jpair(s) .. "}"
	end
	add("\t\"steps\": [\n" .. table.concat(steps, ",\n") .. "\n\t],")
	local levels = {}
	for _, l in ipairs(d.levels) do
		levels[#levels + 1] = "\t\t{\"level\": " .. string.format("%d", l.level) .. ", \"cards\": " .. jlist(l.cards) .. "}"
	end
	add("\t\"levels\": [\n" .. table.concat(levels, ",\n") .. "\n\t],")
	add("\t\"anytime\": " .. jlist(d.anytime) .. ",")
	local cards = {}
	for _, c in ipairs(d.cards) do
		local r = {}
		for _, row in ipairs(c.rows) do
			r[#r + 1] = "\t\t\t\t{\"id\": " .. jstr(row.id) .. ", \"text\": " .. jpair(row) .. "}"
		end
		cards[#cards + 1] = "\t\t" .. jstr(c.key) .. ": {\n\t\t\t\"title\": " .. jpair(c.title) .. ",\n\t\t\t\"level\": " ..
			(c.level and string.format("%d", c.level) or "null") .. ",\n\t\t\t\"menu\": " .. (c.menu and jstr(c.menu) or "null") ..
			",\n\t\t\t\"rows\": [\n" .. table.concat(r, ",\n") .. "\n\t\t\t]\n\t\t}"
	end
	add("\t\"cards\": {\n" .. table.concat(cards, ",\n") .. "\n\t}")
	add("}")
	add("")
	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------------------------------------------
-- main
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

function Guide.make()
	HOWITWORKS_GEN_NO_MAIN = true
	local Gen = dofile("tools/gen_howitworks_data.lua")
	local data, C = Gen.make()
	local G = dofile("tools/guide_config.lua")
	local menu = Guide.parseMenu(assert(readFile(TOPBAR), TOPBAR))
	assert(#menu > 20, TOPBAR .. ": the top menu entries were not found (CATEGORIES changed shape?)")
	-- the windows no entry of CATEGORIES opens: the entry their module adds (client/overlay/modules/game_x/x.lua)
	local known = {}
	for _, m in ipairs(menu) do
		if m.module then
			known[m.module] = true
		end
	end
	for _, f in ipairs(data.features) do
		local w = f.window
		if w and not known[w] and w:match("^game_[%w_]+$") then
			local src = readFile("../client/overlay/modules/" .. w .. "/" .. w:sub(6) .. ".lua")
			local m = src and Guide.addedEntry(src, w, menu.categories)
			if m then
				menu[#menu + 1] = m
			end
			known[w] = true
		end
	end
	return Guide.build(data.features, C.unlocks.entries, menu, G)
end

function Guide.main(args)
	local check = false
	for _, a in ipairs(args or {}) do
		if a == "--check" then
			check = true
		end
	end
	local d = Guide.make()
	local files = {{OUT_CLIENT, Guide.renderClient(d)}, {OUT_WEB, Guide.renderWeb(d)}}
	local stale = false
	for _, f in ipairs(files) do
		if check then
			if readFile(f[1]) ~= f[2] then
				io.stderr:write(f[1] .. " is stale: run  cd server && luajit tools/gen_guide_data.lua\n")
				stale = true
			end
		else
			local h = assert(io.open(f[1], "wb"))
			h:write(f[2])
			h:close()
			print("wrote " .. f[1])
		end
	end
	if stale then
		os.exit(1)
	end
	if check then
		print("beginner guide data up to date (" .. #d.cards .. " cards, " .. #d.steps .. " first steps, " .. #d.levels ..
			" levels)")
	end
end

if not GUIDE_GEN_NO_MAIN then
	Guide.main(arg)
end

return Guide
