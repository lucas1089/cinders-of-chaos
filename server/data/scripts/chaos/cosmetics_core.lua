-- cosmetics_core.lua: the rules of cosmetics.lua without engine calls (server/tests/cosmetics_test.lua).
-- Spell effect skins, kill effects, loot label accents, chat name colours, footprints and outlines; data in
-- cosmetics_config.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosCosmeticsCore = ChaosCosmeticsCore or {}
local C = ChaosCosmeticsCore

C.KINDS = {spellskin = true, killfx = true, lootbeam = true, chatcolor = true, footprint = true, outline = true,
	levelfx = true, rarefx = true, emote = true}
-- the kinds that are one chaos_vfx.lua effect (`vfx`) other players see: killfx on the killed monster, levelfx on the
-- character at a level up, rarefx on the corpse of a rare drop, emote on the character after a boss kill (cosmetics.lua)
C.VFX_KINDS = {killfx = true, levelfx = true, rarefx = true, emote = true}
-- the longest line a victory emote says
C.EMOTE_MAX = 32
-- the combat cosmetics others see (O318): sold at 150-250 coins
C.COMBAT_KINDS = {levelfx = true, rarefx = true, emote = true}
-- pvp: battleground.lua / arena_season.lua grant it; boss: a rare personal drop of a boss (exclusives.lua grants it)
-- collection: granted once when the account's collection score reaches `collection` points (collection.lua)
C.SOURCES = {store = true, achievement = true, pvp = true, boss = true, pact = true, candlemarks = true, collection = true}
-- the kinds every viewer's client draws itself (client game_cosmeticfx): the art key names the client's picture
C.DRAWN = {footprint = "prints", outline = "glows"}
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
	if C.VFX_KINDS[c.kind] then
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

-- What the window's preview stage plays for a cosmetic (client game_lookpreview, the effect stage): one step per
-- swap, {type, from, to} (from = the stock effect the skin replaces, to = the skin's own), in previewOf's order; a
-- kill effect is one step with no `from`. Names only: cosmetics.lua resolves them to client ids (playSpec).
function C.playOf(c)
	if not c then
		return {}
	end
	if C.VFX_KINDS[c.kind] then
		return type(c.vfx) == "string" and {{type = "vfx", to = c.vfx}} or {}
	elseif c.kind ~= "spellskin" then
		return {}
	end
	local out = {}
	for _, t in ipairs(C.SWAP_TYPES) do
		local keys = {}
		for from in pairs(c[t] or {}) do
			keys[#keys + 1] = from
		end
		table.sort(keys)
		for _, from in ipairs(keys) do
			out[#out + 1] = {type = t, from = from, to = c[t][from]}
		end
	end
	return out
end

-- one effect of a play step for the client: {id, dx, dy, ms, m = 1 for a missile, n = "<type>_<name>" (the name of
-- its list icon, client game_cosmetics/images/fx/<n>.png)} or nil.
-- lookup(type, name) -> id or {id, dx, dy, ms} (chaos_fx.lua ChaosFx / ChaosFxMissile, chaos_vfx.lua ChaosVfx /
-- ChaosVfxMissile); a name the server does not know is left out (the window plays what it has)
function C.playSpec(stepType, name, lookup)
	if type(name) ~= "string" then
		return nil
	end
	local e = lookup(stepType, name)
	if type(e) == "number" then
		e = {id = e}
	end
	if type(e) ~= "table" or type(e.id) ~= "number" then
		return nil
	end
	local missile = stepType == "missile" or stepType == "vmissile"
	return {id = e.id, dx = e.dx or 0, dy = e.dy or 0, ms = e.ms, m = missile and 1 or nil,
		n = stepType .. "_" .. name}
end

-- the client rows' `play`: [{a = stock spec | nil, b = skin spec}] (steps whose skin effect is unknown are dropped)
function C.playRows(c, lookup)
	local out = {}
	for _, s in ipairs(C.playOf(c)) do
		local b = C.playSpec(s.type, s.to, lookup)
		if b then
			out[#out + 1] = {a = C.playSpec(s.type, s.from, lookup), b = b}
		end
	end
	return out
end

-- ---------------------------------------------------------------- combat cosmetics others see (O318)
-- Throttle: true (and `last[key]` = now) when at least `ms` passed since the key last played, else false. The tables
-- are per server and kept small by the logout, which drops a character's keys (cosmetics.lua).
function C.allowFx(last, key, now, ms)
	local before = last[key]
	if before ~= nil and now >= before and now - before < ms then
		return false
	end
	last[key] = now
	return true
end

-- true when one of the item rarities (stored ids, 0 = none) is at least `minRank` (rankOf(id) -> 0..7)
function C.hasRare(rarities, minRank, rankOf)
	for _, r in ipairs(rarities or {}) do
		if rankOf(r) >= minRank and rankOf(r) > 0 then
			return true
		end
	end
	return false
end

-- The characters that show their victory emote after a boss kill: the killer first, then the others, each once, only
-- those with an emote chosen (wears(id) -> true) and within cfg.combat.range tiles (near(id) -> true), at most
-- cfg.combat.maxPerKill. ids = candidates in order (the killer, the most damage dealer, then party members).
function C.emoteWearers(cfg, ids, wears, near)
	local out, seen = {}, {}
	local max = (cfg.combat or {}).maxPerKill or 5
	for _, id in ipairs(ids or {}) do
		if #out >= max then
			break
		end
		if not seen[id] and wears(id) and near(id) then
			out[#out + 1] = id
		end
		seen[id] = true
	end
	return out
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

-- has the account earned achievement cosmetic c? hasAchievement(id) -> bool; facts (the reward track, optional) =
-- {points = account achievement points, categories = {[category key] = true} completed by the account}
function C.earned(c, hasAchievement, facts)
	if not c or c.source ~= "achievement" then
		return false
	end
	facts = facts or {}
	if c.points then
		return (tonumber(facts.points) or 0) >= c.points
	elseif c.category then
		return type(facts.categories) == "table" and facts.categories[c.category] == true
	end
	return hasAchievement ~= nil and hasAchievement(c.achievement) == true
end

-- the achievement cosmetics to grant now (keys, config order). Only adds: what the account owns stays owned.
function C.syncs(cfg, hasAchievement, owned, facts)
	local out = {}
	for _, c in ipairs(cfg.cosmetics or {}) do
		if c.source == "achievement" and not C.owns(owned, c) and C.earned(c, hasAchievement, facts) then
			out[#out + 1] = c.key
		end
	end
	return out
end

-- ---------------------------------------------------------------- the reward track (achievements window)
-- the point milestones, lowest first: [{points, cosmetic}]
function C.trackSteps(cfg)
	local out = {}
	for _, c in ipairs(cfg.cosmetics or {}) do
		if c.source == "achievement" and c.points then
			out[#out + 1] = {points = c.points, cosmetic = c}
		end
	end
	table.sort(out, function(a, b) return a.points < b.points end)
	return out
end

-- the cosmetic of a category's completion, or nil
function C.categoryCosmetic(cfg, catKey)
	for _, c in ipairs(cfg.cosmetics or {}) do
		if c.source == "achievement" and c.category == catKey then
			return c
		end
	end
	return nil
end

-- what the achievements window shows (short keys, one message): points = the account's achievement points;
-- categoryTrack = ChaosAchievementsCore.categoryTrack(index, account ids). Per cosmetic: n name, k kind, d desc, c colour,
-- a accent, o 1 = owned. steps: p points. cats: key, cn category name, dn done, t total, ti title, x 1 = complete.
function C.trackView(cfg, points, owned, categoryTrack)
	points = math.floor(tonumber(points) or 0)
	local function entry(c, into)
		into.n, into.k, into.d, into.c, into.a = c.name, c.kind, c.desc, c.color, c.accent
		into.o = C.owns(owned, c) and 1 or nil
		return into
	end
	local view = {ap = points, steps = {}, cats = {}}
	for _, s in ipairs(C.trackSteps(cfg)) do
		view.steps[#view.steps + 1] = entry(s.cosmetic, {p = s.points})
	end
	for _, t in ipairs(categoryTrack or {}) do
		local e = {key = t.key, cn = t.name, dn = t.done, t = t.total, ti = t.title, x = t.complete and 1 or nil}
		local c = C.categoryCosmetic(cfg, t.key)
		if c then
			entry(c, e)
		end
		view.cats[#view.cats + 1] = e
	end
	return view
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
function C.how(c, achievementName, categoryName)
	if c.source == "store" then
		return "Store: " .. tostring(c.price) .. " Chaos Coins"
	elseif c.source == "pvp" then
		return "PvP: " .. tostring(c.pvp or "battleground")
	elseif c.source == "boss" then
		return "Boss: " .. tostring(c.boss or "a boss")
	elseif c.source == "pact" then
		return "Chaos Pact: " .. tostring(c.pact or "while subscribed")
	elseif c.source == "candlemarks" then
		return "Candlemarks: Osric the Chandler, in the teleport room's market"
	elseif c.source == "collection" then
		return "Collection score: " .. tostring(c.collection) .. " points"
	elseif c.points then
		return "Achievements: " .. tostring(c.points) .. " account points"
	elseif c.category then
		return "Achievements: complete " .. tostring(categoryName or c.category)
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
			how = C.how(c, opts.achievementName and c.achievement and opts.achievementName(c.achievement) or nil,
				opts.categoryName and c.category and opts.categoryName(c.category) or nil),
			color = c.color, accent = c.accent}
		if c.kind == "spellskin" then
			local l = ix.lines[c.line]
			row.line = c.line
			row.lineName = l and l.name
			row.mine = opts.line == c.line or nil
		end
		if c.kind == "spellskin" or C.VFX_KINDS[c.kind] then
			row.preview = true
		elseif C.DRAWN[c.kind] then
			-- footprints and outlines: the client draws the preview itself (game_cosmeticfx), no server effect
			row.art, row.pulse, row.preview = c.art, c.pulse or nil, true
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
	elseif C.DRAWN[c.kind] then
		-- the SHOW button: the buyer's own client draws it on the buyer for a few seconds (cosmetics.lua "tryfx")
		return {effect = true, color = c.color}
	end
	return {effect = true}
end

-- What the store shows for a cosmetic unlock "cosmetic_<key>": its own appearance, in the shape of the client's look
-- options (client game_lookpreview LookPreviewCore), used for the offer's icon and the preview beside the list:
--   outline    {kind = "outline", art, pulse?, color?}            footprint {kind = "footprint", art, color?}
--   spell skin / kill effect  {kind = "effects", play, killfx?}   (play: playRows, the effects themselves)
--   chat colour / loot label  {kind = "swatch", color, accent?}   (a sample of the colour; nothing to wear)
--   outfit shader             {kind = "shader", shader}
-- nil for an unknown unlock. lookup(type, name) is the one of C.playRows.
function C.offerLook(cfg, unlockName, lookup)
	local c = C.ofUnlock(cfg, unlockName)
	if c then
		if c.kind == "outline" then
			return {kind = "outline", art = c.art, pulse = c.pulse or nil, color = c.color}
		elseif c.kind == "footprint" then
			return {kind = "footprint", art = c.art, color = c.color}
		elseif c.kind == "spellskin" or C.VFX_KINDS[c.kind] then
			local play = lookup and C.playRows(c, lookup) or {}
			if #play > 0 then
				-- a kill effect and a rare-loot effect play on a troll that dies; the others on the figure
				return {kind = "effects", play = play, killfx = (c.kind == "killfx" or c.kind == "rarefx") or nil}
			end
		elseif c.kind == "chatcolor" then
			return c.color and {kind = "swatch", color = c.color} or nil
		elseif c.kind == "lootbeam" then
			return c.accent and {kind = "swatch", color = c.accent, accent = true} or nil
		end
		return nil
	end
	local s = C.outfitShaderOfUnlock(cfg, unlockName)
	if s and type(s.shader) == "string" then
		return {kind = "shader", shader = s.shader}
	end
	return nil
end

-- ---------------------------------------------------------------- Chaos outfit shaders (cfg.outfitShaders)
-- Engine outfit shaders unlocked like a cosmetic (account-wide, table chaos_cosmetics, key "cosmetic_<key>") and
-- worn through the Outfit window (Player:addShader). Behind cfg.outfitShaders.enabled: while it is false they are not
-- listed, granted, sold or added to characters.
function C.outfitShadersOn(cfg)
	return type(cfg.outfitShaders) == "table" and cfg.outfitShaders.enabled == true
end

-- the entries while the switch is on (else an empty list)
function C.outfitShaderList(cfg)
	if not C.outfitShadersOn(cfg) then
		return {}
	end
	return cfg.outfitShaders.list or {}
end

function C.outfitShaderByKey(cfg, key)
	for _, s in ipairs(C.outfitShaderList(cfg)) do
		if s.key == key then
			return s
		end
	end
	return nil
end

-- a store unlock "cosmetic_<key>" of a priced outfit shader (nil while off or unpriced)
function C.outfitShaderOfUnlock(cfg, unlockName)
	if type(unlockName) ~= "string" or unlockName:sub(1, #C.UNLOCK_PREFIX) ~= C.UNLOCK_PREFIX then
		return nil
	end
	local s = C.outfitShaderByKey(cfg, unlockName:sub(#C.UNLOCK_PREFIX + 1))
	return (s and type(s.price) == "number" and s.price > 0) and s or nil
end

-- the shaders.xml ids the account owns (owned = {[key] = true}), for Player:addShader on each character
function C.outfitShaderIds(cfg, owned)
	local out = {}
	for _, s in ipairs(C.outfitShaderList(cfg)) do
		if type(owned) == "table" and owned[s.key] then
			out[#out + 1] = s.shaderId
		end
	end
	return out
end

-- rows of the window's Collection tab, in the format of exclusives_core.lua K.rows (client game_cosmetics shows a
-- kind "shader" row on the character's own outfit): {key, kind, kindName, name, desc, how, use, owned, source, with,
-- shader, icon (server item id; cosmetics.lua turns it into the client id)}
function C.outfitShaderRows(cfg, owned)
	local rows = {}
	for _, s in ipairs(C.outfitShaderList(cfg)) do
		rows[#rows + 1] = {key = s.key, kind = "shader", kindName = "Outfit Shader", name = s.name, desc = s.desc,
			how = s.price and ("Store: " .. tostring(s.price) .. " Chaos Coins") or "Store: not on sale yet",
			use = "Choose it in the Outfit window.", owned = (type(owned) == "table" and owned[s.key] == true) or nil,
			source = "store", with = "shader", shader = s.shader, icon = s.icon}
	end
	return rows
end

-- problems of cfg.outfitShaders (checked whether the switch is on or off): keys, ids, names, prices, colours
function C.validateOutfitShaders(cfg, opts)
	opts = opts or {}
	local problems = {}
	local function bad(fmt, ...)
		problems[#problems + 1] = string.format(fmt, ...)
	end
	local block = cfg.outfitShaders
	if block == nil then
		return problems
	end
	if type(block) ~= "table" or type(block.enabled) ~= "boolean" or type(block.list) ~= "table" then
		bad("outfitShaders: {enabled = true / false, list = {...}}")
		return problems
	end
	local cosmeticKeys = {}
	for _, c in ipairs(cfg.cosmetics or {}) do
		cosmeticKeys[c.key or ""] = true
	end
	local keys, ids, names = {}, {}, {}
	for i, s in ipairs(block.list) do
		local w = "outfit shader " .. tostring(s.key or i)
		if type(s.key) ~= "string" or not s.key:match("^[%w_]+$") or #s.key > 40 then
			bad("%s: key letters, digits and _ only, 40 at most", w)
		elseif keys[s.key] or cosmeticKeys[s.key] then
			bad("%s: key used twice", w)
		end
		keys[s.key or "?"] = true
		-- ids 1-18 are the base server's shaders and the exclusives' (shaders.xml); the engine keeps 1-255 in storages
		if type(s.shaderId) ~= "number" or s.shaderId % 1 ~= 0 or s.shaderId < 19 or s.shaderId > 255 then
			bad("%s: shaderId a whole number 19..255", w)
		elseif ids[s.shaderId] or (opts.takenShaderIds and opts.takenShaderIds[s.shaderId]) then
			bad("%s: shaderId %d used twice", w, s.shaderId)
		end
		ids[s.shaderId or -1] = true
		if type(s.shader) ~= "string" or not s.shader:match("^chaos_[a-z_]+$") then
			bad("%s: shader name chaos_<letters and _>", w)
		elseif names[s.shader] then
			bad("%s: shader %s used twice", w, s.shader)
		elseif opts.clientShaders and not opts.clientShaders[s.shader] then
			bad("%s: shader %s is not registered by the client (game_chaosshaders)", w, s.shader)
		end
		names[s.shader or "?"] = true
		if type(s.name) ~= "string" or s.name == "" or type(s.desc) ~= "string" or s.desc == "" then
			bad("%s: name and desc needed", w)
		end
		if s.price ~= nil and (type(s.price) ~= "number" or s.price <= 0 or s.price % 1 ~= 0) then
			bad("%s: price a whole number above 0, or none (not on sale)", w)
		end
		if not hex(s.color) or #s.color ~= 7 then
			bad("%s: color #RRGGBB (the window's swatch)", w)
		end
		if type(s.icon) ~= "number" then
			bad("%s: icon (a server item id)", w)
		end
		for k in pairs(s) do
			if k == "damage" or k == "area" or k == "bonus" or k == "chance" or k == "stats" then
				bad("%s: field %s is not cosmetic", w, k)
			end
		end
	end
	return problems
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
-- (nil: not checked); opts.categories = {[category key] = true} and opts.maxPoints (the reward track; nil: not
-- checked). Returns problems, warnings.
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
	local trackPoints, trackCats = {}, {} -- the reward track: milestones and categories taken
	local arts = {} -- "kind:art" -> cosmetic key (footprints and outlines)
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
			local ways = (c.achievement ~= nil and 1 or 0) + (c.points ~= nil and 1 or 0) + (c.category ~= nil and 1 or 0)
			if ways ~= 1 then
				bad("%s: an achievement cosmetic needs one of achievement, points or category", w)
			elseif c.points ~= nil then
				-- the reward track: a whole number of account points, one cosmetic per milestone, reachable
				if type(c.points) ~= "number" or c.points < 1 or c.points % 1 ~= 0 then
					bad("%s: points must be a whole number above 0", w)
				elseif trackPoints[c.points] then
					bad("%s: milestone %d used twice", w, c.points)
				elseif opts.maxPoints and c.points > opts.maxPoints then
					bad("%s: milestone %d is above the %d achievement points that exist", w, c.points, opts.maxPoints)
				end
				trackPoints[c.points or -1] = true
			elseif c.category ~= nil then
				if type(c.category) ~= "string" then
					bad("%s: category must be a category key", w)
				elseif trackCats[c.category] then
					bad("%s: category %s rewarded twice", w, c.category)
				elseif opts.categories and not opts.categories[c.category] then
					bad("%s: category %s does not exist", w, c.category)
				end
				trackCats[c.category] = true
			elseif type(c.achievement) ~= "string" then
				bad("%s: an achievement cosmetic needs the achievement id", w)
			elseif opts.achievements and not opts.achievements[c.achievement] then
				bad("%s: achievement %s does not exist", w, c.achievement)
			end
			if c.price ~= nil then
				bad("%s: an achievement cosmetic has no price (never sold)", w)
			end
		elseif c.source == "pact" then
			-- the Chaos Pact's perks (pact_perks.lua): granted, never sold
			if c.price ~= nil then
				bad("%s: a pact cosmetic has no price (never sold)", w)
			end
		elseif c.source == "candlemarks" then
			-- bought for Candlemarks at Osric the Chandler (candlemarks_config.lua offers, kind "cosmetic"), never for coins
			if c.price ~= nil then
				bad("%s: a Candlemark cosmetic has no Chaos Coin price (candlemarks_config.lua prices it)", w)
			end
		elseif c.source == "collection" then
			-- a collection score reward (collection_config.lua milestones; collection_test.lua checks the link)
			if type(c.collection) ~= "number" or c.collection < 1 or c.collection % 1 ~= 0 then
				bad("%s: a collection cosmetic needs the whole number of points it is granted at (collection)", w)
			end
			if c.price ~= nil then
				bad("%s: a collection cosmetic has no price (never sold)", w)
			end
		elseif c.source == "boss" then
			-- a rare personal drop (exclusives_config.lua names it in one boss group; exclusives_test.lua checks that)
			if type(c.boss) ~= "string" or c.boss == "" then
				bad("%s: a boss cosmetic needs the boss's name (boss)", w)
			end
			if c.price ~= nil then
				bad("%s: a boss cosmetic has no price (never sold)", w)
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
		elseif C.VFX_KINDS[c.kind] then
			if type(c.vfx) ~= "string" then
				bad("%s: vfx needed", w)
			elseif catalog.vfx and not catalog.vfx[c.vfx] then
				bad("%s: %s is not an effect of the client pair", w, c.vfx)
			end
			if c.kind == "emote" then
				if type(c.say) ~= "string" or c.say == "" or #c.say > C.EMOTE_MAX or c.say:find("[%c|]") then
					bad("%s: say is a line of 1 to %d characters", w, C.EMOTE_MAX)
				end
			elseif c.say ~= nil then
				bad("%s: say is only for emotes", w)
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
			end		elseif C.DRAWN[c.kind] then
			-- footprints and outlines: an art key of the client's pictures (cfg.prints / cfg.glows), one per cosmetic
			local list = cfg[C.DRAWN[c.kind]] or {}
			local known = false
			for _, a in ipairs(list) do
				known = known or a == c.art
			end
			if type(c.art) ~= "string" or not known then
				bad("%s: art %s is not in cfg.%s", w, tostring(c.art), C.DRAWN[c.kind])
			elseif arts[c.kind .. ":" .. c.art] then
				bad("%s: art %s used by %s too", w, c.art, arts[c.kind .. ":" .. c.art])
			end
			arts[c.kind .. ":" .. tostring(c.art)] = c.key
			if not hex(c.color) or #c.color ~= 7 then
				bad("%s: color #RRGGBB (the window's swatch)", w)
			end
			if c.pulse ~= nil and (c.kind ~= "outline" or type(c.pulse) ~= "boolean") then
				bad("%s: pulse is true / false and only for outlines", w)
			end
		end
	end
	for _, p in ipairs(C.validateOutfitShaders(cfg, opts)) do
		problems[#problems + 1] = p
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
		-- outfit shaders: an offer only for a priced one while the switch is on, at its price
		for _, s in ipairs((type(cfg.outfitShaders) == "table" and cfg.outfitShaders.list) or {}) do
			local name = C.UNLOCK_PREFIX .. tostring(s.key)
			local o = offers[name]
			if o then
				if not C.outfitShadersOn(cfg) then
					bad("outfit shader %s is sold while outfitShaders is off", tostring(s.key))
				elseif type(s.price) ~= "number" then
					bad("outfit shader %s is sold but has no price", tostring(s.key))
				elseif o.cost ~= s.price then
					bad("outfit shader %s: store price %s, config price %s", tostring(s.key), tostring(o.cost), tostring(s.price))
				end
			end
			offers[name] = nil
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
