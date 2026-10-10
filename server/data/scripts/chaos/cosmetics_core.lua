-- cosmetics_core.lua: the rules of cosmetics.lua without engine calls (server/tests/cosmetics_test.lua).
-- Spell effect skins, kill effects, loot label accents and chat name colours; data in cosmetics_config.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosCosmeticsCore = ChaosCosmeticsCore or {}
local C = ChaosCosmeticsCore

C.KINDS = {spellskin = true, killfx = true, lootbeam = true, chatcolor = true}
C.SOURCES = {store = true, achievement = true}
C.SWAP_TYPES = {"fx", "missile", "vfx", "vmissile"}
C.UNLOCK_PREFIX = "cosmetic_"

-- ---------------------------------------------------------------- lookups
local indexes = setmetatable({}, {__mode = "k"})

function C.index(cfg)
	local ix = indexes[cfg]
	if ix then
		return ix
	end
	ix = {byKey = {}, byId = {}, lines = {}, lineOfSpell = {}, skinsOfLine = {}}
	for _, l in ipairs(cfg.lines or {}) do
		ix.lines[l.key] = l
		ix.skinsOfLine[l.key] = {}
	end
	for _, c in ipairs(cfg.cosmetics or {}) do
		ix.byKey[c.key] = c
		ix.byId[c.id] = c
		if c.kind == "spellskin" and ix.skinsOfLine[c.line] then
			local list = ix.skinsOfLine[c.line]
			list[#list + 1] = c
			for _, s in ipairs(c.spells or {}) do
				ix.lineOfSpell[s] = ix.lineOfSpell[s] or c.line
			end
		end
	end
	indexes[cfg] = ix
	return ix
end

function C.byKey(cfg, key)
	return C.index(cfg).byKey[key or ""]
end

function C.byId(cfg, id)
	return C.index(cfg).byId[tonumber(id) or -1]
end

function C.unlockName(c)
	return C.UNLOCK_PREFIX .. c.key
end

-- the cosmetic a store unlock name stands for (store cosmetics only)
function C.ofUnlock(cfg, unlockName)
	if type(unlockName) ~= "string" or unlockName:sub(1, #C.UNLOCK_PREFIX) ~= C.UNLOCK_PREFIX then
		return nil
	end
	local c = C.byKey(cfg, unlockName:sub(#C.UNLOCK_PREFIX + 1))
	return (c and c.source == "store") and c or nil
end

-- the storage that holds the choice of this kind (spell skins: of this line)
function C.storageOf(cfg, kind, lineKey)
	local st = cfg.storage
	if kind == "spellskin" then
		local l = C.index(cfg).lines[lineKey or ""]
		return l and (st.skinBase + l.slot) or nil
	end
	return st[kind]
end

-- the class line of a vocation name (spell skins of that line are the ones the character casts)
function C.lineOfVocation(cfg, vocationName)
	vocationName = tostring(vocationName or ""):lower()
	for _, l in ipairs(cfg.lines or {}) do
		for _, v in ipairs(l.vocations or {}) do
			if v:lower() == vocationName then
				return l.key
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------- spell skins
-- the variant of effect `name` (type "fx" | "missile" | "vfx" | "vmissile") under `skin` for spell `spellId`; nil =
-- keep the default
function C.swap(skin, spellId, kind, name)
	if type(skin) ~= "table" or skin.kind ~= "spellskin" or type(name) ~= "string" then
		return nil
	end
	local listed = false
	for _, s in ipairs(skin.spells or {}) do
		if s == spellId then
			listed = true
			break
		end
	end
	if not listed then
		return nil
	end
	local map = skin[kind]
	return type(map) == "table" and map[name] or nil
end

-- the skin a character uses for a spell: chosenIdOf(lineKey) -> the id stored for that line (or nil)
function C.skinForSpell(cfg, spellId, chosenIdOf)
	local line = C.index(cfg).lineOfSpell[tonumber(spellId) or -1]
	if not line then
		return nil
	end
	local c = C.byId(cfg, chosenIdOf(line))
	if c and c.kind == "spellskin" and c.line == line then
		return c
	end
	return nil
end

-- the effects a store / window preview of a cosmetic shows (names, in order) and their type
function C.previewOf(c)
	if not c then
		return {}
	end
	if c.kind == "killfx" then
		return {{type = "vfx", name = c.vfx}}
	elseif c.kind == "spellskin" then
		local out = {}
		for _, t in ipairs(C.SWAP_TYPES) do
			local keys = {}
			for from in pairs(c[t] or {}) do
				keys[#keys + 1] = from
			end
			table.sort(keys)
			for _, from in ipairs(keys) do
				out[#out + 1] = {type = t, name = c[t][from]}
			end
		end
		return out
	end
	return {}
end

-- ---------------------------------------------------------------- colours
local function hex(s)
	if type(s) ~= "string" then
		return nil
	end
	local r, g, b, a = s:match("^#(%x%x)(%x%x)(%x%x)(%x?%x?)$")
	if not r then
		return nil
	end
	return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), (a ~= "" and #a == 2) and tonumber(a, 16) or 255
end
C.hex = hex

local function channel(v)
	v = v / 255
	return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
end

function C.luminance(s)
	local r, g, b = hex(s)
	if not r then
		return nil
	end
	return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
end

-- WCAG contrast ratio of two colours (1 .. 21); nil for a bad colour
function C.contrast(a, b)
	local la, lb = C.luminance(a), C.luminance(b)
	if not la or not lb then
		return nil
	end
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

-- ---------------------------------------------------------------- owning and choosing
-- owned = {[key] = true}; the store cosmetics the account owns plus the achievement ones granted
function C.owns(owned, c)
	return c ~= nil and type(owned) == "table" and owned[c.key] == true
end

-- the achievement cosmetics to grant now: hasAchievement(id) -> bool
function C.syncs(cfg, hasAchievement, owned)
	local out = {}
	for _, c in ipairs(cfg.cosmetics or {}) do
		if c.source == "achievement" and not C.owns(owned, c) and hasAchievement(c.achievement) then
			out[#out + 1] = c.key
		end
	end
	return out
end

-- may this character choose cosmetic `id` of `kind` now? id 0 = back to the default. Returns the cosmetic (nil for
-- the default) or nil, reason.
function C.choose(cfg, owned, kind, id)
	if not C.KINDS[kind] then
		return nil, "Unknown cosmetic."
	end
	id = tonumber(id) or -1
	if id == 0 then
		return false
	end
	local c = C.byId(cfg, id)
	if not c or c.kind ~= kind then
		return nil, "Unknown cosmetic."
	end
	if not C.owns(owned, c) then
		if c.source == "store" then
			return nil, c.name .. " is not unlocked yet: Store > " .. C.storeCategory(cfg, c.kind) .. "."
		end
		return nil, c.name .. " is not unlocked yet."
	end
	return c
end

function C.storeCategory(cfg, kind)
	for _, k in ipairs(cfg.kinds or {}) do
		if k.key == kind then
			return k.store or k.name
		end
	end
	return "Cosmetics"
end

-- how a cosmetic is got, for the window
function C.how(c, achievementName)
	if c.source == "store" then
		return "Store: " .. tostring(c.price) .. " Chaos Coins"
	end
	return "Achievement: " .. tostring(achievementName or c.achievement)
end

-- ---------------------------------------------------------------- window rows
-- chosen = {killfx = id, lootbeam = id, chatcolor = id, lines = {[lineKey] = id}}; opts.line = the character's line;
-- opts.achievementName(id) -> name. One row per cosmetic, in config order.
function C.rows(cfg, owned, chosen, opts)
	opts = opts or {}
	chosen = chosen or {}
	local ix = C.index(cfg)
	local rows = {}
	for _, c in ipairs(cfg.cosmetics or {}) do
		local sel
		if c.kind == "spellskin" then
			sel = (chosen.lines or {})[c.line] == c.id
		else
			sel = chosen[c.kind] == c.id
		end
		local row = {id = c.id, key = c.key, kind = c.kind, name = c.name, desc = c.desc, source = c.source,
			price = c.source == "store" and c.price or nil, owned = C.owns(owned, c), selected = sel or nil,
			how = C.how(c, opts.achievementName and opts.achievementName(c.achievement) or nil),
			color = c.color, accent = c.accent}
		if c.kind == "spellskin" then
			local l = ix.lines[c.line]
			row.line = c.line
			row.lineName = l and l.name
			row.mine = opts.line == c.line or nil
		end
		if c.kind == "spellskin" or c.kind == "killfx" then
			row.preview = true
		end
		rows[#rows + 1] = row
	end
	return rows
end

-- the store offer's preview for the client: an effect (the Preview button asks the server) or a colour
function C.offerPreview(c)
	if not c then
		return nil
	end
	if c.kind == "chatcolor" then
		return {color = c.color}
	elseif c.kind == "lootbeam" then
		return {accent = c.accent}
	end
	return {effect = true}
end

-- ---------------------------------------------------------------- SQL
local function sqlKey(s)
	return (tostring(s or ""):gsub("[^%w_]", ""):sub(1, 40))
end
C.sqlKey = sqlKey

function C.sqlCreate(cfg)
	return "CREATE TABLE IF NOT EXISTS `" .. cfg.table .. "` (" ..
		"`account_id` int(11) NOT NULL, `cosmetic` varchar(40) NOT NULL, `source` varchar(16) NOT NULL DEFAULT 'store', " ..
		"`created` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`, `cosmetic`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
end

function C.sqlSelect(cfg, accountId)
	return "SELECT `cosmetic` FROM `" .. cfg.table .. "` WHERE `account_id` = " .. math.floor(tonumber(accountId) or 0)
end

function C.sqlInsert(cfg, accountId, key, source, now)
	return "INSERT IGNORE INTO `" .. cfg.table .. "` (`account_id`, `cosmetic`, `source`, `created`) VALUES (" ..
		math.floor(tonumber(accountId) or 0) .. ", '" .. sqlKey(key) .. "', '" .. sqlKey(source) .. "', " ..
		math.floor(tonumber(now) or 0) .. ")"
end

function C.sqlDelete(cfg, accountId, key)
	return "DELETE FROM `" .. cfg.table .. "` WHERE `account_id` = " .. math.floor(tonumber(accountId) or 0) ..
		" AND `cosmetic` = '" .. sqlKey(key) .. "'"
end

-- ---------------------------------------------------------------- checks
-- opts.catalog = {fx = {[name] = true}, missile = {...}, vfx = {...}, vmissile = {...}} (names the client pair has;
-- a missing type is not checked); opts.achievements = {[id] = name} (nil: not checked); opts.shop = shop_config.lua
-- (nil: not checked). Returns problems, warnings.
function C.validate(cfg, opts)
	opts = opts or {}
	local problems, warnings = {}, {}
	local function bad(fmt, ...)
		problems[#problems + 1] = string.format(fmt, ...)
	end
	local catalog = opts.catalog or {}
	-- families: members known, no name in two families of a type
	local familyOf = {}
	for _, t in ipairs(C.SWAP_TYPES) do
		familyOf[t] = {}
		for fam, members in pairs((cfg.families or {})[t] or {}) do
			if #members < 2 then
				bad("family %s.%s needs two members", t, fam)
			end
			for _, m in ipairs(members) do
				if familyOf[t][m] then
					bad("%s %s is in two families", t, m)
				end
				familyOf[t][m] = fam
				if catalog[t] and not catalog[t][m] then
					bad("family %s.%s: %s is not an effect of the client pair", t, fam, m)
				end
			end
		end
	end
	local ids, keys, spellLine, lines = {}, {}, {}, {}
	for _, l in ipairs(cfg.lines or {}) do
		if lines[l.key] then
			bad("line %s listed twice", l.key)
		end
		lines[l.key] = l
		if type(l.slot) ~= "number" or l.slot < 0 or l.slot > 6 then
			bad("line %s: slot 0..6", l.key)
		end
	end
	for i, c in ipairs(cfg.cosmetics or {}) do
		local w = "cosmetic " .. tostring(c.key or i)
		if type(c.id) ~= "number" or c.id < 1 or c.id % 1 ~= 0 then
			bad("%s: id must be a whole number above 0", w)
		elseif ids[c.id] then
			bad("%s: id %d used twice", w, c.id)
		end
		ids[c.id or -1] = true
		if type(c.key) ~= "string" or not c.key:match("^[%w_]+$") or #c.key > 40 then
			bad("%s: key letters, digits and _ only, 40 at most", w)
		elseif keys[c.key] then
			bad("%s: key used twice", w)
		end
		keys[c.key or "?"] = true
		if not C.KINDS[c.kind] then
			bad("%s: unknown kind %s", w, tostring(c.kind))
		end
		if type(c.name) ~= "string" or c.name == "" or type(c.desc) ~= "string" or c.desc == "" then
			bad("%s: name and desc needed", w)
		end
		if not C.SOURCES[c.source] then
			bad("%s: unknown source %s", w, tostring(c.source))
		elseif c.source == "store" and (type(c.price) ~= "number" or c.price <= 0) then
			bad("%s: a store cosmetic needs a price", w)
		elseif c.source == "achievement" then
			if type(c.achievement) ~= "string" then
				bad("%s: an achievement cosmetic needs the achievement id", w)
			elseif opts.achievements and not opts.achievements[c.achievement] then
				bad("%s: achievement %s does not exist", w, c.achievement)
			end
		end
		-- never power: only the fields of the kind
		for k in pairs(c) do
			if k == "damage" or k == "area" or k == "bonus" or k == "chance" or k == "stats" then
				bad("%s: field %s is not cosmetic", w, k)
			end
		end
		if c.kind == "spellskin" then
			if not lines[c.line] then
				bad("%s: unknown line %s", w, tostring(c.line))
			end
			if type(c.spells) ~= "table" or #c.spells < 1 or #c.spells > 3 then
				bad("%s: 1 to 3 spells", w)
			end
			for _, s in ipairs(c.spells or {}) do
				if spellLine[s] and spellLine[s] ~= c.line then
					bad("%s: spell %s belongs to line %s already", w, tostring(s), spellLine[s])
				end
				spellLine[s] = c.line
				if opts.spellVocations and opts.spellVocations[s] and lines[c.line] then
					local ok = false
					for _, v in ipairs(lines[c.line].vocations or {}) do
						if opts.spellVocations[s][v] then
							ok = true
						end
					end
					if not ok then
						bad("%s: spell %s is not a spell of the %s", w, tostring(s), lines[c.line].name)
					end
				elseif opts.spellVocations and not opts.spellVocations[s] then
					bad("%s: spell %s does not exist", w, tostring(s))
				end
			end
			local swaps = 0
			for _, t in ipairs(C.SWAP_TYPES) do
				for from, to in pairs(c[t] or {}) do
					swaps = swaps + 1
					local fa, fb = familyOf[t][from], familyOf[t][to]
					if not fa then
						bad("%s: %s %s is in no recolour family", w, t, tostring(from))
					elseif fa ~= fb then
						bad("%s: %s %s -> %s is not a recolour (other family)", w, t, tostring(from), tostring(to))
					elseif from == to then
						bad("%s: %s %s swapped for itself", w, t, from)
					end
				end
			end
			if swaps == 0 then
				bad("%s: no effect swapped", w)
			end
		elseif c.kind == "killfx" then
			if type(c.vfx) ~= "string" then
				bad("%s: vfx needed", w)
			elseif catalog.vfx and not catalog.vfx[c.vfx] then
				bad("%s: %s is not an effect of the client pair", w, c.vfx)
			end
		elseif c.kind == "lootbeam" then
			local r, g, b, a = hex(c.accent)
			if not r then
				bad("%s: accent #RRGGBB or #RRGGBBAA", w)
			else
				if a < 200 then
					bad("%s: accent too transparent (the labels must stay readable)", w)
				end
				for _, rc in ipairs(cfg.labelRarityColors or {}) do
					local ratio = C.contrast(rc, string.format("#%02x%02x%02x", r, g, b))
					if ratio < 3 then
						bad("%s: rarity colour %s unreadable on the accent (contrast %.2f)", w, rc, ratio)
					end
				end
			end
		elseif c.kind == "chatcolor" then
			local r = hex(c.color)
			if not r or #c.color ~= 7 then
				bad("%s: color #RRGGBB", w)
			else
				local ratio = C.contrast(c.color, cfg.consoleBackground or "#1c1a18")
				if ratio < 4.5 then
					bad("%s: %s is not readable in the console (contrast %.2f)", w, c.color, ratio)
				end
			end
		end
	end
	-- the store offers: every store cosmetic has its offer at its price; nothing else is sold as a cosmetic
	if opts.shop then
		local offers = {}
		for _, cat in ipairs(opts.shop.categories or {}) do
			for _, o in ipairs(cat.offers or {}) do
				if o.kind == "unlock" and type(o.unlock) == "string" and o.unlock:sub(1, #C.UNLOCK_PREFIX) == C.UNLOCK_PREFIX then
					if offers[o.unlock] then
						bad("offer %s listed twice", o.unlock)
					end
					offers[o.unlock] = o
				end
			end
		end
		for _, c in ipairs(cfg.cosmetics or {}) do
			local o = offers[C.unlockName(c)]
			if c.source == "store" then
				if not o then
					warnings[#warnings + 1] = "store cosmetic " .. c.key .. " has no offer in shop_config.lua"
				elseif o.cost ~= c.price then
					bad("cosmetic %s: store price %s, config price %s", c.key, tostring(o.cost), tostring(c.price))
				elseif o.name ~= c.name then
					bad("cosmetic %s: store name %s, config name %s", c.key, tostring(o.name), tostring(c.name))
				end
			elseif o then
				bad("cosmetic %s is sold in the store but its source is %s", c.key, tostring(c.source))
			end
			offers[C.unlockName(c)] = nil
		end
		for name in pairs(offers) do
			bad("offer %s names no cosmetic", name)
		end
	end
	return problems, warnings
end

return C
