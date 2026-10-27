-- class_migration.lua: the one-time move of the old vocations onto the four base classes (docs/CLASSES.md, phase 2).
--
--   Knight / Elite Knight              -> Warrior / Juggernaut (same ids 4 / 8), free switch to Berserker
--   Paladin / Royal Paladin            -> Ranger / Deadeye (same ids 3 / 7), free switch to Beastmaster
--   Sorcerer / Master Sorcerer         -> Mystic / Elementalist (same ids 1 / 5)
--   Druid (2) / Elder Druid (6)        -> Mystic (1) / Illusionist (10)
--   Illusionist (9) / Arch Illusionist -> Mystic (1) / Illusionist (10)
--   every one of them: the passive tree is emptied once, for free
--
-- At startup (before anyone can log in), when server_config `chaos_class_migration` is below
-- Chaos.classes.migration.version, it runs ChaosClasses.migrationSql (classes.lua) and stores the version: so it runs
-- once, whatever the number of restarts. The vocations 2, 6 and 9 are gone from vocations.xml
-- (server/tools/add_vocations.py), so it must have run before such a character logs in; it does, being a startup event.
--
-- At the character's next login (storage Chaos.classes.storage.migratedFrom = the old vocation): health, mana and
-- capacity follow the new class's gains when they changed (retired ids: Chaos.classes.migration.oldGains), and the
-- player is told what happened and, for an old Elite Knight / Royal Paladin, how to make the free switch
-- (!ascend berserker / beastmaster, ascension.lua). Then the storage is set to 0.
--
-- GMs: /lua ChaosClassMigration.run(true) runs the SQL again (it is safe to repeat; it only touches old ids).

if not ChaosClasses then
	dofile("data/scripts/chaos/classes.lua")
end
local C = ChaosClasses
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end

ChaosClassMigration = ChaosClassMigration or {}
local M = ChaosClassMigration

local function cfg()
	return Chaos.classes
end

local function count(sql)
	local rows = Chaos.select(sql, {{"n", "n"}})
	return rows[1] and rows[1].n or 0
end

local function doneVersion()
	local rows = Chaos.select("SELECT `value` FROM `server_config` WHERE `config` = " ..
		db.escapeString(cfg().migration.configKey), {{"value", "s"}})
	return rows[1] and tonumber(rows[1].value) or 0
end

-- run the migration SQL (once per version, or again with force); returns the number of characters it moved
function M.run(force)
	local m = cfg().migration
	if not force and doneVersion() >= m.version then
		return 0
	end
	local n = count("SELECT COUNT(*) AS `n` FROM `players` WHERE `vocation` BETWEEN 1 AND 10")
	local retired = count("SELECT COUNT(*) AS `n` FROM `players` WHERE `vocation` IN (2, 6, 9)")
	for _, q in ipairs(C.migrationSql(Chaos.tables.passiveTree)) do
		if not db.query(q) then
			print("[ChaosClassMigration] failed: " .. q)
		end
	end
	db.query("INSERT INTO `server_config` (`config`, `value`) VALUES (" .. db.escapeString(m.configKey) .. ", " ..
		db.escapeString(tostring(m.version)) .. ") ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)")
	print(string.format("[ChaosClassMigration] version %d: %d characters of the old vocations (%d of the retired ids 2, 6, 9 moved), passive trees reset",
		m.version, n, retired))
	return n
end

local startup = GlobalEvent("ChaosClassMigration")
function startup.onStartup()
	local ok, err = pcall(M.run, false)
	if not ok then
		print("[ChaosClassMigration] " .. tostring(err))
	end
	return true
end
startup:register()

-- the word of the free switch target (Chaos.classes.ascension.choices) or nil
local function wordOf(vocId)
	for _, list in pairs(cfg().ascension.choices) do
		for word, id in pairs(list) do
			if id == vocId then
				return word
			end
		end
	end
	return nil
end

-- the login part: stats when the gains changed, the message
function M.onLogin(player)
	local st = cfg().storage
	local from = player:getStorageValue(st.migratedFrom)
	if from <= 0 then
		return
	end
	local plan = C.migrationFor(from)
	player:setStorageValue(st.migratedFrom, 0)
	if not plan then
		return
	end
	local voc = player:getVocation()
	local old = cfg().migration.oldGains[from]
	if not old and from ~= voc:getId() then
		local ov = Vocation(from)
		old = ov and {hp = ov:getHealthGain(), mana = ov:getManaGain(), cap = ov:getCapacityGain()}
	end
	local new = {hp = voc:getHealthGain(), mana = voc:getManaGain(), cap = voc:getCapacityGain()}
	if old and ChaosShopServices and ChaosShopServices.recomputeStats
			and (old.hp ~= new.hp or old.mana ~= new.mana or old.cap ~= new.cap) then
		local stats = ChaosShopServices.recomputeStats(player:getLevel(), Chaos.shopServices.vocationBaseLevel,
			player:getCapacity(), old, new)
		player:setMaxHealth(stats.health)
		player:setMaxMana(stats.mana)
		player:setCapacity(stats.cap)
		if player:getHealth() > player:getMaxHealth() then
			player:setHealth(player:getMaxHealth())
		end
	end
	local free = player:getStorageValue(st.freeSwitch)
	local text = C.migrationMessage(cfg().migration.oldNames[from] or "vocation", voc:getName(),
		free > 0 and wordOf(free) or nil, plan.resetTree, Chaos.lang(player))
	if not C.isAscended(voc:getId()) then
		local choices = cfg().ascension.choices[voc:getId()]
		if choices then
			local names = {}
			for k in pairs(choices) do
				names[#names + 1] = k
			end
			table.sort(names)
			text = text .. Chaos.t(player, " From level %d choose your ascended class at the Ascendant Oracle: %s.",
				cfg().ascension.minLevel, table.concat(names, Chaos.t(player, " or ")))
		end
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	player:popupFYI((text:gsub("%. ", ".\n")))
	if ChaosPassiveTree and ChaosPassiveTree.apply then
		ChaosPassiveTree.apply(player)
	end
end

local login = CreatureEvent("ChaosClassMigrationLogin")
function login.onLogin(player)
	local ok, err = pcall(M.onLogin, player)
	if not ok then
		print("[ChaosClassMigration] " .. tostring(err))
	end
	return true
end
login:register()
