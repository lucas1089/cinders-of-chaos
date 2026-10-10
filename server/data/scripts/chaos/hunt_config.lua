-- Hunt tracker (hunt.lua, hunt_core.lua, client game_hunt). Returned as a table, loaded as Chaos.huntConfig.
-- See server/README.md "Hunt tracker". Lua 5.1 / LuaJIT compatible.
return {
	-- a session starts by itself at login; the clock only runs while the character is online and not paused
	autoStart = true,
	-- after a logout the session is kept this long, so a relog (or a short disconnect) goes on with the same numbers
	keepOfflineMinutes = 30,
	-- the rates (per hour) are shown from this many seconds of session time on; before that they would jump around
	minRateSeconds = 30,

	-- how often (ms) the supply count runs and the open window gets a fresh state
	thinkMs = 2000,
	-- used supplies are counted from the inventory: a potion, rune or arrow less than at the last count is "used".
	-- In a protection zone nothing is counted (putting potions in the depot or selling them is not using them).
	countSuppliesInPz = false,

	-- EventCallback indexes (lower runs first). onDropLoot: 0 stock loot, 1 Chaos loot layer, 2 paragon gold /
	-- rift key / AUTO SELLER, 2.5 loot filter snapshot, 2.7 store pouches, 3 autoloot. The corpse is read twice, before and
	-- after the index-2 callbacks, and per item the larger count is kept: items the auto seller takes out and the coins
	-- or keys added at 2 both count.
	lootBeforeIndex = 1.9,
	lootAfterIndex = 2.4,
	-- onGainExperience: after every bonus (stages 0, store buffs 5, rift cap 100) so the number is what is really gained
	expIndex = 1000,
	-- onTargetCombat: registers the damage counter on what a player attacks (after combat_fx at 50)
	targetIndex = 60,

	-- gold value of the coins (no NPC buys them); everything else uses the NPC sell price (sell_prices.lua)
	coins = {[2148] = 1, [2152] = 100, [2160] = 10000},
	-- gold value of items no NPC buys, by server id (orbs are tracked as Chaos drops at 0 gold unless set here)
	extraValues = {},

	-- Chaos drops list: these ids, plus every unique, every item with a rarity and every "... Orb" / "Orb of ..."
	orbIds = {29856, 29857, 29851, 24691, 24697, 24688, 29855},

	-- rows sent to the client per list (the totals always count everything)
	maxKills = 40,
	maxLoot = 60,
	maxSupplies = 30,
	maxSpecials = 40
}
