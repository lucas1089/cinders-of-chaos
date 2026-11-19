-- Keeper of the Pinnacle (O667; server/data/scripts/chaos/pinnacle.lua, pinnacle_config.lua, pinnacle_core.lua; server/README.md "Pinnacle
-- bosses (O667)"). Runs in the NPC's own Lua state: it reads the fragment storages (read-only) and opens the modal window of the bosses;
-- the answers (Open, Focus) are handled and checked again by pinnacle.lua in the main state. Keywords: pinnacle, fragment, set, boss,
-- open, focus.
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

function onCreatureAppear(cid)			npcHandler:onCreatureAppear(cid)			end
function onCreatureDisappear(cid)		npcHandler:onCreatureDisappear(cid)			end
-- only the nearest NPC answers a greeting (data/lib/chaos_npc_focus.lua)
if not ChaosNpcFocus then pcall(dofile, "data/lib/chaos_npc_focus.lua") end
function onCreatureSay(cid, type, msg)
	if not ChaosNpcFocus or ChaosNpcFocus.hears(cid, npcHandler) then
		npcHandler:onCreatureSay(cid, type, msg)
	end
end
function onThink()				npcHandler:onThink()					end

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosI18n or not ChaosI18n.npcText then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosPinnacleCore then
	dofile("data/scripts/chaos/pinnacle_core.lua")
end
local K = ChaosPinnacleCore
local cfg = dofile("data/scripts/chaos/pinnacle_config.lua")
-- the player's language (the stored one: this state never sees the client's hello; i18n_core.lua "NPC scripts")
local function t(cid, key, ...)
	return ChaosI18n.npcText(cid, key, ...)
end

local function has(text, ...)
	for _, w in ipairs({...}) do
		if text:find(w, 1, true) then
			return true
		end
	end
	return false
end

-- one line of the window for a boss: the level it opens at and the four kinds held
local function bossLine(cid, player, i, boss, focus)
	local have = K.have(cfg, function(key) return player:getStorageValue(key) end, i)
	local parts = {}
	for kind = 1, 4 do
		parts[#parts + 1] = string.format("%s %d", boss.fragments[kind], math.max(0, have[kind] or 0))
	end
	return t(cid, "%s (from level %d)%s: %s", boss.name, boss.minLevel, focus == i and t(cid, " [focus]") or "", table.concat(parts, ", "))
end

local function openWindow(cid, player)
	if not ModalWindow then
		return false
	end
	local focus = math.max(0, tonumber(player:getStorageValue(cfg.storage.base + cfg.storage.focus)) or 0)
	local lines, names = {}, {}
	for i, boss in ipairs(cfg.bosses) do
		lines[#lines + 1] = bossLine(cid, player, i, boss, focus)
		names[#names + 1] = boss.name
	end
	local s = cfg.fragments.sources
	local text = t(cid, "Four Ascended bosses wait on the pinnacle. Each opens with a whole set of four fragments, one of each kind. A waystone map of tier %d or higher, a rift of tier %d and an Omen guardian each drop one kind; any of the three may drop the keystone.\n\n%s\n\nOpen spends a set and takes your party within reach along. Focus makes your fragments drop for the chosen boss.",
		s.waystone.minTier, s.rift.minTier, table.concat(lines, "\n"))
	local w = ModalWindow(cfg.modal.list, t(cid, "The Pinnacle"), text)
	for i, name in ipairs(names) do
		w:addChoice(i, name)
	end
	w:addButton(1, t(cid, "Open"))
	w:addButton(2, t(cid, "Focus"))
	w:addButton(3, t(cid, "Close"))
	w:setDefaultEnterButton(1)
	w:setDefaultEscapeButton(3)
	w:sendToPlayer(player)
	return true
end

local function creatureSayCallback(cid, type, msg)
	if not npcHandler:isFocused(cid) then
		return false
	end
	local player = Player(cid)
	if not player then
		return false
	end
	local text = msg:lower()
	if not has(text, "pinnacle", "fragment", "set", "boss", "open", "focus", "ascended", "key") then
		return false
	end
	if not cfg.enabled then
		npcHandler:say(t(cid, "The pinnacle is closed for now. Come back later."), cid)
		return true
	end
	npcHandler:say(t(cid, "Choose a boss. A whole set of fragments opens its arena: alone, or with a party of up to %d.", cfg.party.max), cid)
	openWindow(cid, player)
	return true
end

npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
ChaosI18n.npcMessages(npcHandler) -- greet, farewell and walk away in the player's language
npcHandler:addModule(FocusModule:new())
