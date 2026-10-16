-- Cooldown channels (server/README.md "Cooldown channels", engine src-patch 0042): which items are potions. Read by
-- cooldown_channels.lua and tests/cooldown_channels_test.lua. The channel delays themselves are config.lua options of
-- the engine (cooldownChannels, moveItemDelay, runeChannelDelay, potionChannelDelay; server/tools/prod_config.py).
-- The engine also loads this file as a script because it lives under data/scripts; it only sets a table.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosCooldownChannelsConfig = {
	-- the base server's potion actions: every <action> of this script in actions.xml is a potion (health, mana and
	-- spirit potions of every tier, the antidote and the stock buff potions of the same script)
	actionsXml = "data/actions/actions.xml",
	potionScripts = {"other/potions.lua"},
	-- the same ids, used when actions.xml cannot be read (the base server's list, 2026-10-16)
	potionIds = {
		7588, 7589, 7590, 7591, 7618, 7620, 8472, 8473, 8474, 8704, 26029, 26030, 26031,
		26733, 26734, 26735, 26736, 26737, 26738,
		28076, 28077, 28078, 28079, 28080, 28081, 28082, 28083,
		28085, 28086, 28087, 28088, 28089, 28090, 28091
	},
	-- the Everfull potions (potions_config.lua) are potions too: their ids are added when that table is loaded
	everfullFrom = "data/scripts/chaos/potions_config.lua"
}
return ChaosCooldownChannelsConfig
