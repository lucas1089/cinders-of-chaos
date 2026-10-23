-- Beta test mode (beta_mode_core.lua; server/README.md "Beta test mode"). Returned as a table, read at the start of the
-- scripts (chaos_constants.lua sets Chaos.betaMode) and by tests/beta_mode_test.lua. Data only. Lua 5.1 / LuaJIT and 5.3.
--
-- enabled = true lifts the per-character and per-account weekly and daily GAMEPLAY limits listed in beta_mode_core.lua
-- (B.LIMITS), so testers can try content without waiting for a week or for a partner. Nothing that is bought with real
-- money changes: the store's weeklyLimit offers (Double Experience Potion, Whetstones, ...) stay capped.
-- Switch it with `chaos-ctl.sh beta-mode on|off|status` (it edits the `enabled = ...` line below with sed) or the admin
-- app (Comandos tab > Modo beta (testes) > Ligar / Desligar); then `chaos-ctl.sh restart` (or /reload scripts) to read it.
-- Keep it OFF on the launch server (docs/LAUNCH.md).
return {
	enabled = false,
	-- Store offer keys (shop_config.lua `key`) whose weekly limit beta mode ALSO lifts. The store sells for Chaos Coins,
	-- which players buy with real money, so the owner decides offer by offer. Owner 2026-10-23: the Orb of Binding is
	-- lifted while the beta coins are free starter coins. Used only while enabled = true.
	storeOfferKeys = {"item:32252x1"}
}
