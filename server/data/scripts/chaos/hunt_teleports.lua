-- Hunt teleports (server/README.md "Hunt teleports"): the teleports of the planned content hunts in the teleport room
-- of Cinderhold. The logic is in hunt_teleports_core.lua (pure, tests/hunt_teleports_test.lua), the numbers and
-- texts in hunt_teleports_config.lua, the places in data/lib/chaos_hunt_places.lua (written by
-- server/tools/install_content_areas.py together with the room's new alcoves, the hunts and their display monsters).
--   startup  a magic forcefield with action id `aid` on each placed plan's teleport tile (kept when it is already
--            there), its description and the sign behind it name the hunt and its level band
--   labels   every floatText.interval ms the label floats over each teleport for the players near it, each in their
--            own language (the base room labels its teleports the same way: a monster-say text); the floors' level
--            ranges and "Quests" over the quest hall too
--   step in  below the band's floor: back where the player came from, a poff and the reason in the player's
--            language; else to the plan's arrival tile with the teleport effect at both ends
--   exits    areagen.lua's exit portal (action id 47951) asks ChaosHuntTeleports.backFor: a placed plan's exit sends
--            players back in front of the plan's own teleport (its floor and slot) instead of the temple
--   ways back the hunts of cfg.returns (added to the hall without a base teleport, so without a way back on the
--            map) get a forcefield with the same action id beside their arrival at startup (`at`, else the nearest
--            free tile, ChaosHuntTeleportsCore.pickReturnTile); it sends players in front of the hunt's own teleport
--            and the label "Back to the teleport room" floats over it
--   display  the display monsters in the closed cells are harmless: HT.isDisplay / isDisplaySpot for the other
--            systems (boss mechanics, monster tiers, treasure goblin skip them), onTargetCombat refuses their hits
-- Assumed engine API (TFS 1.4): Tile (getGround, getItemById, hasFlag, getHouse, getDownItemCount), Game.createItem,
-- Item:setActionId/setAttribute, MoveEvent stepin by aid, GlobalEvent startup, EventCallback onTargetCombat,
-- Player:teleportTo/sendCancelMessage/sendTextMessage.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/hunt_teleports_core.lua")
ChaosHuntTeleportsConfig = dofile("data/scripts/chaos/hunt_teleports_config.lua")

ChaosHuntTeleports = ChaosHuntTeleports or {}
local HT = ChaosHuntTeleports
local H = ChaosHuntTeleportsCore
local cfg = ChaosHuntTeleportsConfig

local PLACES = "data/lib/chaos_hunt_places.lua"

local function loadPlaces()
	local f = io.open(PLACES, "r")
	if not f then
		return nil
	end
	f:close()
	local ok, places = pcall(dofile, PLACES)
	if not ok then
		print("[hunt teleports] " .. PLACES .. ": " .. tostring(places))
		return nil
	end
	return places
end

local function P(p)
	return Position(p.x, p.y, p.z)
end

local function langOf(player)
	if Chaos.lang then
		local ok, l = pcall(Chaos.lang, player)
		if ok then
			return H.lang(l)
		end
	end
	return "en"
end

function HT.reload()
	local places = loadPlaces()
	local problems = H.validate(cfg, places)
	for _, p in ipairs(H.validateReturns(cfg)) do
		problems[#problems + 1] = p
	end
	for _, p in ipairs(problems) do
		print("[hunt teleports] " .. p)
	end
	HT.idx = H.index(cfg, places)
	return HT.idx
end
HT.reload()

-- for areagen.lua's exit portal: the room's back tile when `pos` is the exit of a placed plan
function HT.backFor(pos)
	if not cfg.enabled then
		return nil
	end
	local b = H.backFor(HT.idx, pos)
	return b and P(b) or nil
end

-- display monsters (the two in the closed cells beside each teleport): found by their spot, since the spawn file's
-- chaoshunt attribute is not visible to Lua. Other systems ask HT.isDisplaySpot(position) in their onSpawn (the
-- monster is not placed yet there) or HT.isDisplay(monster) later.
function HT.isDisplaySpot(pos)
	return H.isDisplaySpot(cfg, pos)
end

function HT.isDisplay(creature)
	if not creature or not creature:isMonster() or creature:getMaster() then
		return false
	end
	return H.isDisplaySpot(cfg, creature:getPosition())
end

-- a display monster never hurts anyone: every target or area hit of it is refused (the engine asks onTargetCombat
-- for each creature a combat of it would reach, melee included). It may still turn to a player; it cannot act on it.
local passive = EventCallback
passive.onTargetCombat = function(creature, target)
	if creature and target and HT.isDisplay(creature) then
		return RETURNVALUE_NOTPOSSIBLE
	end
	return RETURNVALUE_NOERROR
end
passive:register(-50)

local function placePortal(entry)
	local pos = P(entry.teleport)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return false, string.format("%s: no tile at %d,%d,%d (run install_content_areas.py)", entry.id, pos.x, pos.y, pos.z)
	end
	local item = tile:getItemById(cfg.items.portal)
	if item and item:getActionId() ~= cfg.aid then
		return false, string.format("%s: another teleport stands at %d,%d,%d", entry.id, pos.x, pos.y, pos.z)
	end
	if not item then
		item = Game.createItem(cfg.items.portal, 1, pos)
		if not item then
			return false, entry.id .. ": the teleport could not be created"
		end
		item:setActionId(cfg.aid)
	end
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, H.label(cfg, entry, "en") .. " / " .. H.label(cfg, entry, "pt-BR") .. ".")
	if entry.sign then
		local stile = Tile(P(entry.sign))
		local sign = stile and stile:getItemById(cfg.items.sign)
		if sign then
			sign:setAttribute(ITEM_ATTRIBUTE_TEXT, H.signText(cfg, entry))
		end
	end
	return true
end

-- what a tile is for a way back (ChaosHuntTeleportsCore.pickReturnTile): walk (ground, nothing blocking, no stairs
-- or hole) and spot (also no protection zone, no house, no teleport or field, nothing lying on it); nil: no tile
local function returnInfo(p)
	local tile = Tile(P(p))
	if not tile or not tile:getGround() then
		return nil
	end
	local walk = not tile:hasFlag(TILESTATE_BLOCKSOLID) and not tile:hasFlag(TILESTATE_BLOCKPATH)
		and not tile:hasFlag(TILESTATE_FLOORCHANGE)
	local spot = walk and not tile:hasFlag(TILESTATE_PROTECTIONZONE) and not tile:hasFlag(TILESTATE_TELEPORT)
		and not tile:hasFlag(TILESTATE_MAGICFIELD) and not tile:getHouse() and (tile:getDownItemCount() or 0) == 0
	return {walk = walk, spot = spot}
end

-- our forcefield within the radius of the arrival (an earlier startup's, kept)
local function placedReturn(r, radius)
	local a = r.arrival
	for dy = -radius, radius do
		for dx = -radius, radius do
			local p = {x = a.x + dx, y = a.y + dy, z = a.z}
			local tile = Tile(P(p))
			local item = tile and tile:getItemById(cfg.items.portal)
			if item and item:getActionId() == cfg.aid then
				return p, item
			end
		end
	end
	return nil
end

local function placeReturn(r)
	local radius = cfg.returns and cfg.returns.radius or 4
	local at, item = placedReturn(r, radius)
	if not at then
		at = H.pickReturnTile(r.arrival, radius, returnInfo, r.at)
		if not at then
			return false, string.format("%s: no free tile within %d of the arrival %d,%d,%d for the way back", r.id, radius,
				r.arrival.x, r.arrival.y, r.arrival.z)
		end
		item = Game.createItem(cfg.items.portal, 1, P(at))
		if not item then
			return false, r.id .. ": the way back could not be created"
		end
		item:setActionId(cfg.aid)
	end
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, H.returnLabel(cfg, "en") .. " / " .. H.returnLabel(cfg, "pt-BR") .. ".")
	r.pos = at
	HT.idx.byReturn[H.key(at)] = r
	if r.at and H.key(at) ~= H.key(r.at) then
		print(string.format("[hunt teleports] %s: the way back stands at %d,%d,%d (its `at` is not free)", r.id, at.x, at.y, at.z))
	end
	return true
end

local startup = GlobalEvent("ChaosHuntTeleports")
function startup.onStartup()
	if not cfg.enabled then
		return true
	end
	local idx = HT.reload()
	local made = 0
	for _, entry in ipairs(idx.list) do
		local ok, err = placePortal(entry)
		if ok then
			made = made + 1
		else
			print("[hunt teleports] " .. err)
		end
	end
	-- the hall order: the base server's hunts keep their map teleports; their signs name the hunt and its band
	for _, entry in ipairs(idx.base or {}) do
		local stile = entry.sign and Tile(P(entry.sign))
		local sign = stile and stile:getItemById(cfg.items.sign)
		if sign then
			sign:setAttribute(ITEM_ATTRIBUTE_TEXT, H.signText(cfg, entry))
		end
	end
	-- the ways back of the hunts without one on the map (cfg.returns)
	local backs = 0
	for _, r in ipairs(idx.returns or {}) do
		local ok, err = placeReturn(r)
		if ok then
			backs = backs + 1
		else
			print("[hunt teleports] " .. err)
		end
	end
	if #(idx.returns or {}) > 0 then
		print(string.format("[hunt teleports] %d of %d ways back ready", backs, #idx.returns))
	end
	if #idx.list == 0 then
		print("[hunt teleports] no placed hunts (" .. PLACES .. " missing: run server/tools/install_content_areas.py)")
	else
		print(string.format("[hunt teleports] %d of %d teleports ready", made, #idx.list))
	end
	return true
end
startup:register()

local float = GlobalEvent("ChaosHuntTeleportsLabels")
function float.onThink()
	if not cfg.enabled or not HT.idx then
		return true
	end
	local r = cfg.floatText.range
	for _, list in ipairs({HT.idx.list, HT.idx.base or {}}) do
		for _, entry in ipairs(list) do
			local pos = P(entry.teleport)
			for _, spec in ipairs(Game.getSpectators(pos, false, true, r, r, r, r) or {}) do
				spec:say(H.label(cfg, entry, langOf(spec)), TALKTYPE_MONSTER_SAY, false, spec, pos)
			end
		end
	end
	-- the ways back: "Back to the teleport room" over each
	for _, ret in ipairs(HT.idx.returns or {}) do
		if ret.pos then
			local pos = P(ret.pos)
			for _, spec in ipairs(Game.getSpectators(pos, false, true, r, r, r, r) or {}) do
				spec:say(H.returnLabel(cfg, langOf(spec)), TALKTYPE_MONSTER_SAY, false, spec, pos)
			end
		end
	end
	-- the floors: "Floor 7: levels 1-80" in the corridor, the next floor's band over the stairs up
	if cfg.hall and HT.idx.floors and next(HT.idx.floors) then
		local seen = {}
		for _, l in ipairs(H.floorLabels(cfg, HT.idx, "en")) do
			local key = H.key(l.pos)
			if not seen[key] then
				seen[key] = true
				local pos = P(l.pos)
				for _, spec in ipairs(Game.getSpectators(pos, false, true, r, r, r, r) or {}) do
					for _, ll in ipairs(H.floorLabels(cfg, HT.idx, langOf(spec))) do
						if H.key(ll.pos) == key then
							spec:say(ll.text, TALKTYPE_MONSTER_SAY, false, spec, pos)
						end
					end
				end
			end
		end
	end
	-- the quest hall: "Quests" over its corridor, for the players in it (the hall is 33 columns wide), and where the
	-- plaza's aisle meets the corridor to it, for the players near
	if cfg.hall and HT.idx.quests then
		local areas = {{HT.idx.quests.label, 17, 4}, {HT.idx.quests.entrance, r, r}}
		for i, a in ipairs(areas) do
			if a[1] then
				local pos = P(a[1])
				for _, spec in ipairs(Game.getSpectators(pos, false, true, a[2], a[2], a[3], a[3]) or {}) do
					local l = H.questLabels(cfg, HT.idx, langOf(spec))[i]
					if l then
						spec:say(l.text, TALKTYPE_MONSTER_SAY, false, spec, pos)
					end
				end
			end
		end
	end
	return true
end
if (cfg.floatText and cfg.floatText.interval or 0) > 0 then
	float:interval(cfg.floatText.interval)
	float:register()
end

local step = MoveEvent()
step:type("stepin")
function step.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if not player then
		return true
	end
	-- a way back (cfg.returns): in front of the hunt's own teleport of the hall
	local back = cfg.enabled and H.returnFor(HT.idx, position)
	if back then
		position:sendMagicEffect(cfg.effects.go)
		player:teleportTo(P(back))
		player:getPosition():sendMagicEffect(cfg.effects.go)
		return true
	end
	local entry = HT.idx and HT.idx.byTeleport[H.key(position)]
	if not cfg.enabled or not entry then
		player:teleportTo(fromPosition, true)
		return true
	end
	local lang = langOf(player)
	local ok, msg = H.enter(cfg, entry, player:getLevel(), lang)
	if not ok then
		player:teleportTo(fromPosition, true)
		position:sendMagicEffect(cfg.effects.refuse)
		player:sendCancelMessage(msg)
		return true
	end
	position:sendMagicEffect(cfg.effects.go)
	player:teleportTo(P(entry.arrival))
	player:getPosition():sendMagicEffect(cfg.effects.go)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, msg)
	return true
end
step:aid(ChaosHuntTeleportsConfig.aid)
step:register()
