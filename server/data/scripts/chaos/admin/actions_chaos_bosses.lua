-- Chaos: Bosses & Events. Pocket bosses (pocketboss.lua ChaosPocketBoss, charges by pocketboss_core.lua), the Ashen
-- Sepulchre raid (raid.lua ChaosRaid), world bosses (worldboss.lua ChaosWorldBoss), invasions and world events
-- (invasion.lua ChaosInvasion, worldevents.lua) and treasure goblins (treasure_goblin.lua ChaosTreasureGoblin): what the
-- staff commands /pocketboss, /raid, /worldboss, /invasion and /goblin do. A pocket charge row is written with the
-- same single statement as the pocket system's own save (it has no public write for staff); the raid lockout reset is
-- the statement of /raid reset, for a named character.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "chaos_bosses"; def.id = "chaos_bosses." .. def.id; ChaosAdminPending[def.id] = def end

local ONLINE = {name = "player", label = "Player (online)", type = "player"}
local PLAYER = {name = "player", label = "Player", type = "player"}

local function sys(name, fn) return ChaosAdmin.system(name, fn) end

-- ------------------------------------------------------------------ pocket bosses (server/README.md "Pocket bosses")
local function pocketSave(PB, guid, key, row)
	PB.rows[guid] = PB.rows[guid] or {}
	PB.rows[guid][key] = row
	if not PB.ensureTable() then return false end
	local tbl = (Chaos.tables and Chaos.tables.pocketBoss) or Chaos.pocketBossConfig.table
	return db.query(string.format("INSERT INTO `%s` (`player_id`, `boss_key`, `day`, `used`, `bonus`, `bonus_day`, `bonus_added`, `kills`, `event_at`) " ..
		"VALUES (%d, %s, %d, %d, %d, %d, %d, 0, %d) ON DUPLICATE KEY UPDATE `day` = VALUES(`day`), `used` = VALUES(`used`), " ..
		"`bonus` = VALUES(`bonus`), `bonus_day` = VALUES(`bonus_day`), `bonus_added` = VALUES(`bonus_added`), `event_at` = VALUES(`event_at`)",
		tbl, guid, db.escapeString(key), row.day or 0, row.used or 0, row.bonus or 0, row.bonusDay or 0, row.bonusAdded or 0, row.eventAt or 0))
end

local function pocketLines(PB, t)
	local lines = {}
	for _, b in ipairs(PB.bosses()) do
		local c = PB.charges(t, b.key)
		lines[#lines + 1] = string.format("%s (%s, level %d): %d left (%d of %d daily, %d bonus)", b.name, b.key, b.minLevel or 0,
			c.left, c.daily, c.max, c.bonus)
	end
	return lines
end

reg{id = "pocket_view", name = "Pocket bosses: charges", description = "Every pocket boss with the character's charges left today (daily and bonus).",
	params = {ONLINE},
	handler = function(actor, p)
		local PB, why = sys("ChaosPocketBoss", "charges")
		if not PB then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local lines = pocketLines(PB, t)
		return true, string.format("%s: %d pocket boss(es).", t:getName(), #lines), lines
	end}

reg{id = "pocket_set", name = "Pocket bosses: set charges", description = "Sets today's daily charges left and the bonus charges held for one boss (bonus at most charges.bonusMax).",
	minGroup = 5,
	params = {ONLINE, {name = "boss", label = "Boss key", type = "string", max = 48},
		{name = "daily", label = "Daily charges left", type = "int", min = 0, max = 100},
		{name = "bonus", label = "Bonus charges", type = "int", min = 0, max = 100, default = 0}},
	handler = function(actor, p)
		local PB, why = sys("ChaosPocketBoss", "charges")
		if not PB or not ChaosPocketBossCore then return false, why or "pocketboss.lua is not loaded." end
		if not PB.index().byKey[p.boss] then return false, "No pocket of boss " .. p.boss .. "." end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local cfg = Chaos.pocketBossConfig
		local c = PB.charges(t, p.boss) -- loads the character's rows
		local maxBonus = math.max(0, math.floor(tonumber((cfg.charges or {}).bonusMax) or 0))
		local row = {day = c.day, used = math.max(0, c.max - math.min(p.daily, c.max)), bonus = math.min(p.bonus, maxBonus),
			bonusDay = c.bonusDay, bonusAdded = c.bonusAdded, eventAt = c.eventAt}
		if not pocketSave(PB, t:getGuid(), p.boss, row) then return false, "The row could not be written." end
		pcall(PB.push, t)
		c = PB.charges(t, p.boss)
		return true, string.format("%s, %s: %d left (%d daily, %d bonus).", t:getName(), p.boss, c.left, c.daily, c.bonus)
	end}

reg{id = "pocket_reset_day", name = "Pocket bosses: reset the day", description = "Gives back today's daily charges of every boss (as /pocketboss reset).",
	params = {ONLINE},
	handler = function(actor, p)
		local PB, why = sys("ChaosPocketBoss", "view")
		if not PB then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		PB.view(t) -- loads the character's rows
		local guid, n = t:getGuid(), 0
		for key, row in pairs(PB.rows[guid] or {}) do
			row.used = 0
			pocketSave(PB, guid, key, row)
			n = n + 1
		end
		pcall(PB.push, t)
		return true, string.format("%s: today's pocket charges are back (%d boss row(s)).", t:getName(), n)
	end}

reg{id = "pocket_runs", name = "Pocket bosses: open pockets", description = "Every open pocket: slot, boss, state, players and time left (as /pocketboss).",
	handler = function(actor)
		local PB, why = sys("ChaosPocketBoss", "timeLeft")
		if not PB then return false, why end
		local lines, ms = {}, os.mtime and os.mtime() or os.time() * 1000
		for slot, r in pairs(PB.runs) do
			local n = 0
			for _ in pairs(r.players or {}) do n = n + 1 end
			lines[#lines + 1] = string.format("slot %d: %s, %s, %d player(s), %ds left", slot, r.boss and r.boss.name or "?",
				tostring(r.state), n, PB.timeLeft(r, ms) or 0)
		end
		return true, #lines .. " pocket(s) open. Close one with Instances & PvP > Instances: close.", lines
	end}

-- ------------------------------------------------------------------ the Ashen Sepulchre raid (server/README.md "The Ashen Sepulchre")
reg{id = "raid_status", name = "Raid: status", description = "Every open raid: slot, instance, kills, players and the boss fought (as /raid status).",
	handler = function(actor)
		local X, why = sys("ChaosRaid", "lockSet")
		if not X then return false, why end
		local cfg = ChaosRaidConfig or {bosses = {}}
		local lines = {}
		for slot, r in pairs(X.runs) do
			local n = 0
			for _ in pairs(r.players or {}) do n = n + 1 end
			lines[#lines + 1] = string.format("slot %d: raid %d, killed %d / trash %d, %d player(s)%s", slot, r.inst.id, r.inst.killed or 0,
				r.inst.trash or 0, n, r.fight and (", fighting " .. tostring((cfg.bosses[r.fight.idx] or {}).name)) or "")
		end
		return true, #lines .. " open raid(s).", lines
	end}

reg{id = "raid_lockouts", name = "Raid: lockouts", description = "The raid bosses a character looted this week.",
	params = {PLAYER},
	handler = function(actor, p)
		local X, why = sys("ChaosRaid", "lockSet")
		if not X then return false, why end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		local keys = {}
		for key in pairs(X.lockSet(t.guid) or {}) do keys[#keys + 1] = tostring(key) end
		table.sort(keys)
		local row = X.row(t.guid) or {}
		return true, string.format("%s: %d lockout(s) this week; %d marks, %d clears.", t.name, #keys, row.marks or 0, row.clears or 0),
			{#keys > 0 and table.concat(keys, ", ") or "none"}
	end}

reg{id = "raid_reset_lockouts", name = "Raid: reset lockouts", description = "Clears a character's raid lockouts of this week (as /raid reset).",
	minGroup = 5, confirm = true, params = {PLAYER},
	handler = function(actor, p)
		local X, why = sys("ChaosRaid", "lockSet")
		if not X or not ChaosRaidCore then return false, why or "raid.lua is not loaded." end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		local cfg = ChaosRaidConfig
		local week = ChaosRaidCore.cfgWeek(cfg, os.time())
		db.query(string.format("DELETE FROM `%s` WHERE `player_id` = %d AND `week` = %d", cfg.tables.lockouts, t.guid, week))
		X.locks[t.guid] = nil
		if t.player then
			local set = X.lockSet(t.guid)
			for i, b in ipairs(cfg.bosses) do
				t.player:setStorageValue(cfg.storage + i, ChaosRaidCore.lockStorage(cfg, set, b.key, os.time()))
			end
		end
		return true, t.name .. ": raid lockouts of this week cleared."
	end}

-- ------------------------------------------------------------------ world bosses (server/README.md "World bosses")
reg{id = "worldboss_status", name = "World boss: status", description = "The world boss event's phase, boss and next start (as /worldboss).",
	handler = function(actor)
		local W, why = sys("ChaosWorldBoss", "status")
		if not W then return false, why end
		return true, "World boss", {W.status()}
	end}

reg{id = "worldboss_start", name = "World boss: start", description = "Starts the world boss event now: a boss by name or number, empty = the schedule's choice, random = any.",
	minGroup = 5, confirm = true, params = {{name = "boss", label = "Boss (name, number, random or empty)", type = "string", max = 48, required = false}},
	handler = function(actor, p)
		local W, why = sys("ChaosWorldBoss", "start")
		if not W then return false, why end
		local arg = p.boss or ""
		local index = W.findBoss(arg)
		if index == false then return false, "Unknown boss." end
		if index == nil and arg:lower() == "random" then
			local c = Chaos.worldBoss
			index = W.pickBoss(#c.bosses, "random", Game.getStorageValue(c.rotationStorage))
		end
		local ok, err = W.start(index)
		return ok and true or false, ok and "World boss event started." or ("Not started: " .. tostring(err))
	end}

reg{id = "worldboss_stop", name = "World boss: stop", description = "Stops the running world boss event.",
	minGroup = 5, confirm = true,
	handler = function(actor)
		local W, why = sys("ChaosWorldBoss", "stop")
		if not W then return false, why end
		return W.stop() and true or false, "World boss event stopped (or none was running)."
	end}

-- ------------------------------------------------------------------ invasions (server/README.md "Invasions and world events")
reg{id = "invasion_status", name = "Invasion: status", description = "The running invasion or occupation and the upcoming ones (as /invasion status).",
	handler = function(actor)
		local V, why = sys("ChaosInvasion", "statusText")
		if not V then return false, why end
		local lines = {}
		for line in tostring(V.statusText()):gmatch("[^\n]+") do lines[#lines + 1] = line end
		return true, "Invasions", lines
	end}

reg{id = "invasion_start", name = "Invasion: start", description = "Starts an invasion now (area key or random; faction key or random).",
	minGroup = 5, confirm = true,
	params = {{name = "area", label = "Area key or random", type = "string", max = 32, default = "random"},
		{name = "faction", label = "Faction key or random", type = "string", max = 32, required = false}},
	handler = function(actor, p)
		local V, why = sys("ChaosInvasion", "start")
		if not V then return false, why end
		local ok, err = V.start(p.area, p.faction ~= "" and p.faction or nil)
		return ok and true or false, ok and ("Invasion started: " .. tostring(V.state.areaName) .. ", " .. tostring(V.state.factionName) .. ".")
			or ("Not started: " .. tostring(err))
	end}

reg{id = "invasion_stop", name = "Invasion: stop", description = "Stops the running invasion.",
	minGroup = 5, confirm = true,
	handler = function(actor)
		local V, why = sys("ChaosInvasion", "stop")
		if not V then return false, why end
		return V.stop() and true or false, "Invasion stopped (or none was running)."
	end}

-- ------------------------------------------------------------------ treasure goblins (as /goblin)
reg{id = "goblin_spawn", name = "Treasure goblin: spawn", description = "Spawns a treasure goblin two tiles in front of you (variant key and level optional).",
	minGroup = 5,
	params = {{name = "variant", label = "Variant key (optional)", type = "string", max = 32, required = false},
		{name = "level", label = "Level (0 = from the area)", type = "int", min = 0, max = 2000, default = 0}},
	handler = function(actor, p)
		local TG, why = sys("ChaosTreasureGoblin", "spawn")
		if not TG then return false, why end
		local pos = actor:getPosition()
		pos:getNextPosition(actor:getDirection(), 2)
		local G, c = ChaosTreasureGoblinCore, ChaosTreasureGoblinConfig
		local variant = p.variant and p.variant ~= "" and G and c and G.variant(c, p.variant)
		if p.variant and p.variant ~= "" and not variant then return false, "Unknown variant " .. p.variant .. "." end
		local monster = TG.spawn(pos, {variant = variant and variant.key or nil, level = p.level > 0 and p.level or nil})
		return monster ~= nil, monster and (monster:getName() .. " spawned.") or "Could not place the goblin."
	end}
