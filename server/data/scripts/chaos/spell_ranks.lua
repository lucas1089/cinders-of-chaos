-- Spell ranks, the engine side (O686 phase 2; docs/SPELL_UPGRADES.md; server/README.md "Spell ranks (O686 phase 2)").
-- Rules: spell_ranks_core.lua, numbers: spell_ranks_config.lua, the read API every state shares: data/lib/chaos_spell_ranks.lua,
-- tests: server/tests/spell_ranks_test.lua (core) and spell_ranks_glue_test.lua (this file on a mocked engine).
--
-- * Damage tracking. combatlog.lua already attributes every hit of a character to the spell running (the supports' cast context,
--   a snare's named burst, the engine's precast) and calls CL.spellHook(owner, summon, monster, amount, spell id) for a monster
--   target and CL.healSpellHook(healer, ally, effective heal, spell id, ms) for a heal that reached a player. Here they fill one small
--   table per monster, character id -> {total damage, damage by spell id} (at most 16 ids), dropped after the kill. The combat log
--   must be enabled (combatlog_config.lua `enabled`, true) for ranks to be earned.
-- * The read point. EventCallback onGainExperience at index -9: after the pace curve and the multikill chain (-10), before every
--   bonus. NOT before the stage: base player.lua multiplies the stage, stamina and the store potion first and runs the callbacks
--   after (patch_base_events.py), so `exp` already holds them. The kill's base experience is rebuilt the way xpcap.lua does it
--   (ChaosXpCap.baseOf: rawExp x the monster level factor x the stage x the tier x the pace curve), never `exp`. This is A1 of
--   the design, corrected. The callback never changes the experience.
-- * SP are kept in memory as fractions, written to the storage block at most every flushSeconds and at logout. The rank is stored
--   packed (core P.pack) so any Lua state reads it. The account echo is the table chaos_spell_ranks.
-- * `enabled = false` (the shipped state): everything above runs, nothing a player feels changes (data/lib/chaos_spell_ranks.lua
--   answers 1 to every factor). With `enabled = true`: the rank factor on spell hits and heals (passivetree_effects.lua), the cost and
--   cooldown handlers below, and the monster health factor of phase 3.
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.spellRanks = 168, read only:
--   client -> server  open
--   server -> client  state {on, v, s = [[spell id, rank, SP into the rank, SP the next rank costs], ...]}  (spells with SP only)
--                     rank {s = [[spell id, rank, into, cost]]}  at a rank-up, with the switch on (phase 6: the client polls `open` rarely)
--                     forms {v, f}, pick {...} (spell_forms.lua), combo {id, n, x, y, z} (spell_combos.lua, phase 6)
-- Assumed engine API (TFS 1.4.2): CreatureEvent login/logout/extendedopcode, EventCallback onGainExperience, GlobalEvent
-- startup/think, TalkAction, Player:get/setStorageValue/getAccountId/getLevel/sendTextMessage, Creature:getMaxHealth/getMaster,
-- db.query/asyncQuery/storeQuery. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosSpellRanksCore or not ChaosSpellRanksCore.power then
	dofile("data/scripts/chaos/spell_ranks_core.lua")
end
ChaosSpellRanksConfig = dofile("data/scripts/chaos/spell_ranks_config.lua")
dofile("data/lib/chaos_spell_ranks.lua")
if not ChaosSupports then
	dofile("data/lib/chaos_supports.lua")
end
if not ChaosSpellEvents or not ChaosSpellEvents.set then
	pcall(dofile, "data/lib/chaos_spell_events.lua")
end

local R = ChaosSpellRanks
local P = ChaosSpellRanksCore
local cfg = ChaosSpellRanksConfig
local OPCODE = (ChaosOpcodes and ChaosOpcodes.spellRanks) or cfg.opcode
local TABLE = (Chaos.tables and Chaos.tables.spellRanks) or cfg.table
local floor, max = math.floor, math.max

R.players = R.players or {} -- player id -> state (see R.load)
R.tracked = R.tracked or {} -- monster id -> {max, last, dead, by = {player id -> record}, ignore}
R.heals = R.heals or {} -- player id -> heal list
R.catalog = R.catalog or {} -- spell id -> {id, name, heal, cooldownMs, weight, scale, level (O752)}
R.flushSeconds = 30

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function log(text)
	print("[Chaos spell ranks] " .. text)
end

local function try(label, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		log(label .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

-- ---------------------------------------------------------------- the spells
-- the ranked spells from a spells.xml text: attack and healing instants with a unique id (design 1.1)
function R.loadCatalog(text)
	local entries = ChaosSupports.parseSpellsXml(text)
	local count, out, excluded = {}, {}, {}
	for _, e in ipairs(entries) do
		if e.id then
			count[e.id] = (count[e.id] or 0) + 1
		end
	end
	for _, id in ipairs(cfg.eligible.excluded or {}) do
		excluded[id] = true
	end
	R.healIds = {}
	for _, e in ipairs(entries) do
		if e.tag == "instant" and e.id and e.id > 0 and e.id <= cfg.storage.maxSpellId and count[e.id] == 1
				and not excluded[e.id] and cfg.eligible.groups[e.group or ""] then
			local heal = cfg.eligible.heal[e.group or ""] == true
			local weight, scale = P.weight({heal = heal, cooldownMs = e.cooldown}, cfg)
			out[e.id] = {id = e.id, name = e.name, heal = heal, cooldownMs = e.cooldown, weight = weight, scale = scale, level = e.level}
			if heal then
				R.healIds[e.id] = true
			end
		end
	end
	R.catalog = out
	return out
end

local function ensureCatalog()
	if next(R.catalog) == nil then
		local f = io.open("data/spells/spells.xml", "r")
		if f then
			local text = f:read("*a")
			f:close()
			R.loadCatalog(text)
		end
	end
	return R.catalog
end

function R.eligible(spellId)
	return R.catalog[spellId] ~= nil
end

-- ---------------------------------------------------------------- the table of the account echo
local tableReady
local function ensureTable()
	if tableReady == nil then
		tableReady = db.query(string.format(
			"CREATE TABLE IF NOT EXISTS `%s` (`account_id` int(10) unsigned NOT NULL, `spell_id` smallint(5) unsigned NOT NULL, " ..
			"`best_rank` tinyint(3) unsigned NOT NULL DEFAULT 0, `updated_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
			"PRIMARY KEY (`account_id`, `spell_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8", TABLE)) and true or false
	end
	return tableReady
end

local function echoRows(accountId)
	local out = {}
	if not ensureTable() then
		return out
	end
	local rows = Chaos.select(string.format("SELECT `spell_id`, `best_rank` FROM `%s` WHERE `account_id` = %d", TABLE, accountId),
		{{"spell_id", "n"}, {"best_rank", "n"}})
	for _, r in ipairs(rows) do
		out[r.spell_id] = r.best_rank
	end
	return out
end

local function echoWrite(accountId, spellId, rank)
	if ensureTable() then
		db.asyncQuery(string.format(
			"INSERT INTO `%s` (`account_id`, `spell_id`, `best_rank`, `updated_at`) VALUES (%d, %d, %d, %d) " ..
			"ON DUPLICATE KEY UPDATE `best_rank` = GREATEST(`best_rank`, VALUES(`best_rank`)), `updated_at` = VALUES(`updated_at`)",
			TABLE, accountId, spellId, rank, os.time()))
	end
end

-- ---------------------------------------------------------------- state of a character
local function rankKey(id)
	return cfg.storage.rankBase + id
end

local function spKey(id)
	return cfg.storage.spBase + id
end

local function bestOfWeights(st)
	local best = {}
	for id, rank in pairs(st.rank) do
		local m = R.catalog[id]
		if m and rank > (best[m.weight] or 0) then
			best[m.weight] = rank
		end
	end
	st.best = best
end

-- the packed storage of a spell with a new rank (the Form picks and the awakened bit stay)
local function writeRank(player, id, rank)
	local _, f1, f2, aw = P.unpack(player:getStorageValue(rankKey(id)))
	player:setStorageValue(rankKey(id), P.pack(rank, f1, f2, aw))
end

-- load a character: SP and rank of every ranked spell, the echo floors applied; writes what the floors changed
function R.load(player)
	ensureCatalog()
	local id = player:getId()
	local unit = cfg.spUnit
	local st = {sp = {}, rank = {}, dirty = {}, floors = {}, best = {}, tester = Chaos.isTester(player),
		accountId = player:getAccountId(), pushAt = 0}
	local version = player:getStorageValue(cfg.storage.version)
	if version == nil or version < 0 then
		version = 0
	end
	local echo = (not st.tester) and echoRows(st.accountId) or {}
	for sid, m in pairs(R.catalog) do
		if P.reassignedClears(sid, version, cfg) then
			player:setStorageValue(spKey(sid), 0)
			player:setStorageValue(rankKey(sid), 0)
		end
		local units = player:getStorageValue(spKey(sid))
		local sp = (units and units > 0) and units / unit or 0
		local floorRank = P.echoFloor(echo[sid] or 0, cfg)
		st.floors[sid] = floorRank
		if floorRank > 0 then
			local withFloor = P.withFloor(sp, floorRank, m.scale, cfg)
			if withFloor ~= sp then
				sp = withFloor
				st.dirty[sid] = true
			end
		end
		st.sp[sid] = sp
		local rank = P.rankOf(sp, m.scale, cfg)
		st.rank[sid] = rank
		local stored = P.unpack(player:getStorageValue(rankKey(sid)))
		if stored ~= rank then
			writeRank(player, sid, rank)
		end
	end
	if version ~= cfg.version then
		player:setStorageValue(cfg.storage.version, cfg.version)
	end
	bestOfWeights(st)
	R.players[id] = st
	return st
end

-- write the SP that changed
function R.flush(player, st)
	st = st or R.players[player:getId()]
	if not st then
		return
	end
	for sid in pairs(st.dirty) do
		player:setStorageValue(spKey(sid), floor(st.sp[sid] * cfg.spUnit + 0.5))
		st.dirty[sid] = nil
	end
end

local function say(player, text)
	if player.sendTextMessage then
		player:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_INFO_DESCR, text)
	end
end

local function rankUp(player, st, sid, newRank)
	st.rank[sid] = newRank
	writeRank(player, sid, newRank)
	bestOfWeights(st)
	local name = R.catalog[sid].name
	if Chaos.t then
		say(player, Chaos.t(player, "%s reached rank %d.", name, newRank))
	else
		say(player, string.format("%s reached rank %d.", name, newRank))
	end
	if not st.tester then
		echoWrite(st.accountId, sid, newRank)
	end
	-- phase 6: the client hears of a rank-up at once (the Upgrades tab and the rank bars), so it polls `open` rarely (README "Spell combos")
	if cfg.enabled == true and Chaos.send then
		local m = R.catalog[sid]
		local rank, into, nextCost = P.rankOf(st.sp[sid] or 0, m.scale, cfg)
		Chaos.send(player, OPCODE, "rank", {s = {{sid, rank, floor(into * 1000) / 1000, floor(nextCost * 1000) / 1000}}})
	end
end

-- SP of one kill to a character: shares = spell id -> fraction of K. Returns the number of spells that gained.
function R.award(player, st, shares, K)
	local n = 0
	for sid, share in pairs(shares) do
		local m = R.catalog[sid]
		if m then
			local rank = st.rank[sid] or 0
			local mult = P.catchUp(rank, st.best[m.weight] or 0, cfg)
			local sp = st.sp[sid] or 0
			local g = P.gain(K, share, mult, m.scale, sp, cfg)
			if g > 0 then
				st.sp[sid] = sp + g
				st.dirty[sid] = true
				n = n + 1
				local newRank = P.rankOf(st.sp[sid], m.scale, cfg)
				if newRank > rank then
					rankUp(player, st, sid, newRank)
				end
			end
		end
	end
	return n
end

-- ---------------------------------------------------------------- damage tracking
function R.onDamage(owner, summon, creature, amount, spellId)
	local st = R.players[owner:getId()]
	if not st or (st.tester and cfg.testersEarn ~= true) then -- O686 phase 8: testersEarn was dead (the live pass with bots)
		return
	end
	local mid = creature:getId()
	local info = R.tracked[mid]
	local t = nowMs()
	if not info then
		-- a trainer, a summon or a clone of a monster never pays rank (design 1.1)
		local ignore = (creature.getMaster and creature:getMaster() ~= nil)
			or (ChaosCombatLog and ChaosCombatLog.isTrainer and ChaosCombatLog.isTrainer(creature)) or false
		info = {max = 0, last = t, by = {}, ignore = ignore}
		R.tracked[mid] = info
	end
	if info.ignore then
		return
	end
	info.last = t
	info.max = creature:getMaxHealth()
	local pid = owner:getId()
	local rec = info.by[pid]
	if not rec then
		rec = P.newRecord()
		info.by[pid] = rec
	end
	P.record(rec, P.creditSpell({spellId = spellId, summon = summon and summon:getName() or nil}, cfg), amount, cfg)
end

function R.onHeal(healer, ally, effective, spellId, t)
	local st = R.players[healer:getId()]
	if not st or (st.tester and cfg.testersEarn ~= true) or not spellId or not R.catalog[spellId] or not R.catalog[spellId].heal then
		return
	end
	local pid = healer:getId()
	R.heals[pid] = P.recordHeal(R.heals[pid] or {}, spellId, effective, ally:getMaxHealth(), t or nowMs(), cfg)
end

function R.attachHooks()
	local CL = rawget(_G, "ChaosCombatLog")
	if CL then
		CL.spellHook = R.onDamage
		CL.healSpellHook = R.onHeal
		return true
	end
	return false
end
R.attachHooks()

function R.drop(monsterId)
	R.tracked[monsterId] = nil
end

-- ---------------------------------------------------------------- the kill
-- the base experience of a kill for this character (A1): no stage, stamina, potion, bonus or multikill in it
function R.baseExp(player, source, exp, rawExp)
	local X = rawget(_G, "ChaosXpCap")
	if X and X.baseOf then
		local ok, b = pcall(X.baseOf, player, source, rawExp, nil)
		if ok and b and b > 0 then
			return b
		end
	end
	return tonumber(exp) or 0
end

function R.onKill(player, source, exp, rawExp)
	if not source or not source.isMonster or not source:isMonster() or (tonumber(exp) or 0) <= 0 then
		return
	end
	local pid = player:getId()
	local st = R.players[pid]
	local sid = source:getId()
	local info = R.tracked[sid]
	if not st or not info then
		return
	end
	if not info.dead then
		info.dead = nowMs()
		addEvent(R.drop, cfg.credit.afterDeathMs, sid)
	end
	if info.ignore or cfg.track == false then
		return
	end
	local ok = P.counts({tester = st.tester, level = player:getLevel(), exp = exp,
		monsterMaster = source.getMaster and source:getMaster() or nil}, cfg)
	if not ok then
		return
	end
	local E = R.baseExp(player, source, exp, rawExp)
	local K = P.killValue(E, player:getLevel(), cfg)
	if K <= 0 then
		return
	end
	local shares = P.shares(info.by[pid], info.max, R.heals[pid], nowMs(), R.eligible, cfg)
	R.award(player, st, shares, K)
end

local xpCb = EventCallback
xpCb.onGainExperience = function(player, source, exp, rawExp)
	try("kill", R.onKill, player, source, exp, rawExp)
	return exp
end
xpCb:register(-9)

-- ---------------------------------------------------------------- cost and cooldown (only with the ranks switched on)
if ChaosSpellEvents and ChaosSpellEvents.set then
	ChaosSpellEvents.set("cost", "spellranks", function(player, name, id, group, aggressive, mana, health)
		if cfg.enabled == true and R.catalog[id] then
			mana = R.manaFor(player, id, mana)
		end
		return mana, health
	end)
	ChaosSpellEvents.set("cooldown", "spellranks", function(player, name, id, group, aggressive, cooldownType, ms)
		if cfg.enabled == true and cooldownType == "spell" and R.catalog[id] then
			return R.cooldownFor(player, id, ms)
		end
		return ms
	end)
end

-- ---------------------------------------------------------------- the wire
function R.state(player)
	local st = R.players[player:getId()]
	local list = {}
	if st then
		for sid, m in pairs(R.catalog) do
			local sp = st.sp[sid] or 0
			if sp > 0 and #list < cfg.push.maxSpells then
				local rank, into, nextCost = P.rankOf(sp, m.scale, cfg)
				list[#list + 1] = {sid, rank, floor(into * 1000) / 1000, floor(nextCost * 1000) / 1000}
			end
		end
		table.sort(list, function(a, b) return a[1] < b[1] end)
	end
	local out = {on = cfg.enabled == true, v = cfg.version, s = list}
	-- O752: the spell path milestones (spell_milestones.lua): the gate rules and the next milestone of the character's class
	local SM = rawget(_G, "ChaosSpellMilestones")
	if SM and SM.wire then
		local ok, ms = pcall(SM.wire, player)
		if ok and ms then
			out.ms = ms
		end
	end
	return out
end

function R.receive(player, msg)
	-- phase 4: the Forms answer `pick` (spell_forms.lua)
	local FM = rawget(_G, "ChaosSpellForms")
	if type(msg) == "table" and msg.action == "pick" and FM and FM.receive then
		return FM.receive(player, msg)
	end
	-- phase 7: awakening answers `awaken` (spell_awakening.lua)
	local AW = rawget(_G, "ChaosSpellAwakening")
	if type(msg) == "table" and msg.action == "awaken" and AW and AW.receive then
		return AW.receive(player, msg)
	end
	if type(msg) ~= "table" or msg.action ~= "open" then
		return false
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "spellranks", cfg.push.minIntervalMs) then
		return false
	end
	R.flush(player)
	Chaos.send(player, OPCODE, "state", R.state(player))
	if FM and FM.picksOf then
		Chaos.send(player, OPCODE, "forms", {v = cfg.version, f = FM.picksOf(player)})
	end
	if AW and AW.push then
		AW.push(player)
	end
	return true
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosSpellRanksLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSpellRanksLogout")
	player:registerEvent("ChaosSpellRanksExtended")
	try("login", R.load, player)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosSpellRanksLogout")
function logout.onLogout(player)
	try("logout", function()
		R.flush(player)
		local id = player:getId()
		R.players[id], R.heals[id] = nil, nil
	end)
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosSpellRanksExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	try("opcode", R.receive, player, Chaos.decode(buffer))
end
ext:type("extendedopcode")
ext:register()

local startup = GlobalEvent("ChaosSpellRanksStartup")
function startup.onStartup()
	ensureCatalog()
	ensureTable()
	R.attachHooks()
	return true
end
startup:type("startup")
startup:register()

-- every flushSeconds: write the SP that changed, drop the tables of monsters nothing has hit for a while
function R.tick(t)
	t = t or nowMs()
	for id, info in pairs(R.tracked) do
		if t - info.last > cfg.credit.staleMs then
			R.tracked[id] = nil
		end
	end
	for pid, st in pairs(R.players) do
		local player = Player(pid)
		if player then
			R.flush(player, st)
		else
			R.players[pid] = nil
		end
	end
end

local think = GlobalEvent("ChaosSpellRanksThink")
function think.onThink(interval)
	try("tick", R.tick)
	return true
end
think:interval(R.flushSeconds * 1000)
think:register()

-- staff: /spellrank <spell id> <rank>   sets the rank of a spell on yourself (the SP of that rank); /spellrank clear
local talk = TalkAction("/spellrank")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	if Chaos.staffCommand and not Chaos.staffCommand(player, words, param, true) then
		return false
	end
	local st = R.players[player:getId()]
	local a, b = tostring(param or ""):match("^%s*(%S+)%s*(%S*)")
	if not st then
		return false
	end
	if a == "clear" then
		for sid, m in pairs(R.catalog) do
			st.sp[sid], st.rank[sid], st.dirty[sid] = 0, 0, true
			writeRank(player, sid, 0)
		end
		bestOfWeights(st)
		R.flush(player, st)
		say(player, "Spell ranks cleared.")
		return false
	end
	local sid, rank = tonumber(a), tonumber(b)
	local m = sid and R.catalog[sid]
	if not m or not rank or rank < 0 or rank > cfg.maxRank then
		say(player, "Usage: /spellrank <spell id> <rank 0-" .. cfg.maxRank .. "> | clear")
		return false
	end
	rank = floor(rank)
	st.sp[sid], st.rank[sid], st.dirty[sid] = P.spForRank(rank, m.scale, cfg), rank, true
	writeRank(player, sid, rank)
	bestOfWeights(st)
	R.flush(player, st)
	say(player, string.format("%s is rank %d.", m.name, rank))
	return false
end
talk:separator(" ")
talk:register()
