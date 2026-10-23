-- Live spectator for the admin app (server/README.md "Live spectator", docs/ADMIN_APP.md "Assistir jogador").
-- remote_cmd.lua runs the line "spectate NAME" (queued by chaos-ctl.sh spectate NAME) by calling ChaosSpectate.watch;
-- while the watch lasts (watchSeconds after the newest line) this writes, every intervalMs, a snapshot of what NAME
-- sees to remote.spectate in the server folder (JSON, through a .tmp file and a rename). chaos-ctl.sh hands it to
-- server/tools/spectate_render.py, which draws it with the client's sprites for the app. Read only: no packet is sent
-- and nothing in the game changes; the player is not told. Pure part: spectate_core.lua; numbers: spectate_config.lua.
-- Assumed engine API (TFS 1.4.2): GlobalEvent onThink with interval, Player(name), Tile(x, y, z), tile:getGround,
-- getTopItemCount, getDownItemCount, getCreatureCount, getThing, getCreatures, ItemType(id):getClientId,
-- isStackable, isFluidContainer, item:getId, getSubType, creature getters (outfit, direction, health, skull), json.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosSpectateCore then
	dofile("data/scripts/chaos/spectate_core.lua")
end
if not ChaosRemoteCmdCore then
	dofile("data/scripts/chaos/remote_cmd_core.lua")
end

Chaos.spectateConfig = dofile("data/scripts/chaos/spectate_config.lua")
local cfg = Chaos.spectateConfig
local K = ChaosSpectateCore
ChaosSpectate = ChaosSpectate or {}
local S = ChaosSpectate
S.fs = S.fs or ChaosRemoteCmdCore.realFs()
S.state = S.state or {}

local function fileName()
	return ChaosRemoteCmdCore.bareName(cfg.file, "remote.spectate")
end

local function clientIdOf(serverId)
	local it = ItemType(serverId)
	return it and K.call(it, "getClientId") or 0
end

S.api = S.api or {
	tile = function(x, y, z)
		return Tile(x, y, z)
	end,
	-- a client id, or {client id, count or fluid} for the items whose sprite depends on it
	item = function(item)
		local id = K.call(item, "getId")
		if not id then
			return nil
		end
		local it = ItemType(id)
		local cid = K.int(it and K.call(it, "getClientId"), 0)
		if cid <= 0 then
			return nil
		end
		if K.call(it, "isStackable") or K.call(it, "isFluidContainer") or K.call(it, "isSplash") then
			return {cid, K.int(K.call(item, "getSubType"), 0)}
		end
		return cid
	end,
	clientId = clientIdOf
}

-- one snapshot of the watched player (or "offline"); false when there is no watch
function S.tick(now)
	now = now or os.time()
	local name = K.active(S.state, now)
	if not name then
		return false
	end
	local p = Player(name)
	local snap
	if p then
		snap = K.snapshot(S.api, p, name, now, cfg)
	else
		snap = K.offline(name, now)
	end
	local ok, text = pcall(json.encode, snap)
	if not ok then
		print("[ChaosSpectate] cannot encode the snapshot of " .. name .. ": " .. tostring(text))
		return false
	end
	return K.writeAtomic(S.fs, fileName(), text)
end

-- the "spectate NAME" line: starts or renews the watch and writes a snapshot at once. Returns true for a new watch
-- (remote_cmd.lua logs only those, not the renewals every 5 s).
function S.watch(name, now)
	if not K.isName(name) then
		return false
	end
	now = now or os.time()
	local fresh = K.watch(S.state, name, now, cfg)
	S.tick(now)
	return fresh
end

if cfg.enabled ~= false then
	local poll = GlobalEvent("ChaosSpectate")
	function poll.onThink(interval)
		S.tick()
		return true
	end
	poll:interval(cfg.intervalMs or 1000)
	poll:register()
end
