-- The Haunted Harvest, the engine side (server/README.md "Haunted Harvest"; pure logic harvest_event_core.lua, numbers
-- harvest_event_config.lua, places harvest_places.lua from server/tools/gen_harvest_places.py; tests
-- tests/harvest_event_test.lua). A seasonal haunted village of the pair 33 kit: nothing runs while
-- ChaosHarvestArt.PAIR33 (data/lib/chaos_harvest_art.lua) is off or while its two areas are not on the map
-- (install_all.py step contentareas places them once the switch is on).
--   startup     dresses the areas: the planned teleport of the ritual chamber goes, the set pieces and the mechanics'
--               resting states (pumpkins, graves, coffins, cauldrons, bell, seal, circle) are put on their tiles, the
--               ground under the seal and the circle gets its action id
--   tick        opens or shuts the event (the window, or the state a gamemaster forced): the Harvest Portals next to
--               the temples (cityportals.lua kind "harvest"), a broadcast, the runtime event of events_schedule.lua
--   actions     ripe pumpkins, graves, buried and upright coffins, candy cauldrons, the cursed bell, the sexton's key on
--               the seal, ritual candles on the circle, the hollow charm
--   movements   the Harvest Portal, the open seal, the open ritual portal
--   boss        Malvorn's phases (the King's Crypt graves raise his court, a ward) and the daily first-kill candy
--   staff       /harvest [status | on | off | auto], the admin panel's Events > Haunted Harvest (the admin app's remote
--               commands run the same action) and the event hook "haunted_harvest" (Start / Stop event)
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosHarvestCore then
	dofile("data/scripts/chaos/harvest_event_core.lua")
end
if not ChaosCityPortals then
	dofile("data/scripts/chaos/cityportals.lua")
end
ChaosHarvestArt = ChaosHarvestArt or dofile("data/lib/chaos_harvest_art.lua")
Chaos.harvestConfig = dofile("data/scripts/chaos/harvest_event_config.lua")

ChaosHarvest = ChaosHarvest or {}
local X = ChaosHarvest
local K = ChaosHarvestCore
local cfg = Chaos.harvestConfig
local kit = ChaosHarvestArt.kit
local KI, KS = kit.items or {}, kit.states or {}
local okP, places = pcall(dofile, "data/scripts/chaos/harvest_places.lua")
X.places = okP and places or nil
X.open = X.open or false
X.circleCount = X.circleCount or 0
X.bellAt = X.bellAt or {}
X.phases = X.phases or {} -- boss creature id -> {done = {}, wardUntil = 0}

local function log(text)
	print("[harvest] " .. text)
end

local function P(t)
	return Position(t.x or t[1], t.y or t[2], t.z or t[3])
end

-- a set piece of harvest_places.lua is {id, x, y, z}: its position starts at the second field (read with P, the
-- y landed in z: "getNumber(). Argument 4 has out-of-range value", the decoration never placed, beta 2026-10-22)
local function decorPos(d)
	return Position(d[2], d[3], d[4])
end

local function rng(a, b)
	return math.random(a, b)
end

local function id(key)
	local e = KI[key]
	return e and e.id or 0
end

local function tell(player, key, ...)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, key, ...))
end

local function effect(pos, name)
	local e = rawget(_G, name or "")
	if e then
		pos:sendMagicEffect(e)
	end
end

function X.force()
	return math.max(0, tonumber(Game.getStorageValue(cfg.globalStorage.force)) or 0)
end

-- the areas are on the map (install step contentareas ran with the switch on)
function X.placed()
	local p = X.places
	if not (ChaosHarvestArt.PAIR33 and p) then
		return false
	end
	local a, b = Tile(P(p.surface.arrival)), Tile(P(p.catacombs.arrival))
	return a ~= nil and a:getGround() ~= nil and b ~= nil and b:getGround() ~= nil
end

function X.isOpen(t)
	return X.placed() and K.isOpen(cfg, t or os.time(), X.force(), ChaosHarvestArt.PAIR33)
end

-- ------------------------------------------------------------------ dressing
local function hasAny(tile, ids)
	for _, i in pairs(ids) do
		local it = tile:getItemById(i)
		if it then
			return it
		end
	end
	return nil
end

-- the item of a mechanic on its tile, or a new one in `rest` (the resting state); timed states start decaying
local function ensure(pos, states, rest)
	local tile = Tile(P(pos))
	if not tile then
		return nil
	end
	local it = hasAny(tile, states)
	if it then
		return it
	end
	it = Game.createItem(rest, 1, P(pos))
	if it and kit.decay and kit.decay[rest] then
		it:decay()
	end
	return it
end

local function groundAid(list, aid)
	for _, t in ipairs(list) do
		local tile = Tile(P(t))
		local g = tile and tile:getGround()
		if g then
			g:setActionId(aid)
		end
	end
end

function X.dress()
	local p = X.places
	local n = 0
	-- the planned teleport under the ritual circle goes: the circle's portal is the way into the King's Crypt
	local tt = Tile(P(p.circle.teleport))
	local tp = tt and tt:getItemById(1387)
	if tp then
		tp:remove()
	end
	for _, d in ipairs(p.decor) do
		local pos = decorPos(d)
		local tile = Tile(pos)
		if tile and not tile:getItemById(d[1]) and Game.createItem(d[1], 1, pos) then
			n = n + 1
		end
	end
	local pumpkin = {}
	for s = 1, 6 do
		pumpkin[s] = KS.pumpkin_growth[tostring(s)]
	end
	for _, q in ipairs(p.pumpkins) do
		ensure(q, pumpkin, pumpkin[q.stage or 1])
	end
	for _, list in ipairs({p.graves, p.kingGraves}) do
		for _, q in ipairs(list) do
			ensure(q, KS.grave, KS.grave.mound)
		end
	end
	for _, q in ipairs(p.coffins) do
		ensure(q, KS.coffin_up, KS.coffin_up.closed)
	end
	for _, q in ipairs(p.cauldrons) do
		ensure(q, {KS.cauldron.treat, KS.cauldron.mimic, id("cauldron")}, KS.cauldron.treat)
	end
	for _, q in ipairs(p.bells) do
		ensure(q, KS.cursed_bell, KS.cursed_bell.still)
	end
	ensure(p.seal.anchor, KS.crypt_seal, KS.crypt_seal.sealed)
	ensure(p.circle.anchor, KS.ritual_circle, KS.ritual_circle.dormant)
	groundAid(p.seal.tiles, cfg.aid.seal)
	groundAid(p.circle.tiles, cfg.aid.circle)
	return n
end

-- ------------------------------------------------------------------ open / shut
function X.setOpen(open, quiet)
	if open == X.open then
		return
	end
	X.open = open
	if open then
		ChaosCityPortals.place({kind = "harvest", aid = cfg.aid.portal, item = cfg.portal.item, towns = cfg.portal.towns,
			log = log})
		if not quiet then
			Chaos.broadcast(MESSAGE_STATUS_WARNING, cfg.messages.opened)
		end
	else
		ChaosCityPortals.remove(cfg.aid.portal)
		if ChaosEvents and ChaosEvents.dynamic then
			ChaosEvents.dynamic.harvest = nil
		end
		if not quiet then
			Chaos.broadcast(MESSAGE_STATUS_WARNING, cfg.messages.closed)
		end
	end
end

function X.tick(quiet)
	local now = os.time()
	X.setOpen(X.isOpen(now), quiet)
	if X.open and ChaosEvents and ChaosEvents.dynamic then
		ChaosEvents.dynamic.harvest = K.dynamicEntry(cfg, now, X.force())
	end
end

-- a gamemaster's or the panel's switch: "on", "off", "auto"; returns the text of the new state
function X.setForce(mode)
	local f = K.forceOf(mode)
	if f == nil then
		return nil, "Use on, off or auto."
	end
	Game.setStorageValue(cfg.globalStorage.force, f)
	X.tick(false)
	return X.status()
end

function X.status()
	local f = X.force()
	local s, e = K.windowRange(cfg, os.time())
	return string.format("Haunted Harvest: %s (%s; window %s - %s; switch PAIR33 %s; areas %s)", X.open and "OPEN" or "shut",
		f == 1 and "forced open" or (f == 2 and "forced shut" or "the window decides"), os.date("%Y-%m-%d", s),
		os.date("%Y-%m-%d", e), ChaosHarvestArt.PAIR33 and "on" or "off", X.placed() and "on the map" or "not on the map")
end

-- ------------------------------------------------------------------ helpers of the mechanics
local function spawnAround(names, pos)
	local n = 0
	for _, name in ipairs(names) do
		if Game.createMonster(name, pos, true, false) then
			n = n + 1
		end
	end
	return n
end

local function candy(player, n)
	if n > 0 then
		player:addItem(cfg.items.candy, n)
	end
end

local function shut(player)
	if not X.open then
		tell(player, cfg.messages.shut)
		return true
	end
	return false
end

local function dayCount(player)
	local today = K.dayKey(os.time())
	if player:getStorageValue(cfg.storage.day) ~= today then
		player:setStorageValue(cfg.storage.day, today)
		player:setStorageValue(cfg.storage.pumpkinCandy, 0)
	end
	return math.max(0, player:getStorageValue(cfg.storage.pumpkinCandy))
end

-- ------------------------------------------------------------------ pumpkins
local pumpkinUse = Action()
function pumpkinUse.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if shut(player) then
		return true
	end
	local given = dayCount(player)
	local r = K.pumpkin(cfg, rng, given)
	if r.capped then
		tell(player, cfg.messages.capped)
		return true
	end
	candy(player, r.candy)
	player:setStorageValue(cfg.storage.pumpkinCandy, given + r.candy)
	tell(player, cfg.messages.harvested, r.candy)
	if r.charm then
		player:addItem(cfg.items.charm, 1)
	end
	local pos = item:getPosition()
	if r.wake then
		item:transform(KS.pumpkin_growth["6"])
		item:decay()
		tell(player, cfg.messages.woke)
		effect(pos, "CONST_ME_FIREAREA")
		spawnAround({r.wake}, pos)
	else
		item:transform(KS.pumpkin_growth["1"])
		item:decay()
		effect(pos, "CONST_ME_POFF")
	end
	return true
end
pumpkinUse:id(KS.pumpkin_growth and KS.pumpkin_growth["5"] or 41528)
pumpkinUse:register()

local pumpkinYoung = Action()
function pumpkinYoung.onUse(player, item)
	tell(player, cfg.messages.notRipe)
	return true
end
for s = 1, 4 do
	pumpkinYoung:id(KS.pumpkin_growth and KS.pumpkin_growth[tostring(s)] or (41523 + s))
end
pumpkinYoung:register()

-- ------------------------------------------------------------------ graves and coffins
local graveUse = Action()
function graveUse.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if shut(player) then
		return true
	end
	local pos = item:getPosition()
	if item:getId() == KS.grave.mound then
		item:transform(KS.grave.dug)
		item:decay()
		tell(player, cfg.messages.dig)
		effect(pos, "CONST_ME_POFF")
		return true
	end
	-- the buried coffin
	local r = K.grave(cfg, rng)
	item:transform(KS.grave.coffin_bursting)
	item:decay()
	candy(player, r.candy)
	if r.key then
		player:addItem(cfg.items.key, 1)
		tell(player, cfg.messages.coffinKey)
	end
	if #r.raise > 0 then
		tell(player, cfg.messages.risen)
		effect(pos, "CONST_ME_MORTAREA")
		spawnAround(r.raise, pos)
	else
		tell(player, cfg.messages.coffinEmpty, r.candy)
	end
	return true
end
graveUse:id(KS.grave and KS.grave.mound or 41535, KS.grave and KS.grave.coffin_closed or 41537)
graveUse:register()

local coffinUse = Action()
function coffinUse.onUse(player, item)
	if shut(player) then
		return true
	end
	local pos = item:getPosition()
	local r = K.coffin(cfg, rng)
	item:transform(KS.coffin_up.opening)
	item:decay()
	candy(player, r.candy)
	if #r.raise > 0 then
		tell(player, cfg.messages.risen)
		effect(pos, "CONST_ME_MORTAREA")
		spawnAround(r.raise, pos)
	else
		tell(player, cfg.messages.coffinEmpty, r.candy)
	end
	return true
end
coffinUse:id(KS.coffin_up and KS.coffin_up.closed or 41577)
coffinUse:register()

-- ------------------------------------------------------------------ cauldrons and the bell
local function refill(pos)
	addEvent(function()
		local tile = Tile(P(pos))
		if not tile then
			return
		end
		local it = tile:getItemById(KS.cauldron.mimic) or tile:getItemById(id("cauldron"))
		if it then
			it:transform(KS.cauldron.treat)
		end
	end, (cfg.cauldron.refillSeconds or 300) * 1000)
end

local cauldronUse = Action()
function cauldronUse.onUse(player, item)
	if shut(player) then
		return true
	end
	local pos = item:getPosition()
	if item:getId() ~= KS.cauldron.treat then
		tell(player, cfg.messages.cauldronEmpty)
		return true
	end
	local r = K.cauldron(cfg, rng)
	if r.trick then
		item:transform(KS.cauldron.mimic)
		tell(player, cfg.messages.trick)
		effect(pos, "CONST_ME_BATS")
		spawnAround(r.trick, pos)
	else
		item:transform(id("cauldron"))
		candy(player, r.candy)
		tell(player, cfg.messages.treat, r.candy)
		effect(pos, "CONST_ME_GIFT_WRAPS")
	end
	refill({x = pos.x, y = pos.y, z = pos.z})
	return true
end
cauldronUse:id(KS.cauldron and KS.cauldron.treat or 41540, KS.cauldron and KS.cauldron.mimic or 41541)
cauldronUse:register()

local bellUse = Action()
function bellUse.onUse(player, item)
	if shut(player) then
		return true
	end
	local pos = item:getPosition()
	local key = pos.x .. "," .. pos.y .. "," .. pos.z
	local now = os.time()
	if (X.bellAt[key] or 0) > now then
		tell(player, cfg.messages.bellCooldown)
		return true
	end
	X.bellAt[key] = now + (cfg.bell.cooldownSeconds or 180)
	item:transform(KS.cursed_bell.tolling)
	item:decay()
	tell(player, cfg.messages.bell)
	local names = {}
	for i = 1, cfg.bell.ravens or 3 do
		names[i] = cfg.bell.raven
	end
	spawnAround(names, pos)
	return true
end
bellUse:id(KS.cursed_bell and KS.cursed_bell.still or 41545)
bellUse:register()

-- ------------------------------------------------------------------ the seal and the circle
local tools = Action()
function tools.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if not target or not target.isItem or not target:isItem() then
		return false
	end
	if shut(player) then
		return true
	end
	local tid = target:getId()
	if item:getId() == cfg.items.key then
		if tid == KS.crypt_seal.sealed then
			item:remove(cfg.seal.keys or 1)
			target:transform(KS.crypt_seal.breaking)
			target:decay()
			tell(player, cfg.messages.sealBreaks)
			effect(target:getPosition(), "CONST_ME_MORTAREA")
			return true
		end
		return false
	end
	-- a ritual candle on the circle
	if tid == KS.ritual_circle.dormant then
		item:remove(1)
		local n, lit = K.circleAdd(X.circleCount, cfg)
		X.circleCount = n
		if lit then
			target:transform(KS.ritual_circle.lighting)
			target:decay()
			Chaos.broadcast(MESSAGE_STATUS_CONSOLE_ORANGE, cfg.messages.circleLit)
		else
			tell(player, cfg.messages.candlePlaced, n, cfg.circle.candles)
		end
		effect(target:getPosition(), "CONST_ME_FIREAREA")
		return true
	end
	if KS.ritual_circle and (tid == KS.ritual_circle.lighting or tid == KS.ritual_circle.flare or
			tid == KS.ritual_circle.portal_open) then
		tell(player, cfg.messages.circleBusy)
		return true
	end
	return false
end
tools:id(cfg.items.key, cfg.items.candle)
tools:register()

local function onTile(pos, ids)
	local tile = Tile(pos)
	return tile and hasAny(tile, ids) ~= nil
end

local function anchorHas(anchor, wanted)
	local tile = Tile(P(anchor))
	return tile ~= nil and tile:getItemById(wanted) ~= nil
end

local sealStep = MoveEvent()
sealStep:type("stepin")
function sealStep.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player or not X.places then
		return true
	end
	if anchorHas(X.places.seal.anchor, KS.crypt_seal.open) then
		player:teleportTo(P(X.places.catacombs.arrival))
		effect(P(X.places.catacombs.arrival), "CONST_ME_MORTAREA")
	elseif not onTile(position, {KS.crypt_seal.sealed}) then
		tell(player, cfg.messages.sealNeedsKey)
	end
	return true
end
sealStep:aid(cfg.aid.seal)
sealStep:register()

local circleStep = MoveEvent()
circleStep:type("stepin")
function circleStep.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player or not X.places then
		return true
	end
	if anchorHas(X.places.circle.anchor, KS.ritual_circle.portal_open) then
		player:teleportTo(P(X.places.circle.landing))
		effect(P(X.places.circle.landing), "CONST_ME_TELEPORT")
	end
	return true
end
circleStep:aid(cfg.aid.circle)
circleStep:register()

-- the Harvest Portal next to a temple
local portalStep = MoveEvent()
portalStep:type("stepin")
function portalStep.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	if not X.open or not X.places then
		tell(player, cfg.messages.shut)
		player:teleportTo(fromPosition, true)
		return true
	end
	player:teleportTo(P(X.places.surface.arrival))
	effect(P(X.places.surface.arrival), "CONST_ME_TELEPORT")
	return true
end
portalStep:aid(cfg.aid.portal)
portalStep:register()

-- ------------------------------------------------------------------ the hollow charm
local function cosmeticName(e)
	if e.kind == "cosmetic" and ChaosCosmeticsCore and ChaosCosmeticsConfig then
		local c = ChaosCosmeticsCore.byKey(ChaosCosmeticsConfig, e.key)
		return c and c.name or e.key
	end
	if e.kind == "exclusive" and ChaosExclusivesCore and ChaosExclusivesConfig then
		local c = ChaosExclusivesCore.byKey(ChaosExclusivesConfig, e.key)
		return c and c.name or e.key
	end
	return e.key
end

local function owns(account, e)
	if e.kind == "cosmetic" and ChaosCosmetics and ChaosCosmetics.owns then
		return ChaosCosmetics.owns(account, e.key)
	elseif e.kind == "exclusive" and ChaosExclusives and ChaosExclusives.owns then
		return ChaosExclusives.owns(account, e.key)
	end
	return true -- a kind this server cannot grant counts as owned
end

local function grant(player, e)
	local account = player:getAccountId()
	if e.kind == "cosmetic" then
		return ChaosCosmetics.grant(account, e.key, "harvest")
	end
	return ChaosExclusives.grant(account, e.key, "harvest", player)
end

local charmUse = Action()
function charmUse.onUse(player, item)
	local account = player:getAccountId()
	local e = K.charmPick(cfg.charmPool, function(x) return owns(account, x) end, rng)
	if not e then
		item:remove(1)
		candy(player, cfg.charmFallbackCandy)
		tell(player, cfg.messages.charmCandy, cfg.charmFallbackCandy)
		return true
	end
	local ok = grant(player, e)
	if not ok then
		return true
	end
	item:remove(1)
	tell(player, cfg.messages.charmUsed, cosmeticName(e))
	player:getPosition():sendMagicEffect(CONST_ME_GIFT_WRAPS)
	return true
end
charmUse:id(cfg.items.charm)
charmUse:register()

-- ------------------------------------------------------------------ the boss
local bossHealth = CreatureEvent("HarvestKingHealth")
function bossHealth.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local st = X.phases[creature:getId()]
	if not st then
		st = {done = {}, wardUntil = 0}
		X.phases[creature:getId()] = st
	end
	if os.time() < st.wardUntil then
		primaryDamage = K.wardDamage(cfg, primaryDamage)
		secondaryDamage = K.wardDamage(cfg, secondaryDamage)
	end
	local max = math.max(1, creature:getMaxHealth())
	local before = creature:getHealth() * 100 / max
	local after = (creature:getHealth() - primaryDamage - secondaryDamage) * 100 / max
	local i = K.bossPhase(cfg, before, after, st.done)
	if i and X.places then
		st.done[i] = true
		st.wardUntil = os.time() + (cfg.boss.wardSeconds or 20)
		Chaos.broadcast(MESSAGE_STATUS_CONSOLE_ORANGE, cfg.messages.bossPhase, creature:getName())
		for _, q in ipairs(X.places.kingGraves) do
			local tile = Tile(P(q))
			local g = tile and hasAny(tile, KS.grave)
			if g then
				g:transform(KS.grave.coffin_bursting)
				g:decay()
			end
			local names = {}
			for n = 1, cfg.boss.perGrave or 1 do
				names[n] = cfg.boss.court[rng(1, #cfg.boss.court)]
			end
			spawnAround(names, P(q))
			effect(P(q), "CONST_ME_MORTAREA")
		end
		creature:getPosition():sendMagicEffect(CONST_ME_MAGIC_RED)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
bossHealth:register()

local bossDeath = CreatureEvent("HarvestKingDeath")
function bossDeath.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	X.phases[creature:getId()] = nil
	Chaos.broadcast(MESSAGE_STATUS_WARNING, cfg.messages.bossSlain, creature:getName())
	local today = K.dayKey(os.time())
	for cid in pairs(creature:getDamageMap() or {}) do
		local p = Player(cid)
		if p and p:getStorageValue(cfg.storage.bossDay) ~= today then
			p:setStorageValue(cfg.storage.bossDay, today)
			candy(p, cfg.boss.dailyCandy or 0)
			tell(p, cfg.messages.bossBonus, cfg.boss.dailyCandy or 0)
		end
	end
	return true
end
bossDeath:register()

-- ------------------------------------------------------------------ the night
local function ambient()
	if X.open and X.places and #X.places.decor > 0 then
		for _ = 1, 3 do
			local d = X.places.decor[math.random(1, #X.places.decor)]
			local pos = decorPos(d)
			local seen = Game.getSpectators(pos, false, true, 8, 8, 6, 6)
			if seen and #seen > 0 then
				effect(pos, cfg.ambient.effects[math.random(1, #cfg.ambient.effects)])
			end
		end
	end
	addEvent(ambient, (cfg.ambient.everySeconds or 15) * 1000)
end

-- ------------------------------------------------------------------ startup and tick
local startup = GlobalEvent("ChaosHarvestStartup")
function startup.onStartup()
	if not ChaosHarvestArt.PAIR33 then
		log("ChaosHarvestArt.PAIR33 is off: the Haunted Harvest stays closed")
		return true
	end
	local bad = K.checkPlaces(X.places, kit)
	if #bad > 0 then
		log("harvest_places.lua: " .. bad[1] .. " (run server/tools/gen_harvest_places.py)")
		X.places = nil
		return true
	end
	if not X.placed() then
		log("the event areas are not on the map (install_all.py --only contentareas with the switch on)")
		return true
	end
	local ok, n = pcall(X.dress)
	log(ok and string.format("dressed: %d set pieces placed", n) or ("dressing failed: " .. tostring(n)))
	X.tick(true)
	addEvent(ambient, 5000)
	log(X.status())
	return true
end
startup:register()

local ticker = GlobalEvent("ChaosHarvestTick")
function ticker.onThink(interval)
	if ChaosHarvestArt.PAIR33 and X.places then
		X.tick(false)
	end
	return true
end
ticker:interval((cfg.tickSeconds or 60) * 1000)
ticker:register()

-- ------------------------------------------------------------------ staff
local function groupOf(player)
	local ok, g = pcall(function() return player:getGroup():getId() end)
	return ok and g or 0
end

local talk = TalkAction("/harvest")
function talk.onSay(player, words, param)
	if groupOf(player) < (cfg.staffGroup or 4) then
		return true
	end
	local cmd = (tostring(param or ""):match("^%s*(%S*)") or ""):lower()
	local text
	if cmd == "" or cmd == "status" then
		text = X.status()
	elseif groupOf(player) < (cfg.switchGroup or 5) then
		text = "Opening or shutting the Haunted Harvest needs group " .. (cfg.switchGroup or 5) .. "."
	else
		local s, why = X.setForce(cmd)
		text = s or why
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, "[harvest] " .. text)
	return false
end
talk:separator(" ")
talk:register()

-- the admin panel (Events > Haunted Harvest; the admin app's "panel" remote commands run it too)
ChaosAdminPending = ChaosAdminPending or {}
ChaosAdminPending["events.harvest"] = {id = "events.harvest", category = "events", name = "Haunted Harvest",
	description = "The seasonal haunted event zone: its state, or force it open / shut (auto: the window decides).",
	minGroup = 5, confirm = true,
	params = {{name = "mode", label = "Mode", type = "select", options = {{value = "status", label = "Status"},
		{value = "on", label = "Open now"}, {value = "off", label = "Shut now"}, {value = "auto", label = "Window decides"}}}},
	handler = function(actor, p)
		if p.mode == "status" then
			return true, X.status()
		end
		local s, why = X.setForce(p.mode)
		if not s then
			return false, why
		end
		return true, s
	end}
-- the event hook (Events > Start / Stop event; admin/core.lua reads ChaosAdminHooks when called, so the load order
-- of the two files does not matter)
ChaosAdminHooks = ChaosAdminHooks or {}
ChaosAdminHooks.haunted_harvest = {name = "haunted_harvest", kind = "event",
	description = "Haunted Harvest: start forces it open, stop sets it back to its window (harvest_event.lua)",
	start = function() return X.setForce("on") end,
	stop = function() return X.setForce("auto") end}

return X
