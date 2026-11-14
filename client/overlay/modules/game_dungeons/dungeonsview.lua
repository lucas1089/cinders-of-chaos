-- Pure helpers of the Dungeons window (no client API), tested by dungeonsview_test.lua.
-- The difficulty panel: the table of server/data/scripts/chaos/dungeons_difficulty.lua (D.levels; the server test
-- dungeons_difficulty_test.lua checks this copy) and, for a dungeon with its own health curves (the Vault and the
-- generated dungeons 6-9), the percents the server sends as `health = {monsters = {six}, boss = {six}}` in its
-- "dungeon" payload. A payload without `health` (a base dungeon, or an older server) gets the table's texts, the same
-- strings as dungeons.otui.
local function tr(s, ...) local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr) if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
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

-- the Weekly Challenge (server weekly_challenge.lua, the "dungeon" payload's `weekly` = {label, theme, current,
-- resetIn}): the line on top of the challenges and its text; nil without `weekly`
function V.weeklyTitle(w)
  if type(w) ~= 'table' or not w.label then return nil end
  return tr('Weekly Challenge %s: %s', tostring(w.label), tostring(w.theme or '?'))
end

-- 3725 -> "1h 02m", 200000 -> "2d 7h"
function V.span(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local d, h, m = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
  if d > 0 then return string.format('%dd %dh', d, h) end
  if h > 0 then return string.format('%dh %02dm', h, m) end
  return string.format('%dm', m)
end

function V.weeklyText(w)
  if type(w) ~= 'table' or not w.label then return nil end
  local lines = { tr('The same layout for everyone this week, always at difficulty 1. Solo or a party of up to 4.'),
    tr('Fastest clear per class: Leaderboards, Weekly Challenge Solo and Party. The top 3 of each class get Conquest Tokens.') }
  if w.current == false then
    lines[#lines + 1] = tr('This layout is last week\'s: the new one opens at the next server save.')
  elseif tonumber(w.resetIn) then
    lines[#lines + 1] = tr('New layout in %s.', V.span(w.resetIn))
  end
  return table.concat(lines, '\n')
end

-- the banner of a dungeon payload: the Weekly Challenge shows its week's theme ("Marrow Crypts" -> The Marrow Crypts)
function V.bannerTitle(dungeon)
  if type(dungeon) ~= 'table' then return nil end
  if type(dungeon.weekly) == 'table' and dungeon.weekly.theme then return 'The ' .. tostring(dungeon.weekly.theme) end
  return dungeon.title
end

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

-- ------------------------------------------------------------------------------------------------ the card rail (O555)
-- The window shows one picture card per dungeon in a row, grouped. The server sends no dungeon type, so the client
-- derives the group from what the "list" and "dungeon" payloads carry: a `weekly` field makes the Weekly Challenge
-- group, every other dungeon falls into a level band by its required level.
local function short(n)
  local f = rawget(_G, 'formatShortNumber')
  if type(f) == 'function' then return f(n) end
  return tostring(n)
end

V.BAND_EDGES = { 500, 1000 } -- first level of the second and third band
V.GROUPS = { 'low', 'mid', 'high', 'weekly' } -- the order of the groups on the rail

-- the group key of a dungeon: `weekly` is the "dungeon" payload's field (a table), `level` the "list" entry's
function V.groupOf(level, weekly)
  if type(weekly) == 'table' then return 'weekly' end
  level = tonumber(level) or 1
  if level >= V.BAND_EDGES[2] then return 'high' end
  if level >= V.BAND_EDGES[1] then return 'mid' end
  return 'low'
end

-- heading of a group and the text of its filter chip
function V.groupTitle(key)
  if key == 'weekly' then return tr('Weekly') end
  if key == 'high' then return tr('Levels %d+', V.BAND_EDGES[2]) end
  if key == 'mid' then return tr('Levels %d-%d', V.BAND_EDGES[1], V.BAND_EDGES[2] - 1) end
  return tr('Levels 1-%d', V.BAND_EDGES[1] - 1)
end

-- the short tag on a card's picture
function V.groupTag(key)
  if key == 'weekly' then return tr('Weekly') end
  if key == 'high' then return tr('Late') end
  if key == 'mid' then return tr('Mid') end
  return tr('Early')
end

local function byLevel(a, b)
  local la, lb = tonumber(a.level) or 0, tonumber(b.level) or 0
  if la ~= lb then return la < lb end
  return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
end

-- entries = the "list" payload ({id, title, level, boss, queue}); infoOf(id) = the "dungeon" payload or nil.
-- -> the groups to draw, in rail order: { {key, title, items = {entries by level}}, ... }. filter = a group key, or
-- nil / 'all' / a key nobody has (then everything shows). Groups without a card are left out.
function V.arrange(entries, infoOf, filter)
  local byGroup = {}
  for _, e in ipairs(entries or {}) do
    local info = infoOf and infoOf(e.id) or nil
    local key = V.groupOf(e.level, info and info.weekly or nil)
    byGroup[key] = byGroup[key] or {}
    table.insert(byGroup[key], e)
  end
  if filter ~= nil and filter ~= 'all' and not byGroup[filter] then filter = nil end
  local out = {}
  for _, key in ipairs(V.GROUPS) do
    local items = byGroup[key]
    if items and (filter == nil or filter == 'all' or filter == key) then
      table.sort(items, byLevel)
      out[#out + 1] = { key = key, title = V.groupTitle(key), items = items }
    end
  end
  return out
end

-- the filter chips: All first, then every group that has a card, with its count
function V.filters(entries, infoOf)
  local groups = V.arrange(entries, infoOf, nil)
  local out = { { key = 'all', title = tr('All'), count = #(entries or {}) } }
  for _, g in ipairs(groups) do
    out[#out + 1] = { key = g.key, title = g.title, count = #g.items }
  end
  return out
end

-- the dungeon id the rail selects after a rebuild: the one that was chosen when it is still shown, else the first card
function V.pick(groups, wanted)
  local first
  for _, g in ipairs(groups or {}) do
    for _, e in ipairs(g.items) do
      if e.id == wanted then return e.id end
      first = first or e.id
    end
  end
  return first
end

-- ids in rail order
function V.railIds(groups)
  local ids = {}
  for _, g in ipairs(groups or {}) do
    for _, e in ipairs(g.items) do ids[#ids + 1] = e.id end
  end
  return ids
end

-- width of a group's container on the rail: every card carries its right margin (the gap), the last one too
function V.groupWidth(count, cardWidth, gap)
  count = math.max(0, math.floor(tonumber(count) or 0))
  return count * (cardWidth + gap)
end

-- the queue: the "list" sends a number, the "dungeon" payload { players, estimated }
function V.queuePlayers(q)
  if type(q) == 'table' then return tonumber(q.players) or 0 end
  return tonumber(q) or 0
end

function V.queueShort(players)
  players = V.queuePlayers(players)
  return players == 0 and tr('Open') or tr('%s Players', players)
end

function V.queueText(players)
  return tr('Queue: %s', V.queueShort(players))
end

-- 'red' from 6 players, 'orange' from 3, else 'green'
function V.queueTone(players)
  players = V.queuePlayers(players)
  if players >= 6 then return 'red' end
  if players >= 3 then return 'orange' end
  return 'green'
end

function V.levelText(level)
  return tr('%s+ Level', short(tonumber(level) or 1))
end

-- the text over a card the character cannot enter yet, nil when it can (or a level is not known)
function V.lockText(level, playerLevel)
  level, playerLevel = tonumber(level), tonumber(playerLevel)
  if not level or not playerLevel or playerLevel >= level then return nil end
  return tr('Needs level %s', short(level))
end

V.DIFFICULTY_NAMES = { 'Normal', 'Hard', 'Expert', 'Master', 'Torment', 'Hell' }

function V.difficultyName(d)
  return tr(V.DIFFICULTY_NAMES[clampDifficulty(d)])
end

-- the hardest difficulty the character has unlocked ("Best: Hard"); nil for the first one (nothing to say yet)
function V.bestText(d)
  d = clampDifficulty(d)
  if d <= 1 then return nil end
  return tr('Best: %s', V.difficultyName(d))
end

-- the chips of the chosen dungeon's header: level, queue and best difficulty (nil where there is nothing to say)
function V.headerChips(entry, dungeon, playerLevel)
  entry = entry or {}
  local req = dungeon and dungeon.req or {}
  local level = req.level or entry.level
  local players = V.queuePlayers(dungeon and dungeon.queue or entry.queue)
  local chips = {
    level = V.levelText(level),
    levelTone = V.lockText(level, playerLevel) and 'red' or 'plain',
    queue = V.queueText(players),
    queueTone = V.queueTone(players),
  }
  if dungeon then chips.best = V.bestText(dungeon.difficulty) end
  return chips
end

-- the status field of the bottom bar: the level the dungeon asks while the character is below it, else the queue
function V.statusText(level, playerLevel, players)
  return V.lockText(level, playerLevel) or V.queueShort(players)
end
