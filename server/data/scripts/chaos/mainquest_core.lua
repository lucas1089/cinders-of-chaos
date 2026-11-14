-- mainquest_core.lua: the pure rules of the main quest "The Ember Oath" (O551; mainquest_config.lua; server/README.md "Main quest
-- (O551)"). No engine calls: mainquest.lua gathers the facts of a character and acts on what these functions return.
-- Tests: server/tests/mainquest_test.lua (luajit and lua5.3). Lua 5.1 / LuaJIT and 5.3.
--
-- Facts of a character for its current step: {level, count, flags = {[key] = true}, stats = {[stat] = n}, spell, gear, visit,
--   storage = {[key] = n}, sheet = PD.sheet result, boss = bool}. A step is done when every condition holds.

ChaosMainQuestCore = ChaosMainQuestCore or {}
local M = ChaosMainQuestCore

local floor, max, min = math.floor, math.max, math.min

local function num(v, d)
	v = tonumber(v)
	if not v or v ~= v then
		return d
	end
	return v
end

function M.cfg()
	if not M.config then
		local ok, t = pcall(dofile, "data/scripts/chaos/mainquest_config.lua")
		M.config = ok and type(t) == "table" and t or nil
	end
	return M.config
end

function M.lang(code)
	code = tostring(code or "en"):lower()
	return code:sub(1, 2) == "pt" and "pt" or "en"
end

function M.text(t, lang)
	if type(t) ~= "table" then
		return tostring(t or "")
	end
	return t[M.lang(lang)] or t.en or ""
end

-- "{name}" places filled from vars (a missing name stays as it is, so a config gap shows)
function M.fill(text, vars)
	return (tostring(text):gsub("{([%w_]+)}", function(k)
		local v = vars and vars[k]
		if v == nil then
			return nil
		end
		return tostring(v)
	end))
end

function M.int(n)
	local s = tostring(floor(num(n, 0)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- ------------------------------------------------------------------------------------------------- bits
function M.hasBit(mask, bit)
	mask = floor(num(mask, 0))
	if mask < 0 then
		return false
	end
	return floor(mask / bit) % 2 == 1
end

function M.setBit(mask, bit)
	mask = max(0, floor(num(mask, 0)))
	if M.hasBit(mask, bit) then
		return mask
	end
	return mask + bit
end

function M.clearBit(mask, bit)
	mask = max(0, floor(num(mask, 0)))
	if M.hasBit(mask, bit) then
		return mask - bit
	end
	return mask
end

-- the storage name ("flags" or "flags2") and the bit value of a flag key; "talk" is bit 1 of "flags"
function M.flagPlace(cfg, key)
	if key == "talk" then
		return "flags", 1
	end
	for i, k in ipairs(cfg.flags or {}) do
		if k == key then
			local n = i + 1 -- bit number, 2 .. 60
			if n <= 30 then
				return "flags", 2 ^ (n - 1)
			end
			return "flags2", 2 ^ (n - 31)
		end
	end
	return nil
end

-- set a flag on a player through its storages (a hook in another system's own Lua state, an NPC script: no ChaosMainQuest there).
-- Nothing happens before the quest saw the character (state -1) or when the flag is unknown. Returns true when set.
function M.emitFlag(cfg, player, flag)
	if not cfg or not player then
		return false
	end
	local name, bit = M.flagPlace(cfg, flag)
	if not name then
		return false
	end
	local base = cfg.storage.base
	if num(player:getStorageValue(base + cfg.storage.state), -1) < 0 then
		return false
	end
	local key = base + cfg.storage[name]
	player:setStorageValue(key, M.setBit(max(0, num(player:getStorageValue(key), 0)), bit))
	return true
end

-- ------------------------------------------------------------------------------------------------- validation
local KINDS = {count = true, visit = true, stat = true, flag = true, talk = true, spell = true, gear = true, storage = true,
	resist = true, boss = true}

local function holes(text)
	local out = {}
	for k in tostring(text):gmatch("{([%w_]+)}") do
		out[#out + 1] = k
	end
	table.sort(out)
	return table.concat(out, ",")
end

function M.validate(cfg)
	local out = {}
	local s = cfg.storage or {}
	for _, k in ipairs({"state", "step", "count", "flags", "flags2", "tries", "cooldown", "won", "pity", "items"}) do
		local key = num(s.base, 0) + num(s[k], -1000)
		if key < 7101110 or key > 7101139 then
			out[#out + 1] = "storage " .. k .. " outside 7101110-7101139"
		end
	end
	if #(cfg.flags or {}) > 58 then
		out[#out + 1] = "more than 58 flags"
	end
	local seenFlag = {}
	for _, k in ipairs(cfg.flags or {}) do
		if seenFlag[k] then
			out[#out + 1] = "flag " .. k .. " twice"
		end
		seenFlag[k] = true
	end
	if #(cfg.steps or {}) == 0 then
		out[#out + 1] = "no steps"
	end
	local chapters = {}
	for _, ch in ipairs(cfg.chapters or {}) do
		chapters[ch.n] = ch
	end
	local seen, last, lastCh = {}, 0, 0
	local bosses = 0
	for i, st in ipairs(cfg.steps or {}) do
		local where = "step " .. i .. " (" .. tostring(st.key) .. ")"
		if type(st.key) ~= "string" or seen[st.key] then
			out[#out + 1] = where .. ": no key or a key twice"
		end
		seen[st.key or i] = true
		if num(st.level, 0) < last then
			out[#out + 1] = where .. ": level below the step before it"
		end
		last = num(st.level, 0)
		if not chapters[st.ch] then
			out[#out + 1] = where .. ": unknown chapter"
		elseif st.ch < lastCh then
			out[#out + 1] = where .. ": chapter before the step before it"
		end
		lastCh = st.ch or lastCh
		if #(st.conds or {}) == 0 then
			out[#out + 1] = where .. ": no conditions"
		end
		for _, c in ipairs(st.conds or {}) do
			if not KINDS[c.c] then
				out[#out + 1] = where .. ": unknown condition " .. tostring(c.c)
			elseif c.c == "stat" and type(c.stat) ~= "string" then
				out[#out + 1] = where .. ": a stat condition names no stat"
			elseif c.c == "flag" and not M.flagPlace(cfg, c.key) then
				out[#out + 1] = where .. ": flag " .. tostring(c.key) .. " is not in `flags`"
			elseif c.c == "count" and (num(c.target, 0) < 1 or #(c.mons or {}) == 0) then
				out[#out + 1] = where .. ": a count needs monsters and a target"
			elseif c.c == "count" and c.item and (type(c.item.en) ~= "string" or type(c.item.pt) ~= "string") then
				out[#out + 1] = where .. ": the quest item needs en and pt"
			elseif c.c == "count" and c.item and (num(c.itemId, 0) < 100 or type(c.lore) ~= "table" or type(c.lore.en) ~= "string"
					or type(c.lore.pt) ~= "string") then
				out[#out + 1] = where .. ": the quest item needs an itemId and a lore with en and pt"
			elseif c.c == "talk" and c.bring then
				local j = M.indexOf(cfg, c.bring)
				local from = j and cfg.steps[j]
				if not (j and j < i and M.dropCond(from)) then
					out[#out + 1] = where .. ": bring names no earlier drop step: " .. tostring(c.bring)
				end
			elseif c.c == "visit" and not (c.pos and num(c.radius, 0) >= 1) then
				out[#out + 1] = where .. ": a visit needs a position and a radius"
			elseif c.c == "resist" and (not c.mark or (c.mode ~= "prepare" and c.mode ~= "hold")) then
				out[#out + 1] = where .. ": a resist condition needs a mark and prepare / hold"
			elseif c.c == "boss" then
				bosses = bosses + 1
			end
		end
		for _, f in ipairs({"title", "hint", "done"}) do
			local t = st[f]
			if type(t) ~= "table" or type(t.en) ~= "string" or type(t.pt) ~= "string" then
				out[#out + 1] = where .. ": " .. f .. " needs en and pt"
			elseif holes(t.en) ~= holes(t.pt) then
				out[#out + 1] = where .. ": " .. f .. " en and pt have different {places}"
			end
		end
		if num(st.mins, -1) < 0 then
			out[#out + 1] = where .. ": no reward minutes"
		end
	end
	if bosses ~= 1 then
		out[#out + 1] = "exactly one boss step is needed"
	end
	for _, ch in ipairs(cfg.chapters or {}) do
		if type(ch.name) ~= "table" or type(ch.intro) ~= "table" then
			out[#out + 1] = "chapter " .. tostring(ch.n) .. " needs a name and an intro"
		end
	end
	return out
end

-- ------------------------------------------------------------------------------------------------- the quest drop
-- the chance per kill that makes a step of `mins` minutes with `target` drops last about that long
function M.dropChance(cfg, mins, target)
	local d = cfg.drop or {}
	local kills = max(1, num(mins, 1)) * num(d.killsPerMinute, 6)
	local p = num(target, 1) / kills
	return max(num(d.minChance, 0.05), min(num(d.maxChance, 0.6), p))
end

-- one kill of a monster while a count condition is open: does it count, does the drop fall. pity = kills without a drop.
-- rand = a number in [0,1). Returns counted, dropped, newPity
function M.onKill(cfg, step, cond, name, pity, rand)
	local match = false
	for _, m in ipairs(cond.mons or {}) do
		if m == name then
			match = true
		end
	end
	if not match then
		return false, false, pity
	end
	if not cond.item then
		return true, false, pity
	end
	local chance = M.dropChance(cfg, step.mins, cond.target)
	local expected = 1 / chance
	pity = num(pity, 0) + 1
	if pity >= expected * num((cfg.drop or {}).pityMult, 3) or num(rand, 1) < chance then
		return false, true, 0
	end
	return false, false, pity
end

-- ------------------------------------------------------------------------------------------------- the quest items (O553)
-- A drop step makes real items: a stock item (`itemId`) with custom attributes (mainquest_config.lua `questItem`): the key of the
-- drop step and the guid of its owner. The engine's item lock keeps it from every NPC, the trash and the market. The functions
-- that take engine objects (player, item, container) call only the plain TFS methods and are tested on a mock.

-- the index of the step with this key (nil when none)
function M.indexOf(cfg, key)
	for i, st in ipairs(cfg.steps or {}) do
		if st.key == key then
			return i
		end
	end
	return nil
end

-- the count condition of a step that drops a quest item (nil when the step has none)
function M.dropCond(step)
	for _, c in ipairs(step and step.conds or {}) do
		if c.c == "count" and c.item then
			return c
		end
	end
	return nil
end

-- the index of the step that takes the items of drop step i (a talk condition `bring`), nil when none does
function M.bringIndex(cfg, i)
	local key = cfg.steps[i] and cfg.steps[i].key
	for j = i + 1, #cfg.steps do
		for _, c in ipairs(cfg.steps[j].conds) do
			if c.c == "talk" and c.bring == key then
				return j
			end
		end
	end
	return nil
end

-- what a kill does for a character on step i: {mode, cond, step, index} or nil.
--   kill    a count step with no item: the counter
--   drop    a drop step: the item rolls while the character holds fewer than the target
--   refill  the bring step of a drop step: the same drop rolls again while the character holds fewer than it must bring (a lost
--           item falls again from the same monsters; Warden Ysolde says so)
function M.killRule(cfg, i)
	local step = cfg.steps[i]
	if not step then
		return nil
	end
	for _, c in ipairs(step.conds) do
		if c.c == "count" then
			return {mode = c.item and "drop" or "kill", cond = c, step = step, index = i}
		elseif c.c == "talk" and c.bring then
			local j = M.indexOf(cfg, c.bring)
			local from = j and cfg.steps[j]
			local dc = from and M.dropCond(from)
			if dc then
				return {mode = "refill", cond = dc, step = from, index = j, bring = true}
			end
		end
	end
	return nil
end

-- a step that opened before the real items (the stored `items` step is not this one): its old counter is honoured once
function M.legacy(i, itemsStep)
	return floor(num(itemsStep, -1)) ~= floor(num(i, 0))
end

-- the items a legacy drop step owes: the counter earned, made real (never more than the target, minus what is held)
function M.legacyOwed(cond, count, held)
	local earned = min(max(1, floor(num(cond.target, 1))), max(0, floor(num(count, 0))))
	return max(0, earned - max(0, floor(num(held, 0))))
end

-- players a kill counts for. killers = the players that made it (last hit, most damage, a summon's master); damagers = every
-- player that dealt damage. api: partyOf(p) -> the members of p's party (leader included) or nil; posOf(p) -> {x, y, z};
-- idOf(p) -> a unique id; sharedOn(p) -> true when p's party shares experience (it works). A killer always counts. A party member
-- of a killer counts when it stands on the killer's floor within `range` tiles and it dealt damage or the share works.
-- Returns the players (killers first, then the others by id) and the set of ids of the killers.
function M.credited(killers, damagers, api, range)
	local out, seen, direct = {}, {}, {}
	local function add(p)
		local id = api.idOf(p)
		if not seen[id] then
			seen[id] = true
			out[#out + 1] = p
		end
	end
	for _, k in ipairs(killers or {}) do
		direct[api.idOf(k)] = true
		add(k)
	end
	local dealt = {}
	for _, d in ipairs(damagers or {}) do
		dealt[api.idOf(d)] = true
	end
	local pending = {}
	for _, k in ipairs(killers or {}) do
		local members = api.partyOf(k)
		local kp = api.posOf(k)
		local shared = members and api.sharedOn(k) or false
		for _, m in ipairs(members or {}) do
			local id = api.idOf(m)
			if not seen[id] and not pending[id] then
				local mp = api.posOf(m)
				local near = kp and mp and kp.z == mp.z and max(math.abs(kp.x - mp.x), math.abs(kp.y - mp.y)) <= num(range, 30)
				if near and (dealt[id] or shared) then
					pending[id] = m
				end
			end
		end
	end
	local ids = {}
	for id in pairs(pending) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		add(pending[id])
	end
	return out, direct
end

local function customOf(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	if ok then
		return v
	end
	return nil
end

-- every item a character carries (the worn slots and the containers inside them), at most `limit` of them: fn(item) per item
function M.eachCarried(player, fn, limit)
	local seenN = 0
	limit = limit or 3000
	local function walk(container, depth)
		local okSize, size = pcall(function() return container:getSize() end)
		for k = 0, (okSize and size or 0) - 1 do
			if seenN >= limit then
				return
			end
			local item = container:getItem(k)
			if item then
				seenN = seenN + 1
				fn(item)
				local okC, isC = pcall(function() return item:isContainer() end)
				if okC and isC and depth < 8 then
					walk(item, depth + 1)
				end
			end
		end
	end
	for slot = 1, 10 do
		local item = player:getSlotItem(slot)
		if item then
			seenN = seenN + 1
			fn(item)
			local okC, isC = pcall(function() return item:isContainer() end)
			if okC and isC then
				walk(item, 1)
			end
		end
	end
end

-- the quest items of this character: the list of {item, count} and the total. stepKey = the drop step's key; nil = every step's
function M.questItems(cfg, player, stepKey)
	local qa = cfg.questItem
	local guid = player:getGuid()
	local list, total = {}, 0
	M.eachCarried(player, function(item)
		local k = customOf(item, qa.quest)
		if k ~= nil and (stepKey == nil or k == stepKey) and num(customOf(item, qa.owner), -1) == guid then
			local okN, n = pcall(function() return item:getCount() end)
			n = max(1, floor(num(okN and n or 1, 1)))
			list[#list + 1] = {item = item, count = n}
			total = total + n
		end
	end, qa.scanLimit)
	return list, total
end

function M.heldCount(cfg, player, stepKey)
	local _, total = M.questItems(cfg, player, stepKey)
	return total
end

-- take up to n quest items of a drop step (nil n = all of them) from the backpack: the number taken
function M.takeQuestItems(cfg, player, stepKey, n)
	local list = M.questItems(cfg, player, stepKey)
	local left = n or math.huge
	local taken = 0
	for _, e in ipairs(list) do
		if left <= 0 then
			break
		end
		local k = min(e.count, left)
		local ok, removed = pcall(function() return e.item:remove(k) end)
		if ok and removed then
			taken = taken + k
			left = left - k
		end
	end
	return taken
end

local function articleOf(name)
	return tostring(name):lower():match("^%s*[aeiou]") and "an" or "a"
end

-- make a created item a quest item of this step for this character (name, description, the marks, the lock); returns its name
function M.markItem(cfg, item, step, cond, player, lang)
	local qa = cfg.questItem
	local name = M.text(cond.item, lang)
	local idx = M.indexOf(cfg, step.key)
	local text = (idx and M.bringIndex(cfg, idx)) and cfg.texts.itemDesc or cfg.texts.itemDescAuto
	local desc = M.text(cond.lore, lang) .. " " .. string.format(M.text(text, lang), floor(num(cond.target, 1)))
	if ITEM_ATTRIBUTE_NAME then
		item:setAttribute(ITEM_ATTRIBUTE_NAME, name)
	end
	if ITEM_ATTRIBUTE_ARTICLE then
		item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, articleOf(name))
	end
	if ITEM_ATTRIBUTE_DESCRIPTION then
		item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, desc)
	end
	item:setCustomAttribute(qa.quest, step.key)
	item:setCustomAttribute(qa.owner, player:getGuid())
	item:setCustomAttribute(qa.lock, qa.lockValue)
	return name
end

-- ------------------------------------------------------------------------------------------------- the reward
-- the income table: {{level, gold per hour}, ...}, linear between the points, flat beyond
function M.income(points, level)
	level = num(level, 0)
	if level <= points[1][1] then
		return points[1][2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	return points[#points][2]
end

function M.gold(cfg, points, step)
	local r = num((cfg.reward or {}).round, 100)
	local g = M.income(points, step.level) * num(step.mins, 0) / 60
	return floor(g / r + 0.5) * r
end

-- {gold, items = {{id, count}}} (potions of the role folded in when the step names none: not used here)
function M.rewardOf(cfg, points, step)
	local out = {gold = M.gold(cfg, points, step), items = {}}
	for _, it in ipairs(step.items or {}) do
		out.items[#out.items + 1] = {it[1], it[2] or 1}
	end
	return out
end

function M.rewardText(cfg, rw, lang, nameOf)
	local T = cfg.texts
	local parts = {}
	if rw.gold > 0 then
		parts[#parts + 1] = string.format(M.text(T.gold, lang), M.int(rw.gold))
	end
	for _, it in ipairs(rw.items) do
		parts[#parts + 1] = string.format(M.text(T.items, lang), it[2], nameOf and nameOf(it[1]) or ("item " .. it[1]))
	end
	return #parts > 0 and table.concat(parts, ", ") or M.text(T.none, lang)
end

-- ------------------------------------------------------------------------------------------------- resistances
-- one resistance condition against the defence sheet (player_defence.lua PD.sheet: resist = {{k, sum, pct}}), the penalty
-- marks of player_defence_config.lua (marks[n].points) and the least safe result. Returns met (groups at the goal), total,
-- and the weakest group {k, value, goal}
function M.resistProgress(cond, sheet, marks, safeMin)
	local mark = marks and marks[cond.mark]
	if not mark or not sheet or not sheet.resist then
		return 0, 4, nil
	end
	local met, weakest = 0, nil
	local n = 0
	for _, r in ipairs(sheet.resist) do
		n = n + 1
		local value, goal
		if cond.mode == "prepare" then
			value, goal = num(r.sum, 0), num(mark.points, 0)
		else
			value, goal = num(r.pct, 0), num(safeMin, 0)
		end
		if value >= goal then
			met = met + 1
		end
		if not weakest or value - goal < weakest.value - weakest.goal then
			weakest = {k = r.k, value = value, goal = goal}
		end
	end
	return met, max(n, 4), weakest
end

-- the numbers the texts name, read from the configs of the systems: pd = player_defence_config, def = defence_config,
-- gd = gentledeath_config, cfg = this config
function M.vars(cfg, pd, def, gd, lang)
	local v = {}
	local marks = pd and pd.penalty and pd.penalty.marks or {}
	for i, m in ipairs(marks) do
		v["m" .. i], v["p" .. i], v["w" .. i] = m.level, m.points, m.warnFrom or m.level
	end
	if pd and pd.tree then
		v.share, v.tcap = floor((pd.tree.share or 1) * 100 + 0.5), pd.tree.cap
	end
	if def then
		v.cap = def.resistCap
	end
	v.safe = num((cfg.resist or {}).safeMin, 0)
	if gd and gd.xpLoss then
		local x = gd.xpLoss
		local free, half, full
		for _, p in ipairs(x) do
			if p.mult == 0 then
				free = p.level
			elseif p.mult == 1 and not full then
				full = p.level
			end
		end
		for _, p in ipairs(x) do
			if p.mult > 0 and p.mult < 1 then
				half = p.level
			end
		end
		if M.lang(lang) == "pt" then
			v.death_rule = string.format("nenhuma até o nível %d, metade no nível %d, total a partir do nível %d", free or 0, half or 0, full or 0)
		else
			v.death_rule = string.format("none up to level %d, half at level %d, full from level %d", free or 0, half or 0, full or 0)
		end
	end
	return v
end

-- the level a resistance step is meant for follows the config: know = warnFrom - offset, prepare = warnFrom, hold = the mark
function M.resistLevel(cfg, cond, marks)
	local m = marks and marks[cond.mark]
	if not m then
		return nil
	end
	if cond.mode == "hold" then
		return m.level
	elseif cond.mode == "prepare" then
		return m.warnFrom or m.level
	end
	return (m.warnFrom or m.level) - num((cfg.resist or {}).knowOffset, 15)
end

-- ------------------------------------------------------------------------------------------------- progress
local function condProgress(cond, facts, step)
	local k = cond.c
	if k == "count" then
		local t = max(1, floor(num(cond.target, 1)))
		local n = (cond.item and facts.held ~= nil) and facts.held or facts.count
		return min(t, max(0, floor(num(n, 0)))), t
	elseif k == "stat" then
		local t = max(1, floor(num(cond.target, 1)))
		return min(t, max(0, floor(num(facts.stats and facts.stats[cond.stat], 0)))), t
	elseif k == "flag" then
		return (facts.flags and facts.flags[cond.key]) and 1 or 0, 1
	elseif k == "talk" then
		return (facts.flags and facts.flags.talk) and 1 or 0, 1
	elseif k == "spell" then
		return facts.spell and 1 or 0, 1
	elseif k == "gear" then
		return facts.gear and 1 or 0, 1
	elseif k == "visit" then
		return facts.visit and 1 or 0, 1
	elseif k == "storage" then
		return num(facts.storage and facts.storage[cond.key], 0) >= num(cond.min, 1) and 1 or 0, 1
	elseif k == "boss" then
		return facts.boss and 1 or 0, 1
	elseif k == "resist" then
		local met, total = M.resistProgress(cond, facts.sheet, facts.marks, facts.safeMin)
		return met >= total and 1 or 0, 1, met, total
	end
	return 0, 1
end

-- progress, target and whether the step runs yet (false below its level: the row shows the level then). One condition with a
-- target above 1 shows its own count; several show how many hold
function M.progress(step, facts)
	facts = facts or {}
	local level = num(facts.level, 0)
	if step.level and level < step.level then
		return floor(level), floor(step.level), false
	end
	local conds = step.conds or {}
	if #conds == 1 then
		local p, t = condProgress(conds[1], facts, step)
		if conds[1].c == "resist" then
			local _, _, met, total = condProgress(conds[1], facts, step)
			return met or 0, total or 4, true
		end
		return p, t, true
	end
	local done = 0
	for _, c in ipairs(conds) do
		local p, t = condProgress(c, facts, step)
		if p >= t then
			done = done + 1
		end
	end
	return done, #conds, true
end

function M.isDone(step, facts)
	local p, t, running = M.progress(step, facts)
	return running and p >= t
end

-- the conditions that need a look at the engine (so the engine side reads only what the step needs)
function M.needs(step)
	local n = {}
	for _, c in ipairs(step.conds or {}) do
		n[c.c] = true
	end
	return n
end

-- ------------------------------------------------------------------------------------------------- chapters
function M.chapterOf(cfg, step)
	for _, ch in ipairs(cfg.chapters) do
		if ch.n == step.ch then
			return ch
		end
	end
	return nil
end

-- the first step of the chapter after the one of step index i (#steps + 1 when it is the last)
function M.nextChapterStart(cfg, i)
	local st = cfg.steps[i]
	if not st then
		return #cfg.steps + 1
	end
	for j = i, #cfg.steps do
		if cfg.steps[j].ch ~= st.ch then
			return j
		end
	end
	return #cfg.steps + 1
end

-- how many steps of each chapter a character has done: {{n, done, total}}
function M.chapterCounts(cfg, stepIndex)
	local out = {}
	for _, ch in ipairs(cfg.chapters) do
		out[#out + 1] = {n = ch.n, done = 0, total = 0}
	end
	for i, st in ipairs(cfg.steps) do
		local row = out[st.ch]
		if row then
			row.total = row.total + 1
			if i < stepIndex then
				row.done = row.done + 1
			end
		end
	end
	return out
end

-- ------------------------------------------------------------------------------------------------- first look
function M.firstState(cfg, level)
	if num(level, 0) > num(cfg.quietAbove, 500) then
		return cfg.states.quiet
	end
	return cfg.states.active
end

-- the first look: from step `from`, the steps the character has done already are passed silently (no reward). factsOf(i) ->
-- the facts of step i (the level of the character included); a step above the character's level is never passed. A step with a
-- count (kills, drops) or a talk condition is passed only for a character that played before (`played`), as the cast and kills
-- steps of the welcome path were. Returns the step to start on (#steps + 1 = every step done).
function M.skipDone(cfg, from, factsOf, played)
	local i = max(1, floor(num(from, 1)))
	while cfg.steps[i] do
		local step = cfg.steps[i]
		local needs = M.needs(step)
		local done
		local lvl = num(factsOf(i).level, 0)
		if played and not needs.boss and lvl - num(step.level, 0) >= num(cfg.silentGap, 40) then
			done = true
		elseif needs.count or needs.talk or needs.visit or needs.spell or needs.boss then
			done = played and lvl >= num(step.level, 0) and not needs.boss
		else
			done = M.isDone(step, factsOf(i))
		end
		if not done then
			break
		end
		i = i + 1
	end
	return i
end

-- ------------------------------------------------------------------------------------------------- the boss
-- the phase of Vael by his health fraction (1 = full): the first phase whose `above` is below the fraction
function M.phaseOf(boss, fraction)
	fraction = num(fraction, 1)
	for i, p in ipairs(boss.phases) do
		if fraction > p.above then
			return i, p
		end
	end
	return #boss.phases, boss.phases[#boss.phases]
end

-- the hit of a boss run: the share of the maximum health before the defence layer, times what the resistance of its element
-- leaves (resistPct: the result after the penalty, may be negative; at least -100, at most the cap). Never below 1.
function M.hitAmount(base, share, resistPct, cap)
	local r = num(resistPct, 0)
	cap = num(cap, 75)
	if r > cap then
		r = cap
	end
	if r < -100 then
		r = -100
	end
	return max(1, floor(num(base, 0) * num(share, 0) * (1 - r / 100)))
end

-- the door of the last page. ctx: {level, state, stepKey, sheetSafe = bool, cooldownLeft, won}. Returns nil (open) or a text key
function M.doorProblem(cfg, ctx)
	local b = cfg.boss
	if num(ctx.level, 0) < b.minLevel then
		return "door_closed"
	end
	if not ctx.sheetSafe then
		return "door_closed"
	end
	if ctx.state == cfg.states.active and ctx.stepKey ~= "boss" then
		return "door_closed"
	end
	if num(ctx.cooldownLeft, 0) > 0 then
		return "door_cooldown"
	end
	return nil
end

-- ------------------------------------------------------------------------------------------------- the tracker
-- the message: {title, step, count, chapter, chapterName, rows = [{key, title, progress, target, state, hint, where, detail}]}
-- rows = {} hides the section. facts of the current step; vars: M.vars; weakest text for a resist step
function M.view(cfg, state, stepIndex, facts, lang, vars)
	local steps = cfg.steps
	local i = floor(num(stepIndex, 1))
	if state ~= cfg.states.active or not steps[i] then
		return {rows = {}}
	end
	local step = steps[i]
	local p, t, running = M.progress(step, facts)
	local title = M.fill(M.text(step.title, lang), vars)
	if not running then
		title = string.format(M.text(cfg.texts.reachLevel, lang), title, t)
	end
	local detail
	for _, c in ipairs(step.conds) do
		if c.c == "resist" and facts and facts.sheet then
			local _, _, w = M.resistProgress(c, facts.sheet, facts.marks, facts.safeMin)
			if w then
				detail = string.format(M.text(cfg.texts.weakest, lang), w.k, floor(w.value), floor(w.goal))
			end
		end
	end
	if running and facts and facts.held ~= nil then
		local rule = M.killRule(cfg, i)
		if rule and rule.cond.item then
			detail = string.format(M.text(cfg.texts.held, lang), M.text(rule.cond.item, lang), floor(facts.held),
				floor(num(rule.cond.target, 1)))
		end
	end
	local ch = M.chapterOf(cfg, step)
	return {title = M.text(cfg.texts.title, lang), step = i, count = #steps, chapter = ch and ch.n or 0,
		chapterName = ch and M.text(ch.name, lang) or "",
		rows = {{key = step.key, title = title, progress = p, target = t, state = (running and p >= t) and "done" or "open",
			hint = M.fill(M.text(step.hint, lang), vars), where = step.where, detail = detail}}}
end

function M.sig(v, lang)
	local r = v.rows and v.rows[1]
	if not r then
		return "hidden"
	end
	return string.format("%s|%d/%d|%s|%d/%d|%s", tostring(lang), v.step, v.count, r.title, r.progress, r.target, tostring(r.detail))
end

-- ------------------------------------------------------------------------------------------------- the NPC
-- Warden Ysolde heard "oath" (or the quest's other words): when the current step wants a talk and the character's level is
-- there, set the talk flag. get(name) / set(name, v) read and write the storages by the names of cfg.storage. A step that brings
-- a drop step's items (O553 `bring`) needs the whole target first: items = {held(stepKey) -> n, take(stepKey, n) -> taken} (the
-- NPC script binds them to the character; a character whose step opened before the real items, M.legacy, hands nothing over).
-- Returns true (the flag was set; then the number of items taken and the drop condition), "short" (then held, target and the
-- drop condition: she took nothing), "wait" when the step is open but wants something else, nil with no open step.
function M.talk(cfg, get, set, items)
	if get("state") ~= cfg.states.active then
		return nil
	end
	local i = get("step")
	local step = cfg.steps[i]
	if not step then
		return nil
	end
	for _, c in ipairs(step.conds) do
		if c.c == "talk" then
			local j = c.bring and M.indexOf(cfg, c.bring)
			local dc = j and M.dropCond(cfg.steps[j])
			if dc and not M.legacy(i, get("items")) then
				local target = max(1, floor(num(dc.target, 1)))
				local held = items and items.held(c.bring) or 0
				if held < target then
					return "short", held, target, dc
				end
				local taken = items.take(c.bring, target)
				if taken < target then
					return "short", max(0, held - taken), target, dc
				end
				set("flags", M.setBit(get("flags"), 1))
				return true, taken, dc
			end
			set("flags", M.setBit(get("flags"), 1))
			return true, 0
		end
	end
	return "wait"
end

return M
