-- Factions with reputation (client game_factions, extended opcode ChaosOpcodes.factions = 215).
-- Four factions (factions_config.lua), each with a home NPC that is its quartermaster. Reputation per character from
-- daily / weekly contracts, kills of the faction's monster families, bounty contracts, rift seals of its theme,
-- invasions of its enemies, its world boss and faction tokens turned in; daily diminishing returns, a weekly cap and a
-- rival that loses a little of every gain (factions_core.lua K.gain). Ranks unlock quartermaster offers (fixed gear,
-- orb bundles for gold, a recipe, the tabard aura, a mount), rank titles (titles.lua) and the Exalted achievements.
-- Pure logic: factions_core.lua (tests: server/tests/factions_test.lua); overview: server/README.md "Factions".
-- Tables: chaos_factions, chaos_faction_contracts, chaos_faction_purchases (server/sql/chaos_factions.sql; also
-- created at startup). No player storages.
--
-- Hooks (no edits of the other systems; each guarded, installed at startup and again at login after a /reload):
--   death event on every monster without a master   kills by bestiary category (ChaosBestiary.cat()), tier from
--                                                    ChaosTierDead (monster_tiers.lua), party credit as the bestiary;
--                                                    token drops into the corpse
--   ChaosLeaderboard.record      wrapped: "bounty" -> the finished contract's monster (ChaosBounty.players); "rift" ->
--                                the run's theme (ChaosRift.runOf) and tier. Both deduplicated (a second wrap counts once).
--   ChaosWorldBoss.computeRewards wrapped: every rewarded share (online) -> world boss contracts, its faction
--   ChaosInvasion.deliver        wrapped: every delivered invasion reward -> invasion contracts, the invader's foes
--   ChaosTitles.register("faction")  rank titles; the Exalted title brings the faction's plate frame
--   ChaosAchievements.set        faction_exalted_<key>, faction_exalted (achievements_data.lua)
--   ChaosLeaderboard.record("factions", player, gained, "add")  every minute and at logout (weekly Reputation board)
--
-- Protocol (JSON {action, data}; server -> client with Chaos.sendChunked):
--   client -> server  open {f?} | close | turnin {f, n?} | deliver {key} | buy {key} | craft {key, n?}
--   server -> client  state {now, nextDay, nextWeek, weekCap, ranks, factions, contracts, offers, sel?}  (K.payload)
--                     msg {text, ok}
--   The NPCs (data/npc/scripts/chaos_faction_npc.lua, their own Lua state) send  npc {f}: the client opens the window
--   on that faction and asks with open.
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/factions_core.lua")
if not ChaosNpcPlace then
	dofile("data/scripts/chaos/npc_place.lua")
end

Chaos.factionsConfig = dofile("data/scripts/chaos/factions_config.lua")
local cfg = Chaos.factionsConfig
local K = ChaosFactionsCore
local OPCODE = ChaosOpcodes.factions or cfg.opcode
local T = cfg.tables

ChaosFactions = ChaosFactions or {}
local F = ChaosFactions
F.idx = K.index(cfg)
local idx = F.idx
F.players = F.players or {} -- guid -> state (kept over /reload scripts; written back at logout and every minute)
F.seen = F.seen or setmetatable({}, {__mode = "k"}) -- invasion reward tables already counted

local function log(text)
	print("[Chaos factions] " .. text)
end

local function try(name, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(res))
		return nil
	end
	return res
end

local function now()
	return os.time() + (F.offset or 0)
end

local function day()
	return K.day(now(), cfg)
end

local function week()
	return K.week(now(), cfg)
end

-- the type behind a shown name (chaos_constants.lua "Monster names")
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end

local function itemName(id, n)
	local it = ItemType(id)
	if not it or it:getId() == 0 then
		return "item " .. tostring(id)
	end
	if n and n ~= 1 and it.getPluralName then
		local p = it:getPluralName()
		if p and p ~= "" then
			return p
		end
	end
	return it:getName()
end

-- ---------------------------------------------------------------- tables
local tablesReady = false
function F.ensureTables()
	if tablesReady then
		return true
	end
	local ok = db.query("CREATE TABLE IF NOT EXISTS `" .. T.rep .. "` (`player_id` int(11) NOT NULL, " ..
		"`faction` varchar(16) NOT NULL, `rep` int(11) NOT NULL DEFAULT 0, `day` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`day_gain` int(11) NOT NULL DEFAULT 0, `week` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`week_gain` int(11) NOT NULL DEFAULT 0, `week_bank` int(11) NOT NULL DEFAULT 0, " ..
		"`exalted_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`total` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`, `faction`), " ..
		"FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8")
	-- the weekly cap carries over (factions_config.lua rolloverWeeks, 2026-10-15): tables made before keep their rows
	ok = db.query("ALTER TABLE `" .. T.rep .. "` ADD COLUMN IF NOT EXISTS `week_bank` int(11) NOT NULL DEFAULT 0") and ok
	ok = db.query("CREATE TABLE IF NOT EXISTS `" .. T.contracts .. "` (`player_id` int(11) NOT NULL, " ..
		"`period` varchar(12) NOT NULL, `faction` varchar(16) NOT NULL, `slot` tinyint(3) unsigned NOT NULL, " ..
		"`level` int(11) NOT NULL DEFAULT 1, `progress` int(11) NOT NULL DEFAULT 0, `done` tinyint(1) NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`player_id`, `period`, `faction`, `slot`), FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) " ..
		"ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8") and ok
	ok = db.query("CREATE TABLE IF NOT EXISTS `" .. T.purchases .. "` (`player_id` int(11) NOT NULL, " ..
		"`offer` varchar(32) NOT NULL, `week` int(10) unsigned NOT NULL DEFAULT 0, `count` int(11) NOT NULL DEFAULT 0, " ..
		"`at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`, `offer`, `week`), FOREIGN KEY (`player_id`) " ..
		"REFERENCES `players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8") and ok
	tablesReady = ok and true or false
	return tablesReady
end

-- ---------------------------------------------------------------- the bestiary catalogue (categories, levels)
local function entryOf(name)
	local B = ChaosBestiary
	if not B or not B.cat then
		return nil
	end
	local ok, cat = pcall(B.cat)
	return ok and cat and cat.byKey and cat.byKey[tostring(name):lower()] or nil
end

local familyCache
local function families(cat, minLevel, level)
	if not familyCache then
		local B = ChaosBestiary
		local ok, catalogue = pcall(function() return B and B.cat and B.cat() end)
		if not ok or not catalogue or not catalogue.byKey then
			return 1 -- no bestiary: every family is offered
		end
		familyCache = {}
		for _, e in pairs(catalogue.byKey) do
			if (e.spawns or 0) > 0 and not e.boss then
				familyCache[e.cat] = familyCache[e.cat] or {}
				table.insert(familyCache[e.cat], e.level or 0)
			end
		end
	end
	local n = 0
	for _, lv in ipairs(familyCache[cat] or {}) do
		if lv >= minLevel and lv <= level * 1.5 + 30 then
			n = n + 1
		end
	end
	return n >= 2 and n or 0
end

local function catName(cat)
	local B = ChaosBestiary
	return B and B.catNames and B.catNames[cat] or cat
end

-- ---------------------------------------------------------------- player state
-- P = {guid, st = {[faction] = entry}, dirty = {[faction] = true}, crow = {[period:faction:slot] = {level, progress,
--      done}}, contracts = list, cday, cweek, owned = {[offer] = true}, weekly = {[offer] = n}, wweek, killPts =
--      {[faction] = n}, lb = reputation not yet on the board, open = window open}
local function stateOf(player)
	local guid = player:getGuid()
	local P = F.players[guid]
	if P then
		return P
	end
	P = {guid = guid, st = {}, dirty = {}, crow = {}, owned = {}, weekly = {}, killPts = {}, lb = 0}
	F.players[guid] = P
	if not F.ensureTables() then
		return P
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `faction`, `rep`, `day`, `day_gain`, `week`, `week_gain`, " ..
			"`week_bank`, `exalted_at`, `total` FROM `%s` WHERE `player_id` = %d", T.rep, guid),
			{{"faction", "s"}, {"rep", "n"}, {"day", "n"}, {"day_gain", "n"}, {"week", "n"}, {"week_gain", "n"},
			{"week_bank", "n"}, {"exalted_at", "n"}, {"total", "n"}})) do
		if idx.byKey[r.faction] then
			P.st[r.faction] = {rep = r.rep, day = r.day, dayGain = r.day_gain, week = r.week, weekGain = r.week_gain,
				bank = r.week_bank or 0, exalted = r.exalted_at, total = r.total, carry = 0}
		end
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `period`, `faction`, `slot`, `level`, `progress`, `done` FROM `%s` " ..
			"WHERE `player_id` = %d", T.contracts, guid), {{"period", "s"}, {"faction", "s"}, {"slot", "n"}, {"level", "n"},
			{"progress", "n"}, {"done", "n"}})) do
		P.crow[r.period .. ":" .. r.faction .. ":" .. r.slot] = {level = r.level, progress = r.progress, done = r.done == 1}
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `offer`, `week`, `count` FROM `%s` WHERE `player_id` = %d",
			T.purchases, guid), {{"offer", "s"}, {"week", "n"}, {"count", "n"}})) do
		if r.week == 0 then
			P.owned[r.offer] = true
		else
			P.weekly[r.week .. ":" .. r.offer] = r.count
		end
	end
	return P
end
F.stateOf = stateOf

local function saveEntry(P, key)
	local e = P.st[key]
	if not e or not F.ensureTables() then
		return
	end
	db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `faction`, `rep`, `day`, `day_gain`, `week`, `week_gain`, " ..
		"`week_bank`, `exalted_at`, `total`) VALUES (%d, %s, %d, %d, %d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE " ..
		"`rep` = VALUES(`rep`), `day` = VALUES(`day`), `day_gain` = VALUES(`day_gain`), `week` = VALUES(`week`), " ..
		"`week_gain` = VALUES(`week_gain`), `week_bank` = VALUES(`week_bank`), `exalted_at` = VALUES(`exalted_at`), " ..
		"`total` = VALUES(`total`)", T.rep, P.guid, db.escapeString(key),
		math.floor(e.rep), e.day or 0, math.floor(e.dayGain or 0), e.week or 0, math.floor(e.weekGain or 0),
		math.floor(e.bank or 0), e.exalted or 0, math.floor(e.total or 0)))
end

local function flush(P)
	for key in pairs(P.dirty) do
		saveEntry(P, key)
	end
	P.dirty = {}
end

local function flushBoard(player, P)
	local lb = cfg.leaderboard
	if P.lb > 0 and lb and ChaosLeaderboard and ChaosLeaderboard.record then
		pcall(ChaosLeaderboard.record, lb.board, player or {guid = P.guid}, P.lb, lb.mode)
	end
	P.lb = 0
end

-- ---------------------------------------------------------------- contracts
local function periodKeys()
	return "d" .. day(), "w" .. week()
end

local function saveContract(P, c)
	if not F.ensureTables() then
		return
	end
	local per = (c.period == "daily" and "d" .. c.pk) or ("w" .. c.pk)
	db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `period`, `faction`, `slot`, `level`, `progress`, `done`) " ..
		"VALUES (%d, %s, %s, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `progress` = VALUES(`progress`), `done` = VALUES(`done`)",
		T.contracts, P.guid, db.escapeString(per), db.escapeString(c.faction), c.slot, c.level, c.progress or 0, c.done and 1 or 0))
end

-- the character's contracts of the current day and week (built once per period; the level at the first look is kept)
function F.contractsOf(player)
	local P = stateOf(player)
	local d, w = day(), week()
	if P.contracts and P.cday == d and P.cweek == w then
		return P.contracts
	end
	local dk, wk = periodKeys()
	-- old periods go
	for key in pairs(P.crow) do
		if key:sub(1, #dk + 1) ~= dk .. ":" and key:sub(1, #wk + 1) ~= wk .. ":" then
			P.crow[key] = nil
		end
	end
	if F.ensureTables() then
		db.asyncQuery(string.format("DELETE FROM `%s` WHERE `player_id` = %d AND `period` <> %s AND `period` <> %s",
			T.contracts, P.guid, db.escapeString(dk), db.escapeString(wk)))
	end
	local level = player:getLevel()
	local ctx = {families = families, catName = catName, riftCfg = ChaosRiftConfig, itemName = itemName}
	local list = {}
	for _, spec in ipairs({{"daily", d, dk}, {"weekly", w, wk}}) do
		local kind, pk, prefix = spec[1], spec[2], spec[3]
		local made = K.contracts(cfg, idx, kind, pk, P.guid, function(f, slot)
			local row = P.crow[prefix .. ":" .. f .. ":" .. slot]
			return row and row.level or level
		end, ctx)
		for _, c in ipairs(made) do
			local row = P.crow[prefix .. ":" .. c.faction .. ":" .. c.slot]
			c.pk = pk
			c.progress = row and row.progress or 0
			c.done = row and row.done or false
			if not row then
				P.crow[prefix .. ":" .. c.faction .. ":" .. c.slot] = {level = c.level, progress = 0, done = false}
				saveContract(P, c)
			end
			list[#list + 1] = c
		end
	end
	P.contracts, P.cday, P.cweek = list, d, w
	return list
end

-- ---------------------------------------------------------------- the window
local function nearFaction(player)
	local pos = player:getPosition()
	local r = cfg.npcRange or 6
	local names = {}
	for _, f in ipairs(idx.list) do
		names[f.npc.name:lower()] = f.key
	end
	for _, c in ipairs(Game.getSpectators(pos, false, false, r, r, r, r) or {}) do
		if c:isNpc() then
			local key = names[c:getName():lower()]
			if key then
				return key
			end
		end
	end
	return nil
end
F.nearFaction = nearFaction

local function weeklyView(P)
	local w = week()
	local out = {}
	for key, n in pairs(P.weekly) do
		local wk, offer = key:match("^(%d+):(.+)$")
		if tonumber(wk) == w then
			out[offer] = n
		end
	end
	return out
end

function F.payload(player, sel)
	local P = stateOf(player)
	local contracts = F.contractsOf(player)
	local tokens = {}
	for _, f in ipairs(idx.list) do
		tokens[f.key] = player:getItemCount(cfg.tokens[f.key].id)
	end
	local data = K.payload(cfg, idx, P.st, {now = now(), day = day(), week = week(), contracts = contracts, owned = P.owned,
		lang = Chaos.lang(player), weekly = weeklyView(P), near = nearFaction(player), tokens = tokens, itemName = itemName, itemMods = ChaosItemMods,
		offerItemId = function(o)
			return cfg.tokens[o.faction] and cfg.tokens[o.faction].id or 0
		end,
		clientId = function(id)
			local ok, c = pcall(function() return ItemType(id):getClientId() end)
			return ok and tonumber(c) and c > 0 and c or id
		end})
	data.gold = Chaos.totalMoney(player)
	data.sel = sel
	return data
end

function F.send(player, sel)
	if not cfg.enabled or not player then
		return false
	end
	local data = try("payload", F.payload, player, sel)
	if not data then
		return false
	end
	return Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = data}))
end

local function msg(player, text, ok)
	Chaos.send(player, OPCODE, "msg", {text = text, ok = ok and true or false})
	player:sendTextMessage(ok and MESSAGE_INFO_DESCR or MESSAGE_STATUS_SMALL, text)
end

-- a window refresh at most once a second (kills)
local function pushLater(player)
	local P = F.players[player:getGuid()]
	if not P or not P.open or P.pushPending then
		return
	end
	P.pushPending = true
	addEvent(function(cid)
		local p = Player(cid)
		local Q = p and F.players[p:getGuid()]
		if Q then
			Q.pushPending = false
			if Q.open then
				F.send(p)
			end
		end
	end, 1000, player:getId())
end

-- ---------------------------------------------------------------- reputation
local function setAchievements(player, P)
	if not cfg.achievementStats or not ChaosAchievements or not ChaosAchievements.set then
		return
	end
	local n = 0
	for _, f in ipairs(idx.list) do
		local e = P.st[f.key]
		if e and (e.exalted or 0) > 0 then
			n = n + 1
			pcall(ChaosAchievements.set, player, "faction_exalted_" .. f.key, 1)
		end
	end
	if n > 0 then
		pcall(ChaosAchievements.set, player, "faction_exalted", n)
	end
end

-- give `amount` reputation with faction `key`. source = "kill" | "bounty" | "token" | "rift" | "invasion" |
-- "worldBoss" | "contract". quiet: no message (kills). Returns the K.gain result.
function F.gain(player, key, amount, source, quiet)
	local P = stateOf(player)
	-- community goal's reputation stage and the week's Banner Week (community.lua); 1 when neither is active
	local cm = ChaosCommunity and ChaosCommunity.repMult and tonumber(ChaosCommunity.repMult(player)) or 1
	if cm ~= 1 and (tonumber(amount) or 0) > 0 then
		amount = math.floor(amount * cm + 0.5)
	end
	-- the Reputation of the placed charms (charms.lua), percent
	local charmRep = ChaosCharms and ChaosCharms.repPct and tonumber(ChaosCharms.repPct(player)) or 0
	if charmRep > 0 and (tonumber(amount) or 0) > 0 then
		amount = math.floor(amount * (100 + charmRep) / 100 + 0.5)
	end
	local res = K.gain(cfg, idx, P.st, key, amount, {day = day(), week = week(), contract = source == "contract", now = now()})
	local f = idx.byKey[key]
	if not f then
		return res
	end
	P.dirty[key] = true
	if res.rival then
		P.dirty[res.rival] = true
	end
	if res.gained > 0 then
		P.lb = P.lb + res.gained
	end
	if not quiet and res.gained > 0 then
		local rv = res.rival and idx.byKey[res.rival]
		player:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_STATUS_SMALL, Chaos.t(player, "+%d reputation with %s%s.",
			res.gained, f.name, (res.rivalLoss or 0) > 0 and string.format(" (%s -%d)", rv.name, res.rivalLoss) or ""))
	elseif not quiet and res.capped then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, "You have reached this week's reputation cap with %s.", f.name))
	end
	if res.rankAfter and res.rankBefore and res.rankAfter > res.rankBefore then
		local r = cfg.ranks[res.rankAfter]
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%s now counts you as %s.", f.name, r.name))
		player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
		flush(P)
		if ChaosNameplate and ChaosNameplate.refresh then
			pcall(ChaosNameplate.refresh, player)
		end
	end
	if res.exaltedNow then
		setAchievements(player, P)
	end
	pushLater(player)
	return res
end

-- ---------------------------------------------------------------- contract progress
local function completeContract(player, P, c)
	c.done = true
	local row = P.crow[(c.period == "daily" and "d" or "w") .. c.pk .. ":" .. c.faction .. ":" .. c.slot]
	if row then
		row.progress, row.done = c.progress, true
	end
	saveContract(P, c)
	local f = idx.byKey[c.faction]
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%s contract done: %s.", f.name, K.label(c, Chaos.lang(player))))
	F.gain(player, c.faction, c.rep, "contract")
end

local function progress(player, match, n)
	local P = stateOf(player)
	for _, c in ipairs(F.contractsOf(player)) do
		if not c.done and c.kind ~= "deliver" and match(c) then
			local p, done = K.advance(c, c.progress or 0, n or 1)
			if p ~= c.progress then
				c.progress = p
				local row = P.crow[(c.period == "daily" and "d" or "w") .. c.pk .. ":" .. c.faction .. ":" .. c.slot]
				if row then
					row.progress = p
				end
				if done then
					completeContract(player, P, c)
				elseif c.kind ~= "kill" or p % 10 == 0 then
					saveContract(P, c)
				end
				pushLater(player)
			end
		end
	end
end

-- ---------------------------------------------------------------- items to a player
local function giveStack(player, id, count)
	local rest = count - Chaos.giveItem(player, id, count)
	local inbox = rest > 0 and player:getInbox()
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
	return count - rest
end

local function giveTokens(player, key, n)
	local tok = cfg.tokens[key]
	if not tok or (n or 0) <= 0 then
		return
	end
	giveStack(player, tok.id, n)
	player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "You received %d %s.", n, n == 1 and tok.name or tok.plural))
end

-- ---------------------------------------------------------------- kills
local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	if master and master:isPlayer() then
		return master
	end
	return nil
end

local function creditList(killer, mostDamage)
	local killers, seen = {}, {}
	for _, k in ipairs({playerOf(killer), playerOf(mostDamage)}) do
		if k and not seen[k:getId()] then
			seen[k:getId()] = true
			killers[#killers + 1] = k
		end
	end
	if #killers == 0 then
		return killers
	end
	local BC = ChaosBestiaryCore
	if BC and BC.credit then
		local range = Chaos.bestiaryConfig and Chaos.bestiaryConfig.partyRange or 30
		local ok, list = pcall(BC.credit, killers, function(p)
			local party = p:getParty()
			if not party then
				return nil
			end
			local members = party:getMembers()
			members[#members + 1] = party:getLeader()
			return members
		end, function(p) return p:getPosition() end, range, function(p) return p:getId() end)
		if ok and type(list) == "table" then
			return list
		end
	end
	return killers
end

-- monster: the creature (pack combat, pace.lua: a paced monster counts 1 / its kill-goal factor for the contracts and the
-- reputation points, summed per player)
local function onKillFor(player, e, fkey, tier, monster)
	local share = cfg.sources.kill.minLevelShare
	local info = {cat = e.cat, level = e.level or 0}
	local goal = monster and ChaosPace and ChaosPace.goalMultOf and ChaosPace.goalMultOf(monster) or 1
	local n = (goal > 1 and ChaosPace.killCredit) and ChaosPace.killCredit(player, monster, "faction") or 1
	if n > 0 then
		progress(player, function(c) return K.matchKill(c, info) end, n)
	end
	if info.level < math.floor(player:getLevel() * share) then
		return
	end
	if not cfg.multiClientRep and Chaos.isMultiClient(player) then
		return
	end
	local P = stateOf(player)
	local pts = (P.killPts[fkey] or 0) + (cfg.sources.kill.points[tier] or 1) / (goal > 1 and goal or 1)
	local per = cfg.sources.kill.pointsPerRep
	local rep = math.floor(pts / per)
	P.killPts[fkey] = pts - rep * per
	if rep > 0 then
		F.gain(player, fkey, rep, "kill", true)
	end
end

function F.onKill(creature, corpse, killer, mostDamage)
	local e = entryOf(typeNameOf(creature))
	if not e then
		return
	end
	local fkey = idx.byCategory[e.cat]
	if not fkey then
		return
	end
	local dead = ChaosTierDead and ChaosTierDead[creature:getId()]
	local tier = dead and dead.tier or (ChaosTierOf and ChaosTierOf(creature)) or "normal"
	if tier == "boss" then
		tier = "legendary"
	end
	for _, p in ipairs(creditList(killer, mostDamage)) do
		onKillFor(p, e, fkey, tier, creature)
	end
	-- the token: one roll per kill, into the corpse (the loot owner's)
	local owner = playerOf(mostDamage) or playerOf(killer)
	local td = cfg.tokenDrop
	if owner and (e.level or 0) >= td.minMonsterLevel and (e.level or 0) >= math.floor(owner:getLevel() * cfg.sources.kill.minLevelShare)
			and math.random(1, 10000) <= K.tokenChance(cfg, tier)
				* (ChaosPace and ChaosPace.lootMultOf and ChaosPace.lootMultOf(creature) or 1)
				* (ChaosCatchup and ChaosCatchup.tokenMult and ChaosCatchup.tokenMult(owner) or 1) then
		local tok = cfg.tokens[fkey]
		local placed = false
		if corpse and corpse.isContainer and corpse:isContainer() then
			local ok, added = pcall(function() return corpse:addItem(tok.id, 1) end)
			placed = ok and added ~= nil and added ~= false
		end
		if not placed then
			giveTokens(owner, fkey, 1)
		end
	end
end

local death = CreatureEvent("ChaosFactionsDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	if cfg.enabled then
		try("kill", F.onKill, creature, corpse, killer, mostDamageKiller)
	end
	return true
end
death:register()

local spawn = EventCallback
spawn.onSpawn = function(self, position, startup, artificial)
	if not self:getMaster() then
		self:registerEvent("ChaosFactionsDeath")
	end
	return true
end
spawn:register()

-- ---------------------------------------------------------------- hooks: bounty, rift, world boss, invasion
local function online(who)
	if type(who) == "userdata" then
		return who
	end
	local guid, name
	if type(who) == "table" then
		guid, name = tonumber(who.guid), who.name
	else
		guid = tonumber(who)
	end
	local p = name and Player(name)
	if p and (not guid or p:getGuid() == guid) then
		return p
	end
	for _, q in ipairs(Game.getPlayers()) do
		if q:getGuid() == guid then
			return q
		end
	end
	return nil
end

function F.onBounty(player)
	local B = ChaosBounty
	local bst = B and B.players and B.players[player:getGuid()]
	if not bst or not bst.entries then
		return
	end
	local P = stateOf(player)
	P.bountySeen = P.bountySeen or {}
	for key, e in pairs(bst.entries) do
		local tag = tostring(e.day) .. ":" .. tostring(key)
		if e.status ~= 0 and not P.bountySeen[tag] then
			P.bountySeen[tag] = true
			local entry = e.monster and entryOf(e.monster)
			local fkey = entry and idx.byCategory[entry.cat]
			if fkey then
				F.gain(player, fkey, cfg.sources.bounty, "bounty")
			end
		end
	end
end

function F.onRiftSealed(player, tier)
	local RF = ChaosRift
	local run = RF and RF.runOf and RF.runOf[player:getId()]
	local theme = run and (run.themeName or run.theme)
	if not run or run.omen or type(theme) ~= "string" then
		return
	end
	local P = stateOf(player)
	if P.lastRift == run then
		return -- counted already (a second wrap)
	end
	P.lastRift = run
	tier = math.floor(tonumber(tier) or (run.key and run.key.tier) or 1)
	progress(player, function(c) return K.matchRift(c, theme, tier) end, 1)
	local fkey = idx.byTheme[theme:lower()]
	if fkey then
		local s = cfg.sources.rift
		F.gain(player, fkey, s.base + s.perTier * tier, "rift")
		giveTokens(player, fkey, cfg.tokenDrop.riftSeal + math.floor(tier / math.max(1, cfg.tokenDrop.riftSealPerTiers)))
	end
end

local function onRecord(board, who, value)
	if board ~= "bounty" and board ~= "rift" then
		return
	end
	local player = online(who)
	if not player then
		return
	end
	if board == "bounty" then
		F.onBounty(player)
	else
		F.onRiftSealed(player, value)
	end
end

function F.onWorldBoss(shares, boss)
	local fkey = K.factionOfBoss(idx, boss and boss.name)
	local tag = tostring(boss and boss.name) .. ":" .. math.floor(now() / 600)
	for _, s in ipairs(shares or {}) do
		local p = online({guid = s.guid, name = s.name})
		if p then
			local P = stateOf(p)
			if P.lastBoss ~= tag then
				P.lastBoss = tag
				progress(p, function(c) return K.matchEvent(c, "worldboss") end, 1)
				if fkey then
					F.gain(p, fkey, cfg.sources.worldBoss, "worldBoss")
					giveTokens(p, fkey, cfg.tokenDrop.worldBoss)
				end
			end
		end
	end
end

function F.onInvasion(player, r)
	if type(r) ~= "table" or F.seen[r] then
		return
	end
	F.seen[r] = true
	progress(player, function(c) return K.matchEvent(c, "invasion") end, 1)
	local V = ChaosInvasion
	local inv = r.factionKey or (V and V.state and V.state.factionKey)
	for _, fkey in ipairs(inv and idx.byInvader[inv] or {}) do
		F.gain(player, fkey, cfg.sources.invasion, "invasion")
		giveTokens(player, fkey, cfg.tokenDrop.invasion)
	end
end

function F.installHooks()
	local LB = ChaosLeaderboard
	if LB and LB.record and not LB.factionsWrapped then
		local original = LB.record
		LB.record = function(board, who, value, mode)
			local entry = original(board, who, value, mode)
			if cfg.enabled then
				try("leaderboard hook", onRecord, board, who, value)
			end
			return entry
		end
		LB.factionsWrapped = true
	end
	local W = ChaosWorldBoss
	if W and W.computeRewards and not W.factionsWrapped then
		local original = W.computeRewards
		W.computeRewards = function(shares, r, boss, pool, rng, pityOf)
			local out = original(shares, r, boss, pool, rng, pityOf)
			if cfg.enabled then
				try("world boss hook", F.onWorldBoss, shares, boss)
			end
			return out
		end
		W.factionsWrapped = true
	end
	local V = ChaosInvasion
	if V and V.deliver and not V.factionsWrapped then
		local original = V.deliver
		V.deliver = function(player, r, ...)
			local out = original(player, r, ...)
			if cfg.enabled and player then
				try("invasion hook", F.onInvasion, player, r)
			end
			return out
		end
		V.factionsWrapped = true
	end
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register("faction", function(player)
			local P = F.players[player:getGuid()]
			return P and K.titlesOf(cfg, idx, P.st) or nil
		end)
	end
end
F.installHooks()

-- ---------------------------------------------------------------- NPC actions (the NPC must stand close)
local function needNpc(player, fkey)
	local near = nearFaction(player)
	if near ~= fkey then
		local f = idx.byKey[fkey]
		msg(player, Chaos.t(player, "Speak with %s (%s) for that.", f.npc.name, f.name))
		return false
	end
	return true
end

local function pay(player, gold)
	if gold <= 0 then
		return true
	end
	return Chaos.pay(player, gold) and true or false
end

local function money(player)
	return Chaos.totalMoney(player)
end

function F.turnIn(player, fkey, n)
	local f = idx.byKey[fkey]
	if not f or not needNpc(player, fkey) then
		return
	end
	local P = stateOf(player)
	local e = K.roll(P.st[fkey] or K.newEntry(cfg), day(), week(), cfg)
	P.st[fkey] = e
	if e.weekGain >= K.weekCap(cfg, e) or e.rep >= cfg.rep.max then
		return msg(player, Chaos.t(player, "%s cannot reward you more this week. Keep your tokens.", f.name))
	end
	local tok = cfg.tokens[fkey]
	local have = player:getItemCount(tok.id)
	n = math.min(have, Chaos.toInt(n, 1, 100000) or have)
	if n <= 0 then
		return msg(player, Chaos.t(player, "You carry no %s.", tok.plural))
	end
	if not player:removeItem(tok.id, n) then
		return msg(player, Chaos.t(player, "The tokens could not be taken."))
	end
	local res = F.gain(player, fkey, n * cfg.sources.token, "token", true)
	flush(P)
	msg(player, Chaos.t(player, "%s takes %d %s: +%d reputation%s.", f.npc.name, n, n == 1 and tok.name or tok.plural,
		res.gained, res.capped and Chaos.t(player, " (weekly cap reached)") or ""), true)
end

function F.deliver(player, key)
	local c
	for _, x in ipairs(F.contractsOf(player)) do
		if x.key == key then
			c = x
		end
	end
	if not c or c.kind ~= "deliver" or c.done then
		return msg(player, Chaos.t(player, "That delivery is not open."))
	end
	if not needNpc(player, c.faction) then
		return
	end
	for _, it in ipairs(c.items or {}) do
		if player:getItemCount(it.id) < it.count then
			return msg(player, Chaos.t(player, "You need %d %s.", it.count, itemName(it.id, it.count)))
		end
	end
	if money(player) < (c.gold or 0) then
		return msg(player, Chaos.t(player, "You need %s gold (carried or in the bank).", K.thousands(c.gold)))
	end
	for _, it in ipairs(c.items or {}) do
		if not player:removeItem(it.id, it.count) then
			return msg(player, Chaos.t(player, "The materials could not be taken."))
		end
	end
	if not pay(player, c.gold or 0) then
		for _, it in ipairs(c.items or {}) do
			giveStack(player, it.id, it.count)
		end
		return msg(player, Chaos.t(player, "The gold could not be taken."))
	end
	c.progress = c.count
	completeContract(player, stateOf(player), c)
	msg(player, Chaos.t(player, "Delivered: %s.", K.label(c, Chaos.lang(player))), true)
end

local function bump(P, offer)
	local w = offer.weekly and week() or 0
	local key = w .. ":" .. offer.key
	if offer.weekly then
		P.weekly[key] = (P.weekly[key] or 0) + 1
	else
		P.owned[offer.key] = true
	end
	if F.ensureTables() then
		db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `offer`, `week`, `count`, `at`) VALUES (%d, %s, %d, 1, %d) " ..
			"ON DUPLICATE KEY UPDATE `count` = `count` + 1, `at` = VALUES(`at`)", T.purchases, P.guid,
			db.escapeString(offer.key), w, now()))
	end
end

-- the fixed gear item of an offer (nil, reason when it cannot be made)
function F.makeGear(offer)
	local C, M = ChaosCrafting, ChaosItemMods
	if not C or not M or not C.writeAffix then
		return nil, "The quartermaster's forge is cold (crafting is not loaded)."
	end
	local item = Game.createItem(offer.id, 1)
	if not item then
		return nil, "That item does not exist on this server."
	end
	if (C.isGear and not C.isGear(item)) or (M.kindOf and M.kindOf(item) ~= offer.itemKind) then
		item:remove()
		log(string.format("offer %s: item %d is not a %s", offer.key, offer.id, tostring(offer.itemKind)))
		return nil, "That offer is broken. Tell a gamemaster."
	end
	C.clearMods(item)
	item:setCustomAttribute("rarity", offer.rarity)
	item:setCustomAttribute(M.ILVL, offer.level)
	item:setCustomAttribute("combatPowerLevel", offer.level)
	if C.applyBaseBonus then
		C.applyBaseBonus(item, offer.rarity, offer.level)
	end
	for _, m in ipairs(K.gearMods(offer, M)) do
		local affix = C.affixOf(M.attr(m.key)) or C.affixOf(m.key)
		if affix then
			C.writeAffix(item, affix, m.tier, m.value)
		end
	end
	local f = idx.byKey[offer.faction]
	item:setAttribute(ITEM_ATTRIBUTE_NAME, offer.name:lower())
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "Issued by the quartermaster of " .. f.name)
	item:setCustomAttribute("chaos_faction", offer.faction)
	C.rewriteDescription(item)
	return item
end

function F.buy(player, key)
	local o = idx.offers[tostring(key)]
	if not o or not needNpc(player, o.faction) then
		return
	end
	local P = stateOf(player)
	local ranks = {}
	for _, f in ipairs(idx.list) do
		ranks[f.key] = K.rankAt(cfg, (P.st[f.key] or K.newEntry(cfg)).rep)
	end
	local state, why = K.offerState(cfg, idx, o, {ranks = ranks, owned = P.owned, weekly = weeklyView(P),
		lang = Chaos.lang(player)})
	if state ~= "ok" then
		return msg(player, why or Chaos.t(player, "Not available."))
	end
	local tok = cfg.tokens[o.faction]
	if (o.tokens or 0) > 0 and player:getItemCount(tok.id) < o.tokens then
		return msg(player, Chaos.t(player, "You need %d %s.", o.tokens, tok.plural))
	end
	if money(player) < o.price then
		return msg(player, Chaos.t(player, "You need %s gold (carried or in the bank).", K.thousands(o.price)))
	end
	-- make the goods first, then take the payment
	local item
	if o.kind == "gear" then
		local err
		item, err = F.makeGear(o)
		if not item then
			return msg(player, Chaos.t(player, err))
		end
	end
	if (o.tokens or 0) > 0 and not player:removeItem(tok.id, o.tokens) then
		if item then item:remove() end
		return msg(player, Chaos.t(player, "The tokens could not be taken."))
	end
	if not pay(player, o.price) then
		if (o.tokens or 0) > 0 then giveStack(player, tok.id, o.tokens) end
		if item then item:remove() end
		return msg(player, Chaos.t(player, "The gold could not be taken."))
	end
	local note = ""
	if o.kind == "gear" then
		if player:addItemEx(item, false) ~= RETURNVALUE_NOERROR then
			local inbox = player:getInbox()
			if inbox then
				inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
				note = Chaos.t(player, " Your backpack was full: it is in your inbox.")
			end
		end
	elseif o.kind == "orbs" then
		for _, it in ipairs(o.items) do
			giveStack(player, it.id, it.count)
		end
	elseif o.kind == "aura" then
		player:addAura(o.aura)
	elseif o.kind == "mount" then
		player:addMount(o.mount)
	end
	bump(P, o)
	log(string.format("%s bought %s for %d gold and %d tokens", player:getName(), o.key, o.price, o.tokens or 0))
	msg(player, Chaos.t(player, "Bought: %s.%s", o.name, note), true)
end

function F.craft(player, key, n)
	local o = idx.offers[tostring(key)]
	if not o or o.kind ~= "recipe" then
		return
	end
	local P = stateOf(player)
	if not P.owned[o.key] then
		return msg(player, Chaos.t(player, "You do not know that recipe."))
	end
	if not needNpc(player, o.faction) then
		return
	end
	n = Chaos.toInt(n, 1, 20) or 1
	local cr = o.craft
	local tok = cfg.tokens[o.faction]
	for _, it in ipairs(cr.inputs or {}) do
		if player:getItemCount(it.id) < it.count * n then
			return msg(player, Chaos.t(player, "You need %d %s.", it.count * n, itemName(it.id, it.count * n)))
		end
	end
	if (cr.tokens or 0) > 0 and player:getItemCount(tok.id) < cr.tokens * n then
		return msg(player, Chaos.t(player, "You need %d %s.", cr.tokens * n, tok.plural))
	end
	if money(player) < (cr.gold or 0) * n then
		return msg(player, Chaos.t(player, "You need %s gold.", K.thousands((cr.gold or 0) * n)))
	end
	for _, it in ipairs(cr.inputs or {}) do
		player:removeItem(it.id, it.count * n)
	end
	if (cr.tokens or 0) > 0 then
		player:removeItem(tok.id, cr.tokens * n)
	end
	pay(player, (cr.gold or 0) * n)
	for _, it in ipairs(cr.output) do
		giveStack(player, it.id, it.count * n)
	end
	msg(player, Chaos.t(player, "%s: made %dx.", o.name:gsub("^Recipe: ", ""), n), true)
end

-- ---------------------------------------------------------------- NPC placement
function F.placeNpcs()
	local placed = 0
	for _, f in ipairs(idx.list) do
		local n = f.npc
		local done
		if n.pos then
			-- a fixed spot: that tile (an NPC of that name already near it is kept)
			done = try("place " .. n.name, ChaosNpcPlace.place, n.name, Position(n.pos.x, n.pos.y, n.pos.z), {{0, 0}},
				{radius = 8, spacing = 0, minFromTemple = 0})
		else
			local town = (n.town and Town(n.town)) or (n.townId and Town(n.townId))
			local temple = town and town:getTemplePosition()
			done = temple and try("place " .. n.name, ChaosNpcPlace.place, n.name, temple, cfg.npcOffsets, cfg.npcPlace)
		end
		if done then
			placed = placed + 1
		else
			log("could not place " .. n.name .. " (no town, no free tile next to the temple, or data/npc/" .. n.name ..
				".xml is missing: tools/install_factions.py)")
		end
	end
	return placed
end

-- ---------------------------------------------------------------- events
local startup = GlobalEvent("ChaosFactionsStartup")
function startup.onStartup()
	F.ensureTables()
	F.installHooks()
	if cfg.enabled then
		local problems = K.validate(cfg, ChaosItemMods)
		for _, p in ipairs(problems) do
			log("config: " .. p)
		end
		addEvent(function()
			log(F.placeNpcs() .. " faction NPC(s) placed")
		end, 1500)
	end
	return true
end
startup:register()

local login = CreatureEvent("ChaosFactionsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosFactionsExtended")
	player:registerEvent("ChaosFactionsLogout")
	F.installHooks() -- again after a /reload of an other system
	local P = try("load", stateOf, player)
	if P then
		try("achievements", setAchievements, player, P)
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosFactionsLogout")
function logout.onLogout(player)
	local P = F.players[player:getGuid()]
	if P then
		flush(P)
		try("board", flushBoard, player, P)
		F.players[player:getGuid()] = nil
	end
	return true
end
logout:type("logout")
logout:register()

local think = GlobalEvent("ChaosFactionsFlush")
function think.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		local P = F.players[player:getGuid()]
		if P then
			flush(P)
			try("board", flushBoard, player, P)
		end
	end
	return true
end
think:interval(60000)
think:register()

local ext = CreatureEvent("ChaosFactionsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE or not cfg.enabled then
		return
	end
	local m = Chaos.decode(buffer)
	if not m or type(m.action) ~= "string" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "factions", cfg.requestMs or 400) then
		return
	end
	local d = type(m.data) == "table" and m.data or {}
	local P = stateOf(player)
	if m.action == "open" then
		P.open = true
		F.send(player, idx.byKey[tostring(d.f)] and d.f or nil)
		return
	elseif m.action == "close" then
		P.open = false
		return
	elseif m.action == "turnin" then
		try("turnin", F.turnIn, player, tostring(d.f), d.n)
	elseif m.action == "deliver" then
		try("deliver", F.deliver, player, tostring(d.key))
	elseif m.action == "buy" then
		try("buy", F.buy, player, tostring(d.key))
	elseif m.action == "craft" then
		try("craft", F.craft, player, tostring(d.key), d.n)
	else
		return
	end
	F.send(player)
end
ext:type("extendedopcode")
ext:register()

-- staff: /faction Name, vigil, 36000   (set a standing)   /faction Name   (show)
local talk = TalkAction("/faction")
function talk.onSay(player, words, param)
	if player:getGroup():getId() < (cfg.staffGroup or 4) then
		return false
	end
	local name, key, value = param:match("^%s*([^,]+),%s*(%w+),%s*(%-?%d+)%s*$")
	local target = Player(name or param:match("^%s*(.-)%s*$"))
	if not target then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/faction <online character>[, <faction key>, <reputation>]")
		return false
	end
	local P = stateOf(target)
	if key then
		if not idx.byKey[key] then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "Unknown faction " .. key .. ".")
			return false
		end
		K.set(cfg, P.st, key, tonumber(value), now())
		P.dirty[key] = true
		flush(P)
		setAchievements(target, P)
		if ChaosNameplate and ChaosNameplate.refresh then
			pcall(ChaosNameplate.refresh, target)
		end
	end
	local parts = {}
	for _, f in ipairs(idx.list) do
		local e = P.st[f.key] or K.newEntry(cfg)
		parts[#parts + 1] = string.format("%s %d (%s)", f.short, e.rep, K.bar(cfg, e.rep).name)
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, target:getName() .. ": " .. table.concat(parts, ", "))
	if P.open then
		F.send(target)
	end
	return false
end
talk:separator(" ")
talk:register()
