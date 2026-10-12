-- Item sets on the character: the set pieces a player wears, the bonuses they make active and the signature effects
-- (data/lib/chaos_item_sets.lua, the sets in chaos_item_sets_config.lua). Overview: server/README.md "Item sets".
-- Tested by server/tests/itemsets_test.lua against a mocked engine.
--
--   counting      item_mods.lua works the equipment out again on equip / unequip, at login and every 3 s, and asks
--                 ChaosItemSets.refresh(player) on the same path: the pieces worn in a slot they fit (ChaosItemMods.fits),
--                 counted by chaos_item_sets.lua (duplicates once, two-handed twice, the piece's level). The answer is
--                 the bonuses' modifier numbers, which item_mods.lua adds to the items' before the caps, so a set
--                 behaves like more modifiers (block, bleed chance, damage over time, a legendary power...) and
--                 everything that reads ChaosItemModsCache (item_powers.lua, loot.lua, the spells) sees them.
--   condition     skills, magic level, maximum health / mana (flat or percent): one CONDITION_ATTRIBUTES, sub id
--                 config.conditionSubId, replaced when it changes
--   resistances   onHealthChange on the player: hits of that element -N%
--   effects       Pyre Bulwark, Ashen Oath, Umbral Recoil   a dodge or block (ChaosItemMods.onAvoid, chained after
--                                                          item_powers.lua's Glacial Ward)
--                 Hemorrhage, Pack Bond (heal)             onKill of the player
--                 Red Harvest, Hanging Verdict, Thorn Volley, Soul Siphon, Umbral Recoil (the hit), Pack Bond
--                 (damage)                                 onHealthChange on the monsters the player or a summon of the
--                                                          player attacks (registered by onTargetCombat)
--                 Mirror Grace                             onHealthChange on a healed player
--   chase drops   ChaosItemSets.grantChase(player, source, key, ctx): rift.lua, raid.lua, descent.lua and dungeons.lua
--                 call it (guarded) where they hand out their rewards
--   look text     "Set: <name> (n/total)" and every bonus, [active] when the viewer has it
-- Every effect has a cooldown or a limit and a recursion guard; the effects only hit monsters that are nobody's summon.
-- Nothing is stored: the state is worked out again from the equipment. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua") -- loads chaos_item_mods.lua
end
if not (ChaosItemSets and ChaosItemSets.sets) then
	dofile("data/lib/chaos_item_sets.lua")
end

local S = ChaosItemSets
local M = ChaosItemMods
ChaosItemSetsCache = ChaosItemSetsCache or {} -- player id -> {state, totals, sig, condSig}
local cache = ChaosItemSetsCache
local guard = false
local cooldowns = {} -- player id -> {key -> ms}
local empowered = {} -- player id -> ms until the next hit is empowered (Umbral Recoil)
local bleeding = {} -- monster id -> {pid, untilMs}: a bleed of a Hemorrhage wearer ticks on it
local lastHit = {} -- monster id -> {hit, by (creature id), pid, at}
local tracked = 0

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function eff(key)
	return S.config.effects[key]
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	return master and master:isPlayer() and master or nil
end

local function wild(creature)
	return creature and creature:isMonster() and not creature:getMaster()
end

local function cdOf(player)
	local id = player:getId()
	cooldowns[id] = cooldowns[id] or {}
	return cooldowns[id]
end

local function effectsOf(player)
	local c = player and cache[player:getId()]
	return c and c.totals and c.totals.effects or nil
end

local function has(player, key)
	local e = effectsOf(player)
	return e ~= nil and e[key] == true
end

-- the animated text colours (combat_fx.lua M.label sends one byte of the client's 8-bit palette)
local TEXT = {orange = TEXTCOLOR_ORANGE or 198, yellow = TEXTCOLOR_YELLOW or 210, purple = TEXTCOLOR_PURPLE or 154,
	red = TEXTCOLOR_RED or 180}

local function label(pos, text, color)
	if ChaosCombatFx and ChaosCombatFx.label then
		pcall(ChaosCombatFx.label, pos, text, color)
	end
end

local function heal(creature, amount)
	if Chaos.heal then
		return Chaos.heal(creature, amount)
	end
	creature:addHealth("healing", amount)
end

-- ---------------------------------------------------------------- what is worn
function S.entriesOf(player)
	local out = {}
	local bits = M and M.slotBits and M.slotBits() or {}
	for slot in pairs(bits) do
		local item = player:getSlotItem(slot)
		if item and (not M.fits or M.fits(item, slot, bits)) then
			local set, piece = S.pieceOf(item)
			if set then
				out[#out + 1] = {id = piece.id, set = set.key, slot = slot}
			end
		end
	end
	table.sort(out, function(a, b) return a.slot < b.slot end)
	return out
end

-- the player's counted state (the tooltip, the look text); worked out now when nothing is cached
function S.stateOf(player)
	local c = player and cache[player:getId()]
	if c and c.state then
		return c.state
	end
	return S.count(player and S.entriesOf(player) or {}, player and player:getLevel() or 0)
end

-- ---------------------------------------------------------------- the condition
local PARAMS = {
	{"magic", "CONDITION_PARAM_STAT_MAGICPOINTS"}, {"skill_sword", "CONDITION_PARAM_SKILL_SWORD"},
	{"skill_axe", "CONDITION_PARAM_SKILL_AXE"}, {"skill_club", "CONDITION_PARAM_SKILL_CLUB"},
	{"skill_dist", "CONDITION_PARAM_SKILL_DISTANCE"}, {"skill_shield", "CONDITION_PARAM_SKILL_SHIELD"},
	{"skill_fist", "CONDITION_PARAM_SKILL_FIST"}, {"maxhealth", "CONDITION_PARAM_STAT_MAXHITPOINTS"},
	{"maxmana", "CONDITION_PARAM_STAT_MAXMANAPOINTS"},
	{"maxhealthpct", "CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT", 100}, -- the engine's percent is 100 + bonus
	{"maxmanapct", "CONDITION_PARAM_STAT_MAXMANAPOINTSPERCENT", 100}
}

local function applyCondition(player, entry, cond)
	local parts = {}
	for _, p in ipairs(PARAMS) do
		parts[#parts + 1] = tostring(cond[p[1]] or 0)
	end
	local sig = table.concat(parts, ",")
	if entry.condSig == sig then
		return
	end
	entry.condSig = sig
	local sub = S.config.conditionSubId
	player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, sub, true)
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT)
	c:setTicks(-1)
	c:setParameter(CONDITION_PARAM_SUBID, sub)
	local any = false
	for _, p in ipairs(PARAMS) do
		local v = cond[p[1]] or 0
		local param = _G[p[2]]
		if v > 0 and param then
			c:setParameter(param, (p[3] or 0) + v)
			any = true
		end
	end
	if any then
		player:addCondition(c)
	end
end

-- item_mods.lua M.refresh: the set state of the player now. Returns the modifier numbers of the active bonuses (added
-- to the items' before the caps) and a signature of what counts (the totals are worked out again when it changes).
function S.refresh(player)
	local id = player:getId()
	local entry = cache[id] or {}
	cache[id] = entry
	local state = S.count(S.entriesOf(player), player:getLevel())
	entry.state = state
	local sig = S.signature(state)
	if sig ~= entry.sig or not entry.totals then
		entry.sig = sig
		entry.totals = S.totals(state)
	end
	applyCondition(player, entry, entry.totals.cond)
	return entry.totals.mods, sig
end

-- ---------------------------------------------------------------- shared effect helpers
local function monstersAround(pos, radius, limit, skip)
	local out = {}
	for _, c in ipairs(Game.getSpectators(pos, false, false, radius, radius, radius, radius) or {}) do
		if #out >= limit then
			break
		end
		if c ~= skip and wild(c) and c:getHealth() > 0 then
			out[#out + 1] = c
		end
	end
	return out
end

local function strike(player, target, ctype, amount, fx)
	if not target or target:getHealth() <= 0 then
		return
	end
	guard = true
	local ok, err = pcall(doTargetCombatHealth, player:getId(), target:getId(), ctype, -math.abs(amount), -math.abs(amount),
		fx or CONST_ME_NONE)
	guard = false
	if not ok then
		print("[ChaosItemSets] " .. tostring(err))
	end
end

-- a damage over time of the player on a monster: `tick` damage every `interval` ms, `rounds` times
local function addDot(target, player, condType, rounds, interval, tick, fx)
	if not (Condition and condType) then
		return
	end
	local c = Condition(condType)
	c:setParameter(CONDITION_PARAM_OWNER, player:getId())
	c:setParameter(CONDITION_PARAM_DELAYED, true)
	c:addDamage(rounds, interval, -tick)
	target:addCondition(c)
	if fx then
		target:getPosition():sendMagicEffect(fx)
	end
end

local function ailment()
	return M and M.config and M.config.ailment or {share = 40, rounds = 4, interval = 1000}
end

local function bleed(target, player, hit)
	local a = ailment()
	addDot(target, player, CONDITION_BLEEDING, a.rounds, a.interval, S.dotTick(hit, a.share, a.rounds), CONST_ME_DRAWBLOOD)
end

local function prune()
	tracked = tracked + 1
	if tracked < 500 then
		return
	end
	tracked = 0
	local t = now()
	for id, b in pairs(bleeding) do
		if b.untilMs < t then
			bleeding[id] = nil
		end
	end
	for id, h in pairs(lastHit) do
		if t - h.at > 10000 then
			lastHit[id] = nil
		end
	end
end

-- ---------------------------------------------------------------- dodges and blocks
local function onAvoid(player, attacker, kind, damage)
	if guard or not player or not player:isPlayer() then
		return
	end
	local e = effectsOf(player)
	if not e then
		return
	end
	local t, cd = now(), cdOf(player)
	if e.pyrebulwark and wild(attacker) and (tonumber(damage) or 0) > 0 then
		local c = eff("pyrebulwark")
		if S.ready(cd, "pyrebulwark", t, c.cooldownMs) then
			addDot(attacker, player, CONDITION_FIRE, c.rounds, c.interval, S.dotTick(damage, c.pct, c.rounds), CONST_ME_HITBYFIRE)
			label(attacker:getPosition(), "Pyre Bulwark", TEXT.orange)
		end
	end
	if e.oathward and kind == "block" then
		local c = eff("oathward")
		if S.ready(cd, "oathward", t, c.cooldownMs) then
			local pos = player:getPosition()
			local party = player.getParty and player:getParty()
			local members = {player}
			if party then
				members = party:getMembers() or {}
				members[#members + 1] = party:getLeader()
			end
			for _, m in ipairs(members) do
				local mp = m and m:getPosition()
				if mp and mp.z == pos.z and math.max(math.abs(mp.x - pos.x), math.abs(mp.y - pos.y)) <= c.radius
						and m:getHealth() > 0 then
					heal(m, S.share(m:getMaxHealth(), c.healPct))
					mp:sendMagicEffect(CONST_ME_MAGIC_GREEN or CONST_ME_MAGIC_BLUE)
				end
			end
			label(pos, "Ashen Oath", TEXT.yellow)
		end
	end
	if e.umbralrecoil and kind == "dodge" then
		local c = eff("umbralrecoil")
		if S.ready(cd, "umbralrecoil", t, c.cooldownMs) then
			empowered[player:getId()] = t + c.windowMs
			if Condition and CONDITION_HASTE then
				local h = Condition(CONDITION_HASTE)
				h:setParameter(CONDITION_PARAM_TICKS, c.ms)
				h:setParameter(CONDITION_PARAM_SPEED, c.speed)
				player:addCondition(h)
			end
			player:getPosition():sendMagicEffect(CONST_ME_PURPLEENERGY or CONST_ME_MAGIC_BLUE or 48)
			label(player:getPosition(), "Umbral Recoil", TEXT.purple)
		end
	end
end

-- chained after whatever item_powers.lua set (Glacial Ward); again at startup, after every script is loaded
local function chainAvoid()
	if not M then
		return
	end
	if M.onAvoid ~= S.avoidHook then
		S.prevAvoid = M.onAvoid
	end
	S.avoidHook = S.avoidHook or function(...)
		if S.prevAvoid then
			local ok, err = pcall(S.prevAvoid, ...)
			if not ok then
				print("[ChaosItemSets] " .. tostring(err))
			end
		end
		onAvoid(...)
	end
	M.onAvoid = S.avoidHook
end
chainAvoid()
S.onAvoid = onAvoid -- tests

-- ---------------------------------------------------------------- hits on monsters
local DEALT = {"hemorrhage", "redharvest", "hangingverdict", "thornvolley", "soulsiphon", "umbralrecoil", "packbond"}

local dealt = CreatureEvent("ChaosItemSetsDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin, critical)
	if guard or primaryType == COMBAT_HEALING or not wild(creature) then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local p = playerOf(attacker)
	local e = effectsOf(p)
	if not e then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local t, cd, cid = now(), cdOf(p), creature:getId()
	local own = attacker == p
	if origin == ORIGIN_CONDITION then
		local hit = math.abs(primaryDamage) + math.abs(secondaryDamage)
		if own and e.hemorrhage and primaryType == COMBAT_PHYSICALDAMAGE then
			bleeding[cid] = {pid = p:getId(), untilMs = t + eff("hemorrhage").windowMs}
			prune()
		end
		if own and e.soulsiphon and hit > 0 then
			heal(p, S.share(hit, eff("soulsiphon").pct))
		end
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local pct = 0
	if not own and e.packbond then
		pct = pct + eff("packbond").pct
	end
	if own and e.hangingverdict and origin == ORIGIN_RANGED and S.verdict(creature:getHealth(), creature:getMaxHealth()) then
		pct = pct + eff("hangingverdict").pct
	end
	if own and e.umbralrecoil and (empowered[p:getId()] or 0) >= t then
		empowered[p:getId()] = nil
		pct = pct + eff("umbralrecoil").pct
		label(creature:getPosition(), "Recoil", TEXT.purple)
	end
	if pct > 0 then
		primaryDamage = S.scale(primaryDamage, pct)
		secondaryDamage = S.scale(secondaryDamage, pct)
	end
	local hit = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if hit <= 0 then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	lastHit[cid] = {hit = hit, by = attacker and attacker:getId() or 0, pid = p:getId(), at = t}
	prune()
	local lethal = hit >= creature:getHealth()
	if own and not lethal then
		if e.redharvest and critical and S.ready(cd, "redharvest", t, eff("redharvest").cooldownMs) then
			bleed(creature, p, hit)
			bleeding[cid] = {pid = p:getId(), untilMs = t + eff("hemorrhage").windowMs}
			label(creature:getPosition(), "Red Harvest", TEXT.red)
		end
		if e.thornvolley and origin == ORIGIN_RANGED and S.ready(cd, "thornvolley", t, eff("thornvolley").cooldownMs) then
			local c = eff("thornvolley")
			local other = monstersAround(creature:getPosition(), c.radius, 1, creature)[1]
			if other then
				strike(p, other, primaryType, S.share(hit, c.pct), CONST_ME_GROUNDSHAKER or CONST_ME_NONE)
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:register()

local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and target:isMonster() then
		local e = effectsOf(playerOf(creature))
		if e then
			for _, key in ipairs(DEALT) do
				if e[key] then
					target:registerEvent("ChaosItemSetsDealt")
					break
				end
			end
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

-- ---------------------------------------------------------------- kills
local kill = CreatureEvent("ChaosItemSetsKill")
function kill.onKill(player, target)
	if guard or not wild(target) or not player:isPlayer() then
		return true
	end
	local tid = target:getId()
	local b, h = bleeding[tid], lastHit[tid]
	bleeding[tid], lastHit[tid] = nil, nil
	local e = effectsOf(player)
	if not e then
		return true
	end
	local t = now()
	if e.hemorrhage and b and b.pid == player:getId() and b.untilMs >= t then
		local c = eff("hemorrhage")
		local hit = h and h.hit or S.share(target:getMaxHealth(), 5)
		local spread = monstersAround(target:getPosition(), c.radius, c.targets, target)
		for _, m in ipairs(spread) do
			bleed(m, player, hit)
			bleeding[m:getId()] = {pid = player:getId(), untilMs = t + c.windowMs}
		end
		if #spread > 0 then
			label(target:getPosition(), "Hemorrhage", TEXT.red)
		end
	end
	if e.packbond and h and h.pid == player:getId() and h.by ~= player:getId() then
		local summon = Creature(h.by)
		if summon and summon:getMaster() == player then
			heal(player, S.share(player:getMaxHealth(), eff("packbond").healPct))
		end
	end
	return true
end
kill:register()

-- ---------------------------------------------------------------- hits and heals on players
local ELEMENT = {}
for name, el in pairs({COMBAT_PHYSICALDAMAGE = "physical", COMBAT_FIREDAMAGE = "fire", COMBAT_ICEDAMAGE = "ice",
		COMBAT_EARTHDAMAGE = "earth", COMBAT_ENERGYDAMAGE = "energy", COMBAT_DEATHDAMAGE = "death", COMBAT_HOLYDAMAGE = "holy"}) do
	if _G[name] then
		ELEMENT[_G[name]] = el
	end
end

local taken = CreatureEvent("ChaosItemSetsTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if guard then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if primaryType == COMBAT_HEALING then
		-- Mirror Grace: the healer gets a share of a heal on another player
		local healer = attacker and attacker:isPlayer() and attacker or nil
		if healer and healer ~= creature and has(healer, "mirrorgrace") and primaryDamage > 0 then
			guard = true
			pcall(heal, healer, S.share(primaryDamage, eff("mirrorgrace").pct))
			guard = false
		end
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local c = cache[creature:getId()]
	local res = c and c.totals and c.totals.res
	if res and next(res) then
		local r1, r2 = res[ELEMENT[primaryType] or ""] or 0, res[ELEMENT[secondaryType] or ""] or 0
		if r1 > 0 then
			primaryDamage = S.scale(primaryDamage, -math.min(r1, 90))
		end
		if r2 > 0 then
			secondaryDamage = S.scale(secondaryDamage, -math.min(r2, 90))
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

-- ---------------------------------------------------------------- chase drops
local function give(player, item)
	if player:addItemEx(item, false) == RETURNVALUE_NOERROR then
		return false
	end
	local box = player.getInbox and player:getInbox()
	if box and box:addItemEx(item, INDEX_WHEREEVER, FLAG_NOLIMIT) == RETURNVALUE_NOERROR then
		return true
	end
	player:addItemEx(item, true)
	return true
end

-- one chase roll for a player (S.rollChase): the piece is made, given (backpack, else the inbox) and announced.
-- source / key / ctx as S.chaseChance; ctx.level and ctx.itemFind are filled in. Returns the piece's name or nil.
function S.grantChase(player, source, key, ctx, rand)
	if not player then
		return nil
	end
	ctx = ctx or {}
	ctx.level = ctx.level or player:getLevel()
	if not ctx.itemFind then
		ctx.itemFind = ChaosLoot and ChaosLoot.itemFindMult and ChaosLoot.itemFindMult(player) or 1
	end
	local hit = S.rollChase(source, key, ctx, rand)
	if not hit then
		return nil
	end
	local item = Game.createItem(hit.piece.id, 1)
	if not item then
		return nil
	end
	if ChaosMakeUnique then
		ChaosMakeUnique(item)
	end
	local inbox = give(player, item)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("You found %s, a piece of %s.%s", hit.piece.name,
		hit.set.name, inbox and " Your backpack was full: it is in your inbox." or ""))
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_GREEN)
	if Game.broadcastMessage then
		Game.broadcastMessage(string.format("%s found %s (%s)!", player:getName(), hit.piece.name, hit.set.name),
			MESSAGE_EVENT_ADVANCE)
	end
	return hit.piece.name
end

-- ---------------------------------------------------------------- look text
local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing.isItem and thing:isItem() then
		local set = S.pieceOf(thing)
		if set then
			local lines = S.lookLines(set.key, S.stateOf(self))
			if #lines > 0 then
				description = (description or "") .. "\n" .. table.concat(lines, "\n")
			end
		end
	end
	return description
end
look:register(121) -- after salvage.lua's lock line (120)

-- ---------------------------------------------------------------- the Character Info page (client game_chaosinfo)
-- "sets": the sets the player wears, how many pieces count and which bonuses are active (commands_ui.lua shows the text)
function S.summaryLines(state)
	local out = {}
	for _, set in ipairs(S.sets) do
		local st = state and state.sets[set.key]
		if st and (st.count > 0 or next(st.low)) then
			local active = {}
			for _, b in ipairs(S.active(set, st.count)) do
				active[#active + 1] = "(" .. b.n .. ")"
			end
			local low = 0
			for _ in pairs(st.low) do
				low = low + 1
			end
			out[#out + 1] = string.format("%s: %d/%d, %s%s", set.name, st.count, set.total,
				#active > 0 and ("bonuses " .. table.concat(active, " ") .. " active") or "no bonus yet",
				low > 0 and string.format(" (%d worn below their level)", low) or "")
		end
	end
	if #out == 0 then
		out[1] = "No item set pieces worn."
	end
	return out
end

if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end
ChaosCommands.register("sets", function(player)
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Item sets: " .. table.concat(S.summaryLines(S.stateOf(player)), "; "))
	return false
end)

-- ---------------------------------------------------------------- login / logout
local startup = GlobalEvent("ChaosItemSetsStartup")
function startup.onStartup()
	chainAvoid()
	return true
end
startup:register()

local login = CreatureEvent("ChaosItemSetsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosItemSetsTaken")
	player:registerEvent("ChaosItemSetsKill")
	player:registerEvent("ChaosItemSetsLogout")
	chainAvoid()
	return true
end
login:register()

local logout = CreatureEvent("ChaosItemSetsLogout")
function logout.onLogout(player)
	local id = player:getId()
	cache[id], cooldowns[id], empowered[id] = nil, nil, nil
	return true
end
logout:register()

S.runtime = {bleeding = bleeding, lastHit = lastHit, empowered = empowered, cooldowns = cooldowns} -- tests
