-- Cinders of Chaos admin panel: core (registry, permission checks, audit log, opcode dispatch).
-- Action files (actions_*.lua) only append definitions to the global ChaosAdminPending table, so the
-- load order of files inside this directory does not matter.
--
-- NOTE: written without the ability to run a TFS 1.4.2 server; see README.md "Untested".

------------------------------------------------------------------------------------------------
-- Configuration (edit here)
------------------------------------------------------------------------------------------------
CHAOS_ADMIN_OPCODE = 120 -- extended opcode used by client/overlay/modules/game_admin

ChaosAdminConfig = {
	-- Minimum group id that can open the panel at all. Group must ALSO have getAccess() == true.
	-- Default TFS groups: 1 player, 2 tutor, 3 senior tutor, 4 gamemaster, 5 community manager, 6 god.
	minGroup = 4,
	-- Default minimum group per category (an individual action may raise it with its own minGroup).
	categoryMinGroup = {
		players = 4, server = 5, world = 4, economy = 5,
		events = 5, content = 5, security = 5, tools = 4, store = 5,
		-- the Chaos systems (actions_chaos_*.lua): a gamemaster inspects and fixes; whatever gives value asks
		-- minGroup 5 on the action, whatever wipes progress is dangerous
		chaos_currency = 4, chaos_progress = 4, chaos_class = 4, chaos_bosses = 4, chaos_instances = 4,
		chaos_player = 4, chaos_social = 4,
	},
	-- Group required for actions flagged "dangerous" (shutdown, reload, set group, ...).
	dangerousMinGroup = 6,
	throttleMs = 150,    -- min delay between two requests from the same player
	logViewerMax = 100,  -- hard cap for "last N admin_log rows"
	dbLog = true,
	-- Legacy talkaction files (data/talkactions/scripts/<name>.lua) that "tools.talkaction" may run.
	talkactionWhitelist = {"online", "uptime", "info", "storage_get", "kills", "deathlist", "serverinfo"},
}

------------------------------------------------------------------------------------------------
-- Registry
------------------------------------------------------------------------------------------------
ChaosAdminPending = ChaosAdminPending or {} -- id -> definition, filled by actions_*.lua
ChaosAdmin = ChaosAdmin or {}
ChaosAdmin.lastRequest = ChaosAdmin.lastRequest or {}

ChaosAdmin.categories = {
	{id = "players",  label = "Players"},
	{id = "server",   label = "Server"},
	{id = "world",    label = "World"},
	{id = "economy",  label = "Economy"},
	{id = "events",   label = "Events"},
	{id = "content",  label = "Content"},
	{id = "security", label = "Accounts & Security"},
	{id = "tools",    label = "Tools"},
	{id = "store",    label = "Store"},
	{id = "chaos_currency",  label = "Chaos: Currencies"},
	{id = "chaos_progress",  label = "Chaos: Progression"},
	{id = "chaos_class",     label = "Chaos: Classes"},
	{id = "chaos_player",    label = "Chaos: Buffs & Gear"},
	{id = "chaos_bosses",    label = "Chaos: Bosses & Events"},
	{id = "chaos_instances", label = "Chaos: Instances & PvP"},
	{id = "chaos_social",    label = "Chaos: Guilds & Market"},
}

local function categoryExists(id)
	for _, c in ipairs(ChaosAdmin.categories) do
		if c.id == id then return true end
	end
	return false
end

function ChaosAdmin.requiredGroup(def)
	local base = ChaosAdminConfig.categoryMinGroup[def.category] or ChaosAdminConfig.minGroup
	local g = math.max(base, ChaosAdminConfig.minGroup, tonumber(def.minGroup) or 0)
	if def.dangerous then
		g = math.max(g, ChaosAdminConfig.dangerousMinGroup)
	end
	return g
end

function ChaosAdmin.getAction(id)
	local def = type(id) == "string" and ChaosAdminPending[id] or nil
	if def and categoryExists(def.category) and type(def.handler) == "function" then
		return def
	end
	return nil
end

------------------------------------------------------------------------------------------------
-- Permission (re-checked on EVERY request)
------------------------------------------------------------------------------------------------
function ChaosAdmin.isAdmin(player)
	if not player or not player:isPlayer() then return false end
	local group = player:getGroup()
	if not group then return false end
	return group:getAccess() and group:getId() >= ChaosAdminConfig.minGroup
end

function ChaosAdmin.canUse(player, def)
	return ChaosAdmin.isAdmin(player) and player:getGroup():getId() >= ChaosAdmin.requiredGroup(def)
end

-- Acting on another player: forbid equal/higher groups (self is always allowed).
function ChaosAdmin.canTouch(actor, target)
	if actor == target or actor:getId() == target:getId() then return true end
	return target:getGroup():getId() < actor:getGroup():getId()
end

------------------------------------------------------------------------------------------------
-- Helpers for action handlers
------------------------------------------------------------------------------------------------
function ChaosAdmin.findOnline(name)
	if type(name) ~= "string" or name == "" then return nil end
	return Player(name)
end

-- Returns Player or nil, errMsg. Applies the group hierarchy check.
function ChaosAdmin.targetOnline(actor, name, allowSelfOnly)
	local t = ChaosAdmin.findOnline(name)
	if not t then return nil, "Player '" .. tostring(name) .. "' is not online." end
	if not ChaosAdmin.canTouch(actor, t) then
		return nil, "Target has an equal or higher group than you."
	end
	return t
end

-- SQL defence in depth: a number for a query as a plain integer string ("42"), or nil when it is not a finite whole
-- number (a string that is not one, NaN, infinity, 1.5, nil). Floor first: "7.0" and 1e3 style values are accepted as 7 and 1000.
-- Callers refuse on nil; ids and addresses never reach a query through ".." unchecked.
function ChaosAdmin.sqlInt(x)
	x = tonumber(x)
	if not x or x ~= x or x == math.huge or x == -math.huge or math.floor(x) ~= x then return nil end
	return string.format("%d", x)
end

-- Offline lookup in the DB. Returns {id=, account_id=, name=, group_id=} or nil.
function ChaosAdmin.dbPlayer(name)
	local rid = db.storeQuery("SELECT `id`, `account_id`, `name`, `group_id` FROM `players` WHERE `name` = " .. db.escapeString(name))
	if not rid then return nil end
	local r = {
		id = result.getNumber(rid, "id"), account_id = result.getNumber(rid, "account_id"),
		name = result.getString(rid, "name"), group_id = result.getNumber(rid, "group_id"),
	}
	result.free(rid)
	return r
end

function ChaosAdmin.ipToString(ip)
	ip = tonumber(ip) or 0
	return string.format("%d.%d.%d.%d", bit.band(ip, 0xFF), bit.band(bit.rshift(ip, 8), 0xFF),
		bit.band(bit.rshift(ip, 16), 0xFF), bit.rshift(ip, 24))
end

function ChaosAdmin.stringToIp(s)
	local a, b, c, d = tostring(s):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
	if not a or a > 255 or b > 255 or c > 255 or d > 255 then return nil end
	return a + b * 256 + c * 65536 + d * 16777216
end

-- Resolve "2160" or "crystal coin" to an ItemType, or nil + error.
function ChaosAdmin.resolveItem(v)
	local it
	if tonumber(v) then
		it = ItemType(tonumber(v))
	else
		it = ItemType(tostring(v))
	end
	if not it or it:getId() == 0 then return nil, "Unknown item '" .. tostring(v) .. "'." end
	return it
end

-- Any character by name, online or offline, with the group hierarchy check (self always allowed).
-- Returns {guid, name, account, group, player = the online Player or nil} or nil, errMsg.
function ChaosAdmin.targetAny(actor, name)
	local p = ChaosAdmin.findOnline(name)
	if p then
		if not ChaosAdmin.canTouch(actor, p) then
			return nil, "Target has an equal or higher group than you."
		end
		return {guid = p:getGuid(), name = p:getName(), account = p:getAccountId(), group = p:getGroup():getId(), player = p}
	end
	local d = ChaosAdmin.dbPlayer(name)
	if not d then return nil, "Player '" .. tostring(name) .. "' not found." end
	if d.id ~= actor:getGuid() and (tonumber(d.group_id) or 1) >= actor:getGroup():getId() then
		return nil, "Target has an equal or higher group than you."
	end
	return {guid = d.id, name = d.name, account = d.account_id, group = d.group_id}
end

-- A Chaos system's global table (optionally with function `fn`), or nil, why: the panel never assumes a system file
-- is loaded on this server.
function ChaosAdmin.system(name, fn)
	local t = rawget(_G, name)
	if type(t) ~= "table" or (fn and type(t[fn]) ~= "function") then
		return nil, name .. (fn and ("." .. fn) or "") .. " is not loaded on this server."
	end
	return t
end

-- Optional "player" param: empty means the acting admin.
function ChaosAdmin.targetOrSelf(actor, name)
	if not name or name == "" then return actor end
	return ChaosAdmin.targetOnline(actor, name)
end

-- Hook registry: other systems (dungeons, towers, bosses, events) expose start/stop without the panel
-- knowing their internals. start/stop may be a function(actor, params) or the NAME of a global function.
--   ChaosAdminRegisterHook("my_event", {kind = "event", description = "...", start = fn, stop = fn})
-- kind: "event" (Events tab) or "dungeon" | "tower" | "boss" | "other" (Content tab).
ChaosAdminHooks = ChaosAdminHooks or {}
function ChaosAdminRegisterHook(name, def)
	def.name = name
	ChaosAdminHooks[name] = def
end

function ChaosAdmin.callHook(name, op, actor)
	local h = ChaosAdminHooks[name]
	if not h then return false, "Unknown hook '" .. tostring(name) .. "'." end
	local fn = h[op]
	if type(fn) == "string" then fn = rawget(_G, fn) end
	if type(fn) ~= "function" then return false, "Hook '" .. name .. "' has no '" .. op .. "' operation." end
	local ok, a, b = pcall(fn, actor, h)
	if not ok then return false, "Hook error: " .. tostring(a) end
	if a == false then return false, b or "Hook returned false." end
	return true, type(a) == "string" and a or (b or ("Hook '" .. name .. "' " .. op .. " executed."))
end

function ChaosAdmin.constant(name)
	return rawget(_G, name)
end

function ChaosAdmin.expForLevel(level)
	level = level - 1
	return math.floor((50 * level ^ 3 - 150 * level ^ 2 + 400 * level) / 3)
end

function ChaosAdmin.broadcast(text, kind)
	Game.broadcastMessage(text, kind or MESSAGE_STATUS_WARNING)
end

-- Helper for handlers that do not want to repeat pcall boilerplate for optional APIs.
function ChaosAdmin.try(fn, ...)
	local ok, a, b, c = pcall(fn, ...)
	if ok then return true, a, b, c end
	return false, a
end

------------------------------------------------------------------------------------------------
-- Audit log (DB + console)
------------------------------------------------------------------------------------------------
local function sanitizeLogText(s, max)
	s = tostring(s or ""):gsub("[%c]", " ")
	if #s > max then s = s:sub(1, max) end
	return s
end

function ChaosAdmin.log(player, actionId, target, params, status, message)
	target = sanitizeLogText(target, 128)
	message = sanitizeLogText(message, 255)
	local okJ, paramJson = pcall(json.encode, params or {})
	paramJson = okJ and sanitizeLogText(paramJson, 2000) or "{}"
	local name = player and player:getName() or "?"
	local gid = player and player:getGroup():getId() or 0
	print(string.format("[ChaosAdmin] %s (group %d) %s target='%s' params=%s -> %s: %s",
		name, gid, actionId, target, paramJson, status, message))
	if not ChaosAdminConfig.dbLog then return end
	db.asyncQuery(string.format(
		"INSERT INTO `chaos_admin_log` (`created_at`,`account_id`,`player_id`,`player_name`,`group_id`,`ip`,`action`,`target`,`params`,`status`,`message`) VALUES (%d,%d,%d,%s,%d,%d,%s,%s,%s,%s,%s)",
		os.time(), player and player:getAccountId() or 0, player and player:getGuid() or 0,
		db.escapeString(name), gid, player and player:getIp() or 0, db.escapeString(sanitizeLogText(actionId, 64)),
		db.escapeString(target), db.escapeString(paramJson), db.escapeString(status), db.escapeString(message)))
end

------------------------------------------------------------------------------------------------
-- Parameter validation (server-side; the client schema is only a UI hint)
------------------------------------------------------------------------------------------------
local function cleanString(v, maxLen)
	if type(v) ~= "string" then
		if type(v) == "number" then v = tostring(v) else return nil end
	end
	v = v:gsub("[%c]", " "):match("^%s*(.-)%s*$")
	if #v > maxLen then return nil end
	return v
end

local function cleanParam(spec, raw)
	local t = spec.type or "string"
	if raw == nil or raw == "" then
		if spec.default ~= nil then raw = spec.default
		elseif spec.required == false or t == "bool" then
			if t == "bool" then return false end
			return nil
		else
			return nil, "Missing parameter '" .. spec.name .. "'."
		end
	end
	local bad = "Invalid value for '" .. spec.name .. "'."
	if t == "player" then
		local s = cleanString(raw, 30)
		if not s or not s:match("^[%a%d '%-%.]+$") then return nil, bad end
		return s
	elseif t == "string" or t == "text" then
		local s = cleanString(raw, spec.max or (t == "text" and 500 or 200))
		if not s then return nil, bad end
		return s
	elseif t == "int" then
		local n = tonumber(raw)
		if not n or n ~= n or n ~= math.floor(n) then return nil, bad end
		local lo, hi = spec.min or -2147483648, spec.max or 2147483647
		if n < lo or n > hi then return nil, string.format("'%s' must be between %d and %d.", spec.name, lo, hi) end
		return n
	elseif t == "bool" then
		return raw == true or raw == 1 or raw == "1" or raw == "true"
	elseif t == "select" then
		for _, o in ipairs(spec.options or {}) do
			local val = type(o) == "table" and o.value or o
			if tostring(val) == tostring(raw) then return tostring(val) end
		end
		return nil, bad
	elseif t == "pos" then
		local x, y, z = tostring(raw):match("^%s*(%d+)%s*[, ]%s*(%d+)%s*[, ]%s*(%d+)%s*$")
		x, y, z = tonumber(x), tonumber(y), tonumber(z)
		if not x or x > 65535 or y > 65535 or z > 15 then return nil, bad end
		return {x = x, y = y, z = z}
	elseif t == "ip" then
		local s = cleanString(raw, 15)
		if not s or not ChaosAdmin.stringToIp(s) then return nil, bad end
		return s
	end
	return nil, "Unknown parameter type."
end

local function cleanParams(def, raw)
	raw = type(raw) == "table" and raw or {}
	local out = {}
	for _, spec in ipairs(def.params or {}) do
		local v, err = cleanParam(spec, raw[spec.name])
		if err then return nil, err end
		out[spec.name] = v
	end
	return out
end

------------------------------------------------------------------------------------------------
-- Catalog + dispatch
------------------------------------------------------------------------------------------------
-- The catalog is about 60 KB for group 6 (176 actions; tests/admin_panel_test.lua measures it), over the 8192 bytes one
-- extended opcode message can carry, so everything goes through
-- Chaos.sendChunked (S/P/E parts; the client listens with ProtocolGame.registerExtendedJSONOpcode).
local function send(player, action, data)
	if not Chaos then dofile("data/scripts/chaos/chaos_constants.lua") end
	Chaos.sendChunked(player, CHAOS_ADMIN_OPCODE, json.encode({action = action, data = data}))
end

function ChaosAdmin.buildCatalog(player)
	local gid = player:getGroup():getId()
	local cats = {}
	for _, c in ipairs(ChaosAdmin.categories) do
		cats[#cats + 1] = {id = c.id, label = c.label, actions = {}}
	end
	local byId = {}
	for _, c in ipairs(cats) do byId[c.id] = c end
	local ids = {}
	for id in pairs(ChaosAdminPending) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local def = ChaosAdmin.getAction(id)
		if def and gid >= ChaosAdmin.requiredGroup(def) then
			local params = {}
			for _, p in ipairs(def.params or {}) do
				params[#params + 1] = {
					name = p.name, label = p.label or p.name, type = p.type or "string", required = p.required ~= false and p.default == nil,
					min = p.min, max = p.max, default = p.default, options = p.options, hint = p.hint,
				}
			end
			local list = byId[def.category].actions
			list[#list + 1] = {
				id = def.id, name = def.name, description = def.description or "", params = params,
				confirm = (def.confirm or def.dangerous) and true or false, dangerous = def.dangerous and true or false,
			}
		end
	end
	local out = {}
	for _, c in ipairs(cats) do
		if #c.actions > 0 then out[#out + 1] = c end
	end
	return {categories = out, group = gid}
end

-- true for the plain {"action":"catalog"} request the client sends by itself at login (and on refresh)
function ChaosAdmin.isCatalogProbe(buffer)
	if type(buffer) ~= "string" or #buffer > 256 then return false end
	local ok, req = pcall(json.decode, buffer)
	return ok and type(req) == "table" and req.action == "catalog"
end

-- Runs one action for an admin: group checks, parameter validation, the handler in pcall and the audit log. Used by the
-- panel (extended opcode) and by the remote commands (remote_cmd.lua, the phone app). Returns
-- {ok = bool, message = string, lines = table or nil}.
function ChaosAdmin.execute(player, actionId, rawParams)
	local def = ChaosAdmin.getAction(actionId)
	if not def then
		ChaosAdmin.log(player, tostring(actionId):sub(1, 64), "", {}, "invalid", "unknown action")
		return {ok = false, message = "Unknown action."}
	end
	if not ChaosAdmin.canUse(player, def) then
		ChaosAdmin.log(player, def.id, "", {}, "denied", "insufficient group")
		return {ok = false, message = "You are not allowed to use this action."}
	end
	local params, err = cleanParams(def, rawParams)
	if not params then
		ChaosAdmin.log(player, def.id, "", {}, "invalid", err)
		return {ok = false, message = err}
	end
	local target = ""
	for _, spec in ipairs(def.params or {}) do
		if (spec.type == "player" or spec.name == "account") and params[spec.name] then
			target = tostring(params[spec.name]); break
		end
	end
	local ok, a, b, c = pcall(def.handler, player, params)
	local success, msg, lines
	if ok then
		success, msg, lines = a and true or false, b or (a and "Done." or "Failed."), c
	else
		success, msg = false, "Internal error: " .. tostring(a)
	end
	ChaosAdmin.log(player, def.id, target, params, success and "ok" or "fail", msg)
	return {ok = success, message = msg, lines = lines}
end

local function handleRequest(player, req)
	if req.action == "catalog" then
		send(player, "catalog", ChaosAdmin.buildCatalog(player))
		return
	end
	if req.action ~= "run" then return end

	local data = type(req.data) == "table" and req.data or {}
	local rid = tonumber(data.rid) or 0
	local actionId = data.id
	local res = ChaosAdmin.execute(player, actionId, data.params)
	send(player, "result", {rid = rid, id = actionId, ok = res.ok, message = res.message, lines = res.lines})
end

------------------------------------------------------------------------------------------------
-- Opcode wiring
------------------------------------------------------------------------------------------------
local loginEvent = CreatureEvent("ChaosAdminLogin")
function loginEvent.onLogin(player)
	player:registerEvent("ChaosAdminExtended")
	player:registerEvent("ChaosAdminLogout")
	return true
end
loginEvent:type("login")
loginEvent:register()

local logoutEvent = CreatureEvent("ChaosAdminLogout")
function logoutEvent.onLogout(player)
	ChaosAdmin.lastRequest[player:getId()] = nil
	return true
end
logoutEvent:type("logout")
logoutEvent:register()

local extEvent = CreatureEvent("ChaosAdminExtended")
function extEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= CHAOS_ADMIN_OPCODE then return end

	-- Permission is evaluated here, on every single message. Non-admins get no reply at all.
	if not ChaosAdmin.isAdmin(player) then
		-- every client asks for the catalog once after login (game_admin): not worth a log line or a row
		if ChaosAdmin.isCatalogProbe(buffer) then return end
		local now = os.mtime and os.mtime() or os.time() * 1000
		local last = ChaosAdmin.lastRequest[player:getId()] or 0
		if now - last > 5000 then
			ChaosAdmin.lastRequest[player:getId()] = now
			ChaosAdmin.log(player, "panel.access", "", {}, "denied", "non-admin sent admin opcode")
		end
		return
	end

	local now = os.mtime and os.mtime() or os.time() * 1000
	local last = ChaosAdmin.lastRequest[player:getId()] or 0
	if now - last < ChaosAdminConfig.throttleMs then return end
	ChaosAdmin.lastRequest[player:getId()] = now

	if type(buffer) ~= "string" or #buffer > 8192 then return end
	local ok, req = pcall(json.decode, buffer)
	if not ok or type(req) ~= "table" then return end

	local ok2, err = pcall(handleRequest, player, req)
	if not ok2 then
		print("[ChaosAdmin] internal error: " .. tostring(err))
	end
end
extEvent:type("extendedopcode")
extEvent:register()
