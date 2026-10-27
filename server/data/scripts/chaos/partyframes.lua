-- Party frames (client game_partyframes, extended opcode ChaosOpcodes.partyFrames = 235)
--
-- Every cfg.tickMs (500 ms) each watching character that is in a party is sent the state of that party: the members'
-- health, mana, level, vocation, outfit, floor and distance, in fight / dead / connection lost, and their first few
-- buffs and debuffs (data/lib/chaos_buffs.lua). The rules (who sees which numbers, the action checks) are in
-- partyframes_core.lua (tests/partyframes_test.lua): exact numbers only for members in range, a rough health bar for far
-- ones, nothing about anyone outside the party. Only characters whose client opened the frames are sent anything, and an
-- unchanged state is repeated only every cfg.heartbeatMs.
--
-- Protocol (JSON {action, data}):
--   client -> server  open {buffs = true|false} | close | kick {id} | lead {id} | invite {name}
--   server -> client  state {leader = id, members = [entry]} (members empty: no party), message {text}
--   entry: see partyframes_core.lua
-- The party itself is the engine's (shields, shared experience, invitations stay as they are); the actions here are the
-- same ones the engine offers (pass the leadership, invite) plus the removal of a member by the leader. Selecting,
-- following and looking are client calls on the creature, not part of this protocol.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosPartyFrames or not ChaosPartyFrames.state then
	dofile("data/scripts/chaos/partyframes_core.lua")
end
if not ChaosBuffs then
	pcall(dofile, "data/lib/chaos_buffs.lua")
end

local P = ChaosPartyFrames
local OPCODE = ChaosOpcodes.partyFrames or 235
P.watch = P.watch or {} -- player id -> {buffs = bool, sig = text, sentAt = ms, hadParty = bool}

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function send(player, action, data)
	-- the viewer's display scale (display_scale_core.lua): the members' health and mana
	if action == "state" and ChaosDisplayScale and ChaosDisplayScale.apply then
		data = ChaosDisplayScale.apply("partyState", player, data)
	end
	Chaos.send(player, OPCODE, action, data)
end

local function note(player, text)
	text = Chaos.tx(player, text) -- the core's refusals are English texts
	send(player, "message", {text = text})
	player:sendTextMessage(MESSAGE_STATUS_SMALL, text)
end

-- the plain data of one character (what partyframes_core.lua works on)
local function plain(player, withBuffs, now)
	local pos = player:getPosition()
	local o = player:getOutfit()
	local voc = player:getVocation()
	-- the class line (base vocation) the party's shared experience bonus counts (party_xp_core.lua)
	local okBase, base = pcall(function() return voc:getBase():getId() end)
	local m = {id = player:getId(), name = player:getName(), level = player:getLevel(), voc = voc and voc:getId() or 0,
		line = okBase and tonumber(base) or 0,
		hp = player:getHealth(), hpMax = player:getMaxHealth(), mp = player:getMana(), mpMax = player:getMaxMana(),
		x = pos.x, y = pos.y, z = pos.z, fight = player:hasCondition(CONDITION_INFIGHT), offline = player:getIp() == 0,
		outfit = {t = o.lookType, h = o.lookHead, b = o.lookBody, l = o.lookLegs, f = o.lookFeet, a = o.lookAddons}}
	if withBuffs and ChaosBuffs then
		local ok, items = pcall(ChaosBuffs.get, player, now, 900)
		if ok and items then
			m.buffs = ChaosBuffs.brief(items)
		end
	end
	return m
end

-- within one tick every character is read once, whoever of the party asks (a party of N watchers would read N x N)
local tickCache
local function plainCached(player, withBuffs, now)
	if not tickCache then
		return plain(player, withBuffs, now)
	end
	local key = player:getId() * 2 + (withBuffs and 1 or 0)
	local m = tickCache[key]
	if not m then
		m = plain(player, withBuffs, now)
		tickCache[key] = m
	end
	return m
end

-- the members of a party, the leader first: {Player...}
local function membersOf(party)
	local list = {party:getLeader()}
	for _, member in ipairs(party:getMembers()) do
		list[#list + 1] = member
	end
	return list
end

function P.sendState(player, w, now, force)
	local party = player:getParty()
	if not party then
		if w.hadParty or force then
			w.hadParty, w.sig = false, nil
			send(player, "state", {members = {}})
		end
		return
	end
	local leader = party:getLeader()
	if not leader then
		return
	end
	local list = {}
	for _, member in ipairs(membersOf(party)) do
		list[#list + 1] = plainCached(member, w.buffs, now)
	end
	local state = P.state(plainCached(player, false, now), list, leader:getId())
	-- the shared experience bonus in the title of the frames ("+20% XP", party_xp_core.lua; O261)
	local okA, active = pcall(function() return party:isSharedExperienceActive() end)
	local okE, enabled = pcall(function() return party:isSharedExperienceEnabled() end)
	P.withShare(state, list, okA and active or false, okE and enabled or false)
	local sig = P.signature(state)
	w.hadParty = true
	if not force and sig == w.sig and now - (w.sentAt or 0) < P.cfg.heartbeatMs then
		return
	end
	w.sig, w.sentAt = sig, now
	send(player, "state", state)
end

local think = GlobalEvent("ChaosPartyFramesThink")
function think.onThink(interval)
	local now = nowMs()
	tickCache = {}
	for _, player in ipairs(Game.getPlayers()) do
		local w = P.watch[player:getId()]
		if w then
			local ok, err = pcall(P.sendState, player, w, now, false)
			if not ok then
				print("[Chaos party frames] " .. tostring(err))
			end
		end
	end
	tickCache = nil
	return true
end
think:interval(P.cfg.tickMs)
think:register()

local login = CreatureEvent("ChaosPartyFramesLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPartyFramesExtended")
	player:registerEvent("ChaosPartyFramesLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosPartyFramesLogout")
function logout.onLogout(player)
	P.watch[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

-- ---------------------------------------------------------------- actions
local function idSet(party)
	local set = {}
	for _, member in ipairs(membersOf(party)) do
		set[member:getId()] = true
	end
	return set
end

local function sameParty(party, other)
	local op = other:getParty()
	return op ~= nil and op == party
end

local function kick(player, id)
	local party = player:getParty()
	if not party then
		return
	end
	local ok, why = P.canKick(player:getId(), party:getLeader():getId(), id, idSet(party))
	if not ok then
		return note(player, why)
	end
	local target = Player(id)
	if not target or not sameParty(party, target) then
		return note(player, Chaos.t(player, "That player is not in your party."))
	end
	party:removeMember(target)
	note(player, Chaos.t(player, "%s was removed from the party.", target:getName()))
	target:sendTextMessage(MESSAGE_STATUS_WARNING, Chaos.t(target, "You were removed from the party by %s.", player:getName()))
end

local function lead(player, id)
	local party = player:getParty()
	if not party then
		return
	end
	local ok, why = P.canPassLeadership(player:getId(), party:getLeader():getId(), id, idSet(party))
	if not ok then
		return note(player, why)
	end
	local target = Player(id)
	if not target or not sameParty(party, target) then
		return note(player, Chaos.t(player, "That player is not in your party."))
	end
	party:setLeader(target)
end

local function invite(player, name)
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "party.invite", P.cfg.inviteMs) then
		return
	end
	local party = player:getParty()
	local info
	if party then
		info = {leaderId = party:getLeader():getId(), members = #membersOf(party), invited = {}}
		for _, p in ipairs(party:getInvitees()) do
			info.invited[p:getId()] = true
		end
	end
	local target = type(name) == "string" and Player(name) or nil
	local t = target and {id = target:getId(), name = target:getName(), isSelf = target == player, inParty = target:getParty() ~= nil,
		hidden = target ~= player and not player:canSeeCreature(target)}
	local ok, why = P.canInvite(player:getId(), info, name, t, P.cfg.maxMembers)
	if not ok then
		return note(player, why)
	end
	if not party then
		party = Party(player)
		if not party then
			return note(player, Chaos.t(player, "You cannot start a party now."))
		end
	end
	if party:addInvite(target) then
		note(player, Chaos.t(player, "%s was invited to your party.", target:getName()))
	else
		note(player, Chaos.t(player, "%s cannot be invited now.", target:getName()))
	end
end

local ext = CreatureEvent("ChaosPartyFramesExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local id = player:getId()
	local action, data = msg.action, type(msg.data) == "table" and msg.data or {}
	if action == "open" then
		local w = {buffs = data.buffs ~= false, hadParty = false}
		P.watch[id] = w
		P.sendState(player, w, nowMs(), true)
	elseif action == "close" then
		P.watch[id] = nil
	elseif action == "kick" or action == "lead" or action == "invite" then
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "party.act", P.cfg.actionMs) then
			return
		end
		if action == "kick" then
			local target = Chaos.toInt(data.id, 1)
			if target then
				kick(player, target)
			end
		elseif action == "lead" then
			local target = Chaos.toInt(data.id, 1)
			if target then
				lead(player, target)
			end
		else
			invite(player, data.name)
		end
	end
end
ext:type("extendedopcode")
ext:register()
