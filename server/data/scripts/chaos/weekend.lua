-- The Weekend Ritual (O321): a fixed weekend every week that players can count on. Friday 18:00 to Sunday 23:59 server
-- time: a theme bonus from a rotation (experience, loot, skill training, rift chests) and a fixed Saturday highlight (a
-- world boss or an invasion). Rules: weekend_core.lua (tests/weekend_test.lua); numbers: weekend_config.lua;
-- server/README.md "Weekend Ritual (O321)". It builds on what exists, with no new system:
--   experience   EventCallback onGainExperience at xpIndex (55), before the experience cap (xpcap.lua, 85): the cap
--                still clamps the kill to x4 of its base, whatever the bonuses multiply to
--   skill        EventCallback onGainSkillTries after the store's training buffs
--   loot         loot_config.lua rateMult asks ChaosWeekend.lootMult(ctx) (under its maxRate)
--   rift chests  ChaosRiftCore.hooks.world, wrapped: the community modifier's answer plus riftReward percent
--   !events      ChaosEvents.dynamic["weekend_ritual"] while it runs (a line per player language), the login line
--   calendar     events_schedule.lua E.calendar adds ChaosWeekend.calendarEntries (login screen, Event Calendar)
--   highlight    ChaosWorldBoss.start() or ChaosInvasion.start() at the fixed hour; both announce themselves
-- Season characters get no personal bonus unless weekend_config.lua seasonCharacters is true (the same rule as the
-- store's world buffs and the rested hunting). Staff: /weekend [status|on|off], admin panel Events > Weekend Ritual,
-- Events > Start / Stop event "weekend_ritual". Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosWeekendCore or not ChaosWeekendCore.window then
	dofile("data/scripts/chaos/weekend_core.lua")
end
Chaos.weekendConfig = dofile("data/scripts/chaos/weekend_config.lua")

ChaosWeekend = ChaosWeekend or {}
local W = ChaosWeekend
local K = ChaosWeekendCore

W.done = W.done or {} -- warnings said in this run ("warn30:20261030": not kept over a restart)

local function cfg()
	return Chaos.weekendConfig
end

local function gs()
	return cfg().globalStorage
end

local function globalGet(key)
	local v = Game.getStorageValue(key)
	return tonumber(v) or -1
end

local function log(text)
	print("[Chaos weekend] " .. text)
end

-- ---------------------------------------------------------------- the switch
-- the config wins; the staff switch (a global storage) can only turn it off
function W.enabled()
	return cfg().enabled == true and globalGet(gs().off) ~= 1
end

function W.setStaffOff(off)
	Game.setStorageValue(gs().off, off and 1 or 0)
	W.refresh()
	return true
end

-- ---------------------------------------------------------------- the window
local function offset(t)
	return K.offset(cfg(), t)
end

-- the window now (inactive when the ritual is off). Cached for the second: a kill asks for it.
function W.window(t)
	t = t or os.time()
	if W.cache and W.cache.t == t and W.cache.on == W.enabled() then
		return W.cache.w
	end
	local on = W.enabled()
	local w = K.window(cfg(), t, offset(t))
	if not on then
		w = {active = false, nextStart = w.nextStart, nextKey = w.nextKey, nextThemeKey = w.nextThemeKey,
			nextTheme = w.nextTheme}
	end
	W.cache = {t = t, on = on, w = w}
	return w
end

local function seasonal(player)
	local S = ChaosSeason
	if not (player and S and S.realmOf) then
		return false
	end
	local ok, realm = pcall(S.realmOf, player)
	return ok and (tonumber(realm) or 0) > 0
end

-- {xp, loot, skill, riftReward} of a player now
function W.mults(player)
	return K.mults(cfg(), W.window(), seasonal(player))
end

-- the loot rate (loot_config.lua rateMult); ctx.player is the corpse owner
function W.lootMult(ctx)
	local w = W.window()
	if not w.active then
		return 1
	end
	return W.mults(ctx and ctx.player).loot
end

-- ---------------------------------------------------------------- texts
local function themeName(theme)
	return ChaosI18n.msg(theme.name)
end

local function themeText(theme)
	return ChaosI18n.msg(theme.text)
end

local function dayName(t)
	return ChaosI18n.msg(K.WEEKDAYS[K.parts(t, offset(t)).wday])
end

local function clock(t)
	local p = K.parts(t, offset(t))
	return K.clockText(p.hour, p.min)
end

-- the end of the window, "Sunday 23:59": the last minute, not the next midnight
local function endDay(w)
	return dayName(w.endsAt - 60), clock(w.endsAt - 60)
end

-- the line of !events and the login while it runs, in the player's language
local function lineFor(w)
	return function(player)
		local day, at = endDay(w)
		return Chaos.t(player, "Weekend Ritual - %s: %s Until %s at %s.", themeName(w.theme), themeText(w.theme), day, at)
	end
end

-- ---------------------------------------------------------------- the events calendar and !events
function W.refresh()
	local E = ChaosEvents
	if not (E and E.dynamic) then
		return
	end
	local w = W.window()
	if w.active then
		E.dynamic.weekend_ritual = {id = "weekend_ritual", name = cfg().calendar.name, description = w.theme.text,
			describe = lineFor(w), untilTime = w.endsAt}
	else
		E.dynamic.weekend_ritual = nil
	end
end

-- the entries of the login screen calendar and the Event Calendar (events_schedule.lua E.calendar), none when off
function W.calendarEntries(t)
	if not W.enabled() then
		return {}
	end
	t = t or os.time()
	local days = Chaos.events and Chaos.events.calendarDays or 62
	return K.calendar(cfg(), t, offset(t), days)
end

-- ---------------------------------------------------------------- experience, skill training, rift chests
local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	if not (source and source.isMonster and source:isMonster()) then
		return exp
	end
	local w = W.window()
	if not w.active then
		return exp
	end
	local mult = W.mults(self).xp
	if mult ~= 1 then
		return math.floor(exp * mult)
	end
	return exp
end
xpCb:register(cfg().xpIndex or 55)

local skillCb = EventCallback
skillCb.onGainSkillTries = function(self, skill, tries)
	local w = W.window()
	if not w.active or not tries or tries <= 0 then
		return tries
	end
	return K.scaleTries(tries, W.mults(self).skill)
end
skillCb:register(cfg().skillIndex or 6)

-- the rift's world modifiers (rift_core.lua R.worldMods): the community goal's answer, and the theme's richer chests
local function hookRifts()
	ChaosRiftCore = ChaosRiftCore or {}
	ChaosRiftCore.hooks = ChaosRiftCore.hooks or {}
	local current = ChaosRiftCore.hooks.world
	if current and W.riftHook == current then
		return -- already wrapped (a reload of this file only)
	end
	local inner = current
	W.riftHook = function(player, ctx)
		local wm
		if inner then
			local ok, got = pcall(inner, player, ctx)
			wm = ok and type(got) == "table" and got or nil
		end
		local w = W.window()
		if not w.active then
			return wm
		end
		local extra = W.mults(player).riftReward
		if extra <= 0 then
			return wm
		end
		local out = {}
		for k, v in pairs(wm or {}) do
			out[k] = v
		end
		out.rewardMult = (out.rewardMult or 0) + extra
		return out
	end
	ChaosRiftCore.hooks.world = W.riftHook
end
hookRifts()

-- ---------------------------------------------------------------- announcements and the highlight
local function toast(text)
	if ChaosNotify and ChaosNotify.gmBroadcast then
		ChaosNotify.gmBroadcast(nil, text)
	end
end

local function say(text, withToast)
	local english = Chaos.broadcast(MESSAGE_EVENT_ADVANCE, text)
	if withToast then
		toast(text)
	end
	log(english)
end

local function kindLabel(h)
	if h.kind == "invasion" then
		return ChaosI18n.msg("an invasion")
	end
	return ChaosI18n.msg("a world boss")
end

-- the weekend highlight: the world boss of the rotation (or the named one), or an invasion
function W.startHighlight()
	local h = cfg().highlight
	if h.kind == "invasion" then
		if not (ChaosInvasion and ChaosInvasion.start) then
			return false, "invasion.lua is not loaded"
		end
		return ChaosInvasion.start(h.area or "random", h.faction)
	end
	local B = ChaosWorldBoss
	if not (B and B.start) then
		return false, "worldboss.lua is not loaded"
	end
	local index
	if h.boss and h.boss ~= "" then
		index = B.findBoss and B.findBoss(h.boss)
		if not index then
			return false, "unknown boss " .. tostring(h.boss)
		end
	end
	return B.start(index)
end

local function doneTable(w)
	local done = {}
	for k, v in pairs(W.done) do
		done[k] = v
	end
	if w and w.key then
		local g = gs()
		if globalGet(g.started) == w.key then done["start:" .. w.key] = true end
		if globalGet(g.ended) == w.key then done["end:" .. w.key] = true end
		if globalGet(g.highlight) == w.key then done["hl:" .. w.key] = true end
	end
	return done
end

local function markDone(a)
	local g = gs()
	for _, k in ipairs(a.mark or {}) do
		W.done[k] = true
	end
	if a.kind == "start" then Game.setStorageValue(g.started, a.key)
	elseif a.kind == "endwarn" then Game.setStorageValue(g.ended, a.key)
	elseif a.kind == "highlight" then Game.setStorageValue(g.highlight, a.key) end
end

-- one pass: refresh the !events line, then say and start what is due
function W.tick(t)
	t = t or os.time()
	W.refresh()
	if not W.enabled() then
		return
	end
	local c = cfg()
	local w = W.window(t)
	if not w.active then
		return
	end
	local actions = K.due(c, t, offset(t), doneTable(w))
	for _, a in ipairs(actions) do
		if a.kind == "start" then
			markDone(a)
			local day, at = endDay(w)
			say(ChaosI18n.msg("WEEKEND RITUAL: the weekend begins! %s: %s It lasts until %s at %s.", themeName(w.theme),
				themeText(w.theme), day, at), true)
		elseif a.kind == "endwarn" then
			markDone(a)
			local day, at = endDay(w)
			say(ChaosI18n.msg("WEEKEND RITUAL: it ends in %d minutes (%s at %s). Make the most of it!", a.minutes, day, at), true)
		elseif a.kind == "warnhl" then
			markDone(a)
			say(ChaosI18n.msg("WEEKEND RITUAL: the weekend highlight, %s, begins in %d minutes.", kindLabel(c.highlight),
				a.minutes), a.minutes == (c.highlight.warnMinutes or {})[1])
		elseif a.kind == "highlight" then
			local ok, err = W.startHighlight()
			if ok then
				markDone(a)
			else
				-- another world boss or invasion is running: tried again on the next pass, until the grace is over
				log("highlight not started yet: " .. tostring(err))
			end
		end
	end
end

local ticker = GlobalEvent("ChaosWeekendTick")
function ticker.onThink(interval)
	W.tick()
	return true
end
ticker:interval((cfg().tickSeconds or 30) * 1000)
ticker:register()

local startup = GlobalEvent("ChaosWeekendStartup")
function startup.onStartup()
	for _, problem in ipairs(K.validate(cfg())) do
		log("weekend_config.lua: " .. problem)
	end
	W.cache = nil
	W.refresh()
	return true
end
startup:register()

-- ---------------------------------------------------------------- login: the countdown before the start
-- (while it runs the line comes from !events' login lines, events_schedule.lua)
local login = CreatureEvent("ChaosWeekendLogin")
function login.onLogin(player)
	if not W.enabled() then
		return true
	end
	local t = os.time()
	local pv = K.preview(cfg(), t, offset(t))
	if pv then
		local p = K.parts(pv.startsAt, offset(t))
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, Chaos.t(player, "Weekend Ritual starts %s at %s (in %s): %s",
			ChaosI18n.msg(K.WEEKDAYS[p.wday]), K.clockText(p.hour, p.min), K.span(pv.wait), themeName(pv.theme)))
	end
	return true
end
login:register()

-- ---------------------------------------------------------------- staff
function W.status()
	local c = cfg()
	local t = os.time()
	local lines = {}
	if not c.enabled then
		return "The Weekend Ritual is off in weekend_config.lua (enabled = false)."
	end
	if globalGet(gs().off) == 1 then
		lines[#lines + 1] = "Switched off by staff (/weekend on, or the admin panel)."
	end
	local w = K.window(c, t, offset(t))
	if w.active then
		lines[#lines + 1] = string.format("Running: %s, until %s (%s left).", w.theme.name, K.stamp(w.endsAt, offset(t)),
			K.span(w.remaining))
		local at = K.highlightAt(c, w, offset(t))
		if at then
			lines[#lines + 1] = string.format("Highlight (%s) at %s.", c.highlight.kind, K.stamp(at, offset(t)))
		end
	end
	if w.nextStart then
		lines[#lines + 1] = string.format("Next start: %s, %s.", K.stamp(w.nextStart, offset(t)), w.nextTheme.name)
	end
	return table.concat(lines, " ")
end

local function groupOf(player)
	local ok, g = pcall(function() return player:getGroup():getId() end)
	return ok and tonumber(g) or 0
end

local talk = TalkAction("/weekend")
function talk.onSay(player, words, param)
	if groupOf(player) < (cfg().staffGroup or 4) then
		return true
	end
	local cmd = (tostring(param or ""):match("^%s*(%S*)") or ""):lower()
	local text
	if cmd == "" or cmd == "status" then
		text = W.status()
	elseif groupOf(player) < (cfg().switchGroup or 5) then
		text = "Switching the Weekend Ritual needs group " .. (cfg().switchGroup or 5) .. "."
	elseif cmd == "on" or cmd == "off" then
		W.setStaffOff(cmd == "off")
		text = W.status()
	else
		text = "Use /weekend status, /weekend on or /weekend off."
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, "[weekend] " .. text)
	return false
end
talk:separator(" ")
talk:register()

-- the admin panel (Events > Weekend Ritual; the admin app's remote commands run it too)
ChaosAdminPending = ChaosAdminPending or {}
ChaosAdminPending["events.weekend"] = {id = "events.weekend", category = "events", name = "Weekend Ritual",
	description = "The weekend theme bonus and the Saturday highlight: its state, or switch it off or on (the config's enabled still wins).",
	minGroup = 5, confirm = true,
	params = {{name = "mode", label = "Mode", type = "select", options = {{value = "status", label = "Status"},
		{value = "on", label = "Switch on"}, {value = "off", label = "Switch off"}}}},
	handler = function(actor, p)
		if p.mode == "on" or p.mode == "off" then
			W.setStaffOff(p.mode == "off")
		end
		return true, W.status()
	end}
ChaosAdminHooks = ChaosAdminHooks or {}
ChaosAdminHooks.weekend_ritual = {name = "weekend_ritual", kind = "event",
	description = "Weekend Ritual: start switches it on, stop switches it off (weekend.lua; the schedule stays Friday 18:00 to Sunday 23:59)",
	start = function() W.setStaffOff(false); return true, W.status() end,
	stop = function() W.setStaffOff(true); return true, W.status() end}

return W
