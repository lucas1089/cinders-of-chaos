-- Party shared experience: tells the party leader why it is off (party_xp_core.lua has the engine's rules and the
-- explanation; server/README.md "Party shared experience"). An EventCallback onGainExperience at index 2000 (after every
-- bonus; it never changes the experience): for a monster kill, a member of a party whose leader switched sharing on but
-- the engine has it off is diagnosed, and the leader is told at most once per two minutes per party and reason. No
-- timer and no scan: it runs only when such a member gains experience from a monster.
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosPartyXpCore then
	dofile("data/scripts/chaos/party_xp_core.lua")
end
local K = ChaosPartyXpCore
ChaosPartyXp = ChaosPartyXp or {}
local X = ChaosPartyXp
X.last = X.last or {}
X.sweptAt = X.sweptAt or 0

local function memberFacts(p)
	local pos = p:getPosition()
	return {
		name = p:getName(), level = p:getLevel(), pos = {x = pos.x, y = pos.y, z = pos.z},
		-- in fight: the stock "infight" condition lasts after an attack, a hit taken or a heal of an ally
		fighting = p:getCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT) ~= nil
	}
end

function X.facts(party)
	local leader = party:getLeader()
	if not leader then
		return nil
	end
	local facts = {active = party:isSharedExperienceActive(), enabled = party:isSharedExperienceEnabled(),
		leader = memberFacts(leader), members = {}, leaderPlayer = leader}
	for _, m in ipairs(party:getMembers()) do
		facts.members[#facts.members + 1] = memberFacts(m)
	end
	return facts
end

function X.check(player, now)
	local party = player:getParty()
	if not party then
		return nil
	end
	-- cheap exits first: a working share needs nothing
	if party:isSharedExperienceEnabled() then
		return nil
	end
	local facts = X.facts(party)
	if not facts then
		return nil
	end
	local diag = K.diagnose(facts)
	local lines = K.lines(diag)
	if not lines then
		return nil
	end
	local leader = facts.leaderPlayer
	if not K.due(X.last, leader:getId(), diag.reason, now) then
		return nil
	end
	if now - X.sweptAt > 600 then
		X.sweptAt = now
		K.sweep(X.last, now, 3600)
	end
	local out = K.lines(diag, function(key, ...) return Chaos.t(leader, key, ...) end)
	for _, text in ipairs(out) do
		leader:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_INFO_DESCR, text)
	end
	return diag
end

local cb = EventCallback
cb.onGainExperience = function(player, source, exp, rawExp)
	if source and source.isMonster and source:isMonster() and (tonumber(exp) or 0) > 0 then
		local ok, err = pcall(X.check, player, os.time())
		if not ok then
			print("[Chaos party xp] " .. tostring(err))
		end
	end
	return exp
end
cb:register(2000)
