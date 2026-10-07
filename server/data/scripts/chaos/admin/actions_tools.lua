-- Tools category. Cheat tools only ever affect the acting admin.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "tools"; def.id = "tools." .. def.id; ChaosAdminPending[def.id] = def end

ChaosAdmin = ChaosAdmin or {}
ChaosAdmin.god = ChaosAdmin.god or {}

-- God-mode: damage and mana loss are cancelled while the toggle is on and the player still passes the admin check.
local godEvent = CreatureEvent("ChaosAdminGod")
function godEvent.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if creature:isPlayer() and ChaosAdmin.god[creature:getGuid()] and ChaosAdmin.isAdmin(creature) then
		return 0, primaryType, 0, secondaryType
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
local godManaEvent = CreatureEvent("ChaosAdminGodMana")
function godManaEvent.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if creature:isPlayer() and ChaosAdmin.god[creature:getGuid()] and ChaosAdmin.isAdmin(creature) then
		return 0, primaryType, 0, secondaryType
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
godEvent:type("healthchange")
godEvent:register()
godManaEvent:type("manachange")
godManaEvent:register()

reg{id = "talkaction", name = "Run talkaction", description = "Run a whitelisted legacy talkaction script (data/talkactions/scripts/<name>.lua) as yourself. The script's own permission checks still apply. Output appears in your console.",
	params = {{name = "name", label = "Talkaction file name", type = "string", max = 40},
		{name = "param", label = "Parameter", type = "string", max = 120, required = false}},
	handler = function(actor, p)
		local name = p.name:lower()
		if not name:match("^[a-z0-9_]+$") then return false, "Invalid talkaction name." end
		local allowed = false
		for _, n in ipairs(ChaosAdminConfig.talkactionWhitelist) do if n == name then allowed = true end end
		if not allowed then return false, "Talkaction '" .. name .. "' is not in ChaosAdminConfig.talkactionWhitelist." end
		local f = loadfile("data/talkactions/scripts/" .. name .. ".lua")
		if not f then return false, "Talkaction script not found." end
		local env = setmetatable({}, {__index = _G})
		setfenv(f, env)
		f()
		if type(env.onSay) ~= "function" then return false, "Script has no onSay." end
		env.onSay(actor, "/" .. name, p.param or "")
		return true, "Ran /" .. name .. " " .. (p.param or "")
	end}

reg{id = "invisible", name = "Invisible", description = "Toggle the invisible condition on yourself.",
	handler = function(actor)
		if actor:getCondition(CONDITION_INVISIBLE) then
			actor:removeCondition(CONDITION_INVISIBLE)
			return true, "You are visible."
		end
		local c = Condition(CONDITION_INVISIBLE)
		c:setParameter(CONDITION_PARAM_TICKS, -1)
		actor:addCondition(c)
		return true, "You are invisible."
	end}

reg{id = "ghost", name = "Ghost mode", description = "Toggle ghost mode (completely hidden from players).", minGroup = 6,
	handler = function(actor)
		local on = not actor:isInGhostMode()
		actor:setGhostMode(on)
		if on then actor:setStorageValue(STORAGE_GHOSTMODE or 94658, 1) else actor:setStorageValue(STORAGE_GHOSTMODE or 94658, 0) end
		return true, on and "Ghost mode ON." or "Ghost mode OFF."
	end}

reg{id = "god_mode", name = "God mode", description = "Toggle invulnerability (health and mana loss cancelled).", minGroup = 5,
	handler = function(actor)
		local guid = actor:getGuid()
		if ChaosAdmin.god[guid] then
			ChaosAdmin.god[guid] = nil
			actor:unregisterEvent("ChaosAdminGod")
			actor:unregisterEvent("ChaosAdminGodMana")
			return true, "God mode OFF."
		end
		ChaosAdmin.god[guid] = true
		actor:registerEvent("ChaosAdminGod")
		actor:registerEvent("ChaosAdminGodMana")
		return true, "God mode ON (until relog/server restart)."
	end}

reg{id = "speed", name = "Set speed", description = "Set your walking speed. 0 resets to the base speed.",
	params = {{name = "speed", label = "Speed (0 = reset, max 4000)", type = "int", min = 0, max = 4000, default = 0}},
	handler = function(actor, p)
		local target = p.speed
		if target == 0 then target = actor:getBaseSpeed() end
		actor:changeSpeed(target - actor:getSpeed())
		return true, "Speed is now " .. actor:getSpeed() .. "."
	end}
