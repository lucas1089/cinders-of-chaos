-- Accounts & Security category.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "security"; def.id = "security." .. def.id; ChaosAdminPending[def.id] = def end

reg{id = "account_lookup", name = "Account lookup", description = "Look up an account by name or numeric id: type, characters, ban state. Never shows password or email.",
	params = {{name = "account", label = "Account name or id", type = "string", max = 40}},
	handler = function(actor, p)
		local q
		if tonumber(p.account) then
			q = "SELECT `id`,`name`,`type` FROM `accounts` WHERE `id` = " .. math.floor(tonumber(p.account))
		else
			q = "SELECT `id`,`name`,`type` FROM `accounts` WHERE `name` = " .. db.escapeString(p.account)
		end
		local rid = db.storeQuery(q)
		if not rid then return false, "Account not found." end
		local id = result.getNumber(rid, "id")
		local lines = {"Account #" .. id .. " '" .. result.getString(rid, "name") .. "'  type " .. result.getNumber(rid, "type")}
		result.free(rid)
		local ban = db.storeQuery("SELECT `reason`,`expires_at` FROM `account_bans` WHERE `account_id` = " .. id)
		if ban then
			lines[#lines + 1] = string.format("BANNED until %s  reason: %s", os.date("%Y-%m-%d %H:%M", result.getNumber(ban, "expires_at")), result.getString(ban, "reason"))
			result.free(ban)
		end
		local pl = db.storeQuery("SELECT `name`,`level`,`group_id`,`lastlogin` FROM `players` WHERE `account_id` = " .. id .. " ORDER BY `level` DESC")
		if pl then
			repeat
				lines[#lines + 1] = string.format("  %s  lvl %d  group %d  last login %s", result.getString(pl, "name"), result.getNumber(pl, "level"),
					result.getNumber(pl, "group_id"), os.date("%Y-%m-%d %H:%M", result.getNumber(pl, "lastlogin")))
			until not result.next(pl)
			result.free(pl)
		end
		return true, "Account lookup", lines
	end}

reg{id = "ban_list", name = "Account ban list", description = "Active account bans, newest first (max 50).",
	handler = function()
		local rid = db.storeQuery("SELECT ab.`account_id`, a.`name` AS acc, ab.`reason`, ab.`expires_at` FROM `account_bans` ab LEFT JOIN `accounts` a ON a.`id` = ab.`account_id` ORDER BY ab.`banned_at` DESC LIMIT 50")
		local lines = {}
		if rid then
			repeat
				lines[#lines + 1] = string.format("#%d %s  until %s  %s", result.getNumber(rid, "account_id"), result.getString(rid, "acc"),
					os.date("%Y-%m-%d %H:%M", result.getNumber(rid, "expires_at")), result.getString(rid, "reason"))
			until not result.next(rid)
			result.free(rid)
		end
		return true, #lines .. " ban(s).", lines
	end}

reg{id = "ip_ban", name = "IP ban", description = "Ban an IP address (or the current IP of an online player) for N days.", confirm = true,
	params = {{name = "target", label = "Online player name OR ip a.b.c.d", type = "string", max = 40},
		{name = "days", label = "Days", type = "int", min = 1, max = 3650, default = 7},
		{name = "reason", label = "Reason", type = "string", max = 200, required = false}},
	handler = function(actor, p)
		local ip = ChaosAdmin.stringToIp(p.target)
		local victim
		if not ip then
			victim = Player(p.target)
			if not victim then return false, "Not a valid IP and no such online player." end
			if not ChaosAdmin.canTouch(actor, victim) or victim:getId() == actor:getId() then
				return false, "Not allowed to ban that player."
			end
			ip = victim:getIp()
		end
		if ip == 0 or ip == actor:getIp() then return false, "Refusing to ban that IP." end
		local rid = db.storeQuery("SELECT 1 FROM `ip_bans` WHERE `ip` = " .. ip)
		if rid then result.free(rid); return false, "IP is already banned." end
		local now = os.time()
		db.query(string.format("INSERT INTO `ip_bans` (`ip`,`reason`,`banned_at`,`expires_at`,`banned_by`) VALUES (%d,%s,%d,%d,%d)",
			ip, db.escapeString(p.reason or ""), now, now + p.days * 86400, actor:getGuid()))
		if victim then victim:remove() end
		return true, string.format("IP %s banned for %d day(s).", ChaosAdmin.ipToString(ip), p.days)
	end}

reg{id = "ip_unban", name = "IP unban", description = "Remove an IP ban.",
	params = {{name = "ip", label = "IP a.b.c.d", type = "ip"}},
	handler = function(actor, p)
		local ip = ChaosAdmin.stringToIp(p.ip)
		db.query("DELETE FROM `ip_bans` WHERE `ip` = " .. ip)
		return true, "IP ban removed (if any) for " .. p.ip .. "."
	end}

reg{id = "ip_ban_list", name = "IP ban list", description = "Active IP bans (max 50).",
	handler = function()
		local rid = db.storeQuery("SELECT `ip`,`reason`,`expires_at` FROM `ip_bans` ORDER BY `banned_at` DESC LIMIT 50")
		local lines = {}
		if rid then
			repeat
				lines[#lines + 1] = string.format("%s  until %s  %s", ChaosAdmin.ipToString(result.getNumber(rid, "ip")),
					os.date("%Y-%m-%d %H:%M", result.getNumber(rid, "expires_at")), result.getString(rid, "reason"))
			until not result.next(rid)
			result.free(rid)
		end
		return true, #lines .. " IP ban(s).", lines
	end}

reg{id = "sessions", name = "Active sessions", description = "Online players with IP and login time; IPs shared by several characters are flagged.",
	handler = function()
		local byIp, rows = {}, {}
		for _, pl in ipairs(Game.getPlayers()) do
			local ip = ChaosAdmin.ipToString(pl:getIp())
			byIp[ip] = (byIp[ip] or 0) + 1
			local ll = type(pl.getLastLoginSaved) == "function" and pl:getLastLoginSaved() or 0
			rows[#rows + 1] = {ip = ip, text = string.format("%s  %s  group %d  login %s", pl:getName(), ip, pl:getGroup():getId(),
				ll > 0 and os.date("%H:%M:%S", ll) or "?")}
		end
		table.sort(rows, function(a, b) return a.ip < b.ip end)
		local lines = {}
		for _, r in ipairs(rows) do lines[#lines + 1] = r.text .. (byIp[r.ip] > 1 and ("  [" .. byIp[r.ip] .. " chars on this IP]") or "") end
		return true, #lines .. " session(s).", lines
	end}

reg{id = "admin_log", name = "Admin log viewer", description = "Last N rows of chaos_admin_log, optionally filtered by action prefix or admin name.",
	params = {{name = "count", label = "Rows", type = "int", min = 1, max = 100, default = 25},
		{name = "action", label = "Action prefix (e.g. players.)", type = "string", max = 40, required = false},
		{name = "admin", label = "Admin name", type = "player", required = false}},
	handler = function(actor, p)
		local n = math.min(p.count, ChaosAdminConfig.logViewerMax)
		local where = {}
		if p.action and p.action ~= "" then
			local esc = p.action:gsub("[%%_\\]", "\\%0")
			where[#where + 1] = "`action` LIKE " .. db.escapeString(esc .. "%")
		end
		if p.admin and p.admin ~= "" then where[#where + 1] = "`player_name` = " .. db.escapeString(p.admin) end
		local sql = "SELECT `created_at`,`player_name`,`action`,`target`,`status`,`message` FROM `chaos_admin_log`" ..
			(#where > 0 and (" WHERE " .. table.concat(where, " AND ")) or "") .. " ORDER BY `id` DESC LIMIT " .. n
		local rid = db.storeQuery(sql)
		local lines = {}
		if rid then
			repeat
				lines[#lines + 1] = string.format("%s  %s  %s  %s  [%s] %s", os.date("%m-%d %H:%M:%S", result.getNumber(rid, "created_at")),
					result.getString(rid, "player_name"), result.getString(rid, "action"), result.getString(rid, "target"),
					result.getString(rid, "status"), result.getString(rid, "message"))
			until not result.next(rid)
			result.free(rid)
		end
		return true, #lines .. " log row(s), newest first.", lines
	end}
