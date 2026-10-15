-- Store pouches window: the logic without client API (tested by pouchesview_test.lua).
-- The rules mirror the server's pouches_core.lua: list, gold, uniques, gear (+ minRarity), supplies, gems, other,
-- overflow (take what a full Orbs / Rift Key Pouch passes on; on when the server does not say).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

PouchesView = {}
local V = PouchesView

V.FLAGS = { 'list', 'gold', 'uniques', 'gear', 'supplies', 'gems', 'other', 'overflow' }
V.DEFAULT_ON = { overflow = true }
V.MAX_RARITY = 15

-- rules from the server (missing keys: off, overflow on; minRarity clamped to 1..15)
function V.normalize(r)
  r = type(r) == 'table' and r or {}
  local out = {}
  for _, k in ipairs(V.FLAGS) do
    if r[k] == nil and V.DEFAULT_ON[k] then out[k] = true else out[k] = r[k] == true end
  end
  local m = math.floor(tonumber(r.minRarity) or 5)
  out.minRarity = math.max(1, math.min(V.MAX_RARITY, m))
  return out
end

-- the line under the title: whether this character has the Loot Bag
function V.statusText(owned, title)
  title = title or tr('Loot Bag')
  if type(owned) ~= 'table' then return '' end
  if owned.loot then
    return tr('You have a %s. It collects while you carry it (backpack or a bag inside it).', title)
  end
  return tr('You have no %s yet: Store > Convenience. These rules are kept for when you do.', title)
end

-- the right-click hook: the item looks like the Loot Bag (client id from the server) and carries the item lock
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
