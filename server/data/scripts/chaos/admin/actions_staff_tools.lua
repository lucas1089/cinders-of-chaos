-- Tools: the staff chat commands of the Chaos systems as panel actions, calling the same functions (the talkaction
-- files are not changed): /testkit (admin/testkit.lua ChaosTestKit.give), /areagen (areagen.lua ChaosAreaGen),
-- /creatorcodes (creator_codes.lua ChaosCreatorCodes.round), /itemfinder (itemfinder.lua ChaosItemFinder), /memorial
-- (memorial.lua ChaosMemorial), /hideout (hideout.lua ChaosHideout.enter), /gmnotify (notifications.lua
-- ChaosNotify.gmBroadcast), /telemetry (telemetry.lua ChaosTelemetry) and /records (records.lua ChaosRecords).
-- /botreview and /reports are in Accounts & Security (botreview.lua and reports.lua register them themselves).
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "tools"; def.id = "tools." .. def.id; ChaosAdminPending[def.id] = def end

local function sys(name, fn) return ChaosAdmin.system(name, fn) end

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

-- ------------------------------------------------------------------ /testkit (server/README.md "Test kit")
reg{id = "testkit", name = "Test kit", description = "Strong gear, uniques, supplies, level and skills for a test character (ChaosTestKit.give, as /testkit kind, name). Empty kind = by vocation.",
	minGroup = 5, confirm = true,
	params = {{name = "player", label = "Player (empty = me)", type = "player", required = false},
		{name = "kind", label = "Kit (mage, knight, paladin, ...; empty = by vocation)", type = "string", max = 20, required = false}},
	handler = function(actor, p)
		local K, why = sys("ChaosTestKit", "give")
		if not K then return false, why end
		local t, err = ChaosAdmin.targetOrSelf(actor, p.player)
		if not t then return false, err end
		local kind = p.kind and p.kind ~= "" and p.kind:lower() or nil
		if kind and not (K.kits and K.kits[kind]) then
			local names = {}
			for k in pairs(K.kits or {}) do names[#names + 1] = k end
			table.sort(names)
			return false, "Unknown kit. Kits: " .. table.concat(names, ", ")
		end
		local given = K.give(t, kind)
		return true, "Test kit (" .. tostring(given) .. ") given to " .. t:getName() .. "; relog to apply item bonuses."
	end}

-- ------------------------------------------------------------------ /areagen (server/README.md "Generated areas")
reg{id = "areagen_status", name = "Generated areas: status", description = "Every generated area: built or not, monsters alive, the arrival point (as /areagen status).",
	handler = function(actor)
		local AG, why = sys("ChaosAreaGen", "buildAll")
		if not AG then return false, why end
		local lines = {}
		for _, def in ipairs((ChaosAreaGenConfig or {}).areas or {}) do
			local entry = AG.areas and AG.areas[def.id]
			if entry then
				local alive, total = 0, 0
				for _, pt in ipairs(entry.points or {}) do alive, total = alive + #pt.alive, total + pt.count end
				local a = entry.model.arrival
				lines[#lines + 1] = string.format("%s (%s): built, %d / %d alive, arrival %d,%d,%d%s", def.id, def.name, alive, total, a.x, a.y, a.z,
					entry.isDungeon and ", dungeon" or "")
			else
				lines[#lines + 1] = def.id .. ": not built"
			end
		end
		return true, #lines .. " generated area(s).", lines
	end}

reg{id = "areagen_goto", name = "Generated areas: go to", description = "Teleports you to the arrival point of a generated area (as /areagen goto id).",
	params = {{name = "area", label = "Area id", type = "string", max = 40}},
	handler = function(actor, p)
		local AG, why = sys("ChaosAreaGen", "buildAll")
		if not AG then return false, why end
		local entry = AG.areas and AG.areas[p.area]
		if not entry then return false, "Area " .. p.area .. " is not built." end
		local a = entry.model.arrival
		actor:teleportTo(Position(a.x, a.y, a.z))
		return true, "Teleported to " .. p.area .. "."
	end}

-- ------------------------------------------------------------------ /creatorcodes (server/README.md "Creator codes")
reg{id = "creatorcodes_status", name = "Creator codes: status", description = "The creator code settings and every code with its paid shares (as /creatorcodes).",
	minGroup = 5,
	handler = function(actor)
		local CC, why = sys("ChaosCreatorCodes", "round")
		local cfg = Chaos.creatorCodesConfig
		if not CC or not cfg then return false, why or "creator_codes.lua is not loaded." end
		local T, lines = cfg.tables, {}
		for _, r in ipairs(Chaos.select(string.format("SELECT c.`code`, c.`active`, " ..
				"(SELECT COUNT(*) FROM `%s` u WHERE u.`code_id` = c.`id` AND u.`state` = 'paid') AS `n`, " ..
				"(SELECT COALESCE(SUM(u.`share`), 0) FROM `%s` u WHERE u.`code_id` = c.`id` AND u.`state` = 'paid') AS `s` FROM `%s` c ORDER BY c.`code` LIMIT 40",
				T.uses, T.uses, T.codes), {{"code", "s"}, {"active", "n"}, {"n", "n"}, {"s", "n"}})) do
			lines[#lines + 1] = string.format("%s%s: %d paid share(s), %d coins", r.code, r.active == 1 and "" or " (off)", r.n, r.s)
		end
		return true, string.format("Creator codes: %s, %d%% of the coins, hold %d days, caps %d / donation, %d / month.",
			cfg.enabled and "on" or "off", cfg.sharePct or 0, cfg.holdDays or 0, cfg.orderCap or 0, cfg.monthlyCap or 0), lines
	end}

reg{id = "creatorcodes_run", name = "Creator codes: run a round", description = "Matches new donations to codes and pays the shares due now (ChaosCreatorCodes.round, as /creatorcodes run).",
	minGroup = 5, confirm = true,
	handler = function(actor)
		local CC, why = sys("ChaosCreatorCodes", "round")
		if not CC then return false, why end
		local m, paid = CC.round("by " .. actor:getName())
		return true, string.format("Creator codes: %d matched, %d paid.", m or 0, paid or 0)
	end}

-- ------------------------------------------------------------------ /itemfinder, /memorial, /hideout
reg{id = "itemfinder", name = "Item finder: index", description = "The item finder index (items, rows, build time); with a text, a search; Rebuild builds the index again (as /itemfinder).",
	params = {{name = "query", label = "Search (optional)", type = "string", max = 60, required = false},
		{name = "rebuild", label = "Rebuild the index", type = "bool"}},
	handler = function(actor, p)
		local F, why = sys("ChaosItemFinder", "build")
		if not F then return false, why end
		if p.rebuild or not F.index then F.build() end
		local st = F.index and F.index.stats or {}
		local text = string.format("Item finder: %d items, %d rows, built in %d ms, %d KB.", st.items or 0, st.rows or 0, st.ms or 0, st.kb or 0)
		if not p.query or p.query == "" or not ChaosItemFinderCore then return true, text end
		local r = ChaosItemFinderCore.search(F.index, p.query, 1)
		local lines = {}
		for _, row in ipairs(r.rows or {}) do lines[#lines + 1] = string.format("%s (%d)", row.name, row.n) end
		return true, text .. " " .. tostring(r.total) .. " found.", lines
	end}

reg{id = "memorial", name = "Memorial: status", description = "The Capital Memorial's entries per kind and its plaza; Refresh reads the records again (as /memorial [refresh]).",
	params = {{name = "refresh", label = "Refresh the entries", type = "bool"}},
	handler = function(actor, p)
		local X, why = sys("ChaosMemorial", "refresh")
		local M = ChaosMemorialCore
		if not X or not M then return false, why or "memorial.lua is not loaded." end
		if p.refresh then X.refresh() end
		local counts = {}
		for _, kind in ipairs(M.KINDS or {}) do counts[#counts + 1] = kind .. " " .. #M.displayList(X.entries, kind) end
		return true, string.format("%s (%s): %s; page %d.", tostring(X.seasonName), tostring(X.seasonKey), table.concat(counts, ", "), X.page or 0)
	end}

reg{id = "hideout_enter", name = "Hideout: enter", description = "Takes you into a character's hideout (ChaosHideout.enter, as /hideout name).",
	params = {{name = "player", label = "Owner", type = "player"}},
	handler = function(actor, p)
		local H, why = sys("ChaosHideout", "enter")
		if not H then return false, why end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		local ok, text = H.enter(actor, t.guid)
		return ok and true or false, ok and ("In the hideout of " .. t.name .. ".") or tostring(text)
	end}

-- ------------------------------------------------------------------ /gmnotify, /telemetry, /records
reg{id = "gmnotify", name = "Staff notification", description = "Sends a staff notification to every online player (ChaosNotify.gmBroadcast, as /gmnotify).",
	params = {{name = "message", label = "Message", type = "text", max = 300}},
	handler = function(actor, p)
		local N, why = sys("ChaosNotify", "gmBroadcast")
		if not N then return false, why end
		N.gmBroadcast(nil, p.message)
		return true, "Notification sent."
	end}

reg{id = "telemetry", name = "Telemetry: status", description = "This hour's telemetry buckets; Flush writes them now (as /telemetry [flush]).",
	minGroup = 5, params = {{name = "flush", label = "Flush now", type = "bool"}},
	handler = function(actor, p)
		local T, why = sys("ChaosTelemetry", "flush")
		local K = ChaosTelemetryCore
		if not T or not K then return false, why or "telemetry.lua is not loaded." end
		if p.flush then return true, string.format("Telemetry: %d statement(s) written.", T.flush(false) or 0) end
		local acc = T.acc or {}
		return true, string.format("Telemetry hour %s UTC: %d samples, buckets hunt %d, boss %d, deaths %d, casts %d, economy %d.",
			os.date("!%Y-%m-%d %H:00", acc.hour or 0), acc.onlineSamples or 0, K.count(acc.hunt or {}), K.count(acc.boss or {}),
			K.count(acc.deaths or {}), K.count(acc.casts or {}), K.count(acc.economy or {}))
	end}

reg{id = "records", name = "Records: status", description = "Competitive record boards, held awards and the clock offset; Rebuild builds the boards again (as /records [rebuild]).",
	minGroup = 5, params = {{name = "rebuild", label = "Rebuild the boards", type = "bool"}},
	handler = function(actor, p)
		local R, why = sys("ChaosRecords", "build")
		if not R then return false, why end
		if p.rebuild then R.build() end
		local held = R.held or {}
		return true, string.format("Records: %d boards, %d award(s) held (week %s), clock offset %d s.", count(R.boards), held.count or 0,
			tostring(held.week), R.offset or 0)
	end}
