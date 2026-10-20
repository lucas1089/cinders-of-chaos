-- Weapon Proficiency catalogue: the rules without client API (tested by catalogcore_test.lua with luajit and lua5.3).
-- The base window (mods/game_proficiency) lists the weapons it is told about by the server's catalogue packet
-- (id, market category, proficiency id, name). The Chaos server sends none, so the window opened and showed nothing.
-- This builds the same list from the client's own item data: every item whose market category is a weapon one (or
-- whose weapon type is) and that has a name.
ProficiencyCatalogCore = {}
local C = ProficiencyCatalogCore

-- MarketCategory (gamelib/market.lua) of the weapons the window groups
C.CATEGORIES = { Axes = 17, Clubs = 18, DistanceWeapons = 19, Swords = 20, WandsRods = 21, FistWeapons = 27 }
C.WEAPON_CATEGORY = {}
for _, v in pairs(C.CATEGORIES) do C.WEAPON_CATEGORY[v] = true end

-- weapon type (gamelib const WEAPON_*) -> market category, for an item without market data
function C.categoryOfWeaponType(types, weaponType)
  if type(types) ~= 'table' or weaponType == nil then return nil end
  local map = {}
  local pairsOf = { sword = 'Swords', axe = 'Axes', club = 'Clubs', fist = 'FistWeapons', bow = 'DistanceWeapons',
    crossbow = 'DistanceWeapons', throw = 'DistanceWeapons', wand = 'WandsRods' }
  for key, category in pairs(pairsOf) do
    if types[key] ~= nil then map[types[key]] = C.CATEGORIES[category] end
  end
  return map[weaponType]
end

-- read(id) -> {category = market category or nil, weaponType = n or nil, name = text or nil} or nil (no such item).
-- Returns the list {{id, category, name}} in id order, and the number of ids looked at.
function C.collect(read, firstId, lastId, types)
  local out, seen = {}, 0
  for id = firstId, lastId do
    local info = read(id)
    if info then
      seen = seen + 1
      local category = info.category
      if not C.WEAPON_CATEGORY[category or -1] then
        category = C.categoryOfWeaponType(types, info.weaponType)
      end
      local name = type(info.name) == 'string' and info.name or ''
      if category and name ~= '' then
        out[#out + 1] = { id = id, category = category, name = name }
      end
    end
  end
  return out, seen
end
