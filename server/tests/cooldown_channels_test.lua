-- Run from the server/ folder: luajit tests/cooldown_channels_test.lua (and lua5.3; CI runs both)
-- Cooldown channels (engine src-patch 0042, server/README.md "Cooldown channels"): the potion list of
-- cooldown_channels_core.lua / cooldown_channels_config.lua, and cooldown_channels.lua against a mocked engine (every
-- potion registered on COOLDOWN_CHANNEL_POTION, nothing without the engine function).
dofile("data/scripts/chaos/cooldown_channels_core.lua")
local K = ChaosCooldownChannelsCore
local cfg = dofile("data/scripts/chaos/cooldown_channels_config.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	if not v then
		error(m or "not ok", 2)
	end
end
local function has(list, id)
	for _, v in ipairs(list) do
		if v == id then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- the engine's channel numbers
eq(K.channelValue("potion"), 5, "potion channel = enums.h COOLDOWN_CHANNEL_POTION")
eq(K.channelValue("attack"), 2, "attack channel")
eq(K.channelValue("heal"), 3, "heal channel")
COOLDOWN_CHANNEL_POTION = 9
eq(K.channelValue("potion"), 9, "the engine's global wins")
COOLDOWN_CHANNEL_POTION = nil

-- ---------------------------------------------------------------- actions.xml parsing
local xml = [[
<actions>
	<action itemid="7618" script="other/potions.lua" />
	<action itemid = "7620" script = "other/potions.lua"/>
	<!-- <action itemid="9999" script="other/potions.lua" /> -->
	<action fromid="26733" toid="26735" script="other/potions.lua" />
	<action itemid="100;101" script="other/potions.lua" />
	<action itemid="7439" script="other/strengthening_potions.lua" />
	<action itemid="2160" script="other/changegold.lua" />
	<action fromid="1" toid="999999" script="other/potions.lua" />
</actions>]]
local ids = K.actionIds(xml, {"other/potions.lua"})
eq(table.concat(ids, ","), "100,101,7618,7620,26733,26734,26735", "potion actions, commented line and huge range skipped")
ok(not has(ids, 7439), "a buff potion of another script stays on the action channel")
eq(#K.actionIds(xml, {}), 0, "no script asked: nothing")
eq(#K.actionIds(nil, {"other/potions.lua"}), 0, "no file")

-- ---------------------------------------------------------------- the potion list
local list, fromXml = K.potionIds(cfg, xml, {32085, 32086})
ok(fromXml, "read from actions.xml")
ok(has(list, 7618) and has(list, 32085) and has(list, 32086), "stock and Everfull potions")
ok(not has(list, 7588), "the config list is only the fallback")
list, fromXml = K.potionIds(cfg, nil, {32085})
ok(not fromXml, "no actions.xml: the config list")
ok(has(list, 7588) and has(list, 28091) and has(list, 32085), "config list plus Everfull")
local seen = {}
for i, id in ipairs(list) do
	ok(not seen[id], "no id twice: " .. id)
	seen[id] = true
	if i > 1 then
		ok(list[i - 1] < id, "sorted")
	end
end
-- the fallback list is the base server's potion script list (no rune, no buff potion of another script)
for _, id in ipairs({2268, 2273, 2265, 7439, 7440, 7443}) do
	ok(not has(cfg.potionIds, id), "not a potion: " .. id)
end

-- ---------------------------------------------------------------- the engine file against a mocked engine
local registered = {}
local printed = {}
local realPrint = print
print = function(s)
	printed[#printed + 1] = s
end
ChaosPotionsConfig = {everfull = {{id = 32085}, {id = 32086}}}
Game = {setItemCooldownChannel = function(id, channel)
	registered[id] = channel
	return true
end}
COOLDOWN_CHANNEL_POTION = 5
local realOpen = io.open
io.open = function(path, mode)
	if path == cfg.actionsXml then
		return {read = function() return xml end, close = function() end}
	end
	return realOpen(path, mode)
end
dofile("data/scripts/chaos/cooldown_channels.lua")
io.open = realOpen
eq(registered[7618], 5, "stock potion on the potion channel")
eq(registered[26734], 5, "range potion")
eq(registered[32086], 5, "Everfull potion")
eq(registered[7439], nil, "buff potion of another script untouched")
eq(#printed, 0, "nothing printed when actions.xml is read")

-- no actions.xml: the config list, and a note on the console
registered, printed = {}, {}
io.open = function(path, mode)
	if path == cfg.actionsXml then
		return nil
	end
	return realOpen(path, mode)
end
dofile("data/scripts/chaos/cooldown_channels.lua")
io.open = realOpen
eq(registered[7588], 5, "fallback list registered")
eq(#printed, 1, "fallback noted")

-- an engine without src-patch 0042: nothing registered, one console line
registered, printed = {}, {}
Game = {}
dofile("data/scripts/chaos/cooldown_channels.lua")
eq(next(registered), nil, "no engine function: nothing")
eq(#printed, 1, "missing engine function noted")
print = realPrint

print("cooldown_channels_test: OK")
