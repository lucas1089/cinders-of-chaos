-- Loot filter rules on the client (no client API, tested by lootfilter_test.lua). Mirror of the server's
-- server/data/scripts/chaos/lootfilter_core.lua (classify, color, label): keep both in step. The server stays the
-- authority for autoloot and click-to-loot; the client uses these rules only to draw.
-- info = {r = rarity 0..15, u = unique (0/1 or bool), o = orb (0/1 or bool), g = category, nm = name, c = count,
--         t = the best modifier tier on it (1..8, nil = none), il = item level}

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
L.MAX_TIER = 8
L.UNIQUE_COLOR = '#e07b24'
L.ORB_COLOR = '#4fd8d0'
L.CATEGORIES = { 'equipment', 'currency', 'supplies', 'other' }
L.CATEGORY_NAMES = { equipment = 'Equipment', currency = 'Currency (orbs, coins)', supplies = 'Supplies (potions, runes, ammo)', other = 'Other' }

local function flag(v)
  return v == true or v == 1 or v == '1'
end

function L.defaults()
  return { highlight = 3, dim = 0, lootMin = 0, lootFrom = 0,
    show = { equipment = true, currency = true, supplies = true, other = true }, icons = true, notify = true, tier = 0 }
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
  local t = tonumber(s.tier)
  out.tier = t and t == t and math.max(0, math.min(L.MAX_TIER, math.floor(t))) or d.tier
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
    if (s.tier or 0) > 0 and (tonumber(info.t) or 0) >= s.tier then return 'highlight' end
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
  if type(info.x) == 'string' and info.x ~= '' then
    lines[#lines + 1] = info.x -- item level and the modifiers with their tiers (server lootfilter.lua)
  end
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

-- "HH:MM:SS" of a unix time
function L.clock(t)
  return os.date('%H:%M:%S', t)
end

-- ---------------------------------------------------------------- loot feed rows (icons only)
-- A row is the killed monster's icon followed by the item icons; no text. The server sends the monster's look
-- (kill.look, lootfilter_core.lua F.look) in the outfit names the client's UICreature takes.
local OUTFIT_FIELDS = { type = 65535, auxType = 65535, head = 255, body = 255, legs = 255, feet = 255, addons = 3 }

-- the outfit table for UICreature:setOutfit, or nil when there is nothing to draw
function L.outfit(look)
  if type(look) ~= 'table' then return nil end
  local out = {}
  for k, max in pairs(OUTFIT_FIELDS) do
    local v = tonumber(look[k]) or 0
    v = math.floor(v)
    out[k] = (v == v and v >= 0 and v <= max) and v or 0
  end
  if out.type == 0 and out.auxType == 0 then return nil end
  if type(look.shader) == 'string' and look.shader ~= '' then out.shader = look.shader end
  return out
end

-- tooltip of the monster icon: its name and the kill time
function L.killTip(name, t, empty)
  local lines = { (type(name) == 'string' and name ~= '') and name or 'Unknown creature', 'Killed at ' .. L.clock(t) }
  if empty then lines[#lines + 1] = 'Nothing to loot' end
  return table.concat(lines, '\n')
end

-- what one row draws: {k, outfit, tip, empty, items = [info in the server's order, every n set]}; nil without a kill id
function L.feedRow(data, now)
  if type(data) ~= 'table' then return nil end
  local k = tonumber(data.k)
  if not k then return nil end
  local items = {}
  if type(data.items) == 'table' then
    for _, info in ipairs(data.items) do
      if type(info) == 'table' then
        info.n = tonumber(info.n) or (#items + 1)
        items[#items + 1] = info
      end
    end
  end
  local empty = #items == 0
  return { k = k, outfit = L.outfit(data.look), tip = L.killTip(data.m, now, empty), empty = empty, items = items }
end

-- the count an item icon shows (what is left in the corpse; the dropped count once all of it is gone) and whether it is gone
function L.iconCount(info)
  local count = tonumber(info.c) or 1
  local left = tonumber(info.left) or count
  return left > 0 and left or count, left <= 0
end

-- ---------------------------------------------------------------- rule counters and sounds
-- Mirror of lootfilter_core.lua F.RULES / F.SOUNDS / F.pickSound. The server counts (kill.hits, counts) and saves the
-- sound settings; the client plays the sound of a kill and draws the counters.
L.RULES = {
  { key = 'unique', name = 'Uniques', color = '#e07b24' },
  { key = 'power', name = 'Legendary powers', color = '#ffd040' },
  { key = 'rarity', name = 'Rarity glow', color = '#a35cf0' },
  { key = 'tier', name = 'Modifier tier', color = '#4a90ff' },
  { key = 'orb', name = 'Orbs', color = '#4fd8d0' },
}
-- id -> file (/modules/game_lootfilter/sounds/<key>.ogg); 0 = none
L.SOUNDS = {
  { key = 'chime', name = 'Chime' },
  { key = 'bell', name = 'Bell' },
  { key = 'ping', name = 'Ping' },
  { key = 'drum', name = 'Drum' },
  { key = 'fanfare', name = 'Fanfare' },
}
L.SOUND_DIR = '/modules/game_lootfilter/sounds/'

function L.soundDefaults()
  return { rules = { unique = 5, power = 1, rarity = 0, tier = 0, orb = 0 }, vol = 70, mute = false, hunt = true }
end

-- the sound settings as received from the server (or edited in the window), every field present and in range
function L.normalizeSound(t)
  local d = L.soundDefaults()
  if type(t) ~= 'table' then return d end
  local out = { rules = {}, vol = d.vol, mute = flag(t.mute), hunt = t.hunt == nil and d.hunt or flag(t.hunt) }
  local rules = type(t.rules) == 'table' and t.rules or {}
  for _, r in ipairs(L.RULES) do
    local v = tonumber(rules[r.key])
    if v == nil or v ~= v then
      out.rules[r.key] = d.rules[r.key]
    else
      v = math.floor(v)
      out.rules[r.key] = (v >= 0 and v <= #L.SOUNDS) and v or 0
    end
  end
  local vol = tonumber(t.vol)
  if vol and vol == vol then out.vol = math.max(0, math.min(100, math.floor(vol))) end
  return out
end

-- every rule present (0 when nothing counted)
function L.counts(c)
  local out = {}
  for _, r in ipairs(L.RULES) do
    local v = tonumber(type(c) == 'table' and c[r.key] or nil) or 0
    out[r.key] = v > 0 and math.floor(v) or 0
  end
  return out
end

-- the file and the gain (0..1) a kill plays, or nil: the first rule in L.RULES order that matched and has a sound
function L.pickSound(hits, snd)
  if type(snd) ~= 'table' or snd.mute or (tonumber(snd.vol) or 0) <= 0 or type(hits) ~= 'table' then return nil end
  for _, r in ipairs(L.RULES) do
    local id = tonumber(snd.rules and snd.rules[r.key]) or 0
    local s = L.SOUNDS[id]
    if s and (tonumber(hits[r.key]) or 0) > 0 then
      return L.SOUND_DIR .. s.key .. '.ogg', math.max(0, math.min(1, (tonumber(snd.vol) or 0) / 100)), r.key
    end
  end
  return nil
end

-- the file of one sound id (the window's play button), or nil for none
function L.soundFile(id)
  local s = L.SOUNDS[tonumber(id) or 0]
  return s and (L.SOUND_DIR .. s.key .. '.ogg') or nil
end

-- 1234567 -> "1,234,567"
function L.number(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if out:sub(1, 1) == ',' then out = out:sub(2) end
  return out
end

-- the counter line of a rule in the window
function L.countLine(counts, key)
  local s = counts and counts.session and tonumber(counts.session[key]) or 0
  local t = counts and counts.total and tonumber(counts.total[key]) or 0
  return 'Session ' .. L.number(s) .. '   Total ' .. L.number(t)
end

-- the hunt tracker's rows: { {key, name, color, session, total} } (every rule, in order)
function L.huntRows(counts)
  local out = {}
  local s, t = L.counts(counts and counts.session), L.counts(counts and counts.total)
  for _, r in ipairs(L.RULES) do
    out[#out + 1] = { key = r.key, name = r.name, color = r.color, session = s[r.key], total = t[r.key] }
  end
  return out
end
