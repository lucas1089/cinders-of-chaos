-- Small world events, one at a time at random moments every few hours (settings: invasion_config.lua worldEvents):
--   Chaos Storm         15 minutes: magic / rare / legendary spawns in one area x tierMult (monster_tiers.lua asks
--                       ChaosWorldEvents.tierMult(position) in its spawn roll), lightning around the players there
--   Wandering Merchant  resident since O399 (merchant.resident): always in one town area, moving every moveHours (3)
--                       to the next one; an NPC (data/npc/Wandering Merchant.xml) at a random free spot selling orbs and
--                       rare consumables, one of each per character and stop (the list is in the config); the area is
--                       announced, not the spot. Not one of the random world events while resident.
--   Golden Hour         30 minutes: +25% Chaos loot in one area (loot_config.lua rateMult asks ChaosWorldEvents.lootMult)
-- Each shows in !events / the login lines while it runs (ChaosEvents.dynamic) and in the client's upcoming-events
-- window. Never in the area of a running invasion; no event starts within quietMinutes of an invasion.
-- Staff: /invasion event <storm|merchant|golden|stop> [area]. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosInvasionCore or not ChaosInvasionCore.pickWorldEvent then
	dofile("data/scripts/chaos/invasion_core.lua")
end
Chaos.invasionConfig = Chaos.invasionConfig or dofile("data/scripts/chaos/invasion_config.lua")

ChaosWorldEvents = ChaosWorldEvents or {}
local W = ChaosWorldEvents
local I = ChaosInvasionCore

W.active = W.active or nil -- {kind, area, endsAt, token, npcId}
W.merchant = W.merchant or nil -- the resident merchant: {slot, area, endsAt, npcId, npcPos}
W.token = W.token or 0

local function cfg()
	return ChaosInvasion and ChaosInvasion.cfg and ChaosInvasion.cfg() or Chaos.invasionConfig
end
local function we()
	return cfg().worldEvents or {}
end

local function announce(text)
	if ChaosInvasion and ChaosInvasion.announce then
		ChaosInvasion.announce(text)
	else
		Chaos.broadcast(MESSAGE_EVENT_ADVANCE, text)
	end
end

local function activeIn(kind, pos)
	local a = W.active
	if not a or a.kind ~= kind or os.time() >= a.endsAt then
		return false
	end
	return I.inArea(pos, a.area)
end

-- hooks for monster_tiers.lua and loot_config.lua (guarded calls there)
function W.tierMult(position)
	if position and activeIn("storm", position) then
		return (we().storm or {}).tierMult or 3
	end
	return 1
end

function W.lootMult(ctx)
	local m = ctx and ctx.monster
	if not m then
		return 1
	end
	local ok, pos = pcall(function() return m:getPosition() end)
	if ok and pos and activeIn("golden", pos) then
		return (we().golden or {}).lootMult or 1.25
	end
	return 1
end

local function setCalendar(entry)
	if ChaosEvents and ChaosEvents.dynamic then
		ChaosEvents.dynamic.worldEvent = entry
	end
end

local function describe(kind, area, endsAt)
	local e = we()[kind] or {}
	local until_ = os.date("%H:%M", endsAt)
	if kind == "storm" then
		return ChaosI18n.msg("A Chaos Storm rages over %s until %s: magic, rare and legendary monsters appear %s times as often there.",
			area.name, until_, tostring(e.tierMult or 3))
	elseif kind == "golden" then
		return ChaosI18n.msg("Golden Hour in %s until %s: +%d%% loot from every monster there.", area.name, until_,
			math.floor(((e.lootMult or 1.25) - 1) * 100 + 0.5))
	end
	return ChaosI18n.msg("A Wandering Merchant has set up shop somewhere in %s until %s: orbs and rare goods at a good price. Find him!",
		area.name, until_)
end

-- a random free spot for the merchant: the area's merchantSpots, else a walkable tile of the area
local function merchantSpot(area)
	local tileOk = ChaosInvasion and ChaosInvasion.tileOk
	for _, s in ipairs(area.merchantSpots or {}) do
		local p = Position(s.x, s.y, s.z or area.z or 7)
		if not tileOk or tileOk(p, area) then
			return p
		end
	end
	for _ = 1, 400 do
		local p = Position(math.random(area.from.x + 2, area.to.x - 2), math.random(area.from.y + 2, area.to.y - 2), area.z or 7)
		if tileOk and tileOk(p, area) then
			return p
		end
	end
	return nil
end

local function stormFx(token)
	local a = W.active
	if not a or a.token ~= token or a.kind ~= "storm" then
		return
	end
	for _, p in ipairs(Game.getPlayers()) do
		local pos = p:getPosition()
		if I.inArea(pos, a.area) then
			for k = 1, 3 do
				local fx = Position(pos.x + math.random(-6, 6), pos.y + math.random(-5, 5), pos.z)
				fx:sendMagicEffect(k == 1 and CONST_ME_BIGCLOUDS or (k == 2 and CONST_ME_PURPLEENERGY or CONST_ME_ENERGYHIT))
			end
		end
	end
	addEvent(stormFx, ((we().storm or {}).effectSeconds or 3) * 1000, token)
end

local function goldenFx(token)
	local a = W.active
	if not a or a.token ~= token or a.kind ~= "golden" then
		return
	end
	for _, p in ipairs(Game.getPlayers()) do
		local pos = p:getPosition()
		if I.inArea(pos, a.area) then
			Position(pos.x + math.random(-5, 5), pos.y + math.random(-4, 4), pos.z):sendMagicEffect(CONST_ME_YELLOW_RINGS)
		end
	end
	addEvent(goldenFx, 5000, token)
end

function W.stop(quiet)
	local a = W.active
	if not a then
		return false
	end
	W.active = nil
	if a.npcId then
		local npc = Npc(a.npcId)
		if npc then
			npc:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			npc:remove()
		end
	end
	setCalendar(nil)
	if not quiet then
		local e = we()[a.kind] or {}
		announce(ChaosI18n.msg("The %s in %s is over.", e.name or a.kind, a.area.name))
	end
	return true
end

local function busyArea(key)
	return ChaosInvasion and ChaosInvasion.state and ChaosInvasion.state.phase ~= "idle" and ChaosInvasion.state.areaKey == key
end

-- ----------------------------------------------------------------- the resident Wandering Merchant (O399)
local function merchantCfg()
	local e = we().merchant
	return e and e.resident and e.enabled ~= false and e or nil
end

local function merchantAreas(c, e)
	local list = {}
	for _, a in ipairs(I.worldEventAreas(c, "merchant")) do
		local kindOk = not e.kinds
		for _, k in ipairs(e.kinds or {}) do
			if k == a.kind then
				kindOk = true
			end
		end
		if kindOk then
			list[#list + 1] = a
		end
	end
	return list
end

local function removeMerchant()
	local m = W.merchant
	W.merchant = nil
	if ChaosEvents and ChaosEvents.dynamic then
		ChaosEvents.dynamic.wanderingMerchant = nil
	end
	if m and m.npcId then
		local npc = Npc(m.npcId)
		if npc then
			npc:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			npc:remove()
		end
	end
end

-- put the merchant at this stop's area (areaKey: a staff choice; avoidKey: an area an invasion takes); returns ok, text
function W.placeMerchant(areaKey, avoidKey, quiet)
	local e = merchantCfg()
	if not e then
		return false, "the merchant is not resident (worldEvents.merchant.resident)"
	end
	local c = cfg()
	local slot, endsAt = I.merchantSlot(os.time(), e.moveHours)
	local list = merchantAreas(c, e)
	local area
	if areaKey then
		area = I.areaByKey(c, areaKey)
	else
		area = I.merchantArea(list, slot)
		for i = 1, #list do
			if area and not busyArea(area.key) and area.key ~= avoidKey then
				break
			end
			area = list[((slot + i) % #list) + 1]
		end
		if area and (busyArea(area.key) or area.key == avoidKey) then
			area = nil
		end
	end
	removeMerchant()
	if not area then
		return false, "no area for the merchant"
	end
	local pos = merchantSpot(area)
	local npc = pos and Game.createNpc(e.npc or "Wandering Merchant", pos, false, true)
	if not npc then
		return false, "the merchant NPC could not be placed (data/npc/Wandering Merchant.xml installed?)"
	end
	pos:sendMagicEffect(CONST_ME_TELEPORT)
	W.merchant = {slot = slot, area = area, endsAt = endsAt, npcId = npc:getId(), npcPos = {x = pos.x, y = pos.y, z = pos.z}}
	local text = ChaosI18n.msg("The Wandering Merchant has set up shop somewhere in %s until %s: orbs and rare goods, one of each per customer. Find him!",
		area.name, os.date("%H:%M", endsAt))
	if ChaosEvents and ChaosEvents.dynamic then
		ChaosEvents.dynamic.wanderingMerchant = {id = "wanderingMerchant", name = e.name or "Wandering Merchant",
			description = tostring(text), untilTime = endsAt}
	end
	if not quiet then
		announce(text)
	end
	return true, string.format("%s in %s at %d,%d,%d until %s", e.name or "Wandering Merchant", area.name, pos.x, pos.y,
		pos.z, os.date("%H:%M", endsAt))
end

-- stop the running event if it is in that area (an invasion starts there); the merchant moves on
function W.stopIn(areaKey)
	if W.active and W.active.area.key == areaKey then
		W.stop(false)
	end
	if W.merchant and W.merchant.area.key == areaKey then
		W.placeMerchant(nil, areaKey, false)
	end
end

-- start kind (nil = by weight) in areaKey (nil = random allowed area); returns ok, text
function W.start(kind, areaKey)
	if kind == "stop" then
		return W.stop(false), "stopped"
	end
	local c = cfg()
	local w = c.worldEvents or {}
	if kind and not w[kind] then
		return false, "unknown event (storm, merchant, golden)"
	end
	if kind == "merchant" and merchantCfg() then
		return W.placeMerchant(areaKey, nil, false) -- staff: move the resident merchant now
	end
	kind = kind or I.pickWorldEvent(w, W.lastKind, math.random)
	if not kind then
		return false, "no world event enabled"
	end
	local candidates = {}
	for _, a in ipairs(I.worldEventAreas(c, kind)) do
		local kindOk = true
		if w[kind].kinds then
			kindOk = false
			for _, k in ipairs(w[kind].kinds) do
				if k == a.kind then
					kindOk = true
				end
			end
		end
		if kindOk and not busyArea(a.key) and (not areaKey or a.key == areaKey) then
			candidates[#candidates + 1] = a
		end
	end
	if areaKey and #candidates == 0 then
		local a = I.areaByKey(c, areaKey)
		if a and not busyArea(a.key) then
			candidates = {a}
		end
	end
	if #candidates == 0 then
		return false, "no area for " .. kind
	end
	local area = candidates[math.random(#candidates)]
	W.stop(true)
	W.token = W.token + 1
	local e = w[kind]
	local endsAt = os.time() + (e.minutes or 15) * 60
	W.active = {kind = kind, area = area, endsAt = endsAt, token = W.token}
	W.lastKind = kind
	if kind == "merchant" then
		local pos = merchantSpot(area)
		local npc = pos and Game.createNpc(e.npc or "Wandering Merchant", pos, false, true)
		if not npc then
			W.active = nil
			return false, "the merchant NPC could not be placed (data/npc/Wandering Merchant.xml installed?)"
		end
		W.active.npcId = npc:getId()
		W.active.npcPos = {x = pos.x, y = pos.y, z = pos.z}
		pos:sendMagicEffect(CONST_ME_TELEPORT)
	elseif kind == "storm" then
		addEvent(stormFx, 500, W.token)
	elseif kind == "golden" then
		addEvent(goldenFx, 500, W.token)
	end
	local text = describe(kind, area, endsAt)
	setCalendar({id = "worldEvent", name = e.name or kind, description = tostring(text), untilTime = endsAt})
	announce(text)
	local where = W.active.npcPos and string.format(" at %d,%d,%d", W.active.npcPos.x, W.active.npcPos.y, W.active.npcPos.z) or ""
	return true, (e.name or kind) .. " in " .. area.name .. where -- the spot only for the staff reply
end

-- the running event for the client window
function W.calendar(t)
	local list = {}
	local a = W.active
	if a and t < a.endsAt then
		local e = we()[a.kind] or {}
		list[#list + 1] = {kind = a.kind, at = a.endsAt, inSeconds = 0, when = "until " .. os.date("%H:%M", a.endsAt),
			name = (e.name or a.kind) .. " in " .. a.area.name}
	elseif W.nextAt and W.nextAt > t then
		list[#list + 1] = {kind = "world", at = W.nextAt, inSeconds = W.nextAt - t, when = "around " .. os.date("%H:%M", W.nextAt),
			name = merchantCfg() and "A world event (Chaos Storm or Golden Hour)" or "A world event (Chaos Storm, Wandering Merchant or Golden Hour)"}
	end
	local m = W.merchant
	if m and t < m.endsAt then
		local e = we().merchant or {}
		list[#list + 1] = {kind = "merchant", at = m.endsAt, inSeconds = 0, when = "until " .. os.date("%H:%M", m.endsAt),
			name = (e.name or "Wandering Merchant") .. " in " .. m.area.name}
	end
	return list
end

local function planNext(from)
	local c = cfg()
	local upcoming = I.upcoming(c, from, 8 * 3600)
	W.nextAt = I.nextWorldEventAt(c.worldEvents or {}, from, math.random, upcoming)
end

local think = GlobalEvent("ChaosWorldEvents")
function think.onThink(interval)
	local t = os.time()
	local w = we()
	-- the resident merchant: a new stop when the clock passes the end of this one (or the NPC is gone)
	if merchantCfg() and (not W.merchantRetryAt or t >= W.merchantRetryAt) then
		local m = W.merchant
		if not m or t >= m.endsAt or not Npc(m.npcId) then
			local ok, err = W.placeMerchant(nil, nil, false)
			if not ok then
				print("[Chaos world events] merchant not placed: " .. tostring(err))
				W.merchantRetryAt = t + 300
			else
				W.merchantRetryAt = nil
			end
		end
	end
	if W.active and t >= W.active.endsAt then
		W.stop(false)
		planNext(t)
	end
	if not w.enabled or W.active then
		return true
	end
	if not W.nextAt then
		local first = w.firstMinutes or {20, 60}
		W.nextAt = t + math.random(first[1], math.max(first[1], first[2])) * 60
	end
	if t >= W.nextAt then
		if ChaosInvasion and ChaosInvasion.state and ChaosInvasion.state.phase == "running" then
			W.nextAt = t + 10 * 60 -- not during an invasion
			return true
		end
		local ok, err = W.start(nil, nil)
		if not ok then
			print("[Chaos world events] not started: " .. tostring(err))
			planNext(t)
		end
	end
	return true
end
think:interval(20000)
think:register()
