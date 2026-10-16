-- Chaos: Instances & PvP. Every instance type (instance_limits.lua ChaosInstanceLimits: list, close, waiting lines),
-- rifts (rift.lua ChaosRift), the Infinity Tower seasons (infinitytower.lua ChaosTower), the arena (arena.lua
-- ChaosArena), the battleground (battleground.lua ChaosBattleground) and the guild siege (siege.lua ChaosSiege): what
-- /instances, /rift, /towerseason, /towerrun, /arena, /bg and /siege do.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "chaos_instances"; def.id = "chaos_instances." .. def.id; ChaosAdminPending[def.id] = def end

local ONLINE = {name = "player", label = "Player (online)", type = "player"}

local function sys(name, fn) return ChaosAdmin.system(name, fn) end

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

-- ------------------------------------------------------------------ every instance (server/README.md "Instance limits")
reg{id = "instances_list", name = "Instances: running", description = "Every running instance of every system (dungeons, rifts, tower, raids, pockets, trials, arena, ...) with its id, time left and players (as /instances).",
	params = {{name = "type", label = "Type filter (optional)", type = "string", max = 24, required = false}},
	handler = function(actor, p)
		local IL, why = sys("ChaosInstanceLimits", "runs")
		if not IL then return false, why end
		local lines = {}
		for _, r in ipairs(IL.runs()) do
			if not p.type or p.type == "" or r.key == p.type:lower() then lines[#lines + 1] = IL.describe(r) end
		end
		return true, #lines .. " instance(s) running.", lines
	end}

reg{id = "instances_close", name = "Instances: close", description = "Ends one instance by type and id (everyone out, no reward, the system's failure rule), as /instances close.",
	minGroup = 4, confirm = true,
	params = {{name = "type", label = "Type (from Instances: running)", type = "string", max = 24},
		{name = "id", label = "Id (from Instances: running)", type = "string", max = 24}},
	handler = function(actor, p)
		local IL, why = sys("ChaosInstanceLimits", "close")
		if not IL then return false, why end
		local ok, text = IL.close(p.type:lower(), tonumber(p.id) or p.id, "A gamemaster closed it.")
		return ok and true or false, (ok and "" or "Not closed: ") .. tostring(text)
	end}

reg{id = "instances_lines", name = "Instances: waiting lines", description = "Who waits for a free slot, per instance type (as /instances line).",
	handler = function(actor)
		local IL, why = sys("ChaosInstanceLimits", "runs")
		if not IL then return false, why end
		local K, lines = ChaosInstanceLimitsCore, {}
		for key, list in pairs(IL.lines or {}) do
			if K and K.waitPrune then K.waitPrune(list, os.time()) end
			if #list > 0 then
				local names = {}
				for _, e in ipairs(list) do names[#names + 1] = e.name or tostring(e.id) end
				lines[#lines + 1] = key .. ": " .. table.concat(names, ", ")
			end
		end
		return true, #lines > 0 and "Waiting lines" or "Nobody is waiting.", lines
	end}

-- ------------------------------------------------------------------ rifts (server/README.md "Rifts")
reg{id = "rift_status", name = "Rift: status", description = "Running rifts (tier, kills, time, players) and the state of every rift slot (as /rift status).",
	handler = function(actor)
		local RF, why = sys("ChaosRift", "giveOmenKey")
		local R, cfg = ChaosRiftCore, ChaosRiftConfig
		if not RF or not R or not cfg then return false, why or "rift.lua is not loaded." end
		local lines = {}
		for slot, run in pairs(RF.runs or {}) do
			local names = {}
			for _, e in pairs(run.players or {}) do names[#names + 1] = e.name end
			lines[#lines + 1] = string.format("slot %d: run %d tier %d %s, %d/%d, %ds left, players %s", slot, run.id, run.key.tier, run.state,
				run.killed, run.total, R.timeLeft(run, os.time()), table.concat(names, ", "))
		end
		local states = {}
		for slot = 0, R.slotCount(cfg) - 1 do
			local st = RF.slots[slot] or {state = "empty"}
			states[st.state] = (states[st.state] or 0) + 1
		end
		local parts = {}
		for k, v in pairs(states) do parts[#parts + 1] = v .. " " .. k end
		table.sort(parts)
		return true, string.format("%d rift(s) running; slots: %s; unusable: %d.", count(RF.runs), table.concat(parts, ", "), count(RF.bad)), lines
	end}

reg{id = "rift_omen_key", name = "Rift: give Omen Key", description = "Gives an Omen Key (a guardian kind, empty = random) to a character (as /rift omen).",
	minGroup = 5, params = {ONLINE, {name = "kind", label = "Omen kind (key or number, optional)", type = "string", max = 24, required = false}},
	handler = function(actor, p)
		local RF, why = sys("ChaosRift", "giveOmenKey")
		if not RF then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local kind
		if p.kind and p.kind ~= "" then
			kind = ChaosRiftCore.omenKind(ChaosRiftConfig, tonumber(p.kind) or p.kind)
			if not kind then return false, "Unknown omen kind " .. p.kind .. "." end
		end
		RF.giveOmenKey(t, kind and kind.key or nil, "GM omen key")
		return true, t:getName() .. " got an Omen Key."
	end}

-- ------------------------------------------------------------------ the Infinity Tower (server/README.md "Infinity Tower")
reg{id = "tower_season", name = "Tower: season", description = "The current Tower Season, its end and the last season paid out (as /towerseason).",
	handler = function(actor)
		local T, why = sys("ChaosTower", "checkSeasons")
		if not T or not T.currentSeason then return false, why or "infinitytower.lua is not loaded." end
		local season, finish = T.currentSeason()
		return true, string.format("Tower Season %d ends %s.", season, finish and os.date("%Y-%m-%d %H:%M", finish) or "?")
	end}

reg{id = "tower_pay", name = "Tower: pay ended seasons", description = "Runs the season-end check now: pays only seasons that have ended (idempotent), as /towerseason pay.",
	minGroup = 5, confirm = true,
	handler = function(actor)
		local T, why = sys("ChaosTower", "checkSeasons")
		if not T then return false, why end
		local n = T.checkSeasons(false) or 0
		return true, n > 0 and (n .. " ended season(s) paid out.") or "No ended season to pay out."
	end}

reg{id = "tower_record", name = "Tower: record a run", description = "Records a run for a character (floors, seconds) so the window, ranking and milestones can be checked (as /towerrun).",
	minGroup = 5,
	params = {ONLINE, {name = "floors", label = "Floors cleared", type = "int", min = 1, max = 1000},
		{name = "seconds", label = "Seconds", type = "int", min = 1, max = 86400}},
	handler = function(actor, p)
		local T, why = sys("ChaosTower", "recordRun")
		if not T then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		T.recordRun(t, p.floors, p.seconds)
		return true, string.format("%s: run of %d floor(s) in %d s recorded.", t:getName(), p.floors, p.seconds)
	end}

-- ------------------------------------------------------------------ arena and battleground
reg{id = "arena_status", name = "Arena: status", description = "Matches running, the queue and unusable slots (as /arena slots); with a player, the ratings.",
	params = {{name = "player", label = "Player (optional)", type = "player", required = false}},
	handler = function(actor, p)
		local S, why = sys("ChaosArena", "stopAll")
		if not S then return false, why end
		local lines = {}
		for slot, w in pairs(S.bad or {}) do lines[#lines + 1] = "bad slot " .. slot .. ": " .. tostring(w) end
		if p.player and p.player ~= "" then
			local t, err = ChaosAdmin.targetAny(actor, p.player)
			if not t then return false, err end
			local r = S.loadRatings(t.guid)
			for mode, e in pairs(r or {}) do
				lines[#lines + 1] = string.format("%s %s: %d (%d-%d-%d)", t.name, mode, e.rating or 0, e.wins or 0, e.losses or 0, e.draws or 0)
			end
		end
		return true, string.format("Arena: %d match(es) running, %d in queue.", count(S.matches), #(S.queue or {})), lines
	end}

reg{id = "arena_stop", name = "Arena: stop all", description = "Stops every arena match (not rated), as /arena stop.",
	minGroup = 5, confirm = true,
	handler = function(actor)
		local S, why = sys("ChaosArena", "stopAll")
		if not S then return false, why end
		return true, string.format("Arena: %d match(es) stopped (not rated).", S.stopAll() or 0)
	end}

reg{id = "bg_status", name = "Battleground: status", description = "Matches, queue entries and unusable slots (as /bg slots).",
	handler = function(actor)
		local B, why = sys("ChaosBattleground", "stopAll")
		if not B then return false, why end
		local lines = {}
		for slot, w in pairs(B.bad or {}) do lines[#lines + 1] = "bad slot " .. slot .. ": " .. tostring(w) end
		local open = Chaos.battlegroundConfig == nil or Chaos.battlegroundConfig.enabled ~= false
		return true, string.format("Battleground: %d match(es), %d queue entries, queue %s.", count(B.matches), #(B.queue or {}),
			open and "open" or "closed"), lines
	end}

reg{id = "bg_stop", name = "Battleground: stop all", description = "Stops every battleground match (not rated), as /bg stop.",
	minGroup = 5, confirm = true,
	handler = function(actor)
		local B, why = sys("ChaosBattleground", "stopAll")
		if not B then return false, why end
		return true, string.format("Battleground: %d match(es) stopped (not rated).", B.stopAll() or 0)
	end}

-- ------------------------------------------------------------------ the guild siege (server/README.md "Guild siege")
reg{id = "siege_status", name = "Siege: status", description = "The guild siege's state and the next date (as /siege).",
	handler = function(actor)
		local S, why = sys("ChaosSiege", "status")
		if not S then return false, why end
		local lines = {}
		for line in tostring(S.status()):gmatch("[^\n]+") do lines[#lines + 1] = line end
		return true, "Guild siege", lines
	end}

local SIEGE_OPS = {{value = "start", label = "Start now (gathering)"}, {value = "match", label = "Open the gates now"},
	{value = "end", label = "End with results"}, {value = "stop", label = "Cancel (no results)"}}

reg{id = "siege_control", name = "Siege: control", description = "Start the siege, open the gates, end it with results or cancel it (as /siege start | match | end | stop).",
	minGroup = 5, confirm = true, params = {{name = "op", label = "What", type = "select", default = "start", options = SIEGE_OPS}},
	handler = function(actor, p)
		local S, why = sys("ChaosSiege", "status")
		if not S then return false, why end
		if p.op == "start" then
			local ok, err = S.start(true)
			return ok and true or false, ok and "Guild siege started (gathering)." or ("Not started: " .. tostring(err))
		elseif p.op == "match" then
			return S.matchNow() and true or false, "The gates are open (or the siege is not gathering)."
		elseif p.op == "end" then
			return S.endNow() and true or false, "Guild siege ended with results (or none was running)."
		end
		return S.stop() and true or false, "Guild siege cancelled (or none was running)."
	end}
