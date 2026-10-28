-- exercise_core.lua: the rules of the exercise (training) weapons, no engine calls (exercise_training.lua is the glue;
-- numbers and lists: exercise_config.lua; tests: server/tests/exercise_test.lua; overview: server/README.md "Training
-- weapons"). Lua 5.1 / LuaJIT and Lua 5.3.
--
--   E.kindOf(itemId)                      "melee" | "fist" | "ranged" | "rod" | "wand" | "shield" | nil
--   E.lineOf(vocationId)                  "warrior" | "ranger" | ... | nil
--   E.allowed(kind, vocationId)           may this class use that kind?
--   E.skillFor(kind, vocationId, levels, percents) -> name
--                                         the skill that trains: "fist" | "sword" | "club" | "axe" | "distance" | "magic" |
--                                         "shield". levels / percents = {sword =, club =, axe =}: the melee kind trains the best
--                                         of the three (one melee skill, melee_skill_core.lua); the fist kind (Monk line) "fist"
--   E.refusal(kind, vocationId) -> key, args   the text of a refusal (a key of i18n_strings.lua)
--   E.convertTo(itemId [, vocationId])    the item a weapon the class cannot use turns into (same tier, charges kept), or nil:
--                                         an old club weapon -> sword (fist for the Monk line), a sword weapon held by a Monk ->
--                                         fist, a fist weapon (the old axe) held by any other class -> sword
--   E.isRetiredChest(itemId)              a chest that is not sold any more
--   E.dummyKind(itemId) -> "bonus" | "plain" | nil
--   E.rate(stages, level, default)        the stage's rate for a skill level
--   E.step(kind, level, serverRate, bonus) -> amount     tries (or mana) one training step gives
--   E.reach(kind, dx, dy, dz) -> ok, why  may a player this far from the dummy train? ("floor" | "far")
--   E.beginChain(pid, now) -> gen | nil   a new chain may start (no live one); nil = "already training"
--   E.isCurrent(pid, gen)                 the chain is still the player's current one
--   E.touchChain(pid, gen, now)           a live chain made a step
--   E.endChain(pid [, gen])               the chain ended
--   E.validate() -> {problems}            the config is consistent (every item has a kind, every line exists, ...)

if not ChaosMeleeSkill then
	dofile("data/scripts/chaos/melee_skill_core.lua")
end

ChaosExercise = ChaosExercise or {}
local E = ChaosExercise

E.cfg = E.cfg or dofile("data/scripts/chaos/exercise_config.lua")

local function cfg()
	return E.cfg
end

local function num(v)
	return tonumber(v) or 0
end

local function contains(list, v)
	for _, x in ipairs(list or {}) do
		if x == v then
			return true
		end
	end
	return false
end

function E.kindOf(itemId)
	return cfg().items[itemId]
end

function E.lineOf(vocationId)
	for line, ids in pairs(cfg().lines) do
		if contains(ids, vocationId) then
			return line
		end
	end
	return nil
end

function E.allowed(kind, vocationId)
	local def = cfg().kinds[kind]
	local line = E.lineOf(vocationId)
	return def ~= nil and line ~= nil and contains(def.lines, line)
end

function E.skillFor(kind, vocationId, levels, percents)
	local def = cfg().kinds[kind]
	if not def or not E.allowed(kind, vocationId) then
		return nil
	end
	local line = E.lineOf(vocationId)
	local skill = (def.skillBy and def.skillBy[line]) or def.skill
	if skill == "melee" then
		-- the rate of a step follows the skill that counts, so a character with a weak sword and a strong axe is not
		-- trained at the weak skill's fast stage rate (the tries would be rerouted to the axe, melee_skill.lua, but
		-- they would have been multiplied by the wrong stage)
		return (ChaosMeleeSkill.best(levels, percents))
	end
	return skill
end

-- the class lines that may use a kind, as a readable list (for the refusal)
local LINE_NAMES = {warrior = "Warrior", ranger = "Ranger", mystic = "Mystic", thief = "Thief", monk = "Monk",
	necromancer = "Necromancer", templar = "Templar"}

function E.lineNames(kind)
	local def = cfg().kinds[kind]
	local out = {}
	for _, line in ipairs(def and def.lines or {}) do
		out[#out + 1] = LINE_NAMES[line] or line
	end
	table.sort(out)
	return out
end

-- key + args of a refusal: a key of i18n_strings.lua. The args are the class lines that may use the kind.
function E.refusal(kind, vocationId)
	if E.lineOf(vocationId) == nil then
		return "Your vocation cannot use this item.", {}
	end
	return "Your class cannot train with this item. It is for: %s.", {table.concat(E.lineNames(kind), ", ")}
end

-- the weapon of the tier an item belongs to, of a kind ("melee" | "fist"); nil for an item of no tier
local function tierOf(itemId)
	for _, tier in ipairs(cfg().tiers or {}) do
		if tier.melee == itemId or tier.fist == itemId or tier.club == itemId then
			return tier
		end
	end
	return nil
end

function E.convertTo(itemId, vocationId)
	local tier = tierOf(itemId)
	local kind = cfg().items[itemId]
	if not tier or (kind ~= "melee" and kind ~= "fist") then
		return nil
	end
	local want = E.lineOf(vocationId) == "monk" and "fist" or "melee"
	if vocationId == nil or E.lineOf(vocationId) == nil then
		-- no class to go by: only the club weapon of before becomes the sword one
		want = itemId == tier.club and "melee" or kind
	end
	local to = tier[want]
	if to == itemId then
		return nil
	end
	return to
end

function E.isRetiredChest(itemId)
	return contains(cfg().retiredChests, itemId)
end

function E.dummyKind(itemId)
	if contains(cfg().dummies.bonus, itemId) then
		return "bonus"
	elseif contains(cfg().dummies.plain, itemId) then
		return "plain"
	end
	return nil
end

function E.rate(stages, level, default)
	level = num(level)
	for _, stage in ipairs(stages or {}) do
		if level >= stage.min and level <= stage.max then
			return stage.rate
		end
	end
	return default
end

-- tries of a skill (or the mana spent for the magic level) one step gives; a whole number
function E.step(kind, level, serverRate, bonus)
	local c = cfg()
	local magic = kind == "rod" or kind == "wand"
	local rate = E.rate(magic and c.magicStages or c.skillStages, level, serverRate)
	local base = (magic and c.manaPerStep or c.triesPerStep) * rate
	if bonus then
		base = base * c.bonusFactor
	end
	return math.ceil(base - 1e-9)
end

-- may a player at this offset from the dummy train with this kind? Melee and shield need the next tile; the rest the
-- kind's range. A different floor never works (a client can name any dummy: allowfaruse skips the engine's range check).
function E.reach(kind, dx, dy, dz)
	local def = cfg().kinds[kind]
	if not def then
		return false, "far"
	end
	if num(dz) ~= 0 then
		return false, "floor"
	end
	if math.max(math.abs(num(dx)), math.abs(num(dy))) > def.range then
		return false, "far"
	end
	return true
end

-- ---------------------------------------------------------------- one chain of steps per player
-- The base script let a second click start a second chain (its "already training" branch reset the flag the chain
-- itself set): N clicks trained N times as fast for the same charges. A chain is alive while its last step is newer
-- than activeMs.
E.chains = E.chains or {}
E.generation = E.generation or 0

-- a new chain: its number, or nil while a live one exists ("already training")
function E.beginChain(pid, now)
	local cur = E.chains[pid]
	if cur and now - cur.last < cfg().activeMs then
		return nil
	end
	E.generation = E.generation + 1
	E.chains[pid] = {gen = E.generation, last = now}
	return E.generation
end

-- is this the player's current chain (a chain that stalled and was replaced stops at its next step)
function E.isCurrent(pid, gen)
	local cur = E.chains[pid]
	return cur ~= nil and cur.gen == gen
end

function E.touchChain(pid, gen, now)
	local cur = E.chains[pid]
	if cur and cur.gen == gen then
		cur.last = now
	end
end

function E.endChain(pid, gen)
	local cur = E.chains[pid]
	if cur and (gen == nil or cur.gen == gen) then
		E.chains[pid] = nil
	end
end

function E.validate()
	local c, problems = cfg(), {}
	for line, ids in pairs(c.lines) do
		if #ids == 0 then
			problems[#problems + 1] = "line " .. line .. " is empty"
		end
	end
	local seen = {}
	for line, ids in pairs(c.lines) do
		for _, id in ipairs(ids) do
			if seen[id] then
				problems[#problems + 1] = "vocation " .. id .. " is in two lines"
			end
			seen[id] = line
		end
	end
	for kind, def in pairs(c.kinds) do
		for _, line in ipairs(def.lines) do
			if not c.lines[line] then
				problems[#problems + 1] = "kind " .. kind .. ": unknown line " .. tostring(line)
			end
		end
		for line, skill in pairs(def.skillBy or {}) do
			if not c.lines[line] or not contains(def.lines, line) then
				problems[#problems + 1] = "kind " .. kind .. ": skillBy of a line that cannot use it: " .. tostring(line)
			end
			if type(skill) ~= "string" then
				problems[#problems + 1] = "kind " .. kind .. ": bad skillBy"
			end
		end
		if (kind == "ranged" or kind == "rod" or kind == "wand") and not def.ani then
			problems[#problems + 1] = "kind " .. kind .. " has no distance effect"
		end
	end
	for id, kind in pairs(c.items) do
		if not c.kinds[kind] then
			problems[#problems + 1] = "item " .. id .. ": unknown kind " .. tostring(kind)
		end
	end
	for i, tier in ipairs(c.tiers or {}) do
		for _, key in ipairs({"melee", "fist", "club"}) do
			local want = key == "fist" and "fist" or "melee"
			if c.items[tier[key]] ~= want then
				problems[#problems + 1] = "tier " .. i .. ": " .. key .. " is not a " .. want .. " weapon"
			end
		end
	end
	for _, id in ipairs(c.retiredChests or {}) do
		for _, ch in ipairs(c.chests or {}) do
			if ch.melee == id or ch.fist == id then
				problems[#problems + 1] = "chest " .. id .. " is both sold and retired"
			end
		end
	end
	return problems
end

return E
