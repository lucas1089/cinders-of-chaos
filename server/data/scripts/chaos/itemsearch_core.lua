-- Find my item (O412): the rules of a search over every place a character keeps items, without engine calls.
-- stash.lua runs it for the stash opcode's "Find" action; server/tests/itemsearch_test.lua tests it; numbers in
-- stash_config.lua `find`. server/README.md "Find my item (O412)".
--
-- Places, in the order the results list them:
--   equip   an equipped item (slot 1..10)
--   bag     an item inside a container of an equipped slot (the backpack, a quiver): slot, path (the index of each
--           container from the slot's container down, 0 = first), at (its index in its own container), ids (the client
--           ids of the containers on the way: the client checks them before it opens anything)
--   purse   the store inbox (what the store delivered), any depth
--   inbox   the depot inbox (the market and mail), any depth; the stash window's Inbox button collects it
--   stash   a stash entry: tab, row (a stored item) or item (a merged stack)
--
--   K.fold(text)                         lower case, pt-BR accents dropped, spaces collapsed: "Lendária  Espada" -> "lendaria espada"
--   K.query(text, cfg)                   {words} or nil, why ("short" | "long")
--   K.matches(words, haystack)           every word is in the folded haystack
--   K.search(cfg, words, places, api)    {items, total, capped, scanned}
--       places = {{kind = "equip" | "bag" | "purse" | "inbox", slot, item, name}, {kind = "stash", entries = {...}}}
--       api.describe(item) -> {name, count, cid, rarity, unique, words (extra text: rarity names, affix lines),
--                              container}; api.children(item) -> the items inside (top first) or nil
--       a stash entry is already described: {name, count, cid, rarity, unique, words, tab, tabName, old, row, item}
--   K.page(result, page, size)           {items (that page), page, pages, total, capped}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosItemSearchCore = ChaosItemSearchCore or {}
local K = ChaosItemSearchCore

local function int(v)
	v = tonumber(v)
	if not v or v ~= v then
		return 0
	end
	return math.floor(v)
end

-- the pt-BR letters a player may type with or without the accent (UTF-8 sequences -> the plain letter)
local ACCENTS = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a",
	["é"] = "e", ["ê"] = "e", ["è"] = "e", ["É"] = "e", ["Ê"] = "e",
	["í"] = "i", ["ì"] = "i", ["Í"] = "i",
	["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ò"] = "o", ["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o",
	["ú"] = "u", ["ü"] = "u", ["Ú"] = "u",
	["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n"
}

function K.fold(text)
	if type(text) ~= "string" then
		return ""
	end
	local s = text:gsub("[\195][\128-\191]", function(c) return ACCENTS[c] or c end)
	s = s:lower():gsub("[%c]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return s
end

-- the words of a query: at least cfg.minChars letters in all, at most cfg.maxChars, at most cfg.maxWords words
function K.query(text, cfg)
	cfg = cfg or {}
	if type(text) ~= "string" then
		return nil, "short"
	end
	if #text > int(cfg.maxChars or 40) then
		return nil, "long"
	end
	local folded = K.fold(text)
	local words = {}
	for w in folded:gmatch("%S+") do
		if #words < int(cfg.maxWords or 5) then
			words[#words + 1] = w
		end
	end
	if #folded:gsub(" ", "") < int(cfg.minChars or 2) then
		return nil, "short"
	end
	return words
end

function K.matches(words, haystack)
	if type(words) ~= "table" or #words == 0 then
		return false
	end
	for _, w in ipairs(words) do
		if not haystack:find(w, 1, true) then
			return false
		end
	end
	return true
end

local function hay(d)
	return K.fold((d.name or "") .. " " .. (d.words or ""))
end

local function cut(s, n)
	s = tostring(s or "")
	if #s > n then
		return s:sub(1, n)
	end
	return s
end

local function copy(list)
	local out = {}
	for i, v in ipairs(list or {}) do
		out[i] = v
	end
	return out
end

local ORDER = {equip = 1, bag = 2, purse = 3, inbox = 4, stash = 5}
K.ORDER = ORDER

function K.search(cfg, words, places, api)
	cfg = cfg or {}
	local max = math.max(1, int(cfg.max or 200))
	local scanLimit = math.max(1, int(cfg.scanLimit or 3000))
	local maxDepth = math.max(1, int(cfg.maxDepth or 8))
	local nameLen = int(cfg.nameChars or 40)
	local out = {items = {}, total = 0, capped = false, scanned = 0}

	local function add(row, d)
		out.total = out.total + 1
		if #out.items >= max then
			out.capped = true
			return
		end
		row.name = cut(d.name, nameLen)
		row.count = math.max(1, int(d.count))
		row.cid = int(d.cid)
		row.rarity = int(d.rarity) > 0 and int(d.rarity) or nil
		row.unique = d.unique == true or nil
		out.items[#out.items + 1] = row
	end

	-- one container's items (depth: of the container itself, 1 = the slot's / the inbox's own container)
	local function walk(place, container, path, ids, names, depth)
		local kids = api.children(container)
		if type(kids) ~= "table" then
			return
		end
		for i, child in ipairs(kids) do
			if out.scanned >= scanLimit then
				out.capped = true
				return
			end
			out.scanned = out.scanned + 1
			local d = api.describe(child) or {}
			if K.matches(words, hay(d)) then
				add({loc = place.kind, slot = place.slot, path = copy(path), at = i - 1, ids = copy(ids),
					where = cut(table.concat(names, " > "), int(cfg.whereChars or 80))}, d)
			end
			if d.container and depth < maxDepth then
				path[#path + 1] = i - 1
				ids[#ids + 1] = int(d.cid)
				names[#names + 1] = cut(d.name, 24)
				walk(place, child, path, ids, names, depth + 1)
				path[#path], ids[#ids], names[#names] = nil, nil, nil
			end
		end
	end

	for _, place in ipairs(places or {}) do
		if place.kind == "stash" then
			for _, e in ipairs(place.entries or {}) do
				if out.scanned >= scanLimit then
					out.capped = true
					break
				end
				out.scanned = out.scanned + 1
				if K.matches(words, hay(e)) then
					add({loc = "stash", tab = int(e.tab), tabName = e.tabName, old = e.old or nil, row = e.row,
						item = e.item}, e)
				end
			end
		elseif place.item ~= nil then
			local d = place.kind == "equip" and (api.describe(place.item) or {}) or nil
			if d then
				out.scanned = out.scanned + 1
				if K.matches(words, hay(d)) then
					add({loc = "equip", slot = place.slot}, d)
				end
			end
			-- a container: what is inside (an equipped one is a "bag"; the inbox and the purse keep their kind)
			local top = d or api.describe(place.item) or {}
			if top.container then
				local kind = place.kind == "equip" and "bag" or place.kind
				walk({kind = kind, slot = place.slot}, place.item, {}, {int(top.cid)}, {cut(place.name or top.name, 24)}, 1)
			end
		end
	end

	-- the places in their order, each in the order it was walked
	for i, r in ipairs(out.items) do
		r.n = i
	end
	table.sort(out.items, function(a, b)
		local oa, ob = ORDER[a.loc] or 9, ORDER[b.loc] or 9
		if oa ~= ob then
			return oa < ob
		end
		return a.n < b.n
	end)
	for _, r in ipairs(out.items) do
		r.n = nil
	end
	return out
end

function K.page(result, page, size)
	size = math.max(1, int(size))
	local items = result and result.items or {}
	local pages = math.max(1, math.ceil(#items / size))
	page = math.max(1, math.min(pages, int(page) > 0 and int(page) or 1))
	local out = {}
	for i = (page - 1) * size + 1, math.min(#items, page * size) do
		out[#out + 1] = items[i]
	end
	return {items = out, page = page, pages = pages, total = result and result.total or 0,
		shown = #items, capped = result and result.capped or false}
end

return K
