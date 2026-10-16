-- Chaos: Classes. Vocation Trials (trials.lua ChaosTrials, storages of trials_config.lua), the ascension quest
-- (ascension_quest.lua ChaosAscension / ChaosAscensionQuestCore, storages of ascension_quest_config.lua) and the passive
-- tree (passivetree.lua ChaosPassiveTree, Chaos.storage.passiveExtraPoints): view, fix and reset a character, as the
-- staff commands /trial and /ascendset do on yourself or a named character. Every action needs the character online
-- (the storages live with it).
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "chaos_class"; def.id = "chaos_class." .. def.id; ChaosAdminPending[def.id] = def end

local ONLINE = {name = "player", label = "Player (online)", type = "player"}

local function sys(name, fn) return ChaosAdmin.system(name, fn) end

local function vocOf(t)
	local v = t:getVocation()
	return v and v:getId() or 0, v and v:getName() or "?"
end

-- ------------------------------------------------------------------ Vocation Trials (server/README.md "Vocation Trials")
local function trialStore()
	return Chaos.trials and Chaos.trials.storage
end

local function trialLine(T, t)
	local voc, vname = vocOf(t)
	local st = trialStore()
	local held = ChaosTrialsCore.heldNodes(voc, T.tierCleared(t, voc), T.picks(t, voc))
	local names = {}
	for _, node in ipairs(held) do names[#names + 1] = node.name end
	local wait = math.max(0, t:getStorageValue(st.cooldown) - os.time())
	return string.format("%s (%s): tier %d cleared, %d Trial Tokens, %d node(s) held%s%s.", t:getName(), vname, T.tierCleared(t, voc),
		math.max(0, t:getStorageValue(st.tokens)), #held, #names > 0 and (": " .. table.concat(names, ", ")) or "",
		wait > 0 and string.format(", next attempt in %d min", math.ceil(wait / 60)) or "")
end

local function trialTarget(actor, p)
	local T, why = sys("ChaosTrials", "tierCleared")
	if not T or not ChaosTrialsCore or not trialStore() then return nil, nil, why or "trials.lua is not loaded." end
	local t, err = ChaosAdmin.targetOnline(actor, p.player)
	if not t then return nil, nil, err end
	return T, t
end

local function trialDone(T, t, text)
	pcall(T.refresh, t)
	pcall(T.sendState, t)
	return true, text .. " " .. trialLine(T, t)
end

reg{id = "trials_view", name = "Trials: view", description = "Tier cleared, tokens, held nodes and the cooldown of the character's current vocation (as /trial status).",
	params = {ONLINE},
	handler = function(actor, p)
		local T, t, err = trialTarget(actor, p)
		if not T then return false, err end
		return true, trialLine(T, t)
	end}

reg{id = "trials_cooldown", name = "Trials: clear cooldown", description = "The next attempt is allowed at once (a failed run's wait removed).",
	params = {ONLINE},
	handler = function(actor, p)
		local T, t, err = trialTarget(actor, p)
		if not T then return false, err end
		t:setStorageValue(trialStore().cooldown, 0)
		return trialDone(T, t, "Cooldown cleared.")
	end}

reg{id = "trials_tier", name = "Trials: set tier cleared", description = "Sets the highest tier cleared of the current vocation (as /trial clear).",
	minGroup = 5, params = {ONLINE, {name = "tier", label = "Tier (0-3)", type = "int", min = 0, max = 3}},
	handler = function(actor, p)
		local T, t, err = trialTarget(actor, p)
		if not T then return false, err end
		local voc = vocOf(t)
		t:setStorageValue(trialStore().tierBase + voc, math.min(p.tier, #(Chaos.trials.tiers or {})))
		return trialDone(T, t, "Tier set.")
	end}

reg{id = "trials_tokens", name = "Trials: set tokens", description = "Sets the Trial Tokens held (as /trial tokens).",
	minGroup = 5, params = {ONLINE, {name = "tokens", label = "Tokens", type = "int", min = 0, max = 100}},
	handler = function(actor, p)
		local T, t, err = trialTarget(actor, p)
		if not T then return false, err end
		t:setStorageValue(trialStore().tokens, p.tokens)
		return trialDone(T, t, "Tokens set.")
	end}

reg{id = "trials_reset", name = "Trials: reset vocation", description = "Clears the tier, the held nodes and the cooldown of the current vocation (as /trial reset).",
	dangerous = true, params = {ONLINE},
	handler = function(actor, p)
		local T, t, err = trialTarget(actor, p)
		if not T then return false, err end
		local st, voc = trialStore(), vocOf(t)
		t:setStorageValue(st.tierBase + voc, 0)
		t:setStorageValue(st.picksBase + voc, 0)
		t:setStorageValue(st.cooldown, 0)
		return trialDone(T, t, "Trials reset.")
	end}

-- ------------------------------------------------------------------ ascension (server/README.md "Ascension quest")
local STAGES = {[0] = "not begun", [1] = "Proof of Strength", [2] = "the Trial", [3] = "the Choice", [4] = "complete"}

local function ascTarget(actor, p)
	local Q = ChaosAscensionQuestCore
	if not Q or not Q.cfg then return nil, nil, "ascension_quest.lua is not loaded on this server." end
	local t, err = ChaosAdmin.targetOnline(actor, p.player)
	if not t then return nil, nil, err end
	return Q, t
end

local function ascLine(Q, t)
	local k = Q.cfg().storage
	local stage = Q.stage(t:getStorageValue(k.stage))
	local wait = math.max(0, t:getStorageValue(k.cooldown) - os.time())
	local _, vname = vocOf(t)
	return string.format("%s (%s): stage %d (%s), proof %d / %d%s.", t:getName(), vname, stage, STAGES[stage] or "?",
		math.max(0, t:getStorageValue(k.proof)), Q.cfg().proof.needed, wait > 0 and string.format(", Trial again in %d min", math.ceil(wait / 60)) or "")
end

reg{id = "ascension_view", name = "Ascension: view", description = "Quest stage, Proof of Strength points and the Trial cooldown.",
	params = {ONLINE},
	handler = function(actor, p)
		local Q, t, err = ascTarget(actor, p)
		if not Q then return false, err end
		return true, ascLine(Q, t)
	end}

reg{id = "ascension_cooldown", name = "Ascension: clear Trial cooldown", description = "The Trial may be tried again at once.",
	params = {ONLINE},
	handler = function(actor, p)
		local Q, t, err = ascTarget(actor, p)
		if not Q then return false, err end
		t:setStorageValue(Q.cfg().storage.cooldown, 0)
		return true, ascLine(Q, t)
	end}

reg{id = "ascension_stage", name = "Ascension: set stage", description = "Sets the quest stage (0 not begun, 1 Proof, 2 Trial, 3 Choice, 4 complete); with stage 2+ the proof counts as full.",
	minGroup = 5, params = {ONLINE, {name = "stage", label = "Stage (0-4)", type = "int", min = 0, max = 4}},
	handler = function(actor, p)
		local Q, t, err = ascTarget(actor, p)
		if not Q then return false, err end
		local k = Q.cfg().storage
		t:setStorageValue(k.stage, p.stage)
		if p.stage >= 2 then t:setStorageValue(k.proof, Q.cfg().proof.needed) end
		return true, ascLine(Q, t)
	end}

reg{id = "ascension_reset", name = "Ascension: reset quest", description = "Stage, proof and cooldown back to 0 (the vocation stays; change it with Ascension: set vocation).",
	dangerous = true, params = {ONLINE},
	handler = function(actor, p)
		local Q, t, err = ascTarget(actor, p)
		if not Q then return false, err end
		local k = Q.cfg().storage
		for _, key in ipairs({k.stage, k.proof, k.cooldown}) do t:setStorageValue(key, 0) end
		return true, ascLine(Q, t)
	end}

reg{id = "ascension_set", name = "Ascension: set vocation", description = "Sets the ascended vocation of the character's own line (as /ascendset; docs/CLASSES.md has the ids).",
	minGroup = 5, params = {ONLINE, {name = "vocation", label = "Vocation id", type = "int", min = 1, max = 255}},
	handler = function(actor, p)
		local Q, t, err = ascTarget(actor, p)
		if not Q then return false, err end
		local A, why = sys("ChaosAscension", "ascend")
		if not A then return false, why end
		if Q.baseOf(vocOf(t)) ~= Q.baseOf(p.vocation) then
			return false, t:getName() .. " is of another line (use the store's Vocation Change)."
		end
		local ok, text = A.ascend(t, nil, {staff = true, vocId = p.vocation, quiet = true})
		if not ok then return false, "Not changed: " .. tostring(text) end
		return true, ascLine(Q, t)
	end}

-- ------------------------------------------------------------------ passive tree (server/README.md "Passive tree points")
local function treeLine(P, t)
	local v = P.publicView(t)
	local extra = math.max(0, t:getStorageValue(Chaos.storage.passiveExtraPoints))
	local bosses = ChaosBossPoints and ChaosBossPoints.count and ChaosBossPoints.count(t) or 0
	return string.format("%s: %d points (%d extra, %d from bosses), %d node(s) allocated, class %s.", t:getName(), v.total or 0, extra,
		bosses, #(v.nodes or {}), tostring(v.cls))
end

local function treeTarget(actor, p)
	local P, why = sys("ChaosPassiveTree", "publicView")
	if not P then return nil, nil, why end
	local t, err = ChaosAdmin.targetOnline(actor, p.player)
	if not t then return nil, nil, err end
	return P, t
end

reg{id = "tree_view", name = "Passive tree: view", description = "Total points (level, extra, bosses) and the nodes allocated in the active preset.",
	params = {ONLINE},
	handler = function(actor, p)
		local P, t, err = treeTarget(actor, p)
		if not P then return false, err end
		return true, treeLine(P, t)
	end}

reg{id = "tree_points", name = "Passive tree: extra points", description = "Adds (or takes with a negative number) extra passive points (Chaos.storage.passiveExtraPoints; never below 0).",
	minGroup = 5, params = {ONLINE, {name = "points", label = "Points (+/-)", type = "int", min = -100, max = 100}},
	handler = function(actor, p)
		local P, t, err = treeTarget(actor, p)
		if not P then return false, err end
		local key = Chaos.storage.passiveExtraPoints
		t:setStorageValue(key, math.max(0, math.max(0, t:getStorageValue(key)) + p.points))
		if P.internal and P.internal.sendPoints then pcall(P.internal.sendPoints, t) end
		return true, treeLine(P, t)
	end}

reg{id = "tree_reset", name = "Passive tree: free reset", description = "Empties every preset of the character for free (ChaosPassiveTree.resetAll, the store respec path): every point comes back.",
	minGroup = 5, confirm = true, params = {ONLINE},
	handler = function(actor, p)
		local P, t, err = treeTarget(actor, p)
		if not P then return false, err end
		if not P.resetAll then return false, "ChaosPassiveTree.resetAll is not loaded." end
		P.resetAll(t)
		return true, "Reset. " .. treeLine(P, t)
	end}
