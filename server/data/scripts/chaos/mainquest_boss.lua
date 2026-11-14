-- mainquest_boss.lua: the last page of the main quest (O551; mainquest_config.lua `boss`, server/README.md "Main quest (O551)"):
-- Vael Ashmourn, the Unsworn Warden, fought alone in the Oath Chamber. It is a spell trial of the Vocation Trials engine
-- (trials.lua; trials_config.lua spellTiers key "mq"): a runtime-built solo room, lives instead of death, a clock, a crash marker,
-- the floor telegraphs of the family's mechanics. What this file adds:
--   * the door: Warden Ysolde's "door" (the NPC sets the door flag, the sweep here answers) opens only to a character at level 500
--     with the four resistances at the safe value (the strict gate of the last "Hold the line" step) and, while the quest runs,
--     only on the boss step; a failed run closes it for retryCooldownSeconds
--   * the four phases by Vael's health (fire, cold, lightning, chaos): his lines, and the element of his hits. The Trials replace
--     a monster's hit by a share of the character's maximum health, which threw away what the defence layer (player_defence.lua)
--     had worked out; for this boss T.questHit applies the resistance of the phase's element to that share, so the resistances
--     the quest taught decide the hit (core: ChaosMainQuestCore.hitAmount; tests/mainquest_boss_test.lua)
--   * Vael's own attacks (O554; mainquest_boss_config.lua, mainquest_boss_attacks_core.lua): six named shapes (cone, rain, ring, lance, cross,
--     and in the last phase the cross and the rain together), each marked on the floor by the floor telegraph (O549) before the hit;
--     only a character on a marked tile at the hit takes it, with the resistance of the phase's element. They take the place of the
--     family's floor mechanics (stillness, zones, pyre) in this trial: T.questOwnsFloor
--   * the reward, once per character: gold to the bank, orbs, Vigil reputation and the achievement Ember-Sworn (its title; the counter
--     mainquest_boss, achievements_data.lua)
-- Hooks of trials.lua: T.hookFor (won / failed), T.bossNameFor, T.questHit. Assumed engine API (TFS 1.4): GlobalEvent, Creature(name),
-- Monster(id), Creature:say, Player storages and bank. Lua 5.1 / LuaJIT and 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosMainQuestCore or not ChaosMainQuestCore.view then
	dofile("data/scripts/chaos/mainquest_core.lua")
end
if not ChaosVaelAttacks or not ChaosVaelAttacks.plan then
	dofile("data/scripts/chaos/mainquest_boss_attacks_core.lua")
end
ChaosTrials = ChaosTrials or {}

local K = ChaosMainQuestCore
local T = ChaosTrials
ChaosMainQuestBoss = ChaosMainQuestBoss or {}
local B = ChaosMainQuestBoss

local function C()
	return K.cfg()
end

local function log(text)
	print("[Chaos main quest boss] " .. tostring(text))
end

local function key(name)
	local s = C().storage
	return s.base + s[name]
end

local function get(player, name)
	return player:getStorageValue(key(name))
end

local function set(player, name, v)
	player:setStorageValue(key(name), v)
end

local function langOf(player)
	if Chaos.lang then
		local ok, l = pcall(Chaos.lang, player)
		if ok then
			return K.lang(l)
		end
	end
	return "en"
end

local function vael(player, which)
	return K.text(C().vael[which], langOf(player))
end

local function say(player, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text)
end

-- ---------------------------------------------------------------- the door
-- the four resistances at the safe value (the same rule as the "Hold the line" steps: the result after the penalty)
function B.sheetSafe(player)
	if not (ChaosPlayerDefence and ChaosPlayerDefence.sheet) then
		return false
	end
	local ok, sheet = pcall(ChaosPlayerDefence.sheet, player)
	if not ok or not sheet or not sheet.resist then
		return false
	end
	local safe = (C().resist or {}).safeMin or 0
	local n = 0
	for _, r in ipairs(sheet.resist) do
		n = n + 1
		if (tonumber(r.pct) or -999) < safe then
			return false
		end
	end
	return n >= 4
end

local function keeperNear(player)
	local c = C()
	local ok, npc = pcall(Creature, c.boss.keeper)
	if not ok or not npc or not npc.getPosition then
		return false
	end
	local a, b = player:getPosition(), npc:getPosition()
	return a.z == b.z and math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) <= (c.boss.range or 6)
end

-- nil (open) or the text key of the refusal
function B.doorProblem(player)
	local c = C()
	local step = c.steps[get(player, "step")]
	return K.doorProblem(c, {level = player:getLevel(), state = get(player, "state"), stepKey = step and step.key or nil,
		sheetSafe = B.sheetSafe(player), cooldownLeft = math.max(0, get(player, "cooldown") - os.time()),
		won = get(player, "won") == 1})
end

-- the character asked for the door: the answer in the chat (Ysolde's lines), and the run when it opens
function B.enter(player)
	local c = C()
	if not keeperNear(player) then
		return false, K.text(c.ysolde.door_closed, langOf(player))
	end
	local why = B.doorProblem(player)
	if why then
		return false, K.text(c.ysolde[why], langOf(player))
	end
	if not (ChaosTrials and ChaosTrials.enter) then
		return false, K.text(c.ysolde.door_closed, langOf(player))
	end
	local ok, text = ChaosTrials.enter(player, nil, {spell = c.boss.tier})
	if not ok then
		return false, text
	end
	set(player, "tries", math.max(0, get(player, "tries")) + 1)
	return true, vael(player, "enter")
end

-- the door flag set by Ysolde's script (own Lua state): one look per sweep
function B.sweepDoor(player)
	local c = C()
	local name, bit = K.flagPlace(c, "door")
	if not name then
		return
	end
	local mask = math.max(0, get(player, name))
	if not K.hasBit(mask, bit) then
		return
	end
	set(player, name, K.clearBit(mask, bit))
	local ok, text = B.enter(player)
	local who = langOf(player) == "pt" and "Guardiã Ysolde: " or "Warden Ysolde: "
	if ok then
		say(player, who .. K.text(C().ysolde.door_open, langOf(player)))
		say(player, (C().boss.name or "Vael") .. ": " .. tostring(text))
	elseif text and text ~= "" then
		say(player, who .. text)
	end
end

-- ---------------------------------------------------------------- the trial's hooks
local function isOurs(tr)
	return tr and tr.spell == C().boss.tier
end

-- the resistance of a character to an element (the result after the penalty) and the cap: nil when the defence layer is not there
function B.resist(player, element)
	local PD = ChaosPlayerDefence
	local pct = PD and PD.resistOfElement and PD.resistOfElement(player, element) or nil
	if pct == nil then
		return nil, 75
	end
	local cap = 75
	local def = dofile("data/scripts/chaos/defence_config.lua")
	if type(def) == "table" and def.resistCap then
		cap = def.resistCap
	end
	return pct, cap
end

-- the hit of Vael: the share of the maximum health the Trials worked out, with the resistance to the phase's element
function T.questHit(player, tr, isBoss, amount)
	if not isOurs(tr) then
		return amount
	end
	local boss = tr.bossId and Monster(tr.bossId)
	local fraction = 1
	if boss and boss.getMaxHealth and boss:getMaxHealth() > 0 then
		fraction = boss:getHealth() / boss:getMaxHealth()
	end
	local _, phase = K.phaseOf(C().boss, fraction)
	local pct, cap = B.resist(player, phase.element)
	if pct == nil then
		return amount
	end
	return K.hitAmount(amount, 1, pct, cap)
end

-- the family's floor mechanics (stillness, zones, pyre) do not run in this trial: Vael's attacks are its floor (trials.lua tick)
function T.questOwnsFloor(tr)
	local a = ChaosVaelAttacks and ChaosVaelAttacks.cfg()
	return isOurs(tr) and a ~= nil and a.enabled == true
end

function T.bossNameFor(tr)
	if isOurs(tr) then
		return C().boss.name
	end
	return nil
end

B.hook = {
	won = function(player, tr)
		local c = C()
		local lines = {vael(player, "victory")}
		if get(player, "won") == 1 then
			return lines -- the reward is once per character
		end
		set(player, "won", 1)
		local r = c.boss.reward
		player:setBankBalance(player:getBankBalance() + r.gold)
		for _, it in ipairs(r.items) do
			local given = Chaos.giveItem and Chaos.giveItem(player, it[1], it[2]) or 0
			if (tonumber(given) or 0) < it[2] then
				local okI, inbox = pcall(function() return player:getInbox() end)
				if okI and inbox then
					inbox:addItem(it[1], it[2] - (tonumber(given) or 0))
				end
			end
		end
		if ChaosFactions and ChaosFactions.gain and r.repGain then
			pcall(ChaosFactions.gain, player, "vigil", r.repGain, "mainquest", true)
		end
		if ChaosAchievements and ChaosAchievements.set then
			pcall(ChaosAchievements.set, player, "mainquest_boss", 1)
		end
		local lang = langOf(player)
		lines[#lines + 1] = string.format(K.text(c.texts.finished, lang))
		lines[#lines + 1] = string.format(K.text(c.texts.gold, lang), K.int(r.gold))
		return lines
	end,
	failed = function(player, tr, how)
		if how == "error" or how == "logout" or how == "abort" then
			return
		end
		set(player, "cooldown", os.time() + (C().boss.retryCooldownSeconds or 60))
		say(player, vael(player, "defeat"))
	end
}

function T.hookFor(tr)
	if isOurs(tr) then
		return B.hook
	end
	return nil
end

-- ---------------------------------------------------------------- the phases: Vael's lines
function B.watch()
	local c = C()
	if not c or not c.enabled or not T.runs then
		return
	end
	for pid, tr in pairs(T.runs) do
		if isOurs(tr) and not tr.over and tr.bossId then
			local boss = Monster(tr.bossId)
			local player = Player(pid)
			if boss and player and boss:getMaxHealth() > 0 then
				local fraction = boss:getHealth() / boss:getMaxHealth()
				local idx, phase = K.phaseOf(c.boss, fraction)
				if tr.mqPhase ~= idx then
					tr.mqPhase = idx
					local text = vael(player, phase.say)
					boss:say(text, TALKTYPE_MONSTER_SAY)
					say(player, (c.boss.name or "Vael") .. ": " .. text)
				end
				local below = (ChaosTrialsCore and ChaosTrialsCore.cfg and ChaosTrialsCore.cfg() or {}).enrageBelow or 0.30
				if fraction < below and not tr.mqEnraged then
					tr.mqEnraged = true
					local text = vael(player, "enrage")
					boss:say(text, TALKTYPE_MONSTER_SAY)
					say(player, (c.boss.name or "Vael") .. ": " .. text)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- Vael's attacks (O554)
local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function atkCfg()
	return ChaosVaelAttacks.cfg()
end

-- every floor tile of the trial's room (the shapes cut what lies outside)
local function roomGrid(tr)
	if not tr.mqGrid then
		local list, L = {}, tr.L
		for y = L.y1, L.y2 do
			for x = L.x1, L.x2 do
				list[#list + 1] = {x = x, y = y, z = L.z}
			end
		end
		tr.mqGrid = ChaosBossMechCore.grid(list)
	end
	return tr.mqGrid
end

local function enrageBelow()
	return (ChaosTrialsCore and ChaosTrialsCore.cfg and ChaosTrialsCore.cfg() or {}).enrageBelow or 0.30
end

-- the sprite marks of one pulse for players without game_telegraph (who = nil: everybody near; the floor mark replaces them for
-- the others); the hit effect itself is always sent
local function pulse(tiles, kind, who)
	for _, t in ipairs(tiles) do
		local pos = Position(t.x, t.y, t.z)
		local fx = kind == "fill" and (CONST_ME_DRAWBLOOD or CONST_ME_MAGIC_RED) or (CONST_ME_MAGIC_RED or CONST_ME_FIREAREA)
		if who then
			pos:sendMagicEffect(fx, who)
		else
			pos:sendMagicEffect(fx)
		end
	end
end

-- starts one attack: picks it by the phase, makes its tiles, opens the floor marks and times the hit. false when none was cast
-- (no fair plan: the same is tried again in a second)
function B.startAttack(tr, player, boss, rand)
	local cfg = atkCfg()
	rand = rand or math.random
	local A = ChaosVaelAttacks
	local max = boss:getMaxHealth()
	local fraction = max > 0 and boss:getHealth() / max or 1
	local idx, phase = K.phaseOf(C().boss, fraction)
	local enraged = fraction < enrageBelow()
	local attack = A.pick(cfg, idx, tr.mqLast, rand)
	local now = nowMs()
	if not attack then
		tr.mqNext = now + 1000
		return false
	end
	local bp, pp = boss:getPosition(), player:getPosition()
	local plan = A.plan(cfg, attack, {grid = roomGrid(tr), boss = {x = bp.x, y = bp.y, z = bp.z},
		target = {x = pp.x, y = pp.y, z = pp.z}, players = {{x = pp.x, y = pp.y, z = pp.z}}, rand = rand})
	if not plan.fair or #plan.tiles == 0 then
		tr.mqNext = now + 1000
		return false
	end
	tr.mqLast = attack.key
	tr.mqSeq = (tr.mqSeq or 0) + 1
	local pending = {seq = tr.mqSeq, plan = plan, attack = attack, phase = phase, enraged = enraged, startedAt = now}
	tr.mqPending = pending
	tr.mqNext = now + A.delayAfter(cfg, idx, enraged, attack)
	-- the floor marks (O549): one per part, the sprite marks only for whoever has no game_telegraph
	local marks = {}
	for i, part in ipairs(plan.parts) do
		if ChaosTelegraph and #part.tiles > 0 then
			marks[i] = ChaosTelegraph.open("mq:" .. tr.pid .. ":" .. pending.seq .. ":" .. i, part.tiles,
				{ms = plan.windMs, color = cfg.color[phase.element], user = "trials"})
		end
	end
	pending.marks = marks
	local pid = tr.pid
	for _, pl in ipairs(ChaosBossMechCore.pulses(plan.windMs, 600, 900)) do
		addEvent(function()
			if T.runs[pid] ~= tr or tr.over or tr.mqPending ~= pending then
				return
			end
			for i, part in ipairs(plan.parts) do
				if marks[i] and ChaosTelegraph then
					ChaosTelegraph.draw(marks[i], function(who) pulse(part.tiles, pl.kind, who) end)
				else
					pulse(part.tiles, pl.kind, nil)
				end
			end
		end, pl.at)
	end
	-- the call: Vael says it, the character reads it (and what to do about it, once a run)
	local lang = langOf(player)
	local text = K.text(attack.say, lang)
	boss:say(text, TALKTYPE_MONSTER_SAY)
	say(player, (C().boss.name or "Vael") .. ": " .. text)
	tr.mqTold = tr.mqTold or {}
	if not tr.mqTold[attack.key] then
		tr.mqTold[attack.key] = true
		say(player, K.text(attack.name, lang) .. ": " .. K.text(attack.tip, lang))
	end
	addEvent(B.resolveAttack, plan.windMs + (cfg.lagMs or 0), pid, tr, pending)
	return true
end

-- the hit: only a character on a marked tile takes it, the share of its parts, with the resistance of the phase's element
function B.resolveAttack(pid, tr, pending)
	if T.runs[pid] ~= tr or tr.mqPending ~= pending then
		return
	end
	tr.mqPending = nil
	local player = Player(pid)
	local boss = tr.bossId and Monster(tr.bossId)
	if tr.over or not player or not boss then
		if ChaosTelegraph then
			pcall(ChaosTelegraph.closePrefix, "mq:" .. pid .. ":" .. pending.seq .. ":")
		end
		return
	end
	local cfg = atkCfg()
	local A = ChaosVaelAttacks
	local effect = _G[cfg.hitEffect[pending.phase.element] or "CONST_ME_FIREAREA"] or CONST_ME_FIREAREA
	for i, t in ipairs(pending.plan.tiles) do
		if i % 2 == 1 then
			Position(t.x, t.y, t.z):sendMagicEffect(effect)
		end
	end
	local pos = player:getPosition()
	if tr.fallen or (tr.shieldUntil or 0) > nowMs() or not (ChaosTrialsCore and ChaosTrialsCore.inRoom(tr.L, pos)) then
		return
	end
	local share = A.shareAt(cfg, pending.plan, pos, pending.enraged)
	if share <= 0 then
		return -- dodged
	end
	local pct, cap = B.resist(player, pending.phase.element)
	local scale = tr.tierDef and tr.tierDef.hit and tr.tierDef.hit > 0 and (tr.scale.hit / tr.tierDef.hit) or 1
	local eff = A.effectiveShare(share, scale, pct, cap)
	if T.hurt then
		T.hurt(tr, player, eff, effect)
	end
end

-- the loop: while Vael fights, one attack at a time, by the phase's cadence
function B.attackTick(rand)
	local cfg = ChaosVaelAttacks and atkCfg()
	if not cfg or not cfg.enabled or not T.runs then
		return
	end
	local now = nowMs()
	for pid, tr in pairs(T.runs) do
		if isOurs(tr) and not tr.over and tr.phase == "fight" and tr.stage and tr.stage.kind == "boss" and tr.bossId and not tr.mqPending then
			local boss, player = Monster(tr.bossId), Player(pid)
			if boss and player and boss:getMaxHealth() > 0 then
				tr.mqNext = tr.mqNext or (now + cfg.firstDelayMs)
				local shield = tr.shieldUntil or 0
				if shield > now then
					tr.mqNext = math.max(tr.mqNext, shield + 1000) -- after a fall: no attack while the monsters cannot touch the character
				end
				if now >= tr.mqNext then
					B.startAttack(tr, player, boss, rand)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- events
if GlobalEvent then
	local think = GlobalEvent("ChaosMainQuestBossWatch")
	function think.onThink(interval)
		local ok, err = pcall(B.watch)
		if not ok then
			log("watch: " .. tostring(err))
		end
		return true
	end
	think:interval(1000)
	think:register()

	local attackLoop = GlobalEvent("ChaosMainQuestBossAttacks")
	function attackLoop.onThink(interval)
		local ok, err = pcall(B.attackTick)
		if not ok then
			log("attacks: " .. tostring(err))
		end
		return true
	end
	attackLoop:interval((ChaosVaelAttacks.cfg() or {}).tickMs or 250)
	attackLoop:register()
end
