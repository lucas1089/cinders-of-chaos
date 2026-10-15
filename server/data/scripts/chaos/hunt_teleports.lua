-- Hunt teleports (server/README.md "Hunt teleports"): the teleports of the planned content hunts in the teleport room
-- of Cinderhold. The logic is in hunt_teleports_core.lua (pure, tests/hunt_teleports_test.lua), the numbers and
-- texts in hunt_teleports_config.lua, the places in data/lib/chaos_hunt_places.lua (written by
-- server/tools/install_content_areas.py together with the room's new alcoves, the hunts and their display monsters).
--   startup  a magic forcefield with action id `aid` on each placed plan's teleport tile (kept when it is already
--            there), its description and the sign behind it name the hunt and its level band
--   labels   every floatText.interval ms the label floats over each teleport for the players near it, each in their
--            own language (the base room labels its teleports the same way: a monster-say text)
--   step in  below the band's floor: back where the player came from, a poff and the reason in the player's
--            language; else to the plan's arrival tile with the teleport effect at both ends
--   exits    areagen.lua's exit portal (action id 47951) asks ChaosHuntTeleports.backFor: a placed plan's exit sends
--            players back to the room instead of the temple
-- Assumed engine API (TFS 1.4): Tile, Game.createItem, Item:setActionId/setAttribute, MoveEvent stepin by aid,
-- GlobalEvent startup, Player:teleportTo/sendCancelMessage/sendTextMessage.

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
	for _, entry in ipairs(HT.idx.list) do
		local pos = P(entry.teleport)
		for _, spec in ipairs(Game.getSpectators(pos, false, true, r, r, r, r) or {}) do
			spec:say(H.label(cfg, entry, langOf(spec)), TALKTYPE_MONSTER_SAY, false, spec, pos)
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
