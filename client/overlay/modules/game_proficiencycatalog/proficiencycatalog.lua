-- Weapon Proficiency catalogue (owner 2026-10-17: "Proficiencia da arma abre mas nao mostra nada").
-- Cause: the base window (mods/game_proficiency) fills its weapon list only from the server's catalogue packet
-- (g_game.onWeaponProficiencyCatalogItem / ...Ready, answering the request it sends when it opens). The Chaos server has
-- no proficiency system and sends none, so the list stayed empty. Here, when the window is about to open and no
-- catalogue has come, the weapons are read from the client's own item data (catalogcore.lua) and handed to the window
-- through the same two functions the packet calls. The window then lists the weapons with their perk trees (the perk
-- data is the client's proficiencies.json); experience stays 0 and a perk choice is not kept, since the server has
-- nothing to keep it (a server that answers the request still works: its catalogue and info replace these).
-- The scan runs once per game start (a few thousand item types) and only when the window is opened.

local C = ProficiencyCatalogCore
local originalOpen
local fed = false

local function proficiency()
  return modules.game_proficiency
end

local function readItem(id)
  local ok, thing = pcall(g_things.getThingType, id, ThingCategoryItem)
  if not ok or not thing then return nil end
  local info = {}
  local okM, market = pcall(function() return thing:getMarketData() end)
  if okM and type(market) == 'table' then
    info.category, info.name = tonumber(market.category), market.name
  end
  local okW, weaponType = pcall(function() return thing:getWeaponType() end)
  if okW then info.weaponType = tonumber(weaponType) end
  return info
end

local function weaponTypes()
  return { sword = WEAPON_SWORD, axe = WEAPON_AXE, club = WEAPON_CLUB, fist = WEAPON_FIST, bow = WEAPON_BOW,
    crossbow = WEAPON_CROSSBOW, throw = WEAPON_THROW, wand = WEAPON_WANDROD }
end

local function lastItemId()
  local ok, list = pcall(g_things.getThingTypes, ThingCategoryItem)
  local n = ok and type(list) == 'table' and #list or 0
  return n > 100 and n or 40000
end

local function feed()
  local p = proficiency()
  local w = p and p.WeaponProficiency
  if not w or w.catalogReady or fed then return end
  if type(p.onWeaponProficiencyCatalogItem) ~= 'function' or type(p.onWeaponProficiencyCatalogReady) ~= 'function' then return end
  fed = true
  local list, looked = C.collect(readItem, 100, lastItemId(), weaponTypes())
  for _, e in ipairs(list) do p.onWeaponProficiencyCatalogItem(e.id, e.category, 0, e.name) end
  p.onWeaponProficiencyCatalogReady()
  g_logger.info(string.format('[proficiencycatalog] %d weapons of %d item types', #list, looked)) -- i18n-ok: not UI text
end

local function wrappedOpen(...)
  local ok, err = pcall(feed)
  if not ok then g_logger.warning('[proficiencycatalog] ' .. tostring(err)) end
  return originalOpen(...)
end

local function onGameStart() fed = false end

function init()
  local p = proficiency()
  if not p or type(p.requestOpenWindow) ~= 'function' then
    g_logger.warning('[proficiencycatalog] game_proficiency not found')
    return
  end
  originalOpen = p.requestOpenWindow
  p.requestOpenWindow = wrappedOpen
  connect(g_game, { onGameStart = onGameStart })
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart })
  local p = proficiency()
  if p and originalOpen and p.requestOpenWindow == wrappedOpen then p.requestOpenWindow = originalOpen end
  originalOpen = nil
end
