-- Dungeon difficulty (dungeons.lua, client game_dungeons): what each of the six difficulties does to the dungeon's
-- monsters. The numbers are the ones the client's difficulty panel shows (client/overlay/modules/game_dungeons/
-- dungeons.otui, DifficultyInfo; tests/dungeons_difficulty_test.lua checks that both agree).
-- Loaded with  ChaosDungeonDifficulty = dofile("data/scripts/chaos/dungeons_difficulty.lua")  (pure, no engine calls;
-- also harmless when the script loader runs it on its own). Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   health      percent of the monster's max health (applied once per monster when the run sees it)
--   damage      percent of the damage the monster deals to the run's players (health and mana)
--   experience  bonus percent on the experience of its kills (the run's players)
--   gold        bonus percent on the gold coins in its corpse (fractions a chance of one more coin)
--   loot        every entry of its loot table gets one more roll at this percent of its chance (extra items)

local D = {}

D.levels = {
	{health = 100, damage = 100, experience = 0, gold = 0, loot = 0},
	{health = 200, damage = 130, experience = 75, gold = 75, loot = 0},
	{health = 320, damage = 190, experience = 100, gold = 100, loot = 15},
	{health = 500, damage = 280, experience = 200, gold = 200, loot = 30},
	{health = 800, damage = 400, experience = 300, gold = 300, loot = 45},
	{health = 1300, damage = 600, experience = 400, gold = 400, loot = 60}
}
D.coins = {[2148] = true, [2152] = true, [2160] = true} -- gold, platinum, crystal coins

-- The boss chest of a generated dungeon (areagen_config.lua `dungeon.chest`, areagen.lua AG.giveChest): every finisher
-- gets it at the end of a won run. Per difficulty: gear pieces from the boss's own loot table, their rarity floor
-- (loot_config.lua gear.names: 3 Rare, 4 Epic, 5 Legendary, 6 Exotic, 7 Mythic, 8 Chaos) and the loot layer's bonus
-- steps of `tier`, item levels above the boss drop (chaos_item_mods.lua M.sourceLevel of the boss level, tier boss;
-- capped at its max), the dungeon's gold x (1 + the difficulty's gold bonus) to the bank, currency rolls at `tier`.
-- The steps follow the Vault's boss curve (100-225%: a quarter more work per difficulty, so a little more each step).
D.chestLevels = {
	{pieces = 1, rarity = 3, itemLevel = 0, tier = "rare", currency = 1},
	{pieces = 1, rarity = 4, itemLevel = 1, tier = "rare", currency = 1},
	{pieces = 2, rarity = 5, itemLevel = 2, tier = "legendary", currency = 1},
	{pieces = 2, rarity = 6, itemLevel = 3, tier = "legendary", currency = 2},
	{pieces = 3, rarity = 7, itemLevel = 4, tier = "boss", currency = 2},
	{pieces = 3, rarity = 8, itemLevel = 5, tier = "boss", currency = 3}
}

-- what one finisher's chest holds at this difficulty: {pieces, rarity, itemLevel (bonus), tier, currency, gold}
-- spec = the dungeon's chest table ({gold = n})
function D.chest(spec, difficulty)
	local _, d = D.of(difficulty)
	local c = D.chestLevels[d]
	local gold = math.floor((spec and spec.gold or 0) * (1 + D.levels[d].gold / 100))
	return {pieces = c.pieces, rarity = c.rarity, itemLevel = c.itemLevel, tier = c.tier, currency = c.currency,
		gold = gold}
end

local floor = math.floor

function D.of(difficulty)
	local d = floor(tonumber(difficulty) or 1)
	if d < 1 then
		d = 1
	elseif d > #D.levels then
		d = #D.levels
	end
	return D.levels[d], d
end

-- new max health of a monster
function D.health(maxHealth, difficulty)
	return math.max(1, floor((maxHealth or 0) * D.of(difficulty).health / 100))
end

-- new max health of a dungeon's boss: a dungeon may give its boss its own percents per difficulty (`curve`, six
-- numbers; the solo Hollow Vault, areagen_config.lua bossHealth) so a 30 minute run stays in time; without one the
-- boss scales like every other monster
function D.bossHealth(maxHealth, difficulty, curve)
	if type(curve) ~= "table" or #curve == 0 then
		return D.health(maxHealth, difficulty)
	end
	local _, d = D.of(difficulty)
	return math.max(1, floor((maxHealth or 0) * (curve[math.min(d, #curve)] or 100) / 100))
end

-- ---------------------------------------------------------------------------------------------------------------
-- The run model of a generated dungeon (server/README.md "Solo kill times", the dungeons): how long a capable player
-- at the dungeon's level needs, from config numbers only, so it can be recomputed after any change of monsters, counts
-- or the damage model.
--   dps(L)           the measured one-target damage of the classes: 913 at level 300, 2,600 at 1000, the same slope
--                    (2.41 a level) above, scaled by the level below 300
--   health(hp, L)    a monster file's health at level L: hp x (1 + 0.0074 L) (the engine's level bonus)
--   trash(d)         the run's monsters to the gate (progressNeeded, 85%) x their kill time alone x trashHealth[d]
--                    / aoe (pulls of several at once: 2.3)
--   boss(d)          the boss's health x bossHealth[d] / dps (the mechanics keep this time: boss_mechanics G.balance)
--   run(d)           trash(d) + boss(d) + walk (the walk between packs and to the boss: 90 s)
-- Targets (owner, 2026-10-14): run(1) about 10 minutes, run(6) about 15, boss(1) 2-3 minutes, boss(6) 5-6; the time
-- limit 15 minutes and the speed challenge 40% of it.
D.model = {aoe = 2.3, walk = 90, dpsAt300 = 913, dpsAt1000 = 2600}

function D.dps(level)
	local m, L = D.model, tonumber(level) or 1
	if L <= 300 then
		return m.dpsAt300 * math.max(L, 1) / 300
	end
	return m.dpsAt300 + (L - 300) * (m.dpsAt1000 - m.dpsAt300) / 700
end

function D.levelHealth(hp, level)
	return (hp or 0) * (1 + 0.0074 * (level or 0))
end

-- spec = {level = the player's level (the dungeon's + 25), monsters = {{hp, level, count}}, boss = boss health at
-- difficulty 1 (after its healthMult), need = share 0..1 of the monsters to kill, bossCurve, trashCurve}
-- -> {trash, boss, walk, total} in seconds at this difficulty
function D.runSeconds(spec, difficulty)
	local _, d = D.of(difficulty)
	local dps = D.dps(spec.level)
	local single, n = 0, 0
	for _, m in ipairs(spec.monsters or {}) do
		single = single + D.levelHealth(m.hp, m.level) * (m.count or 1) / dps
		n = n + (m.count or 1)
	end
	local tc = spec.trashCurve and spec.trashCurve[math.min(d, #spec.trashCurve)] or D.levels[d].health
	local bc = spec.bossCurve and spec.bossCurve[math.min(d, #spec.bossCurve)] or D.levels[d].health
	local trash = single * (spec.need or 1) * tc / 100 / D.model.aoe
	local boss = (spec.boss or 0) * bc / 100 / dps
	return {trash = trash, boss = boss, walk = D.model.walk, total = trash + boss + D.model.walk, monsters = n}
end

-- damage dealt by a monster (negative or positive, the sign is kept)
function D.damage(value, difficulty)
	local pct = D.of(difficulty).damage
	if pct == 100 then
		return value
	end
	local v = floor(math.abs(value or 0) * pct / 100 + 0.5)
	return (value or 0) < 0 and -v or v
end

function D.experience(exp, difficulty)
	return floor((exp or 0) * (1 + D.of(difficulty).experience / 100))
end

-- extra coins for a stack of `count` (fraction: a chance of one more)
function D.extraGold(count, difficulty, rand)
	local x = (count or 0) * D.of(difficulty).gold / 100
	local n = floor(x)
	local frac = x - n
	if frac > 0 and rand(1, 10000) <= floor(frac * 10000 + 0.5) then
		n = n + 1
	end
	return n
end

-- chance (per 100000, the engine's loot scale) of the extra roll of a loot entry
function D.extraLootChance(chance, difficulty)
	return floor((chance or 0) * D.of(difficulty).loot / 100)
end

-- "Monster Health 200%\nMonster Damage 130%\nBonus XP +75%\nGold Drop +75%" (the panel text of the client)
function D.panelText(difficulty)
	local l = D.of(difficulty)
	local lines = {string.format("Monster Health %d%%", l.health), string.format("Monster Damage %d%%", l.damage)}
	if l.experience > 0 then
		lines[#lines + 1] = string.format("Bonus XP +%d%%", l.experience)
	end
	if l.gold > 0 then
		lines[#lines + 1] = string.format("Gold Drop +%d%%", l.gold)
	end
	if l.loot > 0 then
		lines[#lines + 1] = string.format("Loot Chance +%d%%", l.loot)
	end
	return table.concat(lines, "\n")
end

return D
