-- exclusives_core.lua: the rules of exclusives.lua without engine calls (server/tests/exclusives_test.lua).
-- Data: exclusives_config.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   K.index(cfg)                         {byKey, kinds, groupOfKill, groupOf (exclusive key -> boss group)}
--   K.byKey(cfg, key) / K.kind(cfg, k)    an exclusive / the window's kind entry
--   K.worldBossKill(cfg, bossName)        "wb_<boss>" of a world boss's name (nil: unknown)
--   K.groupForKill(cfg, killKey)          the boss group a kill rolls (nil: none)
--   K.roll(group, owned, rng)             the personal roll of one eligible player: key or nil, why
--   K.achievementOf(data, key)            the achievement (achievements_data.lua) whose reward.exclusives names it
--   K.syncs(cfg, data, hasAchievement, owned)   achievement exclusives the account earned and does not own (keys)
--   K.how(cfg, e, data)                   "Achievement: <name>" / "Boss: <group name>"
--   K.rows(cfg, owned, data, opts)        the wardrobe's Collection rows
--   K.rewardName(cfg, e)                  the name an achievement reward shows ("wings Cinder Plumes")
--   K.validate(cfg, opts)                 problems (see the function)
--   K.sqlCreate / sqlSelect / sqlInsert / sqlDelete

ChaosExclusivesCore = ChaosExclusivesCore or {}
local K = ChaosExclusivesCore

K.KINDS = {outfit = true, addons = true, mount = true, wings = true, aura = true, shader = true, frame = true,
	portal = true, transmog = true, pet = true, cosmetic = true}
K.SOURCES = {achievement = true, boss = true}
-- the fields each kind needs: number, string
local FIELDS = {
	outfit = {n = {"male", "female"}}, addons = {n = {"male", "female"}}, mount = {n = {"id", "look"}},
	wings = {n = {"id", "look"}}, aura = {n = {"id", "look"}}, shader = {n = {"id"}, s = {"shader"}},
	frame = {s = {"frame"}}, portal = {s = {"style"}}, transmog = {s = {"set"}}, pet = {s = {"species"}},
	cosmetic = {s = {"cosmetic"}}
}
K.MAX_CHANCE = 0.25 -- a boss drop stays rare

-- ---------------------------------------------------------------- lookups
local indexes = setmetatable({}, {__mode = "k"})

function K.index(cfg)
	local ix = indexes[cfg]
	if ix then
		return ix
	end
	ix = {byKey = {}, kinds = {}, groupOfKill = {}, groupOf = {}}
	for _, k in ipairs(cfg.kinds or {}) do
		ix.kinds[k.key] = k
	end
	for _, e in ipairs(cfg.exclusives or {}) do
		ix.byKey[e.key] = e
	end
	for _, g in ipairs(cfg.bosses or {}) do
		for _, kill in ipairs(g.kills or {}) do
			ix.groupOfKill[kill] = ix.groupOfKill[kill] or g
		end
		for _, key in ipairs(g.rewards or {}) do
			ix.groupOf[key] = ix.groupOf[key] or g
		end
	end
	indexes[cfg] = ix
	return ix
end

function K.byKey(cfg, key)
	return K.index(cfg).byKey[key or ""]
end

function K.kind(cfg, kind)
	return K.index(cfg).kinds[kind or ""]
end

function K.worldBossKill(cfg, bossName)
	local lname = tostring(bossName or ""):lower()
	local keys = {}
	for part in pairs(cfg.worldBosses or {}) do
		keys[#keys + 1] = part
	end
	table.sort(keys)
	for _, part in ipairs(keys) do
		if lname:find(part, 1, true) then
			return cfg.worldBosses[part]
		end
	end
	return nil
end

function K.groupForKill(cfg, killKey)
	return K.index(cfg).groupOfKill[killKey or ""]
end

-- ---------------------------------------------------------------- the drop roll
-- group = a boss group; owned = {[key] = true} of the account; rng() -> [0, 1) (math.random). One roll for the chance,
-- then one for the pick among the rewards the account does not own (config order). Returns key or nil, why
-- ("miss" | "owned": the account has every reward of the group | "none": no group).
function K.roll(group, owned, rng)
	if type(group) ~= "table" then
		return nil, "none"
	end
	rng = rng or math.random
	owned = owned or {}
	local chance = tonumber(group.chance) or 0
	if rng() >= chance then
		return nil, "miss"
	end
	local left = {}
	for _, key in ipairs(group.rewards or {}) do
		if not owned[key] then
			left[#left + 1] = key
		end
	end
	if #left == 0 then
		return nil, "owned"
	end
	local i = math.floor(rng() * #left) + 1
	if i > #left then
		i = #left
	end
	return left[i]
end

-- ---------------------------------------------------------------- achievements
-- the achievement whose reward.exclusives names `key` (the first; validate refuses two)
function K.achievementOf(data, key)
	for _, a in ipairs(data and data.list or {}) do
		for _, r in ipairs(type(a.reward) == "table" and a.reward.exclusives or {}) do
			if type(r) == "table" and r.key == key then
				return a
			end
		end
	end
	return nil
end

-- achievement exclusives earned and not owned yet (config order); hasAchievement(id) -> bool (account-wide)
function K.syncs(cfg, data, hasAchievement, owned)
	local out = {}
	owned = owned or {}
	for _, e in ipairs(cfg.exclusives or {}) do
		if e.source == "achievement" and not owned[e.key] then
			local a = K.achievementOf(data, e.key)
			if a and hasAchievement and hasAchievement(a.id) == true then
				out[#out + 1] = e.key
			end
		end
	end
	return out
end

function K.rewardName(cfg, e)
	local k = K.kind(cfg, e.kind)
	return (k and k.name:lower() or e.kind) .. " " .. e.name
end

-- ---------------------------------------------------------------- the window
function K.how(cfg, e, data, owned)
	if e.source == "boss" then
		local g = K.index(cfg).groupOf[e.key]
		return "Boss: " .. (g and g.name or "a boss") .. ", rare drop"
	end
	local a = K.achievementOf(data, e.key)
	if not a then
		return "Achievement"
	end
	if a.hidden and not owned then
		return "Achievement: ??? (a secret)"
	end
	return "Achievement: " .. a.name .. " (" .. (a.desc or "") .. ")"
end

-- owned = {[key] = true}; opts.clientItem(serverId) -> client id (nil: none). One row per exclusive, config order:
-- {key, kind, kindName, name, desc, how, use, owned, item, look (an outfit look type to show), source}
function K.rows(cfg, owned, data, opts)
	opts = opts or {}
	owned = owned or {}
	local rows = {}
	for _, e in ipairs(cfg.exclusives or {}) do
		local k = K.kind(cfg, e.kind) or {}
		local own = owned[e.key] == true
		local row = {key = e.key, kind = e.kind, kindName = k.name or e.kind, name = e.name, desc = e.desc,
			how = K.how(cfg, e, data, own), use = k.use, owned = own or nil, source = e.source}
		if opts.clientItem and e.icon then
			row.item = opts.clientItem(e.icon)
		end
		if e.kind == "outfit" or e.kind == "addons" then
			row.look = opts.female and e.female or e.male
			row.addons = 3
		elseif e.kind == "mount" or e.kind == "wings" or e.kind == "aura" then
			row.look = e.look
		end
		if e.kind == "wings" or e.kind == "aura" or e.kind == "shader" then
			row.with = e.kind -- the client shows it on the character's own outfit
			row.shader = e.shader
		end
		rows[#rows + 1] = row
	end
	return rows
end

-- ---------------------------------------------------------------- checks
-- opts (each optional; nil = not checked):
--   achievements  achievements_data.lua: every achievement exclusive named by exactly one reward, with the right name;
--                 every reward.exclusives entry is an achievement exclusive
--   shop          shop_config.lua: nothing of here is sold (outfit / addons looks, mount, wings, aura, shader ids, frames,
--                 portal / transmog unlocks, pet store keys)
--   storeLooks    {looks = {[look] = true}, mounts = {[id] = true}} of shop_cosmetics.lua (the generated list)
--   cosmetics     cosmetics_config.lua (kind cosmetic: source "boss" there)
--   transmog      transmog_config.lua (kind transmog: source "boss" there)
--   pets          pets_config.lua (kind pet: source.boss there)
--   portal        townportal_config.lua (kind portal: route "boss" there)
--   frames        {[frame] = true} the frames the client has (nameplate_core.lua N.FRAMES)
function K.validate(cfg, opts)
	opts = opts or {}
	local problems = {}
	local function bad(fmt, ...)
		problems[#problems + 1] = string.format(fmt, ...)
	end
	local keys, ids = {}, {}
	local inGroups = {}
	for _, g in ipairs(cfg.bosses or {}) do
		local w = "boss group " .. tostring(g.key)
		if type(g.name) ~= "string" or g.name == "" then
			bad("%s: name needed", w)
		end
		if type(g.chance) ~= "number" or g.chance <= 0 or g.chance > K.MAX_CHANCE then
			bad("%s: chance must be above 0 and at most %s", w, tostring(K.MAX_CHANCE))
		end
		if type(g.kills) ~= "table" or #g.kills == 0 then
			bad("%s: kills needed", w)
		end
		if type(g.rewards) ~= "table" or #g.rewards == 0 then
			bad("%s: rewards needed", w)
		end
		for _, kill in ipairs(g.kills or {}) do
			local other = K.index(cfg).groupOfKill[kill]
			if other ~= g then
				bad("%s: kill %s is rolled by group %s too", w, tostring(kill), tostring(other and other.key))
			end
		end
		for _, key in ipairs(g.rewards or {}) do
			if inGroups[key] then
				bad("%s: %s is a reward of group %s too", w, key, inGroups[key])
			end
			inGroups[key] = g.key
		end
	end
	for i, e in ipairs(cfg.exclusives or {}) do
		local w = "exclusive " .. tostring(e.key or i)
		if type(e.key) ~= "string" or not e.key:match("^[%w_]+$") or #e.key > 40 then
			bad("%s: key letters, digits and _ only, 40 at most", w)
		elseif keys[e.key] then
			bad("%s: key used twice", w)
		end
		keys[e.key or "?"] = true
		if not K.KINDS[e.kind] then
			bad("%s: unknown kind %s", w, tostring(e.kind))
		elseif not K.kind(cfg, e.kind) then
			bad("%s: kind %s has no window entry (cfg.kinds)", w, e.kind)
		end
		if type(e.name) ~= "string" or e.name == "" or type(e.desc) ~= "string" or e.desc == "" then
			bad("%s: name and desc needed", w)
		end
		if type(e.icon) ~= "number" then
			bad("%s: icon (a server item id) needed", w)
		end
		for k in pairs(e) do
			if k == "price" or k == "cost" or k == "damage" or k == "bonus" or k == "stats" then
				bad("%s: field %s does not belong to an exclusive (never sold, never power)", w, k)
			end
		end
		local f = FIELDS[e.kind] or {}
		for _, k in ipairs(f.n or {}) do
			if type(e[k]) ~= "number" or e[k] < 1 or e[k] % 1 ~= 0 then
				bad("%s: %s must be a whole number above 0", w, k)
			end
		end
		for _, k in ipairs(f.s or {}) do
			if type(e[k]) ~= "string" or e[k] == "" then
				bad("%s: %s needed", w, k)
			end
		end
		-- one id per kind (two exclusives never give the same mount / wings / aura / shader / look)
		local idKey
		if e.kind == "mount" or e.kind == "wings" or e.kind == "aura" or e.kind == "shader" then
			idKey = e.kind .. ":" .. tostring(e.id)
		elseif e.kind == "outfit" or e.kind == "addons" then
			idKey = "look:" .. tostring(e.male)
		elseif f.s then
			idKey = e.kind .. ":" .. tostring(e[f.s[1]])
		end
		if idKey then
			if ids[idKey] then
				bad("%s: %s is given by %s too", w, idKey, ids[idKey])
			end
			ids[idKey] = e.key
		end
		if not K.SOURCES[e.source] then
			bad("%s: source must be achievement or boss", w)
		elseif e.source == "boss" and not inGroups[e.key] then
			bad("%s: a boss exclusive needs a boss group that drops it", w)
		elseif e.source == "achievement" and inGroups[e.key] then
			bad("%s: an achievement exclusive is not a boss drop", w)
		end
	end
	for key, g in pairs(inGroups) do
		local e = K.byKey(cfg, key)
		if not e then
			bad("boss group %s: reward %s is no exclusive", g, key)
		elseif e.source ~= "boss" then
			bad("boss group %s: reward %s is not a boss exclusive", g, key)
		end
	end
	-- achievements: each achievement exclusive named by exactly one achievement, with the right name
	if opts.achievements then
		local named = {}
		for _, a in ipairs(opts.achievements.list or {}) do
			for _, r in ipairs(type(a.reward) == "table" and a.reward.exclusives or {}) do
				local e = type(r) == "table" and K.byKey(cfg, r.key) or nil
				if not e then
					bad("achievement %s: reward exclusive %s does not exist", tostring(a.id), tostring(type(r) == "table" and r.key or r))
				else
					if e.source ~= "achievement" then
						bad("achievement %s: %s is not an achievement exclusive", tostring(a.id), e.key)
					end
					if r.name ~= K.rewardName(cfg, e) then
						bad("achievement %s: reward name of %s must be %s", tostring(a.id), e.key, K.rewardName(cfg, e))
					end
					named[e.key] = (named[e.key] or 0) + 1
				end
			end
		end
		for _, e in ipairs(cfg.exclusives or {}) do
			if e.source == "achievement" and (named[e.key] or 0) ~= 1 then
				bad("exclusive %s: needs exactly one achievement with it in reward.exclusives, has %d", e.key, named[e.key] or 0)
			end
		end
	end
	-- never sold
	if opts.shop then
		local sold = {looks = {}, mount = {}, wings = {}, aura = {}, shader = {}, frame = {}, unlock = {}}
		for _, cat in ipairs(opts.shop.categories or {}) do
			for _, o in ipairs(cat.offers or {}) do
				if o.kind == "outfit" or o.kind == "addons" then
					sold.looks[o.looktype or -1] = true
					sold.looks[o.lookfemale or -1] = true
				elseif sold[o.kind] and o.id then
					sold[o.kind][o.id] = true
				elseif o.kind == "frame" then
					sold.frame[o.frame or ""] = true
				elseif o.kind == "unlock" and type(o.unlock) == "string" then
					sold.unlock[o.unlock] = true
				end
			end
		end
		local storeLooks = opts.storeLooks or {}
		for _, e in ipairs(cfg.exclusives or {}) do
			local hit
			if e.kind == "outfit" or e.kind == "addons" then
				hit = sold.looks[e.male] or sold.looks[e.female] or (storeLooks.looks or {})[e.male] or
					(storeLooks.looks or {})[e.female]
			elseif e.kind == "mount" then
				hit = sold.mount[e.id] or (storeLooks.mounts or {})[e.id]
			elseif e.kind == "wings" or e.kind == "aura" or e.kind == "shader" then
				hit = sold[e.kind][e.id]
			elseif e.kind == "frame" then
				hit = sold.frame[e.frame]
			elseif e.kind == "portal" then
				hit = sold.unlock["portal_" .. tostring(e.style)]
			elseif e.kind == "transmog" then
				hit = sold.unlock["transmog_" .. tostring(e.set)]
			elseif e.kind == "cosmetic" then
				hit = sold.unlock["cosmetic_" .. tostring(e.cosmetic)]
			end
			if hit then
				bad("exclusive %s is sold in the store", e.key)
			end
		end
	end
	-- the other catalogues
	for _, e in ipairs(cfg.exclusives or {}) do
		if e.kind == "cosmetic" and opts.cosmetics then
			local found
			for _, c in ipairs(opts.cosmetics.cosmetics or {}) do
				if c.key == e.cosmetic then
					found = c
				end
			end
			if not found then
				bad("exclusive %s: cosmetic %s does not exist", e.key, tostring(e.cosmetic))
			elseif found.source ~= e.source then
				bad("exclusive %s: cosmetic %s has source %s, not %s", e.key, found.key, tostring(found.source), e.source)
			elseif found.name ~= e.name then
				bad("exclusive %s: name must be the cosmetic's (%s)", e.key, tostring(found.name))
			end
		elseif e.kind == "transmog" and opts.transmog then
			local found
			for _, s in ipairs(opts.transmog.sets or {}) do
				if s.key == e.set then
					found = s
				end
			end
			if not found or found.source ~= "boss" then
				bad("exclusive %s: transmog set %s must exist with source boss", e.key, tostring(e.set))
			elseif found.name ~= e.name then
				bad("exclusive %s: name must be the set's (%s)", e.key, tostring(found.name))
			end
		elseif e.kind == "pet" and opts.pets then
			local found
			for _, s in ipairs(opts.pets.species or {}) do
				if s.key == e.species then
					found = s
				end
			end
			if not found or not (found.source and found.source.boss) then
				bad("exclusive %s: pet %s must exist with source.boss", e.key, tostring(e.species))
			elseif found.name ~= e.name then
				bad("exclusive %s: name must be the pet's (%s)", e.key, tostring(found.name))
			end
		elseif e.kind == "portal" and opts.portal then
			local found
			for _, s in ipairs(opts.portal.styles or {}) do
				if s.key == e.style then
					found = s
				end
			end
			if not found or found.route ~= "boss" then
				bad("exclusive %s: portal style %s must exist with route boss", e.key, tostring(e.style))
			elseif found.name ~= e.name then
				bad("exclusive %s: name must be the style's (%s)", e.key, tostring(found.name))
			end
		elseif e.kind == "frame" and opts.frames and not opts.frames[e.frame or ""] then
			bad("exclusive %s: frame %s has no picture in the client (nameplate_core.lua N.FRAMES)", e.key, tostring(e.frame))
		end
	end
	return problems
end

-- ---------------------------------------------------------------- SQL
local function sqlKey(s)
	return (tostring(s or ""):gsub("[^%w_]", ""):sub(1, 40))
end
K.sqlKey = sqlKey

function K.sqlCreate(cfg)
	return "CREATE TABLE IF NOT EXISTS `" .. cfg.table .. "` (" ..
		"`account_id` int(11) NOT NULL, `exclusive` varchar(40) NOT NULL, `source` varchar(16) NOT NULL DEFAULT '', " ..
		"`created` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`, `exclusive`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
end

function K.sqlSelect(cfg, accountId)
	return "SELECT `exclusive` FROM `" .. cfg.table .. "` WHERE `account_id` = " .. math.floor(tonumber(accountId) or 0)
end

function K.sqlInsert(cfg, accountId, key, source, now)
	return "INSERT IGNORE INTO `" .. cfg.table .. "` (`account_id`, `exclusive`, `source`, `created`) VALUES (" ..
		math.floor(tonumber(accountId) or 0) .. ", '" .. sqlKey(key) .. "', '" .. sqlKey(source) .. "', " ..
		math.floor(tonumber(now) or 0) .. ")"
end

function K.sqlDelete(cfg, accountId, key)
	return "DELETE FROM `" .. cfg.table .. "` WHERE `account_id` = " .. math.floor(tonumber(accountId) or 0) ..
		" AND `exclusive` = '" .. sqlKey(key) .. "'"
end

return K
