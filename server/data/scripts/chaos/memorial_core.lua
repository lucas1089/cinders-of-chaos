-- The Capital Memorial: pure logic (no engine API), tested by server/tests/memorial_test.lua. Engine glue: memorial.lua;
-- numbers: memorial_config.lua. Overview: server/README.md "The Capital Memorial".
--
-- Entries (one row per character and thing remembered, table chaos_memorial_entries, per season key):
--   {kind = "first" | "record" | "fallen", key, guid, name, title, detail, level, class, at, value, ord, shown}
-- `shown` follows the character's choice (records and firsts: on unless turned off; a Hardcore fall: off unless
-- chosen), so the plaza, the client and the website read only shown rows. The plaza holds a page of each kind; with
-- more entries than statues the pages turn every `rotateSeconds`. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosMemorialCore = ChaosMemorialCore or {}
local M = ChaosMemorialCore
local floor = math.floor

-- a text in `lang` (Chaos.t keys, i18n_strings.lua); English without ChaosI18n or without a language
local function T(lang, key, ...)
	if lang and ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

M.KINDS = {"first", "record", "fallen"}
M.TEXT_MAX = 255

-- the records' season key: "s<id>" while a season runs, else the calendar quarter "q<year><q>"
function M.seasonKey(season, t)
	if type(season) == "table" and season.id then
		return "s" .. tostring(season.id)
	end
	local d = os.date("*t", t or os.time())
	return string.format("q%d%d", d.year, floor((d.month - 1) / 3) + 1)
end

function M.seasonName(key, season)
	if type(season) == "table" and season.name and key == M.seasonKey(season) then
		return season.name
	end
	local y, q = tostring(key):match("^q(%d%d%d%d)(%d)$")
	if y then
		return string.format("Q%s %s", q, y)
	end
	return tostring(key)
end

-- a character's choice: row = {records, fallen} (0/1) or nil -> {records = bool, fallen = bool}
function M.choiceOf(row, defaults)
	defaults = defaults or {records = true, fallen = false}
	if type(row) ~= "table" then
		return {records = defaults.records ~= false, fallen = defaults.fallen == true}
	end
	return {records = tonumber(row.records) ~= 0, fallen = tonumber(row.fallen) == 1}
end

function M.shownFor(kind, choice)
	if kind == "fallen" then
		return choice.fallen == true
	end
	return choice.records ~= false
end

-- ---------------------------------------------------------------- texts
function M.fmt(n)
	n = floor(tonumber(n) or 0)
	local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (n < 0 and "-" or "") .. s
end

-- a record's value as the records show it: time "m:ss" / "h:mm:ss", pct (value / 100) "12.34%", else a number
function M.formatValue(format, v)
	v = floor(tonumber(v) or 0)
	if format == "time" then
		local h, m, s = floor(v / 3600), floor(v % 3600 / 60), v % 60
		if h > 0 then
			return string.format("%d:%02d:%02d", h, m, s)
		end
		return string.format("%d:%02d", m, s)
	elseif format == "pct" then
		local whole, frac = floor(v / 100), v % 100
		return frac == 0 and string.format("%d%%", whole) or string.format("%d.%02d%%", whole, frac)
	end
	return M.fmt(v)
end

local MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
local MONTHS_PT = {"Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"}
function M.dateText(t, lang)
	local d = os.date("*t", tonumber(t) or 0)
	return string.format("%d %s %d", d.day, (lang == "pt-BR" and MONTHS_PT or MONTHS)[d.month], d.year)
end

local function cut(s, n)
	s = tostring(s or "")
	if #s <= n then
		return s
	end
	return s:sub(1, n - 3) .. "..."
end
M.cut = cut

-- "Vexa", "Vexa and Mira", "Vexa, Mira and Bryn", "Vexa, Mira and 2 others" (hidden members are counted, not named)
function M.namesText(names, hidden, lang)
	names = names or {}
	hidden = tonumber(hidden) or 0
	local list = {}
	for i = 1, math.min(#names, 4) do
		list[i] = names[i]
	end
	local others = hidden + math.max(0, #names - 4)
	if others > 0 then
		list[#list + 1] = others == 1 and T(lang, "1 other") or T(lang, "%d others", others)
	end
	if #list == 0 then
		return T(lang, "heroes who keep their names")
	end
	if #list == 1 then
		return list[1]
	end
	return table.concat(list, ", ", 1, #list - 1) .. T(lang, " and ") .. list[#list]
end

-- the look text of an item of the plaza (at most 255 characters); `lang`: the player's language (nil: English)
function M.firstText(group, seasonName, lang)
	return cut(T(lang, "A guardian statue. Realm first of %s: %s, slain by %s on %s.", seasonName, group.title,
		M.namesText(group.names, group.hidden, lang), M.dateText(group.at, lang)), M.TEXT_MAX)
end

function M.recordText(e, seasonName, lang)
	local who = e.shown and string.format("%s%s", e.name, e.class and e.class ~= "" and (", " .. e.class) or "") or
		T(lang, "a hero who keeps their name")
	return cut(T(lang, "A statue. %s record of %s: %s, %s. Set on %s.", seasonName, e.title, e.detail, who,
		M.dateText(e.at, lang)), M.TEXT_MAX)
end

function M.fallenText(e, seasonName, lang)
	return cut(T(lang, "A memorial stone. Here lies %s, a level %d %s, %s on %s. Fallen in Hardcore, %s.", e.name,
		tonumber(e.level) or 0, (e.class and e.class ~= "") and e.class or T(lang, "adventurer"),
		e.detail ~= "" and e.detail or T(lang, "fallen"), M.dateText(e.at, lang), seasonName), M.TEXT_MAX)
end

function M.stoneText(seasonName, counts, page, pages, rotateSeconds, lang)
	local firsts, records = counts.first or 0, counts.record or 0
	local text = T(lang, "The Ember Memorial, %s. %s, %s and %d of the fallen are remembered here.", seasonName,
		firsts == 1 and T(lang, "%d realm first", firsts) or T(lang, "%d realm firsts", firsts),
		records == 1 and T(lang, "%d record", records) or T(lang, "%d records", records), counts.fallen or 0)
	if (pages or 1) > 1 then
		text = text .. " " .. T(lang, "The statues turn every %d minutes (page %d of %d).", floor((rotateSeconds or 600) / 60),
			page or 1, pages)
	end
	return cut(text .. " " .. T(lang, "Past seasons: the website's Memorial page."), M.TEXT_MAX)
end

-- ---------------------------------------------------------------- building the entries
-- realm firsts: rows {target, board, name (short), at, value, guids = "1,2"} and names {guid -> {name, class, staff}}
-- -> entries, one per member (staff left out), ordered by time
function M.firstEntries(rows, people, titleOf)
	local out = {}
	table.sort(rows, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return tostring(a.target) < tostring(b.target)
	end)
	for i, r in ipairs(rows) do
		for g in tostring(r.guids or ""):gmatch("%d+") do
			local guid = tonumber(g)
			local p = people[guid]
			if p and not p.staff then
				out[#out + 1] = {kind = "first", key = tostring(r.target), guid = guid, name = p.name, class = p.class,
					title = titleOf and titleOf(r) or tostring(r.name), detail = "", level = p.level or 0, at = r.at,
					value = r.value or 0, ord = i}
			end
		end
	end
	return out
end

-- the season's best of each board and variant: rows {slot = "board|variant|size", guid, value, at, name, class, level},
-- boards {key -> {mode = "min" | "max" | "add", format, title(variant), variantRank = {variant -> n}}} in `order`
function M.recordEntries(rows, boards, order)
	local best = {}
	for _, r in ipairs(rows) do
		local b, v = tostring(r.slot):match("^([^|]+)|([^|]+)|")
		local def = b and boards[b]
		if def and def.mode ~= "add" and (tonumber(r.value) or 0) > 0 then
			local key = b .. "|" .. v
			local cur = best[key]
			local better
			if not cur then
				better = true
			elseif r.value ~= cur.value then
				better = (def.mode == "min" and r.value < cur.value) or (def.mode ~= "min" and r.value > cur.value)
			elseif r.at ~= cur.at then
				better = r.at < cur.at
			else
				better = r.guid < cur.guid
			end
			if better then
				best[key] = {board = b, variant = v, guid = r.guid, value = r.value, at = r.at, name = r.name, class = r.class,
					level = r.level}
			end
		end
	end
	local rank = {}
	for i, b in ipairs(order or {}) do
		rank[b] = i
	end
	local list = {}
	for key, e in pairs(best) do
		e.key = key
		list[#list + 1] = e
	end
	local function vrank(e)
		local vr = boards[e.board].variantRank
		return vr and vr[e.variant] or 999
	end
	table.sort(list, function(a, b)
		local ra, rb = rank[a.board] or 99, rank[b.board] or 99
		if ra ~= rb then
			return ra < rb
		end
		local va, vb = vrank(a), vrank(b)
		if va ~= vb then
			return va < vb
		end
		return a.key < b.key
	end)
	local out = {}
	for i, e in ipairs(list) do
		local def = boards[e.board]
		out[i] = {kind = "record", key = e.key, guid = e.guid, name = e.name, class = e.class, level = e.level or 0,
			title = def.title and def.title(e.variant) or e.key, detail = M.formatValue(def.format, e.value), at = e.at,
			value = e.value, ord = i}
	end
	return out
end

-- the Hardcore falls of the season: rows {guid, name, class, level (fallen), cause, at}, highest level first
function M.fallenEntries(rows)
	table.sort(rows, function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.guid < b.guid
	end)
	local out = {}
	for i, r in ipairs(rows) do
		out[i] = {kind = "fallen", key = tostring(r.guid), guid = r.guid, name = r.name, class = r.class, level = r.level,
			title = "Hardcore", detail = tostring(r.cause or ""), at = r.at, value = r.level, ord = i}
	end
	return out
end

-- shown by each character's choice; at most max[kind] entries of a kind (the firsts count by thing, not by member)
function M.applyChoices(entries, choiceOf, max)
	local keys, out = {}, {}
	for _, e in ipairs(entries) do
		e.shown = M.shownFor(e.kind, choiceOf(e.guid))
		local cap = max and max[e.kind]
		keys[e.kind] = keys[e.kind] or {n = 0, seen = {}}
		local k = keys[e.kind]
		if not k.seen[e.key] then
			k.seen[e.key] = true
			k.n = k.n + 1
		end
		if not cap or k.n <= cap then
			out[#out + 1] = e
		end
	end
	return out
end

-- ---------------------------------------------------------------- the plaza
-- the things a kind shows (shown only): firsts grouped by key {key, title, at, names, hidden}; records and fallen one by
-- one (a record whose holder keeps their name still stands, without it; a fall is only there when shown)
function M.displayList(entries, kind)
	local out = {}
	if kind == "first" then
		local byKey = {}
		for _, e in ipairs(entries) do
			if e.kind == "first" then
				local g = byKey[e.key]
				if not g then
					g = {key = e.key, title = e.title, at = e.at, names = {}, hidden = 0, ord = e.ord}
					byKey[e.key] = g
					out[#out + 1] = g
				end
				if e.shown then
					g.names[#g.names + 1] = e.name
				else
					g.hidden = g.hidden + 1
				end
			end
		end
		table.sort(out, function(a, b)
			if a.ord ~= b.ord then
				return a.ord < b.ord
			end
			return a.key < b.key
		end)
		return out
	end
	for _, e in ipairs(entries) do
		if e.kind == kind and (kind == "record" or e.shown) then
			out[#out + 1] = e
		end
	end
	table.sort(out, function(a, b)
		return (a.ord or 0) < (b.ord or 0)
	end)
	return out
end

function M.pages(n, slots)
	if (slots or 0) <= 0 then
		return 1
	end
	return math.max(1, math.ceil((n or 0) / slots))
end

function M.pageIndex(now, rotateSeconds, pages)
	if (pages or 1) <= 1 then
		return 1
	end
	return floor((tonumber(now) or 0) / math.max(60, rotateSeconds or 600)) % pages + 1
end

-- the slice of `list` on page `page` for `slots` statues
function M.page(list, slots, page)
	local out = {}
	local first = ((page or 1) - 1) * slots
	for i = 1, slots do
		out[i] = list[first + i]
	end
	return out
end

-- every item of the plaza for the time `now`: {{kind, slot (index), entry or nil, text}} plus the stone
function M.plan(cfg, entries, seasonName, now, lang)
	local out, counts, maxPages = {}, {}, 1
	local lists = {}
	for _, kind in ipairs(M.KINDS) do
		lists[kind] = M.displayList(entries, kind)
		counts[kind] = #lists[kind]
		maxPages = math.max(maxPages, M.pages(#lists[kind], #(cfg.slots[kind] or {})))
	end
	local page = M.pageIndex(now, cfg.rotateSeconds, maxPages)
	for _, kind in ipairs(M.KINDS) do
		local slots = #(cfg.slots[kind] or {})
		local pages = M.pages(#lists[kind], slots)
		local mine = ((page - 1) % pages) + 1
		local slice = M.page(lists[kind], slots, mine)
		for i = 1, slots do
			local e = slice[i]
			local text
			if e then
				text = kind == "first" and M.firstText(e, seasonName, lang) or kind == "record" and M.recordText(e, seasonName, lang) or
					M.fallenText(e, seasonName, lang)
			end
			out[#out + 1] = {kind = kind, slot = i, entry = e, text = text}
		end
	end
	out[#out + 1] = {kind = "stone", slot = 1, text = M.stoneText(seasonName, counts, page, maxPages, cfg.rotateSeconds, lang)}
	return out, page, maxPages
end

-- absolute position of a slot ({dx, dy} from the plaza's ORIGIN)
function M.slotPos(at, off)
	if type(at) ~= "table" or type(off) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(at.x or at[1]), tonumber(at.y or at[2]), tonumber(at.z or at[3])
	if not (x and y and z) then
		return nil
	end
	return {x = x + off[1], y = y + off[2], z = z}
end

-- ---------------------------------------------------------------- the client
-- the Memorial tab: the viewer's choice, whether a fall waits for an answer, and the season's shown entries
function M.payload(seasonName, choice, ask, entries)
	local out = {season = seasonName, records = choice.records, fallen = choice.fallen, ask = ask or nil,
		firsts = {}, recs = {}, falls = {}}
	for _, g in ipairs(M.displayList(entries, "first")) do
		out.firsts[#out.firsts + 1] = {t = g.title, n = M.namesText(g.names, g.hidden), at = g.at}
	end
	for _, e in ipairs(M.displayList(entries, "record")) do
		out.recs[#out.recs + 1] = {t = e.title, v = e.detail, n = e.shown and e.name or "", c = e.shown and e.class or "", at = e.at}
	end
	for _, e in ipairs(M.displayList(entries, "fallen")) do
		out.falls[#out.falls + 1] = {n = e.name, l = e.level, c = e.class, k = e.detail, at = e.at}
	end
	return out
end

-- the question after a fall (the modal window), "pt" or "en": {title, text, yes, no}
function M.ask(name, level, cause, lang)
	if lang == "pt" then
		return {title = "O Memorial das Brasas", yes = "Lembrar de mim", no = "Não",
			text = string.format("%s caiu no Hardcore no nível %d (%s).\n\nO Memorial da capital deve lembrar disso, com o " ..
				"nome, o nível, a classe, o que matou e a data? Só com o seu sim. Você pode mudar quando quiser em Aventura > " ..
				"Crônica > Memorial.", tostring(name), tonumber(level) or 0, tostring(cause or "fallen"))}
	end
	return {title = "The Ember Memorial", yes = "Remember me", no = "No",
		text = string.format("%s fell in Hardcore at level %d (%s).\n\nShould the Memorial in the capital remember it, with the " ..
			"name, level, class, what killed it and the date? Only with your yes. You can change it any time in Adventure > " ..
			"Chronicle > Memorial.", tostring(name), tonumber(level) or 0, tostring(cause or "fallen"))}
end

function M.askText(name, level, cause, lang)
	return M.ask(name, level, cause, lang).text
end

-- the line after a choice
function M.savedText(kind, lang)
	local pt = lang == "pt"
	if kind == "yes" then
		return pt and "O Memorial vai lembrar da sua queda. Você pode mudar quando quiser em Aventura > Crônica > Memorial." or
			"The Memorial will remember your fall. You can change it any time in Adventure > Chronicle > Memorial."
	elseif kind == "no" then
		return pt and "O Memorial não vai mostrar a sua queda. Você pode mudar quando quiser em Aventura > Crônica > Memorial." or
			"The Memorial will not show your fall. You can change it any time in Adventure > Chronicle > Memorial."
	end
	return pt and "Memorial: a sua escolha foi salva." or "Memorial: your choice is saved."
end

return M
