-- Party shared experience: why it is off. Pure logic (no engine calls), shared by party_xp.lua and tests/party_xp_test.lua.
--
-- The engine's rule (party.cpp, stock; no Chaos engine patch touches it): the leader switches "shared experience" on,
-- and it then WORKS only while EVERY member (the leader included) passes all of these at once; one member failing one
-- of them switches it off for the whole party, and the only sign is the party shield icon:
--   * the party has at least 2 members;
--   * level range: nobody below ceil(2/3 x the highest level in the party);
--   * range: within 30 tiles and 1 floor of the leader;
--   * active: attacked a monster or healed a party member in the last pzLocked seconds (a buff, a shield or an aura does
--     not count, so a pure support that only buffs keeps the share off for everyone).
-- party_xp.lua tells the leader which of these it is (owner report 2026-10-17 "Exp share nao parece estar funcionando":
-- the share was silently off). ChaosPartyXpCore.diagnose(facts) names the members and the rule.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosPartyXpCore = ChaosPartyXpCore or {}
local K = ChaosPartyXpCore

K.RANGE = 30 -- tiles (x and y), EXPERIENCE_SHARE_RANGE
K.FLOORS = 1 -- EXPERIENCE_SHARE_FLOORS
K.LEVEL_NUM, K.LEVEL_DEN = 2, 3
K.NOTICE_SECONDS = 120 -- one notice per party and reason at most this often
K.OFF_NOTICE_SECONDS = 1800 -- "switched off by the leader" is only a hint: rarer

-- lowest level that may share, given the highest in the party (float math as the engine: ceil(highest * 2 / 3))
function K.minLevel(highest)
	return math.ceil((highest * K.LEVEL_NUM) / K.LEVEL_DEN)
end

-- tiles in range of the leader (same floor +- FLOORS, both axes within RANGE)
function K.inRange(a, b)
	if not a or not b then
		return false
	end
	return math.abs(a.x - b.x) <= K.RANGE and math.abs(a.y - b.y) <= K.RANGE and math.abs(a.z - b.z) <= K.FLOORS
end

-- facts = {active = leader switched sharing on, enabled = the engine says it is working,
--          leader = member, members = {member...}}
-- member = {name, level, pos = {x, y, z}, fighting = in fight (attacked / was attacked / healed lately)}
-- -> {ok = bool, reason = "ok"|"off"|"working"|"alone"|"problems", problems = {{name, kind}}}
-- kind: "level" | "range" | "idle". A working share (enabled) is never diagnosed.
function K.diagnose(facts)
	local out = {ok = false, problems = {}}
	if type(facts) ~= "table" or type(facts.leader) ~= "table" then
		out.reason = "alone"
		return out
	end
	if facts.enabled then
		out.ok, out.reason = true, "working"
		return out
	end
	local members = facts.members or {}
	if #members < 1 then
		out.reason = "alone"
		return out
	end
	if not facts.active then
		out.reason = "off"
		return out
	end
	local all = {facts.leader}
	for _, m in ipairs(members) do
		all[#all + 1] = m
	end
	local highest = 0
	for _, m in ipairs(all) do
		highest = math.max(highest, tonumber(m.level) or 0)
	end
	local minLevel = K.minLevel(highest)
	for _, m in ipairs(all) do
		if (tonumber(m.level) or 0) < minLevel then
			out.problems[#out.problems + 1] = {name = m.name, kind = "level", need = minLevel}
		end
		if m ~= facts.leader and not K.inRange(facts.leader.pos, m.pos) then
			out.problems[#out.problems + 1] = {name = m.name, kind = "range"}
		end
		if not m.fighting then
			out.problems[#out.problems + 1] = {name = m.name, kind = "idle"}
		end
	end
	out.reason = "problems"
	return out
end

-- the chat line for a diagnosis (English keys; Chaos.t translates them), or nil when there is nothing to say
-- t(key, ...) is the translator (identity format by default)
function K.lines(diag, t)
	t = t or function(key, ...) return select("#", ...) > 0 and string.format(key, ...) or key end
	if diag.reason == "off" then
		return {t("Shared experience is off. The party leader can turn it on from the party shield menu.")}
	end
	if diag.reason ~= "problems" then
		return nil
	end
	local lines = {}
	for _, p in ipairs(diag.problems) do
		if p.kind == "level" then
			lines[#lines + 1] = t("%s is below level %d (the party shares only within two thirds of its highest level)", p.name, p.need)
		elseif p.kind == "range" then
			lines[#lines + 1] = t("%s is too far from the leader (30 tiles, 1 floor)", p.name)
		else
			lines[#lines + 1] = t("%s has not attacked a monster or healed a member lately (buffs do not count)", p.name)
		end
	end
	if #lines == 0 then
		return nil
	end
	return {t("Shared experience is not working: every member must pass these at once."), table.concat(lines, "; ") .. "."}
end

-- one notice per party and reason every NOTICE_SECONDS (OFF_NOTICE_SECONDS for "off"); state = {[key] = last time}
function K.due(state, key, reason, now)
	local gap = reason == "off" and K.OFF_NOTICE_SECONDS or K.NOTICE_SECONDS
	local k = tostring(key) .. ":" .. tostring(reason)
	local last = state[k]
	if last and now - last < gap then
		return false
	end
	state[k] = now
	return true
end

-- drops entries older than `keep` seconds so the table cannot grow
function K.sweep(state, now, keep)
	for k, at in pairs(state) do
		if now - at > (keep or 3600) then
			state[k] = nil
		end
	end
end

-- ---------------------------------------------------------------- the bonus the party frames show (O261)
-- The shared experience is `exp x bonus / members` (the stock Party:onShareExperience, with the class lines counted by
-- tools/patch_base_classes.py): bonus 1.2 for one class line, else 1 + n(5(n-1)+10)/100 for n lines, at most 5 lines
-- (x2.5). The party frames show the part above what each member would get alone, in percent: "+20% XP".
K.MAX_LINES = 5

-- the bonus in percent for n distinct class lines in the party (0 for no line at all)
function K.bonusPercent(lines)
	lines = math.floor(tonumber(lines) or 0)
	if lines ~= lines or lines < 1 then
		return 0
	end
	if lines == 1 then
		return 20
	end
	local n = math.min(lines, K.MAX_LINES)
	return n * (5 * (n - 1) + 10)
end

-- distinct class lines of a list of members ({line = base vocation id}); a member without a line (0, nil) adds none
function K.lineCount(members)
	local seen, n = {}, 0
	for _, m in ipairs(members or {}) do
		local id = tonumber(m.line) or 0
		if id > 0 and not seen[id] then
			seen[id] = true
			n = n + 1
		end
	end
	return n
end

-- {pct, on}: on 1 = the share works now, 2 = the leader switched it on but it is off (see K.diagnose), 0 = not switched on
function K.shareView(members, active, enabled)
	local on = enabled and 1 or (active and 2 or 0)
	return {pct = K.bonusPercent(K.lineCount(members)), on = on}
end
