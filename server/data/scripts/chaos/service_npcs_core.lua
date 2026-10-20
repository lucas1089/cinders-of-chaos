-- service_npcs_core.lua: the pure logic of the service NPCs (service_npcs_config.lua; engine side: service_npcs.lua places
-- them, service_npcs_run.lua and data/npc/scripts/chaos_service_npc.lua talk). No engine calls. Lua 5.1 / LuaJIT and 5.3.
--   K.has(text, ...)                    true when the lowercase text holds one of the words
--   K.intent(key, text)                 what a player's line asks of the NPC `key`, or nil
--   K.openJson(key, cfg)                the opcode key and the message that open the NPC's window (nil: no window)
--   K.buyName(text)                     the house name after "buy", or nil
--   K.afterWord(text, words)            the rest of the line after the first of the words, trimmed
--   K.findHouse(houses, query)          house | nil, "none" | "many"
--   K.freeHouses(houses, townId, max, perSqm)  the free houses of a town, cheapest first, and how many there are in all
--   K.townCounts(houses, max)           {{town, name, free}} of the towns with a free house, most free first
--   K.price(tiles, perSqm)              what a house costs
--   K.buyCheck(f)                       true | false, reason (a key of K.TEXT)
--   K.validate(cfg)                     a list of problems of the config
ChaosServiceNpcsCore = ChaosServiceNpcsCore or {}
local K = ChaosServiceNpcsCore
local unpack = table.unpack or unpack

function K.has(text, ...)
	text = tostring(text or ""):lower()
	for _, w in ipairs({...}) do
		if text:find(w, 1, true) then
			return true
		end
	end
	return false
end

-- Intents in order: the first row whose words appear wins, so the narrow ones come first.
K.INTENTS = {
	stash = {
		{"job", "who are", "your name", "what do you do"},
		{"open", "stash", "store", "stow", "deposit", "withdraw", "supply", "supplies", "trade", "items", "keep", "locker"}
	},
	pocketboss = {
		{"job", "who are", "your name", "what do you do"},
		{"charge", "daily", "how many", "reset"},
		{"open", "boss", "pocket", "spawn", "list", "hunt", "trade", "respawn", "when"}
	},
	banker = {
		{"job", "who are", "your name", "what do you do"},
		{"balance", "how much", "account"},
		{"open", "bank", "deposit", "withdraw", "transfer", "gold", "money", "trade", "coins"}
	},
	broker = {
		{"job", "who are", "your name", "what do you do"},
		{"buy", "purchase"},
		{"leave", "abandon", "give up", "vacate"},
		{"sell"},
		{"town", "where", "cities"},
		{"list", "house", "free", "offer", "home", "trade", "deed"}
	},
	services = {
		{"job", "who are", "your name", "what do you do"},
		{"name", "rename"},
		{"vocation", "class", "ascend", "switch"},
		{"familiar", "pet"},
		{"frame", "plate"},
		{"shop", "web", "order"},
		{"open", "service", "trade", "menu"}
	}
}
-- the answer names of the rows above, per NPC, in the same order
K.INTENT_NAMES = {
	stash = {"job", "open"},
	pocketboss = {"job", "charges", "open"},
	banker = {"job", "balance", "open"},
	broker = {"job", "buy", "leave", "sell", "towns", "list"},
	services = {"job", "name", "vocation", "familiar", "frame", "webshop", "open"}
}

function K.intent(key, text)
	local rows, names = K.INTENTS[key], K.INTENT_NAMES[key]
	if not rows or type(text) ~= "string" then
		return nil
	end
	for i, words in ipairs(rows) do
		if K.has(text, unpack(words)) then
			return names[i]
		end
	end
	return nil
end

function K.openJson(key, cfg)
	local n = cfg and cfg.npcs and cfg.npcs[key]
	if not n or not n.window then
		return nil
	end
	return n.window.opcode, n.window.json
end

-- the rest of `text` after the first of `words` that occurs as a whole word, trimmed; nil when none does
function K.afterWord(text, words)
	text = tostring(text or "")
	local lower = text:lower()
	local best
	for _, w in ipairs(words) do
		local s, e = lower:find("%f[%w]" .. w .. "%f[%W]")
		if s and (not best or s < best.s) then
			best = {s = s, e = e}
		end
	end
	if not best then
		return nil
	end
	local rest = text:sub(best.e + 1):gsub("^[%s:,]+", ""):gsub("%s+$", "")
	return rest
end

function K.buyName(text)
	local rest = K.afterWord(text, {"buy", "purchase"})
	if not rest then
		return nil
	end
	rest = rest:gsub("^[Tt]he%s+", ""):gsub("^[Hh]ouse%s+", ""):gsub("^[Hh]ome%s+", "")
	return rest ~= "" and rest or nil
end

local function norm(s)
	local out = tostring(s or ""):lower():gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return out
end
K.norm = norm

-- houses: {{id, name, town, townName, owner, tiles}}; an exact name (any case) wins, else the one house whose name
-- holds the query
function K.findHouse(houses, query)
	local q = norm(query)
	if q == "" then
		return nil, "none"
	end
	local part = {}
	for _, h in ipairs(houses or {}) do
		local n = norm(h.name)
		if n == q then
			return h
		end
		if n:find(q, 1, true) then
			part[#part + 1] = h
		end
	end
	if #part == 1 then
		return part[1]
	end
	return nil, #part == 0 and "none" or "many"
end

function K.price(tiles, perSqm)
	tiles = math.max(0, math.floor(tonumber(tiles) or 0))
	perSqm = math.max(0, math.floor(tonumber(perSqm) or 0))
	return tiles * perSqm
end

function K.freeHouses(houses, townId, max, perSqm)
	local list = {}
	for _, h in ipairs(houses or {}) do
		if (h.owner or 0) <= 0 and h.town == townId then
			list[#list + 1] = h
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = K.price(a.tiles, perSqm), K.price(b.tiles, perSqm)
		if pa ~= pb then
			return pa < pb
		end
		return (a.id or 0) < (b.id or 0)
	end)
	local out = {}
	for i = 1, math.min(#list, max or 6) do
		out[i] = list[i]
	end
	return out, #list
end

function K.townCounts(houses, max)
	local by, order = {}, {}
	for _, h in ipairs(houses or {}) do
		if (h.owner or 0) <= 0 and h.town then
			local t = by[h.town]
			if not t then
				t = {town = h.town, name = h.townName or tostring(h.town), free = 0}
				by[h.town] = t
				order[#order + 1] = t
			end
			t.free = t.free + 1
		end
	end
	table.sort(order, function(a, b)
		if a.free ~= b.free then
			return a.free > b.free
		end
		return a.town < b.town
	end)
	local out = {}
	for i = 1, math.min(#order, max or 8) do
		out[i] = order[i]
	end
	return out
end

-- The rules of the base server's !buyhouse (data/talkactions/scripts/buyhouse.lua of TFS 1.4: a premium account, a house
-- with no owner, none owned yet, enough money), without the door: facts = {priceOn (house price enabled), premium,
-- owner (guid of the house), owns (the player owns a house), price, money (carried and banked)}.
K.TEXT = {
	off = "Houses are not for sale on this server.",
	premium = "A house needs a premium account.",
	taken = "That house already has an owner.",
	owns = "You already own a house. Leave it first.",
	money = "You need %d gold coins (carried or in the bank) for that house."
}
function K.buyCheck(f)
	f = f or {}
	if f.priceOn == false then
		return false, "off"
	elseif not f.premium then
		return false, "premium"
	elseif (f.owner or 0) > 0 then
		return false, "taken"
	elseif f.owns then
		return false, "owns"
	elseif (tonumber(f.money) or 0) < (tonumber(f.price) or 0) then
		return false, "money"
	end
	return true
end

function K.validate(cfg)
	local problems, names = {}, {}
	if type(cfg) ~= "table" or type(cfg.npcs) ~= "table" then
		return {"no npcs"}
	end
	for _, key in ipairs(cfg.order or {}) do
		local n = cfg.npcs[key]
		if not n then
			problems[#problems + 1] = key .. ": not in npcs"
		else
			if type(n.name) ~= "string" or n.name == "" then
				problems[#problems + 1] = key .. ": no name"
			elseif names[n.name] then
				problems[#problems + 1] = key .. ": name used twice"
			end
			names[tostring(n.name)] = true
			if type(n.script) ~= "string" or not n.script:match("%.lua$") then
				problems[#problems + 1] = key .. ": no script"
			end
			if n.window and (type(n.window.opcode) ~= "string" or type(n.window.json) ~= "string") then
				problems[#problems + 1] = key .. ": window needs opcode and json"
			end
		end
	end
	return problems
end

return K
