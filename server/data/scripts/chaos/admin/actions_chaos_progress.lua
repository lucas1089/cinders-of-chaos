-- Chaos: Progression. Seasons (season.lua ChaosSeason), the season pass (seasonpass.lua ChaosSeasonPass), achievements
-- (achievements.lua ChaosAchievements) and the Ashen Chronicle (chronicle.lua ChaosChronicle): the same functions their
-- staff commands (/season, /seasonpass, /achievements, /chronicle) call, on a chosen character. Season start / end write
-- the same server_config override as /season start|end; the season's own minute check applies it.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "chaos_progress"; def.id = "chaos_progress." .. def.id; ChaosAdminPending[def.id] = def end

local PLAYER = {name = "player", label = "Player", type = "player"}
local ONLINE = {name = "player", label = "Player (online)", type = "player"}

local function sys(name, fn) return ChaosAdmin.system(name, fn) end

-- ------------------------------------------------------------------ seasons (server/README.md "Seasons")
local function seasonLines(S)
	local cfg = Chaos.seasonConfig or {}
	local t, lines = os.time(), {}
	for _, s in ipairs(cfg.seasons or {}) do
		local start, finish = S.times(s, S.ov)
		lines[#lines + 1] = string.format("%d %s: %s, %s - %s%s", s.id, s.name, tostring(S.status(s, t, S.ov)),
			start and os.date("%Y-%m-%d %H:%M", start) or "?", finish and os.date("%Y-%m-%d %H:%M", finish) or "?",
			S.ov[s.id] and " (overridden)" or "")
	end
	local n = 0
	for _ in pairs(S.members or {}) do n = n + 1 end
	lines[#lines + 1] = n .. " character(s) in the running season."
	return lines
end

local function seasonOverride(actor, key, S)
	local value = os.time()
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)",
		db.escapeString(key), db.escapeString(tostring(value))))
	S.loadOverrides()
	return value
end

reg{id = "season_status", name = "Season: status", description = "Every season of season_config.lua with its state and dates, and the running season's character count (as /season).",
	handler = function(actor)
		local S, why = sys("ChaosSeason", "current")
		if not S then return false, why end
		local cur = S.current()
		return true, cur and ("Running: " .. cur.name .. ".") or "No season is running.", seasonLines(S)
	end}

reg{id = "season_player", name = "Season: character", description = "The season flag of one character: its season, migrated or not.",
	params = {PLAYER},
	handler = function(actor, p)
		local S, why = sys("ChaosSeason", "rowOf")
		if not S then return false, why end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		local row = S.rowOf(t.guid)
		if not row then return true, t.name .. " is a standard character." end
		return true, string.format("%s: season %d, %s.", t.name, row.season or 0,
			(row.migrated or 0) > 0 and ("migrated " .. os.date("%Y-%m-%d", row.migrated)) or "not migrated")
	end}

reg{id = "season_start", name = "Season: start now", description = "Starts the given season (0 = the next upcoming one) now: the server_config override of /season start; the season check applies it within a minute.",
	dangerous = true, params = {{name = "season", label = "Season id (0 = upcoming)", type = "int", min = 0, max = 1000, default = 0}},
	handler = function(actor, p)
		local S, why = sys("ChaosSeason", "current")
		if not S then return false, why end
		local cfg = Chaos.seasonConfig
		if S.current() then return false, S.current().name .. " is already running." end
		local t = os.time()
		local s = p.season > 0 and S.byId(cfg.seasons, p.season) or S.upcoming(cfg.seasons, t, S.ov)
		if not s then return false, "No such or no upcoming season in season_config.lua." end
		local _, finish = S.times(s, S.ov)
		if not finish or finish <= t then return false, s.name .. "'s end date has passed: change it in season_config.lua." end
		seasonOverride(actor, cfg.configPrefix .. s.id .. "_start", S)
		return true, s.name .. " starts with the next season check.", seasonLines(S)
	end}

reg{id = "season_end", name = "Season: end now", description = "Ends the running season now (the override of /season end); its characters migrate with the next season check.",
	dangerous = true,
	handler = function(actor)
		local S, why = sys("ChaosSeason", "current")
		if not S then return false, why end
		local s = S.current()
		if not s then return false, "No season is running." end
		seasonOverride(actor, Chaos.seasonConfig.configPrefix .. s.id .. "_end", S)
		return true, s.name .. " ends with the next season check.", seasonLines(S)
	end}

-- ------------------------------------------------------------------ season pass (server/README.md "Season pass")
local function passLine(SP, name, accountId)
	local acc = SP.account(accountId)
	local s, status = SP.shown()
	local tier = ChaosSeasonPassCore and Chaos.seasonPassConfig and ChaosSeasonPassCore.tierOf(Chaos.seasonPassConfig, acc.xp or 0)
	return string.format("%s (account %d): pass %s (%s), %d XP, tier %s.", name, accountId, s and s.name or "none", tostring(status),
		acc.xp or 0, tostring(tier or "?"))
end

reg{id = "pass_view", name = "Season pass: view", description = "The account's season pass XP and tier.",
	params = {PLAYER},
	handler = function(actor, p)
		local SP, why = sys("ChaosSeasonPass", "account")
		if not SP then return false, why end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		return true, passLine(SP, t.name, t.account)
	end}

reg{id = "pass_xp", name = "Season pass: add XP", description = "Adds season pass XP to the account of an online character (as /seasonpass xp).",
	minGroup = 5, params = {ONLINE, {name = "xp", label = "XP", type = "int", min = 1, max = 1000000}},
	handler = function(actor, p)
		local SP, why = sys("ChaosSeasonPass", "addXp")
		if not SP then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local acc = SP.account(t:getAccountId())
		if not SP.active() or not acc.season then return false, "No season pass is running." end
		SP.addXp(acc, p.xp, "admin " .. actor:getName())
		SP.flush(acc)
		pcall(SP.sendState, t, false)
		return true, "+" .. p.xp .. " XP. " .. passLine(SP, t:getName(), t:getAccountId())
	end}

-- ------------------------------------------------------------------ achievements (server/README.md "Achievements")
reg{id = "achievements_view", name = "Achievements: view", description = "Unlocked achievements, points and (with a key) one counter of an online character.",
	params = {ONLINE, {name = "stat", label = "Counter key (optional)", type = "string", max = 48, required = false}},
	handler = function(actor, p)
		local A, why = sys("ChaosAchievements", "unlockedOf")
		if not A then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local ids = {}
		for id in pairs(A.unlockedOf(t)) do ids[#ids + 1] = id end
		table.sort(ids)
		local own, accPoints = A.pointsOf(t)
		local text = string.format("%s: %d unlocked, %s points (account %s).", t:getName(), #ids, tostring(own), tostring(accPoints))
		if p.stat and p.stat ~= "" then
			text = text .. " " .. p.stat .. " = " .. tostring((A.stats[t:getGuid()] or {})[p.stat] or 0)
		end
		return true, text, {table.concat(ids, ", ")}
	end}

reg{id = "achievements_grant", name = "Achievements: grant", description = "Unlocks one achievement with its reward (as /achievements grant).",
	minGroup = 5, params = {ONLINE, {name = "id", label = "Achievement id", type = "string", max = 64}},
	handler = function(actor, p)
		local A, why = sys("ChaosAchievements", "grant")
		if not A then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		if not (A.index and A.index.byId and A.index.byId[p.id]) then return false, "Unknown achievement " .. p.id .. "." end
		if not A.grant(t, p.id) then return false, t:getName() .. ": " .. p.id .. " already unlocked." end
		return true, t:getName() .. ": granted " .. p.id .. "."
	end}

reg{id = "achievements_stat", name = "Achievements: counter", description = "Sets a counter to at least a value, or adds to it (as /achievements stat | add); unlocks follow.",
	minGroup = 5,
	params = {ONLINE, {name = "stat", label = "Counter key", type = "string", max = 48},
		{name = "mode", label = "Mode", type = "select", default = "add", options = {{value = "add", label = "Add"}, {value = "set", label = "Set (at least)"}}},
		{name = "value", label = "Value", type = "int", min = 0, max = 2000000000}},
	handler = function(actor, p)
		local A, why = sys("ChaosAchievements", "progress")
		if not A then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		if not p.stat:match("^[%w_]+$") then return false, "Bad counter key." end
		if p.mode == "set" then A.set(t, p.stat, p.value) else A.progress(t, p.stat, p.value) end
		return true, string.format("%s: %s = %s", t:getName(), p.stat, tostring((A.stats[t:getGuid()] or {})[p.stat] or "?"))
	end}

reg{id = "achievements_reset", name = "Achievements: reset character", description = "Deletes every unlock and counter of the character (as /achievements reset); the character should relog for the retroactive check.",
	dangerous = true, params = {ONLINE},
	handler = function(actor, p)
		local A, why = sys("ChaosAchievements", "grant")
		if not A then return false, why end
		local K = ChaosAchievementsCore
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local guid = t:getGuid()
		db.query("DELETE FROM `" .. K.TABLE_UNLOCKS .. "` WHERE `player_id` = " .. guid)
		db.query("DELETE FROM `" .. K.TABLE_STATS .. "` WHERE `player_id` = " .. guid)
		A.stats[guid], A.unlocked[guid], A.dirty[guid] = {}, {}, {}
		A.accounts[t:getAccountId()] = nil
		return true, t:getName() .. ": achievements and counters cleared (relog for the retroactive check)."
	end}

-- ------------------------------------------------------------------ the Ashen Chronicle (server/README.md "The Ashen Chronicle")
local function chronicleLines(X)
	local K, cfg, st = ChaosChronicleCore, Chaos.chronicleConfig, X.state
	if not st then
		return "No Chronicle is running" .. (X.idle and string.format(" (season %d's world stays: %d chapters).", X.idle.season or 0, X.idle.done or 0) or "."), {}
	end
	local lines = {}
	for _, area in ipairs(cfg.areas or {}) do
		lines[#lines + 1] = string.format("%s: %s", area.name, X.world.open[area.key] and "open" or "closed")
	end
	return string.format("Season %d, arc %s: chapter %d of %d (%s%%).", st.season, st.arc, st.chapter, #K.chapters(cfg, st.arc),
		tostring(K.chapterPct(cfg, st, st.chapter))), lines
end

reg{id = "chronicle_status", name = "Chronicle: status", description = "The running Chronicle: arc, chapter, progress and the areas (as /chronicle).",
	handler = function(actor)
		local X, why = sys("ChaosChronicle", "applyWorld")
		if not X then return false, why end
		local text, lines = chronicleLines(X)
		return true, text, lines
	end}

reg{id = "chronicle_world", name = "Chronicle: apply world", description = "Places the world of the current chapters again (as /chronicle world).",
	handler = function(actor)
		local X, why = sys("ChaosChronicle", "applyWorld")
		if not X then return false, why end
		X.applyWorld()
		return true, "World applied. " .. chronicleLines(X)
	end}

reg{id = "chronicle_complete", name = "Chronicle: complete chapter", description = "Fills every goal of the current chapter and writes it (as /chronicle complete).",
	minGroup = 5, confirm = true,
	handler = function(actor)
		local X, why = sys("ChaosChronicle", "chapterWritten")
		if not X then return false, why end
		local K, cfg, st = ChaosChronicleCore, Chaos.chronicleConfig, X.state
		if not st or K.allDone(cfg, st) then return false, "No chapter to complete." end
		local ci = st.chapter
		for gi, g in ipairs(K.chapters(cfg, st.arc)[ci].goals) do
			st.progress[ci][gi] = g.target
		end
		st.doneAt[ci] = os.time()
		st.chapter = ci + 1
		X.dirty = true
		X.chapterWritten(ci)
		return true, "Chapter " .. ci .. " written. " .. chronicleLines(X)
	end}

reg{id = "chronicle_reset", name = "Chronicle: reset season", description = "Starts the running season's Chronicle again and resets its world (as /chronicle reset): contributions and counted levels are deleted.",
	dangerous = true,
	handler = function(actor)
		local X, why = sys("ChaosChronicle", "saveState")
		if not X then return false, why end
		local K, cfg, st = ChaosChronicleCore, Chaos.chronicleConfig, X.state
		X.idle = nil
		if st then
			X.state = K.newState(cfg, st.arc, st.season, os.time())
			X.dirty = true
			db.asyncQuery(string.format("DELETE FROM `%s` WHERE `season` = %d", cfg.tables.contrib, st.season))
			db.asyncQuery(string.format("DELETE FROM `%s` WHERE `season` = %d", cfg.tables.levels, st.season))
			X.levels = {}
			X.saveState(X.state)
		end
		X.applyWorld()
		return true, "The Chronicle of this season starts again; the world is reset."
	end}
