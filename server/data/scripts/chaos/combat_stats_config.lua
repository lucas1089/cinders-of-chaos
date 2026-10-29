-- combat_stats_config.lua: numbers of the combat stat rows of the client's Skills window (combat_stats.lua,
-- combat_stats_core.lua; server/README.md "Combat stat rows of the Skills window"). Lua 5.1 / LuaJIT and 5.3.
return {
	-- defence stance factor of the engine's Player::getDefense (1 in the defensive stance; the attack stances halve it
	-- for the time between two swings, which a fixed row cannot follow, so the row shows the full value)
	defenseFactor = 1.0,
	-- the percent armour of engine patch 0016, used when the config.lua keys cannot be read
	armorPercentConstant = 250,
	armorPercentMax = 80,
	-- the engine's physical defence of a character with no weapon and no shield (Player::getDefense)
	bareDefense = 7,
	-- ms after login before the first message (the client is still building its windows)
	loginDelayMs = 1500,
	-- ms to wait after an equip, a level, a skill or a tree change before the numbers are worked out (one message
	-- for a burst of moves)
	debounceMs = 250,
	-- at most one answer to a client `get` per this many ms
	getEveryMs = 2000,
}
