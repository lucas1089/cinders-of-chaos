-- Content category.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "content"; def.id = "content." .. def.id; ChaosAdminPending[def.id] = def end

reg{id = "reload_content", name = "Reload quests / tasks", description = "Reload quests (data xml) or tasks (revscripts, reloads ALL scripts).", dangerous = true,
	params = {{name = "what", label = "What", type = "select", options = {{value = "quests", label = "Quests"}, {value = "tasks", label = "Tasks (reload scripts)"}}}},
	handler = function(actor, p)
		local c = ChaosAdmin.constant(p.what == "quests" and "RELOAD_TYPE_QUESTS" or "RELOAD_TYPE_SCRIPTS")
		if c == nil then return false, "Reload type not available." end
		if p.what == "tasks" and EventCallback and EventCallback.clear then EventCallback:clear() end
		Game.reload(c)
		return true, "Reloaded " .. p.what .. "."
	end}

reg{id = "hooks", name = "List content hooks", description = "Dungeon / tower / boss hooks registered via ChaosAdminRegisterHook.",
	handler = function()
		local names = {}
		for n, h in pairs(ChaosAdminHooks or {}) do
			local k = h.kind or "event"
			if k ~= "event" then names[#names + 1] = n end
		end
		table.sort(names)
		local lines = {}
		for _, n in ipairs(names) do
			local h = ChaosAdminHooks[n]
			lines[#lines + 1] = string.format("[%s] %s  -  %s", h.kind, n, h.description or "")
		end
		if #lines == 0 then lines[1] = "No dungeon/tower/boss hooks registered yet (see README)." end
		return true, "Content hooks", lines
	end}

reg{id = "hook_run", name = "Dungeon / tower control", description = "Run start, stop or reset of a registered content hook (dungeon, tower, boss).", confirm = true,
	params = {{name = "name", label = "Hook name", type = "string", max = 60},
		{name = "op", label = "Operation", type = "select", options = {{value = "start", label = "Start"}, {value = "stop", label = "Stop"}, {value = "reset", label = "Reset"}}}},
	handler = function(actor, p)
		local h = ChaosAdminHooks and ChaosAdminHooks[p.name]
		if not h or (h.kind or "event") == "event" then return false, "Unknown content hook." end
		return ChaosAdmin.callHook(p.name, p.op, actor)
	end}

reg{id = "boss_spawn", name = "Spawn boss", description = "Spawn a boss monster by name and optionally announce it.",
	params = {{name = "name", label = "Boss monster name", type = "string", max = 60},
		{name = "pos", label = "Position x,y,z (empty = my tile)", type = "pos", required = false},
		{name = "announce", label = "Announce", type = "bool"}},
	handler = function(actor, p)
		local pos = p.pos and Position(p.pos.x, p.pos.y, p.pos.z) or actor:getPosition()
		local m = Game.createMonster(p.name, pos, true, false)
		if not m then return false, "Could not spawn '" .. p.name .. "'." end
		pos:sendMagicEffect(CONST_ME_TELEPORT)
		if p.announce then
			ChaosAdmin.broadcast(string.format("%s has appeared at %d,%d!", m:getName(), pos.x, pos.y), MESSAGE_EVENT_ADVANCE)
		end
		return true, "Spawned boss " .. m:getName() .. "."
	end}
