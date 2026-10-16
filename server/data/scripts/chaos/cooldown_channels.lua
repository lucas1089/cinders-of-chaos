-- Cooldown channels (engine src-patch 0042; server/README.md "Cooldown channels"). The engine keeps a cooldown channel
-- per kind of action: attack, healing and support runes by their spell group, item moves, other uses, and potions; the
-- auto attack has a timer of its own. It knows the runes by their spells; this script names the potions: every potion
-- of the base potion script (data/actions/actions.xml) and the Everfull potions (potions_config.lua) go on
-- COOLDOWN_CHANNEL_POTION, so a potion never waits for a rune, a move or a door, and never holds one of them.
-- Rules: cooldown_channels_core.lua (tests/cooldown_channels_test.lua). Lua 5.1 / LuaJIT compatible.

if not ChaosCooldownChannelsCore or not ChaosCooldownChannelsCore.potionIds then
	dofile("data/scripts/chaos/cooldown_channels_core.lua")
end
dofile("data/scripts/chaos/cooldown_channels_config.lua")

local K = ChaosCooldownChannelsCore
local cfg = ChaosCooldownChannelsConfig

local function readFile(path)
	local ok, text = pcall(function()
		local f = io.open(path, "rb")
		if not f then
			return nil
		end
		local t = f:read("*a")
		f:close()
		return t
	end)
	return ok and text or nil
end

local function everfullIds()
	if not ChaosPotionsConfig and cfg.everfullFrom then
		pcall(dofile, cfg.everfullFrom)
	end
	local ids = {}
	for _, e in ipairs((ChaosPotionsConfig and ChaosPotionsConfig.everfull) or {}) do
		ids[#ids + 1] = e.id
	end
	return ids
end

if not (Game and Game.setItemCooldownChannel) then
	print("[Chaos] cooldown channels: the engine has no Game.setItemCooldownChannel (src-patch 0042); potions keep " ..
		"the shared action delay")
	return
end

local ids, fromXml = K.potionIds(cfg, readFile(cfg.actionsXml), everfullIds())
local channel = K.channelValue("potion")
local set = 0
for _, id in ipairs(ids) do
	if Game.setItemCooldownChannel(id, channel) then
		set = set + 1
	end
end
if not fromXml then
	print("[Chaos] cooldown channels: " .. cfg.actionsXml .. " not read, the potion list of the config is used")
end
if set == 0 then
	print("[Chaos] cooldown channels: no potion item found")
end
