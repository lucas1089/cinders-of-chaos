-- Pure helpers of the Dungeons window (no client API), tested by dungeonsview_test.lua.
-- The difficulty panel: the table of server/data/scripts/chaos/dungeons_difficulty.lua (D.levels; the server test
-- dungeons_difficulty_test.lua checks this copy) and, for a dungeon with its own health curves (the Vault and the
-- generated dungeons 6-9), the percents the server sends as `health = {monsters = {six}, boss = {six}}` in its
-- "dungeon" payload. A payload without `health` (a base dungeon, or an older server) gets the table's texts, the same
-- strings as dungeons.otui.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
DungeonsView = {}
local V = DungeonsView

V.LEVELS = {
  { health = 100, damage = 100, experience = 0, gold = 0, loot = 0 },
  { health = 200, damage = 130, experience = 75, gold = 75, loot = 0 },
  { health = 320, damage = 190, experience = 100, gold = 100, loot = 15 },
  { health = 500, damage = 280, experience = 200, gold = 200, loot = 30 },
  { health = 800, damage = 400, experience = 300, gold = 300, loot = 45 },
  { health = 1300, damage = 600, experience = 400, gold = 400, loot = 60 },
}

-- the panel texts of dungeons.otui (tr keys with their pt-BR entries)
V.DEFAULT = {
  'Monster Health 100%\nMonster Damage 100%',
  'Monster Health 200%\nMonster Damage 130%\nBonus XP +75%\nGold Drop +75%',
  'Monster Health 320%\nMonster Damage 190%\nBonus XP +100%\nGold Drop +100%\nLoot Chance +15%',
  'Monster Health 500%\nMonster Damage 280%\nBonus XP +200%\nGold Drop +200%\nLoot Chance +30%',
  'Monster Health 800%\nMonster Damage 400%\nBonus XP +300%\nGold Drop +300%\nLoot Chance +45%',
  'Monster Health 1300%\nMonster Damage 600%\nBonus XP +400%\nGold Drop +400%\nLoot Chance +60%',
}

local function clampDifficulty(d)
  d = math.floor(tonumber(d) or 1)
  if d ~= d or d < 1 then return 1 end
  if d > #V.LEVELS then return #V.LEVELS end
  return d
end

-- a sane percent from the payload, or nil (missing, not a number, NaN, out of range)
local function percent(v)
  v = tonumber(v)
  if not v or v ~= v or v < 1 or v > 100000 then return nil end
  return math.floor(v)
end

-- monsters, boss percents of difficulty d from a payload's `health`, or nil when it has none usable
function V.healthOf(health, d)
  if type(health) ~= 'table' or type(health.monsters) ~= 'table' or type(health.boss) ~= 'table' then
    return nil
  end
  d = clampDifficulty(d)
  local m, b = percent(health.monsters[d]), percent(health.boss[d])
  if not m or not b then return nil end
  return m, b
end

-- the text of difficulty d's panel; `health` is the dungeon's payload field (nil: the table's text)
function V.panelText(d, health)
  d = clampDifficulty(d)
  local m, b = V.healthOf(health, d)
  if not m then
    return tr(V.DEFAULT[d])
  end
  local l = V.LEVELS[d]
  local lines = {
    tr('Monster Health %d%%', m),
    tr('Boss Health %d%%', b),
    tr('Monster Damage %d%%', l.damage),
  }
  if l.experience > 0 then lines[#lines + 1] = tr('Bonus XP +%d%%', l.experience) end
  if l.gold > 0 then lines[#lines + 1] = tr('Gold Drop +%d%%', l.gold) end
  if l.loot > 0 then lines[#lines + 1] = tr('Loot Chance +%d%%', l.loot) end
  return table.concat(lines, '\n')
end

-- banner art lives in /images/dungeons/<short name>.png; the server sends the full title. The Vault and the
-- generated dungeons 6-9 have banners drawn by client/tools/gen_dungeon_banners.py.
V.BANNERS = {
  ['Bones Dungeon'] = 'Bones',
  ['Master of the Elements'] = 'MasterElement',
  ['Forbidden Chevalier'] = 'Forbidden',
  ['Rootmaw'] = 'Rootkraken',
  ['Underworld'] = 'Underworld',
  ['The Hollow Vault'] = 'HollowVault',
  ['The Marrow Crypts'] = 'MarrowCrypts',
  ['The Iron Crucible'] = 'IronCrucible',
  ['The Fallen Sanctum'] = 'FallenSanctum',
  ['The Pyre Throne'] = 'PyreThrone',
}
V.BANNER_FALLBACK = 'Underworld'

-- the image path for a title; exists(path) says whether /images/dungeons/<name>.png is there
function V.bannerFor(title, exists)
  title = tostring(title or '')
  local candidates = { V.BANNERS[title], title, title:match('^(%S+)') }
  for _, name in ipairs(candidates) do
    if name and name ~= '' and exists('/images/dungeons/' .. name .. '.png') then
      return '/images/dungeons/' .. name
    end
  end
  return '/images/dungeons/' .. V.BANNER_FALLBACK
end
