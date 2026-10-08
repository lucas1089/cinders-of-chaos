-- Players category. Registers into ChaosAdminPending (see core.lua).
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "players"; ChaosAdminPending["players." .. def.id] = def; def.id = "players." .. def.id end

local PLAYER = {name = "player", label = "Player", type = "player"}
local PLAYER_OPT = {name = "player", label = "Player (empty = me)", type = "player", required = false}

local SKILLS = {
	{value = "fist", label = "Fist"}, {value = "club", label = "Club"}, {value = "sword", label = "Sword"},
	{value = "axe", label = "Axe"}, {value = "distance", label = "Distance"}, {value = "shielding", label = "Shielding"},
	{value = "fishing", label = "Fishing"}, {value = "magic", label = "Magic level"},
}
local SKILL_CONST = {fist = "SKILL_FIST", club = "SKILL_CLUB", sword = "SKILL_SWORD", axe = "SKILL_AXE",
	distance = "SKILL_DISTANCE", shielding = "SKILL_SHIELD", fishing = "SKILL_FISHING"}

reg{id = "info", name = "Player info", description = "Show level, vocation, position, account and group of a player (online or offline).",
	params = {PLAYER},
	handler = function(actor, p)
		local t = Player(p.player)
		if t then
			local pos = t:getPosition()
			return true, "Info for " .. t:getName(), {
				"Name: " .. t:getName() .. " (guid " .. t:getGuid() .. ", account " .. t:getAccountId() .. ")",
				"Level " .. t:getLevel() .. "  " .. t:getVocation():getName() .. "  group " .. t:getGroup():getId(),
				"HP " .. t:getHealth() .. "/" .. t:getMaxHealth() .. "  MP " .. t:getMana() .. "/" .. t:getMaxMana(),
				"Position " .. pos.x .. "," .. pos.y .. "," .. pos.z,
				"IP " .. ChaosAdmin.ipToString(t:getIp()),
				"Money " .. t:getMoney() .. "  Premium days " .. (t:getPremiumDays() or 0),
				"Town " .. (t:getTown() and t:getTown():getName() or "?"),
			}
		end
		local rid = db.storeQuery("SELECT `id`,`account_id`,`level`,`vocation`,`group_id`,`lastlogin`,`balance` FROM `players` WHERE `name` = " .. db.escapeString(p.player))
		if not rid then return false, "Player not found." end
		local lines = {
			"Name: " .. p.player .. " (offline, guid " .. result.getNumber(rid, "id") .. ", account " .. result.getNumber(rid, "account_id") .. ")",
			"Level " .. result.getNumber(rid, "level") .. "  vocation id " .. result.getNumber(rid, "vocation") .. "  group " .. result.getNumber(rid, "group_id"),
			"Last login " .. os.date("%Y-%m-%d %H:%M:%S", result.getNumber(rid, "lastlogin")),
			"Bank balance " .. result.getNumber(rid, "balance"),
		}
		result.free(rid)
		return true, "Offline info for " .. p.player, lines
	end}

reg{id = "kick", name = "Kick", description = "Disconnect an online player.", confirm = true,
	params = {PLAYER},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local name = t:getName()
		t:remove()
		return true, name .. " was kicked."
	end}

reg{id = "ban", name = "Ban account", description = "Ban the account of a player (online or offline) for N days and kick.", confirm = true,
	params = {PLAYER, {name = "days", label = "Days", type = "int", min = 1, max = 3650, default = 7},
		{name = "reason", label = "Reason", type = "string", max = 200, required = false}},
	handler = function(actor, p)
		local d = ChaosAdmin.dbPlayer(p.player)
		if not d then return false, "Player not found." end
		if d.group_id >= actor:getGroup():getId() and d.id ~= actor:getGuid() then
			return false, "Target has an equal or higher group than you."
		end
		if d.id == actor:getGuid() then return false, "You cannot ban yourself." end
		local rid = db.storeQuery("SELECT 1 FROM `account_bans` WHERE `account_id` = " .. d.account_id)
		if rid then result.free(rid); return false, "Account is already banned." end
		local now = os.time()
		db.query(string.format("INSERT INTO `account_bans` (`account_id`,`reason`,`banned_at`,`expires_at`,`banned_by`) VALUES (%d,%s,%d,%d,%d)",
			d.account_id, db.escapeString(p.reason or ""), now, now + p.days * 86400, actor:getGuid()))
		local t = Player(d.name)
		if t then t:remove() end
		return true, string.format("Account %d (%s) banned for %d day(s).", d.account_id, d.name, p.days)
	end}

reg{id = "unban", name = "Unban account", description = "Remove the account ban of a player.",
	params = {PLAYER},
	handler = function(actor, p)
		local d = ChaosAdmin.dbPlayer(p.player)
		if not d then return false, "Player not found." end
		db.query("DELETE FROM `account_bans` WHERE `account_id` = " .. d.account_id)
		return true, "Account ban removed for " .. d.name .. " (if there was one)."
	end}

reg{id = "mute", name = "Mute", description = "Mute a player for N minutes (CONDITION_MUTED).",
	params = {PLAYER, {name = "minutes", label = "Minutes", type = "int", min = 1, max = 10080, default = 10}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local cond = Condition(CONDITION_MUTED)
		cond:setParameter(CONDITION_PARAM_TICKS, p.minutes * 60 * 1000)
		t:addCondition(cond)
		t:sendTextMessage(MESSAGE_STATUS_WARNING, "You have been muted for " .. p.minutes .. " minute(s).")
		return true, t:getName() .. " muted for " .. p.minutes .. " min."
	end}

reg{id = "set_level", name = "Set level", description = "Set the level of an online player (adds/removes experience).",
	params = {PLAYER_OPT, {name = "level", label = "Level", type = "int", min = 1, max = 5000}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOrSelf(actor, p.player)
		if not t then return false, err end
		local want = ChaosAdmin.expForLevel(p.level)
		local cur = t:getExperience()
		if want > cur then
			t:addExperience(want - cur, false)
		elseif want < cur then
			t:removeExperience(cur - want, false)
		end
		return true, string.format("%s is now level %d.", t:getName(), t:getLevel())
	end}

reg{id = "set_skill", name = "Set skill", description = "Raise a skill or magic level to a value (cannot lower; max +500 levels per call).",
	params = {PLAYER_OPT, {name = "skill", label = "Skill", type = "select", options = SKILLS},
		{name = "level", label = "Target level", type = "int", min = 1, max = 2000}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOrSelf(actor, p.player)
		if not t then return false, err end
		local voc = t:getVocation()
		if p.skill == "magic" then
			local cur = t:getBaseMagicLevel()
			if p.level <= cur then return false, "Can only raise (current " .. cur .. ")." end
			if p.level - cur > 500 then return false, "Max +500 levels per call." end
			local total = 0
			for l = cur, p.level - 1 do total = total + voc:getRequiredManaSpent(l + 1) end
			t:addManaSpent(total)
			return true, t:getName() .. " magic level is now " .. t:getBaseMagicLevel()
		end
		local sk = ChaosAdmin.constant(SKILL_CONST[p.skill])
		if sk == nil then return false, "Skill constant missing on this server." end
		local cur = t:getSkillLevel(sk)
		if p.level <= cur then return false, "Can only raise (current " .. cur .. ")." end
		if p.level - cur > 500 then return false, "Max +500 levels per call." end
		local total = 0
		for l = cur, p.level - 1 do total = total + voc:getRequiredSkillTries(sk, l + 1) end
		t:addSkillTries(sk, total)
		return true, t:getName() .. " " .. p.skill .. " is now " .. t:getSkillLevel(sk)
	end}

reg{id = "set_vocation", name = "Set vocation", description = "Change vocation by id.", confirm = true,
	params = {PLAYER_OPT, {name = "vocation", label = "Vocation id", type = "int", min = 0, max = 100}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOrSelf(actor, p.player)
		if not t then return false, err end
		local v = Vocation(p.vocation)
		if not v then return false, "Unknown vocation id." end
		t:setVocation(v:getId())
		return true, t:getName() .. " is now a " .. v:getName() .. ". (Relog recommended.)"
	end}

reg{id = "give_item", name = "Give item", description = "Add an item (id or name) to a player's inventory.",
	params = {PLAYER_OPT, {name = "item", label = "Item id or name", type = "string", max = 60},
		{name = "count", label = "Count", type = "int", min = 1, max = 10000, default = 1}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOrSelf(actor, p.player)
		if not t then return false, err end
		local it, e2 = ChaosAdmin.resolveItem(p.item)
		if not it then return false, e2 end
		local given = 0
		if it:isStackable() then
			local item = t:addItem(it:getId(), p.count)
			if item then given = p.count end
		else
			if p.count > 100 then return false, "Max 100 for non-stackable items." end
			for _ = 1, p.count do
				if t:addItem(it:getId(), 1) then given = given + 1 else break end
			end
		end
		if given == 0 then return false, "Could not add item (no capacity/room?)." end
		return true, string.format("Gave %dx %s to %s.", given, it:getName(), t:getName())
	end}

reg{id = "remove_item", name = "Remove item", description = "Remove items (id or name) from a player's inventory.", confirm = true,
	params = {PLAYER, {name = "item", label = "Item id or name", type = "string", max = 60},
		{name = "count", label = "Count", type = "int", min = 1, max = 100000, default = 1}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local it, e2 = ChaosAdmin.resolveItem(p.item)
		if not it then return false, e2 end
		if t:removeItem(it:getId(), p.count) then
			return true, string.format("Removed %dx %s from %s.", p.count, it:getName(), t:getName())
		end
		return false, "Player does not have that many."
	end}

reg{id = "give_premium", name = "Give premium", description = "Add premium days.",
	params = {PLAYER_OPT, {name = "days", label = "Days", type = "int", min = 1, max = 3650, default = 30}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOrSelf(actor, p.player)
		if not t then return false, err end
		t:addPremiumDays(p.days)
		return true, string.format("Gave %d premium day(s) to %s.", p.days, t:getName())
	end}

reg{id = "teleport_to", name = "Teleport to player", description = "Teleport yourself next to a player.",
	params = {PLAYER},
	handler = function(actor, p)
		local t = Player(p.player)
		if not t then return false, "Player is not online." end
		actor:teleportTo(t:getPosition())
		return true, "Teleported to " .. t:getName() .. "."
	end}

reg{id = "summon", name = "Summon player", description = "Teleport a player to your position.",
	params = {PLAYER},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		t:teleportTo(actor:getPosition())
		return true, t:getName() .. " summoned."
	end}

reg{id = "heal", name = "Heal", description = "Restore full health and mana.",
	params = {PLAYER_OPT},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOrSelf(actor, p.player)
		if not t then return false, err end
		Chaos.heal(t, t:getMaxHealth() - t:getHealth())
		t:addMana(t:getMaxMana() - t:getMana())
		t:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
		return true, t:getName() .. " healed."
	end}

reg{id = "set_group", name = "Set group", description = "Change a player's group id (cannot exceed your own). Persisted in the DB too.",
	dangerous = true,
	params = {PLAYER, {name = "group", label = "Group id", type = "int", min = 1, max = 100}},
	handler = function(actor, p)
		local myGroup = actor:getGroup():getId()
		if p.group > myGroup then return false, "You cannot assign a group above your own." end
		local g = Group(p.group)
		if not g then return false, "Unknown group id." end
		local d = ChaosAdmin.dbPlayer(p.player)
		if not d then return false, "Player not found." end
		if d.id ~= actor:getGuid() and d.group_id >= myGroup then
			return false, "Target has an equal or higher group than you."
		end
		db.query(string.format("UPDATE `players` SET `group_id` = %d WHERE `id` = %d", p.group, d.id))
		local t = Player(d.name)
		if t then t:setGroup(g) end
		return true, string.format("%s is now group %d%s.", d.name, p.group, t and "" or " (applies on next login)")
	end}

reg{id = "add_storage", name = "Set storage", description = "Set a player storage key to a value.",
	params = {PLAYER_OPT, {name = "key", label = "Key", type = "int", min = 1, max = 2147483647},
		{name = "value", label = "Value", type = "int", default = 1}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOrSelf(actor, p.player)
		if not t then return false, err end
		local old = t:getStorageValue(p.key)
		t:setStorageValue(p.key, p.value)
		return true, string.format("Storage %d of %s: %d -> %d", p.key, t:getName(), old, p.value)
	end}
