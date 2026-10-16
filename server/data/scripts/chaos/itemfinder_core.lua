-- Item finder: pure logic (no engine API). itemfinder.lua gathers the data and asks the engine; tests:
-- server/tests/itemfinder_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- The index (K.new, K.add, K.finish): one record per server item id that has at least one row,
--   rec = {id, cid, name, key (normalized name), rows = {kind -> {row, ...}}, n = rows in all}
--   row = {n = name (monster, NPC, station, offer, source), d = detail line, v = value (chance, price), c = count text,
--          i = client id of a linked item, l = server id of a linked item, b = true for a boss, m = materials
--          {{i, l, n, c}}, o = sort number (lower first; never sent)}
-- Kinds are the sections of itemfinder_config.lua (monster, drop, reward, craft, shop, store, gamble, gather, usedin,
-- sellto, use). Item names come from the engine (K.new's info(id) -> name, client id): the renamed names.
-- Searching (K.search): every record whose normalized name matches; exact name first, then names that start with the
-- text, then names whose words start with every word typed, then names that contain the text, then names that contain
-- every word; ties by the shorter name, the name and the id. Paging: K.search pages the hits, K.pageOf the rows of one
-- section. K.request is the opcode's dispatch (the engine throttles and sends).
-- Parsers for the engine: the NPC files (K.parseNpcXml, K.parseNpcScript, K.parseShopList) and the spawn file
-- (K.parseSpawnNpcs); K.placeText names the nearest town.

ChaosItemFinderCore = ChaosItemFinderCore or {}
local K = ChaosItemFinderCore
local floor = math.floor

-- ---------------------------------------------------------------- texts
-- lower case, everything but letters and digits as one space, trimmed (bytes above 127 kept: accented letters)
function K.norm(s)
	s = tostring(s or ""):lower():gsub("[^%w\128-\255]+", " ")
	s = s:gsub("^ +", ""):gsub(" +$", "")
	return s
end

function K.words(s)
	local out = {}
	for w in K.norm(s):gmatch("%S+") do
		out[#out + 1] = w
	end
	return out
end

-- 1234567 -> "1,234,567"
function K.int(n)
	n = floor((tonumber(n) or 0) + 0.5)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (n < 0 and "-" or "") .. out
end

local function trimNum(v, digits)
	local s = string.format("%." .. digits .. "f", v)
	if s:find("%.") then
		s = s:gsub("0+$", ""):gsub("%.$", "")
	end
	return s
end

-- a percent: 1 decimal from 1%, up to 3 below; "<0.001%" for less
function K.percent(p)
	p = tonumber(p) or 0
	if p <= 0 then
		return "0%"
	elseif p >= 100 then
		return "100%"
	elseif p >= 1 then
		return trimNum(p, 1) .. "%"
	elseif p >= 0.001 then
		return trimNum(p, 3) .. "%"
	end
	return "<0.001%"
end

-- a chance of 100000 (the engine's loot lists)
function K.pct(per100000)
	return K.percent((tonumber(per100000) or 0) / 1000)
end

-- a chance of 10000 (the Chaos loot layer)
function K.per10k(v)
	return K.percent((tonumber(v) or 0) / 100)
end

-- "" for one, "x3", "x1-3"
function K.countText(lo, hi)
	lo, hi = tonumber(lo) or 1, tonumber(hi) or tonumber(lo) or 1
	if hi < lo then
		hi = lo
	end
	if hi <= 1 then
		return nil
	end
	if lo == hi then
		return "x" .. K.int(lo)
	end
	return "x" .. K.int(lo) .. "-" .. K.int(hi)
end

function K.gold(n)
	return K.int(n) .. " gold"
end

-- a whole number from client input between lo and hi, or nil
function K.toInt(v, lo, hi)
	v = tonumber(v)
	if not v or v ~= v or v ~= floor(v) then
		return nil
	end
	if (lo and v < lo) or (hi and v > hi) then
		return nil
	end
	return v
end

-- ---------------------------------------------------------------- places
-- towns = {{name, x, y, z}}; the town whose temple is nearest (largest of |dx|, |dy|; the floor does not count)
function K.nearestTown(pos, towns)
	local best, bestD
	for _, t in ipairs(towns or {}) do
		local d = math.max(math.abs(pos.x - t.x), math.abs(pos.y - t.y))
		if not bestD or d < bestD then
			best, bestD = t, d
		end
	end
	return best, bestD
end

-- "in Brassgate", "near Brassgate" (farther than `near` tiles) or nil without towns
function K.placeText(pos, towns, near)
	local t, d = K.nearestTown(pos, towns)
	if not t then
		return nil
	end
	return (d <= (near or 60) and "in " or "near ") .. t.name
end

-- "surface", "underground", "above ground" for a floor
function K.floorText(z)
	z = tonumber(z) or 7
	if z == 7 then
		return "surface"
	elseif z > 7 then
		return "underground"
	end
	return "upstairs"
end

-- the place texts of several positions, each town once, at most `max`
function K.placesText(positions, towns, near, max)
	local seen, out = {}, {}
	for _, p in ipairs(positions or {}) do
		local t = K.placeText(p, towns, near)
		if t and not seen[t] then
			seen[t] = true
			if #out < (max or 3) then
				out[#out + 1] = t
			end
		end
	end
	local more = 0
	for _ in pairs(seen) do
		more = more + 1
	end
	more = more - #out
	local s = table.concat(out, ", ")
	if more > 0 then
		s = s .. string.format(" (+%d)", more)
	end
	return s ~= "" and s or nil
end

-- ---------------------------------------------------------------- the index
local function set(list)
	local s = {}
	for k, v in pairs(list or {}) do
		if type(k) == "number" and v ~= nil and v ~= false then
			s[type(v) == "string" and v:lower() or v] = true
		elseif v == true then
			s[type(k) == "string" and k:lower() or k] = true
		end
	end
	return s
end

-- info(id) -> name, client id (nil for an unknown id); the engine's ItemType
function K.new(cfg, info)
	local kinds = {}
	for i, k in ipairs(cfg.sections) do
		kinds[k] = i
	end
	return {cfg = cfg, info = info, items = {}, byCid = {}, list = {}, seen = {}, ready = false, rowCount = 0,
		kinds = kinds, hiddenItems = set(cfg.hidden and cfg.hidden.items),
		hiddenSources = set(cfg.hidden and cfg.hidden.sources)}
end

-- the record of a server id (made on first use), or nil for an unknown, nameless or hidden id
function K.rec(idx, id)
	id = tonumber(id)
	if not id or id <= 0 or id ~= floor(id) then
		return nil
	end
	local r = idx.items[id]
	if r ~= nil then
		return r or nil
	end
	if idx.hiddenItems[id] then
		idx.items[id] = false
		return nil
	end
	local ok, name, cid = pcall(idx.info, id)
	if not ok or type(name) ~= "string" or name == "" then
		idx.items[id] = false
		return nil
	end
	r = {id = id, cid = tonumber(cid) or 0, name = name, key = K.norm(name), rows = {}, n = 0}
	idx.items[id] = r
	return r
end

function K.nameOf(idx, id)
	local r = K.rec(idx, id)
	return r and r.name or nil
end

-- add a row of `kind` to item `id`. row.ref = a server id: the row links that item (l, i) and takes its name when it
-- has none (recipes that use this item). row.m = {{id, count}}: materials, resolved to {i, l, n, c}. Returns true when
-- added (false: hidden item, hidden source, unknown kind or id, a duplicate)
function K.add(idx, id, kind, row)
	if not idx.kinds[kind] or type(row) ~= "table" then
		return false
	end
	local r = K.rec(idx, id)
	if not r then
		return false
	end
	if row.ref then
		local other = K.rec(idx, row.ref)
		if not other then
			return false
		end
		row.l, row.i = other.id, other.cid
		row.n = row.n or other.name
		row.ref = nil
	end
	if type(row.n) ~= "string" or row.n == "" or idx.hiddenSources[row.n:lower()] then
		return false
	end
	local msig = ""
	if row.m then
		local m, parts = {}, {}
		for _, e in ipairs(row.m) do
			local mr = K.rec(idx, e[1] or e.id)
			if not mr then
				return false -- a recipe with an unknown material is not shown
			end
			m[#m + 1] = {i = mr.cid, l = mr.id, n = mr.name, c = tonumber(e[2] or e.count) or 1}
			parts[#parts + 1] = mr.id .. "x" .. m[#m].c
		end
		row.m = m
		msig = table.concat(parts, ",")
	end
	local sig = table.concat({id, kind, row.n, tostring(row.d), tostring(row.v), tostring(row.c), tostring(row.l), msig},
		"\0")
	if idx.seen[sig] then
		return false
	end
	idx.seen[sig] = true
	local list = r.rows[kind]
	if not list then
		list = {}
		r.rows[kind] = list
	end
	list[#list + 1] = row
	r.n = r.n + 1
	idx.rowCount = idx.rowCount + 1
	return true
end

local function rowLess(a, b)
	local ao, bo = a.o or 0, b.o or 0
	if ao ~= bo then
		return ao < bo
	end
	if a.n ~= b.n then
		return a.n < b.n
	end
	return tostring(a.d or "") < tostring(b.d or "")
end

local function recLess(a, b)
	if a.key ~= b.key then
		return a.key < b.key
	end
	return a.id < b.id
end

-- sort every section, list the records with rows, map client ids (an id shared by several server ids: the one with
-- the most rows, then the lowest id)
function K.finish(idx)
	idx.seen = {}
	local list, byCid = {}, {}
	local items, rows = 0, 0
	for _, r in pairs(idx.items) do
		if r and r.n > 0 then
			for _, l in pairs(r.rows) do
				table.sort(l, rowLess)
			end
			list[#list + 1] = r
			items, rows = items + 1, rows + r.n
			local cur = byCid[r.cid]
			if r.cid > 0 and (not cur or r.n > cur.n or (r.n == cur.n and r.id < cur.id)) then
				byCid[r.cid] = r
			end
		end
	end
	table.sort(list, recLess)
	idx.list, idx.byCid = list, byCid
	idx.ready = true
	idx.stats = {items = items, rows = rows}
	return idx.stats
end

-- ---------------------------------------------------------------- search
local function wordsOf(r)
	if not r.w then
		r.w = K.words(r.key)
	end
	return r.w
end

-- 0 exact, 1 starts with the text, 2 every word typed starts a word of the name, 3 contains the text, 4 contains every
-- word; nil: no match
function K.score(r, q, tokens)
	local key = r.key
	if key == q then
		return 0
	end
	if key:sub(1, #q) == q then
		return 1
	end
	local words = wordsOf(r)
	local all = #tokens > 0
	for _, t in ipairs(tokens) do
		local found = false
		for _, w in ipairs(words) do
			if w:sub(1, #t) == t then
				found = true
				break
			end
		end
		if not found then
			all = false
			break
		end
	end
	if all then
		return 2
	end
	if key:find(q, 1, true) then
		return 3
	end
	for _, t in ipairs(tokens) do
		if not key:find(t, 1, true) then
			return nil
		end
	end
	return #tokens > 0 and 4 or nil
end

local function pages(total, per)
	return math.max(1, math.ceil(total / per))
end

-- the kinds an item has rows of, in section order
function K.kindsOf(idx, r)
	local out = {}
	for _, k in ipairs(idx.cfg.sections) do
		if r.rows[k] then
			out[#out + 1] = k
		end
	end
	return out
end

-- {q, p, pages, total, rows = {{id, cid, name, n, kinds}}}; q too short: no rows
function K.search(idx, q, page)
	local cfg = idx.cfg
	q = K.norm(tostring(q or ""):sub(1, cfg.maxQuery))
	local out = {q = q, p = 1, pages = 1, total = 0, rows = {}}
	if #q < cfg.minQuery then
		return out
	end
	local tokens = K.words(q)
	local hits = {}
	for _, r in ipairs(idx.list) do
		local s = K.score(r, q, tokens)
		if s then
			hits[#hits + 1] = {r = r, s = s}
		end
	end
	table.sort(hits, function(a, b)
		if a.s ~= b.s then
			return a.s < b.s
		end
		if #a.r.key ~= #b.r.key then
			return #a.r.key < #b.r.key
		end
		return recLess(a.r, b.r)
	end)
	out.total = #hits
	out.pages = pages(#hits, cfg.perPage)
	local p = math.min(math.max(K.toInt(page) or 1, 1), out.pages, cfg.maxPage)
	out.p = p
	for i = (p - 1) * cfg.perPage + 1, math.min(#hits, p * cfg.perPage) do
		local r = hits[i].r
		out.rows[#out.rows + 1] = {id = r.id, cid = r.cid, name = r.name, n = r.n, kinds = K.kindsOf(idx, r)}
	end
	return out
end

-- ---------------------------------------------------------------- an item and its sections
local function wireRow(row)
	return {n = row.n, d = row.d, v = row.v, c = row.c, i = row.i, l = row.l, b = row.b, m = row.m}
end

-- one page of one section: {id, k, p, pages, total, rows}
function K.pageOf(idx, r, kind, page)
	local rows = r.rows[kind] or {}
	local per = idx.cfg.rowsPerPage
	local out = {id = r.id, k = kind, total = #rows, pages = pages(#rows, per), rows = {}}
	local p = math.min(math.max(K.toInt(page) or 1, 1), out.pages, idx.cfg.maxPage)
	out.p = p
	for i = (p - 1) * per + 1, math.min(#rows, p * per) do
		out.rows[#out.rows + 1] = wireRow(rows[i])
	end
	return out
end

-- the record of a server id or (when id is nil) of a client id
function K.find(idx, id, cid)
	id, cid = K.toInt(id, 1), K.toInt(cid, 1)
	local r
	if id then
		r = idx.items[id]
	elseif cid then
		r = idx.byCid[cid]
	end
	if r and r.n > 0 then
		return r
	end
	return nil
end

-- {id, cid, name, total, secs = {first page of every section}}; an item without rows: {id, cid, name, none = true}
function K.lookup(idx, id, cid)
	local r = K.find(idx, id, cid)
	if not r then
		local known = K.toInt(id, 1) and idx.items[K.toInt(id, 1)] or nil
		return {id = K.toInt(id, 1) or 0, cid = K.toInt(cid, 1) or (known and known.cid) or 0,
			name = known and known.name or nil, none = true, secs = {}}
	end
	local secs = {}
	for _, k in ipairs(idx.cfg.sections) do
		if r.rows[k] then
			secs[#secs + 1] = K.pageOf(idx, r, k, 1)
		end
	end
	return {id = r.id, cid = r.cid, name = r.name, total = r.n, secs = secs}
end

-- the short "where from" of an item tooltip (item_tooltip.lua): the first two sources and, when the item comes only by
-- luck, the best chance per kill. nil for an item without rows.
--   {s = {{k = kind, n = name, v = value text}}, e = {p = chance 0..1, w = "kill" | "legendary" | "boss", m = monster}}
K.BRIEF = {"drop", "monster", "reward", "craft", "shop", "store", "gamble", "gather"} -- the global drop tables first
K.SURE = {craft = true, shop = true, gamble = true, gather = true} -- a sure way: no effort line (the store and the
-- Conquest vendor still show it: "~1 in 400 legendary kills, or 690 tokens")
K.EFFORT_BELOW = 0.2 -- the effort line shows below this chance per kill (1 in 5)
function K.brief(idx, id, cid)
	local r = idx and idx.ready and K.find(idx, id, cid)
	if not r then
		return nil
	end
	local src, best, sure = {}, nil, false
	local named = {} -- one source per name: a monster whose loot lists the item twice (two entries, or child loot) gave
	-- "Drops from: Abyssal Crab (100%), Abyssal Crab (100%)" (live test winpkg-35); the first row is the best one
	for _, kind in ipairs(K.BRIEF) do
		for _, row in ipairs(r.rows[kind] or {}) do
			local name = tostring(row.n):sub(1, 32)
			if #src < 2 and not named[name] then
				named[name] = true
				src[#src + 1] = {k = kind, n = name, v = row.v}
			end
			sure = sure or K.SURE[kind] == true
			local p = tonumber(row.p)
			if p and p > 0 and (not best or p > best.p) then
				best = {p = p, w = row.pk or "kill", m = kind == "monster" and row.n or nil}
			end
		end
	end
	if #src == 0 then
		return nil
	end
	return {s = src, e = (not sure and best and best.p < K.EFFORT_BELOW) and best or nil}
end

-- the opcode's dispatch: action, data -> answer action, answer data (nil: nothing to answer)
--   search {q, p}       -> results {q, p, pages, total, rows}
--   item {id} | {cid}   -> item {id, cid, name, total, secs} | {.., none = true}
--   page {id, k, p}     -> page {id, k, p, pages, total, rows}
function K.request(idx, action, data)
	if type(action) ~= "string" then
		return nil
	end
	data = type(data) == "table" and data or {}
	if not idx or not idx.ready then
		return "busy", {}
	end
	if action == "search" then
		return "results", K.search(idx, type(data.q) == "string" and data.q or "", data.p)
	elseif action == "item" then
		return "item", K.lookup(idx, data.id, data.cid)
	elseif action == "page" then
		local r = K.find(idx, data.id)
		if not r or type(data.k) ~= "string" or not r.rows[data.k] then
			return nil
		end
		return "page", K.pageOf(idx, r, data.k, data.p)
	end
	return nil
end

-- ---------------------------------------------------------------- parsers (NPC files, spawn file)
local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "name,id,price[,subtype[,real name]];..." -> {{id, price}}; containers: "name,container,id,price;..."
function K.parseShopList(value, containers)
	local out = {}
	for entry in tostring(value or ""):gmatch("[^;]+") do
		local f = {}
		for part in entry:gmatch("[^,]+") do
			f[#f + 1] = trim(part)
		end
		local id, price
		if containers then
			id, price = tonumber(f[3]), tonumber(f[4])
		else
			id, price = tonumber(f[2]), tonumber(f[3])
		end
		if id and price and id > 0 and price >= 0 then
			out[#out + 1] = {id = id, price = price}
		end
	end
	return out
end

local function append(list, more)
	for _, e in ipairs(more) do
		list[#list + 1] = e
	end
end

-- an NPC file: {name, script, buy = {{id, price}}, sell = {{id, price}}} (buy: the NPC sells to the player)
function K.parseNpcXml(text)
	text = tostring(text or "")
	local head = text:match("<npc(%s[^>]*)>") or ""
	local out = {name = head:match('%sname%s*=%s*"([^"]+)"'), script = head:match('%sscript%s*=%s*"([^"]+)"'),
		buy = {}, sell = {}}
	for key, value in text:gmatch('key%s*=%s*"([%w_]+)"%s+value%s*=%s*"([^"]*)"') do
		if key == "shop_buyable" then
			append(out.buy, K.parseShopList(value))
		elseif key == "shop_sellable" then
			append(out.sell, K.parseShopList(value))
		elseif key == "shop_buyable_containers" then
			append(out.buy, K.parseShopList(value, true))
		end
	end
	return out
end

-- the numbers after the names argument of a shop call: "({'a', 'b'}, 2160, 100, ...)" -> 2160, 100
local function callNumbers(args, skip)
	local body = args:sub(2, -2)
	local rest = body:match("^%s*%b{}%s*,(.*)$") or body:match("^%s*nil%s*,(.*)$")
	if not rest then
		return nil
	end
	local nums = {}
	for n in rest:gmatch("[^,]+") do
		nums[#nums + 1] = tonumber(trim(n))
		if #nums >= skip + 2 then
			break
		end
	end
	return nums[skip + 1], nums[skip + 2]
end

-- an NPC script: shopModule:addBuyableItem / addBuyableItemContainer / addSellableItem calls, and (scripts that open
-- their own trade window) tables {name = "...", id = N, buy = N, sell = N}. Returns buy, sell lists of {id, price}.
function K.parseNpcScript(text)
	text = tostring(text or "")
	local buy, sell = {}, {}
	local function put(list, id, price)
		if id and price and id > 0 and price >= 0 then
			list[#list + 1] = {id = id, price = price}
		end
	end
	if text:find("addBuyableItem", 1, true) then
		for args in text:gmatch("addBuyableItem%s*(%b())") do
			put(buy, callNumbers(args, 0))
		end
		for args in text:gmatch("addBuyableItemContainer%s*(%b())") do
			put(buy, callNumbers(args, 1))
		end
	end
	if text:find("addSellableItem", 1, true) then
		for args in text:gmatch("addSellableItem%s*(%b())") do
			put(sell, callNumbers(args, 0))
		end
	end
	if text:find("openShopWindow", 1, true) then
		for body in text:gmatch("{([^{}]-)}") do
			local s = " " .. body
			local id = tonumber(s:match("[^%w_]id%s*=%s*(%d+)"))
			if id then
				put(buy, id, tonumber(s:match("[^%w_]buy%s*=%s*(%d+)")))
				put(sell, id, tonumber(s:match("[^%w_]sell%s*=%s*(%d+)")))
			end
		end
	end
	return buy, sell
end

-- a spawn file: {{name, x, y, z}} of every NPC (positions relative to the centre of the spawn it is in). The spawn
-- starts are listed first and each NPC is placed in the last one before it: one pass over the text for each tag, no
-- capture of whole spawn blocks (the full map's spawn file is 9 MB of mostly monsters)
function K.parseSpawnNpcs(text)
	text = tostring(text or "")
	local function tags(tag)
		local list, i = {}, 1
		while true do
			local s = text:find(tag, i, true)
			if not s then
				break
			end
			local e = text:find(">", s, true)
			if not e then
				break
			end
			list[#list + 1] = {s, text:sub(s + #tag, e - 1)}
			i = e + 1
		end
		return list
	end
	local spawns = tags("<spawn ")
	local out = {}
	local k = 0
	for _, t in ipairs(tags("<npc ")) do
		while k < #spawns and spawns[k + 1][1] < t[1] do
			k = k + 1
		end
		local sp = k > 0 and spawns[k][2]
		local cx = sp and tonumber(sp:match('centerx%s*=%s*"(-?%d+)"'))
		local cy = sp and tonumber(sp:match('centery%s*=%s*"(-?%d+)"'))
		local cz = sp and tonumber(sp:match('centerz%s*=%s*"(-?%d+)"'))
		local a = " " .. t[2]
		local name = a:match('%sname%s*=%s*"([^"]+)"')
		if name and cx and cy and cz then
			local x, y = tonumber(a:match('%sx%s*=%s*"(-?%d+)"')) or 0, tonumber(a:match('%sy%s*=%s*"(-?%d+)"')) or 0
			out[#out + 1] = {name = name, x = cx + x, y = cy + y, z = tonumber(a:match('%sz%s*=%s*"(-?%d+)"')) or cz}
		end
	end
	return out
end

-- "Hunting: A, B (level 70-90)" marks of the map markers -> {lower monster name -> "70-90"} (the lowest band first)
function K.huntBands(marks)
	local out, lows = {}, {}
	for _, m in ipairs(marks or {}) do
		if m.k == "hunt" and type(m.n) == "string" then
			local names, lo, hi = m.n:match("^Hunting: (.-) %(level (%d+)%-(%d+)%)$")
			lo, hi = tonumber(lo), tonumber(hi)
			if names and lo then
				for name in names:gmatch("[^,]+") do
					local key = trim(name):lower()
					if not lows[key] or lo < lows[key] then
						lows[key] = lo
						out[key] = lo .. "-" .. hi
					end
				end
			end
		end
	end
	return out
end

return K
