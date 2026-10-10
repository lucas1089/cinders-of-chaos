-- Season modes (Self-Found, Hardcore): pure rules, no engine calls. Used by season_modes.lua and
-- server/tests/season_modes_test.lua. Numbers and texts: season_config.lua `modes`.
--   modes      byKey(mc, key), pick(mc, key), keyOf(ssf, hc), flags(row, realm), choices(mc)
--   isolation  tradeAllowed(a, b), partyAllowed(a, b), transferAllowed(a, b), marketAllowed(f, action),
--              orbAllowed(f, action), moveCheck(m), ownerTagAction(info)
--   rewards    lootBonus(f, mc), achievementStats(f, level), survivedStats(f)
--   death      deathCause(k), deathPlan(f)
--   protection protection(st, now, hc), trackLoss(st, lost, connected, now, hc), restartGuard(now, r)
--   ladders    ladderTabs(mc), ladderClause(mode, alias), memberMatches(mode, f), lookLine(f, pronoun)
-- A "flags" table f = {key, ssf, hc, fallen, exempt}: the mode a character plays right now. Only an unmigrated
-- character of the running season (realm > 0) plays a mode; everyone else is {key = "standard"}.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosSeasonModes = ChaosSeasonModes or {}
local M = ChaosSeasonModes

-- ---------------------------------------------------------------- modes
function M.byKey(mc, key)
	for _, d in ipairs(mc and mc.list or {}) do
		if d.key == key then
			return d
		end
	end
	return nil
end

-- the mode asked for at the join: nil (an older client) = standard; an unknown key = nil, reason
function M.pick(mc, key)
	if key == nil or key == "" then
		return M.byKey(mc, "standard")
	end
	local d = M.byKey(mc, tostring(key))
	if not d then
		return nil, "Unknown season mode."
	end
	return d
end

function M.keyOf(ssf, hc)
	if ssf and hc then
		return "hcssf"
	elseif ssf then
		return "ssf"
	elseif hc then
		return "hc"
	end
	return "standard"
end

local STANDARD = {key = "standard", ssf = false, hc = false, fallen = false}

-- row = {ssf, hc, fallen (unix or 0), reset (unix or 0)} (chaos_season_modes) or nil; realm of the character now
function M.flags(row, realm)
	if not row then
		return STANDARD
	end
	local fallen = (tonumber(row.fallen) or 0) > 0
	if (tonumber(realm) or 0) == 0 or fallen or (tonumber(row.reset) or 0) > 0 then
		return {key = "standard", ssf = false, hc = false, fallen = fallen}
	end
	local ssf, hc = (tonumber(row.ssf) or 0) > 0, (tonumber(row.hc) or 0) > 0
	return {key = M.keyOf(ssf, hc), ssf = ssf, hc = hc, fallen = false}
end

-- what the join confirmation offers: {key, name, short, ssf, hc, warning}
function M.choices(mc)
	local out = {}
	for _, d in ipairs(mc and mc.list or {}) do
		out[#out + 1] = {key = d.key, name = d.name, short = d.short or d.name, ssf = d.ssf and true or false,
			hc = d.hc and true or false, warning = d.warning or ""}
	end
	return out
end

-- ---------------------------------------------------------------- isolation (on top of the realm rules)
-- a, b = flags (+ exempt = staff). A Self-Found character trades with nobody.
function M.tradeAllowed(a, b)
	if a.exempt or b.exempt then
		return true
	end
	if a.ssf or b.ssf then
		return false, "trade"
	end
	return true
end

-- Self-Found characters party only with Self-Found characters (Hardcore or not); the realm rule stays
function M.partyAllowed(a, b)
	if a.exempt or b.exempt then
		return true
	end
	if (a.ssf and true or false) ~= (b.ssf and true or false) then
		return false, "party"
	end
	return true
end

-- gold transfers (Chaos bank, NPC bank): never from or to a Self-Found character
function M.transferAllowed(a, b)
	if a.exempt then
		return true
	end
	if a.ssf or b.ssf then
		return false, "bank"
	end
	return true
end

local MARKET_BLOCKED = {list = true, buy = true, orderPost = true, fill = true}

-- the market (market.lua actions): a Self-Found character neither buys nor sells (cancel / collect stay open)
function M.marketAllowed(f, action)
	if f.exempt or not f.ssf then
		return true
	end
	if MARKET_BLOCKED[action] then
		return false, "market"
	end
	return true
end

-- the Orb Exchange (orbexchange.lua): no new orders
function M.orbAllowed(f, action)
	if f.exempt or not f.ssf then
		return true
	end
	if action == "place" then
		return false, "orbs"
	end
	return true
end

local function anyOther(list, guid)
	for _, g in ipairs(list or {}) do
		if g ~= guid then
			return g
		end
	end
	return nil
end

-- One item move. m = {mover = guid, ssf = bool, exempt = bool,
--   from = {owner guids of the item and the containers around it}, to = {owner guids of the destination containers},
--   isSsf = function(guid) -> bool (is that character Self-Found now),
--   houseFrom / houseTo = owner guid of the house the item lies in / goes to (nil = none),
--   mail = true when it goes into a mailbox, mailTo = guid of the receiver (nil = unknown)}
-- -> true or false, reason key (cfg.modes.messages)
function M.moveCheck(m)
	if m.exempt then
		return true
	end
	local me = m.mover
	local isSsf = m.isSsf or function() return false end
	if m.ssf then
		if m.mail then
			return false, "mail"
		end
		if anyOther(m.from, me) then
			return false, "loot"
		end
		if anyOther(m.to, me) then
			return false, "give"
		end
		if (m.houseFrom and m.houseFrom ~= me) or (m.houseTo and m.houseTo ~= me) then
			return false, "house"
		end
		return true
	end
	-- a standard / Hardcore character: nothing of a Self-Found character comes to it, nothing goes to one
	if m.mail and m.mailTo and m.mailTo ~= me and isSsf(m.mailTo) then
		return false, "mailTo"
	end
	for _, g in ipairs(m.from or {}) do
		if g ~= me and isSsf(g) then
			return false, "item"
		end
	end
	for _, g in ipairs(m.to or {}) do
		if g ~= me and isSsf(g) then
			return false, "item"
		end
	end
	for _, g in ipairs({m.houseFrom or false, m.houseTo or false}) do
		if g and g ~= me and isSsf(g) then
			return false, "house"
		end
	end
	return true
end

-- what happens to the owner tag of an item after an allowed move.
-- info = {inventory = it is now in the mover's inventory, depot = it is now in a depot / inbox, tag = current owner
-- tag (nil = none), mover = guid}. -> "clear" (it is the mover's now), "set" (it lies in the world: the mover's), nil
function M.ownerTagAction(info)
	if info.inventory then
		return info.tag ~= nil and "clear" or nil
	end
	if info.depot then
		return nil
	end
	if info.tag == nil then
		return "set"
	end
	return nil -- a tagged item keeps its first owner: moving someone's item around does not make it yours
end

-- ---------------------------------------------------------------- rewards
-- percent bonuses for loot.lua (Item Find: more extra loot rolls / chances; Rarity Find: better gear rarity)
function M.lootBonus(f, mc)
	if not f.ssf then
		return 0, 0
	end
	local s = mc and mc.ssf or {}
	return tonumber(s.itemFind) or 0, tonumber(s.rarityFind) or 0
end

-- achievement stats (achievements_data.lua) of a character playing a mode at this level
function M.achievementStats(f, level)
	local out = {}
	if f.hc then
		out.season_hc_level = level
	end
	if f.ssf then
		out.season_ssf_level = level
	end
	return out
end

-- stats of a character still playing its mode when its season ends (alive for Hardcore)
function M.survivedStats(f)
	local out = {}
	if f.hc and not f.fallen then
		out.season_hc_survived = 1
	end
	if f.ssf and not f.fallen then
		out.season_ssf_finished = 1
	end
	return out
end

-- ---------------------------------------------------------------- death
-- k = {name = killer name or nil, player = bool} -> the short death cause kept for the ladder
function M.deathCause(k)
	k = k or {}
	local name = tostring(k.name or "")
	if name == "" then
		return "died"
	end
	if k.player then
		return "slain by " .. name
	end
	return ("killed by " .. name):sub(1, 60)
end

-- a real death of a character playing this mode -> {fallen = true} for Hardcore, nil otherwise. Every real death counts,
-- also one a protection could not stop (a script that kills outside the damage path): nothing is pretended
function M.deathPlan(f)
	if f.hc and not f.fallen then
		return {fallen = true}
	end
	return nil
end

-- ---------------------------------------------------------------- Hardcore protections
-- st = {loginAt, connected (a client is attached), beatSeen (the client sent a heartbeat since the login),
--       lastBeat, lostAt (when the loss started, nil = no loss), pulled (already pulled to the temple),
--       budgetOut (no ping-loss protection left this hour), gameState ("normal" | other), guard (restart guard)}
-- hc = cfg.modes.hc -> {protected = bool, reason = "restart" | "login" | "disconnect" | "pingloss" | nil, pull = bool}
function M.protection(st, now, hc)
	if st.gameState and st.gameState ~= "normal" then
		return {protected = true, reason = "restart", pull = false}
	end
	if st.guard then
		return {protected = true, reason = "restart", pull = false}
	end
	local lost, reason = M.lost(st, now, hc)
	if lost then
		if reason == "pingloss" and st.budgetOut then
			lost = false
		else
			local since = st.lostAt or now
			return {protected = true, reason = reason, pull = not st.pulled and now - since >= (hc.pullSeconds or 10)}
		end
	end
	if st.loginAt and now - st.loginAt < (hc.loginSeconds or 0) then
		return {protected = true, reason = "login", pull = false}
	end
	return {protected = false, pull = false}
end

-- is the client gone (no connection) or silent (no heartbeat for pingLossSeconds)? -> bool, reason
function M.lost(st, now, hc)
	if not st.connected then
		return true, "disconnect"
	end
	if st.beatSeen and st.lastBeat and now - st.lastBeat > (hc.pingLossSeconds or 6) then
		return true, "pingloss"
	end
	return false
end

-- the loss state after one check: st.lostAt / st.pulled / st.losses (os.time of each ping loss this hour).
-- lost = M.lost(...) now. Returns st.
function M.trackLoss(st, lost, reason, now, hc)
	if lost then
		if not st.lostAt then
			st.lostAt = now
			st.pulled = false
			if reason == "pingloss" then
				local keep = {}
				for _, t in ipairs(st.losses or {}) do
					if now - t < 3600 then
						keep[#keep + 1] = t
					end
				end
				st.budgetOut = #keep >= (hc.pingLossPerHour or 3)
				keep[#keep + 1] = now
				st.losses = keep
			end
		end
	else
		st.lostAt, st.pulled, st.budgetOut = nil, false, false
	end
	return st
end

-- the scheduled restart (the base server's daily server save): r = {hour, min, notifyMinutes, guardSeconds}.
-- The server shuts down notifyMinutes after hour:min. True from guardSeconds before that until a minute after.
function M.restartGuard(now, r)
	if not r or not r.hour then
		return false
	end
	local t = os.date("*t", now)
	local at = os.time({year = t.year, month = t.month, day = t.day, hour = r.hour, min = r.min or 0, sec = 0}) +
		(r.notifyMinutes or 0) * 60
	for _, shutdown in ipairs({at - 86400, at, at + 86400}) do
		if now >= shutdown - (r.guardSeconds or 0) and now <= shutdown + 60 then
			return true
		end
	end
	return false
end

-- "HH:MM:SS" | "HH:MM" -> hour, min (nil when invalid)
function M.parseTime(text)
	local h, m = tostring(text or ""):match("^%s*(%d%d?):(%d%d)")
	h, m = tonumber(h), tonumber(m)
	if not h or h > 23 or m > 59 then
		return nil
	end
	return h, m
end

-- ---------------------------------------------------------------- ladders
-- the mode tabs of the season ladder: "all" (every season character), one per mode, "fallen"
function M.ladderTabs(mc)
	local out = {{key = "all", name = "All"}}
	for _, d in ipairs(mc and mc.list or {}) do
		out[#out + 1] = {key = d.key, name = d.short or d.name}
	end
	out[#out + 1] = {key = "fallen", name = "Fallen"}
	return out
end

-- SQL condition on the chaos_season_modes row (LEFT JOINed as `alias`, may be NULL) for a ladder tab; nil = no tab.
-- Hardcore tabs list living characters only; "fallen" lists the fallen ones (they are migrated: the caller drops
-- its `migrated_at = 0` condition for that tab).
function M.ladderClause(mode, alias)
	local a = alias or "sm"
	local c = {
		all = "1 = 1",
		standard = string.format("(%s.`player_id` IS NULL OR (%s.`ssf` = 0 AND %s.`hc` = 0))", a, a, a),
		ssf = string.format("%s.`ssf` = 1 AND %s.`hc` = 0", a, a),
		hc = string.format("%s.`hc` = 1 AND %s.`ssf` = 0 AND %s.`fallen_at` = 0", a, a, a),
		hcssf = string.format("%s.`hc` = 1 AND %s.`ssf` = 1 AND %s.`fallen_at` = 0", a, a, a),
		fallen = string.format("%s.`fallen_at` > 0", a)
	}
	return c[mode]
end

-- the weekly boards in a mode tab: does a character with these flags (+ fallen) belong to it?
function M.memberMatches(mode, f)
	if mode == nil or mode == "all" then
		return not f.fallen
	end
	if mode == "fallen" then
		return f.fallen and true or false
	end
	return not f.fallen and f.key == mode
end

local LOOK = {ssf = "Self-Found", hc = "Hardcore", hcssf = "Hardcore Self-Found"}

-- look text: the mode played, or the fall (fallen = {level, cause}); nil for standard
function M.lookLine(f, pronoun, fallen)
	pronoun = pronoun or "He"
	local verb = pronoun == "You" and "are" or "is"
	if fallen then
		return string.format("%s fell in Hardcore at level %d (%s).", pronoun, tonumber(fallen.level) or 0,
			tostring(fallen.cause or "died"))
	end
	local name = LOOK[f.key]
	if not name then
		return nil
	end
	return string.format("%s %s playing %s.", pronoun, verb, name)
end

return M
