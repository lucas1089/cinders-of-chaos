-- Town Portal: every character can open a portal home, from the action bar (the spell "Town Portal", words
-- "ash domh", data/spells/chaos/shared/town_portal.lua) or from the menu (Character > Town Portal, client
-- game_townportal). Numbers and the portal styles: townportal_config.lua; pure logic: townportal_core.lua
-- (server/tests/townportal_test.lua). Overview: server/README.md "Town Portal".
--
-- Flow: a castMs channel (moving or taking damage interrupts it, nothing is spent) -> a portal beside the caster
-- (to the temple of the character's town) and a return portal beside that temple (back to the exact spot of the
-- cast). One pair per character: a new cast closes the old pair. A pair closes after portalMinutes or when its
-- owner walks back through the return portal. The owner and the owner's party members may use both portals.
-- cooldownSeconds starts when the portal opens. Refused: tutorial island, arena match, world boss arena, guild
-- siege, rifts / omen arenas, dungeons, the Infinity Tower (they drop a player who leaves their area and have no way
-- back in, so they keep their own exits), right after PvP (pz-lock), with a skull, inside a protection zone.
-- The field portal also refuses a pz-locked or skulled player at the step.
--
-- Portal styles: the look of both portals and their open / close / loop / travel effects, seen by everyone. One
-- default, store styles (offer kind "unlock", unlock = "portal_<key>", shop_services.lua asks
-- ChaosTownPortal.storeUnlock) and achievement styles (achievements_data.lua reward = {portal = {key, name}}).
-- The choice is stored per character (townportal_config.lua storage.style).
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.townPortal:
--   client -> server  open | get | select {id} | cast
--   server -> client  state {open, selected, cooldown, styles = [K.view rows]}
--                     cast {ms} (channel started)   castEnd {result = "done" | "moved" | "hit" | "refused"}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/townportal_core.lua")
if not ChaosVfx then
	pcall(dofile, "data/lib/chaos_vfx.lua")
end
if not ChaosFx then
	pcall(dofile, "data/lib/chaos_fx.lua")
end

ChaosTownPortalConfig = dofile("data/scripts/chaos/townportal_config.lua")
ChaosTownPortal = ChaosTownPortal or {}
local T = ChaosTownPortal
local K = ChaosTownPortalCore
local cfg = ChaosTownPortalConfig
local OPCODE = (ChaosOpcodes and ChaosOpcodes.townPortal) or 239
local ST = cfg.storage

T.casts = T.casts or {} -- creature id -> cast {startMs, endMs, pos, damaged, token}
T.pairs = T.pairs or {} -- owner guid -> pair
T.byPos = T.byPos or {} -- "x,y,z" -> {pair, kind = "field" | "back"}
local token = 0

local function key(p)
	return p.x .. "," .. p.y .. "," .. p.z
end

local function P(p)
	return Position(p.x, p.y, p.z)
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- the first effect of the list that exists (a Vfx name, a ChaosFx name or a stock number)
local function fx(pos, list)
	for _, e in ipairs(list or {}) do
		if type(e) == "number" then
			P(pos):sendMagicEffect(e)
			return
		elseif ChaosVfx and ChaosVfx[e] and Vfx then
			if Vfx(P(pos), e) then
				return
			end
		elseif ChaosFx and ChaosFx[e] then
			P(pos):sendMagicEffect(ChaosFx[e])
			return
		end
	end
end

-- ---------------------------------------------------------------- styles
local function achievementData()
	local A = ChaosAchievements
	return A and A.data or nil
end

local function facts(player)
	return {
		storeOwned = function(id)
			return player:getStorageValue(ST.storeOwnedBase + id) > 0
		end,
		hasAchievement = function(id)
			local A = ChaosAchievements
			return A and A.unlockedOf and A.unlockedOf(player)[id] ~= nil or false
		end,
		achievementOf = function(styleKey)
			return K.achievementOf(achievementData(), styleKey)
		end
	}
end

-- the style the character uses: the selected one while it is owned, else the default
function T.styleOf(player)
	local s = K.style(cfg, player:getStorageValue(ST.style))
	if not K.owns(s, facts(player)) then
		s = K.style(cfg, nil)
	end
	return s
end

local function prices()
	return K.storePrices(ChaosShopConfig)
end

local function sendState(player, open)
	local left = K.cooldownLeft(os.time(), player:getStorageValue(ST.cooldown))
	local rows = K.view(cfg, facts(player), T.styleOf(player).id, prices(), achievementData())
	for _, row in ipairs(rows) do
		row.clientItem = ItemType(row.item):getClientId()
	end
	Chaos.send(player, OPCODE, "state", {
		open = open and true or false,
		selected = T.styleOf(player).id,
		cooldown = left,
		cooldownTotal = cfg.cooldownSeconds,
		styles = rows
	})
end
T.sendState = sendState

-- store: shop_services.lua unlockEntry
function T.storeUnlock(unlockName)
	local s = K.styleOfUnlock(cfg, unlockName)
	if not s then
		return nil
	end
	return {
		name = "the portal style " .. s.name,
		done = "Choose it in Character > Portal Style.",
		owned = function(player)
			return player:getStorageValue(ST.storeOwnedBase + s.id) > 0
		end,
		grant = function(player)
			player:setStorageValue(ST.storeOwnedBase + s.id, 1)
			return true
		end
	}
end

-- ---------------------------------------------------------------- where it is refused
local function try(fn)
	local ok, res = pcall(fn)
	return ok and res and true or false
end

local function blockFacts(player)
	local pos = player:getPosition()
	local tile = Tile(pos)
	local skull = player:getSkull()
	local town = player:getTown()
	return {
		casting = T.casts[player:getId()] ~= nil,
		cooldownLeft = K.cooldownLeft(os.time(), player:getStorageValue(ST.cooldown)),
		tutorial = try(function() return ChaosNewPlayer and ChaosNewPlayer.onIsland and ChaosNewPlayer.onIsland(pos) end),
		noTown = not town or town:getTemplePosition().x == 0,
		arena = try(function() return ChaosArena and ChaosArena.isInside and ChaosArena.isInside(player) end),
		worldBoss = try(function() return ChaosWorldBoss and ChaosWorldBoss.inside and ChaosWorldBoss.inside(pos) end),
		siege = try(function() return ChaosSiege and ChaosSiege.locate and ChaosSiege.locate(pos) ~= nil end),
		rift = try(function()
			return ChaosRift and ChaosRift.isInside and ChaosRift.isInside(player)
				or (ChaosRiftCore and ChaosRiftConfig and ChaosRiftCore.slotOfPos(ChaosRiftConfig, pos) ~= nil)
		end),
		dungeon = try(function() return ChaosDungeonIsInside and ChaosDungeonIsInside(player) end),
		tower = try(function() return ChaosTowerRun and ChaosTowerRun.isInside and ChaosTowerRun.isInside(player) end),
		pzLocked = player:isPzLocked(),
		skull = skull == SKULL_WHITE or skull == SKULL_RED or skull == SKULL_BLACK,
		pz = tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
	}
end

function T.blockReason(player)
	return K.blockReason(blockFacts(player))
end

-- ---------------------------------------------------------------- portals
local function spotFree(p)
	if T.byPos[key(p)] then
		return false
	end
	local tile = Tile(P(p))
	if not tile or not tile:getGround() then
		return false
	end
	if tile.getHouse and tile:getHouse() then
		return false
	end
	if tile:hasProperty(CONST_PROP_BLOCKSOLID) or tile:hasProperty(CONST_PROP_BLOCKPATH)
		or tile:hasProperty(CONST_PROP_IMMOVABLEBLOCKSOLID) then
		return false
	end
	if tile:hasFlag(TILESTATE_FLOORCHANGE) or tile:hasFlag(TILESTATE_TELEPORT) or tile:hasFlag(TILESTATE_MAGICFIELD) then
		return false
	end
	if ITEM_TYPE_TELEPORT and tile:getItemByType(ITEM_TYPE_TELEPORT) then
		return false
	end
	if tile:getTopCreature() then
		return false
	end
	return true
end

local function removePortal(pair, kind)
	local pos = pair[kind]
	if not pos then
		return
	end
	T.byPos[key(pos)] = nil
	local tile = Tile(P(pos))
	local item = tile and tile:getItemById(pair.item)
	if item and item:getActionId() == cfg.aid[kind] then
		item:remove()
	end
	fx(pos, pair.style.close)
	pair[kind] = nil
end

function T.closePair(guid, why)
	local pair = T.pairs[guid]
	if not pair then
		return
	end
	T.pairs[guid] = nil
	removePortal(pair, "field")
	removePortal(pair, "back")
	local owner = Player(pair.ownerName)
	if owner and why then
		owner:sendTextMessage(MESSAGE_STATUS_SMALL, why)
	end
end

local function placePortal(pair, kind, pos)
	local item = Game.createItem(pair.item, 1, P(pos))
	if not item then
		return false
	end
	item:setActionId(cfg.aid[kind])
	pair[kind] = pos
	T.byPos[key(pos)] = {pair = pair, kind = kind}
	fx(pos, pair.style.open)
	return true
end

local function spellCooldown(player, seconds)
	local c = Condition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT, cfg.spellId)
	c:setParameter(CONDITION_PARAM_SUBID, cfg.spellId)
	c:setParameter(CONDITION_PARAM_TICKS, seconds * 1000)
	player:addCondition(c)
end

-- the channel finished: open the pair. Returns true or an error text (nothing spent then)
local function openPair(player)
	local reason = K.blockReason(blockFacts(player))
	if reason then
		return reason
	end
	local here = player:getPosition()
	local temple = player:getTown():getTemplePosition()
	T.closePair(player:getGuid(), nil) -- one pair per character
	local field = K.pickSpot(here, cfg.fieldOffsets, spotFree)
	if not field then
		return "There is no room for a portal here."
	end
	local back = K.pickSpot(temple, K.ringOffsets(cfg.templeRadius), function(p)
		return not (p.x == field.x and p.y == field.y and p.z == field.z) and spotFree(p)
	end)
	if not back then
		return "The temple is crowded with portals; try again in a moment."
	end
	local style = T.styleOf(player)
	token = token + 1
	local pair = {owner = player:getGuid(), ownerName = player:getName(), style = style, item = style.item,
		returnTo = {x = here.x, y = here.y, z = here.z}, temple = {x = temple.x, y = temple.y, z = temple.z},
		expiresAt = os.time() + cfg.portalMinutes * 60, token = token}
	if not placePortal(pair, "field", field) then
		return "The portal could not open here."
	end
	if not placePortal(pair, "back", back) then
		removePortal(pair, "field")
		return "The portal could not open here."
	end
	T.pairs[pair.owner] = pair
	player:setStorageValue(ST.cooldown, os.time() + cfg.cooldownSeconds)
	spellCooldown(player, cfg.cooldownSeconds)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"A portal to your temple opened beside you. Its return portal waits beside the temple for %d minutes.",
		cfg.portalMinutes))
	return true
end

-- ---------------------------------------------------------------- the channel
local function endCast(player, result, text)
	T.casts[player:getId()] = nil
	Chaos.send(player, OPCODE, "castEnd", {result = result})
	if text then
		player:sendCancelMessage(text)
	end
end

local function poll(cid, tok)
	local cast = T.casts[cid]
	if not cast or cast.token ~= tok then
		return
	end
	local player = Player(cid)
	if not player then
		T.casts[cid] = nil
		return
	end
	local step = K.castStep(cast, nowMs(), player:getPosition(), cast.damaged)
	if step == "wait" then
		local second = math.floor((nowMs() - cast.startMs) / 1000)
		if second > (cast.second or 0) then
			cast.second = second
			fx(player:getPosition(), cfg.castEffect)
		end
		addEvent(poll, cfg.pollMs, cid, tok)
		return
	end
	if step == "moved" or step == "hit" then
		fx(cast.pos, cfg.interruptEffect)
		endCast(player, step, step == "moved" and "You moved: the portal fizzles." or "You were hit: the portal fizzles.")
		return
	end
	T.casts[cid] = nil -- openPair checks "casting"
	local ok = openPair(player)
	if ok == true then
		Chaos.send(player, OPCODE, "castEnd", {result = "done"})
		sendState(player, false)
	else
		endCast(player, "refused", ok)
	end
end

-- start the channel; source "spell" | "menu". Returns true when it started.
function T.cast(player, source)
	local reason = T.blockReason(player)
	if reason then
		player:sendCancelMessage(reason)
		Chaos.send(player, OPCODE, "castEnd", {result = "refused"})
		return false
	end
	if ChaosCasting then -- a cast-time spell in progress ends (refunded); data/lib/chaos_casting.lua
		ChaosCasting.interrupt(player, "portal")
	end
	token = token + 1
	local cast = K.castStart(nowMs(), player:getPosition(), cfg.castMs)
	cast.token = token
	T.casts[player:getId()] = cast
	fx(player:getPosition(), cfg.castEffect)
	Chaos.send(player, OPCODE, "cast", {ms = cfg.castMs})
	player:sendTextMessage(MESSAGE_STATUS_SMALL, "Opening a town portal... stand still.")
	addEvent(poll, cfg.pollMs, player:getId(), token)
	return true
end

-- ---------------------------------------------------------------- stepping through
local function pushBack(player, fromPosition, text)
	player:sendCancelMessage(text)
	player:teleportTo(fromPosition, true)
end

local function partyKey(p)
	local party = p and p:getParty()
	local leader = party and party:getLeader()
	return leader and leader:getGuid() or nil
end

local function use(creature, item, position, fromPosition, kind)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	local entry = T.byPos[key(position)]
	local pair = entry and entry.kind == kind and entry.pair
	if not pair or T.pairs[pair.owner] ~= pair then
		return true -- a leftover item: nothing happens
	end
	local guid = player:getGuid()
	local owner = Player(pair.ownerName)
	local allowed = K.mayUse(pair, guid, function(g)
		if g == guid then
			return partyKey(player)
		end
		return partyKey(owner)
	end, cfg.partyCanUse)
	if not allowed then
		pushBack(player, fromPosition, pair.ownerName .. "'s portal does not answer you.")
		return true
	end
	if kind == "field" then
		local skull = player:getSkull()
		if player:isPzLocked() or skull == SKULL_WHITE or skull == SKULL_RED or skull == SKULL_BLACK then
			pushBack(player, fromPosition, "The portal will not carry you right after fighting other players.")
			return true
		end
		player:teleportTo(P(pair.temple))
		fx(pair.temple, pair.style.travel or pair.style.open)
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "The return portal beside the temple takes you back.")
	else
		-- the exact spot of the cast; a creature standing there moves the arrival next to it
		local dest = pair.returnTo
		local tile = Tile(P(dest))
		if tile and tile:getTopCreature() then
			dest = K.pickSpot(dest, K.ringOffsets(2), spotFree) or dest
		end
		if not player:teleportTo(P(dest)) then
			pushBack(player, fromPosition, "The way back is blocked.")
			return true
		end
		fx(dest, pair.style.travel or pair.style.open)
		if guid == pair.owner then
			T.closePair(pair.owner, "Your town portal closed behind you.")
		end
	end
	return true
end

local fieldStep = MoveEvent()
function fieldStep.onStepIn(creature, item, position, fromPosition)
	return use(creature, item, position, fromPosition, "field")
end
fieldStep:type("stepin")
fieldStep:aid(cfg.aid.field)
fieldStep:register()

local backStep = MoveEvent()
function backStep.onStepIn(creature, item, position, fromPosition)
	return use(creature, item, position, fromPosition, "back")
end
backStep:type("stepin")
backStep:aid(cfg.aid.back)
backStep:register()

-- ---------------------------------------------------------------- loop effects and expiry
local think = GlobalEvent("ChaosTownPortalThink")
function think.onThink(interval)
	local now = os.time()
	for guid, pair in pairs(T.pairs) do
		if now >= pair.expiresAt then
			T.closePair(guid, "Your town portal faded.")
		elseif pair.style.loop then
			if pair.field then
				fx(pair.field, pair.style.loop)
			end
			if pair.back then
				fx(pair.back, pair.style.loop)
			end
		end
	end
	return true
end
think:interval(cfg.loopMs)
think:register()

-- ---------------------------------------------------------------- events
-- taking damage interrupts the channel
local hit = CreatureEvent("ChaosTownPortalHit")
function hit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local cast = T.casts[creature:getId()]
	-- this engine passes damage as negative values (healing positive): any non-zero damage counts
	if cast and primaryType ~= COMBAT_HEALING and ((primaryDamage or 0) ~= 0 or (secondaryDamage or 0) ~= 0) then
		cast.damaged = true
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
hit:register()

local manaHit = CreatureEvent("ChaosTownPortalManaHit")
function manaHit.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local cast = T.casts[creature:getId()]
	if cast and primaryType ~= COMBAT_HEALING and (primaryDamage or 0) < 0 and attacker then
		cast.damaged = true
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
manaHit:register()

local ext = CreatureEvent("ChaosTownPortalExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	if msg.action == "open" or msg.action == "get" then
		sendState(player, msg.action == "open")
	elseif msg.action == "select" then
		local s = K.style(cfg, Chaos.toInt(data.id, 0) or tonumber(data.id))
		if s and s.id == tonumber(data.id) and K.owns(s, facts(player)) then
			player:setStorageValue(ST.style, s.id)
			player:sendTextMessage(MESSAGE_STATUS_SMALL, "Portal style: " .. s.name .. ".")
		else
			player:sendCancelMessage("You do not own that portal style.")
		end
		sendState(player, false)
	elseif msg.action == "cast" then
		if not ChaosRateLimit or ChaosRateLimit.allow(player, "townportal.cast", 500) then
			T.cast(player, "menu")
		end
	end
end
ext:type("extendedopcode")
ext:register()

local logout = CreatureEvent("ChaosTownPortalLogout")
function logout.onLogout(player)
	T.casts[player:getId()] = nil -- the pair stays until it fades
	return true
end
logout:register()

local login = CreatureEvent("ChaosTownPortalLogin")
function login.onLogin(player)
	player:registerEvent("ChaosTownPortalHit")
	player:registerEvent("ChaosTownPortalManaHit")
	player:registerEvent("ChaosTownPortalExtended")
	player:registerEvent("ChaosTownPortalLogout")
	return true
end
login:register()

-- consistency of the styles with the store and the achievements (printed once at startup)
local startup = GlobalEvent("ChaosTownPortalStartup")
function startup.onStartup()
	for _, problem in ipairs(K.validate(cfg, achievementData(), ChaosShopConfig)) do
		print("[Chaos town portal] " .. problem)
	end
	return true
end
startup:register()
