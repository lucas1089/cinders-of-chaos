-- The Ashen Chronicle: pure logic (no engine API), tested by server/tests/chronicle_test.lua. Engine glue:
-- chronicle.lua; numbers: chronicle_config.lua; story: chronicle_text.lua. Overview: server/README.md "The Ashen Chronicle".
--
-- State of one season (one per season id, kept in the chaos_chronicle_* tables):
--   {season, arc, chapter (the open chapter; #chapters + 1 once all are written), progress = {[ci] = {[gi] = n}},
--    doneAt = {[ci] = t}, contrib = {[ci] = {[guid] = {name, points}}}, startedAt, finishedAt}
-- Events: {kind = "worldboss" | "rift" | "omen" | "ascended" | "cinderheart" | "raid" | "level" | "event", band, level,
-- event, count}. Only the open chapter counts; a goal that is met takes no more progress and gives no more points.
-- The world of a season is replayed from its written chapters (K.worldOf), so a restart, a reset and a new season are
-- all the same diff (K.worldDiff). Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosChronicleCore = ChaosChronicleCore or {}
local K = ChaosChronicleCore
local floor = math.floor

K.KINDS = {worldboss = true, rift = true, omen = true, ascended = true, cinderheart = true, raid = true, level = true,
	event = true}

-- ---------------------------------------------------------------- config
function K.arcOf(cfg, seasonId)
	local key = cfg.arcs and cfg.arcs[tonumber(seasonId) or -1]
	if key and cfg.chapters and cfg.chapters[key] then
		return key
	end
	return nil
end

function K.chapters(cfg, arc)
	return (cfg.chapters and cfg.chapters[arc or ""]) or {}
end

function K.areaByKey(cfg, key)
	for i, a in ipairs(cfg.areas or {}) do
		if a.key == key then
			return a, i
		end
	end
	return nil
end

function K.bandOf(cfg, tier)
	tier = tonumber(tier) or 0
	for _, b in ipairs(cfg.riftBands or {}) do
		if tier >= b.min and tier <= b.max then
			return b.key
		end
	end
	return nil
end

-- every problem of the config and the text (empty list = fine)
function K.validate(cfg, text)
	local out = {}
	local function bad(s)
		out[#out + 1] = s
	end
	local gs = cfg.globalStorage or {}
	if not (gs.base and gs.base >= 7102100 and gs.base + 9 <= 7102119 and gs.done and gs.season) then
		bad("globalStorage must stay inside 7102100-7102119")
	end
	if not (cfg.gateAid and cfg.gateAid >= 47920 and cfg.gateAid + #(cfg.areas or {}) - 1 <= 47929) then
		bad("gateAid must stay inside 47920-47929")
	end
	local areaKeys = {}
	for _, a in ipairs(cfg.areas or {}) do
		if areaKeys[a.key] then
			bad("area " .. tostring(a.key) .. " twice")
		end
		areaKeys[a.key] = true
		if type(a.arrival) ~= "table" or #a.arrival ~= 3 then
			bad("area " .. tostring(a.key) .. ": no arrival offset")
		end
	end
	local sets = cfg.town and cfg.town.sets or {}
	for key, set in pairs(sets) do
		for i, p in ipairs(set.pieces or {}) do
			if not tonumber(p.id) or type(p.at) ~= "table" or #p.at == 0 then
				bad("town set " .. key .. " piece " .. i .. ": id and at")
			end
		end
	end
	for seasonId, arc in pairs(cfg.arcs or {}) do
		local chs = cfg.chapters and cfg.chapters[arc]
		local tarc = text and text.arcs and text.arcs[arc]
		if not chs then
			bad("season " .. tostring(seasonId) .. ": arc " .. tostring(arc) .. " has no chapters")
		elseif #chs < 4 or #chs > 6 then
			bad("arc " .. arc .. ": " .. #chs .. " chapters (4 to 6)")
		end
		if not tarc then
			bad("arc " .. tostring(arc) .. " has no text")
		end
		local seen = {}
		for ci, ch in ipairs(chs or {}) do
			if seen[ch.key] then
				bad("arc " .. arc .. ": chapter key " .. tostring(ch.key) .. " twice")
			end
			seen[ch.key] = true
			local tch = tarc and tarc.chapters and tarc.chapters[ci]
			if not tch or tch.key ~= ch.key then
				bad("arc " .. arc .. " chapter " .. ci .. ": the text has another key")
			else
				for _, f in ipairs({"title", "text", "done", "world", "npc"}) do
					if type(tch[f]) ~= "table" or not tch[f].en or not tch[f].pt then
						bad("arc " .. arc .. " chapter " .. ci .. ": " .. f .. " needs en and pt")
					end
				end
			end
			if type(ch.goals) ~= "table" or #ch.goals == 0 then
				bad("arc " .. arc .. " chapter " .. ci .. ": no goals")
			end
			for gi, g in ipairs(ch.goals or {}) do
				if not K.KINDS[g.kind] then
					bad("arc " .. arc .. " chapter " .. ci .. " goal " .. gi .. ": unknown kind " .. tostring(g.kind))
				end
				if not (tonumber(g.target) and g.target >= 1 and g.target == floor(g.target)) then
					bad("arc " .. arc .. " chapter " .. ci .. " goal " .. gi .. ": target")
				end
				if g.kind == "rift" then
					local ok = false
					for _, b in ipairs(cfg.riftBands or {}) do
						ok = ok or b.key == g.band
					end
					if not ok then
						bad("arc " .. arc .. " chapter " .. ci .. " goal " .. gi .. ": unknown band " .. tostring(g.band))
					end
				elseif g.kind == "level" and not tonumber(g.level) then
					bad("arc " .. arc .. " chapter " .. ci .. " goal " .. gi .. ": level")
				elseif g.kind == "event" and type(g.event) ~= "string" then
					bad("arc " .. arc .. " chapter " .. ci .. " goal " .. gi .. ": event key")
				end
			end
			local w = ch.world or {}
			for _, key in ipairs(w.open or {}) do
				if not areaKeys[key] then
					bad("arc " .. arc .. " chapter " .. ci .. ": unknown area " .. tostring(key))
				end
			end
			for _, list in ipairs({(w.town or {}).add or {}, (w.town or {}).remove or {}}) do
				for _, key in ipairs(list) do
					if not sets[key] then
						bad("arc " .. arc .. " chapter " .. ci .. ": unknown town set " .. tostring(key))
					end
				end
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- state
function K.newState(cfg, arc, seasonId, now)
	local st = {season = tonumber(seasonId) or 0, arc = arc, chapter = 1, progress = {}, doneAt = {}, contrib = {},
		startedAt = now or 0, finishedAt = 0}
	for ci, ch in ipairs(K.chapters(cfg, arc)) do
		st.progress[ci] = {}
		st.contrib[ci] = {}
		for gi = 1, #ch.goals do
			st.progress[ci][gi] = 0
		end
	end
	return st
end

function K.doneCount(cfg, st)
	if not st then
		return 0
	end
	local n = 0
	for ci = 1, #K.chapters(cfg, st.arc) do
		if st.doneAt[ci] then
			n = ci
		else
			break
		end
	end
	return n
end

function K.allDone(cfg, st)
	return st ~= nil and K.doneCount(cfg, st) >= #K.chapters(cfg, st.arc) and #K.chapters(cfg, st.arc) > 0
end

-- does a goal take this event?
function K.goalMatches(goal, ev)
	if type(goal) ~= "table" or type(ev) ~= "table" or goal.kind ~= ev.kind then
		return false
	end
	if goal.kind == "rift" then
		return goal.band == ev.band
	elseif goal.kind == "level" then
		return tonumber(ev.level) == tonumber(goal.level)
	elseif goal.kind == "event" then
		return goal.event == ev.event
	end
	return true
end

-- the points of one contribution
function K.pointsOf(cfg, ev)
	local p = cfg.points or {}
	if ev.kind == "rift" then
		return p["rift_" .. tostring(ev.band)] or 1
	end
	return p[ev.kind] or 1
end

local function goalDone(ch, prog, gi)
	return (prog[gi] or 0) >= ch.goals[gi].target
end

function K.chapterComplete(ch, prog)
	for gi = 1, #ch.goals do
		if not goalDone(ch, prog, gi) then
			return false
		end
	end
	return true
end

-- members: {{guid, name}} (staff already left out). opts.progress = false adds the contributions only (a raid run
-- counted once, its other members). Returns {matched, completed = chapter index or nil, points}.
function K.addEvent(cfg, st, ev, members, now, opts)
	local res = {matched = false, points = 0}
	if not st or type(ev) ~= "table" then
		return res
	end
	local chs = K.chapters(cfg, st.arc)
	local ci = st.chapter
	local ch = chs[ci]
	if not ch then
		return res
	end
	local prog = st.progress[ci]
	local count = math.max(1, floor(tonumber(ev.count) or 1))
	local matchedGoal
	for gi, g in ipairs(ch.goals) do
		if K.goalMatches(g, ev) and not goalDone(ch, prog, gi) then
			matchedGoal = gi
			break
		end
	end
	if not matchedGoal then
		return res
	end
	res.matched = true
	res.chapter = ci
	if not opts or opts.progress ~= false then
		prog[matchedGoal] = math.min(ch.goals[matchedGoal].target, (prog[matchedGoal] or 0) + count)
	end
	local pts = K.pointsOf(cfg, ev) * count
	local book = st.contrib[ci]
	for _, m in ipairs(members or {}) do
		local guid = tonumber(m.guid)
		if guid then
			local e = book[guid] or {name = tostring(m.name or ""), points = 0}
			if m.name and m.name ~= "" then
				e.name = tostring(m.name)
			end
			e.points = e.points + pts
			e.at = now
			e.dirty = true
			book[guid] = e
			res.points = pts
		end
	end
	if K.chapterComplete(ch, prog) then
		st.doneAt[ci] = now or 0
		st.chapter = ci + 1
		res.completed = ci
	end
	return res
end

-- the points of an event for members of a run that was counted already (the raid's other members, the other
-- defenders of an invasion): into chapter ci's book, even when that run's progress wrote the chapter
function K.credit(cfg, st, ci, ev, members, now)
	local book = st and st.contrib[ci]
	if not book or type(ev) ~= "table" then
		return 0
	end
	local pts = K.pointsOf(cfg, ev) * math.max(1, floor(tonumber(ev.count) or 1))
	for _, m in ipairs(members or {}) do
		local guid = tonumber(m.guid)
		if guid then
			local e = book[guid] or {name = tostring(m.name or ""), points = 0}
			if m.name and m.name ~= "" then
				e.name = tostring(m.name)
			end
			e.points = e.points + pts
			e.at = now
			e.dirty = true
			book[guid] = e
		end
	end
	return pts
end

-- percent of a chapter (the mean of its goals, each capped at 100), one decimal
function K.chapterPct(cfg, st, ci)
	local ch = K.chapters(cfg, st.arc)[ci]
	if not ch then
		return 0
	end
	if st.doneAt[ci] then
		return 100
	end
	local sum = 0
	for gi, g in ipairs(ch.goals) do
		sum = sum + math.min(1, (st.progress[ci][gi] or 0) / g.target)
	end
	return floor(sum / #ch.goals * 1000) / 10
end

-- the contributors of a chapter, best first (ties: the earlier, then the lower guid): {{guid, name, points}}
function K.top(book, n)
	local list = {}
	for guid, e in pairs(book or {}) do
		if (e.points or 0) > 0 then
			list[#list + 1] = {guid = guid, name = e.name, points = e.points, at = e.at or 0}
		end
	end
	table.sort(list, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.guid < b.guid
	end)
	local out = {}
	for i = 1, math.min(n or #list, #list) do
		out[i] = list[i]
	end
	return out
end

-- the rows of the record at the season's end: {{chapter, place, guid, name, points}}
function K.recordRows(cfg, st, n)
	local rows = {}
	for ci = 1, #K.chapters(cfg, st.arc) do
		for place, e in ipairs(K.top(st.contrib[ci], n or cfg.topRecorded or 10)) do
			rows[#rows + 1] = {chapter = ci, place = place, guid = e.guid, name = e.name, points = e.points}
		end
	end
	return rows
end

-- the level thresholds the open chapter counts (a level-up from oldLevel to newLevel crossing one is an event)
function K.levelsCrossed(cfg, st, oldLevel, newLevel)
	local out = {}
	local ch = st and K.chapters(cfg, st.arc)[st.chapter]
	for _, g in ipairs(ch and ch.goals or {}) do
		if g.kind == "level" and (tonumber(oldLevel) or 0) < g.level and (tonumber(newLevel) or 0) >= g.level then
			out[#out + 1] = g.level
		end
	end
	return out
end

-- the events of a run the competitive records accepted (ChaosRecords.submit(run) returned true)
function K.eventsOfRun(cfg, run)
	if type(run) ~= "table" then
		return {}
	end
	local b = run.board
	if b == "wb_time" then
		return {{kind = "worldboss"}}
	elseif b == "rift_tier" then
		local band = K.bandOf(cfg, run.value)
		return band and {{kind = "rift", band = band}} or {}
	elseif b == "omen" then
		return {{kind = "omen"}}
	elseif b == "ascended" then
		return {{kind = run.variant == "cinder" and "cinderheart" or "ascended"}}
	elseif b == "raid" then
		return {{kind = "raid"}}
	end
	return {}
end

-- ---------------------------------------------------------------- the world
-- what the world looks like after `done` chapters of `arc`: {open = {[areaKey] = true}, town = {[setKey] = true},
-- flags = done}
function K.worldOf(cfg, arc, done)
	local w = {open = {}, town = {}, flags = 0}
	for ci, ch in ipairs(K.chapters(cfg, arc)) do
		if ci > (done or 0) then
			break
		end
		local cw = ch.world or {}
		for _, key in ipairs(cw.open or {}) do
			w.open[key] = true
		end
		for _, key in ipairs((cw.town or {}).remove or {}) do
			w.town[key] = nil
		end
		for _, key in ipairs((cw.town or {}).add or {}) do
			w.town[key] = true
		end
		w.flags = ci
	end
	return w
end

local function sortedKeys(t)
	local out = {}
	for k in pairs(t or {}) do
		out[#out + 1] = k
	end
	table.sort(out)
	return out
end

-- from the world `cur` (what is placed now) to `want`: {openAreas, closeAreas, addSets, removeSets} (sorted keys)
function K.worldDiff(cur, want)
	cur = cur or {open = {}, town = {}}
	want = want or {open = {}, town = {}}
	local d = {openAreas = {}, closeAreas = {}, addSets = {}, removeSets = {}}
	for _, k in ipairs(sortedKeys(want.open)) do
		if not cur.open[k] then
			d.openAreas[#d.openAreas + 1] = k
		end
	end
	for _, k in ipairs(sortedKeys(cur.open)) do
		if not want.open[k] then
			d.closeAreas[#d.closeAreas + 1] = k
		end
	end
	for _, k in ipairs(sortedKeys(want.town)) do
		if not cur.town[k] then
			d.addSets[#d.addSets + 1] = k
		end
	end
	for _, k in ipairs(sortedKeys(cur.town)) do
		if not want.town[k] then
			d.removeSets[#d.removeSets + 1] = k
		end
	end
	return d
end

-- the position of an area's arrival tile, or nil while the owner has not placed it
function K.arrivalOf(area)
	if type(area) ~= "table" or type(area.at) ~= "table" or type(area.arrival) ~= "table" then
		return nil
	end
	local at, a = area.at, area.arrival
	local x, y, z = tonumber(at.x or at[1]), tonumber(at.y or at[2]), tonumber(at.z or at[3])
	if not (x and y and z) then
		return nil
	end
	return {x = x + a[1], y = y + a[2], z = z + (a[3] or 0)}
end

function K.gateOf(area)
	local g = type(area) == "table" and area.gate
	if type(g) ~= "table" then
		return nil
	end
	local x, y, z = tonumber(g.x or g[1]), tonumber(g.y or g[2]), tonumber(g.z or g[3])
	if not (x and y and z) then
		return nil
	end
	return {x = x, y = y, z = z}
end

-- ---------------------------------------------------------------- texts and payloads
local function pick(text, field, lang)
	if text and text.pick then
		return text.pick(field, lang)
	end
	if type(field) == "table" then
		return lang == "pt" and (field.pt or field.en) or (field.en or field.pt)
	end
	return field
end

function K.fmt(n)
	n = floor(tonumber(n) or 0)
	local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (n < 0 and "-" or "") .. s
end

-- a goal's label ("World bosses slain", "Rifts sealed, tiers 6-10", "Characters reaching level 100")
function K.goalLabel(cfg, goal)
	if goal.kind == "worldboss" then
		return "World bosses slain"
	elseif goal.kind == "rift" then
		for _, b in ipairs(cfg.riftBands or {}) do
			if b.key == goal.band then
				return b.min == b.max and string.format("Rifts sealed, tier %d", b.min) or
					string.format("Rifts sealed, tiers %d-%d", b.min, b.max)
			end
		end
		return "Rifts sealed"
	elseif goal.kind == "omen" then
		return "Omen guardians slain"
	elseif goal.kind == "ascended" then
		return "Ascended Omens slain"
	elseif goal.kind == "cinderheart" then
		return "The Cinderheart slain"
	elseif goal.kind == "raid" then
		return "Ashen Sepulchre clears"
	elseif goal.kind == "level" then
		return string.format("Characters reaching level %d", goal.level)
	elseif goal.kind == "event" then
		return goal.event == "invasion" and "Invasions repelled" or ("Events: " .. tostring(goal.event))
	end
	return tostring(goal.kind)
end

K.GOAL_PT = {worldboss = "Chefes do mundo derrotados", omen = "Guardiões Omen derrotados",
	ascended = "Ascended Omens derrotados", cinderheart = "O Cinderheart derrotado", raid = "Ashen Sepulchre concluído",
	invasion = "Invasões repelidas"}

function K.goalLabelPt(cfg, goal)
	if goal.kind == "rift" then
		for _, b in ipairs(cfg.riftBands or {}) do
			if b.key == goal.band then
				return b.min == b.max and string.format("Rifts selados, tier %d", b.min) or
					string.format("Rifts selados, tiers %d-%d", b.min, b.max)
			end
		end
		return "Rifts selados"
	elseif goal.kind == "level" then
		return string.format("Personagens chegando ao nível %d", goal.level)
	elseif goal.kind == "event" then
		return K.GOAL_PT[goal.event] or ("Eventos: " .. tostring(goal.event))
	end
	return K.GOAL_PT[goal.kind] or K.goalLabel(cfg, goal)
end

-- the broadcast when chapter ci is written
function K.chapterText(text, arc, ci, lang)
	local tarc = text and text.arcs and text.arcs[arc]
	local ch = tarc and tarc.chapters[ci]
	if not ch then
		return nil
	end
	return pick(text, ch.done, lang)
end

-- the Discord queue row of a written chapter, in discord.lua's shape (ChaosDiscord.queue): {kind, channel, title, text,
-- fields = {{name, value, inline}}}; top: the names already filtered for privacy
function K.discordRow(cfg, text, st, ci, top, channel)
	local tarc = text and text.arcs and text.arcs[st.arc]
	local ch = tarc and tarc.chapters[ci]
	if not ch then
		return nil
	end
	local names = {}
	for i, e in ipairs(top or {}) do
		if i > 3 then
			break
		end
		names[#names + 1] = e.name
	end
	local fields = {{name = "What changed", value = pick(text, ch.world, "en"), inline = false}}
	if #names > 0 then
		fields[2] = {name = "Carried by", value = table.concat(names, ", "), inline = false}
	end
	return {kind = cfg.discordEvent or "chronicle", channel = channel or "announce",
		title = pick(text, tarc.title, "en") .. " - " .. pick(text, ch.title, "en"), text = pick(text, ch.done, "en"), fields = fields}
end

-- the Discord row of the season's start or end
function K.discordSeasonRow(cfg, text, st, finished, channel)
	local tarc = text and text.arcs and text.arcs[st.arc]
	if not tarc then
		return nil
	end
	return {kind = cfg.discordEvent or "chronicle", channel = channel or "announce", title = pick(text, tarc.title, "en"),
		text = finished and (K.closingText(cfg, st, "en") .. " " .. pick(text, tarc.ending, "en")) or pick(text, tarc.intro, "en"),
		fields = {}}
end

-- the window's state. opts: {now, seasonName, guid (the viewer), tops = {[ci] = {{name, points}}} (already filtered for
-- privacy), mine = {[ci] = points}, record = {{season, name, chapters = {{i, title, top}}}}, areaReady = {[key] = bool}}
function K.payload(cfg, text, st, opts)
	opts = opts or {}
	local out = {now = opts.now or 0, season = opts.seasonName or "", active = st ~= nil, chapters = {}, record = opts.record or {}}
	if not st then
		return out
	end
	local tarc = text and text.arcs and text.arcs[st.arc] or {}
	out.arc = st.arc
	out.title = {en = pick(text, tarc.title, "en"), pt = pick(text, tarc.title, "pt")}
	out.intro = {en = pick(text, tarc.intro, "en"), pt = pick(text, tarc.intro, "pt")}
	local done = K.doneCount(cfg, st)
	if K.allDone(cfg, st) then
		out.ending = {en = pick(text, tarc.ending, "en"), pt = pick(text, tarc.ending, "pt")}
	end
	for ci, ch in ipairs(K.chapters(cfg, st.arc)) do
		local tch = tarc.chapters and tarc.chapters[ci] or {}
		local state = st.doneAt[ci] and "done" or (ci == st.chapter and "open" or "locked")
		local c = {i = ci, key = ch.key, state = state, pct = K.chapterPct(cfg, st, ci), doneAt = st.doneAt[ci],
			title = {en = pick(text, tch.title, "en"), pt = pick(text, tch.title, "pt")}, goals = {},
			mine = opts.mine and opts.mine[ci] or 0, top = {}}
		if state ~= "locked" then
			local tx = tch.text or {}
			c.text = {en = tx.en or {}, pt = tx.pt or {}}
		end
		if state == "done" then
			c.world = {en = pick(text, tch.world, "en"), pt = pick(text, tch.world, "pt")}
			local closed = {}
			for _, key in ipairs((ch.world or {}).open or {}) do
				if opts.areaReady and opts.areaReady[key] == false then
					closed[#closed + 1] = key
				end
			end
			if #closed > 0 then
				c.pending = closed -- the story opened it; the owner has not placed the area yet
			end
		end
		for gi, g in ipairs(ch.goals) do
			c.goals[gi] = {l = K.goalLabel(cfg, g), lp = K.goalLabelPt(cfg, g), p = (st.progress[ci] or {})[gi] or 0,
				t = g.target}
		end
		for i, e in ipairs(opts.tops and opts.tops[ci] or {}) do
			c.top[i] = {n = e.name, p = e.points}
		end
		out.chapters[ci] = c
	end
	out.done = done
	return out
end

-- the login line while a Chronicle runs (lang "pt" or "en")
function K.loginLine(cfg, text, st, lang)
	if not st then
		return nil
	end
	local tarc = text and text.arcs and text.arcs[st.arc]
	if not tarc then
		return nil
	end
	local pt = lang == "pt"
	if K.allDone(cfg, st) then
		return string.format(pt and "%s: todos os capítulos estão escritos. Aventura > Crônica mostra quem os carregou." or
			"%s: every chapter is written. Adventure > Chronicle shows who carried them.", pick(text, tarc.title, lang))
	end
	local ch = tarc.chapters[st.chapter]
	return string.format(pt and "%s: %s está aberto, %s%% escrito. Aventura > Crônica." or "%s: %s is open, %s%% written. Adventure > Chronicle.",
		pick(text, tarc.title, lang), pick(text, ch and ch.title, lang) or "?", tostring(K.chapterPct(cfg, st, st.chapter)))
end

-- the season's closing line
function K.closingText(cfg, st, lang)
	local done, all = K.doneCount(cfg, st), #K.chapters(cfg, st.arc)
	if lang == "pt" then
		return string.format("O Cronista fecha o livro desta temporada: %d de %d capítulos escritos.", done, all)
	end
	return string.format("The Chronicler closes the book of this season: %d of %d chapters written.", done, all)
end

-- ---------------------------------------------------------------- wrapping other scripts' functions
-- ChaosWrapChain (wrapchain_core.lua): hook a public function once even under other wrappers. One copy only: a
-- second definition here would not know the dispatchers of the first.
function K.ensureWrapChain()
	if not (ChaosWrapChain and ChaosWrapChain.wrap) then
		pcall(dofile, "data/scripts/chaos/wrapchain_core.lua")
	end
	return ChaosWrapChain
end

return K
