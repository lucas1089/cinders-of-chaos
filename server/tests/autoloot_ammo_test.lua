-- Run from the server/ folder: luajit tests/autoloot_ammo_test.lua (and lua5.3; CI runs both)
-- Autoloot list and ammunition (owner report 2026-10-17: "an item shows in the autoloot list but disappears when looting
-- from any monster, no gold gained"): arrows and bolts never reach a corpse (loot.lua step 0), so they cannot be added to the
-- list and an old entry is not shown. Everything else behaves as before.
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
local names = {[2400] = "dagger", [2543] = "bolt", [2545] = "arrow", [2160] = "crystal coin"}
ItemType = function(x)
	local id = tonumber(x)
	if not id then
		for k, v in pairs(names) do if v == x then id = k end end
	end
	return {getId = function() return names[id or 0] and id or 0 end, getName = function() return names[id] or "?" end,
		getClientId = function() return (id or 0) + 1 end}
end
ChaosArchery = {isAmmoId = function(id) return id == 2543 or id == 2545 end}
local handlers = {}
function CreatureEvent(name)
	return {name = name, type = function() end, register = function(self) handlers[name] = self end}
end
local sent = {}
Chaos.send = function(player, opcode, action, data) sent[#sent + 1] = {action = action, data = data} end
Chaos.decode = function(buffer) return buffer end
dofile("data/scripts/chaos/autoloot.lua")

local pl = {st = {}, cancels = {}}
function pl:getStorageValue(k) return self.st[k] or -1 end
function pl:setStorageValue(k, v) self.st[k] = v end
function pl:sendCancelMessage(t) self.cancels[#self.cancels + 1] = t end
function pl:isPremium() return true end
local base = Chaos.storage.autolootBase
local function send(action, name)
	handlers.ChaosAutolootExtended.onExtendedOpcode(pl, ChaosOpcodes.autoloot, {action = action, data = {name = name}})
	return sent[#sent].data
end

local data = send("add", "dagger")
check(data.currentSlot == 1 and pl.st[base + 1] == 2400, "a dagger is added")
data = send("add", "bolt")
check(data.currentSlot == 1 and (pl.st[base + 2] or -1) <= 0 and #pl.cancels > 0, "a bolt is refused")
check(pl.cancels[#pl.cancels]:find("no longer drops", 1, true) ~= nil, "with the reason: " .. tostring(pl.cancels[#pl.cancels]))
data = send("add", "arrow")
check(data.currentSlot == 1 and (pl.st[base + 2] or -1) <= 0, "an arrow is refused")
-- an old list that already holds ammunition: not shown, not counted
pl.st[base + 1], pl.st[base + 2], pl.st[base + 3] = 2545, 2400, 2543
data = send("open")
check(data.currentSlot == 1 and #data.itemsTable == 1 and data.itemsTable[1][2] == "dagger", "old ammunition entries are hidden")
data = send("add", "crystal coin")
check(data.currentSlot == 2, "another item is added after them")
check(pl.st[base + 1] == 2400 and pl.st[base + 2] == 2160 and pl.st[base + 3] == -1, "the rewrite drops the old ammunition entries")
data = send("remove", "dagger")
check(data.currentSlot == 1, "remove works")
-- without the archery library nothing is treated as ammunition
ChaosArchery = nil
data = send("add", "bolt")
check(data.currentSlot == 2, "no archery library: the old behaviour")

if failures > 0 then
	error(failures .. " of " .. count .. " checks failed")
end
print("autoloot_ammo_test: " .. count .. " checks OK")
