-- World category.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "world"; def.id = "world." .. def.id; ChaosAdminPending[def.id] = def end

local POS_OPT = {name = "pos", label = "Position x,y,z (empty = my tile)", type = "pos", required = false, hint = "e.g. 1000,1000,7"}

local function toPos(actor, p)
	if p.pos then return Position(p.pos.x, p.pos.y, p.pos.z) end
	return actor:getPosition()
end

reg{id = "spawn_monster", name = "Spawn monster", description = "Create a monster by name.",
	params = {{name = "name", label = "Monster name", type = "string", max = 60}, POS_OPT,
		{name = "count", label = "Count", type = "int", min = 1, max = 20, default = 1}},
	handler = function(actor, p)
		local pos = toPos(actor, p)
		local made = 0
		for _ = 1, p.count do
			local m = Game.createMonster(p.name, pos, true, false)
			if m then made = made + 1 end
		end
		if made == 0 then return false, "Could not spawn '" .. p.name .. "' (unknown name or no room)." end
		pos:sendMagicEffect(CONST_ME_TELEPORT)
		return true, string.format("Spawned %dx %s.", made, p.name)
	end}

reg{id = "spawn_npc", name = "Spawn NPC", description = "Create an NPC by name.",
	params = {{name = "name", label = "NPC name", type = "string", max = 60}, POS_OPT},
	handler = function(actor, p)
		local pos = toPos(actor, p)
		local n = Game.createNpc(p.name, pos, true, false)
		if not n then return false, "Could not spawn NPC '" .. p.name .. "'." end
		pos:sendMagicEffect(CONST_ME_TELEPORT)
		return true, "Spawned NPC " .. p.name .. "."
	end}

reg{id = "create_item", name = "Create item on tile", description = "Create an item (id or name) on a tile.",
	params = {{name = "item", label = "Item id or name", type = "string", max = 60}, POS_OPT,
		{name = "count", label = "Count", type = "int", min = 1, max = 1000, default = 1}},
	handler = function(actor, p)
		local it, err = ChaosAdmin.resolveItem(p.item)
		if not it then return false, err end
		local pos = toPos(actor, p)
		local item = Game.createItem(it:getId(), p.count, pos)
		if not item then return false, "Could not create item there." end
		pos:sendMagicEffect(CONST_ME_MAGIC_GREEN)
		return true, string.format("Created %dx %s at %d,%d,%d.", p.count, it:getName(), pos.x, pos.y, pos.z)
	end}

reg{id = "remove_items", name = "Remove items on tile", description = "Remove all movable items from a tile (not creatures, not unmovable fixtures).", confirm = true,
	params = {POS_OPT},
	handler = function(actor, p)
		local pos = toPos(actor, p)
		local tile = Tile(pos)
		if not tile then return false, "No tile at that position." end
		local n = 0
		local items = tile:getItems() or {}
		for _, item in ipairs(items) do
			if item:getType():isMovable() then
				item:remove(); n = n + 1
			end
		end
		return true, "Removed " .. n .. " item(s)."
	end}

reg{id = "clean_map", name = "Clean map", description = "Run cleanMap() to remove dropped items server-wide.", dangerous = true,
	handler = function()
		local n = cleanMap()
		return true, "Cleaned " .. tostring(n) .. " item(s)."
	end}

reg{id = "set_time", name = "Set world time", description = "Set the in-game clock if the server supports it (Game.setWorldTime).",
	params = {{name = "hour", label = "Hour (0-23)", type = "int", min = 0, max = 23}},
	handler = function(actor, p)
		if type(Game.setWorldTime) ~= "function" then
			return false, "Game.setWorldTime is not available on this build."
		end
		local ok, err = pcall(Game.setWorldTime, p.hour * 60)
		if not ok then return false, "Game.setWorldTime failed: " .. tostring(err) end
		return true, "World time set to " .. p.hour .. ":00."
	end}

reg{id = "set_weather", name = "Set weather", description = "Toggle rain using the Weather storage of customs/globalevents/rain.lua (only works if the rain weather config is enabled).",
	params = {{name = "weather", label = "Weather", type = "select", options = {{value = "clear", label = "Clear"}, {value = "rain", label = "Rain"}}}},
	handler = function(actor, p)
		Game.setStorageValue("Weather", p.weather == "rain" and 1 or 0)
		return true, "Weather storage set to " .. p.weather .. " (applies on the next weather tick)."
	end}

reg{id = "town_teleport", name = "Teleport to town", description = "Teleport a player to a town temple (name or id).",
	params = {{name = "player", label = "Player (empty = me)", type = "player", required = false},
		{name = "town", label = "Town name or id", type = "string", max = 40}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOrSelf(actor, p.player)
		if not t then return false, err end
		local town = Town(tonumber(p.town) or p.town)
		if not town then
			local names = {}
			for _, tw in ipairs(Game.getTowns()) do names[#names + 1] = tw:getId() .. "=" .. tw:getName() end
			return false, "Unknown town. Known: " .. table.concat(names, ", ")
		end
		t:teleportTo(town:getTemplePosition())
		return true, t:getName() .. " teleported to " .. town:getName() .. "."
	end}

reg{id = "list_towns", name = "List towns", description = "Show all town ids and names.",
	handler = function()
		local lines = {}
		for _, tw in ipairs(Game.getTowns()) do
			local pos = tw:getTemplePosition()
			lines[#lines + 1] = string.format("%d  %s  (%d,%d,%d)", tw:getId(), tw:getName(), pos.x, pos.y, pos.z)
		end
		return true, #lines .. " town(s).", lines
	end}

reg{id = "start_raid", name = "Start raid", description = "Start a raid defined in data/raids/raids.xml.",
	params = {{name = "raid", label = "Raid name", type = "string", max = 80}},
	handler = function(actor, p)
		local rv = Game.startRaid(p.raid)
		if rv ~= RETURNVALUE_NOERROR then
			return false, Game.getReturnMessage(rv)
		end
		return true, "Raid '" .. p.raid .. "' started."
	end}
