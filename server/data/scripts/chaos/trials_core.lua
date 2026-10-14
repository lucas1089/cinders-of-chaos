-- trials_core.lua: the rules of the Vocation Trials that need no engine (ChaosTrialsCore). Used by trials.lua (run,
-- storage, opcode), trials_effects.lua (combat) and the Keeper of Trials' NPC script (its own Lua state).
-- Tests: server/tests/trials_test.lua (luajit and lua5.3). Design: TRIALS.md. Settings: trials_config.lua; the nodes:
-- trials_nodes.lua.
--
-- Vocabulary of the nodes: every node is a table of KEYS (below) with a number each. Keys with engine = "tree" are
-- stats of the passive tree (positive only, applied by passivetree_effects.lua), "trial" keys are applied by
-- trials_effects.lua (they may be negative), "spell" keys need the spell events of engine patch 0008.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.trials then
	Chaos.trials = dofile("data/scripts/chaos/trials_config.lua")
end

ChaosTrialsCore = ChaosTrialsCore or {}
local M = ChaosTrialsCore

-- a text in `lang` through ChaosI18n (i18n_core.lua) when it is loaded, else English (planPick, enterProblem)
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end
local floor, max, min = math.floor, math.max, math.min

function M.cfg()
	return Chaos.trials
end

M.NODES = M.NODES or dofile("data/scripts/chaos/trials_nodes.lua")

-- ------------------------------------------------------------------------------------------------ key vocabulary
-- label: the text after the number; good: the sign that helps the player (+1 or -1); fmt: how the line reads.
--   "pct"  "+15% <label>" / "-8% <label>"      "flat" "+4 <label>" (a tree stat)
local KEYS = {
	-- damage dealt (additive percent, summed, then one multiplier)
	dealAll = {"damage", 1}, dealMelee = {"melee damage", 1}, dealRanged = {"ranged damage", 1},
	dealSpell = {"spell damage", 1}, dealDot = {"damage over time", 1}, dealMinion = {"minion damage", 1},
	dealPhysical = {"physical damage", 1}, dealFire = {"fire damage", 1}, dealIce = {"ice damage", 1},
	dealEnergy = {"energy damage", 1}, dealEarth = {"earth damage", 1}, dealDeath = {"death damage", 1},
	dealHoly = {"holy damage", 1},
	dealLowHp = {"damage below 35% health", 1}, dealHighHp = {"damage above 90% health", 1},
	dealFirst = {"damage vs enemies over 90% health", 1}, dealExecute = {"damage vs enemies under 30% health", 1},
	-- damage taken (additive percent)
	takeAll = {"damage taken", -1}, takeMelee = {"melee and ranged damage taken", -1},
	takeMagic = {"spell damage taken", -1}, takeLowHp = {"damage taken below 35% health", -1},
	-- defence
	evade = {"chance to avoid a melee or ranged hit", 1}, reflect = {"of melee damage is reflected back", 1},
	manaShield = {"of damage taken is paid from mana", 1},
	-- on kill
	killHeal = {"of max health restored per kill", 1}, killMana = {"of max mana restored per kill", 1},
	-- leech and healing
	leechMelee = {"of melee damage returned as health", 1}, leechSpell = {"of spell damage returned as health", 1},
	leechAll = {"of all damage returned as health", 1}, healOut = {"healing you cast", 1}, healIn = {"healing you receive", 1},
	-- spell events (engine patch 0008)
	spellCost = {"mana cost of spells", -1, engine = "spell"}, spellCd = {"spell cooldowns", -1, engine = "spell"},
	-- the passive tree's own stats (positive, applied by passivetree_effects.lua)
	criticalHitChance = {"critical hit chance", 1, engine = "tree", flat = true},
	criticalHitAmount = {"critical hit damage", 1, engine = "tree", flat = true},
	vitality = {"maximum health", 1, engine = "tree"}, spirit = {"maximum mana", 1, engine = "tree"},
	absorbPhysical = {"physical damage absorbed", 1, engine = "tree"}, absorbFire = {"fire damage absorbed", 1, engine = "tree"},
	absorbIce = {"ice damage absorbed", 1, engine = "tree"}, absorbEnergy = {"energy damage absorbed", 1, engine = "tree"},
	absorbHoly = {"holy damage absorbed", 1, engine = "tree"}, absorbAllElements = {"elemental damage absorbed", 1, engine = "tree"},
	-- parts of the multi-key lines (shown together by M.describe)
	lastStandCd = {"", 1, special = true}, killStackPct = {"", 1, special = true}, killStackMax = {"", 1, special = true},
	killStackMs = {"", 1, special = true}, echoChance = {"", 1, special = true}, echoPct = {"", 1, special = true},
	novaChance = {"", 1, special = true}, novaPct = {"", 1, special = true}, novaRadius = {"", 1, special = true}
}
for key, d in pairs(KEYS) do
	d.label, d.good = d[1], d[2]
	d.engine = d.engine or "trial"
end
M.KEYS = KEYS

-- tree stats that may only be positive (passivetree_effects.lua clamps them at 0)
function M.isTreeKey(key)
	return KEYS[key] ~= nil and KEYS[key].engine == "tree"
end

-- ------------------------------------------------------------------------------------------------ families and vocations
local familyOfVoc
local function buildFamilyIndex()
	familyOfVoc = {}
	for key, f in pairs(M.cfg().families) do
		for _, voc in ipairs(f.voc) do
			familyOfVoc[voc] = key
		end
	end
end

function M.familyKey(voc)
	if not familyOfVoc then
		buildFamilyIndex()
	end
	return familyOfVoc[voc]
end

function M.family(voc)
	local key = M.familyKey(voc)
	return key and M.cfg().families[key] or nil, key
end

-- every vocation with a trial, ascending
function M.vocations()
	local list = {}
	for key, f in pairs(M.cfg().families) do
		for _, voc in ipairs(f.voc) do
			list[#list + 1] = voc
		end
	end
	table.sort(list)
	return list
end

function M.variant(voc)
	return M.cfg().variants[voc] or {}
end

-- ------------------------------------------------------------------------------------------------ nodes
-- node id = vocation x 100 + pair x 10 + side (side 1 = A, 2 = B): 811 = vocation 8, pair 1, node A
function M.nodeId(voc, pair, side)
	return voc * 100 + pair * 10 + side
end

function M.parseId(id)
	id = floor(tonumber(id) or 0)
	local voc, rest = floor(id / 100), id % 100
	local pair, side = floor(rest / 10), rest % 10
	if voc < 1 or pair < 1 or pair > 3 or side < 1 or side > 2 then
		return nil
	end
	return voc, pair, side
end

function M.pairsOf(voc)
	local data = M.NODES[voc]
	if not data then
		return nil
	end
	local out = {}
	for p = 1, #data do
		out[p] = {pair = p, tier = p, a = data[p][1], b = data[p][2]}
		out[p].a.id, out[p].b.id = M.nodeId(voc, p, 1), M.nodeId(voc, p, 2)
		out[p].a.pair, out[p].b.pair, out[p].a.side, out[p].b.side = p, p, 1, 2
		out[p].a.voc, out[p].b.voc = voc, voc
	end
	return out
end

function M.nodeById(id)
	local voc, pair, side = M.parseId(id)
	local pairs_ = voc and M.pairsOf(voc)
	local entry = pairs_ and pairs_[pair]
	if not entry then
		return nil
	end
	return side == 1 and entry.a or entry.b
end

-- ------------------------------------------------------------------------------------------------ picks (what is held)
-- picks = {p1, p2, p3}, each 0 (none), 1 (the A node) or 2 (the B node). Stored as p1 + 3 x p2 + 9 x p3 per vocation.
function M.pack(picks)
	local raw = 0
	local mul = 1
	for p = 1, 3 do
		raw = raw + ((picks and picks[p]) or 0) * mul
		mul = mul * 3
	end
	return raw
end

function M.unpack(raw)
	raw = floor(tonumber(raw) or 0)
	if raw < 0 or raw > 26 then
		raw = 0
	end
	return {raw % 3, floor(raw / 3) % 3, floor(raw / 9) % 3}
end

function M.clearedTier(raw)
	local t = floor(tonumber(raw) or 0)
	return max(0, min(#M.cfg().tiers, t))
end

-- the pairs a character may choose from: tier cleared n opens pairs 1..n; picks kept for locked pairs do not count
function M.activePicks(tierCleared, picks)
	local out = {0, 0, 0}
	for p = 1, 3 do
		if p <= tierCleared then
			out[p] = (picks and picks[p]) or 0
		end
	end
	return out
end

-- the effect table of a vocation's held nodes (fx and cost summed under their keys)
function M.effects(voc, tierCleared, picks)
	local total = {}
	local list = M.pairsOf(voc)
	if not list then
		return total
	end
	local held = M.activePicks(tierCleared, picks)
	for p = 1, 3 do
		local node = held[p] == 1 and list[p].a or held[p] == 2 and list[p].b or nil
		if node then
			for _, part in ipairs({node.fx, node.cost}) do
				for key, v in pairs(part) do
					total[key] = (total[key] or 0) + v
				end
			end
		end
	end
	return total
end

function M.heldNodes(voc, tierCleared, picks)
	local out = {}
	local list = M.pairsOf(voc)
	local held = M.activePicks(tierCleared, picks)
	for p = 1, 3 do
		local side = held[p]
		if list and side > 0 then
			out[#out + 1] = side == 1 and list[p].a or list[p].b
		end
	end
	return out
end

-- does any effect key need the spell events of engine patch 0008
function M.needsSpellEvents(node)
	for _, part in ipairs({node.fx, node.cost}) do
		for key in pairs(part) do
			if KEYS[key] and KEYS[key].engine == "spell" then
				return true
			end
		end
	end
	return false
end

local function fmtNum(v)
	if v == floor(v) then
		return tostring(floor(v))
	end
	return string.format("%.1f", v)
end

local function signed(v)
	return (v >= 0 and "+" or "-") .. fmtNum(math.abs(v))
end

-- the text lines of a node: {{text =, good = true|false}, ...}; gains first, then the price
function M.describe(node)
	local lines = {}
	local function add(part, isCost)
		local keys = {}
		for key in pairs(part) do
			keys[#keys + 1] = key
		end
		table.sort(keys)
		local done = {}
		for _, key in ipairs(keys) do
			local d, v = KEYS[key], part[key]
			if d and not done[key] then
				local good
				if d.special then
					if key == "lastStandCd" then
						lines[#lines + 1] = {text = string.format("Survive a lethal hit (once per %d s)", v), good = true}
					elseif key == "killStackPct" then
						lines[#lines + 1] = {text = string.format("Each kill: +%s%% damage for %s s, up to %d times", fmtNum(v),
							fmtNum((part.killStackMs or 0) / 1000), part.killStackMax or 1), good = true}
					elseif key == "echoChance" then
						lines[#lines + 1] = {text = string.format("%d%% chance: a hit strikes again for %d%%", v, part.echoPct or 50), good = true}
					elseif key == "novaChance" then
						lines[#lines + 1] = {text = string.format("%d%% chance: a hit bursts within %d sqm for %d%%", v,
							part.novaRadius or 2, part.novaPct or 40), good = true}
					end
				elseif d.flat then
					lines[#lines + 1] = {text = string.format("%s%% %s", signed(v), d.label), good = not isCost}
				else
					if d.label:sub(1, 2) == "of" then
						lines[#lines + 1] = {text = string.format("%s%% %s", fmtNum(math.abs(v)), d.label), good = (v * d.good) > 0}
					else
						lines[#lines + 1] = {text = string.format("%s%% %s", signed(v), d.label), good = (v * d.good) > 0}
					end
				end
			end
		end
	end
	add(node.fx or {}, false)
	add(node.cost or {}, true)
	return lines
end

-- config checks used by the tests (and printed by trials.lua at startup): a list of problems
function M.validate()
	local problems = {}
	local seenName = {}
	for _, voc in ipairs(M.vocations()) do
		local list = M.pairsOf(voc)
		if not list or #list ~= 3 then
			problems[#problems + 1] = "vocation " .. voc .. " has no three pairs"
		else
			for p = 1, 3 do
				for side, node in ipairs({list[p].a, list[p].b}) do
					local where = voc .. "/" .. p .. "/" .. side
					if not node.name or node.name == "" then
						problems[#problems + 1] = where .. " has no name"
					elseif seenName[node.name:lower()] then
						problems[#problems + 1] = where .. " repeats the name " .. node.name
					end
					seenName[(node.name or ""):lower()] = true
					if next(node.fx) == nil then
						problems[#problems + 1] = where .. " gives nothing"
					end
					if next(node.cost) == nil then
						problems[#problems + 1] = where .. " has no trade-off"
					end
					for _, part in ipairs({{node.fx, false}, {node.cost, true}}) do
						for key, v in pairs(part[1]) do
							local d = KEYS[key]
							if not d then
								problems[#problems + 1] = where .. " uses the unknown key " .. key
							elseif type(v) ~= "number" or v == 0 then
								problems[#problems + 1] = where .. " " .. key .. " is not a number"
							elseif not d.special then
								if d.engine == "tree" and (part[2] or v < 0) then
									problems[#problems + 1] = where .. " tree stat " .. key .. " must be a positive gain"
								elseif d.engine ~= "tree" and (v * d.good > 0) == part[2] then
									problems[#problems + 1] = where .. " " .. key .. (part[2] and " is a gain in the cost" or " is a loss in the gain")
								end
							end
						end
					end
					if node.fx.killStackPct and not (node.fx.killStackMax and node.fx.killStackMs) then
						problems[#problems + 1] = where .. " kill stacks need max and duration"
					end
					if node.fx.echoChance and not node.fx.echoPct then
						problems[#problems + 1] = where .. " echo needs a percent"
					end
					if node.fx.novaChance and not node.fx.novaPct then
						problems[#problems + 1] = where .. " nova needs a percent"
					end
				end
			end
		end
	end
	return problems
end

-- ------------------------------------------------------------------------------------------------ choosing and switching
-- Can the character put pair `pair` on `side` (1 or 2) now? Returns a plan {free, gold, tokens, change} or nil, reason.
--   state = {tier = highest tier cleared, picks = {p1,p2,p3}, tokens = n, level = n}
function M.planPick(state, pair, side, lang)
	pair, side = floor(tonumber(pair) or 0), floor(tonumber(side) or 0)
	if pair ~= pair or pair < 1 or pair > 3 or (side ~= 0 and side ~= 1 and side ~= 2) then
		return nil, T(lang, "That is not a choice of your trial nodes.")
	end
	if pair > (state.tier or 0) then
		local t = M.cfg().tiers[pair]
		return nil, T(lang, "Locked: clear your trial on %s first.", t and t.name or T(lang, "a higher difficulty"))
	end
	local current = (state.picks and state.picks[pair]) or 0
	if side == current then
		return nil, T(lang, side == 0 and "Nothing is chosen there." or "You already hold that node.")
	end
	local plan = {pair = pair, side = side, from = current}
	if current == 0 then
		plan.free, plan.gold, plan.tokens = true, 0, 0
		return plan
	end
	local sw = M.cfg().switch
	plan.free = false
	plan.gold = max(0, floor(tonumber(state.level) or 0)) * sw.goldPerLevel
	plan.tokens = 1
	if (state.tokens or 0) < plan.tokens then
		return nil, T(lang, "Changing a held node costs a Trial Token. Clear a trial you have already cleared to earn one."), plan
	end
	return plan
end

-- ------------------------------------------------------------------------------------------------ tiers, scaling, rewards
function M.tier(i)
	return M.cfg().tiers[i]
end

-- level / previous tier / protection: why a character may not enter tier i (nil = may), in `lang` (English by default)
function M.enterProblem(tierIdx, level, tierCleared, now, cooldownUntil, lang)
	local t = M.tier(tierIdx)
	if not t then
		return T(lang, "That difficulty does not exist.")
	end
	if tierIdx > (tierCleared or 0) + 1 then
		return T(lang, "Clear the trial on %s first.", M.tier(tierIdx - 1).name)
	end
	if (level or 0) < t.minLevel then
		return T(lang, "%s needs level %d.", t.name, t.minLevel)
	end
	if (cooldownUntil or 0) > (now or 0) then
		return T(lang, "The trial is still closed to you for %d seconds.", (cooldownUntil or 0) - (now or 0))
	end
	return nil
end

-- numbers of a run for a player of `level` at tier i as vocation `voc`
function M.scale(tierIdx, level, voc)
	local c = M.cfg()
	local t = c.tiers[tierIdx]
	local v = M.variant(voc or 0)
	local lvl = max(t.minLevel, min(t.maxLevel, floor(tonumber(level) or 0)))
	local factor = (lvl / t.minLevel) ^ c.hpExponent
	local hp = floor(t.hp * factor * (v.hp or 1) + 0.5)
	return {
		level = lvl, hp = hp, addHp = max(50, floor(hp * t.addHp + 0.5)),
		hit = t.hit * (v.hit or 1), addHit = t.addHit * (v.hit or 1),
		time = t.time, lives = t.lives,
		waveSize = max(1, floor(t.wave * (v.adds or 1) + 0.5))
	}
end

-- the stages before the boss: the family list with the tier's extra waves (and the seals / marks count of the tier)
function M.stages(familyKey, tierIdx)
	local c = M.cfg()
	local f, t = c.families[familyKey], c.tiers[tierIdx]
	local out = {}
	for _, kind in ipairs(f.stages) do
		if kind == "seals" then
			out[#out + 1] = {kind = "seals", count = t.seals}
		elseif kind == "marks" then
			out[#out + 1] = {kind = "marks", count = t.marks}
		else
			out[#out + 1] = {kind = "wave"}
		end
	end
	local waves = 0
	for _, s in ipairs(out) do
		if s.kind == "wave" then
			waves = waves + 1
		end
	end
	if waves > 0 then
		for _ = 1, t.extraWaves do
			table.insert(out, #out + 1, {kind = "wave"})
		end
	end
	out[#out + 1] = {kind = "boss"}
	return out
end

function M.hasMech(familyKey, name)
	for _, m in ipairs(M.cfg().families[familyKey].mech) do
		if m == name then
			return true
		end
	end
	return false
end

-- week key of a time: YYYYMMDD of the Monday that starts its week (Monday reward.weekResetHour, 6), the shared week of
-- the bounty board, leaderboards, raids and the guild boss (ChaosBounty.week). The old keys were YYYYWW (6 digits, from
-- the day of the year): one never equals a new key, so the first clear after the switch starts a fresh count (a
-- one-time grace: nobody keeps fewer repeats than before).
function M.weekKey(t)
	if not ChaosBounty or not ChaosBounty.week then
		dofile("data/scripts/chaos/bounty_core.lua")
	end
	local hour = M.cfg().reward.weekResetHour or 6
	return ChaosBounty.week(t or os.time(), {rollHour = hour})
end

-- what a clear pays: {first = bool, gold, chaos, divine, tokens, counted}. tierCleared = before this clear.
-- weekCount = repeat rewards already paid this week.
function M.clearOutcome(tierIdx, level, tierCleared, tokens, weekCount)
	local c = M.cfg()
	local first = tierIdx > (tierCleared or 0)
	local r = first and c.reward.first or c.reward.repeatReward
	local out = {first = first, tier = tierIdx, gold = 0, chaos = 0, divine = 0, tokens = 0}
	if first then
		out.gold = (level or 0) * r.goldPerLevel * tierIdx
		out.chaos, out.divine = r.chaos[tierIdx] or 0, r.divine[tierIdx] or 0
		return out
	end
	out.tokens = min(c.switch.tokensPerRepeat, max(0, c.switch.maxTokens - (tokens or 0)))
	if (weekCount or 0) < c.reward.repeatsPerWeek then
		out.gold = (level or 0) * r.goldPerLevel * tierIdx
		out.chaos, out.divine = r.chaos[tierIdx] or 0, r.divine[tierIdx] or 0
		out.counted = true
	end
	return out
end

-- ------------------------------------------------------------------------------------------------ combat maths
local BOUNDS = {dealMin = 0.25, dealMax = 2.5, takeMin = 0.3, takeMax = 2.0}
M.BOUNDS = BOUNDS

M.LOW_HP, M.HIGH_HP, M.FIRST_HP, M.EXECUTE_HP = 0.35, 0.90, 0.90, 0.30

local TYPE_KEY = {physical = "dealPhysical", fire = "dealFire", ice = "dealIce", energy = "dealEnergy", earth = "dealEarth",
	death = "dealDeath", holy = "dealHoly"}
local ORIGIN_KEY = {melee = "dealMelee", ranged = "dealRanged", spell = "dealSpell", dot = "dealDot", minion = "dealMinion"}

-- damage dealt multiplier. b = bonus table; ctx = {origin, ctype, hpRatio, targetRatio, stacks}
function M.dealMultiplier(b, ctx)
	local pct = b.dealAll or 0
	pct = pct + (b[ORIGIN_KEY[ctx.origin or ""] or "_"] or 0)
	pct = pct + (b[TYPE_KEY[ctx.ctype or ""] or "_"] or 0)
	local own, target = ctx.hpRatio or 1, ctx.targetRatio or 1
	if own <= M.LOW_HP then
		pct = pct + (b.dealLowHp or 0)
	end
	if own >= M.HIGH_HP then
		pct = pct + (b.dealHighHp or 0)
	end
	if target >= M.FIRST_HP then
		pct = pct + (b.dealFirst or 0)
	end
	if target <= M.EXECUTE_HP then
		pct = pct + (b.dealExecute or 0)
	end
	if (b.killStackPct or 0) > 0 and (ctx.stacks or 0) > 0 then
		pct = pct + b.killStackPct * min(ctx.stacks, b.killStackMax or 1)
	end
	return max(BOUNDS.dealMin, min(BOUNDS.dealMax, 1 + pct / 100))
end

local ELEMENT = {fire = true, ice = true, energy = true, earth = true, death = true, holy = true}

-- damage taken multiplier. ctx = {origin ("melee" "ranged" "spell" "dot" "other"), ctype, hpRatio}
function M.takeMultiplier(b, ctx)
	local pct = b.takeAll or 0
	if ctx.origin == "melee" or ctx.origin == "ranged" then
		pct = pct + (b.takeMelee or 0)
	elseif ctx.origin == "spell" or ctx.origin == "dot" then
		pct = pct + (b.takeMagic or 0)
	end
	if (ctx.hpRatio or 1) <= M.LOW_HP then
		pct = pct + (b.takeLowHp or 0)
	end
	return max(BOUNDS.takeMin, min(BOUNDS.takeMax, 1 + pct / 100))
end

-- evade: a chance (percent, capped) to avoid a melee or ranged hit completely
M.EVADE_CAP = 35
function M.evadeChance(b, origin)
	if origin ~= "melee" and origin ~= "ranged" then
		return 0
	end
	return min(M.EVADE_CAP, max(0, b.evade or 0))
end

-- reflect: damage returned for a melee hit of `amount`
function M.reflectAmount(b, origin, amount)
	if origin ~= "melee" or (b.reflect or 0) <= 0 then
		return 0
	end
	return floor(amount * min(50, b.reflect) / 100)
end

-- mana shield: of a hit of `amount`, the part paid from mana (a share of the hit, at most the mana left)
M.SHIELD_CAP = 50
function M.shieldSplit(b, amount, mana)
	local share = min(M.SHIELD_CAP, max(0, b.manaShield or 0))
	if share <= 0 or amount <= 0 or mana <= 0 then
		return amount, 0
	end
	local paid = min(mana, floor(amount * share / 100))
	return amount - paid, paid
end

-- last stand: a lethal hit leaves 1 health when the node is held and its cooldown is over. state.readyAt (seconds).
-- Returns the (possibly cut) damage and whether it triggered.
function M.lastStand(b, state, now, health, damage)
	local cd = b.lastStandCd or 0
	if cd <= 0 or damage < health or (state.lastStandAt or 0) + cd > now then
		return damage, false
	end
	state.lastStandAt = now
	return max(0, health - 1), true
end

-- kill stacks: state.stackKills = list of kill times (ms); returns the stack count at `now`
function M.stackCount(state, b, now)
	local ms = b.killStackMs or 0
	local list = state.stackKills
	if not list or ms <= 0 then
		return 0
	end
	local n, keep = 0, {}
	for _, t in ipairs(list) do
		if now - t <= ms then
			keep[#keep + 1] = t
			n = n + 1
		end
	end
	state.stackKills = keep
	return min(n, b.killStackMax or 1)
end

function M.addKill(state, b, now)
	if (b.killStackPct or 0) <= 0 then
		return
	end
	state.stackKills = state.stackKills or {}
	state.stackKills[#state.stackKills + 1] = now
	local cap = b.killStackMax or 1
	while #state.stackKills > cap do
		table.remove(state.stackKills, 1)
	end
end

function M.roll(chance, random)
	return chance > 0 and (random or math.random)(1, 100) <= chance
end

function M.scaleDamage(v, m)
	local a = floor(math.abs(v * m) + 1e-6)
	return v < 0 and -a or a
end

-- ------------------------------------------------------------------------------------------------ run mechanics
-- "stillness" (as the ascension quest): state = {key, since, warned}; "move" "wait" "warn" "slam"
function M.stillness(state, posKey, now)
	local c = M.cfg()
	if state.key ~= posKey then
		state.key, state.since, state.warned = posKey, now, false
		return "move"
	end
	local still = now - (state.since or now)
	if still >= c.stillMs then
		state.since, state.warned = now, false
		return "slam"
	end
	if still >= c.stillWarnMs and not state.warned then
		state.warned = true
		return "warn"
	end
	return "wait"
end

-- "zones": `count` distinct tiles within `radius` of the centre, the centre first
function M.zoneTiles(center, count, radius, rand)
	local list, seen = {{x = center.x, y = center.y, z = center.z}}, {[center.x .. ":" .. center.y] = true}
	local candidates = {}
	for dx = -radius, radius do
		for dy = -radius, radius do
			if dx ~= 0 or dy ~= 0 then
				candidates[#candidates + 1] = {x = center.x + dx, y = center.y + dy, z = center.z}
			end
		end
	end
	while #list < count and #candidates > 0 do
		local c = table.remove(candidates, rand(#candidates))
		list[#list + 1] = c
	end
	return list
end

-- the lethal hit is cut to leave 1 health: primary, secondary, caught
function M.catchDamage(health, primary, secondary)
	primary, secondary = max(0, primary or 0), max(0, secondary or 0)
	if primary + secondary < health then
		return primary, secondary, false
	end
	local keep = max(0, health - 1)
	local p = min(primary, keep)
	local s = min(secondary, keep - p)
	return p, s, true
end

-- seals: the order in which the elements must be broken (n entries over the four seals), and the check of a step.
M.SEAL_ELEMENTS = {"fire", "ice", "energy", "earth"}
function M.sealOrder(n, rand)
	local pool, order = {}, {}
	for i = 1, #M.SEAL_ELEMENTS do
		pool[i] = i
	end
	-- a shuffled pass over the four, then repeats of a fresh shuffle (never the same seal twice in a row)
	while #order < n do
		local bag = {}
		for i, v in ipairs(pool) do
			bag[i] = v
		end
		for i = #bag, 2, -1 do
			local j = rand(i)
			bag[i], bag[j] = bag[j], bag[i]
		end
		for _, v in ipairs(bag) do
			if #order < n and order[#order] ~= v then
				order[#order + 1] = v
			end
		end
	end
	return order
end

-- state.seal = {index (which seal of `order` is next), charge (ms on a seal), on (seal id being stood on)}
-- stand = seal id (1..4) under the player or nil; returns "none" "charging" "done" "wrong"
function M.sealStep(state, order, stand, dt)
	if not stand then
		state.on, state.charge = nil, 0
		return "none"
	end
	if state.on ~= stand then
		state.on, state.charge = stand, 0
	end
	state.charge = (state.charge or 0) + dt
	if state.charge < M.cfg().sealChargeMs then
		return "charging"
	end
	state.charge = 0
	if order[state.index] == stand then
		state.index = state.index + 1
		return "done"
	end
	return "wrong"
end

-- pyre: is the player within 1 tile of a safe tile
function M.pyreSafe(pos, safes)
	for _, s in ipairs(safes) do
		if pos.z == s.z and math.abs(pos.x - s.x) <= 1 and math.abs(pos.y - s.y) <= 1 then
			return true
		end
	end
	return false
end

-- marks: state = {left (seconds of the run), flees}: a mark that got away costs time
function M.markEscaped(secondsLeft)
	return max(0, secondsLeft - M.cfg().markPenaltySeconds)
end

-- ------------------------------------------------------------------------------------------------ the room
function M.layout(slot)
	local r = M.cfg().room
	local g = r.grid
	local col = (slot - 1) % g.cols
	local row = floor((slot - 1) / g.cols)
	local ox, oy, z = g.origin.x + col * g.spacing, g.origin.y + row * g.spacing, g.origin.z
	local n = r.inner
	local L = {slot = slot, x1 = ox + 1, y1 = oy + 1, x2 = ox + n, y2 = oy + n, z = z, floor = {}, walls = {}}
	for x = ox, ox + n + 1 do
		for y = oy, oy + n + 1 do
			local p = {x = x, y = y, z = z}
			if x == ox or y == oy or x == ox + n + 1 or y == oy + n + 1 then
				L.walls[#L.walls + 1] = p
			else
				L.floor[#L.floor + 1] = p
			end
		end
	end
	L.basins = {{x = L.x1, y = L.y1, z = z}, {x = L.x2, y = L.y1, z = z}, {x = L.x1, y = L.y2, z = z}, {x = L.x2, y = L.y2, z = z}}
	local cx, cy = ox + floor((n + 1) / 2), oy + floor((n + 1) / 2)
	L.center = {x = cx, y = cy, z = z}
	-- six tiles apart: the guardian sees the player from the start (monsters notice a player within about 8 x 6 tiles)
	L.playerStart = {x = cx, y = cy + 4, z = z}
	L.bossStart = {x = cx, y = cy - 2, z = z}
	-- the four seals: the corners of a square around the centre, far from the walls
	L.seals = {{x = cx - 6, y = cy - 3, z = z}, {x = cx + 6, y = cy - 3, z = z}, {x = cx - 6, y = cy + 3, z = z},
		{x = cx + 6, y = cy + 3, z = z}}
	return L
end

function M.slotAt(pos)
	local r = M.cfg().room
	local g = r.grid
	if not pos or pos.z ~= g.origin.z then
		return nil
	end
	local dx, dy = pos.x - g.origin.x, pos.y - g.origin.y
	if dx < 0 or dy < 0 then
		return nil
	end
	local col, row = floor(dx / g.spacing), floor(dy / g.spacing)
	if col >= g.cols or dx % g.spacing > r.inner + 1 or dy % g.spacing > r.inner + 1 then
		return nil
	end
	local slot = row * g.cols + col + 1
	if slot > g.slots then
		return nil
	end
	return slot
end

function M.inRoom(L, pos)
	return pos ~= nil and pos.z == L.z and pos.x >= L.x1 and pos.x <= L.x2 and pos.y >= L.y1 and pos.y <= L.y2
end

-- ------------------------------------------------------------------------------------------------ client state
-- the table sent to the client (trialState): everything the Trials window shows, built from plain data
--   state = {voc, level, tier, picks, tokens, cooldown, now}
function M.clientState(state)
	local voc = state.voc
	local fam, famKey = M.family(voc)
	if not fam then
		return {supported = false}
	end
	local c = M.cfg()
	local tiers = {}
	for i, t in ipairs(c.tiers) do
		local sc = M.scale(i, state.level, voc)
		tiers[i] = {key = t.key, name = t.name, minLevel = t.minLevel, cleared = i <= (state.tier or 0),
			problem = M.enterProblem(i, state.level, state.tier, state.now, state.cooldown), time = t.time, lives = t.lives,
			bossHealth = sc.hp}
	end
	local pairs_ = {}
	local list = M.pairsOf(voc)
	local held = M.activePicks(state.tier or 0, state.picks)
	for p = 1, 3 do
		local entry = {pair = p, tier = c.tiers[p].name, locked = p > (state.tier or 0), held = held[p], nodes = {}}
		for side, node in ipairs({list[p].a, list[p].b}) do
			local plan, why = M.planPick(state, p, side)
			entry.nodes[side] = {id = node.id, name = node.name, lore = node.lore, lines = M.describe(node),
				needsSpellEvents = M.needsSpellEvents(node) or nil, can = plan ~= nil, why = why,
				switch = plan and not plan.free or (not plan and held[p] ~= 0 and held[p] ~= side) or nil}
		end
		pairs_[p] = entry
	end
	return {supported = true, voc = voc, family = famKey, trial = fam.name, story = fam.story, level = state.level,
		tier = state.tier or 0, tokens = state.tokens or 0, maxTokens = c.switch.maxTokens, tiers = tiers, pairs = pairs_,
		switchGold = (state.level or 0) * c.switch.goldPerLevel, running = state.running or nil,
		repeatsLeft = state.repeatsLeft}
end

return M
