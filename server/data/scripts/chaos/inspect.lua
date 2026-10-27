-- Inspect Player (client game_playerinspect, extended opcode ChaosOpcodes.inspect = 240). Rules and limits are in
-- inspect_core.lua (ChaosInspect, tests/inspect_test.lua); see server/README.md "Inspect Player".
--
-- Protocol (JSON {action, data}):
--   client -> server  inspect {cid} | inspect {name}     cid: the creature the player right-clicked (same floor, within
--                                                         10 tiles, in view), name: typed in the window (any online player)
--                     privacy {}                          ask for the own setting
--                     privacy {allow = true | false}      set it ("Allow others to inspect me", default on)
--   server -> client  result {name, level, voc, vocId, ascended, guild = {name, rank}, ach, rift, trials, outfit, self, parts}
--                     equip {name, rows = [{slot, tip}], part}      parts packets follow `result`; slot 1-10 as the inventory,
--                                                                    tip = the rich tooltip of item_tooltip_core.lua; each
--                                                                    packet at most 8000 bytes (ChaosInspect.equipPackets),
--                                                                    through Chaos.sendChunked (a bigger single row in parts)
--                     tree {name, nodes, masteries = [{id, choice}], cls, line, vocation, spent}   the active passive
--                                                                    tree, read-only (ChaosInspect.treePayload), after the
--                                                                    equipment; through Chaos.sendChunked when it is large
--                     records {name, rows = [{key, name, value}]}   the personal records (O260: best drop, Tower floor,
--                                                                    rift tier, fastest boss kills), after the result
--                     denied {code, text}
--                     privacy {allow}
-- Hidden staff and players in ghost mode answer like a name that is not online.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua")
end
if not ChaosItemTooltip then
	dofile("data/scripts/chaos/item_tooltip_core.lua")
end
if not ChaosInspect then
	dofile("data/scripts/chaos/inspect_core.lua")
end

local I = ChaosInspect
local T = ChaosItemTooltip
local OPCODE = ChaosOpcodes.inspect or 240
local OFF = Chaos.storage.inspectOff
local budget = {} -- player id -> bucket

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function reply(player, action, data)
	Chaos.send(player, OPCODE, action, data)
end

local function deny(player, code, name)
	reply(player, "denied", {code = code, text = Chaos.tx(player, I.reasonText(code, name))})
end

local function pcallv(fn, ...)
	local ok, v = pcall(fn, ...)
	if ok then
		return v
	end
	return nil
end

-- the table I.allowed reads, from a viewer and a target player
local function describe(viewer, target)
	local t = {online = true, same = viewer:getId() == target:getId()}
	t.staff = (target:getAccountType() >= ACCOUNT_TYPE_GAMEMASTER) or (pcallv(function() return target:getGroup():getAccess() end) == true)
	t.ghost = target:isInGhostMode() == true
	t.off = target:getStorageValue(OFF) == 1
	local a, b = viewer:getPosition(), target:getPosition()
	t.sameFloor = a.z == b.z
	t.dx, t.dy = a.x - b.x, a.y - b.y
	t.visible = viewer:canSee(b) == true
	return t
end

local function guildOf(target)
	local guild = pcallv(function() return target:getGuild() end)
	if not guild then
		return nil
	end
	local rank = pcallv(function() return guild:getRankByLevel(target:getGuildLevel()) end)
	return {name = guild:getName(), rank = rank and rank.name or nil}
end

local function riftBest(target)
	local A = ChaosAchievements
	local stats = A and A.stats and A.stats[target:getGuid()]
	return stats and tonumber(stats.rift_tier) or 0
end

local function trialsTier(target)
	local tr = ChaosTrials
	if tr and tr.tierCleared then
		return tonumber(pcallv(tr.tierCleared, target)) or 0
	end
	return 0
end

local function achievementPoints(target)
	local A = ChaosAchievements
	if A and A.pointsOf then
		return tonumber((pcallv(A.pointsOf, target))) or 0
	end
	return 0
end

local function equipment(target)
	local equipped = {}
	for _, slot in ipairs(I.SLOTS) do
		local item = target:getSlotItem(slot)
		if item then
			equipped[item:getId()] = true
		end
	end
	local rows = {}
	for _, slot in ipairs(I.SLOTS) do
		local item = target:getSlotItem(slot)
		if item then
			local attrs
			if item.getClientAttributes then
				attrs = pcallv(item.getClientAttributes, item)
			end
			local ok, tip = pcall(T.build, item, {equippedIds = equipped, attrs = attrs})
			if ok then
				-- the display scale of the item's level requirement (display_scale_core.lua DS.itemTip)
				rows[#rows + 1] = {slot = slot, tip = (ChaosDisplayScale and ChaosDisplayScale.itemTip and ChaosDisplayScale.itemTip(tip) or tip)}
			else
				print("[inspect] " .. tostring(tip))
			end
		end
	end
	return rows
end

local function inspect(player, data)
	local pid = player:getId()
	budget[pid] = budget[pid] or {}
	if not I.allow(budget[pid], nowMs()) then
		return deny(player, "rate")
	end
	local how, target, typed = "name", nil, nil
	if data.cid ~= nil then
		how = "range"
		local cid = Chaos.toInt(data.cid, 1)
		target = cid and Player(cid) or nil
	else
		typed = I.cleanName(data.name)
		if not typed then
			return deny(player, "bad")
		end
		target = Player(typed)
	end
	local ok, code = I.allowed(target and describe(player, target) or nil, how)
	if not ok then
		return deny(player, code, target and target:getName() or typed)
	end
	local packets = I.equipPackets(target:getName(), equipment(target), json.encode)
	local voc = target:getVocation()
	local vocId = voc and voc:getId() or 0
	reply(player, "result", {
		name = target:getName(), level = target:getLevel(), voc = voc and voc:getName() or "", vocId = vocId,
		ascended = ChaosClasses and ChaosClasses.isAscended(vocId) or false, guild = guildOf(target),
		ach = achievementPoints(target), rift = riftBest(target), trials = trialsTier(target),
		outfit = I.outfitOf(target:getOutfit()), self = target:getId() == pid, parts = #packets,
		tree = ChaosPassiveTree ~= nil and ChaosPassiveTree.publicView ~= nil
	})
	-- the personal records (records.lua, O260), in the viewer's language
	if ChaosRecords and ChaosRecords.personalRows then
		local okRec, rows = pcall(ChaosRecords.personalRows, target:getGuid(), player)
		if okRec and type(rows) == "table" then
			reply(player, "records", {name = target:getName(), rows = rows})
		end
	end
	-- each packet fits one extended opcode message (I.config.packetBytes); a single row bigger than that goes in parts
	for _, packet in ipairs(packets) do
		Chaos.sendChunked(player, OPCODE, packet)
	end
	-- the passive tree (allocations, mastery effects, class and line), shown read-only by the client's tree window
	if ChaosPassiveTree and ChaosPassiveTree.publicView then
		local view = pcallv(ChaosPassiveTree.publicView, target)
		if view then
			Chaos.sendChunked(player, OPCODE, json.encode({action = "tree", data = I.treePayload(target:getName(), view)}))
		end
	end
end

local function privacy(player, data)
	if data.allow ~= nil then
		if not (ChaosRateLimit == nil or ChaosRateLimit.allow(player, "inspect.privacy", 500)) then
			return
		end
		player:setStorageValue(OFF, data.allow == true and -1 or 1)
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, data.allow == true and "Others can inspect you again." or
			"Others can no longer inspect you."))
	end
	reply(player, "privacy", {allow = player:getStorageValue(OFF) ~= 1})
end

local ext = CreatureEvent("ChaosInspectExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.data) ~= "table" then
		return
	end
	if msg.action == "inspect" then
		inspect(player, msg.data)
	elseif msg.action == "privacy" then
		privacy(player, msg.data)
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosInspectLogin")
function login.onLogin(player)
	player:registerEvent("ChaosInspectExtended")
	player:registerEvent("ChaosInspectLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosInspectLogout")
function logout.onLogout(player)
	budget[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

return I
