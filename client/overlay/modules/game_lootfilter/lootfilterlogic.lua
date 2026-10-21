-- Loot filter rules on the client (no client API, tested by lootfilter_test.lua). Mirror of the server's
-- server/data/scripts/chaos/lootfilter_core.lua (classify, color, label): keep both in step. The server stays the
-- authority for autoloot and click-to-loot; the client uses these rules only to draw.
-- info = {r = rarity 0 or an id (1 2 3 4 5 10; an old item 1..15), u = unique (0/1 or bool), o = orb (0/1 or bool), g = category, nm = name, c = count,
--         t = the best modifier tier on it (1..8, nil = none), il = item level}
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

LootFilterLogic = {}
local L = LootFilterLogic

-- The seven rarities (server/data/lib/chaos_rarity.lua): an item carries the id 1 Common, 2 Uncommon, 3 Magic, 4 Rare,
-- 5 Legendary or 10 Divine (Unique is the unique flag). An item saved before the seven rarities may carry 6 .. 9 (they
-- became Legendary) or 11 .. 15 (Divine), so L.RARITY has a row for every id 1 .. 15; L.RARITY_IDS are the ids of today, in
-- order, for the lists the player picks from.
local COMMON = { name = 'Common', color = '#c8c8c8' }
local UNCOMMON = { name = 'Uncommon', color = '#5ccf5c' }
local MAGIC = { name = 'Magic', color = '#4a90ff' }
local RARE = { name = 'Rare', color = '#a35cf0' }
local LEGENDARY = { name = 'Legendary', color = '#ffd040' }
local DIVINE = { name = 'Divine', color = '#c8e8ff' }
L.RARITY = {
  [1] = COMMON, [2] = UNCOMMON, [3] = MAGIC, [4] = RARE,
  [5] = LEGENDARY, [6] = LEGENDARY, [7] = LEGENDARY, [8] = LEGENDARY, [9] = LEGENDARY,
  [10] = DIVINE, [11] = DIVINE, [12] = DIVINE, [13] = DIVINE, [14] = DIVINE, [15] = DIVINE,
}
L.RARITY_IDS = { 1, 2, 3, 4, 5, 10 }
L.MAX_RARITY = 10

-- the id of today's rarity for any id (0 stays 0; an id above 15 is the highest)
function L.canon(id)
  id = math.floor(tonumber(id) or 0)
  if id <= 0 then return 0 end
  if id > 15 then return L.MAX_RARITY end
  local row = L.RARITY[id]
  for _, c in ipairs(L.RARITY_IDS) do
    if L.RARITY[c] == row then return c end
  end
  return 0
end
L.MAX_TIER = 8
L.UNIQUE_COLOR = '#e07b24'
L.ORB_COLOR = '#4fd8d0'
L.CATEGORIES = { 'equipment', 'currency', 'supplies', 'other' }
L.CATEGORY_NAMES = { equipment = 'Equipment', currency = 'Currency (orbs, coins)', supplies = 'Supplies (potions, runes)', other = 'Other' }

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
    out[k] = v and L.canon(math.max(0, v)) or d[k] -- a threshold saved with an old id (6 .. 15) is the rarity it became
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
    local r = L.canon(info.r)
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

-- How a highlighted slot glows. 'soft' for orbs: a thin, faint ring on the slot edge only
-- (images/lf_glow_soft.png), no extra frame, so the orb sprite stays clear (owner request
-- 2026-10-21: the bright teal glow hid the orb). 'glow' for gear and uniques: the soft wide
-- glow (images/lf_glow.png) as before.
function L.glowStyle(info)
  if flag(info.u) or L.RARITY[tonumber(info.r) or 0] then return 'glow' end
  if flag(info.o) then return 'soft' end
  return 'glow'
end

function L.rarityName(r)
  local e = L.RARITY[tonumber(r) or 0]
  return e and tr(e.name) or nil
end

function L.label(info)
  local name = info.nm or 'item'
  if flag(info.u) then return '[' .. tr('Unique') .. '] ' .. name end
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
    if left and left < count then lines[#lines + 1] = tr('%s left in the corpse', left) end
    lines[#lines + 1] = count > 1 and tr('Click: loot all   Shift+click: loot one') or tr('Click: loot')
  end
  return table.concat(lines, '\n')
end

-- threshold combo text: 0 = Off, else "<Name>+"
function L.thresholdText(v, offText)
  local r = L.RARITY[v]
  if not r then return offText or 'Off' end
  return tr(r.name) .. '+'
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
  local lines = { (type(name) == 'string' and name ~= '') and name or tr('Unknown creature'), tr('Killed at %s', L.clock(t)) }
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
