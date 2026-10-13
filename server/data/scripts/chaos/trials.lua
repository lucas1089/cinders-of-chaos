-- trials.lua: the Vocation Trials (design, node table and rules: TRIALS.md; numbers: trials_config.lua; special nodes:
-- trials_nodes.lua; maths: trials_core.lua; combat effects of the nodes: trials_effects.lua).
--
-- A Trial is a solo, runtime-built arena (its own slot grid, built with Game.createTile as the rifts and the ascension
-- trial do) with the theme of the vocation's class family: waves and a boss (Warrior, Ranger, Monk, Necromancer,
-- Templar), elemental seals and a boss (Mystic), marked targets against the clock and a boss (Thief). Three
-- difficulties, Normal / Cruel / Merciless; the first clear of a tier opens one pair of special nodes for that vocation.
-- Of each pair the character holds one node (trials_nodes.lua). The nodes are NOT passive points: they are stored here
-- (storages), summed into the passive bonus table (ChaosTrials.addBonuses, called by passivetree.lua) and kept through
-- the tree's resets.
--
-- Protocol (opcode 65, the passive tree's, through ChaosPassiveTree.extraActions):
--   client -> server  trialRequest                    -> trialState
--                     trialChoose {pair, side}        side 1 / 2 / 0 (give the pair up) -> trialState, a message
--                     trialEnter {tier}               starts the run (same checks as the Keeper's window)
--                     trialLeave                      leaves the run (fails it, no cooldown)
--   server -> client  {"action":"trialState","data":ChaosTrialsCore.clientState}
--                     {"action":"sendMessage","data":{title, message}}   (the tree's message box)
-- The run HUD is the rift HUD (opcode ChaosOpcodes.rift: start / update / end).
--
-- Deaths: a lethal hit is caught (no death, no experience or item loss); it costs one of the shared lives, the player
-- is healed and put back at the start with a short shield; no life left fails the run. Nothing is lost on a failed
-- run; a failed attempt closes the door for failCooldownSeconds. Logging out, leaving the room, the time limit all fail it.
-- A server stop or crash inside a run: the marker storage is found at the next login, the character is moved out and no
-- cooldown is applied (the attempt does not count).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosTrialsCore then
	dofile("data/scripts/chaos/trials_core.lua")
end
if not ChaosClasses then
	dofile("data/scripts/chaos/classes.lua")
end
dofile("data/lib/chaos_dark_paint.lua")

ChaosTrials = ChaosTrials or {}
local T = ChaosTrials
local M = ChaosTrialsCore

Chaos.registerInstance("trials", {label = "a trial", inside = function(player)
	return T.runs ~= nil and T.runs[player:getId()] ~= nil
end, at = function(pos)
	return M.slotAt(pos) ~= nil
end, runs = function() -- /instances (instance_limits.lua)
	local out, ms = {}, os.mtime and os.mtime() or os.time() * 1000
	for pid, tr in pairs(T.runs or {}) do
		local p = Player(pid)
		out[#out + 1] = {id = pid, what = string.format("%s, %s, slot %d, %s", p and p:getName() or "?", tr.tierDef.name, tr.slot,
			tr.over and "ending" or tr.phase), left = not tr.over and math.max(0, math.floor((tr.deadline - ms) / 1000)) or nil,
			players = p and 1 or 0}
	end
	return out
end, close = function(id) -- ended without a cooldown or a reward, back where the trial began ("Nothing is lost")
	if T.runs and T.runs[id] and not T.runs[id].over and T.finish then
		T.finish(id, "abort", "A gamemaster closed the trial.")
		return true, "Trial of player " .. id .. " closed."
	end
	return false, "No running trial " .. tostring(id) .. "."
end})
local OPCODE = ChaosOpcodes.passivetree
local RIFT_OPCODE = ChaosOpcodes.rift

T.runs = T.runs or {} -- player id -> run
T.slotBusy = T.slotBusy or {} -- slot -> player id
T.built = T.built or {}
T.bad = T.bad or {}
T.monsterRun = T.monsterRun or {} -- monster id -> player id
T.fast = T.fast or {} -- player id -> true: a GM shortened the next run (boss health 1)
T.hooks = T.hooks or {}

local function C()
	return Chaos.trials
end
local function S()
	return C().storage
end
local function P(t)
	return Position(t.x, t.y, t.z)
end
local function log(text)
	print("[ChaosTrials] " .. text)
end
local function mnow()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- ======================================================================== storage
local function getS(player, key)
	return player:getStorageValue(key)
end

local function vocId(player)
	local v = player:getVocation()
	return v and v:getId() or 0
end

function T.tierCleared(player, voc)
	return M.clearedTier(math.max(0, getS(player, S().tierBase + (voc or vocId(player)))))
end

function T.picks(player, voc)
	return M.unpack(math.max(0, getS(player, S().picksBase + (voc or vocId(player)))))
end

local function tokens(player)
	return math.max(0, getS(player, S().tokens))
end

local function weekCount(player)
	if getS(player, S().weekKey) ~= M.weekKey() then
		return 0
	end
	return math.max(0, getS(player, S().weekCount))
end

local function inCombat(player)
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
end

local function inProtectionZone(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function achievement(player, fn, key, amount)
	if ChaosAchievements and ChaosAchievements[fn] then
		pcall(ChaosAchievements[fn], player, key, amount)
	end
end

local function box(player, title, text)
	Chaos.send(player, OPCODE, "sendMessage", {title = title, message = text})
end

-- ======================================================================== the passive bonus table
-- passivetree.lua applyBonuses calls this for every apply (login, save, reset): the held nodes of the vocation are
-- summed into `bonuses` (trial keys are read by trials_effects.lua, tree keys by passivetree_effects.lua)
function T.addBonuses(player, bonuses)
	local voc = vocId(player)
	if not M.family(voc) then
		return
	end
	local tier, picks = T.tierCleared(player, voc), T.picks(player, voc)
	local held = M.heldNodes(voc, tier, picks)
	if #held == 0 then
		return
	end
	for key, v in pairs(M.effects(voc, tier, picks)) do
		bonuses[key] = (bonuses[key] or 0) + v
	end
	bonuses.trialNodes = #held
end

function T.refresh(player)
	if ChaosPassiveTree and ChaosPassiveTree.apply then
		ChaosPassiveTree.apply(player)
	end
end

-- ======================================================================== the client's state
function T.state(player)
	local voc = vocId(player)
	local tr = T.runs[player:getId()]
	return M.clientState({voc = voc, level = player:getLevel(), tier = T.tierCleared(player, voc), picks = T.picks(player, voc),
		tokens = tokens(player), cooldown = getS(player, S().cooldown), now = os.time(), running = tr and not tr.over or nil,
		repeatsLeft = math.max(0, C().reward.repeatsPerWeek - weekCount(player))})
end

function T.sendState(player)
	Chaos.send(player, OPCODE, "trialState", T.state(player))
end

-- ======================================================================== choosing and switching
local function pay(player, gold)
	if gold <= 0 then
		return true
	end
	if player.removeTotalMoney then
		return player:removeTotalMoney(gold)
	end
	return player:removeMoney(gold)
end

-- ok, text
function T.choose(player, pair, side)
	if not C().enabled then
		return false, "The Vocation Trials are closed."
	end
	local voc = vocId(player)
	if not M.family(voc) then
		return false, "Your vocation has no trial."
	end
	if T.runs[player:getId()] then
		return false, "You cannot change your nodes during a trial."
	end
	local state = {tier = T.tierCleared(player, voc), picks = T.picks(player, voc), tokens = tokens(player), level = player:getLevel()}
	local plan, why = M.planPick(state, pair, side)
	if not plan then
		return false, why
	end
	if not plan.free then
		if inCombat(player) then
			return false, "You cannot change a held node in combat."
		end
		if tokens(player) < plan.tokens then
			return false, "You need a Trial Token."
		end
		if not pay(player, plan.gold) then
			return false, string.format("Changing a node costs %d gold coins and a Trial Token.", plan.gold)
		end
		player:setStorageValue(S().tokens, tokens(player) - plan.tokens)
		achievement(player, "progress", C().achievements.switches, 1)
	end
	local picks = state.picks
	picks[plan.pair] = plan.side
	player:setStorageValue(S().picksBase + voc, M.pack(picks))
	T.refresh(player)
	local count = #M.heldNodes(voc, state.tier, picks)
	achievement(player, "set", C().achievements.nodes, count)
	local node = plan.side > 0 and M.nodeById(M.nodeId(voc, plan.pair, plan.side))
	if not node then
		return true, "The choice was given up" .. (plan.free and "." or string.format(" (1 Trial Token and %d gold coins).", plan.gold))
	end
	return true, string.format("%s is yours%s.", node.name, plan.free and "" or string.format(" (1 Trial Token and %d gold coins)", plan.gold))
end

-- ======================================================================== the room
local function groundId(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local function placeItem(pos, id)
	local tile = Tile(pos)
	if tile and not tile:getItemById(id) then
		return Game.createItem(id, 1, pos)
	end
	return tile and tile:getItemById(id)
end

local function darkRoom()
	local r = C().room
	if r.darkActive ~= nil then
		return r.darkActive
	end
	r.darkActive = false
	local d = r.dark
	if d and d.enabled and ChaosDarkPaint and ChaosDarkTiles and ChaosDarkPaint.ready(d.style) then
		local wall, basin = ChaosDarkTiles.id(d.wall), ChaosDarkTiles.id(d.basin)
		if wall and basin then
			r.wallId, r.basinId, r.darkActive = wall, basin, true
		end
	end
	return r.darkActive
end

function T.buildSlot(slot)
	local dark = darkRoom()
	local L = M.layout(slot)
	if T.built[slot] then
		return L
	end
	if T.bad[slot] then
		return nil, T.bad[slot]
	end
	if not Game.createTile then
		return nil, "Game.createTile is missing"
	end
	local r = C().room
	for _, list in ipairs({L.floor, L.walls}) do
		for _, f in ipairs(list) do
			local tile = Tile(P(f))
			local gid = tile and groundId(tile)
			if tile and ((gid ~= r.groundId and not (dark and ChaosDarkPaint.isDark(gid))) or (tile.getHouse and tile:getHouse())) then
				T.bad[slot] = string.format("tile %d,%d,%d already exists in the map", f.x, f.y, f.z)
				log("slot " .. slot .. ": " .. T.bad[slot])
				return nil, T.bad[slot]
			end
		end
	end
	for _, list in ipairs({L.floor, L.walls}) do
		for _, f in ipairs(list) do
			local pos = P(f)
			local tile = Tile(pos) or Game.createTile(pos, true)
			if tile and not tile:getGround() then
				Game.createItem(r.groundId, 1, pos)
			end
		end
	end
	for _, f in ipairs(L.walls) do
		placeItem(P(f), r.wallId)
	end
	for _, f in ipairs(L.basins) do
		placeItem(P(f), r.basinId)
	end
	if dark then
		local walls = {}
		for _, f in ipairs(L.walls) do
			walls[f.x .. "," .. f.y] = true
		end
		local reserved = {L.center, L.playerStart, L.bossStart}
		for _, s in ipairs(L.seals) do
			reserved[#reserved + 1] = s
		end
		for _, b in ipairs(L.basins) do
			reserved[#reserved + 1] = b
		end
		ChaosDarkPaint.apply(ChaosDarkPaint.plan(L.floor, r.dark.style, math.random, {walls = walls, reserved = reserved}), L.z)
	end
	T.built[slot] = true
	return L
end

local function cleanSlot(L)
	local r = C().room
	local keep = {[r.groundId] = true, [r.wallId] = true, [r.basinId] = true}
	for _, f in ipairs(L.floor) do
		local tile = Tile(P(f))
		if tile then
			for _, c in ipairs(tile:getCreatures() or {}) do
				if c:isMonster() then
					T.monsterRun[c:getId()] = nil
					c:remove()
				end
			end
			for _, item in ipairs(tile:getItems() or {}) do
				local id = item:getId()
				if not keep[id] and not (r.darkActive and ChaosDarkPaint.isDark(id)) then
					item:remove()
				end
			end
		end
	end
end

local function freeSlot()
	for slot = 1, C().room.grid.slots do
		if not T.slotBusy[slot] and not T.bad[slot] then
			return slot
		end
	end
	return nil
end

-- ======================================================================== HUD (the rift HUD)
local function secondsLeft(tr)
	return math.max(0, math.floor((tr.deadline - mnow()) / 1000))
end

local function hudData(tr, state)
	local boss = tr.bossState
	return {title = "Vocation Trial - " .. tr.tierDef.name, theme = tr.fam.name, left = secondsLeft(tr), limit = tr.limit,
		total = tr.total, killed = math.min(tr.killed, tr.total), bossAt = tr.total, boss = boss, state = state or "running",
		bossName = tr.fam.boss.name, mods = {}, notes = tr.notes or {}, lives = tr.lives, livesMax = tr.livesMax, tier = tr.tier}
end

local function sendHud(tr, action, state)
	local player = Player(tr.pid)
	if player then
		Chaos.send(player, RIFT_OPCODE, action, hudData(tr, state))
	end
end

local function say(tr, text)
	local p = Player(tr.pid)
	if p then
		p:sendTextMessage(MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR, text)
	end
end

-- ======================================================================== monsters
local function dress(monster, look, name)
	if name and monster.rename then
		monster:rename(name, "the " .. name)
	end
	if look then
		local o = monster:getOutfit()
		for k, v in pairs(look) do
			o[k] = v
		end
		monster:setOutfit(o)
	end
end

local function setHealth(monster, hp)
	monster:setMaxHealth(hp)
	local missing = hp - monster:getHealth()
	if missing > 0 then
		Chaos.heal(monster, missing)
	end
end

local function heal(player)
	Chaos.heal(player, player:getMaxHealth() - player:getHealth())
	player:addMana(player:getMaxMana() - player:getMana())
end

-- a random floor tile of the room (not on its edge) between minDist and maxDist tiles from `from` (king moves). Monsters only
-- notice a player within their view (about 8 x 6 tiles), so thralls are made within 6 of the player.
local function randomFar(tr, from, minDist, maxDist)
	local L = tr.L
	for _ = 1, 60 do
		local pos = {x = math.random(L.x1 + 1, L.x2 - 1), y = math.random(L.y1 + 1, L.y2 - 1), z = L.z}
		local d = math.max(math.abs(pos.x - from.x), math.abs(pos.y - from.y))
		if d >= (minDist or 0) and d <= (maxDist or 99) then
			return pos
		end
	end
	return {x = L.center.x, y = L.center.y - 4, z = L.z}
end

local function spawnThrall(tr, pos, hp, opts)
	local f = tr.fam
	local m = Game.createMonster("Trial Thrall", P(pos), true, true)
	if not m then
		return nil
	end
	dress(m, f.add.look, f.add.name)
	setHealth(m, hp)
	local bonus = f.add.speed or 0
	if bonus > 0 and tr.stage and (tr.stage.kind == "wave" or (opts and opts.fast)) then
		m:changeSpeed(bonus * ((opts and opts.fast) and 3 or 2))
	end
	m:registerEvent("ChaosTrialMonsterDeath")
	T.monsterRun[m:getId()] = tr.pid
	tr.adds[m:getId()] = true
	m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	local p = Player(tr.pid)
	if p and m.selectTarget then
		m:selectTarget(p)
	end
	return m
end

local function aliveAdds(tr)
	local n = 0
	for id in pairs(tr.adds) do
		if Monster(id) then
			n = n + 1
		else
			tr.adds[id] = nil
		end
	end
	return n
end

local function removeMonsters(tr)
	local ids = {}
	for id in pairs(tr.adds) do
		ids[#ids + 1] = id
	end
	if tr.bossId then
		ids[#ids + 1] = tr.bossId
	end
	for _, id in ipairs(ids) do
		local m = Monster(id)
		if m then
			m:remove()
		end
	end
	for id, pid in pairs(T.monsterRun) do
		if pid == tr.pid then
			T.monsterRun[id] = nil
		end
	end
end

-- ======================================================================== the run
local finish

local function eventsOn(player)
	player:registerEvent("ChaosTrialPrepareDeath")
	player:registerEvent("ChaosTrialLogout")
end

local function eventsOff(player)
	player:unregisterEvent("ChaosTrialPrepareDeath")
end

local function startStage(tr)
	tr.stageIdx = tr.stageIdx + 1
	local stage = tr.stages[tr.stageIdx]
	local player = Player(tr.pid)
	if not stage or not player then
		return
	end
	tr.stage = stage
	tr.stageStart = mnow()
	local pos = player:getPosition()
	if stage.kind == "wave" then
		tr.waveNo = (tr.waveNo or 0) + 1
		tr.notes = {string.format("Wave %d of %d.", tr.waveNo, tr.waveCount)}
		for _ = 1, tr.scale.waveSize do
			local at = randomFar(tr, pos, 4, 6)
			if not spawnThrall(tr, at, tr.scale.addHp) then
				tr.total = tr.total - 1 -- could not be made: it does not count
			end
		end
		say(tr, string.format("Wave %d of %d.", tr.waveNo, tr.waveCount))
	elseif stage.kind == "seals" then
		tr.seal = {index = 1, charge = 0}
		tr.sealOrder = M.sealOrder(stage.count, math.random)
		tr.nextHarass = mnow() + 8000
		say(tr, "The seals burn. Break them in the order the Keeper names, standing on each until it gives.")
	elseif stage.kind == "marks" then
		tr.markIdx = 0
		tr.markId = nil
		say(tr, "Marked targets come one after another. Kill each before it slips away.")
	elseif stage.kind == "boss" then
		local scale = tr.scale
		local m = Game.createMonster("Trial Warden", P(tr.L.bossStart), false, true)
		if not m then
			log("cannot create Trial Warden (is data/monster/monsters/chaos/trials registered?)")
			finish(tr.pid, "error", "The guardian did not answer the call. Nothing is lost; please tell the staff.")
			return
		end
		dress(m, tr.fam.boss.look, tr.fam.boss.name)
		setHealth(m, T.fast[tr.pid] and 200 or scale.hp)
		m:registerEvent("ChaosTrialMonsterDeath")
		T.monsterRun[m:getId()] = tr.pid
		tr.bossId = m:getId()
		tr.bossState = "alive"
		tr.bossStarted = mnow()
		tr.nextAdd = mnow() + C().addEvery
		tr.nextZone = mnow() + C().zoneEvery
		m:getPosition():sendMagicEffect(CONST_ME_MORTAREA)
		if m.selectTarget then
			m:selectTarget(player)
		end
		tr.notes = {tr.fam.boss.name .. " awakens."}
		say(tr, tr.fam.boss.name .. " awakens. " .. tr.fam.story)
	end
	sendHud(tr, "update")
end

local function nextStage(tr)
	if tr.over then
		return
	end
	if tr.stageIdx >= #tr.stages then
		return
	end
	startStage(tr)
end

local function spawnMark(tr)
	local player = Player(tr.pid)
	if not player then
		return
	end
	tr.markIdx = tr.markIdx + 1
	local at = randomFar(tr, player:getPosition(), 5, 6)
	local m = spawnThrall(tr, at, math.max(50, math.floor(tr.scale.addHp * 0.6)), {fast = true})
	if m then
		tr.markId = m:getId()
		tr.markDeadline = mnow() + tr.tierDef.markSeconds * 1000
		m:getPosition():sendMagicEffect(CONST_ME_MAGIC_RED)
	end
	tr.notes = {string.format("Mark %d of %d: %d s.", tr.markIdx, tr.stage.count, tr.tierDef.markSeconds)}
end

-- a share of the maximum health; a Hollow Vessel counts health + maximum energy shield (Chaos.percentBase)
local function hurt(tr, player, share, effect)
	local g = tr.bossId and Monster(tr.bossId)
	local dmg = math.max(1, math.floor(Chaos.percentBase(player) * share))
	tr.raw = true
	pcall(doTargetCombat, g or 0, player, COMBAT_PHYSICALDAMAGE, -dmg, -dmg, effect or CONST_ME_GROUNDSHAKER, ORIGIN_SPELL)
	tr.raw = false
end
T.hurt = hurt -- tests

local function spawnBossAdds(tr, player)
	local c = C()
	local boss = tr.bossId and Monster(tr.bossId)
	local at = boss and boss:getPosition() or P(tr.L.bossStart)
	for _ = 1, math.min(c.addCount, c.addMax - aliveAdds(tr)) do
		local pos = {x = at.x + math.random(-2, 2), y = at.y + math.random(-2, 2), z = at.z}
		if not M.inRoom(tr.L, pos) then
			pos = tr.L.center
		end
		spawnThrall(tr, pos, tr.scale.addHp)
	end
	say(tr, tr.fam.boss.name .. " calls for aid!")
end

local function zones(tr, player)
	local c = C()
	local center = player:getPosition()
	local list = M.zoneTiles({x = center.x, y = center.y, z = center.z}, c.zoneCount, c.zoneRadius, math.random)
	local marked = {}
	for _, z in ipairs(list) do
		if M.inRoom(tr.L, z) then
			local pos = P(z)
			pos:sendMagicEffect(CONST_ME_MAGIC_RED or CONST_ME_FIREAREA)
			marked[#marked + 1] = pos
		end
	end
	local pid, share = tr.pid, tr.tierDef.zoneShare
	addEvent(function()
		local cur, p = T.runs[pid], Player(pid)
		if cur ~= tr or tr.over or not p then
			return
		end
		local here = p:getPosition()
		for _, pos in ipairs(marked) do
			pos:sendMagicEffect(CONST_ME_FIREAREA)
			if pos.x == here.x and pos.y == here.y and pos.z == here.z then
				hurt(tr, p, share, CONST_ME_FIREAREA)
			end
		end
	end, c.zoneDelay)
end

local function pyre(tr, player)
	local c = C()
	local safes = {}
	for _ = 1, c.pyreSafe do
		safes[#safes + 1] = randomFar(tr, tr.L.center, 0)
	end
	for _, s in ipairs(safes) do
		P(s):sendMagicEffect(CONST_ME_HOLYAREA)
	end
	say(tr, "The fire gathers! Stand next to a sanctuary light.")
	local pid, share = tr.pid, tr.tierDef.pyreShare
	addEvent(function()
		local cur, p = T.runs[pid], Player(pid)
		if cur ~= tr or tr.over or not p then
			return
		end
		for x = tr.L.x1, tr.L.x2, 2 do
			for y = tr.L.y1, tr.L.y2, 3 do
				P({x = x, y = y, z = tr.L.z}):sendMagicEffect(CONST_ME_FIREAREA)
			end
		end
		if not M.pyreSafe(p:getPosition(), safes) then
			hurt(tr, p, share, CONST_ME_FIREAREA)
		end
	end, c.pyreWarn)
end

local SEAL_FX = {fire = "FIREAREA", ice = "ICEAREA", energy = "ENERGYAREA", earth = "POISONAREA"}
local function sealEffect(element)
	return _G["CONST_ME_" .. SEAL_FX[element]] or CONST_ME_MAGIC_BLUE
end

local function sealNote(tr)
	local idx = math.min(tr.seal.index, #tr.sealOrder)
	local el = M.SEAL_ELEMENTS[tr.sealOrder[idx]]
	tr.notes = {string.format("Seal %d of %d: break the %s seal.", idx, #tr.sealOrder, el:upper())}
end

local function tickSeals(tr, player, ms, pos)
	local L = tr.L
	for i, seal in ipairs(L.seals) do
		P(seal):sendMagicEffect(sealEffect(M.SEAL_ELEMENTS[i]))
	end
	local stand
	for i, seal in ipairs(L.seals) do
		if seal.x == pos.x and seal.y == pos.y then
			stand = i
		end
	end
	local before = tr.seal.index
	local r = M.sealStep(tr.seal, tr.sealOrder, stand, C().tickMs)
	if r == "done" then
		pos:sendMagicEffect(CONST_ME_HOLYAREA)
		say(tr, string.format("The %s seal breaks.", M.SEAL_ELEMENTS[stand]))
		tr.killed = tr.seal.index - 1
		if tr.seal.index > #tr.sealOrder then
			tr.notes = {"The seals are broken."}
			addEvent(function()
				if T.runs[tr.pid] == tr and not tr.over then
					nextStage(tr)
				end
			end, 1200)
			tr.stage = {kind = "seals-done"}
		else
			sealNote(tr)
		end
		sendHud(tr, "update")
	elseif r == "wrong" then
		say(tr, "The wrong seal rebukes you!")
		hurt(tr, player, C().sealPenaltyShare, CONST_ME_ENERGYHIT or CONST_ME_FIREAREA)
	elseif before == 1 and tr.seal.index == 1 and tr.notes and not tr.notes[1] then
		sealNote(tr)
	end
	if ms >= (tr.nextHarass or 0) and aliveAdds(tr) < 2 then
		tr.nextHarass = ms + 12000
		spawnThrall(tr, randomFar(tr, pos, 4, 6), tr.scale.addHp)
	end
end

local function tickMarks(tr, player, ms)
	if not tr.markId and tr.markIdx >= tr.stage.count then
		if not tr.stage.done then
			tr.stage.done = true
			local stage = tr.stage
			addEvent(function()
				if T.runs[tr.pid] == tr and not tr.over and tr.stage == stage then
					nextStage(tr)
				end
			end, 1200)
		end
		return
	end
	if not tr.markId and tr.markIdx < tr.stage.count then
		spawnMark(tr)
		sendHud(tr, "update")
		return
	end
	if tr.markId then
		local m = Monster(tr.markId)
		if not m then
			tr.markId = nil
		elseif ms >= tr.markDeadline then
			m:getPosition():sendMagicEffect(CONST_ME_POFF)
			T.monsterRun[tr.markId] = nil
			tr.adds[tr.markId] = nil
			m:remove()
			tr.markId = nil
			tr.deadline = tr.deadline - M.cfg().markPenaltySeconds * 1000
			tr.markIdx = tr.markIdx - 1 -- it comes back
			say(tr, string.format("The mark got away! %d seconds are lost.", C().markPenaltySeconds))
			spawnMark(tr)
			sendHud(tr, "update")
		else
			local left = math.ceil((tr.markDeadline - ms) / 1000)
			tr.notes = {string.format("Mark %d of %d: %d s.", tr.markIdx, tr.stage.count, left)}
		end
	end
end

local function tick(pid)
	local tr = T.runs[pid]
	if not tr or tr.over then
		return
	end
	local c = C()
	local player = Player(pid)
	if not player then
		finish(pid, "logout")
		return
	end
	local pos = player:getPosition()
	if not M.inRoom(tr.L, pos) then
		finish(pid, "left", "You left the trial.")
		return
	end
	local ms = mnow()
	if tr.phase == "fight" then
		if ms >= tr.deadline then
			finish(pid, "time", "Time is up: the trial is lost.")
			return
		end
		if ChaosInstanceLimits then -- warnings before the end (instance_limits.lua)
			ChaosInstanceLimits.warn(tr, math.floor((tr.deadline - ms) / 1000), {player}, "Trial", C().limits)
		end
		for id in pairs(tr.adds) do -- thralls that lost their target take the player again
			local m = Monster(id)
			if m and m.getTarget and not m:getTarget() and m.selectTarget then
				m:selectTarget(player)
			end
		end
		local stage = tr.stage
		if stage then
			if stage.kind == "seals" then
				tickSeals(tr, player, ms, pos)
			elseif stage.kind == "marks" then
				tickMarks(tr, player, ms)
			elseif stage.kind == "wave" then
				if aliveAdds(tr) == 0 and (tr.pendingRise or 0) == 0 and not stage.done then
					stage.done = true
					addEvent(function()
						if T.runs[pid] == tr and not tr.over then
							nextStage(tr)
						end
					end, 1500)
				end
			elseif stage.kind == "boss" then
				local boss = tr.bossId and Monster(tr.bossId)
				if boss and boss.getTarget and not boss:getTarget() and boss.selectTarget then
					boss:selectTarget(player)
				end
				if M.hasMech(tr.famKey, "stillness") then
					local r = M.stillness(tr.still, pos.x .. ":" .. pos.y, ms)
					if r == "warn" then
						pos:sendMagicEffect(CONST_ME_STONES or CONST_ME_POFF)
						say(tr, "The ground trembles under you. Move!")
					elseif r == "slam" then
						hurt(tr, player, tr.tierDef.stillShare, CONST_ME_GROUNDSHAKER)
					end
				end
				if M.hasMech(tr.famKey, "adds") and ms >= tr.nextAdd then
					tr.nextAdd = ms + c.addEvery
					spawnBossAdds(tr, player)
				end
				if M.hasMech(tr.famKey, "zones") and ms >= tr.nextZone then
					tr.nextZone = ms + c.zoneEvery
					zones(tr, player)
				end
			end
		end
		if M.hasMech(tr.famKey, "pyre") and ms >= (tr.nextPyre or 0) then
			tr.nextPyre = ms + c.pyreEvery
			pyre(tr, player)
		end
		if ms >= (tr.nextHud or 0) then
			tr.nextHud = ms + c.hud.everySeconds * 1000
			sendHud(tr, "update")
		end
	end
	addEvent(tick, c.tickMs, pid)
end

local function beginFight(pid)
	local tr = T.runs[pid]
	if not tr or tr.over then
		return
	end
	tr.phase = "fight"
	tr.deadline = mnow() + tr.limit * 1000
	tr.nextPyre = mnow() + 5000
	startStage(tr)
end

-- ======================================================================== finishing
local function giveStack(player, id, count)
	if count <= 0 then
		return false
	end
	local rest = count - Chaos.giveItem(player, id, count)
	if rest <= 0 then
		return false
	end
	local inbox = player:getInbox()
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
	return true
end

-- pays and records a clear; returns the outcome (M.clearOutcome) for the message
local function reward(player, tr)
	local c = C()
	local voc = tr.voc
	local before = T.tierCleared(player, voc)
	local out = M.clearOutcome(tr.tier, player:getLevel(), before, tokens(player), weekCount(player))
	if out.first then
		player:setStorageValue(S().tierBase + voc, tr.tier)
	end
	if out.counted then
		player:setStorageValue(S().weekKey, M.weekKey())
		player:setStorageValue(S().weekCount, weekCount(player) + 1)
	end
	if out.tokens > 0 then
		player:setStorageValue(S().tokens, tokens(player) + out.tokens)
	end
	if out.gold > 0 then
		player:setBankBalance(player:getBankBalance() + out.gold)
	end
	local inbox = giveStack(player, c.reward.items.chaos, out.chaos)
	inbox = giveStack(player, c.reward.items.divine, out.divine) or inbox
	out.inbox = inbox
	player:setStorageValue(S().runs, math.max(0, getS(player, S().runs)) + 1)
	achievement(player, "progress", c.achievements.runs, 1)
	achievement(player, "set", c.achievements.tier .. "_" .. tr.tier, 1)
	if out.first then
		T.refresh(player)
	end
	return out
end

local function clearMarker(player)
	if getS(player, S().marker) > 0 then
		player:setStorageValue(S().marker, 0)
		player:save()
	end
end

-- how: "won" | "death" (no lives) | "time" | "left" | "logout" | "error" | "abort"
function finish(pid, how, text)
	local tr = T.runs[pid]
	if not tr or tr.over then
		return
	end
	tr.over = true
	local player = Player(pid)
	removeMonsters(tr)
	local exitDelay = 0
	if player then
		eventsOff(player)
		heal(player)
		player:removeCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT)
		clearMarker(player)
		if how == "won" then
			local out = reward(player, tr)
			local lines = {}
			if out.first then
				local list = M.pairsOf(tr.voc)
				lines[#lines + 1] = string.format("First clear on %s: the %s pair of nodes opens (%s or %s).", tr.tierDef.name,
					({"first", "second", "third"})[tr.tier], list[tr.tier].a.name, list[tr.tier].b.name)
			else
				lines[#lines + 1] = "Cleared again: +" .. out.tokens .. " Trial Token" .. (out.tokens == 1 and "" or "s") .. "."
			end
			if out.gold > 0 then
				lines[#lines + 1] = string.format("%d gold coins to your bank, %d Orb(s) of Upheaval, %d Orb(s) of Fate%s.", out.gold, out.chaos,
					out.divine, out.inbox and " (some in your inbox)" or "")
			elseif not out.first then
				lines[#lines + 1] = "The weekly repeat rewards are used up; the token is yours."
			end
			for _, l in ipairs(lines) do
				player:sendTextMessage(MESSAGE_EVENT_ADVANCE, l)
			end
			player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)
			exitDelay = C().exitSeconds * 1000
			T.sendState(player)
			Chaos.send(player, RIFT_OPCODE, "end", {result = "success", text = lines[1] or "", exitIn = C().exitSeconds})
		else
			local fail = how == "error" and (text or "The trial could not begin. Nothing is lost.")
				or ((text or "You have failed the trial.") .. " Nothing is lost.")
			if how ~= "error" and how ~= "logout" and how ~= "abort" then
				player:setStorageValue(S().cooldown, os.time() + C().enter.failCooldownSeconds)
			end
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, fail)
			Chaos.send(player, RIFT_OPCODE, "end", {result = "failed", text = fail})
			T.sendState(player)
		end
	end
	local back, slot = tr.back, tr.slot
	addEvent(function()
		local p = Player(pid)
		if p and M.slotAt(p:getPosition()) == slot then
			p:teleportTo(back)
			back:sendMagicEffect(CONST_ME_TELEPORT)
			p:removeCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT)
		end
		T.runs[pid] = nil
		if T.slotBusy[slot] == pid then
			T.slotBusy[slot] = nil
		end
		cleanSlot(tr.L)
		if ChaosInstanceLimits then
			ChaosInstanceLimits.freed("trials", "the trial chambers")
		end
	end, exitDelay)
end
T.finish = finish

local function loseLife(pid)
	local tr = T.runs[pid]
	local player = Player(pid)
	if not tr or tr.over or not player then
		return
	end
	tr.fallen = false
	if tr.phase ~= "fight" then
		return
	end
	tr.lives = tr.lives - 1
	if tr.lives <= 0 then
		finish(pid, "death", "You have fallen with no lives left.")
		return
	end
	heal(player)
	player:teleportTo(P(tr.L.playerStart))
	P(tr.L.playerStart):sendMagicEffect(CONST_ME_TELEPORT)
	tr.shieldUntil = mnow() + C().shieldSeconds * 1000
	tr.still = {}
	say(tr, string.format("You fall! %d %s left. The monsters cannot touch you for %d seconds.", tr.lives,
		tr.lives == 1 and "life" or "lives", C().shieldSeconds))
	sendHud(tr, "update")
end

-- ======================================================================== combat hooks (called by trials_effects.lua)
T.hooks.preHit = function(player, attacker, pd, pt, sd, st, origin)
	local tr = T.runs[player:getId()]
	if not tr or tr.over or tr.raw or not attacker or not attacker:isMonster() then
		return pd, sd
	end
	if T.monsterRun[attacker:getId()] ~= tr.pid then
		return pd, sd
	end
	if mnow() < (tr.shieldUntil or 0) then
		return 0, 0
	end
	local isBoss = attacker:getId() == tr.bossId
	local share = isBoss and tr.scale.hit or tr.scale.addHit
	if isBoss and M.hasMech(tr.famKey, "enrage") then
		local max = attacker:getMaxHealth()
		if max > 0 and attacker:getHealth() / max < C().enrageBelow then
			share = share * C().enrageMult
		end
	end
	-- a share of the maximum health; a Hollow Vessel counts health + maximum energy shield (Chaos.percentBase)
	local amount = math.max(1, math.floor(Chaos.percentBase(player) * share * (0.85 + math.random() * 0.3)))
	return -amount, 0
end

T.hooks.catch = function(player, attacker, pd, pt, sd, st, origin)
	local tr = T.runs[player:getId()]
	if not tr or tr.over then
		return pd, sd
	end
	local sign = (pd < 0 or (pd == 0 and sd < 0)) and -1 or 1
	local p = math.abs(pd)
	local s = (st == COMBAT_HEALING) and 0 or math.abs(sd)
	-- a fallen player (the life is taken one tick later) cannot be hurt again: several hits in one tick cost one life
	if tr.fallen then
		return 0, 0
	end
	local cp, cs, caught = M.catchDamage(player:getHealth(), p, s)
	if caught and tr.phase == "fight" then
		tr.fallen = true
		addEvent(loseLife, 0, tr.pid)
	end
	return sign * cp, (st == COMBAT_HEALING) and sd or sign * cs
end

-- ======================================================================== monster deaths
local deathEvent = CreatureEvent("ChaosTrialMonsterDeath")
function deathEvent.onDeath(creature, corpse, killer, mostDamageKiller)
	local id = creature:getId()
	local pid = T.monsterRun[id]
	T.monsterRun[id] = nil
	local tr = pid and T.runs[pid]
	if not tr or tr.over then
		return true
	end
	if id == tr.bossId then
		tr.bossId = nil
		tr.bossState = "dead"
		-- anti-abuse: the boss must have been fought (at least a few seconds), the player alive and in the room
		local p = Player(pid)
		if p and p:getHealth() > 0 and M.inRoom(tr.L, p:getPosition()) and mnow() - (tr.bossStarted or 0) >= 1500 then
			addEvent(finish, 0, pid, "won")
		else
			addEvent(finish, 0, pid, "error", "The trial ended in an odd way. Nothing is lost.")
		end
		return true
	end
	if tr.adds[id] then
		tr.adds[id] = nil
		local pos = creature:getPosition()
		if id == tr.markId then
			tr.markId = nil
			tr.killed = tr.killed + 1
			tr.notes = {string.format("Mark %d of %d down.", tr.markIdx, tr.stage and tr.stage.count or 0)}
			sendHud(tr, "update")
		elseif tr.stage and tr.stage.kind == "wave" then
			tr.killed = tr.killed + 1
		end
		if M.hasMech(tr.famKey, "rise") and not tr.risen[id] and M.roll(C().riseChance) and tr.bossState ~= "dead" then
			tr.pendingRise = (tr.pendingRise or 0) + 1
			local at = {x = pos.x, y = pos.y, z = pos.z}
			addEvent(function()
				local cur = T.runs[pid]
				if cur ~= tr or tr.over then
					return
				end
				tr.pendingRise = math.max(0, (tr.pendingRise or 1) - 1)
				local m = spawnThrall(tr, at, math.max(50, math.floor(tr.scale.addHp * C().riseHp)))
				if m then
					tr.risen[m:getId()] = true
					m:getPosition():sendMagicEffect(CONST_ME_MORTAREA)
				end
			end, C().riseDelayMs)
		end
	end
	return true
end
deathEvent:register()

-- the safety net: whatever got past the health event
local prepare = CreatureEvent("ChaosTrialPrepareDeath")
function prepare.onPrepareDeath(creature, killer)
	local tr = T.runs[creature:getId()]
	if not tr then
		return true
	end
	if creature:getHealth() < 1 then
		Chaos.heal(creature, 1)
	end
	if not tr.fallen then
		tr.fallen = true
		addEvent(loseLife, 0, tr.pid)
	end
	return false
end
prepare:register()

-- ======================================================================== entering
local function otherRun(player)
	if ChaosRift and ChaosRift.isInside and ChaosRift.isInside(player) then
		return "a rift"
	end
	if ChaosAscensionQuest and ChaosAscensionQuest.trials and ChaosAscensionQuest.trials[player:getId()] then
		return "the Trial of Ascension"
	end
	if M.slotAt(player:getPosition()) then
		return "a trial"
	end
	return nil
end

-- ok, text
function T.enter(player, tierIdx, opts)
	opts = opts or {}
	local c = C()
	if not c.enabled then
		return false, "The Vocation Trials are closed."
	end
	tierIdx = Chaos.toInt(tierIdx, 1, #c.tiers)
	if not tierIdx then
		return false, "That difficulty does not exist."
	end
	local voc = vocId(player)
	local fam, famKey = M.family(voc)
	if not fam then
		return false, "Your vocation has no trial."
	end
	local pid = player:getId()
	if T.runs[pid] then
		return false, "You are in a trial already."
	end
	local other = otherRun(player)
	if other then
		return false, "You are busy in " .. other .. "."
	end
	local problem = M.enterProblem(tierIdx, player:getLevel(), T.tierCleared(player, voc), os.time(), getS(player, S().cooldown))
	if problem then
		return false, problem
	end
	if inCombat(player) then
		return false, "You cannot enter a trial in combat."
	end
	if c.enter.needProtectionZone and not inProtectionZone(player) then
		return false, "Enter the trial from a protection zone."
	end
	if Chaos.isMultiClient(player) then
		return false, "Characters that share a connection with another character cannot enter a trial."
	end
	if opts.needNpc and not T.keeperNear(player) then
		return false, "The trial is entered at the " .. c.npc.name .. "."
	end
	local running = 0
	for _ in pairs(T.runs) do
		running = running + 1
	end
	local IL = ChaosInstanceLimits
	local slot = not (IL and IL.capped("trials", running, c.limits)) and freeSlot() or nil
	if not slot then
		if IL then
			local lefts, ms = {}, mnow()
			for _, tr in pairs(T.runs) do
				lefts[#lefts + 1] = tr.over and c.exitSeconds or math.max(0, math.floor((tr.deadline - ms) / 1000))
			end
			return false, IL.busy(player, "trials", "trial chambers", lefts, c.limits)
		end
		return false, "Every trial chamber is in use. Try again in a moment."
	end
	local L, err = T.buildSlot(slot)
	if not L then
		log("slot " .. slot .. ": " .. tostring(err))
		slot = freeSlot()
		L = slot and T.buildSlot(slot)
		if not L then
			return false, "The trial chambers cannot be opened. Please tell the staff."
		end
	end
	cleanSlot(L)
	local tierDef = c.tiers[tierIdx]
	local scale = M.scale(tierIdx, player:getLevel(), voc)
	local stages = M.stages(famKey, tierIdx)
	local total, waves = 0, 0
	for _, s in ipairs(stages) do
		if s.kind == "wave" then
			waves = waves + 1
			total = total + scale.waveSize
		elseif s.count then
			total = total + s.count
		end
	end
	local famCopy = setmetatable({key = famKey}, {__index = fam})
	local tr = {pid = pid, slot = slot, L = L, voc = voc, famKey = famKey, fam = famCopy, tier = tierIdx, tierDef = tierDef,
		scale = scale, stages = stages, stageIdx = 0, waveCount = waves, total = total, killed = 0, bossState = "waiting",
		lives = scale.lives, livesMax = scale.lives, limit = tierDef.time, adds = {}, risen = {}, still = {},
		phase = "countdown", back = player:getPosition(), notes = {}, deadline = mnow() + tierDef.time * 1000}
	T.runs[pid] = tr
	T.slotBusy[slot] = pid
	player:setStorageValue(S().marker, tierIdx * 100 + voc)
	player:save()
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(P(L.playerStart))
	P(L.playerStart):sendMagicEffect(CONST_ME_TELEPORT)
	heal(player)
	eventsOn(player)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s (%s): %d minutes, %d %s. %s", fam.name, tierDef.name,
		math.floor(tierDef.time / 60), tr.lives, tr.lives == 1 and "life" or "lives", fam.story))
	Chaos.send(player, RIFT_OPCODE, "start", hudData(tr))
	addEvent(beginFight, c.countdownSeconds * 1000, pid)
	addEvent(tick, c.tickMs, pid)
	log(string.format("%s enters %s on %s (slot %d)", player:getName(), fam.name, tierDef.name, slot))
	return true
end

function T.keeperNear(player)
	local pos = player:getPosition()
	local r = C().npc.range or 6
	local name = C().npc.name:lower()
	for _, c in ipairs(Game.getSpectators(pos, false, false, r, r, r, r) or {}) do
		if c:isNpc() and c:getName():lower() == name then
			return c
		end
	end
	return nil
end

function T.leave(player)
	local tr = T.runs[player:getId()]
	if tr and not tr.over then
		finish(player:getId(), "abort", "You left the trial.")
		return true
	end
	return false
end

-- ======================================================================== opcode actions (the tree window)
ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.extraActions = ChaosPassiveTree.extraActions or {}
local actions = ChaosPassiveTree.extraActions

local function limited(player, key, ms)
	return ChaosRateLimit and not ChaosRateLimit.allow(player, key, ms)
end

actions.trialRequest = function(player)
	if limited(player, "trial.state", 200) then
		return true
	end
	T.sendState(player)
	return true
end

actions.trialChoose = function(player, data)
	if limited(player, "trial.choose", 400) then
		return true
	end
	data = type(data) == "table" and data or {}
	local ok, text = T.choose(player, data.pair, data.side)
	box(player, "Vocation Trials", text)
	T.sendState(player)
	return true
end

actions.trialEnter = function(player, data)
	if limited(player, "trial.enter", 1000) then
		return true
	end
	data = type(data) == "table" and data or {}
	local ok, text = T.enter(player, data.tier)
	if not ok then
		box(player, "Vocation Trials", text)
	end
	T.sendState(player)
	return true
end

actions.trialLeave = function(player)
	T.leave(player)
	return true
end

-- ======================================================================== the Keeper's window
local modal = CreatureEvent("ChaosTrialModal")
function modal.onModalWindow(player, modalWindowId, buttonId, choiceId)
	if modalWindowId ~= C().modalId then
		return true
	end
	if buttonId ~= 1 or not choiceId or choiceId < 1 then
		return true
	end
	local ok, text = T.enter(player, choiceId, {needNpc = true})
	if not ok then
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
	return true
end
modal:register()

-- ======================================================================== login / logout
local login = CreatureEvent("ChaosTrialLogin")
function login.onLogin(player)
	player:registerEvent("ChaosTrialModal")
	player:registerEvent("ChaosTrialLogout")
	player:registerEvent("ChaosTrialNodesLogout")
	-- a character saved inside a trial room (a crash, a restart): back to its temple; the attempt does not count
	if M.slotAt(player:getPosition()) and not T.runs[player:getId()] then
		local temple = player:getTown() and player:getTown():getTemplePosition()
		if temple then
			player:teleportTo(temple)
		end
	end
	if getS(player, S().marker) > 0 and not T.runs[player:getId()] then
		player:setStorageValue(S().marker, 0)
		player:setStorageValue(S().cooldown, 0)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			"Your last trial was cut short by a server restart. It does not count against you; no waiting is needed.")
	end
	return true
end
login:register()

local logout = CreatureEvent("ChaosTrialLogout")
function logout.onLogout(player)
	local tr = T.runs[player:getId()]
	if tr and not tr.over then
		player:teleportTo(tr.back)
		finish(player:getId(), "logout", "You left the trial.")
	end
	return true
end
logout:register()

-- ======================================================================== GM: /trial
local talk = TalkAction("/trial")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false
	end
	local args = {}
	for w in (param or ""):gmatch("%S+") do
		args[#args + 1] = w:lower()
	end
	-- tokens buy Trial rewards: an administrator only, logged (docs/GM_HANDBOOK.md section 2)
	if args[1] == "tokens" and not Chaos.staffCommand(player, words, param, true) then
		return false
	end
	local voc = vocId(player)
	local reply = function(text)
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
	if args[1] == "clear" then
		local t = Chaos.toInt(args[2], 0, #C().tiers) or 1
		player:setStorageValue(S().tierBase + voc, t)
		T.refresh(player)
		T.sendState(player)
		reply("Trial tier cleared set to " .. t .. " for vocation " .. voc .. ".")
	elseif args[1] == "tokens" then
		local n = Chaos.toInt(args[2], 0, 100) or 1
		player:setStorageValue(S().tokens, n)
		T.sendState(player)
		reply("Trial Tokens: " .. n)
	elseif args[1] == "fast" then
		T.fast[player:getId()] = not T.fast[player:getId()] or nil
		reply("Short boss " .. (T.fast[player:getId()] and "on" or "off"))
	elseif args[1] == "reset" then
		player:setStorageValue(S().tierBase + voc, 0)
		player:setStorageValue(S().picksBase + voc, 0)
		player:setStorageValue(S().cooldown, 0)
		T.refresh(player)
		T.sendState(player)
		reply("Trials reset for vocation " .. voc .. ".")
	elseif args[1] == "enter" then
		local ok, text = T.enter(player, tonumber(args[2]) or 1)
		reply(ok and "Entering." or text)
	elseif args[1] == "status" then
		local held = M.heldNodes(voc, T.tierCleared(player, voc), T.picks(player, voc))
		local names, keys = {}, {}
		for _, node in ipairs(held) do
			names[#names + 1] = node.name
		end
		local b = ChaosPassiveCache[player:getId()] or {}
		for k, v in pairs(b) do
			if M.KEYS[k] and not M.KEYS[k].special then
				keys[#keys + 1] = k .. "=" .. v
			end
		end
		table.sort(keys)
		reply(string.format("tier %d, tokens %d, held: %s | bonuses: %s", T.tierCleared(player, voc), tokens(player),
			table.concat(names, ", "), table.concat(keys, " ")))
	elseif args[1] == "win" then
		local tr = T.runs[player:getId()]
		local boss = tr and tr.bossId and Monster(tr.bossId)
		if boss then
			boss:addHealth("physical", -boss:getHealth())
		end
		reply(boss and "The guardian is slain." or "No guardian alive.")
	else
		reply("/trial clear <0-3> | tokens <n> | fast | reset | enter <tier> | status | win")
	end
	return false
end
talk:separator(" ")
talk:register()

-- ======================================================================== startup: the Keeper, monster tiers
local function placeKeeper(pos)
	local name = C().npc.name
	for _, c in ipairs(Game.getSpectators(pos, false, false, 8, 8, 8, 8) or {}) do
		if c:isNpc() and c:getName():lower() == name:lower() then
			return c
		end
	end
	return Game.createNpc(name, pos)
end

local function freeTileNear(temple, offsets)
	for _, o in ipairs(offsets) do
		local pos = Position(temple.x + o[1], temple.y + o[2], temple.z)
		local tile = Tile(pos)
		if tile and tile:getGround() and not tile:hasProperty(CONST_PROP_BLOCKSOLID) and not tile:getTopCreature()
				and not tile:hasFlag(TILESTATE_TELEPORT) and not tile:hasFlag(TILESTATE_FLOORCHANGE) then
			return pos
		end
	end
	return nil
end

function T.placeKeepers()
	local n = C().npc
	local placed = 0
	for _, p in ipairs(n.positions or {}) do
		if placeKeeper(Position(p.x or p[1], p.y or p[2], p.z or p[3])) then
			placed = placed + 1
		end
	end
	if #(n.positions or {}) == 0 then
		for _, townId in ipairs(n.townIds or {}) do
			local town = Town(townId)
			local temple = town and town:getTemplePosition()
			local pos = temple and freeTileNear(temple, n.offsets)
			if pos and placeKeeper(pos) then
				placed = placed + 1
			else
				log("could not place the " .. n.name .. " in town " .. tostring(townId))
			end
		end
	end
	return placed
end

local function skipTiers()
	if ChaosTierConfig and ChaosTierConfig.skip then
		ChaosTierConfig.skip["trial warden"] = true
		ChaosTierConfig.skip["trial thrall"] = true
	end
end
skipTiers()

local startup = GlobalEvent("ChaosTrialsStartup")
function startup.onStartup()
	skipTiers()
	for _, problem in ipairs(M.validate()) do
		log("config: " .. problem)
	end
	if C().enabled and C().npc.spawn then
		addEvent(function()
			log(T.placeKeepers() .. " " .. C().npc.name .. " placed")
		end, 1200)
	end
	return true
end
startup:register()
