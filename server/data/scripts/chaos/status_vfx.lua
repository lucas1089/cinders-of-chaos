-- Status layer, the engine glue (O597; the rules are data/lib/chaos_status_vfx.lua; server/README.md "Status layer
-- (O597)"). Extended opcode ChaosOpcodes.statusVfx (165), JSON {action, data}:
--   client -> server  hello {on = 1 | 0}   "tell me the statuses near me" / "stop" (the client's option; sent at login)
--   server -> client  cfg {on, e, ms}      the answer to hello: e = the effect ids, flat {start, loop, stop} per status
--                                          in bit order; on = 0 when the server's pair is older than 73 (nothing follows)
--                     s {l = {creature id, mask, ...}}   what changed since the last message (mask 0 = nothing any more)
-- Only a player whose client said hello gets messages, so an older client and the Unity client get none.
-- Every S.scanMs the creatures within S.viewX x S.viewY of each watcher are read once (conditions and marks) and each
-- watcher gets its changes, at most S.maxPairs pairs a message. No watcher: the scan does nothing.
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosStatusVfx then
	dofile("data/lib/chaos_status_vfx.lua")
end

local S = ChaosStatusVfx
local OPCODE = (ChaosOpcodes and ChaosOpcodes.statusVfx) or S.OPCODE

local watchers = {}   -- player id -> known {creature id -> mask}
local watching = 0
local rows
local scans = 0

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function unwatch(id)
	if watchers[id] then
		watchers[id] = nil
		watching = math.max(0, watching - 1)
	end
end

local function maskOf(creature, id, now)
	local isPlayer = creature:isPlayer()
	local m = S.conditionMask(rows, isPlayer, function(ctype, cid)
		if cid then
			return creature:getCondition(ctype, cid) ~= nil
		end
		return creature:hasCondition(ctype)
	end)
	local marks = S.markMask(id, now)
	if marks ~= 0 then
		for _, name in ipairs(S.namesOf(marks)) do
			if not S.hasBit(m, S.bits[name]) then
				m = m + S.bits[name]
			end
		end
	end
	return S.cutBrief(id, m, now)
end

local function scanOnce()
	local now = nowMs()
	rows = rows or S.resolve(_G)
	local cache = {}
	for pid, known in pairs(watchers) do
		local player = Player(pid)
		if not player then
			unwatch(pid)
		else
			local visible = {}
			local list = Game.getSpectators(player:getPosition(), false, false, S.viewX, S.viewX, S.viewY, S.viewY)
			for _, c in ipairs(list) do
				local id = c:getId()
				local m = cache[id]
				if m == nil then
					local ok, v = pcall(maskOf, c, id, now)
					m = ok and v or 0
					cache[id] = m
				end
				if m ~= 0 then
					visible[id] = m
				end
			end
			local changed = S.changes(known, visible)
			if #changed > 0 then
				for _, part in ipairs(S.batches(changed)) do
					Chaos.send(player, OPCODE, "s", {l = part})
				end
			end
		end
	end
	scans = scans + 1
	if scans % 20 == 0 then
		S.pruneMarks(now)
	end
end

local think = GlobalEvent("ChaosStatusVfxScan")
function think.onThink(interval)
	if watching > 0 and S.live() then
		local ok, err = pcall(scanOnce)
		if not ok then
			print("[ChaosStatusVfx] scan: " .. tostring(err))
		end
	elseif S.markCount > 0 then
		S.pruneMarks(nowMs())
	end
	return true
end
think:interval(S.scanMs)
think:register()

local login = CreatureEvent("ChaosStatusVfxLogin")
function login.onLogin(player)
	player:registerEvent("ChaosStatusVfxExtended")
	player:registerEvent("ChaosStatusVfxLogout")
	unwatch(player:getId())
	return true
end
login:register()

local logout = CreatureEvent("ChaosStatusVfxLogout")
function logout.onLogout(player)
	unwatch(player:getId())
	S.forget(player:getId())
	return true
end
logout:register()

local ext = CreatureEvent("ChaosStatusVfxExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "hello" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "statusvfx.hello", 100) then
		return
	end
	local id = player:getId()
	local want = type(msg.data) == "table" and msg.data.on == 1
	unwatch(id)
	if want and S.live() then
		watchers[id] = {}
		watching = watching + 1
	end
	Chaos.send(player, OPCODE, "cfg", S.hello())
end
ext:type("extendedopcode")
ext:register()
