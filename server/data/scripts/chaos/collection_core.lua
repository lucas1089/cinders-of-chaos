-- collection_core.lua: the rules of the collection score without engine calls (server/tests/collection_test.lua).
-- Data in collection_config.lua, engine glue in collection.lua. See server/README.md "Collection score".
-- Entries are typed texts: "c:<cosmetic key>" (cosmetics_config.lua), "w:<kind>:<look>" (an outfit / addons look,
-- a mount / wings / aura client look, "w:shader:<name>"), "f:<frame>" (a name plate frame), "t:<title key>" (a title),
-- "m:<milestone key>" (a milestone reached; stored with its time).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosCollectionCore = ChaosCollectionCore or {}
local K = ChaosCollectionCore

K.WARDROBE_KINDS = {"outfit", "mount", "wings", "aura", "shader"}
-- the groups the window lists, in order
K.GROUPS = {"outfit", "mount", "wings", "aura", "shader", "frame", "spellskin", "killfx", "levelfx", "rarefx", "emote",
	"lootbeam", "chatcolor", "footprint", "outline", "title"}
K.TITLE_MAX_CHARS = 24

-- a shader's name as part of an entry (letters, digits and _ only, so the stored text is the one looked up)
function K.shaderKey(name)
	return (tostring(name):gsub("[^%w_]", "_"))
end

-- ---------------------------------------------------------------- points
-- a sold item: one point per cfg.pricePerPoint coins, rounded up
function K.pricePoints(cfg, price)
	price = tonumber(price) or 0
	if price <= 0 then
		return 0
	end
	return math.max(cfg.minPoints or 1, math.ceil(price / cfg.pricePerPoint))
end

-- a cosmetic of cosmetics_config.lua: its store price, else the points of where it comes from
function K.cosmeticPoints(cfg, c)
	if not c then
		return 0
	end
	if c.source == "store" then
		return K.pricePoints(cfg, c.price)
	end
	return (cfg.sourcePoints or {})[c.source] or 0
end

-- ---------------------------------------------------------------- the data the points come from
-- cat = ChaosWardrobeCore.catalogue (outfit {look}, mount / wings / aura {id, look}, shader {id, name}):
-- {mount = {[xml id] = client look}, wings = ..., aura = ..., shader = {[xml id] = shader name}}
function K.lookIndex(cat)
	local ix = {mount = {}, wings = {}, aura = {}, shader = {}}
	for _, kind in ipairs({"mount", "wings", "aura"}) do
		for _, e in ipairs((cat or {})[kind] or {}) do
			ix[kind][e.id] = e.look
		end
	end
	for _, e in ipairs((cat or {}).shader or {}) do
		ix.shader[e.id] = e.name
	end
	return ix
end

-- {["outfit:128"] = coins, ["mount:368"] = coins, ["wings:1234"], ["aura:..."], ["shader:name"], ["frame:ember"]}: the
-- lowest price of any offer of shop_config.lua (any depth) that sells it. ix = K.lookIndex(cat)
function K.priceMap(root, ix)
	local map = {}
	local function put(key, cost)
		if key and tonumber(cost) and (map[key] == nil or cost < map[key]) then
			map[key] = cost
		end
	end
	local function walk(t, depth)
		if type(t) ~= "table" or depth > 8 then
			return
		end
		if type(t.kind) == "string" and tonumber(t.cost) then
			local k = t.kind
			if k == "outfit" or k == "addons" then
				put(t.looktype and ("outfit:" .. t.looktype), t.cost)
				put(t.lookfemale and ("outfit:" .. t.lookfemale), t.cost)
			elseif k == "mount" then
				local look = t.clientid or ix.mount[t.id]
				put(look and ("mount:" .. look), t.cost)
			elseif k == "wings" or k == "aura" then
				local look = ix[k][t.id]
				put(look and (k .. ":" .. look), t.cost)
			elseif k == "shader" then
				local name = ix.shader[t.id]
				put(name and ("shader:" .. K.shaderKey(name)), t.cost)
			elseif k == "frame" then
				put(t.frame and ("frame:" .. t.frame), t.cost)
			end
		end
		for _, v in pairs(t) do
			if type(v) == "table" then
				walk(v, depth + 1)
			end
		end
	end
	walk(root, 0)
	return map
end

-- {["outfit:128"] = true, ...}: what exclusives_config.lua entries give and no offer sells. ix = K.lookIndex(cat)
function K.exclusiveSet(entries, ix)
	local set = {}
	for _, e in ipairs(entries or {}) do
		if e.kind == "outfit" or e.kind == "addons" then
			set[e.male and ("outfit:" .. e.male) or "?"] = true
			set[e.female and ("outfit:" .. e.female) or "?"] = true
		elseif e.kind == "mount" or e.kind == "wings" or e.kind == "aura" then
			local look = ix[e.kind][e.id]
			set[look and (e.kind .. ":" .. look) or "?"] = true
		elseif e.kind == "shader" then
			local name = ix.shader[e.id]
			set[name and ("shader:" .. K.shaderKey(name)) or "?"] = true
		elseif e.kind == "frame" then
			set[e.frame and ("frame:" .. e.frame) or "?"] = true
		end
	end
	set["?"] = nil
	return set
end

-- the owned items of a wardrobe list (ChaosWardrobeCore.list: outfit {l, o}, mount / wings / aura {l, o}, shader {n, o})
-- as "kind:id" texts (the price map's keys)
function K.wardrobeOwned(list)
	local out = {}
	for _, kind in ipairs({"outfit", "mount", "wings", "aura"}) do
		for _, e in ipairs((list or {})[kind] or {}) do
			if e.o and e.l then
				out[#out + 1] = kind .. ":" .. e.l
			end
		end
	end
	for _, e in ipairs((list or {}).shader or {}) do
		if e.o and e.n then
			out[#out + 1] = "shader:" .. K.shaderKey(e.n)
		end
	end
	return out
end

-- ---------------------------------------------------------------- entries and the score
-- ctx = {cosmetics = {[key] = cosmetic}, prices = K.priceMap, exclusive = K.exclusiveSet}
-- points and group of one entry; 0 for a milestone, an unknown cosmetic or a free item
function K.entry(cfg, ctx, entry)
	local tag, rest = tostring(entry):match("^(%a):(.+)$")
	if tag == "c" then
		local c = ctx.cosmetics[rest]
		return K.cosmeticPoints(cfg, c), c and c.kind or nil
	elseif tag == "w" or tag == "f" then
		local key = tag == "f" and ("frame:" .. rest) or rest
		local kind = tag == "f" and "frame" or key:match("^(%a+):")
		local price = ctx.prices[key]
		local points = 0
		if price then
			points = K.pricePoints(cfg, price)
		elseif ctx.exclusive[key] then
			points = cfg.exclusivePoints or 0
		end
		return points, kind
	elseif tag == "t" then
		return cfg.titlePoints or 0, "title"
	end
	return 0, nil
end

-- entries = array of typed texts (each once). Returns the score and the groups {[group] = {n = items, p = points}}.
-- Titles count up to cfg.titleMax.
function K.score(cfg, ctx, entries)
	local total, groups, seen, titles = 0, {}, {}, 0
	for _, e in ipairs(entries or {}) do
		if not seen[e] then
			seen[e] = true
			local points, group = K.entry(cfg, ctx, e)
			if group == "title" then
				titles = titles + 1
				if titles > (cfg.titleMax or 0) then
					points = 0
				end
			end
			if group and points > 0 then
				total = total + points
				local g = groups[group] or {n = 0, p = 0}
				g.n, g.p = g.n + 1, g.p + points
				groups[group] = g
			end
		end
	end
	return total, groups
end

-- the largest score every item of the catalogue could give: the cosmetics and every priced or exclusive wardrobe item
-- and frame (titles at their cap); the milestones must stay below it
function K.maxScore(cfg, ctx)
	local total = 0
	for _, c in pairs(ctx.cosmetics) do
		total = total + K.cosmeticPoints(cfg, c)
	end
	for _, cost in pairs(ctx.prices) do
		total = total + K.pricePoints(cfg, cost)
	end
	for key in pairs(ctx.exclusive) do
		if not ctx.prices[key] then
			total = total + (cfg.exclusivePoints or 0)
		end
	end
	return total + (cfg.titleMax or 0) * (cfg.titlePoints or 0)
end

-- ---------------------------------------------------------------- milestones
function K.sorted(cfg)
	local list = {}
	for _, m in ipairs(cfg.milestones or {}) do
		list[#list + 1] = m
	end
	table.sort(list, function(a, b) return a.points < b.points end)
	return list
end

-- the milestones reached and not claimed yet (claimed = {[key] = time}), lowest first
function K.due(cfg, score, claimed)
	local out = {}
	for _, m in ipairs(K.sorted(cfg)) do
		if score >= m.points and not (claimed or {})[m.key] then
			out[#out + 1] = m
		end
	end
	return out
end

-- the first milestone above the score, or nil
function K.nextMilestone(cfg, score)
	for _, m in ipairs(K.sorted(cfg)) do
		if m.points > score then
			return m
		end
	end
	return nil
end

-- a reward for the window, structured so the client words it in the player's language: {k = "title", n = text,
-- f = plate frame | nil} or {k = <the cosmetic's kind>, n = its name}
function K.rewardInfo(reward, cosmetics)
	if reward.kind == "title" then
		return {k = "title", n = reward.text, f = reward.frame}
	end
	local c = cosmetics[reward.key]
	return {k = c and c.kind or "cosmetic", n = c and c.name or reward.key}
end

-- The titles an account holds from its claimed milestones, for ChaosTitles: {key, text, frame?, at}. The newest one
-- is the default title (titles.lua sorts by `at`).
function K.titlesOf(cfg, claimed)
	local out = {}
	for _, m in ipairs(K.sorted(cfg)) do
		local at = (claimed or {})[m.key]
		if at then
			for _, r in ipairs(m.rewards or {}) do
				if r.kind == "title" then
					out[#out + 1] = {key = "collection:" .. m.key, text = r.text, frame = r.frame, at = at}
				end
			end
		end
	end
	return out
end

-- The window's payload: {score, groups = {{g, n, p}}, next = {points, left} | nil, milestones = {{key, points, done,
-- rewards = {K.rewardInfo}}}}. Short and fixed: it rides on the cosmetics `state`.
function K.view(cfg, score, groups, claimed, cosmetics)
	local view = {score = score, groups = {}, milestones = {}}
	for _, g in ipairs(K.GROUPS) do
		local e = groups[g]
		if e then
			view.groups[#view.groups + 1] = {g = g, n = e.n, p = e.p}
		end
	end
	local nxt = K.nextMilestone(cfg, score)
	if nxt then
		view.next = {points = nxt.points, left = nxt.points - score}
	end
	for _, m in ipairs(K.sorted(cfg)) do
		local infos = {}
		for _, r in ipairs(m.rewards or {}) do
			infos[#infos + 1] = K.rewardInfo(r, cosmetics)
		end
		view.milestones[#view.milestones + 1] = {key = m.key, points = m.points, done = (claimed or {})[m.key] and true or nil,
			rewards = infos}
	end
	return view
end

-- ---------------------------------------------------------------- SQL
local function sqlKey(s)
	return (tostring(s or ""):gsub("[^%w_:%-%.]", ""):sub(1, 64))
end
K.sqlKey = sqlKey

function K.sqlCreate(cfg)
	return "CREATE TABLE IF NOT EXISTS `" .. cfg.table .. "` (`account_id` int(11) NOT NULL, `entry` varchar(64) NOT NULL, " ..
		"`at` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`, `entry`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
end

function K.sqlSelect(cfg, accountId)
	return "SELECT `entry`, `at` FROM `" .. cfg.table .. "` WHERE `account_id` = " .. math.floor(tonumber(accountId) or 0)
end

function K.sqlInsert(cfg, accountId, entry, now)
	return "INSERT IGNORE INTO `" .. cfg.table .. "` (`account_id`, `entry`, `at`) VALUES (" ..
		math.floor(tonumber(accountId) or 0) .. ", '" .. sqlKey(entry) .. "', " .. math.floor(tonumber(now) or 0) .. ")"
end

-- ---------------------------------------------------------------- checks
-- opts.cosmetics = cosmetics_config.lua cosmetics (list); opts.frames = {[frame] = true} (nameplate_core.lua N.FRAMES);
-- opts.maxScore = K.maxScore (the milestones must be reachable). Returns problems.
function K.validate(cfg, opts)
	opts = opts or {}
	local problems = {}
	local function bad(fmt, ...)
		problems[#problems + 1] = string.format(fmt, ...)
	end
	if type(cfg.pricePerPoint) ~= "number" or cfg.pricePerPoint <= 0 then
		bad("pricePerPoint must be above 0")
	end
	local byKey = {}
	for _, c in ipairs(opts.cosmetics or {}) do
		byKey[c.key] = c
	end
	local keys, points, rewardKeys = {}, {}, {}
	local last = 0
	for i, m in ipairs(cfg.milestones or {}) do
		local w = "milestone " .. tostring(m.key or i)
		if type(m.key) ~= "string" or not m.key:match("^[%w_]+$") or #m.key > 40 then
			bad("%s: key letters, digits and _ only", w)
		elseif keys[m.key] then
			bad("%s: key used twice", w)
		end
		keys[m.key or "?"] = true
		if type(m.points) ~= "number" or m.points < 1 or m.points % 1 ~= 0 then
			bad("%s: points must be a whole number above 0", w)
		else
			if points[m.points] then
				bad("%s: %d points used twice", w, m.points)
			end
			points[m.points] = true
			if m.points <= last then
				bad("%s: milestones go from low to high", w)
			end
			last = m.points
			if opts.maxScore and m.points > opts.maxScore then
				bad("%s: %d points are more than the %d the catalogue gives", w, m.points, opts.maxScore)
			end
		end
		if type(m.rewards) ~= "table" or #m.rewards == 0 then
			bad("%s: at least one reward", w)
		end
		for _, r in ipairs(m.rewards or {}) do
			if r.kind == "title" then
				if type(r.text) ~= "string" or r.text == "" or #r.text > K.TITLE_MAX_CHARS or r.text:find("[%c|]") then
					bad("%s: a title is 1 to %d characters", w, K.TITLE_MAX_CHARS)
				end
				if r.frame ~= nil and not (opts.frames and opts.frames[r.frame]) then
					bad("%s: plate frame %s has no picture in the client", w, tostring(r.frame))
				end
			elseif r.kind == "cosmetic" then
				local c = byKey[r.key]
				if not c then
					bad("%s: cosmetic %s does not exist", w, tostring(r.key))
				elseif c.source ~= "collection" then
					bad("%s: cosmetic %s must have the source collection", w, r.key)
				elseif c.collection ~= m.points then
					bad("%s: cosmetic %s is granted at %s points, the milestone has %s", w, r.key, tostring(c.collection), tostring(m.points))
				end
				if rewardKeys[r.key] then
					bad("%s: cosmetic %s is the reward of two milestones", w, r.key)
				end
				rewardKeys[r.key or "?"] = true
			else
				bad("%s: unknown reward kind %s", w, tostring(r.kind))
			end
		end
	end
	-- every collection cosmetic is the reward of a milestone
	for _, c in ipairs(opts.cosmetics or {}) do
		if c.source == "collection" and not rewardKeys[c.key] then
			bad("cosmetic %s has the source collection but no milestone grants it", c.key)
		end
	end
	if #(cfg.milestones or {}) == 0 then
		bad("no milestones")
	end
	return problems
end

return K
