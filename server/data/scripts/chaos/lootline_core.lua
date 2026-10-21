-- One loot line per kill (server/README.md "One loot line per kill"): the rules, no engine calls (lootline.lua is the
-- engine side; server/tests/lootline_test.lua). Playtest 2026-10-16: a kill printed three lines, the stock "Loot of
-- <monster>: <items>" (default_onDropLoot.lua), "Chaos bonus loot of <monster>: <items>" (loot.lua) and "Looted:
-- <items> (<pouch notes>)." (pouches.lua). Now they are one line:
--   "Loot of a dragon: 120 gold coins, a dragon ham, 2 ember shards, {Ashbringer}. Looted: 120 gold coins,
--    {Ashbringer} (2 to your backpack)."
-- The stock part comes first and keeps its "Loot of" start (the client's loot colouring and short numbers read loot
-- messages by their mode; the stock prefix stays), the Chaos bonus items join its list (uniques and rare items keep
-- their {} highlight), and the pouch part (what the pouches and the Loot Bag took, their notes) ends the line. The
-- pouch part is the owner's own: in a party the other members get the line without it.
-- Since the beta report of 2026-10-21 the item list is the corpse as it is after the loot layer (K.describe, index 1.9 of
-- lootline.lua), not the stock list: the layer thins the corpse after the stock line was written.
-- Each recipient reads the fixed parts in their language (t = Chaos.t bound to the recipient: "Loot of %s: %s",
-- "nothing", ...; pt-BR in i18n_strings.lua); item and monster names stay as the engine gives them. The stock line is
-- read in English (the engine writes it so); the client's loot colouring keys on the message mode and the {} marks,
-- not on the words, so the translated prefix keeps it working.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosLootLineCore = ChaosLootLineCore or {}
local K = ChaosLootLineCore

K.PREFIX = "Loot of "

-- a stock loot line ("Loot of <monster>: <items>")
function K.isStockLine(text)
	return type(text) == "string" and text:sub(1, #K.PREFIX) == K.PREFIX and text:find(": ", #K.PREFIX + 1, true) ~= nil
end

-- "Loot of a dragon: 120 gold coins" -> "a dragon", "120 gold coins"
function K.split(text)
	if not K.isStockLine(text) then
		return nil, nil
	end
	local at = text:find(": ", #K.PREFIX + 1, true)
	return text:sub(#K.PREFIX + 1, at - 1), text:sub(at + 2)
end

local function trimDot(s)
	return (s:gsub("%s+$", ""):gsub("%.$", ""))
end

function K.english(pattern, ...)
	if select("#", ...) == 0 then
		return pattern
	end
	return string.format(pattern, ...)
end

-- the stock "nothing" texts the recipient's language has a key for
local NOTHING = {["nothing"] = true, ["nothing (due to low stamina)"] = true}

-- ---------------------------------------------------------------- rarity in the stock part
-- The stock callback (index 0) writes its line with the rarity it rolled ("[Rare] fire sword", no {}); the Chaos loot
-- layer (index 1, loot.lua) may raise that rarity afterwards. Its raises come as upgrades ({name, from, to}), and at
-- the flush every stock entry shows its final rarity, wrapped in {} (the client's loot highlight) from flagRarity
-- (3 = Magic) on, as the bonus items and the pouch part are. The base server writes its own names for the ids the stock
-- roll gives (data/lib/chaos_rarity.lua legacyNames: Rare for 3, Epic for 4, Divine for 10), so a stock entry's rarity is
-- translated to the name of today ("[Rare]" of id 3 is "[Magic]"); the raises of loot.lua name today's rarities.
if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end
K.FLAG_RARITY = 3
K.RARITY_NAMES = ChaosRarity.storedNames()

-- name -> stored rarity id (today's names; `names` = a list of names whose position is the id, for a test)
function K.rarityIds(names)
	local ids = {}
	if names then
		for i, n in ipairs(names) do
			ids[n] = i
		end
		return ids
	end
	for i = 1, ChaosRarity.STORED do
		ids[ChaosRarity.list[i].name] = ChaosRarity.list[i].id
	end
	return ids
end

-- a rarity name of the stock line -> the name of today for the same id ("Rare" -> "Magic", "Epic" -> "Rare", "Exotic" ->
-- "Legendary"); a name it does not know stays
function K.stockName(name)
	for i, n in ipairs(ChaosRarity.legacyNames) do
		if n == name then
			return ChaosRarity.name(i) or name
		end
	end
	return name
end

-- one stock entry: "2x [Rare] fire sword" -> {count = "2x ", rarity = "Rare", name = "fire sword"}; an entry already
-- in {} -> {raw = the entry}
function K.parseEntry(s)
	if s:sub(1, 1) == "{" and s:sub(-1) == "}" then
		return {raw = s}
	end
	local count, rest = s:match("^(%d+x )(.*)$")
	rest = rest or s
	local rarity, name = rest:match("^%[([^%]]+)%] (.+)$")
	return {count = count or "", rarity = rarity and K.stockName(rarity), name = name or rest}
end

function K.formatEntry(e, ids, flag)
	if e.raw then
		return e.raw
	end
	local text = e.count .. (e.rarity and ("[" .. e.rarity .. "] ") or "") .. e.name
	local id = e.rarity and ids[e.rarity]
	if id and id >= (flag or K.FLAG_RARITY) then
		return "{" .. text .. "}"
	end
	return text
end

-- the stock item list with the upgrades applied and rare entries wrapped. upgrades = {{name = the item's name,
-- from = its rarity name before (nil: none), to = its rarity name now}}. Returns the list and the upgrades that match
-- no entry, as texts (they join the line as bonus items).
function K.annotate(items, upgrades, ids, flag)
	ids = ids or K.rarityIds()
	local list = {}
	for part in (items .. ", "):gmatch("(.-), ") do
		list[#list + 1] = K.parseEntry(part)
	end
	local extra = {}
	for _, u in ipairs(upgrades or {}) do
		local hit
		for _, e in ipairs(list) do
			if not e.raw and not e.upgraded and e.name == u.name and e.rarity == u.from then
				hit = e
				break
			end
		end
		if hit then
			hit.rarity, hit.upgraded = u.to, true
		else
			extra[#extra + 1] = K.formatEntry({count = "", rarity = u.to, name = u.name}, ids, flag)
		end
	end
	local out = {}
	for i, e in ipairs(list) do
		out[i] = K.formatEntry(e, ids, flag)
	end
	return table.concat(out, ", "), extra
end

-- ---------------------------------------------------------------- the corpse as it is (beta 2026-10-21)
-- The stock line is written at index 0, from the corpse the stock pass filled. The Chaos loot layer (index 1) then takes
-- items out again: the pack thinning (pace.lua: at hunting level 1000 about 24% of the items stay, 7% of the coins and
-- NPC-sellable items), arrows and throwing weapons, the waystones of low monsters; smart loot swaps a gear item for
-- another; Echoing Spoils (1.5) and the dungeon difficulty (1.7) add some. The stock list was sent as it was written, so
-- "Loot of a nightfang widow: ..." listed about four times what the corpse held (beta report 2026-10-21). Now
-- lootline.lua reads the corpse at index `settleIndex` (after all of that, before the auto seller at 2) and the line lists
-- exactly those items: entries = {{id, name, plural, article, count, stackable, rarity (stored id), rarityName, unique,
-- veiled}} in the corpse's order; one id with the same rarity, unique and veiled mark is one entry with its counts
-- added. A rarity is "[Rare] name", wrapped in {} from `flag` on (as the bonus items and the pouch part); a unique is
-- {name}; a stack of more than one is "120 gold coins", one item "a dragon ham". Returns the list of entry texts.
function K.describe(entries, flag)
	flag = flag or K.FLAG_RARITY
	local groups, byKey = {}, {}
	for _, e in ipairs(entries or {}) do
		local r = ChaosRarity.canon(e.rarity) -- an old id (6 .. 15) counts as the rarity it became
		local key = tostring(e.id or e.name) .. ":" .. r .. ":" .. (e.unique and 1 or 0) .. ":" .. (e.veiled and 1 or 0)
		local g = byKey[key]
		if not g then
			g = {e = e, rarity = r, count = 0}
			byKey[key] = g
			groups[#groups + 1] = g
		end
		g.count = g.count + math.max(1, math.floor(tonumber(e.count) or 1))
	end
	local out = {}
	for _, g in ipairs(groups) do
		local e = g.e
		local name = tostring(e.name or ("item " .. tostring(e.id)))
		local text
		if g.count > 1 then
			local plural = e.plural ~= nil and e.plural ~= "" and e.plural or name
			text = g.count .. " " .. plural
		elseif g.rarity > 0 or e.unique or not e.article or e.article == "" then
			text = name
		else
			text = e.article .. " " .. name
		end
		if e.veiled then
			text = "Veiled " .. text
		end
		local rname = g.rarity > 0 and (e.rarityName or ChaosRarity.name(g.rarity)) or nil
		if rname and not e.unique then
			text = "[" .. rname .. "] " .. text
		end
		if e.unique or (g.rarity > 0 and g.rarity >= flag) then
			text = "{" .. text .. "}"
		end
		out[#out + 1] = text
	end
	return out
end

local function join(a, b)
	local out = {}
	for _, x in ipairs(a) do
		out[#out + 1] = x
	end
	for _, x in ipairs(b) do
		out[#out + 1] = x
	end
	return out
end

-- rec = {stock = the stock line or nil, monster = the monster's name description (used without a stock line),
-- items = {entry texts of the corpse after the loot layer, K.describe} or nil (when set it is the whole list: the stock
-- items, bonus and upgrades are not read), bonus = {item texts of the Chaos loot layer}, upgrades = {rarity raises of stock items, K.annotate}, names = the
-- rarity names (default K.RARITY_NAMES), flag = the {} rarity (default K.FLAG_RARITY), pouch = the pouch line
-- ("Looted: ... (notes).", already in the owner's language) or nil}. withPouch: false for the other members of a party.
-- t: the recipient's translator (default English). Returns the line, or nil when there is nothing to say.
function K.compose(rec, withPouch, t)
	t = t or K.english
	local monster, items = K.split(rec.stock)
	monster = monster or rec.monster
	local bonus = rec.bonus or {}
	local list
	local ids = K.rarityIds(rec.names)
	if type(rec.items) == "table" then
		-- the corpse as it was after the loot layer (K.describe): the stock list, the bonus items and the rarity raises
		-- are all in it, so none of them is added again. An empty corpse keeps the stock "nothing" text (low stamina).
		if #rec.items > 0 then
			list = table.concat(rec.items, ", ")
		elseif items then
			items = trimDot(items)
			list = t(NOTHING[items] and items or "nothing")
		end
	elseif items then
		items = trimDot(items)
		local extra
		if items:sub(1, 7) ~= "nothing" then
			items, extra = K.annotate(items, rec.upgrades, ids, rec.flag)
		else
			extra = select(2, K.annotate("", rec.upgrades, ids, rec.flag))
		end
		bonus = join(extra, bonus)
		-- "nothing" (an empty corpse) and "nothing (due to low stamina)": the bonus items replace it
		if #bonus > 0 and items:sub(1, 7) == "nothing" then
			list = table.concat(bonus, ", ")
		elseif #bonus > 0 then
			list = items .. ", " .. table.concat(bonus, ", ")
		elseif NOTHING[items] then
			list = t(items)
		else
			list = items
		end
	else
		-- no stock line (or not held): the raises are bonus items
		local b = join(select(2, K.annotate("", rec.upgrades, ids, rec.flag)), bonus)
		if #b > 0 then
			list = table.concat(b, ", ")
		end
	end
	local pouch = withPouch ~= false and rec.pouch or nil
	if not list and not pouch then
		return nil
	end
	local parts = {}
	if list then
		parts[#parts + 1] = t("Loot of %s: %s", monster or t("a creature"), list) .. "."
	end
	if pouch then
		parts[#parts + 1] = trimDot(pouch) .. "."
	end
	return table.concat(parts, " ")
end

return K
