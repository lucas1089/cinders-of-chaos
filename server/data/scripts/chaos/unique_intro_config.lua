-- unique_intro_config.lua: the one-time line a character reads when it finds its first unique (O467).
-- Rules: unique_intro_core.lua (tests/unique_intro_test.lua); engine side: unique_intro.lua; hooks: loot.lua (a unique
-- drop), retention_loot.lua (the first-unique gift), itemsets.lua, conquest.lua, raid.lua, uber.lua, worldboss.lua,
-- pocketboss.lua, invasion.lua (each calls ChaosUniqueIntro.found(player) where it hands the player a unique).
-- server/README.md "Uniques explain themselves (O467)". Lua 5.1 / 5.3 / LuaJIT compatible.

return {
	enabled = true,
	-- player storage 7103090 (block 7103090 - 7103099, README "Storage keys"): 1 once the line was shown, else unset
	storage = 7103090,
	-- English; the pt-BR text is in i18n_strings.lua. The first sentence says what a unique is, the second where to read
	-- what this one does (the right-click entry of client game_codex, "Open in Codex").
	text = "A unique is a named item with fixed stats and one power of its own. Right-click it and choose Open in Codex to see what it does.",
}
