-- Beta test mode: pure logic. Config: beta_mode_config.lua (Chaos.betaMode); tests: tests/beta_mode_test.lua; overview:
-- server/README.md "Beta test mode". Lua 5.1 / LuaJIT and Lua 5.3 compatible, no engine calls.
--
-- While Chaos.betaMode.enabled is true, the limits below are lifted: every system asks
--     ChaosBetaMode and ChaosBetaMode.lifted("<key>")
-- at the one place it enforces the limit. Nothing bought with real money is in this list. The store's weeklyLimit offers
-- (shop.lua) are lifted only for the keys the owner names in beta_mode_config.lua `storeOfferKeys` (empty by default).

ChaosBetaMode = ChaosBetaMode or {}
local B = ChaosBetaMode

-- every limit beta mode lifts: key, where it is enforced, what it limits
B.LIMITS = {
	{key = "dungeon_cooldown", where = "dungeons.lua entryProblem / setCooldown",
		text = "the dungeon cooldown after a run (15 minutes after a clear, 5 after a failed run)"},
	{key = "raid_lockout", where = "raid_core.lua K.eligible",
		text = "the weekly raid lockout of each boss: loot from every kill, not once a week"},
	{key = "guildboss_weekly", where = "guildboss_core.lua B.summonError",
		text = "the weekly guild boss: one kill and three summons a week per guild"},
	{key = "bestiary_tasks", where = "bestiary_core.lua C.canAccept",
		text = "the kill tasks: 4 a day and 20 a week per character"},
	{key = "candlemarks_weekly", where = "candlemarks_core.lua K.checkBuy",
		text = "the weekly limits of the Candlemarks shop offers (orbs, gems, supplies, pocket charges, cosmetics)"},
	{key = "faction_offers_weekly", where = "factions_core.lua K.offerState",
		text = "the weekly limits of the faction quartermaster offers (Ash-Blessed Orbs, Forge Whetstones, ...)"},
	{key = "battleground_honor_cap", where = "battleground_core.lua K.honorFor",
		text = "the weekly honor cap of battleground matches (6,000)"},
	{key = "community_daily_cap", where = "community_core.lua C.credit / C.roomToday",
		text = "the daily point caps of the community goal (per character and per source)"}
}

B.byKey = {}
for _, l in ipairs(B.LIMITS) do
	B.byKey[l.key] = l
end

-- is beta mode on in this config?
function B.enabledIn(cfg)
	return type(cfg) == "table" and cfg.enabled == true
end

-- is limit `key` lifted under this config? Unknown keys are never lifted.
function B.liftedIn(cfg, key)
	return B.enabledIn(cfg) and B.byKey[key] ~= nil
end

-- is the weekly limit of store offer `offerKey` lifted under this config? Only an offer the owner named.
function B.storeLiftedIn(cfg, offerKey)
	if not B.enabledIn(cfg) or type(cfg.storeOfferKeys) ~= "table" then
		return false
	end
	for _, k in ipairs(cfg.storeOfferKeys) do
		if k == offerKey then
			return true
		end
	end
	return false
end

-- live (Chaos.betaMode, set by chaos_constants.lua; a /reload reads the file again)
function B.enabled()
	return B.enabledIn(Chaos and Chaos.betaMode)
end

function B.lifted(key)
	return B.liftedIn(Chaos and Chaos.betaMode, key)
end

function B.storeLifted(offerKey)
	return B.storeLiftedIn(Chaos and Chaos.betaMode, offerKey)
end

-- the status line of the tools
function B.statusLine(cfg)
	if B.enabledIn(cfg) then
		return string.format("Beta test mode: ON (%d limits lifted, %d store offers)", #B.LIMITS,
			type(cfg.storeOfferKeys) == "table" and #cfg.storeOfferKeys or 0)
	end
	return "Beta test mode: OFF"
end

return B
