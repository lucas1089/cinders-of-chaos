-- Chaos: Guilds & Market. Mentors (mentor.lua ChaosMentor), the market and the Orb Exchange sweeps and escrow
-- (market.lua ChaosMarket, orbexchange.lua ChaosOrbExchange), guild wars (guildwar.lua ChaosGuildWar), the weekly guild
-- boss (guildboss.lua ChaosGuildBoss) and the community goal (community.lua ChaosCommunity): what /mentor, /market,
-- /orbx, /guildwar, /guildboss and /community do. The mentor unlink and the guild boss fuel and week reset are the same
-- single statements as those commands (the systems have no public write for them), followed by the system's reload.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "chaos_social"; def.id = "chaos_social." .. def.id; ChaosAdminPending[def.id] = def end

local PLAYER = {name = "player", label = "Player", type = "player"}
local GUILD = {name = "guild", label = "Guild name", type = "string", max = 40}

local function sys(name, fn) return ChaosAdmin.system(name, fn) end

local function guildId(name)
	local r = Chaos.select("SELECT `id`, `name` FROM `guilds` WHERE `name` = " .. db.escapeString(name or ""), {{"id", "n"}, {"name", "s"}})[1]
	return r and r.id, r and r.name
end

-- ------------------------------------------------------------------ mentors (server/README.md "Mentors")
local function mentorLink(T, guid)
	return Chaos.select(string.format("SELECT `id`, `mentor_id`, `source`, `linked_at`, `shared_minutes` FROM `%s` WHERE `apprentice_id` = %d " ..
		"AND `status` = 'active' LIMIT 1", T.links, guid), {{"id", "n"}, {"mentor_id", "n"}, {"source", "s"}, {"linked_at", "n"},
		{"shared_minutes", "n"}})[1]
end

reg{id = "mentor_view", name = "Mentor: view", description = "A character's mentor row (marks, graduates, apprentices) and its link as an apprentice (as /mentor name).",
	params = {PLAYER},
	handler = function(actor, p)
		local M, why = sys("ChaosMentor", "load")
		if not M or not Chaos.mentorConfig then return false, why or "mentor.lua is not loaded." end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		local T, lines = Chaos.mentorConfig.tables, {}
		local row = Chaos.select(string.format("SELECT `marks`, `earned`, `graduates`, `accepting`, `active` FROM `%s` WHERE `player_id` = %d",
			T.mentors, t.guid), {{"marks", "n"}, {"earned", "n"}, {"graduates", "n"}, {"accepting", "n"}, {"active", "n"}})[1]
		if row and row.active == 1 then
			local n = Chaos.select(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `mentor_id` = %d AND `status` = 'active'", T.links, t.guid),
				{{"n", "n"}})[1]
			lines[#lines + 1] = string.format("Mentor: %d marks (%d earned), %d graduates, %d apprentice(s), accepting %s.", row.marks,
				row.earned, row.graduates, n and n.n or 0, row.accepting == 1 and "yes" or "no")
		end
		local link = mentorLink(T, t.guid)
		if link then
			lines[#lines + 1] = string.format("Apprentice of player %d since %s (%s), %d minutes together.", link.mentor_id,
				os.date("%Y-%m-%d", link.linked_at), link.source, link.shared_minutes)
		end
		return true, t.name .. (#lines > 0 and ": mentor data" or ": no mentor data."), lines
	end}

reg{id = "mentor_unlink", name = "Mentor: remove link", description = "Ends a character's active link as an apprentice (status released, as /mentor name, unlink).",
	confirm = true, params = {PLAYER},
	handler = function(actor, p)
		local M, why = sys("ChaosMentor", "load")
		if not M or not Chaos.mentorConfig then return false, why or "mentor.lua is not loaded." end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		local T = Chaos.mentorConfig.tables
		local link = mentorLink(T, t.guid)
		if not link then return false, t.name .. " has no active mentor link." end
		db.query(string.format("UPDATE `%s` SET `status` = 'released', `ended_at` = %d WHERE `id` = %d AND `status` = 'active'", T.links, os.time(), link.id))
		db.asyncQuery(string.format("INSERT INTO `%s` (`at`, `player_id`, `other_id`, `action`, `detail`) VALUES (%d, %d, %d, 'unlink', %s)",
			T.log, os.time(), t.guid, link.mentor_id, db.escapeString(("by " .. actor:getName()):sub(1, 128))))
		if M.invites then M.invites[t.guid] = nil end
		for _, g in ipairs({t.guid, link.mentor_id}) do
			for _, pl in ipairs(Game.getPlayers() or {}) do
				if pl:getGuid() == g then pcall(M.load, g) end
			end
		end
		return true, t.name .. ": mentor link removed."
	end}

-- ------------------------------------------------------------------ market and Orb Exchange (server/README.md "Market", "Orb Exchange")
reg{id = "market_sweep", name = "Market: expiry sweep", description = "Expires the offers and buy orders whose time ran out now (as /market sweep).",
	minGroup = 5,
	handler = function(actor)
		local MK, why = sys("ChaosMarket", "sweep")
		if not MK then return false, why end
		return true, string.format("Market sweep: %s offers and %s buy orders expired.", tostring(MK.sweep()), tostring(MK.sweepOrders and MK.sweepOrders() or 0))
	end}

reg{id = "orbx_escrow", name = "Orb Exchange: escrow", description = "What the open Orb Exchange orders hold in escrow, per asset (as /orbx escrow).",
	handler = function(actor)
		local X, why = sys("ChaosOrbExchange", "escrowReport")
		if not X then return false, why end
		local lines = {}
		for _, r in ipairs(X.escrowReport()) do lines[#lines + 1] = string.format("%s: %d in %d orders", r.give_asset, r.n or 0, r.c or 0) end
		return true, "Orb Exchange escrow", lines
	end}

reg{id = "orbx_sweep", name = "Orb Exchange: sweep", description = "Expires old orders and merges the orders of ended seasons (as /orbx sweep).",
	minGroup = 5,
	handler = function(actor)
		local X, why = sys("ChaosOrbExchange", "sweep")
		if not X then return false, why end
		return true, string.format("Orb Exchange sweep: %s orders expired, %s orders of ended seasons merged.", tostring(X.sweep()),
			tostring(X.mergeEndedSeasons and X.mergeEndedSeasons() or 0))
	end}

-- ------------------------------------------------------------------ guild wars (server/README.md "Guild wars in game")
local function wars(W)
	if not W.loaded then W.load() end
	return W.wars or {}
end

reg{id = "guildwar_list", name = "Guild wars: list", description = "Every war offer and running war with its score and terms (as /guildwar).",
	handler = function(actor)
		local W, why = sys("ChaosGuildWar", "load")
		if not W then return false, why end
		local C, lines = ChaosGuildWarCore, {}
		for _, w in pairs(wars(W)) do
			lines[#lines + 1] = string.format("%d: %s vs %s, %s, %s, %s", w.id, w.name1, w.name2, w.status, C.scoreText(w), C.termsText(w))
		end
		return true, #lines .. " war offer(s) or war(s).", lines
	end}

reg{id = "guildwar_end", name = "Guild wars: end war", description = "Ends a running war now with its current score (as /guildwar end, id).",
	minGroup = 5, confirm = true, params = {{name = "war", label = "War id", type = "int", min = 1, max = 2147483647}},
	handler = function(actor, p)
		local W, why = sys("ChaosGuildWar", "finish")
		if not W then return false, why end
		local war = wars(W)[p.war]
		if not war or war.status ~= "active" then return false, "No running war " .. p.war .. "." end
		W.finish(war, "staff")
		return true, "War " .. p.war .. " ended."
	end}

-- ------------------------------------------------------------------ the weekly guild boss (server/README.md "The weekly guild boss")
local function gbWeek()
	return ChaosGuildBossCore.weekKey(Chaos.guildBossConfig, os.time())
end

reg{id = "guildboss_status", name = "Guild boss: status", description = "Open guild boss arenas and, with a guild, its week row (embers, kills).",
	params = {{name = "guild", label = "Guild name (optional)", type = "string", max = 40, required = false}},
	handler = function(actor, p)
		local GB, why = sys("ChaosGuildBoss", "weekRow")
		if not GB then return false, why end
		local lines = {}
		for slot, r in pairs(GB.runs or {}) do
			local n = 0
			for _ in pairs(r.players or {}) do n = n + 1 end
			lines[#lines + 1] = string.format("slot %d: %s, %s, %d player(s), lives %d/%d, phase %d", slot, tostring(r.guildName), tostring(r.state),
				n, r.lives or 0, r.livesMax or 0, r.phase or 0)
		end
		if p.guild and p.guild ~= "" then
			local gid, gname = guildId(p.guild)
			if not gid then return false, "No guild named " .. p.guild .. "." end
			local row = GB.weekRow(gid) or {}
			lines[#lines + 1] = string.format("%s this week: %d embers, %d attempt(s)%s.", gname, row.fuel or 0, row.attempts or 0,
				(row.killed_at or 0) > 0 and (", killed " .. os.date("%Y-%m-%d %H:%M", row.killed_at)) or "")
		end
		return true, #lines > 0 and "Guild boss" or "No guild boss arena is open.", lines
	end}

reg{id = "guildboss_fuel", name = "Guild boss: add embers", description = "Adds embers to a guild's furnace this week (as /guildboss fuel).",
	minGroup = 5, params = {GUILD, {name = "embers", label = "Embers", type = "int", min = 1, max = 1000000}},
	handler = function(actor, p)
		local GB, why = sys("ChaosGuildBoss", "weekRow")
		if not GB or not ChaosGuildBossCore then return false, why or "guildboss.lua is not loaded." end
		local gid, gname = guildId(p.guild)
		if not gid then return false, "No guild named " .. p.guild .. "." end
		GB.weekRow(gid)
		local tbl, now = Chaos.guildBossConfig.tables.week, os.time()
		db.query(string.format("INSERT INTO `%s` (`guild_id`, `week`, `fuel`, `updated_at`) VALUES (%d, %d, %d, %d) " ..
			"ON DUPLICATE KEY UPDATE `fuel` = `fuel` + %d, `updated_at` = %d", tbl, gid, gbWeek(), p.embers, now, p.embers, now))
		return true, string.format("%s: %d embers.", gname, (GB.weekRow(gid) or {}).fuel or 0)
	end}

reg{id = "guildboss_reset", name = "Guild boss: reset week", description = "Deletes a guild's guild boss row of this week (as /guildboss reset): embers and the kill of the week start again.",
	dangerous = true, params = {GUILD},
	handler = function(actor, p)
		local GB, why = sys("ChaosGuildBoss", "weekRow")
		if not GB or not ChaosGuildBossCore then return false, why or "guildboss.lua is not loaded." end
		local gid, gname = guildId(p.guild)
		if not gid then return false, "No guild named " .. p.guild .. "." end
		db.query(string.format("DELETE FROM `%s` WHERE `guild_id` = %d AND `week` = %d", Chaos.guildBossConfig.tables.week, gid, gbWeek()))
		return true, gname .. ": this week's guild boss row reset."
	end}

-- ------------------------------------------------------------------ community goal (server/README.md "Community goals")
reg{id = "community_status", name = "Community goal: status", description = "The realm's community goal progress and this week's world modifiers (as /community).",
	params = {{name = "realm", label = "Realm (0 = standard)", type = "int", min = 0, max = 1000, default = 0}},
	handler = function(actor, p)
		local X, why = sys("ChaosCommunity", "goal")
		if not X or not Chaos.communityConfig then return false, why or "community.lua is not loaded." end
		local cfg, g, w = Chaos.communityConfig, X.goal(p.realm), X.currentWeek()
		local names = {}
		for _, m in ipairs(w.mods or {}) do names[#names + 1] = m.key end
		return true, string.format("Realm %d, period %d: %d / %d points (%d%%). Week %s modifiers (%s): %s.", p.realm, g.period or 0, g.progress or 0,
			cfg.goal.target, math.floor(ChaosCommunityCore.pct(cfg, g.progress or 0)), tostring(w.key), tostring(w.source), table.concat(names, ", "))
	end}
