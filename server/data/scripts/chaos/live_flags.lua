-- Systems that are switched on, published for the website's news gates (website/overlay/plugins/chaos/news_lib.php reads this file from
-- CHAOS_SERVER_DATA: `name = true` is on, `name = "YYYY-MM-DD"` is on since that day; CHAOS_LIVE_FLAGS of site.env wins; website/README.md
-- "Featured news (O688)"). A plain table, loaded with dofile by nothing in the game; Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	-- the spell upgrades of O686: live since 2026-11-21 (O709, spell_ranks_config.lua `enabled = true`). The four news entries spell-ranks,
	-- spell-forms, spell-awakening and spell-combos open on that day and the banner is fresh from it
	spell_upgrades = "2026-11-21",
}
