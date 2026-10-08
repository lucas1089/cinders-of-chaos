-- Loot filter rules on the client (no client API, tested by lootfilter_test.lua). Mirror of the server's
-- server/data/scripts/chaos/lootfilter_core.lua (classify, color, label): keep both in step. The server stays the
-- authority for autoloot and click-to-loot; the client uses these rules only to draw.
-- info = {r = rarity 0..15, u = unique (0/1 or bool), o = orb (0/1 or bool), g = category, nm = name, c = count}

LootFilterLogic = {}
local L = LootFilterLogic

L.RARITY = {
  { name = 'Common',       color = '#c8c8c8' },
  { name = 'Uncommon',     color = '#5ccf5c' },
  { name = 'Rare',         color = '#4a90ff' },
  { name = 'Epic',         color = '#a35cf0' },
  { name = 'Legendary',    color = '#ffd040' },
  { name = 'Exotic',       color = '#f5b13a' },
  { name = 'Mythic',       color = '#ff5a5a' },
  { name = 'Chaos',        color = '#e02424' },
  { name = 'Eternal',      color = '#ff8a70' },
  { name = 'Divine',       color = '#c8e8ff' },
  { name = 'Phantasmal',   color = '#9ad8ff' },
  { name = 'Celestial',    color = '#e4f2ff' },
  { name = 'Cosmic',       color = '#b878ff' },
  { name = 'Abyssal',      color = '#9a4ce0' },
  { name = 'Transcendent', color = '#e070ff' },
}
L.UNIQUE_COLOR = '#e07b24'
L.ORB_COLOR = '#4fd8d0'
L.CATEGORIES = { 'equipment', 'currency', 'supplies', 'other' }
L.CATEGORY_NAMES = { equipment = 'Equipment', currency = 'Currency (orbs, coins)', supplies = 'Supplies (potions, runes, ammo)', other = 'Other' }

local function flag(v)
  return v == true or v == 1 or v == '1'
end

function L.defaults()
  return { highlight = 3, dim = 0, lootMin = 0, lootFrom = 0,
    show = { equipment = true, currency = true, supplies = true, other = true }, icons = true, notify = true }
end

-- settings as received from the server (JSON), with every field present
function L.normalize(s)
  local d = L.defaults()
  if type(s) ~= 'table' then return d end
  local out = { show = {} }
  for _, k in ipairs({ 'highlight', 'dim', 'lootMin', 'lootFrom' }) do
    local v = tonumber(s[k])
    out[k] = v and math.max(0, math.min(#L.RARITY, math.floor(v))) or d[k]
  end
  local show = type(s.show) == 'table' and s.show or {}
  for _, c in ipairs(L.CATEGORIES) do
    out.show[c] = show[c] ~= false
  end
  out.icons = s.icons ~= false
  out.notify = s.notify ~= false
  return out
end

function L.classify(info, s)
  if flag(info.u) or flag(info.o) then
    return 'highlight'
  end
  local category = info.g or 'other'
  local shown = not (s.show and s.show[category] == false)
  if category == 'equipment' then
    local r = tonumber(info.r) or 0
    if s.highlight > 0 and r >= s.highlight then return 'highlight' end
    if not shown or r < s.dim then return 'dim' end
    return 'normal'
  end
  return shown and 'normal' or 'dim'
end

function L.color(info)
  if flag(info.u) then return L.UNIQUE_COLOR end
  local r = L.RARITY[tonumber(info.r) or 0]
  if r then return r.color end
  if flag(info.o) then return L.ORB_COLOR end
  return nil
end

function L.rarityName(r)
  local e = L.RARITY[tonumber(r) or 0]
  return e and e.name or nil
end

function L.label(info)
  local name = info.nm or 'item'
  if flag(info.u) then return '[Unique] ' .. name end
  local r = L.rarityName(info.r)
  if r then return '[' .. r .. '] ' .. name end
  return name
end

-- tooltip text of a loot channel icon
function L.tooltip(info)
  local count = tonumber(info.c) or 1
  local lines = { (count > 1 and (count .. 'x ') or '') .. L.label(info) }
  local left = tonumber(info.left)
  if left and left <= 0 then
    lines[#lines + 1] = 'Looted (or gone)'
  else
    if left and left < count then lines[#lines + 1] = left .. ' left in the corpse' end
    lines[#lines + 1] = count > 1 and 'Click: loot all   Shift+click: loot one' or 'Click: loot'
  end
  return table.concat(lines, '\n')
end

-- threshold combo text: 0 = Off, else "<Name>+"
function L.thresholdText(v, offText)
  local r = L.RARITY[v]
  if not r then return offText or 'Off' end
  return r.name .. '+'
end

-- keep at most `max` entries of an ordered list of keys; returns the keys dropped from the front
function L.trim(list, max)
  local dropped = {}
  while #list > max do
    dropped[#dropped + 1] = table.remove(list, 1)
  end
  return dropped
end

-- "HH:MM" of a unix time
function L.clock(t)
  return os.date('%H:%M', t)
end
