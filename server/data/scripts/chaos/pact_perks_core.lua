-- Chaos Pact (VIP) perks: pure rules (no engine calls), shared by pact_perks.lua and server/tests/pact_perks_test.lua.
--   ChaosPactPerksCore.month(t)                       YYYYMM of a unix time (server local time)
--   ChaosPactPerksCore.plan(perks, s)                 what to change for one character now:
--       s = {active, chatOwned, monthlyOwned = {[key] = true}, month, storages = {[unlockName] = value}}
--       -> {grant = {keys}, revoke = {keys}, setStorage = {{unlock, value}}}
--   ChaosPactPerksCore.loadoutBonus(perks, active)    loadout slots added while the Pact is active
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. server/README.md "Chaos Pact and account storage", VIP perks.
ChaosPactPerksCore = ChaosPactPerksCore or {}
local K = ChaosPactPerksCore

function K.month(t)
	local d = os.date("*t", t)
	return d.year * 100 + d.month
end

function K.loadoutBonus(perks, active)
	return (active and perks and tonumber(perks.loadoutSlots)) or 0
end

function K.plan(perks, s)
	local out = {grant = {}, revoke = {}, setStorage = {}}
	if type(perks) ~= "table" then
		return out
	end
	local pv = perks.pactStorageValue or 2
	-- the chat colour: only while active
	if perks.chatColor then
		if s.active and not s.chatOwned then
			out.grant[#out.grant + 1] = perks.chatColor
		elseif not s.active and s.chatOwned then
			out.revoke[#out.revoke + 1] = perks.chatColor
		end
	end
	-- the cosmetic of this month: granted while active, kept for good
	local monthly = s.active and perks.monthly and perks.monthly[s.month]
	if monthly and not (s.monthlyOwned or {})[monthly] then
		out.grant[#out.grant + 1] = monthly
	end
	-- the unlocks: a bought one (1) is never touched; the Pact's (pv) comes and goes
	for _, name in ipairs(perks.unlocks or {}) do
		local v = (s.storages or {})[name] or -1
		if s.active and v < 1 then
			out.setStorage[#out.setStorage + 1] = {name, pv}
		elseif not s.active and v == pv then
			out.setStorage[#out.setStorage + 1] = {name, -1}
		end
	end
	return out
end
