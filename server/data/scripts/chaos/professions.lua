-- Professions: gathering for the Material Broker and a passive experience bonus (client game_professions, extended opcode
-- ChaosOpcodes.professions = 195). Owner's rule: professions gather materials to sell to NPCs and give an experience
-- bonus; they make no gear and no orbs. Numbers: professions_config.lua; pure logic: professions_core.lua (tests:
-- server/tests/professions_test.lua); overview: server/README.md "Professions".
-- Tables: chaos_professions (levels), chaos_professions_sales (sold today per material) (server/sql/chaos_professions.sql;
-- also created at startup). No player storages: node cooldowns and the angling roll timer are kept in memory.
--
-- How a gather starts (each needs the profession's tool):
--   Delving / Wortcunning  "use" a node item (with the tool in the backpack) or "use with" the stock pick / sickle on it.
--                          Node items are placed at startup on tiles of the areas of the config (per-player cooldown).
--   Flaying                "use with" the obsidian knife on a fresh corpse of a beast or reptile (tagged at the death by
--                          an onDropLoot callback; once per corpse; the corpse owner and the owner's party).
--   Angling                the stock fishing cast itself: data/actions/scripts/tools/fishing.lua calls ChaosProfessions
--                          .onFishCast (one hooked line, tools/install_professions.py); one roll per cfg.angling.rollMs.
-- The stock tool scripts (pick, sickle, skinning) ask ChaosProfessions.onTool first (one hooked line each); it handles only
-- our nodes and tagged corpses and returns false for anything else, so the stock tools work as before.
-- A gather of a node or corpse is a channel on the cast bar (opcode 231, client game_castbar; clicking the bar cancels):
-- moving, attacking or taking damage interrupts it. Then a material of tier min(place, profession, character), profession
-- experience, a little character experience, the weekly board.
--
-- Hooks (guarded; installed at startup and again at login after a /reload):
--   EventCallback onGainExperience (index cfg.bonus.index)  the passive bonus on monster experience
--   EventCallback onDropLoot (index 4)                      flaying tags on beast / reptile corpses
--   ChaosCasting.interrupt                                  wrapped: the cast bar's cancel also cancels a gather
--   ChaosAchievements.set   prof_<key> (level), prof_total (levels of all four together)   achievements_data.lua
--   ChaosLeaderboard.record(cfg.board, player, n, "add")   materials gathered, every minute and at logout
--   ChaosBuffs source "professions" (data/lib/chaos_buffs.lua) calls ChaosProfessions.buffItem
--
-- Protocol (JSON {action, data}; state with Chaos.sendChunked):
--   client -> server  open | close | sell {id, n} | sellAll
--   server -> client  state {profs, bonus, cap, per, tiers, demand, areas, broker, full, capDay, late, nextDay, nextWeek,
--                     respawn} (K.payload) | result {ok, text} | levelup {k, lv}
--   The Material Broker (data/npc/scripts/material_broker.lua, its own Lua state) sends  npc {}: the client opens the
--   window on its Broker tab and asks with open; selling needs a broker within cfg.broker.range tiles (checked here).
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/professions_core.lua")
if not ChaosNpcPlace then
	dofile("data/scripts/chaos/npc_place.lua")
end

Chaos.professionsConfig = dofile("data/scripts/chaos/professions_config.lua")
local cfg = Chaos.professionsConfig
local K = ChaosProfessionsCore
local OPCODE = ChaosOpcodes.professions or cfg.opcode
local T = cfg.tables

ChaosProfessions = ChaosProfessions or {}
local P = ChaosProfessions
P.cfg = cfg
P.idx = K.index(cfg)
local idx = P.idx
P.players = P.players or {} -- guid -> state (kept over /reload scripts)
P.nodes = P.nodes or {} -- "x:y:z" -> {key, prof, tier, id, pos, area}
P.cooldowns = P.cooldowns or {} -- guid -> {node key -> os.time when ready again}
P.channels = P.channels or {} -- creature id -> the gather in progress
P.serial = P.serial or 0
P.offset = P.offset or 0 -- seconds added to the clock (tests)

local FLAY_ATTR, FLAYED_ATTR = "chaos_flay", "chaos_flayed"

local function log(text)
	print("[Chaos professions] " .. text)
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
	return os.time() + (P.offset or 0)
end

local function nowMs()
	return (os.mtime and os.mtime() or os.time() * 1000) + (P.offset or 0) * 1000
end

local function today()
	return K.day(now(), cfg.rollHour)
end

local function week()
	return K.week(now(), cfg.rollHour)
end

local function esc(s)
	return db.escapeString(tostring(s))
end

local function constant(name, fallback)
	local v = rawget(_G, name)
	return v ~= nil and v or fallback
end

-- text: a key (Chaos.t) or a deferred text (ChaosI18n.msg): in the player's language
local function msg(player, text, kind)
	player:sendTextMessage(kind or MESSAGE_INFO_DESCR, Chaos.t(player, text))
end

local function fx(pos, name, fallback)
	local id = constant(name, fallback)
	if id and pos then
		pcall(function() Position(pos.x, pos.y, pos.z):sendMagicEffect(id) end)
	end
end

local function custom(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	if not ok then
		return nil
	end
	if type(v) == "userdata" or type(v) == "table" then
		local ok2, n = pcall(function() return v.value end)
		return ok2 and n or nil
	end
	return v
end

local function posKey(pos)
	return pos.x .. ":" .. pos.y .. ":" .. pos.z
end

local function samePos(a, b)
	return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

local function plural(mat, n)
	return n == 1 and mat.name or mat.plural
end

local function fmtPct(v)
	local s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
	return s
end

-- ---------------------------------------------------------------- database
P.SCHEMA = {
	[[CREATE TABLE IF NOT EXISTS `chaos_professions` (`player_id` int(11) NOT NULL, `prof` varchar(16) NOT NULL,
`level` smallint(5) unsigned NOT NULL DEFAULT 1, `xp` int(11) NOT NULL DEFAULT 0, `gathered` int(11) NOT NULL DEFAULT 0,
PRIMARY KEY (`player_id`, `prof`), CONSTRAINT `chaos_professions_players_fk` FOREIGN KEY (`player_id`)
REFERENCES `players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_professions_sales` (`player_id` int(11) NOT NULL, `item_id` int(11) NOT NULL,
`day` int(11) NOT NULL DEFAULT 0, `sold` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`, `item_id`),
CONSTRAINT `chaos_professions_sales_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE)
ENGINE=InnoDB DEFAULT CHARSET=utf8]]
}

function P.ensureTables()
	for _, q in ipairs(P.SCHEMA) do
		db.query(q)
	end
end

local function load(player)
	local guid = player:getGuid()
	local S = {guid = guid, levels = {}, sales = {}, lb = 0, rollAt = 0, open = false}
	for _, p in ipairs(idx.list) do
		S.levels[p.key] = {level = 1, xp = 0, gathered = 0}
	end
	local rows = Chaos.select(string.format("SELECT `prof`, `level`, `xp`, `gathered` FROM `%s` WHERE `player_id` = %d",
		T.levels, guid), {{"prof", "s"}, {"level", "n"}, {"xp", "n"}, {"gathered", "n"}})
	for _, r in ipairs(rows) do
		if S.levels[r.prof] then
			local e = S.levels[r.prof]
			e.level = math.max(1, math.min(cfg.maxLevel, r.level))
			e.xp = math.max(0, r.xp)
			e.gathered = math.max(0, r.gathered)
		end
	end
	local d = today()
	local sales = Chaos.select(string.format("SELECT `item_id`, `day`, `sold` FROM `%s` WHERE `player_id` = %d", T.sales, guid),
		{{"item_id", "n"}, {"day", "n"}, {"sold", "n"}})
	for _, r in ipairs(sales) do
		if r.day == d then
			S.sales[r.item_id] = {day = r.day, sold = r.sold}
		end
	end
	return S
end

local function levelsOf(S)
	local out = {}
	for key, e in pairs(S.levels) do
		out[key] = e.level
	end
	return out
end

local function refreshBonus(S)
	S.bonus = K.bonusPct(cfg, levelsOf(S))
end

local function stateOf(player)
	local guid = player:getGuid()
	local S = P.players[guid]
	if not S then
		S = load(player)
		refreshBonus(S)
		P.players[guid] = S
	end
	return S
end
P.stateOf = stateOf

local function saveLevel(S, key)
	local e = S.levels[key]
	db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `prof`, `level`, `xp`, `gathered`) VALUES (%d, %s, %d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `level` = VALUES(`level`), `xp` = VALUES(`xp`), `gathered` = VALUES(`gathered`)", T.levels,
		S.guid, esc(key), e.level, e.xp, e.gathered))
	e.dirty = nil
end

local function flush(S)
	for key, e in pairs(S.levels) do
		if e.dirty then
			saveLevel(S, key)
		end
	end
end

local function flushBoard(player, S)
	if S.lb > 0 and ChaosLeaderboard and ChaosLeaderboard.record then
		local n = S.lb
		S.lb = 0
		pcall(ChaosLeaderboard.record, cfg.board, player or {guid = S.guid}, n, "add")
	end
end

local function soldToday(S, id)
	local s = S.sales[id]
	if s and s.day == today() then
		return s.sold
	end
	return 0
end

-- ---------------------------------------------------------------- achievements and the buff bar
local function setAchievements(player, S)
	if not (ChaosAchievements and ChaosAchievements.set) then
		return
	end
	local total = 0
	for _, p in ipairs(idx.list) do
		local lv = S.levels[p.key].level
		total = total + lv
		pcall(ChaosAchievements.set, player, "prof_" .. p.key, lv)
	end
	pcall(ChaosAchievements.set, player, "prof_total", total)
end

-- the buff bar's passive entry (chaos_buffs.lua source "professions"): nil while the bonus is 0
function P.buffItem(player, def)
	local S = P.players[player:getGuid()]
	if not S or not S.bonus or S.bonus <= 0 then
		return nil
	end
	local parts = {}
	for _, p in ipairs(idx.list) do
		parts[#parts + 1] = p.name .. " " .. S.levels[p.key].level
	end
	return {pct = S.bonus, name = "Profession Mastery +" .. fmtPct(S.bonus) .. "%",
		desc = "+" .. fmtPct(S.bonus) .. "% experience from monsters (" .. table.concat(parts, ", ") .. "; at most +" ..
			fmtPct(cfg.bonus.cap) .. "%)."}
end

-- ---------------------------------------------------------------- the broker
local function brokerNear(player)
	local pos = player:getPosition()
	local r = cfg.broker.range
	for _, c in ipairs(Game.getSpectators(pos, false, false, r, r, r, r) or {}) do
		if c:isNpc() and c:getName():lower() == cfg.broker.npc:lower() then
			return true
		end
	end
	return false
end
P.brokerNear = brokerNear

P.demandCache = P.demandCache or {}
function P.demand()
	local w = week()
	if not P.demandCache[w] then
		P.demandCache = {[w] = K.demand(cfg, w, idx)}
	end
	return P.demandCache[w]
end

-- ---------------------------------------------------------------- places and nodes
local function townNear(pos)
	local best, bestD
	for _, t in ipairs(Game.getTowns and Game.getTowns() or {}) do
		local tp = t:getTemplePosition()
		local d = math.abs(tp.x - pos.x) + math.abs(tp.y - pos.y)
		if not bestD or d < bestD then
			best, bestD = t:getName(), d
		end
	end
	return best
end

local function tileFree(x, y, z)
	local tile = Tile(Position(x, y, z))
	if not tile or not tile:getGround() then
		return false
	end
	if tile:hasFlag(TILESTATE_PROTECTIONZONE) or tile:hasFlag(TILESTATE_TELEPORT) or tile:hasFlag(TILESTATE_FLOORCHANGE)
			or tile:getHouse() then
		return false
	end
	if tile:hasProperty(CONST_PROP_BLOCKSOLID) or tile:hasProperty(CONST_PROP_BLOCKPATH) then
		return false
	end
	return #(tile:getItems() or {}) == 0
end
P.tileFree = tileFree

local function nodeOnTile(pos, id)
	local tile = Tile(Position(pos.x, pos.y, pos.z))
	return tile and tile:getItemById(id) or nil
end

-- put the node items of one area on the map (again: an existing node item is kept); returns how many it holds
function P.placeArea(area)
	local rand = K.rng(K.seedOf(area.key))
	-- a tile that holds this area's node already counts as free, so a second call picks the same spots again
	local spots = K.pickSpots(area, cfg, function(x, y, z)
		local nd = P.nodes[x .. ":" .. y .. ":" .. z]
		if nd then
			return nd.area == area.key
		end
		return tileFree(x, y, z)
	end, rand)
	-- nodes already registered for this area stay (a second call adds only what is missing)
	local n = 0
	for prof, list in pairs(spots) do
		local def = idx.nodeOf[prof][area.tier]
		for _, s in ipairs(list) do
			local key = posKey(s)
			if not nodeOnTile(s, def.id) then
				Game.createItem(def.id, 1, Position(s.x, s.y, s.z))
			end
			P.nodes[key] = {key = key, prof = prof, tier = area.tier, id = def.id, pos = s, area = area.key}
		end
	end
	for _, nd in pairs(P.nodes) do
		if nd.area == area.key then
			n = n + 1
		end
	end
	return n
end

function P.placeNodes()
	local total = 0
	for _, area in ipairs(cfg.areas) do
		total = total + (try("place " .. area.key, P.placeArea, area) or 0)
	end
	P.townOf = {}
	for _, area in ipairs(cfg.areas) do
		P.townOf[area.key] = try("town", townNear, area.center)
	end
	return total
end

-- a runtime area (staff tests, events): registered and placed at once
function P.addArea(area)
	for i, a in ipairs(cfg.areas) do
		if a.key == area.key then
			table.remove(cfg.areas, i)
			break
		end
	end
	cfg.areas[#cfg.areas + 1] = area
	idx.area[area.key] = area
	P.townOf = P.townOf or {}
	P.townOf[area.key] = try("town", townNear, area.center)
	return P.placeArea(area)
end

local function cooldownLeft(S, key)
	local cd = P.cooldowns[S.guid]
	local at = cd and cd[key]
	if at and at > now() then
		return at - now()
	end
	return 0
end

local function areaRows(S)
	local rows = {}
	for _, area in ipairs(cfg.areas) do
		local total, ready = {}, {}
		for _, nd in pairs(P.nodes) do
			if nd.area == area.key then
				total[nd.prof] = (total[nd.prof] or 0) + 1
				if cooldownLeft(S, nd.key) == 0 then
					ready[nd.prof] = (ready[nd.prof] or 0) + 1
				end
			end
		end
		if area.fishing then
			total.angling = total.angling or 1
			ready.angling = 1
		end
		rows[#rows + 1] = {area = area, total = total, ready = ready, town = P.townOf and P.townOf[area.key]}
	end
	return rows
end

-- ---------------------------------------------------------------- the window
function P.send(player)
	local S = stateOf(player)
	local have, sold = {}, {}
	P.cid = P.cid or {}
	for _, m in ipairs(cfg.materials) do
		have[m.id] = player:getItemCount(m.id)
		sold[m.id] = soldToday(S, m.id)
		if not P.cid[m.id] then
			local it = ItemType(m.id)
			P.cid[m.id] = it and it:getClientId() or 0
		end
	end
	local t = now()
	local view = {levels = S.levels, charLevel = player:getLevel(), demand = P.demand(), sold = sold, have = have, cid = P.cid,
		areas = areaRows(S), broker = brokerNear(player), nextDay = K.nextDay(t, cfg.rollHour) - t,
		nextWeek = K.nextWeek(t, cfg.rollHour) - t}
	Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = K.payload(cfg, idx, view)}))
end

local function result(player, ok, text)
	text = text and Chaos.tx(player, text) or text
	Chaos.send(player, OPCODE, "result", {ok = ok and true or false, text = text})
	if text and text ~= "" then
		player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_STATUS_DEFAULT, text)
	end
	return ok
end

-- ---------------------------------------------------------------- rewards
local function giveMaterial(player, id, count)
	local before = player:getItemCount(id)
	player:addItem(id, count, false)
	local got = player:getItemCount(id) - before
	local rest = count - got
	if rest > 0 then
		local inbox = player:getInbox()
		if inbox then
			inbox:addItem(id, rest)
			msg(player, ChaosI18n.msg("Your backpack is full: %s went to your inbox.", rest), MESSAGE_STATUS_SMALL)
		end
	end
	return count
end

-- r = K.resolve(...) result
function P.reward(player, S, prof, r)
	local p = idx.prof[prof]
	local e = S.levels[prof]
	local mat = r.mat
	if r.count > 0 then
		giveMaterial(player, mat.id, r.count)
		e.gathered = e.gathered + r.count
		S.lb = S.lb + r.count
	end
	local before = e.level
	local gained = K.addXp(cfg, e, r.xp)
	e.dirty = true
	local exp = K.charXp(cfg, player:getLevel())
	pcall(function() player:addExperience(exp, true) end)
	if r.count > 0 then
		msg(player, ChaosI18n.msg("You gathered %d %s (+%d %s experience).", r.count, plural(mat, r.count), r.xp, p.name))
	else
		msg(player, ChaosI18n.msg("Nothing worth keeping (+%d %s experience).", r.xp, p.name), MESSAGE_STATUS_SMALL)
	end
	if gained > 0 then
		refreshBonus(S)
		saveLevel(S, prof)
		fx(player:getPosition(), "CONST_ME_FIREWORK_YELLOW", 29)
		msg(player, ChaosI18n.msg("You advanced to %s level %d. Profession experience bonus: +%s%%.", p.name, e.level,
			fmtPct(S.bonus)), MESSAGE_EVENT_ADVANCE)
		Chaos.send(player, OPCODE, "levelup", {k = prof, lv = e.level, from = before})
		setAchievements(player, S) -- the buff bar's entry follows S.bonus on its next look (every second)
	end
	if S.open then
		try("send", P.send, player)
	end
end

-- ---------------------------------------------------------------- the channel
local function castbar(player, action, data)
	local op = ChaosOpcodes.castbar or 231
	pcall(Chaos.send, player, op, action, data)
end

function P.interrupt(player, reason, text)
	local ch = P.channels[player:getId()]
	if not ch then
		return false
	end
	P.channels[player:getId()] = nil
	castbar(player, "end", {s = ch.serial, r = reason})
	if text then
		player:sendCancelMessage(Chaos.tx(player, text))
	end
	return true
end

local function finish(player, ch)
	P.channels[player:getId()] = nil
	local S = stateOf(player)
	local g = {prof = ch.prof, placeTier = ch.tier, profLevel = S.levels[ch.prof].level, charLevel = player:getLevel()}
	if ch.node then
		local nd = P.nodes[ch.node]
		if not nd or not nodeOnTile(nd.pos, nd.id) then
			castbar(player, "end", {s = ch.serial, r = "failed"})
			return player:sendCancelMessage(Chaos.t(player, "The vein is gone."))
		end
		P.cooldowns[S.guid] = P.cooldowns[S.guid] or {}
		P.cooldowns[S.guid][ch.node] = now() + cfg.respawnMin * 60
		-- a countdown over the node for this character only, until it is ready for them again (tilebars.lua)
		if ChaosTileBars and ChaosTileBars.set and Chaos.tileBarsConfig and Chaos.tileBarsConfig.professions then
			ChaosTileBars.set("prof:" .. S.guid .. ":" .. ch.node, {pos = nd.pos, label = "Ready in",
				endsIn = cfg.respawnMin * 60, color = "#7fb069", owner = player})
		end
	elseif ch.corpse then
		local corpse = P.findCorpse(ch.pos, ch.corpse)
		if not corpse then
			castbar(player, "end", {s = ch.serial, r = "failed"})
			return player:sendCancelMessage(Chaos.t(player, "The corpse is gone."))
		end
		corpse:setCustomAttribute(FLAYED_ATTR, 1)
		g.chance = cfg.flaying.chance
	end
	castbar(player, "end", {s = ch.serial, r = "done"})
	local p = idx.prof[ch.prof]
	fx(ch.pos, p.fx, 3)
	P.reward(player, S, ch.prof, K.resolve(cfg, idx, g, math.random))
end

local function tick(pid, serial)
	local ch = P.channels[pid]
	if not ch or ch.serial ~= serial then
		return
	end
	local player = Player(pid)
	if not player then
		P.channels[pid] = nil
		return
	end
	if not samePos(player:getPosition(), ch.from) then
		return P.interrupt(player, "moved", "You moved: gathering is interrupted.")
	end
	if ch.hurt or player:getTarget() then
		return P.interrupt(player, "failed", "Combat interrupts gathering.")
	end
	local t = nowMs()
	if t >= ch.endMs then
		return try("finish", finish, player, ch)
	end
	if t >= ch.fxAt then
		ch.fxAt = t + 1000
		fx(ch.pos, idx.prof[ch.prof].fx, 3)
	end
	addEvent(tick, 200, pid, serial)
end

-- ctx = {prof, tier, pos (the target), node = key | corpse = tag}
function P.startChannel(player, ctx)
	local pid = player:getId()
	if P.channels[pid] then
		return result(player, false, "You are already gathering.")
	end
	if player:getTarget() then
		return result(player, false, "Stop attacking first.")
	end
	if ChaosCasting and ChaosCasting.active and ChaosCasting.active[pid] then
		return result(player, false, "You are casting a spell.")
	end
	local p = idx.prof[ctx.prof]
	P.serial = P.serial + 1
	local t = nowMs()
	local ch = {serial = P.serial, prof = ctx.prof, tier = ctx.tier, pos = ctx.pos, node = ctx.node, corpse = ctx.corpse,
		from = player:getPosition(), endMs = t + p.channelMs, fxAt = t + 1000}
	P.channels[pid] = ch
	castbar(player, "start", {s = ch.serial, n = p.verb, ms = p.channelMs})
	fx(ctx.pos, p.fx, 3)
	addEvent(tick, 200, pid, ch.serial)
	return true
end

-- ---------------------------------------------------------------- gather entry points
local function hasTool(player, prof)
	for _, id in ipairs(idx.prof[prof].tools) do
		if player:getItemCount(id) > 0 then
			return true
		end
	end
	return false
end

local function toolFits(itemId, prof)
	for _, k in ipairs(idx.tool[itemId] or {}) do
		if k == prof then
			return true
		end
	end
	return false
end

local function near(player, pos)
	local pp = player:getPosition()
	return pp.z == pos.z and math.abs(pp.x - pos.x) <= 1 and math.abs(pp.y - pos.y) <= 1
end

function P.gatherNode(player, nodeItem, pos)
	if not cfg.enabled then
		return false
	end
	local def = idx.node[nodeItem:getId()]
	local p = idx.prof[def.prof]
	local S = stateOf(player)
	pos = pos or nodeItem:getPosition()
	if not near(player, pos) then
		return result(player, false, "Stand next to it.")
	end
	local key = posKey(pos)
	if not P.nodes[key] then -- a node item that was not placed by the areas (staff): its own tier, its own cooldown
		P.nodes[key] = {key = key, prof = def.prof, tier = def.tier, id = def.id, pos = {x = pos.x, y = pos.y, z = pos.z}}
	end
	local left = cooldownLeft(S, key)
	if left > 0 then
		return result(player, false, string.format("You took what you could from this %s. It is ready for you again in %d:%02d.",
			p.noun, math.floor(left / 60), left % 60))
	end
	local e = S.levels[def.prof]
	local tier = K.gatherTier(cfg, def.tier, e.level, player:getLevel())
	if tier < def.tier and e.level < cfg.tiers[def.tier].profLevel then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, "With %s %d you only get %s materials here (%s %d for more).",
			p.name, e.level, cfg.tiers[tier].name:lower(), p.name, cfg.tiers[def.tier].profLevel))
	end
	return P.startChannel(player, {prof = def.prof, tier = def.tier, pos = pos, node = key})
end

function P.findCorpse(pos, tag)
	local tile = Tile(Position(pos.x, pos.y, pos.z))
	for _, it in ipairs(tile and tile:getItems() or {}) do
		if tonumber(custom(it, FLAY_ATTR)) == tag and not custom(it, FLAYED_ATTR) then
			return it
		end
	end
	return nil
end

local function canLoot(player, corpse)
	if ChaosLootFilter and ChaosLootFilter.canLoot then
		return ChaosLootFilter.canLoot(player, corpse)
	end
	local owner = corpse:getCorpseOwner()
	return owner == 0 or owner == player:getId()
end

function P.flay(player, corpse, pos)
	local tag = tonumber(custom(corpse, FLAY_ATTR))
	if not tag then
		return false
	end
	if custom(corpse, FLAYED_ATTR) then
		return result(player, false, "This corpse was flayed already.")
	end
	if not near(player, pos) then
		return result(player, false, "Stand next to it.")
	end
	if not canLoot(player, corpse) then
		return result(player, false, "You are not the owner.")
	end
	return P.startChannel(player, {prof = "flaying", tier = tag % 10, pos = {x = pos.x, y = pos.y, z = pos.z}, corpse = tag})
end

-- the stock tool scripts (pick, sickle, skinning) call this first; true = handled here
function P.onTool(player, item, target, toPosition)
	if not cfg.enabled or not item or (type(target) ~= "userdata" and type(target) ~= "table") then
		return false
	end
	local okItem, isItem = pcall(function() return target:isItem() end)
	if not okItem or not isItem then
		return false
	end
	local id = target:getId()
	local def = idx.node[id]
	if def then
		if not toolFits(item:getId(), def.prof) then
			result(player, false, "Use " .. idx.prof[def.prof].toolName .. " on it.")
			return true
		end
		try("gather", P.gatherNode, player, target, toPosition)
		return true
	end
	if toolFits(item:getId(), "flaying") and custom(target, FLAY_ATTR) then
		try("flay", P.flay, player, target, toPosition)
		return true
	end
	return false
end

-- one stock fishing cast on fishable water (the hooked line in fishing.lua): the Angling roll
function P.onFishCast(player, item, target, toPosition)
	if not cfg.enabled then
		return
	end
	local S = stateOf(player)
	local t = nowMs()
	if t < (S.rollAt or 0) then
		return
	end
	S.rollAt = t + cfg.angling.rollMs
	local tier = K.fishingPlace(cfg, toPosition)
	local e = S.levels.angling
	local r = K.resolve(cfg, idx, {prof = "angling", placeTier = tier, profLevel = e.level, charLevel = player:getLevel(),
		chance = cfg.angling.chance}, math.random)
	if r.count == 0 then
		return
	end
	fx(toPosition, "CONST_ME_WATERSPLASH", 2)
	P.reward(player, S, "angling", r)
end

-- ---------------------------------------------------------------- selling
local function sellOne(player, S, mat, want, quiet)
	local have = player:getItemCount(mat.id)
	local n = math.min(have, want or have)
	if n <= 0 then
		return 0, 0
	end
	local mult = P.demand()[mat.id] or 1
	local sold = soldToday(S, mat.id)
	local q = K.quote(cfg, mat, mult, sold, n)
	if q.units <= 0 then
		if not quiet then
			result(player, false, string.format("The broker takes no more %s today (%d a day).", mat.plural, cfg.broker.capPerDay))
		end
		return 0, 0
	end
	if not player:removeItem(mat.id, q.units) then
		return 0, 0
	end
	player:setBankBalance(player:getBankBalance() + q.gold)
	local d = today()
	S.sales[mat.id] = {day = d, sold = sold + q.units}
	db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `item_id`, `day`, `sold`) VALUES (%d, %d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `day` = VALUES(`day`), `sold` = VALUES(`sold`)", T.sales, S.guid, mat.id, d, sold + q.units))
	return q.units, q.gold
end

function P.sell(player, id, n)
	if not brokerNear(player) then
		return result(player, false, "Sell to a Material Broker: one stands next to every temple (in Cinderhold in the teleport room's market).")
	end
	local mat = idx.mat[tonumber(id) or 0]
	if not mat then
		return false
	end
	local S = stateOf(player)
	local units, gold = sellOne(player, S, mat, Chaos.toInt(n, 1, 100000))
	if units > 0 then
		result(player, true, string.format("Sold %d %s for %d gold (to your bank account).", units, plural(mat, units), gold))
	end
	return units > 0
end

function P.sellAll(player)
	if not brokerNear(player) then
		return result(player, false, "Sell to a Material Broker: one stands next to every temple (in Cinderhold in the teleport room's market).")
	end
	local S = stateOf(player)
	local units, gold = 0, 0
	for _, mat in ipairs(cfg.materials) do
		local u, g = sellOne(player, S, mat, nil, true)
		units, gold = units + u, gold + g
	end
	if units == 0 then
		return result(player, false, "Nothing the broker takes today.")
	end
	return result(player, true, string.format("Sold %d materials for %d gold (to your bank account).", units, gold))
end

-- ---------------------------------------------------------------- broker placement
function P.placeBrokers()
	local towns = {}
	if cfg.broker.towns == "all" then
		towns = Game.getTowns and Game.getTowns() or {}
	else
		for _, t in ipairs(cfg.broker.towns) do
			towns[#towns + 1] = Town(t)
		end
	end
	local placed, missed = 0, {}
	for _, town in ipairs(towns) do
		local temple = town and town:getTemplePosition()
		if temple and try("place broker", ChaosNpcPlace.place, cfg.broker.npc, temple, cfg.broker.offsets, cfg.broker.place) then
			placed = placed + 1
		else
			missed[#missed + 1] = town and town:getName() or "?"
		end
	end
	if #missed > 0 then
		log("no Material Broker at " .. table.concat(missed, ", ") .. " (no free tile near the temple, or data/npc/" ..
			cfg.broker.npc .. ".xml is missing: tools/install_professions.py)")
	end
	return placed
end

-- ---------------------------------------------------------------- hooks
local function familyOf(monster)
	local name = (Chaos.monsterTypeName and Chaos.monsterTypeName(monster) or monster:getName()):lower()
	P.families = P.families or {}
	local fam = P.families[name]
	if fam == nil then
		if not ChaosBestiaryCore then
			pcall(dofile, "data/scripts/chaos/bestiary_core.lua")
		end
		Chaos.bestiaryConfig = Chaos.bestiaryConfig or dofile("data/scripts/chaos/bestiary_config.lua")
		local ok, cat = pcall(ChaosBestiaryCore.categoryOf, name, nil, false, false, Chaos.bestiaryConfig)
		fam = ok and cat or false
		P.families[name] = fam
	end
	return fam or nil, name
end

local function monsterLevel(monster)
	local mt = monster:getType()
	local okE, exp = pcall(function() return mt:experience() end)
	local okH, hp = pcall(function() return mt:maxHealth() end)
	if ChaosBestiaryCore and ChaosBestiaryCore.estimateLevel then
		return ChaosBestiaryCore.estimateLevel({exp = okE and exp or 0, health = okH and hp or 0}, Chaos.bestiaryConfig)
	end
	return 1
end

-- tag a fresh corpse of a beast / reptile for flaying: serial x 10 + tier
function P.tagCorpse(monster, corpse)
	if not cfg.enabled or not corpse or not monster or monster:getMaster() then
		return
	end
	local fam, name = familyOf(monster)
	if not fam or not cfg.flaying.families[fam] or cfg.flaying.exclude[name] then
		return
	end
	P.serial = P.serial + 1
	corpse:setCustomAttribute(FLAY_ATTR, P.serial * 10 + K.flayTier(cfg, monsterLevel(monster)))
end

function P.installHooks()
	if ChaosCasting and ChaosCasting.interrupt and not ChaosCasting.professionsWrapped then
		local orig = ChaosCasting.interrupt
		ChaosCasting.interrupt = function(player, reason, ...)
			local r = orig(player, reason, ...)
			if reason == "cancel" and player then
				pcall(P.interrupt, player, "cancel", "Gathering cancelled.")
			end
			return r
		end
		ChaosCasting.professionsWrapped = true
	end
end

-- ---------------------------------------------------------------- events
local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	if cfg.enabled and source and source.isMonster and source:isMonster() and not source:getMaster() then
		local S = P.players[self:getGuid()]
		if S and S.bonus and S.bonus > 0 then
			return K.applyBonus(exp, S.bonus)
		end
	end
	return exp
end
xpCb:register(cfg.bonus.index) -- after the world experience buff (5), before the dungeon / rift caps (90, 100)

local drop = EventCallback
drop.onDropLoot = function(self, corpse)
	try("tag", P.tagCorpse, self, corpse)
end
drop:register(4) -- after the stock loot (0), the Chaos loot layer (1), blessings (2) and autoloot (3)

local startup = GlobalEvent("ChaosProfessionsStartup")
function startup.onStartup()
	P.ensureTables()
	P.installHooks()
	for _, p in ipairs(K.validate(cfg)) do
		log("config: " .. p)
	end
	if cfg.enabled then
		addEvent(function()
			log(P.placeBrokers() .. " Material Broker(s) placed")
		end, 1600)
		addEvent(function()
			log(P.placeNodes() .. " gathering node(s) placed")
		end, 2200)
	end
	return true
end
startup:register()

local login = CreatureEvent("ChaosProfessionsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosProfessionsExtended")
	player:registerEvent("ChaosProfessionsLogout")
	player:registerEvent("ChaosProfessionsHurt")
	P.installHooks()
	local S = try("load", stateOf, player)
	if S then
		try("achievements", setAchievements, player, S)
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosProfessionsLogout")
function logout.onLogout(player)
	P.channels[player:getId()] = nil
	local S = P.players[player:getGuid()]
	if S then
		flush(S)
		try("board", flushBoard, player, S)
		P.players[player:getGuid()] = nil
	end
	return true
end
logout:type("logout")
logout:register()

local hurt = CreatureEvent("ChaosProfessionsHurt")
function hurt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= COMBAT_HEALING and ((primaryDamage or 0) > 0 or (secondaryDamage or 0) > 0) then
		local ch = P.channels[creature:getId()]
		if ch then
			ch.hurt = true
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
hurt:type("healthchange")
hurt:register()

local think = GlobalEvent("ChaosProfessionsFlush")
function think.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		local S = P.players[player:getGuid()]
		if S then
			flush(S)
			try("board", flushBoard, player, S)
		end
	end
	return true
end
think:interval(60000)
think:register()

-- plain "use" of a node item: gathers with the tool from the backpack
local nodeAction = Action()
function nodeAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local def = idx.node[item:getId()]
	if not def then
		return false
	end
	if not hasTool(player, def.prof) then
		local p = idx.prof[def.prof]
		return result(player, false, string.format("You need %s for %s (Material Brokers sell them).", p.toolName, p.name)) or true
	end
	try("gather", P.gatherNode, player, item, fromPosition)
	return true
end
for _, n in ipairs(cfg.nodes) do
	nodeAction:id(n.id)
end
nodeAction:register()

local ext = CreatureEvent("ChaosProfessionsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE or not cfg.enabled then
		return
	end
	local m = Chaos.decode(buffer)
	if not m or type(m.action) ~= "string" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "professions", cfg.requestMs) then
		return
	end
	local d = type(m.data) == "table" and m.data or {}
	local S = stateOf(player)
	if m.action == "open" then
		S.open = true
	elseif m.action == "close" then
		S.open = false
		return
	elseif m.action == "sell" then
		try("sell", P.sell, player, d.id, d.n)
	elseif m.action == "sellAll" then
		try("sellAll", P.sellAll, player)
	else
		return
	end
	try("send", P.send, player)
end
ext:type("extendedopcode")
ext:register()

-- staff: /professions Name, delving, 50   (set a level)   /professions Name   (show)   /professions nodes   (place again)
local talk = TalkAction("/professions")
function talk.onSay(player, words, param)
	if player:getGroup():getId() < cfg.staffGroup then
		return false
	end
	if param:match("^%s*nodes%s*$") then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s gathering nodes on the map.", P.placeNodes()))
		return false
	end
	local name, key, value = param:match("^%s*([^,]+),%s*(%w+),%s*(%d+)%s*$")
	local target = Player(name or param:match("^%s*(.-)%s*$"))
	if not target then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/professions <online character>[, <profession>, <level>] | /professions nodes")
		return false
	end
	local S = stateOf(target)
	if key then
		local e = S.levels[key]
		if not e then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Unknown profession %s.", key))
			return false
		end
		e.level, e.xp, e.dirty = math.max(1, math.min(cfg.maxLevel, tonumber(value))), 0, true
		refreshBonus(S)
		flush(S)
		setAchievements(target, S)
	end
	local parts = {}
	for _, p in ipairs(idx.list) do
		parts[#parts + 1] = p.name .. " " .. S.levels[p.key].level
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, target:getName() .. ": " .. table.concat(parts, ", ") .. "; bonus +" ..
		fmtPct(S.bonus) .. "%")
	if S.open then
		P.send(target)
	end
	return false
end
talk:separator(" ")
talk:register()
