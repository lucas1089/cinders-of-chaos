-- Achievements: pure logic (ChaosAchievementsCore), no engine calls. Used by achievements.lua, tested by
-- server/tests/achievements_test.lua (luajit and lua5.3). The list itself is achievements_data.lua.
--
--   K.build(data)                         -> index {list, byId, categories, catByKey, bossStats, problems}
--   K.validate(data)                      -> list of problem strings, set of bad entry numbers (left out of the index)
--   K.add(stats, key, amount)             counter += amount (amount > 0); returns true when it changed
--   K.setMax(stats, key, value)           counter = max(counter, value); values never go down
--   K.progressOf(def, stats, points)      -> value (capped at target), target
--   K.evaluate(index, stats, unlocked)    -> list of defs that are met now and not in `unlocked` (id -> time), in list
--                                            order; achievements on "points" see the points of the new ones too
--   K.points(index, unlocked)             -> sum of points of the unlocked ids (unknown ids count 0, retired ones their points)
--   K.maxPoints(index)
--   K.categorySummary(index, unlocked)    -> [{key, name, done, total, points, max}]
--   K.view(index, stats, unlocked)        -> the window's rows (hidden + locked -> "???", no progress)
--   K.recent(index, unlocked, n)          -> the newest n unlocks [{id, name, points, at}]
--   K.titlesOf(index, unlocked)           -> titles for ChaosTitles (source "achievement")
--   K.rewardText(reward, nameOf)          -> "3 Orb of Upheaval, mount Doombringer" (nameOf(itemId) -> name)
--   K.toast(def, rewardText)              -> title, text of the unlock toast ("Blooded", "+5 points. Reward: ...")
--   K.summaryToast(list, rewards)         -> title, text of several unlocks at once (the login summary); nil for none
--   K.retroStats(facts)                   -> stats that the character's current state proves (level, Paragon, ...)
--   K.paragonLevel(level, startLevel)
--   K.unlockMethod()                      -> {describe, check} for ChaosClassUnlocksCore.registerMethod("achievement")
--   K.has(account, query)                 account = {ids = set, points = n}; query = id or "points:N"
--   K.validKey(s), K.sql*                 storage helpers (statements only, the caller runs them)
--   K.completedCategories / categoryTitles / categoryTrack   category completion of the reward track (see below)
-- The texts a player reads (categorySummary, view, rewardText, toast, summaryToast) take an optional last `lang`
-- ("pt-BR" | "en"): through ChaosI18n (i18n_core.lua) when it is loaded, else English. Names and titles stay as they are.

ChaosAchievementsCore = ChaosAchievementsCore or {}
local K = ChaosAchievementsCore

local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

local function validKey(s)
	return type(s) == "string" and #s > 0 and #s <= 48 and s:match("^[%w_]+$") ~= nil
end
K.validKey = validKey

-- ------------------------------------------------------------------------------------------------ the list
function K.validate(data)
	local problems, badIndex = {}, {}
	local cats = {}
	for _, c in ipairs(data and data.categories or {}) do
		cats[c.key] = true
	end
	local seen = {}
	for i, a in ipairs(data and data.list or {}) do
		local where = "entry " .. i .. " (" .. tostring(a.id) .. ")"
		local before = #problems
		if not validKey(a.id) then
			problems[#problems + 1] = where .. ": id must be letters, digits or _"
		elseif seen[a.id] then
			problems[#problems + 1] = where .. ": duplicate id"
		end
		if type(a.name) ~= "string" or a.name == "" then
			problems[#problems + 1] = where .. ": no name"
		end
		if not cats[a.cat] then
			problems[#problems + 1] = where .. ": unknown category " .. tostring(a.cat)
		end
		if type(a.points) ~= "number" or a.points < 0 then
			problems[#problems + 1] = where .. ": points must be a number >= 0"
		end
		if a.all then
			if type(a.all) ~= "table" or #a.all == 0 then
				problems[#problems + 1] = where .. ": all must be a list of stats"
			else
				for _, s in ipairs(a.all) do
					if not validKey(s) then
						problems[#problems + 1] = where .. ": bad stat in all: " .. tostring(s)
					end
				end
			end
		elseif not validKey(a.stat) then
			problems[#problems + 1] = where .. ": no stat"
		end
		if a.target ~= nil and (type(a.target) ~= "number" or a.target < 1) then
			problems[#problems + 1] = where .. ": target must be >= 1"
		end
		if a.title ~= nil and (type(a.title) ~= "string" or #a.title > 24) then
			problems[#problems + 1] = where .. ": title must be text of at most 24 characters"
		end
		if #problems > before then
			badIndex[i] = true
		else
			seen[a.id] = true
		end
	end
	return problems, badIndex
end

function K.build(data)
	local index = {list = {}, byId = {}, categories = {}, catByKey = {}, bossStats = data and data.bossStats or {},
		retired = data and data.retired or {}}
	local bad
	index.problems, bad = K.validate(data)
	for _, c in ipairs(data and data.categories or {}) do
		local cat = {key = c.key, name = c.name}
		index.categories[#index.categories + 1] = cat
		index.catByKey[c.key] = cat
	end
	for i, a in ipairs(data and data.list or {}) do
		if not bad[i] then
			local def = {}
			for k, v in pairs(a) do
				def[k] = v
			end
			def.order = i
			def.target = a.all and #a.all or (a.target or 1)
			index.list[#index.list + 1] = def
			index.byId[a.id] = def
		end
	end
	-- category completion rewards (reward track): a bad entry is reported and left out
	index.categoryRewards = {}
	local rewardProblems, rewardOk = K.categoryRewardProblems(data)
	for _, p in ipairs(rewardProblems) do
		index.problems[#index.problems + 1] = p
	end
	for key, r in pairs(rewardOk) do
		index.categoryRewards[key] = r
	end
	return index
end

-- ------------------------------------------------------------------------------------------------ stats
function K.add(stats, key, amount)
	amount = math.floor(tonumber(amount) or 1)
	if not validKey(key) or amount <= 0 then
		return false
	end
	stats[key] = (stats[key] or 0) + amount
	return true
end

function K.setMax(stats, key, value)
	value = math.floor(tonumber(value) or 0)
	if not validKey(key) or value <= (stats[key] or 0) then
		return false
	end
	stats[key] = value
	return true
end

function K.progressOf(def, stats, points)
	local value
	if def.all then
		value = 0
		for _, s in ipairs(def.all) do
			if (stats[s] or 0) >= 1 then
				value = value + 1
			end
		end
	elseif def.stat == "points" then
		value = points or 0
	else
		value = stats[def.stat] or 0
	end
	return math.min(value, def.target), def.target
end

function K.points(index, unlocked)
	local sum = 0
	for id in pairs(unlocked or {}) do
		local def = index.byId[id]
		if def then
			sum = sum + def.points
		elseif index.retired and index.retired[id] then
			sum = sum + index.retired[id] -- an achievement that was retired: the points stay
		end
	end
	return sum
end

function K.maxPoints(index)
	local sum = 0
	for _, def in ipairs(index.list) do
		sum = sum + def.points
	end
	return sum
end

-- every achievement met now that is not unlocked yet. Points-based ones are checked again after the others, so one
-- evaluation sees the points it just earned (and a points achievement that pushes past the next one too).
function K.evaluate(index, stats, unlocked)
	unlocked = unlocked or {}
	local out, taken = {}, {}
	local points = K.points(index, unlocked)
	local changed = true
	while changed do
		changed = false
		for _, def in ipairs(index.list) do
			if not unlocked[def.id] and not taken[def.id] then
				local value, target = K.progressOf(def, stats, points)
				if value >= target then
					taken[def.id] = true
					out[#out + 1] = def
					points = points + def.points
					changed = true
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.order < b.order end)
	return out
end

-- ------------------------------------------------------------------------------------------------ the window
function K.categorySummary(index, unlocked, lang)
	local out, byKey = {}, {}
	for _, c in ipairs(index.categories) do
		local e = {key = c.key, name = c.name and T(lang, c.name), done = 0, total = 0, points = 0, max = 0}
		out[#out + 1] = e
		byKey[c.key] = e
	end
	for _, def in ipairs(index.list) do
		local e = byKey[def.cat]
		if e then
			e.total = e.total + 1
			e.max = e.max + def.points
			if unlocked and unlocked[def.id] then
				e.done = e.done + 1
				e.points = e.points + def.points
			end
		end
	end
	return out
end

-- rows for the client. Short keys keep the packet small:
--   i id, n name, d description, c category, p points, h hidden (1), u unlock time (0 = locked), v value, t target,
--   ti title, r reward text
function K.view(index, stats, unlocked, nameOf, lang)
	unlocked = unlocked or {}
	local points = K.points(index, unlocked)
	local rows = {}
	for _, def in ipairs(index.list) do
		local at = unlocked[def.id]
		local row = {i = def.id, c = def.cat, p = def.points, u = at or 0}
		if def.hidden and not at then
			row.h = 1
			row.n = "???"
			row.d = T(lang, "A hidden achievement. Keep playing to find it.")
			row.v, row.t = 0, 0
		else
			row.n = def.name
			row.d = def.desc and T(lang, def.desc) or ""
			row.v, row.t = K.progressOf(def, stats or {}, points)
			if def.hidden then
				row.h = 1
			end
			row.ti = def.title
			if def.reward then
				row.r = K.rewardText(def.reward, nameOf, lang)
			end
		end
		rows[#rows + 1] = row
	end
	return rows
end

function K.recent(index, unlocked, n)
	local out = {}
	for id, at in pairs(unlocked or {}) do
		local def = index.byId[id]
		if def then
			out[#out + 1] = {id = id, name = def.name, points = def.points, at = at, order = def.order}
		end
	end
	table.sort(out, function(a, b)
		if a.at ~= b.at then
			return a.at > b.at
		end
		return a.order > b.order
	end)
	for i = #out, (n or 5) + 1, -1 do
		out[i] = nil
	end
	for _, e in ipairs(out) do
		e.order = nil
	end
	return out
end

function K.titlesOf(index, unlocked)
	local out = {}
	for id, at in pairs(unlocked or {}) do
		local def = index.byId[id]
		if def and def.title then
			out[#out + 1] = {key = "achievement:" .. id, text = def.title, at = at, order = def.order, frame = def.frame}
		end
	end
	table.sort(out, function(a, b) return a.order < b.order end)
	for _, t in ipairs(out) do
		t.order = nil
	end
	return out
end

function K.rewardText(reward, nameOf, lang)
	if type(reward) ~= "table" then
		return ""
	end
	local parts = {}
	if (reward.gold or 0) > 0 then
		parts[#parts + 1] = T(lang, "%s gold", tostring(reward.gold))
	end
	for _, it in ipairs(reward.items or {}) do
		local name = nameOf and nameOf(it.id) or ("item " .. tostring(it.id))
		parts[#parts + 1] = tostring(it.count or 1) .. " " .. tostring(name)
	end
	if reward.outfit then
		parts[#parts + 1] = T(lang, (reward.outfit.addons or 0) > 0 and "outfit %s with addons" or "outfit %s",
			tostring(reward.outfit.name or "?"))
	end
	if reward.mount then
		parts[#parts + 1] = T(lang, "mount %s", tostring(reward.mount.name or "?"))
	end
	if reward.portal then
		parts[#parts + 1] = T(lang, "portal style %s", tostring(reward.portal.name or "?"))
	end
	-- visual exclusives of exclusives_config.lua (unlocked for the account by exclusives.lua)
	for _, e in ipairs(reward.exclusives or {}) do
		parts[#parts + 1] = tostring(type(e) == "table" and e.name or e)
	end
	return table.concat(parts, ", ")
end

-- ------------------------------------------------------------------------------------------------ toasts
-- the toast of one unlock (notifications.lua ChaosNotify.send, kind "achievement" = the ACHIEVEMENT UNLOCKED header):
-- title = the name, text = "+15 points. Title: the Unbroken. Reward: mount Doombringer."
function K.toast(def, rewardText, lang)
	local parts = {T(lang, (def.points or 0) == 1 and "+%d point." or "+%d points.", def.points or 0)}
	if def.title then
		parts[#parts + 1] = T(lang, "Title: %s.", def.title)
	end
	if rewardText and rewardText ~= "" then
		parts[#parts + 1] = T(lang, "Reward: %s.", rewardText)
	end
	return tostring(def.name or def.id or "Achievement"), table.concat(parts, " ")
end

-- several unlocks at once (the quiet login check): one toast. rewards = {[id] = reward text}
function K.summaryToast(list, rewards, lang)
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	rewards = rewards or {}
	if #list == 1 then
		return K.toast(list[1], rewards[list[1].id], lang)
	end
	local points, names, got = 0, {}, {}
	for _, def in ipairs(list) do
		points = points + (def.points or 0)
		if #names < 3 then
			names[#names + 1] = def.name
		end
		local r = rewards[def.id]
		if r and r ~= "" then
			got[#got + 1] = r
		end
	end
	local text = T(lang, "+%d points: %s%s.", points, table.concat(names, ", "), #list > 3 and T(lang, " and %s more", #list - 3) or "")
	if #got > 0 then
		text = text .. T(lang, " Rewards: %s%s.", table.concat(got, ", ", 1, math.min(#got, 2)), #got > 2 and T(lang, " and %s more", #got - 2) or "")
	end
	return T(lang, "%s achievements unlocked", #list), text
end

-- ------------------------------------------------------------------------------------------------ retroactive
function K.paragonLevel(level, startLevel)
	return math.max(0, math.floor((level or 0) - (startLevel or 1000)))
end

-- facts = {level, paragonStart, ascended, tutorialDone, guild, bountyDone, bountyWeek (a week key or <= 0),
--          arena = {["1v1"] = {wins, best}, ...}}
-- Only what the character's saved state proves; counters that need history (kills, orbs, ...) start at 0.
function K.retroStats(facts)
	facts = facts or {}
	local s = {}
	s.level = facts.level or 0
	s.paragon = K.paragonLevel(facts.level, facts.paragonStart)
	s.ascended = facts.ascended and 1 or 0
	s.tutorial = facts.tutorialDone and 1 or 0
	s.guild = facts.guild and 1 or 0
	s.bounty_done = facts.bountyDone or 0
	s.bounty_weeks = (tonumber(facts.bountyWeek) or 0) > 0 and 1 or 0
	for mode, a in pairs(facts.arena or {}) do
		local key = "arena" .. tostring(mode)
		if validKey(key) then
			s[key .. "_wins"] = a.wins or 0
			s[key .. "_rating"] = a.best or 0
		end
	end
	return s
end

-- merge a retro table into the stats (max); returns true when anything went up
function K.applyRetro(stats, retro)
	local changed = false
	for k, v in pairs(retro or {}) do
		if K.setMax(stats, k, v) then
			changed = true
		end
	end
	return changed
end

-- ------------------------------------------------------------------------------------------------ account
-- account = {ids = {[id] = true}, points = n}
function K.has(account, query)
	if type(account) ~= "table" then
		return false
	end
	if type(query) == "string" then
		local n = query:match("^points:(%d+)$")
		if n then
			return (account.points or 0) >= tonumber(n)
		end
		return account.ids ~= nil and account.ids[query] == true
	end
	return false
end

function K.accountFromIds(index, ids)
	local set, points = {}, 0
	for _, id in ipairs(ids or {}) do
		if not set[id] then
			set[id] = true
			local def = index.byId[id]
			points = points + (def and def.points or 0)
		end
	end
	return {ids = set, points = points}
end

-- ------------------------------------------------------------------------------------------------ class unlock method
-- The "achievement" kind of ChaosClassUnlocksCore (class_unlocks_core.lua), extended:
--   achievement = {points = 500}            the account has 500 achievement points (distinct achievements of all its
--                                           characters)
--   achievement = {name = "rift_t10"}       any character of the account has unlocked that achievement (also `id`)
--   both                                    either is enough
-- facts.achievement(query) is the class lock's callback (class_unlocks.lua); it calls ChaosAchievements.has(player,
-- query), so points are asked for as "points:N".
function K.unlockMethod(index)
	return {
		describe = function(spec, class)
			spec = spec or {}
			if spec.text then
				return spec.text
			end
			local ways = {}
			if spec.points then
				ways[#ways + 1] = string.format("earn %d achievement points on your account", spec.points)
			end
			local id = spec.name or spec.id
			if id then
				local def = index and index.byId[id]
				ways[#ways + 1] = "earn the achievement " .. (def and def.name or tostring(id))
			end
			return #ways > 0 and table.concat(ways, ", or ") or "earn achievements"
		end,
		check = function(spec, facts)
			if type(spec) ~= "table" or not facts or not facts.achievement then
				return false
			end
			if spec.points and facts.achievement("points:" .. math.floor(spec.points)) == true then
				return true
			end
			local id = spec.name or spec.id
			return id ~= nil and facts.achievement(id) == true
		end
	}
end

-- ------------------------------------------------------------------------------------------------ reward track
-- Category completion: data.categoryRewards = {[category key] = {title, frame}}. Completion is account-wide: `ids` is
-- the set of achievement ids of the account (K.accountFromIds(...).ids), hidden achievements count too.
--   K.categoryRewardProblems(data)          -> problems, {[key] = reward} of the good entries
--   K.completedCategories(index, ids)       -> {[category key] = true} (a category without achievements never completes)
--   K.categoryTitles(index, ids)            -> titles for ChaosTitles (key "achievement_cat:<key>", frame)
--   K.categoryTrack(index, ids)             -> [{key, name, done, total, title, frame, complete}] in category order
function K.categoryRewardProblems(data)
	local problems, ok = {}, {}
	local cats = {}
	for _, c in ipairs(data and data.categories or {}) do
		cats[c.key] = true
	end
	for key, r in pairs(data and data.categoryRewards or {}) do
		local where = "categoryRewards." .. tostring(key)
		if not cats[key] then
			problems[#problems + 1] = where .. ": unknown category"
		elseif type(r) ~= "table" or type(r.title) ~= "string" or r.title == "" or #r.title > 24 then
			problems[#problems + 1] = where .. ": title must be text of at most 24 characters"
		elseif r.frame ~= nil and (type(r.frame) ~= "string" or not validKey(r.frame)) then
			problems[#problems + 1] = where .. ": frame must be a frame key"
		else
			ok[key] = r
		end
	end
	table.sort(problems)
	return problems, ok
end

function K.completedCategories(index, ids)
	ids = ids or {}
	local total, done = {}, {}
	for _, def in ipairs(index.list) do
		total[def.cat] = (total[def.cat] or 0) + 1
		if ids[def.id] then
			done[def.cat] = (done[def.cat] or 0) + 1
		end
	end
	local out = {}
	for key, n in pairs(total) do
		if n > 0 and (done[key] or 0) >= n then
			out[key] = true
		end
	end
	return out
end

function K.categoryTitles(index, ids)
	local complete = K.completedCategories(index, ids)
	local out = {}
	for _, c in ipairs(index.categories) do
		local r = (index.categoryRewards or {})[c.key]
		if r and complete[c.key] then
			out[#out + 1] = {key = "achievement_cat:" .. c.key, text = r.title, at = 0, frame = r.frame}
		end
	end
	return out
end

function K.categoryTrack(index, ids)
	ids = ids or {}
	local out = {}
	for _, s in ipairs(K.categorySummary(index, ids)) do
		local r = (index.categoryRewards or {})[s.key]
		if r then
			out[#out + 1] = {key = s.key, name = s.name, done = s.done, total = s.total, title = r.title, frame = r.frame,
				complete = s.total > 0 and s.done >= s.total}
		end
	end
	return out
end

-- ------------------------------------------------------------------------------------------------ SQL
K.TABLE_UNLOCKS = "chaos_achievements"
K.TABLE_STATS = "chaos_achievement_stats"

function K.sqlCreate()
	return {
		"CREATE TABLE IF NOT EXISTS `" .. K.TABLE_UNLOCKS .. "` (`player_id` int(11) NOT NULL, " ..
			"`achievement` varchar(48) NOT NULL, `unlocked_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
			"PRIMARY KEY (`player_id`, `achievement`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
		"CREATE TABLE IF NOT EXISTS `" .. K.TABLE_STATS .. "` (`player_id` int(11) NOT NULL, " ..
			"`stat` varchar(48) NOT NULL, `value` bigint(20) NOT NULL DEFAULT 0, " ..
			"PRIMARY KEY (`player_id`, `stat`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
	}
end

function K.sqlSaveStat(guid, key, value)
	if not validKey(key) then
		return nil
	end
	return string.format("INSERT INTO `%s` (`player_id`, `stat`, `value`) VALUES (%d, '%s', %d) " ..
		"ON DUPLICATE KEY UPDATE `value` = GREATEST(`value`, VALUES(`value`))", K.TABLE_STATS, math.floor(guid), key,
		math.floor(value))
end

-- an offline character: add to (mode "add") or raise (mode "max") a counter in the database
function K.sqlOffline(guid, key, amount, mode)
	if not validKey(key) then
		return nil
	end
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return nil
	end
	local expr = mode == "max" and "GREATEST(`value`, VALUES(`value`))" or "`value` + VALUES(`value`)"
	return string.format("INSERT INTO `%s` (`player_id`, `stat`, `value`) VALUES (%d, '%s', %d) " ..
		"ON DUPLICATE KEY UPDATE `value` = %s", K.TABLE_STATS, math.floor(guid), key, amount, expr)
end

function K.sqlUnlock(guid, id, at)
	if not validKey(id) then
		return nil
	end
	return string.format("INSERT IGNORE INTO `%s` (`player_id`, `achievement`, `unlocked_at`) VALUES (%d, '%s', %d)",
		K.TABLE_UNLOCKS, math.floor(guid), id, math.floor(at or 0))
end

return K
