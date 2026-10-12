-- Seasonal Journey: pure logic (no engine calls), shared by season_journey.lua and server/tests/season_journey_test.lua.
-- The chapters and rewards: season_journey_config.lua. Overview: server/README.md "Seasonal Journey".
--
--   K.validate(cfg)                     -> list of problem strings (startup log, the test)
--   K.journeyOf(cfg, seasonId)          -> the journey of that season or nil
--   K.applies(obj, flags)               flags = {ssf, hc} of the character's season mode
--   K.merge(stats, mode, stat, value)   "add" / "max"; true when the stat changed
--   K.value(stats, stat, level)         the current value of an objective's stat
--   K.chapterOpen(journey, i, ctx)      -> true or false, reason ("Finish ..." / "Reach level ...")
--   K.evaluate(journey, ctx)            -> objectives done now [{chapter, obj}], chapters completed now [{index, chapter}]
--                                          (marks them in ctx.done / ctx.claimed; a chapter is returned once, ever)
--   K.view(journey, ctx, opts)          -> {header, chapters = [{key, name, ..., objectives}]} for the window
--   K.rewardText(reward), K.rewardsText(list)
--   K.pieces(journey, claimed)          -> pieces of the set owned, pieces in total
-- ctx = {level, stats = {stat = n}, flags = {ssf, hc}, done = {objKey = at}, claimed = {chapterKey = at}, now}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosSeasonJourneyCore = ChaosSeasonJourneyCore or {}
local K = ChaosSeasonJourneyCore

K.ONLY = {hc = true, ssf = true, nossf = true, nohc = true}
K.REWARDS = {passxp = true, items = true, look = true, outfit = true, mount = true, title = true}

local function validKey(s)
	return type(s) == "string" and #s > 0 and #s <= 32 and s:match("^[%w_]+$") ~= nil
end

-- ---------------------------------------------------------------- config checks
function K.validate(cfg)
	local problems = {}
	local function bad(text)
		problems[#problems + 1] = text
	end
	if type(cfg) ~= "table" or type(cfg.journeys) ~= "table" or type(cfg.stats) ~= "table" then
		bad("config: journeys and stats must be tables")
		return problems
	end
	for stat, mode in pairs(cfg.stats) do
		if not validKey(stat) or (mode ~= "add" and mode ~= "max") then
			bad("stat " .. tostring(stat) .. ": mode must be add or max")
		end
	end
	for seasonId, j in pairs(cfg.journeys) do
		local where = "journey " .. tostring(seasonId)
		if type(j.name) ~= "string" or type(j.chapters) ~= "table" or #j.chapters == 0 then
			bad(where .. ": name and chapters needed")
		else
			local objKeys, chapKeys, lastLevel = {}, {}, -1
			for i, ch in ipairs(j.chapters) do
				local cw = where .. " chapter " .. i
				if not validKey(ch.key) or chapKeys[ch.key] then
					bad(cw .. ": key missing or duplicate")
				end
				chapKeys[ch.key or ""] = true
				if type(ch.name) ~= "string" or ch.name == "" then
					bad(cw .. ": no name")
				end
				local lvl = tonumber(ch.level) or 0
				if lvl < lastLevel then
					bad(cw .. ": level lower than the chapter before")
				end
				lastLevel = lvl
				if type(ch.objectives) ~= "table" or #ch.objectives == 0 then
					bad(cw .. ": no objectives")
				end
				for _, o in ipairs(ch.objectives or {}) do
					local ow = cw .. " objective " .. tostring(o.key)
					if not validKey(o.key) or objKeys[o.key] then
						bad(ow .. ": key missing or duplicate")
					end
					objKeys[o.key or ""] = true
					if o.stat ~= "level" and not cfg.stats[o.stat or ""] then
						bad(ow .. ": unknown stat " .. tostring(o.stat))
					end
					if type(o.target) ~= "number" or o.target < 1 then
						bad(ow .. ": target must be >= 1")
					end
					if type(o.text) ~= "string" or o.text == "" then
						bad(ow .. ": no text")
					end
					if o.only ~= nil and not K.ONLY[o.only] then
						bad(ow .. ": unknown only " .. tostring(o.only))
					end
				end
				for _, r in ipairs(ch.rewards or {}) do
					if not K.REWARDS[r.kind] then
						bad(cw .. ": unknown reward kind " .. tostring(r.kind))
					elseif (r.kind == "passxp" and not ((tonumber(r.amount) or 0) > 0))
						or (r.kind == "items" and not (r.id and (tonumber(r.count) or 0) > 0))
						or ((r.kind == "look" or r.kind == "mount") and not tonumber(r.id))
						or (r.kind == "outfit" and not (tonumber(r.male) and tonumber(r.female)))
						or (r.kind == "title" and (type(r.title) ~= "string" or r.title == "" or #r.title > 24)) then
						bad(cw .. ": incomplete " .. r.kind .. " reward")
					end
				end
			end
		end
	end
	return problems
end

function K.journeyOf(cfg, seasonId)
	return cfg and cfg.journeys and cfg.journeys[tonumber(seasonId) or -1] or nil
end

-- ---------------------------------------------------------------- objectives
function K.applies(obj, flags)
	flags = flags or {}
	local only = obj.only
	if only == nil then
		return true
	elseif only == "hc" then
		return flags.hc == true
	elseif only == "ssf" then
		return flags.ssf == true
	elseif only == "nossf" then
		return flags.ssf ~= true
	elseif only == "nohc" then
		return flags.hc ~= true
	end
	return false
end

function K.objectivesOf(chapter, flags)
	local out = {}
	for _, o in ipairs(chapter.objectives or {}) do
		if K.applies(o, flags) then
			out[#out + 1] = o
		end
	end
	return out
end

function K.merge(stats, mode, stat, value)
	value = math.floor(tonumber(value) or 0)
	local old = stats[stat] or 0
	local new
	if mode == "max" then
		new = math.max(old, value)
	else
		if value <= 0 then
			return false
		end
		new = old + value
	end
	if new == old then
		return false
	end
	stats[stat] = new
	return true
end

function K.value(stats, stat, level)
	if stat == "level" then
		return tonumber(level) or 0
	end
	return tonumber(stats and stats[stat]) or 0
end

-- ---------------------------------------------------------------- chapters
local function chapterComplete(chapter, ctx)
	for _, o in ipairs(K.objectivesOf(chapter, ctx.flags)) do
		if not ctx.done[o.key] then
			return false
		end
	end
	return true
end

function K.chapterOpen(journey, i, ctx)
	local ch = journey.chapters[i]
	if not ch then
		return false, "Unknown chapter."
	end
	local prev = journey.chapters[i - 1]
	if prev and not (ctx.claimed or {})[prev.key] then
		return false, "Finish " .. prev.name .. " first."
	end
	if (tonumber(ctx.level) or 0) < (tonumber(ch.level) or 0) then
		return false, "Reach level " .. ch.level .. "."
	end
	return true
end

function K.evaluate(journey, ctx)
	ctx.done = ctx.done or {}
	ctx.claimed = ctx.claimed or {}
	local now = ctx.now or 0
	local objectives, chapters = {}, {}
	if not journey then
		return objectives, chapters
	end
	for i, ch in ipairs(journey.chapters) do
		if not K.chapterOpen(journey, i, ctx) then
			break -- later chapters need this one first
		end
		for _, o in ipairs(K.objectivesOf(ch, ctx.flags)) do
			if not ctx.done[o.key] and K.value(ctx.stats, o.stat, ctx.level) >= o.target then
				ctx.done[o.key] = now
				objectives[#objectives + 1] = {chapter = ch, obj = o}
			end
		end
		if not ctx.claimed[ch.key] and chapterComplete(ch, ctx) then
			ctx.claimed[ch.key] = now
			chapters[#chapters + 1] = {index = i, chapter = ch}
		end
	end
	return objectives, chapters
end

-- ---------------------------------------------------------------- texts
function K.rewardText(r)
	if type(r) ~= "table" then
		return ""
	end
	if r.kind == "passxp" then
		return string.format("%d pass XP", r.amount or 0)
	elseif r.kind == "items" then
		return string.format("%d %s", r.count or 1, r.name or ("item " .. tostring(r.id)))
	elseif r.kind == "title" then
		return "Title: " .. tostring(r.title)
	end
	return tostring(r.name or r.kind)
end

function K.rewardsText(list)
	local parts = {}
	for _, r in ipairs(list or {}) do
		parts[#parts + 1] = K.rewardText(r)
	end
	return table.concat(parts, ", ")
end

function K.pieces(journey, claimed)
	local have, total = 0, 0
	for _, ch in ipairs(journey and journey.chapters or {}) do
		for _, r in ipairs(ch.rewards or {}) do
			if r.piece then
				total = total + 1
				if claimed and claimed[ch.key] then
					have = have + 1
				end
			end
		end
	end
	return have, total
end

-- ---------------------------------------------------------------- the window
-- opts = {preview = true (a standard character: no progress), clientId = function(serverId) -> client id}
-- Returns the header and one entry per chapter; the server sends the header with the chapter summaries, then each
-- chapter's objectives as its own message (every message stays far below the 8192-byte limit of one opcode message).
function K.view(journey, ctx, opts)
	opts = opts or {}
	ctx.done = ctx.done or {}
	ctx.claimed = ctx.claimed or {}
	local chapters = {}
	local current
	for i, ch in ipairs(journey.chapters) do
		local open, why = K.chapterOpen(journey, i, ctx)
		local list = K.objectivesOf(ch, opts.preview and {} or ctx.flags)
		if opts.preview then
			-- a preview shows what every mode would see: the mode objectives marked as such
			list = ch.objectives
		end
		local rows, doneCount = {}, 0
		for _, o in ipairs(list) do
			local done = not opts.preview and ctx.done[o.key] ~= nil
			if done then
				doneCount = doneCount + 1
			end
			local progress, target = nil, o.target
			if not opts.preview then
				progress = math.min(o.target, K.value(ctx.stats, o.stat, ctx.level))
			end
			if o.flag then -- a rank or a yes / no: the bar shows 0 / 1, not the number behind it
				target = 1
				progress = progress and (progress >= o.target and 1 or 0) or nil
			end
			rows[#rows + 1] = {key = o.key, text = o.text, target = target, progress = progress, done = done,
				only = o.only}
		end
		local rewards = {}
		for _, r in ipairs(ch.rewards or {}) do
			local cid = (r.kind == "items" or r.kind == "look") and opts.clientId and opts.clientId(r.id) or nil
			local look = r.kind == "outfit" and (opts.female and r.female or r.male) or (r.kind == "mount" and r.clientid) or nil
			rewards[#rewards + 1] = {kind = r.kind, text = K.rewardText(r), piece = r.piece or nil, clientId = cid,
				count = r.kind == "items" and r.count or nil, look = look}
		end
		local state
		if opts.preview then
			state = "preview"
		elseif ctx.claimed[ch.key] then
			state = "done"
		elseif open then
			state = "open"
			current = current or i
		else
			state = "locked"
		end
		chapters[i] = {key = ch.key, name = ch.name, text = ch.text, level = ch.level or 0, state = state,
			lockedWhy = (state == "locked") and why or nil, done = doneCount, total = #rows, objectives = rows,
			rewards = rewards}
	end
	local have, total = K.pieces(journey, not opts.preview and ctx.claimed or nil)
	local finished = 0
	for _, c in ipairs(chapters) do
		if c.state == "done" then
			finished = finished + 1
		end
	end
	return {name = journey.name, set = journey.set, pieces = have, piecesTotal = total, finished = finished,
		current = current, preview = opts.preview or nil}, chapters
end

-- ---------------------------------------------------------------- storage helpers (statements only)
function K.entryKey(kind, key)
	return (kind == "chapter" and "c:" or "o:") .. tostring(key)
end

-- rows of chaos_season_journey -> done, claimed maps
function K.entriesToMaps(rows)
	local done, claimed = {}, {}
	for _, r in ipairs(rows or {}) do
		local kind, key = tostring(r.entry):match("^([oc]):(.+)$")
		if kind == "o" then
			done[key] = tonumber(r.at) or 0
		elseif kind == "c" then
			claimed[key] = tonumber(r.at) or 0
		end
	end
	return done, claimed
end

return K
