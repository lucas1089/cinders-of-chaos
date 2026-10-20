-- Store pouches window: the logic without client API (tested by pouchesview_test.lua).
-- The rules mirror the server's pouches_core.lua: list, gold, uniques, gear (+ minRarity), supplies, gems, other,
-- overflow (take what a full Orbs / Rift Key Pouch passes on; on when the server does not say).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

PouchesView = {}
local V = PouchesView

V.FLAGS = { 'list', 'gold', 'uniques', 'gear', 'supplies', 'gems', 'other', 'overflow' }
V.DEFAULT_ON = { overflow = true }
V.MAX_RARITY = 15 -- the highest id a saved rule can hold; the seven rarities are the ids 1 2 3 4 5 10 (V.RARITY_IDS)
V.RARITY_IDS = { 1, 2, 3, 4, 5, 10 } -- Common, Uncommon, Magic, Rare, Legendary, Divine (server data/lib/chaos_rarity.lua)

-- the id of today's rarity an id stands for: 6 .. 9 -> 5 (Legendary), 10 .. 15 -> 10 (Divine); at least 1
function V.canonRarity(id)
  id = math.floor(tonumber(id) or 1)
  if id <= 1 then return 1 end
  if id <= 5 then return id end
  if id <= 9 then return 5 end
  return 10
end

-- rules from the server (missing keys: off, overflow on; minRarity an id of the seven rarities, an old 6 .. 15 mapped)
function V.normalize(r)
  r = type(r) == 'table' and r or {}
  local out = {}
  for _, k in ipairs(V.FLAGS) do
    if r[k] == nil and V.DEFAULT_ON[k] then out[k] = true else out[k] = r[k] == true end
  end
  out.minRarity = V.canonRarity(tonumber(r.minRarity) or 5)
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

-- the window's height so nothing overlaps (live test winpkg-35: the Loot Bag note was cut off and "Saved on your
-- character at once." ran under the buttons). m = {top, contentBottom (the last of the rules, the note or Open Store),
-- savedHeight, buttonHeight, paddingBottom, minHeight}; the gaps: 10 above the saved line, 8 under it.
V.SAVED_GAP, V.BUTTON_GAP = 10, 8
function V.fitHeight(m)
  local need = (m.contentBottom - m.top) + V.SAVED_GAP + (m.savedHeight or 0) + V.BUTTON_GAP + (m.buttonHeight or 0) +
    (m.paddingBottom or 0)
  return math.max(m.minHeight or 0, math.ceil(need))
end

-- the right-click hook: the item looks like the Loot Bag (client id from the server) and carries the item lock
-- flag the server sets on every store pouch (custom attribute key 3), so a stock bag of the same look does not match
function V.isLootPouch(clientId, lockFlag, ids)
  if type(ids) ~= 'table' or not ids.loot or ids.loot == 0 then return false end
  return clientId == ids.loot and (tonumber(lockFlag) or 0) ~= 0
end

-- the rarity combo: the names in order from the server (Common .. Divine), else the built-in ones; the id of each is
-- V.RARITY_IDS[i]
V.RARITY_NAMES = { 'Common', 'Uncommon', 'Magic', 'Rare', 'Legendary', 'Divine' }
function V.rarityOptions(names)
  local out = {}
  for i = 1, #V.RARITY_IDS do
    out[i] = tr((type(names) == 'table' and names[i]) or V.RARITY_NAMES[i])
  end
  return out
end

-- the combo position (1..6) of a rule's minRarity
function V.rarityIndex(minRarity)
  local c = V.canonRarity(minRarity)
  for i, id in ipairs(V.RARITY_IDS) do
    if id == c then return i end
  end
  return 1
end
