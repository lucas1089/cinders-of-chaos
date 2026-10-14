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
