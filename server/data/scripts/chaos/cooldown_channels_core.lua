-- Cooldown channels: pure rules (no engine calls) for cooldown_channels.lua and tests/cooldown_channels_test.lua.
-- Engine src-patch 0042 (server/README.md "Cooldown channels") keeps one next-action time per channel: attack runes,
-- healing runes and support runes by their spell group, item moves, other uses, and the potions. The engine cannot tell
-- a potion from any other scripted item, so this list names them (Game.setItemCooldownChannel).
--   ChaosCooldownChannelsCore.actionIds(xml, scripts)    item ids of the <action> lines of actions.xml whose script is
--                                                         one of `scripts` (itemid="a", itemid="a;b", fromid/toid)
--   ChaosCooldownChannelsCore.potionIds(cfg, xml, extra) the potion item ids: from actions.xml when it could be read
--                                                         (else cfg.potionIds), plus `extra` (the Everfull potions)
--   ChaosCooldownChannelsCore.channelValue(name)          "potion" -> COOLDOWN_CHANNEL_POTION (5), ...
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosCooldownChannelsCore = ChaosCooldownChannelsCore or {}
local K = ChaosCooldownChannelsCore

-- the engine's numbers (enums.h CooldownChannel_t); the globals win when the engine has them
K.CHANNELS = {action = 0, move = 1, attack = 2, heal = 3, support = 4, potion = 5}
local GLOBALS = {
	action = "COOLDOWN_CHANNEL_ACTION", move = "COOLDOWN_CHANNEL_MOVE", attack = "COOLDOWN_CHANNEL_ATTACK",
	heal = "COOLDOWN_CHANNEL_HEAL", support = "COOLDOWN_CHANNEL_SUPPORT", potion = "COOLDOWN_CHANNEL_POTION"
}

function K.channelValue(name)
	local g = GLOBALS[name]
	local v = g and rawget(_G, g)
	if type(v) == "number" then
		return v
	end
	return K.CHANNELS[name]
end

local function attrsOf(tag)
	local a = {}
	for k, v in tag:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do
		a[k:lower()] = v
	end
	return a
end

local function addRange(out, from, to)
	from, to = tonumber(from), tonumber(to)
	if not from or not to or to < from or to - from > 1000 then
		return
	end
	for id = from, to do
		out[id] = true
	end
end

local function sortedKeys(set)
	local list = {}
	for id in pairs(set) do
		list[#list + 1] = id
	end
	table.sort(list)
	return list
end

function K.actionIds(xml, scripts)
	local want = {}
	for _, s in ipairs(scripts or {}) do
		want[s:lower()] = true
	end
	local set = {}
	xml = (xml or ""):gsub("<!%-%-.-%-%->", "")
	for tag in xml:gmatch("<action%s[^>]*>") do
		local a = attrsOf(tag)
		if a.script and want[a.script:lower()] then
			if a.itemid then
				for part in a.itemid:gmatch("[^;,]+") do
					local from, to = part:match("^%s*(%d+)%s*%-%s*(%d+)%s*$")
					if from then
						addRange(set, from, to)
					elseif tonumber(part) then
						set[tonumber(part)] = true
					end
				end
			end
			if a.fromid and a.toid then
				addRange(set, a.fromid, a.toid)
			end
		end
	end
	return sortedKeys(set)
end

function K.potionIds(cfg, xml, extra)
	local set = {}
	local fromXml = xml and K.actionIds(xml, cfg.potionScripts) or {}
	local source = #fromXml > 0 and fromXml or (cfg.potionIds or {})
	for _, id in ipairs(source) do
		set[id] = true
	end
	for _, id in ipairs(extra or {}) do
		if tonumber(id) then
			set[tonumber(id)] = true
		end
	end
	return sortedKeys(set), #fromXml > 0
end

return K
