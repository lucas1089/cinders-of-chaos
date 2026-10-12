-- Run from the server/ folder: luajit tests/season_modes_test.lua (and lua5.3; CI runs both)
-- Season modes (Self-Found, Hardcore): the pure rules of season_modes_core.lua with the real season_config.lua
-- (every blocked path, the fall, the Hardcore protections, the ladder tabs), then season_modes.lua itself against a
-- mocked engine (the join, item moves with owner tags, trade / party callbacks, the market / orb / bank hooks, the
-- fall and its migration, a protected lethal hit, the pull to the temple, the shutdown save, a mode tab of the ladder).
dofile("data/scripts/chaos/season_core.lua")
dofile("data/scripts/chaos/season_modes_core.lua")
local M = ChaosSeasonModes
local cfg = dofile("data/scripts/chaos/season_config.lua")
local mc = cfg.modes

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- config
local seen = {}
for _, d in ipairs(mc.list) do
	eq(seen[d.key], nil, "mode keys unique " .. d.key)
	seen[d.key] = true
	eq(M.keyOf(d.ssf, d.hc), d.key, "key matches its flags " .. d.key)
	eq(type(d.warning) == "string" and #d.warning > 10, true, "a warning " .. d.key)
end
for _, k in ipairs({"standard", "ssf", "hc", "hcssf"}) do
	eq(seen[k], true, "mode listed " .. k)
end
for _, k in ipairs({"trade", "party", "bank", "market", "orbs", "mail", "mailTo", "loot", "give", "item", "house"}) do
	eq(type(mc.messages[k]), "string", "message " .. k)
end
eq(mc.hc.pullSeconds > mc.hc.heartbeatSeconds, true, "pull after more than one heartbeat")
eq(mc.hc.pingLossSeconds > mc.hc.heartbeatSeconds, true, "a ping loss is more than one missed heartbeat")

-- ---------------------------------------------------------------- picking a mode
eq(M.pick(mc, nil).key, "standard", "no mode (older client) = standard")
eq(M.pick(mc, "").key, "standard", "empty = standard")
eq(M.pick(mc, "hcssf").key, "hcssf", "HC SSF")
local bad, why = M.pick(mc, "godmode")
eq(bad, nil, "unknown mode refused")
eq(type(why), "string", "with a reason")
local choices = M.choices(mc)
eq(#choices, 4, "four choices")
eq(choices[4].ssf and choices[4].hc, true, "HC SSF is both")

-- ---------------------------------------------------------------- flags
eq(M.flags(nil, 1).key, "standard", "no row")
eq(M.flags({ssf = 1, hc = 0}, 0).key, "standard", "realm 0 (migrated / season over) = standard")
eq(M.flags({ssf = 1, hc = 0}, 1).key, "ssf", "SSF")
eq(M.flags({ssf = 0, hc = 1}, 1).key, "hc", "HC")
eq(M.flags({ssf = 1, hc = 1}, 1).key, "hcssf", "HC SSF")
local fl = M.flags({ssf = 1, hc = 1, fallen = 1790000000}, 0)
eq(fl.key, "standard", "a fallen character plays standard")
eq(fl.fallen, true, "and is marked fallen")
eq(M.flags({ssf = 1, hc = 1, reset = 5}, 1).key, "standard", "reset at the season end")

local STD, SSF, HC, HCSSF = M.flags(nil, 0), M.flags({ssf = 1}, 1), M.flags({hc = 1}, 1), M.flags({ssf = 1, hc = 1}, 1)
local GM = {key = "standard", exempt = true}

-- ---------------------------------------------------------------- trade, party, gold, market, orbs
eq(M.tradeAllowed(STD, HC), true, "standard trades with HC")
eq(M.tradeAllowed(HC, HC), true, "HC trades with HC")
eq(select(2, M.tradeAllowed(SSF, STD)), "trade", "SSF -> standard: blocked")
eq(select(2, M.tradeAllowed(STD, SSF)), "trade", "standard -> SSF: blocked")
eq(M.tradeAllowed(SSF, SSF), false, "SSF -> SSF: blocked (self-found means nobody)")
eq(M.tradeAllowed(HCSSF, HC), false, "HC SSF -> HC: blocked")
eq(M.tradeAllowed(SSF, GM), true, "staff hand out test items")
eq(M.partyAllowed(SSF, SSF), true, "SSF party with SSF")
eq(M.partyAllowed(SSF, HCSSF), true, "SSF party with HC SSF")
eq(select(2, M.partyAllowed(SSF, STD)), "party", "SSF with standard: blocked")
eq(M.partyAllowed(STD, HCSSF), false, "standard with HC SSF: blocked")
eq(M.partyAllowed(HC, STD), true, "HC parties with standard")
eq(M.transferAllowed(SSF, STD), false, "gold from SSF: blocked")
eq(select(2, M.transferAllowed(STD, HCSSF)), "bank", "gold to SSF: blocked")
eq(M.transferAllowed(HC, STD), true, "HC gold transfer allowed")
eq(M.transferAllowed(GM, SSF), true, "staff")
for _, action in ipairs({"list", "buy", "orderPost", "fill"}) do
	eq(select(2, M.marketAllowed(SSF, action)), "market", "SSF market " .. action .. " blocked")
	eq(M.marketAllowed(HC, action), true, "HC market " .. action)
end
eq(M.marketAllowed(SSF, "cancel"), true, "SSF may still cancel / collect")
eq(M.marketAllowed(HCSSF, "browse"), true, "SSF may look")
eq(select(2, M.orbAllowed(HCSSF, "place")), "orbs", "orb exchange order blocked")
eq(M.orbAllowed(SSF, "cancel"), true, "orb cancel open")
eq(M.orbAllowed(STD, "place"), true, "standard orbs")

-- ---------------------------------------------------------------- item moves
local ssfSet = {[10] = true, [11] = true}
local function isSsf(g) return ssfSet[g] == true end
local function mv(t)
	t.isSsf = t.isSsf or isSsf
	return M.moveCheck(t)
end
-- a Self-Found character (10)
eq(mv({mover = 10, ssf = true, from = {}, to = {}}), true, "SSF: untagged items (map, quest chests, unowned corpses)")
eq(mv({mover = 10, ssf = true, from = {10}, to = {}}), true, "SSF: its own drop / its own monster corpse")
eq(select(2, mv({mover = 10, ssf = true, from = {20}, to = {}})), "loot", "SSF: another player's drop")
eq(select(2, mv({mover = 10, ssf = true, from = {11}, to = {}})), "loot", "SSF: its SSF party member's corpse (loot stays personal)")
eq(select(2, mv({mover = 10, ssf = true, from = {10, 20}, to = {}})), "loot", "SSF: own bag inside someone's corpse")
eq(select(2, mv({mover = 10, ssf = true, from = {}, to = {20}})), "give", "SSF: into another player's bag / corpse")
eq(select(2, mv({mover = 10, ssf = true, from = {}, to = {}, mail = true})), "mail", "SSF: sends no mail (also to itself)")
eq(select(2, mv({mover = 10, ssf = true, from = {}, to = {}, houseFrom = 20})), "house", "SSF: items of someone's house")
eq(select(2, mv({mover = 10, ssf = true, from = {}, to = {}, houseTo = 20})), "house", "SSF: into someone's house")
eq(mv({mover = 10, ssf = true, from = {}, to = {}, houseFrom = 10, houseTo = 10}), true, "SSF: its own house")
eq(mv({mover = 10, ssf = true, exempt = true, from = {20}, to = {}}), true, "staff never blocked")
-- a standard / Hardcore character (20)
eq(mv({mover = 20, from = {30}, to = {}}), true, "standard: other standard players' drops (the realm rule decides)")
eq(select(2, mv({mover = 20, from = {10}, to = {}})), "item", "standard: a Self-Found character's drop / corpse")
eq(select(2, mv({mover = 20, from = {}, to = {11}})), "item", "standard: into a Self-Found character's bag")
eq(select(2, mv({mover = 20, from = {}, to = {}, mail = true, mailTo = 10})), "mailTo", "standard: mail to a Self-Found")
eq(mv({mover = 20, from = {}, to = {}, mail = true, mailTo = 30}), true, "standard: mail to standard")
eq(mv({mover = 20, from = {}, to = {}, mail = true}), true, "standard: mail to an unknown name (the engine refuses it)")
eq(select(2, mv({mover = 20, from = {}, to = {}, houseFrom = 10})), "house", "standard: a Self-Found character's house")
-- the owner tag after a move
eq(M.ownerTagAction({inventory = true, tag = 20, mover = 20}), "clear", "picked up: the tag goes")
eq(M.ownerTagAction({inventory = true, mover = 20}), nil, "untagged into the inventory")
eq(M.ownerTagAction({depot = true, mover = 20}), nil, "into the own depot: no tag")
eq(M.ownerTagAction({mover = 20}), "set", "dropped on the ground: the dropper's")
eq(M.ownerTagAction({tag = 10, mover = 20}), nil, "moved around: keeps its first owner")

-- ---------------------------------------------------------------- rewards
local find, rarity = M.lootBonus(SSF, mc)
eq(find, mc.ssf.itemFind, "SSF item find")
eq(rarity, mc.ssf.rarityFind, "SSF rarity find")
eq(select(1, M.lootBonus(HCSSF, mc)), mc.ssf.itemFind, "HC SSF item find")
eq(select(1, M.lootBonus(HC, mc)), 0, "HC no loot bonus")
local st = M.achievementStats(HCSSF, 120)
eq(st.season_hc_level, 120, "HC level stat")
eq(st.season_ssf_level, 120, "SSF level stat")
eq(M.achievementStats(STD, 120).season_hc_level, nil, "standard no stat")
eq(M.survivedStats(HC).season_hc_survived, 1, "alive at the end")
eq(M.survivedStats(fl).season_hc_survived, nil, "fallen: no survival")
eq(M.survivedStats(SSF).season_ssf_finished, 1, "SSF finished")

-- ---------------------------------------------------------------- death
eq(M.deathPlan(HC).fallen, true, "HC death: fallen")
eq(M.deathPlan(HCSSF).fallen, true, "HC SSF death: fallen")
eq(M.deathPlan(SSF), nil, "SSF death: nothing special")
eq(M.deathPlan(STD), nil, "standard death")
eq(M.deathPlan(fl), nil, "an already fallen character does not fall twice")
eq(M.deathCause({name = "Dragon Lord"}), "killed by Dragon Lord", "monster cause")
eq(M.deathCause({name = "Sir Bob", player = true}), "slain by Sir Bob", "player cause")
eq(M.deathCause(nil), "died", "no killer")
eq(#M.deathCause({name = string.rep("x", 200)}) <= 60, true, "cause fits the column")
-- after the fall: the season row is migrated (realm 0) and the mode row fallen
eq(ChaosSeason.realm({season = 1, migrated = 1790000000}, 1790000100, {{id = 1, start = 1, finish = 1890000000}}), 0,
	"migrated at once: standard realm")
eq(M.flags({hc = 1, fallen = 1790000100}, 0).fallen, true, "fallen flag kept")

-- ---------------------------------------------------------------- Hardcore protections
local H = mc.hc
local t0 = 1790000000
local function prot(s, t) return M.protection(s, t, H) end
local s0 = {loginAt = t0, connected = true, lastBeat = t0, beatSeen = true, gameState = "normal"}
eq(prot(s0, t0 + 1).reason, "login", "login protection")
eq(prot(s0, t0 + H.loginSeconds - 1).protected, true, "still at the end of the window")
eq(prot({loginAt = t0, connected = true, lastBeat = t0 + H.loginSeconds, beatSeen = true}, t0 + H.loginSeconds).protected,
	false, "over after loginSeconds")
-- a disconnect: protected at once, pulled after pullSeconds
local s1 = {loginAt = t0 - 100, connected = false, gameState = "normal"}
local lost, reason = M.lost(s1, t0, H)
eq(lost and reason, "disconnect", "no client = disconnect")
M.trackLoss(s1, lost, reason, t0, H)
eq(s1.lostAt, t0, "loss start kept")
local p = prot(s1, t0 + 1)
eq(p.protected and p.reason, "disconnect", "disconnected: protected")
eq(p.pull, false, "not pulled yet")
M.trackLoss(s1, true, "disconnect", t0 + H.pullSeconds, H)
eq(s1.lostAt, t0, "the start does not move")
eq(prot(s1, t0 + H.pullSeconds).pull, true, "pulled after pullSeconds")
s1.pulled = true
eq(prot(s1, t0 + H.pullSeconds + 5).pull, false, "pulled once")
eq(prot(s1, t0 + 999).protected, true, "protected as long as the client is away")
-- back
s1.connected, s1.lastBeat, s1.beatSeen = true, t0 + 1000, true
lost, reason = M.lost(s1, t0 + 1000, H)
M.trackLoss(s1, lost, reason, t0 + 1000, H)
eq(s1.lostAt, nil, "reconnected: loss over")
eq(prot(s1, t0 + 1000).protected, false, "no protection while connected")
-- a ping loss (the client attached but silent)
local s2 = {loginAt = t0 - 100, connected = true, beatSeen = true, lastBeat = t0}
eq(M.lost(s2, t0 + H.pingLossSeconds, H), false, "a late heartbeat within the window")
lost, reason = M.lost(s2, t0 + H.pingLossSeconds + 1, H)
eq(reason, "pingloss", "silence = ping loss")
M.trackLoss(s2, lost, reason, t0 + H.pingLossSeconds + 1, H)
eq(prot(s2, t0 + H.pingLossSeconds + 1).reason, "pingloss", "ping loss protected")
-- no heartbeat ever (an older client): only the disconnect counts
eq(M.lost({connected = true, beatSeen = false, lastBeat = t0}, t0 + 999, H), false, "no heartbeat seen: no ping loss")
-- the ping-loss budget per hour
local s3 = {loginAt = t0 - 9999, connected = true, beatSeen = true}
local tt = t0
for i = 1, H.pingLossPerHour do
	M.trackLoss(s3, true, "pingloss", tt, H)
	eq(s3.budgetOut, false, "ping loss " .. i .. " within the budget")
	M.trackLoss(s3, false, nil, tt + 1, H)
	tt = tt + 60
end
M.trackLoss(s3, true, "pingloss", tt, H)
eq(s3.budgetOut, true, "over the budget")
s3.lastBeat = tt - H.pingLossSeconds - 5
eq(prot(s3, tt).protected, false, "no ping-loss protection over the budget")
s3.connected = false
eq(prot(s3, tt).protected, true, "a real disconnect is still protected")
M.trackLoss(s3, false, nil, tt + 1, H)
M.trackLoss(s3, true, "pingloss", tt + 3700, H)
eq(s3.budgetOut, false, "the budget comes back after an hour")
-- restart: no death while the server closes, nor in the guard window before the daily restart
eq(prot({loginAt = t0 - 999, connected = true, gameState = "closing"}, t0).reason, "restart", "server closing")
eq(prot({loginAt = t0 - 999, connected = true, guard = true}, t0).reason, "restart", "restart guard")
local function at(h, m, sec) return os.time({year = 2026, month = 11, day = 5, hour = h, min = m, sec = sec or 0}) end
local r = {hour = 8, min = 0, notifyMinutes = 5, guardSeconds = 120}
eq(M.restartGuard(at(8, 2, 59), r), false, "before the guard")
eq(M.restartGuard(at(8, 3, 0), r), true, "guard starts 120 s before the shutdown at 08:05")
eq(M.restartGuard(at(8, 5, 30), r), true, "during the shutdown")
eq(M.restartGuard(at(8, 6, 1), r), false, "after it")
eq(M.restartGuard(at(12, 0), r), false, "midday")
eq(M.restartGuard(at(8, 4), nil), false, "no restart configured")
eq(M.restartGuard(os.time({year = 2026, month = 11, day = 5, hour = 23, min = 59}),
	{hour = 23, min = 58, notifyMinutes = 5, guardSeconds = 600}), true, "a shutdown after midnight is seen the day before")
local h, mi = M.parseTime("08:00:00")
eq(h * 100 + mi, 800, "parse HH:MM:SS")
eq(M.parseTime("25:00"), nil, "bad hour")
eq(M.parseTime(nil), nil, "nothing")

-- ---------------------------------------------------------------- ladders
local tabs = M.ladderTabs(mc)
eq(tabs[1].key, "all", "All first")
eq(tabs[#tabs].key, "fallen", "Fallen last")
eq(#tabs, 6, "all + 4 modes + fallen")
eq(M.ladderClause("all", "sm"), "1 = 1", "all")
eq(M.ladderClause("standard", "sm"):find("IS NULL", 1, true) ~= nil, true, "standard includes characters without a row")
eq(M.ladderClause("hc", "sm"):find("`fallen_at` = 0", 1, true) ~= nil, true, "HC ladder: living only")
eq(M.ladderClause("hcssf", "sm"):find("`ssf` = 1", 1, true) ~= nil, true, "HC SSF")
eq(M.ladderClause("fallen", "x"), "x.`fallen_at` > 0", "fallen")
eq(M.ladderClause("drop table"), nil, "unknown tab: no SQL")
eq(M.memberMatches("ssf", SSF), true, "SSF in SSF tab")
eq(M.memberMatches("ssf", HCSSF), false, "HC SSF has its own tab")
eq(M.memberMatches("hc", fl), false, "a fallen one left the HC tab")
eq(M.memberMatches("fallen", fl), true, "and is in Fallen")
eq(M.memberMatches("all", fl), false, "not among the season's living")
eq(M.memberMatches("all", HC), true, "all")
eq(M.lookLine(HCSSF, "He"), "He is playing Hardcore Self-Found.", "look HC SSF")
eq(M.lookLine(STD, "He"), nil, "look standard")
eq(M.lookLine(fl, "You", {level = 88, cause = "killed by a dragon"}), "You fell in Hardcore at level 88 (killed by a dragon).",
	"look fallen")

-- ================================================================ season_modes.lua against a mocked engine
local NOERR, NOTPOSSIBLE = 0, 1
RETURNVALUE_NOERROR, RETURNVALUE_NOTPOSSIBLE, CONTAINER_POSITION = NOERR, NOTPOSSIBLE, 0xFFFF
MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR, COMBAT_HEALING, COMBAT_PHYSICALDAMAGE, SKILL_LEVEL = 1, 2, 64, 1, 8
GAME_STATE_NORMAL, GAME_STATE_SHUTDOWN, ITEM_ATTRIBUTE_TEXT, PLAYERSEX_FEMALE, CONST_ME_TELEPORT = 1, 3, "text", 0, 11
local queries, broadcasts, sent = {}, {}, {}
db = {
	query = function(q) queries[#queries + 1] = q return true end,
	asyncQuery = function(q) queries[#queries + 1] = q end,
	storeQuery = function() return false end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end
}
result = {getNumber = function() return 0 end, free = function() end}
json = {encode = function() return "{}" end}
local gameState = GAME_STATE_NORMAL
local players = {}
Game = {
	getPlayers = function() local out = {} for _, p in pairs(players) do out[#out + 1] = p end return out end,
	broadcastMessage = function(text) broadcasts[#broadcasts + 1] = text end,
	getGameState = function() return gameState end
}
local registered = {callbacks = {}, events = {}, globals = {}}
local function cbObject()
	return setmetatable({}, {__index = {register = function(self) registered.callbacks[#registered.callbacks + 1] = self end}})
end
setmetatable(_G, {__index = function(_, k) if k == "EventCallback" then return cbObject() end end})
local function eventObject(kind)
	return function(name)
		local o = {}
		o.register = function() registered[kind][name] = o end
		o.type = function() end
		o.interval = function() end
		return o
	end
end
CreatureEvent, GlobalEvent = eventObject("events"), eventObject("globals")
ItemType = function() return {isPickupable = function() return true end} end
configManager = {getBoolean = function() return true end, getNumber = function() return 5 end}
configKeys = {}

-- the season side, as season.lua leaves it
local season = {id = 1, name = "Season of Ash", tag = "[S1]"}
local migrated = {}
Chaos = {seasonConfig = cfg, leaderboardConfig = nil,
	select = function() return {} end,
	findPlayer = function(name) return ({Solo = 10, Bob = 20})[name] end,
	send = function(player, opcode, action, data) sent[#sent + 1] = {player = player, action = action, data = data} end,
	decode = function(b) return b end,
	heal = function(c, n) c.health = c.health + n end}
ChaosOpcodes = {season = 246, leaderboard = 229}
ChaosSeason = setmetatable({}, {__index = ChaosSeason})
local S = ChaosSeason
S.members = {[10] = true, [11] = true, [20] = true, [30] = true}
S.ladderCache = {}
S.current = function() return season end
S.realmOf = function(p) return S.members[p:getGuid()] and 1 or 0 end
S.realmOfGuid = function(g) return S.members[g] and 1 or 0 end
S.mailReceiver = ChaosSeason.mailReceiver
S.migrateRow = function(guid, sid, why) migrated[#migrated + 1] = {guid, sid, why} S.members[guid] = nil end

-- engine objects
local function newItem(id, tags, parent)
	local it = {id = id, attrs = {}, parent = parent, children = {}}
	for k, v in pairs(tags or {}) do it.attrs[k] = v end
	function it:isTile() return false end
	function it:isItem() return true end
	function it:getId() return self.id end
	function it:getCustomAttribute(k) return self.attrs[k] end
	function it:setCustomAttribute(k, v) self.attrs[k] = v end
	function it:removeCustomAttribute(k) self.attrs[k] = nil end
	function it:getParent() return self.parent end
	function it:isContainer() return #self.children > 0 or self.container == true end
	function it:getItems() return self.children end
	function it:getAttribute(k) return self.attrs[k] end
	function it:getTopParent()
		local x = self
		while x.parent and not x.parent.isTileObj and not x.parent.isPlayerObj do x = x.parent end
		return x.parent and x.parent.isPlayerObj and x.parent or x
	end
	if parent and parent.children then parent.children[#parent.children + 1] = it end
	return it
end
local function newTile(houseOwner)
	local tile = {isTileObj = true, items = {}}
	function tile:isTile() return true end
	function tile:getHouse() return houseOwner and {getOwnerGuid = function() return houseOwner end} or nil end
	function tile:getTopDownItem() return self.items[#self.items] end
	function tile:getItems() return self.items end
	return tile
end
local tiles = {}
Tile = function(pos) return tiles[pos.x .. ":" .. pos.y] end
local function newPlayer(guid, name, group)
	local p = {guid = guid, id = 1000 + guid, name = name, level = 60, health = 100, ip = 1, isPlayerObj = true, msgs = {},
		events = {}, saved = 0}
	function p:getGuid() return self.guid end
	function p:getId() return self.id end
	function p:getName() return self.name end
	function p:getLevel() return self.level end
	function p:getHealth() return self.health end
	function p:getIp() return self.ip end
	function p:isPlayer() return true end
	function p:isTile() return false end
	function p:isItem() return false end
	function p:getSex() return 1 end
	function p:getGroup() return {getId = function() return group or 1 end} end
	function p:registerEvent(n) self.events[n] = true end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function p:sendCancelMessage(text) self.msgs[#self.msgs + 1] = text end
	function p:save() self.saved = self.saved + 1 end
	function p:getTown() return {getTemplePosition = function() return {x = 1, y = 1, z = 7, sendMagicEffect = function() end} end} end
	function p:teleportTo(pos) self.pos = pos end
	function p:getExperience() return 0 end
	players[guid] = p
	return p
end
Player = function(id) for _, p in pairs(players) do if p.id == id or p.guid == id then return p end end end

dofile("data/scripts/chaos/season_modes.lua")
eq(type(S.modesMove), "function", "hooks installed")
for _, name in ipairs({"ChaosSeasonModesHealth", "ChaosSeasonModesPrepare", "ChaosSeasonModesDeath", "ChaosSeasonModesLogin",
		"ChaosSeasonModesExtended"}) do
	eq(registered.events[name] ~= nil, true, "event " .. name)
end
local function callback(field)
	local out = {}
	for _, cb in ipairs(registered.callbacks) do
		if cb[field] then out[#out + 1] = cb[field] end
	end
	return out[1]
end

local solo = newPlayer(10, "Solo") -- will be Self-Found
local hcp = newPlayer(30, "Grim") -- will be Hardcore
local bob = newPlayer(20, "Bob") -- standard season character
local gm = newPlayer(99, "Gm", 6)

-- the join: the confirmation offers the four modes, the pick is stored
eq(#S.modesChoices(), 4, "choices sent with the confirmation")
eq(S.modesPick("ssf").key, "ssf", "pick")
eq(S.modesPick("nope"), nil, "bad pick")
S.modesJoined(solo, season, S.modesPick("ssf"))
eq(queries[#queries - 1]:find("REPLACE INTO `chaos_season_modes`", 1, true) ~= nil, true, "mode row stored")
S.modesJoined(hcp, season, S.modesPick("hc"))
eq(hcp.events.ChaosSeasonModesHealth, true, "Hardcore events registered at the join")
eq(S.modeFlagsOfGuid(10).key, "ssf", "Solo is SSF")
eq(S.modeFlagsOfGuid(30).key, "hc", "Grim is HC")
local mine = {}
S.modesMine(hcp, mine)
eq(mine.mode, "hc", "window: mode")
eq(mine.heartbeat, mc.hc.heartbeatSeconds, "window: the client sends heartbeats")

-- trade, party, gold, market, orbs
local tradeReq = callback("onTradeRequest")
eq(tradeReq(solo, bob), false, "trade request SSF -> standard refused")
eq(solo.msgs[#solo.msgs], mc.messages.trade, "with the SSF text")
eq(tradeReq(bob, hcp), true, "standard <-> HC trades")
eq(callback("onTradeAccept")(bob, solo), false, "trade accept refused too")
eq(tradeReq(gm, solo), true, "staff exempt")
local party = {getLeader = function() return bob end}
eq(callback("onJoin")(party, solo), false, "SSF joins a standard party: refused")
eq(S.modesTransferBlocked(bob, 10), true, "bank transfer to SSF blocked")
eq(S.modesTransferBlocked(solo, 20), true, "bank transfer from SSF blocked")
eq(S.modesTransferBlocked(bob, 30), false, "standard -> HC fine")
eq(S.modesMarketRefusal(solo, "list"), mc.messages.market, "market listing refused")
eq(S.modesMarketRefusal(solo, "fill"), mc.messages.market, "buy order fill refused")
eq(S.modesMarketRefusal(bob, "list"), nil, "standard market fine")
eq(S.modesOrbRefusal(solo, "place"), mc.messages.orbs, "orb order refused")
eq(select(1, S.modesLootBonus(solo)), mc.ssf.itemFind, "loot bonus")
eq(select(2, S.modesLootBonus(bob)), 0, "no bonus for standard")
eq(S.modesBuffItem(solo, {mode = "ssf"}) ~= nil, true, "SSF buff shown")
eq(S.modesBuffItem(bob, {mode = "ssf"}), nil, "no SSF buff for standard")

-- item moves: the owner tags
local ground = newTile()
tiles["5:5"] = ground
local bobDrop = newItem(2400, {chaos_owner = 20}, ground)
ground.items[#ground.items + 1] = bobDrop
local toInv = {x = CONTAINER_POSITION}
eq(select(2, S.modesMove(solo, bobDrop, toInv, nil)), "loot", "SSF picks up a standard player's drop: refused")
local corpse = newItem(3000, {chaos_owner = 11}, ground)
local inCorpse = newItem(2160, nil, corpse)
eq(select(2, S.modesMove(solo, inCorpse, toInv, nil)), "loot", "SSF loots another's corpse: refused")
corpse.attrs.chaos_owner = 10
eq(S.modesMove(solo, inCorpse, toInv, nil), true, "SSF loots its own corpse")
local mapItem = newItem(2152, nil, ground)
eq(S.modesMove(solo, mapItem, toInv, nil), true, "SSF picks an untagged map item")
local soloDrop = newItem(2400, {chaos_owner = 10}, ground)
eq(select(2, S.modesMove(bob, soloDrop, toInv, nil)), "item", "standard takes an SSF drop: refused")
eq(S.modesMove(gm, soloDrop, toInv, nil), true, "staff exempt")
-- dropped on a tile with a bag on top: it would go into that bag
local bobBag = newItem(1988, {chaos_owner = 20}, ground)
bobBag.container = true
ground.items[#ground.items + 1] = bobBag
local ownItem = newItem(2400, nil, solo)
eq(select(2, S.modesMove(solo, ownItem, {x = 5, y = 5, z = 7}, ground)), "give", "SSF drops into a standard bag: refused")
-- mail
local mailTile = newTile()
mailTile.items = {newItem(2593)}
tiles["6:6"] = mailTile
local letter = newItem(2597, {text = "Solo\nhi"}, bob)
eq(select(2, S.modesMove(bob, letter, {x = 6, y = 6, z = 7}, mailTile)), "mailTo", "mail to an SSF character refused")
local letter2 = newItem(2597, {text = "Bob\nhi"}, solo)
eq(select(2, S.modesMove(solo, letter2, {x = 6, y = 6, z = 7}, mailTile)), "mail", "SSF sends mail: refused")
-- house
local house = newTile(20)
local houseItem = newItem(2400, nil, house)
eq(select(2, S.modesMove(solo, houseItem, toInv, nil)), "house", "SSF takes from another's house: refused")
-- tags after the move
local moved = callback("onItemMoved")
local dropped = newItem(2400, nil, ground)
moved(bob, dropped, 1, {}, {x = 5, y = 5, z = 7}, nil, ground)
eq(dropped.attrs.chaos_owner, 20, "a drop carries its dropper")
dropped.parent = bob
moved(bob, dropped, 1, {}, toInv, nil, bob)
eq(dropped.attrs.chaos_owner, nil, "picked up: untagged")
local depotLocker = newItem(2589, nil, ground)
local depotItem = newItem(2400, nil, depotLocker)
moved(bob, depotItem, 1, {}, toInv, nil, depotLocker)
eq(depotItem.attrs.chaos_owner, nil, "into the own depot: no tag")
-- monster corpses carry their owner
local mcorpse = newItem(3001, nil, ground)
mcorpse.getCorpseOwner = function() return solo.id end
callback("onDropLoot")({}, mcorpse)
eq(mcorpse.attrs.chaos_owner, 10, "corpse owner tag")

-- Hardcore: login protection, a lethal hit, the pull, the restart / shutdown
registered.events.ChaosSeasonModesLogin.onLogin(hcp)
local healthEv = registered.events.ChaosSeasonModesHealth
eq(select(1, healthEv.onHealthChange(hcp, nil, 500, COMBAT_PHYSICALDAMAGE, 0, 0, 0)), 0, "login protection: no damage")
eq(select(1, healthEv.onHealthChange(bob, nil, 500, COMBAT_PHYSICALDAMAGE, 0, 0, 0)), 500, "standard takes damage")
eq(registered.events.ChaosSeasonModesPrepare.onPrepareDeath(hcp, nil), false, "login protection: lethal hit cancelled")
S.hcState[hcp:getId()].loginAt = os.time() - 100
S.hcState[hcp:getId()].lastBeat = os.time()
eq(select(1, healthEv.onHealthChange(hcp, nil, 500, COMBAT_PHYSICALDAMAGE, 0, 0, 0)), 500, "after the window: damage")
eq(registered.events.ChaosSeasonModesPrepare.onPrepareDeath(hcp, nil), true, "after the window: can die")
hcp.ip = 0 -- the client is gone
S.hcState[hcp:getId()].lostAt = os.time() - mc.hc.pullSeconds - 1
eq(registered.events.ChaosSeasonModesPrepare.onPrepareDeath(hcp, nil), false, "disconnected: cannot die")
registered.globals.ChaosSeasonModesWatch.onThink(1000)
eq(hcp.pos and hcp.pos.x, 1, "pulled to the temple")
hcp.ip = 1
local statesSent = 0
S.sendState = function() statesSent = statesSent + 1 end
registered.globals.ChaosSeasonModesWatch.onThink(1000)
eq(statesSent, 1, "reconnected: the state goes out (the client restarts its heartbeat)")
eq(S.hcProtection(hcp).reason, "login", "reconnected: a fresh login protection")
S.hcState[hcp:getId()].loginAt = os.time() - 100
eq(S.hcProtection(hcp).protected, false, "then no protection")
registered.events.ChaosSeasonModesExtended.onExtendedOpcode(hcp, 246, {action = "sync"})
eq(statesSent, 2, "a sync from the client is answered with the state")
gameState = GAME_STATE_SHUTDOWN
eq(S.hcProtection(hcp).reason, "restart", "closing server: protected")
gameState = GAME_STATE_NORMAL
registered.globals.ChaosSeasonModesShutdown.onShutdown()
eq(hcp.saved >= 1, true, "shutdown saves Hardcore characters")
eq(S.hcProtection(hcp).reason, "restart", "and protects them until the end")
S.shutdownGuard = nil
-- the heartbeat
registered.events.ChaosSeasonModesExtended.onExtendedOpcode(hcp, 246, {action = "beat"})
eq(S.hcState[hcp:getId()].beatSeen, true, "heartbeat seen")

-- the fall: a real death of a Hardcore character
local pcorpse = newItem(3058, {chaos_realm = 1}, ground)
local killer = {getName = function() return "Dragon Lord" end, isPlayer = function() return false end}
registered.events.ChaosSeasonModesDeath.onDeath(hcp, pcorpse, killer, killer)
eq(migrated[#migrated][1], 30, "migrated at once")
eq(migrated[#migrated][3], "fallen", "as fallen")
eq(pcorpse.attrs.chaos_realm, 0, "its corpse is in the standard realm (the character can take its items back)")
eq(pcorpse.attrs.chaos_owner, 30, "and is its own")
eq(S.fallenMark(30).level, 60, "fallen mark: level")
eq(S.fallenMark(30).cause, "killed by Dragon Lord", "fallen mark: cause")
eq(S.modeFlagsOfGuid(30).key, "standard", "plays standard now")
eq(broadcasts[#broadcasts]:find("fallen", 1, true) ~= nil, true, "announced")
local fallQuery
for _, q in ipairs(queries) do if q:find("SET `fallen_at`", 1, true) then fallQuery = q end end
eq(fallQuery ~= nil and fallQuery:find("`fallen_at` = 0", 1, true) ~= nil, true, "the fall is written once")
local before = #migrated
registered.events.ChaosSeasonModesDeath.onDeath(hcp, nil, killer, killer)
eq(#migrated, before, "a fallen character does not fall again")
registered.events.ChaosSeasonModesDeath.onDeath(solo, nil, killer, killer)
eq(#migrated, before, "an SSF death is a normal death")

-- end of the season: the mode is reset, survival achievements
local achieved = {}
ChaosAchievements = {set = function(who, key, value) achieved[#achieved + 1] = {who, key, value} end}
Chaos.select = function(q) if q:find("FROM `chaos_season_modes` WHERE `player_id`", 1, true) then
	return {{ssf = 1, hc = 1, fallen_at = 0}} end return {} end
S.modesMigrated(11, 1, "season ended")
eq(achieved[1][2] == "season_hc_survived" or achieved[2][2] == "season_hc_survived", true, "survived the season")
eq(queries[#queries]:find("SET `reset_at`", 1, true) ~= nil, true, "mode reset")

-- ladders: a mode tab
local lbSent
Chaos.leaderboardConfig = {ladder = {key = "ladder"}, boards = {{key = "bounty"}}, rows = 20, resetHour = 6}
ChaosLeaderboard = {nextReset = function(t) return t + 100 end,
	rankedBoard = function() return {{guid = 10, name = "Solo", value = 5}, {guid = 20, name = "Bob", value = 9},
		{guid = 30, name = "Grim", value = 3}} end}
Chaos.send = function(_, _, action, data) lbSent = data end
S.ladderHelpers = {boardTitle = function() return nil end, vocationName = function() return "Knight" end,
	groupOf = function() return {key = 1, ids = {4}} end, where = function() return "1 = 1" end}
eq(S.modesSendBoard(bob, "bounty", nil, "ssf"), true, "answered")
eq(#lbSent.rows, 1, "SSF tab of a weekly board: only SSF")
eq(lbSent.rows[1].name, "Solo", "Solo")
S.modesSendBoard(bob, "bounty", nil, "fallen")
eq(#lbSent.rows, 1, "Fallen tab")
eq(lbSent.rows[1].fallen.level, 60, "with the fall")
S.modesSendBoard(bob, "bounty", nil, "hc")
eq(#lbSent.rows, 0, "HC tab: the fallen one left it")
eq(S.modesSendBoard(bob, "bounty", nil, "bogus"), false, "an unknown tab is not answered")
-- the class ladder: the mode clause joins the season ladder's WHERE; Fallen drops `migrated_at = 0` and sorts by the fall
local lastSql
Chaos.select = function(q) lastSql = q return {{id = 30, name = "Grim", level = 60, vocation = 4, fallen_level = 60,
	fallen_cause = "killed by Dragon Lord"}} end
S.ladderHelpers.where = function() return "sp.`season` = 1 AND sp.`migrated_at` = 0" end
S.modesSendBoard(bob, "ladder", 1, "hc")
eq(lastSql:find("LEFT JOIN `chaos_season_modes` sm", 1, true) ~= nil, true, "ladder joins the modes")
eq(lastSql:find("sm.`hc` = 1 AND sm.`ssf` = 0 AND sm.`fallen_at` = 0", 1, true) ~= nil, true, "HC clause")
S.modesSendBoard(bob, "ladder", 1, "fallen")
eq(lastSql:find("migrated_at", 1, true), nil, "Fallen: migrated characters stay")
eq(lastSql:find("ORDER BY sm.`fallen_level` DESC", 1, true) ~= nil, true, "Fallen: highest fall first")
eq(lbSent.rows[1].fallen.cause, "killed by Dragon Lord", "ladder row carries the fall")
eq(lbSent.season.mode, "fallen", "the tab is echoed")

print(string.format("season_modes_test: OK (%d checks)", checks))
