-- Events category. Events are driven by hooks registered with ChaosAdminRegisterHook (see core.lua).
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "events"; def.id = "events." .. def.id; ChaosAdminPending[def.id] = def end

ChaosAdmin = ChaosAdmin or {}

-- Built-in hooks ------------------------------------------------------------------------------
ChaosAdminHooks = ChaosAdminHooks or {}
local function reghook(name, def) def.name = name; ChaosAdminHooks[name] = def end

reghook("weather_rain", {kind = "event", description = "Rain weather (Weather storage of customs/globalevents/rain.lua)",
	start = function() Game.setStorageValue("Weather", 1); return true, "Rain enabled." end,
	stop = function() Game.setStorageValue("Weather", 0); return true, "Rain disabled." end})

reghook("double_exp", {kind = "event", description = "2x experience for 60 minutes (needs EventCallback onGainExperience, see below)",
	start = function() ChaosAdmin.expEvent = {mult = 2, untilTs = os.time() + 3600}; return true, "2x experience active for 60 min." end,
	stop = function() ChaosAdmin.expEvent = nil; return true, "Experience event stopped." end})

-- Experience event multiplier applied through the revscript EventCallback system of this server.
local ec = EventCallback
function ec.onGainExperience(self, source, exp, rawExp)
	local e = ChaosAdmin and ChaosAdmin.expEvent
	if e and os.time() < e.untilTs then
		return exp * e.mult
	end
	return exp
end
ec:register(50)

local TEMPLATES = {
	{value = "event_start", label = "Event starting"}, {value = "event_end", label = "Event ended"},
	{value = "maintenance", label = "Maintenance warning"}, {value = "boss", label = "Boss appeared"},
	{value = "double_exp", label = "Double experience"},
}
local TEMPLATE_TEXT = {
	event_start = "An event is starting now! %s",
	event_end = "The event has ended. Thank you for playing! %s",
	maintenance = "Maintenance is planned soon, please find a safe place. %s",
	boss = "A powerful boss has appeared! %s",
	double_exp = "Double experience is active! %s",
}

reg{id = "list", name = "List event hooks", description = "Show hooks usable with Start/Stop event.",
	handler = function()
		local names = {}
		for n, h in pairs(ChaosAdminHooks) do if (h.kind or "event") == "event" then names[#names + 1] = n end end
		table.sort(names)
		local lines = {}
		for _, n in ipairs(names) do lines[#lines + 1] = n .. "  -  " .. (ChaosAdminHooks[n].description or "") end
		return true, #lines .. " event hook(s).", lines
	end}

reg{id = "start", name = "Start event", description = "Run the start() of a registered event hook by name.", confirm = true,
	params = {{name = "name", label = "Hook name (see 'List event hooks')", type = "string", max = 60}},
	handler = function(actor, p)
		local h = ChaosAdminHooks[p.name]
		if not h or (h.kind or "event") ~= "event" then return false, "Unknown event hook." end
		return ChaosAdmin.callHook(p.name, "start", actor)
	end}

reg{id = "stop", name = "Stop event", description = "Run the stop() of a registered event hook by name.",
	params = {{name = "name", label = "Hook name", type = "string", max = 60}},
	handler = function(actor, p)
		local h = ChaosAdminHooks[p.name]
		if not h or (h.kind or "event") ~= "event" then return false, "Unknown event hook." end
		return ChaosAdmin.callHook(p.name, "stop", actor)
	end}

reg{id = "broadcast_template", name = "Broadcast template", description = "Send a predefined announcement with optional extra text.",
	params = {{name = "template", label = "Template", type = "select", options = TEMPLATES},
		{name = "extra", label = "Extra text", type = "string", max = 150, required = false}},
	handler = function(actor, p)
		ChaosAdmin.broadcast(string.format(TEMPLATE_TEXT[p.template], p.extra or ""):gsub("%s+$", ""), MESSAGE_EVENT_ADVANCE)
		return true, "Broadcast sent."
	end}

reg{id = "set_exp", name = "Experience rate event", description = "Multiply experience gain for N minutes (0 minutes = stop).", confirm = true,
	params = {{name = "multiplier", label = "Multiplier", type = "int", min = 1, max = 10, default = 2},
		{name = "minutes", label = "Minutes (0 = stop)", type = "int", min = 0, max = 1440, default = 60}},
	handler = function(actor, p)
		if p.minutes == 0 or p.multiplier == 1 then
			ChaosAdmin.expEvent = nil
			return true, "Experience event stopped."
		end
		ChaosAdmin.expEvent = {mult = p.multiplier, untilTs = os.time() + p.minutes * 60}
		ChaosAdmin.broadcast(string.format("Experience x%d for %d minute(s)!", p.multiplier, p.minutes), MESSAGE_EVENT_ADVANCE)
		return true, string.format("Exp x%d for %d min.", p.multiplier, p.minutes)
	end}
