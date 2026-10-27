-- Item lock in the game's item right-click menu: the logic without client API (tested by lockmenu_test.lua with LuaJIT and
-- Lua 5.3). The menu shows "Lock item" / "Unlock item" for an item of the player's own inventory slots or open containers
-- that the lock can apply to. The client cannot know "gear" exactly (the server decides: salvage.lua lockAt), so it
-- offers the entry for a non-stackable, non-container item that has a rarity, is unique, is already locked or is a Rift Key;
-- the server checks everything again and answers with a text message.
CraftingLockMenu = CraftingLockMenu or {}
local L = CraftingLockMenu

L.INVENTORY_X = 0xFFFF
L.SLOTS = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true,
  [13] = true }

-- the position of an item the lock applies to: an inventory slot or an open container (0x40 + id), never the map
function L.ownPosition(pos)
  if type(pos) ~= 'table' or tonumber(pos.x) ~= L.INVENTORY_X then return nil end
  local y, z = tonumber(pos.y), tonumber(pos.z) or 0
  if not y then return nil end
  if L.SLOTS[y] then return { x = L.INVENTORY_X, y = y, z = 0 } end
  if y >= 0x40 and y < 0x50 and z >= 0 and z <= 255 then return { x = L.INVENTORY_X, y = y, z = z } end
  return nil
end

-- info = {pos, stackable, container, rarity, unique, locked, name}
function L.applies(info)
  if type(info) ~= 'table' or not L.ownPosition(info.pos) then return false end
  if info.stackable or info.container then return false end
  if info.locked then return true end
  if (tonumber(info.rarity) or 0) > 0 or info.unique then return true end
  return type(info.name) == 'string' and info.name:lower():find('rift key', 1, true) ~= nil
end

-- wantLocked: true = the "Unlock item" entry (the item is locked), false = the "Lock item" entry
function L.show(info, wantLocked)
  return L.applies(info) and (info.locked and true or false) == wantLocked
end

-- the extended-opcode data of salvage.lua lockAt
function L.request(info, clientId, on)
  local pos = L.ownPosition(info and info.pos)
  if not pos or not tonumber(clientId) then return nil end
  return { pos = pos, cid = tonumber(clientId), on = on and true or false }
end

return L
