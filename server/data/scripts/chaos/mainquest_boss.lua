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
	local PD = ChaosPlayerDefence
	local pct = PD and PD.resistOfElement and PD.resistOfElement(player, phase.element) or nil
	if pct == nil then
		return amount
	end
	local cap = 75
	local def = dofile("data/scripts/chaos/defence_config.lua")
	if type(def) == "table" and def.resistCap then
		cap = def.resistCap
	end
	return K.hitAmount(amount, 1, pct, cap)
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
end
