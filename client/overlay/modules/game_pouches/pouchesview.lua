-- Store pouches window: the logic without client API (tested by pouchesview_test.lua).
-- The rules mirror the server's pouches_core.lua: list, gold, uniques, gear (+ minRarity), supplies, gems, other.

PouchesView = {}
local V = PouchesView

V.FLAGS = { 'list', 'gold', 'uniques', 'gear', 'supplies', 'gems', 'other' }
V.MAX_RARITY = 15

-- rules from the server (missing keys: off, minRarity clamped to 1..15)
function V.normalize(r)
  r = type(r) == 'table' and r or {}
  local out = {}
  for _, k in ipairs(V.FLAGS) do out[k] = r[k] == true end
  local m = math.floor(tonumber(r.minRarity) or 5)
  out.minRarity = math.max(1, math.min(V.MAX_RARITY, m))
  return out
end

-- the line under the title: whether this character has the Loot Pouch
function V.statusText(owned, title)
  title = title or 'Loot Pouch'
  if type(owned) ~= 'table' then return '' end
  if owned.loot then
    return 'You have a ' .. title .. '. It collects while you carry it (backpack or a bag inside it).'
  end
  return 'You have no ' .. title .. ' yet: Store > Convenience. These rules are kept for when you do.'
end

-- the right-click hook: the item looks like the Loot Pouch (client id from the server) and carries the item lock
-- flag the server sets on every store pouch (custom attribute key 3), so a stock bag of the same look does not match
function V.isLootPouch(clientId, lockFlag, ids)
  if type(ids) ~= 'table' or not ids.loot or ids.loot == 0 then return false end
  return clientId == ids.loot and (tonumber(lockFlag) or 0) ~= 0
end

-- the rarity combo: names 1..15 from the server, else numbers
function V.rarityOptions(names)
  local out = {}
  for i = 1, V.MAX_RARITY do
    out[i] = (type(names) == 'table' and names[i]) or ('Rarity ' .. i)
  end
  return out
end
