-- Town Portal: pure logic (no engine calls), used by townportal.lua and server/tests/townportal_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   K.style(cfg, id)                        style of an id (unknown / nil -> the default style)
--   K.styleByKey(cfg, key)
--   K.validate(cfg, achievementsData, shopConfig) -> list of problems (styles, routes, store offers, rewards)
--   K.achievementOf(achievementsData, key)  the achievement whose reward is {portal = {key = key}}
--   K.storePrices(shopConfig)               unlock name -> cost of the "Portal Styles" offers
--   K.unlockName(style) / K.styleOfUnlock(cfg, name)
--   K.owns(style, facts)                    facts: storeOwned(id) -> bool, hasAchievement(id) -> bool, achievementOf(key),
--                                           seasonOwned(key) -> bool (route "season": the season pass, seasonpass.lua),
--                                           bossOwned(key) -> bool (route "boss": exclusives.lua, "portal_<key>")
--   K.blockReason(f)                        why a cast may not start / finish (nil = allowed); f = facts table
--   K.ringOffsets(radius)                   offsets of the rings 1..radius around a tile, nearest first
--   K.pickSpot(origin, offsets, isFree)     first origin + offset with isFree(pos) true, or nil
--   K.cooldownLeft(now, untilTime)
--   K.castStart(now, pos, castMs) / K.castStep(cast, nowMs, pos, damaged) -> "wait" | "moved" | "hit" | "done"
--   K.mayUse(pair, guid, partyOf)           owner or (cfg.partyCanUse) a member of the owner's party
--   K.view(cfg, facts, selectedId, prices, achievementsData)  the Portal Style window rows

ChaosTownPortalCore = ChaosTownPortalCore or {}
local K = ChaosTownPortalCore

local ROUTES = {default = true, store = true, achievement = true, season = true, boss = true}

function K.style(cfg, id)
	id = tonumber(id)
	local default
	for _, s in ipairs(cfg.styles) do
		if s.id == id then
			return s
		end
		if s.route == "default" then
			default = default or s
		end
	end
	return default
end

function K.styleByKey(cfg, key)
	for _, s in ipairs(cfg.styles) do
		if s.key == key then
			return s
		end
	end
	return nil
end

function K.unlockName(style)
	return "portal_" .. style.key
end

function K.styleOfUnlock(cfg, name)
	local key = type(name) == "string" and name:match("^portal_([%w_]+)$")
	local s = key and K.styleByKey(cfg, key)
	return s and s.route == "store" and s or nil
end

-- every achievement (achievements_data.lua list) whose reward names the portal style `key`
local function rewardsOf(data, key)
	local list = {}
	for _, a in ipairs(data and data.list or {}) do
		local p = type(a.reward) == "table" and a.reward.portal
		if type(p) == "table" and p.key == key then
			list[#list + 1] = a
		end
	end
	return list
end

function K.achievementOf(data, key)
	return rewardsOf(data, key)[1]
end

-- the store offers that sell portal styles: unlock name -> cost (and the number of offers per name)
function K.storePrices(shop)
	local prices, count = {}, {}
	for _, cat in ipairs(shop and shop.categories or {}) do
		for _, o in ipairs(cat.offers or {}) do
			if o.kind == "unlock" and type(o.unlock) == "string" and o.unlock:match("^portal_") then
				prices[o.unlock] = o.cost
				count[o.unlock] = (count[o.unlock] or 0) + 1
			end
		end
	end
	return prices, count
end

function K.validate(cfg, data, shop)
	local problems = {}
	local function bad(text)
		problems[#problems + 1] = text
	end
	local ids, keys, defaults = {}, {}, 0
	local prices, count = K.storePrices(shop)
	for i, s in ipairs(cfg.styles or {}) do
		local where = "style " .. i .. " (" .. tostring(s.key) .. ")"
		if type(s.id) ~= "number" or s.id < 0 or s.id ~= math.floor(s.id) then
			bad(where .. ": id must be a whole number >= 0")
		elseif ids[s.id] then
			bad(where .. ": duplicate id " .. s.id)
		end
		ids[s.id or -1] = true
		if type(s.key) ~= "string" or not s.key:match("^[a-z_]+$") then
			bad(where .. ": key must be lower case letters")
		elseif keys[s.key] then
			bad(where .. ": duplicate key")
		end
		keys[s.key or ""] = true
		if type(s.name) ~= "string" or s.name == "" then
			bad(where .. ": no name")
		end
		if type(s.item) ~= "number" or s.item <= 0 then
			bad(where .. ": no portal item")
		end
		if type(s.open) ~= "table" or #s.open == 0 or type(s.close) ~= "table" or #s.close == 0 then
			bad(where .. ": open and close effects are needed")
		end
		if not ROUTES[s.route] then
			bad(where .. ": route must be default, store, achievement, season or boss")
		end
		local rewards = type(s.key) == "string" and rewardsOf(data, s.key) or {}
		local unlock = type(s.key) == "string" and ("portal_" .. s.key) or "?"
		if s.route == "default" then
			defaults = defaults + 1
		end
		if s.route == "store" then
			if s.id < 1 or s.id > 29 then
				bad(where .. ": store style ids are 1..29 (the owned storages)")
			end
			if (count[unlock] or 0) ~= 1 then
				bad(where .. ": needs exactly one store offer (unlock = " .. unlock .. "), has " .. (count[unlock] or 0))
			end
		elseif count[unlock] then
			bad(where .. ": only store styles may be sold (" .. s.route .. " style in the store)")
		end
		if s.route == "achievement" then
			if #rewards ~= 1 then
				bad(where .. ": needs exactly one achievement with reward portal " .. s.key .. ", has " .. #rewards)
			end
		elseif #rewards > 0 then
			bad(where .. ": only achievement styles may be achievement rewards (" .. tostring(s.route) .. ")")
		end
	end
	if defaults ~= 1 then
		bad("exactly one default style is needed, found " .. defaults)
	end
	-- no offer or reward may name a style that does not exist
	for name in pairs(prices) do
		if not K.styleOfUnlock(cfg, name) then
			bad("store offer " .. name .. " names no store style")
		end
	end
	for _, a in ipairs(data and data.list or {}) do
		local p = type(a.reward) == "table" and a.reward.portal or nil
		if p ~= nil then
			local s = type(p) == "table" and K.styleByKey(cfg, p.key)
			if not s or s.route ~= "achievement" then
				bad("achievement " .. tostring(a.id) .. ": reward portal names no achievement style")
			elseif p.name ~= s.name then
				bad("achievement " .. tostring(a.id) .. ": reward portal name must be " .. s.name)
			end
		end
	end
	return problems
end

function K.owns(style, facts)
	if not style then
		return false
	end
	if style.route == "default" then
		return true
	elseif style.route == "store" then
		return facts.storeOwned(style.id) and true or false
	elseif style.route == "achievement" then
		local a = facts.achievementOf(style.key)
		return a ~= nil and facts.hasAchievement(a.id) and true or false
	elseif style.route == "season" then
		return facts.seasonOwned ~= nil and facts.seasonOwned(style.key) and true or false
	elseif style.route == "boss" then
		return facts.bossOwned ~= nil and facts.bossOwned(style.key) and true or false
	end
	return false
end

-- inside a hideout the Town Portal is a way out (coordinator 2026-10-16, noob-friendly): no channel, no portal pair
-- (a return portal would lead back into a hideout), no cooldown; townportal.lua sends the character out through the
-- hideout's own exit logic (ChaosHideout.leave: the spot entered from, else the home temple, else Cinderhold; never a
-- hideout or an instance). f: the facts of K.blockReason.
function K.hideoutExit(f)
	return f ~= nil and f.hideout == true and not f.casting and not f.tutorial
end

-- f: {tutorial, pz, pzLocked, skull, arena, worldBoss, siege, rift, dungeon, tower, cooldownLeft, casting, noTown}
-- (true / a number for the ones that apply). Order: the most useful message first. A hideout is handled before this
-- (K.hideoutExit); its line below only answers when the hideout system is not loaded.
function K.blockReason(f)
	if f.casting then
		return "You are already opening a portal."
	end
	if (f.cooldownLeft or 0) > 0 then
		return string.format("Your Town Portal is ready again in %d second%s.", f.cooldownLeft, f.cooldownLeft == 1 and "" or "s")
	end
	if f.tutorial then
		return "There is no town portal on the island yet: finish or skip the tutorial first."
	end
	if f.noTown then
		return "You have no home town to open a portal to."
	end
	if f.arena then
		return "You cannot open a town portal in an arena match."
	end
	if f.worldBoss then
		return "You cannot open a town portal in the world boss arena."
	end
	if f.siege then
		return "You cannot open a town portal during a guild siege."
	end
	if f.rift then
		return "A rift holds you: leave it through its own exit or finish it."
	end
	if f.dungeon then
		return "A dungeon holds you: leave it through its own exit or finish it."
	end
	if f.tower then
		return "The Infinity Tower holds you: leave it through its own exit."
	end
	if f.hideout then -- Hideouts (hideout.lua)
		return "Leave your hideout through its exit portal or Leave in the Hideout window."
	end
	if f.marches then -- the Scorched Marches (pvpzone.lua)
		return "The Marches hold you: leave through a safe exit (your embers are banked there)."
	end
	if f.instance then -- any other registered instance (Chaos.inAnyInstance): its label, e.g. "a raid"
		return string.format("You cannot open a town portal in %s: leave it through its own exit.",
			type(f.instance) == "string" and f.instance or "this place")
	end
	if f.pzLocked then
		return "You cannot open a town portal right after fighting other players."
	end
	if f.skull then
		return "You cannot open a town portal while you carry a skull."
	end
	if f.pz then
		return "You are already in a protection zone."
	end
	return nil
end

-- rings 1..radius around (0, 0), each ring from the nearest tiles outwards (straight before diagonal)
function K.ringOffsets(radius)
	local list = {}
	for r = 1, radius do
		local ring = {}
		for dx = -r, r do
			for dy = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					ring[#ring + 1] = {dx, dy}
				end
			end
		end
		table.sort(ring, function(a, b)
			local da, db = a[1] * a[1] + a[2] * a[2], b[1] * b[1] + b[2] * b[2]
			if da ~= db then
				return da < db
			end
			if a[2] ~= b[2] then
				return a[2] < b[2]
			end
			return a[1] < b[1]
		end)
		for _, o in ipairs(ring) do
			list[#list + 1] = o
		end
	end
	return list
end

function K.pickSpot(origin, offsets, isFree)
	for _, o in ipairs(offsets) do
		local p = {x = origin.x + o[1], y = origin.y + o[2], z = origin.z}
		if isFree(p) then
			return p
		end
	end
	return nil
end

function K.cooldownLeft(now, untilTime)
	untilTime = tonumber(untilTime) or 0
	return untilTime > now and (untilTime - now) or 0
end

-- times in milliseconds
function K.castStart(nowMs, pos, castMs)
	return {startMs = nowMs, endMs = nowMs + castMs, pos = {x = pos.x, y = pos.y, z = pos.z}}
end

function K.castStep(cast, nowMs, pos, damaged)
	if damaged then
		return "hit"
	end
	if pos.x ~= cast.pos.x or pos.y ~= cast.pos.y or pos.z ~= cast.pos.z then
		return "moved"
	end
	if nowMs >= cast.endMs then
		return "done"
	end
	return "wait"
end

-- pair = {owner = guid}; partyOf(guid) -> party key (nil when not in a party)
function K.mayUse(pair, guid, partyOf, partyCanUse)
	if not pair then
		return false
	end
	if pair.owner == guid then
		return true
	end
	if not partyCanUse then
		return false
	end
	local mine, theirs = partyOf(guid), partyOf(pair.owner)
	return mine ~= nil and mine == theirs
end

-- the Portal Style window rows
function K.view(cfg, facts, selectedId, prices, data)
	local selected = K.style(cfg, selectedId)
	local rows = {}
	for _, s in ipairs(cfg.styles) do
		local row = {id = s.id, name = s.name, desc = s.desc or "", route = s.route, item = s.item,
			owned = K.owns(s, facts), selected = selected and selected.id == s.id or false}
		if s.route == "store" then
			row.price = prices[K.unlockName(s)]
			row.how = row.price and string.format("Store: %d Chaos Coins (Portal Styles)", row.price) or "Store"
		elseif s.route == "achievement" then
			local a = K.achievementOf(data, s.key)
			row.how = a and string.format("Achievement: %s (%s)", a.hidden and not row.owned and "???" or a.name,
				a.hidden and not row.owned and "a secret" or a.desc) or "Achievement"
		elseif s.route == "season" or s.route == "boss" then
			row.how = s.how or (s.route == "boss" and "Boss drop" or "Season pass")
		else
			row.how = "Every character has it."
		end
		rows[#rows + 1] = row
	end
	return rows
end

return K
